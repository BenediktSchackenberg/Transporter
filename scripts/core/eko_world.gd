class_name EkoWorld
extends RefCounted
## Eko-Modus (Benedikt, 15.11.2026, Idee nach "Is this machine playing?" / Clawblox, MIT): freie Wesen ohne vorgegebenes Ziel.
## Ein Sprachmodell-Agent (z. B. Claude Code) steuert ein Wesen ueber wenige Grundhandlungen (WorldServer, docs/EKO_API.md):
## gehen, Material am Bauhof aufnehmen, Block setzen, Block wieder aufnehmen, sprechen. Was entsteht, entscheidet allein der Agent.
## Bloecke liegen in einem feinen Raster (4 x 4 je Feld wie FreeBuild) und werden mit FreeBuild-Farben gezeichnet (EkoView).
## Phase 1: Material kostenlos, Wesen laufen in Echtzeit (unabhaengig von der Spielgeschwindigkeit), Bloecke versperren keine Wege.

signal changed

const PER_TILE := 4                 # Bloecke je Feld und Achse
const MAX_Z := 24                   # hoechste Schicht (0-basiert: 0..23)
const CARRY := 4                    # Bloecke, die ein Wesen gleichzeitig tragen kann
const REACH := 2                    # Reichweite in Feldern (Schachbrett-Abstand) fuer Setzen/Aufnehmen
const SOURCE_REACH := 2             # Abstand in Feldern zum Bauhof fuer Material
const WALK_SPEED := 3.0             # Felder je Echtzeitsekunde
const SAY_SECONDS := 8.0
const MAX_BLOCKS := 20000
const MAX_EVENTS := 30
const MAX_CHAT := 100
const VIEW_RADIUS := 10             # Kartenausschnitt in Feldern um das Wesen
const SIDES := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const COLORS := [Color("#e8c04a"), Color("#5fb3d9"), Color("#d96b5f"), Color("#7fcf6a"), Color("#b98ad9")]

var sim
var beings := {}                    # Name -> {name, mover, held: [Material], say, say_left, events: [], color, joined}
var blocks := {}                    # Vector3i (Blockraster) -> Material
var chat: Array = []                # [{t (Echtzeit-ISO), von, text}]


func setup(simulation) -> void:
	sim = simulation


# ------------------------------------------------------------------ Wesen
func join(name: String) -> Dictionary:
	name = name.strip_edges().left(24)
	if name == "" or not RegEx.create_from_string("^[A-Za-z0-9_ÄÖÜäöüß -]+$").search(name):
		return {"ok": false, "msg": "Name fehlt oder enthaelt ungueltige Zeichen."}
	if not beings.has(name):
		var m := Mover.new()
		m.lane = 0.0
		m.speed = WALK_SPEED
		m.pos = sim.city.tile_center(_spawn_tile())
		beings[name] = {"name": name, "mover": m, "held": [], "say": "", "say_left": 0.0, "events": [],
			"color": COLORS[beings.size() % COLORS.size()]}
		_event(beings[name], "ist in der Welt erwacht")
		sim.log_event("Eko-Modus: %s ist erwacht." % name, "info")
	changed.emit()
	return {"ok": true, "name": name}


func _spawn_tile() -> Vector2i:
	for s in sources():   # begehbares Feld am Bauhof, damit das Wesen gleich Material holen kann
		var w := Vector2i(int(s.feld[0]), int(s.feld[1]))
		for r in range(0, SOURCE_REACH + 1):
			for d in [Vector2i(0, r), Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, r)]:
				if sim.city.walkable(w + d):
					return w + d
		return w
	return Vector2i(sim.city.size / 2, sim.city.size / 2)


func tile_of(b: Dictionary) -> Vector2i:
	return (b.mover as Mover).tile()


## Materialquellen: Bauhof jeder Stadt (Phase 1: kostenlos).
func sources() -> Array:
	var out: Array = []
	for t in sim.city.towns:
		var id := int(t.get("bauhof", -1))
		var b: Dictionary = sim.city.building(id)
		if not b.is_empty():
			out.append({"name": str(b.name), "feld": [int(b.walk.x), int(b.walk.y)]})
	if out.is_empty():
		for b in sim.city.buildings:
			if str(b.get("role", "")) == "bauhof" or str(b.get("name", "")).contains("Bauhof"):
				out.append({"name": str(b.name), "feld": [int(b.walk.x), int(b.walk.y)]})
				break
	return out


## Echtzeit-Takt (Sekunden). Laeuft nur, wenn die Partie nicht pausiert ist.
func update(dt: float) -> void:
	for b in beings.values():
		var m: Mover = b.mover
		if not m.arrived():
			m.advance(dt, 1.0)
			if m.arrived():
				_event(b, "ist bei Feld %d,%d angekommen" % [m.tile().x, m.tile().y])
		if float(b.say_left) > 0.0:
			b.say_left = maxf(0.0, float(b.say_left) - dt)


# ------------------------------------------------------------------ Handlungen
func input(name: String, type: String, data: Dictionary) -> Dictionary:
	var b: Dictionary = beings.get(name, {})
	if b.is_empty():
		return {"ok": false, "msg": "Unbekanntes Wesen. Erst POST /join."}
	var r: Dictionary
	match type:
		"MoveTo":
			r = _move_to(b, data)
		"Stop":
			var m: Mover = b.mover
			m.set_path([m.tile()])
			r = {"ok": true, "msg": "angehalten"}
		"Pickup":
			r = _pickup(b, data)
		"Place":
			r = _place(b, data)
		"Say":
			r = say(name, str(data.get("text", "")))
		_:
			r = {"ok": false, "msg": "Unbekannte Handlung %s. Erlaubt: MoveTo, Stop, Pickup, Place, Say." % type}
	if not bool(r.ok):
		_event(b, "Fehlschlag %s: %s" % [type, r.msg])
	changed.emit()
	return r


func _move_to(b: Dictionary, data: Dictionary) -> Dictionary:
	var t = data.get("tile", data.get("feld"))
	if not (t is Array) or t.size() < 2:
		return {"ok": false, "msg": "MoveTo braucht tile: [x, y] (Feldkoordinaten)."}
	var to := Vector2i(int(t[0]), int(t[1]))
	if not sim.city.inside(to):
		return {"ok": false, "msg": "Feld %d,%d liegt ausserhalb der Karte (0..%d)." % [to.x, to.y, sim.city.size - 1]}
	var m: Mover = b.mover
	var p: Array[Vector2i] = sim.nav.walk_path(m.tile(), to)
	if p.is_empty():
		return {"ok": false, "msg": "Kein Fussweg zu %d,%d." % [to.x, to.y]}
	m.set_path(p)
	var end: Vector2i = p[-1]
	return {"ok": true, "msg": "unterwegs nach %d,%d (%d Felder, ca. %.0f s)%s" % [end.x, end.y, p.size() - 1,
		(p.size() - 1) / WALK_SPEED, "" if end == to else "; Ziel nicht begehbar, naechster erreichbarer Punkt"]}


func _pickup(b: Dictionary, data: Dictionary) -> Dictionary:
	var held: Array = b.held
	if data.has("block"):   # gesetzten Block wieder aufnehmen
		var p = _vec(data.block)
		if p == null:
			return {"ok": false, "msg": "block braucht [x, y, z]."}
		if not blocks.has(p):
			return {"ok": false, "msg": "An %s liegt kein Block." % _fmt(p)}
		if blocks.has(p + Vector3i(0, 0, 1)):
			return {"ok": false, "msg": "Auf %s liegt noch ein Block; erst den oberen aufnehmen." % _fmt(p)}
		if not _in_reach(b, p):
			return {"ok": false, "msg": "Block %s ist ausser Reichweite (hoechstens %d Felder)." % [_fmt(p), REACH]}
		if held.size() >= CARRY:
			return {"ok": false, "msg": "Haende voll (%d Bloecke)." % CARRY}
		for d in SIDES:   # Nachbarn, die nur an diesem Block haengen, wuerden sonst frei schweben (gefunden von Eko, 15.11.)
			if blocks.has(p + d) and not _supported(p + d, p):
				return {"ok": false, "msg": "%s haelt noch %s; erst den aeusseren Block aufnehmen." % [_fmt(p), _fmt(p + d)]}
		held.append(blocks[p])
		blocks.erase(p)
		_event(b, "nimmt %s bei %s auf" % [held[-1], _fmt(p)])
		return {"ok": true, "msg": "aufgenommen: %s" % held[-1], "traegt": held}
	var mat := str(data.get("material", ""))
	if not FreeBuild.MATERIALS.has(mat):
		return {"ok": false, "msg": "Material muss eines von %s sein." % ", ".join(FreeBuild.MATERIALS.keys())}
	if not _at_source(b):
		return {"ok": false, "msg": "Material gibt es nur am Bauhof (siehe quellen in /observe)."}
	var n := clampi(int(data.get("count", 1)), 1, CARRY - held.size())
	if held.size() >= CARRY:
		return {"ok": false, "msg": "Haende voll (%d Bloecke)." % CARRY}
	for i in n:
		held.append(mat)
	_event(b, "holt %d x %s am Bauhof" % [n, mat])
	return {"ok": true, "msg": "%d x %s aufgenommen" % [n, mat], "traegt": held}


func _place(b: Dictionary, data: Dictionary) -> Dictionary:
	var held: Array = b.held
	var p = _vec(data.get("block"))
	if p == null:
		return {"ok": false, "msg": "Place braucht block: [x, y, z] (Blockraster: Feld x %d + 0..%d, z = Schicht ab 0)." % [PER_TILE, PER_TILE - 1]}
	if held.is_empty():
		return {"ok": false, "msg": "Du traegst nichts. Erst Material am Bauhof holen (Pickup)."}
	var mat := str(data.get("material", held[0]))
	if mat not in held:
		return {"ok": false, "msg": "Du traegst kein %s (traegst: %s)." % [mat, ", ".join(held)]}
	var why := can_place(p)
	if why != "":
		return {"ok": false, "msg": why}
	if not _in_reach(b, p):
		return {"ok": false, "msg": "%s ist ausser Reichweite (hoechstens %d Felder)." % [_fmt(p), REACH]}
	held.erase(mat)
	blocks[p] = mat
	_event(b, "setzt %s bei %s" % [mat, _fmt(p)])
	return {"ok": true, "msg": "%s gesetzt bei %s" % [mat, _fmt(p)], "traegt": held}


## Leerer Text = erlaubt. Bloecke nur auf freiem Boden (keine Strasse, kein Gebaeude), mit Halt darunter oder seitlich; ueber Wasser nur oberhalb des Bodens.
func can_place(p: Vector3i) -> String:
	var tile := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
	if not sim.city.inside(tile) or p.z < 0 or p.z >= MAX_Z:
		return "%s liegt ausserhalb (Schicht 0..%d)." % [_fmt(p), MAX_Z - 1]
	if blocks.has(p):
		return "An %s liegt schon ein Block." % _fmt(p)
	if blocks.size() >= MAX_BLOCKS:
		return "Die Welt traegt keine weiteren Bloecke (%d)." % MAX_BLOCKS
	if sim.city.is_road(tile):
		return "Feld %d,%d ist eine Strasse." % [tile.x, tile.y]
	if int(sim.city.building_at[sim.city.idx(tile)]) >= 0:
		return "Auf Feld %d,%d steht ein Gebaeude." % [tile.x, tile.y]
	if p.z == 0 and sim.city.g(tile) == CityData.G.WATER:   # ueber dem Wasser mit seitlichem Halt erlaubt (Bruecken)
		return "Feld %d,%d ist Wasser (darueber geht es nur mit seitlichem Halt, z. B. als Bruecke vom Ufer)." % [tile.x, tile.y]
	if not _supported(p, Vector3i(-1, -1, -1)):
		return "%s haette keinen Halt (Block darunter oder daneben noetig)." % _fmt(p)
	return ""


## Halt: Boden (Schicht 0 auf Land), Block darunter oder seitlich daneben; without wird nicht mitgezaehlt.
func _supported(p: Vector3i, without: Vector3i) -> bool:
	if p.z == 0:
		var tile := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
		if sim.city.g(tile) != CityData.G.WATER:
			return true
	for d in SIDES + [Vector3i(0, 0, -1)]:
		if p + d != without and blocks.has(p + d):
			return true
	return false


func say(name: String, text: String) -> Dictionary:
	var b: Dictionary = beings.get(name, {})
	text = text.strip_edges().left(200)
	if b.is_empty() or text == "":
		return {"ok": false, "msg": "Text fehlt."}
	b.say = text
	b.say_left = SAY_SECONDS
	chat.append({"t": Time.get_datetime_string_from_system(true) + "Z", "von": name, "text": text})
	if chat.size() > MAX_CHAT:
		chat = chat.slice(-MAX_CHAT)
	return {"ok": true, "msg": "gesagt"}


func chat_after(after: String, limit: int) -> Array:
	return chat.filter(func(m): return after == "" or str(m.t) > after).slice(-clampi(limit, 1, MAX_CHAT))


# ------------------------------------------------------------------ Beobachtung
func observe(name: String) -> Dictionary:
	var b: Dictionary = beings.get(name, {})
	if b.is_empty():
		return {"ok": false, "msg": "Unbekanntes Wesen. Erst POST /join."}
	var m: Mover = b.mover
	var t := m.tile()
	var near_blocks: Array = []
	var near_buildings := {}
	var rows: Array = []
	var height := {}   # Feld -> hoechste Schicht + 1
	for p in blocks:
		var bt := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
		if absi(bt.x - t.x) <= VIEW_RADIUS and absi(bt.y - t.y) <= VIEW_RADIUS:
			if near_blocks.size() < 400:
				near_blocks.append([p.x, p.y, p.z, blocks[p]])
			height[bt] = maxi(int(height.get(bt, 0)), p.z + 1)
	for y in range(t.y - VIEW_RADIUS, t.y + VIEW_RADIUS + 1):
		var row := ""
		for x in range(t.x - VIEW_RADIUS, t.x + VIEW_RADIUS + 1):
			var c := Vector2i(x, y)
			if c == t:
				row += "@"
			elif not sim.city.inside(c) or sim.city.g(c) == CityData.G.WATER:
				row += "~"
			elif height.has(c):
				var h := int(height[c])
				row += str(h) if h <= 9 else "+"
			elif sim.city.is_road(c):
				row += "="
			elif int(sim.city.building_at[sim.city.idx(c)]) >= 0:
				row += "#"
				var bd: Dictionary = sim.city.building(int(sim.city.building_at[sim.city.idx(c)]))
				near_buildings[str(bd.name)] = [int(bd.walk.x), int(bd.walk.y)]
			elif not sim.city.walkable(c):
				row += "^"
			else:
				row += "."
		rows.append(row)
	var others: Array = []
	for o in beings.values():
		if o.name != name:
			var ot := tile_of(o)
			others.append({"name": o.name, "feld": [ot.x, ot.y], "traegt": o.held, "sagt": o.say if float(o.say_left) > 0.0 else ""})
	var src: Array = []
	for s in sources():
		s["entfernung"] = absi(int(s.feld[0]) - t.x) + absi(int(s.feld[1]) - t.y)
		src.append(s)
	return {"ok": true,
		"du": {"name": name, "feld": [t.x, t.y], "unterwegs": not m.arrived(), "ziel": [m.goal.x, m.goal.y] if not m.arrived() else null,
			"traegt": b.held, "tragkraft": CARRY, "am_bauhof": _at_source(b)},
		"zeit": Catalog.game_minutes_to_text(sim.game_min), "wetter": sim.wx.headline(),
		"karte": {"mitte": [t.x, t.y], "radius": VIEW_RADIUS, "zeilen": rows,
			"legende": "@ du, . freier Boden, = Strasse, # Gebaeude, ~ Wasser, ^ unbegehbar (Baum/Berg), 1-9/+ hoechste Blockschicht auf dem Feld"},
		"bloecke_in_der_naehe": near_blocks, "bloecke_gesamt": blocks.size(),
		"gebaeude_in_der_naehe": near_buildings, "quellen": src, "materialien": FreeBuild.MATERIALS.keys(),
		"andere_wesen": others, "deine_letzten_ereignisse": b.events.slice(-10)}


# ------------------------------------------------------------------ Hilfen
func _at_source(b: Dictionary) -> bool:
	var t := tile_of(b)
	for s in sources():
		if maxi(absi(int(s.feld[0]) - t.x), absi(int(s.feld[1]) - t.y)) <= SOURCE_REACH:
			return true
	return false


func _in_reach(b: Dictionary, p: Vector3i) -> bool:
	var t := tile_of(b)
	var bt := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
	return maxi(absi(bt.x - t.x), absi(bt.y - t.y)) <= REACH


func _vec(v):
	if v is Array and v.size() >= 3:
		return Vector3i(int(v[0]), int(v[1]), int(v[2]))
	return null


func _fmt(p: Vector3i) -> String:
	return "[%d,%d,%d]" % [p.x, p.y, p.z]


func _event(b: Dictionary, text: String) -> void:
	var ev: Array = b.events
	ev.append("%s %s" % [Catalog.game_minutes_to_text(sim.game_min), text])
	if ev.size() > MAX_EVENTS:
		b.events = ev.slice(-MAX_EVENTS)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	var bl: Array = []
	for p in blocks:
		bl.append([p.x, p.y, p.z, blocks[p]])
	var bs: Array = []
	for b in beings.values():
		bs.append({"name": b.name, "x": b.mover.pos.x, "y": b.mover.pos.y, "held": b.held, "events": b.events})
	return {"blocks": bl, "beings": bs, "chat": chat}


func from_dict(d: Dictionary) -> void:
	blocks.clear()
	beings.clear()
	for e in d.get("blocks", []):
		blocks[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = str(e[3])
	for e in d.get("beings", []):
		join(str(e.name))
		var b: Dictionary = beings[str(e.name)]
		b.mover.pos = Vector2(float(e.x), float(e.y))
		b.held = e.get("held", [])
		b.events = e.get("events", [])
	chat = d.get("chat", [])
