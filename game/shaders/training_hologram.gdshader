shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 emitter = vec3(0.65, 0.529, -0.8);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_position - emitter;
	float h = clamp((p.y - 0.855) / 1.2, 0.0, 1.0);
	float half_width = mix(0.8, 1.1, h);
	float edge_distance = min(half_width - abs(p.x), min(h, 1.0-h) * 1.2);
	float edge = exp(-max(edge_distance, 0.0) * 65.0);
	float scan = 0.97 + 0.03 * sin(p.y * 420.0);
	ALBEDO = mix(vec3(0.006, 0.035, 0.16), vec3(0.02, 0.36, 1.0), edge) * scan;
	ALPHA = 0.92 + edge * 0.06;
}
