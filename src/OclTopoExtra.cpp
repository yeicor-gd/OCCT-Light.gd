#include "OclTopoExtra.h"
#include "occtl/occtl_topo_relation.h"

void OclTopoExtra::_bind_methods() {
    godot::ClassDB::bind_static_method(
        "OclTopoExtra",
        godot::D_METHOD("solid_is_self_intersecting", "graph", "solid", "min_edge_length", "out_result"),
        &OclTopoExtra::solid_is_self_intersecting);
}

int OclTopoExtra::solid_is_self_intersecting(
    const Ref<OclGraphHandle>& graph,
    int64_t solid,
    double min_edge_length,
    const Ref<OclInt32>& out_result)
{
    int32_t val = 0;
    occtl_status_t st = ::occtl_topo_solid_is_self_intersecting(
        reinterpret_cast<const occtl_graph_t*>(
            static_cast<uintptr_t>(graph.is_valid() ? graph->get_handle() : 0)),
        occtl_node_id_t{static_cast<uint64_t>(solid)},
        min_edge_length,
        &val);
    if (out_result.is_valid())
        out_result->set_value(static_cast<int>(val));
    return static_cast<int>(st);
}
