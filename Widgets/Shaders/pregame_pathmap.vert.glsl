#version 420
#line 10000

//__DEFINES__

layout (location = 0) in vec2 xyworld_xyfract;

uniform sampler2D heightmapTex;
uniform vec2  invMapSize;
uniform vec2  mapCenter;

out DataVS {
	float slope;
	float height;
};

//__ENGINEUNIFORMBUFFERDEFS__

#line 11049


vec2 uvstep = 8.0 * invMapSize;


float texlod = 1.0;
float GetSlope(vec3 w, vec2 uv) { 
	float height = max(0.0, w.y);
	float max_slope = 0.0;
	for (int x = -1; x <= 1; x += 2) {
		for (int y = -1; y <= 1; y += 2) {
			float neighbour_height = max(0.0, textureLod(heightmapTex, uv + vec2(float(x), float(y)) * uvstep, texlod).x);
			max_slope = max(abs(height - neighbour_height), max_slope);
		}
	}
	return max_slope;
}
void main() {
	vec3 worldPos = vec3(0.0);
	worldPos.xz = mapCenter * (1 + xyworld_xyfract.xy);
	vec2 uv = vec2(clamp(worldPos.x, 8.0, mapSize.x-8.0), clamp(worldPos.z, 8.0, mapSize.z-8.0)) * invMapSize;
	height = textureLod(heightmapTex, uv, texlod).x;
	worldPos.y = height;
	slope = GetSlope(worldPos, uv);
	worldPos.y += 1.5;

	gl_Position = cameraViewProj * vec4(worldPos, 1.0);
}