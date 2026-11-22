shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink_color : source_color = vec4(0.025, 0.044, 0.095, 1.0);
uniform vec4 gold_color : source_color = vec4(0.91, 0.79, 0.59, 1.0);

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + 1.0), f.x), f.y);
}

void fragment() {
    vec2 uv = UV;
    float grain = noise21(uv * 19.0 + vec2(TIME * 0.10, -TIME * 0.06));
    float curve = uv.x * 0.74 + uv.y * 0.26 + (grain - 0.5) * 0.22;
    float edge = smoothstep(curve - 0.075, curve + 0.075, progress * 1.17);
    float edge_light = exp(-pow((curve - progress * 1.17) * 31.0, 2.0));
    float stars = step(0.996, hash21(floor(uv * vec2(330.0, 185.0))));
    vec3 color = mix(ink_color.rgb, gold_color.rgb, edge_light * 0.18 + stars * 0.21);
    COLOR = vec4(color, clamp(edge, 0.0, 1.0));
}
