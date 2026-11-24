## Interface of something that draws a [PathData] (vector lines now, the mod tiles in phase 2).[br]
## The path data never knows which renderer draws it, so the same map can switch between them
class_name PathRenderer extends RefCounted


## Builds the visuals of the path (added by the caller under the paths layer), or [code]null[/code] if it draws nothing
func build(_path: PathData, _geometry: HexGeometry, _seed: int) -> Node2D:
	return null


## Centerline of the path as drawn, in tilemap local space. Used for bridges and for clicking on paths
func centerline(_path: PathData, _geometry: HexGeometry, _seed: int) -> PackedVector2Array:
	return PackedVector2Array()
