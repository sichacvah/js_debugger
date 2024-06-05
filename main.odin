package js_console

import "./renderer"
import "core:encoding/json"
import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import mu "vendor:microui"
import stbtt "vendor:stb/truetype"

MouseState :: enum {
  DOWN,
  UP,
}

EMPTY_UI_ID :: 0
LayoutKind :: enum {
  Horz,
  Vert,
}
LAYOUT_STACK_SIZE :: 256
Layout :: struct {
  kind: LayoutKind,
  pos: [2]i32,
  size: [2]i32,
  is_clickable: bool,
}

ID :: distinct uint

UIState :: struct {
  mouse_pos: [2]i32,
  mouse_state: MouseState,
  prev_hot_id: ID,
  hot_id: ID,
  active_id: ID, 
  layouts: renderer.ItemsStack(Layout, LAYOUT_STACK_SIZE),
  r: ^renderer.Renderer,
}


push_layout :: proc(state: ^UIState, layout: Layout) {
  assert(state.layouts.id < LAYOUT_STACK_SIZE)
  prev_layout := top_layout(state)  
  state.layouts.items[state.layouts.id] = layout
  state.layouts.id += 1
  if prev_layout != nil {
    top_layout(state).pos = next_position(prev_layout)
  } 
}

top_layout :: proc(state: ^UIState) -> ^Layout {
  if state.layouts.id == 0 {
    return nil
  }
  return &state.layouts.items[state.layouts.id - 1]
}

pop_layout :: proc(state: ^UIState) -> Layout {
  assert(state.layouts.id > 0)
  size := top_layout(state).size
  state.layouts.id -= 1
  if state.layouts.id > 0 {
    expand_layout(state, size)
  }
  return state.layouts.items[state.layouts.id]
}

next_position :: proc(layout: ^Layout) -> [2]i32 {
  assert(layout != nil)
  pos : [2]i32
  switch layout.kind {
    case .Horz:
      pos.x = layout.pos.x + layout.size.x
      pos.y = layout.pos.y
    case .Vert:
      pos.x = layout.pos.x
      pos.y = layout.pos.y + layout.size.y
  }
  return pos
}

ui_begin :: proc(state: ^UIState, pos: [2]i32) {
  push_layout(state, {kind = .Horz, pos = pos})
}

ui_end :: proc(state: ^UIState) {
  _ = pop_layout(state)
}

begin_layout :: proc(state: ^UIState, kind: LayoutKind, offset: [2]i32 = {0, 0}) { 
  push_layout(state, {kind = kind, pos = offset})
}

end_layout :: proc(state: ^UIState) {
  _ = pop_layout(state)
}

clickable_begin :: proc(state: ^UIState) {
  l := top_layout(state)
  assert(l != nil)
  push_layout(state, {kind = .Horz, is_clickable = true, pos = l.pos})  
}

rect_contains :: #force_inline proc(rect_pos: [2]i32, rect_size: [2]i32, pos: [2]i32) -> bool {
  return (pos.x >= rect_pos.x && pos.x <= (rect_pos.x + rect_size.x)) &&
    (pos.y >= rect_pos.y && pos.y <= rect_pos.y + rect_size.y)
}

raw_button :: proc(
  state: ^UIState,
  id: ID,
  title: string,
  text_color: renderer.Color = COLOR_TEXT,
  hover_color: renderer.Color = COLOR_TEXT,
  hover_overlay_color: renderer.Color = COLOR_SUBTLE,
  paddings: Paddings = {},
) -> bool {
  layout := top_layout(state)
  assert(layout != nil)
  
  pos := next_position(layout)
  w := renderer.measure_text(state.r, title, 1) + paddings.left + paddings.right
  h := renderer.get_text_height(state.r, 1) + paddings.top + paddings.bot
  expand_layout(state, {w, h})
  click := false
  if state.active_id == id {
    if state.mouse_state == .UP {
      if state.hot_id == id {
        state.hot_id = EMPTY_UI_ID
        click = true
      }
      state.active_id = EMPTY_UI_ID 
    }
  } else if state.hot_id == id {
    if state.mouse_state == .DOWN {
      state.active_id = id
    }
  }

  if rect_contains(pos, {w, h}, state.mouse_pos) {
    if state.active_id == id || state.active_id == EMPTY_UI_ID {
      state.hot_id = id
    } 
  } else {
    if state.hot_id == id {
      state.hot_id = EMPTY_UI_ID
    }
  }

  if state.hot_id == id && hover_overlay_color.a != 0 {
    renderer.render_quad(state.r, f32(pos.x), f32(pos.y), f32(w), f32(h), hover_overlay_color)
  }
  draw_text(state.r, title, pos.x + paddings.left, pos.y + paddings.top, state.hot_id == id ? hover_color : text_color)
  return click
}

button :: proc(state: ^UIState, id: ID, title: string, color: renderer.Color = COLOR_TEXT, paddings: Paddings = {}) -> bool {
  return raw_button(state, id, title, color, {0,0,0,0}, color , paddings)
}

text_button :: proc(
  state: ^UIState,
  id: ID,
  title: string,
  color: renderer.Color = COLOR_TEXT, 
  hover_color: renderer.Color = COLOR_SUBTLE,
  paddings: Paddings = {}
) -> bool {
  return raw_button(state, id, title, color, hover_color, {0,0,0,0}, paddings)
}

draw_text :: proc(r: ^renderer.Renderer, str: string, x: i32, y: i32, color: renderer.Color = COLOR_TEXT) -> i32 {
  return renderer.render_text(r, str, {x, y}, color, 1)
}

clickable_end :: proc(state: ^UIState, id: ID) -> bool {
  c := pop_layout(state)
  assert(c.is_clickable, "clickable_begin and clickable_end mismatch")
  click := false
  if state.active_id == id {
    if state.mouse_state == .UP {
      if state.hot_id == id {
        state.hot_id = EMPTY_UI_ID
        click = true
      }
      state.active_id = EMPTY_UI_ID 
    }
  } else if state.hot_id == id {
    if state.mouse_state == .DOWN {
      state.active_id = id
    }
  }

  if rect_contains(c.pos, c.size, state.mouse_pos) {
    if state.active_id == id || state.active_id == EMPTY_UI_ID {
      state.hot_id = id
    } 
  } else {
    if state.hot_id == id {
      state.hot_id = EMPTY_UI_ID
    }
  }

  if state.hot_id == id {
    renderer.render_quad(state.r, f32(c.pos.x), f32(c.pos.y), f32(c.size.x), f32(c.size.y), COLOR_SUBTLE)
  }

  return click
}

expand_layout :: proc(state: ^UIState, size: [2]i32) {
  layout := top_layout(state) 
  assert(layout != nil, "label should rendered inside layout")
  switch layout.kind {
    case .Vert:
      layout.size.y += size.y
      if layout.size.x < size.x {
        layout.size.x = size.x
      }
    case .Horz:
      layout.size.x += size.x
      if layout.size.y < size.y {
        layout.size.y = size.y
      }
  }
}

Paddings :: struct {
  top: i32,
  bot: i32,
  left: i32,
  right: i32,
}

make_paddings_quad :: proc(side: i32) -> Paddings {
  return {side, side, side, side}
}

make_paddings_raw :: proc(top: i32, bot: i32, left: i32, right: i32) -> Paddings {
  return {top, bot, left, right}
}

make_paddings_rect :: proc(vert: i32, horz: i32) -> Paddings {
  return {vert, vert, horz, horz}
}

make_paddings :: proc{
  make_paddings_raw,
  make_paddings_quad,
  make_paddings_rect,
}

label :: proc(state: ^UIState, title: string, paddings: Paddings = {}, color: renderer.Color = COLOR_TEXT, render: bool = true) -> (w: i32, h: i32) {
  layout := top_layout(state) 
  assert(layout != nil, "label should rendered inside layout")
  pos := next_position(layout)
  h = renderer.get_text_height(state.r, 1)
  w = draw_text(state.r, title, pos.x, pos.y, color)
  expand_layout(state, {w, h}) 
  return
}

AppState :: struct {
  ui_state:          ^UIState,
	scroll:            [2]f32,
	last_button_click: f64,
	is_double_clicked: bool,
	double_click_pos:  [2]f32,
	msg:               json.Value,
}

JSValue :: union {
	JSPrime,
	JSComposite,
}

JSPrime :: union {
	json.Null,
	json.Integer,
	json.Float,
	json.Boolean,
	json.String,
}

JSComposite :: struct {
	is_opened: bool,
	val:       JSCompositeValue,
}

JSArray :: distinct []JSValue
JSObject :: distinct []JSValue

JSCompositeValue :: union {
	JSArray,
	JSObject,
}

convert_to_js :: proc(val: json.Value) -> JSValue {
	switch v in val {
	case json.Null:
		return JSPrime(v)
	case json.Boolean:
		return JSPrime(v)
	case json.Integer:
		return JSPrime(v)
	case json.Float:
		return JSPrime(v)
	case json.String:
		return JSPrime(v)
	case json.Array:
		arr := make([]JSValue, len(v))
		for i, indx in v {
			arr[indx] = convert_to_js(i)
		}
		return JSComposite{is_opened = false, val = JSCompositeValue(JSArray(arr))}
	case json.Object:
		arr := make([]JSValue, len(v) * 2)
		i := 0
		for k, v in v {
			arr[i] = JSPrime(k)
			arr[i + 1] = convert_to_js(v)
			i += 2
		}
		return JSComposite{is_opened = false, val = JSCompositeValue(JSObject(arr))}
	}
	return JSPrime(nil)
}

json_str := `
{"a": 10, "b": "string", v: true, c: {b: 1}}
`


//{"a": 10, "b": "string", "v": true, "arr": [1, 2, -13]}
// , 10, {b: {c: 100.0}, "flag": true}, true, "just string"

conversion_buffer := [1024]byte{}
// #e0def4
COLOR_TEXT :: renderer.Color{0xe0, 0xde, 0xf4, 0xff}
// #524f67
COLOR_SUBTLE :: renderer.Color{0x52, 0x4f, 0x67, 0xff}
// #9ccfd8
COLOR_FOAM :: renderer.Color{0x9c, 0xcf, 0xd8, 0xff}
// #f6c177
COLOR_GOLD :: renderer.Color{0xf6, 0xc1, 0x77, 0xff}
// #ebbcba
COLOR_ROSE :: renderer.Color{0xeb, 0xbc, 0xba, 0xff}

draw_int :: proc(
	ui_state: ^UIState,
	i: i64,
) {
	str := strconv.append_int(conversion_buffer[:], i, 10)
  label(ui_state, str, color = COLOR_GOLD)
}

draw_float :: proc(
	ui_state: ^UIState,
	f: f64,
) {
	str := strconv.append_float(conversion_buffer[:], f, 'f', 2, 64)
	if str[0] == '+' {
		str = str[1:]
	}
  label(ui_state, str, color = COLOR_GOLD)
}

draw_string :: proc(
	ui_state: ^UIState,
	str: string,
) {
  label(ui_state, "\"", color = COLOR_GOLD)
  label(ui_state, str, color = COLOR_GOLD)
  label(ui_state, "\"", color = COLOR_GOLD)
}

draw_bool :: proc(ui_state: ^UIState,b: bool) {
  label(ui_state, b ? "true" : "false", color = COLOR_ROSE)
}

draw_null :: proc(ui_state: ^UIState) {
  label(ui_state, "null")
}

draw_key :: proc(ui_state: ^UIState, key: string) {
  label(ui_state, key)
}

draw_js_prime :: proc(
	ui_state: ^UIState,
	prime: JSPrime
) {
	switch v in prime {
	case json.Null:
		draw_null(ui_state)
	case json.Boolean:
		draw_bool(ui_state, v)
	case json.Float:
		draw_float(ui_state, v)
	case json.Integer:
		draw_int(ui_state, v)
	case json.String:
		draw_string(ui_state, v)
	}
}

draw_closed_composite :: proc(
	ui_state: ^UIState,
	value: JSComposite,
) {
	switch c in value.val {
	case JSArray:
		label(ui_state, "[", color = COLOR_SUBTLE)
    label(ui_state, "...")
		label(ui_state, "]", color = COLOR_SUBTLE)
	case JSObject:
    label(ui_state, "{", color = COLOR_SUBTLE)
    label(ui_state, "...")
		label(ui_state, "}", color = COLOR_SUBTLE)
	}
}

draw_array :: proc(
	ui_state: ^UIState,
	value: ^JSArray,
	is_opened: bool,
) {
	if !is_opened {
    begin_layout(ui_state, .Horz)
		label(ui_state, "[ ", color = COLOR_SUBTLE)
		for indx := 0; indx < len(value); indx += 1 {
			switch js_val in value[indx] {
			case JSComposite:
				draw_closed_composite(ui_state, js_val)
			case JSPrime:
				draw_js_prime(ui_state, js_val)
			}
			if indx < len(value) - 1 {
        label(ui_state, ", ", color = COLOR_SUBTLE)
			}
		}
    label(ui_state, " ]", color = COLOR_SUBTLE)
    end_layout(ui_state)
	} else {
    begin_layout(ui_state, .Vert)
		label(ui_state, "[ ", color = COLOR_SUBTLE)
		for indx := 0; indx < len(value); indx += 1 {
      begin_layout(ui_state, .Horz)
      draw_json_value(ui_state, &value[indx])
      label(ui_state, ",", color = COLOR_SUBTLE)
      end_layout(ui_state)
		}
    label(ui_state, " ]", color = COLOR_SUBTLE)
    end_layout(ui_state)

	}
	return
}

draw_object_key :: proc(
  ui_state: ^UIState,
  key: string,
) {
  label(ui_state, key, color = COLOR_FOAM)
  label(ui_state, ": ", color = COLOR_FOAM)
}

draw_coll_plain_value :: proc(ui_state: ^UIState, value: JSPrime) {
  begin_layout(ui_state, .Horz)
  v := JSValue(value)
  draw_json_value(ui_state, &v)
  label(ui_state, ",", color = COLOR_SUBTLE)
  end_layout(ui_state)
}

add_horz_padding_to_layout :: proc(ui_state: ^UIState, padding: i32) {
  l := top_layout(ui_state)
  assert(l != nil)
  l.pos.x += padding
}

ws_size :i32 = 0

get_padding_size :: proc(ui_state: ^UIState) -> i32 {
  @(static) is_measured := false
  if !is_measured {
    ws_size = renderer.measure_text(ui_state.r, " ", 1)
    is_measured = true
  }
  return ws_size * 2
}

add_json_offset :: proc(ui_state: ^UIState) {
  add_horz_padding_to_layout(ui_state, get_padding_size(ui_state))
}

remove_json_offset :: proc(ui_state: ^UIState) {
  add_horz_padding_to_layout(ui_state, -get_padding_size(ui_state))
}

draw_object_values :: proc(ui_state: ^UIState, value: ^JSObject, is_opened: bool) {
  if !is_opened {
    for indx := 0; indx < len(value); indx += 2 {
      key := (value[indx].(JSPrime).(json.String))
      begin_layout(ui_state, .Horz)
      draw_object_key(ui_state, key)
			switch js_val in value[indx + 1] {
			case JSComposite:
				draw_closed_composite(ui_state, js_val)
			case JSPrime:
				draw_js_prime(ui_state, js_val)
			}
			if indx < len(value) - 2 {
        label(ui_state, ", ")
			}
      end_layout(ui_state)
		}
  } else {
    for indx := 0; indx < len(value); indx += 2 {
      key := (value[indx].(JSPrime).(json.String))
      switch &v in value[indx + 1] {
        case JSComposite:
          if !v.is_opened {

            begin_layout(ui_state, .Horz)
            draw_object_key(ui_state, key)
            draw_js_composite(ui_state, &v)
            end_layout(ui_state)
          } else {
            begin_layout(ui_state, .Vert)
            begin_layout(ui_state, .Horz)
            draw_object_key(ui_state, key)
            if text_button(ui_state, ID(uintptr(&v)), "▼") {
                v.is_opened = false
            }
            switch &c in v.val {
              case JSObject:
                label(ui_state, "{", color = COLOR_SUBTLE) 
                end_layout(ui_state)
                add_json_offset(ui_state)
                draw_object_values(ui_state, &c, v.is_opened)
                remove_json_offset(ui_state)
              case JSArray:
                unimplemented() 
            }
            label(ui_state, "},", color = COLOR_SUBTLE) 
            end_layout(ui_state)
          }
        case JSPrime:
          begin_layout(ui_state, .Horz)
          draw_object_key(ui_state, key)
          draw_coll_plain_value(ui_state, v) 
          end_layout(ui_state)
      }
		}
  }
}

draw_object :: proc(
  ui_state: ^UIState,
	value: ^JSObject,
  comp:  ^JSComposite,
) {
  r := ui_state.r
  is_opened := comp.is_opened
	if !is_opened {
    begin_layout(ui_state, .Horz)
    if text_button(ui_state, ID(uintptr(comp)), "▶") { 
      comp.is_opened = true
    }
    label(ui_state, "{ ", color = COLOR_SUBTLE)
    draw_object_values(ui_state, value, is_opened) 
    label(ui_state, " }", color = COLOR_SUBTLE)
    end_layout(ui_state)
	} else { 
    begin_layout(ui_state, .Horz)
    if text_button(ui_state, ID(uintptr(comp)), "▼") {
      comp.is_opened = false
    }
    begin_layout(ui_state, .Vert)
    label(ui_state, "{", color = COLOR_SUBTLE)
    add_json_offset(ui_state)
    draw_object_values(ui_state, value, is_opened)
    remove_json_offset(ui_state)
		label(ui_state, "}", color = COLOR_SUBTLE)
    end_layout(ui_state)
    end_layout(ui_state)
	}
	return
}

draw_js_composite :: proc(
	ui_state: ^UIState,
	value: ^JSComposite,
) {
	switch &v in value.val {
	case JSArray:
		draw_array(ui_state, &v, value.is_opened)
	case JSObject:
		draw_object(ui_state, &v, value)
	}
}

draw_json_value :: proc(
	ui_state: ^UIState,
	value: ^JSValue,
) {
	switch &v in value {
	case JSPrime:
		draw_js_prime(ui_state, v)
	case JSComposite:
		draw_js_composite(ui_state, &v)
	}
}

FontDecl :: struct {
	name: string,
	path: string,
	size: int,
}
default_fonts := []FontDecl {
	{name = "mono", path = "./resources/JetBrainsMono-Regular.ttf", size = 48},
}
init_fonts :: proc(r: ^renderer.Renderer, allocator: mem.Allocator, fonts: []FontDecl) {
	for decl in default_fonts {
		renderer.init_font(r, allocator, decl.name, decl.path)
		renderer.init_font_variant(r, allocator, decl.name, decl.size)
	}
}

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
WIDTH :: 1920
HEIGHT :: 1080

/**
███    ███  █████  ██ ███    ██ 
████  ████ ██   ██ ██ ████   ██ 
██ ████ ██ ███████ ██ ██ ██  ██ 
██  ██  ██ ██   ██ ██ ██  ██ ██ 
██      ██ ██   ██ ██ ██   ████                           
-> MAIN                                
*/
main :: proc() {
	app_state: AppState
  ui_state: UIState
  app_state.ui_state = &ui_state
	allocator := context.allocator
	// TODO: custom allocator, arena? 

	msg, err := json.parse(transmute([]u8)json_str)
	if err != .None {
		fmt.eprintln("Failed to parse msg")
		return
	}
	app_state.msg = msg

	if !bool(glfw.Init()) {
		fmt.eprintln("GLFW has failed to load.")
		return
	}

	r := renderer.renderer_init(allocator)

	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, true)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.SAMPLES, 4)
	r.window_handle = glfw.CreateWindow(WIDTH, HEIGHT, "Yasm debug", nil, nil)
	defer glfw.Terminate()
	defer glfw.DestroyWindow(r.window_handle)

	if r.window_handle == nil {
		fmt.eprintln("GLFW has failed to load the window.")
		return
	}

	glfw.MakeContextCurrent(r.window_handle)
	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	gl.BlendEquation(gl.FUNC_ADD)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.Enable(gl.BLEND)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.SCISSOR_TEST)
	gl.Enable(gl.MULTISAMPLE)


	init_fonts(r, allocator, default_fonts)
	renderer.init_resources(r)
	ctx := new(mu.Context)

	mu.init(ctx)
	fv := &r.fontvariants.items[1]
	assert(fv != nil)
	ctx.style.font = mu.Font(fv)

	ctx.text_width = text_width
	ctx.text_height = text_height

	glfw.SetWindowUserPointer(r.window_handle, &app_state)
	glfw.SetScrollCallback(r.window_handle, glfw_scroll_cb)
	glfw.SetMouseButtonCallback(r.window_handle, glfw_mouse_button_cb)
	glfw.SetInputMode(r.window_handle, glfw.STICKY_MOUSE_BUTTONS, 1)
  app_state.ui_state.r = r

	main_loop(&app_state)
}

glfw_scroll_cb :: proc "c" (window: glfw.WindowHandle, xoff, yoff: f64) {
	app_state := cast(^AppState)glfw.GetWindowUserPointer(window)
	app_state.scroll.x += f32(xoff)
	app_state.scroll.y += f32(yoff)
}

glfw_mouse_button_cb :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	if button != glfw.MOUSE_BUTTON_LEFT {
		return
	}
	app_state := cast(^AppState)glfw.GetWindowUserPointer(window)
	x, y := glfw.GetCursorPos(window)
	if action == glfw.PRESS {
		dt := glfw.GetTime() - app_state.last_button_click
		if dt > 0.02 && dt < 0.2 {
			app_state.is_double_clicked = true
			app_state.double_click_pos = {f32(x), f32(y)}
		}
		app_state.last_button_click = glfw.GetTime()
	} else {
		app_state.is_double_clicked = false
	}
}


text_height :: proc(font: mu.Font) -> i32 {
	fv := cast(^renderer.FontVariant)font
	assert(fv != nil)
	return i32(f32(fv.size + fv.ascent + fv.descent) * fv.scale)
}

text_width :: proc(font: mu.Font, text: string) -> i32 {
	fv := cast(^renderer.FontVariant)font
	assert(fv != nil)
	width: f32 = 0
	for r in text {
		width += fv.chars[r].advance_x
	}
	return i32(width)
}

process_frame :: proc(ui_state: ^UIState, msg: ^JSValue) {
  fmt.println("MSG: ", msg)
	//w := renderer.measure_text(ui_state.r, " ", {0, 0}, COLOR_TEXT, 1)
	x, y: i32
	x = 8
	y = 8

  ui_begin(ui_state, {x, y})
  /* 
  if button(ui_state, 1, "▶", COLOR_TEXT, make_paddings(4)) {
    fmt.println("CLICKED")
  }
  */
	draw_json_value(ui_state, msg)
  ui_end(ui_state)
}

process_events :: proc(app_state: ^AppState) {
	assert(app_state != nil)
	r := app_state.ui_state.r
	xraw, yraw := glfw.GetCursorPos(r.window_handle)
  app_state.ui_state.mouse_pos = {i32(xraw), i32(yraw)}
  app_state.ui_state.mouse_state = glfw.GetMouseButton(r.window_handle, glfw.MOUSE_BUTTON_LEFT) == glfw.RELEASE ? .UP : .DOWN
}

main_loop :: proc(app_state: ^AppState) {
	assert(app_state != nil)
  assert(app_state.ui_state != nil)
	r := app_state.ui_state.r
	assert(r != nil && r.window_handle != nil)
	renderer.change_shader(r, .ui)
	gl.BindTexture(gl.TEXTURE_2D, r.white_tex.id)
	msg := convert_to_js(app_state.msg)
	for !glfw.WindowShouldClose(r.window_handle) {
		glfw.PollEvents()

		renderer.clean(r)
    process_events(app_state)
    process_frame(app_state.ui_state, &msg)
    renderer.flush(r)
		glfw.SwapBuffers(r.window_handle)
	}
}
