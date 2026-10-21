extends Node3D
const Doc=preload("res://cad/CADDocument.gd")
const Regions=preload("res://cad/CADSketchRegions.gd")
var checks:=0
var failures:=0
func check(ok: bool,text_: String):
	checks+=1
	if not ok:failures+=1;push_error("ARRANGEMENT FAIL: "+text_)
	else:print("ARRANGEMENT PASS: "+text_)
func add(doc,root: int,kind: String,points: Array,closed: bool=true) -> int:
	var id: int=doc.new_sketch(Transform3D.IDENTITY) if root<0 else doc.new_entity(root,kind)
	doc.set_profile(id,kind,points,closed);return id
func found(regions: Array,at: Vector2) -> Dictionary:
	for r in regions:
		if Regions.contains(r,at):return r
	return {}
func total_area(regions: Array) -> float:
	var total:=0.0
	for r in regions:
		var v:=Regions.triangles(r)
		for i in range(0,v.size(),3):total+=absf((v[i+1]-v[i]).cross(v[i+2]-v[i]))/2
	return total
func _ready():
	var doc:=Doc.new();add_child(doc)
	var root:=add(doc,-1,"rectangle",[[0,0],[30,20]])
	add(doc,root,"circle",[[0,0],[8,0]])
	var regions:=doc.sketch_regions(root)
	check(regions.size()==2,"rectangle with an interior circle has inside and outside areas")
	check(absf(total_area(regions)-2400)<0.02,"all region fills exactly partition the rectangle")
	var ring:=found(regions,Vector2(20,0))
	check(ring.holes.size()==1 and not Regions.contains(ring,Vector2.ZERO),"surrounding region keeps the inner hole")
	add(doc,root,"line",[[-30,0],[30,0]],false)
	regions=doc.sketch_regions(root)
	check(regions.size()==4,"line splits rectangle and circle into four areas")
	check(absf(total_area(regions)-2400)<0.02,"split fills conserve area without overlap")
	doc.clear_all();root=add(doc,-1,"circle",[[0,0],[10,0]]);add(doc,root,"circle",[[20,0],[30,0]])
	regions=doc.sketch_regions(root)
	check(regions.size()==2,"two externally tangent circles remain separate areas")
	check(absf(total_area(regions)-200*PI)<0.5,"tangent-circle fill conserves both discs")
	doc.clear_all();root=add(doc,-1,"circle",[[0,0],[20,0]]);add(doc,root,"circle",[[12,0],[20,0]])
	regions=doc.sketch_regions(root)
	check(regions.size()==2,"internally tangent circles produce disc and surrounding area")
	check(absf(total_area(regions)-400*PI)<1,"internal tangent fills conserve outer disc")
	var surrounding:=found(regions,Vector2(-10,0))
	check(not surrounding.is_empty() and not Regions.contains(surrounding,Vector2(12,0)),"touching hole remains excluded from surrounding fill")
	check(await doc.extrude_regions(root,[surrounding.id],5,"New"),"region with touching circular hole extrudes")
	check(absf(Doc.volume(doc.bodies[0].faces)-PI*(400-64)*5)<8,"touching-hole extrusion has expected volume")
	doc.clear_all();root=add(doc,-1,"rectangle",[[0,0],[20,20]])
	add(doc,root,"line",[[0,-20],[0,0]],false)
	regions=doc.sketch_regions(root)
	check(regions.size()==1 and absf(total_area(regions)-1600)<0.001,"dangling internal line does not create a false region")
	add(doc,root,"line",[[0,0],[0,20]],false)
	regions=doc.sketch_regions(root)
	check(regions.size()==2,"two stopped segments split a region once both boundaries connect")
	add(doc,root,"line",[[-20,0],[20,0]],false)
	regions=doc.sketch_regions(root)
	check(regions.size()==4,"crossing line chains create four independently selectable regions")
	check(absf(total_area(regions)-1600)<0.001,"crossing-line cells exactly cover their source area")
	doc.clear_all();root=add(doc,-1,"circle",[[0,0],[80,0]])
	var old_id: String=doc.sketch_regions(root)[0].id
	check(await doc.dimension(root,"radius",200),"circle resize crosses adaptive tessellation threshold")
	check(doc.sketch_regions(root)[0].id==old_id,"whole-circle area identity survives tessellation changes")
	doc.clear_all();root=add(doc,-1,"rectangle",[[0,0],[15,10]]);add(doc,root,"rectangle",[[15,0],[30,10]])
	regions=doc.sketch_regions(root)
	check(regions.size()==3,"overlapping rectangles produce three selectable cells")
	check(absf(total_area(regions)-900)<0.001,"overlapping rectangles count intersection once")
	check(await doc.extrude_regions(root,regions.map(func(r):return r.id),4,"New"),"adjacent cells union in one extrusion")
	check(absf(Doc.volume(doc.bodies[0].faces)-3600)<0.05,"adjacent extrusion contains no duplicate intersection volume")
	print("ARRANGEMENT RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
