#include "OclRopePhysics.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

OclRopePhysics::OclRopePhysics() {}

OclRopePhysics::~OclRopePhysics() {}

// ---------------------------------------------------------------------------
// Pseudo-random number generator (xorshift32)
// ---------------------------------------------------------------------------

float OclRopePhysics::randf() {
	rng_state_ ^= rng_state_ << 13;
	rng_state_ ^= rng_state_ >> 17;
	rng_state_ ^= rng_state_ << 5;
	return (float)(rng_state_ & 0x7FFFFFFF) / (float)0x7FFFFFFF;
}

float OclRopePhysics::randf_range(float low, float high) {
	return low + randf() * (high - low);
}

// ---------------------------------------------------------------------------
// Shell projection
// ---------------------------------------------------------------------------

Vector3 OclRopePhysics::project_to_shell(Vector3 p, float target_radius) const {
	float d_sq = p.length_squared();
	if (d_sq < 0.000001f) {
		return Vector3(1, 0, 0) * inner_radius_;
	}
	if (target_radius < 0.0f) {
		if (d_sq >= inner_radius_sq_ && d_sq <= outer_radius_sq_) {
			return p;
		}
		float d = std::sqrt(d_sq);
		target_radius = std::clamp(d, inner_radius_, outer_radius_);
		return p * (target_radius / d);
	}
	return p * (target_radius / std::sqrt(d_sq));
}

void OclRopePhysics::project_all_nodes() {
	for (size_t i = 1; i + 1 < nodes_.size(); i++) {
		nodes_[i].pos = project_to_shell(nodes_[i].pos);
	}
}

// ---------------------------------------------------------------------------
// Random initialisation helpers
// ---------------------------------------------------------------------------

bool OclRopePhysics::is_valid_initial_position(Vector3 position) const {
	float min_sq = collision_radius_ * collision_radius_;
	for (const Node &n : nodes_) {
		if (n.pos.distance_squared_to(position) < min_sq) {
			return false;
		}
	}
	return true;
}

Vector3 OclRopePhysics::next_random_position(Vector3 from) {
	Vector3 radial = from.normalized();

	Vector3 dir = Vector3(
						  randf_range(-1.0f, 1.0f),
						  randf_range(-1.0f, 1.0f),
						  randf_range(-1.0f, 1.0f))
						  .normalized();

	dir -= radial * dir.dot(radial);

	if (dir.length_squared() < 0.000001f) {
		dir = radial.cross(Vector3(0, 1, 0));
		if (dir.length_squared() < 0.000001f) {
			dir = radial.cross(Vector3(1, 0, 0));
		}
		dir = dir.normalized();
	}

	dir += radial * randf_range(-radial_bias_, radial_bias_);
	dir = dir.normalized();

	Vector3 p = from + dir * segment_length_;
	return project_to_shell(p);
}

Vector3 OclRopePhysics::find_next_position(Vector3 from) {
	for (int attempt = 0; attempt < init_attempts_; attempt++) {
		Vector3 candidate = next_random_position(from);

		if (nodes_.size() > 1) {
			Vector3 previous = nodes_.back().pos;
			Vector3 old_dir = (from - previous).normalized();
			Vector3 new_dir = (candidate - from).normalized();
			if (old_dir.dot(new_dir) < -0.5f) {
				continue;
			}
		}

		if (is_valid_initial_position(candidate)) {
			return candidate;
		}
	}
	return next_random_position(from);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void OclRopePhysics::clear() {
	nodes_.clear();
}

bool OclRopePhysics::is_initialized() const {
	return !nodes_.empty();
}

void OclRopePhysics::init_rope(int64_t _seed, Vector3 start, Vector3 end) {
	rng_state_ = (uint32_t)((uint64_t)_seed & 0xFFFFFFFF);
	if (rng_state_ == 0) {
		rng_state_ = 1;
	}

	fixed_start_ = start;
	fixed_end_ = end;

	nodes_.clear();
	nodes_.reserve(node_count_);
	nodes_.push_back({ start, 0.0f }); // pinned

	Vector3 front = start;
	Vector3 back = end;

	std::vector<Vector3> left, right;
	left.reserve(node_count_ / 2 + 1);
	right.reserve(node_count_ / 2 + 1);

	while ((int)left.size() + (int)right.size() < node_count_ - 2) {
		if (left.size() <= right.size()) {
			front = find_next_position(front);
			left.push_back(front);
		} else {
			back = find_next_position(back);
			right.push_back(back);
		}
	}

	std::reverse(right.begin(), right.end());

	for (const Vector3 &p : left) {
		nodes_.push_back({ p, 1.0f });
	}
	for (const Vector3 &p : right) {
		nodes_.push_back({ p, 1.0f });
	}

	nodes_.push_back({ end, 0.0f }); // pinned

	bend_rest_length_ = segment_length_ * 2.0f;
}

// ---------------------------------------------------------------------------
// Constraint solvers
// ---------------------------------------------------------------------------

void OclRopePhysics::solve_distance(int a_index, int b_index) {
	Node &a = nodes_[a_index];
	Node &b = nodes_[b_index];

	Vector3 delta = b.pos - a.pos;
	float length_sq = delta.length_squared();
	if (length_sq < 0.0000001f) {
		return;
	}

	float sl = segment_length_;
	float sl_sq = sl * sl;
	if (std::abs(length_sq - sl_sq) < 0.000001f * 2.0f * sl) {
		return;
	}

	float length = std::sqrt(length_sq);
	float error = length - sl;
	if (std::abs(error) < 0.000001f) {
		return;
	}

	float weight = a.inv_mass + b.inv_mass;
	if (weight == 0.0f) {
		return;
	}

	Vector3 correction = delta * (error / length);
	a.pos += correction * (a.inv_mass / weight);
	b.pos -= correction * (b.inv_mass / weight);
}

void OclRopePhysics::solve_length_constraints() {
	int count = (int)nodes_.size();

	// Even edges
	for (int i = 0; i < count - 1; i += 2) {
		solve_distance(i, i + 1);
	}
	// Odd edges
	for (int i = 1; i < count - 1; i += 2) {
		solve_distance(i, i + 1);
	}
}

void OclRopePhysics::solve_shell_constraints() {
	for (size_t i = 1; i + 1 < nodes_.size(); i++) {
		nodes_[i].pos = project_to_shell(nodes_[i].pos);
	}
}

void OclRopePhysics::solve_bend_distance(int a_index, int b_index, float rest_length) {
	Node &a = nodes_[a_index];
	Node &b = nodes_[b_index];

	Vector3 delta = b.pos - a.pos;
	float dist_sq = delta.length_squared();
	if (dist_sq < 0.000001f) {
		return;
	}

	float rest_sq = rest_length * rest_length;
	if (std::abs(dist_sq - rest_sq) < 0.000001f * 2.0f * rest_length) {
		return;
	}

	float dist = std::sqrt(dist_sq);
	float error = dist - rest_length;
	if (std::abs(error) < 0.000001f) {
		return;
	}

	float weight = a.inv_mass + b.inv_mass;
	if (weight == 0.0f) {
		return;
	}

	Vector3 correction = delta * (error * bend_stiffness_ / dist);
	a.pos += correction * (a.inv_mass / weight);
	b.pos -= correction * (b.inv_mass / weight);
}

void OclRopePhysics::solve_bending_constraints() {
	for (int level = 1; level <= bend_levels_; level++) {
		int spacing = level + 1;
		float rest = segment_length_ * spacing;

		for (int pass = 0; pass < bend_passes_; pass++) {
			for (int i = 0; i + spacing < (int)nodes_.size(); i++) {
				solve_bend_distance(i, i + spacing, rest);
			}
		}
	}
}

void OclRopePhysics::solve_self_collisions() {
	const int count = (int)nodes_.size();
	if (count < 2) {
		return;
	}

	const int min_separation = (int)std::ceil(collision_radius_ / segment_length_);
	const float col_rad_sq = collision_radius_ * collision_radius_;
	const float max_correction = collision_radius_ * 0.5f;

	collision_buf_.resize(count);

	for (int pass = 0; pass < collision_passes_; pass++) {
		for (int i = 0; i < count; i++) {
			collision_buf_[i] = { nodes_[i].pos.x, i };
		}
		std::sort(collision_buf_.begin(), collision_buf_.end(),
				[](const SortEntry &a, const SortEntry &b) { return a.x < b.x; });

		for (int si = 0; si < count; si++) {
			const int i = collision_buf_[si].idx;
			if (nodes_[i].inv_mass == 0.0f) {
				continue;
			}
			const float xi = collision_buf_[si].x;

			for (int sj = si + 1; sj < count; sj++) {
				if (collision_buf_[sj].x - xi > collision_radius_) {
					break;
				}

				const int j = collision_buf_[sj].idx;
				if (std::abs(j - i) <= min_separation) {
					continue;
				}

				Vector3 delta = nodes_[j].pos - nodes_[i].pos;
				float dist_sq = delta.length_squared();
				if (dist_sq >= col_rad_sq || dist_sq < 0.000001f) {
					continue;
				}

				float dist = std::sqrt(dist_sq);
				float overlap = collision_radius_ - dist;
				float weight = nodes_[i].inv_mass + nodes_[j].inv_mass;
				if (weight == 0.0f) {
					continue;
				}

				Vector3 correction = delta * (std::min(overlap * collision_stiffness_, max_correction) / dist);
				nodes_[i].pos -= correction * (nodes_[i].inv_mass / weight);
				nodes_[j].pos += correction * (nodes_[j].inv_mass / weight);
			}
		}
	}
}

void OclRopePhysics::solve_endpoint_tangent(int anchor_index, int node_index) {
	const Node &anchor = nodes_[anchor_index];
	Node &node = nodes_[node_index];

	Vector3 radius = anchor.pos.normalized();
	Vector3 tangent = node.pos - anchor.pos;
	Vector3 radial = radius * tangent.dot(radius);
	tangent -= radial;

	if (tangent.length_squared() < 0.000001f) {
		return;
	}

	Vector3 target = anchor.pos + tangent.normalized() * segment_length_;
	node.pos = node.pos.lerp(target, endpoint_flatness_);
}

void OclRopePhysics::solve_endpoint_tangents() {
	for (int pass = 0; pass < endpoint_flatness_passes_; pass++) {
		solve_endpoint_tangent(0, 1);
		int last = (int)nodes_.size() - 1;
		solve_endpoint_tangent(last, last - 1);
	}
}

void OclRopePhysics::pin_anchors() {
	nodes_[0].pos = fixed_start_;
	nodes_.back().pos = fixed_end_;
}

// ---------------------------------------------------------------------------
// Main relax loop
// ---------------------------------------------------------------------------

void OclRopePhysics::relax() {
	if (nodes_.size() < 2) {
		return;
	}

	for (int iter = 0; iter < iterations_; iter++) {
		solve_length_constraints();
		project_all_nodes();

		solve_bending_constraints();
		project_all_nodes();

		solve_endpoint_tangents();
		project_all_nodes();

		solve_self_collisions();
		project_all_nodes();

		pin_anchors();
	}
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

PackedVector3Array OclRopePhysics::get_positions() {
	PackedVector3Array result;
	result.resize(nodes_.size());
	for (size_t i = 0; i < nodes_.size(); i++) {
		result[i] = nodes_[i].pos;
	}
	return result;
}

// ---------------------------------------------------------------------------
// GDScript bindings
// ---------------------------------------------------------------------------

void OclRopePhysics::_bind_methods() {
	// Exported properties
	ClassDB::bind_method(D_METHOD("get_node_count"), &OclRopePhysics::get_node_count);
	ClassDB::bind_method(D_METHOD("set_node_count", "value"), &OclRopePhysics::set_node_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "node_count", PROPERTY_HINT_RANGE, "2,10000,1"), "set_node_count", "get_node_count");

	ClassDB::bind_method(D_METHOD("get_segment_length"), &OclRopePhysics::get_segment_length);
	ClassDB::bind_method(D_METHOD("set_segment_length", "value"), &OclRopePhysics::set_segment_length);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "segment_length", PROPERTY_HINT_RANGE, "0.01,100,0.01"), "set_segment_length", "get_segment_length");

	ClassDB::bind_method(D_METHOD("get_iterations"), &OclRopePhysics::get_iterations);
	ClassDB::bind_method(D_METHOD("set_iterations", "value"), &OclRopePhysics::set_iterations);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,100000,1"), "set_iterations", "get_iterations");

	ClassDB::bind_method(D_METHOD("get_init_attempts"), &OclRopePhysics::get_init_attempts);
	ClassDB::bind_method(D_METHOD("set_init_attempts", "value"), &OclRopePhysics::set_init_attempts);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "init_attempts", PROPERTY_HINT_RANGE, "1,100,1"), "set_init_attempts", "get_init_attempts");

	ClassDB::bind_method(D_METHOD("get_bend_passes"), &OclRopePhysics::get_bend_passes);
	ClassDB::bind_method(D_METHOD("set_bend_passes", "value"), &OclRopePhysics::set_bend_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bend_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_bend_passes", "get_bend_passes");

	ClassDB::bind_method(D_METHOD("get_bend_stiffness"), &OclRopePhysics::get_bend_stiffness);
	ClassDB::bind_method(D_METHOD("set_bend_stiffness", "value"), &OclRopePhysics::set_bend_stiffness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bend_stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_bend_stiffness", "get_bend_stiffness");

	ClassDB::bind_method(D_METHOD("get_bend_levels"), &OclRopePhysics::get_bend_levels);
	ClassDB::bind_method(D_METHOD("set_bend_levels", "value"), &OclRopePhysics::set_bend_levels);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bend_levels", PROPERTY_HINT_RANGE, "0,20,1"), "set_bend_levels", "get_bend_levels");

	ClassDB::bind_method(D_METHOD("get_collision_passes"), &OclRopePhysics::get_collision_passes);
	ClassDB::bind_method(D_METHOD("set_collision_passes", "value"), &OclRopePhysics::set_collision_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_collision_passes", "get_collision_passes");

	ClassDB::bind_method(D_METHOD("get_collision_stiffness"), &OclRopePhysics::get_collision_stiffness);
	ClassDB::bind_method(D_METHOD("set_collision_stiffness", "value"), &OclRopePhysics::set_collision_stiffness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_collision_stiffness", "get_collision_stiffness");

	ClassDB::bind_method(D_METHOD("get_endpoint_flatness"), &OclRopePhysics::get_endpoint_flatness);
	ClassDB::bind_method(D_METHOD("set_endpoint_flatness", "value"), &OclRopePhysics::set_endpoint_flatness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "endpoint_flatness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_endpoint_flatness", "get_endpoint_flatness");

	ClassDB::bind_method(D_METHOD("get_endpoint_flatness_passes"), &OclRopePhysics::get_endpoint_flatness_passes);
	ClassDB::bind_method(D_METHOD("set_endpoint_flatness_passes", "value"), &OclRopePhysics::set_endpoint_flatness_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "endpoint_flatness_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_endpoint_flatness_passes", "get_endpoint_flatness_passes");

	ClassDB::bind_method(D_METHOD("get_radial_bias"), &OclRopePhysics::get_radial_bias);
	ClassDB::bind_method(D_METHOD("set_radial_bias", "value"), &OclRopePhysics::set_radial_bias);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radial_bias", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_radial_bias", "get_radial_bias");

	// Non-exported properties (still accessible from GDScript)
	ClassDB::bind_method(D_METHOD("get_inner_radius"), &OclRopePhysics::get_inner_radius);
	ClassDB::bind_method(D_METHOD("set_inner_radius", "value"), &OclRopePhysics::set_inner_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "inner_radius", PROPERTY_HINT_RANGE, "0,1000,0.01"), "set_inner_radius", "get_inner_radius");

	ClassDB::bind_method(D_METHOD("get_outer_radius"), &OclRopePhysics::get_outer_radius);
	ClassDB::bind_method(D_METHOD("set_outer_radius", "value"), &OclRopePhysics::set_outer_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "outer_radius", PROPERTY_HINT_RANGE, "0,1000,0.01"), "set_outer_radius", "get_outer_radius");

	ClassDB::bind_method(D_METHOD("get_collision_radius"), &OclRopePhysics::get_collision_radius);
	ClassDB::bind_method(D_METHOD("set_collision_radius", "value"), &OclRopePhysics::set_collision_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_radius", PROPERTY_HINT_RANGE, "0,100,0.01"), "set_collision_radius", "get_collision_radius");

	// Methods
	ClassDB::bind_method(D_METHOD("clear"), &OclRopePhysics::clear);
	ClassDB::bind_method(D_METHOD("init_rope", "_seed", "start", "end"), &OclRopePhysics::init_rope, DEFVAL(Vector3(-1, 0, 0)), DEFVAL(Vector3(1, 0, 0)));
	ClassDB::bind_method(D_METHOD("relax"), &OclRopePhysics::relax);
	ClassDB::bind_method(D_METHOD("get_positions"), &OclRopePhysics::get_positions);
	ClassDB::bind_method(D_METHOD("is_initialized"), &OclRopePhysics::is_initialized);
}
