extends MeshInstance3D
## Offset only the translucent presentation surface. CAD/ray planes stay exact.
var logical_pose:=Transform3D.IDENTITY
var camera: Node3D
func _process(_delta):
	update_depth_bias()
func update_depth_bias():
	if not is_instance_valid(camera): return
	var parent_pose: Transform3D=get_parent().global_transform
	var world_pose:=parent_pose*logical_pose
	var normal:=world_pose.basis.z.normalized()
	var side:=1.0 if normal.dot(camera.global_position-world_pose.origin)>=0 else -1.0
	var offset:=normal*(-side*0.0007*XRServer.world_scale)
	transform=logical_pose
	position+=parent_pose.basis.inverse()*offset
