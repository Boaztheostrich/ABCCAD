#!/usr/bin/env python3
"""Native OpenXR regression: inject input, assert read-only Godot scene snapshots."""
import json, pathlib, sys, time
from operator_client import Operator
HERE = pathlib.Path(__file__).resolve().parent
c = Operator()
report = []
def call(name, **args):
    result = c.call(name,args)
    if result.get('isError'): raise RuntimeError(result)
    return result

def state(): return json.loads((HERE/'evidence/state.json').read_text())
def wait_for(predicate, timeout=4):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        s=state()
        if predicate(s): return s
        time.sleep(.06)
    raise AssertionError(f'Condition timed out: {state()}')
def check(label, condition):
    assert condition, label
    report.append(label)
    print('PASS',label,flush=True)
def inp(hand, component, value, **extra):
    call('openxr_set_controller_input',hand=hand,component=component,value=value,**extra)
def pose(hand, position):
    for kind in ['aim','grip']:
        call('openxr_set_controller_pose',hand=hand,pose_type=kind,position=position,orientation=[0,0,0,1],base_space='stage')
def press(hand,button):
    inp(hand,button,1);time.sleep(.25);inp(hand,button,0);time.sleep(.15)
try:
    call('openxr_release_input_devices')
    for hand,x in [('left',-.4),('right',.4)]:
        key=hand.title()+'Hand'
        pose(hand,[x,1.1,-.65])
        s=wait_for(lambda s: abs(s['hands'][key]['position'][0]-x)<.01)
        check(hand+' native pose reaches Godot', s['hands'][key]['active'])
        before={b['id'] for b in s['blocks']}
        button='X' if hand=='left' else 'A'
        inp(hand,button,1)
        s=wait_for(lambda s:len(s['blocks'])==len(before)+1)
        time.sleep(.45)
        check(hand+' spawn exactly once while held',len(state()['blocks'])==len(before)+1)
        inp(hand,button,0)
        wait_for(lambda s:not s['hands'][key]['spawn'])
        block=next(b for b in s['blocks'] if b['id'] not in before)
        block_id=block['id']
        time.sleep(.7)
        block=next(b for b in state()['blocks'] if b['id']==block_id)
        pose(hand,block['position'])
        time.sleep(.25)
        inp(hand,'Grip',1)
        s=wait_for(lambda s:s['hands'][key]['held']==block_id)
        check(hand+' native analog grip grabs eligible block',s['hands'][key]['grip']>.9)
        target=[x,1.1,-.65]
        pose(hand,target)
        s=wait_for(lambda s: next(b for b in s['blocks'] if b['id']==block_id)['position'][1]>.9)
        check(hand+' held block follows controller',s['hands'][key]['held']==block_id)
        old=s['hands'][key]['color_index']
        old_color=next(b for b in s['blocks'] if b['id']==block_id).get('color')
        press(hand,'Y' if hand=='left' else 'B')
        s=wait_for(lambda s:s['hands'][key]['color_index']==(old+1)%7)
        check(hand+' color increments once',s['hands'][key]['color_index']==(old+1)%7)
        check(hand+' held block material changes color',next(b for b in s['blocks'] if b['id']==block_id)['color'] != old_color)
        before_voxels=s['voxels']
        inp(hand,'Grip',0)
        s=wait_for(lambda s:s['hands'][key]['held']==0 and s['voxels']>before_voxels)
        check(hand+' release registers snapped voxels',s['hands'][key]['grip']==0)
    before=state()['hands']['RightHand']['block_index']
    inp('right','Thumbstick',1,sub_component='X');time.sleep(.25)
    inp('right','Thumbstick',0,sub_component='X')
    s=wait_for(lambda s:s['hands']['RightHand']['stick'][0]==0)
    check('right block switch and left mirrored selection',s['hands']['RightHand']['block_index']==(before+1)%5 and s['hands']['LeftHand']['block_index']==s['hands']['RightHand']['block_index'])
finally:
    for hand in ['left','right']:
        for component in ['Grip','Trigger','X' if hand=='left' else 'A','Y' if hand=='left' else 'B']:
            try: inp(hand,component,0)
            except Exception: pass
        try: inp(hand,'Thumbstick',0,sub_component='X')
        except Exception: pass
    call('openxr_release_input_devices')
    (HERE/'evidence/validation.json').write_text(json.dumps({'passed':report,'state':state()},indent=2))
