shader_type sky;
render_mode use_quarter_res_pass;
uniform bool overview_mode = false;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void sky() {
    // The spherical ground's visible horizon falls below the eye-level plane.
    float elevation=clamp(EYEDIR.y+0.30,0.0,1.0);
    vec3 horizon=vec3(0.72,0.77,0.78);
    vec3 zenith=vec3(0.18,0.37,0.56);
    vec3 sky_color=mix(horizon,zenith,pow(elevation,0.55));
    vec2 p=EYEDIR.xz/max(EYEDIR.y+0.32,0.15)*1.3;
    float cloud=noise(p)*0.55+noise(p*2.03)*0.27+noise(p*4.07)*0.12+noise(p*8.1)*0.06;
    // Fade clouds before their projection reaches the horizon. Extending the
    // clamped projection below it made vertical white streaks around the world.
    float mask=smoothstep(0.53,0.73,cloud)*smoothstep(0.02,0.30,EYEDIR.y)*0.62;
    sky_color=mix(sky_color,vec3(0.92,0.90,0.84),mask);
    vec3 sun=normalize(vec3(-0.5,0.68,0.45));
    float alignment=max(dot(EYEDIR,sun),0.0);
    sky_color+=vec3(1.0,0.76,0.45)*pow(alignment,20.0)*0.18;
    sky_color+=vec3(2.5,2.0,1.5)*smoothstep(0.9995,0.9998,alignment);
    COLOR=overview_mode ? mix(vec3(0.011,0.026,0.045),vec3(0.029,0.060,0.085),clamp(EYEDIR.y*0.5+0.5,0.0,1.0)) : mix(vec3(0.52,0.63,0.67),sky_color,smoothstep(-0.55,-0.20,EYEDIR.y));
}
