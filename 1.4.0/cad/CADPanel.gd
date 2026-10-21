extends Control
## A compact Part Studio: persistent command bar, explicit feature list and
## one context inspector. No native popup menus, so every control works in XR.
var workbench: Node3D
var status: Label
var hint: Label
var tree: VBoxContainer
var inspector: VBoxContainer
var command_buttons := {}
var mode := "select"
var _signature := ""
var _tree_signature := ""
var keypad: PanelContainer
var entry: Label
var entry_text := ""
var entry_field := ""
var entry_sketch := -1
var entry_body := -1
var entry_feature := -1
var entry_feature_source: Dictionary={}
var replace_entry := true
var progress_ring: Control
var preview_button: Button
var probe_settings:=false
var confirmation: PanelContainer
var confirmation_message: Label
var confirm_button: Button
var _confirmed_action: Callable

func _ready():
	var skin:=Theme.new()
	skin.default_font_size=25
	skin.set_color("font_color","Label",Color("263445"))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		skin.set_color(state,"Button",Color("263445"))
	skin.set_color("font_disabled_color","Button",Color("68778c"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color({"normal":"e7ecf2","hover":"d5e4f8","pressed":"b6d4fb","focus":"d5e4f8","disabled":"edf0f4"}[state])
		style.set_corner_radius_all(4)
		style.content_margin_left=16
		style.content_margin_right=16
		skin.set_stylebox(state,"Button",style)
	self.theme=skin
	var bg:=ColorRect.new()
	bg.color=Color("f6f8fb")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layout:=VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation",0)
	add_child(layout)
	var header:=_section(layout,Color("18334f"),16)
	var bar:=_row(header)
	var title:=_label(bar,"ABCCAD  /  Part studio",29)
	title.add_theme_color_override("font_color",Color.WHITE)
	title.size_flags_horizontal=SIZE_EXPAND_FILL
	_button(bar,"Save",func(): SignalBus.request_save_game.emit(""))
	_button(bar,"Load",func(): workbench.open_load_menu())
	_button(bar,"Export · mm",func(): workbench.export_selected())
	_button(bar,"Close",func(): workbench.close_panel())
	var toolbar:=_section(layout,Color("ffffff"),12)
	bar=_row(toolbar)
	for item in [["select","Select"],["sketch","Sketch"],["extrude","Extrude"],["origin","Origin"],["table","Table"]]:
		var key: String=item[0]
		var button:=_button(bar,item[1],func(): show_command(key))
		button.toggle_mode=true
		command_buttons[key]=button
	_button(bar,"Undo",func(): workbench.document.undo())
	_button(bar,"Redo",func(): workbench.document.redo())
	_button(bar,"1:1",func(): workbench.reset_view())
	preview_button=_button(bar,"Layers",func(): workbench.set_print_preview(not workbench.print_enabled))
	preview_button.toggle_mode=true
	var lights_button:=_button(bar,"Lights",func(): show_command("lights"))
	lights_button.toggle_mode=true
	command_buttons["lights"]=lights_button
	var content:=HBoxContainer.new()
	content.size_flags_vertical=SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",0)
	layout.add_child(content)
	var side:=_section(content,Color("e9eef4"),16)
	side.custom_minimum_size.x=304
	_label(side,"FEATURES",21)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=SIZE_EXPAND_FILL
	side.add_child(scroll)
	tree=VBoxContainer.new()
	tree.size_flags_horizontal=SIZE_EXPAND_FILL
	tree.add_theme_constant_override("separation",8)
	scroll.add_child(tree)
	bar=_row(side)
	_button(bar,"↑",func(): scroll.scroll_vertical-=180)
	_button(bar,"↓",func(): scroll.scroll_vertical+=180)
	var main:=_section(content,Color("f6f8fb"),24)
	main.size_flags_horizontal=SIZE_EXPAND_FILL
	inspector=VBoxContainer.new()
	inspector.add_theme_constant_override("separation",10)
	main.add_child(inspector)
	var spacer:=Control.new()
	spacer.size_flags_vertical=SIZE_EXPAND_FILL
	main.add_child(spacer)
	hint=_label(main,"Trigger-drag the lower pill to move this window; corner to resize. Two empty grips scale your model view.",21)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var footer:=_section(layout,Color("ffffff"),16)
	status=_label(footer,"Ready · mm",22)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y=70
	progress_ring=preload("res://cad/CADProgressRing.gd").new()
	progress_ring.custom_minimum_size=Vector2(80,80)
	progress_ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	progress_ring.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	progress_ring.position=Vector2(1000,775)
	progress_ring.size=Vector2(80,80)
	add_child(progress_ring)
	progress_ring.visible=false
	_build_keypad()
	_build_confirmation()
	SignalBus.export_finished.connect(func(_ok,text):
		if workbench: workbench.message=text; refresh())
	SignalBus.save_finished.connect(func(_ok,text):
		if workbench: workbench.message=text; refresh())

func _section(parent: Node, color: Color, padding: int) -> VBoxContainer:
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.set_content_margin_all(padding)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	# Return the box; sizing flags belong to its enclosing panel as well.
	box.resized.connect(func():
		panel.size_flags_horizontal=box.size_flags_horizontal
		panel.custom_minimum_size.x=box.custom_minimum_size.x)
	return box

func _row(parent: Node) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	return row

func _label(parent: Node, text: String, font_size: int=25) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,58)
	button.size_flags_horizontal=SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _eye(parent: Node,shown: bool,action: Callable) -> Button:
	var button:=_button(parent,"",action)
	button.custom_minimum_size.x=54
	button.size_flags_horizontal=0
	var icon:=preload("res://cad/CADEyeIcon.gd").new()
	icon.shown=shown
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return button

func _clear(parent: Node):
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func show_command(value: String):
	if workbench.dimension_drag and workbench.dimension_drag.hand: workbench.dimension_drag.end(true)
	keypad.visible=false
	mode=value
	if mode!="sketch": set_hint("")
	if mode=="select": workbench.choose_tool("select")
	elif mode=="origin":
		workbench.tool="origin"
		workbench.message="Hold right trigger to move the origin. Front faces you; Top stays level."
	elif mode=="sketch":
		if workbench.document.sketch(workbench.active_sketch).is_empty(): workbench.begin_sketch()
		elif workbench.tool not in ["line","circle","rectangle"]: workbench.tool="select"
	elif mode!="table" or workbench.tool!="capture_plane": workbench.tool="select"
	if mode=="extrude":workbench.begin_region_selection()
	_signature=""
	refresh()
	workbench.extrude_arrow.refresh()

func _start_sketch(plane: String):
	if workbench.document.busy: return
	if plane=="Face": workbench.new_sketch(true)
	elif plane=="Table": workbench.new_table_sketch()
	else: workbench.new_base_sketch(plane)
	_signature=""
	refresh()

func refresh():
	if not workbench or not status: return
	var doc=workbench.document
	var s: Dictionary=doc.sketch(workbench.active_sketch)
	var body: Dictionary=doc.body(workbench.selected_body)
	if confirmation: confirm_button.disabled=doc.busy
	preview_button.set_pressed_no_signal(workbench.print_enabled)
	preview_button.text="Layers · on" if workbench.print_enabled else "Layers"
	progress_ring.visible=workbench.print_loading
	progress_ring.progress=workbench.print_progress
	for key in command_buttons: command_buttons[key].set_pressed_no_signal(key==mode)
	var signature:=str([mode,workbench.active_sketch,workbench.selected_body,workbench.tool,s,body.get("features",[]).size(),workbench.operation,workbench.depth_mm,workbench.selected_regions,workbench.regions().size(),doc.origin_mm,doc.busy,workbench.auto_constraints,not workbench.selected_hit.is_empty(),doc.reference_plane,workbench.contact_points,workbench.probe_offset_mm,workbench.print_loading,workbench.scene_lights() if mode=="lights" else []])
	var tree_signature:=str([doc.bodies.map(func(b): return [b.id,b.name,b.features.map(func(f):return [f.sketch.id,f.depth_mm,f.operation])]),doc.sketches.map(func(sk): return [sk.id,sk.kind]),workbench.active_sketch,workbench.selected_body,doc.busy,workbench.plane_visibility,workbench.sketch_visibility])
	if tree_signature!=_tree_signature:
		_tree_signature=tree_signature
		_clear(tree)
		_label(tree,"Planes",22)
		for plane_name in ["Front","Top","Right","Sketch plane","Table"]:
			if plane_name=="Table" and doc.reference_plane.is_empty(): continue
			var key: String=plane_name
			var row:=_row(tree)
			var b:=_button(row,key,func():
				if key in ["Front","Top","Right"]: _start_sketch(key); show_command("sketch"))
			b.add_theme_font_size_override("font_size",21)
			var eye:=_eye(row,workbench.plane_visibility.get(key,true),func():workbench.toggle_plane_visibility(key))
			eye.tooltip_text=("Hide " if workbench.plane_visibility.get(key,true) else "Show ")+key
		_label(tree,"Sketches & extrudes",22)
		for sk in doc.sketch_roots():
			var id: int=sk.id
			var row:=_row(tree)
			var button:=_button(row,"Sketch %d" % id,func():
				workbench.active_sketch=id
				workbench.tool="select"
				workbench._changed())
			button.add_theme_font_size_override("font_size",19)
			button.clip_text=true
			button.toggle_mode=true
			button.set_pressed_no_signal(id==doc.sketch_root(workbench.active_sketch))
			button.disabled=doc.busy
			var eye:=_eye(row,workbench.sketch_visibility.get(id,true),func():workbench.toggle_sketch_visibility(id))
			eye.tooltip_text=("Hide" if workbench.sketch_visibility.get(id,true) else "Show")+" sketch"
			var trash:=_button(row,"",func():request_delete_sketch(id))
			trash.custom_minimum_size.x=48
			trash.size_flags_horizontal=0
			trash.disabled=doc.busy
			trash.tooltip_text="Delete sketch"
			var icon:=preload("res://cad/CADTrashIcon.gd").new()
			icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
			trash.add_child(icon); icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var feature_number:=0
			for body_item in doc.bodies:
				for fi in body_item.features.size():
					var feature: Dictionary=body_item.features[fi]
					feature_number+=1
					if doc.sketch_root(int(feature.sketch.id))!=id: continue
					var bid: int=body_item.id
					var index: int=fi
					var feature_row:=_row(tree)
					var edit:=_button(feature_row,"↳ Extrude %d · %.2f mm" % [feature_number,float(feature.depth_mm)],func(): edit_feature(bid,index))
					edit.add_theme_font_size_override("font_size",19)
					edit.tooltip_text="%s · %s · select to edit depth" % [body_item.name,feature.operation]
					edit.disabled=doc.busy
		_label(tree,"Parts · "+str(doc.bodies.size()),22)
		for b in doc.bodies:
			var id: int=b.id
			var button:=_button(tree,b.name,func():
				workbench.selected_body=id
				workbench.selected_hit={}
				workbench._update_print_preview()
				refresh())
			button.toggle_mode=true
			button.set_pressed_no_signal(id==workbench.selected_body)
			button.disabled=doc.busy
		var clear_button:=_button(tree,"Clear all…",request_clear_all)
		clear_button.disabled=doc.busy or (doc.sketches.is_empty() and doc.bodies.is_empty())
		for row in tree.get_children():
			if row is Button: row.custom_minimum_size.y=44
			elif row is HBoxContainer:
				for child in row.get_children():
					if child is Button: child.custom_minimum_size.y=44
	if signature!=_signature:
		_signature=signature
		_clear(inspector)
		_label(inspector,{"select":"Part studio","sketch":"Sketch","extrude":"Extrude","origin":"Workspace origin","table":"Table reference","lights":"Lights"}[mode],36)
		if mode=="select":
			_label(inspector,body.get("name","Select a face or start a sketch"),27)
			var text:=_label(inspector,"Grip any extruded part to move or rotate it.\nSketches follow the part; exported sizes stay in mm.",23)
			text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			var new_button:=_button(inspector,"New sketch",func(): workbench.begin_sketch(); show_command("sketch"))
			new_button.disabled=doc.busy
			var b:=_button(inspector,"Sketch on selected face",func(): _start_sketch("Face"); show_command("sketch"))
			b.disabled=workbench.selected_hit.is_empty() or doc.busy
			var row:=_row(inspector)
			b=_button(row,"Convert face edges",func(): workbench.convert_edges(); show_command("sketch"))
			b.disabled=workbench.selected_hit.is_empty() or doc.busy
			b=_button(row,"Block → CAD",func(): workbench.promote_selected_block())
			b.disabled=workbench.selected_hit.is_empty() or int(workbench.selected_hit.get("source",{}).get("id",0))>=0 or doc.busy
			if not body.is_empty():
				_label(inspector,"Solid history",21)
				for feature in body.features.slice(maxi(0,body.features.size()-4)):
					_label(inspector,"Extrude · %s · %.2f mm" % [feature.operation,feature.depth_mm],22)
		elif mode=="sketch":
			if s.is_empty():
				_label(inspector,"Choose a sketch plane",25)
				var row:=_row(inspector)
				for plane in ["Front","Top","Right"]:
					var name: String=plane
					_button(row,name+" sketch",func(): _start_sketch(name))
				var b:=_button(inspector,"Sketch on selected face",func(): _start_sketch("Face"))
				b.disabled=workbench.selected_hit.is_empty()
			else:
				_label(inspector,"Sketch %d · %d shapes" % [doc.sketch_root(s.id),doc.sketch_shape_count(s.id)],25)
				var row:=_row(inspector)
				for item in [["line","Line"],["circle","Circle"],["rectangle","Center rectangle"]]:
					var key: String=item[0]
					var b:=_button(row,item[1],func(): workbench.choose_tool(key))
					b.toggle_mode=true
					b.set_pressed_no_signal(workbench.tool==key)
				row=_row(inspector)
				var project:=_button(row,"Project",func(): workbench.start_use_edge())
				project.toggle_mode=true;project.set_pressed_no_signal(workbench.tool=="use_edge")
				if s.kind=="line" and not s.points.is_empty():
					_button(row,"From vertex",func(): workbench.start_extend_vertex())
					if not s.closed: _button(row,"Resume lines",func(): workbench.resume_lines())
				if s.kind=="line" and s.points.size()>=3:
					_button(inspector,"Angle dimension · select two lines",func(): workbench.start_angle())
				row=_row(inspector)
				for field in {"rectangle":["width","height"],"circle":["diameter"],"line":["length"]}[s.kind]:
					if s.points.is_empty() and not s.get("projected_edges",[]).is_empty(): continue
					var key: String=field
					var b:=_button(row,key.capitalize()+" · %.2f mm" % _value(key),func(): edit_number(key))
					b.disabled=s.points.size()<2 or doc.busy
				row=_row(inspector)
				_button(row,"Auto: on" if workbench.auto_constraints else "Auto: off",func(): workbench.auto_constraints=not workbench.auto_constraints; refresh())
				_button(row,"Clear constraints",func(): doc.clear_constraints(workbench.active_sketch))
				var constraint_count:=0;var projected_count:=0
				for entity in doc.sketch_members(workbench.active_sketch):
					constraint_count+=entity.get("constraints",[]).size();projected_count+=entity.get("projected_edges",[]).size()
				_label(inspector,"%d constraints · %d projected edges" % [constraint_count,projected_count],22)
				if workbench.tool in ["line","circle","rectangle","use_edge","extend_vertex","angle"]: _button(inspector,"Finish Project · B" if workbench.tool=="use_edge" else "End tool · B",func(): workbench.end_sketch_tool())
				if s.kind=="line" and not s.closed and s.points.size()>=3:
					_button(inspector,"Close profile",func(): workbench.close_profile())
				if not workbench.regions().is_empty():
					var b:=_button(inspector,"Continue to extrude →",func(): show_command("extrude"))
					b.disabled=doc.busy
		elif mode=="extrude":
			_label(inspector,"Choose a sketch, then select its enclosed areas.",23)
			var row:=_row(inspector)
			for op in ["New","Add","Remove"]:
				var key: String=op
				var b:=_button(row,op,func(): workbench.operation=key; refresh())
				b.toggle_mode=true
				b.set_pressed_no_signal(workbench.operation==op)
			_button(inspector,"Depth · %.2f mm" % workbench.depth_mm,func(): edit_number("depth"))
			_label(inspector,"Trigger-drag the arrow to preview depth. Apply commits.",21)
			_button(inspector,"Reverse direction ↔",func():workbench.reverse_extrude_direction())
			_label(inspector,"Profile: "+("Sketch "+str(doc.sketch_root(int(s.id))) if not s.is_empty() else "none"),25)
			var area_count: int=workbench.regions().size()
			var selection_hint:=_label(inspector,"Please select the area or areas you want to extrude." if area_count>1 else "One enclosed area selected automatically." if area_count==1 else "Close an area in this sketch first.",22)
			selection_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			_label(inspector,"%d / %d areas selected · point and trigger to toggle" % [workbench.selected_regions.size(),area_count],21)
			if workbench.operation!="New": _label(inspector,"Target: "+body.get("name","select a part"),25)
			var b:=_button(inspector,"Computing…" if doc.busy else "Apply extrude",func():
				if await workbench.extrude():
					mode="select"
					_signature=""
					refresh())
			b.modulate=Color("b7d7ff")
			b.disabled=doc.busy or s.is_empty() or workbench.selected_regions.is_empty() or (workbench.operation!="New" and body.is_empty())
			_button(inspector,"Back",func(): show_command("sketch"))
		elif mode=="lights":
			var text:=_label(inspector,"Adjust the lights in your workspace.",23)
			text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			for item in workbench.scene_lights():
				var name_: String=item.name
				var row:=_row(inspector)
				var label:=_label(row,item.label,23)
				label.size_flags_horizontal=SIZE_EXPAND_FILL
				label.size_flags_vertical=SIZE_SHRINK_CENTER
				label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				var button:=_button(row,"On" if item.enabled else "Off",func(): workbench.toggle_scene_light(name_))
				button.toggle_mode=true
				button.set_pressed_no_signal(item.enabled)
				button.custom_minimum_size.x=96
				button.size_flags_horizontal=0
			var note:=_label(inspector,"Changes apply immediately. Restart restores defaults.",21)
			note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		elif mode=="origin":
			var text:=_label(inspector,"Hold right trigger and move the origin.\nFront turns toward you; Top stays level.",25)
			text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			for axis in ["x","y","z"]:
				var key: String="origin_"+axis
				_button(inspector,axis.to_upper()+" · %.2f mm" % _value(key),func(): edit_number(key))
			_button(inspector,"Done",func(): show_command("select"))
		else:
			if workbench.tool=="capture_plane":
				_label(inspector,"Contact %d of 3" % mini(3,workbench.contact_points.size()+1),29)
				var text:=_label(inspector,"Touch the blue probe marker to the table, then trigger. Repeat at three widely spaced spots.",24)
				text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				_button(inspector,"Undo contact",func():
					if not workbench.contact_points.is_empty(): workbench.contact_points.pop_back()
					workbench._redraw_reference()
					refresh())
				_button(inspector,"Cancel capture",func(): workbench.cancel_table_capture())
			elif probe_settings:
				var text:=_label(inspector,"Align the blue marker with the point of the controller that will touch the table. Offsets are in controller-local millimeters.",24)
				text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				var row:=_row(inspector)
				for axis in ["x","y","z"]:
					var key: String="probe_"+axis
					_button(row,axis.to_upper()+" · %.1f" % _value(key),func(): edit_number(key))
				_button(inspector,"Back to table",func(): probe_settings=false; _signature=""; refresh())
			else:
				var text:=_label(inspector,"Mark three contacts to align a sketch plane with a real surface. Use the blue probe as the contact point.",23)
				text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				var b:=_button(inspector,"Capture table · 3 contacts",func(): workbench.start_table_capture())
				b.disabled=doc.busy
				if not doc.reference_plane.is_empty():
					var row:=_row(inspector)
					b=_button(row,"Plane lock: on" if workbench.reference_locked() else "Plane lock: off",func(): workbench.toggle_plane_lock())
					b.disabled=doc.busy
					b=_button(row,"Rotation: locked" if doc.reference_plane.get("lock_rotation",false) else "Rotation: free",func(): workbench.toggle_part_rotation_lock())
					b.disabled=doc.busy
					b=_button(inspector,"Sketch on table",func(): _start_sketch("Table"); show_command("sketch"))
					b.disabled=doc.busy
				_button(inspector,"Probe calibration",func(): probe_settings=true; _signature=""; refresh())
				_label(inspector,"1:1 = physical size. Table normal = print/export Z.",21)
				_label(inspector,"If the room or tracking origin changes, capture again.",21)
	status.text=workbench.message.left(150)+"\nmm  ·  View %.2f×  ·  Top ∥ ground" % workbench.display_scale()

	if workbench.print_loading: status.text="Building 0.2 mm layers · %d%%" % roundi(workbench.print_progress*100)+"\nYou can keep working or toggle Layers off to cancel."

func set_hint(text: String):
	hint.text=text if not text.is_empty() else "Trigger-drag the lower pill to move this window; corner to resize. Two empty grips scale your model view."

func _value(key: String) -> float:
	if key=="depth": return workbench.depth_mm
	if key.begins_with("probe_"): return workbench.probe_offset_mm[{"probe_x":0,"probe_y":1,"probe_z":2}[key]]
	if key.begins_with("origin_"): return workbench.document.origin_mm[{"origin_x":0,"origin_y":1,"origin_z":2}[key]]
	var s: Dictionary=workbench.document.sketch(workbench.active_sketch)
	if s.is_empty() or s.points.size()<2: return 0
	if key.begins_with("angle:"):
		var ci:=int(key.split(":")[1])
		return float(s.constraints[ci].value) if ci>=0 and ci<s.constraints.size() else 0.0
	var index: int=int(key.split(":")[1]) if ":" in key else s.points.size()-1
	var a:=Vector2(s.points[0][0],s.points[0][1])
	var b:=Vector2(s.points[index][0],s.points[index][1])
	if key=="width": return absf(b.x-a.x)*2
	if key=="height": return absf(b.y-a.y)*2
	if key.begins_with("length"):
		var previous: int=(index+s.points.size()-1)%s.points.size()
		a=Vector2(s.points[previous][0],s.points[previous][1])
	if key=="diameter": return a.distance_to(b)*2
	return a.distance_to(b)

func _build_keypad():
	keypad=PanelContainer.new()
	keypad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("f3f5f8")
	style.set_content_margin_all(18)
	style.set_corner_radius_all(14)
	keypad.add_theme_stylebox_override("panel",style)
	add_child(keypad)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	keypad.add_child(box)
	var title:=_label(box,"Dimension · drag to move",24)
	title.custom_minimum_size.y=48
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	entry=Label.new()
	entry.custom_minimum_size.y=84
	entry.add_theme_font_size_override("font_size",32)
	entry.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(entry)
	var grid:=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",10)
	grid.size_flags_vertical=SIZE_EXPAND_FILL
	box.add_child(grid)
	for key in ["7","8","9","4","5","6","1","2","3","±","0","."]:
		var value: String=key
		var b:=_button(grid,key,func(): type_key(value))
		b.custom_minimum_size.y=82
		b.add_theme_font_size_override("font_size",38)
	var row:=GridContainer.new()
	row.columns=2
	row.add_theme_constant_override("h_separation",10)
	row.add_theme_constant_override("v_separation",10)
	box.add_child(row)
	_button(row,"Backspace",func(): entry_text=entry_text.left(-1); _entry_label())
	_button(row,"Clear",func(): entry_text=""; _entry_label())
	_button(row,"Cancel",func(): keypad.visible=false)
	var apply:=_button(row,"Apply",apply_entry)
	apply.modulate=Color("b7d7ff")
	for button in row.get_children(): button.custom_minimum_size.y=64
	keypad.visible=false

func edit_number(field: String,at: Vector3=Vector3.INF):
	entry_field=field
	entry_sketch=workbench.active_sketch
	entry_body=-1;entry_feature=-1;entry_feature_source={}
	entry_text="%.3f" % (0.0 if field=="feature_depth" else _value(field))
	replace_entry=true
	workbench.number_pad.open(at)
	_entry_label()

func edit_feature(body_id: int,index: int):
	var b: Dictionary=workbench.document.body(body_id)
	if workbench.document.busy or b.is_empty() or index<0 or index>=b.features.size(): return
	workbench.active_sketch=int(b.features[index].sketch.id)
	workbench.selected_body=body_id
	workbench.selected_hit={}
	workbench._changed()
	show_command("select")
	edit_number("feature_depth")
	entry_body=body_id;entry_feature=index;entry_feature_source=b.features[index].duplicate(true)
	entry_text=str(float(b.features[index].depth_mm))
	_entry_label()
	workbench._update_print_preview()

func type_key(key: String):
	if replace_entry: entry_text=""; replace_entry=false
	if key=="±": entry_text=entry_text.substr(1) if entry_text.begins_with("-") else "-"+entry_text
	elif key==".":
		if not "." in entry_text: entry_text+="."
	elif entry_text.length()<12: entry_text+=key
	_entry_label()

func _entry_label():
	var title:=entry_field.replace("_"," ").capitalize()
	if entry_field.begins_with("length:"): title="Segment %d length" % (int(entry_field.split(":")[1])+1)
	if entry_field.begins_with("angle:"): title="Angle"
	entry.text=title+"  /  "+entry_text+("°" if entry_field.begins_with("angle:") else " mm")

func apply_entry():
	if not entry_text.is_valid_float() or not is_finite(entry_text.to_float()): entry.text="Enter a valid number in mm"; return
	var value:=entry_text.to_float()
	if entry_field.begins_with("angle:") and (value<=0.01 or value>=179.99): entry.text="Use an angle between 0.01° and 179.99°"; return
	if absf(value)>100000: entry.text="Use a value between −100000 and 100000 mm"; return
	if workbench.document.busy: return
	if entry_field=="feature_depth":
		if absf(value)<0.01: entry.text="Depth must be at least 0.01 mm"; return
		var target: Dictionary=workbench.document.body(entry_body)
		if target.is_empty() or entry_feature<0 or entry_feature>=target.features.size() or target.features[entry_feature]!=entry_feature_source:
			entry.text="This feature changed. Select its Extrude row again."
			return
		if not await workbench.document.edit_feature_depth(entry_body,entry_feature,value):
			entry.text="Cannot rebuild at this depth. Release held parts or try another value."
			return
	elif entry_field=="depth":
		if absf(value)<0.01: entry.text="Depth must be at least 0.01 mm"; return
		workbench.depth_mm=value
	elif entry_field.begins_with("probe_"):
		var p: Vector3=workbench.probe_offset_mm
		p[{"probe_x":0,"probe_y":1,"probe_z":2}[entry_field]]=value
		workbench.set_probe_offset(p)
	elif entry_field.begins_with("origin_"):
		var p: Vector3=workbench.document.origin_mm
		p[{"origin_x":0,"origin_y":1,"origin_z":2}[entry_field]]=value
		workbench.document.move_origin(p)
	else:
		if value<=0: entry.text="Use a positive dimension (mm)"; return
		if not await workbench.document.dimension(entry_sketch,entry_field,value):
			entry.text="Dimension conflicts with constraints or geometry. Clear constraints to change that relationship."
			return
	keypad.visible=false
	workbench.message=entry_field.replace("_"," ").capitalize()+" set to "+str(value)+("°. Solid features updated." if entry_field.begins_with("angle:") else " mm. Solid features updated.")
	workbench._changed()

func _build_confirmation():
	confirmation=PanelContainer.new()
	confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("f3f5f8"); style.set_content_margin_all(70)
	confirmation.add_theme_stylebox_override("panel",style)
	add_child(confirmation)
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",28); confirmation.add_child(box)
	_label(box,"Confirm deletion",36)
	confirmation_message=_label(box,"",28)
	confirmation_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	confirmation_message.size_flags_vertical=SIZE_EXPAND_FILL
	var row:=_row(box)
	_button(row,"Cancel",cancel_confirmation)
	confirm_button=_button(row,"Delete",_apply_confirmation)
	confirm_button.modulate=Color("ffb8af")
	confirmation.visible=false

func request_delete_sketch(id: int):
	if workbench.document.busy: return
	var plan: Dictionary=workbench.document.deletion_plan(id)
	if plan.sketches.is_empty(): return
	var roots: Dictionary={}
	for sid in plan.sketches:roots[workbench.document.sketch_root(int(sid))]=true
	var count: int=roots.size()
	var text_: String="Delete Sketch %d?" % workbench.document.sketch_root(id)
	if plan.bodies.size()>0 or count>1:
		if plan.bodies.size()>0: text_+="\nAlso deletes %d dependent %s." % [plan.bodies.size(),"part" if plan.bodies.size()==1 else "parts"]
		if count>1: text_+="\nAlso deletes %d dependent %s." % [count-1,"sketch" if count==2 else "sketches"]
	text_+="\n\nSaved files stay. You can Undo this deletion."
	confirmation_message.text=text_
	confirm_button.text="Delete sketch"
	_confirmed_action=func():return workbench.document.delete_sketch(id)
	confirmation.visible=true

func request_clear_all():
	if workbench.document.busy: return
	confirmation_message.text="Clear all CAD parts and sketches?\n\nTable calibration, the table reference, classic blocks and saved files stay. You can Undo this reset."
	confirm_button.text="Clear all"
	_confirmed_action=func():return workbench.document.clear_all()
	confirmation.visible=true

func cancel_confirmation():
	confirmation.visible=false
	_confirmed_action=Callable()

func _apply_confirmation():
	if workbench.document.busy or not _confirmed_action.is_valid(): return
	var action:=_confirmed_action
	cancel_confirmation()
	if action.call():
		workbench.tool="select"
		mode="select"
		workbench.selected_hit={}
		workbench._changed()
