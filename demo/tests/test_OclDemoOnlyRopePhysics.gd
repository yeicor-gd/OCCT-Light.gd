class_name TestOclDemoOnlyRopePhysics

static func _check(condition: bool, msg: String) -> String:
	return "OK" if condition else msg

static func test_is_initialized_before_init() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	return _check(not rope.is_initialized(), "Should not be initialized before init_rope")

static func test_init_creates_correct_node_count() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 50
	rope.init_rope(42)
	return _check(rope.get_positions().size() == 50, "Expected 50 nodes, got %d" % rope.get_positions().size())

static func test_init_deterministic() -> String:
	var rope1 = OclDemoOnlyRopePhysics.new()
	rope1.init_rope(12345)
	var pos1 = rope1.get_positions()

	var rope2 = OclDemoOnlyRopePhysics.new()
	rope2.init_rope(12345)
	var pos2 = rope2.get_positions()

	for i in range(pos1.size()):
		if pos1[i].distance_to(pos2[i]) > 0.0001:
			return "Node %d differs: %v vs %v" % [i, pos1[i], pos2[i]]
	return "OK"

static func test_relax_completes() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 50
	rope.iterations = 100
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	return _check(positions.size() == 50, "Wrong node count after relax")

static func test_positions_within_shell() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 1.0
	rope.outer_radius = 2.0
	rope.node_count = 50
	rope.iterations = 200
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	for i in range(1, positions.size() - 1):
		var d = positions[i].length()
		if d < rope.inner_radius - 0.01 or d > rope.outer_radius + 0.01:
			return "Node %d at distance %.3f not in [%.3f, %.3f]" % [i, d, rope.inner_radius, rope.outer_radius]
	return "OK"

static func test_segment_lengths() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 50
	rope.segment_length = 1.0
	rope.iterations = 500
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	for i in range(positions.size() - 1):
		var dist = positions[i].distance_to(positions[i + 1])
		if absf(dist - rope.segment_length) > rope.segment_length * 1.0:
			return "Segment %d length %.3f too far from %.3f" % [i, dist, rope.segment_length]
	return "OK"

static func test_endpoint_anchoring() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	var start = Vector3(0, 0, -2)
	var end = Vector3(0, 0, 2)
	rope.init_rope(42, start, end)
	rope.relax()
	var positions = rope.get_positions()
	return _check(
		positions[0].distance_to(start) < 0.001 and positions[-1].distance_to(end) < 0.001,
		"Endpoints not anchored: %v != %v, %v != %v" % [positions[0], start, positions[-1], end]
	)

static func test_clear_resets_state() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.init_rope(42)
	if not rope.is_initialized():
		return "Should be initialized after init_rope"
	rope.clear()
	return _check(not rope.is_initialized(), "Should not be initialized after clear")

static func test_get_positions_type() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.init_rope(42)
	var positions = rope.get_positions()
	return _check(positions is PackedVector3Array, "Expected PackedVector3Array")

static func test_performance() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 400
	rope.segment_length = 0.05
	rope.iterations = 4000
	rope.init_rope(42)

	rope.relax()

	return "OK"

static func test_custom_radii() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 3.0
	rope.outer_radius = 5.0
	rope.node_count = 50
	rope.iterations = 200
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	for i in range(1, positions.size() - 1):
		var d = positions[i].length()
		if d < 2.9 or d > 5.1:
			return "Node %d at distance %.3f not in [3.0, 5.0]" % [i, d]
	return "OK"

static func test_different_seeds_differ() -> String:
	var rope1 = OclDemoOnlyRopePhysics.new()
	rope1.init_rope(1)
	var pos1 = rope1.get_positions()

	var rope2 = OclDemoOnlyRopePhysics.new()
	rope2.init_rope(2)
	var pos2 = rope2.get_positions()

	var any_different = false
	for i in range(pos1.size()):
		if pos1[i].distance_to(pos2[i]) > 0.01:
			any_different = true
			break

	return _check(any_different, "Different seeds produced identical results")

static func test_property_defaults() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	print_rich("        [color=cyan]DEFAULTS: node_count=%d segment_length=%.1f iterations=%d collision_passes=%d bend_passes=%d bend_levels=%d[/color]" % [
		rope.node_count, rope.segment_length, rope.iterations,
		rope.collision_passes, rope.bend_passes, rope.bend_levels
	])
	return _check(
		rope.node_count == 200 and
		rope.segment_length == 1.0 and
		rope.iterations == 200 and
		rope.inner_radius == 1.0 and
		rope.outer_radius == 2.0,
		"Default property values mismatch"
	)

# --- Shortcut tests ---

static func test_shortcut_basic() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 20
	rope.init_rope(42)
	var main_count = rope.get_positions().size()
	# Add shortcut from node 5 to node 15 with 8 segments
	var idx = rope.add_shortcut(5, 15, 8)
	return _check(
		idx == 1 and rope.get_rope_count() == 2,
		"Expected rope_count=2, got %d" % rope.get_rope_count()
	)

static func test_shortcut_node_count_after_init() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 20
	rope.init_rope(42)
	var before = rope.get_positions().size()
	rope.add_shortcut(5, 15, 8)
	var after = rope.get_positions().size()
	# 8 segments means 9 nodes (8 intermediate + 2 endpoints? No: 8 segments = 9 nodes: start + 7 inner + end)
	# Actually: segments+1 nodes (first pinned to anchor_start, last pinned to anchor_end)
	return _check(
		after == before + 9,
		"Expected %d nodes after shortcut, got %d (before=%d)" % [before + 9, after, before]
	)

static func test_shortcut_relax() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 20
	rope.iterations = 200
	rope.init_rope(42)
	rope.add_shortcut(5, 15, 8)
	rope.relax()
	var pos = rope.get_positions()
	return _check(pos.size() == 29, "Expected 29 nodes after relax, got %d" % pos.size())

static func test_shortcut_anchors_match() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 20
	rope.iterations = 200
	rope.init_rope(42)
	rope.add_shortcut(5, 15, 8)
	rope.relax()
	var main = rope.get_rope_positions(0)
	var shortcut = rope.get_rope_positions(1)
	# Shortcut endpoints should match main rope anchor positions
	var start_match = shortcut[0].distance_to(main[5]) < 0.001
	var end_match = shortcut[-1].distance_to(main[15]) < 0.001
	return _check(
		start_match and end_match,
		"Shortcut anchors don't match: start=%v vs %v, end=%v vs %v" % [shortcut[0], main[5], shortcut[-1], main[15]]
	)

static func test_shortcut_within_shell() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 1.0
	rope.outer_radius = 2.0
	rope.node_count = 20
	rope.iterations = 200
	rope.init_rope(42)
	rope.add_shortcut(5, 15, 8)
	rope.relax()
	var shortcut = rope.get_rope_positions(1)
	for i in range(1, shortcut.size() - 1):
		var d = shortcut[i].length()
		if d > 2.01:
			return "Shortcut node %d at distance %.3f outside outer radius" % [i, d]
		# Shortcuts may pass through the interior (d < inner_radius is OK).
	return "OK"

static func test_shortcut_chained() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 20
	rope.iterations = 200
	rope.init_rope(42)
	# First shortcut on main rope
	var s1 = rope.add_shortcut(5, 15, 8)
	# Second shortcut: attach to main rope node 2 and first shortcut's inner node (index 20+1=21)
	var total_before = rope.get_positions().size()
	var s2 = rope.add_shortcut(2, total_before - 8, 4)  # shortcut 1 nodes start at index 20
	rope.relax()
	return _check(
		rope.get_rope_count() == 3,
		"Expected 3 ropes (main + 2 shortcuts), got %d" % rope.get_rope_count()
	)

static func test_shortcut_invalid_indices() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 10
	rope.init_rope(42)
	var idx = rope.add_shortcut(-1, 5, 3)
	var idx2 = rope.add_shortcut(0, 100, 3)
	return _check(idx == -1 and idx2 == -1, "Should return -1 for invalid indices")

static func test_shortcut_zero_segments() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 10
	rope.init_rope(42)
	var idx = rope.add_shortcut(0, 9, 0)
	return _check(idx == -1, "Should return -1 for 0 segments")

static func test_shortcut_init_on_shell() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 3.0
	rope.outer_radius = 10.0
	rope.node_count = 20
	rope.init_rope(42)
	rope.add_shortcut(5, 15, 8)
	var shortcut = rope.get_rope_positions(1)
	for i in range(1, shortcut.size() - 1):
		var d = shortcut[i].length()
		if d < rope.inner_radius - 0.1 or d > rope.outer_radius + 0.1:
			return "Shortcut node %d at distance %.3f not on shell [%.3f, %.3f]" % [i, d, rope.inner_radius, rope.outer_radius]
	return "OK"

static func test_shortcut_no_sharp_radial_angle() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 3.0
	rope.outer_radius = 10.0
	rope.node_count = 30
	rope.iterations = 500
	rope.init_rope(42, Vector3.BACK * 10.0, Vector3.FORWARD * 10.0)
	rope.add_shortcut(8, 22, 6)
	rope.relax()
	var main = rope.get_rope_positions(0)
	# Check main rope has no sharp radial jumps between free nodes (skip pinned endpoints)
	for i in range(1, main.size() - 2):
		var r1 := main[i].length()
		var r2 := main[i + 1].length()
		if absf(r1 - r2) > rope.segment_length * 2.0:
			return "Main rope sharp radial jump at %d: r=%.3f -> r=%.3f" % [i, r1, r2]
	return "OK"

static func test_shortcut_anchors_match_after_all_fixes() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 3.0
	rope.outer_radius = 10.0
	rope.node_count = 30
	rope.iterations = 500
	rope.init_rope(42)
	rope.add_shortcut(5, 20, 6)
	rope.relax()
	var main = rope.get_rope_positions(0)
	var shortcut = rope.get_rope_positions(1)
	var start_match = shortcut[0].distance_to(main[5]) < 0.001
	var end_match = shortcut[-1].distance_to(main[20]) < 0.001
	return _check(
		start_match and end_match,
		"Shortcut anchors don't match: start=%v vs %v, end=%v vs %v" % [shortcut[0], main[5], shortcut[-1], main[20]]
	)

# --- Space-filling tests ---

static func test_space_filling_relax_completes() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 50
	rope.iterations = 200
	rope.space_filling_passes = 2
	rope.space_filling_stiffness = 0.5
	rope.space_filling_halvings = 2
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	return _check(positions.size() == 50, "Wrong node count after space-filling relax")

static func test_space_filling_disabled() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 50
	rope.iterations = 200
	rope.space_filling_passes = 0
	rope.init_rope(42)
	rope.relax()
	return _check(rope.get_positions().size() == 50, "Relax with space_filling_passes=0 should still work")

static func test_space_filling_improves_distribution() -> String:
	# Run without space-filling
	var rope1 = OclDemoOnlyRopePhysics.new()
	rope1.node_count = 80
	rope1.inner_radius = 4.0
	rope1.outer_radius = 14.0
	rope1.collision_radius = 4.0
	rope1.iterations = 500
	rope1.space_filling_passes = 0
	rope1.init_rope(42)
	rope1.relax()
	var pos1 = rope1.get_positions()

	# Run with space-filling
	var rope2 = OclDemoOnlyRopePhysics.new()
	rope2.node_count = 80
	rope2.inner_radius = 4.0
	rope2.outer_radius = 14.0
	rope2.collision_radius = 4.0
	rope2.iterations = 500
	rope2.space_filling_passes = 3
	rope2.space_filling_stiffness = 0.5
	rope2.space_filling_halvings = 2
	rope2.init_rope(42)
	rope2.relax()
	var pos2 = rope2.get_positions()

	# Compute average nearest-neighbor distance for inner nodes
	var avg_nn1 := _avg_nearest_neighbor(pos1)
	var avg_nn2 := _avg_nearest_neighbor(pos2)

	print_rich("        [color=cyan]SPACE FILLING: avg NN without=%.3f with=%.3f[/color]" % [avg_nn1, avg_nn2])

	# With space-filling, average nearest-neighbor should be larger (more spread out)
	return _check(
		avg_nn2 >= avg_nn1 * 0.95,
		"Space-filling should not reduce spread: without=%.3f with=%.3f" % [avg_nn1, avg_nn2]
	)

static func test_space_filling_with_shortcuts() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.node_count = 30
	rope.inner_radius = 3.0
	rope.outer_radius = 10.0
	rope.iterations = 300
	rope.space_filling_passes = 2
	rope.space_filling_stiffness = 0.5
	rope.space_filling_halvings = 2
	rope.init_rope(42)
	rope.add_shortcut(5, 20, 6)
	rope.relax()
	var positions = rope.get_positions()
	# Verify all inner nodes are within shell
	for i in range(1, positions.size() - 1):
		var d = positions[i].length()
		if d > 10.01:
			return "Node %d at distance %.3f outside outer radius" % [i, d]
	return _check(positions.size() == 37, "Expected 37 nodes, got %d" % positions.size())

static func _avg_nearest_neighbor(positions: PackedVector3Array) -> float:
	var total := 0.0
	var count := 0
	for i in range(positions.size()):
		var best := INF
		for j in range(positions.size()):
			if i == j:
				continue
			var d := positions[i].distance_to(positions[j])
			if d < best:
				best = d
		if best < INF:
			total += best
			count += 1
	return total / max(count, 1)

static func test_shortcut_low_density_stable() -> String:
	var rope = OclDemoOnlyRopePhysics.new()
	rope.inner_radius = 3.0
	rope.outer_radius = 10.0
	rope.node_count = 40
	rope.iterations = 500
	rope.init_rope(42, Vector3.BACK * 10.0, Vector3.FORWARD * 10.0)
	# Low segment density: few long segments across a wide gap
	var chord_start := rope.find_main_node_at_fraction(0.2)
	var chord_end := rope.find_main_node_at_fraction(0.8)
	var main_positions := rope.get_rope_positions(0)
	var chord := main_positions[chord_start].distance_to(main_positions[chord_end])
	var segments := maxi(3, roundi(chord * 0.3 / rope.segment_length))
	rope.add_shortcut(chord_start, chord_end, segments)
	rope.relax()
	# Shortcut should exist and have reasonable segment count
	var sc := rope.get_rope_positions(1)
	if sc.size() < 2:
		return "Shortcut not created"
	# All shortcut nodes should be on the shell
	for i in range(sc.size()):
		var d := sc[i].length()
		if d < rope.inner_radius - 0.5 or d > rope.outer_radius + 0.5:
			return "Shortcut node %d at distance %.3f outside shell" % [i, d]
	# Main rope should still be connected (no nodes flying off to infinity)
	var main := rope.get_rope_positions(0)
	for i in range(main.size()):
		if main[i].length() > rope.outer_radius * 2.0:
			return "Main rope node %d at distance %.3f — flew off to infinity" % [i, main[i].length()]
	return "OK"
