extends Node3D
const Doc=preload("res://cad/CADDocument.gd")
const Solid=preload("res://cad/CADSolidValidation.gd")
const Export=preload("res://STLExport.gd")
var checks:=0
var failures:=0
var last_status:=""
var combined_status:=""
var combined_ok:=true
func check(ok: bool,label_: String):
	checks+=1
	if not ok:failures+=1;push_error("PRINTABLE FAIL: "+label_)
	else:print("PRINTABLE PASS: "+label_)
func cube(offset: Vector3=Vector3.ZERO) -> Array:
	var faces:=Doc.faces_from_mesh(BoxMesh.new())
	for p in faces:
		p[0]+=offset.x;p[1]+=offset.y;p[2]+=offset.z
	return faces
func unchanged(doc,before: Dictionary,undo: Array,redo: Array) -> bool:
	return doc.snapshot()==before and doc.undo_steps==undo and doc.redo_steps==redo and not doc.busy
func _ready():
	# Fixtures stay local even when these checks run in a personally configured project.
	get_node("/root/DriveUpload").endpoint=""
	var valid:=cube()
	check(Solid.error(valid).is_empty(),"closed cube is printable")
	var degenerate: Array=valid+[valid[0],valid[0],valid[1]]
	check(Solid.clean_faces(degenerate)==valid,"exact zero-area CSG debris is removed without changing the solid")
	check(Solid.error(Solid.clean_faces(degenerate)).is_empty(),"cleanup does not reject an otherwise closed solid")
	check(not Solid.error(valid.slice(3)).is_empty(),"open shell is rejected")
	var flipped:=valid.duplicate(true);var swap=flipped[0];flipped[0]=flipped[1];flipped[1]=swap
	check(not Solid.error(flipped).is_empty(),"inconsistent triangle winding is rejected")
	check(Solid.error(valid+cube(Vector3(2,2,2))).is_empty(),"disconnected closed shells remain supported")
	check(Solid.error(valid+cube(Vector3(1,1,0)))==Solid.CONTACT_MESSAGE,"edge-only connection is rejected")
	check(Solid.error(valid+cube(Vector3(1,1,1)))==Solid.CONTACT_MESSAGE,"vertex-only connection is rejected despite two uses per edge")
	# Split one triangle at an edge midpoint without splitting its neighbor.
	var junction:=valid.slice(3)
	var middle: Array=[]
	for axis in 3:middle.append((valid[0][axis]+valid[1][axis])/2.0)
	junction.append_array([valid[0],middle,valid[2],middle,valid[1],valid[2]])
	check(Solid.error(junction).is_empty(),"valid CSG T junction is not mistaken for an open shell")
	# Exact exported artifact from the native simulator, not an invented mesh.
	var old_mesh: Mesh=STLIO.Importer.LoadFromBytes(FileAccess.get_file_as_bytes("res://tests/fixtures/stl-regression/bowtie-nonmanifold.stl"))
	check(Solid.error(Doc.faces_from_mesh(old_mesh))==Solid.CONTACT_MESSAGE,"actual failing bow-tie STL reproduces the four-face edge")
	var folder:="/private/tmp/abccad-printable-"+str(OS.get_process_id())
	var failed:=Export.save(old_mesh,"invalid_",[folder])
	check(failed.error==ERR_INVALID_DATA and failed.path=="" and not DirAccess.dir_exists_absolute(folder),"legacy invalid geometry writes no STL or directory")
	check("edge or point" in Export.message(failed,true) and not "freeing storage" in Export.message(failed,true),"blocked export explains geometry and a correction")
	var combined:=Export.save(Doc.mesh_from_faces(valid+cube(Vector3(1,1,0))),"separate_",[folder],[Doc.mesh_from_faces(valid),Doc.mesh_from_faces(cube(Vector3(1,1,0)))])
	check(combined.error==OK,"separate valid assembly parts may touch without being welded into one part")
	var bad_assembly:=Export.save(Doc.mesh_from_faces(valid+Doc.faces_from_mesh(old_mesh)),"invalid_",[folder],[Doc.mesh_from_faces(valid),old_mesh])
	check(bad_assembly.error==ERR_INVALID_DATA and "Part 2" in Export.message(bad_assembly,true),"assembly export identifies the invalid CAD part")
	var doc:=Doc.new();add_child(doc)
	doc.status.connect(func(text):last_status=text)
	var id: int=doc.new_sketch(Transform3D.IDENTITY)
	doc.set_profile(id,"line",[[0,0],[60,60],[0,60],[60,0]],true)
	var regions: Array=doc.sketch_regions(id)
	check(regions.size()==2,"native bow-tie profile still exposes two selectable areas")
	var before: Dictionary=doc.snapshot();var undo: Array=doc.undo_steps.duplicate(true);var redo: Array=doc.redo_steps.duplicate(true)
	check(not await doc.extrude_regions(id,regions.map(func(r):return r.id),20,"New"),"bow-tie areas cannot create one edge-connected part")
	check(unchanged(doc,before,undo,redo) and "edge or point" in last_status,"rejected operation preserves document, history and editing state")
	check(await doc.extrude_regions(id,[regions[0].id],20,"New"),"one bow-tie lobe still extrudes as a valid part")
	check(await doc.extrude_regions(id,[regions[1].id],20,"New"),"other lobe can be created as a separate part")
	check(doc.bodies.size()==2,"separate-part workaround retains both printable solids")
	# Add an edge-contacting prism to an otherwise valid cube.
	doc.clear_all();id=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(id,"rectangle",[[0,0],[10,10]],true)
	check(await doc.extrude(id,10,"New"),"create valid target for Add")
	var target: int=doc.bodies[0].id
	id=doc.new_sketch(Transform3D.IDENTITY,target);doc.set_profile(id,"rectangle",[[20,20],[30,30]],true)
	before=doc.snapshot();undo=doc.undo_steps.duplicate(true);redo=doc.redo_steps.duplicate(true)
	check(not await doc.extrude(id,10,"Add",target),"Add rejects a zero-thickness edge connection")
	check(unchanged(doc,before,undo,redo),"failed Add retains the last good target and history")
	# The same guard must run during history regeneration after dimensions change.
	doc.clear_all();id=doc.new_sketch(Transform3D.IDENTITY);doc.set_profile(id,"rectangle",[[0,0],[10,10]],true)
	var second: int=doc.new_entity(id,"rectangle");doc.set_profile(second,"rectangle",[[30,20],[40,30]],true)
	regions=doc.sketch_regions(id)
	check(await doc.extrude_regions(id,regions.map(func(r):return r.id),10,"New"),"separated rectangular islands create one movable part")
	before=doc.snapshot();undo=doc.undo_steps.duplicate(true);redo=doc.redo_steps.duplicate(true)
	check(not await doc.dimension(second,"width",40),"dimension edit that creates an edge contact is rejected")
	check(unchanged(doc,before,undo,redo),"invalid dimension rebuild restores last good geometry and history")
	# Old saves remain loadable; both real export paths use the guarded save API.
	var legacy: Dictionary=doc.snapshot()
	legacy.bodies[0].faces=Doc.faces_from_mesh(old_mesh)
	doc.load_document(legacy)
	check(doc.snapshot()==legacy,"older invalid design remains loadable for repair")
	var exporter:=preload("res://VoxelExporter.gd").new();add_child(exporter)
	SignalBus.export_finished.connect(func(ok,text):combined_ok=ok;combined_status=text)
	exporter._export_voxels_to_stl()
	check(not combined_ok and "STL export blocked" in combined_status and "edge or point" in combined_status,"main menu assembly export blocks the actual legacy bow-tie")
	check(doc.snapshot()==legacy,"blocked legacy export never rewrites or discards the saved design")
	exporter.queue_free()
	doc.queue_free()
	print("PRINTABLE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
