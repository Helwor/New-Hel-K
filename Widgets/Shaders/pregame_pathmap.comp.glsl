#version 430
#extension GL_ARB_shader_storage_buffer_object : require
//__DEFINES__
//__ENGINEUNIFORMBUFFERDEFS__

#line 9007

layout(local_size_x = 8, local_size_y = 8) in;
layout(std430, binding = 4) buffer Data {
	vec4 slopes[];
};
uniform sampler2D heightmapTex;
uniform vec2  invMapSize;
uniform vec2  mapCenter;
uniform float resolution;


#line 11021

const vec2 uvstep = 8.1 * invMapSize;
const ivec2 gridSize = ivec2(mapSize.x/resolution, mapSize.y/resolution);
const float texlod = 1.0;

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
	uvec2 gridPos = gl_GlobalInvocationID.xy;
    if (gridPos.x >= gridSize.x || gridPos.y >= gridSize.y)
    	return;
	vec3 worldPos = vec3(0.0);
	vec2 xyworld_xyfract = (vec2(gridPos) / vec2(gridSize)) * 2.0 - 1.0;
	worldPos.xz = mapCenter * (1.0 + xyworld_xyfract);
	vec2 uv = vec2(clamp(worldPos.x, 8.0, mapSize.x-8.0), clamp(worldPos.z, 8.0, mapSize.y-8.0)) * invMapSize;
	worldPos.y = textureLod(heightmapTex, uv, texlod).x;
	int ssbo_index = int(gridPos.y) * gridSize.x + int(gridPos.x);
	slopes[ssbo_index/4][ssbo_index%4] = GetSlope(worldPos, uv);
}