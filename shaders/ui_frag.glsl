#version 330 core

in vec4 frag_color;
in vec2 frag_uv;

uniform sampler2D Texture;

void main() {
  gl_FragColor = vec4(
    frag_color.rgb / 255.0f * texture(Texture, frag_uv.st).rgb,
    frag_color.a / 255.0f
  );
}
