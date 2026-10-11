class_name DegradedInputOverlay extends Control
## Draws noise over an otherwise intact LineEdit, retaining its native caret,
## selection, editing shortcuts, clipboard contents, and command value.

var line: LineEdit
var display_text := ""
var original_font_color := Color.WHITE
var original_selected_color := Color.WHITE
var original_uneditable_color := Color.WHITE
var _saved_overrides: Dictionary = {}

func initialize(target: LineEdit) -> void:
	line = target
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	original_font_color = line.get_theme_color("font_color")
	original_selected_color = line.get_theme_color("font_selected_color")
	original_uneditable_color = line.get_theme_color("font_uneditable_color")
	for key in ["font_color", "font_selected_color", "font_uneditable_color"]:
		_saved_overrides[key] = line.has_theme_color_override(key)
	visible = false

func show_noise(text: String) -> void:
	display_text = text
	visible = true
	for key in ["font_color", "font_selected_color", "font_uneditable_color"]:
		line.add_theme_color_override(key, Color.TRANSPARENT)
	queue_redraw()

func restore() -> void:
	if not visible:
		return
	visible = false
	for key in ["font_color", "font_selected_color", "font_uneditable_color"]:
		if _saved_overrides[key]:
			var color := original_font_color
			if key == "font_selected_color":
				color = original_selected_color
			elif key == "font_uneditable_color":
				color = original_uneditable_color
			line.add_theme_color_override(key, color)
		else:
			line.remove_theme_color_override(key)

func _draw() -> void:
	if line == null:
		return
	var font := line.get_theme_font("font")
	var font_size := line.get_theme_font_size("font_size")
	var style := line.get_theme_stylebox("normal")
	var x := style.get_content_margin(SIDE_LEFT) + line.get_scroll_offset()
	var y := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	# Position each replacement using the original glyph's advance, so caret
	# and selection still align even if a noise glyph has a different width.
	for i in range(mini(display_text.length(), line.text.length())):
		var color := original_font_color if line.editable else original_uneditable_color
		if line.has_selection() and i >= line.get_selection_from_column() and i < line.get_selection_to_column():
			color = original_selected_color
		draw_string(font, Vector2(x, y), display_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += font.get_string_size(line.text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
