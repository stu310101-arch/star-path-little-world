shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;
uniform vec4 water_color : source_color = vec4(0.15,0.39,0.37,1.0);
varying vec3 world_point;
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec3 p=world_point;
 float wave=sin(p.x*3.8+p.z*2.4+sin(p.y*2.0)+TIME*.55);
 float second=sin(p.z*5.7-p.y*3.2-p.x*1.8-TIME*.36);
 float glint=smoothstep(.91,1.0,wave*second);
 float fresnel=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
 ALBEDO=water_color.rgb+glint*.08;
 ROUGHNESS=.31;
 SPECULAR=.35;
 ALPHA=.30+fresnel*.27+glint*.10;
}
