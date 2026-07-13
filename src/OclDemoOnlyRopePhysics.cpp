#include "OclDemoOnlyRopePhysics.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

#if defined(_MSC_VER)
    #define FORCE_INLINE __forceinline
#else
    #define FORCE_INLINE inline __attribute__((always_inline))
#endif

static FORCE_INLINE float fast_rsqrt(float x) {
	union { float f; int32_t i; } conv;
	conv.f = x;
	conv.i = 0x5f3759df - (conv.i >> 1);
	float y = conv.f;
	y = y * (1.5f - 0.5f * x * y * y);
	return y;
}

static FORCE_INLINE float fast_abs(float x) {
	union { float f; uint32_t u; } v;
	v.f = x;
	v.u &= 0x7FFFFFFFu;
	return v.f;
}

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

OclDemoOnlyRopePhysics::OclDemoOnlyRopePhysics() {}

OclDemoOnlyRopePhysics::~OclDemoOnlyRopePhysics() {}

// ---------------------------------------------------------------------------
// Pseudo-random number generator (xorshift32)
// ---------------------------------------------------------------------------

float OclDemoOnlyRopePhysics::randf() {
	rng_state_ ^= rng_state_ << 13;
	rng_state_ ^= rng_state_ >> 17;
	rng_state_ ^= rng_state_ << 5;
	return (float)(rng_state_ & 0x7FFFFFFF) / (float)0x7FFFFFFF;
}

float OclDemoOnlyRopePhysics::randf_range(float low, float high) {
	return low + randf() * (high - low);
}

// ---------------------------------------------------------------------------
// Shell projection
// ---------------------------------------------------------------------------

Vector3 OclDemoOnlyRopePhysics::project_to_shell(Vector3 p, float target_radius) const {
	float d_sq = p.length_squared();
	if (d_sq < 0.000001f) {
		return Vector3(1, 0, 0) * inner_radius_;
	}
	if (target_radius < 0.0f) {
		if (d_sq >= inner_radius_sq_ && d_sq <= outer_radius_sq_) {
			return p;
		}
		float inv_d = fast_rsqrt(d_sq);
		float d = d_sq * inv_d;
		target_radius = std::clamp(d, inner_radius_, outer_radius_);
		return p * (target_radius * inv_d);
	}
	return p * (target_radius * fast_rsqrt(d_sq));
}

// ---------------------------------------------------------------------------
// Random initialisation helpers
// ---------------------------------------------------------------------------

bool OclDemoOnlyRopePhysics::is_valid_initial_position(Vector3 position) const {
	float min_sq = collision_radius_ * collision_radius_;
	for (const Node &n : nodes_) {
		if (n.pos.distance_squared_to(position) < min_sq) {
			return false;
		}
	}
	return true;
}

Vector3 OclDemoOnlyRopePhysics::next_random_position(Vector3 from) {
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

Vector3 OclDemoOnlyRopePhysics::find_next_position(Vector3 from) {
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

void OclDemoOnlyRopePhysics::clear() {
	nodes_.clear();
	ropes_.clear();
	anchor_start_.clear();
	anchor_end_.clear();
}

bool OclDemoOnlyRopePhysics::is_initialized() const {
	return !nodes_.empty();
}

void OclDemoOnlyRopePhysics::init_rope(int64_t _seed, Vector3 start, Vector3 end) {
	rng_state_ = (uint32_t)((uint64_t)_seed & 0xFFFFFFFF);
	if (rng_state_ == 0) {
		rng_state_ = 1;
	}

	fixed_start_ = start;
	fixed_end_ = end;

	nodes_.clear();
	ropes_.clear();
	anchor_start_.clear();
	anchor_end_.clear();

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

	ropes_.push_back({ 0, (int)nodes_.size() });
	bend_rest_length_ = segment_length_ * 2.0f;
}

// ---------------------------------------------------------------------------
// Shortcut API
// ---------------------------------------------------------------------------

int OclDemoOnlyRopePhysics::add_shortcut(int anchor_start, int anchor_end, int segments, float seg_length) {
	if (segments < 1 || nodes_.empty()) {
		return -1;
	}
	if (anchor_start < 0 || anchor_start >= (int)nodes_.size() ||
		anchor_end < 0 || anchor_end >= (int)nodes_.size()) {
		return -1;
	}

	if (seg_length < 0.0f) {
		seg_length = segment_length_;
	}

	Vector3 p_start = nodes_[anchor_start].pos;
	Vector3 p_end = nodes_[anchor_end].pos;

	int rope_start = (int)nodes_.size();
	int rope_count = segments + 1;

	// Create inner nodes by linearly interpolating (through the interior).
	nodes_.push_back({ p_start, 0.0f }); // first node (pinned to anchor_start during solve)
	for (int i = 1; i < segments; i++) {
		float t = (float)i / (float)(segments);
		Vector3 p = p_start.lerp(p_end, t);
		nodes_.push_back({ p, 1.0f });
	}
	nodes_.push_back({ p_end, 0.0f }); // last node (pinned to anchor_end during solve)

	ropes_.push_back({ rope_start, rope_count });
	anchor_start_.push_back(anchor_start);
	anchor_end_.push_back(anchor_end);

	return (int)ropes_.size() - 1;
}

int OclDemoOnlyRopePhysics::get_rope_count() const {
	return (int)ropes_.size();
}

PackedVector3Array OclDemoOnlyRopePhysics::get_rope_positions(int rope_index) {
	PackedVector3Array result;
	if (rope_index < 0 || rope_index >= (int)ropes_.size()) {
		return result;
	}
	const Rope &r = ropes_[rope_index];
	result.resize(r.count);
	for (int i = 0; i < r.count; i++) {
		result[i] = nodes_[r.start + i].pos;
	}
	return result;
}

int OclDemoOnlyRopePhysics::find_main_node_at_fraction(float fraction) const {
	if (ropes_.empty()) return 0;
	int main_n = ropes_[0].count;
	return std::clamp((int)std::round(fraction * (main_n - 1)), 0, main_n - 1);
}

// ---------------------------------------------------------------------------
// Constraint solvers
// ---------------------------------------------------------------------------

void OclDemoOnlyRopePhysics::solve_distance(int a_index, int b_index, float sl) {
	Node &a = nodes_[a_index];
	Node &b = nodes_[b_index];

	float dx = b.pos.x - a.pos.x;
	float dy = b.pos.y - a.pos.y;
	float dz = b.pos.z - a.pos.z;
	float length_sq = dx * dx + dy * dy + dz * dz;
	if (length_sq < 0.0000001f) {
		return;
	}

	float sl_sq = sl * sl;
	if (fast_abs(length_sq - sl_sq) < 0.000001f * 2.0f * sl) {
		return;
	}

	float inv_length = fast_rsqrt(length_sq);
	float length = length_sq * inv_length;
	float error = length - sl;
	if (fast_abs(error) < 0.000001f) {
		return;
	}

	float weight = a.inv_mass + b.inv_mass;
	if (weight == 0.0f) {
		return;
	}

	float corr = error * inv_length;
	float aw = a.inv_mass / weight;
	float bw = b.inv_mass / weight;
	a.pos.x += dx * corr * aw;
	a.pos.y += dy * corr * aw;
	a.pos.z += dz * corr * aw;
	b.pos.x -= dx * corr * bw;
	b.pos.y -= dy * corr * bw;
	b.pos.z -= dz * corr * bw;
}

void OclDemoOnlyRopePhysics::solve_bend_distance(int a_index, int b_index, float rest_length) {
	Node &a = nodes_[a_index];
	Node &b = nodes_[b_index];

	float dx = b.pos.x - a.pos.x;
	float dy = b.pos.y - a.pos.y;
	float dz = b.pos.z - a.pos.z;
	float dist_sq = dx * dx + dy * dy + dz * dz;
	if (dist_sq < 0.000001f) {
		return;
	}

	float rest_sq = rest_length * rest_length;
	if (fast_abs(dist_sq - rest_sq) < 0.000001f * 2.0f * rest_length) {
		return;
	}

	float inv_dist = fast_rsqrt(dist_sq);
	float dist = dist_sq * inv_dist;
	float error = dist - rest_length;
	if (fast_abs(error) < 0.000001f) {
		return;
	}

	float weight = a.inv_mass + b.inv_mass;
	if (weight == 0.0f) {
		return;
	}

	float corr = error * bend_stiffness_ * inv_dist;
	float aw = a.inv_mass / weight;
	float bw = b.inv_mass / weight;
	a.pos.x += dx * corr * aw;
	a.pos.y += dy * corr * aw;
	a.pos.z += dz * corr * aw;
	b.pos.x -= dx * corr * bw;
	b.pos.y -= dy * corr * bw;
	b.pos.z -= dz * corr * bw;
}

void OclDemoOnlyRopePhysics::solve_rope_constraints(int rope_start, int rope_count, float sl, float sl_sq, float bend_stiff) {
	int n = rope_count;
	float sl_sq_val = sl_sq;

	// --- Length constraints (even/odd passes) — always full strength ---
	{
		Node *nd = nodes_.data();
		for (int pass = 0; pass < 2; pass++) {
			for (int i = pass; i < n - 1; i += 2) {
				int ai = rope_start + i;
				int bi = rope_start + i + 1;
				Node &a = nd[ai];
				Node &b = nd[bi];
				float dx = b.pos.x - a.pos.x;
				float dy = b.pos.y - a.pos.y;
				float dz = b.pos.z - a.pos.z;
				float len_sq = dx * dx + dy * dy + dz * dz;
				if (len_sq < 0.0000001f) continue;
				if (fast_abs(len_sq - sl_sq_val) < 0.000002f * sl) continue;
				float inv_len = fast_rsqrt(len_sq);
				float err = len_sq * inv_len - sl;
				if (fast_abs(err) < 0.000001f) continue;
				float w = a.inv_mass + b.inv_mass;
				if (w == 0.0f) continue;
				float c = err * inv_len / w;
				float aw = a.inv_mass * c;
				float bw_a = b.inv_mass * c;
				a.pos.x += dx * aw;
				a.pos.y += dy * aw;
				a.pos.z += dz * aw;
				b.pos.x -= dx * bw_a;
				b.pos.y -= dy * bw_a;
				b.pos.z -= dz * bw_a;
			}
		}
	}

	// --- Bending constraints ---
	{
		Node *nd = nodes_.data();
		for (int level = 1; level <= bend_levels_; level++) {
			int spacing = level + 1;
			if (spacing >= n) continue;
			float rest = sl * (float)spacing;
			for (int pass = 0; pass < bend_passes_; pass++) {
				for (int i = 0; i + spacing < n; i++) {
					int ai = rope_start + i;
					int bi = rope_start + i + spacing;
					Node &a = nd[ai];
					Node &b = nd[bi];
					float dx = b.pos.x - a.pos.x;
					float dy = b.pos.y - a.pos.y;
					float dz = b.pos.z - a.pos.z;
					float dsq = dx * dx + dy * dy + dz * dz;
					if (dsq < 0.000001f) continue;
					float rsq = rest * rest;
					if (fast_abs(dsq - rsq) < 0.000002f * rest) continue;
					float inv_d = fast_rsqrt(dsq);
					float err = dsq * inv_d - rest;
					if (fast_abs(err) < 0.000001f) continue;
					float w = a.inv_mass + b.inv_mass;
					if (w == 0.0f) continue;
					float c = err * bend_stiff * inv_d / w;
					float aw = a.inv_mass * c;
					float bw_a = b.inv_mass * c;
					a.pos.x += dx * aw;
					a.pos.y += dy * aw;
					a.pos.z += dz * aw;
					b.pos.x -= dx * bw_a;
					b.pos.y -= dy * bw_a;
					b.pos.z -= dz * bw_a;
				}
			}
		}
	}
}

void OclDemoOnlyRopePhysics::solve_shell_constraints() {
	for (size_t i = 1; i + 1 < nodes_.size(); i++) {
		nodes_[i].pos = project_to_shell(nodes_[i].pos);
	}
}

void OclDemoOnlyRopePhysics::project_rope_nodes(int rope_start, int rope_count) {
	Node *nd = nodes_.data();
	for (int i = 1; i + 1 < rope_count; i++) {
		if (nd[rope_start + i].inv_mass == 0.0f) continue;
		Vector3 &p = nd[rope_start + i].pos;
		float d_sq = p.x * p.x + p.y * p.y + p.z * p.z;
		if (d_sq < 0.000001f) {
			p = Vector3(1, 0, 0) * inner_radius_;
			continue;
		}
		if (d_sq >= inner_radius_sq_ && d_sq <= outer_radius_sq_) continue;
		float inv_d = fast_rsqrt(d_sq);
		float d = d_sq * inv_d;
		float tr = std::clamp(d, inner_radius_, outer_radius_);
		float s = tr * inv_d;
		p.x *= s;
		p.y *= s;
		p.z *= s;
	}
}

void OclDemoOnlyRopePhysics::solve_self_collisions() {
	const int count = (int)nodes_.size();
	if (count < 2 || collision_passes_ <= 0 || collision_radius_ <= 0.0f) {
		return;
	}

	const int min_sep = (int)std::ceil(collision_radius_ / segment_length_);
	const float col_rad_sq = collision_radius_ * collision_radius_;
	const float max_corr = collision_radius_ * 0.5f;
	const float col_stiff = collision_stiffness_;
	const float inv_cell = 1.0f / collision_radius_;
	const float lo = -(outer_radius_ + collision_radius_);
	const int dim = (int)std::ceil(2.0f * (outer_radius_ + collision_radius_) * inv_cell) + 1;
	const int grid_size = dim * dim * dim;

	cell_head_.resize(grid_size);
	cell_next_.resize(count);
	cell_offsets_.resize(grid_size + 1);
	cell_data_.resize(count);

	// Only clear used cells instead of full grid memset
	for (int c : grid_used_) {
		cell_head_[c] = 0;
	}
	grid_used_.clear();

	// Build grid: assign cells
	for (int i = 0; i < count; i++) {
		if (nodes_[i].inv_mass == 0.0f) continue;
		const Vector3 &p = nodes_[i].pos;
		int cx = std::clamp((int)((p.x - lo) * inv_cell), 0, dim - 1);
		int cy = std::clamp((int)((p.y - lo) * inv_cell), 0, dim - 1);
		int cz = std::clamp((int)((p.z - lo) * inv_cell), 0, dim - 1);
		int cell = cx + cy * dim + cz * dim * dim;
		cell_next_[i] = cell;
		cell_head_[cell]++;
		if (cell_head_[cell] == 1) {
			grid_used_.push_back(cell);
		}
	}

	// Prefix sum (must be sequential — each cell depends on all previous)
	cell_offsets_[0] = 0;
	for (int c = 0; c < grid_size; c++) {
		cell_offsets_[c + 1] = cell_offsets_[c] + cell_head_[c];
	}

	// Scatter node indices into flat array
	for (int c : grid_used_) {
		cell_head_[c] = cell_offsets_[c];
	}
	for (int i = 0; i < count; i++) {
		if (nodes_[i].inv_mass == 0.0f) continue;
		int cell = cell_next_[i];
		cell_data_[cell_head_[cell]++] = i;
	}

	// Query passes
	int64_t total_checks = 0;
	for (int pass = 0; pass < collision_passes_; pass++) {
		for (int i = 0; i < count; i++) {
			if (nodes_[i].inv_mass == 0.0f) continue;
			const Vector3 &pi = nodes_[i].pos;
			const float i_im = nodes_[i].inv_mass;
			int cell = cell_next_[i];
			int cz = cell / (dim * dim);
			int cy = (cell / dim) % dim;
			int cx = cell % dim;

			for (int ddx = -1; ddx <= 1; ddx++) {
				int nx = cx + ddx;
				if (nx < 0 || nx >= dim) continue;
				for (int ddy = -1; ddy <= 1; ddy++) {
					int ny = cy + ddy;
					if (ny < 0 || ny >= dim) continue;
					for (int ddz = -1; ddz <= 1; ddz++) {
						int nz = cz + ddz;
						if (nz < 0 || nz >= dim) continue;

						int ncell = nx + ny * dim + nz * dim * dim;
						int start = cell_offsets_[ncell];
						int end = cell_offsets_[ncell + 1];
						for (int k = start; k < end; k++) {
							int j = cell_data_[k];
							if (j <= i) continue;
							if (j - i <= min_sep) continue;
							// Skip pairs inside the same bifurcation zone
							if (bifurcation_mask_[i] != 0 && bifurcation_mask_[j] != 0 &&
								(bifurcation_mask_[i] & bifurcation_mask_[j]) != 0) continue;
							total_checks++;
							float cdx = nodes_[j].pos.x - pi.x;
							float cdy = nodes_[j].pos.y - pi.y;
							float cdz = nodes_[j].pos.z - pi.z;
							float dist_sq = cdx * cdx + cdy * cdy + cdz * cdz;
							if (dist_sq < col_rad_sq) {
								float inv_dist = fast_rsqrt(dist_sq);
								float overlap = collision_radius_ - dist_sq * inv_dist;
								float weight = i_im + nodes_[j].inv_mass;
								if (weight != 0.0f) {
									float corr = std::min(overlap * col_stiff, max_corr) * inv_dist;
									float iw = i_im / weight;
									float jw = nodes_[j].inv_mass / weight;
									nodes_[i].pos.x -= cdx * corr * iw;
									nodes_[i].pos.y -= cdy * corr * iw;
									nodes_[i].pos.z -= cdz * corr * iw;
									nodes_[j].pos.x += cdx * corr * jw;
									nodes_[j].pos.y += cdy * corr * jw;
									nodes_[j].pos.z += cdz * corr * jw;
								}
							}
						}
					}
				}
			}
		}
	}

	last_collision_checks_ = total_checks;
}

void OclDemoOnlyRopePhysics::solve_endpoint_tangent(int anchor_index, int node_index, float target_dist, float blending) {
	const Node &anchor = nodes_[anchor_index];
	Node &node = nodes_[node_index];

	float ax = anchor.pos.x, ay = anchor.pos.y, az = anchor.pos.z;
	float len_r = std::sqrt(ax * ax + ay * ay + az * az);
	if (len_r < 1e-6f) return;
	float inv_r = 1.0f / len_r;
	float rnx = ax * inv_r, rny = ay * inv_r, rnz = az * inv_r;

	float tx = node.pos.x - ax;
	float ty = node.pos.y - ay;
	float tz = node.pos.z - az;
	float dot = tx * rnx + ty * rny + tz * rnz;
	tx -= rnx * dot;
	ty -= rny * dot;
	tz -= rnz * dot;

	float t_len_sq = tx * tx + ty * ty + tz * tz;
	if (t_len_sq < 0.000001f) {
		return;
	}

	float inv_t = fast_rsqrt(t_len_sq);
	float nx = tx * inv_t, ny = ty * inv_t, nz = tz * inv_t;
	float target_x = ax + nx * target_dist;
	float target_y = ay + ny * target_dist;
	float target_z = az + nz * target_dist;

	node.pos.x += (target_x - node.pos.x) * blending;
	node.pos.y += (target_y - node.pos.y) * blending;
	node.pos.z += (target_z - node.pos.z) * blending;
}

void OclDemoOnlyRopePhysics::solve_endpoint_tangents() {
	const int main_count = ropes_.empty() ? (int)nodes_.size() : ropes_[0].start + ropes_[0].count;
	const int range = std::min(endpoint_flatness_passes_, (main_count - 2) / 2);
	if (range <= 0 && anchor_start_.empty()) return;
	for (int pass = 0; pass < endpoint_flatness_passes_; pass++) {
		// Main rope endpoints
		for (int k = 1; k <= range; k++) {
			float t = (float)k / (float)std::max(range, 1);
			float fade = endpoint_flatness_ * (1.0f - t * t);
			solve_endpoint_tangent(0, k, k * segment_length_, fade);
			solve_endpoint_tangent(main_count - 1, main_count - 1 - k, k * segment_length_, fade);
		}
		// Shortcut endpoints — depart perpendicular to both radial
		// and the main-rope tangent so the ball can pick either path.
		for (int s = 0; s < (int)anchor_start_.size(); s++) {
			const Rope &rope = ropes_[1 + s];

			for (int side = 0; side < 2; side++) {
				int ai   = (side == 0) ? anchor_start_[s] : anchor_end_[s];
				int base = (side == 0) ? rope.start : (rope.start + rope.count - 1);
				int ndir = (side == 0) ? 1 : -1;

				Vector3 ap = nodes_[ai].pos;
				float ar = ap.length();
				if (ar < 1e-6f) continue;
				Vector3 radial = ap / ar;

				// Main-rope tangent at the anchor
				Vector3 tangent;
				if (ai > 0 && ai < main_count - 1)
					tangent = nodes_[ai + 1].pos - nodes_[ai - 1].pos;
				else if (ai == 0)
					tangent = nodes_[1].pos - nodes_[0].pos;
				else
					tangent = nodes_[ai].pos - nodes_[ai - 1].pos;
				tangent = tangent.normalized();

				// Departure = cross(radial, tangent), sided by initial node position
				Vector3 depart = radial.cross(tangent);
				if (depart.length_squared() < 1e-12f) {
					// Parallel — fall back to tangent-plane projection
					for (int k = 1; k <= range; k++) {
						float t = (float)k / (float)std::max(range, 1);
						float fade = endpoint_flatness_ * (1.0f - t * t);
						solve_endpoint_tangent(ai, base + ndir * k, k * segment_length_, fade);
					}
					continue;
				}
				depart = depart.normalized();

				// Pick the side that matches the initial node placement
				Vector3 init_dir = nodes_[base + ndir].pos - nodes_[base].pos;
				if (init_dir.dot(depart) < 0.0f) depart = -depart;

				for (int k = 1; k <= range; k++) {
					float t = (float)k / (float)std::max(range, 1);
					float fade = endpoint_flatness_ * (1.0f - t * t);
					Node &node = nodes_[base + ndir * k];
					node.pos.x += (ap.x + depart.x * k * segment_length_ - node.pos.x) * fade;
					node.pos.y += (ap.y + depart.y * k * segment_length_ - node.pos.y) * fade;
					node.pos.z += (ap.z + depart.z * k * segment_length_ - node.pos.z) * fade;
				}
			}
		}
	}
}

void OclDemoOnlyRopePhysics::pin_anchors() {
	nodes_[0].pos = fixed_start_;
	if (!ropes_.empty()) {
		const Rope &main = ropes_[0];
		nodes_[main.start + main.count - 1].pos = fixed_end_;
	}
	// --- Re-pin shortcut anchors after shell projection ---
	for (int s = 0; s < (int)anchor_start_.size(); s++) {
		int shortcut_idx = ropes_.size() - (int)anchor_start_.size() + s;
		const Rope &rope = ropes_[shortcut_idx];
		int as = anchor_start_[s];
		int ae = anchor_end_[s];
		nodes_[rope.start].pos = nodes_[as].pos;
		nodes_[rope.start + rope.count - 1].pos = nodes_[ae].pos;
	}
}

// ---------------------------------------------------------------------------
// Main relax loop
// ---------------------------------------------------------------------------

void OclDemoOnlyRopePhysics::relax() {
	const int total_count = (int)nodes_.size();
	if (total_count < 2) {
		return;
	}

	const int rope_count = (int)ropes_.size();
	if (rope_count == 0) {
		return;
	}

	const float sl = segment_length_;
	const float bend_stiff = bend_stiffness_;

	// Pre-compute bifurcation masks: two nodes sharing a set bit must NOT
	// collide so that the shortcut can diverge cleanly from the main rope
	// near each anchor without an oscillating push/pull.
	const int num_shortcuts = (int)anchor_start_.size();
	const int main_count = ropes_[0].count;
	const int N = (num_shortcuts > 0 && collision_radius_ > 0.0f)
			? (int)std::ceil(collision_radius_ / segment_length_)
			: 0;
	bifurcation_mask_.assign(total_count, 0);
	for (int s = 0; s < num_shortcuts && 2 * s + 1 < 32; s++) {
		uint32_t start_bit = 1u << (2 * s);
		uint32_t end_bit   = 1u << (2 * s + 1);
		int as = anchor_start_[s];
		int ae = anchor_end_[s];

		// Main rope nodes near the start anchor
		for (int i = std::max(0, as - N); i <= std::min(main_count - 1, as + N); i++) {
			bifurcation_mask_[i] |= start_bit;
		}
		// Main rope nodes near the end anchor
		for (int i = std::max(0, ae - N); i <= std::min(main_count - 1, ae + N); i++) {
			bifurcation_mask_[i] |= end_bit;
		}

		// Shortcut nodes near its own start anchor
		const Rope &rope = ropes_[1 + s];
		for (int j = 0; j <= std::min(rope.count - 1, N); j++) {
			bifurcation_mask_[rope.start + j] |= start_bit;
		}
		// Shortcut nodes near its own end anchor
		for (int j = std::max(0, rope.count - 1 - N); j < rope.count; j++) {
			bifurcation_mask_[rope.start + j] |= end_bit;
		}
	}

	for (int iter = 0; iter < iterations_; iter++) {
		for (int r = 0; r < rope_count; r++) {
			const Rope &rope = ropes_[r];
			float r_sl_sq = sl * sl;
			solve_rope_constraints(rope.start, rope.count, sl, r_sl_sq, bend_stiff);
		}

		solve_self_collisions();

		solve_endpoint_tangents();

		project_rope_nodes(0, total_count);

		pin_anchors();
	}
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

PackedVector3Array OclDemoOnlyRopePhysics::get_positions() {
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

void OclDemoOnlyRopePhysics::_bind_methods() {
	// Configuration properties
	ClassDB::bind_method(D_METHOD("get_node_count"), &OclDemoOnlyRopePhysics::get_node_count);
	ClassDB::bind_method(D_METHOD("set_node_count", "value"), &OclDemoOnlyRopePhysics::set_node_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "node_count", PROPERTY_HINT_RANGE, "2,10000,1"), "set_node_count", "get_node_count");

	ClassDB::bind_method(D_METHOD("get_segment_length"), &OclDemoOnlyRopePhysics::get_segment_length);
	ClassDB::bind_method(D_METHOD("set_segment_length", "value"), &OclDemoOnlyRopePhysics::set_segment_length);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "segment_length", PROPERTY_HINT_RANGE, "0.01,100,0.01"), "set_segment_length", "get_segment_length");

	ClassDB::bind_method(D_METHOD("get_iterations"), &OclDemoOnlyRopePhysics::get_iterations);
	ClassDB::bind_method(D_METHOD("set_iterations", "value"), &OclDemoOnlyRopePhysics::set_iterations);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,100000,1"), "set_iterations", "get_iterations");

	ClassDB::bind_method(D_METHOD("get_init_attempts"), &OclDemoOnlyRopePhysics::get_init_attempts);
	ClassDB::bind_method(D_METHOD("set_init_attempts", "value"), &OclDemoOnlyRopePhysics::set_init_attempts);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "init_attempts", PROPERTY_HINT_RANGE, "1,100,1"), "set_init_attempts", "get_init_attempts");

	ClassDB::bind_method(D_METHOD("get_bend_passes"), &OclDemoOnlyRopePhysics::get_bend_passes);
	ClassDB::bind_method(D_METHOD("set_bend_passes", "value"), &OclDemoOnlyRopePhysics::set_bend_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bend_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_bend_passes", "get_bend_passes");

	ClassDB::bind_method(D_METHOD("get_bend_stiffness"), &OclDemoOnlyRopePhysics::get_bend_stiffness);
	ClassDB::bind_method(D_METHOD("set_bend_stiffness", "value"), &OclDemoOnlyRopePhysics::set_bend_stiffness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bend_stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_bend_stiffness", "get_bend_stiffness");

	ClassDB::bind_method(D_METHOD("get_bend_levels"), &OclDemoOnlyRopePhysics::get_bend_levels);
	ClassDB::bind_method(D_METHOD("set_bend_levels", "value"), &OclDemoOnlyRopePhysics::set_bend_levels);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bend_levels", PROPERTY_HINT_RANGE, "0,20,1"), "set_bend_levels", "get_bend_levels");

	ClassDB::bind_method(D_METHOD("get_collision_passes"), &OclDemoOnlyRopePhysics::get_collision_passes);
	ClassDB::bind_method(D_METHOD("set_collision_passes", "value"), &OclDemoOnlyRopePhysics::set_collision_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_collision_passes", "get_collision_passes");

	ClassDB::bind_method(D_METHOD("get_collision_stiffness"), &OclDemoOnlyRopePhysics::get_collision_stiffness);
	ClassDB::bind_method(D_METHOD("set_collision_stiffness", "value"), &OclDemoOnlyRopePhysics::set_collision_stiffness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_collision_stiffness", "get_collision_stiffness");

	ClassDB::bind_method(D_METHOD("get_endpoint_flatness"), &OclDemoOnlyRopePhysics::get_endpoint_flatness);
	ClassDB::bind_method(D_METHOD("set_endpoint_flatness", "value"), &OclDemoOnlyRopePhysics::set_endpoint_flatness);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "endpoint_flatness", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_endpoint_flatness", "get_endpoint_flatness");

	ClassDB::bind_method(D_METHOD("get_endpoint_flatness_passes"), &OclDemoOnlyRopePhysics::get_endpoint_flatness_passes);
	ClassDB::bind_method(D_METHOD("set_endpoint_flatness_passes", "value"), &OclDemoOnlyRopePhysics::set_endpoint_flatness_passes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "endpoint_flatness_passes", PROPERTY_HINT_RANGE, "0,20,1"), "set_endpoint_flatness_passes", "get_endpoint_flatness_passes");

	ClassDB::bind_method(D_METHOD("get_radial_bias"), &OclDemoOnlyRopePhysics::get_radial_bias);
	ClassDB::bind_method(D_METHOD("set_radial_bias", "value"), &OclDemoOnlyRopePhysics::set_radial_bias);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radial_bias", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_radial_bias", "get_radial_bias");

	ClassDB::bind_method(D_METHOD("get_inner_radius"), &OclDemoOnlyRopePhysics::get_inner_radius);
	ClassDB::bind_method(D_METHOD("set_inner_radius", "value"), &OclDemoOnlyRopePhysics::set_inner_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "inner_radius", PROPERTY_HINT_RANGE, "0,1000,0.01"), "set_inner_radius", "get_inner_radius");

	ClassDB::bind_method(D_METHOD("get_outer_radius"), &OclDemoOnlyRopePhysics::get_outer_radius);
	ClassDB::bind_method(D_METHOD("set_outer_radius", "value"), &OclDemoOnlyRopePhysics::set_outer_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "outer_radius", PROPERTY_HINT_RANGE, "0,1000,0.01"), "set_outer_radius", "get_outer_radius");

	ClassDB::bind_method(D_METHOD("get_collision_radius"), &OclDemoOnlyRopePhysics::get_collision_radius);
	ClassDB::bind_method(D_METHOD("set_collision_radius", "value"), &OclDemoOnlyRopePhysics::set_collision_radius);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_radius", PROPERTY_HINT_RANGE, "0,100,0.01"), "set_collision_radius", "get_collision_radius");

	// Methods
	ClassDB::bind_method(D_METHOD("clear"), &OclDemoOnlyRopePhysics::clear);
	ClassDB::bind_method(D_METHOD("init_rope", "_seed", "start", "end"), &OclDemoOnlyRopePhysics::init_rope, DEFVAL(Vector3(-1, 0, 0)), DEFVAL(Vector3(1, 0, 0)));
	ClassDB::bind_method(D_METHOD("relax"), &OclDemoOnlyRopePhysics::relax);
	ClassDB::bind_method(D_METHOD("get_positions"), &OclDemoOnlyRopePhysics::get_positions);
	ClassDB::bind_method(D_METHOD("is_initialized"), &OclDemoOnlyRopePhysics::is_initialized);

	// Shortcut methods
	ClassDB::bind_method(D_METHOD("add_shortcut", "anchor_start", "anchor_end", "segments", "seg_length"), &OclDemoOnlyRopePhysics::add_shortcut, DEFVAL(-1.0f));
	ClassDB::bind_method(D_METHOD("get_rope_count"), &OclDemoOnlyRopePhysics::get_rope_count);
	ClassDB::bind_method(D_METHOD("get_rope_positions", "rope_index"), &OclDemoOnlyRopePhysics::get_rope_positions);
	ClassDB::bind_method(D_METHOD("find_main_node_at_fraction", "fraction"), &OclDemoOnlyRopePhysics::find_main_node_at_fraction);
}
