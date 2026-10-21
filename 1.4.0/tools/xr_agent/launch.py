#!/usr/bin/env python3
"""Launch one explicitly configured ABCCAD/Operator session. Ctrl-C stops its child only."""
import argparse, fcntl, json, os, pathlib, signal, socket, subprocess, sys, time
HERE = pathlib.Path(__file__).resolve().parent

def load_config():
    return json.loads((HERE / 'config.json').read_text())

def run(probe=False):
    config = load_config()
    (HERE / 'evidence').mkdir(exist_ok=True)
    lock = open(HERE / 'session.lock', 'w')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: raise RuntimeError('This workflow already owns a running session. Stop it with Ctrl-C first.')
    for key in ['godot', 'project', 'runtime', 'operator_dir']:
        if not pathlib.Path(config[key]).exists(): raise RuntimeError(f'Missing {key}: {config[key]}; update config.json.')
    manifest = json.loads((pathlib.Path(config['operator_dir']) / 'XrApiLayer_METAX_operator.json').read_text())['api_layer']
    library = pathlib.Path(config['operator_dir']) / manifest['library_path']
    if not library.is_file(): raise RuntimeError(f'Operator layer library missing: {library}')
    port = int(os.environ.get('AGENTICXR_MCP_PORT', '8720'))
    with socket.socket() as sock:
        if sock.connect_ex(('127.0.0.1', port)) == 0:
            raise RuntimeError(f'Port {port} already has a server. Identify/stop the existing XR app before launching another.')
    env = os.environ.copy()
    env['XR_RUNTIME_JSON'] = config['runtime']
    env['XR_API_LAYER_PATH'] = os.pathsep.join(dict.fromkeys([config['operator_dir']] + env.get('XR_API_LAYER_PATH','').split(os.pathsep))).rstrip(os.pathsep)
    layers = [x for x in env.get('XR_ENABLE_API_LAYERS','').split(os.pathsep) if x]
    env['XR_ENABLE_API_LAYERS'] = os.pathsep.join(dict.fromkeys(layers + [manifest['name']]))
    env['ABCCAD_STATE_FILE'] = str(HERE / 'evidence/state.json')
    if probe: (HERE / 'evidence/state.json').unlink(missing_ok=True)
    log = HERE / 'evidence' / (time.strftime('%Y%m%d-%H%M%S') + '.log')
    command = [config['godot'], '--path', config['project'], '--xr-mode','on','--rendering-method','mobile','--rendering-driver',config['driver'],'--max-fps','60']
    if probe: command += ['--scene','res://tests/xr_agent_probe.tscn']
    command += ['--','--opaque']
    child = None
    try:
        with log.open('w') as output:
            child = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT)
            (HERE / 'session.json').write_text(json.dumps({'pid':child.pid,'log':str(log),'project':config['project']}))
            print(f'ABCCAD PID {child.pid}; log: {log}', flush=True)
            for _ in range(100):
                if child.poll() is not None: raise RuntimeError(f'Godot exited {child.returncode}; inspect {log}')
                try:
                    from operator_client import Operator
                    client = Operator(f'http://127.0.0.1:{port}')
                    info = client.call('openxr_get_instance_info', {})
                    if info.get('isError'): raise RuntimeError(info)
                    content = json.loads(info['content'][0]['text'])
                    if content['application']['name'] != 'Voxel-test-v1.4': raise RuntimeError(f'Unexpected XR target: {content}')
                    print('Live ABCCAD Operator connection verified. Ctrl-C stops this Godot process.', flush=True)
                    break
                except (OSError, TimeoutError): time.sleep(.2)
            else: raise RuntimeError(f'Operator did not start; inspect {log} and layer paths.')
            return child.wait()
    finally:
        if child and child.poll() is None:
            child.terminate()
            try: child.wait(timeout=8)
            except subprocess.TimeoutExpired: child.kill(); child.wait()
        (HERE / 'session.json').unlink(missing_ok=True)

def stop():
    record_path = HERE / 'session.json'
    if not record_path.is_file():
        print('No session owned by this workflow.'); return 0
    record = json.loads(record_path.read_text())
    config = load_config()
    pid = int(record['pid'])
    command = subprocess.run(['/bin/ps','-p',str(pid),'-o','command='],capture_output=True,text=True,check=False).stdout.strip()
    expected = config['godot'] + ' --path ' + config['project'] + ' '
    if not command.startswith(expected):
        raise RuntimeError('Recorded PID is absent or no longer matches this workflow; refusing to signal it.')
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        if not record_path.exists():
            print(f'Stopped owned ABCCAD process {pid}.'); return 0
        time.sleep(.1)
    raise RuntimeError('Godot was signaled but did not finish shutdown; inspect the recorded log.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stop', action='store_true', help='Stop only the verified process owned by this workflow')
    parser.add_argument('--probe', action='store_true', help='Enable read-only scene snapshots for validation')
    args = parser.parse_args()
    try: sys.exit(stop() if args.stop else run(args.probe))
    except KeyboardInterrupt: print('\nOwned ABCCAD session stopped.')
    except Exception as error: print(f'Launch failed: {error}', file=sys.stderr); sys.exit(1)
