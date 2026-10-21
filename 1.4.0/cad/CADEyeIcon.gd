extends Control
var shown:=true
func _draw():
	var center:=size/2
	var outline:=PackedVector2Array()
	for i in 25:
		var angle:=TAU*i/24
		outline.append(center+Vector2(cos(angle)*13,sin(angle)*8))
	draw_polyline(outline,Color("354c64"),2,true)
	draw_circle(center,4,Color("354c64"))
	if not shown: draw_line(center+Vector2(-15,12),center+Vector2(15,-12),Color("354c64"),3,true)
