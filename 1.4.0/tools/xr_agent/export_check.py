#!/usr/bin/env python3
"""Export through each hand's native menu pointer; parse real binary STL geometry."""
import base64,collections,json,math,pathlib,struct,time
from operator_client import Operator
HERE=pathlib.Path(__file__).resolve().parent
DOWNLOADS=pathlib.Path.home()/'Downloads'
c=Operator()
def call(name,**args):
 r=c.call(name,args)
 assert not r.get('isError'),r
 return r

def state():return json.loads((HERE/'evidence/state.json').read_text())
def triangle_keys(points):
 return collections.Counter(tuple(sorted(tuple(round(v,5) for v in p) for p in points[i:i+3])) for i in range(0,len(points),3))
def validate_stl(path, expected):
 data=path.read_bytes()
 assert len(data)>=84,'Truncated STL'
 n=struct.unpack_from('<I',data,80)[0]
 assert n>0 and len(data)==84+50*n,(n,len(data))
 points=[]
 for i in range(n):
  values=struct.unpack_from('<12fH',data,84+50*i)
  vertices=[values[3:6],values[6:9],values[9:12]]
  assert all(math.isfinite(v) for pt in vertices for v in pt)
  points+=vertices
 assert triangle_keys(points)==triangle_keys(expected), 'Exported triangles do not match actual placed meshes'
 bounds=[[min(p[k] for p in points),max(p[k] for p in points)] for k in range(3)]
 assert all(.001 < hi-lo < 10 for lo,hi in bounds),bounds
 return {'path':str(path),'bytes':len(data),'triangles':n,'bounds':bounds,'matches_placed_mesh_triangles':True}
report=[]
try:
 for hand in ['left','right']:
  panels=state()['ui'];panel=next(p for p in panels if p['path'].endswith('/Viewport2Din3D'))
  if not panel['visible']:
   call('openxr_set_controller_input',hand='left',component='Menu',value=1,auto_release=True,hold_duration=.25)
   time.sleep(.4)
   panel=next(p for p in state()['ui'] if p['path'].endswith('/Viewport2Din3D'))
  assert panel['visible'],'Menu did not open'
  target=next(b['position'] for b in panel['buttons'] if b['name']=='Export to STL')
  for pose in ['aim','grip']:
   call('openxr_set_controller_pose',hand=hand,pose_type=pose,position=[target[0],target[1],target[2]+.45],orientation=[0,0,0,1],base_space='stage')
  time.sleep(.4)
  expected=state()['export_faces']
  assert expected, 'No placed scene geometry to compare'
  before=set(DOWNLOADS.glob('voxel_build_*.stl'))
  call('openxr_set_controller_input',hand=hand,component='Trigger',value=1,auto_release=True,hold_duration=.25)
  deadline=time.monotonic()+4
  while time.monotonic()<deadline:
   new=set(DOWNLOADS.glob('voxel_build_*.stl'))-before
   if new:break
   time.sleep(.1)
  assert len(new)==1,(hand,new)
  result=validate_stl(new.pop(),expected);result['hand']=hand
  report.append(result);print('PASS',hand,'menu pointer export',json.dumps(result),flush=True)
  capture=call('openxr_capture_composited_image',eye='left')
  for b in capture['content']:
   if b['type']=='image':(HERE/f'evidence/{hand}-export.png').write_bytes(base64.b64decode(b['data']))
  time.sleep(1.7)
finally:
 for hand in ['left','right']:
  call('openxr_set_controller_input',hand=hand,component='Trigger',value=0)
 call('openxr_release_input_devices')
 (HERE/'evidence/export-validation.json').write_text(json.dumps(report,indent=2))
