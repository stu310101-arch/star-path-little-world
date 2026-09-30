shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = exp(-r * r * 26.0);
	float halo = exp(-r * r * 4.0) * (1.0 - smoothstep(0.65, 1.0, r));
	ALBEDO = mix(vec3(0.015, 0.24, 1.0), vec3(0.40, 0.85, 1.0), core);
	ALPHA = core * 0.48 + halo * 0.22;
}
