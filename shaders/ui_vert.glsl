#version 330 core

uniform mat4 projection;
// POS_LOCATION const
layout(location = 0) in vec2 v_position;
// TEX_COORD_LOCATION const
layout(location = 1) in vec2 tex_coord;
// COLOR_LOCATION const
layout(location = 2) in vec4 v_color;

out vec4 frag_color;
out vec2 frag_uv;

void main() {
  frag_color = v_color;
  frag_uv = tex_coord;
  gl_Position = projection * vec4(v_position, 0.0f, 1.0f);
}
