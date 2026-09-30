shader_type spatial;
render_mode cull_disabled;
uniform vec4 bed_color : source_color = vec4(.28,.43,.34,1.0);
varying vec3 world_point;
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec3 p=world_point;
 float silt=sin(p.x*2.3+sin(p.y*3.1))*sin(p.z*2.1+p.y);
 float caustic=pow(max(0.0,1.0-abs(sin(p.x*6.0+p.y*3.0+TIME*.35)+sin(p.z*7.0-p.y*3.0-TIME*.27))),8.0);
 ALBEDO=bed_color.rgb*(.92+silt*.07)+vec3(.018,.036,.023)*caustic;
 ROUGHNESS=1.0;
}
