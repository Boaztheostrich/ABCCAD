extends Node3D
var checks := 0
var failures := 0
func key(v: Vector3) -> String: return "%.5f,%.5f,%.5f" % [v.x,v.y,v.z]
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error("COLLISION FAIL: " + label)
func _ready():
	for scene_name in ["cube","brick","wedge","m_cube","Corner_piece"]:
		var block = load("res://" + scene_name + ".tscn").instantiate()
		add_child(block)
		block.freeze = true
		var mesh_node = block.get_node("MeshInstance3D")
		var collision = block.get_node("CollisionShape3D2")
		var expected := {}
		var actual := {}
		for v in mesh_node.mesh.get_faces(): expected[key(mesh_node.transform * v)] = true
		for v in collision.shape.points: actual[key(collision.transform * v)] = true
		check(expected == actual, scene_name + " collision hull matches actual rendered vertices")
		await get_tree().physics_frame
		if scene_name == "m_cube":
			var query := PhysicsRayQueryParameters3D.create(Vector3(0.45,0,1),Vector3(0.45,0,-1),4)
			var hit = get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and hit.collider == block, "panel can be targeted near its visible edge")
		block.queue_free()
		await get_tree().process_frame
	print("COLLISION RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
