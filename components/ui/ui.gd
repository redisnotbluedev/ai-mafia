extends MarginContainer

@export var caption_text: RichTextLabel
@export var audio_player: AudioStreamPlayer

var bold_regex: RegEx = RegEx.create_from_string(r"\*\*(.+?)\*\*")
var italics_regex: RegEx = RegEx.create_from_string(r"\*(.+?)\*")

func show_text(text: String, render_markdown: bool = true):
	text = bold_regex.sub(text, "[b]$1[/b]")
	text = italics_regex.sub(text, "[i]$1[/i]")
	
	caption_text.text = "[font_size=%d]%s[/font_size]" % [
		get_viewport_rect().size.y / 27,
		text
	]

func play_sound(stream: AudioStream):
	audio_player.stream = stream
	audio_player.play()
	await audio_player.finished

func get_chunks(message: String, max_len: int = 100) -> Array:
	var chunks: Array = []
	var start: int = 0
	var len: int = message.length()
	
	while start < len:
		var natural_end: int = len
		
		for i in range(start, len):
			var ch: String = message[i]
			var next: String = message[i + 1] if i + 1 < len else ""
			
			if ch in ["!", "?"] and next in [" ", "\n", "\t", ""]:
				natural_end = i + 1
				break
			
			if ch == ".":
				var is_ellipsis: bool = (i >= 2 and message[i-1] == '.' and message[i-2] == '.')
				if not is_ellipsis:
					var next_next: String = message[i + 2] if i + 2 < len else ""
					if next in [" ", "\n", "\t", ""] or (next in ["'", "\"", ")", "]"] and next_next in [" ", "\n", "\t", ""]):
						natural_end = i + 1
						break
		
		var end: int = natural_end
		
		if natural_end - start > max_len:
			var ideal: int = start + max_len - 1
			var best_pos: int = -1
			var best_diff: int = len
			
			for i in range(start, natural_end):
				if message[i] in [",", ";"]:
					var diff: int = abs(i - ideal)
					if diff < best_diff:
						best_diff = diff
						best_pos = i
			
			if best_pos != -1:
				end = best_pos + 1
		
		var chunk: String = message.substr(start, end - start).strip_edges()
		if chunk:
			chunks.append(chunk)
		start = end
	
	return chunks
