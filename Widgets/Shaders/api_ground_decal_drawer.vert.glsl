#version 420

#line 10004

layout (location = 0) in vec4 pos;
noperspective out vec2 screenUV;

void main() {
    gl_Position = vec4(pos);
    screenUV = pos.xy * 0.5 + 0.5; // [-1,1] -> [0,1]
}