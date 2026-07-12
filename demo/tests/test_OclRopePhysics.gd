class_name TestOclRopePhysics

static func _check(condition: bool, msg: String) -> String:
	return "OK" if condition else msg

static func test_is_initialized_before_init() -> String:
	var rope = OclRopePhysics.new()
	return _check(not rope.is_initialized(), "Should not be initialized before init_rope")

static func test_init_creates_correct_node_count() -> String:
	var rope = OclRopePhysics.new()
	rope.node_count = 50
	rope.init_rope(42)
	return _check(rope.get_positions().size() == 50, "Expected 50 nodes, got %d" % rope.get_positions().size())

static func test_init_deterministic() -> String:
	var rope1 = OclRopePhysics.new()
	rope1.init_rope(12345)
	var pos1 = rope1.get_positions()

	var rope2 = OclRopePhysics.new()
	rope2.init_rope(12345)
	var pos2 = rope2.get_positions()

	for i in range(pos1.size()):
		if pos1[i].distance_to(pos2[i]) > 0.0001:
			return "Node %d differs: %v vs %v" % [i, pos1[i], pos2[i]]
	return "OK"

static func test_relax_completes() -> String:
	var rope = OclRopePhysics.new()
	rope.node_count = 50
	rope.iterations = 100
	rope.init_rope(42)
	rope.relax()
	var positions = rope.get_positions()
	return _check(positions.size() == 50, "Wrong node count after relax")

static func test_positions_within_shell() -> String:
	var rope = OclRopePhysics.new()
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
	var rope = OclRopePhysics.new()
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
	var rope = OclRopePhysics.new()
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
	var rope = OclRopePhysics.new()
	rope.init_rope(42)
	if not rope.is_initialized():
		return "Should be initialized after init_rope"
	rope.clear()
	return _check(not rope.is_initialized(), "Should not be initialized after clear")

static func test_get_positions_type() -> String:
	var rope = OclRopePhysics.new()
	rope.init_rope(42)
	var positions = rope.get_positions()
	return _check(positions is PackedVector3Array, "Expected PackedVector3Array")

static func test_performance() -> String:
	var rope = OclRopePhysics.new()
	rope.node_count = 200
	rope.iterations = 2000
	var start_time = Time.get_ticks_msec()
	rope.init_rope(42)
	rope.relax()
	var elapsed = Time.get_ticks_msec() - start_time
	return _check(elapsed < 10000, "Too slow: %d ms" % elapsed)

static func test_custom_radii() -> String:
	var rope = OclRopePhysics.new()
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
	var rope1 = OclRopePhysics.new()
	rope1.init_rope(1)
	var pos1 = rope1.get_positions()

	var rope2 = OclRopePhysics.new()
	rope2.init_rope(2)
	var pos2 = rope2.get_positions()

	var any_different = false
	for i in range(pos1.size()):
		if pos1[i].distance_to(pos2[i]) > 0.01:
			any_different = true
			break

	return _check(any_different, "Different seeds produced identical results")

static func test_property_defaults() -> String:
	var rope = OclRopePhysics.new()
	return _check(
		rope.node_count == 200 and
		rope.segment_length == 1.0 and
		rope.iterations == 2000 and
		rope.inner_radius == 1.0 and
		rope.outer_radius == 2.0,
		"Default property values mismatch"
	)
