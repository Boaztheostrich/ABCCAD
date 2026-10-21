extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("DIRECTION FAIL: "+text_)
	else: print("DIRECTION PASS: "+text_)
func frames():
	for _i in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
func _ready():
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	wb.enabled=true; wb.open_panel(); wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	check(is_equal_approx(wb._snap_tolerance(),30),"origin/coincident/HV capture radius is 10x larger")
	check(wb._infer_point(id,Vector2(20,10),wb._snap_tolerance()).constraint.get("kind")=="origin","origin snaps from 22 mm away")
	doc.set_profile(id,"line",[[0,0]],false)
	var snapped: Dictionary=wb._infer_point(id,Vector2(20,2),wb._snap_tolerance())
	check(snapped.constraint.get("kind")=="horizontal" and snapped.point.distance_to(Vector2(20,0))<0.001,"strong snap does not collapse next endpoint onto start")
	check(wb._infer_point(id,Vector2(100,24),wb._snap_tolerance()).constraint.get("kind")=="horizontal","horizontal accepts a 24 mm aiming deviation")
	check(wb._infer_point(id,Vector2(24,100),wb._snap_tolerance()).constraint.get("kind")=="vertical","vertical accepts a 24 mm aiming deviation")
	doc.set_profile(id,"line",[[0,0],[20,0]],false)
	var corner: Dictionary=wb._infer_point(id,Vector2(20,10),wb._snap_tolerance())
	check(corner.constraint.get("kind")=="vertical" and corner.point==Vector2(20,10),"strong snaps do not pull a short new segment back to the previous segment midpoint")
	doc.set_profile(id,"line",[[0,0]],false)
	var pnode: Node3D=wb.plane_display.get_children().filter(func(n):return n.get_meta("sketch_plane",false))[0]
	check(is_equal_approx(pnode.material_override.albedo_color.a,0.5),"active sketch plane is 50 percent opaque")
	var hand:=Node3D.new();add_child(hand)
	var plane: Transform3D=Doc.unpack_transform(doc.sketch(id).plane)
	hand.global_basis=plane.basis
	# Plane transform stores origin in mm; construct a world-meter ray explicitly.
	hand.global_position=plane.origin*0.001+plane.basis*Vector3(0.02,0.002,0.3)
	var hit: Dictionary=wb.pointer_surface_hit(hand)
	check(hit.get("plane",false) and hit.point.distance_to(plane.origin*0.001+plane.basis*Vector3(0.02,0,0))<0.001,"laser endpoint follows the snapped point on sketch plane")
	doc.set_profile(id,"rectangle",[[0,0],[20,15]],true)
	wb.ui.show_command("extrude");wb.depth_mm=30;wb.extrude_arrow.refresh()
	var before: Dictionary=doc.snapshot()
	check(wb.extrude_arrow.visible and wb.extrude_arrow.direction.dot(plane.basis.z)>0.99,"positive extrusion arrow follows sketch normal")
	check(wb.extrude_arrow.end_point.distance_to(plane.origin*0.001+plane.basis.z*0.03)<0.001,"direction indicator end reflects actual 30 mm depth")
	wb.reverse_extrude_direction()
	check(wb.depth_mm==-30 and wb.extrude_arrow.direction.dot(plane.basis.z)<-0.99 and doc.snapshot()==before,"reverse flips arrow and signed depth without editing model")
	hand.global_basis=Basis.IDENTITY
	hand.global_position=wb.extrude_arrow.tip_point+Vector3(0,0,0.2)
	wb._world_click(hand)
	check(wb.depth_mm==30,"triggering arrow reverses depth")
	wb.ui.show_command("select");wb.extrude_arrow.refresh()
	check(not wb.extrude_arrow.visible,"arrow hides outside Extrude command")
	wb.depth_mm=10;check(await wb.extrude(),"create solid for laser targeting")
	await frames()
	hand.global_transform=Transform3D(plane.basis,plane.origin*0.001+plane.basis*Vector3(0,0,0.1))
	hit=wb.pointer_surface_hit(hand)
	check(not hit.is_empty() and not hit.get("plane",false) and hit.point.distance_to(plane.origin*0.001+plane.basis.z*0.01)<0.001,"laser stops on exact visible solid face")
	var cut: int=doc.new_sketch(plane,int(doc.bodies[0].id));doc.set_profile(cut,"circle",[[0,0],[5,0]])
	check(await doc.extrude(cut,10,"Remove"),"create through-hole for exact ray check")
	await frames();wb.plane_visibility["Sketch plane"]=false;wb._redraw()
	hit=wb.pointer_surface_hit(hand)
	check(hit.is_empty(),"laser passes through real hole instead of stopping on convex pickup hull")
	for controller in [wb.left,wb.right]:
		var pointer=controller.get_node(str(controller.name)+"/FunctionPointer")
		check(wb._ray_node(controller)==pointer,"drawing and cursor share actual controller laser transform")
	print("DIRECTION SURFACE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
