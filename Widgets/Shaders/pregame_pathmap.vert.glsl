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
uniform float depth_mul;
uniform float depth_pow;
uniform float texture_mode;
const float inv6 = 1 / 1e6;
uniform float texlod;
out DataVS {
	float slope;
	float height;
};

#line 11022

const ivec2 gridSize = ivec2(mapSize.x / 16.0, mapSize.y / 16.0);

int ssbo_index;
void main() {
	ivec2 gridPos = ivec2((xyworld_xyfract * 0.5 + 0.5) * gridSize);

	vec4 worldPos = vec4(0.0, 0.0, 0.0, 1.0);
	worldPos.xz = mapCenter * (1 + xyworld_xyfract.xy);
	height = textureLod(heightmapTex, worldPos.xz * invMapSize, texlod).x;
	worldPos.y = height + 0.1;
	ssbo_index = gridPos.y * gridSize.x + gridPos.x;
	slope = slopes[ssbo_index/4][ssbo_index%4];

	if (texture_mode < 1.0) {
		gl_Position = cameraViewProj * worldPos;
		float z_ndc = gl_Position.z / gl_Position.w;
		// z_ndc = pow(z_ndc * (1.0 - slope * inv6), depth_pow);
		z_ndc = pow(z_ndc, depth_pow);
		gl_Position.z = z_ndc * gl_Position.w;
	}
	else {
		gl_Position = vec4(
			worldPos.x / mapSize.x * 2.0 - 1.0,
			worldPos.z / mapSize.y * 2.0 - 1.0,
			0.0, 1.0
		);
	}


}