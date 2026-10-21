extends "res://main.gd"
const Doc=preload("res://cad/CADDocument.gd")
var checks:=0
var failures:=0
var wb: Node3D
var doc: Node3D
var hand: Node3D
func check(ok: bool,text: String):
	checks+=1
	if not ok: failures+=1; push_error("SKETCH FAIL: "+text)
	else: print("SKETCH PASS: "+text)
func click(point: Vector2):
	var plane: Transform3D=Doc.unpack_transform(doc.sketch(wb.active_sketch).plane)
	plane.origin*=0.001
	var world: Transform3D=doc.view_transform*plane
	hand.global_transform=Transform3D(world.basis.orthonormalized(),world*Vector3(point.x*0.001,point.y*0.001,0.3))
	wb._world_click(hand)
func _ready():
	super._ready()
	await get_tree().process_frame
	wb=get_node("AdvancedCAD")
	doc=wb.document
	wb.enabled=true
	wb.open_panel()
	hand=Node3D.new(); add_child(hand)
	wb.begin_sketch()
	hand.global_position=Vector3(0,1.15,0)
	check(wb.pick_base_plane(hand)=="Front","aim at visible Front plane")
	wb._world_click(hand)
	check(wb.tool=="line" and wb.active_sketch>0,"plane click starts line sketch")
	var id: int=wb.active_sketch
	click(Vector2.ZERO)
	check(doc.sketch(id).points.size()==1 and doc.sketch(id).constraints[0].kind=="origin","first trigger anchors at origin")
	var before: Dictionary=doc.snapshot()
	wb.sketch_visual.update_preview(doc.sketch(id),Vector2(60,0),true)
	check(wb.sketch_visual.preview.mesh.get_surface_count()==1 and wb.sketch_visual.live_label.text=="60.00 mm" and doc.snapshot()==before,"live line and length preview never commits geometry")
	click(Vector2(60,0))
	click(Vector2(60,50))
	check(doc.sketch(id).points.size()==3 and wb.tool=="line","each click continues from previous endpoint")
	check(doc.sketch(id).constraints.any(func(c):return c.kind=="horizontal") and doc.sketch(id).constraints.any(func(c):return c.kind=="vertical"),"horizontal and vertical snap constraints persist")
	var state: Dictionary=doc.constraint_states()[id]
	check(not state.fully_defined and not state.segments[0],"origin plus axis alignment alone leaves lines blue")
	click(Vector2.ZERO)
	check(doc.sketch(id).closed and doc.sketch(id).points.size()==3 and wb.tool=="select","snapping to start closes triangle and exits line tool")
	check(await doc.dimension(id,"length:1",60),"first segment receives persistent 60 mm dimension")
	state=doc.constraint_states()[id]
	check(state.segments[0] and not state.segments[1],"only the fully constrained first edge turns black")
	check(await doc.dimension(id,"length:0",80.131),"closing diagonal can drive an already aligned triangle")
	var points: Array=doc.sketch(id).points
	var height: float=sqrt(80.131*80.131-60*60)
	check(absf(points[2][0]-60)<0.002 and absf(points[2][1]-height)<0.002 and Vector2(points[0][0],points[0][1]).length()<0.002,"diagonal dimension moves vertical endpoint while keeping origin and base")
	check(doc.constraint_states()[id].fully_defined,"fully constrained triangle turns black")
	var good: Dictionary=doc.snapshot()
	check(not await doc.dimension(id,"length:2",10) and doc.snapshot()==good,"conflicting dimensions reject without changing valid sketch")
	check(Doc.validate(doc.snapshot()).is_empty(),"driving dimensions validate for save")
	doc.load_document(JSON.parse_string(JSON.stringify(good)))
	check(doc.constraint_states()[id].fully_defined,"constraint colors survive JSON save/restore")
	wb.active_sketch=id
	check(await wb.extrude(),"dimensioned closed chain extrudes")
	check(absf(Doc.volume(doc.bodies[0].faces)-60*height*5)<2,"export solid retains the exact dimensioned triangle")
	wb.new_base_sketch("Front"); id=wb.active_sketch
	click(Vector2(10,20)); click(Vector2(40,35))
	before=doc.snapshot()
	wb.end_sketch_tool()
	check(wb.tool=="select" and doc.snapshot()==before and not doc.sketch(id).closed,"B ends an open chain without closing or adding preview endpoint")
	wb.choose_tool("line")
	check(wb.active_sketch!=id and doc.sketch(wb.active_sketch).points.is_empty(),"line after B starts a separate chain on same plane")
	wb.choose_tool("circle"); id=wb.active_sketch
	click(Vector2.ZERO); click(Vector2(25,0))
	check(not doc.constraint_states()[id].fully_defined,"undimensioned origin circle stays blue")
	check(await doc.dimension(id,"diameter",83.892) and doc.constraint_states()[id].fully_defined,"diameter defines an origin-centered circle")
	check(absf(Vector2(doc.sketch(id).points[1][0],doc.sketch(id).points[1][1]).length()*2-83.892)<0.002,"diameter input is not confused with radius")
	wb.new_base_sketch("Top"); wb.choose_tool("rectangle"); id=wb.active_sketch
	click(Vector2.ZERO); click(Vector2(20,15))
	check(await doc.dimension(id,"width",40) and not doc.constraint_states()[id].fully_defined,"one rectangle dimension leaves the other size blue")
	check(await doc.dimension(id,"height",30) and doc.constraint_states()[id].fully_defined,"width and height define an anchored center rectangle")
	var plane: Transform3D=Doc.unpack_transform(doc.sketch(id).plane)
	check(plane.basis.z.is_equal_approx(Vector3.UP),"Top sketch remains parallel to ground")
	wb.tool="select"; wb._redraw()
	check(wb.sketch_visual.dimensions.size()==2,"both rectangle dimensions appear on sketch")
	var dimension: Dictionary=wb.sketch_visual.dimensions[0]
	plane.origin*=0.001
	hand.global_transform=Transform3D(plane.basis,plane*Vector3(dimension.point.x*0.001,dimension.point.y*0.001,0.2))
	check(not wb.sketch_visual.hit_dimension(hand).is_empty(),"dimension label can be targeted directly by controller ray")
	wb._world_click(hand)
	check(wb.ui.keypad.visible and wb.ui.entry_field=="width","selecting dimension opens laser keypad")
	wb.end_sketch_tool()
	check(not wb.ui.keypad.visible,"B cancels numeric entry")
	print("SKETCH WORKFLOW RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
