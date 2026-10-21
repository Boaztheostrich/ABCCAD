extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
const Angle=preload("res://cad/CADAngleDimension.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok: failures+=1;push_error("ANGLE FAIL: "+text_)
	else: print("ANGLE PASS: "+text_)
func _ready():
	super._ready()
	await get_tree().process_frame
	var wb=get_node("AdvancedCAD");var doc=wb.document
	wb.enabled=true;wb.open_panel();wb.set_process(false);wb.new_base_sketch("Front")
	var id: int=wb.active_sketch
	doc.set_profile(id,"line",[[0,0],[0,70],[50,20]],false)
	var s: Dictionary=doc.sketch(id)
	var c:=Angle.pair(s,0,1)
	check(not c.is_empty() and absf(c.value-45)<0.001,"connected segments default to inside 45 degrees")
	check(Angle.pair(s,0,0).is_empty(),"same line cannot form an angle")
	var inside:=Angle.placed(s,c,Vector2(12,40))
	var outside:=Angle.placed(s,c,Vector2(20,100))
	var other:=Angle.placed(s,c,Vector2(-25,50))
	check(absf(inside.value-45)<0.001,"inside placement measures acute angle")
	check(absf(outside.value-135)<0.001 and absf(other.value-135)<0.001,"either outside placement measures supplementary angle")
	check(absf(Angle.geometry(s,outside).label.distance_to(Vector2(0,70))-outside.radius)<0.001,"arc radius follows placement")
	wb.start_angle();check(wb.tool=="angle" and doc.sketches.size()==1,"angle tool retains current sketch")
	wb.angle_click(Vector2(0,30));wb.angle_click(Vector2(25,45))
	check(wb.angle_lines.size()==2 and not wb.angle_pending.is_empty(),"two trigger selections pick connected lines")
	var before: Dictionary=doc.snapshot()
	wb.end_sketch_tool();check(wb.tool=="select" and doc.snapshot()==before,"B cancels without modifying geometry or history")
	wb.start_angle();wb.angle_click(Vector2(0,30));wb.angle_click(Vector2(25,45));wb.angle_click(Vector2(12,40))
	check(wb.tool=="select" and s.constraints.size()==1 and s.constraints[0].field=="angle","third trigger saves the placed angle")
	check(wb.sketch_visual.dimensions.any(func(d):return d.field=="angle:0"),"degree label has an editable hit target")
	wb.ui.edit_number("angle:0");check(wb.ui.entry.text.contains("45.000°") and not wb.ui.entry.text.contains("mm"),"angle keypad uses degrees")
	wb.ui.keypad.visible=false
	doc.add_inference(id,0,{"kind":"origin"});doc.add_inference(id,1,{"kind":"vertical"})
	check(await doc.dimension(id,"length:1",70),"dimension first segment before angle edit")
	check(await doc.dimension(id,"length:2",sqrt(5000)),"dimension second segment before angle edit")
	check(await doc.dimension(id,"angle:0",60),"angle drives geometry to 60 degrees")
	s=doc.sketch(id)
	check(absf(rad_to_deg(absf(Angle.geometry(s,s.constraints[0]).sweep))-60)<0.01,"geometry matches requested angle")
	check(Angle.point(s,0).length()<0.001 and absf(Angle.point(s,1).x)<0.001 and absf(Angle.point(s,1).y-70)<0.001,"angle preserves origin vertical and fixed length")
	check(absf(Angle.point(s,2).distance_to(Angle.point(s,1))-sqrt(5000))<0.002,"angle retains second segment length")
	for degrees in [15.0,120.0,45.0,60.0]:
		check(await doc.dimension(id,"angle:0",degrees),"driving angle converges at %.0f degrees" % degrees)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(doc.snapshot()))
	check(Doc.validate(saved).is_empty(),"angle and arc placement pass JSON save validation")
	doc.undo();s=doc.sketch(id);check(absf(s.constraints[0].value-45)<0.001,"undo restores angle and geometry")
	doc.redo();s=doc.sketch(id);check(absf(s.constraints[0].value-60)<0.001,"redo restores edited angle")
	var old: Dictionary=doc.snapshot();var undo_count: int=doc.undo_steps.size()
	check(not await doc.dimension(id,"angle:0",180) and doc.snapshot()==old and doc.undo_steps.size()==undo_count,"degenerate 180 degree edit rejects without history changes")
	doc.load_document(saved);s=doc.sketch(id)
	check(absf(s.constraints[0].value-60)<0.001 and absf(s.constraints[0].radius-inside.radius)<0.001,"reload restores degree value and placement")
	# Supplementary dimensions drive the physical interior angle correctly.
	c=Angle.placed(s,Angle.pair(s,0,1),Vector2(20,100))
	var ci: int=doc.add_angle(id,c)
	check(ci==0 and s.constraints.filter(func(x):return x.get("field")=="angle").size()==1,"replacing placement does not duplicate angle constraint")
	check(await doc.dimension(id,"angle:0",140),"supplementary angle can drive geometry")
	var natural:=Angle.pair(doc.sketch(id),0,1)
	check(absf(natural.value-40)<0.01,"140 degree outside dimension produces 40 degree inside angle")
	# Conflicting fully fixed segments must roll back rather than break constraints.
	doc.clear_constraints(id);s=doc.sketch(id)
	doc.set_profile(id,"line",[[0,0],[0,70],[50,70]],false)
	doc.add_inference(id,0,{"kind":"origin"});doc.add_inference(id,1,{"kind":"vertical"});doc.add_inference(id,2,{"kind":"horizontal"})
	ci=doc.add_angle(id,Angle.pair(s,0,1));old=doc.snapshot();undo_count=doc.undo_steps.size()
	check(not await doc.dimension(id,"angle:%d" % ci,45),"conflicting horizontal vertical angle is rejected")
	check(doc.snapshot()==old and doc.undo_steps.size()==undo_count,"conflict restores geometry constraints and history")
	var bad:=old.duplicate(true);bad.sketches[0].constraints[ci].other=999
	check(not Doc.validate(bad).is_empty(),"invalid saved angle reference is rejected")
	# Closing segment and unconnected lines.
	doc.clear_constraints(id);doc.set_profile(id,"line",[[0,0],[60,0],[60,60],[0,60]],true);s=doc.sketch(id)
	check(not Angle.pair(s,3,0).is_empty(),"closing segment can dimension across first vertex")
	check(Angle.pair(s,0,2).is_empty(),"unconnected lines are rejected")
	# A solid driven by an angular dimension rebuilds, remains valid and exports.
	doc.clear_constraints(id);doc.set_profile(id,"line",[[0,0],[60,0],[30,50]],true);s=doc.sketch(id)
	ci=doc.add_angle(id,Angle.pair(s,0,1))
	check(await doc.extrude(id,10,"New"),"angular sketch extrudes")
	var volume: float=Doc.volume(doc.bodies[-1].faces)
	check(await doc.dimension(id,"angle:%d" % ci,75),"editing extruded angle rebuilds solid")
	check(absf(Doc.volume(doc.bodies[-1].faces)-volume)>1 and Doc.validate(doc.snapshot()).is_empty(),"rebuilt solid changes shape and retains valid history")
	check(not doc.print_export_faces(doc.bodies[-1].id).is_empty(),"angular solid remains exportable")
	print("ANGLE RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
