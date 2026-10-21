extends Control
var progress:=0.0:
	set(value):
		progress=value
		queue_redraw()
func _draw():
	var center:=size*0.5
	var radius:=minf(size.x,size.y)*0.5-8
	draw_arc(center,radius,0,TAU,64,Color("dce4ef"),6,true)
	if progress>0: draw_arc(center,radius,-PI/2,-PI/2+TAU*clampf(progress,0.001,1),64,Color("347dda"),6,true)
