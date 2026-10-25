shader_type spatial;
varying vec3 point;
varying vec3 radial;
void vertex() {
    point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    radial=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec3 d1=vec3(.82,.32,.47), d2=vec3(-.43,.89,.22), d3=vec3(.21,-.31,.93);
    float a=dot(point,d1)*.70+sin(dot(point,d2)*.13)*1.4+TIME*.45;
    float b=dot(point,d2)*1.3+sin(dot(point,d3)*.19)*1.1-TIME*.38;
    float c=dot(point,d3)*8.6+TIME*.81;
    float filter=1.0-smoothstep(.35,2.0,fwidth(c));
    float distance_fade=1.0-smoothstep(35.0,220.0,length(VERTEX));
    float aa=1.0-smoothstep(.25,1.5,fwidth(a));
    float ab=1.0-smoothstep(.25,1.5,fwidth(b));
    vec3 slope=(d1*cos(a)*.017*aa+d2*cos(b)*.012*ab+d3*cos(c)*.009*filter)*distance_fade;
    slope-=radial*dot(slope,radial);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(radial-slope),0.0)).xyz);
    float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
    ALBEDO=mix(vec3(.018,.065,.079),vec3(.045,.135,.161),fresnel);
    ALBEDO=mix(ALBEDO,vec3(.022,.083,.115),.6*(1.0-distance_fade));
    ROUGHNESS=.32+0.30*(1.0-distance_fade)+0.025*(sin(a)*sin(b)*.5+.5)*distance_fade;
    METALLIC=0.0;
    SPECULAR=.42;
}
