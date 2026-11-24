## Versioning of the map save format.[br]
## [code]manifest_version[/code] in the save is the APP version (e.g. "Alpha 0.3"), this is the FORMAT version,
## so the app can change version without touching the format and vice versa.[br]
## Saves without [code]format_version[/code] are format 1 (everything saved up to Alpha 0.3).[br]
## Each step only upgrades from N to N+1, so loading a very old save just runs every step in order
class_name MapMigrations extends RefCounted

## Format written by this build
const CURRENT_FORMAT_VERSION: int = 2


## Returns a copy of the raw save dictionary upgraded to [constant CURRENT_FORMAT_VERSION].[br]
## A save from a newer build is returned as is (whatever this build knows is still loaded)
static func migrate(raw: Dictionary) -> Dictionary:
	var dict: Dictionary = raw.duplicate()
	var version: int = get_format_version(dict)

	if version > CURRENT_FORMAT_VERSION:
		push_warning("MapMigrations - save format %d is newer than this build (%d), data from newer features may be lost if saved again" % [version, CURRENT_FORMAT_VERSION])
		return dict

	if version < 2:
		dict = _v1_to_v2(dict)

	return dict


static func get_format_version(dict: Dictionary) -> int:
	return int(dict.get("format_version", 1))


## Format 2: adds roads/rivers ("paths") and their map settings ("path_settings")
static func _v1_to_v2(dict: Dictionary) -> Dictionary:
	if not dict.get("paths") is Dictionary:
		dict["paths"] = {}
	if not dict.get("path_settings") is Dictionary:
		dict["path_settings"] = {}
	dict["format_version"] = 2
	return dict
