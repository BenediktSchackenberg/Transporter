extends SceneTree
## Absturzsuche 10.11.: setzt alle Modell-Zusammenfassungen aus den Partieprotokollen als Sprechblasen-Text (Label, WORD_SMART,
## wie entity_view.gd) und laesst Godot sie umbrechen. Stuerzt Godot ab, steht der letzte Text in user://logs/bubble_probe.txt.
## Aufruf: Godot --path . -s tests/probe_bubbles.gd -- --file=<summaries.json>

func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
	var texts: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var bubble := PanelContainer.new()
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	bubble.add_child(lbl)
	root.add_child(bubble)
	var n := 0
	for t in texts:
		for cut in [110, String(t).length()]:
			var s := String(t).left(cut)
			var f := FileAccess.open("user://logs/bubble_probe.txt", FileAccess.WRITE)
			f.store_string(s)
			f.close()
			lbl.text = s
			bubble.reset_size()
			lbl.get_minimum_size()
			lbl.get_line_count()
			n += 1
	print("Sprechblasen ohne Absturz: ", n)
	quit()
