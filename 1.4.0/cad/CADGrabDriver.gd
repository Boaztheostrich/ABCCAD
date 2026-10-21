extends XRToolsGrabDriver
## CAD parts use a rigid grab pose. XRTools hands inherit XR world scale,
## which must never resize a CAD body or multiply a precise grab offset.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(primary): return
	var hand_pose:=primary.by.global_transform
	hand_pose.basis=hand_pose.basis.orthonormalized()
	var destination:=hand_pose*primary.transform.affine_inverse()
	if state==GrabState.LERP:
		lerp_time+=delta
		if lerp_time<lerp_duration:
			destination=lerp_start.interpolate_with(destination,lerp_time/lerp_duration)
		else:
			state=GrabState.SNAP
			_update_weight()
			primary.set_arrived()
	global_transform=destination
	force_update_transform()
	if is_instance_valid(target): target.force_update_transform()
