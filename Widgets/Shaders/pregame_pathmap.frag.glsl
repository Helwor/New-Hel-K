#version 420

//__DEFINES__
//__ENGINEUNIFORMBUFFERDEFS__

#line 9007

uniform float depth_mul;
uniform float depth_pow;
uniform float alpha;
const float inv6 = 1 / 1e6;
// uniform float vehpass; 
in DataVS {
	float slope;
	float height;
};


out vec4 fragColor;
const float botpass = 18.0;
const float vehpass = 6.0;
void main() {
	if (slope < 2.5 && height > -16.0)
		discard;
	float water = step(height, -16.0) * 0.6 + step(height, -22.0) * 0.4;
	fragColor.r = step(-16.0, height) * (pow(min(slope, vehpass) / vehpass, 3.0));
	fragColor.b = water + pow(min(slope - vehpass, botpass - vehpass) / (botpass - vehpass), 3.0) * 0.8;
	fragColor.g = water * 0.3;
	fragColor.a = alpha + water * 0.2;
	gl_FragDepth = pow(gl_FragCoord.z * (1.0 - slope * inv6 ), depth_pow);
}