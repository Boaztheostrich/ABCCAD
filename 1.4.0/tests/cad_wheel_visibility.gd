extends SceneTree
const Wheel=preload("res://cad/CADCommandWheel.gd")
var failures:=0
var checks:=0
func check(ok: bool, text: String):
	checks+=1
	if not ok: failures+=1;push_error("WHEEL VISIBILITY FAIL: "+text)
	else: print("WHEEL VISIBILITY PASS: "+text)
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(800,800)
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera);camera.current=true;camera.fov=75;camera.near=0.001
	await process_frame
	var wheel:=Wheel.new()
	wheel.update_input(Vector2.ZERO,false,0.1,true,8)
	wheel.update_input(Vector2.RIGHT,false,0.1,true,8)
	var hand:=Vector3(0.25,-0.30,-0.40)
	var old_position:=hand*0.02+Vector3(0,0.17,-0.10)
	check(not camera.is_position_in_frustum(old_position) and wheel._open and wheel.selected==2,"original zoomed-out wheel is overhead/off-screen while selection remains active")
	check(wheel.update_input(Vector2.RIGHT,true,0.1,true,8)==2,"invisible original wheel still accepts clicks, matching reported symptom")
	wheel.free()
	for scale_ in [0.02,0.1,1.0,8.43,20.0]:
		for controller in [hand,Vector3(0,-0.8,-0.05),Vector3.ZERO,Vector3(-1,1,-0.4)]:
			var position: Vector3=controller*scale_
			var pose:=Wheel.presentation_transform(position,camera.global_transform,scale_)
			var physical_offset: Vector3=(pose.origin-position)/scale_
			check(physical_offset.is_equal_approx(Vector3(0,0.17,-0.10)),"fixed controller-relative offset at world scale %.2f, hand %s" % [scale_,controller])
			check(is_equal_approx(pose.basis.x.length(),scale_),"ring size uses the same physical scale as its offset")
			if controller==Vector3(0,-0.8,-0.05): check(pose.origin.y<0,"hand at side keeps wheel below head, including at extreme zoom")
	var head:=Transform3D(Basis.from_euler(Vector3(0.3,1.2,-0.1)),Vector3(120,42,-70))
	var pose:=Wheel.presentation_transform(head*hand,head,1)
	var actual: Vector3=head.basis.inverse()*(pose.origin-head*hand)
	check(actual.distance_to(Vector3(0,0.17,-0.1))<0.0001,"head rotation and recentering preserve physical controller offset")
	var near_pose:=Wheel.presentation_transform(Vector3(0,-0.17,0.1),Transform3D.IDENTITY,1)
	check(near_pose.basis.is_finite(),"controller beside viewer keeps finite orientation")
	print("WHEEL VISIBILITY RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
