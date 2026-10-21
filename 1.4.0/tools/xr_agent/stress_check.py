#!/usr/bin/env python3
"""Move/recolor loaded blocks with the opposite hand, rotate, undo and redo natively."""
import json,pathlib,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent;c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r

def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(test,timeout=5):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=state()
  if test(s):return s
  time.sleep(.06)
 raise AssertionError(state())
def inp(h,b,v,**extra):call('openxr_set_controller_input',hand=h,component=b,value=v,**extra)
def pose(h,p,q=[0,0,0,1]):
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=h,pose_type=kind,position=p,orientation=q,base_space='stage')
def check(label,condition):
 assert condition,label
 passed.append(label);print('PASS',label,flush=True)
def geometry(s):return sorted([(b['shape'],tuple(round(x,4) for x in b['position']),b['color'],tuple(round(x,4) for x in b['rotation'])) for b in s['blocks']])
try:
 for hand,side in [('left',1),('right',-1)]:
  key=hand.title()+'Hand'
  block=next(b for b in state()['blocks'] if b['position'][0]*side>0)
  bid=block['id'];cells=state()['voxels'];oldcolor=block['color']
  pose(hand,block['position']);time.sleep(.25);inp(hand,'Grip',1)
  wait(lambda s:s['hands'][key]['held']==bid)
  check(hand+' grabs block placed/restored from opposite side',state()['hands'][key]['held']==bid)
  pose(hand,[side*.8,1.2,-.9],[0,.7071067812,0,.7071067812]);time.sleep(.35)
  inp(hand,'Y' if hand=='left' else 'B',1);time.sleep(.25);inp(hand,'Y' if hand=='left' else 'B',0)
  s=wait(lambda s:next(b for b in s['blocks'] if b['id']==bid)['color']!=oldcolor)
  check(hand+' recolors restored block',True)
  inp(hand,'Grip',0)
  wait(lambda s:s['hands'][key]['held']==0 and s['voxels']==cells)
  time.sleep(.2);expected=geometry(state());before=len(state()['blocks'])
  inp('left','Thumbstick',-1,sub_component='X');time.sleep(.2);inp('left','Thumbstick',0,sub_component='X')
  wait(lambda s:len(s['blocks'])==before-1)
  check(hand+' moved block undo removes exact placed object',True)
  inp('left','Thumbstick',1,sub_component='X');time.sleep(.2);inp('left','Thumbstick',0,sub_component='X')
  s=wait(lambda s:len(s['blocks'])==before)
  check(hand+' redo restores position rotation color and cell count',geometry(s)==expected and s['voxels']==cells)
finally:
 for h in ['left','right']:
  for b in ['Grip','Y' if h=='left' else 'B']:inp(h,b,0)
 inp('left','Thumbstick',0,sub_component='X')
 call('openxr_release_input_devices')
 (HERE/'evidence/stress-validation.json').write_text(json.dumps({'passed':passed,'state':state()},indent=2))
