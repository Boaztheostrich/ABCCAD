extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("DELETE FAIL: "+text_)
	else: print("DELETE PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD")
	var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.new_base_sketch("Front")
	var first: int=wb.active_sketch
	doc.set_profile(first,"rectangle",[[0,0],[20,15]])
	check(await doc.extrude(first,10,"New"),"create dependent part")
	var independent: int=doc.new_sketch(doc.base_plane("Top"))
	doc.set_profile(independent,"circle",[[0,0],[5,0]])
	var before: Dictionary=doc.snapshot()
	wb.ui.request_delete_sketch(first)
	check(wb.ui.confirmation.visible and doc.snapshot()==before,"trash opens prompt without deleting anything")
	check("1 dependent part" in wb.ui.confirmation_message.text,"prompt explicitly reports dependent part deletion")
	wb.ui.cancel_confirmation()
	check(doc.snapshot()==before and not wb.ui.confirmation.visible,"cancel keeps entire model")
	wb.ui.request_delete_sketch(first);wb.ui._apply_confirmation()
	check(doc.bodies.is_empty() and doc.sketch(first).is_empty() and not doc.sketch(independent).is_empty(),"confirm removes dependent part and retains independent sketch")
	check(Doc.validate(doc.snapshot()).is_empty(),"deleted state validates")
	doc.undo();check(doc.snapshot()==before,"undo restores complete sketch and part")
	doc.redo();check(doc.sketch(first).is_empty() and doc.bodies.is_empty(),"redo repeats only confirmed deletion")
	doc.undo()
	var follower: int=doc.new_sketch(doc.base_plane("Front"))
	doc.set_profile(follower,"line",[[0,0],[10,5]],false)
	doc.add_inference(follower,0,{"kind":"coincident","target":first,"index":0})
	var plan: Dictionary=doc.deletion_plan(first)
	check(follower in plan.sketches,"dependent coincident sketch is included in deletion plan")
	var ref: Dictionary={"plane_mm":Doc.pack_transform(doc.base_plane("Top")),"stage_pose":Doc.pack_transform(Transform3D.IDENTITY),"locked":true,"lock_rotation":false}
	doc.set_reference_plane(ref)
	before=doc.snapshot()
	wb.ui.request_clear_all()
	check(wb.ui.confirmation.visible and doc.snapshot()==before,"Clear all also requires explicit confirmation")
	wb.ui.cancel_confirmation();check(doc.snapshot()==before,"cancel Clear all preserves every item")
	wb.ui.request_clear_all();wb.ui._apply_confirmation()
	check(doc.sketches.is_empty() and doc.bodies.is_empty() and doc.reference_plane==ref,"Clear all resets CAD geometry and retains table reference")
	doc.undo();check(doc.snapshot()==before,"Undo restores entire cleared CAD workspace")
	doc.busy=true
	check(not doc.clear_all() and not doc.delete_sketch(first) and doc.snapshot()==before,"held/busy model cannot be deleted")
	doc.busy=false
	wb.ui.request_clear_all();wb.close_panel()
	check(not wb.ui.confirmation.visible,"closing menu cancels stale destructive prompt")
	# Redo a user deletion of a converted body must not restore its old block.
	doc.bodies[0].converted_source={"shape":"cube","transform":Doc.pack_transform(Transform3D(Basis.IDENTITY,Vector3(0,1,-1))),"color":"ffffffff","grid":[0,10,-10],"cells":[[0,10,-10]]}
	doc.clear_all();doc.undo();doc.redo()
	check(VoxelDatabase.get_voxel_count()==0 and doc.bodies.is_empty(),"clear redo never resurrects a converted legacy block")
	var restored: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	check(Doc.validate(restored).is_empty() and restored.has("deleted_conversions"),"conversion deletion intent survives saved JSON")
	print("CAD DELETE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
