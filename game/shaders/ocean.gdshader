shader_type spatial;
render_mode specular_disabled;
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float wave = sin(world_point.x * 1.2 + world_point.y * 0.7 + TIME * 0.24)
		* sin(world_point.z * 1.05 - world_point.y * 0.6 - TIME * 0.18);
	float ripple = smoothstep(0.65, 0.95, wave) * 0.12;
	ALBEDO = mix(vec3(0.09, 0.34, 0.40), vec3(0.27, 0.56, 0.58), ripple);
	ROUGHNESS = 0.92;
}
