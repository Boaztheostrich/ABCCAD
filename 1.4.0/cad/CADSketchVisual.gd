extends Node3D
const Doc=preload("res://cad/CADDocument.gd")
const BLUE=Color("147bd1")
const BLACK=Color("101923")
var dimensions: Array=[]
var preview: MeshInstance3D
var live_label: Label3D
var fill: MeshInstance3D
var guides: MeshInstance3D
var workbench: Node3D
var _layout_pose:=Transform3D.IDENTITY
var _layout_view:=Transform3D.IDENTITY

func material(color: Color) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color=color
	m.cull_mode=BaseMaterial3D.CULL_DISABLED
	m.no_depth_test=true
	m.render_priority=3
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	if color.a<1.0: m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func label(text_: String,at: Vector3,color: Color,size_: float=0.00018) -> Label3D:
	var node:=Label3D.new()
	node.text=text_
	node.font_size=40
	node.pixel_size=size_
	node.modulate=color
	# Billboard glyphs can cross behind the sketch plane at oblique angles.
	# Render annotations after translucent plane/fill geometry, keeping their
	# actual blue/black ink rather than washing it out under that surface.
	node.shaded=false
	node.no_depth_test=true
	node.render_priority=8
	node.outline_render_priority=7
	node.outline_size=3
	node.outline_modulate=Color(0.95,0.97,0.99,1)
	node.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	node.position=at
	add_child(node)
	return node

func lines(vertices: PackedVector3Array,color: Color,parent: Node=null) -> MeshInstance3D:
	if parent==null: parent=self
	var node:=MeshInstance3D.new()
	if not vertices.is_empty():
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_LINES)
		for vertex in vertices: surface.add_vertex(vertex)
		node.mesh=surface.commit()
	node.material_override=material(color)
	parent.add_child(node)
	return node

func redraw():
	for child in get_children(): remove_child(child); child.queue_free()
	dimensions.clear()
	var states: Dictionary=workbench.document.constraint_states()
	var blue_vertices:=PackedVector3Array()
	var black_vertices:=PackedVector3Array()
	for s in workbench.document.sketches:
		if not workbench.sketch_visibility.get(int(s.id),true): continue
		var plane: Transform3D=Doc.unpack_transform(s.plane)
		var region_profile: PackedVector2Array=Doc.profile(s)
		var profile: PackedVector2Array=region_profile
		if s.get("closed_by_projection",false):
			profile=PackedVector2Array()
			for p in s.points: profile.append(Vector2(p[0],p[1]))
		for edge in s.get("projected_edges",[]):
			for p in edge: black_vertices.append(plane*Vector3(p[0],p[1],0.4)*0.001)
		var state: Dictionary=states.get(int(s.id),{})
		var count: int=profile.size() if s.closed and not s.get("closed_by_projection",false) else profile.size()-1
		for i in maxi(0,count):
			var defined: bool=state.get("fully_defined",false)
			if s.kind=="line" and i<state.get("segments",[]).size(): defined=state.segments[i]
			for endpoint in [profile[i],profile[(i+1)%profile.size()]]:
				var vertex: Vector3=plane*Vector3(endpoint.x,endpoint.y,0.3)*0.001
				if defined: black_vertices.append(vertex)
				else: blue_vertices.append(vertex)
		for center in s.get("projected_centers",[]):
			var vertices:=PackedVector3Array()
			for offset in [Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(0,2)]:
				vertices.append(plane*Vector3(center[0]+offset.x,center[1]+offset.y,0.6)*0.001)
			lines(vertices,BLACK)
		if workbench.document.sketch_root(int(s.id))!=workbench.document.sketch_root(workbench.active_sketch): continue
		for i in s.points.size():
			var p:=Vector2(s.points[i][0],s.points[i][1])
			var ring:=PackedVector3Array()
			for step in 16:
				for angle in [TAU*step/16,TAU*(step+1)/16]:
					var v: Vector2=p+Vector2(cos(angle),sin(angle))*0.7
					ring.append(plane*Vector3(v.x,v.y,0.5)*0.001)
			lines(ring,BLACK if i<state.get("points",[]).size() and state.points[i] else BLUE)
		if s.kind=="line":
			for i in maxi(0,count):
				var a: Vector2=profile[i]
				var b: Vector2=profile[(i+1)%profile.size()]
				var normal:=Vector2(-(b-a).y,(b-a).x).normalized()
				if s.closed:
					var area:=0.0
					for j in profile.size(): area+=profile[j].cross(profile[(j+1)%profile.size()])
					if area>0: normal=-normal
				if normal.length()<0.1: continue
				var at: Vector2=(a+b)/2+normal*9.0
				_dimension_leader(a,b,normal*9.0,plane,BLACK if i<state.get("segments",[]).size() and state.segments[i] else BLUE)
				_dimension(s,"length:%d" % ((i+1)%profile.size()),a.distance_to(b),at,plane,state.get("segments",[])[i] if i<state.get("segments",[]).size() else false)
			for ci in s.get("constraints",[]).size():
				var c: Dictionary=s.constraints[ci]
				if c.get("field")=="angle": draw_angle(s,c,"angle:%d" % ci)
		elif s.points.size()==2:
			var a:=Vector2(s.points[0][0],s.points[0][1])
			var b:=Vector2(s.points[1][0],s.points[1][1])
			if s.kind=="circle":
				var r:=a.distance_to(b)
				_dimension(s,"diameter",r*2,a+Vector2(r*0.8,-r*0.8-10),plane,state.get("fully_defined",false),"Ø")
			else:
				var half: Vector2=(b-a).abs()
				_dimension_leader(a+Vector2(-half.x,-half.y),a+Vector2(half.x,-half.y),Vector2(0,-10),plane,BLACK if state.get("fully_defined",false) else BLUE)
				_dimension_leader(a+Vector2(half.x,-half.y),a+half,Vector2(12,0),plane,BLACK if state.get("fully_defined",false) else BLUE)
				_dimension(s,"width",half.x*2,a+Vector2(0,-half.y-10),plane,state.get("fully_defined",false))
				_dimension(s,"height",half.y*2,a+Vector2(half.x+12,0),plane,state.get("fully_defined",false))
	var active: Dictionary=workbench.document.sketch(workbench.active_sketch)
	if not active.is_empty() and workbench.sketch_visibility.get(workbench.document.sketch_root(workbench.active_sketch),true):
		var plane:=Doc.unpack_transform(active.plane)
		for region in workbench.regions():
			var vertices: PackedVector2Array=preload("res://cad/CADSketchRegions.gd").triangles(region)
			if vertices.is_empty():continue
			var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for v in vertices:surface.add_vertex(plane*Vector3(v.x,v.y,0.1)*0.001)
			var node:=MeshInstance3D.new();node.mesh=surface.commit()
			var selected: bool=workbench.ui.mode=="extrude" and region.id in workbench.selected_regions
			var hovered: bool=workbench.ui.mode=="extrude" and str(region.id)==workbench.hovered_region
			node.material_override=material(Color(1.0,0.55,0.02,0.65) if selected else Color(0.12,0.60,1.0,0.5) if hovered else Color(0.40,0.47,0.54,0.16))
			add_child(node)
			if selected:
				var outline:=PackedVector3Array()
				for poly in [region.outer]+region.holes:
					for i in poly.size():
						for v in [poly[i],poly[(i+1)%poly.size()]]:outline.append(plane*Vector3(v.x,v.y,0.7)*0.001)
				ribbons(outline,Color("ff9800"))
	ribbons(blue_vertices,BLUE)
	ribbons(black_vertices,BLACK)
	preview=MeshInstance3D.new()
	preview.material_override=material(BLUE)
	add_child(preview)
	guides=MeshInstance3D.new(); guides.material_override=material(Color("c57e00")); add_child(guides)
	guides.material_override.render_priority=5
	live_label=label("",Vector3.ZERO,BLUE)
	live_label.visible=false
	transform=workbench.document.view_transform
	visible=workbench.is_modeling()
	layout_dimensions()

func _dimension(s: Dictionary,field: String,value: float,at: Vector2,plane: Transform3D,defined: bool,prefix: String=""):
	var color:=BLACK if defined else BLUE
	_add_dimension(s,field,prefix+"%.2f" % value,at,plane,color,value/2.0 if field=="diameter" else 0.0)

func _add_dimension(s: Dictionary,field: String,text_: String,at: Vector2,plane: Transform3D,color: Color,radius: float=0):
	var offset: Array=s.get("dimension_labels",{}).get(field,[])
	var node:=label(text_,Vector3.ZERO,color)
	var text_size:=ThemeDB.fallback_font.get_string_size(text_,HORIZONTAL_ALIGNMENT_LEFT,-1,node.font_size)*node.pixel_size*1000
	var d: Dictionary={"sketch":int(s.id),"field":field,"point":at,"preferred":at,"plane":plane,"node":node,"leader":lines(PackedVector3Array(),color),"half_size":text_size/2+Vector2(2,2),"manual":not offset.is_empty(),"offset":Vector2(offset[0],offset[1]) if not offset.is_empty() else Vector2.ZERO,"radius":radius}
	if radius>0: d.center=Vector2(s.points[0][0],s.points[0][1])
	dimensions.append(d)

func _process(_delta):
	if not workbench or dimensions.is_empty() or not visible: return
	if workbench.dimension_drag and workbench.dimension_drag.hand: return
	var pose: Transform3D=workbench.camera.global_transform
	if pose.origin.distance_to(_layout_pose.origin)>0.01*XRServer.world_scale or pose.basis.get_rotation_quaternion().angle_to(_layout_pose.basis.get_rotation_quaternion())>0.015 or not workbench.document.view_transform.is_equal_approx(_layout_view): layout_dimensions()

func layout_dimensions():
	_layout_pose=workbench.camera.global_transform
	_layout_view=workbench.document.view_transform
	var occupied: Array=[]
	# Explicit placements stay where the user put them; automatic labels avoid them.
	var ordered: Array=dimensions.filter(func(d):return d.manual)+dimensions.filter(func(d):return not d.manual)
	for d in ordered:
		var preferred: Vector2=d.preferred+d.offset
		var at:=preferred
		var bounds:=_label_bounds(d,at)
		if not d.manual:
			for attempt in 128:
				if not occupied.any(func(r):return r.intersects(bounds)): break
				# Move in the sketch plane along whichever axis projects more vertically.
				var frame: Basis=_layout_view.basis*d.plane.basis
				var up: Vector3=_layout_pose.basis.y.normalized()
				var u:=Vector2(frame.x.dot(up),frame.y.dot(up))
				if u.length()<0.1: u=Vector2.UP
				at=preferred+u.normalized()*float(attempt+1)*14.0
				bounds=_label_bounds(d,at)
		occupied.append(bounds)
		position_dimension(d,at)

func _label_bounds(d: Dictionary,at: Vector2) -> Rect2:
	var world: Vector3=_layout_view*(d.plane*Vector3(at.x,at.y,1.2)*0.001)
	var eye:=_layout_pose.affine_inverse()*world
	# Perspective-sized bounds on the camera's unit-depth plane, including padding.
	var depth:=maxf(0.01,-eye.z)
	var scale_: float=_layout_view.basis.x.length()
	var half: Vector2=d.half_size*0.001*scale_/depth
	return Rect2(Vector2(eye.x,eye.y)/depth-half,half*2)

func position_dimension(d: Dictionary,at: Vector2):
	d.point=at
	d.node.position=d.plane*Vector3(at.x,at.y,1.2)*0.001
	var anchor: Vector2=d.preferred
	if float(d.radius)>0: anchor=d.center+(at-d.center).normalized()*float(d.radius)
	var delta: Vector2=anchor-at
	# End the leader at the text boundary, so it never runs through the value.
	var half: Vector2=d.half_size
	var factor:=maxf(absf(delta.x)/half.x,absf(delta.y)/half.y)
	var vertices:=PackedVector3Array()
	if factor>1.0:
		for v in [anchor,at+delta/factor]: vertices.append(d.plane*Vector3(v.x,v.y,0.6)*0.001)
	if vertices.is_empty(): d.leader.mesh=null
	else:
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_LINES)
		for v in vertices: surface.add_vertex(v)
		d.leader.mesh=surface.commit()

func _dimension_leader(a: Vector2,b: Vector2,offset: Vector2,plane: Transform3D,color: Color):
	var aa:=a+offset
	var bb:=b+offset
	var direction: Vector2=(bb-aa).normalized()
	var normal:=Vector2(-direction.y,direction.x)
	var local: Array=[a,aa+offset.normalized()*3,b,bb+offset.normalized()*3]
	var middle: Vector2=(aa+bb)/2
	if aa.distance_to(bb)>24:
		local.append_array([aa,middle-direction*10,bb,middle+direction*10])
	else: local.append_array([aa,bb])
	for pair in [[aa,direction],[bb,-direction]]:
		for sign in [-1,1]: local.append(pair[0]); local.append(pair[0]+pair[1]*2+normal*sign*0.8)
	var vertices:=PackedVector3Array()
	for v in local: vertices.append(plane*Vector3(v.x,v.y,0.6)*0.001)
	lines(vertices,color)

func angle_vertices(s: Dictionary,c: Dictionary) -> PackedVector3Array:
	var g:=preload("res://cad/CADAngleDimension.gd").geometry(s,c)
	var plane:=Doc.unpack_transform(s.plane)
	var radius:=float(c.radius)
	var local: Array=[]
	var steps:=maxi(12,ceili(absf(g.sweep)*24))
	for i in steps:
		# Leave a clear gap for the degree label in the middle of the arc.
		if absf((float(i)+0.5)/steps-0.5)*radius*absf(g.sweep)<9: continue
		local.append(g.center+g.a.rotated(g.sweep*float(i)/steps)*radius)
		local.append(g.center+g.a.rotated(g.sweep*float(i+1)/steps)*radius)
	for item in [[g.a,1,int(c.point),int(c.flip_a)],[g.b,-1,int(c.other),int(c.flip_b)]]:
		var ray: Vector2=item[0]
		var end: Vector2=g.center+ray*radius
		var length_: float=g.center.distance_to(preload("res://cad/CADAngleDimension.gd").point(s,int(item[2])))
		if int(item[3])<0 or radius>length_:
			local.append_array([g.center+ray*(2.0 if int(item[3])<0 else length_),g.center+ray*(radius+3)])
		var tangent: Vector2=ray.rotated(PI/2)*signf(g.sweep)*int(item[1])
		for sign_ in [-1,1]: local.append_array([end,end+tangent*2.5+ray*float(sign_)*0.9])
	var vertices:=PackedVector3Array()
	for v in local: vertices.append(plane*Vector3(v.x,v.y,0.9)*0.001)
	return vertices

func draw_angle(s: Dictionary,c: Dictionary,field: String):
	var g:=preload("res://cad/CADAngleDimension.gd").geometry(s,c)
	var plane:=Doc.unpack_transform(s.plane)
	ribbons(angle_vertices(s,c),BLACK)
	var at: Vector2=g.label
	_add_dimension(s,field,"%.2f°" % float(c.value),at,plane,BLACK)

func update_angle(s: Dictionary,c: Dictionary,segments: Array):
	var plane:=Doc.unpack_transform(s.plane)
	update_project_highlight(segments,plane)
	preview.visible=not c.is_empty()
	live_label.visible=not c.is_empty()
	if c.is_empty(): return
	preview.mesh=_ribbon_mesh(angle_vertices(s,c))
	var g:=preload("res://cad/CADAngleDimension.gd").geometry(s,c)
	live_label.text="%.2f°" % float(c.value)
	live_label.position=plane*Vector3(g.label.x,g.label.y,1.2)*0.001

func update_preview(s: Dictionary,point: Vector2,show: bool):
	if not preview: return
	preview.visible=show
	live_label.visible=show and not s.points.is_empty()
	if not show or s.points.is_empty():
		if guides: guides.visible=false
		return
	var plane: Transform3D=Doc.unpack_transform(s.plane)
	var a:=Vector2(s.points[-1][0],s.points[-1][1])
	var vertices:=PackedVector3Array()
	var points:=PackedVector2Array([a,point])
	var text_:="%.2f mm" % a.distance_to(point)
	if workbench.tool=="rectangle":
		var half: Vector2=(point-a).abs()
		points=PackedVector2Array([a-half,a+Vector2(half.x,-half.y),a+half,a+Vector2(-half.x,half.y),a-half])
		text_="%.2f × %.2f mm" % [half.x*2,half.y*2]
	elif workbench.tool=="circle":
		points.clear()
		for i in 97: points.append(a+Vector2(cos(TAU*i/96),sin(TAU*i/96))*a.distance_to(point))
		text_="Ø%.2f mm" % (a.distance_to(point)*2)
	for i in points.size()-1:
		for v in [points[i],points[i+1]]: vertices.append(plane*Vector3(v.x,v.y,0.8)*0.001)
	preview.mesh=_ribbon_mesh(vertices)
	live_label.text=text_
	live_label.position=plane*Vector3((a.x+point.x)/2,(a.y+point.y)/2+7,1)*0.001

func hit_dimension(hand: Node3D) -> Dictionary:
	var closest:=INF
	var result: Dictionary={}
	var normal: Vector3=workbench.camera.global_basis.z.normalized()
	var right: Vector3=workbench.camera.global_basis.x.normalized()
	var up: Vector3=workbench.camera.global_basis.y.normalized()
	var direction: Vector3=-hand.global_basis.z.normalized()
	var denominator:=direction.dot(normal)
	if absf(denominator)<0.00001: return {}
	for d in dimensions:
		var center: Vector3=d.node.global_position
		var t: float=(center-hand.global_position).dot(normal)/denominator
		if t<=0 or t>=closest: continue
		var delta: Vector3=hand.global_position+direction*t-center
		var scale_: float=workbench.document.view_transform.basis.x.length()*0.001
		if absf(delta.dot(right))<d.half_size.x*scale_ and absf(delta.dot(up))<d.half_size.y*scale_:
			closest=t;result=d
	return result

func ribbons(vertices: PackedVector3Array,color: Color):
	if vertices.is_empty(): return
	var node:=MeshInstance3D.new()
	node.mesh=_ribbon_mesh(vertices)
	node.material_override=material(color)
	add_child(node)

func _ribbon_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye: Vector3=workbench.document.view_transform.affine_inverse()*workbench.camera.global_position
	for i in range(0,vertices.size(),2):
		var a:=vertices[i]
		var b:=vertices[i+1]
		if a.distance_to(b)<0.0000001: continue
		var normal: Vector3=(b-a).cross(eye-(a+b)/2).normalized()*0.00022
		for v in [a-normal,a+normal,b+normal,a-normal,b+normal,b-normal]: surface.add_vertex(v)
	return surface.commit()

func update_guides(references: Array,plane: Transform3D):
	if not guides: return
	guides.visible=not references.is_empty()
	if references.is_empty(): return
	var vertices:=PackedVector3Array()
	for pair in references:
		var a: Vector2=pair[0]; var b: Vector2=pair[1]
		var length: float=a.distance_to(b)
		if length<0.001: continue
		var axis: Vector2=(b-a)/length
		for step in range(0,int(ceil(length)),6):
			for distance in [float(step),minf(step+3,length)]:
				var p: Vector2=a+axis*distance
				vertices.append(plane*Vector3(p[0],p[1],0.6)*0.001)
	guides.mesh=_ribbon_mesh(vertices) if not vertices.is_empty() else null

func update_project_highlight(segments: Array,plane: Transform3D):
	if not guides: return
	guides.visible=not segments.is_empty()
	var vertices:=PackedVector3Array()
	for edge in segments:
		for p in edge: vertices.append(plane*Vector3(p[0],p[1],0.6)*0.001)
	guides.mesh=_ribbon_mesh(vertices) if not vertices.is_empty() else null
