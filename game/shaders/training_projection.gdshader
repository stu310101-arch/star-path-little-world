shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 emitter = vec3(0.65, 0.529, -0.8);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The fan starts at the lens and expands into the screen's lower edge.
	vec3 p = world_position - emitter;
	float height = clamp(p.y / 0.855, 0.0, 1.0);
	float half_width = mix(0.13, 0.8, height);
	float across = abs(p.x) / half_width;
	float feather = 1.0 - smoothstep(0.68, 1.0, across);
	float core = exp(-across * across * 16.0) * (1.0 - height);
	float source_fade = mix(0.30, 0.11, height);
	ALBEDO = vec3(0.015, 0.30, 1.0);
	ALPHA = feather * source_fade + core * 0.2;
}
