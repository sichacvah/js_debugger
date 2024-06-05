package renderer

import "core:fmt"
import stbtt "vendor:stb/truetype"
import "core:math"
import "vendor:glfw"
import "core:mem"
import glm "core:math/linalg/glsl"
import "core:strings"
import gl "vendor:OpenGL"
import "core:os"
import "core:unicode/utf8"

/*

██████  ███████ ███    ██ ██████  ███████ ██████  ███████ ██████  
██   ██ ██      ████   ██ ██   ██ ██      ██   ██ ██      ██   ██ 
██████  █████   ██ ██  ██ ██   ██ █████   ██████  █████   ██████  
██   ██ ██      ██  ██ ██ ██   ██ ██      ██   ██ ██      ██   ██ 
██   ██ ███████ ██   ████ ██████  ███████ ██   ██ ███████ ██   ██ 
-> Renderer                                                                  

Plain Open Gl renderer for ui purporse

Public API:

- render_quad
- render_img
- render_text_line

*/


/*

 ██████  ██████  ███    ██ ███████ ████████  █████  ███    ██ ████████ ███████ 
██      ██    ██ ████   ██ ██         ██    ██   ██ ████   ██    ██    ██      
██      ██    ██ ██ ██  ██ ███████    ██    ███████ ██ ██  ██    ██    ███████ 
██      ██    ██ ██  ██ ██      ██    ██    ██   ██ ██  ██ ██    ██         ██ 
 ██████  ██████  ██   ████ ███████    ██    ██   ██ ██   ████    ██    ███████ 
-> Constants                                                                                                                                                   
*/

/*
  LOCATIONS in ui_vert.glsl
  defined with layout(location = *SOMECONST*)
*/
POS_LOCATION :: 0
TEX_COORD_LOCATION :: 1
COLOR_LOCATION :: 2

// Buffer size for verticies
BUFFER_SIZE :: 16384
// Empty white texture size 
EMPTY_TEXTURE_SIZE :: 3


INVALID_FONT_ID :: 0
INVALID_FV_ID :: 0
INVALID_SHADER_ID :: 0

MAX_FONTS_COUNT :: 16
MAX_FV_PER_FONT :: 4
MAX_FONTVARIANTS :: MAX_FONTS_COUNT * MAX_FV_PER_FONT

/*

███████ ████████ ██████  ██    ██  ██████ ████████ ███████ 
██         ██    ██   ██ ██    ██ ██         ██    ██      
███████    ██    ██████  ██    ██ ██         ██    ███████ 
     ██    ██    ██   ██ ██    ██ ██         ██         ██ 
███████    ██    ██   ██  ██████   ██████    ██    ███████ 
-> Structs                                                          
*/

/*
Using same shader for both ui and image render
*/
EmptyTexture :: struct {
	id:     u32,
	buf:    [EMPTY_TEXTURE_SIZE * EMPTY_TEXTURE_SIZE * 4]u8,
	width:  i32,
	height: i32,
}

/*
Using different shader for text
*/
Shader :: enum {
	ui = 0,
	text,
	max,
}

FontVerticalMetrics :: struct {
  ascent: i32,
  line_gap: i32,
  descent: i32,
}

Font :: struct {
  // ttf file content
  content: []byte,
  name: string,
  info: stbtt.fontinfo,
  vm: FontVerticalMetrics,
}

FontVariantAtlas :: struct {
  tex_id: u32,
  width:  i32,
  height: i32,
}

FontVariant :: struct {
  font_id: int,
  size:    i32,
  chars:   map[rune]Char,
  scale:   f32,
  atlas:   FontVariantAtlas,
  ascent:  i32,
  descent: i32,
  // from fontstash
  ascender: f32,
  descender: f32,
  lineheight: f32,
}

Char :: struct {
  advance_x: f32,
  left_bearing: f32,
  bwidth:    i32,
  bheight:   i32,
  xoff:      i32,
  yoff:      i32,
  glyph:     i32,
  tex_x:     f32,
}

VertexArray :: struct($T: typeid, $N: int) {
  id: u32,
  items: [N]T,
  attrib: i32,
}

ItemsStack :: struct($T: typeid, $N: int) {
  id: int,
  items: [N]T,
}

Color :: struct {
	r, g, b, a: u8,
}

Quad :: struct {
	tl: [2]f32,
	br: [2]f32,
}

Renderer :: struct {
  shaders: [Shader.max]u32,
  current_shader: Shader,
  white_tex: EmptyTexture,
  window_handle: glfw.WindowHandle,
  uniform_projection: i32,
  vao: u32,
  verticies: VertexArray(glm.vec2, BUFFER_SIZE * 4),
  colors:    VertexArray(Color, BUFFER_SIZE * 4),
  tex_coords: VertexArray(glm.vec2, BUFFER_SIZE * 4),
  indicies:  VertexArray(u16, BUFFER_SIZE * 6),
  buffer_indx: int,
  // Add one for invalid font/fontvariant
  fonts: ItemsStack(Font, MAX_FONTS_COUNT + 1),
  fontvariants: ItemsStack(FontVariant, MAX_FONTS_COUNT * MAX_FV_PER_FONT + 1),
}


/*

██████  ███████ ███    ██ ██████  ███████ ██████  ███████ ██████  
██   ██ ██      ████   ██ ██   ██ ██      ██   ██ ██      ██   ██ 
██████  █████   ██ ██  ██ ██   ██ █████   ██████  █████   ██████  
██   ██ ██      ██  ██ ██ ██   ██ ██      ██   ██ ██      ██   ██ 
██   ██ ███████ ██   ████ ██████  ███████ ██   ██ ███████ ██   ██ 
-> Renderer                                                                                                                                    
*/

renderer_init :: proc(allocator: mem.Allocator) -> ^Renderer {
  r := new(Renderer, allocator)
  assert(r != nil)
  r.buffer_indx = 0
  r.fonts.id = 1
  r.fontvariants.id = 1
  r.white_tex.width = EMPTY_TEXTURE_SIZE
  r.white_tex.height = EMPTY_TEXTURE_SIZE
  r.current_shader = Shader.ui
  for _, i in r.white_tex.buf {
    r.white_tex.buf[i] = 255
  }
  return r
}

renderer_destroy :: proc(r: ^Renderer, allocator: mem.Allocator) {
  if r.fonts.id > 1 {
    for i := 1; i < r.fonts.id; i += 1 {
      font_destroy(r, i)
    }
  }
  if r.fontvariants.id > 1 {
    for i := 1; i < r.fontvariants.id; i += 1 {
      delete_map(r.fontvariants.items[i].chars)
    }
  }
  free(r, allocator)
} 

get_font_file_content :: proc(r: ^Renderer, id: int) -> []byte {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < r.fonts.id)
	return r.fonts.items[id].content
}

font_destroy :: proc(r: ^Renderer, id: int) {
  assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < r.fonts.id)
  content := get_font_file_content(r, id)
  delete(content)
  r.fonts.items[id].name = ""
}

get_font_id_by_name :: proc(r: ^Renderer, name: string) -> int {
  assert(len(name) > 0)
	if r.fonts.id == 0 {
		return INVALID_FONT_ID
	}
	for f, indx in r.fonts.items[1:r.fonts.id] {
		if strings.compare(name, f.name) == 0 {
			return indx + 1
		}
	}
	return INVALID_FONT_ID
}

get_font_info :: #force_inline proc(r: ^Renderer, id: int) -> ^stbtt.fontinfo {
	assert(id < MAX_FONTS_COUNT)
  assert(id != INVALID_FONT_ID)
  assert(id < r.fonts.id)
	return &r.fonts.items[id].info
}

load_symbols :: #force_inline proc(fontinfo: ^stbtt.fontinfo, fontvariant: ^FontVariant, runes: []rune) {
  x0, y0, x1, y1, advance_x: i32
  left_bearing: i32
  for r in runes {
    char := Char {
      glyph = stbtt.FindGlyphIndex(fontinfo, r)
    }

    stbtt.GetGlyphHMetrics(fontinfo, char.glyph, &advance_x, &left_bearing)
    char.advance_x = f32(advance_x) * fontvariant.scale
    char.left_bearing = f32(left_bearing) * fontvariant.scale

    stbtt.GetGlyphBitmapBox(
      fontinfo,
      char.glyph,
      fontvariant.scale,
      fontvariant.scale,
      &x0,
      &y0,
      &x1,
      &y1,
    )

    char.bwidth = x1 - x0
    char.bheight = y1 - y0

    fontvariant.atlas.width += char.bwidth
    if fontvariant.atlas.height < char.bheight {
      fontvariant.atlas.height = char.bheight
    }
    fontvariant.chars[r] = char
  }
}

ASCI_SIZE :: 96
ASCI_START :: 32
asci_symbols := [ASCI_SIZE]rune{}
CYRILLYC_SIZE :: 63
CYRILLYC_START :: 1040
cyrillyc_symbols := [CYRILLYC_SIZE]rune{}

init_default_symbols :: proc() {
  @(static) is_inited := false

  if !is_inited {
    is_inited = true
    for  i := 0; i < ASCI_SIZE; i += 1 {
      asci_symbols[i] = rune(i + ASCI_START)
    }
    for i := 0; i < CYRILLYC_SIZE; i += 1 {
      cyrillyc_symbols[i] = rune(i + CYRILLYC_START)
    }
  }
}


init_font_variant :: proc(r: ^Renderer, allocator: mem.Allocator, fontname: string, size: int) -> int {
  init_default_symbols()
  assert(r.fontvariants.id < MAX_FONTVARIANTS)
  font_id := get_font_id_by_name(r, fontname)
  assert(font_id != INVALID_FONT_ID)
  
  fontvariant := &r.fontvariants.items[r.fontvariants.id]
  fontvariant.font_id = font_id
  fontvariant.size = i32(size) 

  r.fontvariants.id += 1
  fontinfo := get_font_info(r, font_id)
  fontvariant.scale = stbtt.ScaleForPixelHeight(fontinfo, f32(size))
  vm := get_font(r, font_id).vm
  fh := f32(vm.ascent - vm.descent)

  fontvariant.ascender = f32(vm.ascent) / fh
  fontvariant.descender = f32(vm.descent) / fh
  fontvariant.lineheight = (fh + f32(vm.line_gap)) / fh

  fontvariant.ascent = get_font(r, font_id).vm.ascent
  fontvariant.descent = get_font(r, font_id).vm.descent
  load_symbols(fontinfo, fontvariant, asci_symbols[:])
  load_symbols(fontinfo, fontvariant, cyrillyc_symbols[:])
  load_symbols(fontinfo, fontvariant, {'▶', '▼'})
   
  //gl.ActiveTexture(gl.TEXTURE1)
  gl.GenTextures(1, &fontvariant.atlas.tex_id) 
  gl.BindTexture(gl.TEXTURE_2D, fontvariant.atlas.tex_id)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

  gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
 
  gl.TexImage2D(
    gl.TEXTURE_2D,
    0,
    gl.RGBA,
    fontvariant.atlas.width,
    fontvariant.atlas.height,
    0,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    nil,
  )

  x : i32 = 0 
  for cp, &char in fontvariant.chars {
    bytes := stbtt.GetGlyphBitmap(
      fontinfo,
      fontvariant.scale,
      fontvariant.scale,
      char.glyph,
      &char.bwidth,
      &char.bheight,
      &char.xoff,
      &char.yoff
    )
    rgba_bytes := make([]byte, char.bwidth * char.bheight * 4, allocator)
    for i : i32 = 0; i < char.bwidth * char.bheight; i += 1 {
      rgba_bytes[i*4 + 0] = 255
      rgba_bytes[i*4 + 1] = 255
      rgba_bytes[i*4 + 2] = 255
      rgba_bytes[i*4 + 3] = bytes[i]
    }
    
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexSubImage2D(
      gl.TEXTURE_2D,
      0,
      x,
      0,
      char.bwidth,
      char.bheight,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      raw_data(rgba_bytes),
    )
    char.tex_x = f32(x) / f32(fontvariant.atlas.width)
    x += char.bwidth
  }

  return r.fontvariants.id - 1
}

init_font :: proc(r: ^Renderer, allocator: mem.Allocator, name: string, path: string) -> int {
  assert(r != nil) 
	content, ok := os.read_entire_file(path, allocator)
  if !ok {
    return INVALID_FONT_ID
  }
  assert(r.fonts.id + 1 <= MAX_FONTS_COUNT)
  id := r.fonts.id
  font :=  &r.fonts.items[id]
  font.name = name
  font.content = content
  {
    ok := stbtt.InitFont(
      &font.info,
      raw_data(content),
      stbtt.GetFontOffsetForIndex(raw_data(content), 0),
    )
    if !ok {
      return INVALID_FONT_ID
    }
  }
  stbtt.GetFontVMetrics(
    &font.info,
    &font.vm.ascent,
    &font.vm.descent,
    &font.vm.line_gap
  )
  r.fonts.id += 1
  return id
}

make_shader :: proc(r: ^Renderer, shader: Shader) -> bool {
	if shader == Shader.max {
		return false
	}
	program_id, program_ok := gl.load_shaders_file(vert_shader, fragment_shaders[shader])
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}
	r.shaders[shader] = program_id
	return true
}

fragment_shaders: [Shader.max]string = {}
vert_shader := "./shaders/ui_vert.glsl"


init_all_programms :: proc(r: ^Renderer) {
	fragment_shaders[Shader.ui] = "./shaders/ui_frag.glsl"
	fragment_shaders[Shader.text] = "./shaders/text_frag.glsl"
	for _, i in r.shaders {
		assert(make_shader(r, Shader(i)))
	}
}

render_quad :: #force_inline proc(r: ^Renderer, x: f32, y: f32, width: f32, height: f32, color: Color) {
  if r.current_shader != Shader.ui {
    change_shader(r, Shader.ui)
    gl.BindTexture(gl.TEXTURE_2D, r.white_tex.id)
  }
  push_quad(
    r,
		Quad{tl = {x, y}, br = {x + width, y + height}},
    color,
		Quad{tl = {0.0, 0.0}, br = {1.0, 1.0}}
  )
}

get_font :: proc(r: ^Renderer, id: int) -> ^Font {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < r.fonts.id)
	return &r.fonts.items[id]
}

flush :: proc(r: ^Renderer) {
  if r.buffer_indx == 0 {
    return
  }
	w, h := glfw.GetWindowSize(r.window_handle)
	gl.Viewport(0, 0, w, h)
	projection := glm.mat4Ortho3d(0.0, f32(w), f32(h), 0.0, -1.0, 1.0)

	gl.UniformMatrix4fv(r.uniform_projection, 1, false, &projection[0, 0])
	gl.BindBuffer(gl.ARRAY_BUFFER, r.verticies.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		r.buffer_indx * 4 * size_of(r.verticies.items[0]),
		raw_data(r.verticies.items[0:r.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.colors.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		r.buffer_indx * 4 * size_of(r.colors.items[0]),
		raw_data(r.colors.items[0:r.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.tex_coords.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		r.buffer_indx * 4 * size_of(r.tex_coords.items[0]),
		raw_data(r.tex_coords.items[0:r.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.indicies.id)
	gl.BufferSubData(
		gl.ELEMENT_ARRAY_BUFFER,
		0,
		r.buffer_indx * 6 * size_of(r.indicies.items[0]),
		raw_data(r.indicies.items[0:r.buffer_indx * 6]),
	)

	gl.DrawElements(gl.TRIANGLES, i32(r.buffer_indx * 6), gl.UNSIGNED_SHORT, nil)
	r.buffer_indx = 0
}

push_quad :: proc(r: ^Renderer, quad: Quad, color: Color, tex: Quad) {
	if r.buffer_indx == BUFFER_SIZE {
		flush(r)
	}

	vertex_indx := r.buffer_indx * 4
	r.verticies.items[vertex_indx + 0] = glm.vec2(quad.tl)
	r.verticies.items[vertex_indx + 1] = glm.vec2(quad.br)
	r.verticies.items[vertex_indx + 2] = glm.vec2{quad.br.x, quad.tl.y}
	r.verticies.items[vertex_indx + 3] = glm.vec2{quad.tl.x, quad.br.y}

	r.colors.items[vertex_indx + 0] = color
	r.colors.items[vertex_indx + 1] = color
	r.colors.items[vertex_indx + 2] = color
	r.colors.items[vertex_indx + 3] = color

	r.tex_coords.items[vertex_indx + 0] = glm.vec2(tex.tl)
	r.tex_coords.items[vertex_indx + 1] = glm.vec2(tex.br)
	r.tex_coords.items[vertex_indx + 2] = glm.vec2{tex.br.x, tex.tl.y}
	r.tex_coords.items[vertex_indx + 3] = glm.vec2{tex.tl.x, tex.br.y}

	r.indicies.items[r.buffer_indx * 6 + 0] = u16(r.buffer_indx * 4 + 0)
	r.indicies.items[r.buffer_indx * 6 + 1] = u16(r.buffer_indx * 4 + 1)
	r.indicies.items[r.buffer_indx * 6 + 2] = u16(r.buffer_indx * 4 + 2)
	r.indicies.items[r.buffer_indx * 6 + 3] = u16(r.buffer_indx * 4 + 0)
	r.indicies.items[r.buffer_indx * 6 + 4] = u16(r.buffer_indx * 4 + 3)
	r.indicies.items[r.buffer_indx * 6 + 5] = u16(r.buffer_indx * 4 + 1)

	r.buffer_indx += 1
}

render_rune :: proc(rendr: ^Renderer, r: rune, x: f32, y: f32, color: Color, fv: int) {
  fv := rendr.fontvariants.items[fv]
  if rendr.current_shader != Shader.text {
    flush(rendr)
    change_shader(rendr, .text)
    gl.BindTexture(gl.TEXTURE_2D, fv.atlas.tex_id)
  }
  
  x0 := i32(x)
  y := i32(y)
  ascent := f32(get_font(rendr, fv.font_id).vm.ascent) * fv.scale
  ch := fv.chars[r]

  x1 := x0 + ch.xoff
  y1 := y  + ch.yoff + i32(ascent)
  push_quad(
    rendr,
    Quad{ tl = {f32(x1), f32(y1)}, br = {f32(x1 + ch.bwidth), f32(y1 + ch.bheight)} },
    color,
    Quad{
      tl = {ch.tex_x, 0.0},
      br = {
        ch.tex_x + (f32(ch.bwidth) / f32(fv.atlas.width)),
        f32(ch.bheight) / f32(fv.atlas.height),
      }
    }
  )

  x0 += i32(ch.advance_x)
}

Rect :: struct {
  x: i32,
  y: i32,
  w: i32,
  h: i32,
}

zero_rect :: proc(rect: ^Rect) -> bool {
  return rect.x > 0 || rect.y > 0 || rect.w > 0 || rect.h > 0
}

get_string_size :: proc(rendr: ^Renderer, str: string, fv: int) -> (w: i32, h: i32) {
  if rendr == nil {
    return
  }
  if rendr.fontvariants.id < fv || fv == INVALID_FV_ID {
    assert(false, "Wrong font variant id")
  }
  fv := rendr.fontvariants.items[fv]
  font := get_font(rendr, fv.font_id)
  for r in str {
    ch := fv.chars[r]
    w += i32(ch.advance_x)
  } 
  h = i32(f32(fv.size) * fv.scale)
  return 
}

measure_text :: proc(rendr: ^Renderer, text: string, fv: int) -> i32 {
  return render_text(rendr, text, {0, 0}, {0,0,0,0}, fv, false)
}

render_text :: proc(rendr: ^Renderer, text: string, start: [2]i32, color: Color, fv: int, should_render: bool = true) -> i32 {
  fv := rendr.fontvariants.items[fv]
  if should_render && rendr.current_shader != Shader.text {
    change_shader(rendr, .text)
    //gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, fv.atlas.tex_id)
  }
 
  font := get_font(rendr, fv.font_id)
  x0 := start[0]
  y := start[1]
  ascent := f32(fv.ascent) * fv.scale
  i := 0;
  for i < len(text) {
    
    r, size := utf8.decode_rune_in_string(text[i:])
    ch := fv.chars[r]
    x1 := f32(x0 + ch.xoff)
    y1 := f32(y  + ch.yoff) + ascent
    if r == rune(' ') || r == rune('\t') {
      x0 += i32(ch.advance_x)
      i += size
      continue
    }
    if should_render {
      push_quad(
        rendr,
        Quad{ tl = {x1, y1}, br = {x1 + f32(ch.bwidth), y1 + f32(ch.bheight)} },
        color,
        Quad{
          tl = {ch.tex_x, 0.0},
          br = {
            ch.tex_x + (f32(ch.bwidth) / f32(fv.atlas.width)),
            f32(ch.bheight) / f32(fv.atlas.height),
          }
        }
      )
    }
    i += size
    x0 += i32(math.round(ch.advance_x))
  }
  
  return i32(x0) - start.x
}

clean :: proc(r: ^Renderer) {
  w, h := glfw.GetWindowSize(r.window_handle)
  gl.Scissor(0, 0, w, h)
  gl.ClearColor(0x19 / 255.0, 0x17 / 255.0, 0x24 / 255.0, 1.0)
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

clip :: proc(r: ^Renderer, x, y, w, h: i32) {
  flush(r)
  gl.Scissor(x, y, w, h)
}

change_shader :: proc(r: ^Renderer, shader: Shader) {
	flush(r)
  r.current_shader = shader
	program := r.shaders[shader]
	gl.UseProgram(program)
	if r.uniform_projection < 0 {
		fmt.eprintln("Could not bind uniform projection")
	}
}

get_line_gap :: proc(r: ^Renderer, fv_id: int) -> i32 {
  assert(fv_id != INVALID_FV_ID)
  assert(fv_id < r.fontvariants.id)
  fv := &r.fontvariants.items[fv_id]
  assert(fv != nil)
  font := get_font(r, fv_id) 
  assert(font != nil)
  return font.vm.line_gap
}

get_text_height :: proc(r: ^Renderer, fv_id: int) -> i32 {
  assert(fv_id != INVALID_FV_ID)
  assert(fv_id < r.fontvariants.id)
  fv := &r.fontvariants.items[fv_id]
  assert(fv != nil)
  return i32(fv.lineheight) * fv.size
}

init_resources :: proc(r: ^Renderer) -> bool {
  assert(r != nil)
  init_all_programms(r)

  r.verticies.attrib = POS_LOCATION
  r.tex_coords.attrib = TEX_COORD_LOCATION
  r.colors.attrib = COLOR_LOCATION

  gl.GenVertexArrays(1, &r.vao)
  gl.BindVertexArray(r.vao)

  gl.GenBuffers(1, &r.verticies.id)
	gl.GenBuffers(1, &r.indicies.id)
	gl.GenBuffers(1, &r.colors.id)
	gl.GenBuffers(1, &r.tex_coords.id)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.tex_coords.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(r.tex_coords.items) * size_of(r.tex_coords.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(r.tex_coords.attrib))
	gl.VertexAttribPointer(
		u32(r.tex_coords.attrib),
		2,
		gl.FLOAT,
		false,
		size_of(r.tex_coords.items[0]),
		0,
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.verticies.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(r.verticies.items) * size_of(r.verticies.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(r.verticies.attrib))
	gl.VertexAttribPointer(
		u32(r.verticies.attrib),
		2,
		gl.FLOAT,
		false,
		size_of(r.verticies.items[0]),
		0,
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.colors.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(r.colors.items) * size_of(r.colors.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(r.colors.attrib))
	gl.VertexAttribPointer(
		u32(r.colors.attrib),
		4,
		gl.UNSIGNED_BYTE,
		false,
		size_of(r.colors.items[0]),
		0,
	)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.indicies.id)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(r.indicies.items) * size_of(r.indicies.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)

	// White texture
	//gl.ActiveTexture(gl.TEXTURE0)
	gl.GenTextures(1, &r.white_tex.id)
	gl.BindTexture(gl.TEXTURE_2D, r.white_tex.id)

  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		r.white_tex.width,
		r.white_tex.height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		raw_data(r.white_tex.buf[:]),
	)
  gl.GenerateMipmap(gl.TEXTURE_2D)

	return true
}
