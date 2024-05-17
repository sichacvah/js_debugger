package js_console

import "core:fmt"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:mem"
import "core:os"
import "core:strings"
import stbtt "vendor:stb/truetype"

WIDTH :: 1600
HEIGHT :: 900
GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
BUFFER_SIZE :: 16384

atlas_width := 3 
atlas_height := 3
white_tex : [3 * 3 * 3]u8 = {
  255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255,
}
tex_id : u32

MAX_SHADERS_COUNT :: 10
UI_SHADER :: 1

Vertex :: struct {
  
}


Ctx :: struct {
  shaders:            [MAX_SHADERS_COUNT + 1]u32,
	window_width:       i32,
	window_height:      i32,
	title:              string,
	window_handle:      glfw.WindowHandle,
	program:            u32,
	attrib_v_position:  i32,
	attrib_v_color:     i32,
	uniform_projection: i32,
  attrib_tex_coord:   i32,
	vbo:                u32,
	cbo:                u32,
	vao:                u32,
	ebo:                u32,
  tbo:                u32,
	vertex_buffer:      [BUFFER_SIZE * 4]glm.vec2,
	elements_buffer:    [BUFFER_SIZE * 6]u16,
	colors_buffer:      [BUFFER_SIZE * 4]Color,
  tex_buffer:         [BUFFER_SIZE * 4]glm.vec2,
	buffer_indx:        int,
  // one for invalid font
  fonts:              [MAX_FONTS_COUNT + 1]Font,
  fonts_count:        int,
  allocator:          mem.Allocator,
  text_shader:        u32,
  font_tex_id:        u32, 
  font_vertext_buffer:[BUFFER_SIZE * 4]glm.vec2,
}

INVALID_FONT_ID :: 0

Color :: struct {
	r, g, b, a: u8,
}

ctx_init :: proc(ctx: ^Ctx) {
	assert(ctx != nil)
	ctx.buffer_indx = 0
  ctx.fonts_count = 1
}

Quad :: struct {
	tl:    [2]f32,
	br:    [2]f32,
}


/*

███████  ██████  ███    ██ ████████ ███████ 
██      ██    ██ ████   ██    ██    ██      
█████   ██    ██ ██ ██  ██    ██    ███████ 
██      ██    ██ ██  ██ ██    ██         ██ 
██       ██████  ██   ████    ██    ███████ 
-> Fonts                                                                                        
*/


/*
██████  ███████ ███████  ██████  ██    ██ ██████   ██████ ███████ ███████ 
██   ██ ██      ██      ██    ██ ██    ██ ██   ██ ██      ██      ██      
██████  █████   ███████ ██    ██ ██    ██ ██████  ██      █████   ███████ 
██   ██ ██           ██ ██    ██ ██    ██ ██   ██ ██      ██           ██ 
██   ██ ███████ ███████  ██████   ██████  ██   ██  ██████ ███████ ███████ 
-> Resources                                                                                                                                                    
*/

default_fonts := []string{"mono", "./resources/JetBrainsMono-Regular.ttf"}

init_fonts :: proc(ctx: ^Ctx) {
  assert(len(default_fonts) % 2 == 0)  
  for i := 0; i < len(default_fonts); i += 2 {
    name := default_fonts[i]
    path := default_fonts[i + 1] 
    id := load_font_file(ctx, name, path)
    assert(init_font(ctx, id))
  }
}

MAX_FONTS_COUNT :: 16

Font :: struct {
  content: []byte,
  name: string,
  valid: bool,
  info:  stbtt.fontinfo,
}

FontVariant :: struct {
  font_id: int,
  size:    i32,
  chars:   map[rune]Char,
  tex_id:  u32,
}

Char :: struct {
  advance_x : i32,
  advance_y : i32,
  bwidth:     i32,
  bheight:    i32,
  xoff:       i32,
  yoff:       i32,
  idx:        i32,
}

free_font_file :: proc(ctx: ^Ctx, id: int) {
  assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts_count)
  content := get_font_file_content(ctx, id)  
  delete(content)
  ctx.fonts[id].name = ""
  ctx.fonts[id].valid = false
}

get_font_file_content :: proc(ctx: ^Ctx, id: int) -> []byte {
  assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts_count)
  return ctx.fonts[id].content
}

get_font_info_by_name :: #force_inline proc(ctx: ^Ctx, name: string) -> ^stbtt.fontinfo {
  assert(len(name) > 0)
  if ctx.fonts_count == 0 {
    return nil
  }
  for f, indx in ctx.fonts[0:ctx.fonts_count] {
    if strings.compare(name, f.name) == 0 {
      return get_font_info(ctx, indx)
    }
  }
  return nil
}

get_font_info :: #force_inline proc(ctx: ^Ctx, id: int) -> ^stbtt.fontinfo {
  assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts_count)
  return &ctx.fonts[id].info
}

init_font :: proc(ctx: ^Ctx, id: int) -> bool {
  assert(ctx != nil)
  assert(id < MAX_FONTS_COUNT && id != INVALID_FONT_ID && id < ctx.fonts_count)
  content := get_font_file_content(ctx, id)
  assert(content != nil)
  return bool(stbtt.InitFont(get_font_info(ctx, id), raw_data(content), stbtt.GetFontOffsetForIndex(raw_data(content), 0)))
}


load_font_file :: proc(ctx: ^Ctx, name: string, path: string) -> int {
  content, ok := os.read_entire_file(path, ctx.allocator)
  assert(ctx.fonts_count < MAX_FONTS_COUNT)
  if (!ok) {
    return INVALID_FONT_ID
  }
  font := &ctx.fonts[ctx.fonts_count]
  font.name = name
  font.content = content
  font.valid = true
  ctx.fonts_count += 1
  return ctx.fonts_count - 1
}

init_resources :: proc(ctx: ^Ctx) -> bool {
	assert(ctx != nil)
	program_id, program_ok := gl.load_shaders_file("./shaders/ui_vert.glsl", "./shaders/ui_frag.glsl")
	if !program_ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}

	ctx.program = program_id
  
	ctx.attrib_v_position = gl.GetAttribLocation(ctx.program, "v_position")
	if ctx.attrib_v_position < 0 {
		fmt.eprintln("Could not bind attribute v_position")
		return false
	}

	ctx.attrib_v_color = gl.GetAttribLocation(ctx.program, "v_color")
	if ctx.attrib_v_color < 0 {
		fmt.eprintln("Could not bind attribute v_color")
		return false
	}

	ctx.attrib_tex_coord = gl.GetAttribLocation(ctx.program, "tex_coord")
	if ctx.attrib_tex_coord < 0 {
		fmt.eprintln("Could not bind attribute tex_coord")
		return false
	}
	ctx.uniform_projection = gl.GetUniformLocation(ctx.program, "projection")
	if ctx.uniform_projection < 0 {
		fmt.eprintln("Could not bind uniform projection")
		return false
	}

	gl.UseProgram(ctx.program)
	gl.GenVertexArrays(1, &ctx.vao)
	gl.BindVertexArray(ctx.vao)

	gl.GenBuffers(1, &ctx.vbo)
	gl.GenBuffers(1, &ctx.ebo)
	gl.GenBuffers(1, &ctx.cbo)
  gl.GenBuffers(1, &ctx.tbo)

	
  gl.BindBuffer(gl.ARRAY_BUFFER, ctx.tbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.tex_buffer) * size_of(glm.vec2),
		nil,
	  gl.DYNAMIC_DRAW,	
	)
  gl.EnableVertexAttribArray(u32(ctx.attrib_tex_coord))
	gl.VertexAttribPointer(u32(ctx.attrib_tex_coord), 2, gl.FLOAT, false, size_of(glm.vec2), 0)
	

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.vertex_buffer) * size_of(glm.vec2),
		nil,
	  gl.DYNAMIC_DRAW,	
	)
  gl.EnableVertexAttribArray(u32(ctx.attrib_v_position))
	gl.VertexAttribPointer(u32(ctx.attrib_v_position), 2, gl.FLOAT, false, size_of(glm.vec2), 0)
 

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.cbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(ctx.colors_buffer) * size_of(Color),
		nil,
		gl.DYNAMIC_DRAW,
	)
	gl.EnableVertexAttribArray(u32(ctx.attrib_v_color))
	gl.VertexAttribPointer(u32(ctx.attrib_v_color), 4, gl.UNSIGNED_BYTE, false, size_of(Color), 0)


	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ctx.ebo)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(ctx.elements_buffer) * size_of(u16),
		nil,
		gl.DYNAMIC_DRAW,
	)

  gl.ActiveTexture(gl.TEXTURE0)
  gl.GenTextures(1, &tex_id)
  gl.BindTexture(gl.TEXTURE_2D, tex_id)
  gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 3, 3, 0, gl.RGB, gl.UNSIGNED_BYTE, raw_data(white_tex[:]))
  gl.GenerateMipmap(gl.TEXTURE_2D)

  text_shader, text_shader_ok := gl.load_shaders_file("./shaders/ui_vert.glsl", "./shaders/text_frag.glsl")
	if !text_shader_ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}

  ctx.text_shader = text_shader
  gl.UseProgram(ctx.text_shader)
  gl.BindBuffer(gl.ARRAY_BUFFER, ctx.vbo)
  gl.ActiveTexture(gl.TEXTURE1)
  gl.GenTextures(1, &ctx.font_tex_id)
  gl.BindTexture(gl.TEXTURE_2D, ctx.font_tex_id)
  gl.UseProgram(ctx.program)

	return true
}

free_resources :: proc(ctx: ^Ctx) {
}


flush :: proc(ctx: ^Ctx) {
	w, h := glfw.GetWindowSize(ctx.window_handle)
	gl.Viewport(0, 0, w, h)
	projection := glm.mat4Ortho3d(0.0, f32(w), f32(h), 0.0, -1.0, 1.0)

	gl.UseProgram(ctx.program)
  gl.ActiveTexture(gl.TEXTURE0)

	gl.UniformMatrix4fv(ctx.uniform_projection, 1, false, &projection[0, 0])
	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.vbo)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 4 * size_of(ctx.vertex_buffer[0]),
		raw_data(ctx.vertex_buffer[0:ctx.buffer_indx * 4]),
	)

	gl.BindBuffer(gl.ARRAY_BUFFER, ctx.cbo)
	gl.BufferSubData(
		gl.ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 4 * size_of(ctx.colors_buffer[0]),
		raw_data(ctx.colors_buffer[0:ctx.buffer_indx * 4]),
	)

  gl.BindBuffer(gl.ARRAY_BUFFER, ctx.tbo)
  gl.BufferSubData(
    gl.ARRAY_BUFFER,
    0,
    ctx.buffer_indx * 4 * size_of(ctx.tex_buffer[0]),
    raw_data(ctx.tex_buffer[0:ctx.buffer_indx * 4])
  )

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ctx.ebo)
	gl.BufferSubData(
		gl.ELEMENT_ARRAY_BUFFER,
		0,
		ctx.buffer_indx * 6 * size_of(u16),
		raw_data(ctx.elements_buffer[0:ctx.buffer_indx * 6]),
	) 

	gl.DrawElements(gl.TRIANGLES, i32(ctx.buffer_indx * 6), gl.UNSIGNED_SHORT, nil)
	ctx.buffer_indx = 0
}

render_text :: proc(ctx: ^Ctx, txt: string, pos: glm.vec2) {
  gl.UseProgram(ctx.text_shader)
  ww, hh := glfw.GetWindowSize(ctx.window_handle)
	gl.Viewport(0, 0, ww, hh)
	projection := glm.mat4Ortho3d(0.0, f32(ww), f32(hh), 0.0, -1.0, 1.0)

  gl.ActiveTexture(gl.TEXTURE0)
  gl.BindTexture(gl.TEXTURE_2D, ctx.font_tex_id)

  /* We require 1 byte alignment when uploading texture data */
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

	/* Clamping to edges is important to prevent artifacts when scaling */
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

	/* Linear filtering usually looks best for text */
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.UniformMatrix4fv(ctx.uniform_projection, 1, false, &projection[0, 0])
  fontinfo := get_font_info_by_name(ctx, "mono")
  assert(fontinfo != nil)
  x1 := pos[0]
  y1 := pos[1]
  w, h, xoff, yoff : i32
  for c in txt {

    bitmap := stbtt.GetCodepointSDF(
      fontinfo, 
      stbtt.ScaleForPixelHeight(fontinfo, 160),
      i32(c),
      5,
      150.0,
      150.0 / 5,
      &w,
      &h,
      &xoff,
      &yoff,
    )
  
    gl.TexImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RED,
      w,
      h,
      0,
      gl.RED,
      gl.UNSIGNED_BYTE,
      bitmap,
    )
    gl.GenerateMipmap(gl.TEXTURE_2D);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
 
    x2 := x1 + f32(w + xoff)
    y2 := y1 + f32(h + yoff)

    positions : []glm.vec2 = {glm.vec2{x1 + f32(xoff), y1 + f32(yoff)}, glm.vec2{x2, y2}, glm.vec2{x1 + f32(xoff), y2}, glm.vec2{x2, y1 + f32(yoff)}}
    gl.BindBuffer(gl.ARRAY_BUFFER, ctx.vbo) 
    gl.BufferSubData(
      gl.ARRAY_BUFFER,
      0,
      4 * size_of(glm.vec2),
      raw_data(positions[:])
    )
    uvs : []glm.vec2 = {glm.vec2{0, 0}, glm.vec2{1, 1}, glm.vec2{0, 1}, glm.vec2{1, 0}}
    gl.BindBuffer(gl.ARRAY_BUFFER, ctx.tbo) 
    gl.BufferSubData(
      gl.ARRAY_BUFFER,
      0,
      4 * size_of(glm.vec2),
      raw_data(uvs[:])
    )

    elements : []u16  = {0, 1, 2, 0, 3, 1}

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ctx.ebo)
    gl.BufferSubData(
      gl.ELEMENT_ARRAY_BUFFER,
      0,
      6 * size_of(u16),
      raw_data(elements[0:6]),
    )
   
    wht := Color{255, 255, 255, 255}
    colors : []Color = { wht, wht, wht, wht }
	  gl.BindBuffer(gl.ARRAY_BUFFER, ctx.cbo)
    gl.BufferSubData(
      gl.ARRAY_BUFFER,
      0,
      4 * size_of(Color),
      raw_data(colors[:]),
    )
    
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil)
    x1 += f32(w) + 10
    y1 += f32(0)
  }
}


push_quad :: proc(ctx: ^Ctx, quad: Quad, color: Color, tex: Quad) {
	if ctx.buffer_indx == BUFFER_SIZE {
		flush(ctx)
	}

	ctx.vertex_buffer[ctx.buffer_indx * 4 + 0] = glm.vec2(quad.tl)
	ctx.vertex_buffer[ctx.buffer_indx * 4 + 1] = glm.vec2(quad.br)
	ctx.vertex_buffer[ctx.buffer_indx * 4 + 2] = glm.vec2{quad.br.x, quad.tl.y}
	ctx.vertex_buffer[ctx.buffer_indx * 4 + 3] = glm.vec2{quad.tl.x, quad.br.y}

	ctx.colors_buffer[ctx.buffer_indx * 4 + 0] = color
	ctx.colors_buffer[ctx.buffer_indx * 4 + 1] = color
	ctx.colors_buffer[ctx.buffer_indx * 4 + 2] = color
	ctx.colors_buffer[ctx.buffer_indx * 4 + 3] = color

  x0 := tex.tl.x / f32(atlas_width)
  y0 := tex.tl.y / f32(atlas_height)
  x1 := tex.br.x / f32(atlas_width)
  y1 := tex.br.y / f32(atlas_height)

	ctx.tex_buffer[ctx.buffer_indx * 4 + 0] = glm.vec2{ x0, y0 }
	ctx.tex_buffer[ctx.buffer_indx * 4 + 1] = glm.vec2{ x1, y1 }
	ctx.tex_buffer[ctx.buffer_indx * 4 + 2] = glm.vec2{ x0, y1 }
	ctx.tex_buffer[ctx.buffer_indx * 4 + 3] = glm.vec2{ x1, y0 }
	ctx.elements_buffer[ctx.buffer_indx * 6 + 0] = u16(ctx.buffer_indx * 4 + 0)
	ctx.elements_buffer[ctx.buffer_indx * 6 + 1] = u16(ctx.buffer_indx * 4 + 1)
	ctx.elements_buffer[ctx.buffer_indx * 6 + 2] = u16(ctx.buffer_indx * 4 + 2)
	ctx.elements_buffer[ctx.buffer_indx * 6 + 3] = u16(ctx.buffer_indx * 4 + 0)
	ctx.elements_buffer[ctx.buffer_indx * 6 + 4] = u16(ctx.buffer_indx * 4 + 3)
	ctx.elements_buffer[ctx.buffer_indx * 6 + 5] = u16(ctx.buffer_indx * 4 + 1)

	ctx.buffer_indx += 1
}

main_loop :: proc(ctx: ^Ctx) {
	assert(ctx != nil && ctx.window_handle != nil)
	for !glfw.WindowShouldClose(ctx.window_handle) {
		// Process all incoming events like keyboard press, window resize, and etc.
		glfw.PollEvents()

		w, h := glfw.GetWindowSize(ctx.window_handle)
		gl.Scissor(0, 0, w, h)
		gl.ClearColor(0.0, 0.0, 0.0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)
    /*
    for a := 0; a < 10; a += 1 {
      for b : = 0; b < 10; b += 1 {
        i := f32(a)
        j := f32(b)
		    push_quad(ctx, Quad{tl = {j * 100.0, i * 100.0}, br = {j * 100.0 + 80.0, i * 100.0 + 80.0}}, Color{255, 255, 0, 150}, Quad{tl = {0.0, 0.0}, br = {3.0, 3.0}})
      } 
    }
		flush(ctx)
    */
    render_text(ctx, "H-O", glm.vec2{100.0, 100.0})

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
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR,GL_MAJOR_VERSION) 
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR,GL_MINOR_VERSION)
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
  //gl.Enable(gl.TEXTURE_2D)

  glfw.SwapInterval(0)
	init_resources(ctx)
	main_loop(ctx)
}
