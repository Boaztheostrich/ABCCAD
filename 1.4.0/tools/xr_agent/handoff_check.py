#!/usr/bin/env python3
"""Real controller handoffs in both directions, with recolor/move/save-ready build."""
import json,pathlib,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent
c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r
def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(test,timeout=5):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=state()
  if test(s):return s
  time.sleep(.05)
 s=state();raise AssertionError({'hands':s['hands'],'blocks':[{k:b[k] for k in ['id','shape','held','position']} for b in s['blocks']],'voxels':s['voxels']})
def inp(h,b,v,**extra):call('openxr_set_controller_input',hand=h,component=b,value=v,**extra)
def pose(h,p):
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=h,pose_type=kind,position=p,orientation=[0,0,0,1],base_space='stage')
def press(h,b):inp(h,b,1);time.sleep(.16);inp(h,b,0);time.sleep(.12)
def check(label):passed.append(label);print('PASS',label,flush=True)
try:
 assert not state()['blocks'],'Start in an empty probe scene'
 for index,shape,cells in [(0,'brick',2),(1,'cube',1),(2,'wedge',1),(3,'m_cube',121),(4,'corner_wedge',1)]:
  if state()['hands']['RightHand']['block_index']!=index:
   inp('right','Thumbstick',1,sub_component='X');time.sleep(.16);inp('right','Thumbstick',0,sub_component='X')
   wait(lambda s:s['hands']['RightHand']['block_index']==index)
  for source,dest,x in [('left','right',-.9),('right','left',.9)]:
   sk=source.title()+'Hand';dk=dest.title()+'Hand'
   pose(dest,[0,2,1]);pose(source,[x,1.5,-.6]);before={b['id'] for b in state()['blocks']};total=state()['voxels']
   press(source,'X' if source=='left' else 'A')
   s=wait(lambda s:len(s['blocks'])==len(before)+1);bid=next(b['id'] for b in s['blocks'] if b['id'] not in before)
   time.sleep(.9);block=next(b for b in state()['blocks'] if b['id']==bid)
   pose(source,block['position']);time.sleep(.15);inp(source,'Grip',1)
   wait(lambda s:s['hands'][sk]['held']==bid)
   pose(source,[x,1.5,-.6]);time.sleep(.2)
   block=next(b for b in state()['blocks'] if b['id']==bid)
   pose(dest,block['position']);time.sleep(.25);inp(dest,'Grip',1)
   s=wait(lambda s:s['hands'][dk]['held']==bid and s['hands'][sk]['held']==0)
   assert s['voxels']==total,'Handoff placed cells while held'
   check(source+' to '+dest+' '+shape+' handoff clears source and leaves grid intact')
   inp(source,'Grip',0);pose(source,[0,2,1])
   press(dest,'Y' if dest=='left' else 'B')
   target=[x,1.5,-1-index*1.2];pose(dest,target)
   wait(lambda s:any(b['id']==bid and max(abs(b['position'][k]-target[k]) for k in range(3))<.08 for b in s['blocks']))
   inp(dest,'Grip',0)
   s=wait(lambda s:s['hands'][dk]['held']==0 and s['voxels']==total+cells)
   block=next(b for b in s['blocks'] if b['id']==bid)
   assert block['color']==['0000ffff','ff0000ff','00ff00ff','ffc0cbff','ffff00ff','000000ff','663399ff'][s['hands'][dk]['color_index']]
   check(dest+' '+shape+' final release preserves shape color and footprint')
finally:
 for hand in ['left','right']:
  for button in ['Grip','X' if hand=='left' else 'A','Y' if hand=='left' else 'B']:inp(hand,button,0)
  inp(hand,'Thumbstick',0,sub_component='X')
 call('openxr_release_input_devices')
 (HERE/'evidence/handoff-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
