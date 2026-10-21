#!/usr/bin/env python3
"""Run after cad_check.py: native CAD grip, rotation, hand transfer, placement save."""
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

def raw(hand,pos,q=[0,0,0,1]):
 cad=state()['cad'];o=cad['xr_origin'];v=[pos[k]-o[9+k] for k in range(3)];pos=[sum(o[3*k+j]*v[j] for j in range(3))/cad['world_scale'] for k in range(3)]
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=hand,pose_type=kind,position=pos,orientation=q,base_space='stage')
def center():
 f=state()['cad']['document']['bodies'][0]['faces'];return [(min(v[k] for v in f)+max(v[k] for v in f))/2000 for k in range(3)]
def capture(name):
 for b in call('openxr_capture_composited_image',eye='left')['content']:
  if b['type']=='image':(HERE/'evidence'/name).write_bytes(base64.b64decode(b['data']))
try:
 click('Select')
 before=state()['cad']['document']
 initial=center();raw('left',[-.5,1.2,.1]);raw('right',initial);time.sleep(.5)
 call('openxr_set_controller_input',hand='right',component='Grip',value=1)
 wait(lambda s:s['hands']['RightHand']['held']!=0)
 raw('right',[initial[0]+.15,initial[1]+.08,initial[2]+.1],[0,math.sin(.25),0,math.cos(.25)]);time.sleep(.5)
 moved=state()['cad']['document'];assert moved!=before
 destination=center();raw('left',destination);time.sleep(.3)
 call('openxr_set_controller_input',hand='left',component='Grip',value=1)
 wait(lambda s:s['hands']['LeftHand']['held']!=0 and s['hands']['RightHand']['held']==0)
 call('openxr_set_controller_input',hand='right',component='Grip',value=0)
 raw('left',[destination[0]-.05,destination[1]+.03,destination[2]-.02]);time.sleep(.4)
 call('openxr_set_controller_input',hand='left',component='Grip',value=0)
 wait(lambda s:s['hands']['LeftHand']['held']==0)
 assert state()['cad']['document']!=before
 click('Save');wait(lambda s:s['last_save']['success']);check('Actual grip grabs CAD part, moves and rotates, swaps hands, and saves final placement')
 raw('left',[0,0,1]);raw('right',[0,0,1]);capture('cad-ui-part-studio.png')
 click('Extrude');raw('right',[0,0,1]);capture('cad-ui-extrude.png')
 (HERE/'evidence/cad-grab-native-validation.json').write_text(json.dumps({'passed':passed,'before':before,'state':state()},indent=2))
finally:
 for h in ['left','right']:
  for key in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=key,value=0)
 call('openxr_release_input_devices')
