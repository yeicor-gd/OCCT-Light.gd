# OCCT-Light.gd Master Plan — AGENTS.md

## Build & Test Cycle (must pass after every commit)
```bash
# Autowrapper submodule
cd OCCT-Light.gd-autowrapper && ./generate.sh

# Full build
cd ../build && cmake .. && make -j$(nproc)
cp libgdext.linux.debug.template_debug.x86_64.so ../demo/addons/OCCT-Light.gd/

# Run tests
GODOT_TEST_RUNNER=true godot --headless --path ../demo/ tests.tscn

# Commit submodule first, then parent
cd ../OCCT-Light.gd-autowrapper && git add -A && git commit -m "<msg>" && git push
cd .. && git add -A && git commit -m "<msg>" && git push
```

## Critical Context
- **CMake glob staleness**: `file(GLOB_RECURSE)` runs only at `cmake ..` time; new `.cpp` files require `cmake .. && make`.
- **Autowrapper dir**: `OCCT-Light.gd-autowrapper/` as submodule; commit there first, then parent.
- **Gitignore**: `/src/autowrapper/`, `/demo/tests/test_Occtl*.gd`, `/doc_classes/*.xml` — generated files not tracked.
- **Module registration**: `src/register_types.cpp` (manual) + `src/autowrapper/module.cpp` (+7 part files, auto-generated).
- **Float constants can't use BIND_CONSTANT**: stay as methods returning double.
- **View types uninitialized POD**: freshly `new()`'d view objects have garbage pointer fields; must explicitly zero before use.
- **BIND_CONSTANT vs BIND_ENUM_CONSTANT**: C enums aren't registered with godot-cpp type system, so use `BIND_CONSTANT` even for enum values. `BIND_ENUM_CONSTANT` causes incomplete-type compiler error because `_gde_constant_get_enum_name` requires `GetTypeInfo<T>` which doesn't exist for C enums.
- **Manual tests naming**: Use `test_Manual_*.gd` prefix to avoid gitignore pattern `/demo/tests/test_Occtl*.gd`.

## C Macro reference resolution
- `_constant_value_resolve(v, consts)` follows `#define` chains within the **same** parsed header.
- Cross-header references (e.g., `OCCTL_REF_UID_WIRE_SIZE` in `occtl_topo_types.h` referencing `OCCTL_UID_WIRE_SIZE` in `occtl_core.h`) are **not** resolved → fall back to `int64_t` return type for methods.

---

## ✅ ITEM 1 — Enum/int constants use BIND_CONSTANT (DONE)

Header: skip method decls for integer constants and all enum values. Float constants keep methods.
Source `_bind_methods`: `BIND_CONSTANT` for literal ints, `bind_method` for everything else. Enum values use `BIND_CONSTANT`.
Source bodies: only generate for non-int constants.
Doc XML: `<constant>` tags for int/enum, `<method>` for float.
Tests: class-level access `ClassName.CONSTANT` for int/enum, instance method for float.
Constant value resolver: `_constant_value_resolve()` follows `#define` chains within same header.

---

## ITEM 2 — Static factory methods on value types (gen_values.py)

**Goal**: Add `static` factory methods like `from_vector3(v: Vector3) -> Ref<OcctlPoint3>` on value-type wrapper classes.

**Where**: `OCCT-Light.gd-autowrapper/src/gen_values.py`

**Registration**: Use `ClassDB::bind_static_method("OcctlPoint3", D_METHOD("from_vector3", "v"), &OcctlPoint3::from_vector3)`.

**Factory methods required** (+ field assignments):

| Wrapper Class | Method | Params | Field Assignments |
|---|---|---|---|
| `OcctlPoint3` | `from_vector3(v: Vector3)` | `v` | `x=v.x, y=v.y, z=v.z` |
| `OcctlPoint2` | `from_vector2(v: Vector2)` | `v` | `x=v.x, y=v.y` |
| `OcctlDirection3` | `from_vector3(v: Vector3)` | `v` | `x=v.x, y=v.y, z=v.z` |
| `OcctlDirection2` | `from_vector2(v: Vector2)` | `v` | `x=v.x, y=v.y` |
| `OcctlVector3` | `from_vector3(v: Vector3)` | `v` | `x=v.x, y=v.y, z=v.z` |
| `OcctlVector2` | `from_vector2(v: Vector2)` | `v` | `x=v.x, y=v.y` |
| `OcctlTransform` | `from_transform3d(t: Transform3D)` | `t` | `m[0..2] = t.basis[0].x/y/z, m[3]=t.origin.x, m[4..6]=t.basis[1].x/y/z, m[7]=t.origin.y, m[8..10]=t.basis[2].x/y/z, m[11]=t.origin.z` |
| `OcctlAabb3` | `from_aabb(a: AABB)` | `a` | `min.x=a.position.x, min.y=a.position.y, min.z=a.position.z, max.x=a.position.x+a.size.x, max.y=a.position.y+a.size.y, max.z=a.position.z+a.size.z` |
| `OcctlColorRgba` | `from_color(c: Color)` | `c` | `r=c.r, g=c.g, b=c.b, a=c.a` |
| `OcctlAxis1Placement` | `from_components(point: Vector3, dir: Vector3)` | `point, dir` | `location.x=point.x, location.y=point.y, location.z=point.z, direction.x=dir.x, direction.y=dir.y, direction.z=dir.z` |
| `OcctlAxis2Placement` | `from_components(point: Vector3, z_dir: Vector3, x_dir: Vector3)` | `point, z_dir, x_dir` | `location.x/y/z=point.x/y/z, x_dir.x/y/z=x_dir_ref.x/y/z` |
| `OcctlAxis3Placement` | `from_components(point: Vector3, z_dir: Vector3, x_dir: Vector3)` | `point, z_dir, x_dir` | `location.x/y/z=point.x/y/z, z_dir.x/y/z, x_dir.x/y/z` |
| `OcctlAxis2Placement2d` | `from_components(point: Vector2, z_dir: Vector2, x_dir: Vector2)` | `point, z_dir, x_dir` | `location.x/y=point.x/y, x_dir.x/y=x_dir_ref.x/y` |
| `OcctlError` | `from_values(status: int, message: String)` | `status, message` | `status=static_cast<occtl_status_t>(status), message=message.utf8().get_data()` |

**Transform field mapping** (`occtl_transform_t` has `double m[12]` row-major 3×4):
- m[0..2] = row 0: basis.x, m[3] = origin.x
- m[4..6] = row 1: basis.y, m[7] = origin.y
- m[8..10] = row 2: basis.z, m[11] = origin.z

```cpp
instance->m[0] = t.basis[0].x; instance->m[1] = t.basis[0].y; instance->m[2] = t.basis[0].z;
instance->m[3] = t.origin.x;
instance->m[4] = t.basis[1].x; instance->m[5] = t.basis[1].y; instance->m[6] = t.basis[1].z;
instance->m[7] = t.origin.y;
instance->m[8] = t.basis[2].x; instance->m[9] = t.basis[2].y; instance->m[10] = t.basis[2].z;
instance->m[11] = t.origin.z;
```

**Implementation**:
1. Define a `FACTORY_METHODS` dict mapping class name → list of `(method_name, [(param_name, param_type)], [(field_path, value_expr)])`.
2. In `generate_value_type_header`, add `static Ref<{cls}> {method_name}({params});` after field setters.
3. In `generate_value_type_source`:
   - In `_bind_methods()`: add `ClassDB::bind_static_method("{cls}", D_METHOD("{method_name}", ...), &{cls}::{method_name});`
   - After `_bind_methods()`: add implementation `Ref<{cls}> {cls}::{method_name}({params})` that creates `Ref`, instantiates, sets fields, returns.

---

## ITEM 3 — DEFVAL for nullable C params (gen_wrapper.py)

**Goal**: When a C function param has a default of `NULL`, add `DEFVAL(Variant())` so GDScript callers can omit it.

**Where**: `OCCT-Light.gd-autowrapper/src/gen_wrapper.py`, `_method_arg_names()`

**DEFVAL macro** (from godot-cpp `class_db.hpp`): `#define DEFVAL(m_defval) (m_defval)` — just wraps in parens. Used as trailing arguments to `bind_method`:

```cpp
ClassDB::bind_method(D_METHOD("method", "arg1", "arg2"), &Cls::method, DEFVAL(0), DEFVAL(Variant()));
```

**Detection**: Check if `CParameter` has a `default_value` field from tree-sitter parser. If `default_value` is `"NULL"` or `"nullptr"`, it's a nullable pointer parameter.

**Changes**:
1. In `_method_arg_names(f)` — add `DEFVAL(Variant())` for each nullable trailing param.
2. Also emit `DEFVAL(0)` for nullable `int`/`size_t` params.

**Known candidates**: `runtime_init(const occtl_runtime_init_info_t* info)` where `info` is nullable (NULL defaults). Check `parser.py` for default value extraction.

**Implementation sketch**:
```python
def _method_arg_names(f):
    args = []
    defvals = []
    for p in f.params:
        args.append(f'"{p.name}"')
        if hasattr(p, 'default_value') and p.default_value in ('NULL', 'nullptr', '0'):
            defvals.append(f'DEFVAL(Variant())' if 'pointer' in p.type_name else f'DEFVAL(0)')
    # DEFVALs go after the D_METHOD args, before the function pointer
    arg_str = ", ".join(args)
    if arg_str:
        arg_str = ", " + arg_str
    defval_str = ", " + ", ".join(defvals) if defvals else ""
    return arg_str + defval_str
```

But wait — the `bind_method` call is:
```cpp
bind_method(D_METHOD("mname", "arg1", "arg2"), &Cls::method, DEFVAL(...), DEFVAL(...))
```

So `_method_arg_names` returns the string for D_METHOD args + DEFVAL. The generator currently does:
```python
lines.append(f'    godot::ClassDB::bind_method(godot::D_METHOD("{mname}"{_method_arg_names(f)}), &{cls}::{mname});')
```

The DEFVAL args should go AFTER the `&{cls}::{mname}` part. So I need to modify the format.

---

## ITEM 4 — Rename OcctlConvert → OcctlGodot (manual module)

**Files to rename**:
- `src/convert/OcctlConvert.h` → `src/convert/OcctlGodot.h`
- `src/convert/OcctlConvert.cpp` → `src/convert/OcctlGodot.cpp`

**Class rename**: `OcctlConvert` → `OcctlGodot` everywhere (class name, constructor, method references).

**Registration**: `src/register_types.cpp` — `GDREGISTER_CLASS(OcctlConvert)` → `GDREGISTER_CLASS(OcctlGodot)`, update include.

**Test file**: `demo/tests/test_OcctlConvert.gd` → `demo/tests/test_Manual_OcctlGodot.gd` (prefix `test_Manual_` to avoid gitignore pattern). Update `class_name`, update method calls.

**Extended mesh conversions** (from #12):
Add these methods to `OcctlGodot`:

```cpp
// Edge → tube mesh, vertex → point mesh
static Ref<ArrayMesh> edge_to_mesh(const Ref<OcctlEdgeView>& edge, double radius = 0.0);
static Ref<ArrayMesh> vertex_to_mesh(const Ref<OcctlVertexView>& vertex);
static Ref<ArrayMesh> edge_to_mesh_with_colors(const Ref<OcctlEdgeView>& edge, const Dictionary& face_id_colors);

// Triangulation with extra attributes
static Ref<ArrayMesh> triangulation_to_mesh_with_uvs(const Ref<OcctlTriangulationView>& tri);
static Ref<ArrayMesh> triangulation_to_mesh_with_normals(const Ref<OcctlTriangulationView>& tri);
static Ref<ArrayMesh> triangulation_to_mesh_with_tangents(const Ref<OcctlTriangulationView>& tri);
```

Each should:
1. Extract topology data via OCCT-Light C API (iterate triangulation nodes/triangles)
2. Build Godot Array with appropriate `ArrayMesh` format
3. Return the mesh
4. Have toggleable flags (default=include) for colors/UVs/normals/tangents

**Color encoding for face IDs**: Store each face's ID compactly in the vertex color attribute (e.g., `Color(1.0, 1.0, 1.0, 1.0)` for a unique color per face, or encode the face ID in a distinguishable way across the component).

---

## ITEM 5 — Two-call buffer pattern (gen_wrapper.py)

**Goal**: Auto-detect `(int64_t* out_buf, int* n_out)` buffer pattern and generate a single method returning `PackedInt64Array`.

**Where**: `OCCT-Light.gd-autowrapper/src/gen_wrapper.py`

**Detection pattern**: In C function signature, a pointer-to-type param (e.g., `int64_t*`, `int*`) followed by a pointer-to-count param (e.g., `int* n_*`, `size_t* n_*`).

**Generated wrappers**:
```cpp
PackedInt64Array {cls}::{method_name}({regular_params}) {
    int64_t _count = 0;
    int _err = occtl_{c_func}({args_with_NULL}, &_count);
    if (_err != 0 && _err != OCCTL_BUFFER_TOO_SMALL) {
        return PackedInt64Array();
    }
    std::vector<int64_t> _buf(static_cast<size_t>(_count));
    _err = occtl_{c_func}({args_with_buf}, _buf.data(), &_count);
    PackedInt64Array _result;
    _result.resize(static_cast<int64_t>(_count));
    for (int64_t _i = 0; _i < _count; _i++) _result[_i] = _buf[static_cast<size_t>(_i)];
    return _result;
}
```

**Variations**: Handle `int32_t*`, `size_t*`, `occtl_node_id_t*` (which is `int64_t`).

**Functions using this pattern**: Check `graph_children`, `topo_*` functions with `int64_t*` out-buffer params.

**High-priority**: Without this, many graph/topo functions are unusable from GDScript (can't pass pointers).

---

## ITEM 6 — Out-param wrappers stay as pre-allocated (already correct)

**Current approach**: Out-params are pre-allocated wrappers like:
```gdscript
var out = OcctlUint32.new()
obj.method(out)
var result = out.value
```
This is the correct approach — typed, cachable, no dictionary overhead.

**NO multi-return dictionaries**. The C API style is preserved: you pre-allocate outputs, pass them, and read them afterward.

---

## ITEM 7 — Already covered by ITEM 1 (DONE)

Enum values as class-level constants via `BIND_CONSTANT`.

---

## ITEM 12 — Extended mesh conversions (part of ITEM 4)

Integrated into the `OcctlGodot` manual module. See ITEM 4 for details.

**Key design principles**:
- Edge→mesh with radius parameter (default 0.0 = single line, >0 = tube)
- Vertex→mesh as small sphere/cross visualization
- Colors identify feature/face IDs compactly
- UVs extracted from CAD model's parametric space
- Normals and tangents from the triangulation's per-vertex data
- All extra attributes toggleable via boolean params (default: included)

---

## ITEM 14 — Doc XML cross-references

**Goal**: Improve generated documentation XML with proper cross-references using BBCode-style tags.

**Where**: `OCCT-Light.gd-autowrapper/src/gen_wrapper.py`, `generate_wrapper_doc_xml()` and `gen_values.py`, `generate_value_type_doc_xml()`

**Cross-reference tags** (from Godot class reference primer):
- `[Class]` — link to another class
- `[constant Class.name]` — link to a constant
- `[enum Class.name]` — link to an enum
- `[method Class.name]` — link to a method
- `[member Class.name]` — link to a member
- `[param name]` — reference a parameter
- `[code]...[/code]` — inline code
- `[b]...[/b]` — bold for emphasis

**Changes**:
1. In function doc XML: Add `[param name]` references for each param description.
2. Add `[return]` reference for return value description.
3. Link to related OCCT-Light types (e.g., `OcctlPoint3`, `OcctlTopoShape`).
4. For functions that use enum value params, link to the enum with `[enum Class.ENUM_NAME]`.
5. For constant doc XML, add `[constant Class.NAME]` cross-references.

---

## FILE MAPPING

### `OCCT-Light.gd-autowrapper/src/gen_wrapper.py`
- Header/source/doc/test generation for function wrappers
- **Items**: #1 (DONE), #3, #5, #14

### `OCCT-Light.gd-autowrapper/src/gen_values.py`
- Header/source generation for value struct wrappers (getters/setters)
- **Items**: #2, #14 (doc XML)

### `OCCT-Light.gd-autowrapper/src/gen_out_prim.py`
- Out-param primitive wrappers (Int32, Uint32, etc.)

### `OCCT-Light.gd-autowrapper/src/gen_module.py`
- Module registration (GDREGISTER_CLASS for all wrapper classes)

### `src/convert/OcctlGodot.h`, `src/convert/OcctlGodot.cpp`
- Manual conversion module (renamed from OcctlConvert)
- **Items**: #4 (rename + extended mesh conversions)

### `src/register_types.cpp`
- Module entry point that registers manual + auto classes

---

## EXECUTION ORDER

1. ~~#1 Enum/int constants use BIND_CONSTANT~~ (DONE, committed & pushed)
2. **#2 Static factory methods** — gen_values.py
3. **#3 DEFVAL** — gen_wrapper.py
4. **#5 Two-call buffer** — gen_wrapper.py
5. **#4 Rename OcctlConvert → OcctlGodot** + extended mesh conversions
6. **#14 Doc XML cross-refs** — gen_wrapper.py + gen_values.py
