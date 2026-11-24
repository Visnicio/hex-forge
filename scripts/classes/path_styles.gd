## Registry of the [PathStyle]s the editor knows about.[br]
## Built-in styles are preloaded (listing res:// at runtime is unreliable in exported builds).
## Mods will be able to add theirs later (phase 2), unknown ids always fall back to the default of the kind
class_name PathStyles extends RefCounted

const BUILTIN_STYLES: Array[PathStyle] = [
	preload("res://resources/paths/styles/road.tres"),
	preload("res://resources/paths/styles/trail.tres"),
	preload("res://resources/paths/styles/river.tres"),
	preload("res://resources/paths/styles/stream.tres"),
]

static var _extra_styles: Array[PathStyle] = []


static func default_style_id(kind: PathData.Kind) -> String:
	return "builtin:river" if kind == PathData.Kind.RIVER else "builtin:road"


## Style for the path, falling back to the default of its kind when the id is unknown
## (e.g. the map was made with a mod that isnt installed)
static func resolve(style_id: String, kind: PathData.Kind) -> PathStyle:
	for style: PathStyle in all_styles():
		if style.id == style_id:
			return style
	for style: PathStyle in all_styles():
		if style.id == default_style_id(kind):
			return style
	return BUILTIN_STYLES[0]


static func styles_for(kind: PathData.Kind) -> Array[PathStyle]:
	var kind_name: String = PathData.KIND_NAMES[kind]
	var result: Array[PathStyle] = []
	for style: PathStyle in all_styles():
		if style.kind == kind_name or style.kind == "any":
			result.append(style)
	return result


static func all_styles() -> Array[PathStyle]:
	var result: Array[PathStyle] = BUILTIN_STYLES.duplicate()
	result.append_array(_extra_styles)
	return result


## Replaces the styles that came from the current tileset/mod
static func set_extra_styles(styles: Array[PathStyle]) -> void:
	_extra_styles = styles.duplicate()
