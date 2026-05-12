#version 120
varying vec4 color;

void main() {
	color = gl_Color.rgba;
	gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
	if (gl_Vertex.y <= 0.0)
		color.a *=  0.25;
}