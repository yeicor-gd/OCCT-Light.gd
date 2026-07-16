#ifndef OCLDEMOONLYROPEPHYSICS_H
#define OCLDEMOONLYROPEPHYSICS_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <cstdint>
#include <vector>

using namespace godot;

class OclDemoOnlyRopePhysics : public godot::Resource {
	GDCLASS(OclDemoOnlyRopePhysics, godot::Resource)
protected:
	static void _bind_methods();

public:
	OclDemoOnlyRopePhysics();
	~OclDemoOnlyRopePhysics();

	// --- Configuration properties ---
	int get_node_count() const { return node_count_; }
	void set_node_count(int v) { node_count_ = v; }

	float get_segment_length() const { return segment_length_; }
	void set_segment_length(float v) { segment_length_ = v; }

	int get_iterations() const { return iterations_; }
	void set_iterations(int v) { iterations_ = v; }

	int get_init_attempts() const { return init_attempts_; }
	void set_init_attempts(int v) { init_attempts_ = v; }

	int get_bend_passes() const { return bend_passes_; }
	void set_bend_passes(int v) { bend_passes_ = v; }

	float get_bend_stiffness() const { return bend_stiffness_; }
	void set_bend_stiffness(float v) { bend_stiffness_ = v; }

	int get_bend_levels() const { return bend_levels_; }
	void set_bend_levels(int v) { bend_levels_ = v; }

	int get_collision_passes() const { return collision_passes_; }
	void set_collision_passes(int v) { collision_passes_ = v; }

	float get_collision_stiffness() const { return collision_stiffness_; }
	void set_collision_stiffness(float v) { collision_stiffness_ = v; }

	float get_endpoint_flatness() const { return endpoint_flatness_; }
	void set_endpoint_flatness(float v) { endpoint_flatness_ = v; }

	int get_endpoint_flatness_passes() const { return endpoint_flatness_passes_; }
	void set_endpoint_flatness_passes(int v) { endpoint_flatness_passes_ = v; }

	int get_endpoint_levels() const { return endpoint_levels_; }
	void set_endpoint_levels(int v) { endpoint_levels_ = v; }

	int get_endpoint_length_passes() const { return endpoint_length_passes_; }
	void set_endpoint_length_passes(int v) { endpoint_length_passes_ = v; }

	float get_endpoint_length_stiffness() const { return endpoint_length_stiffness_; }
	void set_endpoint_length_stiffness(float v) { endpoint_length_stiffness_ = v; }

	int get_endpoint_length_levels() const { return endpoint_length_levels_; }
	void set_endpoint_length_levels(int v) { endpoint_length_levels_ = v; }

	float get_radial_bias() const { return radial_bias_; }
	void set_radial_bias(float v) { radial_bias_ = v; }

	float get_inner_radius() const { return inner_radius_; }
	void set_inner_radius(float v) { inner_radius_ = v; inner_radius_sq_ = v * v; }

	float get_outer_radius() const { return outer_radius_; }
	void set_outer_radius(float v) { outer_radius_ = v; outer_radius_sq_ = v * v; }

	float get_collision_radius() const { return collision_radius_; }
	void set_collision_radius(float v) { collision_radius_ = v; }

	int get_space_filling_passes() const { return space_filling_passes_; }
	void set_space_filling_passes(int v) { space_filling_passes_ = v; }

	float get_space_filling_stiffness() const { return space_filling_stiffness_; }
	void set_space_filling_stiffness(float v) { space_filling_stiffness_ = v; }

	int get_space_filling_halvings() const { return space_filling_halvings_; }
	void set_space_filling_halvings(int v) { space_filling_halvings_ = v; }

	int get_radial_flattening_passes() const { return radial_flattening_passes_; }
	void set_radial_flattening_passes(int v) { radial_flattening_passes_ = v; }

	float get_radial_flattening_stiffness() const { return radial_flattening_stiffness_; }
	void set_radial_flattening_stiffness(float v) { radial_flattening_stiffness_ = v; }

	float get_strength() const { return strength_; }
	void set_strength(float v) { strength_ = v; }

	float get_anchor_smoothing_stiffness() const { return anchor_smoothing_stiffness_; }
	void set_anchor_smoothing_stiffness(float v) { anchor_smoothing_stiffness_ = v; }

	int get_anchor_smoothing_levels() const { return anchor_smoothing_levels_; }
	void set_anchor_smoothing_levels(int v) { anchor_smoothing_levels_ = v; }

	// --- Public API ---
	void clear();
	void init_rope(int64_t _seed, Vector3 start = Vector3(-1, 0, 0), Vector3 end = Vector3(1, 0, 0));
	void relax();
	PackedVector3Array get_positions();
	bool is_initialized() const;

	// --- Shortcut API ---
	int add_shortcut(int anchor_start, int anchor_end, int segments, float seg_length = -1.0f);
	int get_rope_count() const;
	PackedVector3Array get_rope_positions(int rope_index);
	int find_main_node_at_fraction(float fraction) const;
	int get_shortcut_start_anchor(int idx) const;
	int get_shortcut_end_anchor(int idx) const;

	// --- Internal types ---
	struct Node {
		Vector3 pos;
		float inv_mass;
	};

	struct Rope {
		int start;  // start index in nodes_
		int count;  // number of nodes in this rope
	};

private:
	// Configuration
	int node_count_ = 100;
	float segment_length_ = 1.0f;
	int iterations_ = 200;
	int init_attempts_ = 10;
	int bend_passes_ = 12;
	float bend_stiffness_ = 0.8f;
	int bend_levels_ = 4;
	int collision_passes_ = 6;
	float collision_stiffness_ = 0.8f;
	float endpoint_flatness_ = 1.0f;
	int endpoint_flatness_passes_ = 12;
	int endpoint_levels_ = 12;
	int endpoint_length_passes_ = 10;
	float endpoint_length_stiffness_ = 0.8f;
	int endpoint_length_levels_ = 5;
	float inner_radius_ = 1.0f;
	float outer_radius_ = 2.0f;
	float collision_radius_ = 0.35f;
	float inner_radius_sq_ = 1.0f;
	float outer_radius_sq_ = 4.0f;
	int space_filling_passes_ = 10;
	float space_filling_stiffness_ = 0.8f;
	int space_filling_halvings_ = 2;
	float radial_bias_ = 0.1f;
	int radial_flattening_passes_ = 8;
	float radial_flattening_stiffness_ = 0.8f;
	float strength_ = 1.0f;
	float anchor_smoothing_stiffness_ = 0.8f;
	int anchor_smoothing_levels_ = 5;

	// Simulation state
	std::vector<Node> nodes_;
	std::vector<Rope> ropes_;
	std::vector<int> anchor_start_;  // per-shortcut: absolute node index
	std::vector<int> anchor_end_;    // per-shortcut: absolute node index
	Vector3 fixed_start_;
	Vector3 fixed_end_;
	float bend_rest_length_ = 0.0f;
	uint32_t rng_state_ = 1;

	// Collision detection scratch buffers
	std::vector<int> cell_head_;
	std::vector<int> cell_next_;
	std::vector<int> cell_offsets_;
	std::vector<int> cell_data_;
	std::vector<int> grid_used_;
	std::vector<uint32_t> bifurcation_mask_;
	std::vector<int> node_rope_;  // per-node: rope index (for min_sep skip)

	// Internal methods
	float randf();
	float randf_range(float low, float high);
	Vector3 next_random_position(Vector3 from);
	Vector3 project_to_shell(Vector3 p, float target_radius = -1.0f) const;
	bool is_valid_initial_position(Vector3 position) const;
	Vector3 find_next_position(Vector3 from);
	void solve_distance(int a, int b, float sl);
	void solve_shell_constraints();
	void solve_bend_distance(int a, int b, float rest_length);
	void solve_self_collisions();
	void solve_repulsion(float radius, float stiffness);
	void solve_space_filling();
	void solve_radial_flattening();
	void solve_endpoint_tangents();
	void solve_endpoint_tangent(int anchor, int node_idx, float target_dist, float blending);
	void solve_endpoint_length(int rope_start, int rope_count, float stiffness);
	void pin_anchors();
	void solve_length_constraints(int rope_start, int rope_count, float sl, float sl_sq);
	void solve_bend_pass(int rope_start, int rope_count, float sl, float bend_stiff);
	void project_rope_nodes(int rope_start, int rope_count);
};

#endif // OCLDEMOONLYROPEPHYSICS_H
