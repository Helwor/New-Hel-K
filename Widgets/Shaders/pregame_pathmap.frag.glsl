#version 420

//__DEFINES__
//__ENGINEUNIFORMBUFFERDEFS__

#line 9007

// uniform float depth_mul;
// uniform float depth_pow;

uniform float intensity;
uniform float checker;
uniform float highlight_back;
// uniform float vehpass; 
uniform float botpass;
in DataVS {
	float slope;
	float height;
};


out vec4 fragColor;
// const float botpass = 14.5;
float inv6 = 1 / 1e6;
float vehpass = 6.0;
vec4 color;
void main() {
    if (checker > 0.0) {
	    if (gl_PrimitiveID % 2 == 0)
	        fragColor = vec4(1.0, 0.0, 0.0, 0.25);
	    else
	        fragColor = vec4(0.0, 1.0, 0.0, 0.25);
	    return;
	}
    if (highlight_back > 0.0 && !gl_FrontFacing){
        fragColor = vec4(0.0, 1.0, 1.0, 0.50); 
        return;
    }
	if (slope < 2.5 && height > -16.0)
		discard;
	float water = step(height, -16.0) * 0.6 + step(height, -22.0) * 0.4;
	// fragColor.r = step(-16.0, height) * (pow(min(slope, vehpass) / vehpass, 3.0));
	color.b = water;
	if (water == 0.0) {
		color.r = step(-16.0, height) * (pow(min(slope, vehpass) / vehpass, 3.0));
		color.b = pow(min(slope - vehpass, botpass - vehpass) / (botpass - vehpass), 3.0) * 1.0;
	}
	color.g = water * 0.3;
	color.a = 1.0;

	color.rgb *= intensity + water * 0.2;
	fragColor = color;

	// fragColor.rgba = vec4(1.0,1.0,1.0, 0.25);
	// gl_FragDepth = pow(gl_FragCoord.z * (1.0 - slope * inv6 ), depth_pow); // sadly costly in performance, need to find something else
}

