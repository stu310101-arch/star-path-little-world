shader_type spatial;
// Authored terrain, paving and solid structures have outward clockwise faces.
// Their hidden reverse sides do not need fragment shading or shadow work.
render_mode cull_back;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bank_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float world_scale = 0.4;
uniform float color_weight = 0.0;
uniform float bump_strength = 0.36;
uniform int surface_kind = 0;
uniform int biome_index = 0;
uniform vec3 biome_tint = vec3(0.38,0.51,0.33);
varying vec3 wp;
varying vec3 wn;

void vertex() {
    wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 weights(vec3 n) {
    vec3 w = pow(abs(n), vec3(8.0));
    return w / max(w.x+w.y+w.z, 0.0001);
}

void fragment() {
    vec3 w = weights(wn);
    vec3 p = wp * world_scale;
    vec3 a = texture(surface_color, p.zy).rgb;
    vec3 b = texture(surface_color, p.xz).rgb;
    vec3 c = texture(surface_color, p.xy).rgb;
    vec3 tex = a*w.x+b*w.y+c*w.z;
    vec3 n1 = texture(surface_normal,p.zy).xyz*2.0-1.0;
    vec3 n2 = texture(surface_normal,p.xz).xyz*2.0-1.0;
    vec3 n3 = texture(surface_normal,p.xy).xyz*2.0-1.0;
    vec3 bump = vec3(n2.x*w.y+n3.x*w.z,n1.y*w.x+n3.y*w.z,n1.x*w.x+n2.y*w.y);
    bump -= wn*dot(wn,bump);
    NORMAL = normalize((VIEW_MATRIX*vec4(normalize(wn+bump*bump_strength),0.0)).xyz);
    vec3 vertex_tint = mix(vec3(1.0),COLOR.rgb,color_weight);
    ALBEDO = tex*tint.rgb*vertex_tint;
    if (surface_kind == 1) {
        // UV2 stores continuous shoreline-distance and exposed-bank weights.
        // All ground triangles share this material, including raised banks.
        ALBEDO = tex * biome_tint;
        vec3 soil = texture(bank_soil,p.zy).rgb*w.x+texture(bank_soil,p.xz).rgb*w.y+texture(bank_soil,p.xy).rgb*w.z;
        if (biome_index == 2) {
            ALBEDO = mix(ALBEDO,soil*vec3(.75,.58,.36),.72);
        } else if (biome_index == 1) {
            ALBEDO = mix(ALBEDO,soil*vec3(.60,.57,.42),.36);
        } else if (biome_index == 4) {
            ALBEDO = mix(ALBEDO,soil*vec3(.52,.42,.25),.22);
        }
        vec3 rock_p = wp * 0.25;
        vec3 rock = texture(bank_rock,rock_p.zy).rgb*w.x+texture(bank_rock,rock_p.xz).rgb*w.y+texture(bank_rock,rock_p.xy).rgb*w.z;
        ALBEDO = mix(ALBEDO,soil*vec3(.48,.46,.39),clamp(UV2.x,0.0,1.0)*.85);
        ALBEDO = mix(ALBEDO,rock*vec3(.48,.48,.42),clamp(UV2.y,0.0,1.0));
    } else if (surface_kind == 2) {
        float grain=dot(tex,vec3(.2126,.7152,.0722));
        ALBEDO=vec3(.033,.039,.041)*(0.84+grain*0.55);
    }
    ROUGHNESS = clamp(texture(surface_roughness,p.zy).r*w.x+texture(surface_roughness,p.xz).r*w.y+texture(surface_roughness,p.xy).r*w.z,0.48,0.96);
    SPECULAR = 0.26;
}
