package js_console

import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import stbtt "vendor:stb/truetype"

/*

 ██████  ██████  ███    ██ ███████ ████████  █████  ███    ██ ████████ ███████ 
██      ██    ██ ████   ██ ██         ██    ██   ██ ████   ██    ██    ██      
██      ██    ██ ██ ██  ██ ███████    ██    ███████ ██ ██  ██    ██    ███████ 
██      ██    ██ ██  ██ ██      ██    ██    ██   ██ ██  ██ ██    ██         ██ 
 ██████  ██████  ██   ████ ███████    ██    ██   ██ ██   ████    ██    ███████ 
-> Constants                                                                              
                                                                               
*/

WIDTH :: 1600
HEIGHT :: 900
GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
BUFFER_SIZE :: 16384

// LOCATIONS in ui_vert.glsl
POS_LOCATION :: 0
TEX_COORD_LOCATION :: 1
COLOR_LOCATION :: 2

EMPTY_TEXTURE_SIZE :: 3

UI_SHADER :: 1
FONT_SHADER :: 2
INVALID_FONT_ID :: 0
INVALID_FV_ID :: 0
INVALID_SHADER_ID :: 0

/*

███████ ████████ ██████  ██    ██  ██████ ████████ ███████ 
██         ██    ██   ██ ██    ██ ██         ██    ██      
███████    ██    ██████  ██    ██ ██         ██    ███████ 
     ██    ██    ██   ██ ██    ██ ██         ██         ██ 
███████    ██    ██   ██  ██████   ██████    ██    ███████ 
-> Structs                                                          
*/

EmptyTexture :: struct {
	id:     u32,
	buf:    [EMPTY_TEXTURE_SIZE * EMPTY_TEXTURE_SIZE * 4]u8,
	width:  i32,
	height: i32,
}

Shader :: enum {
	ui = 0,
	text,
	max,
}

Font :: struct {
	content:  []byte,
	name:     string,
	valid:    bool,
	info:     stbtt.fontinfo,
	ascent:   i32,
	descent:  i32,
	line_gap: i32,
}

FontVariant :: struct {
	font_id:       int,
	size:          i32,
	chars:         map[rune]Char,
	tex_id:        u32,
	scale:         f32,
	atlas_texture: u32,
	atlas_width:   i32,
	atlas_height:  i32,
}

Char :: struct {
	advance_x: f32,
	advance_y: f32,
	bwidth:    i32,
	bheight:   i32,
	xoff:      i32,
	yoff:      i32,
	glyph:     i32,
  tx:        f32,
  buf:       []byte,
}

VertexArray :: struct($T: typeid, $N: int) {
	id:     u32,
	items:  [N]T,
	attrib: i32,
}

ItemsStack :: struct($T: typeid, $N: int) {
	id:    int,
	items: [N]T,
}

Ctx :: struct {
	shaders:            [Shader.max]u32,
  current_shader:     Shader,
	white_tex:          EmptyTexture,
	window_handle:      glfw.WindowHandle,
	uniform_projection: i32,
	vao:                u32,
	verticies:          VertexArray(glm.vec2, BUFFER_SIZE * 4),
	colors:             VertexArray(Color, BUFFER_SIZE * 4),
	tex_coords:         VertexArray(glm.vec2, BUFFER_SIZE * 4),
	inidicies:          VertexArray(u16, BUFFER_SIZE * 6),
	buffer_indx:        int,
	fonts:              ItemsStack(Font, MAX_FONTS_COUNT),
	fontvariants:       ItemsStack(FontVariant, MAX_FONTS_COUNT * MAX_FV_PER_FONT),
	allocator:          mem.Allocator,
}

Color :: struct {
	r, g, b, a: u8,
}

Quad :: struct {
	tl: [2]f32,
	br: [2]f32,
}
/*

 ██████  ██████  ███    ██ ████████ ███████ ██   ██ ████████ 
██      ██    ██ ████   ██    ██    ██       ██ ██     ██    
██      ██    ██ ██ ██  ██    ██    █████     ███      ██    
██      ██    ██ ██  ██ ██    ██    ██       ██ ██     ██    
 ██████  ██████  ██   ████    ██    ███████ ██   ██    ██    
-> Context                                                            
*/

ctx_init :: proc(ctx: ^Ctx) {
	assert(ctx != nil)
	ctx.buffer_indx = 0
	ctx.fonts.id = 1
	ctx.fontvariants.id = 1
	ctx.white_tex.width = EMPTY_TEXTURE_SIZE
	ctx.white_tex.height = EMPTY_TEXTURE_SIZE
  ctx.current_shader = Shader.ui
	for _, i in ctx.white_tex.buf {
		ctx.white_tex.buf = 255
	}  
}

/*

███████ ██   ██  █████  ██████  ███████ ██████  ███████ 
██      ██   ██ ██   ██ ██   ██ ██      ██   ██ ██      
███████ ███████ ███████ ██   ██ █████   ██████  ███████ 
     ██ ██   ██ ██   ██ ██   ██ ██      ██   ██      ██ 
███████ ██   ██ ██   ██ ██████  ███████ ██   ██ ███████ 
-> Shaders
*/

fragment_shaders: [Shader.max]string = {}
vert_shader := "./shaders/ui_vert.glsl"

make_shader :: proc(ctx: ^Ctx, shader: Shader) -> bool {
	if shader == Shader.max {
		return false
	}
	program_id, program_ok := gl.load_shaders_file(vert_shader, fragment_shaders[shader])
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}
	ctx.shaders[shader] = program_id
	return true
}

change_shader :: proc(ctx: ^Ctx, shader: Shader) {
	flush(ctx)
  ctx.current_shader = shader
	program := ctx.shaders[shader]
	gl.UseProgram(program)
	if ctx.uniform_projection < 0 {
		fmt.eprintln("Could not bind uniform projection")
	}
}

init_all_programms :: proc(ctx: ^Ctx) {
	fragment_shaders[Shader.ui] = "./shaders/ui_frag.glsl"
	fragment_shaders[Shader.text] = "./shaders/text_frag.glsl"
	for _, i in ctx.shaders {
		assert(make_shader(ctx, Shader(i)))
	}
}

/*

███████  ██████  ███    ██ ████████ ███████ 
██      ██    ██ ████   ██    ██    ██      
█████   ██    ██ ██ ██  ██    ██    ███████ 
██      ██    ██ ██  ██ ██    ██         ██ 
██       ██████  ██   ████    ██    ███████ 
-> Fonts                                                                                        
*/
default_fonts := []string{"mono", "./resources/JetBrainsMono-Regular.ttf"}
MAX_FONTS_COUNT :: 16
MAX_FV_PER_FONT :: 4
MAX_FONTVARIANTS :: MAX_FONTS_COUNT * MAX_FV_PER_FONT


init_fonts :: proc(ctx: ^Ctx) {
	assert(len(default_fonts) % 2 == 0)
	for i := 0; i < len(default_fonts); i += 2 {
		name := default_fonts[i]
		path := default_fonts[i + 1]
		id := load_font_file(ctx, name, path)
		assert(init_font(ctx, id))
	}
}


/*
██████  ███████ ███████  ██████  ██    ██ ██████   ██████ ███████ ███████ 
██   ██ ██      ██      ██    ██ ██    ██ ██   ██ ██      ██      ██      
██████  █████   ███████ ██    ██ ██    ██ ██████  ██      █████   ███████ 
██   ██ ██           ██ ██    ██ ██    ██ ██   ██ ██      ██           ██ 
██   ██ ███████ ███████  ██████   ██████  ██   ██  ██████ ███████ ███████ 
-> Resources                                                                                                                                                    
*/

free_font_file :: proc(ctx: ^Ctx, id: int) {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts.id)
	content := get_font_file_content(ctx, id)
	delete(content)
	ctx.fonts.items[id].name = ""
	ctx.fonts.items[id].valid = false
}

get_font_file_content :: proc(ctx: ^Ctx, id: int) -> []byte {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts.id)
	return ctx.fonts.items[id].content
}

get_font_id_by_name :: proc(ctx: ^Ctx, name: string) -> int {
  assert(len(name) > 0)
	if ctx.fonts.id == 0 {
		return INVALID_FONT_ID
	}
	for f, indx in ctx.fonts.items[0:ctx.fonts.id] {
		if strings.compare(name, f.name) == 0 {
			return indx
		}
	}
	return INVALID_FONT_ID
}

get_font_info_by_name :: #force_inline proc(ctx: ^Ctx, name: string) -> ^stbtt.fontinfo {
	assert(len(name) > 0)
	if ctx.fonts.id == 0 {
		return nil
	}
	for f, indx in ctx.fonts.items[0:ctx.fonts.id] {
		if strings.compare(name, f.name) == 0 {
			return get_font_info(ctx, indx)
		}
	}
	return nil
}

get_font :: proc(ctx: ^Ctx, id: int) -> ^Font {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts.id)
	return &ctx.fonts.items[id]
}

get_font_info :: #force_inline proc(ctx: ^Ctx, id: int) -> ^stbtt.fontinfo {
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts.id)
	return &ctx.fonts.items[id].info
}

free_fontvariant :: proc(ctx: ^Ctx, id: int) {
	assert(ctx.fontvariants.id < MAX_FONTVARIANTS)
	assert(ctx.fontvariants.id != INVALID_FV_ID)
}

FONT_BUFFER_SIZE :: 1024 * 1024

init_font_variant :: proc(ctx: ^Ctx, fontname: string, size: int) -> int {
	assert(ctx.fontvariants.id < MAX_FONTVARIANTS)
  font_id := get_font_id_by_name(ctx, fontname)

	fontvariant := &ctx.fontvariants.items[ctx.fontvariants.id]
  fontvariant.font_id = font_id
	ctx.fontvariants.id += 1
	fontinfo := get_font_info(ctx, fontvariant.font_id)
	fontvariant.scale = stbtt.ScaleForPixelHeight(fontinfo, f32(size))
  
	x0, y0, x1, y1, advance_x: i32

  // generate asci and cyrillyc symbols
  i := 38
  for i <= 1103 {
		char := Char {
			glyph = stbtt.FindGlyphIndex(fontinfo, rune(i)),
		}
		stbtt.GetGlyphHMetrics(fontinfo, char.glyph, &advance_x, nil)
    char.advance_x = f32(advance_x) * fontvariant.scale
    
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

		fontvariant.atlas_width += char.bwidth
		if fontvariant.atlas_height < char.bheight {
			fontvariant.atlas_height = char.bheight
		}
		fontvariant.chars[rune(i)] = char
    if i == 127 {
      i = 1040
    } else {
      i += 1
    }
	}

	gl.ActiveTexture(gl.TEXTURE1)
	gl.GenTextures(1, &fontvariant.atlas_texture)
	gl.BindTexture(gl.TEXTURE_2D, fontvariant.atlas_texture)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RED,
		fontvariant.atlas_width,
		fontvariant.atlas_height,
		0,
		gl.RED,
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

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexSubImage2D(
      gl.TEXTURE_2D,
      0,
      x,
      0,
      char.bwidth,
      char.bheight,
      gl.RED,
      gl.UNSIGNED_BYTE,
      bytes,
    )
    char.tx = f32(x) / f32(fontvariant.atlas_width)
    x += char.bwidth
	}
  return ctx.fontvariants.id - 1
}

init_font :: proc(ctx: ^Ctx, id: int) -> bool {
	assert(ctx != nil)
	assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts.id)
	content := get_font_file_content(ctx, id)
	assert(content != nil)
	finfo := get_font_info(ctx, id)
	font := get_font(ctx, id)
	stbtt.InitFont(
		finfo,
		raw_data(content),
		stbtt.GetFontOffsetForIndex(raw_data(content), 0),
	) or_return
	stbtt.GetFontVMetrics(finfo, &font.ascent, &font.descent, &font.line_gap)
	return true
}

load_font_file :: proc(ctx: ^Ctx, name: string, path: string) -> int {
	content, ok := os.read_entire_file(path, ctx.allocator)
	assert(ctx.fonts.id < MAX_FONTS_COUNT)
	if (!ok) {
		return INVALID_FONT_ID
	}
	font := &ctx.fonts.items[ctx.fonts.id]
	font.name = name
	font.content = content
	font.valid = true
	ctx.fonts.id += 1
	return ctx.fonts.id - 1
}

init_resources :: proc(ctx: ^Ctx) -> bool {
	assert(ctx != nil)
	init_all_programms(ctx)

	ctx.verticies.attrib = POS_LOCATION
	ctx.tex_coords.attrib = TEX_COORD_LOCATION
	ctx.colors.attrib = COLOR_LOCATION

	gl.GenVertexArrays(1, &ctx.vao)
	gl.BindVertexArray(ctx.vao)

	gl.GenBuffers(1, &ctx.verticies.id)
	gl.GenBuffers(1, &ctx.inidicies.id)
	gl.GenBuffers(1, &ctx.colors.id)
	gl.GenBuffers(1, &ctx.tex_coords.id)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.tex_coords.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.tex_coords.items) * size_of(ctx.tex_coords.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(ctx.tex_coords.attrib))
	gl.VertexAttribPointer(
		u32(ctx.tex_coords.attrib),
		2,
		gl.FLOAT,
		false,
		size_of(ctx.tex_coords.items[0]),
		0,
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.verticies.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.verticies.items) * size_of(ctx.verticies.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(ctx.verticies.attrib))
	gl.VertexAttribPointer(
		u32(ctx.verticies.attrib),
		2,
		gl.FLOAT,
		false,
		size_of(ctx.verticies.items[0]),
		0,
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.colors.id)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.colors.items) * size_of(ctx.colors.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(ctx.colors.attrib))
	gl.VertexAttribPointer(
		u32(ctx.colors.attrib),
		4,
		gl.UNSIGNED_BYTE,
		false,
		size_of(ctx.colors.items[0]),
		0,
	)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ctx.inidicies.id)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(ctx.inidicies.items) * size_of(ctx.inidicies.items[0]),
		nil,
		gl.DYNAMIC_DRAW,
	)

	// White texture
	gl.ActiveTexture(gl.TEXTURE0)
	gl.GenTextures(1, &ctx.white_tex.id)
	gl.BindTexture(gl.TEXTURE_2D, ctx.white_tex.id)

  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		ctx.white_tex.width,
		ctx.white_tex.height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		raw_data(ctx.white_tex.buf[:]),
	)
  gl.GenerateMipmap(gl.TEXTURE_2D)

	return true
}

free_resources :: proc(ctx: ^Ctx) {
}

flush :: proc(ctx: ^Ctx) {
  if ctx.buffer_indx == 0 {
    return
  }
	w, h := glfw.GetWindowSize(ctx.window_handle)
	gl.Viewport(0, 0, w, h)
	projection := glm.mat4Ortho3d(0.0, f32(w), f32(h), 0.0, -1.0, 1.0)

	gl.UniformMatrix4fv(ctx.uniform_projection, 1, false, &projection[0, 0])
	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.verticies.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 4 * size_of(ctx.verticies.items[0]),
		raw_data(ctx.verticies.items[0:ctx.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.colors.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 4 * size_of(ctx.colors.items[0]),
		raw_data(ctx.colors.items[0:ctx.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.tex_coords.id)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 4 * size_of(ctx.tex_coords.items[0]),
		raw_data(ctx.tex_coords.items[0:ctx.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ctx.inidicies.id)
	gl.BufferSubData(
		gl.ELEMENT_ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 6 * size_of(ctx.inidicies.items[0]),
		raw_data(ctx.inidicies.items[0:ctx.buffer_indx * 6]),
	)

	gl.DrawElements(gl.TRIANGLES, i32(ctx.buffer_indx * 6), gl.UNSIGNED_SHORT, nil)
	ctx.buffer_indx = 0
}

push_quad :: proc(ctx: ^Ctx, quad: Quad, color: Color, tex: Quad) {
	if ctx.buffer_indx == BUFFER_SIZE {
		flush(ctx)
	}

	vertex_indx := ctx.buffer_indx * 4
	ctx.verticies.items[vertex_indx + 0] = glm.vec2(quad.tl)
	ctx.verticies.items[vertex_indx + 1] = glm.vec2(quad.br)
	ctx.verticies.items[vertex_indx + 2] = glm.vec2{quad.br.x, quad.tl.y}
	ctx.verticies.items[vertex_indx + 3] = glm.vec2{quad.tl.x, quad.br.y}

	ctx.colors.items[vertex_indx + 0] = color
	ctx.colors.items[vertex_indx + 1] = color
	ctx.colors.items[vertex_indx + 2] = color
	ctx.colors.items[vertex_indx + 3] = color

	ctx.tex_coords.items[vertex_indx + 0] = glm.vec2(tex.tl)
	ctx.tex_coords.items[vertex_indx + 1] = glm.vec2(tex.br)
	ctx.tex_coords.items[vertex_indx + 2] = glm.vec2{tex.br.x, tex.tl.y}
	ctx.tex_coords.items[vertex_indx + 3] = glm.vec2{tex.tl.x, tex.br.y}

	ctx.inidicies.items[ctx.buffer_indx * 6 + 0] = u16(ctx.buffer_indx * 4 + 0)
	ctx.inidicies.items[ctx.buffer_indx * 6 + 1] = u16(ctx.buffer_indx * 4 + 1)
	ctx.inidicies.items[ctx.buffer_indx * 6 + 2] = u16(ctx.buffer_indx * 4 + 2)
	ctx.inidicies.items[ctx.buffer_indx * 6 + 3] = u16(ctx.buffer_indx * 4 + 0)
	ctx.inidicies.items[ctx.buffer_indx * 6 + 4] = u16(ctx.buffer_indx * 4 + 3)
	ctx.inidicies.items[ctx.buffer_indx * 6 + 5] = u16(ctx.buffer_indx * 4 + 1)

	ctx.buffer_indx += 1
}


render_text :: proc(ctx: ^Ctx, text: string, start: [2]f32, color: Color) {
  fv := ctx.fontvariants.items[1]
  if ctx.current_shader != Shader.text {
    flush(ctx)
    change_shader(ctx, .text)
    gl.BindTexture(gl.TEXTURE_2D, fv.atlas_texture)
  }
  
  x0 := i32(start[0])
  y := i32(start[1])
  for r in text {
    ch := fv.chars[r]

    x1 := x0 + ch.xoff
    y1 := y  + i32(f32(get_font(ctx, fv.font_id).ascent) * fv.scale) + ch.yoff
    push_quad(
      ctx,
      Quad{ tl = {f32(x1), f32(y1)}, br = {f32(x1 + ch.bwidth), f32(y1 + ch.bheight)} },
      color,
      Quad{
        tl = {ch.tx, 0.0},
        br = {
          ch.tx + (f32(ch.bwidth) / f32(fv.atlas_width)),
          f32(ch.bheight) / f32(fv.atlas_height),
        } 
      }
    )

    x0 += i32(ch.advance_x)
  } 
}

render_quad :: #force_inline proc(ctx: ^Ctx, x: f32, y: f32, width: f32, height: f32, color: Color) {
  if ctx.current_shader != Shader.ui {
    change_shader(ctx, Shader.ui)
    gl.BindTexture(gl.TEXTURE_2D, ctx.white_tex.id)
  }
  push_quad(
    ctx,
		Quad{tl = {x, y}, br = {x + width, y + height}},
    color,
		Quad{tl = {0.0, 0.0}, br = {1.0, 1.0}}
  )
}

clean :: proc(ctx: ^Ctx) {
  w, h := glfw.GetWindowSize(ctx.window_handle)
  //gl.Viewport(0, 0, w, h)
  gl.Scissor(0, 0, w, h)
  gl.ClearColor(0.0, 0.0, 0.0, 1.0)
  gl.Clear(gl.COLOR_BUFFER_BIT)
}

main_loop :: proc(ctx: ^Ctx) {
	assert(ctx != nil && ctx.window_handle != nil)
  change_shader(ctx, Shader.ui)
  gl.BindTexture(gl.TEXTURE_2D, ctx.white_tex.id)
	for !glfw.WindowShouldClose(ctx.window_handle) {
		// Process all incoming events like keyboard press, window resize, and etc.
		glfw.PollEvents()
    clean(ctx)

		for a := 2; a < 12; a += 1 {
			for b := 2; b < 12; b += 1 {
				i := f32(a)
				j := f32(b)
        render_quad(ctx, j * 100.0, i * 100.0, 80.0, 80.0, Color{ 255, 255, 0, 255 })
			}
		}
    render_text(ctx, "Hel-Яы", {10, 10}, {0x31, 0x74, 0x8f, 255})
    flush(ctx)

		glfw.SwapBuffers(ctx.window_handle)
	}
}


/**
███    ███  █████  ██ ███    ██ 
████  ████ ██   ██ ██ ████   ██ 
██ ████ ██ ███████ ██ ██ ██  ██ 
██  ██  ██ ██   ██ ██ ██  ██ ██ 
██      ██ ██   ██ ██ ██   ████                           
-> MAIN                                
*/

main :: proc() {
	ctx := new(Ctx)
	// TODO: custom allocator, arena? 
	ctx.allocator = context.allocator
	if !bool(glfw.Init()) {
		fmt.eprintln("GLFW has failed to load.")
		return
	}
	ctx_init(ctx)
	init_fonts(ctx)
	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, true)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.SAMPLES, 4)
	ctx.window_handle = glfw.CreateWindow(WIDTH, HEIGHT, "Yasm debug", nil, nil)
	defer glfw.Terminate()
	defer glfw.DestroyWindow(ctx.window_handle)

	if ctx.window_handle == nil {
		fmt.eprintln("GLFW has failed to load the window.")
		return
	}

	glfw.MakeContextCurrent(ctx.window_handle)
	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	gl.Enable(gl.BLEND)
	gl.BlendEquation(gl.FUNC_ADD)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.SCISSOR_TEST)
	gl.Enable(gl.MULTISAMPLE)

	glfw.SwapInterval(0)

  init_font_variant(ctx, "mono", 160)

	init_resources(ctx)
	main_loop(ctx)
}
