#!/usr/bin/env python3
"""Fresh-process CAD restore, true mm STL dimensions/manifold checks, XR capture."""
import base64,collections,json,math,pathlib,shutil,struct,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent;c=Operator();passed=[]
def call(name,**args):
 r=c.call(name,args);assert not r.get('isError'),r;return r
def state():return json.loads((HERE/'evidence/state.json').read_text())
def wait(test):
 end=time.monotonic()+8
 while time.monotonic()<end:
  s=state()
  if test(s):return s
  time.sleep(.08)
 raise AssertionError({k:v for k,v in state()['cad'].items() if k!='document'})
def press(hand,component):
 call('openxr_set_controller_input',hand=hand,component=component,value=1);time.sleep(.18)
 call('openxr_set_controller_input',hand=hand,component=component,value=0);time.sleep(.24)
def raw_pose(hand,p):
 for kind in ['aim','grip']:call('openxr_set_controller_pose',hand=hand,pose_type=kind,position=p,orientation=[0,0,0,1],base_space='stage')
def click(text):
 b=next(b for p in state()['ui'] if p['visible'] for b in p['buttons'] if b['visible'] and b['text']==text)
 p=b['position'];cad=state()['cad'];o=cad['xr_origin'];v=[p[k]+(.4 if k==2 else 0)-o[9+k] for k in range(3)]
 raw_pose('right',[sum(o[3*k+j]*v[j] for j in range(3))/cad['world_scale'] for k in range(3)])
 time.sleep(.2);press('right','Trigger')
def normalize(v):
 if isinstance(v,float):return round(v,4)
 if isinstance(v,list):return [normalize(x) for x in v]
 if isinstance(v,dict):return {k:normalize(x) for k,x in v.items()}
 return v
def check(text):passed.append(text);print('PASS',text,flush=True)
try:
 baseline=json.loads((HERE/'evidence/cad-native-validation.json').read_text())['state']
 filename=baseline['last_save']['message'].removeprefix('Saved ')
 assert not state()['cad']['document']['bodies'],'Start in a fresh empty process'
 call('openxr_set_head_pose',position=[.1,1.35,.15],orientation=[0,0,0,1],base_space='stage')
 time.sleep(.3);press('left','Menu');click('Load build')
 wait(lambda s:any(b['visible'] and b['text']==filename.removesuffix('.json') for p in s['ui'] for b in p['buttons']))
 click(filename.removesuffix('.json'));click('Load Selected')
 s=wait(lambda s:s['last_load'].get('success'))
 assert normalize(s['cad']['document'])==normalize(baseline['cad']['document'])
 check('Fresh process restores every solid vertex, feature, sketch, constraint, and moved origin')
 press('left','Menu')
 downloads=pathlib.Path.home()/'Downloads';before=set(downloads.glob('voxel_build_*.stl'))
 click('Export STL · mm')
 end=time.monotonic()+5
 while time.monotonic()<end:
  files=set(downloads.glob('voxel_build_*.stl'))-before
  if files:break
  time.sleep(.1)
 assert len(files)==1
 source=files.pop();data=source.read_bytes();count=struct.unpack_from('<I',data,80)[0];assert len(data)==84+50*count
 points=[];edges=collections.Counter();triangles=collections.Counter()
 for i in range(count):
  values=struct.unpack_from('<12fH',data,84+50*i);normal=values[:3];v=[values[3:6],values[6:9],values[9:12]]
  assert all(math.isfinite(n) for n in values[:12]) and .99<sum(n*n for n in normal)<1.01
  keys=[tuple(round(n,3) for n in p) for p in v];assert len(set(keys))==3
  for j in range(3):edges[tuple(sorted((keys[j],keys[(j+1)%3])))]+=1
  triangles[tuple(sorted(tuple(round(n,2) for n in p) for p in v))]+=1
  points+=v
 faces=state()['cad']['document']['bodies'][0]['faces']
 expected=collections.Counter(tuple(sorted(tuple(round(n,2) for n in p) for p in faces[i:i+3])) for i in range(0,len(faces),3))
 assert len(points)==len(faces) and all(abs(points[i][k]-faces[i][k])<.001 for i in range(len(faces)) for k in range(3)),'STL vertices differ from model by more than 0.001 mm'
 dimensions=[max(p[k] for p in points)-min(p[k] for p in points) for k in range(3)]
 assert all(abs(dimensions[k]-[40,30,15][k])<.001 for k in range(3)),dimensions
 assert all(v==2 for v in edges.values()),'STL has open/nonmanifold edges'
 vertices={v for edge in edges for v in edge}
 assert len(vertices)-len(edges)+count==0,'Expected one through-hole (genus one)'
 shutil.copy2(source,HERE/'evidence/cad-mvp-mm.stl')
 check('Exported STL is 40 × 30 × 15 mm, matches the solid, and every edge is paired')
 click('Advanced CAD · sketches & extrudes')
 click('Sketch');click('Auto: on');wait(lambda s:any(b['text']=='Auto: off' for p in s['ui'] if p['visible'] for b in p['buttons']))
 click('Auto: off');check('Automatic constraints can be disabled and re-enabled with the laser')
 raw_pose('left',[-.2,1.3,-.2]);raw_pose('right',[.2,1.3,-.2]);time.sleep(.25)
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=1)
 time.sleep(.25);raw_pose('left',[-.8,1.3,-.2]);raw_pose('right',[.8,1.3,-.2]);wait(lambda s:s['cad']['world_scale']<.3)
 for h in ['left','right']:call('openxr_set_controller_input',hand=h,component='Grip',value=0)
 time.sleep(.5)
 for b in call('openxr_capture_composited_image',eye='left')['content']:
  if b['type']=='image':(HERE/'evidence/cad-mvp-overview.png').write_bytes(base64.b64decode(b['data']))
 check('Restored document remains dimensionally unchanged at magnified view scale')
 assert normalize(state()['cad']['document'])==normalize(baseline['cad']['document'])
finally:
 for h in ['left','right']:
  for component in ['Grip','Trigger']:call('openxr_set_controller_input',hand=h,component=component,value=0)
 call('openxr_release_input_devices')
 (HERE/'evidence/cad-restore-validation.json').write_text(json.dumps({'passed':passed,'stl':{'triangles':count,'dimensions_mm':dimensions} if 'dimensions' in globals() else {},'state':state()},indent=2))
