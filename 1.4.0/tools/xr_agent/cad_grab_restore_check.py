#!/usr/bin/env python3
"""Fresh process after cad_grab_check.py: restore moved part and check STL vertices."""
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

def normalized(v):
 if isinstance(v,float):return round(v,3)
 if isinstance(v,list):return [normalized(x) for x in v]
 if isinstance(v,dict):return {k:normalized(x) for k,x in v.items()}
 return v
try:
 baseline=json.loads((HERE/'evidence/cad-grab-native-validation.json').read_text())['state']
 filename=baseline['last_save']['message'].removeprefix('Saved ')
 assert not state()['cad']['document']['bodies']
 call('openxr_set_head_pose',position=[0,1.35,.15],orientation=[0,0,0,1],base_space='stage');time.sleep(.3)
 press('left','Menu');click('Load build')
 wait(lambda s:any(b['visible'] and b['text']==filename.removesuffix('.json') for p in s['ui'] for b in p['buttons']))
 click(filename.removesuffix('.json'));click('Load Selected')
 s=wait(lambda s:s['last_load'].get('success'))
 assert normalized(s['cad']['document'])==normalized(baseline['cad']['document'])
 check('Fresh native process restores moved solid, rotated sketch planes, and feature history')
 press('left','Menu');click('Advanced CAD · sketches & extrudes');click('Part 1')
 click('Export · mm');s=wait(lambda s:'STL saved in mm' in s['cad']['message'])
 source=pathlib.Path.home()/'Downloads'/s['cad']['message'].split(' · ',1)[1]
 data=source.read_bytes();count=struct.unpack_from('<I',data,80)[0];points=[]
 for i in range(count):
  v=struct.unpack_from('<12fH',data,84+50*i);points.extend([v[3:6],v[6:9],v[9:12]])
 faces=s['cad']['document']['bodies'][0]['faces'];assert len(points)==len(faces)
 assert max(abs(points[i][k]-faces[i][k]) for i in range(len(points)) for k in range(3))<.001
 check('Restored moved/rotated part exports STL matching every model vertex within 0.001 mm')
 # Capture the actual workbench from closer to the panel for legible text.
 panel=next(p for p in state()['ui'] if p['path'].endswith('/CADPanel'));v=panel['position']
 call('openxr_set_head_pose',position=[v[0],v[1],v[2]+.65],orientation=[0,0,0,1],base_space='stage')
 for h in ['left','right']:
  for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=h,pose_type=kind,position=[0,0,1],orientation=[0,0,0,1],base_space='stage')
 time.sleep(.5)
 for name,command in [('cad-ui-part-studio.png','Select'),('cad-ui-extrude.png','Extrude')]:
  click(command)
  for kind in ['aim','grip']:call('openxr_set_controller_pose',hand='right',pose_type=kind,position=[0,0,1],orientation=[0,0,0,1],base_space='stage')
  time.sleep(.3)
  for block in call('openxr_capture_composited_image',eye='left')['content']:
   if block['type']=='image':(HERE/'evidence'/name).write_bytes(base64.b64decode(block['data']))
 (HERE/'evidence/cad-grab-restore-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
finally:
 for h in ['left','right']:
  for k in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=k,value=0)
 call('openxr_release_input_devices')
