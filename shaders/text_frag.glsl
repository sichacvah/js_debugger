#version 330 core

in vec2 frag_uv;
in vec4 frag_color;
uniform sampler2D tex;

void main(void) {
  //float d = texture2D(tex, frag_uv).r;
  //float aaf = fwidth(d);
  //float alpha = smoothstep(0.5 - aaf, 0.5 + aaf, d);
  //gl_FragColor = vec4(frag_color.rgb, alpha * frag_color.a / 255.0f);

  gl_FragColor =  vec4(frag_color.rgb / 255.0f, texture2D(tex, frag_uv.st).r);
}
