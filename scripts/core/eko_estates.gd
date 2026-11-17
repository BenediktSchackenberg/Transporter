class_name EkoEstates
extends RefCounted
## Stammsitz je KI-Spieler (Benedikt 15.11.2026: "jeder KI-Spieler bekommt eine feste Startposition, 8 Spielfelder + Bauplatz, kann in
## die Staedte gehen, aber seine Basis als Festung oder wunderschoenes Schloss ausbauen, Stadtmauern, Sicherheitszaeune").
## Anwesen = 3 x 3 Felder zu je FIELD x FIELD Kacheln auf flachem Land ausserhalb der Orte; Feld 4 (Mitte) ist der Bauplatz.
## Das Wesen erwacht dort. Bauwerke (Bauwerk {art, feld, material, hoehe}) baut eine Baufirma Block fuer Block in die Welt
## (dieselben Bloecke wie beim freien Bauen: Explosionen und Angriffe treffen sie). Mauer und Zaun sind fuer Fussgaenger echte
## Hindernisse; durch das Tor kommt man nur, wenn es offen ist (Tor {offen}). Wer im geschlossenen Anwesen steht, ist vor Nah- und
## Fernwaffen von aussen sicher; Loecher in der Mauer (eingerissen, gesprengt) sind Durchgaenge. Ein Turm wehrt Angreifer ab.

const FIELD := 8                    # Kacheln je Feld und Seite
const SIDE := FIELD * 3             # Kantenlaenge des Anwesens in Kacheln
const P := EkoWorld.PER_TILE
const BUILD_RATE := 6.0             # Bloecke je Sekunde (Baufirma)
const LABOR := 1.0                  # Arbeitslohn je Block
const ARTEN := {
	"mauer": "Mauer um das ganze Anwesen mit Zinnen und Tor (hoehe 3-8, Standard stein)",
	"zaun": "Sicherheitszaun um das ganze Anwesen mit Tor (Standard stahl, 2 hoch, billiger)",
	"burg": "Burg auf dem Bauplatz: Ringmauer mit Zinnen, vier Ecktuerme, Bergfried",
	"festung": "Festung auf dem Bauplatz: doppelt starke Mauern aus Beton, Ecktuerme, Bunker",
	"schloss": "Schloss auf dem Bauplatz: Palast mit Fensterreihen, Dach, zwei Seitentuerme, Garten",
	"turm": "Wachturm in einem Feld (wehrt Angreifer im Umkreis ab)",
	"garten": "Garten mit Wegen und Pflanzen in einem Feld",
}

var w                               # EkoWorld
var estates := {}                   # Name -> {rect, tor_offen, gate, wall_tiles, bauten}
var _next := 1


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


func rect_of(name: String) -> Rect2i:
	var e: Dictionary = estates.get(name, {})
	if e.is_empty():
		return Rect2i()
	return Rect2i(int(e.rect[0]), int(e.rect[1]), SIDE, SIDE)


## Zahlt die Firma? zahlung "firma" oder der eigene Firmenname (Partie 16.11.: Bodo schrieb zahlung "Bodo & Söhne").
func pays_firm(b: Dictionary, data: Dictionary) -> bool:
	var cid: int = w.active_firm(b)
	if cid < 0:
		return false
	var z := str(data.get("zahlung", "")).strip_edges().to_lower()
	return z in ["firma", "company", "unternehmen"] or (z != "" and z == str(_sim().company(cid).company_name).to_lower())


## Ausbau-Vorschlag fuer den Stammsitz (naechste_schritte): erstes noch fehlendes Bauwerk in sinnvoller Reihenfolge mit Preis.
## Rueckgabe {art, feld, kosten} oder {} (alles gebaut). Preise je Stammsitz und Art zwischengespeichert (Vorlagen haben Tausende Bloecke).
const SUGGEST := [["mauer", 0], ["turm", 0], ["schloss", 4], ["garten", 3], ["turm", 2], ["garten", 5]]
var _cost_cache := {}


func suggestion(name: String) -> Dictionary:
	if not estates.has(name):
		return {}
	var e: Dictionary = estates[name]
	var has_main := (e.bauten as Array).any(func(x): return int(x.feld) == 4 and x.art != "huette")
	for s in SUGGEST:
		var art: String = s[0]
		var f: int = s[1]
		if (e.bauten as Array).any(func(x): return x.art == art and (int(x.feld) == f or art in ["mauer", "zaun"])):
			continue
		if art == "mauer" and (e.bauten as Array).any(func(x): return x.art == "zaun"):
			continue
		if f == 4 and has_main:
			continue
		var key := "%s/%s/%d" % [name, art, f]
		if not _cost_cache.has(key):
			var mat: String = {"mauer": "stein", "schloss": "stein", "turm": "stein", "garten": "boden"}[art]
			var c := 0.0
			for bl in _template(name, art, f, mat, 4 if art == "mauer" else 2):
				c += float(EkoWorld.PRICES.get(str(bl[3]), 3.0)) + LABOR
			_cost_cache[key] = snappedf(c, 1.0)
		return {"art": art, "feld": f, "kosten": float(_cost_cache[key])}
	return {}


## Liegt das Feld in einem Stammsitz oder direkt daneben (Rand von einem Feld fuer Mauer und Zaun)?
func covers(q: Vector2i) -> bool:
	for e in estates.values():
		if q.x >= int(e.rect[0]) - 1 and q.y >= int(e.rect[1]) - 1 and q.x <= int(e.rect[0]) + SIDE and q.y <= int(e.rect[1]) + SIDE:
			return true
	return false


func field_rect(name: String, f: int) -> Rect2i:
	var r := rect_of(name)
	return Rect2i(r.position.x + (f % 3) * FIELD, r.position.y + (f / 3) * FIELD, FIELD, FIELD)


func center_of(name: String) -> Vector2i:
	return field_rect(name, 4).get_center()


# ------------------------------------------------------------------ Standort
## Flaches, freies Land ausserhalb der Orte, ohne Strassen, Gebaeude, Wasser, Berge und Parzellen; Abstand zu anderen Anwesen;
## zu Fuss mit einem Ort verbunden. Reihenfolge nach Seed, damit jede Partie andere Lagen hat.
## Wildnis: Basis am gewaehlten Platz (naechster passender Platz, hoechstens NEAR_MAX Felder entfernt).
const NEAR_MAX := 20.0
func assign_near(name: String, ctr: Vector2i) -> bool:
	return assign(name, ctr)


func assign(name: String, near := Vector2i(-1, -1)) -> bool:
	if estates.has(name):
		return true
	var C = _sim().city
	var n: int = C.size
	var busy := PackedByteArray()
	busy.resize(n * n)
	var wild: bool = _sim().wildnis and near.x >= 0
	for p in _sim().parcels.items.values():
		if str(p.state) in ["frei", "zur_entwicklung"] and str(p.zone) != "korridor":
			continue   # freies Land und Entwicklungsreserve ausserhalb der Orte darf Stammsitz werden (wird reserviert); Privatland und Trassen nicht
		if wild and int(p.get("building", -1)) < 0 and not str(p.owner).begins_with("C") 				and not _sim().prod._deposits.has(str(p.id)):
			continue   # Wildnis: noch niemand besitzt das Land (17.11.: Basis fand 20 Felder um den Platz nur "Privatland" der Kartenerzeugung)
		for y in range(int(p.rect[1]), int(p.rect[1]) + int(p.rect[3])):
			for x in range(int(p.rect[0]), int(p.rect[0]) + int(p.rect[2])):
				if x >= 0 and y >= 0 and x < n and y < n:
					busy[y * n + x] = 1
	var towns: Array = C.towns.filter(func(t): return not _sim().wildnis or bool(t.get("siedlung", false))).map(func(t): return Rect2i(int(t.rect[0]), int(t.rect[1]), int(t.rect[2]), int(t.rect[3])).grow(12))
	if near.x >= 0:   # Wildnis: die Basis entsteht am gewaehlten Platz (17.11.: Liorfurt rutschte 50 Felder weg)
		towns = towns.filter(func(t): return not t.has_point(near))
	var cands: Array = []
	for y in range(4, n - SIDE - 4, 6 if near.x < 0 else 2):
		for x in range(4, n - SIDE - 4, 6 if near.x < 0 else 2):
			var r := Rect2i(x, y, SIDE, SIDE)
			if near.x >= 0 and (r.get_center() - near).length() > NEAR_MAX:
				continue
			if towns.any(func(t): return t.intersects(r)):
				continue
			if estates.values().any(func(e): return Rect2i(int(e.rect[0]), int(e.rect[1]), SIDE, SIDE).grow(8).intersects(r)):
				continue
			cands.append(r)
	var seed_v: int = int(C.seed_value)
	if near.x >= 0:
		cands.sort_custom(func(a, b): return (a.get_center() - near).length_squared() < (b.get_center() - near).length_squared())
	else:
		cands.sort_custom(func(a, b): return hash([seed_v, a.position, name]) < hash([seed_v, b.position, name]))
	var stat := {"kand": cands.size(), "frei": 0, "ohne_weg": 0}
	for pass_i in 2:   # zweiter Durchgang: einzelne Huegelfelder erlaubt (hoechstens 10 %)
		var rough := SIDE * SIDE / 4 if near.x >= 0 else 0   # Wildnis: Wasser und Huegel in der Basis sind natuerlicher Schutz
		if _try(name, cands, busy, stat, (0 if pass_i == 0 else SIDE * SIDE / 10) + rough, rough):
			return true
	last_failure = stat
	return false


func _try(name: String, cands: Array, busy: PackedByteArray, stat: Dictionary, hills_ok: int, water_ok := 0) -> bool:
	for r in cands:
		var why := _block_reason(r, busy, hills_ok, water_ok)
		if why != "":
			stat[why] = int(stat.get(why, 0)) + 1
			continue
		stat.frei += 1
		var ctr: Vector2i = r.get_center()
		var goal := _nearest_town_tile(ctr)
		_open(r)
		if not _sim().nav.walk_reachable(ctr, goal):
			stat.ohne_weg += 1
			continue
		estates[name] = {"rect": [r.position.x, r.position.y], "tor_offen": true, "gate": [], "wall_tiles": [], "bauten": []}
		for p in _sim().parcels.items.values():   # Land reservieren: hier waechst keine Stadt hin
			if Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3])).intersects(r) and str(p.state) in ["frei", "zur_entwicklung"]:
				p.state = "privat_gehalten"
				p["use"] = "stammsitz"
		_starter_hut(name)
		_sim().log_event("%s erhält einen Stammsitz bei %d,%d." % [name, ctr.x, ctr.y], "info")
		return true
	return false


var last_failure := {}


func _block_reason(r: Rect2i, busy: PackedByteArray, hills_ok: int = 0, water_ok: int = 0) -> String:
	var C = _sim().city
	var cnt := {"parzelle": 0, "wasser": 0, "gebaeude": 0, "strasse": 0, "gleis": 0, "trasse": 0, "berg": 0}
	var S = _sim()
	for y in range(r.position.y - 1, r.end.y + 1):   # mit Rand: Mauer und Zaun nicht direkt an Strasse oder Gleis
		for x in range(r.position.x - 1, r.end.x + 1):
			var q := Vector2i(x, y)
			if not C.inside(q):
				continue
			var i: int = C.idx(q)
			if C.is_road(q): cnt.strasse += 1
			if C.ground[i] == CityData.G.RAIL or (S.rail != null and S.rail.is_rail(q)): cnt.gleis += 1
			if S.access != null and S.access.reserved(q): cnt.trasse += 1
			if not r.has_point(q):
				continue
			if busy[i] == 1: cnt.parzelle += 1
			if C.ground[i] == CityData.G.WATER: cnt.wasser += 1
			if C.building_at[i] >= 0: cnt.gebaeude += 1
			if not C.height.is_empty() and C.height[i] > 0: cnt.berg += 1
	for k in cnt:
		if int(cnt[k]) > (hills_ok if k == "berg" else (water_ok if k == "wasser" else 0)):
			return k
	return ""


func _nearest_town_tile(ctr: Vector2i) -> Vector2i:
	var best := ctr
	var bd := 1 << 30
	for s in w.sources():
		var t := Vector2i(int(s.feld[0]), int(s.feld[1]))
		var d: int = absi(t.x - ctr.x) + absi(t.y - ctr.y)
		if d < bd:
			bd = d
			best = t
	return best


## Anwesen begehbar machen und roden (Baeume liegen als gefaellt im Spielstand).
func _open(r: Rect2i) -> void:
	var cut := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			_sim().nav.walk.set_point_solid(c, false)
			cut[c] = true
	var before: int = _sim().city.trees.size()
	_sim().city.trees = _sim().city.trees.filter(func(t): return not cut.has(t[0]))
	if _sim().city.trees.size() != before:
		for c in cut:
			_sim().prod.felled.append([c.x, c.y])
		_sim().prod.trees_felled.emit(cut.keys())


# ------------------------------------------------------------------ Bauwerke
func order(b: Dictionary, data: Dictionary) -> Dictionary:
	var name: String = b.name
	if not estates.has(name):
		return {"ok": false, "msg": "Du hast keinen Stammsitz."}
	var art := str(data.get("art", ""))
	if not ARTEN.has(art):
		return {"ok": false, "msg": "art muss eine von %s sein." % ", ".join(ARTEN.keys())}
	var f := int(data.get("feld", 4))
	if art in ["burg", "festung", "schloss"]:
		f = 4
	if f < 0 or f > 8:
		return {"ok": false, "msg": "feld 0-8 (4 = Bauplatz in der Mitte)."}
	var e: Dictionary = estates[name]
	if (e.bauten as Array).any(func(x): return x.art == art and (int(x.feld) == f or art in ["mauer", "zaun"])):
		return {"ok": false, "msg": "Dieses Bauwerk gibt es dort schon."}
	var mat := str(data.get("material", {"mauer": "stein", "zaun": "stahl", "festung": "beton", "schloss": "stein", "burg": "stein", "turm": "stein", "garten": "boden"}[art]))
	if not EkoWorld.PRICES.has(mat):
		return {"ok": false, "msg": "Unbekanntes Material %s." % mat}
	var h := clampi(int(data.get("hoehe", 4 if art == "mauer" else 2)), 2, 8)
	var blocks := _template(name, art, f, mat, h)
	var cost := 0.0
	for bl in blocks:
		cost += float(EkoWorld.PRICES.get(str(bl[3]), 3.0)) + LABOR
	cost = snappedf(cost, 1.0)
	var from_firm: bool = pays_firm(b, data)
	if from_firm:
		var c = _sim().company(w.active_firm(b))
		if c.ledger.cash < cost:
			return {"ok": false, "msg": "%s kostet %s, die Firmenkasse hat %s." % [art, Catalog.money(cost), Catalog.money(c.ledger.cash)]}
		c.ledger.book("property_costs", -cost, true, "Stammsitz: %s" % art, _sim().game_min, "K0")
	else:
		if float(b.get("geld", 0.0)) < cost:
			return {"ok": false, "msg": "%s (%d Blöcke) kostet %s, du hast %s. Mit zahlung: \"firma\" zahlt deine Firma." % [art, blocks.size(), Catalog.money(cost), Catalog.money(float(b.get("geld", 0.0)))]}
		_sim().economy.transfer("Y0", "K0", cost)
		b.geld = float(b.geld) - cost
	(e.bauten as Array).append({"id": "S%d" % _next, "art": art, "feld": f, "material": mat, "blocks": blocks, "placed": 0, "acc": 0.0, "status": "im_bau"})
	_next += 1
	w._event(b, "lässt auf seinem Stammsitz bauen: %s" % art)
	_sim().log_event("%s lässt auf dem Stammsitz bauen: %s (%d Blöcke, %s)." % [name, art, blocks.size(), Catalog.money(cost)], "info")
	return {"ok": true, "status": "laeuft", "msg": "%s beauftragt: %d Blöcke %s, %s, fertig in etwa %d s." % [art, blocks.size(), mat, Catalog.money(cost), int(blocks.size() / BUILD_RATE)]}


## Starthuette (Feld 7, suedlich des Bauplatzes): Holzhaus mit Tuer, Dach, Bett und Ladestation, sofort fertig. Damit ist das Wesen
## von Anfang an zu Hause und laedt schnell; der Bauplatz bleibt frei fuer das, was es selbst baut.
const HUT_FIELD := 7


func _starter_hut(name: String) -> void:
	var F := field_rect(name, HUT_FIELD)
	var x0 := F.position.x * P + 10
	var y0 := F.position.y * P + 10
	var blocks: Array = []
	for z in 3:
		for x in range(x0, x0 + 12):
			for y in range(y0, y0 + 12):
				var edge := x == x0 or y == y0 or x == x0 + 11 or y == y0 + 11
				if not edge:
					continue
				if y == y0 + 11 and x in [x0 + 5, x0 + 6] and z < 2:   # Tuer nach Sueden
					continue
				blocks.append([x, y, z, "glas" if z == 1 and (x == x0 or x == x0 + 11) and y in [y0 + 4, y0 + 7] else "holz"])
	for x in range(x0, x0 + 12):
		for y in range(y0, y0 + 12):
			blocks.append([x, y, 3, "dach"])
	blocks.append([x0 + 2, y0 + 2, 0, "bett"])
	blocks.append([x0 + 9, y0 + 2, 0, "ladestation"])
	blocks.append([x0 + 2, y0 + 8, 0, "tisch"])
	blocks.append([x0 + 9, y0 + 8, 0, "lampe"])
	for bl in blocks:
		w.blocks[Vector3i(int(bl[0]), int(bl[1]), int(bl[2]))] = str(bl[3])
	(estates[name].bauten as Array).append({"id": "S%d" % _next, "art": "huette", "feld": HUT_FIELD, "material": "holz", "blocks": [],
		"placed": 0, "acc": 0.0, "status": "fertig"})
	_next += 1
	w.changed.emit()


## Blocklisten der Bauwerke ([x, y, z, material] in Blockkoordinaten).
func _template(name: String, art: String, f: int, mat: String, h: int) -> Array:
	var out: Array = []
	var R := rect_of(name)
	var F := field_rect(name, f)
	match art:
		"mauer", "zaun":
			var x0 := R.position.x * P
			var y0 := R.position.y * P
			var x1 := R.end.x * P - 1
			var y1 := R.end.y * P - 1
			var gate := _gate_blocks(name)
			var hh := h if art == "mauer" else 2
			for x in range(x0, x1 + 1):
				for y in [y0, y1]:
					_wall_column(out, x, y, hh, mat, art == "mauer" and x % 2 == 0, gate)
			for y in range(y0 + 1, y1):
				for x in [x0, x1]:
					_wall_column(out, x, y, hh, mat, art == "mauer" and y % 2 == 0, gate)
		"burg", "festung":
			var thick := 2 if art == "festung" else 1
			var x0 := F.position.x * P
			var y0 := F.position.y * P
			var x1 := F.end.x * P - 1
			var y1 := F.end.y * P - 1
			for t in thick:
				for x in range(x0 + t, x1 + 1 - t):
					for y in [y0 + t, y1 - t]:
						if not (y == y1 - t and absi(x - (x0 + x1) / 2) <= 1):   # Durchgang Sued
							_wall_column(out, x, y, 5, mat, t == 0 and x % 2 == 0, {})
				for y in range(y0 + 1 + t, y1 - t):
					for x in [x0 + t, x1 - t]:
						_wall_column(out, x, y, 5, mat, t == 0 and y % 2 == 0, {})
			for c in [Vector2i(x0, y0), Vector2i(x1 - 3, y0), Vector2i(x0, y1 - 3), Vector2i(x1 - 3, y1 - 3)]:   # Ecktuerme
				_tower(out, c, 4, 8, mat)
			var k := Vector2i((x0 + x1) / 2 - 3, (y0 + y1) / 2 - 3)   # Bergfried / Bunker
			_tower(out, k, 7, 10 if art == "burg" else 4, mat)
			if art == "festung":
				for x in range(k.x, k.x + 7):
					for y in range(k.y, k.y + 7):
						out.append([x, y, 4, mat])   # Bunkerdecke
		"schloss":
			var x0 := F.position.x * P + 2
			var y0 := F.position.y * P + 4
			var w0 := FIELD * P - 4
			var d0 := 12
			for z in 6:
				for x in range(x0, x0 + w0):
					for y in [y0, y0 + d0 - 1]:
						var win := (z == 2 or z == 4) and x % 3 == 1
						out.append([x, y, z, "glas" if win else mat])
				for y in range(y0 + 1, y0 + d0 - 1):
					for x in [x0, x0 + w0 - 1]:
						out.append([x, y, z, "glas" if (z == 2 or z == 4) and y % 3 == 1 else mat])
			for x in range(x0, x0 + w0):   # Dach
				for y in range(y0, y0 + d0):
					out.append([x, y, 6, "dach"])
			_tower(out, Vector2i(x0 - 2, y0 - 2), 4, 9, mat)
			_tower(out, Vector2i(x0 + w0 - 2, y0 - 2), 4, 9, mat)
			for x in range(x0, x0 + w0):   # Garten vor dem Schloss
				for y in range(y0 + d0 + 2, F.end.y * P - 1):
					if (x + y) % 4 == 0:
						out.append([x, y, 0, "pflanze"])
					elif x == x0 + w0 / 2:
						out.append([x, y, 0, "boden"])
		"turm":
			var c := Vector2i(F.position.x * P + FIELD * P / 2 - 2, F.position.y * P + FIELD * P / 2 - 2)
			_tower(out, c, 4, 10, mat)
		"garten":
			for x in range(F.position.x * P + 1, F.end.x * P - 1):
				for y in range(F.position.y * P + 1, F.end.y * P - 1):
					if x % 8 == 0 or y % 8 == 0:
						out.append([x, y, 0, "boden"])
					elif (x * 7 + y * 3) % 5 == 0:
						out.append([x, y, 0, "pflanze"])
	return out


func _wall_column(out: Array, x: int, y: int, h: int, mat: String, merlon: bool, gate: Dictionary) -> void:
	if gate.has(Vector2i(floori(float(x) / P), floori(float(y) / P))):
		return
	for z in h:
		out.append([x, y, z, mat])
	if merlon:   # Zinne
		out.append([x, y, h, mat])


func _tower(out: Array, c: Vector2i, size: int, h: int, mat: String) -> void:
	for z in h:
		for x in range(c.x, c.x + size):
			for y in range(c.y, c.y + size):
				var edge := x == c.x or y == c.y or x == c.x + size - 1 or y == c.y + size - 1
				if edge or z == h - 1:
					out.append([x, y, z, "glas" if edge and z == h - 3 and (x + y) % 2 == 0 else mat])
	for x in range(c.x, c.x + size):   # Zinnenkranz
		for y in range(c.y, c.y + size):
			if (x == c.x or y == c.y or x == c.x + size - 1 or y == c.y + size - 1) and (x + y) % 2 == 0:
				out.append([x, y, h, mat])


## Tor: zwei Kacheln mitten in der Suedseite.
func _gate_blocks(name: String) -> Dictionary:
	var R := rect_of(name)
	var cx := R.position.x + SIDE / 2
	return {Vector2i(cx - 1, R.end.y - 1): true, Vector2i(cx, R.end.y - 1): true}


# ------------------------------------------------------------------ Takt, Tor, Schutz
func tick(dt: float) -> void:
	_plans_tick(dt)
	for name in estates:
		var hands := 1.0
		if _sim().wildnis:   # Benedikt 17.11.: die KI baut selbst – nur waehrend sie an der Basis arbeitet (Bauen {baustelle: "stammsitz"})
			var o: Dictionary = w.beings.get(name, {})
			hands = 1.0 if str(o.get("baut", "")) == "stammsitz" and not o.has("im_lkw") and covers(w.tile_of(o)) else 0.0
		for s in estates[name].bauten:
			if s.status != "im_bau":
				continue
			s.acc = float(s.acc) + dt * BUILD_RATE * hands
			while float(s.acc) >= 1.0 and int(s.placed) < (s.blocks as Array).size():
				s.acc = float(s.acc) - 1.0
				var bl: Array = s.blocks[int(s.placed)]
				var p := Vector3i(int(bl[0]), int(bl[1]), int(bl[2]))
				if not w.blocks.has(p):
					w.blocks[p] = str(bl[3])
				s.placed = int(s.placed) + 1
			if int(s.placed) >= (s.blocks as Array).size():
				_finish(name, s)
			w.changed.emit()


func _finish(name: String, s: Dictionary) -> void:
	s.status = "fertig"
	var e: Dictionary = estates[name]
	if s.art in ["mauer", "zaun"]:
		var tiles := {}
		for bl in s.blocks:
			tiles[Vector2i(floori(float(bl[0]) / P), floori(float(bl[1]) / P))] = true
		e.wall_tiles = tiles.keys().map(func(t): return [t.x, t.y])
		e.gate = _gate_blocks(name).keys().map(func(t): return [t.x, t.y])
		apply_walls(name)
	if s.art == "turm":
		var c := field_rect(name, int(s.feld)).get_center()
		w.arms.towers.append({"stadt": -1, "feld": [c.x, c.y], "besitzer": name})
	if w.beings.has(name):
		w._event(w.beings[name], "Stammsitz: %s ist fertig" % s.art)
	_sim().log_event("Stammsitz von %s: %s ist fertig." % [name, s.art], "good")


## Mauerkacheln sperren (nur solange dort noch Mauer steht), Tor nach Zustand.
func apply_walls(name: String) -> void:
	var e: Dictionary = estates[name]
	var N = _sim().nav
	for t in e.wall_tiles:   # Mauer und Zaun sperren Fussgaenger und Fahrzeuge (Benedikt 16.11.: "nicht mit dem Auto durchfahren")
		var c := Vector2i(int(t[0]), int(t[1]))
		var wall := _has_wall(c)
		N.walk.set_point_solid(c, wall)
		if N.road.is_in_boundsv(c) and (wall or _sim().city.is_road(c)):
			N.road.set_point_solid(c, wall)   # Loch in der Mauer: Strasse dort wieder frei
	for t in e.gate:   # durchs offene Tor duerfen auch Fahrzeuge (falls dort eine Strasse ist)
		var g := Vector2i(int(t[0]), int(t[1]))
		N.walk.set_point_solid(g, not bool(e.tor_offen))
		if N.road.is_in_boundsv(g) and _sim().city.is_road(g):
			N.road.set_point_solid(g, not bool(e.tor_offen))


func _has_wall(c: Vector2i) -> bool:
	for i in P:
		for j in P:
			if w.blocks.has(Vector3i(c.x * P + i, c.y * P + j, 0)):
				return true
	return false


func gate(b: Dictionary, data: Dictionary) -> Dictionary:
	var e: Dictionary = estates.get(b.name, {})
	if e.is_empty() or (e.gate as Array).is_empty():
		return {"ok": false, "msg": "Du hast noch keine Mauer und keinen Zaun mit Tor (Bauwerk mauer oder zaun)."}
	e.tor_offen = bool(data.get("offen", not bool(e.tor_offen)))
	apply_walls(b.name)
	var R := rect_of(b.name)
	for t in e.gate:   # Torfluegel: geschlossen sichtbar als Holzbloecke
		for i in P:
			for z in 3:
				var p := Vector3i(int(t[0]) * P + i, R.end.y * P - 1, z)
				if bool(e.tor_offen):
					w.blocks.erase(p)
				else:
					w.blocks[p] = "holz"
	w.changed.emit()
	w._event(b, "%s das Tor seines Stammsitzes" % ("öffnet" if bool(e.tor_offen) else "schließt"))
	return {"ok": true, "msg": "Tor %s." % ("offen" if bool(e.tor_offen) else "geschlossen – niemand kommt hinein (du auch nicht hinaus, bis du es öffnest)")}


## Mauer intakt (keine Luecke), Tor zu, Wesen steht drinnen -> geschuetzt vor Nah- und Fernwaffen von aussen.
func sheltered(b: Dictionary, from: Vector2i) -> bool:
	var e: Dictionary = estates.get(b.name, {})
	if e.is_empty() or (e.wall_tiles as Array).is_empty() or bool(e.tor_offen):
		return false
	var R := rect_of(b.name)
	if not R.has_point(w.tile_of(b)) or R.has_point(from):
		return false
	return breaches(b.name) == 0


func breaches(name: String) -> int:
	var n := 0
	for t in estates[name].wall_tiles:
		if not _has_wall(Vector2i(int(t[0]), int(t[1]))):
			n += 1
	return n


## Wesen auf dem Bauplatz mit fertiger Burg, Festung oder fertigem Schloss gilt als zu Hause (schnelles Laden).
func at_home(b: Dictionary) -> bool:
	var e: Dictionary = estates.get(b.name, {})
	if e.is_empty():
		return false
	for s in e.bauten:
		if s.status == "fertig" and s.art in ["burg", "festung", "schloss", "huette"] and field_rect(b.name, int(s.feld)).has_point(w.tile_of(b)):
			return true
	return false


## Nach Zerstoerung: Loecher in der Mauer werden begehbar.
func refresh() -> void:
	for name in estates:
		if not (estates[name].wall_tiles as Array).is_empty():
			apply_walls(name)


# ------------------------------------------------------------------ Beobachtung, Speichern
func obs(b: Dictionary) -> Dictionary:
	var name: String = b.name
	if not estates.has(name):
		return {}
	var e: Dictionary = estates[name]
	var R := rect_of(name)
	var fields: Array = []
	for f in 9:
		var F := field_rect(name, f)
		fields.append({"feld": f, "kacheln": [F.position.x, F.position.y, FIELD, FIELD], "bauplatz": f == 4})
	return {"bereich": [R.position.x, R.position.y, SIDE, SIDE], "mitte": [center_of(name).x, center_of(name).y], "felder": fields,
		"bauten": (e.bauten as Array).map(func(s): return {"art": s.art, "feld": s.feld, "material": s.material, "status": s.status,
			"fortschritt": "%d %%" % int(100.0 * float(s.placed) / maxf(1.0, float((s.blocks as Array).size())))}),
		"tor": {"felder": e.gate, "offen": bool(e.tor_offen)} if not (e.gate as Array).is_empty() else {},
		"mauerluecken": breaches(name) if not (e.wall_tiles as Array).is_empty() else 0, "geschuetzt_drinnen": sheltered(b, Vector2i(-999, -999)),
		"zu_hause": at_home(b),
		"bauwerke": ARTEN, "bauen": "Bauwerk {art, feld 0-8 (4 = Bauplatz), material?, hoehe?, zahlung?: \"firma\"} – Preis je Block nach material_preise; Tor {offen: true|false}",
		"eigener_entwurf": "Bauplan {titel, ort: stammsitz|grundstueck, feld?, schichten: [[Zeilen der untersten Schicht], ...], legende?, zahlung?} – baue genau so, wie du es dir ausdenkst (bis 32 x 32 Blöcke je Feld)"}


func visible(b: Dictionary) -> Array:
	var t: Vector2i = w.tile_of(b)
	var out: Array = []
	for name in estates:
		if name == b.name:
			continue
		var R := rect_of(name)
		if w._dist(t, R.get_center()) <= EkoWorld.VIEW_RADIUS + SIDE:
			var e: Dictionary = estates[name]
			out.append({"besitzer": name, "bereich": [R.position.x, R.position.y, SIDE, SIDE], "mauer": not (e.wall_tiles as Array).is_empty(),
				"tor_offen": bool(e.tor_offen), "luecken": breaches(name) if not (e.wall_tiles as Array).is_empty() else 0,
				"bauten": (e.bauten as Array).filter(func(s): return s.status == "fertig").map(func(s): return s.art)})
	return out


func to_dict() -> Dictionary:
	return {"estates": estates, "next": _next, "plans": plans}


func from_dict(d: Dictionary) -> void:
	estates = d.get("estates", {})
	_next = int(d.get("next", 1))
	plans = d.get("plans", [])
	for name in estates:
		_open(rect_of(name))
		if not (estates[name].bauten as Array).any(func(x): return x.art == "huette"):   # aeltere Stammsitze bekommen die Starthuette nachgeliefert
			_starter_hut(name)
		if not (estates[name].wall_tiles as Array).is_empty():
			apply_walls(name)

# ------------------------------------------------------------------ Eigener Bauplan (15.11.2026)
## Benedikt: "die KI soll immer entscheiden, wie ein Haus gebaut wird und wie es aussieht". Das Wesen beschreibt sein Gebaeude
## Schicht fuer Schicht (unten zuerst) als Zeichenraster; eine Baufirma baut genau das (Block fuer Block, Preis nach Material).
## Ort: ein Feld des Stammsitzes (bis 32 x 32 Bloecke) oder das eigene Grundstueck (MoveIn danach wie beim Selbstbau).
const LEGEND := {"S": "stein", "Z": "ziegel", "H": "holz", "B": "beton", "G": "glas", "T": "stahl", "D": "dach", "F": "boden",
	"P": "pflanze", "L": "lampe", "X": "bett", "Y": "ladestation", "Q": "tisch", "R": "regal", "K": "teppich", "U": "buch", "C": "decke"}
const PLAN_MAX_LAYERS := 16
const PLAN_MAX_BLOCKS := 4000

var plans: Array = []               # Bauplaene auf Grundstuecken {name, titel, blocks, placed, acc, status}


func build_plan(b: Dictionary, data: Dictionary) -> Dictionary:
	var name: String = b.name
	var layers = data.get("schichten", [])
	if not (layers is Array) or layers.is_empty() or layers.size() > PLAN_MAX_LAYERS:
		return {"ok": false, "msg": "schichten: Liste von 1-%d Schichten (unten zuerst), jede Schicht eine Liste von Zeilen, z. B. [\"SSGSS\", \"S...S\"]. Zeichen: %s; '.' = leer." % [PLAN_MAX_LAYERS, _legend_text()]}
	var legend := LEGEND.duplicate()
	var own = data.get("legende", {})
	if own is Dictionary:
		for k in own:
			if str(k).length() == 1 and EkoWorld.PRICES.has(str(own[k])):
				legend[str(k)] = str(own[k])
	# Zielflaeche in Bloecken
	var area := Rect2i()
	var ort := str(data.get("ort", "stammsitz" if estates.has(name) else "grundstueck"))
	if ort == "stammsitz":
		if not estates.has(name):
			return {"ok": false, "msg": "Du hast keinen Stammsitz."}
		var F := field_rect(name, clampi(int(data.get("feld", 4)), 0, 8))
		area = Rect2i(F.position * P, F.size * P)
	else:
		var pid := str(b.get("grundstueck", ""))
		if pid == "":
			return {"ok": false, "msg": "Du hast kein Grundstück (BuyPlot) und keinen Stammsitz."}
		var pr: Rect2i = w.plot_rect(pid)
		area = Rect2i(pr.position * P, pr.size * P)
	var blocks: Array = []
	var cost := 0.0
	for z in layers.size():
		var rows = layers[z]
		if rows is String:
			rows = str(rows).split("/")
		for y in (rows as Array).size():
			var row := str(rows[y])
			for x in row.length():
				var ch := row[x]
				if ch == "." or ch == " ":
					continue
				if not legend.has(ch):
					return {"ok": false, "msg": "Unbekanntes Zeichen '%s' in Schicht %d, Zeile %d. Zeichen: %s." % [ch, z, y, _legend_text()]}
				var p := Vector3i(area.position.x + x, area.position.y + y, z)
				if not area.has_point(Vector2i(p.x, p.y)):
					return {"ok": false, "msg": "Der Plan ist größer als die Fläche (%d x %d Blöcke)." % [area.size.x, area.size.y]}
				blocks.append([p.x, p.y, p.z, legend[ch]])
				cost += float(EkoWorld.PRICES.get(legend[ch], 3.0)) + LABOR
	if blocks.is_empty() or blocks.size() > PLAN_MAX_BLOCKS:
		return {"ok": false, "msg": "Ein Plan hat 1-%d Blöcke (deiner: %d)." % [PLAN_MAX_BLOCKS, blocks.size()]}
	cost = snappedf(cost, 1.0)
	if pays_firm(b, data):
		var c = _sim().company(w.active_firm(b))
		if c.ledger.cash < cost:
			return {"ok": false, "msg": "Der Bau kostet %s, die Firmenkasse hat %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
		c.ledger.book("property_costs", -cost, true, "Bauplan %s" % str(data.get("titel", "")), _sim().game_min, "K0")
	else:
		if float(b.get("geld", 0.0)) < cost:
			return {"ok": false, "msg": "Der Bau (%d Blöcke) kostet %s, du hast %s. Mit zahlung: \"firma\" zahlt deine Firma." % [blocks.size(), Catalog.money(cost), Catalog.money(float(b.get("geld", 0.0)))]}
		_sim().economy.transfer("Y0", "K0", cost)
		b.geld = float(b.geld) - cost
	var titel := str(data.get("titel", "Eigenbau")).left(40)
	plans.append({"name": name, "titel": titel, "blocks": blocks, "placed": 0, "acc": 0.0, "status": "im_bau"})
	w._event(b, "lässt nach eigenem Plan bauen: %s" % titel)
	_sim().log_event("%s lässt nach eigenem Entwurf bauen: „%s“ (%d Blöcke, %s)." % [name, titel, blocks.size(), Catalog.money(cost)], "info")
	return {"ok": true, "status": "laeuft", "msg": "„%s“ beauftragt: %d Blöcke, %s, fertig in etwa %d s." % [titel, blocks.size(), Catalog.money(cost), int(blocks.size() / BUILD_RATE)]}


func _legend_text() -> String:
	var parts: Array = []
	for k in LEGEND:
		parts.append("%s=%s" % [k, LEGEND[k]])
	return ", ".join(parts)


func _plans_tick(dt: float) -> void:
	for pl in plans:
		if pl.status != "im_bau":
			continue
		pl.acc = float(pl.acc) + dt * BUILD_RATE
		while float(pl.acc) >= 1.0 and int(pl.placed) < (pl.blocks as Array).size():
			pl.acc = float(pl.acc) - 1.0
			var bl: Array = pl.blocks[int(pl.placed)]
			var p := Vector3i(int(bl[0]), int(bl[1]), int(bl[2]))
			if not w.blocks.has(p):
				w.blocks[p] = str(bl[3])
			pl.placed = int(pl.placed) + 1
		if int(pl.placed) >= (pl.blocks as Array).size():
			pl.status = "fertig"
			if w.beings.has(pl.name):
				w._event(w.beings[pl.name], "Bau „%s“ ist fertig" % pl.titel)
			_sim().log_event("„%s“ von %s ist fertig gebaut." % [pl.titel, pl.name], "good")
		w.changed.emit()
