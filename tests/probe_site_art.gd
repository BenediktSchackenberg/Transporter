extends SceneTree
## Sichtpruefung der Baustellen (Auftrag 23, Phase 3) ohne Partie: Baustellen in allen Phasen und zwei Strassenbaustellen nebeneinander,
## nach einigen Sekunden Animation als Bild gespeichert. Aufruf (mit Fenster, nicht headless):
##   Godot --path . -s tests/probe_site_art.gd -- --out=user://baustellen.png [--pick=3,4,8] [--zoom=0.9] [--t=4]
## pick: Nummern 0-7 = Bauphasen (PHASES), 8 = Strasseninstandsetzung, 9 = Leitungsbau; nebeneinander in einer Reihe.

const PHASES := [[0, "vorbereitung"], [1, "erdarbeiten"], [2, "fundament"], [3, "rohbau"], [4, "dach"], [5, "huelle"], [5, "innenausbau"], [5, "uebergabe"]]
const GEAR := {"erdarbeiten": ["bagger", "lkw"], "fundament": ["betonmischer"], "rohbau": ["kran"], "dach": ["kran"]}

var out := "user://baustellen.png"
var wait := 4.0
var nodes: Array = []
var clock := 0.0
var frames := 0
var pick: Array = [1, 3, 4]


func _initialize() -> void:
	var zoom := 0.85
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		if a.begins_with("--t="):
			wait = float(a.substr(4))
		if a.begins_with("--pick="):
			pick = Array(a.substr(7).split(",")).map(func(x): return int(x))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var bg := ColorRect.new()
	bg.color = Color("5b8a3c")
	bg.size = Vector2(20000, 20000)
	bg.position = Vector2(-10000, -10000)
	root.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	root.add_child(cam)
	var slot := 0
	for k in pick:
		var base := Vector2(slot * 8.0, -slot * 8.0)
		slot += 1
		if k >= 8:   # Strassenbaustellen: Instandsetzung und Leitungsbau
			var j: int = k - 8
			var cell := Vector2i(int(base.x) + 3, int(base.y) + 3)
			var r2 := Rect2(float(cell.x) * 32.0 - 16.0, float(cell.y) * 32.0 - 16.0, 64.0, 64.0)
			var n2 := SiteView.SiteNode.new()
			n2.parcel_rect = r2
			n2.foot = Rect2(r2.position, Vector2.ZERO)
			n2.origin = r2.end
			n2.position = Iso.to_screen(r2.end)
			n2.crew = {"phase": "strasse", "role": "Straßenbau" if j == 0 else "Leitungsbau", "foreman": 1, "workers": 3, "operators": 1,
				"gear": ["bagger", "lkw"] if j == 1 else ["lkw"], "working": true}
			n2.seed_key = 77 + j
			root.add_child(n2)
			nodes.append(n2)
			continue
		var ph: Array = PHASES[k]
		var r := Rect2(base * 32.0, Vector2(7, 6) * 32.0)
		var foot := Rect2(r.position + Vector2(2.0, 1.5) * 32.0, Vector2(3.0, 2.5) * 32.0)
		var n := SiteView.SiteNode.new()
		n.parcel_rect = r
		n.foot = foot
		n.origin = r.end
		n.position = Iso.to_screen(r.end)
		n.state = int(ph[0])
		n.height = [0.0, 0.0, 6.0, 70.0, 88.0, 88.0, 88.0, 88.0][k]
		n.crew = {"phase": ph[1], "role": ph[1], "foreman": 1, "workers": 4, "operators": 1, "gear": GEAR.get(ph[1], []), "working": true,
			"color": Catalog.COMPANY_COLORS[k % 4]}
		n.seed_key = 1000 + k
		root.add_child(n)
		nodes.append(n)
	var all := Rect2(nodes[0].position, Vector2.ZERO)
	for n3 in nodes:
		all = all.expand(n3.position).expand(Iso.to_screen(n3.parcel_rect.position))
	cam.position = all.get_center()


func _process(delta: float) -> bool:
	clock += delta
	frames += 1
	for n in nodes:
		n.t = clock
		n.queue_redraw()
	if clock >= wait and frames > 10:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("Baustellenbild: ", ProjectSettings.globalize_path(out))
		return true
	return false
