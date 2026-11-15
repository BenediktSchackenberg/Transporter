class_name EkoWorld
extends RefCounted
## Eko-Modus (Benedikt, 15.11.2026, Idee nach "Is this machine playing?" / Clawblox, MIT): freie Wesen ohne vorgegebenes Ziel.
## Ein Sprachmodell-Agent (z. B. Claude Code) steuert ein Wesen ueber wenige Grundhandlungen (WorldServer, docs/EKO_API.md):
## gehen, Material am Bauhof aufnehmen, Block setzen, Block wieder aufnehmen, sprechen, mit Figuren in der Naehe reden. Was entsteht, entscheidet allein der Agent.
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
const TALK_REACH := 3               # Felder: so nah muss man fuer ein Gespraech sein
const HEAR_RADIUS := 12             # Felder: Gesagtes in diesem Umkreis wird gehoert
const ARTEN := ["mensch", "roboter"]
const COLORS := [Color("#e8c04a"), Color("#5fb3d9"), Color("#d96b5f"), Color("#7fcf6a"), Color("#b98ad9")]

var sim
var beings := {}                    # Name -> {name, art, mover, held: [Material], say, say_left, events: [], color}
var blocks := {}                    # Vector3i (Blockraster) -> Material
var chat: Array = []                # [{t (Echtzeit-ISO), von, an, text, feld}]


func setup(simulation) -> void:
	sim = simulation


# ------------------------------------------------------------------ Wesen
func join(name: String, art: String = "mensch") -> Dictionary:
	name = name.strip_edges().left(24)
	art = art if art in ARTEN else "mensch"
	if name == "" or not RegEx.create_from_string("^[A-Za-z0-9_ÄÖÜäöüß -]+$").search(name):
		return {"ok": false, "msg": "Name fehlt oder enthaelt ungueltige Zeichen."}
	if not beings.has(name):
		var m := Mover.new()
		m.lane = 0.0
		m.speed = WALK_SPEED
		m.pos = sim.city.tile_center(_spawn_tile())
		beings[name] = {"name": name, "art": art, "mover": m, "held": [], "say": "", "say_left": 0.0, "events": [], "geld": 0.0,
			"job": "", "grundstueck": "", "done_jobs": 0, "rest_left": 0.0, "firma": -1,
			"color": COLORS[beings.size() % COLORS.size()]}
		_event(beings[name], "ist in der Welt erwacht")
		sim.log_event("%s %s ist erwacht." % ["Der kleine Roboter" if art == "roboter" else "Das Wesen", name], "info")
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
		if float(b.get("rest_left", 0.0)) > 0.0:
			b.rest_left = maxf(0.0, float(b.rest_left) - dt)
	_jobs_tick(dt)
	_houses_tick(dt)


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
			var here: Array[Vector2i] = [m.tile()]
			m.set_path(here)
			r = {"ok": true, "msg": "angehalten"}
		"Pickup":
			r = _pickup(b, data)
		"Place":
			r = _place(b, data)
		"Say":
			r = say(name, str(data.get("text", "")))
		"Talk":
			r = _talk(b, str(data.get("to", "")), str(data.get("text", "")))
		"AcceptJob":
			r = _accept_job(b, str(data.get("job", "")))
		"Deliver":
			r = _deliver(b, str(data.get("job", "")))
		"BuyPlot":
			r = _buy_plot(b, str(data.get("plot", "")))
		"OrderHouse":
			r = _order_house(b, data)
		"Rest":
			r = _rest(b)
		"FoundCompany":
			r = _found_company(b, data)
		"Firma":
			r = _firm_action(b, data)
		_:
			r = {"ok": false, "msg": "Unbekannte Handlung %s. Erlaubt: MoveTo, Stop, Pickup, Place, Say, Talk, AcceptJob, Deliver, BuyPlot, OrderHouse, Rest, FoundCompany, Firma." % type}
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
	if data.has("job"):   # Kisten eines Botengangs
		return _pickup_job(b, str(data.job))
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
	var mat := str(data.get("material", held.filter(func(m): return FreeBuild.MATERIALS.has(m)).front() if held.any(func(m): return FreeBuild.MATERIALS.has(m)) else held[0]))
	if mat not in held:
		return {"ok": false, "msg": "Du traegst kein %s (traegst: %s)." % [mat, ", ".join(held)]}
	if not FreeBuild.MATERIALS.has(mat):
		return {"ok": false, "msg": "%s wird abgeliefert (Deliver), nicht verbaut." % mat}
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
	for h in houses.values():
		var o := Vector2i(int(h.origin[0]), int(h.origin[1]))
		if p.x >= o.x and p.y >= o.y and p.x < o.x + HOUSE_SIDE and p.y < o.y + HOUSE_SIDE:
			return "Dort steht ein Haus."
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
	_chat(name, "", text, tile_of(b))
	return {"ok": true, "msg": "gesagt"}


func _chat(von: String, an: String, text: String, at: Vector2i) -> void:
	chat.append({"t": Time.get_datetime_string_from_system(true) + "Z", "von": von, "an": an, "text": text, "feld": [at.x, at.y]})
	if chat.size() > MAX_CHAT:
		chat = chat.slice(-MAX_CHAT)


## Gespraech mit einer Figur in der Naehe: einem anderen Wesen (bekommt es als Ereignis und hoert es) oder einem Unternehmer.
## Unternehmer antworten aus ihrem echten Zustand (Ziel und Begruendung der letzten KI-Entscheidung); Firmen mit Sprachmodell
## sehen die Worte als Meldung in ihrer Beobachtung (sim.notify).
func _talk(b: Dictionary, to: String, text: String) -> Dictionary:
	text = text.strip_edges().left(200)
	if to == "" or text == "":
		return {"ok": false, "msg": "Talk braucht to (Name aus figuren_in_der_naehe oder andere_wesen) und text."}
	var t := tile_of(b)
	b.say = text
	b.say_left = SAY_SECONDS
	if beings.has(to) and to != b.name:
		var o: Dictionary = beings[to]
		if _dist(t, tile_of(o)) > TALK_REACH:
			return {"ok": false, "msg": "%s ist zu weit weg (hoechstens %d Felder)." % [to, TALK_REACH]}
		_chat(b.name, to, text, t)
		_event(o, "%s sagt zu dir: %s" % [b.name, text])
		return {"ok": true, "msg": "%s hat es gehoert und kann antworten." % to}
	for c in sim.companies:
		if str(c.player_name) == to or str(c.company_name) == to:
			var at: Vector2i = sim.avatars[c.id].tile()
			if _dist(t, at) > TALK_REACH:
				return {"ok": false, "msg": "%s ist zu weit weg (bei Feld %d,%d, hoechstens %d Felder)." % [to, at.x, at.y, TALK_REACH]}
			_chat(b.name, str(c.player_name), text, t)
			sim.notify(c.id, "%s %s spricht dich an: \"%s\"" % ["Der kleine Roboter" if b.art == "roboter" else "Das Wesen", b.name, text])
			var reply := _company_reply(c)
			sim.avatars[c.id].say(reply.left(90), false)
			_chat(str(c.player_name), b.name, reply, at)
			_event(b, "%s antwortet: %s" % [c.player_name, reply])
			return {"ok": true, "msg": "%s antwortet: %s" % [c.player_name, reply]}
	return {"ok": false, "msg": "Niemand namens %s in der Naehe (siehe figuren_in_der_naehe)." % to}


func _company_reply(c) -> String:
	var last := {}
	for i in range(sim.decisions.entries.size() - 1, -1, -1):
		var d: Dictionary = sim.decisions.entries[i]
		if int(d.company) == c.id and (str(d.get("ziel", "")) != "" or str(d.get("begruendung", "")) != ""):
			last = d
			break
	var s := "Ich bin %s von %s. Gerade %s." % [c.player_name, c.company_name, LiveText.figure_text(sim, c.id)]
	if str(last.get("ziel", "")) != "":
		s += " Mein Ziel: %s." % str(last.ziel).left(90)
	if str(last.get("begruendung", "")) != "":
		s += " Zuletzt dachte ich: %s" % str(last.begruendung).left(120)
	for j in jobs.values():
		if int(j.cid) == c.id and j.status == "offen":
			s += " Ich hätte Arbeit für dich: %s Lohn %s (Auftrag %s, mit AcceptJob annehmen)." % [j.text, Catalog.money(float(j.lohn)), j.id]
	return s


## Was andere in Hoerweite gesagt haben (ohne eigene Worte), neueste zuletzt.
func heard(name: String, n: int = 6) -> Array:
	var t := tile_of(beings[name])
	var out: Array = []
	for m in chat:
		if str(m.von) != name and m.has("feld") and _dist(t, Vector2i(int(m.feld[0]), int(m.feld[1]))) <= HEAR_RADIUS:
			out.append({"von": m.von, "an": m.get("an", ""), "text": m.text})
	return out.slice(-n)


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


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
			others.append({"name": o.name, "art": o.art, "feld": [ot.x, ot.y], "traegt": o.held, "sagt": o.say if float(o.say_left) > 0.0 else ""})
	var figures: Array = []
	for c in sim.companies:
		var at: Vector2i = sim.avatars[c.id].tile()
		if c.is_active():   # alle Unternehmer der Region, naechste zuerst; ansprechen geht ab TALK_REACH Feldern
			figures.append({"name": c.player_name, "rolle": "Unternehmer", "firma": c.company_name, "feld": [at.x, at.y],
				"entfernung": _dist(t, at), "gerade": LiveText.figure_text(sim, c.id).left(80)})
	figures.sort_custom(func(a, b2): return int(a.entfernung) < int(b2.entfernung))
	figures = figures.slice(0, 8)
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
		"andere_wesen": others, "figuren_in_der_naehe": figures, "gehoert": heard(name),
		"jobangebote": _job_obs(b) if int(b.get("firma", -1)) < 0 else [], "mein_auftrag": jobs.get(str(b.get("job", "")), {}).duplicate(),
		"lebensziel": _home_obs(b), "meine_firma": firm_obs(b),
		"deine_letzten_ereignisse": b.events.slice(-10)}


# ------------------------------------------------------------------ Arbeit fuer die KI-Firmen (15.11.2026)
## Aktive Firmen mit Geld bieten Wesen kleine Auftraege an und zahlen Lohn aus ihrer Kasse (Konto Y0 "Freie Wesen").
## botengang: Kisten am Betriebshof der Firma abholen und zu einem Gebaeude im Ort bringen.
## mauer: am Hof der Firma eine kleine Mauer aus Bloecken eines Materials setzen (Material vom Bauhof).
const JOB_EVERY_S := 20.0           # Echtzeitsekunden zwischen zwei Runden, in denen Firmen neue Angebote machen
const JOB_OPEN_S := 600.0           # so lange bleibt ein Angebot offen
const JOB_MAX_OPEN := 5
const JOB_MIN_CASH := 3000.0
const CALL_EVERY_S := 25.0          # so oft ruft eine Firmenfigur ein Wesen in Sichtweite an

var jobs := {}                      # "J<n>" -> Auftrag
var _next_job := 1
var _job_timer := 0.0
var _call_timer := 0.0


func _jobs_tick(dt: float) -> void:
	for j in jobs.values():
		if j.status == "offen":
			j.rest_s = float(j.rest_s) - dt
			if float(j.rest_s) <= 0.0:
				j.status = "abgelaufen"
	_job_timer -= dt
	if _job_timer <= 0.0 and not beings.is_empty():
		_job_timer = JOB_EVERY_S
		var open := jobs.values().filter(func(j): return j.status == "offen").size()
		for c in sim.companies:
			if open >= JOB_MAX_OPEN:
				break
			if not c.is_active() or c.ledger.cash < JOB_MIN_CASH or c.depots.is_empty():
				continue
			if jobs.values().any(func(j): return int(j.cid) == c.id and j.status in ["offen", "angenommen"]):
				continue
			if not _new_job(c).is_empty():
				open += 1
	_call_timer -= dt
	if _call_timer <= 0.0:
		_call_timer = CALL_EVERY_S
		for j in jobs.values():
			if j.status != "offen":
				continue
			var at: Vector2i = sim.avatars[int(j.cid)].tile()
			for b in beings.values():
				if _dist(tile_of(b), at) <= VIEW_RADIUS and str(b.get("job", "")) == "":
					var text := "Hey %s! Ich hätte Arbeit für dich: %s Lohn %s. (Auftrag %s)" % [b.name, j.text, Catalog.money(float(j.lohn)), j.id]
					sim.avatars[int(j.cid)].say(text.left(90), false)
					_chat(str(j.person), b.name, text, at)
					_event(b, "%s ruft dir zu: %s" % [j.person, text])
					break


func _new_job(c) -> Dictionary:
	var depot: Dictionary = sim.city.building(int(c.depots[0]))
	var home: Vector2i = depot.walk
	var town: int = sim.city.town_of(home)
	var j := {"id": "J%d" % _next_job, "cid": c.id, "firma": c.company_name, "person": c.player_name, "status": "offen",
		"rest_s": JOB_OPEN_S, "by": "", "von": [home.x, home.y], "von_name": str(depot.name)}
	if sim.rng.randf() < 0.6:
		var dest := {}
		for i in 12:   # Ziel: ein Gebaeude im selben Ort, 10-45 Felder entfernt
			var b: Dictionary = sim.city.buildings[sim.rng.randi() % sim.city.buildings.size()]
			if b.is_empty() or not b.has("walk") or sim.city.town_of(b.walk) != town:
				continue
			var d := _dist(home, b.walk)
			if d >= 10 and d <= 45 and sim.city.walkable(b.walk):
				dest = b
				break
		if dest.is_empty():
			return {}
		var n: int = sim.rng.randi_range(1, 3)
		var d2 := _dist(home, dest.walk)
		j.merge({"art": "botengang", "menge": n, "nach": [int(dest.walk.x), int(dest.walk.y)], "nach_name": str(dest.name),
			"lohn": float(roundi(30 + d2 * 3 + n * 10)),
			"text": "Bring %d Kiste%s von %s nach %s." % [n, "" if n == 1 else "n", depot.name, dest.name]})
	else:
		var area := _free_area_near(home, 2, 1)
		if area.is_empty():
			return {}
		var n: int = sim.rng.randi_range(4, 8)
		var mat: String = ["stein", "ziegel", "holz"][sim.rng.randi() % 3]
		j.merge({"art": "mauer", "menge": n, "material": mat, "bereich": area, "nach": [int(area[0]), int(area[1])],
			"nach_name": "Hof von %s" % c.company_name, "lohn": float(n * 22),
			"text": "Bau mir eine kleine Mauer aus %d Blöcken %s auf den Feldern %d,%d bis %d,%d neben meinem Hof." % [n, mat,
				area[0], area[1], area[0] + area[2] - 1, area[1] + area[3] - 1]})
	jobs[j.id] = j
	_next_job += 1
	return j


## Freie, bebaubare Felder (w x h) in der Naehe eines Punktes, [x, y, w, h] oder [].
func _free_area_near(p: Vector2i, w: int, h: int) -> Array:
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var o := p + Vector2i(dx, dy)
				var ok := true
				for yy in h:
					for xx in w:
						var t := o + Vector2i(xx, yy)
						if not sim.city.walkable(t) or can_place(Vector3i(t.x * PER_TILE, t.y * PER_TILE, 0)) != "":
							ok = false
				if ok:
					return [o.x, o.y, w, h]
	return []


func _accept_job(b: Dictionary, id: String) -> Dictionary:
	var j: Dictionary = jobs.get(id, {})
	if j.is_empty() or j.status != "offen":
		return {"ok": false, "msg": "Auftrag %s gibt es nicht (mehr) oder er ist vergeben." % id}
	if str(b.get("job", "")) != "":
		return {"ok": false, "msg": "Du arbeitest schon an %s. Erst abliefern." % b.job}
	j.status = "angenommen"
	j.by = b.name
	b.job = id
	_event(b, "nimmt Auftrag %s von %s an: %s" % [id, j.person, j.text])
	sim.notify(int(j.cid), "%s hat deinen Auftrag %s angenommen: %s" % [b.name, id, j.text])
	return {"ok": true, "msg": "Auftrag %s angenommen. %s Lohn %s." % [id, j.text, Catalog.money(float(j.lohn))]}


func _pickup_job(b: Dictionary, id: String) -> Dictionary:
	var j: Dictionary = jobs.get(id, {})
	if j.is_empty() or j.by != b.name or j.art != "botengang":
		return {"ok": false, "msg": "Kisten gibt es nur fuer deinen angenommenen Botengang."}
	if _dist(tile_of(b), Vector2i(int(j.von[0]), int(j.von[1]))) > SOURCE_REACH:
		return {"ok": false, "msg": "Die Kisten stehen bei %s (Feld %d,%d)." % [j.von_name, j.von[0], j.von[1]]}
	if b.held.has("kiste"):
		return {"ok": false, "msg": "Du traegst die Kisten schon."}
	if b.held.size() + int(j.menge) > CARRY:
		return {"ok": false, "msg": "Haende zu voll fuer %d Kisten (traegst %s)." % [j.menge, ", ".join(b.held)]}
	for i in int(j.menge):
		b.held.append("kiste")
	_event(b, "nimmt %d Kisten bei %s auf" % [j.menge, j.von_name])
	return {"ok": true, "msg": "%d Kisten aufgenommen, jetzt nach %s (Feld %d,%d)." % [j.menge, j.nach_name, j.nach[0], j.nach[1]], "traegt": b.held}


func _deliver(b: Dictionary, id: String) -> Dictionary:
	var j: Dictionary = jobs.get(id if id != "" else str(b.get("job", "")), {})
	if j.is_empty() or j.by != b.name or j.status != "angenommen":
		return {"ok": false, "msg": "Kein angenommener Auftrag %s." % id}
	if j.art == "botengang":
		if _dist(tile_of(b), Vector2i(int(j.nach[0]), int(j.nach[1]))) > SOURCE_REACH:
			return {"ok": false, "msg": "Abliefern bei %s (Feld %d,%d)." % [j.nach_name, j.nach[0], j.nach[1]]}
		if b.held.count("kiste") < int(j.menge):
			return {"ok": false, "msg": "Du traegst nicht alle %d Kisten." % j.menge}
		for i in int(j.menge):
			b.held.erase("kiste")
	else:
		var n := 0
		var a: Array = j.bereich
		for p in blocks:
			var t := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
			if blocks[p] == j.material and t.x >= int(a[0]) and t.y >= int(a[1]) and t.x < int(a[0]) + int(a[2]) and t.y < int(a[1]) + int(a[3]):
				n += 1
		if n < int(j.menge):
			return {"ok": false, "msg": "Erst %d von %d Blöcken %s im Bereich %s gesetzt." % [n, j.menge, j.material, str(a)]}
	var c = sim.company(int(j.cid))
	var lohn := float(j.lohn)
	c.ledger.book("wages", -lohn, true, "%s: Auftrag %s (%s)" % [b.name, j.id, j.art], sim.game_min, "Y0")
	b.geld = float(b.get("geld", 0.0)) + lohn
	j.status = "erledigt"
	b.job = ""
	b.done_jobs = int(b.get("done_jobs", 0)) + 1
	var thanks := "Danke, %s! Gute Arbeit. Hier sind %s." % [b.name, Catalog.money(lohn)]
	sim.avatars[int(j.cid)].say(thanks, false)
	_chat(str(j.person), b.name, thanks, tile_of(b))
	_event(b, "liefert %s ab und bekommt %s von %s" % [j.id, Catalog.money(lohn), j.person])
	sim.notify(int(j.cid), "%s hat Auftrag %s erledigt (%s Lohn gezahlt)." % [b.name, j.id, Catalog.money(lohn)])
	sim.log_event("%s erledigt Auftrag %s für %s und verdient %s." % [b.name, j.id, j.firma, Catalog.money(lohn)], "good")
	return {"ok": true, "msg": "%s erledigt. %s zahlt dir %s. Du hast jetzt %s." % [j.id, j.person, Catalog.money(lohn), Catalog.money(float(b.geld))]}


func _job_obs(b: Dictionary) -> Array:
	var t := tile_of(b)
	var out: Array = []
	for j in jobs.values():
		if j.status == "offen" or (j.status == "angenommen" and j.by == b.name):
			var e := {"id": j.id, "von": j.person, "firma": j.firma, "auftrag": j.text, "lohn": float(j.lohn), "status": j.status,
				"abholen_bei": j.von if j.art == "botengang" else null, "ziel_feld": j.nach,
				"entfernung": _dist(t, Vector2i(int(j.von[0]), int(j.von[1])))}
			out.append(e)
	out.sort_custom(func(a, c): return int(a.entfernung) < int(c.entfernung))
	return out.slice(0, 6)


# ------------------------------------------------------------------ Lebensziel: Grundstueck, Haus, Wohnen
## Wesen koennen ein freies Wohngrundstueck der Stadt kaufen (Geld an den Ort) und eine Baufirma mit einem Haus beauftragen
## (Geld an K0 "Baufirmen"). Das Haus entsteht sichtbar Block fuer Block (8 x 8 Bloecke = 2 x 2 Felder) und wird als
## Schnitt gezeichnet: ohne Dach und mit niedriger Vorderwand, damit man das Wesen drinnen wohnen sieht (EkoView).
const HOUSE_PRICE := 2400.0
const HOUSE_SIDE := 8               # Bloecke je Seite (2 Felder)
const HOUSE_WALL := 4               # Wandhoehe in Schichten ueber dem Boden
const HOUSE_BUILD_S := 0.6          # Echtzeitsekunden je Block
const REST_SECONDS := 20.0
const FURNITURE := {"boden": "#c9a26b", "teppich": "#7a5ea8", "bett": "#e9e4f0", "decke": "#5fb3d9", "tisch": "#8a5a2b",
	"lampe": "#ffe27a", "pflanze": "#4caf50", "regal": "#6d4c41", "buch": "#d9534f", "ladestation": "#5be7ff", "dach": "#8e3b2f",
	"kiste": "#b07a3a"}

var houses := {}                    # Name des Wesens -> {plot, origin: [bx, by], blocks: [[x,y,z,mat]], placed, status, builder, acc}


func _plot_obs(b: Dictionary) -> Array:
	var t := tile_of(b)
	var town: int = sim.city.town_of(t)
	var out: Array = []
	for p in sim.parcels.search({"town": town, "zone": "wohnen", "max_area": 40, "limit": 40}):
		var r: Array = p.rect
		if int(r[2]) < 2 or int(r[3]) < 2:
			continue
		var c := Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) / 2)
		out.append({"id": p.id, "feld": [c.x, c.y], "groesse": "%dx%d Felder" % [r[2], r[3]], "preis": float(p.price),
			"entfernung": _dist(t, c)})
	out.sort_custom(func(a, c): return int(a.entfernung) < int(c.entfernung))
	return out.slice(0, 5)


func _buy_plot(b: Dictionary, id: String) -> Dictionary:
	if str(b.get("grundstueck", "")) != "":
		return {"ok": false, "msg": "Du hast schon ein Grundstück (%s)." % b.grundstueck}
	var p: Dictionary = sim.parcels.parcel(id)
	if p.is_empty() or p.state != "frei" or not Towns.is_public(str(p.owner)) or p.zone != "wohnen":
		return {"ok": false, "msg": "Grundstück %s ist nicht als Wohngrundstück zu kaufen." % id}
	var r: Array = p.rect
	if int(r[2]) < 2 or int(r[3]) < 2:
		return {"ok": false, "msg": "%s ist zu schmal für ein Haus (mindestens 2x2 Felder)." % id}
	var c := Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) / 2)
	if _dist(tile_of(b), c) > 6:
		return {"ok": false, "msg": "Schau es dir erst an: geh näher heran (Feld %d,%d)." % [c.x, c.y]}
	var price := float(p.price)
	if float(b.get("geld", 0.0)) < price:
		return {"ok": false, "msg": "Zu teuer: %s kostet %s, du hast %s. Arbeite für die Firmen (jobangebote)." % [id, Catalog.money(price), Catalog.money(float(b.get("geld", 0.0)))]}
	var town: int = sim.towns.of_parcel(id) if sim.towns.is_region() else 0
	sim.economy.transfer("Y0", Towns.account_of(town), price)
	b.geld = float(b.geld) - price
	p.owner = "Y0"
	p.state = "privat_gehalten"
	p["bewohner"] = b.name
	sim.parcels.touch(id)
	b.grundstueck = id
	_event(b, "kauft Grundstück %s für %s" % [id, Catalog.money(price)])
	sim.log_event("%s kauft das Grundstück %s für %s." % [b.name, id, Catalog.money(price)], "good")
	return {"ok": true, "msg": "Grundstück %s gehört jetzt dir (%s bezahlt, %s übrig). Mit OrderHouse lässt du ein Haus bauen (%s)." % [id,
		Catalog.money(price), Catalog.money(float(b.geld)), Catalog.money(HOUSE_PRICE)]}


func _order_house(b: Dictionary, data: Dictionary) -> Dictionary:
	if str(b.get("grundstueck", "")) == "":
		return {"ok": false, "msg": "Erst ein Grundstück kaufen (BuyPlot)."}
	if houses.has(b.name):
		return {"ok": false, "msg": "Dein Haus ist schon beauftragt (%s)." % houses[b.name].status}
	if float(b.get("geld", 0.0)) < HOUSE_PRICE:
		return {"ok": false, "msg": "Ein Haus kostet %s, du hast %s." % [Catalog.money(HOUSE_PRICE), Catalog.money(float(b.get("geld", 0.0)))]}
	var p: Dictionary = sim.parcels.parcel(str(b.grundstueck))
	var r: Array = p.rect
	var origin := Vector2i((int(r[0]) + (int(r[2]) - 2) / 2) * PER_TILE, (int(r[1]) + (int(r[3]) - 2) / 2) * PER_TILE)
	var wall := str(data.get("wand", "ziegel"))
	if wall not in ["ziegel", "holz", "stein", "beton"]:
		wall = "ziegel"
	sim.economy.transfer("Y0", "K0", HOUSE_PRICE)
	b.geld = float(b.geld) - HOUSE_PRICE
	var builder := "Baufirma"
	for t in sim.crews.crews.values():
		builder = str(t.name).split(" Trupp")[0]
		break
	houses[b.name] = {"plot": p.id, "origin": [origin.x, origin.y], "blocks": house_plan(origin, wall), "placed": 0, "status": "im_bau",
		"builder": builder, "acc": 0.0, "wand": wall}
	_event(b, "beauftragt %s mit dem Bau seines Hauses (%s)" % [builder, Catalog.money(HOUSE_PRICE)])
	sim.log_event("%s beauftragt %s mit einem kleinen Haus auf %s." % [b.name, builder, p.id], "info")
	return {"ok": true, "msg": "%s baut jetzt dein Haus auf %s (Wände aus %s). Schau zu!" % [builder, p.id, wall]}


## Bauplan 8 x 8 Bloecke: Holzboden, Waende mit Fenstern und Tuer (Sueden), Flachdach, Einrichtung mit Ladestation.
static func house_plan(o: Vector2i, wall: String) -> Array:
	var out: Array = []
	var S := HOUSE_SIDE
	for y in S:
		for x in S:
			out.append([o.x + x, o.y + y, 0, "teppich" if x in [3, 4] and y in [3, 4] else "boden"])
	for z in range(1, HOUSE_WALL + 1):
		for y in S:
			for x in S:
				var edge := x == 0 or y == 0 or x == S - 1 or y == S - 1
				if not edge:
					continue
				if y == S - 1 and x in [3, 4] and z <= 2:   # Tuer nach Sueden
					continue
				var window := z in [2, 3] and ((y in [0, S - 1] and x in [1, 2, 5, 6]) or (x in [0, S - 1] and y in [2, 5]))
				out.append([o.x + x, o.y + y, z, "glas" if window else wall])
	var furn := [[1, 1, 1, "bett"], [2, 1, 1, "bett"], [1, 1, 2, "decke"], [2, 1, 2, "decke"], [6, 1, 1, "pflanze"], [6, 1, 2, "pflanze"],
		[5, 5, 1, "tisch"], [5, 5, 2, "lampe"], [6, 3, 1, "regal"], [6, 3, 2, "buch"], [6, 3, 3, "regal"], [1, 5, 1, "ladestation"], [1, 5, 2, "ladestation"]]
	for f in furn:
		out.append([o.x + int(f[0]), o.y + int(f[1]), int(f[2]), str(f[3])])
	for y in S:
		for x in S:
			out.append([o.x + x, o.y + y, HOUSE_WALL + 1, "dach"])
	return out


func _houses_tick(dt: float) -> void:
	for name in houses:
		var h: Dictionary = houses[name]
		if h.status != "im_bau":
			continue
		h.acc = float(h.acc) + dt
		while float(h.acc) >= HOUSE_BUILD_S and int(h.placed) < h.blocks.size():
			h.acc = float(h.acc) - HOUSE_BUILD_S
			h.placed = int(h.placed) + 1
		if int(h.placed) >= h.blocks.size():
			h.status = "fertig"
			var p: Dictionary = sim.parcels.parcel(str(h.plot))
			p.state = "bebaut"
			sim.parcels.touch(str(h.plot))
			if beings.has(name):
				_event(beings[name], "Das Haus ist fertig! %s übergibt die Schlüssel." % h.builder)
			sim.log_event("Das Haus von %s ist fertig – %s zieht ein." % [name, name], "good")
		changed.emit()


func home_rect(name: String) -> Rect2i:
	var h: Dictionary = houses.get(name, {})
	if h.is_empty():
		return Rect2i()
	return Rect2i(floori(float(h.origin[0]) / PER_TILE), floori(float(h.origin[1]) / PER_TILE), HOUSE_SIDE / PER_TILE, HOUSE_SIDE / PER_TILE)


func is_home(b: Dictionary) -> bool:
	var h: Dictionary = houses.get(b.name, {})
	return not h.is_empty() and h.status == "fertig" and home_rect(b.name).has_point(tile_of(b))


func _rest(b: Dictionary) -> Dictionary:
	if not is_home(b):
		return {"ok": false, "msg": "Ausruhen und Aufladen geht nur zu Hause (dein Haus muss fertig sein, dann hineingehen)."}
	b.rest_left = REST_SECONDS
	b.say = "Zzz … lade auf"
	b.say_left = REST_SECONDS
	_event(b, "ruht sich zu Hause in der Ladestation aus")
	return {"ok": true, "msg": "Du ruhst dich %d Sekunden in deiner Ladestation aus." % int(REST_SECONDS)}


func _home_obs(b: Dictionary) -> Dictionary:
	var h: Dictionary = houses.get(b.name, {})
	var o := {"geld": float(b.get("geld", 0.0)), "erledigte_auftraege": int(b.get("done_jobs", 0)),
		"grundstueck": str(b.get("grundstueck", "")), "hauspreis": HOUSE_PRICE,
		"gruenden": "FoundCompany ab %s Ersparnissen (Kapitalgeber legt %s dazu)" % [Catalog.money(FOUND_MIN_OWN), Catalog.money(FOUND_INVESTOR)] if int(b.get("firma", -1)) < 0 else "Firma %d" % int(b.firma)}
	if not h.is_empty():
		var r := home_rect(b.name)
		o["haus"] = {"status": h.status, "fortschritt": "%d %%" % int(100.0 * float(h.placed) / float(h.blocks.size())),
			"baufirma": h.builder, "felder": [r.position.x, r.position.y, r.size.x, r.size.y],
			"eingang_feld": [r.position.x + 1, r.end.y], "du_bist_zuhause": is_home(b)}
	elif str(b.get("grundstueck", "")) == "":
		o["grundstuecke_zu_kaufen"] = _plot_obs(b)
	return o


# ------------------------------------------------------------------ Eigene Firma (Lumo-Unternehmer, 15.11.2026)
## Ein Wesen mit genug Erspartem gruendet ein Transportunternehmen: eigene Ersparnisse plus Einlage des Kapitalgeberpools.
## Das Wesen trifft die Geschaeftsentscheidungen selbst (Handlung Firma mit einer Aktion aus FIRM_ACTIONS); den Tagesbetrieb
## (Auftraege zuweisen, Fahrer einsetzen, tanken, reparieren) erledigt die Disposition der Regel-KI (Controller "eko").
const FOUND_MIN_OWN := 1500.0       # eigene Ersparnisse mindestens
const FOUND_INVESTOR := 20000.0     # Einlage des Kapitalgeberpools I0
const FIRM_ACTIONS := ["accept_contract", "assign_transport", "collect_contracts", "buy_vehicle", "sell_vehicle", "recruit_worker",
	"dismiss_worker", "assign_worker_task", "rent_depot", "take_loan", "repay_loan", "install_internet", "send_message"]


func firm_being(cid: int) -> String:
	for b in beings.values():
		if int(b.get("firma", -1)) == cid:
			return str(b.name)
	return ""


func _found_company(b: Dictionary, data: Dictionary) -> Dictionary:
	if int(b.get("firma", -1)) >= 0:
		return {"ok": false, "msg": "Du hast schon eine Firma (%s)." % sim.company(int(b.firma)).company_name}
	var own := float(b.get("geld", 0.0))
	if own < FOUND_MIN_OWN:
		return {"ok": false, "msg": "Zum Gründen brauchst du mindestens %s eigene Ersparnisse (du hast %s). Der Kapitalgeber legt %s dazu." % [
			Catalog.money(FOUND_MIN_OWN), Catalog.money(own), Catalog.money(FOUND_INVESTOR)]}
	if float(sim.economy.accounts.get("I0", 0.0)) < FOUND_INVESTOR:
		return {"ok": false, "msg": "Der Kapitalgeberpool hat gerade keine Mittel."}
	var keep := minf(own, float(data.get("behalten", 0.0)))   # Rest bleibt privat (z. B. fuer das Haus)
	var invest := own - keep
	var town: int = sim.city.town_of(tile_of(b))
	var name := str(data.get("name", "")).strip_edges().left(32)
	if name == "":
		name = "%s Kurierdienst" % b.name
	var c = sim.founders.create_for_being(town, str(b.name), name, invest, FOUND_INVESTOR)
	b.geld = keep
	b.firma = c.id
	sim.founders.company_founded.emit(c.id)
	_event(b, "gründet %s (Einlage %s, Kapitalgeber %s)" % [name, Catalog.money(invest), Catalog.money(FOUND_INVESTOR)])
	sim.log_event("%s gründet das Unternehmen %s in %s – eigene Ersparnisse %s, Kapitalgeber %s." % [b.name, name, sim.towns.name_of(town),
		Catalog.money(invest), Catalog.money(FOUND_INVESTOR)], "good", c.id)
	return {"ok": true, "msg": "%s ist gegründet (Firma %d, Kasse %s). Sitz vorerst im Rathaus, zwei Allrounder sind eingestellt. Mit Firma {aktion} führst du sie; Tagesbetrieb läuft automatisch." % [
		name, c.id, Catalog.money(c.ledger.cash)]}


func _firm_action(b: Dictionary, data: Dictionary) -> Dictionary:
	var cid := int(b.get("firma", -1))
	if cid < 0:
		return {"ok": false, "msg": "Du hast noch keine Firma (FoundCompany)."}
	var a = data.get("aktion", data.get("action"))
	if a is String:
		a = JSON.parse_string(a)
	if not (a is Dictionary) or str(a.get("action", "")) not in FIRM_ACTIONS:
		return {"ok": false, "msg": "Firma braucht aktion: {\"action\": eine von %s, ...Parameter}." % ", ".join(FIRM_ACTIONS)}
	var r: Dictionary = sim.executor.execute(cid, a, "", "api")
	_event(b, "Firma: %s → %s" % [a.action, str(r.get("msg", "")).left(80)])
	return {"ok": bool(r.get("ok", false)), "msg": str(r.get("msg", ""))}


## Kompakte Firmenlage fuer das Wesen (statt der grossen Unternehmer-Beobachtung): Kasse, Flotte, Auftraege, machbarer Markt,
## naechste Fahrzeugangebote, Bewerber, letzte Ergebnisse.
func firm_obs(b: Dictionary) -> Dictionary:
	var cid := int(b.get("firma", -1))
	if cid < 0 or sim.company(cid) == null:
		return {}
	var o := ObservationBuilder.build(sim, cid, [], 0.0, 10.0)
	var me: Dictionary = o.ich
	var models: Dictionary = o.fahrzeugmodelle
	return {"firma": sim.company(cid).company_name, "bargeld": int(me.bargeld), "gewinn": int(me.gewinn), "reputation": me.reputation,
		"laufende_auftraege": me.buero.laufende_auftraege, "stellplaetze": me.stellplaetze,
		"fahrzeuge": o.fahrzeuge.map(func(v): return {"id": v.id, "modell": v.modell, "kapazitaet": models[v.modell].kapazitaet, "status": v.status,
			"fahrer": v.fahrer != null, "zustand": v.zustand}),
		"meine_auftraege": o.meine_auftraege.map(func(k): return {"id": k.id, "status": k.status, "ware": k.ware, "menge": k.menge,
			"verguetung": k.verguetung, "frist_in_min": k.frist_in_min, "fahrzeug": k.fahrzeug}),
		"markt": o.markt.filter(func(k): return bool(k.get("machbar", true)) and float(k.min_reputation) <= float(me.reputation)).slice(0, 5).map(
			func(k): return {"id": k.id, "ware": k.ware, "menge": k.menge, "strecke": k.strecke, "anfahrt": k.anfahrt_vom_depot,
				"verguetung": k.verguetung, "frist_in_min": k.frist_in_min, "kuehlung": k.kuehlung, "schwer": k.schwer}),
		"fahrzeugangebote": o.ressourcen.fahrzeugangebote.slice(0, 4).map(func(f): return {"id": f.id, "modell": f.modell, "preis": f.preis,
			"zustand": f.zustand, "haendler": f.haendler}),
		"bewerber": o.ressourcen.arbeitskraefte.slice(0, 3).map(func(w): return {"id": w.id, "name": w.name, "lohn_h": w.lohn_h, "anwerbung": w.anwerbung,
			"fahren": int(w.faehigkeiten.get("fahren", 0))}),
		"personal": o.personal.size(), "letzte_ergebnisse": o.get("ergebnisse_deiner_aktionen", []).slice(-4),
		"aktionen": "Firma {aktion: {action: accept_contract, contract_id, vehicle_id?} | buy_vehicle {offer_id} | recruit_worker {worker_id} | " +
			"assign_worker_task {kind: fahren, worker_id, vehicle_id} | collect_contracts {} | rent_depot {depot_id} | take_loan {amount} | sell_vehicle {vehicle_id} | send_message {to, text}}"}


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
		bs.append({"name": b.name, "art": b.art, "x": b.mover.pos.x, "y": b.mover.pos.y, "held": b.held, "events": b.events,
			"geld": float(b.get("geld", 0.0)), "job": str(b.get("job", "")), "grundstueck": str(b.get("grundstueck", "")),
			"done_jobs": int(b.get("done_jobs", 0)), "firma": int(b.get("firma", -1))})
	return {"blocks": bl, "beings": bs, "chat": chat, "jobs": jobs, "next_job": _next_job, "houses": houses}


func from_dict(d: Dictionary) -> void:
	blocks.clear()
	beings.clear()
	for e in d.get("blocks", []):
		blocks[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = str(e[3])
	for e in d.get("beings", []):
		join(str(e.name), str(e.get("art", "mensch")))
		var b: Dictionary = beings[str(e.name)]
		b.mover.pos = Vector2(float(e.x), float(e.y))
		b.held = e.get("held", [])
		b.events = e.get("events", [])
		for k in ["geld", "job", "grundstueck", "done_jobs", "firma"]:
			if e.has(k):
				b[k] = e[k]
	chat = d.get("chat", [])
	jobs = d.get("jobs", {})
	_next_job = int(d.get("next_job", 1))
	houses = d.get("houses", {})


## Vorfuehrung (--eko-demo-haus): Wesen mit fertigem Haus auf dem naechsten Wohngrundstueck, steht drinnen.
## Das Geld kommt aus dem Ausland (X0 -> Y0), damit die Geldbilanz stimmt.
func demo_house(name: String) -> bool:
	if not beings.has(name):
		join(name, "roboter")
	var b: Dictionary = beings[name]
	var plots := _plot_obs(b)
	if plots.is_empty():
		return false
	var pl: Dictionary = plots[0]
	var need := float(pl.preis) + HOUSE_PRICE + 500.0
	sim.economy.transfer("X0", "Y0", need)
	b.geld = float(b.get("geld", 0.0)) + need
	b.mover.pos = sim.city.tile_center(Vector2i(int(pl.feld[0]), int(pl.feld[1])))
	if not _buy_plot(b, str(pl.id)).ok or not _order_house(b, {"wand": "holz"}).ok:
		return false
	houses[name].placed = houses[name].blocks.size()
	_houses_tick(0.0)
	b.mover.pos = sim.city.tile_center(home_rect(name).position + Vector2i(1, 0))
	var here: Array[Vector2i] = [b.mover.tile()]
	b.mover.set_path(here)
	changed.emit()
	return true
