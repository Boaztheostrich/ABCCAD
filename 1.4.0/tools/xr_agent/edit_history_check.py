#!/usr/bin/env python3
"""Native rapid re-grab, redo/move and panel-edge pickup for all types/both hands."""
import json,pathlib,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent;c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r

def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(predicate,timeout=5):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=state()
  if predicate(s):return s
  time.sleep(.04)
 raise AssertionError(state())
def inp(h,b,v,**args):call('openxr_set_controller_input',hand=h,component=b,value=v,**args)
def pose(h,p):
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=h,pose_type=kind,position=p,orientation=[0,0,0,1],base_space='stage')
def press(h,b):inp(h,b,1);time.sleep(.15);inp(h,b,0);time.sleep(.12)
def stick(v):inp('left','Thumbstick',v,sub_component='X');time.sleep(.16);inp('left','Thumbstick',0,sub_component='X');time.sleep(.12)
def check(label):passed.append(label);print('PASS',label,flush=True)
try:
 assert not state()['blocks'],'Start this test in an empty probe scene'
 for index,shape,cells in [(0,'brick',2),(1,'cube',1),(2,'wedge',1),(3,'m_cube',121),(4,'corner_wedge',1)]:
  current=state()['hands']['RightHand']['block_index']
  if current!=index:
   inp('right','Thumbstick',1,sub_component='X');time.sleep(.16);inp('right','Thumbstick',0,sub_component='X')
   wait(lambda s:s['hands']['RightHand']['block_index']==index)
  for hand,x in [('left',-.9),('right',.9)]:
   key=hand.title()+'Hand';z=-.8-index*1.5
   pose(hand,[x,1.5,-.6]);before={b['id'] for b in state()['blocks']}
   press(hand,'X' if hand=='left' else 'A')
   s=wait(lambda s:len(s['blocks'])==len(before)+1)
   bid=next(b['id'] for b in s['blocks'] if b['id'] not in before)
   time.sleep(.9)
   block=next(b for b in state()['blocks'] if b['id']==bid)
   p=block['position'][:]
   if shape=='m_cube':p=[p[k]+.45*block['rotation'][k] for k in range(3)]
   pose(hand,p);time.sleep(.12);inp(hand,'Grip',1)
   wait(lambda s:s['hands'][key]['held']==bid)
   if shape=='m_cube':check(hand+' panel pickup at visible edge')
   pose(hand,[x,1.5,z]);press(hand,'Y' if hand=='left' else 'B')
   inp(hand,'Grip',0)
   s=wait(lambda s:s['hands'][key]['held']==0 and s['voxels']>=cells)
   total=s['voxels']
   inp(hand,'Grip',1)
   wait(lambda s:s['hands'][key]['held']==bid and s['voxels']==total-cells)
   check(hand+' '+shape+' rapid re-grab clears footprint')
   inp(hand,'Grip',0);wait(lambda s:s['hands'][key]['held']==0 and s['voxels']==total)
   before={b['id'] for b in state()['blocks']}
   stick(-1);wait(lambda s:len(s['blocks'])==len(before)-1)
   stick(1);s=wait(lambda s:len(s['blocks'])==len(before))
   bid=next(b['id'] for b in s['blocks'] if b['id'] not in before)
   block=next(b for b in s['blocks'] if b['id']==bid)
   pose(hand,block['position']);time.sleep(.12);inp(hand,'Grip',1)
   wait(lambda s:s['hands'][key]['held']==bid and s['voxels']==total-cells)
   pose(hand,[x,1.5,z-.3]);inp(hand,'Grip',0)
   wait(lambda s:s['hands'][key]['held']==0 and s['voxels']==total)
   check(hand+' '+shape+' redo then move leaves no phantom cells')
finally:
 for hand in ['left','right']:
  for b in ['Grip','X' if hand=='left' else 'A','Y' if hand=='left' else 'B']:inp(hand,b,0)
  inp(hand,'Thumbstick',0,sub_component='X')
 call('openxr_release_input_devices')
 (HERE/'evidence/edit-history-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
