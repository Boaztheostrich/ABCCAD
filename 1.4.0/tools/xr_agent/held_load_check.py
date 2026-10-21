#!/usr/bin/env python3
"""Reload a saved build with both real controller grips held, then repeat."""
import json,pathlib,subprocess,sys,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent;c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r
def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(test):
 end=time.monotonic()+5
 while time.monotonic()<end:
  s=state()
  if test(s):return s
  time.sleep(.05)
 raise AssertionError({'hands':state()['hands'],'voxels':state()['voxels']})
try:
 baseline=json.loads((HERE/'evidence/native-save-baseline.json').read_text())
 blocks=state()['blocks'];assert len(blocks)>=2
 for hand,block in zip(['left','right'],blocks[:2]):
  for pose in ['aim','grip']:call('openxr_set_controller_pose',hand=hand,pose_type=pose,position=block['position'],orientation=[0,0,0,1],base_space='stage')
  time.sleep(.2);call('openxr_set_controller_input',hand=hand,component='Grip',value=1)
  wait(lambda s:s['hands'][hand.title()+'Hand']['held']==block['id'])
 assert all(v['held'] for v in state()['hands'].values())
 subprocess.run([sys.executable,str(HERE/'save_check.py'),'load','--hand','left'],check=True)
 time.sleep(.3)
 s=state();assert s['voxels']==baseline['voxels'] and all(v['held']==0 for v in s['hands'].values())
 passed.append('Native load replaces both held blocks without stale hand state or deferred cells');print('PASS',passed[-1],flush=True)
 subprocess.run([sys.executable,str(HERE/'save_check.py'),'load','--hand','right'],check=True)
 passed.append('Repeated native reload preserves every transform color and occupied cell');print('PASS',passed[-1],flush=True)
finally:
 for hand in ['left','right']:call('openxr_set_controller_input',hand=hand,component='Grip',value=0)
 call('openxr_release_input_devices')
 (HERE/'evidence/held-load-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
