## Opens a save in the real editor and writes a screenshot, used to compare old saves before/after a change.[br]
## Only uses editor APIs that existed in Alpha 0.3, so it can run on older checkouts too:[br]
## [code]SNAPSHOT_MAP=/path/map.json SNAPSHOT_OUT=/path/shot.png godot --path . res://tests/e2e_load_snapshot.tscn[/code]
extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var editor: Node = load("res://scenes/ui/hex_map_editor/hex_map_editor.tscn").instantiate()
	viewport.add_child(editor)
	for _i: int in 5:
		await get_tree().process_frame

	editor.get_node("MapDataManager").load_map_into_editor(OS.get_environment("SNAPSHOT_MAP"))
	for _i: int in 4:
		await get_tree().physics_frame

	# frame the whole map
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for tilemap: Node in editor.get_node("LayersTilemaps").get_children():
		if tilemap is TileMapLayer and tilemap.tile_set != null:
			for cell: Vector2i in tilemap.get_used_cells():
				var point: Vector2 = tilemap.to_global(tilemap.map_to_local(cell))
				bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
				first = false
	var camera: Camera2D = editor.get_node("Camera2D")
	camera.global_position = bounds.get_center()
	var fit: float = minf(1300.0 / maxf(bounds.size.x, 1.0), 700.0 / maxf(bounds.size.y, 1.0))
	camera.zoom = Vector2.ONE * clampf(fit, 0.3, 4.0)
	for _i: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OS.get_environment("SNAPSHOT_OUT"))
	get_tree().quit()
