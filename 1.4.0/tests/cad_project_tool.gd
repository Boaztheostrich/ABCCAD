extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("PROJECT FAIL: "+text_)
	else: print("PROJECT PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.new_base_sketch("Front")
	var source: int=wb.active_sketch
	doc.set_profile(source,"rectangle",[[0,0],[20,20]],true)
	check(await wb.extrude(),"create 40 mm square source face")
	var body_id: int=doc.bodies[0].id
	var plane:=Doc.unpack_transform(doc.sketch(source).plane)
	wb.select_face((plane*Vector3(0,0,11))*0.001,-plane.basis.z);wb.new_sketch(true)
	var id: int=wb.active_sketch
	var original_body: Dictionary=doc.body(body_id).duplicate(true)
	wb.start_use_edge()
	var hand:=Node3D.new();add_child(hand)
	var face:=Doc.unpack_transform(doc.sketch(id).plane)
	# Select opposite sides first: projection must not connect them by a diagonal.
	var aims: Array=[Vector2(0,-20),Vector2(0,20),Vector2(-20,0),Vector2(20,0)]
	for i in aims.size():
		var p: Vector2=aims[i]
		hand.global_transform=Transform3D(face.basis,(face*Vector3(p.x,p.y,50))*0.001)
		var hit: Dictionary=wb.edge_hit(hand)
		check(not hit.is_empty() and is_equal_approx(hit.points[0].distance_to(hit.points[1]),40),"one of four real edges is selectable without triangle diagonals")
		check(wb.use_edge(hit) and wb.active_sketch==id and wb.tool=="use_edge","trigger copies edge into same sketch and keeps Project active")
		check(doc.sketch(id).points.is_empty() and doc.sketch(id).projected_edges.size()==i+1,"projected lines remain independent of the drawn chain")
		if i<3: check(not doc.sketch(id).closed,"partial projected square remains open")
	var s: Dictionary=doc.sketch(id)
	check(s.closed and s.closed_by_projection and Doc.profile(s).size()==4,"four edges selected in arbitrary order form a closed square region")
	var history: int=doc.undo_steps.size()
	check(not wb.use_edge(wb.edge_hit(hand)) and doc.undo_steps.size()==history,"duplicate projection is ignored without creating undo history")
	check(doc.body(body_id)==original_body,"Project does not change the source object")
	doc.undo();check(doc.sketch(id).projected_edges.size()==3 and not doc.sketch(id).closed,"Undo removes one projected edge and reopens region")
	doc.redo();check(doc.sketch(id).projected_edges.size()==4 and doc.sketch(id).closed,"Redo restores the edge and closed region")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	check(Doc.validate(saved).is_empty(),"projected edges validate after JSON serialization")
	doc.load_document(saved);wb.active_sketch=id
	check(doc.sketch(id).projected_edges.size()==4 and Doc.profile(doc.sketch(id)).size()==4,"save/reload retains all projected geometry and region")
	wb.operation="New";wb.depth_mm=7
	check(await wb.extrude(),"fully projected square can be extruded")
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	for p in doc.export_faces(doc.bodies[-1].faces):
		var v:=Vector3(p[0],p[1],p[2]);low=low.min(v);high=high.max(v)
	check((high-low).distance_to(Vector3(40,40,7))<0.001,"fully projected square exports at 40 by 40 by 7 mm")
	check(Doc.validate(doc.snapshot()).is_empty(),"feature snapshot with projected edges and no drawn points can be saved")
	# Reuse one reference edge to close a profile whose start lies midway along it.
	id=doc.new_sketch(face,body_id);wb.active_sketch=id;wb.operation="New"
	doc.add_projected_edge(id,Vector2(-20,-20),Vector2(20,-20))
	wb.start_use_edge();wb.end_sketch_tool();wb.choose_tool("line")
	check(wb.active_sketch==id and wb.tool=="line","finishing Project then choosing Line keeps the active sketch")
	var snap: Dictionary=doc.infer_point(id,Vector2(0,-20.2),1)
	check(snap.constraint.get("kind")=="projected_point" and is_equal_approx(snap.constraint.t,0.5),"line start snaps to projected midpoint")
	doc.set_profile(id,"line",[[0,-20]],false);doc.add_inference(id,0,snap.constraint)
	var endpoint: Dictionary=doc.infer_point(id,Vector2(20.1,-20),1)
	check(endpoint.constraint.get("kind")=="projected_point" and endpoint.point==Vector2(20,-20),"line points snap to projected endpoints")
	doc.set_profile(id,"line",[[0,-20],[0,10],[20,10],[20,-20]],false)
	doc.add_inference(id,3,endpoint.constraint)
	check(doc.sketch(id).closed_by_projection and Doc.profile(doc.sketch(id)).size()==4,"drawn chain closes through part of a projected edge")
	check(await doc.extrude(id,5,"New"),"mixed drawn/projected profile extrudes")
	check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"projected endpoint constraints and mixed feature persist")
	# Near the exterior of a face, the pointer should still snap to the boundary.
	wb.active_sketch=id;wb.start_use_edge()
	hand.global_transform=Transform3D(face.basis,(face*Vector3(5,-22,50))*0.001)
	var hit: Dictionary=wb.edge_hit(hand)
	check(not hit.is_empty() and is_equal_approx(hit.cursor.y,-20),"Project captures edges even when aiming just outside the solid")
	wb._project_hover_hits[hand.get_instance_id()]=hit
	var cursor: Dictionary=wb.pointer_surface_hit(hand)
	check(cursor.get("project_edge",false) and cursor.point.distance_to((face*Vector3(hit.cursor.x,hit.cursor.y,0))*0.001)<0.00001,"laser terminates at the snapped project edge")
	# The same face can be selected from either controller side and at different zoom.
	id=doc.new_sketch(face,body_id);wb.active_sketch=id;wb.start_use_edge()
	for scale_ in [0.2,1.0,8.43]:
		doc.view_transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_),Vector3.ZERO)
		for side in [-1,1]:
			var target: Vector3=doc.view_transform*(face*Vector3(0,-21,0)*0.001)
			hand.global_position=target+Vector3(side*0.1,0,0.2)*scale_
			hand.look_at(target)
			var selected: Dictionary=wb.edge_hit(hand)
			check(not selected.is_empty() and selected.cursor.distance_to(Vector2(0,-20))<0.001,"either-side laser selects the same edge at view %.2f" % scale_)
	doc.view_transform=Transform3D.IDENTITY
	# Drive the actual trigger path with projected geometry, rather than only the API.
	doc.add_projected_edge(id,Vector2(-20,-20),Vector2(20,-20))
	wb.end_sketch_tool();wb.choose_tool("line")
	XRServer.world_scale=0.5
	for p in [Vector2(-20,-20),Vector2(-20,20),Vector2(20,20),Vector2(20,-20)]:
		hand.global_transform=Transform3D(face.basis,(face*Vector3(p.x,p.y,50))*0.001)
		wb._world_click(hand)
	check(wb.active_sketch==id and doc.sketch(id).closed and doc.sketch(id).closed_by_projection and wb.tool=="select","trigger-drawn three sides close against the projected fourth edge")
	check(Doc.validate(doc.snapshot()).is_empty(),"trigger workflow stores valid projected endpoint references")
	var outline:=Doc.profile(doc.sketch(id));var minimum:=Vector2(INF,INF);var maximum:=Vector2(-INF,-INF)
	for p in outline: minimum=minimum.min(p);maximum=maximum.max(p)
	check((maximum-minimum).distance_to(Vector2(40,40))<0.001 and absf(Geometry2D.triangulate_polygon(outline).size()-6)<0.001,"trigger-drawn profile keeps the intended 40 mm square")
	XRServer.world_scale=1.0
	# A fully projected face must remain available when drawing an adjacent region.
	for reverse in [false,true]:
		# Separate planes keep unrelated earlier sketches out of snap inference.
		face.origin.y+=1000
		id=doc.new_sketch(face);wb.active_sketch=id
		doc.view_transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*10),Vector3.ZERO)
		for edge in [[Vector2(0,-25),Vector2(50,-25)],[Vector2(50,-25),Vector2(50,25)],[Vector2(50,25),Vector2(0,25)],[Vector2(0,25),Vector2(0,-25)]]:
			doc.add_projected_edge(id,edge[0],edge[1])
		wb.start_use_edge();wb.end_sketch_tool();wb.choose_tool("line")
		check(wb.active_sketch==id,"Line after a fully projected face keeps the reference edges in the active sketch")
		var chain: Array=[Vector2(0,25),Vector2(-49.72,25),Vector2(-49.72,-25),Vector2(0,-25)]
		if reverse: chain.reverse()
		for p in chain:
			hand.global_transform=Transform3D(face.basis,doc.view_transform*((face*Vector3(p.x,p.y,50))*0.001))
			wb._world_click(hand)
		check(doc.sketch(id).closed_by_projection and Doc.profile(doc.sketch(id)).size()==4,"adjacent three-sided chain closes against a fully projected face")
		check(await doc.dimension(id,"length:2",50),"adjacent profile retains its 50 mm height")
		var references: Array=doc.sketch(id).projected_edges.duplicate(true)
		check(await doc.dimension(id,"length:3",25),"49.72 mm width can shrink to 25 mm with its ending point on a fixed projection")
		var resized: Dictionary=doc.sketch(id)
		check(absf(resized.points[1][0]+25)<0.002 and absf(resized.points[2][0]+25)<0.002 and absf(resized.points[0][0])<0.002 and absf(resized.points[3][0])<0.002 and resized.projected_edges==references,"width edit moves the blue side and preserves both projected anchors")
		check(await doc.extrude(id,5,"New"),"resized adjacent profile extrudes")
		check(await doc.dimension(id,"length:3",30),"width can be edited again after extrusion")
		check(absf(Doc.volume(doc.bodies[-1].faces)-30*50*5)<0.1,"extrusion rebuild uses the edited width and fixed height")
		check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"adjacent projected profile and dimensions survive serialization")
	# One selection of a cylinder rim projects the entire circular boundary.
	doc.view_transform=Transform3D.IDENTITY
	face.origin.y+=1000
	var circle_source: int=doc.new_sketch(face)
	doc.set_profile(circle_source,"circle",[[0,0],[25,0]],true)
	check(await doc.extrude(circle_source,5,"New"),"create circular extrusion for Project")
	var cylinder_id: int=doc.bodies[-1].id
	var cylinder: Dictionary=doc.body(cylinder_id).duplicate(true)
	face.origin+=face.basis.z*5
	id=doc.new_sketch(face);wb.active_sketch=id;wb.start_use_edge()
	hand.global_transform=Transform3D(face.basis,(face*Vector3(25,0,50))*0.001)
	var rim: Dictionary=wb.edge_hit(hand)
	check(not rim.is_empty() and rim.get("edges",[]).size()>=96,"Project from an unattached sketch also selects the whole circle")
	doc.sketch(id).body_id=cylinder_id
	rim=wb.edge_hit(hand)
	check(not rim.is_empty() and rim.get("edges",[]).size()>=96,"aiming at one circle chord selects the entire rim")
	history=doc.undo_steps.size()
	check(wb.use_edge(rim) and doc.sketch(id).closed and Doc.profile(doc.sketch(id)).size()>=96,"one trigger projects a complete closed circle")
	check(doc.undo_steps.size()==mini(history+1,30) and doc.body(cylinder_id)==cylinder,"whole-circle projection is one undo step and preserves its source")
	check(not wb.use_edge(rim) and doc.undo_steps.size()==mini(history+1,30),"reselecting a projected circle adds no duplicates or history")
	check(doc.sketch(id).get("projected_centers",[]).size()==1,"projected rim includes one center reference")
	var center: Array=doc.sketch(id).projected_centers[0]
	check(Vector2(center[0],center[1]).length()<0.001,"projected circular center is geometrically accurate")
	doc.undo();check(doc.sketch(id).get("projected_edges",[]).is_empty() and doc.sketch(id).get("projected_centers",[]).is_empty(),"Undo removes the whole projected circle and center")
	doc.redo();check(doc.sketch(id).closed and Doc.profile(doc.sketch(id)).size()>=96,"Redo restores the whole closed circle")
	check(Doc.validate(JSON.parse_string(JSON.stringify(doc.snapshot()))).is_empty(),"whole-circle projection persists")
	check(await doc.extrude(id,3,"New"),"projected circle is immediately extrudable")
	check(absf(Doc.volume(doc.bodies[-1].faces)-PI*25*25*3)<10,"projected circular extrusion preserves its diameter")
	var bad: Dictionary=doc.snapshot();bad.sketches[-1].projected_edges=[[[0,0],[0,0]]]
	check(not Doc.validate(bad).is_empty(),"degenerate projected edges are rejected on load")
	print("PROJECT RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
