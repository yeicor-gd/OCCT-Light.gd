@tool
class_name ShortcutPlanner
extends RefCounted

## Plans shortcut paths and obstacle placements across the track.
##
## Shortcuts are sub-paths that connect non-adjacent points on the main path
## using a "negative" profile (the inverse of the track cross-section) applied
## as a boolean subtraction — effectively tunnelling through the track walls.
##
## Obstacles are small solid shapes placed along the path to create
## navigational challenges (walls, gaps, tilting platforms, etc).
##
## Usage sketch (future):
##   var planner := ShortcutPlanner.new()
##   planner.add_shortcut("alpha", path_index_a, path_index_b, EntranceConfig.new())
##   planner.add_obstacle("wall_01", path_index, ObstacleConfig.new())
##   planner.build_all(graph, main_curve, profile_cfg)
##
## TODO: Implement the actual OCCT boolean operations (cut / fuse) between
##       the main track sweep and the shortcut negative-profile sweeps.
##       This requires extending TopoBuilders to handle multi-graph fusion.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Describes where a shortcut connects to the main path.
class ShortcutConfig:
	var label: String
	var entry_segment: int       # main-path segment where the shortcut begins
	var exit_segment: int        # main-path segment where the shortcut rejoins
	var clearance_scale: float = 1.2  # scale the negative profile by this much

	func _init(lbl: String, entry: int, exit: int, scale: float = 1.2):
		label = lbl
		entry_segment = entry
		exit_segment = exit
		clearance_scale = scale


## Describes one obstacle placed on the path.
class ObstacleConfig:
	var label: String
	var segment_index: int       # which segment the obstacle sits on
	var shape_type: int = 0      # 0=box, 1=sphere, 2=cylinder
	var size: Vector3 = Vector3(0.3, 0.3, 0.3)
	var offset: float = 0.5      # progress offset along the segment (0-1)

	func _init(lbl: String, segment: int, type: int = 0, sz: Vector3 = Vector3(0.3, 0.3, 0.3)):
		label = lbl
		segment_index = segment
		shape_type = type
		size = sz


# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var shortcuts: Array[ShortcutConfig] = []
var obstacles: Array[ObstacleConfig] = []


# -----------------------------------------------------------------------------
# Registration
# -----------------------------------------------------------------------------

func add_shortcut(cfg: ShortcutConfig):
	shortcuts.append(cfg)

func add_obstacle(cfg: ObstacleConfig):
	obstacles.append(cfg)

func clear():
	shortcuts.clear()
	obstacles.clear()


# -----------------------------------------------------------------------------
# Building (skeleton)
# -----------------------------------------------------------------------------

## Build all registered shortcuts and obstacles into the provided |graph|.
##
## TODO:
##   1. For each shortcut:
##      a. Build a sweep along a straight/curved path between entry and exit.
##      b. Use a "negative" profile (the inverse of the track cross-section).
##      c. Boolean-cut the negative sweep from the main track solid.
##   2. For each obstacle:
##      a. Create a primitive (box/sphere/cylinder) at the target position.
##      b. Boolean-fuse (or just place) it into the graph.
##   3. Ensure traversable connections between shortcut and main path don't
##      self-intersect (use the existing SegmentGraph data to check).
func build_all(graph: OclGraphHandle, path_curve: Curve3D, profile_cfg: ProfileBuilder.Config) -> OclGraphHandle:
	if shortcuts.is_empty() and obstacles.is_empty():
		return graph

	push_warning("ShortcutPlanner.build_all is not yet implemented. ",
		"Found ", shortcuts.size(), " shortcut(s) and ", obstacles.size(), " obstacle(s) to build.")
	return graph
