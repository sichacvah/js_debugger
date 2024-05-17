#version 330 core

uniform mat4 projection;
in vec2 v_position;
in vec2 tex_coord;
in vec4 v_color;

out vec4 frag_color;
out vec2 frag_uv;

void main() {
  frag_color = v_color;
  frag_uv = tex_coord;
  gl_Position = projection * vec4(v_position, 0.0f, 1.0f);
}
