extends "res://main.gd"
const Document=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error("CAD INTERACTION FAIL: "+label)
	else: print("CAD INTERACTION PASS: "+label)
func frames():
	for _i in 3:
		await get_tree().process_frame
		await get_tree().physics_frame
func _ready():
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	var left=get_node("XROrigin3D/LeftHand")
	for shape in ["cube","brick","wedge","m_cube","corner_wedge"]:
		left.restore_block_from_history({"grid_pos":Vector3i(0,10,-10),"shape_type":shape,"rotation":Basis.IDENTITY,"color":Color.RED,"world_origin":Vector3(0,1,-1)})
		await frames()
		var count: int=VoxelDatabase.get_voxel_count()
		wb.select_face(Vector3(0,1,-0.4),Vector3.FORWARD)
		check(not wb.selected_hit.is_empty(),shape+" ray selects actual visible face")
		if wb.selected_hit.is_empty(): continue
		wb.convert_edges()
		var sketch: Dictionary=doc.sketch(wb.active_sketch)
		check(sketch.closed and sketch.kind=="line" and sketch.points.size()>=3,shape+" converts face boundary into closed sketch lines")
		wb.promote_selected_block()
		await frames()
		check(VoxelDatabase.get_voxel_count()==0 and doc.bodies.size()==1,shape+" converts to CAD without duplicate visible block")
		check(VoxelDatabase.undo_stack.is_empty() and VoxelDatabase.redo_stack.is_empty(),shape+" conversion prevents old block history duplicates")
		var source: Dictionary=doc.bodies[0].converted_source
		var occupied:=Vector3i(source.grid[0],source.grid[1],source.grid[2])
		left.restore_block_from_history({"grid_pos":occupied,"shape_type":"cube","rotation":Basis.IDENTITY,"color":Color.BLUE,"world_origin":VoxelDatabase.grid_to_world(occupied)})
		doc.undo()
		check(doc.bodies.size()==1 and VoxelDatabase.get_voxel_count()==1,shape+" conversion undo refuses overlapping new block")
		VoxelDatabase.remove_voxel(occupied,true,true)
		await frames()
		doc.undo()
		await frames()
		check(VoxelDatabase.get_voxel_count()==count and doc.bodies.is_empty(),shape+" conversion undo restores original footprint")
		doc.redo()
		await frames()
		check(VoxelDatabase.get_voxel_count()==0 and doc.bodies.size()==1,shape+" conversion redo removes restored block once")
		check(Document.validate(doc.snapshot()).is_empty(),shape+" converted document validates")
		check(await doc.extrude(wb.active_sketch,2,"Add"),shape+" supports Add on converted boundary")
		for pos in VoxelDatabase.get_all_voxels(): VoxelDatabase.remove_voxel(pos,true,true)
		doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1})
		await frames()
	# Closing on the starting endpoint shares that vertex; it must not move the
	# previous corner onto the start and collapse the profile.
	wb.active_sketch=doc.new_sketch(Transform3D.IDENTITY)
	doc.set_profile(wb.active_sketch,"line",[[0,0],[40,0],[40,30]],false)
	wb.tool="line"
	var pointer:=Node3D.new()
	add_child(pointer)
	pointer.position=Vector3(0,0,1)
	wb._world_click(pointer)
	var closed: Dictionary=doc.sketch(wb.active_sketch)
	check(closed.closed and closed.points.size()==3 and Vector2(closed.points[-1][0],closed.points[-1][1]).is_equal_approx(Vector2(40,30)),"endpoint closure preserves previous corner")
	check(await doc.extrude(wb.active_sketch,5,"New"),"automatically closed line sketch extrudes successfully")
	# Small triangles must be intersected in mm, not rejected by the ray helper's
	# absolute determinant tolerance in meter coordinates.
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1})
	var tiny: int=doc.new_sketch(Transform3D(Basis.IDENTITY,Vector3(0,1150,-650)))
	doc.set_profile(tiny,"rectangle",[[0,0],[0.5,0.5]])
	check(await doc.extrude(tiny,1,"New"),"create one millimeter solid")
	wb.select_face(Vector3(0.0002,1.1501,-0.3),Vector3.FORWARD)
	check(not wb.selected_hit.is_empty(),"small CAD faces remain ray-selectable")
	print("CAD INTERACTION RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
