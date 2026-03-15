#version 420
#extension GL_ARB_shader_storage_buffer_object : require
//__DEFINES__
//__ENGINEUNIFORMBUFFERDEFS__

#line 9007

layout(std430, binding = 4) buffer SlopeBuffer {
    vec4 slopes[];
};
layout (location = 0) in vec2 xyworld_xyfract;
uniform sampler2D heightmapTex;
uniform vec2  invMapSize;
uniform vec2  mapCenter;
uniform float resolution;
out DataVS {
	float slope;
	float height;
};


#line 11022


const ivec2 gridSize = ivec2(mapSize.x / resolution, mapSize.y / resolution);
const float texlod = 1.0;
int ssbo_index;
void main() {
    ivec2 gridPos = ivec2((xyworld_xyfract * 0.5 + 0.5) * gridSize);
    ssbo_index = gridPos.y * gridSize.x + gridPos.x;

	vec3 worldPos = vec3(0.0);
	worldPos.xz = mapCenter * (1 + xyworld_xyfract.xy);
	vec2 uv = vec2(clamp(worldPos.x, 8.0, mapSize.x-8.0), clamp(worldPos.z, 8.0, mapSize.y-8.0)) * invMapSize;
	height = textureLod(heightmapTex, uv, texlod).x;
	worldPos.y = height;
	slope = slopes[ssbo_index/4][ssbo_index%4];
	worldPos.y += 0.0;
	gl_Position = cameraViewProj * vec4(worldPos, 1.0);
}