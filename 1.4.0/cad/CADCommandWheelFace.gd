extends Control
## One quiet ring, short labels, and one contextual explanation in the center.
## Blue surfaces retain alpha 0.5; text stays opaque for headset readability.
var selected := -1
var menu: Dictionary={"id":"", "title":"COMMAND", "items":[]}
var _highlights: Array[float]=[]

func _process(delta: float):
	_highlights.resize(menu.items.size())
	for i in _highlights.size():
		_highlights[i]=move_toward(_highlights[i],1.0 if i==selected else 0.0,delta*12)
	queue_redraw()

func _draw():
	var center:=size/2
	var count: int=menu.items.size()
	if count==0: return
	var width:=TAU/count
	for i in count:
		var item: Dictionary=menu.items[i]
		var angle: float=-PI/2+i*width
		var start:=angle-width/2+0.025
		var end:=angle+width/2-0.025
		var polygon:=PackedVector2Array()
		for j in 33: polygon.append(center+Vector2.from_angle(lerpf(start,end,j/32.0))*294)
		for j in 33: polygon.append(center+Vector2.from_angle(lerpf(end,start,j/32.0))*125)
		var amount: float=_highlights[i] if i<_highlights.size() else (1.0 if i==selected else 0.0)
		var color:=Color(0.025,0.23,0.59,0.5).lerp(Color(0.06,0.53,1.0,0.5),amount)
		if not item.enabled: color=Color(0.04,0.14,0.28,0.5)
		draw_colored_polygon(polygon,color)
		draw_arc(center,294,start,end,40,Color(0.30,0.72,1.0,lerpf(0.34,0.95,amount)),lerpf(1.3,2.8,amount),true)
		draw_arc(center,125,start,end,24,Color(0.30,0.72,1.0,0.32),1.0,true)
		var at:=center+Vector2.from_angle(angle)*209
		var ink:=Color(0.91,0.97,1.0,1.0 if item.enabled else 0.32)
		_icon(str(item.icon),at+Vector2(0,-15),ink)
		_text_lines(str(item.label),at+Vector2(0,22),17 if count>4 else 18,ink)
		if item.get("active",false): draw_circle(center+Vector2.from_angle(angle)*143,3,Color(0.5,0.85,1.0))
	draw_circle(center,108,Color(0.015,0.15,0.38,0.5))
	draw_arc(center,109,0,TAU,96,Color(0.30,0.72,1.0,0.45),1.2,true)
	_text(str(menu.title),center+Vector2(0,-41),12,Color(0.5,0.78,1.0))
	if selected>=0 and selected<count:
		var item: Dictionary=menu.items[selected]
		_text(str(item.label).replace("\n"," "),center+Vector2(0,-11),18,Color(0.94,0.98,1.0))
		_text_lines(_wrap(str(item.hint),165,13),center+Vector2(0,12),13,Color(0.69,0.83,0.98))
		_text("CLICK TO SELECT" if item.enabled else "UNAVAILABLE",center+Vector2(0,58),11,Color(0.5,0.78,1.0))
	else:
		_text("Tilt to choose",center+Vector2(0,-2),19,Color(0.94,0.98,1.0))
		_text("RIGHT STICK",center+Vector2(0,26),11,Color(0.5,0.78,1.0))

func _wrap(value: String, max_width: float, font_size: int) -> String:
	var output: Array[String]=[]
	var line:=""
	for word in value.split(" "):
		var next:=word if line.is_empty() else line+" "+word
		if ThemeDB.fallback_font.get_string_size(next,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>max_width and not line.is_empty():
			output.append(line);line=word
		else: line=next
	output.append(line)
	return "\n".join(output)

func _text_lines(value: String, at: Vector2, font_size: int, color: Color):
	var lines:=value.split("\n")
	for i in lines.size(): _text(lines[i],at+Vector2(0,i*(font_size+3)),font_size,color)

func _text(value: String, at: Vector2, font_size: int, color: Color):
	var font:=ThemeDB.fallback_font
	draw_string(font,at-Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _stroke(points: PackedVector2Array, at: Vector2, ink: Color):
	for j in points.size()-1: draw_line(at+points[j],at+points[j+1],ink,2.5,true)

func _icon(id: String, at: Vector2, ink: Color):
	match id:
		"line":
			draw_line(at+Vector2(-17,14),at+Vector2(17,-14),ink,2.5,true)
			draw_circle(at+Vector2(-17,14),3,ink);draw_circle(at+Vector2(17,-14),3,ink)
		"circle":
			draw_arc(at,18,0,TAU,48,ink,2.5,true)
			draw_circle(at,2.5,ink)
			draw_line(at,at+Vector2(12,-13),ink,1.4,true)
		"rectangle":
			draw_rect(Rect2(at-Vector2(21,15),Vector2(42,30)),ink,false,2.5)
			draw_circle(at,2.5,ink)
		"sketch":
			_stroke(PackedVector2Array([Vector2(-20,17),Vector2(-20,-9),Vector2(5,-9),Vector2(5,17),Vector2(-20,17),Vector2(17,-20),Vector2(23,-14),Vector2(-3,12),Vector2(-11,15),Vector2(-8,7),Vector2(17,-20)]),at,ink)
		"use_edge", "plane":
			_stroke(PackedVector2Array([Vector2(-23,15),Vector2(-8,-12),Vector2(17,-12),Vector2(5,13),Vector2(-23,15)]),at,ink)
			if id=="use_edge": draw_line(at+Vector2(-23,15),at+Vector2(-8,-12),ink,4,true)
		"extrude":
			_stroke(PackedVector2Array([Vector2(-21,6),Vector2(0,-5),Vector2(21,6),Vector2(0,18),Vector2(-21,6),Vector2(-21,-8),Vector2(0,-19),Vector2(21,-8),Vector2(21,6),Vector2(0,18),Vector2(0,3)]),at,ink)
		"dimension": _stroke(PackedVector2Array([Vector2(-23,-15),Vector2(-23,17),Vector2(-23,2),Vector2(23,2),Vector2(23,-15),Vector2(23,17)]),at,ink)
		"select": _stroke(PackedVector2Array([Vector2(-12,-20),Vector2(-10,18),Vector2(0,9),Vector2(9,23),Vector2(15,19),Vector2(6,5),Vector2(20,2),Vector2(-12,-20)]),at,ink)
		"finish": _stroke(PackedVector2Array([Vector2(-19,0),Vector2(-5,14),Vector2(21,-15)]),at,ink)
		"add", "remove":
			draw_line(at+Vector2(-19,0),at+Vector2(19,0),ink,2.5,true)
			if id=="add":draw_line(at+Vector2(0,-19),at+Vector2(0,19),ink,2.5,true)
		"reverse":
			_stroke(PackedVector2Array([Vector2(-19,-7),Vector2(19,-7),Vector2(10,-16)]),at,ink)
			_stroke(PackedVector2Array([Vector2(19,7),Vector2(-19,7),Vector2(-10,16)]),at,ink)
		"undo", "redo", "back":
			var flip: float=-1 if id=="redo" else 1
			_stroke(PackedVector2Array([Vector2(-8,-17),Vector2(-21,-4),Vector2(8,-4),Vector2(18,3),Vector2(18,13),Vector2(8,20)])*Transform2D(Vector2(flip,0),Vector2(0,1),Vector2.ZERO),at,ink)
			_stroke(PackedVector2Array([Vector2(-21,-4),Vector2(-8,9)])*Transform2D(Vector2(flip,0),Vector2(0,1),Vector2.ZERO),at,ink)
