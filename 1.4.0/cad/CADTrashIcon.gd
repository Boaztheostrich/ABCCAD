extends Control
func _draw():
	var c:=size/2
	var color:=Color("77505a")
	draw_rect(Rect2(c+Vector2(-8,-5),Vector2(16,18)),color,false,2)
	draw_line(c+Vector2(-12,-9),c+Vector2(12,-9),color,2,true)
	draw_line(c+Vector2(-4,-13),c+Vector2(4,-13),color,2,true)
	for x in [-3,3]: draw_line(c+Vector2(x,-1),c+Vector2(x,9),color,2,true)
