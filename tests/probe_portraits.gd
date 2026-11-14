extends SceneTree
## Sichtpruefung der KI-Portraets (Auftrag 23): 16 Figuren mit verschiedenen Namen, Taetigkeiten und Gesten, als Bild gespeichert.
## Godot --path . -s tests/probe_portraits.gd -- --out=user://portraets.png [--t=1.3]
var out := "user://portraets.png"
var wait := 1.3
var clock := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--t="):
			wait = float(a.substr(4))
	DisplayServer.window_set_size(Vector2i(1160, 600))
	var names := ["Greta|Greta Logistik", "Viktor|Vitesse Transporte", "Amira|Amira Express", "Bodo|Bodo & Söhne", "Nils Ahrens|Ahrens Werke",
		"Ronja Lorenz|Lorenz Handel", "Kaya|Kaya Handel", "Voss|Voss Bau", "Yilmaz|Yilmaz & Partner", "Bürgermeister Jürgen Brandt", "Wendt|Wendt Brot",
		"Kruse|Kruse Werke", "Lea|Lea Logistik", "Tarek|Tarek Trans", "Mira|Mira Mobil", "Bo|Bo Bau"]
	var acts := ["denkt", "telefoniert", "unterschreibt", "rechnet", "plant", "liest", "geht", "spricht", "wartet", "wartet", "wartet", "wartet", "wartet", "wartet", "wartet", "wartet"]
	var gests := ["", "", "", "", "", "", "", "", "jubeln", "fluchen", "nervös", "winken", "schulterzucken", "daumen_hoch", "kaffee", "zuversichtlich"]
	for i in names.size():
		var p := PortraitArt.new()
		p.size = Vector2(128, 128)
		p.position = Vector2(16 + (i % 8) * 142, 20 + (i / 8) * 290)
		p.setup(names[i], Catalog.COMPANY_COLORS[i % Catalog.COMPANY_COLORS.size()])
		p.activity = acts[i]
		p.gesture = gests[i]
		p.mood = [0.5, -0.5, 0.0, 0.8][i % 4]
		root.add_child(p)
		var l := Label.new()
		l.text = "%s\n%s" % [names[i].split("|")[0], gests[i] if gests[i] != "" else acts[i]]
		l.position = p.position + Vector2(0, 132)
		root.add_child(l)

func _process(delta: float) -> bool:
	clock += delta
	if clock >= wait:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("Portraets: ", ProjectSettings.globalize_path(out))
		return true
	return false
