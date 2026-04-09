#version 330

//_DEFINES__

#line 20000

//_ENGINEUNIFORMBUFFERDEFS__

in DataVS {
	flat vec4 ret_color;
};

out vec4 fragColor;

void main() {
	fragColor = ret_color;
}