extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for index in 10:
		await physics_frame
	var counts := {}
	_tally(main, counts)
	var rows := []
	for key in counts:
		rows.append([counts[key], key])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("DRAW_TALLY total_meshes=", _sum(counts))
	for row in rows.slice(0, 22):
		print("  ", row[1], " = ", row[0])
	quit(0)
func _sum(counts: Dictionary) -> int:
	var total := 0
	for key in counts:
		total += int(counts[key])
	return total
func _tally(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		var path := String(node.name).split("_")[0]
		var parent := node.get_parent()
		if parent != null:
			path = ("%s/%s" % [String(parent.name).split("_")[0], path]).split("/")[0]
		counts[path] = int(counts.get(path, 0)) + 1
	for child in node.get_children():
		_tally(child, counts)
