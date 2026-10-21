#!/usr/bin/env python3
"""Verify the registered stdio proxy, including a live read from the target app."""
import json, pathlib, selectors, subprocess, sys, time
from launch import load_config
proxy=pathlib.Path(load_config()['operator_dir'])/'meta-xr-operator-mcp-proxy'
p=subprocess.Popen([str(proxy)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1)
def request(i,method,params):
    p.stdin.write(json.dumps({'jsonrpc':'2.0','id':i,'method':method,'params':params})+'\n');p.stdin.flush()
    end=time.monotonic()+15
    selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
    while time.monotonic()<end:
        if selector.select(timeout=.2):
            line=p.stdout.readline()
            if not line: raise RuntimeError(f'Proxy exited: {p.poll()}')
            try: result=json.loads(line)
            except json.JSONDecodeError: continue
            if result.get('id')==i:
                if 'error' in result: raise RuntimeError(result['error'])
                return result['result']
    raise TimeoutError(method)
try:
    request(1,'initialize',{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'abccad-proxy-check','version':'1'}})
    p.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n');p.stdin.flush()
    tools=request(2,'tools/list',{})
    print('Proxy exposes',len(tools['tools']),'tools')
    result=request(3,'tools/call',{'name':'openxr_get_session_info','arguments':{}})
    assert not result.get('isError'),result
    print(json.dumps(result))
finally:
    p.terminate()
    try:p.wait(timeout=3)
    except subprocess.TimeoutExpired:p.kill();p.wait()
