class_name FreeBuild
extends RefCounted
## Freies Bauen der Unternehmer (Benedikt, 13.11.2026): Die KI denkt sich ein Bauwerk aus und baut es Stein auf Stein auf dem
## eigenen Grundstueck – ohne feste Vorlage. Entwurf als Form (turm, haus, pyramide, mauer, bogen) mit Groesse, Wand- und
## Dachmaterial oder frei als Bauplan Schicht fuer Schicht ("XXXX/X..X/X..X/XXXX"). Das Material holt die Firma selbst beim
## Baustoffhandel des Grosslagers ab (hub_buy, eigenes Fahrzeug); verbaut wird nur, was in den eigenen Lagern liegt. Die Baustelle
## waechst sichtbar Block fuer Block (FreeBuildView), Schicht fuer Schicht, das Dach zuletzt. Fehlt Material, wartet sie.
## Raster: 4×4 Bloecke je Feld (Block = 8 Welteinheiten), bis 2×2 Felder Grundflaeche, bis MAX_LAYERS Schichten.

signal build_changed(id: String)

const PER_CELL := 4
const MAX_SIDE := 8
const MAX_LAYERS := 12
const MAX_BLOCKS := 420
const BLOCKS_PER_HOUR := 8.0         # Baufortschritt der eigenen Leute (Bloecke je Spielstunde)
const MAX_DONE := 4                  # fertige Bauwerke je Firma
## Material je Block: Artikel des Grosslagers, Menge, Farbe
const MATERIALS := {
	"stein": {"item": "naturstein", "qty": 1, "color": "#a9a59b"},
	"ziegel": {"item": "ziegel", "qty": 10, "color": "#b5523b"},
	"holz": {"item": "holz", "qty": 1, "color": "#a8763e"},
	"beton": {"item": "beton", "qty": 1, "color": "#c8c5bd"},
	"glas": {"item": "glas", "qty": 2, "color": "#8fc7e0"},
	"stahl": {"item": "stahl", "qty": 1, "color": "#8d99a6"},
}
const CODE := {"X": "", "S": "stein", "Z": "ziegel", "H": "holz", "B": "beton", "G": "glas", "T": "stahl", "D": "dach"}
const FORMS := ["turm", "haus", "pyramide", "mauer", "bogen"]
const ROOFS := ["sattel", "zelt", "flach", "kein"]

var sim
var builds := {}                     # "FB<n>" -> {id, cid, name, idee, rect, blocks: [[x, y, z, mat]], placed, status, missing, day, acc}
var _next := 1


func setup(simulation) -> void:
	sim = simulation


func enabled() -> bool:
	return sim != null and sim.estate != null


func active_of(cid: int) -> Dictionary:
	for b in builds.values():
		if int(b.cid) == cid and str(b.status) != "fertig":
			return b
	return {}


func done_of(cid: int) -> int:
	return builds.values().filter(func(b): return int(b.cid) == cid and str(b.status) == "fertig").size()


# ------------------------------------------------------------------ Entwurf
## Bauwerk entwerfen. p: name, idee, form, breite, tiefe, hoehe (Bloecke), material, dach, dach_material, fenster (bool), plan (Array von Schichten).
func create(cid: int, p: Dictionary) -> Dictionary:
	if not enabled():
		return {"ok": false, "msg": "Freies Bauen ist hier nicht möglich."}
	var c = sim.company(cid)
	if c == null or c.status in ["insolvenz", "verwertung", "geschlossen"]:
		return {"ok": false, "msg": "Unternehmen kann nicht bauen."}
	if not active_of(cid).is_empty():
		return {"ok": false, "msg": "Es läuft schon ein Bau (%s) – erst fertig bauen." % active_of(cid).name}
	if done_of(cid) >= MAX_DONE:
		return {"ok": false, "msg": "Höchstens %d eigene Bauwerke." % MAX_DONE}
	var wall := str(p.get("material", "stein")).to_lower()
	var roof_mat := str(p.get("dach_material", "ziegel")).to_lower()
	for m in [wall, roof_mat]:
		if not MATERIALS.has(m):
			return {"ok": false, "msg": "Unbekanntes Material '%s'. Möglich: %s." % [m, ", ".join(MATERIALS.keys())]}
	var blocks: Array = []
	var plan = p.get("plan", [])
	if plan is String:
		plan = str(plan).split("|")
	if plan is Array and not (plan as Array).is_empty():
		blocks = _from_plan(plan, wall, roof_mat)
		if blocks.is_empty():
			return {"ok": false, "msg": "Bauplan unlesbar: je Schicht Zeilen mit / getrennt, Zeichen X (Wandmaterial), S Z H B G T (Material), D (Dach), . (leer); höchstens %d×%d, %d Schichten." % [MAX_SIDE, MAX_SIDE, MAX_LAYERS]}
	else:
		var form := str(p.get("form", "turm")).to_lower()
		if form not in FORMS:
			return {"ok": false, "msg": "Unbekannte Form '%s'. Möglich: %s – oder ein eigener plan." % [form, ", ".join(FORMS)]}
		var roof := str(p.get("dach", "sattel")).to_lower()
		if roof not in ROOFS:
			roof = "flach"
		blocks = shape(form, clampi(int(p.get("breite", 4)), 2, MAX_SIDE), clampi(int(p.get("tiefe", 4)), 1, MAX_SIDE), clampi(int(p.get("hoehe", 4)), 1, MAX_LAYERS),
			wall, roof, roof_mat, bool(p.get("fenster", false)))
	if blocks.size() > MAX_BLOCKS:
		return {"ok": false, "msg": "Zu groß: %d Blöcke (höchstens %d)." % [blocks.size(), MAX_BLOCKS]}
	var bw := 1
	var bd := 1
	for b in blocks:
		bw = maxi(bw, int(b[0]) + 1)
		bd = maxi(bd, int(b[1]) + 1)
	var cw := ceili(float(bw) / float(PER_CELL))
	var ch := ceili(float(bd) / float(PER_CELL))
	var site: Dictionary = sim.stone._find_site(cid, cw, ch)
	if site.is_empty():
		return {"ok": false, "msg": "Kein freier Platz %d×%d Felder mit Straße auf deinem Grundstück." % [cw, ch], "grund": "platz"}
	blocks.sort_custom(func(a, b): return int(a[2]) < int(b[2]) or (int(a[2]) == int(b[2]) and (int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))))
	var id := "FB%d" % _next
	_next += 1
	var fb := {"id": id, "cid": cid, "name": str(p.get("name", "")).left(40) if str(p.get("name", "")) != "" else "Bauwerk %s" % c.company_name.split(" ")[0],
		"idee": str(p.get("idee", p.get("reason", ""))).left(160), "rect": site.rect, "blocks": blocks, "placed": 0, "status": "im_bau", "missing": {},
		"day": GameCalendar.day_of(sim.game_min), "acc": 0.0}
	builds[id] = fb
	var need := needs(fb)
	sim.log_event("%s baut %s: %d Blöcke (%s). Material: %s." % [c.company_name, fb.name, blocks.size(), fb.idee if fb.idee != "" else "freie Idee",
		", ".join(need.keys().map(func(k): return "%d × %s" % [int(need[k]), CityGoods.get_item(k).name if CityGoods.exists(k) else k]))], "info", cid)
	build_changed.emit(id)
	return {"ok": true, "msg": "%s begonnen: %d Blöcke auf %s. Gesamtbedarf %s – Material liegt in deinen Lagern oder hol es mit hub_buy beim Großlager ab; gebaut wird Block für Block." % [
		fb.name, blocks.size(), site.parcel, str(need)], "ref": id}


## Bloecke aus Form und Groesse. Wand-Hohlkoerper, Fenster aus Glas jede zweite Schicht, Tuer unten mittig (haus), Dach zuletzt.
static func shape(form: String, w: int, d: int, h: int, wall: String, roof: String, roof_mat: String, windows: bool) -> Array:
	var out: Array = []
	var top := h
	match form:
		"pyramide":
			var lv := 0
			while lv * 2 < w and lv * 2 < d and lv < MAX_LAYERS:
				for y in range(lv, d - lv):
					for x in range(lv, w - lv):
						out.append([x, y, lv, wall])
				lv += 1
			return out
		"mauer":
			for z in h:
				for x in w:
					out.append([x, 0, z, wall])
			for x in range(0, w, 2):   # Zinnen
				out.append([x, 0, h, wall])
			return out
		"bogen":
			var pw := maxi(1, w / 4)
			for z in h:
				for y in d:
					for x in pw:
						out.append([x, y, z, wall])
						out.append([w - 1 - x, y, z, wall])
			for y in d:
				for x in w:
					out.append([x, y, h, wall])
			top = h + 1
		_:   # turm, haus: Hohlkoerper
			for z in h:
				for y in d:
					for x in w:
						var edge := x == 0 or y == 0 or x == w - 1 or y == d - 1
						if not edge and d > 2 and w > 2:
							continue
						var m := wall
						if form == "haus" and z == 0 and y == d - 1 and x == w / 2:
							continue   # Tuer
						if windows and z % 2 == 1 and edge and ((y == d - 1 and x > 0 and x < w - 1 and x % 2 == 1) or (x == w - 1 and y > 0 and y < d - 1 and y % 2 == 1)):
							m = "glas"
						out.append([x, y, z, m])
	# Dach
	match roof:
		"flach":
			for y in d:
				for x in w:
					out.append([x, y, top, roof_mat])
		"zelt":
			var k := 0
			while k * 2 < w and k * 2 < d and k < 6:
				for y in range(k, d - k):
					for x in range(k, w - k):
						if x == k or y == k or x == w - 1 - k or y == d - 1 - k:
							out.append([x, y, top + k, roof_mat])
				k += 1
		"sattel":   # First laengs x: von beiden Laengsseiten stufenweise nach innen
			var k2 := 0
			while k2 * 2 < d and k2 < 6:
				for x in w:
					out.append([x, k2, top + k2, roof_mat])
					if d - 1 - k2 != k2:
						out.append([x, d - 1 - k2, top + k2, roof_mat])
				k2 += 1
	return out


## Freier Bauplan: Schichten von unten nach oben, Zeilen mit "/" getrennt.
static func _from_plan(plan: Array, wall: String, roof_mat: String) -> Array:
	var out: Array = []
	for z in mini(plan.size(), MAX_LAYERS + 4):
		var rows: PackedStringArray = str(plan[z]).split("/")
		if rows.size() > MAX_SIDE:
			return []
		for y in rows.size():
			var row := str(rows[y]).strip_edges()
			if row.length() > MAX_SIDE:
				return []
			for x in row.length():
				var ch := row[x].to_upper()
				if ch in [".", " ", "_", "0"]:
					continue
				if not CODE.has(ch):
					return []
				var m: String = CODE[ch]
				m = wall if m == "" else (roof_mat if m == "dach" else m)
				out.append([x, y, z, m])
	return out


## Gesamter Materialbedarf (Artikel -> Menge) bzw. der noch nicht verbauten Bloecke.
func needs(fb: Dictionary, remaining := false) -> Dictionary:
	var out := {}
	var blocks: Array = fb.blocks
	for i in range(int(fb.placed) if remaining else 0, blocks.size()):
		var m: Dictionary = MATERIALS[str(blocks[i][3])]
		out[m.item] = int(out.get(m.item, 0)) + int(m.qty)
	return out


# ------------------------------------------------------------------ Bauen
func update(dt: float) -> void:
	if builds.is_empty():
		return
	var dmin := dt * Catalog.GAME_MIN_PER_SIM_SEC
	for fb in builds.values():
		if str(fb.status) == "fertig":
			continue
		fb.acc = float(fb.acc) + dmin * BLOCKS_PER_HOUR / 60.0
		var changed := false
		while float(fb.acc) >= 1.0 and int(fb.placed) < fb.blocks.size():
			if not _place_next(fb):
				fb.acc = 0.0
				break
			fb.acc = float(fb.acc) - 1.0
			changed = true
		if int(fb.placed) >= fb.blocks.size():
			fb.status = "fertig"
			fb.missing = {}
			sim.log_event("%s: %s ist fertig gebaut (%d Blöcke)." % [sim.company(int(fb.cid)).company_name, fb.name, fb.blocks.size()], "good", int(fb.cid))
			changed = true
		if changed:
			build_changed.emit(fb.id)


## Naechsten Block setzen: Material aus den eigenen Lagern verbrauchen; fehlt es, wartet die Baustelle.
func _place_next(fb: Dictionary) -> bool:
	var blk: Array = fb.blocks[int(fb.placed)]
	var m: Dictionary = MATERIALS[str(blk[3])]
	var owner := "C%d" % int(fb.cid)
	if sim.stock.available(m.item, owner) < int(m.qty):
		var rest := needs(fb, true)
		var miss := {}
		for it in rest:
			var have: int = sim.stock.available(it, owner) + (sim.hub.pending(owner, it) if sim.hub != null and sim.hub.enabled else 0)   # gekauft, noch nicht abgeholt
			if have < int(rest[it]):
				miss[it] = int(rest[it]) - have
		if str(fb.status) != "wartet_material":
			sim.log_event("%s: Baustelle %s wartet auf Material (%s) – beim Großlager abholen." % [sim.company(int(fb.cid)).company_name, fb.name, str(miss)], "warn", int(fb.cid))
		fb.status = "wartet_material"
		fb.missing = miss
		return false
	var left := int(m.qty)
	var c = sim.company(int(fb.cid))
	for site in c.depots:
		if left <= 0:
			break
		left -= sim.stock.consume(m.item, mini(left, sim.stock.available(m.item, owner, int(site))), owner, int(site), "Freibau %s" % fb.name, sim.game_min)
	if left > 0:   # Rest an anderen eigenen Standorten
		left -= sim.stock.consume(m.item, left, owner, -2, "Freibau %s" % fb.name, sim.game_min)
	fb.placed = int(fb.placed) + 1
	fb.status = "im_bau"
	fb.missing = {}
	return true


func cells_of(fb: Dictionary) -> Array:
	var out: Array = []
	for y in int(fb.rect[3]):
		for x in int(fb.rect[2]):
			out.append(Vector2i(int(fb.rect[0]) + x, int(fb.rect[1]) + y))
	return out


# ------------------------------------------------------------------ Beobachtung, Speichern
## Kompakt (Token-Budget der lokalen Modelle).
func obs_of(cid: int) -> Dictionary:
	var a := active_of(cid)
	var out := {"fertig": done_of(cid)}   # Bedarf je Block steht in der Aktionsbeschreibung (Token-Budget)
	if not a.is_empty():
		out["bau"] = {"name": a.name, "status": a.status, "bloecke": "%d/%d" % [int(a.placed), a.blocks.size()], "fehlt": a.missing}
	return out


func to_dict() -> Dictionary:
	return {"builds": builds, "next": _next}


func from_dict(d: Dictionary) -> void:
	builds = d.get("builds", {})
	_next = int(d.get("next", 1))
	for fb in builds.values():
		fb.placed = int(fb.placed)
		fb.cid = int(fb.cid)
