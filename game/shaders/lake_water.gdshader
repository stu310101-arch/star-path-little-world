shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;
uniform vec4 water_color : source_color = vec4(.16,.28,.25,1.0);
varying vec3 point;
varying vec3 radial;
void vertex() {
    point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    radial=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec3 d1=vec3(.77,.42,.46), d2=vec3(-.29,.87,.39), d3=vec3(.16,-.22,.96);
    float a=dot(point,d1)*4.6+sin(dot(point,d2)*.43)*1.2+TIME*.54;
    float b=dot(point,d2)*7.3+sin(dot(point,d3)*.61)*.8-TIME*.42;
    float c=dot(point,d3)*13.6+TIME*.72;
    float detail=1.0-smoothstep(.35,1.6,fwidth(c));
    float far_fade=1.0-smoothstep(18.0,100.0,length(VERTEX));
    float aa=1.0-smoothstep(.2,1.2,fwidth(a));
    float ab=1.0-smoothstep(.2,1.2,fwidth(b));
    vec3 slope=(d1*cos(a)*.028*aa+d2*cos(b)*.022*ab+d3*cos(c)*.012*detail)*far_fade;
    slope-=radial*dot(slope,radial);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(radial-slope),0.0)).xyz);
    float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
    ALBEDO=mix(water_color.rgb*vec3(.46,.52,.49),vec3(.14,.21,.21),fresnel);
    ROUGHNESS=.28+.20*(1.0-far_fade);
    SPECULAR=.48;
    METALLIC=0.0;
    ALPHA=.48+fresnel*.42;
}
