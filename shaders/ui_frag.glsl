#version 330 core

in vec4 frag_color;
in vec2 frag_uv;

uniform sampler2D Texture;
out vec4 Out_Color;

void main() {
  Out_Color =  vec4(frag_color.rgb * texture(Texture, frag_uv.st).rgb, frag_color.a / 255.0f);
}
