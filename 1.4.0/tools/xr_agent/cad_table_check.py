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

def oriented(hand,world,q):
 cad=state()['cad'];o=cad['xr_origin'];delta=[world[k]-o[9+k] for k in range(3)];raw=[sum(o[k*3+j]*delta[j] for j in range(3))/cad['world_scale'] for k in range(3)]
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=hand,pose_type=kind,position=raw,orientation=q,base_space='stage')
def table_point(p):
 oriented('right',[p[0],p[1]+.35,p[2]],[-math.sqrt(.5),0,0,math.sqrt(.5)]);time.sleep(.2);press('right','Trigger')
def capture(name):
 for block in call('openxr_capture_composited_image',eye='left')['content']:
  if block['type']=='image':(HERE/'evidence'/name).write_bytes(base64.b64decode(block['data']))
try:
 assert not state()['cad']['document']['bodies'],'Start empty'
 call('openxr_set_head_pose',position=[0,1.35,.15],orientation=[0,0,0,1],base_space='stage');time.sleep(.4)
 if any(p['visible'] and p['path'].endswith('_tutorial') for p in state()['ui']):click('Never Show Again')
 press('left','Menu');click('Settings')
 if not state()['cad']['enabled']:click('Advanced mode · CAD tools (mm)')
 click('Back');click('Advanced CAD · sketches & extrudes');click('Table')
 click('Capture table · 3 contacts');wait(lambda s:s['cad']['tool']=='capture_plane')
 for contact in [[0,.9,-.5],[.25,.9,-.5],[0,.9,-.75]]:
  pose('right',[contact[0],contact[1],contact[2]+.07]);time.sleep(.25);press('right','Trigger')
 s=wait(lambda s:bool(s['cad']['document'].get('reference_plane')))
 ref=s['cad']['document']['reference_plane'];assert ref['locked'] and all(abs(ref['plane_mm'][9+k]-[0,900,-500][k])<.01 for k in range(3))
 assert all(abs(ref['plane_mm'][6+k]-[0,1,0][k])<.001 for k in range(3))
 check('Three actual controller-tip contacts create an upward locked tabletop plane')
 capture('cad-table-controls.png')
 click('Sketch on table')
 table_point([0,.9,-.5]);table_point([.0127,.9,-.5254])
 number('Width',['2','5','.','4']);number('Height',['5','0','.','8']);click('Extrude');number('Depth',['7','6','.','2']);click('Apply extrude')
 s=wait(lambda s:len(s['cad']['document']['bodies'])==1)
 faces=s['cad']['document']['bodies'][0]['faces'];bounds=[max(p[k] for p in faces)-min(p[k] for p in faces) for k in range(3)]
 assert all(abs(bounds[k]-[25.4,76.2,50.8][k])<.001 for k in range(3)),bounds
 check('Table sketch and extrusion form an exact 1 x 2 x 3 inch reference block in mm')
 before=s['cad']['document'];plane=s['cad']['table_pose']
 pose('left',[-.2,1.4,.2]);pose('right',[.2,1.4,.2]);time.sleep(.2)
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=1)
 time.sleep(.25);pose('left',[-.8,1.4,.2]);pose('right',[.8,1.4,.2])
 s=wait(lambda s:s['cad']['display_scale']>3.8)
 assert s['cad']['document']==before and s['cad']['table_pose']==plane and s['cad']['world_scale']==1
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=0)
 time.sleep(.4);click('1:1');s=wait(lambda s:abs(s['cad']['display_scale']-1)<.001)
 assert s['cad']['document']==before and s['cad']['table_pose']==plane
 check('Two-hand view zoom keeps the real table fixed; 1:1 restores physical scale without editing geometry')
 click('Export · mm');s=wait(lambda s:'STL saved in mm' in s['cad']['message'])
 data=(pathlib.Path.home()/'Downloads'/s['cad']['message'].split(' · ',1)[1]).read_bytes();count=struct.unpack_from('<I',data,80)[0];points=[]
 for i in range(count):
  v=struct.unpack_from('<12fH',data,84+50*i);points.extend([v[3:6],v[6:9],v[9:12]])
 expected=[[v[0],-v[2]-500,v[1]-900] for v in faces]
 assert max(abs(points[i][k]-expected[i][k]) for i in range(len(points)) for k in range(3))<.001
 check('Reference-block STL stays dimensionally exact after table-anchored zoom')
 # A front-plane cylinder has a curved crown along the table print direction.
 click('Select');click('New sketch');click('Front sketch');click('Circle')
 point([.03,.92,-.65]);point([.05,.92,-.65]);number('Radius',['2','0']);click('Extrude');number('Depth',['2','0']);click('Apply extrude')
 s=wait(lambda s:len(s['cad']['document']['bodies'])==2)
 snapshot=s['cad']['document']
 click('Layers')
 # Capture while the async generator is active, rather than inserting a fake loader.
 s=wait(lambda s:s['cad']['print_loading'] or s['cad']['print_vertices']>0)
 if s['cad']['print_loading']:capture('cad-print-loading.png')
 s=wait(lambda s:not s['cad']['print_loading'] and s['cad']['print_vertices']>0,seconds=45)
 assert s['cad']['document']==snapshot and s['cad']['print_enabled']
 check('0.2 mm stepped preview finishes asynchronously without changing exact CAD/export geometry')
 time.sleep(.5)
 # Export must still use the original body, not preview triangles.
 click('Export · mm');s=wait(lambda s:'STL saved in mm' in s['cad']['message'])
 data=(pathlib.Path.home()/'Downloads'/s['cad']['message'].split(' · ',1)[1]).read_bytes();n=struct.unpack_from('<I',data,80)[0]
 assert n*3==len(snapshot['bodies'][-1]['faces'])
 click('Layers · on');wait(lambda s:not s['cad']['print_enabled']);click('Layers')
 wait(lambda s:not s['cad']['print_loading'] and s['cad']['print_enabled'],seconds=45)
 check('Layer preview toggles on/off and STL continues to export the original solid')
 click('Save');wait(lambda s:s['last_save'].get('success'))
 (HERE/'evidence/cad-table-native-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
finally:
 for h in ['left','right']:
  for key in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=key,value=0)
 call('openxr_release_input_devices')
