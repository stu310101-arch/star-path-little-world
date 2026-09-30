shader_type spatial;
render_mode cull_disabled;
uniform vec4 fish_color : source_color = vec4(.65,.35,.12,1.0);
uniform float stroke_phase=0.0;
void vertex() {
 float tail=1.0-smoothstep(-.425,.10,VERTEX.z);
 VERTEX.x+=sin(TIME*5.0+stroke_phase+VERTEX.z*7.0)*.045*tail*tail;
 VERTEX.y-=.14;
}
void fragment() {
 ALBEDO=fish_color.rgb;
 ROUGHNESS=.55;
 SPECULAR=.35;
}
