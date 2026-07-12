#ifndef OCLROPEPHYSICS_H
#define OCLROPEPHYSICS_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <cstdint>
#include <vector>

using namespace godot;

class OclRopePhysics : public godot::Resource {
	GDCLASS(OclRopePhysics, godot::Resource)
protected:
	static void _bind_methods();

public:
	OclRopePhysics();
	~OclRopePhysics();

	// Exported properties
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

	float get_radial_bias() const { return radial_bias_; }
	void set_radial_bias(float v) { radial_bias_ = v; }

	// Non-exported but settable properties
	float get_inner_radius() const { return inner_radius_; }
	void set_inner_radius(float v) { inner_radius_ = v; inner_radius_sq_ = v * v; }

	float get_outer_radius() const { return outer_radius_; }
	void set_outer_radius(float v) { outer_radius_ = v; outer_radius_sq_ = v * v; }

	float get_collision_radius() const { return collision_radius_; }
	void set_collision_radius(float v) { collision_radius_ = v; }

	// Methods
	void clear();
	void init_rope(int64_t _seed, Vector3 start = Vector3(-1, 0, 0), Vector3 end = Vector3(1, 0, 0));
	void relax();
	PackedVector3Array get_positions();
	bool is_initialized() const;

	struct Node {
		Vector3 pos;
		float inv_mass;
	};

private:
	// Configuration
	int node_count_ = 200;
	float segment_length_ = 1.0f;
	int iterations_ = 2000;
	int init_attempts_ = 10;
	int bend_passes_ = 2;
	float bend_stiffness_ = 0.8f;
	int bend_levels_ = 4;
	int collision_passes_ = 2;
	float collision_stiffness_ = 0.8f;
	float endpoint_flatness_ = 0.5f;
	int endpoint_flatness_passes_ = 2;
	float radial_bias_ = 0.1f;
	float inner_radius_ = 1.0f;
	float outer_radius_ = 2.0f;
	float collision_radius_ = 0.35f;
	float inner_radius_sq_ = 1.0f;
	float outer_radius_sq_ = 4.0f;

	// Simulation state
	std::vector<Node> nodes_;
	Vector3 fixed_start_;
	Vector3 fixed_end_;
	float bend_rest_length_ = 0.0f;
	uint32_t rng_state_ = 1;

	// Collision detection scratch buffer
	struct SortEntry { float x; int idx; };
	std::vector<SortEntry> collision_buf_;

	// Internal methods
	float randf();
	float randf_range(float low, float high);
	Vector3 next_random_position(Vector3 from);
	Vector3 project_to_shell(Vector3 p, float target_radius = -1.0f) const;
	bool is_valid_initial_position(Vector3 position) const;
	Vector3 find_next_position(Vector3 from);
	void project_all_nodes();
	void solve_distance(int a, int b);
	void solve_length_constraints();
	void solve_shell_constraints();
	void solve_bending_constraints();
	void solve_bend_distance(int a, int b, float rest_length);
	void solve_self_collisions();
	void solve_endpoint_tangents();
	void solve_endpoint_tangent(int anchor, int node_idx);
	void pin_anchors();
};

#endif // OCLROPEPHYSICS_H
