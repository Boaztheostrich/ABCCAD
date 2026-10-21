@tool
extends CollisionShape3D

# All current block shapes are convex. Use their actual mesh, including its
# local scale/orientation, so pickup and physics agree with what is visible.
func _ready():
	var mesh_instance := get_parent().get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var mesh_to_collision := transform.affine_inverse() * mesh_instance.transform
	var vertices := PackedVector3Array()
	for vertex in mesh_instance.mesh.get_faces():
		vertices.append(mesh_to_collision * vertex)
	var collision := ConvexPolygonShape3D.new()
	collision.points = vertices
	shape = collision
