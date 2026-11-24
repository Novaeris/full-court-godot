class_name FcJerseyGraphics
extends RefCounted
## The number, surname and team wordmark of a jersey as TEXTURE graphics (Production Phase M1), laid out on the jersey UV (u around the body, the front at
## 0.5 and the back at the 0/1 seam; v up from the hem). One texture per unique graphic, cached; drawn by a small SubViewport once, then copied to an
## ImageTexture and the viewport is freed, so there is no per-frame cost. The jersey material (jersey_cloth.gdshader) shows it. Studio Creator and every
## game mode drive it with plain values (number, surname, wordmark, colours): no 3D model changes. Label3D numbers stay as the fallback when no renderer
## exists (headless runs) or the texture cannot be made.

const SHADER_PATH := "res://src/ui/broadcast3d/jersey_cloth.gdshader"
const SIZE := Vector2i(1024, 640)
## Where things sit in the 1024 x 640 layout: [centre y in pixels, font size in pixels]. The jersey is about 0.62 m tall over 640 px, so ten pixels are a centimetre.
const FRONT_NUMBER := [352, 130]
const FRONT_WORDMARK := [250, 52]
const BACK_NUMBER := [275, 250]
const BACK_SURNAME := [96, 66]

static var _textures: Dictionary = {}    # key -> ImageTexture
static var _cloths: Dictionary = {}      # colour -> ShaderMaterial for plain cloth (shorts)
static var _shader: Shader


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


## True when graphics can be drawn (a rendering device exists); false in headless runs, where Label3D numbers are used instead.
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


static func key_for(number: int, surname: String, wordmark: String, ink: Color, outline: Color) -> String:
	return "%d|%s|%s|%s|%s" % [number, surname.to_upper(), wordmark.to_upper(), ink.to_html(false), outline.to_html(false)]


## The last word of a full name, upper case ("" when there is none).
static func surname_of(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	return str(parts[parts.size() - 1]).to_upper() if parts.size() > 0 else ""


## A material for one jersey: the cloth colour and the graphics texture (which fills in a frame later when the drawing finishes).
static func jersey_material(host: Node, base: Color, number: int, surname: String, wordmark: String, ink: Color, outline: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("base_color", base)
	if number > 0 and available():
		m.set_shader_parameter("graphics", graphics_texture(host, number, surname, wordmark, ink, outline))
	return m


## Plain cloth (shorts): shared by every player wearing the same colour.
static func cloth_material(base: Color) -> ShaderMaterial:
	var key := base.to_html(false)
	if not _cloths.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader()
		m.set_shader_parameter("base_color", base)
		_cloths[key] = m
	return _cloths[key]


## The texture for a graphic: from the cache when it exists, otherwise a blank texture that is filled in once the viewport has drawn it.
static func graphics_texture(host: Node, number: int, surname: String, wordmark: String, ink: Color, outline: Color) -> Texture2D:
	var key := key_for(number, surname, wordmark, ink, outline)
	if _textures.has(key):
		return _textures[key]
	var blank := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(blank)
	_textures[key] = tex
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(_layout(number, surname, wordmark, ink, outline))
	host.add_child(viewport)
	_finish(host, viewport, tex)
	return tex


static func _finish(host: Node, viewport: SubViewport, tex: ImageTexture) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(viewport):
		var img := viewport.get_texture().get_image()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex.set_image(img)
		viewport.queue_free()


static func _layout(number: int, surname: String, wordmark: String, ink: Color, outline: Color) -> Control:
	var root := Control.new()
	root.size = Vector2(SIZE)
	_text(root, str(number), 512.0, FRONT_NUMBER, ink, outline)
	if wordmark != "":
		_text(root, wordmark.to_upper(), 512.0, FRONT_WORDMARK, ink, outline)
	# the back centre is the texture seam: draw each half at either edge
	for cx in [0.0, float(SIZE.x)]:
		_text(root, str(number), cx, BACK_NUMBER, ink, outline)
		if surname != "":
			_text(root, surname, cx, BACK_SURNAME, ink, outline)
	return root


static func _text(root: Control, text: String, cx: float, spec: Array, ink: Color, outline: Color) -> void:
	var label := Label.new()
	label.text = text
	var look := LabelSettings.new()
	look.font_size = int(spec[1])
	look.font_color = ink
	look.outline_color = outline
	look.outline_size = maxi(int(float(spec[1]) * 0.07), 2)
	label.label_settings = look
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var w := 520.0
	var h := float(spec[1]) * 1.4
	label.size = Vector2(w, h)
	label.position = Vector2(cx - w * 0.5, float(spec[0]) - h * 0.5)
	root.add_child(label)


static func clear_cache() -> void:
	_textures.clear()
	_cloths.clear()
