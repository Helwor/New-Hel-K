#version 120
#extension GL_EXT_gpu_shader4 : enable
varying vec4 color;
uniform float div;
void main() {
	gl_FragData[0].rgba = color;
	gl_FragDepth = (gl_FragCoord.z) * div ;
}