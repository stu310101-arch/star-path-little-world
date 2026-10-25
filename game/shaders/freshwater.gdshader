shader_type spatial;
render_mode cull_disabled;

uniform vec4 water_color : source_color = vec4(0.27, 0.50, 0.53, 1.0);
varying vec3 world_position;
float lake_hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float lake_noise(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(lake_hash(i),lake_hash(i+vec3(1,0,0)),f.x),mix(lake_hash(i+vec3(0,1,0)),lake_hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(lake_hash(i+vec3(0,0,1)),lake_hash(i+vec3(1,0,1)),f.x),mix(lake_hash(i+vec3(0,1,1)),lake_hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 phase = vec2(
        dot(world_position, vec3(5.2, 0.7, 3.1)) + TIME * 0.70,
        dot(world_position, vec3(-3.1, 1.6, 8.5)) - TIME * 0.46
    );
    vec2 waves = sin(phase);
    vec2 footprint = fwidth(phase);
    vec2 detail = vec2(1.0) - smoothstep(vec2(0.35), vec2(1.6), footprint);
    detail *= 1.0 - smoothstep(144.0, 1600.0, dot(VERTEX, VERTEX));
    float ripple = smoothstep(0.64, 0.99, waves.x) * detail.x;
    float fine = waves.y * detail.y;
    float grazing = 1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
    float fresnel = grazing * grazing * grazing;
    // Broad, quiet highlights keep the existing teal palette legible on phones.
    // A quiet lake has broad, irregular patches, not parallel painted stripes.
    ALBEDO = water_color.rgb + vec3((lake_noise(world_position*.7+vec3(TIME*.045))-0.5)*.008);
    ALBEDO += vec3(0.015, 0.025, 0.027) * fresnel;
    ROUGHNESS = 0.62;
    SPECULAR = 0.22;
}
