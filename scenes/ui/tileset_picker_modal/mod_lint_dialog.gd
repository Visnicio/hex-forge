## Table of what a tileset mod provides for roads, rivers and the biome smoothing, and the fallback used for the rest
## (see [ModLint]). Opened from the tileset picker
class_name ModLintDialog extends AcceptDialog

const STATUS_TEXT: Dictionary = {ModLint.OK: "OK", ModLint.FALLBACK: "Fallback", ModLint.ERROR: "Problem"}
const STATUS_COLOR: Dictionary = {ModLint.OK: Color(0.45, 0.85, 0.5), ModLint.FALLBACK: Color(0.95, 0.8, 0.35), ModLint.ERROR: Color(1.0, 0.4, 0.35)}

var _tree: Tree


func _init() -> void:
	title = "Mod check"
	min_size = Vector2i(820, 420)
	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.set_column_title(0, "Feature")
	_tree.set_column_title(1, "Status")
	_tree.set_column_title(2, "Details / fallback")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 230)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 90)
	add_child(_tree)


func show_for(config: MapTilesetConfiguration) -> void:
	title = "Mod check - " + (config.tileset_name if config else "?")
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for row: Dictionary in ModLint.inspect(config):
		var item: TreeItem = _tree.create_item(root)
		item.set_text(0, row.feature)
		item.set_text(1, STATUS_TEXT[row.status])
		item.set_custom_color(1, STATUS_COLOR[row.status])
		item.set_text(2, row.detail)
		item.set_tooltip_text(2, row.detail)
	popup_centered()
