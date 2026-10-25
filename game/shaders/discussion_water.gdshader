shader_type spatial;
// Opaque, world-space ripples: no reflection capture, screen copy or transparency pass.
uniform vec3 deep_color : source_color = vec3(0.17, 0.34, 0.36);
uniform vec3 light_color : source_color = vec3(0.39, 0.58, 0.57);
varying vec3 world_point;
varying vec3 world_normal;
void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    float a = dot(world_point.xz, vec2(1.7, 1.1)) + TIME * 0.55;
    float b = dot(world_point.xz, vec2(-2.1, 2.8)) - TIME * 0.38;
    float fade = 1.0 - smoothstep(20.0, 55.0, length(VERTEX));
    vec3 slope = vec3(cos(a) * 0.055, 0.0, cos(b) * 0.04) * fade * max(world_normal.y, 0.0);
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(world_normal - slope), 0.0)).xyz);
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
    ALBEDO = mix(deep_color, light_color, fresnel * 0.65 + sin(a) * sin(b) * 0.025);
    ROUGHNESS = 0.31;
    SPECULAR = 0.45;
}
