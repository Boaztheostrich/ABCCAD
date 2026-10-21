#!/usr/bin/env python3
"""Local Operator MCP diagnostic client; no ADB or physical headset required."""
import argparse, json, os, queue, threading, urllib.request, urllib.parse

class Operator:
    def __init__(self, base=None):
        base = base or 'http://127.0.0.1:' + os.environ.get('AGENTICXR_MCP_PORT', '8720')
        self.base = base
        self.events = queue.Queue()
        self.stream = urllib.request.urlopen(base + '/sse', timeout=30)
        self.seq = 0
        threading.Thread(target=self._read, daemon=True).start()
        event, endpoint = self.events.get(timeout=10)
        if event != 'endpoint' or not endpoint.startswith('/message?'):
            raise RuntimeError('Unexpected Operator SSE endpoint')
        self.endpoint = base + endpoint
        self.request('initialize', {'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'abccad-validation','version':'1'}})
        self.send({'jsonrpc':'2.0','method':'notifications/initialized'})
    def _read(self):
        event, data = '', []
        try:
            for raw in self.stream:
                line = raw.decode().rstrip('\r\n')
                if not line:
                    if data: self.events.put((event, '\n'.join(data)))
                    event, data = '', []
                elif line.startswith('event:'): event = line[6:].strip()
                elif line.startswith('data:'): data.append(line[5:].strip())
        except Exception as exc:
            self.events.put(('error', str(exc)))
    def send(self, obj):
        req = urllib.request.Request(self.endpoint, json.dumps(obj).encode(), {'Content-Type':'application/json'})
        with urllib.request.urlopen(req, timeout=10) as response: response.read()
    def request(self, method, params):
        self.seq += 1
        self.send({'jsonrpc':'2.0','id':self.seq,'method':method,'params':params})
        while True:
            event, data = self.events.get(timeout=30)
            if event == 'error': raise RuntimeError(data)
            try: obj = json.loads(data)
            except json.JSONDecodeError: continue
            if not isinstance(obj, dict): continue
            if obj.get('id') == self.seq:
                if 'error' in obj: raise RuntimeError(obj['error'])
                return obj['result']
    def call(self, name, args): return self.request('tools/call', {'name':name,'arguments':args})

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('tool', nargs='?')
    parser.add_argument('arguments', nargs='?', default='{}')
    args = parser.parse_args()
    client = Operator()
    result = client.call(args.tool,json.loads(args.arguments)) if args.tool else client.request('tools/list',{})
    print(json.dumps(result, indent=2))
