extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
const Reference=preload("res://cad/CADReferencePlane.gd")
const Preview=preload("res://cad/CADPrintPreview.gd")
var checks:=0
var failures:=0
var saved:=false
var loaded:=false
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error("TABLE PREVIEW FAIL: "+label)
	else: print("TABLE PREVIEW PASS: "+label)
func frames(count: int=3):
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame
func _ready():
	super._ready()
	await frames()
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	var ring_bounds: Rect2=wb.ui.progress_ring.get_global_rect()
	check(ring_bounds.position.x>=0 and ring_bounds.end.x<=1120 and ring_bounds.position.y>=0 and ring_bounds.end.y<=900,"circular loading indicator stays inside the VR viewport")
	var right=get_node("XROrigin3D/RightHand")
	var left=get_node("XROrigin3D/LeftHand")
	var surface:=Reference.from_contacts([Vector3(0,0.8,-0.5),Vector3(0.2,0.8,-0.5),Vector3(0,0.8,-0.7)])
	check(surface.has("pose") and surface.pose.basis.z.is_equal_approx(Vector3.UP),"three tabletop contacts form upward plane")
	check(surface.pose.origin.is_equal_approx(Vector3(0,0.8,-0.5)),"first contact sets reference origin")
	check(surface.pose.basis.x.is_equal_approx(Vector3.RIGHT),"second contact sets plane X direction")
	check(Reference.from_contacts([Vector3.ZERO,Vector3.RIGHT,Vector3.RIGHT*2]).has("error"),"collinear contacts rejected")
	check(Reference.from_contacts([Vector3.ZERO,Vector3.RIGHT*0.005,Vector3.FORWARD]).has("error"),"near-identical contacts rejected")
	var tilted:=Reference.from_contacts([Vector3.ZERO,Vector3(1,0.1,0),Vector3(0,0.2,-1)])
	check(tilted.has("pose") and tilted.pose.basis.determinant()>0.999,"tilted physical surfaces retain their measured plane")
	wb.probe_offset_mm=Vector3(0,0,-70)
	right.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,0.8,-0.43))
	check(wb.probe_point(right).distance_to(Vector3(0,0.8,-0.5))<0.00001,"controller probe offset applied in physical mm")
	wb.tool="capture_plane"
	wb.contact_points.clear()
	for point in [Vector3(0,0.8,-0.5),Vector3(0.2,0.8,-0.5),Vector3(0,0.8,-0.7)]:
		right.global_position=point+Vector3(0,0,0.07)
		wb.capture_contact(right)
	check(wb.reference_locked() and wb.tool=="select","third trigger contact commits locked table")
	check(Doc.validate(doc.snapshot()).is_empty(),"reference-plane document validates")
	doc.undo()
	check(doc.reference_plane.is_empty(),"undo removes the captured reference as one operation")
	doc.redo()
	check(wb.reference_locked(),"redo restores the complete three-contact plane")
	wb.new_table_sketch()
	var id: int=wb.active_sketch
	check(Doc.unpack_transform(doc.sketch(id).plane).basis.z.is_equal_approx(Vector3.UP),"table sketch lies on captured surface")
	doc.set_profile(id,"rectangle",[[0,0],[12.7,25.4]])
	check(await doc.extrude(id,76.2,"New"),"create metric 1 x 2 x 3 inch reference block")
	await frames()
	var baseline: Dictionary=doc.snapshot()
	var anchor: Transform3D=wb.stage_to_world(Doc.unpack_transform(doc.reference_plane.stage_pose))
	wb.table_view_scale=4
	wb._update_reference_view()
	check(doc.snapshot()==baseline,"table view zoom never changes saved dimensions")
	check((doc.view_transform*(Doc.unpack_transform(doc.reference_plane.plane_mm).origin*0.001)).distance_to(anchor.origin)<0.00001,"zoom pivot remains on physical table origin")
	check(wb.reference_display.global_transform.is_equal_approx(anchor),"reference grid stays fixed while model enlarges")
	var part=doc.get_node("Part_"+str(doc.bodies[0].id))
	check(part.get_node("MeshInstance3D").scale.is_equal_approx(Vector3.ONE*4),"CAD rendering enlarges around locked plane")
	check(part.get_node("CollisionShape3D").scale.is_equal_approx(Vector3.ONE*4),"pickup hull matches enlarged visual")
	wb.reset_view()
	check(absf(wb.display_scale()-1)<0.00001 and doc.view_transform.basis.x.length()>0.999,"physical-size reset restores one meter per tracked meter")
	var bounds: Vector3=part.get_node("MeshInstance3D").mesh.get_aabb().size
	check(absf(bounds.x-0.0254)<0.00001 and absf(bounds.y-0.0762)<0.00001 and absf(bounds.z-0.0508)<0.00001,"1:1 reference block has exact physical 25.4 / 50.8 / 76.2 mm bounds")
	XRServer.world_scale=0.5
	wb._update_reference_view()
	check(absf(doc.view_transform.basis.x.length()/XRServer.world_scale-1)<0.00001,"loaded table retains physical 1:1 even after legacy tracking zoom")
	check(absf(wb.reference_display.global_basis.x.length()/XRServer.world_scale-1)<0.00001,"reference grid size remains physical across tracking-scale changes")
	XRServer.world_scale=1.0
	wb._update_reference_view()
	# A scaled view must invert pickup movement before editing metric geometry.
	wb.table_view_scale=4
	wb._update_reference_view()
	right.my_pickup_function._pick_up_object(part)
	part.global_position+=Vector3(0.04,0,0)
	part._sync_pose()
	var before_point: Array=baseline.bodies[0].faces[0]
	check(absf(doc.bodies[0].faces[0][0]-before_point[0]-10)<0.001,"40 mm movement at 4x view moves model 10 mm")
	right.my_pickup_function.drop_object()
	await frames()
	check(not doc.busy,"scaled CAD pickup releases normally")
	var placed: Dictionary=doc.snapshot()
	doc.undo()
	await frames()
	check(doc.snapshot()==baseline and absf(wb.table_view_scale-4)<0.001,"undo restores placement without resetting table zoom")
	doc.redo()
	await frames()
	check(doc.snapshot()==placed,"redo restores moved part in table coordinates")
	wb.toggle_part_rotation_lock()
	part=doc.get_node("Part_"+str(doc.bodies[0].id))
	var held_basis: Basis=part.global_basis
	left.my_pickup_function._pick_up_object(part)
	part.global_basis=Basis(Vector3.UP,0.5)*held_basis
	part._sync_pose()
	check(part.global_basis.is_equal_approx(held_basis),"rotation lock preserves part orientation during grip")
	left.my_pickup_function.drop_object()
	await frames()
	wb.reset_view()
	var saver=get_node("SaveSystem")
	saver.save_directory="/private/tmp/abccad-table-preview-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(saver.save_directory)
	SignalBus.save_finished.connect(func(ok,_text):saved=ok)
	SignalBus.load_finished.connect(func(ok,_text):loaded=ok)
	saver._save_game("table")
	var saved_state: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	check(saved,"table reference and CAD solid save")
	doc.reference_plane={}
	saver._load_game("table.json")
	await frames()
	check(loaded and JSON.parse_string(JSON.stringify(doc.snapshot()))==saved_state,"plane pose, lock and model survive save/load")
	var invalid: Dictionary=doc.snapshot()
	invalid.reference_plane.stage_pose[0]=3
	check(not Doc.validate(invalid).is_empty(),"malformed reference transform rejected")
	check(doc.base_plane("Top").basis.z.is_equal_approx(Vector3.UP),"built-in Top remains ground-parallel")
	var export_faces: Array=doc.export_faces(doc.bodies[0].faces)
	var export_bounds:=AABB(Vector3(export_faces[0][0],export_faces[0][1],export_faces[0][2]),Vector3.ZERO)
	for point in export_faces: export_bounds=export_bounds.expand(Vector3(point[0],point[1],point[2]))
	check(export_bounds.size.distance_to(Vector3(25.4,50.8,76.2))<0.002,"table export puts reference dimensions on X/Y and height on print Z")
	check(absf(Doc.volume(export_faces)-Doc.volume(doc.bodies[0].faces))<1,"table export rotates coordinates without changing volume")
	var exporter=preload("res://VoxelExporter.gd").new()
	add_child(exporter)
	var mixed_export: PackedVector3Array=exporter.build_export_mesh(1000).get_faces()
	var matches:=mixed_export.size()==export_faces.size()
	for i in mixed_export.size():
		if mixed_export[i].distance_to(Vector3(export_faces[i][0],export_faces[i][1],export_faces[i][2]))>0.001: matches=false
	check(matches,"combined exporter and selected-part export share the same table frame")
	# Standalone layer generator: sloping triangular prism creates true stairs.
	var preview=Preview.new()
	add_child(preview)
	var ramp_id: int=doc.new_sketch(Transform3D.IDENTITY)
	doc.set_profile(ramp_id,"line",[[0,0],[4,0],[0,4]],true)
	check(await doc.extrude(ramp_id,2,"New"),"create ramp section for print preview")
	var ramp: Array=doc.bodies[-1].faces
	var print_plane:=Transform3D(Basis(Vector3.RIGHT,Vector3.FORWARD,Vector3.UP),Vector3.ZERO)
	var snapshot_before: Dictionary=doc.snapshot()
	var mesh: ArrayMesh=await preview.build(ramp,print_plane)
	check(mesh!=null and preview.progress==1,"0.2 mm layer generation completes with progress")
	if mesh:
		var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var preview_faces: Array=[]
		for v in vertices: preview_faces.append([v.x*1000,v.y*1000,v.z*1000])
		check(absf(Doc.volume(preview_faces)-16)<0.02,"exposed layer mesh has consistent closed-surface winding and expected ramp volume")
		var stepped:=true
		for i in range(0,vertices.size(),3):
			var n: Vector3=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).normalized()
			if absf(n.y)>0.0001 and absf(absf(n.y)-1)>0.0001: stepped=false
		check(stepped,"ramp preview has horizontal treads and vertical risers, not smooth slopes")
		var levels: Dictionary={}
		for v in vertices: levels[roundi(v.y*1000/0.2)]=true
		check(levels.size()==21,"4 mm ramp contains twenty 0.2 mm layers")
	check(doc.snapshot()==snapshot_before,"print preview leaves CAD and export document untouched")
	var holed=Doc.new()
	add_child(holed)
	holed.remove_from_group("cad_document")
	var plate_id: int=holed.new_sketch(Transform3D.IDENTITY)
	holed.set_profile(plate_id,"rectangle",[[0,0],[2,2]])
	await holed.extrude(plate_id,1,"New")
	var hole_id: int=holed.new_sketch(Transform3D.IDENTITY,int(holed.bodies[0].id))
	holed.set_profile(hole_id,"circle",[[0,0],[1,0]])
	check(await holed.extrude(hole_id,1,"Remove"),"prepare real through-hole solid for layer preview")
	var hole_mesh: ArrayMesh=await preview.build(holed.bodies[0].faces,Transform3D.IDENTITY)
	var hole_vertices: PackedVector3Array=hole_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var hole_faces: Array=[]
	var open_hole:=true
	for v in hole_vertices: hole_faces.append([v.x*1000,v.y*1000,v.z*1000])
	for i in range(0,hole_vertices.size(),3):
		if Geometry3D.ray_intersects_triangle(Vector3(0,0,2),Vector3.FORWARD,hole_vertices[i]*1000,hole_vertices[i+1]*1000,hole_vertices[i+2]*1000)!=null: open_hole=false
	check(open_hole,"generated stepped mesh keeps the real through-hole open")
	check(absf(Doc.volume(hole_faces)-Doc.volume(holed.bodies[0].faces))<0.01,"vertical through-hole layer mesh preserves solid volume")
	# Even/odd cap fill must leave a through hole open.
	var edges: Array=[]
	for polygon in [[Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)],[Vector2(-1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,-1)]]:
		for i in 4: edges.append([polygon[i],polygon[(i+1)%4]])
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	Preview.append_slab(vertices,colors,edges,0,0.2,0)
	var top_area:=0.0
	for i in range(0,vertices.size(),3):
		var a: Vector3=vertices[i]
		var b: Vector3=vertices[i+1]
		var c: Vector3=vertices[i+2]
		if absf(a.z-0.2)<0.00001 and absf(b.z-0.2)<0.00001 and absf(c.z-0.2)<0.00001: top_area+=(b-a).cross(c-a).length()*0.5
	check(absf(top_area-12)<0.001,"layer caps preserve holes with even/odd fill")
	# Preview-enabled load/selection changes must not leave a stale ghost mesh.
	wb.selected_body=int(doc.bodies[-1].id)
	wb.set_print_preview(true)
	for _i in 400:
		if not wb.print_loading: break
		await get_tree().process_frame
	check(wb.print_display.visible and not wb.print_loading,"workbench swaps the exact surface for generated preview")
	wb.set_print_preview(false)
	wb.set_print_preview(true)
	wb.selected_body=-1
	wb._update_print_preview()
	await frames()
	check(not wb.print_loading and not wb.print_display.visible,"clearing selection cancels preview without ghost geometry")
	# Toggle cancellation must restore the exact solid immediately.
	wb.selected_body=int(doc.bodies[-1].id)
	wb.set_print_preview(true)
	wb.set_print_preview(false)
	await frames()
	check(not wb.print_loading and not wb.print_display.visible,"layer toggle cancels pending generation")
	check(doc.get_node("Part_"+str(doc.bodies[-1].id)).get_node("MeshInstance3D").visible,"turning preview off restores exact CAD mesh")
	wb.set_print_preview(false)
	var ref_only: Dictionary=doc.reference_plane.duplicate(true)
	doc.load_document({"version":1,"bodies":[],"sketches":[],"next_id":1,"reference_plane":ref_only})
	saver._save_game("plane-only")
	var plane_payload=JSON.parse_string(FileAccess.get_file_as_string(saver.save_directory.path_join("plane-only.json")))
	check(saved and plane_payload is Dictionary and plane_payload.cad.reference_plane==JSON.parse_string(JSON.stringify(ref_only)),"a reference plane saves even before a part is created")
	# Cancellation also occurs through leaving/removing the preview worker.
	preview.cancel()
	await frames()
	print("TABLE PREVIEW RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
