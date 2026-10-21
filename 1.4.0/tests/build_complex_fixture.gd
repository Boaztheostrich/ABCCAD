extends Node3D
func vector(v: Vector3) -> Array:
	return [snappedf(v.x,0.0001),snappedf(v.y,0.0001),snappedf(v.z,0.0001)]
func rotation(b: Basis) -> Array:
	return vector(b.x) + vector(b.y) + vector(b.z)
var expected := []
var faces := []
var distribution := {}
func add_piece(type_name: String, position: Vector3, basis: Basis, color: Color):
	var block = load("res://" + type_name + ".tscn").instantiate()
	block.top_level = true
	add_child(block)
	block.freeze = true
	var shape := "corner_wedge" if type_name == "Corner_piece" else type_name
	block.set_meta("shape_type",shape)
	block.global_transform = Transform3D(basis,position)
	var mesh_node = block.get_node("MeshInstance3D")
	mesh_node.set_color(color)
	BlockInteractions.connect_block(block)
	block.get_node("VoxelLogic")._on_dropped(block)
	assert(not block.is_queued_for_deletion(),"Fixture overlaps: " + shape + " at " + str(position))
	var html: String = mesh_node.get_color().to_html()
	expected.append([shape,vector(block.global_position),html,rotation(block.global_basis)])
	distribution[shape] = distribution.get(shape,[]) + [html]
	for v in mesh_node.mesh.get_faces(): faces.append(vector(mesh_node.global_transform * v))
func _ready():
	var directory := OS.get_environment("ABCCAD_FIXTURE_DIR")
	if directory.is_empty(): directory = "res://tests/fixtures"
	DirAccess.make_dir_recursive_absolute(directory)
	var save_system = load("res://SaveSystem.gd").new()
	save_system.save_directory = directory
	add_child(save_system)
	var exporter = load("res://VoxelExporter.gd").new()
	add_child(exporter)
	var types := ["m_cube","cube","brick","wedge","Corner_piece"]
	var colors := [Color.BLUE,Color.RED,Color.GREEN,Color.YELLOW,Color.REBECCA_PURPLE,Color.PINK,Color(0,0.7,0.9)]
	for type_index in types.size():
		var type_name: String = types[type_index]
		for i in 3:
			var position := Vector3.ZERO
			var basis := Basis.IDENTITY
			match type_name:
				"m_cube":
					position = Vector3((i - 1) * 1.1,0.1,-1.0)
					basis = Basis(Vector3.RIGHT,PI/2)
				"cube": position = Vector3(-1.5 + i * 0.1,0.2,-1.3)
				"brick":
					position = Vector3(1.05 + i * 0.2,0.2,-1.2)
				"wedge":
					position = Vector3(-0.4 + i * 0.4,0.2,-0.8)
					basis = Basis(Vector3.UP,i * PI/2)
				"Corner_piece":
					position = Vector3(-0.5 + i * 0.5,0.2,-1.3)
					basis = Basis(Vector3.UP,i * PI/2) * Basis(Vector3.RIGHT,PI/2 if i == 1 else 0)
			add_piece(type_name,position,basis,colors[(type_index + i) % colors.size()])
	# Colored support pillars, a continuous brick deck, and alternating caps.
	for pillar in 4:
		for level in 5:
			add_piece("cube",Vector3(-1.2 + pillar * 0.8,0.2 + level * 0.1,-1.0),Basis.IDENTITY,colors[(pillar + level) % colors.size()])
	for i in 13:
		add_piece("brick",Vector3(-1.25 + i * 0.2,0.7,-1.0),Basis.IDENTITY,colors[i % colors.size()])
	for i in 5:
		add_piece("wedge",Vector3(-1.2 + i * 0.6,0.8,-0.9),Basis(Vector3.UP,(i % 4) * PI/2),colors[(i + 2) % colors.size()])
		add_piece("Corner_piece",Vector3(-1.2 + i * 0.6,0.8,-1.1),Basis(Vector3.UP,(i % 4) * PI/2),colors[(i + 4) % colors.size()])
	save_system._save_game("complex-all-blocks")
	var metadata := {"filename":"complex-all-blocks.json","geometry":expected,"voxels":VoxelDatabase.voxel_grid.size(),"distribution":distribution,"export_faces":faces}
	var file := FileAccess.open(directory.path_join("complex-all-blocks.expected.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	file.close()
	var result = STLIO.Exporter.SaveToPath(exporter.build_export_mesh(),directory.path_join("complex-all-blocks.stl"))
	assert(result == OK)
	print("COMPLEX FIXTURE: %d objects, %d cells; five types, multiple colors each" % [expected.size(),VoxelDatabase.voxel_grid.size()])
	get_tree().quit()
