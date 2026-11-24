## Preferences of the person using the editor (not of the map), kept in user://settings.cfg.[br]
## Things like the biome smoothing live here so turning them on/off never changes a saved map
class_name UserSettings extends RefCounted

const PATH: String = "user://settings.cfg"

static var _config: ConfigFile


static func get_value(section: String, key: String, default: Variant) -> Variant:
	_ensure_loaded()
	return _config.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	_ensure_loaded()
	_config.set_value(section, key, value)
	var error: Error = _config.save(PATH)
	if error != OK:
		push_warning("UserSettings - couldnt save %s: %s" % [PATH, error_string(error)])


static func _ensure_loaded() -> void:
	if _config != null:
		return
	_config = ConfigFile.new()
	if FileAccess.file_exists(PATH):
		_config.load(PATH) # a broken file just means defaults
