#version 420

//__DEFINES__

#line 10000

layout (location = 0) in vec4 circlepointposition;
layout (location = 1) in vec4 pos_range;
layout (location = 2) in vec4 wParams;
layout (location = 3) in vec4 color;
layout (location = 4) in float isCannon;

uniform sampler2D heightmapTex;

out DataVS {
	flat vec4 ret_color;
};
#line 11000
//__ENGINEUNIFORMBUFFERDEFS__

#line 12000

#define center            pos_range.xyz
#define dir               circlepointposition.xy
#define range             pos_range.w
#define heightMod         wParams.x
#define projSpeed         wParams.y
#define gravity           wParams.z
#define heightBoostFactor wParams.w

const float pull_z_pow = 1.029;
const float smoothHeight = 100.0;
const float spfactor = 0.7071067; // projectileSpeed factor

vec3  pos = center;
float speed2d;
float speed2dSq;
float heightBoostFactorLocal = heightBoostFactor;
float rangeFactor;
bool aboveWater = center.y > 0.0;
#line 120341

void SetCannonParams() {
	speed2d = projSpeed * spfactor;
	speed2dSq = speed2d * speed2d;
	rangeFactor =  range / ((speed2dSq + speed2d * sqrt(speed2dSq)) / gravity);
	if (rangeFactor > 1.0 || rangeFactor <= 0.0)
		rangeFactor = 1.0;
	if (heightBoostFactor < 0.0)
		heightBoostFactorLocal = (2.0 - rangeFactor) / sqrt(rangeFactor);
}

float GetRange2DCannon(float yDiff) {
	if (yDiff < -smoothHeight)
		yDiff *= heightBoostFactorLocal;
	else if (yDiff < 0.0)
		yDiff *= 1.0 + (heightBoostFactorLocal - 1.0) * -yDiff / smoothHeight;

	float down = 2.0 * gravity * yDiff;
	if (down > speed2dSq)
		return 0.0;
	return rangeFactor * (speed2dSq + speed2d * sqrt(speed2dSq - down)) / gravity;
}

float GetRange2DWeapon(float yDiff) {
	if (yDiff > range || -yDiff > range)
		return 0.0;
	return sqrt(range * range - yDiff * yDiff);
}

float heightAtWorldPos(vec2 w){
	vec2 uvhm =  heightmapUVatWorldPos(w);
	return textureLod(heightmapTex, uvhm, 0.0).x;
}



void FindBallisticPoint() {
	float rAdj = range;
	float yDiff = 0.0;
	
	pos.xz += dir * rAdj;
	float newY = heightAtWorldPos(pos.xz);
	if (aboveWater)
		newY = max(0.0, newY);
	pos.y = newY;

	float heightDiff = (pos.y - center.y) * heightMod;
	float adjRadius = GetRange2DCannon(heightDiff);
	
	float adjustment = rAdj * 0.5;
	
	for (int i = 0; i < 20; i++) {
		if (abs(adjRadius - rAdj) + yDiff <= 0.01 * rAdj)
			break;
		
		if (adjRadius > rAdj)
			rAdj += adjustment;
		else {
			rAdj -= adjustment;
			adjustment *= 0.5;
		}
		
		pos.xz = center.xz + dir * rAdj;
		newY = heightAtWorldPos(pos.xz);
		if (aboveWater)
			newY = max(0.0, newY);
		yDiff = abs(pos.y - newY);
		pos.y = newY;
		heightDiff = (pos.y - center.y) * heightMod;
		adjRadius = GetRange2DCannon(heightDiff);
	}
	return;
}

void FindWeaponPoint() {
	float rAdj = range;
	float yDiff = 0.0;
	pos.xz += dir * rAdj;
	float newY = heightAtWorldPos(pos.xz);
	if (aboveWater)
		newY = max(0.0, newY);
	pos.y = newY;
	float heightDiff = (pos.y - center.y) * heightMod;
	float adjRadius = GetRange2DWeapon(heightDiff);
	
	float adjustment = rAdj * 0.5;
	
	for (int i = 0; i < 16; i++) {
		if (abs(adjRadius - rAdj) + yDiff <= 0.01 * rAdj)
			break;
		
		if (adjRadius > rAdj)
			rAdj += adjustment;
		else {
			rAdj -= adjustment;
			adjustment *= 0.5;
		}
		
		pos.xz = center.xz + dir * rAdj;
		newY = heightAtWorldPos(pos.xz);
		if (aboveWater)
			newY = max(0.0, newY);
		yDiff = abs(pos.y - newY);
		pos.y = newY;
		heightDiff = (pos.y - center.y) * heightMod;
		adjRadius = GetRange2DWeapon(heightDiff);
	}
	return;
}
void main() {
	if (isCannon > 0.0) {
		SetCannonParams();
		FindBallisticPoint();
	}
	else
		FindWeaponPoint();

	pos.y += 5.0;
	ret_color = color;
	vec4 screen_pos = cameraViewProj * vec4(pos.xyz, 1.0);
	float z_ndc = screen_pos.z / screen_pos.w;
	z_ndc = pow(z_ndc, pull_z_pow);
	screen_pos.z = z_ndc * screen_pos.w;
	gl_Position = screen_pos;
}