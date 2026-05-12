#version 420
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__
#line 10006
uniform sampler2D mapDepths;
uniform sampler2D mapColors;
uniform sampler2D decalTex;
uniform float alphaColorMul;

uniform vec4 decalPos;
#define decalX decalPos.x
#define decalZ decalPos.y
#define decalW decalPos.z
#define decalH decalPos.w
noperspective in vec2 screenUV;
out vec4 fragColor;

vec3 ScreenToWorld(vec2 screenUV, float depth) {
    vec4 fragToScreen = vec4(vec3(screenUV * 2.0 - 1.0, depth), 1.0);
    fragToScreen = cameraViewProjInv * fragToScreen;
    return fragToScreen.xyz / fragToScreen.w;
}

void main() {
    float depth = texture2D(mapDepths, screenUV).x;
    vec3 worldPos = ScreenToWorld(screenUV, depth);
    if (worldPos.x < decalX || worldPos.x > decalX + decalW ||
        worldPos.z < decalZ || worldPos.z > decalZ + decalH || 
        worldPos.y < -3000.0)
        discard;
    vec2 uv = (worldPos.xz - decalPos.xy)  / (decalPos.zw);
    vec4 texColor = texture(decalTex, uv);
    vec4 mapColor = texture(mapColors, screenUV);
    fragColor = texColor;
    // fragColor = mapColor;
    if (alphaColorMul > 0.0){
        float intensity = max(max(texColor.r, texColor.b), texColor.g); // ou max(texColor.r, texColor.b)
        fragColor.a = intensity * alphaColorMul;
    }
//__USERINCLUDE__
}
