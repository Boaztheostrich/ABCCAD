extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok:failures+=1;push_error("MULTI POINTER FAIL: "+text_)
	else:print("MULTI POINTER PASS: "+text_)
func aim(ray: Node3D,plane: Transform3D,point: Vector2):
	ray.global_transform=Transform3D(plane.basis,(plane*Vector3(point.x,point.y,100))*0.001)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.auto_constraints=false;wb.new_base_sketch("Front")
	wb.ui.show_command("sketch")
	var root: int=wb.active_sketch
	var plane:=Doc.unpack_transform(doc.sketch(root).plane)
	var left_ray:=Node3D.new();var right_ray:=Node3D.new();add_child(left_ray);add_child(right_ray)
	wb.choose_tool("circle")
	for p in [Vector2(-40,0),Vector2(-32,0)]:aim(left_ray,plane,p);wb._world_click(left_ray)
	check(doc.sketch(root).kind=="circle" and doc.sketch(root).closed,"pointer draws the first closed circle")
	wb.choose_tool("circle");var second: int=wb.active_sketch
	for p in [Vector2(40,0),Vector2(48,0)]:aim(right_ray,plane,p);wb._world_click(right_ray)
	check(second!=root and doc.sketch_root(second)==root and doc.sketch(second).closed,"other pointer draws another circle in the same sketch")
	wb.choose_tool("line");var first_chain: int=wb.active_sketch
	for p in [Vector2(-60,-30),Vector2(-20,-30)]:aim(left_ray,plane,p);wb._world_click(left_ray)
	wb.end_sketch_tool();wb.choose_tool("line");var second_chain: int=wb.active_sketch
	for p in [Vector2(20,-30),Vector2(60,-30)]:aim(right_ray,plane,p);wb._world_click(right_ray)
	wb.end_sketch_tool()
	check(doc.sketch_roots().size()==1 and doc.sketch_members(root).size()==4,"stopped pointer line chains stay under one sketch")
	check(first_chain!=second_chain and doc.sketch(first_chain).points==[[-60.0,-30.0],[-20.0,-30.0]],"starting a new chain preserves the previous chain")
	wb.ui.show_command("extrude")
	check(wb.regions().size()==2 and wb.selected_regions.is_empty(),"open line chains add no false area and two circles require selection")
	aim(left_ray,plane,Vector2(-40,0));wb._world_click(left_ray)
	aim(right_ray,plane,Vector2(40,0));wb._world_click(right_ray)
	check(wb.selected_regions.size()==2,"both controller rays can select enclosed areas")
	wb._world_click(right_ray)
	check(wb.selected_regions.size()==1,"clicking the same area again deselects it")
	wb._world_click(right_ray)
	var started:=Time.get_ticks_usec()
	for i in 100:wb.selected_profile()
	print("MULTI PROFILE CACHE: %.3f ms per query" % ((Time.get_ticks_usec()-started)/100000.0))
	wb.depth_mm=10
	check(await wb.extrude(),"pointer-selected areas extrude together")
	check(doc.sketch_members(root).all(func(s):return not wb.sketch_visibility.get(int(s.id),true)),"completed extrusion hides the whole sketch")
	wb.ui.show_command("sketch");wb.choose_tool("circle")
	check(doc.sketch_roots().size()==1 and doc.sketch_members(root).all(func(s):return wb.sketch_visibility.get(int(s.id),true)),"resuming drawing reopens all geometry in that sketch")
	wb.new_base_sketch("Top")
	check(doc.sketch_roots().size()==2,"explicit new plane sketch still creates a separate sketch")
	print("MULTI POINTER RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
