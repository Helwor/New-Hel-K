#version 420

#line 20000

//__ENGINEUNIFORMBUFFERDEFS__

//__DEFINES__

uniform float alpha;
// uniform float vehpass; 
in DataVS {
	float slope;
	float height;
};

out vec4 fragColor;
const float botpass = 18.0;
const float vehpass = 6.0;
void main() {
	if (slope < 1.0 && height > -16.0)
		discard;
	fragColor.r = pow(min(slope, vehpass) / vehpass, 3.0) * step(-16.0, height);
	fragColor.b = pow(min(slope - vehpass, botpass - vehpass) / (botpass - vehpass), 3.0);
	fragColor.g = 0.0;
	fragColor.b += step(height, -16.0) * 0.5 + step(height, -22.0) * 0.5;
	fragColor.a = alpha;
	gl_FragDepth = gl_FragCoord.z * 0.99999;
}