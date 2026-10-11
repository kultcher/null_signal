class_name DisruptionText extends RefCounted
## A display-only transform. Never feed the result back into command parsing,
## scan layers, puzzle answers, or session history.

const NOISE := "#%?+*=~"

static func transform(source: String, fraction: float, seed_value: int, redact: bool, noise_step: int = 0, protected_strings: Array[String] = []) -> String:
	if fraction <= 0.0:
		return source
	var protected_ranges: Array[Vector2i] = []
	for literal in protected_strings:
		if literal.is_empty():
			continue
		var start := source.find(literal)
		while start >= 0:
			protected_ranges.append(Vector2i(start, start + literal.length()))
			start = source.find(literal, start + literal.length())
	var source_hash := hash(source)
	var result := ""
	var cursor := 0
	while cursor < source.length():
		var character := source[cursor]
		if character == "[":
			var end := source.find("]", cursor)
			if end >= 0 and _is_format_tag(source.substr(cursor + 1, end - cursor - 1)):
				result += source.substr(cursor, end - cursor + 1)
				cursor = end + 1
				continue
		var protected := false
		for span in protected_ranges:
			if cursor >= span.x and cursor < span.y:
				protected = true
				break
		var code := character.unicode_at(0)
		var is_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var eligible := is_letter if redact else not character in [" ", "\t", "\n", "\r"]
		var sample := float(hash("%d:%d:%d" % [seed_value, cursor, source_hash]) & 0xffff) / 65536.0
		if not protected and eligible and sample < clampf(fraction, 0.0, 1.0):
			character = "█" if redact else NOISE[(hash("%d:%d:%d" % [seed_value, cursor, noise_step]) & 0x7fffffff) % NOISE.length()]
		result += character
		cursor += 1
	return result

static func _is_format_tag(tag: String) -> bool:
	var name := tag.trim_prefix("/").get_slice("=", 0).get_slice(" ", 0)
	return name in ["b", "i", "u", "s", "color", "bgcolor", "font", "font_size", "outline_size", "outline_color", "url", "img", "center", "left", "right", "fill", "indent", "code", "lb", "rb", "br", "wave", "shake", "rainbow", "pulse", "fade"]
