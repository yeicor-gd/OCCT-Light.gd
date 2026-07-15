shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back;

//====================================================
// Appearance
//====================================================

uniform vec4 arrow_color : source_color = vec4(0.15, 1.0, 0.15, 1.0);
uniform float emission_strength = 2.0;

//====================================================
// Animation
//====================================================

uniform float speed = 2.0;
uniform float direction = 1.0;

//====================================================
// World scale
//====================================================

// World meters represented by UV.y = 1.
uniform float uv_meters_along = 50.0;

// Distance between rows of arrows.
uniform float row_spacing_meters = 7.0;

//====================================================
// Across-road layout
//====================================================

// Number of arrow columns.
uniform float column_count = 5.0;

// Global horizontal shift.
uniform float column_offset = 0.0;

// Multiplier applied to spacing.
// >1 spreads columns apart.
// <1 packs them together.
uniform float column_spacing = 1.0;

//====================================================
// Chevron shape
//====================================================

uniform float chevron_width = 0.32;
uniform float chevron_height = 0.58;
uniform float line_width = 0.07;

//====================================================
// Normal fade
//====================================================

uniform float align_start = 0.30;
uniform float align_end = 0.70;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex()
{
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float segment_distance(vec2 p, vec2 a, vec2 b)
{
    vec2 pa = p - a;
    vec2 ba = b - a;

    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);

    return length(pa - ba * h);
}

float chevron(vec2 uv)
{
    uv -= vec2(0.5);

    uv.x /= chevron_width;
    uv.y /= chevron_height;

    // Chevron pointing toward +Y.
    float d = min(
        segment_distance(
            uv,
            vec2(-0.45,-0.45),
            vec2(0.0,0.45)
        ),
        segment_distance(
            uv,
            vec2(0.45,-0.45),
            vec2(0.0,0.45)
        )
    );

    float aa = fwidth(d);

    return 1.0 - smoothstep(
        line_width - aa,
        line_width + aa,
        d
    );
}

void fragment()
{
    //------------------------------------------------
    // Along-road animation
    //------------------------------------------------

    float rows = uv_meters_along / row_spacing_meters;

    float v = fract(
        UV.y * rows +
        TIME * speed * direction
    );

    //------------------------------------------------
    // Across-road repetition
    //------------------------------------------------

    float cols = max(column_count, 1.0);

    float u =
        UV.x * cols * column_spacing +
        column_offset;

    u = fract(u);

    //------------------------------------------------
    // Arrow
    //------------------------------------------------

    float mask = chevron(vec2(u, v));

    //------------------------------------------------
    // Radial visibility
    //------------------------------------------------

    vec3 radial = normalize(world_pos);

    float align =
        dot(normalize(world_normal), radial);

    mask *= smoothstep(
        align_start,
        align_end,
        align
    );

    //------------------------------------------------
    // Output
    //------------------------------------------------

    ALBEDO = arrow_color.rgb;
    EMISSION = arrow_color.rgb * emission_strength * mask;
	if (mask * arrow_color.a < 0.5)
    	discard;
}