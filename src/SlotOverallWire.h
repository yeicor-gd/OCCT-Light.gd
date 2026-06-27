#ifndef SLOT_OVERALL_WIRE_H
#define SLOT_OVERALL_WIRE_H

#include "Wire.h"

#include <godot_cpp/classes/ref.hpp>

class CadPlane;

class SlotOverallWire : public Wire {
    GDCLASS(SlotOverallWire, Wire)

protected:
    static void _bind_methods();

public:
    SlotOverallWire();

    void build_slot_overall(double p_width, double p_height, const godot::Ref<CadPlane> &p_plane = godot::Ref<CadPlane>(), bool p_centered = true);
};

#endif // SLOT_OVERALL_WIRE_H
