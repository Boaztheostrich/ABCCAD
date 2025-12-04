@tool
extends CollisionShape3D

func _ready():
	shape = _create_collision_shape()

func _create_collision_shape() -> ConvexPolygonShape3D:
	var size = 0.05
	
	var points = PackedVector3Array([
		Vector3(-size, -size, -size),  # corner
		Vector3(size, -size, -size),   # +X
		Vector3(-size, size, -size),   # +Y
		Vector3(-size, -size, size)    # +Z
	])
	
	var collision = ConvexPolygonShape3D.new()
	collision.points = points
	return collision
