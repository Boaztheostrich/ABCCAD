#!/usr/bin/env python3
"""Native menu save/load checks using an explicit isolated test save directory."""
import argparse,json,pathlib,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent
c=Operator()
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r

def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(predicate,timeout=5):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=state()
  if predicate(s):return s
  time.sleep(.08)
 raise AssertionError(state())
def panel():return next(p for p in state()['ui'] if p['path'].endswith('/Viewport2Din3D'))
def press(hand,component):
 call('openxr_set_controller_input',hand=hand,component=component,value=1)
 time.sleep(.25)
 call('openxr_set_controller_input',hand=hand,component=component,value=0)
 time.sleep(.25)
def menu_at_head():
 if panel()['visible']:press('left','Menu')
 press('left','Menu')
 wait(lambda s: next(p for p in s['ui'] if p['path'].endswith('/Viewport2Din3D'))['visible'])
def click(hand,name=None,text=None):
 b=next(b for b in panel()['buttons'] if b['visible'] and (b['name']==name if name else b['text']==text))
 assert not b['disabled'],b
 target=b['position']
 for pose in ['aim','grip']:
  call('openxr_set_controller_pose',hand=hand,pose_type=pose,position=[target[0],target[1],target[2]+.45],orientation=[0,0,0,1],base_space='stage')
 time.sleep(.35);press(hand,'Trigger')
def geometry(s):return sorted([(b['shape'],tuple(round(p,4) for p in b['position']),b['color'],tuple(round(v,4) for v in b['rotation'])) for b in s['blocks']])
args=argparse.ArgumentParser();args.add_argument('mode',choices=['save','load']);args.add_argument('--hand',default='right');args=args.parse_args()
try:
 if args.mode=='save':
  before=state();assert before['voxels']>0
  call('openxr_set_head_pose',position=[1.8,1.7,-.4],orientation=[0,.3826834324,0,.9238795325],base_space='stage')
  wait(lambda s:abs(s['head'][0]-1.8)<.01)
  assert geometry(state())==geometry(before),'Head motion moved placed blocks'
  menu_at_head()
  existing=set((pathlib.Path.home()/'Downloads').glob('voxel_build_*.stl'))
  click(args.hand,name='Save Button')
  saved=wait(lambda s:s.get('last_save',{}).get('success'))
  filename=saved['last_save']['message'].removeprefix('Saved ')
  unexpected=[str(p) for p in set((pathlib.Path.home()/'Downloads').glob('voxel_build_*.stl'))-existing]
  result={'filename':filename,'geometry':geometry(before),'voxels':before['voxels'],'hand':args.hand,'unexpected_exports':unexpected}
  (HERE/'evidence/native-save-baseline.json').write_text(json.dumps(result,indent=2))
  assert not unexpected, 'Save pointer also exported STL: '+str(unexpected)
  print('PASS native save after head movement',json.dumps(result),flush=True)
 else:
  baseline=json.loads((HERE/'evidence/native-save-baseline.json').read_text())
  exports_before=set((pathlib.Path.home()/'Downloads').glob('voxel_build_*.stl'))
  call('openxr_set_head_pose',position=[-1,1.7,.8],orientation=[0,-.2588190451,0,.9659258263],base_space='stage')
  wait(lambda s:abs(s['head'][0]+1)<.01)
  menu_at_head();click(args.hand,name='Load Button')
  filename=baseline['filename']
  wait(lambda s:any(b['text']==filename.removesuffix('.json') for p in s['ui'] for b in p['buttons']))
  click(args.hand,text=filename.removesuffix('.json'))
  click(args.hand,name='Load Selected')
  loaded=wait(lambda s:s.get('last_load',{}).get('success'))
  expected=sorted((x[0],tuple(x[1]),x[2],tuple(x[3])) for x in baseline['geometry'])
  assert geometry(loaded)==expected,(geometry(loaded),expected)
  assert loaded['voxels']==baseline['voxels']
  assert not panel()['visible'],'Successful load did not dismiss menu'
  assert set((pathlib.Path.home()/'Downloads').glob('voxel_build_*.stl'))==exports_before, 'Load pointer also exported STL'
  print('PASS native load after head movement',args.hand,filename,'geometry/rotation/colors/voxels match; menu closes',flush=True)
finally:
 for hand in ['left','right']:
  call('openxr_set_controller_input',hand=hand,component='Trigger',value=0)
 call('openxr_release_input_devices')
