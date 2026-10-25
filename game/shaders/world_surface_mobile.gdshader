shader_type spatial;
// Same outward terrain geometry as the full-quality shader.
render_mode cull_back;

// Mobile keeps the authored colors and shoreline weights, with five texture
// reads for ground instead of fifteen, and no per-pixel normal-map blending.
uniform sampler2D surface_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float world_scale = 0.4;
uniform float color_weight = 0.0;
uniform int surface_kind = 0;
uniform int biome_index = 0;
uniform vec3 biome_tint = vec3(0.38,0.51,0.33);
varying vec3 wp;
varying vec3 blend_weights;
varying vec2 bank_uv;

void vertex() {
    wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 n = abs(normalize(MODEL_NORMAL_MATRIX * NORMAL));
    vec3 w = n*n; w *= w; w *= w;
    blend_weights = w / max(w.x+w.y+w.z, 0.0001);
    // A district has a consistent dominant radial axis; this projection is
    // only used for the secondary bank layers, not the base material.
    vec3 radial = abs(normalize(wp));
    bank_uv = radial.y >= radial.x && radial.y >= radial.z ? wp.xz : (radial.x >= radial.z ? wp.zy : wp.xy);
}

void fragment() {
    vec3 p = wp * world_scale;
    vec3 tex = texture(surface_color,p.zy).rgb*blend_weights.x
        + texture(surface_color,p.xz).rgb*blend_weights.y
        + texture(surface_color,p.xy).rgb*blend_weights.z;
    ALBEDO = tex*tint.rgb*mix(vec3(1.0),COLOR.rgb,color_weight);
    if (surface_kind == 1) {
        ALBEDO = tex*biome_tint;
        vec3 soil = texture(bank_soil,bank_uv*world_scale).rgb;
        if (biome_index == 2) ALBEDO = mix(ALBEDO,soil*vec3(.75,.58,.36),.72);
        else if (biome_index == 1) ALBEDO = mix(ALBEDO,soil*vec3(.60,.57,.42),.36);
        else if (biome_index == 4) ALBEDO = mix(ALBEDO,soil*vec3(.52,.42,.25),.22);
        vec3 rock = texture(bank_rock,bank_uv*.25).rgb;
        ALBEDO = mix(ALBEDO,soil*vec3(.48,.46,.39),clamp(UV2.x,0.0,1.0)*.85);
        ALBEDO = mix(ALBEDO,rock*vec3(.48,.48,.42),clamp(UV2.y,0.0,1.0));
    } else if (surface_kind == 2) {
        ALBEDO = vec3(.033,.039,.041)*(0.84+dot(tex,vec3(.2126,.7152,.0722))*.55);
    }
    ROUGHNESS = 0.85;
    SPECULAR = 0.18;
}
