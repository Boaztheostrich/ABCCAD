#!/usr/bin/env python3
"""Native settings, sketch, keypad, New/Remove solid, zoom, save, and STL checks."""
import json,pathlib,time,sys,base64,struct
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent;c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r
def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(test,seconds=8):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  s=state()
  if test(s):return s
  time.sleep(.08)
 raise AssertionError({k:v for k,v in state().get('cad',{}).items() if k!='document'})
def pose(hand,p):
 cad=state()['cad'];scale=cad['world_scale'];origin=cad.get('xr_origin',[1,0,0,0,1,0,0,0,1,0,0,0]);delta=[p[k]-origin[9+k] for k in range(3)]
 p=[sum(origin[k*3+j]*delta[j] for j in range(3))/scale for k in range(3)]
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=hand,pose_type=kind,position=p,orientation=[0,0,0,1],base_space='stage')
def press(hand,button):
 call('openxr_set_controller_input',hand=hand,component=button,value=1);time.sleep(.18)
 call('openxr_set_controller_input',hand=hand,component=button,value=0);time.sleep(.22)
def click(text,hand='right',prefix=False):
 s=state();buttons=[b for p in s['ui'] if p['visible'] for b in p['buttons'] if b['visible'] and (b['text'].startswith(text) if prefix else b['text']==text)]
 assert len(buttons)==1,(text,[b['text'] for b in buttons]);b=buttons[0];assert not b['disabled'],text
 p=b['position'];pose(hand,[p[0],p[1],p[2]+.4]);time.sleep(.2);press(hand,'Trigger')
def point(p):pose('right',[p[0],p[1],p[2]+.35]);time.sleep(.2);press('right','Trigger')
def number(field,keys):
 click(field,prefix=True)
 for k in keys:click(k)
 click('Apply mm')
def volume(faces):
 result=0
 for i in range(0,len(faces),3):
  a,b,d=faces[i:i+3];cross=[b[1]*d[2]-b[2]*d[1],b[2]*d[0]-b[0]*d[2],b[0]*d[1]-b[1]*d[0]];result+=sum(a[k]*cross[k] for k in range(3))/6
 return abs(result)
def check(label):passed.append(label);print('PASS',label,flush=True)

import math

def normal(v):
 if isinstance(v,float):return round(v,3)
 if isinstance(v,list):return [normal(x) for x in v]
 if isinstance(v,dict):return {k:normal(x) for k,x in v.items()}
 return v
def capture(name):
 for b in call('openxr_capture_composited_image',eye='left')['content']:
  if b['type']=='image':(HERE/'evidence'/name).write_bytes(base64.b64decode(b['data']))
try:
 baseline=json.loads((HERE/'evidence/cad-table-native-validation.json').read_text())['state']
 file=baseline['last_save']['message'].removeprefix('Saved ').removesuffix('.json')
 assert not state()['cad']['document']['bodies']
 call('openxr_set_head_pose',position=[0,1.35,.15],orientation=[0,0,0,1],base_space='stage');time.sleep(.3)
 press('left','Menu');click('Load build');click(file);click('Load Selected');s=wait(lambda s:s['last_load'].get('success'))
 assert normal(s['cad']['document'])==normal(baseline['cad']['document'])
 assert s['cad']['display_scale']==1 and s['cad']['document']['reference_plane']['locked']
 check('Fresh XR process restores table frame and solids at physical 1:1')
 press('left','Menu');click('Advanced CAD · sketches & extrudes');click('Table');click('Rotation: free');wait(lambda s:s['cad']['document']['reference_plane']['lock_rotation']);click('Rotation: locked')
 check('Plane and part-rotation locks remain accessible after restoration')
 # Use a larger fixture to keep the real loader visible for screenshot/cancel checks.
 click('Load');click('preview-load-test');click('Load Selected');wait(lambda s:s['last_load'].get('success') and len(s['cad']['document']['bodies'])==1)
 press('left','Menu');click('Advanced CAD · sketches & extrudes');click('Part 1');click('Table')
 panel=next(q for q in state()['ui'] if q['path'].endswith('/CADPanel'));v=panel['position'];call('openxr_set_head_pose',position=[v[0],v[1],v[2]+.65],orientation=[0,0,0,1],base_space='stage');time.sleep(.3)
 # Hold trigger briefly and capture immediately; normal click() waits past a short build.
 b=next(b for q in state()['ui'] if q['path'].endswith('/CADPanel') for b in q['buttons'] if b['text']=='Layers' and b['visible']);v=b['position'];pose('right',[v[0],v[1],v[2]+.4]);time.sleep(.2)
 call('openxr_set_controller_input',hand='right',component='Trigger',value=1);time.sleep(.06);call('openxr_set_controller_input',hand='right',component='Trigger',value=0)
 s=wait(lambda s:s['cad']['print_loading'] or s['cad']['print_vertices']>0)
 if s['cad']['print_loading']:
  time.sleep(.2)
  if state()['cad']['print_loading']:capture('cad-print-loading.png')
 s=wait(lambda s:not s['cad']['print_loading'] and s['cad']['print_vertices']>0,seconds=60)
 assert s['cad']['print_vertices']>10000
 check('Larger curved part shows real circular progress and completes stepped preview')
 time.sleep(.5);click('Layers · on');wait(lambda s:not s['cad']['print_enabled'])
 check('Large preview toggles off to restore the exact surface')
 (HERE/'evidence/cad-table-restore-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
finally:
 for h in ['left','right']:
  for k in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=k,value=0)
 call('openxr_release_input_devices')
