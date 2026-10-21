extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
const Regions=preload("res://cad/CADSketchRegions.gd")
var stl=preload("res://tests/cad_stl_export.gd").new()
var rays=preload("res://tests/cad_face_cut.gd").new()
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok:failures+=1;push_error("MULTI FAIL: "+text_)
	else:print("MULTI PASS: "+text_)
func at(regions: Array,p: Vector2) -> Dictionary:
	for r in regions:
		if Regions.contains(r,p):return r
	return {}
func fill_area(region: Dictionary) -> float:
	var vertices:=Regions.triangles(region);var area:=0.0
	for i in range(0,vertices.size(),3):area+=absf((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]))/2
	return area
func reset(doc):
	doc.clear_all()
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	doc.status.connect(func(message):print("MULTI STATUS: ",message))
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.new_base_sketch("Front")
	var root: int=wb.active_sketch
	doc.set_profile(root,"circle",[[-20,0],[-10,0]],true)
	wb.choose_tool("circle");var second: int=wb.active_sketch
	check(second!=root and doc.sketch_roots().size()==1,"starting another circle keeps one sketch entry")
	doc.set_profile(second,"circle",[[20,0],[30,0]],true)
	var regions: Array=wb.regions()
	check(regions.size()==2,"two separate circles form two areas")
	wb.ui.show_command("extrude")
	check(wb.selected_regions.is_empty() and wb.message.contains("Please select"),"multiple areas require explicit selection")
	check(wb.select_region(Vector2(-20,0)) and wb.select_region(Vector2(20,0)) and wb.selected_regions.size()==2,"point-click selects multiple areas")
	check(wb.select_region(Vector2(20,0)) and wb.selected_regions.size()==1,"clicking selected area toggles it off")
	wb.select_region(Vector2(20,0));wb.depth_mm=10
	check(await wb.extrude(),"two selected areas extrude atomically")
	if doc.bodies.is_empty():get_tree().quit(1);return
	check(doc.bodies.size()==1 and doc.bodies[0].features.size()==1,"multi-area operation creates one history feature")
	check(absf(Doc.volume(doc.bodies[0].faces)-2*PI*100*10)<6,"both circular volumes are present")
	check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"group and multi-area feature save validation")
	var snapshot: Dictionary=doc.snapshot();doc.undo();check(doc.bodies.is_empty(),"one undo removes entire multi-area extrusion");doc.redo();check(doc.bodies.size()==1,"one redo restores entire extrusion")
	doc.load_document(snapshot);check(doc.sketch_roots().size()==1 and doc.sketch_members(root).size()==2,"reload retains one sketch with both shapes")
	check(await doc.dimension(second,"radius",12),"editing one shape rebuilds selected areas")
	check(absf(Doc.volume(doc.bodies[0].faces)-PI*(100+144)*10)<7,"dimension rebuild preserves the other selected circle")
	# Separate stopped chains can close a region together.
	reset(doc);wb.new_base_sketch("Front");root=wb.active_sketch
	doc.set_profile(root,"line",[[0,0],[40,0],[40,30]],false);wb.end_sketch_tool();wb.choose_tool("line");second=wb.active_sketch
	check(doc.sketch_roots().size()==1 and second!=root,"stop/start creates a new chain in the same sketch")
	doc.set_profile(second,"line",[[40,30],[0,30],[0,0]],false)
	regions=wb.regions();check(regions.size()==1 and absf(regions[0].area-1200)<0.01,"two open chains enclose one rectangle")
	wb.ui.show_command("extrude");check(wb.selected_regions.size()==1,"single enclosed area is selected automatically")
	check(await wb.extrude(),"area made from separate chains extrudes")
	check(absf(Doc.volume(doc.bodies[0].faces)-12000)<0.1,"separate-chain extrusion has exact volume")
	# Nested circles represent a disc and an annulus, selectable independently.
	reset(doc);root=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(root,"circle",[[0,0],[20,0]],true)
	second=doc.new_entity(root,"circle");doc.set_profile(second,"circle",[[0,0],[8,0]],true)
	regions=doc.sketch_regions(root)
	check(regions.size()==2,"nested circles form two selectable areas")
	var ring:=at(regions,Vector2(15,0));var disc:=at(regions,Vector2.ZERO)
	check(not ring.is_empty() and ring.holes.size()==1 and not disc.is_empty() and disc.holes.is_empty(),"ring excludes inner circle while disc remains selectable")
	check(absf(fill_area(ring)-(400-64)*PI)<2,"orange region fill triangulates the ring without covering its hole")
	check(await doc.extrude_regions(root,[ring.id],10,"New"),"ring alone extrudes with a hole")
	check(absf(Doc.volume(doc.bodies[0].faces)-PI*(400-64)*10)<12,"annular extrusion has the correct hollow volume")
	var ring_bytes: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(doc.print_export_faces(doc.bodies[0].id)))
	var ring_stats: Dictionary=stl.stats(ring_bytes)
	check(ring_stats.normals and ring_stats.volume>0,"annular region exports with outward STL surfaces")
	check(is_inf(rays.hit(stl.read_faces(ring_bytes),Vector3(0,0,11),Vector3(0,0,-1))),"serialized annulus retains its center hole")
	var file:=FileAccess.open("res://builds/ABCCAD_multi_ring_validation.stl",FileAccess.WRITE);file.store_buffer(ring_bytes);file.close()
	# Overlapping loops split into the intersection and each remaining crescent.
	reset(doc);root=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(root,"circle",[[-6,0],[4,0]],true)
	second=doc.new_entity(root,"circle");doc.set_profile(second,"circle",[[6,0],[16,0]],true)
	regions=doc.sketch_regions(root)
	check(regions.size()==3,"intersecting circles form three separate regions")
	var unique: Dictionary={}
	for region in regions:unique[region.id]=true
	check(unique.size()==3,"each overlapping area has its own selection identity")
	check(not at(regions,Vector2.ZERO).is_empty() and not at(regions,Vector2(-12,0)).is_empty() and not at(regions,Vector2(12,0)).is_empty(),"each overlapping area can be picked")
	var ids: Array=regions.map(func(r):return r.id)
	check(await doc.extrude_regions(root,ids,5,"New"),"all adjacent regions can extrude together")
	check(Doc.validate(doc.snapshot()).is_empty(),"overlapping region feature retains valid persistence")
	check(absf(Doc.volume(doc.bodies[0].faces)-(2*PI*100-(200*acos(0.6)-6*sqrt(256)))*5)<8,"adjacent circle areas union without duplicate volume")
	reset(doc);root=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(root,"circle",[[-6,0],[4,0]],true)
	second=doc.new_entity(root,"circle");doc.set_profile(second,"circle",[[6,0],[16,0]],true)
	regions=doc.sketch_regions(root);var crescent:=at(regions,Vector2(-12,0))
	check(await doc.extrude_regions(root,[crescent.id],5,"New"),"one crescent extrudes independently")
	check(await doc.dimension(root,"radius",12),"overlapping circle dimension retains selected crescent")
	var current:=at(doc.sketch_regions(root),Vector2(-12,0))
	check(current.id==crescent.id and absf(Doc.volume(doc.bodies[0].faces)-fill_area(current)*5)<4,"moving intersection rebuilds the correct selected area")
	# A single operation removes multiple circle regions from an existing face.
	reset(doc);root=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(root,"rectangle",[[0,0],[40,25]],true)
	check(await doc.extrude(root,10,"New"),"create target plate for multi-area Remove")
	var target: int=doc.bodies[0].id
	var plane:=Transform3D(Basis.IDENTITY,Vector3(0,0,10))
	root=doc.new_sketch(plane,target);doc.set_profile(root,"circle",[[-20,0],[-14,0]],true)
	second=doc.new_entity(root,"circle");doc.set_profile(second,"circle",[[20,0],[26,0]],true)
	regions=doc.sketch_regions(root)
	wb.active_sketch=second;wb.selected_body=target;wb.operation="Remove";wb.depth_mm=-10;wb.ui.show_command("extrude")
	wb.select_region(Vector2(-20,0));wb.select_region(Vector2(20,0));wb.extrude_arrow.refresh()
	var before_preview: Dictionary=doc.snapshot()
	wb.extrude_preview.refresh(0.2)
	for frame in 4:await get_tree().process_frame
	check(wb.extrude_preview.result_mesh.visible,"multi-area Remove has a settled live preview")
	var preview_faces: Array=Doc.faces_from_mesh(wb.extrude_preview.result_mesh.mesh)
	check(is_inf(rays.hit(preview_faces,Vector3(-20,0,11),Vector3(0,0,-1))) and is_inf(rays.hit(preview_faces,Vector3(20,0,11),Vector3(0,0,-1))),"live preview opens both selected holes")
	check(doc.snapshot()==before_preview,"multi-area live preview does not mutate saved geometry")
	wb.extrude_preview.cancel()
	check(await doc.extrude_regions(root,regions.map(func(r):return r.id),-10,"Remove",target),"both selected circles remove through a solid face")
	check(absf(Doc.volume(doc.bodies[0].faces)-(40000-2*PI*36*10))<5,"multi-area Remove subtracts both holes")
	var hole_bytes: PackedByteArray=STLIO.Exporter.SaveToBytes(Doc.mesh_from_faces(doc.print_export_faces(target)))
	var exported_faces: Array=stl.read_faces(hole_bytes)
	check(is_inf(rays.hit(exported_faces,Vector3(-20,0,11),Vector3(0,0,-1))) and is_inf(rays.hit(exported_faces,Vector3(20,0,11),Vector3(0,0,-1))),"serialized multi-area cut keeps both through holes open")
	file=FileAccess.open("res://builds/ABCCAD_multi_holes_validation.stl",FileAccess.WRITE);file.store_buffer(hole_bytes);file.close()
	var attached: Dictionary={}
	for entity in doc.sketches:attached[int(entity.id)]=entity.duplicate(true)
	doc.apply_body_pose(target,doc.body(target).duplicate(true),attached,Transform3D(Basis.from_euler(Vector3(0.3,0.5,0.2)),Vector3(150,1100,-650)))
	check(Doc.validate(doc.snapshot()).is_empty(),"moving a part retains grouped sketch and feature planes")
	check(await doc.dimension(second,"radius",7),"grouped region dimensions rebuild after part movement")
	check(absf(Doc.volume(doc.bodies[0].faces)-(40000-PI*85*10))<7,"moved-part rebuild retains both selected cut areas")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	check(Doc.validate(saved).is_empty(),"multi-area Remove saves with groups and region selection")
	var corrupt:=saved.duplicate(true);corrupt.bodies[0].features[-1].sketch.region_entities[-1].points[0]=["bad",0]
	check(not Doc.validate(corrupt).is_empty(),"corrupt saved region source coordinates reject safely")
	var bad:=saved.duplicate(true);bad.sketches[-1].group_id=99999
	check(not Doc.validate(bad).is_empty(),"missing sketch group reference rejects on load")
	wb.active_sketch=second;wb.toggle_sketch_visibility(root)
	check(doc.sketch_members(root).all(func(entity):return not wb.sketch_visibility.get(int(entity.id),true)),"sketch eye hides every shape in the sketch")
	var plan: Dictionary=doc.deletion_plan(root)
	check(root in plan.sketches and second in plan.sketches and target in plan.bodies,"deleting a grouped sketch includes all shapes and dependent solids")
	check(doc.delete_sketch(root) and doc.sketch_members(root).is_empty(),"confirmed sketch deletion removes the full group")
	doc.undo();check(doc.sketch_members(root).size()==2 and doc.bodies.size()==1,"undo restores the grouped sketch and solid")
	check(await doc.dimension(root,"radius",6),"both shapes can retain their own driving constraints")
	doc.clear_constraints(second)
	check(doc.sketch_members(root).all(func(s):return s.constraints.is_empty()),"Clear constraints applies to the entire grouped sketch")
	doc.undo()
	check(not doc.sketch(root).constraints.is_empty() and not doc.sketch(second).constraints.is_empty(),"undo restores constraints on both shapes")
	stl.free();rays.free()
	print("MULTI RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
