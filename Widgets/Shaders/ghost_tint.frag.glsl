
uniform sampler2D textureS3o1;
uniform sampler2D textureS3o2;

uniform vec4 teamColor;
uniform vec3 tint;
uniform float strength;
const vec3 white = vec3(1.0, 1.0, 1.0);
void main() {
	vec4 tex1 = ( texture2D(textureS3o1, gl_TexCoord[0].st)); // .a is the alpha of the team paint, .r .g and .b is the texture alpha
	float paintAlpha = tex1.a;
	float texAlpha = tex1.r;
	vec4 diffuse = ( texture2D(textureS3o2, gl_TexCoord[0].st));
	vec4 plain = vec4(teamColor.rgb, 0.15);
	// gl_FragColor = tex3.r * 0.25;
	// gl_FragColor = vec4(diffuse.b);

	// gl_FragColor = vec4(teamColor.rgb, (texAlpha*0.75 + paintAlpha*1.25) * 0.5);
	// texAlpha = clamp(texAlpha, 0.0, 0.15) * 2.0;
	// vec4 surlignage = vec4(tex1.rrrr - diffuse.r);
	// vec4 surlignage2 = vec4(tex1.rrrr - diffuse.b - paintAlpha *0.33);
	// diffuse.g = clamp(diffuse.g, 0.15, 0.25);
	// diffuse.b = clamp(diffuse.b, 0.15, 0.25);
	// float alpha = max(diffuse.g, diffuse.b) + diffuse.r;
	// vec4 body = vec4(mix(white, teamColor.rgb, 0.5 + paintAlpha), texAlpha * 0.5);
	// vec4 paint = vec4(teamColor.rgb, paintAlpha * 0.4);
	// vec4 body = vec4(mix(teamColor.rgb, white, 0.3-(paintAlpha * 0.3)), texAlpha * 0.3 +  paintAlpha * 0.2);
	// vec4 body = vec4(white, texAlpha * 0.5 +  paintAlpha * 0.2);
	// gl_FragColor = body + paint;
	// gl_FragColor = body;
	// vec4 paint = vec4(teamColor.rgb, paintAlpha * 0.5);
	// gl_FragColor = body + paint;
	// gl_FragColor = body;
	// vec4 flatten = vec4(teamColor.rgb, texAlpha - diffuse.b * 0.25);
	// gl_FragColor = flatten + surlignage * 0.5;
	// gl_FragColor = flatten;
	// gl_FragColor = surlignage *0.75;
	// gl_FragColor = surlignage2;
	// gl_FragColor = paint;
	// gl_FragColor = vec4(teamColor.rgb, texAlpha);
	// gl_FragColor = vec4(teamColor.rgb, texAlpha*0.2);
	// gl_FragColor = vec4(teamColor.rgb, texAlpha);

	// gl_FragColor = vec4(teamColor.rgb, 0.05 + texAlpha * 0.2);
	// gl_FragColor = vec4(texAlpha);
	// gl_FragColor = vec4(paintAlpha);

	diffuse =  teamColor * 0.15 + diffuse.g*0.2 + ((1-diffuse.g) * teamColor)*0.2;
	// diffuse =  teamColor * 0.15 + diffuse.g*0.2 + ((texAlpha) * teamColor)*0.4;
	// diffuse = mix(teamColor, vec4(texAlpha), 0.5) * 0.7;
	diffuse.rgb *= tint;
	// vec4 color = vec4(min(diffuse));
	gl_FragColor = diffuse ;
	// gl_FragColor = vec4(texAlpha - max(diffuse.b, diffuse.g) * paintAlpha) ;


	
}

