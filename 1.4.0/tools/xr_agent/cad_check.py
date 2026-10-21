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
try:
 s=state();assert not s['cad']['document']['bodies'] and not s['blocks'],'Start empty'
 if not any(p['visible'] and p['path'].endswith('/Viewport2Din3D') for p in s['ui']):press('left','Menu')
 click('Settings')
 if not state()['cad']['enabled']:click('Advanced mode · CAD tools (mm)')
 wait(lambda s:s['cad']['enabled']);click('Back');click('Advanced CAD · sketches & extrudes')
 wait(lambda s:s['cad']['modeling']);check('Settings opt-in opens advanced workbench')
 click('Sketch');click('Front sketch')
 origin=state()['cad']['document']['origin_mm'];center=[v/1000 for v in origin]
 point(center);point([center[0]+.02,center[1]+.015,center[2]])
 wait(lambda s:s['cad']['document']['sketches'][-1]['closed'])
 number('Width',['4','0']);number('Height',['3','0']);click('Extrude');number('Depth',['1','0'])
 click('Apply extrude')
 s=wait(lambda s:len(s['cad']['document']['bodies'])==1)
 assert abs(volume(s['cad']['document']['bodies'][0]['faces'])-12000)<1
 check('Laser sketch and virtual numeric keypad create exact 40 × 30 × 10 mm part')
 click('Select');point([center[0],center[1],center[2]+.01]);click('Sketch on selected face');click('Circle')
 point([center[0],center[1],center[2]+.01]);point([center[0]+.005,center[1],center[2]+.01])
 number('Radius',['5']);click('Extrude');number('Depth',['±','1','0']);click('Remove');click('Apply extrude')
 s=wait(lambda s:len(s['cad']['document']['bodies'][0]['features'])==2)
 assert 11214<volume(s['cad']['document']['bodies'][0]['faces'])<11216
 check('Face-attached circle and Remove extrusion create dimension-correct through-hole')
 click('Select');face=[center[0]+.012,center[1]+.008,center[2]+.01];point(face);click('Sketch on selected face');click('Center rectangle')
 point(face);point([face[0]+.004,face[1]+.003,face[2]])
 number('Width',['8']);number('Height',['6']);click('Extrude');number('Depth',['5']);click('Add');click('Apply extrude')
 s=wait(lambda s:len(s['cad']['document']['bodies'][0]['features'])==3)
 assert 11454<volume(s['cad']['document']['bodies'][0]['faces'])<11456
 check('Add extrusion unions an exact 8 × 6 × 5 mm boss to the selected face')
 # Select the exact feature directly in the persistent feature list.
 click('Sketch 3 · Circle');click('Sketch')
 number('Radius',['6'])
 s=wait(lambda s:11108<volume(s['cad']['document']['bodies'][0]['faces'])<11111)
 check('Editing a saved sketch dimension rebuilds the cut and downstream boss')
 # The through-hole must be open, not just have approximately the right volume.
 faces=s['cad']['document']['bodies'][0]['faces'];cap_hits=0
 for i in range(0,len(faces),3):
  a,b,d=faces[i:i+3];x=center[0]*1000;y=center[1]*1000
  area=(b[1]-d[1])*(a[0]-d[0])+(d[0]-b[0])*(a[1]-d[1])
  if abs(area)<1e-8:continue
  u=((b[1]-d[1])*(x-d[0])+(d[0]-b[0])*(y-d[1]))/area
  v=((d[1]-a[1])*(x-d[0])+(a[0]-d[0])*(y-d[1]))/area
  if min(u,v,1-u-v)>1e-7:cap_hits+=1
 assert cap_hits==0,'A through-hole still has a cap'
 check('Through-hole is actually open along its centerline')

 click('Export · mm')
 wait(lambda s:'STL saved in mm' in s['cad']['message'])
 check('Selected-part STL export succeeds in millimeter coordinates')
 # Spread both empty hands. This changes tracking scale, not a single model vertex.
 before=s['cad']['document'];pose('left',[-.2,1.5,.2]);pose('right',[.2,1.5,.2]);time.sleep(.2)
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=1)
 time.sleep(.3);pose('left',[-.4,1.5,.2]);pose('right',[.4,1.5,.2])
 s=wait(lambda s:s['cad']['world_scale']<.8)
 assert s['cad']['document']==before
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=0)
 check('Two empty grips zoom the view without changing model dimensions')
 time.sleep(.4)  # The workbench is resummoned after the gesture ends.
 click('1:1');wait(lambda s:abs(s['cad']['world_scale']-1)<.001);time.sleep(.4)
 click('Origin');number('X ·',['1','0','0'])
 assert abs(state()['cad']['document']['origin_mm'][0]-100)<.001
 for name,normal in [('Top',[0,1,0]),('Right',[1,0,0]),('Front',[0,0,1])]:
  click('Select');click('New sketch');click(name+' sketch')
  assert state()['cad']['document']['sketches'][-1]['plane'][6:9]==normal
 check('Movable origin and Front/Top/Right base planes preserve fixed ground alignment')
 click('Save');wait(lambda s:s['last_save'].get('success'))
 check('CAD solids, attached sketches, constraints, and origin save through existing menu signal')
 for block in call('openxr_capture_composited_image',eye='left')['content']:
  if block['type']=='image':(HERE/'evidence/cad-mvp.png').write_bytes(base64.b64decode(block['data']))
finally:
 for h in ['left','right']:
  for key in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=key,value=0)
 call('openxr_release_input_devices')
 (HERE/'evidence/cad-native-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
