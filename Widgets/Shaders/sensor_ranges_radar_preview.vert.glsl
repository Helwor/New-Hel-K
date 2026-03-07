#version 420
#line 10000

// Shader licensed under GNU GPL, v2 or later. Relicensed from MIT, preserving the notice "(c) Beherith (mysterme@gmail.com)".

//__DEFINES__

layout (location = 0) in vec2 xyworld_xyfract;
uniform vec4 radarcenter_range;  // x y z range
uniform vec4 radar_color;
//// PASSED TO GEO SHADER

///*
uniform sampler2D heightmapTex;
uniform float gridLosSize;
uniform float invGridLosSize;
uniform vec2  invMapSize;

out DataVS {
	vec4 worldPos; // pos and radius
	vec4 blendedcolor;
	vec2 xyworld_xyfract_v;
	float obscured;
};

//__ENGINEUNIFORMBUFFERDEFS__

#line 11028

float heightAtWorldPos(vec2 w){
	vec2 uvhm =   vec2(clamp(w.x,8.0,mapSize.x-8.0),clamp(w.y,8.0, mapSize.y-8.0)) * invMapSize;
	return max(0.0, textureLod(heightmapTex, uvhm, 0.0).x);
}

float heightAtLosPos(vec2 w) { // work around to simulate a MIP 2 due to not being able to get more than MIP 1
	vec2 uv = vec2(clamp(w.x, 8.0, mapSize.x-8.0), clamp(w.y, 8.0, mapSize.y-8.0)) * invMapSize;
	vec2 uvstep = 16.0 * invMapSize;
	float sum = 0.0;
	for (int x = -1; x <= 1; x += 2) {
		for (int y = -1; y <= 1; y += 2) {
			sum += textureLod(heightmapTex, uv + vec2(float(x), float(y)) * uvstep, 1.0).r;
		}
	}
	return max(0.0, sum * 0.25);
}

float GetLosHeight(vec2 pos){
	return heightAtLosPos(pos);
}


vec3 worldToLosCenter(vec3 worldPos) {
	vec3 result;
	result.xz = (floor(worldPos.xz * invGridLosSize) + 0.5) * gridLosSize;
	result.y = heightAtLosPos(result.xz);
	return result;
}


float prv_angle = -1e7;
float max_angle = -1e7;
float max_inground = 0.0;
vec3 raypos;
float heightatsample;
vec3 radarPos = radarcenter_range.xyz;
vec3 radarLosPos;
vec3 pointLosPos;


void StepSizeMethod() {
	float steps_f;
	raypos = radarLosPos;
	vec3 fromradar = pointLosPos - raypos;
	steps_f = length(fromradar.xz) / 32.0;
	vec3 smallstep = fromradar / steps_f;

	int steps = int(ceil(steps_f));
	for (int i = 1; i <= steps; i++) {
		raypos += smallstep;
		// max_inground = max(max_inground, heightAtLosPos(raypos.xz) - raypos.y);
		max_inground = max(max_inground, heightAtWorldPos(raypos.xz) - raypos.y);
		if (max_inground >= 0.5) {
			break;
		}
	}
}

void LosDDAMethod() { // Digital Differential Analyzer & angle comparaison inspired from engine code LosMap.cpp/LosHander.cpp (actual los grid cell)
	if (max_inground < 0.5)
		return;

	vec3 rayposLos = raypos;
	rayposLos = worldToLosCenter(raypos);
	float raylosSqDist = dot(rayposLos.xz - radarLosPos.xz, rayposLos.xz - radarLosPos.xz);

	vec2 currentLos = radarLosPos.xz;
	vec2 targetLos = pointLosPos.xz;

	ivec2 startCase = ivec2(floor(currentLos / gridLosSize));
	ivec2 rayCase = ivec2(floor(rayposLos / gridLosSize));
	ivec2 endCase = ivec2(floor(targetLos / gridLosSize));
	ivec2 currentCase = startCase;

	// cell dir
	ivec2 stepDir = ivec2(sign(endCase.x - startCase.x), sign(endCase.y - startCase.y));

	// 2D dir
	vec2 rayDir = targetLos - currentLos;
	float rayLength = length(rayDir);
	if (rayLength > 0.0) rayDir /= rayLength;

	// distance between horizontal cells, and vertical cells
	float tDeltaX = (rayDir.x != 0.0) ? gridLosSize / abs(rayDir.x) : 1e20;
	float tDeltaY = (rayDir.y != 0.0) ? gridLosSize / abs(rayDir.y) : 1e20;

	// current distance to next cell h and v
	float tMaxX, tMaxY;
	if (stepDir.x > 0)
		tMaxX = ((float(currentCase.x) + 1.0) * gridLosSize - currentLos.x) / rayDir.x;
	else if (stepDir.x < 0)
		tMaxX = (currentLos.x - float(currentCase.x) * gridLosSize) / abs(rayDir.x);
	else
		tMaxX = 1e20;
	

	if (stepDir.y > 0)
		tMaxY = ((float(currentCase.y) + 1.0) * gridLosSize - currentLos.y) / rayDir.y;
	else if (stepDir.y < 0)
		tMaxY = (currentLos.y - float(currentCase.y) * gridLosSize) / abs(rayDir.y);
	else
		tMaxY = 1e20;
	
	bool inground = false;
	while (currentCase != endCase) {

		if (tMaxX <= tMaxY) {
			currentCase.x += stepDir.x;
			tMaxX += tDeltaX;
		}
		if (tMaxY <= tMaxX) {
			currentCase.y += stepDir.y;
			tMaxY += tDeltaY;
		}


		currentLos = vec2(currentCase) * gridLosSize + gridLosSize * 0.5;
		vec2 offset = currentLos - radarLosPos.xz;

		if (!inground) {
			inground = dot(offset, offset) >= raylosSqDist;
		}
		if (inground){
			float height = GetLosHeight(currentLos);
			float invR = inversesqrt(dot(offset, offset) + 1e-6);
			float dh = height - radarLosPos.y;
			float angle = (dh + 5.0) * invR;
			// if (!inground && dot(offset, offset) >= raylosSqDist)
			if (angle < max_angle) {
				obscured = 1.0;
				prv_angle = angle;
				break;
			}
			if (angle < prv_angle) {
				float temp_angle = prv_angle - 5.0 * invR;
				if (angle < temp_angle) {
					obscured = 1.0;
					max_angle = temp_angle;
					prv_angle = angle;
					break;
				}
				max_angle = temp_angle;
			}
			
			prv_angle = angle;
		}
	}
}


void main() {
	worldPos = vec4(0.0);
	worldPos.xz = (radarcenter_range.xz + (xyworld_xyfract.xy * radarcenter_range.w)); // transform it out in XZ
	worldPos.y = heightAtWorldPos(worldPos.xz) + 5.0; // get the world height at that point
	raypos = worldPos.xyz;
	float radarEmitHeight = radarcenter_range.y - heightAtWorldPos(radarcenter_range.xz);
	radarLosPos = worldToLosCenter(radarPos);
	radarLosPos.y += radarEmitHeight;
	pointLosPos = worldToLosCenter(worldPos.xyz);
	pointLosPos.y += 5.0;

	blendedcolor = radar_color;
	xyworld_xyfract_v = xyworld_xyfract;
	obscured = 0.0;


	StepSizeMethod();
	LosDDAMethod();

	// obscured = step(0.1, max_inground);
	worldPos = vec4(worldPos);
	blendedcolor = vec4(radar_color.rgb, 0.0);
	// blendedcolor.a = min(0.8-clamp(max_inground*0.5,0.4,1.0),0.5);
	blendedcolor.a = mix(0.5, 0.0, obscured);
	// if (max_inground >= 2.0) {
	//     blendedcolor.r = 1.0; // Rouge si entré dans le sol
	// } else {
	//     blendedcolor.g = 1.0; // Vert sinon
	// }

	worldPos.y += 5.0;
	gl_Position = cameraViewProj * vec4(worldPos.xyz, 1.0);
}