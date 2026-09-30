shader_type spatial;
render_mode cull_disabled;
uniform vec4 water_color : source_color = vec4(0.27,0.50,0.53,1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec3 p=world_position;
    float ripple=sin(p.x*9.0+p.z*5.0+sin(p.y*6.0)+TIME*1.2);
    float fine=sin(p.z*17.0-p.x*6.0+TIME*0.8);
    float light=smoothstep(0.94,1.0,ripple)*0.028+fine*0.005;
    ALBEDO=water_color.rgb+vec3(light);
    ROUGHNESS=0.38;
    SPECULAR=0.3;
}
