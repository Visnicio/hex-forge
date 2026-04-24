# An Actual Useful Hex Mapper

A hex tile map editor built in **Godot 4.6**, focused on being genuinely usable for tabletop/worldbuilding maps. Supports multiple painting layers, undo/redo, save/load, and runtime tileset mods via `.pck` files.

**Status:** Alpha 0.3

---

## Features

- **Hex tilemap painting** — left-click to paint, right-click to erase, with stroke-based undo/redo (`Ctrl+Z` / `Ctrl+Shift+Z`)
- **Multiple layers** — add, reorder, and rename layers; each layer has its own `TileMapLayer`
- **Tileset picker** — choose from built-in sample tilesets or any mod installed by the user
- **Save / Load** — maps are serialized to JSON files (`Ctrl+S` / `Ctrl+O`)
- **World markers** — place annotation markers on the map
- **Modding support** — drop a `.pck` file into `user://tilesets/` to add custom tilesets at runtime
- **Camera controls** — pan (WASD), zoom (scroll wheel), rush mode (Shift)
- **Hide UI** — press `H` to toggle the interface for a clean view

---

## Getting Started

### Prerequisites

- [Godot 4.6](https://godotengine.org/download) (standard, not .NET)

### Running from the editor

1. Clone or download this repository.
2. Open Godot and import the project by pointing it to the root folder (where `project.godot` lives).
3. Press **F5** (or the Play button) to run.

### Running an exported build

Download the latest export from the releases page and run the executable directly. No installation required.

---

## How to Use

| Action | Input |
|---|---|
| Paint tile | Left-click / drag |
| Erase tile | Right-click / drag |
| Undo | `Ctrl+Z` |
| Redo | `Ctrl+Shift+Z` |
| Save map | `Ctrl+S` |
| Open map | `Ctrl+O` |
| Pan camera | `W A S D` |
| Zoom | Scroll wheel |
| Rush pan | Hold `Shift` |
| Hide UI | `H` |
| Deselect pencil | `Escape` |

1. **Pick a tileset** — click the tileset button and choose one from the dropdown.
2. **Select a layer** — click a layer in the layers panel on the right. The selected layer receives all paint strokes.
3. **Pick a tile** — click any tile in the tile palette on the left.
4. **Paint** — click or drag on the map.
5. **Save** — `Ctrl+S`, choose a location, done.

---

## Modding — Adding Custom Tilesets

The editor loads tileset mods from `user://tilesets/` at startup. On most systems this folder is:

| OS | Path |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\an_actual_useful_hex_mapper\tilesets\` |
| Linux | `~/.local/share/godot/app_userdata/an_actual_useful_hex_mapper/tilesets\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/an_actual_useful_hex_mapper/tilesets\` |

### Creating a mod

A mod is a Godot `.pck` file that follows this structure:

```
my_tileset/                  ← root folder, same name as the .pck file
└── mod_info.tres            ← ModInfoResource (required)
└── tileset.tres             ← your TileSet resource
└── tileset_config.tres      ← MapTilesetConfiguration resource
└── ... (any other assets)
```

**`mod_info.tres`** must be a `ModInfoResource` with:
- `author` — your name
- `mod_name` — display name
- `mod_configuration` — a reference to your `MapTilesetConfiguration` resource

**`MapTilesetConfiguration`** fields:
- `tileset_name` — the name shown in the tileset picker dropdown (must be unique)
- `tileset_resource` — reference to your `TileSet` resource
- `tilemap_scale` — how much the tiles are scaled on the map (e.g. `0.2` for high-resolution tilesets)

> **Important:** the `.pck` filename and its root folder **must share the same name**. The loader uses the filename to find `res://<mod_name>/mod_info.tres` after unpacking.

Export the project as a `.pck` file in Godot (`Project → Export → Export PCK/ZIP`), drop it into the tilesets folder, and restart the editor.

---

## Project Architecture

```
project root
├── autload/                        # SaveManager, SignalBus (autoloads)
├── scripts/
│   ├── autloads/                   # GlobalEditorData, ModLoader (autoloads)
│   └── utils.gd                   # JSON helpers, modal factory
├── resources/
│   ├── definitions/               # Resource class definitions
│   │   ├── tilesets/              # MapTilesetConfiguration
│   │   └── modding/               # ModInfoResource
│   ├── shaders/                   # Canvas item shaders
│   └── tilesets/                  # Built-in TileSet resources
├── samples/                       # Built-in MapTilesetConfiguration samples
├── scenes/
│   ├── entities/                  # WorldMarker, MarkerPreview
│   └── ui/
│       ├── hex_map_editor/        # Main editor controller + camera + save logic
│       ├── tileset_picker_modal/  # Tileset selection dropdown
│       ├── user_layers/           # Layer list manager
│       ├── user_layer/            # Individual layer UI item
│       ├── input_modal/           # Generic text input dialog
│       └── controls_and_info_modal/
└── assets/                        # Graphics and icons
```

### Key autoloads

| Name | File | Role |
|---|---|---|
| `ModLoader` | `scripts/autloads/mod_loader.gd` | Creates `user://tilesets/`, loads `.pck` mods at startup |
| `GlobalEditorData` | `scripts/autloads/global_editor_data.gd` | Shared references (`HexMapEditor`, `UserLayers`, etc.) |
| `SaveManager` | `autload/save_manager.gd` | JSON map save/load |
| `SignalBus` | `autload/signal_bus.gd` | Decoupled event signals |

### Data flow for mods

```
startup
  └─ ModLoader._ready()
       ├─ ensures user://tilesets/ exists
       └─ for each .pck → ProjectSettings.load_resource_pack()
                        → load res://<mod>/mod_info.tres
                        → store MapTilesetConfiguration in mod_tilesets{}

TileSetPickerModal._ready()
  ├─ load_samples_tilesets()   ← reads res://samples/
  └─ get_mods_tilesets()       ← merges ModLoader.mod_tilesets (mods override same-named samples)
```

---

## Roadmap

- [ ] Stamps (place pre-composed tile groups)
- [ ] Export to image (A4 format)
- [ ] Clickable tiles (attach notes or data to individual cells)
- [ ] Inkarnate-style freehand drawing (requires shader work)

---

## Known Issues / TODOs

These are tracked directly in the source code:

### Scale sync reads `pencil_tilemap.scale` directly
**File:** [`scripts/autloads/global_editor_data.gd:27`](scripts/autloads/global_editor_data.gd#L27)

`_sync_tileset_data_between_layers()` reads `map_editor_ref.pencil_tilemap.scale` to sync every layer's scale on each physics tick. This creates a tight coupling between the global state manager and an implementation detail of `HexMapEditor`. The proper fix is to call `HexMapEditor._update_tilesets_scales()` (or an equivalent signal) so that scale changes are pushed explicitly rather than polled.

### `layers_tilemaps_holder` set via hardcoded node path
**File:** [`scenes/ui/hex_map_editor/hex_map_editor.gd:49`](scenes/ui/hex_map_editor/hex_map_editor.gd#L49)

`GlobalEditorData.layers_tilemaps_holder` is set with `get_node_or_null("LayersTilemaps")`, hardcoding a scene-tree path. This is fragile if the node is ever renamed or moved. Ideal fix: self-register from `LayersTilemaps` itself (similar to how `UserLayers` registers in its own `_ready`), or expose it as an `@export` on `HexMapEditor`.

### New layer tileset assignment reads global state directly
**File:** [`scenes/ui/user_layers/user_layers.gd:30`](scenes/ui/user_layers/user_layers.gd#L30)

When a new layer is created, it pulls the active tileset from `GlobalEditorData.map_editor_ref.current_tileset`. This bypasses the event system and was a workaround for a timing issue. The clean solution would be to connect `TileSetPickerModal.config_changed` (or a derived signal on `GlobalEditorData`) so new layers receive the tileset via signal rather than a direct read.

---

## Good First Issues

Low-scope improvements suitable for a first contribution:

- **Translate remaining Portuguese comments** — a few inline comments in older files are still in Portuguese. Find them with `grep -rn "[àáâãéêíóôõúüç]" --include="*.gd"` and translate to English.
- **Fix the typo in the `autload/` folder name** — it should be `autoload/`. Requires renaming the folder and updating the paths in `project.godot` and any `preload`/`load` calls that reference it.
- **Remove stray `print` / `print_debug` calls** — several debug prints were left in production paths (e.g. `mod_loader.gd`, `tileset_picker_modal.gd`). Replace with proper logging or remove them.
- **Guard against `null` in `_erase_at_mouse`** — unlike `_paint_at_mouse`, `_erase_at_mouse` in `hex_map_editor.gd` does not check whether `current_selected_layer` is `null` before use, which can crash if no layer is selected.
- **`add_new_layer` default name collision** — clicking "Add Layer" always creates a layer named `"New Layer"`. If the user clicks it twice, two layers share the same name and the same `TileMapLayer` node name (deduplicated by Godot with a suffix, but the display name in the UI stays identical). Add a counter suffix to make names unique.
- **`MapTilesetConfiguration.tilemap_scale` typo in comment** — the comment on that property reads `"how much the tiles will eb scaled"` (`eb` → `be`).
