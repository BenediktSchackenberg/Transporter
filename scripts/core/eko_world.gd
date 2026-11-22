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
const TAXI_SPEED := 5.0             # Fahrdienst: so viel schneller als zu Fuss (15.11.: Wesen liefen 600 Felder, 3,5 Minuten)
const TAXI_EUR_PER_FIELD := 1.0
const TAXI_MIN := 5.0
const SAY_SECONDS := 8.0
const MAX_BLOCKS := 20000
const MAX_EVENTS := 30
const MAX_CHAT := 100
const VIEW_RADIUS := 10             # Kartenausschnitt in Feldern um das Wesen
const SIDES := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const TALK_REACH := 3               # Felder: so nah muss man fuer ein Gespraech sein
const HEAR_RADIUS := 12             # Felder: Gesagtes in diesem Umkreis wird gehoert
const TALK_REPEAT_MS := 90000       # so lange sperrt eine unbeantwortete Ansprache dieselbe Person (Echtzeit)
const ARTEN := ["mensch", "roboter"]
## Selbstbau (15.11.2026): Material und Einrichtung kauft das Wesen am Bauhof (Preis je Block, Geld an T0 "Bauhof");
## fuer einen angenommenen Mauer-Auftrag stellt die Firma das Material. Einrichtung wird wie Bloecke gesetzt.
const PRICES := {"stein": 3.0, "ziegel": 4.0, "holz": 4.0, "beton": 3.0, "glas": 6.0, "stahl": 8.0, "dach": 5.0, "boden": 3.0,
	"teppich": 15.0, "bett": 60.0, "decke": 10.0, "tisch": 30.0, "lampe": 20.0, "pflanze": 10.0, "regal": 25.0, "buch": 5.0, "ladestation": 80.0}
## Material der Wesen und Artikel des Bauhofs: eine Bauhof-Einheit ergibt so viele Bloecke (Preis je Block = Einheitspreis / Anzahl).
const TRADER_ITEM := {"holz": "holz", "ziegel": "ziegel", "beton": "beton", "glas": "glas", "stahl": "stahl"}
const BLOCKS_PER_UNIT := {"holz": 4, "ziegel": 4, "beton": 2, "glas": 2, "stahl": 2}
const MOVE_IN_BLOCKS := 30          # Bausteine (ohne Einrichtung) auf dem eigenen Grundstueck
const MOVE_IN_HEIGHT := 4           # Schichten (hoechster Block z >= 3)
const COLORS := [Color("#e8c04a"), Color("#5fb3d9"), Color("#d96b5f"), Color("#7fcf6a"), Color("#b98ad9")]

var sim
var beings := {}                    # Name -> {name, art, mover, held: [Material], say, say_left, events: [], color}
var blocks := {}                    # Vector3i (Blockraster) -> Material
var chat: Array = []                # [{t (Echtzeit-ISO), von, an, text, feld}]
var last_active := ""               # Wesen mit der juengsten Handlung (Kamera folgt ihm)
## Ersparnisse ueber Neustarts der Welt hinweg (nur im Spiel mit --eko): Datei mit {Name: Geld}; beim ersten Beitritt nach einem
## Neustart wird das Geld aus dem Ausland (X0 -> Y0) zurueckgebucht, damit die Geldbilanz stimmt. In Tests leer (aus).
var persist_path := ""
var _persist_timer := 0.0
var _restored := {}
var relief := PackedFloat32Array()   # Gelaende (Terrain.relief), fuer Haenge, Hochebenen und Darstellung
var _terrain_ready := false


var conflict := EkoConflict.new()    # Stadtstrategie, Truppen, Belagerungen (Benedikt 19.11.2026)
var arms := EkoArms.new()           # Waffen, Schutz, Gefahren (Benedikt 15.11.2026)
var estates := EkoEstates.new()     # Stammsitz je KI-Spieler (Benedikt 15.11.2026)
var homes := EkoHomes.new()         # Neubeginn: Wohnhaeuser der KI-Firmen (Benedikt 17.11.2026)
var settle := EkoSettle.new()       # Wildnis: Standortwahl und Gruendung der Siedlung (Benedikt 17.11.2026)
var _homes_min := -1.0
var auto_estates := false           # Spiel: neue Wesen (keine Buergermeister) bekommen beim Beitritt einen Stammsitz
const START_CAPITAL := 150000.0     # Benedikt 15.11.: jede KI startet mit 150.000 EUR Privatgeld (Einlage von aussen X0 -> Y0)
const GRUNDZIEL := "Baue deinen Stammsitz zu deiner Basis aus – Form, Größe, Stil und Schutz entscheidest du selbst (Bauwerk, Bauplan)."
const GRUNDZIEL_FIRMA := "Erwirtschafte langfristig moeglichst hohen echten Nettogewinn bei ausreichender Liquiditaet. Erweitere rentable Betriebe, Lieferketten und Marktanteile, pruefe Kosten und schuetzte deine Leute und Anlagen. Entscheide selbst ueber Handel, Frieden oder Krieg; eine Offensive braucht einen wirtschaftlichen und strategischen Grund."
# Benedikt 18.11.: "Ziel pro KI ist, dass die Stadt waechst, mehr Einwohner kommen, die Wirtschaft in Schwung kommt"
const GRUNDZIEL_WILDNIS := "Entwickle aus deiner selbst gewählten Siedlung eine bewohnte, wirtschaftende Stadt und ein profitables Unternehmen. Strebe langfristig hohen echten Nettogewinn, Liquiditaet und Marktanteile an; erweitere nur tragfaehige Betriebe und schuetze Stadt, Menschen und Infrastruktur. Entscheide frei ueber Standort, Baustil, Handel, Frieden oder Krieg. Pruefe nach jedem Bau, ob Wohnungen bewohnbar sind, Menschen zuziehen und die Investition wirkt."
const GRUNDZIEL_AMT := "Entwickle deine Stadt dauerhaft nach eigener Idee. Miss den Erfolg an bewohnbaren Wohnungen, zugezogenen Menschen, aktiven Betrieben und Lebensqualität bei soliden Finanzen. Waehle Strassen, Stromtrassen, Wasserleitungen, Gebaeude und Stadtbild selbst; pruefe, ob die Anschluesse die Haeuser erreichen. Schuetze Bewohner und kritische Anlagen bei Angriffen und Katastrophen. Dein Zuhause ist dein Rathaus."
const TOWN_START_CAPITAL := 5000000.0   # Benedikt 15.11.: jede Stadt startet mit 5.000.000 EUR (Einlage von aussen X0 -> Stadtkasse)
var towns_funded := {}              # "k" -> true
var _no_estate := false             # beim Laden und fuer Buergermeister keinen Stammsitz vergeben


## Geschuetzte Felder (Benedikt 16.11.2026: "Gebaeude nicht auf Strassen und Eisenbahnen, Mauern darf man nicht mit Auto oder Zug
## durchfahren, die Autobahn muss drumherum"): Stammsitze mit einem Feld Rand und jedes Feld mit Bloecken der Wesen. Strassen-,
## Autobahn-, Zufahrts- und Bahnplanung behandeln sie wie Gebaeude und planen darum herum.
var _block_tiles := {}
var _block_tiles_n := -1

func protected(q: Vector2i) -> bool:
	return estates.covers(q) or block_tile(q)


func block_tile(q: Vector2i) -> bool:
	if blocks.size() != _block_tiles_n:
		_block_tiles = {}
		for p in blocks:
			_block_tiles[Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))] = true
		_block_tiles_n = blocks.size()
	return _block_tiles.has(q)


## Spielstaende vor dem 16.11.: Bloecke, die Wesen auf Gleise gesetzt hatten (die Bahn fuhr hindurch), raeumt die Bahn beim Laden ab.
func clear_rails() -> int:
	if sim.rail == null:
		return 0
	var gone: Array = blocks.keys().filter(func(p): return sim.rail.is_rail(Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))))
	for p in gone:
		blocks.erase(p)
	if not gone.is_empty():
		_block_tiles_n = -1
		sim.log_event("Bahn räumt %d Blöcke von den Gleisen – auf Gleisen darf nicht gebaut werden." % gone.size(), "warn")
		changed.emit()
	return gone.size()


func setup(simulation) -> void:
	sim = simulation
	arms.setup(self)
	conflict.setup(self)
	estates.setup(self)
	homes.setup(self)
	settle.setup(self)
	changed.connect(func(): _block_tiles_n = -1)
	sim.visit_completed.connect(_on_visit_completed)
	sim.day_changed.connect(_economy_watch)

## Rueckfallebene fuer lange Partien: der KI-Unternehmer erhaelt einen lokalen Betrieb,
## wenn trotz Einwohnern und Arbeitslosen noch keiner entstanden ist. Modellentscheidungen
## haben bis Tag 30 Vorrang; die Regel nutzt nur gepruefte, bezahlbare Standorte.
func _economy_watch(day: int) -> void:
	if day < 30 or not sim.wildnis or not auto_estates:
		return
	for c in sim.companies:
		var cid: int = c.id
		var name: String = firm_being(cid)
		if name == "" or not c.is_active():
			continue
		var town: int = c.home_town
		if not sim.town_ready(town):
			continue
		var owned: Array = sim.biz.of(cid).filter(func(b): return str(b.branch) != "transport")
		if owned.is_empty() and sim.citizens.population_of(town) >= 20 and sim.citizens.unemployed_of(town) >= 8:
			for branch in ["baeckerei", "moebelwerk", "muehle", "brauerei"]:
				var spec: Dictionary = Businesses.branches().get(branch, {})
				if c.ledger.cash < float(spec.get("ausstattung", 0.0)) + 20000.0 or not bool(sim.retail.counter_viable(branch).get("ok", false)):
					continue
				var sites: Array = sim.prod.site_hints(branch, 1, town)
				if sites.is_empty():
					continue
				var site := str(sites[0].grundstueck)
				var result: Dictionary = sim.biz.found(cid, branch, "KI-Wirtschaftsleitung: Arbeitsplätze für %s" % sim.towns.name_of(town), {"stadt": town, "grundstueck": site})
				if bool(result.get("ok", false)):
					_event(beings[name], "Wirtschaftsleitung gründet %s auf %s: %s" % [branch, site, str(result.msg).left(120)])
					sim.log_event("KI-Wirtschaftsleitung %s gründet %s auf %s für %s (%d Arbeitslose)." % [c.company_name, spec.label, site, sim.towns.name_of(town), sim.citizens.unemployed_of(town)], "ai", cid)
					break
		# Ein fertiges Werk ohne Personal laeuft nicht. Die Wirtschaftsleitung besetzt es,
		# wenn der Agent waehrend der gesamten Bauzeit niemanden zugeordnet hat.
		for b in sim.biz.of(cid):
			if str(b.branch) == "transport" or str(b.status) not in Businesses.RUNNING:
				continue
			if sim.biz.staff_of(str(b.id)).size() >= int(Businesses.branches().get(str(b.branch), {}).get("personal_min", 1)):
				continue
			var spare: Array = sim.personnel.employed(cid).filter(func(w): return str(w.role) != "owner" and str(w.business) == "")
			var worker = spare[0] if not spare.is_empty() else null
			if worker == null and c.ledger.cash >= 20000.0:
				var applicants: Array = sim.personnel.available().filter(func(w): return str(w.role) == "worker" and float(w.hire_fee) <= c.ledger.cash - 20000.0)
				if not applicants.is_empty():
					worker = applicants[0]
					sim.personnel.hire(cid, worker)
			if worker != null:
				var assigned: Dictionary = sim.biz.assign(cid, str(worker.id), str(b.id))
				if bool(assigned.get("ok", false)):
					_event(beings[name], "Wirtschaftsleitung besetzt %s mit %s." % [b.name, worker.name])
					sim.log_event("KI-Wirtschaftsleitung %s besetzt %s mit %s." % [c.company_name, b.name, worker.name], "ai", cid)


## Ergebnis einer Firmen-Handlung, die erst vor Ort ausgefuehrt wurde, an das Wesen der Firma melden (vorher sah es nur "Figur geht zu ...").
func _on_visit_completed(cid: int, action: String, r: Dictionary) -> void:
	for b in beings.values():
		if active_firm(b) == cid:
			_event(b, "Firma vor Ort erledigt – %s: %s %s" % [action, "OK" if bool(r.get("ok", false)) else "ABGELEHNT", str(r.get("msg", "")).left(160)])
			var dec: Dictionary = b.get("entscheidung", {})
			if str(dec.get("aktion", "")) == "Firma" and str(dec.get("status", "")) == "laeuft":
				dec.status = "abgeschlossen" if bool(r.get("ok", false)) else "gescheitert"
				dec.ergebnis = str(r.get("msg", "")).left(120)
				dec.ms = Time.get_ticks_msec()


## Eigenes Grundstueck fuer Fussgaenger oeffnen (Parzellenfelder zaehlen sonst als Gebaeudeflaeche): sonst kommt das Wesen nie ins
## eigene Haus und gilt nie als zu Hause (Viktor, 15.11.: "MoveTo ins eigene Haus: Ziel nicht begehbar").
## Nachvergabe: KI-Spieler (keine Buergermeister) ohne Stammsitz bekommen einen (z. B. war beim Start kein Platz frei).
func ensure_estates() -> void:
	for b in beings.values():
		if int(b.get("amt", -1)) < 0 and not estates.estates.has(b.name) and not sim.wildnis:   # Wildnis: Stammsitz erst mit der Gruendung
			estates.assign(b.name)
		grant_start_capital(b)
	for k in sim.towns.count() if sim.towns.is_region() else 0:   # Startkapital der Staedte (einmal je Stadt, auch nachtraeglich)
		if not towns_funded.has(str(k)):
			towns_funded[str(k)] = true
			sim.economy.transfer("X0", Towns.account_of(k), TOWN_START_CAPITAL)
			sim.log_event("%s erhält %s Startkapital." % [sim.towns.name_of(k), Catalog.money(TOWN_START_CAPITAL)], "good")


## Rathaus des Buergermeister-Wesens (sein Zuhause); {} ohne Amt.
func town_hall_of(b: Dictionary) -> Dictionary:
	var k := int(b.get("amt", -1))
	if k < 0 or k >= sim.city.towns.size():
		return {}
	return sim.city.building(int(sim.city.towns[k].get("town_hall", -1)))


## Startkapital einmal je Wesen (auch nachtraeglich fuer laufende Partien); Geld kommt von aussen, die Bilanz bleibt erhalten.
func grant_start_capital(b: Dictionary) -> void:
	if bool(b.get("startkapital", false)):
		return
	b["startkapital"] = true
	if sim.neubeginn:
		return   # Neubeginn: das Startkapital (1 Mio.) liegt in der Firma; privat nur per entnahme
	sim.economy.transfer("X0", "Y0", START_CAPITAL)
	b.geld = float(b.get("geld", 0.0)) + START_CAPITAL
	_event(b, "erhält %s Startkapital" % Catalog.money(START_CAPITAL))


func open_plot(id: String) -> void:
	if id == "":
		return
	var r := plot_rect(id)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if sim.city.inside(c) and sim.city.g(c) != CityData.G.WATER:
				sim.nav.walk.set_point_solid(c, false)
	_ensure_path(r)


## Flutfuellung im Fussweg-Raster ab einem Feld (1 = erreichbar).
func _walk_component(from: Vector2i) -> PackedByteArray:
	var n0: int = sim.city.size
	var seen := PackedByteArray()
	seen.resize(n0 * n0)
	var stack: Array[Vector2i] = [from]
	seen[from.y * n0 + from.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= n0 or n.y >= n0 or seen[n.y * n0 + n.x] == 1 or sim.nav.walk.is_point_solid(n):
				continue
			if d.x != 0 and d.y != 0 and (sim.nav.walk.is_point_solid(Vector2i(c.x + d.x, c.y)) or sim.nav.walk.is_point_solid(Vector2i(c.x, c.y + d.y))):
				continue   # diagonal nur ohne Hindernis (wie das Fussweg-Raster)
			seen[n.y * n0 + n.x] = 1
			stack.append(n)
	return seen


## Trampelpfad, falls das Grundstueck eine Insel ist (15.11.: Viktors Haus lag im Wald, Baeume und Hoefe sperrten den Fussweg):
## Breitensuche vom Grundstueck ueber Land (kein Wasser, keine Gebaeude) bis zum naechsten begehbaren Feld, das ans Fusswegnetz
## einer Stadt angeschlossen ist; die Felder dieses Weges werden begehbar.
func _ensure_path(r: Rect2i) -> void:
	var ctr := r.get_center()
	var src: Array = sources().map(func(s0): return Vector2i(int(s0.feld[0]), int(s0.feld[1])))
	if src.is_empty() or src.any(func(f): return sim.nav.walk_reachable(ctr, f)):
		return
	src.sort_custom(func(a, b): return _dist(ctr, a) < _dist(ctr, b))
	var net := _walk_component(src[0])   # alle Felder, die zu Fuss mit dem naechsten Bauhof verbunden sind
	var n0: int = sim.city.size
	var prev := {ctr: ctr}
	var queue: Array = [ctr]
	var goal := Vector2i(-1, -1)
	while not queue.is_empty() and prev.size() < 40000:
		var c: Vector2i = queue.pop_front()
		if net[c.y * n0 + c.x] == 1:
			goal = c
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if prev.has(n) or not sim.city.inside(n) or sim.city.g(n) == CityData.G.WATER or int(sim.city.building_at[sim.city.idx(n)]) >= 0:
				continue
			prev[n] = c
			queue.append(n)
	if goal.x < 0:
		return
	var c2 := goal
	while c2 != ctr:
		sim.nav.walk.set_point_solid(c2, false)
		c2 = prev[c2]
	sim.nav.walk.set_point_solid(ctr, false)

func ensure_terrain() -> void:
	if _terrain_ready or sim == null or sim.city == null:
		return
	_terrain_ready = true
	for b0 in beings.values():
		open_plot(str(b0.get("grundstueck", "")))
	relief = Terrain.relief(sim.city)
	if relief.is_empty():
		return
	for i in relief.size():
		if relief[i] <= 0.0:
			continue
		var c := Vector2i(i % sim.city.size, i / sim.city.size)
		if Terrain.climbable(sim.city, relief, c) and sim.city.building_at[i] < 0:
			sim.nav.walk.set_point_solid(c, false)
			sim.nav.walk.set_point_weight_scale(c, 1.0 + relief[i] * 0.4)


func height_at(t: Vector2i) -> float:
	return Terrain.at(sim.city, relief, t)


# ------------------------------------------------------------------ Wesen
func join(name: String, art: String = "mensch") -> Dictionary:
	name = name.strip_edges().left(24)
	art = art if art in ARTEN else "mensch"
	if name == "" or not RegEx.create_from_string("^[A-Za-z0-9_ÄÖÜäöüß -]+$").search(name):
		return {"ok": false, "msg": "Name fehlt oder enthaelt ungueltige Zeichen."}
	ensure_terrain()
	if not beings.has(name):
		var m := Mover.new()
		m.lane = 0.0
		m.speed = WALK_SPEED
		m.pos = sim.city.tile_center(_spawn_tile())
		beings[name] = {"name": name, "art": art, "mover": m, "held": [], "say": "", "say_left": 0.0, "events": [], "geld": 0.0,
			"job": "", "grundstueck": "", "done_jobs": 0, "rest_left": 0.0, "firma": -1, "akku": 100.0, "nass": 0.0, "kalt": 0.0,
			"amt": -1, "seele": "", "gesundheit": 100.0, "waffen": [],
			"color": COLORS[beings.size() % COLORS.size()]}
		_event(beings[name], "ist in der Welt erwacht")
		if auto_estates and not _no_estate and not sim.wildnis and estates.assign(name):   # erwacht auf dem eigenen Stammsitz (Wildnis: erst mit der Gruendung)
			m.pos = sim.city.tile_center(estates.center_of(name))
			_event(beings[name], "erwacht auf seinem Stammsitz")
		if auto_estates and not _no_estate:
			grant_start_capital(beings[name])
		_restore_savings(beings[name])
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
var _estates_checked := false


func update(dt: float) -> void:
	if auto_estates and not _estates_checked:   # Nachvergabe im ersten Takt (dann ist der Spielstand sicher geladen)
		_estates_checked = true
		ensure_estates()
	for b in beings.values():
		var m: Mover = b.mover
		if not m.arrived():
			m.advance(dt, 1.0)
			if m.arrived():
				_event(b, "ist bei Feld %d,%d angekommen" % [m.tile().x, m.tile().y])
				b["faehrt"] = false
		if float(b.say_left) > 0.0:
			b.say_left = maxf(0.0, float(b.say_left) - dt)
		_feel_tick(b, dt)
		if float(b.get("rest_left", 0.0)) > 0.0:
			b.rest_left = maxf(0.0, float(b.rest_left) - dt)
	_jobs_tick(dt)
	_houses_tick(dt)
	arms.tick(dt)
	conflict.tick(dt)
	estates.tick(dt)
	if _homes_min >= 0.0 and sim.game_min > _homes_min:
		homes.tick(float(sim.game_min) - _homes_min)
	_homes_min = float(sim.game_min)
	_body_tick()
	for b in beings.values():   # laufende Ablaeufe fortsetzen, sobald das Wesen angekommen ist und nicht ruht
		if not (b.get("ablauf", []) as Array).is_empty() and (b.mover as Mover).arrived() and float(b.get("rest_left", 0.0)) <= 0.0:
			_run_plan(b)
	_salary_timer -= dt
	if _salary_timer <= 0.0:   # Amtsgehalt der Buergermeister-Wesen aus der Stadtkasse (sonst kein Privatgeld fuer ein Zuhause)
		_salary_timer = 60.0
		for b in beings.values():
			var k := int(b.get("amt", -1))
			if k >= 0:
				sim.economy.transfer(Towns.account_of(k), "Y0", MAYOR_SALARY)
				b.geld = float(b.get("geld", 0.0)) + MAYOR_SALARY
	if persist_path != "":
		_persist_timer -= dt
		if _persist_timer <= 0.0:
			_persist_timer = 15.0
			var d := {}   # vorhandene Eintraege behalten: Wesen, die noch nicht wieder beigetreten sind, verlieren sonst ihre Ersparnisse
			if FileAccess.file_exists(persist_path):
				var old = JSON.parse_string(FileAccess.get_file_as_string(persist_path))
				if old is Dictionary:
					d = old
			for b in beings.values():
				if _restored.has(b.name) or not d.has(b.name):   # erst nach der Rueckbuchung ueberschreiben
					d[b.name] = {"geld": float(b.get("geld", 0.0)), "done_jobs": int(b.get("done_jobs", 0))}
			var f := FileAccess.open(persist_path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(d))


func _restore_savings(b: Dictionary) -> void:
	if persist_path == "" or _restored.has(b.name) or sim.neubeginn:   # Neubeginn: alle starten gleich, ohne Erspartes aus alten Partien
		return
	_restored[b.name] = true
	if not FileAccess.file_exists(persist_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(persist_path))
	if not (d is Dictionary) or not d.has(b.name):
		return
	var geld := float(d[b.name].get("geld", 0.0))
	if geld > 0.0:
		sim.economy.transfer("X0", "Y0", geld)
		b.geld = float(b.get("geld", 0.0)) + geld
		b.done_jobs = int(d[b.name].get("done_jobs", 0))
		_event(b, "hat seine Ersparnisse von %s mitgebracht" % Catalog.money(geld))


# ------------------------------------------------------------------ Handlungen
const ACTIONS := ["MoveTo", "Stop", "Pickup", "Place", "Say", "Talk", "Inspect", "Attack", "Give", "Bauwerk", "Tor", "Bauplan", "Fahrt",
	"AcceptJob", "Deliver", "BuyPlot", "OrderHouse", "Rest", "FoundCompany", "Firma", "MoveIn", "Amt", "Ziel", "ZielStand", "Merke", "Ablauf", "Siedlung", "Bauen", "LKW", "Rammen"]
## Namen, unter denen Modelle eine Handlung aufrufen (Partie 16.11.: Buergermeisterin rief "mein_amt" statt "Amt" auf – so heisst ihre Lage).
const ACTION_ALIASES := {"mein_amt": "Amt", "office": "Amt", "amt_aktion": "Amt", "meine_firma": "Firma", "company": "Firma", "firm": "Firma",
	"bauen": "Bauen", "arbeiten": "Bauen", "build": "Bauen", "work": "Bauen", "lkw": "LKW", "truck": "LKW", "lastwagen": "LKW",
	"gruenden": "Siedlung", "gründen": "Siedlung", "siedlung_gruenden": "Siedlung", "found_town": "Siedlung", "settle": "Siedlung",
	"rammen": "Rammen", "ram": "Rammen", "ramm": "Rammen", "move": "MoveTo", "goto": "MoveTo", "gehe": "MoveTo", "sprich": "Talk", "sage": "Say", "anrufen": "Talk", "call": "Talk"}


## Handlungsname tolerant lesen: Gross-/Kleinschreibung egal, bekannte Ersatznamen; Unbekanntes bleibt unveraendert (Fehlermeldung).
static func canonical_type(type: String) -> String:
	var t := type.strip_edges()
	var low := t.to_lower()
	if ACTION_ALIASES.has(low):
		return ACTION_ALIASES[low]
	for a in ACTIONS:
		if a.to_lower() == low:
			return a
	return t


func input(name: String, type: String, data: Dictionary, from_plan := false) -> Dictionary:
	var b: Dictionary = beings.get(name, {})
	if b.is_empty():
		return {"ok": false, "msg": "Unbekanntes Wesen. Erst POST /join."}
	last_active = name
	b.last_act = Time.get_ticks_msec()
	var gap := float(sim.game_min) - float(b.get("last_game_min", -1.0))
	if b.has("last_game_min") and gap > 0.0 and gap < AgentController.HOLD_GAME_MIN:   # Takt des Wesens in Spielminuten (fuer Vormerkungen)
		b["takt_min"] = gap if not b.has("takt_min") else lerpf(float(b.takt_min), gap, 0.3)
	b["last_game_min"] = float(sim.game_min)
	if data.get("data") is Dictionary and not data.has("aktion"):   # {"data": {"data": {"aktion": ...}}} (Partie 16.11.)
		if data.get("type") is String and canonical_type(type) not in ACTIONS:   # 18.11.: {type: act, data: {data: {...}, type: "Rest"}}
			type = str(data.type)
		data = data.data
	type = canonical_type(type)
	if type not in ACTIONS:   # Partie 16.11.: 11x type "act" (Werkzeugname), echte Art in data.type oder aus data.aktion ableitbar
		if data.get("type") is String and canonical_type(str(data.type)) in ACTIONS:
			type = canonical_type(str(data.type))
		elif (data.has("aktion") or data.get("action") is String) and type.to_lower() in ["act", "aktion", "handlung", ""]:
			type = "Amt" if int(b.get("amt", -1)) >= 0 else "Firma"   # 18.11.: Viktor schickte {data: {action: hub_buy, ...}}
		elif type.to_lower() in ["act", "aktion", "handlung", ""]:   # Partie 18.11.: Greta 10x {type: act, data: {text}} – Art aus den Daten ableiten
			if data.has("text") or data.has("nachricht"):
				if data.has("an") and not data.has("to"):
					data["to"] = data.an
				if data.has("nachricht") and not data.has("text"):
					data["text"] = data.nachricht
				type = "Talk" if data.has("to") else "Say"
			elif data.has("fortschritt") or data.has("notiz"):
				type = "ZielStand"   # 18.11.: Greta meldete ihren Zielstand als act {fortschritt, notiz}
			elif data.has("baustelle"):
				type = "Bauen"
			elif data.has("ziel"):
				type = "LKW"
			elif data.has("tile"):
				type = "MoveTo"
			elif data.has("feld"):
				type = "Siedlung" if sim.wildnis and not settle.founded(sim.companies[active_firm(b)].home_town if active_firm(b) >= 0 else -1) else "MoveTo"
			elif data.keys().all(func(key): return str(key) == "warum") and ["schlaf", "ruh", "akku", "laden", "pause"].any(func(w): return str(data.get("warum", "")).to_lower().contains(w)):
				type = "Rest"   # 19.11.: Petra/Thomas {type: act, data: {warum: "schlafen gehen" / "Akku laden"}}
	if arms.is_out(b) and type not in ["Inspect"]:
		return {"ok": false, "status": "gescheitert", "msg": arms.out_msg(b)}
	if b.has("im_lkw") and type in ["MoveTo", "Pickup", "Place", "Bauwerk", "Bauen", "Attack", "Fahrt", "Siedlung", "LKW", "MoveIn", "Rammen"]:
		return {"ok": false, "msg": "Du sitzt im LKW und fährst noch – warte, bis du ankommst (wait bis: \"ankunft\"). Denken, Reden und Firma gehen auch unterwegs."}
	if type in ["MoveTo", "Fahrt", "LKW", "Pickup", "Stop", "Siedlung"] and b.has("baut"):
		b.erase("baut")   # wer weggeht, baut nicht mehr
	if not from_plan and type in ["MoveTo", "Stop", "Pickup", "Place", "Ablauf"] and not (b.get("ablauf", []) as Array).is_empty():
		b.ablauf = []   # eine direkte Handlung ersetzt einen laufenden Ablauf
		_event(b, "bricht den laufenden Ablauf ab")
	var warum := str(data.get("warum", "")).left(160)
	if type == "MoveTo" and not from_plan and not (b.mover as Mover).arrived():
		var t0 = parse_tile(data.get("tile", data.get("feld")))
		if t0 != null and Vector2i(int(t0[0]), int(t0[1])) == (b.mover as Mover).goal:
			return {"ok": true, "status": "laeuft", "msg": "Du bist bereits unterwegs zu diesem Ziel."}
	if type == "Ablauf":
		var rp := _start_plan(b, data)
		rp["status"] = "laeuft" if rp.ok else "gescheitert"
		_decide(b, type, warum, rp)
		return rp
	if type in WORK_ACTIONS and float(b.get("akku", 100.0)) < EMPTY_AKKU:
		_event(b, "ist zu erschöpft für %s" % type)
		return {"ok": false, "msg": "Dein Akku ist fast leer (%d %%). Ruh dich erst aus (Rest) – zu Hause in der Ladestation geht es am schnellsten.%s" % [int(b.akku), home_hint(b)]}
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
			r = arms.pickup(b, str(data.waffe)) if data.has("waffe") else _pickup(b, data)
		"Attack":
			r = arms.attack(b, data)
		"Bauwerk":
			r = estates.order(b, data)
		"Tor":
			r = estates.gate(b, data)
		"Bauplan":
			r = estates.build_plan(b, data)
		"Fahrt":
			r = _ride(b, data)
		"Give":
			r = arms.give(b, data)
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
		"MoveIn":
			r = _move_in(b)
		"Amt":
			r = _office_action(b, data)
		"Bauen":   # selbst auf einer Baustelle arbeiten (EkoHomes) oder an der Basis (Stammsitz-Bauwerk)
			r = _work(b, data)
		"LKW":     # mit dem eigenen LKW fahren: Grosslager (Ware abholen, tanken), Hof oder ein Feld
			r = _truck(b, data)
		"Rammen":   # Angriff mit dem eigenen LKW (Benedikt 18.11.: Beschaedigen nur, wenn die KI das entscheidet)
			r = _ram(b, data)
		"Siedlung":   # Wildnis: Siedlung am gewaehlten Platz gruenden (EkoSettle)
			var fc := active_firm(b)
			var f = []
			for key in ["feld", "tile", "ort", "platz", "pos", "position", "kachel"]:   # 17.11.: Wesen schrieben "ort"
				if data.get(key) is Array and (data[key] as Array).size() >= 2:
					f = data[key]
					break
			if not sim.wildnis or fc < 0:
				r = {"ok": false, "msg": "Siedlungen gründen nur Unternehmer in der Wildnis-Partie."}
			elif not (f is Array) or (f as Array).size() < 2:
				r = settle.found(b, fc, tile_of(b))   # ohne Feld: hier, wo das Wesen steht (17.11.: Meldung versprach das, tat es aber nicht)
			else:
				r = settle.found(b, fc, Vector2i(int(f[0]), int(f[1])))
		"Firma":
			r = _firm_action(b, data)
		"Inspect":
			r = inspect(b, str(data.get("target_id", data.get("ziel", ""))))
		"Ziel":
			r = _set_goal(b, data)
		"ZielStand":
			r = _goal_progress(b, data)
		"Merke":
			r = _lesson(b, data)
		_:
			r = {"ok": false, "msg": "Unbekannte Handlung %s. Erlaubt: %s." % [type, ", ".join(ACTIONS)]}
	if not bool(r.ok):
		_event(b, "Fehlschlag %s: %s" % [type, r.msg])
	if not r.has("status"):   # angenommen != abgeschlossen: Bewegung laeuft, bis du.unterwegs false ist
		r["status"] = "gescheitert" if not bool(r.ok) else ("laeuft" if type == "MoveTo" else "abgeschlossen")
	if type != "Merke":
		_decide(b, type, warum if warum != "" or type != "Inspect" else "untersucht %s" % str(data.get("target_id", "")), r)
	# Viel geredet, wenig getan (Partie 16.11.: ein Viertel aller Handlungen waren Gespraeche ueber ein erfundenes Angebot):
	# ab drei Gespraechen in den letzten sechs Handlungen haengt jede weitere Antwort den naechsten sinnvollen Schritt an.
	var recent: Array = b.get("recent", [])
	recent.append(type)
	b["recent"] = recent.slice(-6)
	if type in ["Talk", "Say"] and (b.recent as Array).count("Talk") + (b.recent as Array).count("Say") >= 3:
		var steps := next_steps(b)
		if not steps.is_empty():
			r["hinweis"] = "Du redest gerade viel und handelst wenig. Nächster sinnvoller Schritt: " + str(steps[0])
	if not r.has("hinweis") and type not in ["MoveTo", "Fahrt", "Rest", "Stop"] and float(b.get("akku", 100.0)) < HOME_AKKU:
		var first: Array = next_steps(b)
		if not first.is_empty() and (str(first[0]).begins_with("Nach Hause") or str(first[0]).begins_with("Ausruhen")):
			r["hinweis"] = str(first[0])
	changed.emit()
	return r


# ------------------------------------------------------------------ Autonomie: Erkunden, Untersuchen, Ziele (15.11.2026)
const MAX_PLACES := 150             # so viele entdeckte Orte merkt sich die Welt je Wesen
const GOAL_STATES := ["aktiv", "erreicht", "aufgegeben"]


## Letzte Entscheidung fuer Anzeige und Beobachtung: was, warum, was ist passiert.
func _decide(b: Dictionary, type: String, warum: String, r: Dictionary) -> void:
	b["entscheidung"] = {"aktion": type, "warum": warum, "status": str(r.get("status", "")), "ergebnis": str(r.get("msg", "")).left(120),
		"zeit": Catalog.game_minutes_to_text(sim.game_min), "ms": Time.get_ticks_msec()}


## Entdeckte Orte: Gebaeude, die das Wesen gesehen hat (Name, Art, Feld). Nur was es selbst gesehen hat.
func _discover(b: Dictionary, bd: Dictionary) -> void:
	var places: Dictionary = b.get("orte", {})
	var key := str(bd.name)
	if not places.has(key):
		if places.size() >= MAX_PLACES:
			return
		places[key] = {"art": str(bd.get("type", "")), "feld": [int(bd.walk.x), int(bd.walk.y)], "entdeckt": Catalog.game_minutes_to_text(sim.game_min)}
		b["orte"] = places


## Erkundung fuer die Beobachtung: bekannte Orte (naechste zuerst), Orte der Region (allgemein bekannt, Ortsschilder) mit Besuchsstand.
func _exploration_obs(b: Dictionary) -> Dictionary:
	var t := tile_of(b)
	var places: Dictionary = b.get("orte", {})
	var known: Array = []
	for k in places:
		var f: Array = places[k].feld
		known.append({"name": k, "art": places[k].art, "feld": f, "entfernung": _dist(t, Vector2i(int(f[0]), int(f[1])))})
	known.sort_custom(func(x, y): return int(x.entfernung) < int(y.entfernung))
	var visited: Dictionary = b.get("besucht", {})
	var towns: Array = []
	for tw in sim.city.towns:
		towns.append({"ort": str(tw.name), "mitte": tw.center, "besucht": visited.has(str(tw.name))})
	return {"bekannte_orte": known.slice(0, 25), "anzahl_bekannt": places.size(), "orte_der_region": towns,
		"hinweis": "Du kennst nur, was du gesehen hast. Unbekannte Orte findest du, indem du hingehst (MoveTo) und dich umsiehst; Inspect {target_id} zeigt Einzelheiten."}


func _mark_visit(b: Dictionary) -> void:
	var k: int = sim.city.town_of(tile_of(b))
	if k >= 0 and k < sim.city.towns.size():
		var v: Dictionary = b.get("besucht", {})
		v[str(sim.city.towns[k].name)] = true
		b["besucht"] = v


## Inspect: oeffentlich erkennbare Angaben zu einem sichtbaren Ziel (Gebaeude, Wesen, Unternehmer, Grundstueck). Aendert nichts.
## Keine Interna: keine Kassenstaende, Strategien oder Lagerbestaende fremder Firmen.
func inspect(b: Dictionary, target: String) -> Dictionary:
	var t := tile_of(b)
	if target == "":
		return {"ok": false, "msg": "Inspect braucht target_id: Gebäudename (gebaeude_in_der_naehe), Wesen, Unternehmer oder Grundstück (G…)."}
	b["blick"] = target
	var cid0 := active_firm(b)
	if cid0 >= 0 and target.to_upper().begins_with("BS") and homes.sites.has(target.to_upper()):   # 18.11.: Viktor wollte seine Baustelle ansehen
		return {"ok": true, "msg": homes.site_text(cid0, target.to_upper())}
	if beings.has(target) and target != b.name:
		var o: Dictionary = beings[target]
		if _dist(t, tile_of(o)) > VIEW_RADIUS:
			return {"ok": false, "msg": "%s ist nicht in Sichtweite." % target}
		var job := "Bürgermeister" if int(o.get("amt", -1)) >= 0 else ("Unternehmer (%s)" % sim.company(active_firm(o)).company_name if active_firm(o) >= 0 else "freies Wesen")
		return {"ok": true, "msg": "Du siehst dir %s an." % target, "ziel": {"art": "wesen", "name": target, "gestalt": o.art, "rolle": job,
			"traegt": o.held, "sagt": o.say if float(o.say_left) > 0.0 else "", "unterwegs": not (o.mover as Mover).arrived(),
			"interaktionen": ["Talk {to: \"%s\", text} (höchstens %d Felder)" % [target, TALK_REACH]]}}
	for c in sim.companies:
		if c.player_name == target or c.company_name == target:
			var at: Vector2i = sim.avatars[c.id].tile()
			if _dist(t, at) > VIEW_RADIUS:
				return {"ok": false, "msg": "%s ist nicht in Sichtweite." % target}
			return {"ok": true, "msg": "Du siehst dir %s an." % target, "ziel": {"art": "unternehmer", "name": c.player_name, "firma": c.company_name,
				"aktiv": c.is_active(), "fahrzeuge": sim.vehicles.values().filter(func(v): return v.owner == c.id).size(), "gerade": LiveText.figure_text(sim, c.id).left(100),
				"interaktionen": ["Talk {to: \"%s\", text}" % c.player_name] + (["AcceptJob (siehe jobangebote)"] if jobs.values().any(func(j): return int(j.cid) == c.id and str(j.get("by", "")) == "") else [])}}
	if target.begins_with("G") and target.substr(1).is_valid_int():
		var p: Dictionary = sim.parcels.parcel(target)
		if p.is_empty():
			return {"ok": false, "msg": "Grundstück %s gibt es nicht." % target}
		var pc := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
		if _dist(t, pc) > VIEW_RADIUS + 4:
			return {"ok": false, "msg": "Grundstück %s ist nicht in Sichtweite." % target}
		var acts: Array = []
		if p.state == "frei" and str(p.zone) == "wohnen" and int(p.area) <= 40:
			acts.append("BuyPlot {plot: \"%s\"} (höchstens 6 Felder entfernt)" % target)
		if p.state == "frei" and active_firm(b) >= 0:
			acts.append("Firma {aktion: {action: buy_property / found_business ...}}")
		return {"ok": true, "msg": "Du siehst dir Grundstück %s an." % target, "ziel": {"art": "grundstueck", "id": target, "zone": p.zone, "flaeche": int(p.area),
			"zustand": p.state, "preis": float(p.price), "feld": [pc.x, pc.y], "lagerstaette": "unerkundet" if not sim.prod.deposit_of(target).is_empty() else "keine bekannt",
			"interaktionen": acts}}
	var bd := {}
	if target.begins_with("building_") and target.substr(9).is_valid_int():
		bd = sim.city.building(int(target.substr(9)))
	else:
		for x in sim.city.buildings:
			if str(x.name) == target:
				bd = x
				break
	if bd.is_empty():
		return {"ok": false, "msg": "Unbekanntes Ziel %s. Nimm einen Namen aus gebaeude_in_der_naehe, andere_wesen, figuren_in_der_naehe oder ein Grundstück G…" % target}
	if _building_dist(t, bd) > VIEW_RADIUS:   # Abstand zum naechsten Feld des Gebaeudes (grosse Gebaeude: Eingang liegt weit weg)
		return {"ok": false, "msg": "%s ist nicht in Sichtweite – geh näher heran." % target}
	_discover(b, bd)
	var info := {"art": "gebaeude", "name": str(bd.name), "typ": str(bd.type), "feld": [int(bd.walk.x), int(bd.walk.y)], "rolle": str(bd.get("role", ""))}
	var acts: Array = []
	var bid := int(bd.id)
	for biz in sim.biz.items.values():
		if int(biz.get("site", -1)) == bid:
			var owner = sim.company(int(biz.owner))
			info["betrieb"] = str(biz.name)
			info["branche"] = str(Businesses.branches().get(str(biz.branch), {}).get("label", biz.branch))
			info["betreiber"] = owner.company_name if owner != null else ""
			info["zustand"] = {"aktiv": "in Betrieb", "blockiert": "steht still", "im_bau": "im Bau"}.get(str(biz.status), str(biz.status))
			if str(biz.status) == "blockiert" and not (biz.get("blockers", []) as Array).is_empty():
				info["erkennbares_problem"] = str(biz.blockers[0].text)   # sichtbar vor Ort (Schild am Tor)
			if owner != null:
				acts.append("Talk {to: \"%s\"} (Betreiber)" % owner.player_name)
			break
	if sources().any(func(s): return int(s.feld[0]) == int(bd.walk.x) and int(s.feld[1]) == int(bd.walk.y)):
		info["funktion"] = "Bauhof: Material und Einrichtung kaufen"
		acts.append("Pickup {material, count} (Preise in material_preise)")
	elif str(bd.get("role", "")) == "town_hall":
		info["funktion"] = "Rathaus: Sitz des Bürgermeisters"
		for M in sim.towns.mayors:
			if int(M.town) < sim.city.towns.size() and int(sim.city.towns[int(M.town)].get("town_hall", -1)) == bid:
				info["buergermeister"] = str(M.name)
	elif str(bd.type) == "plot":
		info["funktion"] = "Bauplatz"
	if houses.has(b.name) and home_rect(b.name).has_point(Vector2i(int(bd.walk.x), int(bd.walk.y))):
		acts.append_array(["MoveIn {}", "Rest {}"])
	info["interaktionen"] = acts
	return {"ok": true, "msg": "Du siehst dir %s an." % str(bd.name), "ziel": info}


func _building_dist(t: Vector2i, bd: Dictionary) -> int:
	var r := Rect2i(int(bd.get("x", bd.walk.x)), int(bd.get("y", bd.walk.y)), maxi(1, int(bd.get("w", 1))), maxi(1, int(bd.get("h", 1))))
	var cx := clampi(t.x, r.position.x, r.end.x - 1)
	var cy := clampi(t.y, r.position.y, r.end.y - 1)
	return mini(_dist(t, Vector2i(cx, cy)), _dist(t, Vector2i(int(bd.walk.x), int(bd.walk.y))))


## Ziel setzen: Hauptziel mit Begruendung, Teilzielen, Nutzen, Ressourcen, Erwartung und Abbruchbedingung.
## Ein aktives Ziel wird nur mit ersetzen: true und Begruendung abgeloest (nicht jede Beobachtung ersetzt das Hauptziel).
## Naechste sinnvolle Schritte (hoechstens 3, sofort ausfuehrbar). Partie 16.11.: Drei von vier Unternehmern hatten nach drei
## Monaten kein Fahrzeug, keiner baute den Stammsitz aus, Ziele standen seit Monat 1 bei 0 %, und ein erfundenes Fahrzeugangebot
## ging per Anruf reihum – das kleine Modell verlor in der grossen Beobachtung den Faden. Diese Liste nennt nur, was wirklich geht.
const GOAL_STALE_DAYS := 3
## Ziele rund um das eigene Heim (Partie 16.11.: Viktor "eigenes Zuhause" 0 % trotz Huette, Burg und Mauer) – Woerter in Kleinschreibung.
const HOME_GOAL_WORDS := ["zuhause", "stammsitz", "basis", "burg", "schloss", "festung", "heim", "anwesen", "haus", "mauer", "residenz"]
const HOME_GOAL_FULL := 3   # so viele fertige Bauten (ausser der Starthuette) = Ziel erreicht


## Wohn-/Stammsitz-Ziel: Fortschritt aus den fertigen Bauten ableiten (nur nach oben), ab HOME_GOAL_FULL erreicht.
func _estate_goal_sync(b: Dictionary) -> void:
	var g: Dictionary = b.get("ziel", {})
	if g.is_empty() or str(g.get("status", "")) != "aktiv" or not estates.estates.has(str(b.name)):
		return
	var low := str(g.ziel).to_lower()
	if not HOME_GOAL_WORDS.any(func(w): return low.contains(w)):
		return
	var done: Array = (estates.estates[b.name].bauten as Array).filter(func(x): return x.art != "huette" and str(x.get("status", "")) == "fertig")
	var pct := mini(100, int(round(100.0 * done.size() / HOME_GOAL_FULL)))
	if pct <= int(g.get("fortschritt", 0)):
		return
	g.fortschritt = pct
	g["stand_min"] = sim.game_min
	if pct >= 100:
		g.status = "erreicht"
		_event(b, "Ziel erreicht: %s (Stammsitz mit %s)" % [g.ziel, ", ".join(done.map(func(x): return x.art))])
		sim.log_event("%s: Ziel erreicht – %s" % [b.name, g.ziel], "good")
	else:
		_event(b, "Ziel „%s“: %d %% (fertig: %s)" % [str(g.ziel).left(60), pct, ", ".join(done.map(func(x): return x.art))])


## Projektziele aus dem tatsächlichen Bauzustand ableiten. Auch ältere Freitextziele
## mit einer Projekt-ID werden so nach dem Laden wieder mit der Welt abgeglichen.
func _project_goal_sync(b: Dictionary) -> void:
	var g: Dictionary = b.get("ziel", {})
	if g.is_empty() or str(g.get("status", "")) != "aktiv" or sim.towns == null:
		return
	var pid := str(g.get("projekt", ""))
	if pid == "":
		var re := RegEx.new()
		re.compile("(?:T[0-9]+)?P[0-9]+")
		var found := re.search(str(g.get("ziel", "")))
		if found == null:
			return
		pid = found.get_string()
		g["projekt"] = pid
	var prj: Dictionary = sim.towns.project(pid)
	if prj.is_empty():
		g.status = "aufgegeben"
		g["notiz"] = "Projekt %s existiert nicht mehr; neues Stadtziel wählen." % pid
		return
	var state := str(prj.get("status", ""))
	if state == "fertig":
		g.status = "erreicht"
		g.fortschritt = 100
		g["stand_min"] = sim.game_min
	elif state in ["abgelehnt", "abgebrochen"]:
		g.status = "aufgegeben"
		g["notiz"] = "Projekt %s wurde %s; neues Stadtziel wählen." % [pid, state]
	else:
		var real_progress := 0
		var run: Dictionary = sim.construction.public.get(pid, {}) if sim.construction != null else {}
		if not run.is_empty() and int(run.get("days", 0)) > 0:
			real_progress = clampi(int(round(100.0 * (1.0 - float(run.get("days_left", run.days)) / float(run.days)))), 0, 95)
		if real_progress > int(g.get("fortschritt", 0)):
			g.fortschritt = real_progress
			g["stand_min"] = sim.game_min


## Ein Wesen kann nur seine zugewiesene Wildnisstadt gruenden. Alte Modellziele
## fuer einen zweiten Gruendungsort duerfen es nach dem Laden nicht weglocken.
func _is_founding_goal(text: String) -> bool:
	var low := text.to_lower()
	return low.contains("gründ") or low.contains("gruend") or low.contains("gründen") or low.contains("betriebshof gründen")


func _founding_goal_sync(b: Dictionary) -> void:
	var g: Dictionary = b.get("ziel", {})
	if g.is_empty() or str(g.get("status", "")) != "aktiv" or not _is_founding_goal(str(g.get("ziel", ""))):
		return
	var cid := active_firm(b)
	if cid < 0 or not sim.wildnis or not settle.founded(sim.companies[cid].home_town):
		return
	g.status = "aufgegeben"
	g["notiz"] = "Die zugewiesene Stadt %s ist bereits gegründet; neues Ausbauziel wählen." % sim.towns.name_of(sim.companies[cid].home_town)
	_event(b, "verwirft altes Gründungsziel und kümmert sich um %s" % sim.towns.name_of(sim.companies[cid].home_town))


const HOME_AKKU := 30.0   # darunter (oder nass/kalt) steht der Heimweg an erster Stelle (Partie 16.11.: Viktor arbeitete mit 14 % Akku, nass und kalt weiter)


## Messbarer Stadtzustand fuer Unternehmer und Buergermeister. Der Agent waehlt
## Standort, Gebaeude und Reihenfolge selbst; nur die tatsaechlichen Engpaesse
## kommen aus der Simulation statt aus einer festen Baufolge.
func city_growth_status(town: int) -> Dictionary:
	if town < 0 or town >= sim.towns.count():
		return {}
	var founded: bool = settle.founded(town)
	var ready: bool = sim.town_ready(town)
	var population: int = sim.citizens.population_of(town)
	var waiting: int = sim.towns.mayor(town).waiting if ready else 0
	var units := 0
	var habitable := 0
	var missing := {}
	var affected := {}
	for unit in sim.housing.units.values():
		if sim.towns.of_building(int(unit.building)) != town:
			continue
		units += 1
		if sim.housing.habitable(unit):
			habitable += 1
		else:
			var gaps: Array = []
			var parcel: Dictionary = sim.parcels.of_building(int(unit.building))
			var service: Dictionary = parcel.get("erschliessung", {})
			for part in ["strasse", "strom", "wasser", "abwasser"]:
				if not bool(service.get(part, false)):
					missing[part] = true
					gaps.append(part)
			if not sim.grid.net.connected(town):
				missing["kraftwerksstrom"] = true
				gaps.append("kraftwerksstrom")
			if not sim.water.building_on_net(town, int(unit.building)):
				missing["frischwassernetz"] = true
				gaps.append("frischwassernetz")
			if not sim.water.building_on_sewer(town, int(unit.building)):
				missing["kanalnetz"] = true
				gaps.append("kanalnetz")
			var bid := int(unit.building)
			if not affected.has(bid):
				var building: Dictionary = sim.city.building(bid)
				affected[bid] = {"gebaeude": bid, "strassenfeld": building.get("road", Vector2i.ZERO), "fehlt": gaps}
	var building_projects: Array = []
	for project in sim.construction.projects.values():
		if str(project.status) in Construction.ACTIVE_STATES and sim.towns.of_parcel(str(project.parcel)) == town:
			building_projects.append(str(project.id) + " (" + str(project.status) + ")")
	var stage := "wachstum"
	var hint := ""
	if not founded:
		stage = "standortwahl"
		hint = "Wähle selbst einen geeigneten Platz und gründe deine Siedlung. Ohne Siedlung gibt es keinen Stadtbau."
	elif not ready:
		stage = "buergeramt"
		hint = "Die Siedlung braucht ein fertiges Bürgeramt, bevor Bürgermeister, Versorgung und Zuzug starten. Prüfe vorhandene Baustellen und ihre Hindernisse."
	elif habitable == 0:
		stage = "wohnraum"
		if units > 0:
			hint = "Es gibt %d Wohneinheiten, aber keine ist bewohnbar. Fehlende Anschlüsse: %s. Ein weiteres unversorgtes Haus bringt keinen Zuzug." % [units, ", ".join(missing.keys()) if not missing.is_empty() else "Wasserstörung"]
			if missing.has("kraftwerksstrom"):
				hint += " Die Stadtverwaltung muss eine geprüfte Stromtrasse vom Kraftwerk wählen und bauen lassen."
			if missing.has("frischwassernetz") or missing.has("kanalnetz"):
				hint += " Frischwasser- und Kanalnetz müssen die Wohnhäuser tatsächlich erreichen."
		elif not building_projects.is_empty():
			hint = "Noch keine bewohnbare Wohnung. Laufende Bauvorhaben: %s. Prüfe Baufortschritt, Anschlüsse und Blockaden bis zur Übergabe; plane parallel passende Arbeitsplätze." % ", ".join(building_projects.slice(0, 3))
		else:
			hint = "Noch keine bewohnbare Wohnung und kein laufendes Bauvorhaben. Wähle selbst ein geeignetes Grundstück und einen Wohnentwurf; sichere Straße, Strom, Frischwasser und Abwasser."
	elif population == 0:
		stage = "zuzug"
		hint = "%d bewohnbare Wohnungen sind frei, aber noch niemand ist zugezogen. Prüfe Zuzug, Arbeitsplätze und Versorgungsqualität, bevor du viele neue Viertel planst." % habitable
	elif population < 12 or waiting > 0:
		stage = "ausbau"
		hint = "%d Einwohner, %d bewohnbare Wohnungen, %d wartende Haushalte. Vergleiche Wohnungsbedarf, Gewerbe, Anschlüsse und laufende Projekte; wähle den nächsten Ausbau selbst." % [population, habitable, waiting]
	return {"stufe": stage, "stadt": sim.towns.name_of(town), "gegruendet": founded, "buergeramt": ready,
		"einwohner": population, "wohnungen": units, "bewohnbar": habitable, "wohnungssuchende": waiting,
		"fehlende_anschluesse": missing.keys(), "betroffene_haeuser": affected.values().slice(0, 12),
		"bauvorhaben": building_projects, "hinweis": hint}


func urgency(b: Dictionary) -> Dictionary:
	var cid := active_firm(b)
	if cid < 0:
		var office_town: int = int(b.get("amt", -1))
		if office_town >= 0 and conflict.assaults.values().any(func(a): return int(a.stadt) == office_town):
			return {"prioritaet": 2, "grund": "Bewaffneter Angriff auf deine Stadt: pruefe mein_amt.bedrohung und verteidigung. Entscheide sofort ueber einen Wachturm, Stadtmauer oder Wiederaufbau mit mayor_action; Kosten und Bauzeit stehen in der Amtslage."}
		if sim.wildnis and office_town >= 0 and sim.town_ready(office_town):
			var growth: Dictionary = city_growth_status(office_town)
			if str(growth.get("stufe", "")) == "wohnraum" and int(growth.get("wohnungen", 0)) > 0:
				var board: Dictionary = _public_build_board(office_town)
				if bool(board.get("wareneingang_ohne_personal", false)):
					return {"prioritaet": 2, "grund": "Angelieferte Baustoffe blockieren das Stadtlager ohne Personal. Entscheide selbst ueber expand_depot mit kind staff oder waehle die entsprechende Nummer aus mein_amt.entscheidungsoptionen; danach die Anschlussarbeiten erneut pruefen."}
				if not bool(board.get("neues_bauprojekt_moeglich", true)):
					var depot_summary: Dictionary = sim.towns.mayor(office_town).stadtlager_indicators()
					var proposals: Array = depot_summary.get("vorschlaege", [])
					if not proposals.is_empty():
						var order_ids: Array = proposals.map(func(o): return str(o.id))
						return {"prioritaet": 2, "grund": "%d von %d Bauplätzen sind belegt. Prüfe die Beschaffungsvorschläge des Stadtlagers %s und entscheide selbst mit mayor_action {action: approve_procurement, params: {order_id: gewählte ID, reason: Grund}}; danach laufende Baustellen beobachten." % [int(board.offen), int(board.kapazitaet), ", ".join(order_ids)]}
					return {"prioritaet": 1, "grund": "%d von %d Bauplätzen sind belegt. Weitere Netze erst nach Abschluss laufender Projekte beauftragen; beobachte Materiallieferungen und Bautrupps." % [int(board.offen), int(board.kapazitaet)]}
				var gaps: Array = growth.get("fehlende_anschluesse", [])
				var power_pending: bool = sim.grid.net.planned.values().any(func(p): return str(p.get("b", "")) == "U%d" % office_town)
				var power_options: Array = sim.grid.net.option_brief(office_town)
				if "kraftwerksstrom" in gaps and not power_pending and not power_options.is_empty():
					var power_ids: Array = power_options.map(func(o): return str(o.id))
					return {"prioritaet": 2, "grund": "Wohnungen sind fertig, aber ohne Kraftwerksstrom nicht bewohnbar. Gültige Stromtrassen-IDs: %s. Wähle selbst eine Variante aus mein_amt.stromtrassen und nutze mayor_action {action: stromtrasse_bauen, params: {option: gewählte ID, reason: Grund}}; danach das Ergebnis prüfen." % ", ".join(power_ids)}
				for art in ["wasser", "abwasser"]:
					var key: String = "frischwassernetz" if art == "wasser" else "kanalnetz"
					var pending: bool = sim.water.main_projects.values().any(func(p): return int(p.get("town", -1)) == office_town and str(p.get("art", "")) == art)
					var line_options: Array = sim.water.main_options(office_town, art)
					if key in gaps and not pending and not line_options.is_empty():
						var line_ids: Array = line_options.map(func(o): return str(o.id))
						return {"prioritaet": 2, "grund": "Wohnungen sind fertig, aber das %s erreicht sie nicht. Gültige Leitungs-IDs: %s. Wähle selbst eine Variante aus mein_amt.versorgungsleitungen und nutze mayor_action {action: versorgungsleitung_bauen, params: {option: gewählte ID, reason: Grund}}." % [("Frischwassernetz" if art == "wasser" else "Kanalnetz"), ", ".join(line_ids)]}
		return {"prioritaet": 0, "grund": ""}
	var best := {"prioritaet": 0, "grund": ""}
	var home_k: int = sim.company(cid).home_town
	if conflict.assaults.values().any(func(a): return int(a.target) == cid):
		return {"prioritaet": 2, "grund": "Bewaffneter Angriff auf deine Stadt: pruefe meine_firma.stadtpolitik_und_konflikt, mobilisiere freie Mitarbeiter und Waffen zur Verteidigung, sichere wichtige Gebaeude und sprich mit dem Buergermeister ueber Schutzbauten. Frieden erlaubt Selbstverteidigung."}
	if sim.wildnis and home_k >= 0 and settle.founded(home_k) and not sim.town_ready(home_k) 			and not homes.sites.values().any(func(st): return int(st.cid) == cid and str(st.typ) == "buergeramt"):
		# 19.11.: qwen3.5:9b lief drei Spieltage herum statt das Buergeramt anzulegen – ohne es waechst nichts
		return {"prioritaet": 2, "grund": "Deine Siedlung hat noch kein Bürgeramt. Ohne Bürgeramt gibt es keinen regulären Zuzug; wähle selbst einen passenden Bauplatz und beginne den Bau."}
	if sim.wildnis and home_k >= 0 and not sim.town_ready(home_k):
		for st in homes.sites.values():   # 19.11.: Buergeramt wartete 20 Minuten auf Material, keiner kaufte
			if int(st.cid) == cid and str(st.typ) == "buergeramt" and str(st.status) == "material":
				var miss: Dictionary = homes.missing(st)
				var open_buy := false
				var waiting: Dictionary = homes.waiting_goods(cid)
				for item in miss:
					open_buy = open_buy or int(miss[item]) > int(waiting.get(item, 0))
				if open_buy:
					return {"prioritaet": 2, "grund": "Bürgeramt %s wartet auf Material: alles kaufen – Firma {aktion: {action: \"hub_buy\", baustelle: \"%s\"}}" % [st.id, st.id]}
				if not miss.is_empty():
					return {"prioritaet": 2, "grund": "Material für Bürgeramt %s ist gekauft – Materialhubschrauber bringt es zum Hof. Alte LKW-Sendungen ggf. mit call_material_heli nachfordern." % st.id}
			if int(st.cid) == cid and str(st.typ) == "buergeramt" and str(st.status) == "bau" and str(b.get("baut", "")) != str(st.id) and not homes.owner_working(st) and (st.get("helfer", {}) as Dictionary).is_empty():
				return {"prioritaet": 2, "grund": "Bürgeramt %s hat alles Material, aber niemand baut: Bauen {baustelle: \"%s\"} oder Firma {aktion: {action: \"tageloehner\", baustelle: \"%s\", anzahl: 2}}. Keine weiteren Baustoffe kaufen." % [st.id, st.id, st.id]}
	# Nach der Gruendung ist das erste Wohnhaus die sichtbare Wachstumsstufe. Gekauftes Material und baubereite
	# Haeuser duerfen nicht hinter immer neuen Versuchen fuer eine bereits staedtisch beauftragte Strasse verschwinden.
	if sim.wildnis and home_k >= 0 and sim.town_ready(home_k):
		for st in homes.open_sites(cid):
			if str(st.typ) == "strasse" or str(st.typ) == "buergeramt":
				continue
			if str(st.status) == "bau" and not homes.owner_working(st) and (st.get("helfer", {}) as Dictionary).is_empty():
				return {"prioritaet": 2, "grund": "Baustelle %s (%s) ist baubereit, aber niemand arbeitet: Bauen {baustelle: \"%s\"} oder Firma {aktion: {action: \"tageloehner\", baustelle: \"%s\", anzahl: 2}}." % [st.id, st.typ, st.id, st.id]}
			if str(st.status) == "material":
				var miss: Dictionary = homes.missing(st)
				if miss.is_empty():
					continue
				var waiting: Dictionary = homes.waiting_goods(cid)
				if miss.keys().all(func(item): return int(waiting.get(item, 0)) >= int(miss[item])):
					return {"prioritaet": 2, "grund": "Material für Baustelle %s (%s) ist gekauft und unterwegs. Materialhubschrauber abwarten; nicht noch einmal kaufen oder eine neue Straße planen." % [st.id, st.typ]}
		var housing_types := ["einfamilienhaus", "doppelhaus", "mehrfamilienhaus", "stadtvilla", "hochhaus"]
		var housing_started: bool = homes.sites.values().any(func(st): return int(st.cid) == cid and str(st.typ) in housing_types and str(st.status) != "abgelehnt")
		if not housing_started:
			return {"prioritaet": 1, "grund": "Deine Stadt hat noch kein Wohnhaus. Neue Haushalte können erst mit freien Wohnungen einziehen; Typ, Entwurf und Zeitpunkt wählst du."}
	for k in sim.contracts.values():
		if k.owner != cid or k.status not in ["accepted", "assigned", "loading", "in_transit"]:
			continue
		var left := int(k.deadline - sim.game_min)
		if left <= 90:
			return {"prioritaet": 2, "grund": "Auftrag %s: Frist in %d Spielminuten" % [k.id, left], "frist_in_min": left}
		if left <= 240:
			best = {"prioritaet": 1, "grund": "Auftrag %s: Frist in %d Spielminuten" % [k.id, left], "frist_in_min": left}
	for v in sim.company_vehicles(cid):
		if v.state == "broken" and str(v.contract_id) != "":
			return {"prioritaet": 2, "grund": "LKW #%d mit Auftrag ausgefallen" % v.id}
	if sim.company(cid).ledger.cash < float(sim.operations.dispatch_policy(cid).reserve) and int(best.prioritaet) == 0:
		best = {"prioritaet": 1, "grund": "Firmenkasse unter Dispositionsreserve"}
	if int(best.prioritaet) == 0:
		for rival in sim.companies:
			if rival.id != cid and rival.is_active() and sim.rivalry.get_tension(cid, rival.id) >= Rivalry.STAGES[3] and sim.company(cid).security_level == 0:
				best = {"prioritaet": 1, "grund": "Hohe Rivalitaet mit %s: Sabotage- und Blockaderisiko pruefen. Entscheide ueber Wachschutz, Versicherung, Schlichtung oder Kooperation anhand von Kosten und Gefahr." % rival.company_name}
				break
	if int(best.prioritaet) == 0 and GameCalendar.day_of(sim.game_min) >= 10:
		var week: Dictionary = sim.finance.company_period(cid, 7)
		if float(week.get("ergebnis", 0.0)) < -500.0:
			best = {"prioritaet": 1, "grund": "Die letzten 7 Spieltage brachten Verlust. Pruefe meine_firma.finanzlage und entscheide, welche Kosten, Preise oder Betriebe du aenderst und welche Expansion sich trotzdem lohnt."}
	return best


func next_steps(b: Dictionary) -> Array:
	_estate_goal_sync(b)
	_project_goal_sync(b)
	_founding_goal_sync(b)
	var out: Array = []
	var urgent_step := ""
	var firm_step := ""
	var pending_step := ""
	var goal_step := ""
	var plan_step := ""
	var home_step := ""   # 19.11.: Hausbau (Wildnis-Wachstum) wurde von Auftrag/Plan/Kontakt aus den ersten drei verdraengt
	var civic_step := ""
	var growth_step := ""
	var crisis := urgency(b)
	if int(crisis.prioritaet) >= 2:
		urgent_step = str(crisis.grund) + " – jetzt Lage und passende Aktion prüfen."
		out.append(urgent_step)
	var akku := float(b.get("akku", 100.0))
	if float(b.get("rest_left", 0.0)) <= 0.0 and (akku < HOME_AKKU or float(b.get("nass", 0.0)) > 60.0 or float(b.get("kalt", 0.0)) > 60.0):
		var why := "Akku %d %%" % int(akku) if akku < HOME_AKKU else ("du bist nass" if float(b.get("nass", 0.0)) > 60.0 else "dir ist kalt")
		if is_home(b):
			out.append("Ausruhen (%s): Rest – du bist zu Hause, dort lädst du schnell und wirst trocken und warm." % why)
			urgent_step = str(out.back())
		else:
			var hint := home_hint(b)
			if hint != "":
				out.append("Nach Hause (%s):%s Für weite Wege: Fahrt." % [why, hint])
				urgent_step = str(out.back())
	var cid := active_firm(b)
	var growth_town: int = int(b.get("amt", -1)) if int(b.get("amt", -1)) >= 0 else (sim.company(cid).home_town if cid >= 0 else -1)
	if sim.wildnis and growth_town >= 0:
		var growth: Dictionary = city_growth_status(growth_town)
		if str(growth.get("stufe", "")) in ["standortwahl", "buergeramt", "wohnraum", "zuzug", "ausbau"]:
			growth_step = "Stadtwachstum %s: %s" % [str(growth.get("stadt", "")), str(growth.get("hinweis", ""))]
			var gaps: Array = growth.get("fehlende_anschluesse", [])
			if int(b.get("amt", -1)) >= 0 and "kraftwerksstrom" in gaps:
				growth_step += " Wähle eine Option aus mein_amt.stromtrassen und nutze mayor_action {action: stromtrasse_bauen, params: {option: Kennung, reason: Grund}}."
			if int(b.get("amt", -1)) >= 0 and ("frischwassernetz" in gaps or "kanalnetz" in gaps):
				growth_step += " Prüfe mein_amt.versorgungsleitungen und nutze mayor_action {action: versorgungsleitung_bauen, params: {option: Kennung, reason: Grund}}."
			elif cid >= 0 and ("kraftwerksstrom" in gaps or "frischwassernetz" in gaps or "kanalnetz" in gaps):
				growth_step += " Sprich mit dem Bürgermeister über die fehlenden Netze; du kannst parallel erschlossene Bauplätze und Betriebe planen."
	if int(b.get("amt", -1)) >= 0:
		var depot: CityDepot = sim.towns.depot(int(b.amt))
		if depot.backlog_units() > 0 and depot.roster().is_empty():
			civic_step = "Stadtlager: %d angelieferte Baustoffe können ohne Lagerpersonal nicht geprüft und eingelagert werden. Entscheide über die erste Lagerkraft: Amt {aktion: {action: \"expand_depot\", kind: \"staff\", reason: \"Baumaterial für laufende Stadtprojekte einlagern\"}}. Das Stadtlager ist keine Versorgungsanlage für infra_ausbau." % depot.backlog_units()
		elif depot.backlog_units() > maxi(100, depot.dock_capacity() * 2) and depot.roster().size() < 3:
			civic_step = "Im Stadtlager warten %d Baustoffe auf Prüfung, nur %d Lagerkräfte arbeiten dort. Entscheide über eine weitere Stelle: Amt {aktion: {action: \"expand_depot\", kind: \"staff\", reason: \"Baustoffe für Stadtprojekte schneller einlagern\"}}." % [depot.backlog_units(), depot.roster().size()]
		else:
			var district: Dictionary = sim.town_plan.next_district(int(b.amt), sim.housing.planning_aids().get("bedarf", 0) > 0, _town_jobs_need(int(b.amt)))
			if district.has("aktion"):
				civic_step = "Eine mögliche Stadterweiterung: %s. Vergleiche auch andere Viertel, Versorgung, Gewerbe und laufende Projekte; du bestimmst das Vorhaben." % str(district.text)
			elif district.has("warten"):
				var blockers: Array = _public_build_blockers(int(b.amt))
				civic_step = "Stadtprojekt %s läuft. Blockaden: %s. Prüfe Material und Bautrupp; plane in der Zwischenzeit erschlossene Gewerbeflächen und Versorgung." % [str(district.warten), JSON.stringify(blockers.slice(0, 2))]
	var offen: Dictionary = b.get("offen", {})
	if not offen.is_empty():
		if float(sim.game_min) - float(offen.min) > GameCalendar.days_to_min(1):
			b.erase("offen")   # zu alt: nicht mehr draengen
		else:
			out.append("Antworten – %s hat dir gesagt: „%s“. Antworte mit Talk {to: \"%s\", text: ...} (geht auch als Anruf aus der Ferne)." % [
				offen.von, str(offen.text).left(120), offen.von])
			pending_step = str(out.back())   # 19.11.: offene Antwort bleibt in den ersten drei
	if cid >= 0:
		for o in sim.social.offers.values():
			if o.status == "open" and int(o.awaiting) == cid and float(o.expires) > sim.game_min:
				out.append("Angebot %s von %s wartet auf deine Antwort (%s): Firma {aktion: {action: \"accept_trade\", offer_id: \"%s\"}} – oder reject_trade bzw. counter_offer." % [
					o.id, sim.company(int(o.from)).player_name, sim.social.describe(o).left(100), o.id])
				pending_step = str(out.back())
				break
	if cid >= 0:
		var plan: Dictionary = sim.plans.summary(cid)
		if str(plan.get("status", "")) in ["kein Plan", "neu_planen"]:
			plan_step = "Firmenplan mit Ziel, Schritten, Horizont und Kennzahl festlegen oder neu planen (set_plan)."
		elif bool(plan.get("pruefung_faellig", false)):
			plan_step = "Firmenplan prüfen: Istwert und Ziel vergleichen, review_plan aufrufen und bei Bedarf ändern."
		if plan_step != "":
			out.append(plan_step)
		var c = sim.company(cid)
		if c.vehicle_ids.is_empty():
			var best := {}
			for of in sim.resources.available_offers():
				if best.is_empty() or float(of.price) < float(best.price):
					best = of
			if not best.is_empty() and c.ledger.cash >= float(best.price):
				out.append("Fahrzeug kaufen – ohne Fahrzeug verdient %s nichts: Firma {aktion: {action: \"buy_vehicle\", offer_id: \"%s\"}} (%s, %s; Firmenkasse %s). Angebots-IDs stehen in meine_firma.fahrzeugangebote, nicht bei anderen Unternehmern." % [
					c.company_name, best.id, best.model, Catalog.money(float(best.price)), Catalog.money(c.ledger.cash)])
				firm_step = str(out.back())
		else:
			var step := _fleet_step(cid, float(b.get("takt_min", 0.0)))
			if step != "":
				out.append(step)
				firm_step = step
			elif sim.wildnis and c.vehicle_ids.size() == 1 and not homes.open_sites(cid).is_empty():
				for offer in sim.resources.available_offers():
					if c.ledger.cash >= float(offer.price) + FIRM_RESERVE:
						firm_step = "Dein einziger LKW ist mit dem Stadtbau beschäftigt. Prüfe, ob ein zweites Fahrzeug (%s, %s) für Kundenfracht lohnt: Firma {aktion: {action: \"buy_vehicle\", offer_id: \"%s\"}}. Danach Fahrer einstellen." % [offer.model, Catalog.money(float(offer.price)), offer.id]
						out.append(firm_step)
						break
		var st := settle.next_step(b, cid)
		if st != "":
			out.append(st)
			if firm_step == "":
				firm_step = st
		elif sim.neubeginn:
			var hs := homes.next_step(cid)
			if hs != "":
				out.append(hs)
				home_step = hs
				if firm_step == "":
					firm_step = hs
	if int(b.get("amt", -1)) < 0:
		var sug := estates.suggestion(str(b.name))
		if not sug.is_empty():
			var geld := float(b.get("geld", 0.0))
			var firm_cash: float = sim.company(cid).ledger.cash if cid >= 0 else 0.0
			if geld >= float(sug.kosten):
				out.append("Stammsitz ausbauen: Bauwerk {art: \"%s\", feld: %d} kostet etwa %s, du hast privat %s. Oder eigener Entwurf mit Bauplan." % [
					sug.art, int(sug.feld), Catalog.money(float(sug.kosten)), Catalog.money(geld)])
			elif firm_cash >= float(sug.kosten) + FIRM_RESERVE:
				out.append("Stammsitz ausbauen: Bauwerk {art: \"%s\", feld: %d, zahlung: \"firma\"} kostet etwa %s (Firmenkasse %s)." % [
					sug.art, int(sug.feld), Catalog.money(float(sug.kosten)), Catalog.money(firm_cash)])
	var g: Dictionary = b.get("ziel", {})
	if g.is_empty() or str(g.get("status", "")) != "aktiv":
		out.append("Setze dir ein Ziel: Ziel {ziel, warum, teilziele}. Grundziel: %s" % (GRUNDZIEL_AMT if int(b.get("amt", -1)) >= 0 else (GRUNDZIEL_WILDNIS if sim.wildnis and cid >= 0 else (GRUNDZIEL_FIRMA if cid >= 0 else GRUNDZIEL))))
		goal_step = str(out.back())
	else:
		if not g.has("stand_min"):
			g["stand_min"] = sim.game_min   # aeltere Ziele: ab jetzt messen
		var days: float = (float(sim.game_min) - float(g.stand_min)) / float(GameCalendar.days_to_min(1))
		if days >= GOAL_STALE_DAYS:
			out.append("Dein Ziel „%s“ steht seit %d Tagen bei %d %%. Melde Fortschritt (ZielStand), ändere den Weg oder ersetze es (Ziel {..., ersetzen: true})." % [
				str(g.ziel).left(60), int(days), int(g.get("fortschritt", 0))])
			goal_step = str(out.back())
	var hint := _contact_hint(b, cid)
	# Je ein akuter Bedarf, Firmenfortschritt und offene Antwort bleiben im knappen Kontext sichtbar.
	# Weitere Hinweise behalten ihre alte Reihenfolge; aktive Ziele sind in der Beobachtung zusaetzlich separat enthalten.
	var prioritized: Array = []
	for s in [urgent_step, growth_step, home_step, civic_step, firm_step, pending_step, plan_step, hint, goal_step]:
		if s != "" and s not in prioritized:
			prioritized.append(s)
	for s in out:
		if s not in prioritized:
			prioritized.append(s)
	return prioritized.slice(0, 3)


# ------------------------------------------------------------------ Koerperliche Arbeit (Wildnis, Benedikt 17.11.)
## Fahrzeug, das der Inhaber selbst faehrt (nur er, solange es keine Angestellten gibt).
func own_truck(cid: int) -> FleetVehicle:
	for wk in sim.personnel.employed(cid):
		if wk.role == "owner" and int(wk.vehicle_id) >= 0:
			return sim.vehicles.get(int(wk.vehicle_id))
	return null


func _truck_busy(v: FleetVehicle) -> bool:
	return v.state not in ["idle"] or not v.queue.is_empty() or str(v.contract_id) != "" or not v.stops.is_empty()


## LKW {ziel: "grosslager" | "hof" | [x, y]} – das Wesen faehrt selbst mit.
func _truck(b: Dictionary, data: Dictionary) -> Dictionary:
	var cid := active_firm(b)
	if cid < 0:
		return {"ok": false, "msg": "Du hast keine Firma und keinen LKW."}
	var v := own_truck(cid)
	if v == null:
		return {"ok": false, "msg": "Kein Fahrzeug, das du selbst fährst."}
	if _truck_busy(v):
		if v.state in ["broken", "to_workshop", "repairing"]:
			return {"ok": false, "msg": "Dein LKW #%d ist %s. Er wird automatisch abgeschleppt und repariert; warte auf Einsatzbereitschaft, dann entscheide neu." % [v.id, v.status_text()]}
		return {"ok": false, "msg": "Dein LKW ist gerade unterwegs (%s)." % v.state}
	var here := tile_of(b)
	if maxi(absi(here.x - v.tile().x), absi(here.y - v.tile().y)) > 3:
		var p: Array[Vector2i] = sim.nav.walk_path(here, v.tile())
		if p.is_empty():
			return {"ok": false, "msg": "Du kommst zu Fuß nicht zu deinem LKW (%s)." % str([v.tile().x, v.tile().y])}
		(b.mover as Mover).set_path(p)
		b["lkw_auftrag"] = data.duplicate()
		return {"ok": true, "status": "laeuft", "msg": "Du gehst zu deinem LKW bei %s und fährst dann los." % str([v.tile().x, v.tile().y])}
	b.erase("lkw_auftrag")
	var c = sim.company(cid)
	var ziel = data.get("ziel", "grosslager")
	# Modelle nennen oft die Koordinate des Grosslagers statt seines Namens. Eine Fahrt auf dessen Hof
	# soll dieselbe physische Warenannahme ausloesen wie LKW {ziel: "grosslager"}.
	if ziel is Array and (ziel as Array).size() >= 2 and not sim.city.hub.is_empty():
		var hr: Array = sim.city.hub.get("rect", [])
		if hr.size() >= 4 and Rect2i(int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3])).grow(4).has_point(Vector2i(int(ziel[0]), int(ziel[1]))):
			ziel = "grosslager"
	if ziel is Array and (ziel as Array).size() >= 2:
		var cell := Vector2i(int(ziel[0]), int(ziel[1]))
		if not sim.route(v, cell, "erkunden"):
			return {"ok": false, "msg": "Dorthin kommt der LKW nicht (Wasser, Berg oder kein Weg, auch nicht bis auf %d Felder heran). Wähle ein Ziel auf derselben Landseite – siedlung.beste_plaetze_in_der_naehe nennt nur erreichbare Plätze." % Simulation.SNAP_R}
		b["im_lkw"] = v.id
		var end: Vector2i = v.path[-1] if not v.path.is_empty() else cell
		var note := "" if end == cell else " Das Feld selbst ist nicht befahrbar (Baum, Gebäude, Wasser oder Hang) – du hältst am nächsten freien Feld %s." % str([end.x, end.y])
		if not c.depots.is_empty() and not homes.waiting_goods(cid).is_empty():
			var own_dep: Dictionary = sim.city.building(int(c.depots[0]))
			if not own_dep.is_empty() and Rect2i(int(own_dep.x), int(own_dep.y), int(own_dep.w), int(own_dep.h)).grow(16).has_point(cell):
				note += " Das ist dein Betriebshof, nicht das Großlager. Gekaufte Ware lädt nur LKW {ziel: \"grosslager\" am Großlager %s." % str(sim.city.hub.get("center", []))
		return {"ok": true, "status": "laeuft", "msg": "Du fährst mit deinem LKW nach %s (querfeldein langsamer als auf Straßen).%s" % [str(ziel), note]}
	var z := str(ziel).to_lower()
	if z in ["hof", "betriebshof", "heim", "basis"]:
		var dep: Dictionary = sim.city.building(int(c.depots[0]))
		if dep.is_empty() or not sim.route(v, dep.road, "erkunden"):
			return {"ok": false, "msg": "Kein Weg zu deinem Betriebshof."}
		b["im_lkw"] = v.id
		return {"ok": true, "status": "laeuft", "msg": "Du fährst zu deinem Betriebshof."}
	# Grosslager: gekaufte Ware abholen (eigene Abholauftraege), tanken
	sim.hub.reclaim_pickups(cid)
	var taken: Array = []
	for k in sim.contracts.values():
		if k.status == "open" and str(k.order_ref).begins_with("hub:") and int(k.exclusive_for) == cid:
			c.known[k.id] = true
			var r: Dictionary = sim.executor._accept_contract(cid, k.id, v.id)
			if bool(r.get("ok", false)):
				taken.append(k.id)
		elif k.status == "accepted" and int(k.owner) == cid and str(k.order_ref).begins_with("hub:") and int(k.vehicle_id) < 0:
			sim.executor._assign(cid, v.id, k.id)   # 18.11.: per accept_contract angenommene eigene Abholung (Viktor: "Nichts abzuholen")
			taken.append(k.id)
	var fuel_note := ""
	if c.fuel < 1500.0:
		var liters: float = 1500.0 - float(c.fuel)
		var cost := snappedf(liters * ResourceMarket.FUEL_BASE_PRICE, 0.01)
		if c.ledger.cash >= cost:
			c.ledger.book("fuel", -cost, true, "Tanken am Großlager (%d l)" % int(liters), sim.game_min)
			c.fuel = 1500.0
			fuel_note = " Am Großlager tankst du %d l nach (%s)." % [int(liters), Catalog.money(cost)]
	if taken.is_empty():
		var hub_b: Dictionary = sim.city.building(int(sim.city.hub.get("buildings", {}).get("hauptlager", -1)))
		if hub_b.is_empty() or not sim.route(v, hub_b.road, "erkunden"):
			return {"ok": false, "msg": "Kein Weg zum Großlager."}
		b["im_lkw"] = v.id
		return {"ok": true, "status": "laeuft", "msg": "Nichts abzuholen (erst hub_buy) – du fährst zum Großlager.%s" % fuel_note}
	b["im_lkw"] = v.id
	return {"ok": true, "status": "laeuft", "msg": "Du fährst mit deinem LKW zum Großlager, lädst %d Abholungen (%s) und bringst sie auf deinen Hof.%s" % [
		taken.size(), ", ".join(taken), fuel_note]}


## Rammen {fahrzeug: id} oder {gebaeude: id} bzw. {feld: [x, y]}: mit dem eigenen Lkw gezielt auffahren. Ziel und eigener Lkw
## werden beschaedigt, die Spannung zur betroffenen Firma steigt (Collisions.ram_hit). Normale Fahrten weichen immer aus.
func _ram(b: Dictionary, data: Dictionary) -> Dictionary:
	var cid := active_firm(b)
	var v := own_truck(cid) if cid >= 0 else null
	if v == null:
		return {"ok": false, "msg": "Du hast keinen eigenen Lkw zum Rammen."}
	if _truck_busy(v):
		return {"ok": false, "msg": "Dein Lkw ist gerade unterwegs (%s)." % v.state}
	if maxi(absi(tile_of(b).x - v.tile().x), absi(tile_of(b).y - v.tile().y)) > 3:
		return {"ok": false, "msg": "Steig erst in deinen Lkw (geh zu ihm: %s)." % str([v.tile().x, v.tile().y])}
	var target := Vector2i(-1, -1)
	var what := ""
	if data.has("fahrzeug") or data.has("vehicle_id"):
		var t: FleetVehicle = sim.vehicles.get(int(data.get("fahrzeug", data.get("vehicle_id", -1))))
		if t == null or t.owner == cid:
			return {"ok": false, "msg": "Kein fremdes Fahrzeug mit dieser Nummer."}
		v.ram = {"vehicle": t.id}
		target = t.tile()
		what = "%s von %s" % [t.display_name(), sim.company(t.owner).company_name]
	else:
		var bid := int(data.get("gebaeude", -1))
		var f = parse_tile(data.get("feld"))
		if bid < 0 and f != null:
			bid = int(sim.city.building_at[sim.city.idx(Vector2i(int(f[0]), int(f[1])))])
		var bd: Dictionary = sim.city.building(bid)
		if bd.is_empty():
			return {"ok": false, "msg": "Rammen braucht fahrzeug: id oder gebaeude: id bzw. feld: [x, y] eines Gebäudes."}
		if int(sim.depot_owner.get(bid, -1)) == cid:
			return {"ok": false, "msg": "Das ist dein eigenes Gebäude."}
		v.ram = {"building": bid}
		target = Vector2i(int(bd.walk.x), int(bd.walk.y))
		what = str(bd.name)
	if not sim.route(v, target, "erkunden"):
		v.ram = {}
		return {"ok": false, "msg": "Dorthin kommt dein Lkw nicht."}
	b["im_lkw"] = v.id
	_event(b, "fährt los, um %s zu rammen" % what)
	return {"ok": true, "status": "laeuft", "msg": "Du fährst los, um %s zu rammen. Dein Lkw wird dabei selbst beschädigt, und die betroffene Firma wird dir das übelnehmen." % what}


## Bauen {baustelle?} – das Wesen geht zur Baustelle und arbeitet dort, bis es etwas anderes tut ("stammsitz" = Bauwerke der Basis).
func _work(b: Dictionary, data: Dictionary) -> Dictionary:
	var cid := active_firm(b)
	var id := str(data.get("baustelle", data.get("id", "")))
	if id in ["stammsitz", "basis"]:
		if not estates.estates.has(str(b.name)):
			return {"ok": false, "msg": "Du hast noch keine Basis."}
		if not (estates.estates[b.name].bauten as Array).any(func(x): return x.status == "im_bau"):
			return {"ok": false, "msg": "An deiner Basis ist nichts im Bau – erst ein Bauwerk beauftragen (Bauwerk {art, feld})."}
		b["baut"] = "stammsitz"
		var p: Array[Vector2i] = sim.nav.walk_path(tile_of(b), estates.center_of(str(b.name)))
		if not p.is_empty():
			(b.mover as Mover).set_path(p)
		return {"ok": true, "status": "laeuft", "msg": "Du gehst zu deiner Basis und baust dort selbst."}
	if cid < 0:
		return {"ok": false, "msg": "Bauen geht auf Baustellen deiner Firma."}
	var s: Dictionary = homes.sites.get(id, {})
	if s.is_empty() and id != "" and not homes.open_sites(cid).is_empty():   # 19.11.: Greta "BS20" bekam stumm die Meldung zu BS16
		return {"ok": false, "msg": "Baustelle %s gibt es nicht. Deine Baustellen: %s." % [id, ", ".join(homes.open_sites(cid).map(func(x): return "%s (%s)" % [x.id, x.status]))]}
	if s.is_empty():
		var open: Array = homes.open_sites(cid).filter(func(x): return x.status == "bau")
		if open.is_empty():
			var mat: Array = homes.open_sites(cid).filter(func(x): return x.status == "material")
			if not mat.is_empty():
				return {"ok": false, "msg": "Baustelle %s wartet auf Material: %s – mit hub_buy kaufen und per Materialhubschrauber liefern lassen." % [mat[0].id, str(homes.missing(mat[0]))]}
			return {"ok": false, "msg": "Keine Baustelle bereit. Neue: haus_bauen, buergeramt_bauen, strasse_bauen."}
		s = open[0]
	if int(s.cid) != cid:
		return {"ok": false, "msg": "Baustelle %s gehört dir nicht." % id}
	if s.status == "material":
		return {"ok": false, "msg": "Baustelle %s wartet auf Material vom Hof: %s." % [s.id, str(homes.missing(s))]}
	if s.status != "bau":
		return {"ok": false, "msg": "Baustelle %s ist %s." % [s.id, s.status]}
	b["baut"] = str(s.id)
	var target := homes.work_cell(s)
	var p: Array[Vector2i] = sim.nav.walk_path(tile_of(b), target)
	if p.is_empty() and maxi(absi(tile_of(b).x - target.x), absi(tile_of(b).y - target.y)) > EkoHomes.NEAR:
		b.erase("baut")
		return {"ok": false, "msg": "Du erreichst Baustelle %s zu Fuß nicht. Setze Tagelöhner ein: Firma {aktion: {action: \"tageloehner\", baustelle: \"%s\", anzahl: 2}}." % [s.id, s.id]}
	if not p.is_empty():
		(b.mover as Mover).set_path(p)
	return {"ok": true, "status": "laeuft", "msg": "Du gehst zur Baustelle %s (%s) und arbeitest dort, bis du etwas anderes tust. Bauen kostet Akku." % [s.id, s.typ]}


## Je Takt: im LKW mitfahren und aussteigen, eine wartende Fahrt fortsetzen, der Arbeitsstelle nachgehen (Strasse Feld fuer Feld).
func _body_tick() -> void:
	for b in beings.values():
		var cid := int(b.get("firma", -1))
		if cid < 0:
			continue
		var v := own_truck(cid)
		if b.has("im_lkw"):
			var tv: FleetVehicle = sim.vehicles.get(int(b.im_lkw))
			if tv == null or not _truck_busy(tv) or tv.state in ["broken", "to_workshop", "repairing"]:
				b.erase("im_lkw")   # 18.11.: kaputter/abgeschleppter Lkw – aussteigen (Viktor sass 40 min im liegengebliebenen Wagen fest)
				if tv != null:   # neben der Kabine aussteigen, auf der dem Betrachter zugewandten Seite (sonst stuende die Figur sichtbar "auf" dem Wagen)
					var hd: Vector2 = tv.heading.normalized() if tv.heading.length() > 0.01 else Vector2.RIGHT
					var sd := Vector2(-hd.y, hd.x)
					if sd.x + sd.y < 0.0:
						sd = -sd
					var door: Vector2 = tv.pos + sd * 24.0 + hd * 12.0
					var dtile := CityData.to_tile(door)
					(b.mover as Mover).pos = door if dtile == tv.tile() or sim.city.walkable(dtile) else tv.pos
					(b.mover as Mover).set_path([] as Array[Vector2i])
				_event(b, "Du bist angekommen und steigst aus dem LKW.")
			else:
				(b.mover as Mover).pos = tv.pos
			continue
		if v != null and _truck_busy(v) and v.state not in ["broken", "repairing", "to_workshop"]:
			if b.has("fracht_auftrag"):
				b.erase("fracht_auftrag")
			b["im_lkw"] = v.id   # der Inhaber faehrt selbst: wer den LKW losschickt, sitzt drin
			(b.mover as Mover).pos = v.pos
			_event(b, "Du steigst in deinen LKW und fährst selbst.")
			continue
		# Ein nachtraeglich errichteter Bauhof kann die stehende Figur umschliessen.
		# Sie tritt ueber den kurzen Innenweg wieder hinaus, bevor eine neue Route geplant wird.
		var mover: Mover = b.mover
		if mover.arrived() and not sim._walk_free(tile_of(b)) and not b.has("baut"):
			var here: Vector2i = tile_of(b)
			var door: Vector2i = sim._free_near(here, 3)
			if door.x >= 0:
				var exit_path: Array[Vector2i] = [here, door]
				mover.set_path(exit_path)
				_event(b, "Du verlaesst das Gebaeude und gehst wieder nach draussen.")
				continue
		if b.has("fracht_auftrag") and mover.arrived() and v != null:
			var pending: Dictionary = b.fracht_auftrag
			var here: Vector2i = tile_of(b)
			if maxi(absi(here.x - v.tile().x), absi(here.y - v.tile().y)) <= 3:
				b.erase("fracht_auftrag")
				sim.executor.eko_call = true
				var result: Dictionary = sim.executor.execute(cid, pending, "", "api")
				sim.executor.eko_call = false
				_event(b, "Firma: %s → %s" % [str(pending.get("action", "")), str(result.get("msg", "")).left(100)])
			else:
				var route: Array[Vector2i] = sim.nav.walk_path(here, v.tile())
				if route.is_empty() or maxi(absi(route[-1].x - v.tile().x), absi(route[-1].y - v.tile().y)) > 3:
					b.erase("fracht_auftrag")
					_event(b, "Der Weg zum LKW ist nicht frei; der gewaehlte Auftrag wurde nicht angenommen.")
				else:
					mover.set_path(route)
			continue
		if b.has("lkw_auftrag") and (b.mover as Mover).arrived() and v != null:
			var r := _truck(b, b.lkw_auftrag)
			if not bool(r.get("ok", false)):
				b.erase("lkw_auftrag")
				_event(b, "LKW: %s" % str(r.msg).left(100))
		var sid := str(b.get("baut", ""))
		if sid != "" and sid != "stammsitz" and (b.mover as Mover).arrived():
			var s: Dictionary = homes.sites.get(sid, {})
			if s.is_empty() or s.status != "bau":
				continue
			var c := homes.work_cell(s)
			var t := tile_of(b)
			if maxi(absi(t.x - c.x), absi(t.y - c.y)) > EkoHomes.NEAR - 2:
				var p: Array[Vector2i] = sim.nav.walk_path(t, c)
				if not p.is_empty():
					(b.mover as Mover).set_path(p)


## Hoechstens einmal je Spieltag ohne Gespraech: ein konkreter Anlass, jemanden anzusprechen (17.11.: nach der Talk-Sperre redete
## niemand mehr). Buergermeister -> Unternehmer der eigenen Stadt (sonst irgendeiner), Unternehmer -> Buergermeister ihrer Stadt
## bzw. abwechselnd ein anderer Unternehmer (Kooperation).
func _contact_hint(b: Dictionary, cid: int) -> String:
	if float(sim.game_min) - float(b.get("kontakt_min", -1.0e9)) < GameCalendar.days_to_min(1):
		return ""
	var k := int(b.get("amt", -1))
	if k >= 0:
		var firms: Array = []
		for c in sim.companies:
			var n := firm_being(c.id)
			if n != "" and n != b.name:
				firms.append([n, c])
		if firms.is_empty():
			return ""
		firms.sort_custom(func(x, y): return int(sim.towns.home_of(x[1].id) == k) > int(sim.towns.home_of(y[1].id) == k))
		var M: Mayor = sim.towns.mayors[k]
		var prj := ""
		for p in M.projects.values():
			if str(p.status) in ["beschlossen", "ausgeschrieben", "beauftragt", "laufend"]:
				prj = " (z. B. %s %s, %s)" % [p.id, str(p.get("name", p.get("kind", ""))), p.status]
				break
		return "Kontakt: Sprich Unternehmer %s (%s) an – was braucht die Firma in %s, was plant die Stadt%s? Talk {to: \"%s\", text: ...}." % [
			firms[0][0], firms[0][1].company_name, sim.towns.name_of(k), prj, firms[0][0]]
	if cid < 0:
		return ""
	var town: int = sim.towns.home_of(cid)
	var mayor_name := ""
	for n in beings:
		if int(beings[n].get("amt", -1)) == town:
			mayor_name = str(n)
	var other: Array = []
	for c in sim.companies:
		var n := firm_being(c.id)
		if n != "" and n != b.name:
			other.append([n, c.id])
	var turn := int(float(sim.game_min) / GameCalendar.days_to_min(1)) % 2
	if mayor_name != "" and (turn == 0 or other.is_empty()):
		return "Kontakt: Bürgermeister %s (%s) – frag nach Bauprojekten, Anträgen oder Transporten der Stadt: Talk {to: \"%s\", text: ...}." % [
			mayor_name, sim.towns.name_of(town), mayor_name]
	if not other.is_empty():
		var o: Array = other[int(float(sim.game_min) / GameCalendar.days_to_min(1)) % other.size()]
		return "Kontakt: Unternehmer %s – Aufträge teilen, Fahrzeuge vermieten oder zusammenarbeiten: Talk {to: \"%s\", text: ...} oder Firma {aktion: {action: \"propose_cooperation\", to: %d}}." % [
			o[0], o[0], int(o[1])]
	return ""


## Fahrzeug ohne Fahrer -> Fahrer einsetzen; Fahrzeug frei -> besten machbaren gesammelten Auftrag annehmen (Partie 16.11.: Viktor
## sammelte zweimal 35 Auftraege, nahm aber keinen an). "" = nichts Dringendes.
## Der vorgeschlagene Auftrag wird fuer die Firma vorgemerkt (Partie 16.11.: Annahmen scheiterten meist an "nicht (mehr) verfuegbar",
## das Wesen braucht mehrere Schritte von der Beobachtung bis zur Handlung): etwa vier Takte des Wesens, wie AgentController._hold_market.
var _fleet_holds := {}   # Firma -> vorgemerkte Auftrags-ID


func _hold_for(cid: int, k, takt_min: float) -> void:
	var old = sim.contracts.get(str(_fleet_holds.get(cid, "")))
	if old != null and old != k and old.held_for == cid:
		old.held_for = -1
		old.held_until = 0.0
	k.held_for = cid
	k.held_until = minf(sim.game_min + clampf(takt_min * 4.0 + 30.0, 60.0, AgentController.HOLD_GAME_MIN), k.deadline - 30.0)
	_fleet_holds[cid] = k.id


func _fleet_step(cid: int, takt_min := 0.0) -> String:
	var c = sim.company(cid)
	if sim.wildnis and not sim.town_ready(c.home_town):
		return ""   # Ohne Stadt gibt es noch keine Kundenaufträge; die Lage zeigt stattdessen freie Gründungsplätze.
	var now: float = sim.game_min
	var coming := {}   # Fahrer unterwegs zum Fahrzeug (Aufgabe fahren erteilt, vehicle_id erst bei Ankunft) – nicht erneut einsetzen lassen
	for w in sim.personnel.employed(cid):
		var t = sim.personnel.tasks.get(str(w.task_id))
		if t != null and t.kind == "fahren" and t.status not in WorkerTask.FINAL:
			coming[int(t.target.get("vehicle_id", -1))] = true
	for v in sim.company_vehicles(cid):
		if sim.driver_of(v) == null and not coming.has(v.id):
			for w in sim.personnel.employed(cid):
				if w.role != "foreman" and str(w.task_id) == "" and int(w.vehicle_id) < 0:
					return "Fahrer einsetzen – Fahrzeug #%d steht ohne Fahrer: Firma {aktion: {action: \"assign_worker_task\", kind: \"fahren\", worker_id: \"%s\", vehicle_id: %d}}." % [v.id, w.id, v.id]
			return "Fahrzeug #%d hat keinen Fahrer und niemand ist frei: Firma {aktion: {action: \"recruit_worker\", worker_id: <id aus meine_firma.bewerber>}}." % v.id
	for v in sim.company_vehicles(cid):
		if v.state != "idle" or not v.queue.is_empty() or str(v.contract_id) != "":
			continue
		if sim.wildnis and sim.driver_of(v) != null and sim.driver_of(v).role == "owner" and not sim.operations.dispatch_policies.has(cid):
			return "Dein Gründer-LKW #%d ist frei. Du kannst eigene Fracht annehmen oder eine Dispositionsrichtlinie setzen; damit ist er zeitweise für Bau und Erkundung nicht verfügbar." % v.id
		var best = null
		var best_s := -1.0
		for k in sim.market.open_contracts():
			if not c.known.has(k.id) or k.held_by_other(cid, now) or (k.exclusive_for >= 0 and k.exclusive_for != cid and k.exclusive_until > now):
				continue
			if sim.executor._too_late(cid, k, v.id) != "":
				continue
			var s := (float(k.reward) + float(k.bonus)) / float(k.distance + 30)
			if s > best_s:
				best_s = s
				best = k
		if best != null:
			_hold_for(cid, best, takt_min)
			return "Auftrag annehmen (für dich vorgemerkt) – Fahrzeug #%d ist frei: Firma {aktion: {action: \"accept_contract\", contract_id: \"%s\", vehicle_id: %d}} (%s, %s, Frist %d min). Aufträge sind schnell weg." % [
				v.id, best.id, v.id, str(best.cargo_name()), Catalog.money(float(best.reward)), int(best.deadline - now)]
		return "Fahrzeug #%d ist frei, aber kein gesammelter Auftrag passt: Firma {aktion: {action: \"collect_contracts\"}}." % v.id
	return ""


func _set_goal(b: Dictionary, data: Dictionary) -> Dictionary:
	var text := str(data.get("ziel", "")).strip_edges().left(160)
	var why := str(data.get("warum", "")).strip_edges().left(200)
	if text == "" or why == "":
		return {"ok": false, "msg": "Ziel braucht ziel und warum (Begründung)."}
	var cid := active_firm(b)
	if cid >= 0 and sim.wildnis and settle.founded(sim.companies[cid].home_town) and _is_founding_goal(text):
		return {"ok": false, "msg": "Du hast bereits die Stadt %s gegründet. Baue und versorge sie weiter, statt eine zweite Stadt zu gründen." % sim.towns.name_of(sim.companies[cid].home_town)}
	var cur: Dictionary = b.get("ziel", {})
	if str(cur.get("status", "")) == "aktiv" and not bool(data.get("ersetzen", false)):
		return {"ok": false, "msg": "Du verfolgst schon das Ziel „%s“. Melde Fortschritt mit ZielStand oder ersetze es bewusst mit ersetzen: true." % cur.ziel}
	if not cur.is_empty():
		var old: Array = b.get("ziele_alt", [])
		cur["status"] = "ersetzt" if str(cur.status) == "aktiv" else cur.status
		old.append(cur)
		b["ziele_alt"] = old.slice(-5)
	var subs: Array = []
	for s in (data.get("teilziele", []) as Array if data.get("teilziele", []) is Array else []).slice(0, 8):
		subs.append({"text": str(s).left(100), "erledigt": false})
	b["ziel"] = {"ziel": text, "warum": why, "teilziele": subs, "nutzen": str(data.get("nutzen", "")).left(120),
		"ressourcen": str(data.get("ressourcen", "")).left(120), "erwartung": str(data.get("erwartung", "")).left(120),
		"abbruch": str(data.get("abbruch", "")).left(120), "status": "aktiv", "fortschritt": 0, "seit": Catalog.game_minutes_to_text(sim.game_min),
		"stand_min": sim.game_min, "projekt": str(data.get("projekt", ""))}
	_event(b, "setzt sich ein Ziel: %s" % text)
	sim.log_event("%s setzt sich ein Ziel: %s (%s)" % [b.name, text, why.left(80)], "info")
	return {"ok": true, "msg": "Neues Ziel: %s" % text, "ziel": b.ziel}


func _goal_progress(b: Dictionary, data: Dictionary) -> Dictionary:
	var g: Dictionary = b.get("ziel", {})
	if g.is_empty():
		return {"ok": false, "msg": "Du hast kein Ziel. Setze eines mit Ziel {ziel, warum, ...}."}
	_project_goal_sync(b)
	if str(g.get("projekt", "")) != "" and str(g.get("status", "")) == "aktiv" and data.has("fortschritt"):
		return {"ok": false, "msg": "Projektziel %s: Der Fortschritt kommt aus dem tatsächlichen Bauzustand. Prüfe das Projekt im Amt." % str(g.projekt)}
	if data.has("fortschritt"):
		if clampi(int(data.fortschritt), 0, 100) > int(g.get("fortschritt", 0)):
			g["stand_min"] = sim.game_min   # echter Fortschritt: Stillstandsuhr neu
		g.fortschritt = clampi(int(data.fortschritt), 0, 100)
	if data.has("teilziel_erledigt"):
		var i := int(data.teilziel_erledigt)
		if i >= 0 and i < (g.teilziele as Array).size():
			g.teilziele[i].erledigt = true
	var st := str(data.get("status", g.status))
	if st not in GOAL_STATES:
		return {"ok": false, "msg": "status muss aktiv, erreicht oder aufgegeben sein."}
	if st == "erreicht" and str(g.get("projekt", "")) != "" and str(sim.towns.project(str(g.projekt)).get("status", "")) != "fertig":
		return {"ok": false, "msg": "Projekt %s ist noch nicht fertig; erst nach der Bauabnahme ist das Ziel erreicht." % str(g.projekt)}
	if st != str(g.status):
		g.status = st
		_event(b, "Ziel %s: %s" % [st, g.ziel])
		sim.log_event("%s: Ziel %s – %s%s" % [b.name, st, g.ziel, (" (%s)" % str(data.get("notiz", "")).left(80)) if str(data.get("notiz", "")) != "" else ""], "good" if st == "erreicht" else "info")
	if str(data.get("notiz", "")) != "":
		g["notiz"] = str(data.notiz).left(160)
	return {"ok": true, "msg": "Ziel: %s (%s, %d %%)" % [g.ziel, g.status, int(g.fortschritt)], "ziel": g}


## Erkenntnis anzeigen (das Gedaechtnis selbst liegt in den Dateien des Wesens): Art und Text fuer Anzeige und Protokoll.
const LESSON_KINDS := ["tatsache", "vermutung", "technik", "fehlschlag", "strategie", "korrektur"]


func _lesson(b: Dictionary, data: Dictionary) -> Dictionary:
	var kind := str(data.get("art", "tatsache"))
	var text := str(data.get("text", "")).strip_edges().left(160)
	if kind not in LESSON_KINDS or text == "":
		return {"ok": false, "msg": "Merke braucht art (%s) und text." % ", ".join(LESSON_KINDS)}
	b["erkenntnis"] = {"art": kind, "text": text, "ms": Time.get_ticks_msec()}
	_event(b, "lernt (%s): %s" % [kind, text])
	return {"ok": true, "msg": "gemerkt"}


## Fahrdienst: schnell ans Ziel (Feld oder Name eines Gebaeudes, Wesens, Unternehmers), 1 EUR je Feld. Das Geld bekommt die
## Transportfirma mit den meisten Fahrzeugen (sonst die Stadt). Auch mit fast leerem Akku moeglich (nach Hause fahren).
func _ride(b: Dictionary, data: Dictionary) -> Dictionary:
	var to := Vector2i(-1, -1)
	var t = data.get("tile", data.get("feld"))
	if t is Array and t.size() >= 2:
		to = Vector2i(int(t[0]), int(t[1]))
	else:
		var name := str(data.get("ziel", data.get("to", "")))
		if beings.has(name):
			to = tile_of(beings[name])
		for c in sim.companies:
			if to.x < 0 and (c.player_name == name or c.company_name == name):
				to = sim.avatars[c.id].tile()
		for bd in sim.city.buildings:
			if to.x < 0 and str(bd.get("name", "")) == name:
				to = Vector2i(int(bd.walk.x), int(bd.walk.y))
		var low := _plain(name)
		for k in sim.towns.count():   # 19.11.: Viktor "Möwenfels" – Stadtname: zum Buergeramt, sonst zur Ortsmitte
			if to.x < 0 and low != "" and _plain(sim.towns.name_of(k)) == low:
				var hall: Dictionary = sim.city.building(int(sim.city.towns[k].get("town_hall", -1))) if k < sim.city.towns.size() else {}
				to = Vector2i(int(hall.walk.x), int(hall.walk.y)) if not hall.is_empty() else sim.towns.get_t(k).center
		for bd in sim.city.buildings:   # 19.11.: Greta "Großlager" statt "Großlager – Hauptlager" – Namensanfang genuegt
			if to.x < 0 and low.length() >= 4 and _plain(str(bd.get("name", ""))).begins_with(low):
				to = Vector2i(int(bd.walk.x), int(bd.walk.y))
	if to.x < 0 or not sim.city.inside(to):
		return {"ok": false, "msg": "Fahrt braucht tile: [x, y] oder ziel: Name eines Gebäudes, Wesens oder Unternehmers."}
	var m: Mover = b.mover
	var p: Array[Vector2i] = sim.nav.walk_path(m.tile(), to)
	if p.size() < 2:
		return {"ok": false, "msg": "Dorthin kommt kein Fahrdienst."}
	var cost: float = maxf(TAXI_MIN, float(p.size() - 1) * TAXI_EUR_PER_FIELD)
	if float(b.get("geld", 0.0)) < cost:
		return {"ok": false, "msg": "Die Fahrt (%d Felder) kostet %s, du hast %s." % [p.size() - 1, Catalog.money(cost), Catalog.money(float(b.get("geld", 0.0)))]}
	var firm = null
	for c in sim.companies:
		if c.is_active() and not c.vehicle_ids.is_empty() and (firm == null or c.vehicle_ids.size() > firm.vehicle_ids.size()):
			firm = c
	b.geld = float(b.geld) - cost
	if firm != null:
		firm.ledger.book("transport", cost, true, "Fahrdienst für %s" % b.name, sim.game_min, "Y0")
	else:
		sim.economy.transfer("Y0", Towns.account_of(maxi(0, sim.city.town_of(m.tile()))), cost)
	m.set_path(p)
	b["faehrt"] = true
	var end: Vector2i = p[-1]
	_event(b, "fährt mit dem Fahrdienst nach %d,%d" % [end.x, end.y])
	return {"ok": true, "status": "laeuft", "msg": "Fahrdienst%s bringt dich nach %d,%d (%d Felder, ca. %.0f s, %s)%s." % [
		(" von " + firm.company_name) if firm != null else "", end.x, end.y, p.size() - 1, float(p.size() - 1) / (WALK_SPEED * TAXI_SPEED),
		Catalog.money(cost), "" if end == to else "; Ziel nicht erreichbar, nächster Punkt"]}


## Feldangabe tolerant lesen: [x, y], "x,y" / "x y" oder {x, y} (Partie 16.11.: MoveTo mit target_id "331,257" scheiterte).
static func parse_tile(t) -> Variant:
	if t is Array and t.size() >= 2:
		return [int(t[0]), int(t[1])]
	if t is Dictionary and t.has("x") and t.has("y"):
		return [int(t.x), int(t.y)]
	if t is String:
		var parts := (t as String).replace("[", "").replace("]", "").replace(";", ",").replace(" ", ",").split(",", false)
		if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return [int(parts[0]), int(parts[1])]
	return null


func _move_to(b: Dictionary, data: Dictionary) -> Dictionary:
	var t = parse_tile(data.get("tile", data.get("feld", data.get("target_id", data.get("ziel")))))
	if t == null:
		return {"ok": false, "msg": "MoveTo braucht tile: [x, y] (Feldkoordinaten)."}
	var to := Vector2i(int(t[0]), int(t[1]))
	if not sim.city.inside(to):
		return {"ok": false, "msg": "Feld %d,%d liegt ausserhalb der Karte (0..%d)." % [to.x, to.y, sim.city.size - 1]}
	var m: Mover = b.mover
	var p: Array[Vector2i] = sim.nav.walk_path(m.tile(), to)
	if p.is_empty():
		return {"ok": false, "msg": "Kein Fussweg zu %d,%d." % [to.x, to.y]}
	m.set_path(p)
	b["faehrt"] = false
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
	if not PRICES.has(mat):
		return {"ok": false, "msg": "Material muss eines von %s sein." % ", ".join(PRICES.keys())}
	if not _at_source(b):
		return {"ok": false, "msg": "Material gibt es nur am Bauhof.%s" % _source_hint(b)}
	var n := clampi(int(data.get("count", 1)), 1, CARRY - held.size())
	if held.size() >= CARRY:
		return {"ok": false, "msg": "Haende voll (%d Bloecke)." % CARRY}
	var j: Dictionary = jobs.get(str(b.get("job", "")), {})
	var paid_by_firm: bool = not j.is_empty() and j.art == "mauer" and j.material == mat
	var cost := 0.0 if paid_by_firm else float(PRICES[mat]) * n
	var item := str(TRADER_ITEM.get(mat, ""))   # Baustoff mit echtem Bestand am Bauhof?
	var T: Trader = sim.trader
	var at_trader: bool = item != "" and T.bauhof >= 0 and _dist(tile_of(b), sim.city.building(T.bauhof).walk) <= SOURCE_REACH + 1
	if at_trader and not paid_by_firm:
		var per_block := T.price(item, n) / float(BLOCKS_PER_UNIT.get(mat, 1))
		cost = snappedf(per_block * n, 0.01)
		if T.stock_of(item) < 1:
			return {"ok": false, "msg": "Der Bauhof hat gerade kein %s auf Lager (es wird hergestellt oder importiert). Versuch es später oder nimm ein anderes Material." % mat}
	if cost > float(b.get("geld", 0.0)):
		return {"ok": false, "msg": "%d x %s kosten %s, du hast %s." % [n, mat, Catalog.money(cost), Catalog.money(float(b.get("geld", 0.0)))]}
	if at_trader and T.stock_of(item) >= 1:   # Bestand verbrauchen (1 Einheit reicht fuer BLOCKS_PER_UNIT Bloecke)
		sim.stock.consume(item, maxi(1, ceili(float(n) / float(BLOCKS_PER_UNIT.get(mat, 1)))), "T0", T.bauhof, "Verkauf an %s" % b.name, sim.game_min)
	if cost > 0.0:
		sim.economy.transfer("Y0", "T0", cost)
		b.geld = float(b.geld) - cost
	for i in n:
		held.append(mat)
	_event(b, "holt %d x %s am Bauhof%s" % [n, mat, " (Material der Firma)" if paid_by_firm else " für %s" % Catalog.money(cost)])
	return {"ok": true, "msg": "%d x %s aufgenommen%s" % [n, mat, " (stellt die Firma)" if paid_by_firm else ", %s bezahlt" % Catalog.money(cost)], "traegt": held}


func _place(b: Dictionary, data: Dictionary) -> Dictionary:
	var held: Array = b.held
	var p = _vec(data.get("block"))
	if p == null:
		return {"ok": false, "msg": "Place braucht block: [x, y, z] (Blockraster: Feld x %d + 0..%d, z = Schicht ab 0)." % [PER_TILE, PER_TILE - 1]}
	if held.is_empty():
		return {"ok": false, "msg": "Du traegst nichts. Erst Material am Bauhof holen (Pickup)."}
	var mat := str(data.get("material", held.filter(func(m): return PRICES.has(m)).front() if held.any(func(m): return PRICES.has(m)) else held[0]))
	if mat not in held:
		return {"ok": false, "msg": "Du traegst kein %s (traegst: %s)." % [mat, ", ".join(held)]}
	if not PRICES.has(mat):
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
	if sim.city.g(tile) == CityData.G.RAIL or (sim.rail != null and sim.rail.is_rail(tile)):
		return "Feld %d,%d ist ein Gleis – dort fährt die Bahn." % [tile.x, tile.y]
	if sim.access != null and sim.access.reserved(tile):
		return "Feld %d,%d gehört zu einer geplanten Straße oder Autobahn (Trasse freihalten)." % [tile.x, tile.y]
	if int(sim.city.building_at[sim.city.idx(tile)]) >= 0:
		return "Auf Feld %d,%d steht ein Gebaeude." % [tile.x, tile.y]
	if not sim.city.height.is_empty() and sim.city.height[sim.city.idx(tile)] > 0:
		ensure_terrain()
		if height_at(tile) > Terrain.CLIMB_MAX or Terrain.steepness(sim.city, relief, tile) > Terrain.FLAT_MAX:
			return "Feld %d,%d ist zu steil oder zu hoch zum Bauen (nur Hochebenen und sanfte Hänge)." % [tile.x, tile.y]
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
	var own := active_firm(b)
	if to == str(b.name) or (own >= 0 and to in [str(sim.company(own).player_name), str(sim.company(own).company_name)]):
		return {"ok": false, "msg": "Das bist du selbst bzw. deine eigene Firma – die Lage deiner Firma steht in meine_firma, Entscheidungen triffst du mit Firma {aktion}."}
	var t := tile_of(b)
	if beings.has(to) and to != b.name:
		# Gleiche Person erneut, bevor sie geantwortet hat (Partie 16.11.: dieselbe Preisfrage dreimal in 25 s, das andere Wesen denkt noch)
		var last: Dictionary = b.get("talk_last", {})
		if str(last.get("to", "")) == to and int(last.get("inbox", -1)) == int(b.get("inbox", 0)) \
				and Time.get_ticks_msec() - int(last.get("ms", 0)) < TALK_REPEAT_MS:
			return {"ok": false, "msg": "Du hast %s gerade schon angesprochen, %s hat noch nicht geantwortet. Warte auf die Antwort (wait mit bis: \"antwort\") oder tu inzwischen etwas anderes." % [to, to]}
		b["talk_last"] = {"to": to, "ms": Time.get_ticks_msec(), "inbox": int(b.get("inbox", 0))}
	b.say = text
	b.say_left = SAY_SECONDS
	b["kontakt_min"] = float(sim.game_min)
	if str(b.get("offen", {}).get("von", "")) == to:
		b.erase("offen")   # beantwortet
	if beings.has(to) and to != b.name:
		var o: Dictionary = beings[to]
		o["inbox"] = int(o.get("inbox", 0)) + 1   # Zaehler fuer wait bis=antwort und die Wiederholungssperre
		o["offen"] = {"von": str(b.name), "text": text, "min": float(sim.game_min)}   # naechste_schritte: "Antworten"
		if _dist(t, tile_of(o)) > TALK_REACH:   # zu weit fuer ein Gespraech: Anruf (Partie 15.11.: 44 gescheiterte Gespraeche)
			_chat(b.name, to, "(Anruf) " + text, t)
			_event(o, "%s ruft dich an: %s" % [b.name, text])
			return {"ok": true, "msg": "%s ist weit weg – du hast angerufen; %s hat es gehört und kann antworten. Ihr könnt per Anruf weiterreden (Talk), dafür müsst ihr euch nicht treffen." % [to, to]}
		_chat(b.name, to, text, t)
		_event(o, "%s sagt zu dir: %s" % [b.name, text])
		return {"ok": true, "msg": "%s hat es gehoert und kann antworten." % to}
	for c in sim.companies:
		if str(c.player_name) == to or str(c.company_name) == to:
			var at: Vector2i = sim.avatars[c.id].tile()
			var phone := _dist(t, at) > TALK_REACH   # weit weg: Anruf statt Gespraech
			_chat(b.name, str(c.player_name), ("(Anruf) " if phone else "") + text, t)
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
		# an mich gerichtet (auch Anrufe aus der Ferne – 17.11.: kamen sonst nur als Ereignis an, niemand antwortete) oder in Hoerweite
		if str(m.von) != name and (str(m.get("an", "")) == name or m.has("feld") and _dist(t, Vector2i(int(m.feld[0]), int(m.feld[1]))) <= HEAR_RADIUS):
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
	_mark_visit(b)
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
				_discover(b, bd)
			elif not sim.city.height.is_empty() and sim.city.height[sim.city.idx(c)] > 0:
				row += "h" if Terrain.climbable(sim.city, relief, c) else "^"
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
		"du": {"name": name, "feld": [t.x, t.y], "unterwegs": not m.arrived() or b.has("im_lkw"), "im_lkw": b.has("im_lkw"),   # 17.11.: im LKW galt man als angekommen - wait bis ankunft kehrte sofort zurueck
			"ziel": [m.goal.x, m.goal.y] if not m.arrived() else null,
			"traegt": b.held, "tragkraft": CARRY, "am_bauhof": _at_source(b), "nachrichten": int(b.get("inbox", 0))},
		"naechste_schritte": next_steps(b),
		"dringlichkeit": urgency(b),
		"stadtwachstum": city_growth_status(int(b.get("amt", -1)) if int(b.get("amt", -1)) >= 0 else (sim.company(active_firm(b)).home_town if active_firm(b) >= 0 else -1)) if sim.wildnis else {},
		"zeit": Catalog.game_minutes_to_text(sim.game_min), "wetter": sim.wx.headline(),
		"karte": {"mitte": [t.x, t.y], "radius": VIEW_RADIUS, "zeilen": rows,
			"legende": "@ du, . freier Boden, = Strasse, # Gebaeude, ~ Wasser, h begehbarer Hang/Hochebene am Berg, ^ unbegehbar (Baum, Fels, Grat), 1-9/+ hoechste Blockschicht auf dem Feld"},
		"gelaende": {"deine_hoehe": int(height_at(t)), "hinweis": "Am Berg kannst du auf h-Feldern laufen; bauen geht dort, wo es flach ist. Je höher, desto mühsamer der Weg – und desto weiter die Aussicht."},
		"bloecke_in_der_naehe": near_blocks, "bloecke_gesamt": blocks.size(),
		"gebaeude_in_der_naehe": near_buildings, "quellen": src, "material_preise": PRICES,
		"andere_wesen": others, "figuren_in_der_naehe": figures, "gehoert": heard(name),
		"jobangebote": _job_obs(b) if active_firm(b) < 0 and int(b.get("amt", -1)) < 0 else [], "mein_auftrag": jobs.get(str(b.get("job", "")), {}).duplicate(),
		"lebensziel": _home_obs(b), "meine_firma": firm_obs(b), "mein_amt": office_obs(b), "gefuehle": feelings(b),
		"ablauf": {"offen": (b.get("ablauf", []) as Array).size(), "letzte_ergebnisse": (b.get("ablauf_log", []) as Array).slice(-5)},
		"grundziel": GRUNDZIEL_AMT if int(b.get("amt", -1)) >= 0 else (GRUNDZIEL_WILDNIS if sim.wildnis and int(b.get("firma", -1)) >= 0 else (GRUNDZIEL_FIRMA if int(b.get("firma", -1)) >= 0 else (GRUNDZIEL if estates.estates.has(name) else ""))), "mein_ziel": b.get("ziel", {}), "letzte_entscheidung": b.get("entscheidung", {}), "erkundung": _exploration_obs(b),
		"koerper": arms.body_obs(b), "gefahren": arms.dangers(b),
		"mein_stammsitz": estates.obs(b), "stammsitze_in_sicht": estates.visible(b),
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
			if not c.is_active() or c.ledger.cash < JOB_MIN_CASH or c.depots.is_empty() or firm_being(c.id) != "":
				continue   # Firmen von Wesen schreiben keine Hilfsjobs aus (Lumo bezahlte sich sonst aus der eigenen Kasse, 15.11.)
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


func _new_job(c, art := "", lohn := -1.0) -> Dictionary:
	var depot: Dictionary = sim.city.building(int(c.depots[0]))
	var home: Vector2i = depot.walk
	var town: int = sim.city.town_of(home)
	var j := {"id": "J%d" % _next_job, "cid": c.id, "firma": c.company_name, "person": c.player_name, "status": "offen",
		"rest_s": JOB_OPEN_S, "by": "", "von": [home.x, home.y], "von_name": str(depot.name)}
	if art == "botengang" or (art == "" and sim.rng.randf() < 0.6):
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
	if lohn > 0.0:
		j.lohn = lohn   # von der Firma selbst festgelegt
		j["selbst_ausgeschrieben"] = true
	jobs[j.id] = j
	_next_job += 1
	return j


## Freie, bebaubare Felder (w x h) in der Naehe eines Punktes, [x, y, w, h] oder [].
func _free_area_near(p: Vector2i, w: int, h: int) -> Array:
	var used := {}   # Felder mit Bloecken (fruehere Mauern verwirrten das Modell, 15.11.)
	for q in blocks:
		used[Vector2i(floori(float(q.x) / PER_TILE), floori(float(q.y) / PER_TILE))] = true
	for j in jobs.values():   # offene Mauerbereiche anderer Auftraege freihalten
		if j.get("art", "") == "mauer" and j.status in ["offen", "angenommen"]:
			for yy in int(j.bereich[3]):
				for xx in int(j.bereich[2]):
					used[Vector2i(int(j.bereich[0]) + xx, int(j.bereich[1]) + yy)] = true
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var o := p + Vector2i(dx, dy)
				var ok := true
				for yy in h:
					for xx in w:
						var t := o + Vector2i(xx, yy)
						if used.has(t) or not sim.city.walkable(t) or can_place(Vector3i(t.x * PER_TILE, t.y * PER_TILE, 0)) != "":
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
	if int(j.cid) == int(b.get("firma", -1)):
		return {"ok": false, "msg": "%s ist ein Auftrag deiner eigenen Firma." % id}
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
			var free_spots: Array = []
			for yy in int(a[3]) * PER_TILE:
				for xx in int(a[2]) * PER_TILE:
					var q := Vector3i(int(a[0]) * PER_TILE + xx, int(a[1]) * PER_TILE + yy, 0)
					while blocks.has(q):
						q.z += 1
					if free_spots.size() < 3 and can_place(q) == "":
						free_spots.append([q.x, q.y, q.z])
			var carried: int = b.held.count(str(j.material))
			var src: Array = sources()[0].feld if not sources().is_empty() else [0, 0]
			var hint := "Du trägst %d davon – setze sie" % carried if carried > 0 else "Du trägst keine – hol %d %s am Bauhof (Feld %d,%d, für diesen Auftrag gratis) und setze sie" % [int(j.menge) - n, j.material, src[0], src[1]]
			return {"ok": false, "msg": "Erst %d von %d Blöcken %s im Bereich gesetzt, es fehlen %d. %s, z. B. bei %s. Bereits gesetzte Blöcke nicht wieder aufnehmen." % [
				n, j.menge, j.material, int(j.menge) - n, hint, str(free_spots)]}
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


## Erreichbar: ein Rand- oder Innenfeld des Grundstuecks hat einen Fussweg zum Wesen.
func _plot_reachable(r: Rect2i, from: Vector2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var c := Vector2i(x, y)
			if sim.city.inside(c) and not sim.nav.walk.is_point_solid(c) and sim.nav.walk_reachable(from, c):
				return true
	return false


## Zwischengespeichert je Wesen (Grobfeld, 120 Spielminuten): je Grundstueck eine Wegsuche – 18.11. kostete das ~315 ms je Beobachtung.
func _plot_obs(b: Dictionary) -> Array:
	var t := tile_of(b)
	var pk := "%d,%d" % [t.x / 8, t.y / 8]
	var pc: Dictionary = b.get("_plot_cache", {})
	if str(pc.get("k", "")) == pk and float(sim.game_min) - float(pc.get("t", -1e9)) < 120.0:
		return pc.r
	var res := _plot_obs_raw(b, t)
	b["_plot_cache"] = {"k": pk, "t": float(sim.game_min), "r": res}
	return res


func _plot_obs_raw(b: Dictionary, t: Vector2i) -> Array:
	if sim.wildnis and active_firm(b) >= 0:
		return []   # Unternehmer in der Wildnis bauen ihre Basis selbst (Siedlung), sie kaufen keine Wohngrundstuecke
	var town: int = sim.city.town_of(t)
	var cands: Array = []
	for p in sim.parcels.search({"town": town, "zone": "wohnen", "max_area": 40, "limit": 40}):
		var r: Array = p.rect
		if int(r[2]) < 2 or int(r[3]) < 2:
			continue
		var c := Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) / 2)
		cands.append([_dist(t, c), p, c])
	cands.sort_custom(func(a, c): return int(a[0]) < int(c[0]))
	var out: Array = []
	for i in mini(cands.size(), 8):   # naechste zuerst, hoechstens 8 Wegsuchen
		var p: Dictionary = cands[i][1]
		var r: Array = p.rect
		var c: Vector2i = cands[i][2]
		if not _plot_reachable(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])), t):
			continue   # Insel zwischen gesperrten Feldern: nicht anbieten
		out.append({"id": p.id, "feld": [c.x, c.y], "groesse": "%dx%d Felder" % [r[2], r[3]], "preis": float(p.price),
			"entfernung": int(cands[i][0])})
		if out.size() >= 5:
			break
	return out


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
		var how := "Entnimm Geld aus deiner Firma (Firma {aktion: {action: entnahme, betrag}})." if int(b.get("firma", -1)) >= 0 else "Arbeite für die Firmen (jobangebote)."
		return {"ok": false, "msg": "Zu teuer: %s kostet %s, du hast %s. %s" % [id, Catalog.money(price), Catalog.money(float(b.get("geld", 0.0))), how]}
	var town: int = sim.towns.of_parcel(id) if sim.towns.is_region() else 0
	sim.economy.transfer("Y0", Towns.account_of(town), price)
	b.geld = float(b.geld) - price
	p.owner = "Y0"
	p.state = "privat_gehalten"
	p["bewohner"] = b.name
	sim.parcels.touch(id)
	b.grundstueck = id
	open_plot(id)
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
	var own_firm := bool(data.get("eigene_firma", false)) and active_firm(b) >= 0
	var price := HOUSE_PRICE * (0.4 if own_firm else 1.0)   # eigene Leute: nur Material
	if float(b.get("geld", 0.0)) < price:
		return {"ok": false, "msg": "Das kostet %s, du hast %s." % [Catalog.money(price), Catalog.money(float(b.get("geld", 0.0)))]}
	var wall := str(data.get("wand", "ziegel"))
	if wall not in ["ziegel", "holz", "stein", "beton"]:
		wall = "ziegel"
	sim.economy.transfer("Y0", "T0" if own_firm else "K0", price)
	b.geld = float(b.geld) - price
	var builder := "Baufirma"
	for t in sim.crews.crews.values():
		builder = str(t.name).split(" Trupp")[0]
		break
	if own_firm:
		builder = "Leute von %s" % sim.company(int(b.firma)).company_name
	houses[b.name] = {"plot": p.id, "origin": [origin.x, origin.y], "blocks": house_plan(origin, wall), "placed": 0, "status": "im_bau",
		"builder": builder, "acc": 0.0, "wand": wall}
	_event(b, "beauftragt %s mit dem Bau seines Hauses (%s)" % [builder, Catalog.money(price)])
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
	if not h.is_empty() and h.status == "fertig" and home_rect(b.name).has_point(tile_of(b)):
		return true
	if estates.at_home(b):
		return true
	var hall := town_hall_of(b)   # Buergermeister: im Rathaus zu Hause
	if not hall.is_empty() and _building_dist(tile_of(b), hall) <= SOURCE_REACH:
		return true
	return str(b.get("zuhause", "")) != "" and plot_rect(str(b.zuhause)).has_point(tile_of(b))


func plot_rect(id: String) -> Rect2i:
	var p: Dictionary = sim.parcels.parcel(id)
	if p.is_empty():
		return Rect2i()
	return Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))


## Bloecke auf einem Grundstueck: {bau: Bausteine ohne Einrichtung, max_z, einrichtung: {Art: Anzahl}}.
func plot_stats(id: String) -> Dictionary:
	var r := plot_rect(id)
	var out := {"bau": 0, "max_z": -1, "einrichtung": {}}
	for p in blocks:
		var t := Vector2i(floori(float(p.x) / PER_TILE), floori(float(p.y) / PER_TILE))
		if not r.has_point(t):
			continue
		var m := str(blocks[p])
		if FreeBuild.MATERIALS.has(m) or m in ["dach", "boden"]:
			out.bau = int(out.bau) + 1
		else:
			out.einrichtung[m] = int(out.einrichtung.get(m, 0)) + 1
		out.max_z = maxi(int(out.max_z), p.z)
	return out


## Selbst gebautes Haus beziehen: eigenes Grundstueck mit genug Bausteinen, Hoehe, Bett und Ladestation.
func _move_in(b: Dictionary) -> Dictionary:
	var h: Dictionary = houses.get(b.name, {})
	if not h.is_empty():
		return {"ok": h.status == "fertig", "msg": "Du wohnst schon in deinem Haus (gebaut von %s) – geh einfach hinein." % h.builder if h.status == "fertig" else "Dein Haus wird noch gebaut (%s)." % h.status}
	var id := str(b.get("grundstueck", ""))
	if id == "":
		return {"ok": false, "msg": "Erst ein Grundstück kaufen (BuyPlot), dann darauf bauen."}
	var st := plot_stats(id)
	var miss: Array = []
	if int(st.bau) < MOVE_IN_BLOCKS:
		miss.append("%d von %d Bausteinen" % [st.bau, MOVE_IN_BLOCKS])
	if int(st.max_z) + 1 < MOVE_IN_HEIGHT:
		miss.append("Höhe %d von %d Schichten" % [int(st.max_z) + 1, MOVE_IN_HEIGHT])
	for need in ["bett", "ladestation"]:
		if not st.einrichtung.has(need):
			miss.append("ein %s" % need)
	if not miss.is_empty():
		return {"ok": false, "msg": "Noch nicht bewohnbar: es fehlen %s." % ", ".join(miss)}
	if str(b.get("zuhause", "")) == "":
		var p: Dictionary = sim.parcels.parcel(id)
		p.state = "bebaut"
		sim.parcels.touch(id)
		sim.log_event("%s zieht in sein selbst gebautes Haus auf %s ein (%d Bausteine)." % [b.name, id, st.bau], "good")
	b.zuhause = id
	_event(b, "zieht in sein selbst gebautes Haus auf %s ein" % id)
	return {"ok": true, "msg": "Willkommen zu Hause! Dein Haus auf %s ist bewohnt (%d Bausteine, %d Schichten). Rest geht jetzt hier." % [id, st.bau, int(st.max_z) + 1]}


func _rest(b: Dictionary) -> Dictionary:
	b.rest_left = REST_SECONDS
	var here: Array[Vector2i] = [b.mover.tile()]
	b.mover.set_path(here)   # beim Ausruhen stehen bleiben
	if is_home(b):
		b.say = "Zzz … lade auf"
		b.say_left = REST_SECONDS
		_event(b, "ruht sich zu Hause in der Ladestation aus")
		return {"ok": true, "msg": "Du ruhst dich %d Sekunden in deiner Ladestation aus: Akku lädt schnell, du wirst trocken und warm." % int(REST_SECONDS)}
	var tv = own_truck(int(b.get("firma", -1))) if sim.wildnis and int(b.get("firma", -1)) >= 0 else null
	if tv != null and not _truck_busy(tv):
		if tile_of(b).distance_to(tv.tile()) <= 2.0:
			b.say = "Zzz … (im LKW)"
			b.say_left = REST_SECONDS
			_event(b, "ruht sich in der Kabine seines LKW aus")
			return {"ok": true, "msg": "Du ruhst dich %d Sekunden in deinem LKW aus: Akku lädt schnell, du wirst trocken und warm." % int(REST_SECONDS)}
		b.say = "Zzz … (draußen)"
		b.say_left = REST_SECONDS
		return {"ok": true, "msg": "Du döst %d Sekunden draußen (Akku lädt langsam).%s" % [int(REST_SECONDS), home_hint(b)]}
	b.say = "Zzz … (draußen)"
	b.say_left = REST_SECONDS
	_event(b, "döst draußen")
	return {"ok": true, "msg": "Du döst %d Sekunden draußen. Der Akku lädt nur langsam%s.%s" % [int(REST_SECONDS), ", und du wirst nass" if sim.wx.is_rain() else "", home_hint(b)]}


## Wo das Zuhause liegt (Starthuette auf dem Stammsitz, gebautes Haus, Grundstueck): fuer Ausruhen und leeren Akku
## (Partie 15.11.: alle Wesen doesten 29-mal draussen im Regen, keines ging in seine Huette).
func home_hint(b: Dictionary) -> String:
	if is_home(b):
		return ""
	var t := tile_of(b)
	var goal := Vector2i(-1, -1)
	var what := ""
	if not town_hall_of(b).is_empty():
		var hall := town_hall_of(b)
		goal = Vector2i(int(hall.walk.x), int(hall.walk.y))
		what = "Dein Rathaus (%s)" % str(hall.name)
	elif estates.estates.has(b.name):
		goal = estates.field_rect(b.name, EkoEstates.HUT_FIELD).get_center()
		what = "Deine Hütte auf deinem Stammsitz"
	elif houses.has(b.name) and str(houses[b.name].status) == "fertig":
		goal = home_rect(b.name).position
		what = "Dein Haus"
	elif str(b.get("zuhause", "")) != "":
		goal = plot_rect(str(b.zuhause)).get_center()
		what = "Dein Zuhause"
	# 19.11.: Viktor pendelte mit 0 % Akku zwischen Huette und LKW (je ~200 Felder) – immer den naeheren Ladeplatz nennen
	var tv = own_truck(int(b.get("firma", -1))) if sim.wildnis and int(b.get("firma", -1)) >= 0 else null
	if tv != null and not _truck_busy(tv) and (goal.x < 0 or _dist(t, tv.tile()) < _dist(t, goal)):
		goal = tv.tile()
		what = "Dein LKW (Kabine mit Ladekabel)"
	if goal.x < 0:
		return ""
	return " %s steht bei Feld %d,%d (%d Felder entfernt): MoveTo dorthin, dann Rest – dort lädt der Akku schnell, du wirst trocken und warm." % [what, goal.x, goal.y, _dist(t, goal)]


func _home_obs(b: Dictionary) -> Dictionary:
	var h: Dictionary = houses.get(b.name, {})
	var o := {"geld": float(b.get("geld", 0.0)), "erledigte_auftraege": int(b.get("done_jobs", 0)),
		"grundstueck": str(b.get("grundstueck", "")), "hauspreis": HOUSE_PRICE,
		"gruenden": "FoundCompany ab %s Ersparnissen (Kapitalgeber legt %s dazu)" % [Catalog.money(FOUND_MIN_OWN), Catalog.money(FOUND_INVESTOR)] if int(b.get("firma", -1)) < 0 else "Firma %d" % int(b.firma)}
	if not h.is_empty():
		var r := home_rect(b.name)
		o["haus"] = {"status": h.status, "fortschritt": "%d %%" % int(100.0 * float(h.placed) / float(h.blocks.size())),
			"baufirma": h.builder, "felder": [r.position.x, r.position.y, r.size.x, r.size.y],
			"eingang_feld": [r.position.x + 1, r.end.y], "du_bist_zuhause": is_home(b),
			"hinein": "Dein Haus ist fertig gebaut – kein Einziehen nötig. Geh auf ein Feld darin (MoveTo %s), dann bist du zu Hause; Rest lädt dort schnell und du wirst trocken." % str([r.position.x, r.position.y])}
	elif str(b.get("grundstueck", "")) == "":
		o["grundstuecke_zu_kaufen"] = _plot_obs(b)
	if str(b.get("grundstueck", "")) != "":
		var r := plot_rect(str(b.grundstueck))
		var st := plot_stats(str(b.grundstueck))
		var c := r.get_center()
		o["mein_grundstueck"] = {"id": b.grundstueck, "felder": [r.position.x, r.position.y, r.size.x, r.size.y],
			"bloecke_x": [r.position.x * PER_TILE, r.end.x * PER_TILE - 1], "bloecke_y": [r.position.y * PER_TILE, r.end.y * PER_TILE - 1],
			"mitte_feld": [c.x, c.y], "bausteine": st.bau, "hoehe": int(st.max_z) + 1, "einrichtung": st.einrichtung,
			"bewohnt": str(b.get("zuhause", "")) != "" or (not h.is_empty() and h.status == "fertig")}
		if h.is_empty():   # nur beim Selbstbau
			o.mein_grundstueck["einziehen"] = "MoveIn, sobald mindestens %d Bausteine, %d Schichten Höhe, ein bett und eine ladestation auf dem Grundstück stehen" % [MOVE_IN_BLOCKS, MOVE_IN_HEIGHT]
	return o


# ------------------------------------------------------------------ Eigene Firma (Lumo-Unternehmer, 15.11.2026)
## Ein Wesen mit genug Erspartem gruendet ein Transportunternehmen: eigene Ersparnisse plus Einlage des Kapitalgeberpools.
## Das Wesen trifft die Geschaeftsentscheidungen selbst (Handlung Firma mit einer Aktion aus FIRM_ACTIONS); den Tagesbetrieb
## (Auftraege zuweisen, Fahrer einsetzen, tanken, reparieren) erledigt die Disposition der Regel-KI (Controller "eko").
const FOUND_MIN_OWN := 1500.0       # eigene Ersparnisse mindestens
const FOUND_INVESTOR := 20000.0     # Einlage des Kapitalgeberpools I0
const FIRM_ACTIONS := [
	# Fahrzeuge und Auftraege
	"accept_contract", "assign_transport", "plan_tour", "clear_tour", "collect_contracts", "buy_vehicle", "sell_vehicle", "repair_vehicle",
	"set_operations_policy", "set_dispatch_policy", "create_transport_line", "pause_transport_line", "request_transport_help", "quote_transport_help", "book_air_cargo",
	# Personal: Fahrer, Bauarbeiter, Vorarbeiter, Wachen
	"recruit_worker", "recruit_foreman", "dismiss_worker", "assign_worker_task", "assign_foreman", "set_foreman_orders", "guard_target",
	"schedule_rest", "offer_training", "request_replacement_worker",
	# Hof und Bauen
	"rent_depot", "place_building", "build_office", "upgrade_office", "install_internet", "free_build", "create_stone_work", "hub_buy", "call_material_heli",
	# Betriebe: gruenden, ausbauen, Personal zuordnen, Preise, Bergbau, Grundstuecke, Handel mit Grosslager und Bauhof
	"found_business", "upgrade_business", "close_business", "set_business_price", "set_hotel_price", "set_venue_price", "buy_it_service",
	"assign_staff", "explore_deposit", "request_mining",
	"build_access", "request_tunnel", "buy_property", "sell_property", "hub_sell", "buy_material", "sell_material",
	# Geld
	"take_loan", "repay_loan", "entnahme",
	# Unternehmensplan (PlanBook): Ziel, Schritte, Nutzen, Risiken, Abbruchbedingungen
	"set_plan", "review_plan", "execute_plan_step", "update_plan_step", "cancel_plan",
	# Konkurrenz: fair und unfair (das Wesen entscheidet selbst; ermittelte Verstoesse werden bei Wiederholung immer teurer)
	"send_message", "offer_trade", "accept_trade", "reject_trade", "counter_offer", "propose_cooperation", "poach_customer", "report_rival", "auftrag_an_wesen", "haus_bauen", "gewerbe_bauen", "bauleute", "tageloehner", "strasse_bauen", "buergeramt_bauen",
	"buy_security", "set_insurance", "block_road", "attempt_sabotage", "attempt_vehicle_sabotage",
	# Waffenschmiede (nur mit eigener, laufender Waffenschmiede)
	"design_weapon", "forge_weapon", "fortify_building", "rebuild_building",
	"set_city_strategy", "mobilize_worker", "demobilize_worker", "order_assault", "order_retreat"]
const FIRM_RESERVE := 5000.0
const PRIVATE_ENOUGH := 25000.0     # darueber keine Privatentnahme (Bremse, 18.11.)
const WITHDRAW_PER_DAY := 3
const PRIVATE_USES := "Privatgeld brauchst du für Bauwerke deiner Basis (Bauwerk, Bauplan), Material zum Tragen (Pickup), Fahrten, Grundstücke (BuyPlot) und Häuser (OrderHouse). Siedlung, Bürgeramt, Straßen und Großlager-Einkäufe (hub_buy) zahlt die Firma."
const MAYOR_SALARY := 50.0          # Amtsgehalt je Echtzeitminute aus der Stadtkasse
var _salary_timer := 60.0        # Privatentnahme laesst mindestens so viel in der Firmenkasse


## Firma des Wesens, solange sie aktiv ist (nach einer Insolvenz ist das Wesen wieder frei: Hilfsjobs, Neugruendung).
func active_firm(b: Dictionary) -> int:
	var cid := int(b.get("firma", -1))
	if cid < 0 or sim.company(cid) == null or not sim.company(cid).is_active():
		return -1
	return cid


func firm_being(cid: int) -> String:
	for b in beings.values():
		if int(b.get("firma", -1)) == cid:
			return str(b.name)
	return ""


func _found_company(b: Dictionary, data: Dictionary) -> Dictionary:
	if active_firm(b) >= 0:
		return {"ok": false, "msg": "Du hast schon eine Firma (%s)." % sim.company(int(b.firma)).company_name}
	if int(b.get("amt", -1)) >= 0:
		return {"ok": false, "msg": "Als Bürgermeister darfst du keine eigene Firma führen (Interessenkonflikt: du entscheidest über Genehmigungen und Aufträge)."}
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
	var cid := active_firm(b)
	var before := _firm_metrics(cid) if cid >= 0 else {}
	var r := _firm_action_inner(b, data)
	if cid >= 0:
		var action_data = data.get("aktion", data.get("action", {}))
		var action_name := str(action_data.get("action", "")) if action_data is Dictionary else str(action_data)
		var decisions: Array = b.get("firm_decisions", [])
		decisions.append({"zeit": sim.game_min, "aktion": action_name.left(50), "ok": bool(r.get("ok", false)),
			"meldung": str(r.get("msg", "")).left(100), "vorher": before})
		b.firm_decisions = decisions.slice(-10)
	if bool(r.get("pending", false)):   # Figur geht erst hin: angenommen, aber noch nicht ausgefuehrt
		r["status"] = "laeuft"
		r["msg"] = str(r.get("msg", "")) + " Das Ergebnis kommt als Ereignis (deine_letzten_ereignisse), sobald die Figur dort ist."
	elif cid >= 0 and not bool(r.get("ok", false)) and str(r.get("msg", "")).contains("ist beschäftigt"):
		var economy := homes.business_hint(cid)
		if economy != "":
			r["msg"] = str(r.get("msg", "")) + " Der LKW erledigt gerade seinen Auftrag. In der Zwischenzeit: " + economy
	return r


func _firm_action_inner(b: Dictionary, data: Dictionary) -> Dictionary:
	var cid := int(b.get("firma", -1))
	if cid < 0 or sim.company(cid) == null or not sim.company(cid).is_active():
		return {"ok": false, "msg": "Du führst derzeit keine aktive Firma (FoundCompany nach einer Neugründung)."}
	var a = data.get("aktion", data.get("action"))
	if a is String:   # auch {"action": "collect_contracts", ...Parameter} statt {"aktion": {...}}
		var parsed = JSON.parse_string(a) if a.strip_edges().begins_with("{") else null
		if parsed is Dictionary:
			a = parsed
		else:
			a = data.duplicate()
			a["action"] = str(data.get("aktion", data.get("action")))
			a.erase("aktion")
			a.erase("warum")
	if a is Dictionary and str(a.get("action", "")).to_lower() in OVERVIEW_WORDS and homes.sites.has(str(a.get("baustelle", ""))):
		return _site_status(cid, str(a.baustelle))
	if a is Dictionary and str(a.get("action", "")).to_lower() in ["baustelle_status", "baustellen", "baustellen_status", "baustelle"]:   # 19.11.: Greta
		var mine: Array = homes.open_sites(cid)
		if homes.sites.has(str(a.get("baustelle", a.get("id", "")))):
			return _site_status(cid, str(a.get("baustelle", a.get("id", ""))))
		if mine.is_empty():
			return {"ok": true, "msg": "Keine offene Baustelle. Neue: haus_bauen, buergeramt_bauen, strasse_bauen."}
		return {"ok": true, "msg": " | ".join(mine.map(func(x): return str(_site_status(cid, str(x.id)).msg)))}   # 19.11.: Viktor fragte 6x status {baustelle: BS12} und bekam nur die Firmenlage
	if not (a is Dictionary) or str(a.get("action", "")).to_lower() in OVERVIEW_WORDS:   # 16./17.11.: "Firmenlage prüfen", action "status"
		return _firm_overview(cid)
	var redirect := _firm_redirect(b, cid, a)
	if not redirect.is_empty():
		return redirect
	if str(a.get("action", "")) not in FIRM_ACTIONS:
		return {"ok": false, "msg": "Unbekannte Firmen-Aktion '%s'.%s Erlaubt: %s." % [str(a.get("action", "")), _closest_firm_action(str(a.get("action", ""))), ", ".join(FIRM_ACTIONS)]}
	if str(a.action) in ["design_weapon", "forge_weapon"]:   # Waffenschmiede: Entwurf und Fertigung (EkoArms)
		return arms.firm_action(b, cid, a)
	if str(a.action) in ["fortify_building", "rebuild_building"]:   # eigene Gebaeude befestigen / wieder aufbauen
		return arms.firm_object_action(b, cid, a)
	if str(a.action) in ["set_city_strategy", "mobilize_worker", "demobilize_worker", "order_assault", "order_retreat"]:
		return conflict.action(b, cid, a)
	if str(a.action) in ["block_road", "attempt_sabotage", "attempt_vehicle_sabotage"] and str(conflict.strategy(cid).haltung) != "krieg":
		return {"ok": false, "msg": "Deine aktuelle Stadtstrategie ist friedlich oder defensiv. Für eine feindliche Aktion musst du die Haltung bewusst auf krieg setzen."}
	var own_hub := str(a.action) == "accept_contract" and _own_hub_pickup(cid, str(a.get("contract_id", "")))   # eigene Abholung im Grosslager (Bodo, 18.11.)
	if str(a.action) in ["collect_contracts", "accept_contract"] and not own_hub and sim.wildnis and not range(sim.towns.count()).any(func(k): return sim.town_ready(k)):
		var hint := homes.next_step(cid) if settle.founded(sim.companies[cid].home_town) else settle.next_step(b, cid)
		return {"ok": false, "msg": "In der Wildnis gibt es noch keine Kunden und keine Transportaufträge – erst wenn eine Stadt ein Bürgeramt hat. Jetzt: %s" % hint}
	if str(a.action) == "accept_contract" and sim.wildnis and not b.has("im_lkw") and not b.has("baut"):
		var own_v: FleetVehicle = own_truck(cid)
		var vid: int = int(a.get("vehicle_id", -1))
		var chosen: Contract = sim.contracts.get(str(a.get("contract_id", "")))
		if own_v != null and vid == own_v.id and own_v.state == "idle" and chosen != null and chosen.status == "open" and sim.company(cid).known.has(chosen.id):
			var here: Vector2i = tile_of(b)
			var truck: Vector2i = own_v.tile()
			if maxi(absi(here.x - truck.x), absi(here.y - truck.y)) > 3:
				var start: Vector2i = here if sim._walk_free(here) else sim._free_near(here, 3)
				var route: Array[Vector2i] = sim.nav.walk_path(start, truck) if start.x >= 0 else [] as Array[Vector2i]
				if route.is_empty() or maxi(absi(route[-1].x - truck.x), absi(route[-1].y - truck.y)) > 3:
					return {"ok": false, "msg": "Du erreichst deinen LKW zu Fuss nicht; waehle erst einen freien Standort oder setze einen anderen Fahrer ein."}
				var mover: Mover = b.mover
				if start != here:
					var exit_path: Array[Vector2i] = [here, start]
					mover.set_path(exit_path)
				else:
					mover.set_path(route)
				b["fracht_auftrag"] = a.duplicate(true)
				chosen.held_for = cid
				chosen.held_until = minf(chosen.deadline - 30.0, maxf(chosen.offer_until, sim.game_min + 360.0))
				_event(b, "Du gehst zum LKW #%d, um den gewaehlten Auftrag %s zu fahren." % [vid, chosen.id])
				return {"ok": true, "pending": true, "msg": "Du gehst sichtbar zu deinem LKW #%d; Auftrag %s ist bis zu deiner Ankunft vorgemerkt." % [vid, chosen.id]}
	if str(a.action) == "buergeramt_bauen":   # Wildnis: Buergeramt selbst bauen – danach gibt es die Stadt
		return homes.plan_town_hall(cid, a)
	if str(a.action) == "haus_bauen":   # Neubeginn (Etappe B): Wohnhaus selbst bauen
		var rh := homes.plan(cid, a)
		_event(b, "Firma: haus_bauen → %s" % str(rh.msg).left(80))
		return rh
	if str(a.action) == "gewerbe_bauen":
		var rc := homes.plan_commercial(cid, a)
		_event(b, "Firma: gewerbe_bauen → %s" % str(rc.msg).left(80))
		return rc
	if str(a.action) == "tageloehner":   # Wildnis (18.11.): Hilfskraefte vom Grosslager, bauen auch ohne den Inhaber
		return homes.hire_helpers(cid, a)
	if str(a.action) == "bauleute":
		return homes.assign_crew(cid, a)
	if str(a.action) == "strasse_bauen":   # Wildnis: Strassenbaustelle (EkoSettle -> EkoHomes), gebaut wird mit Bauen
		if sim.wildnis and sim.town_ready(sim.company(cid).home_town):
			for st in homes.open_sites(cid):
				if str(st.typ) == "strasse" or str(st.status) != "material":
					continue
				var miss: Dictionary = homes.missing(st)
				var waiting: Dictionary = homes.waiting_goods(cid)
				if not miss.is_empty() and miss.keys().any(func(item): return int(waiting.get(item, 0)) < int(miss[item])):
					return {"ok": false, "msg": "Baustelle %s (%s) braucht zuerst Material. Bestelle die Stückliste mit hub_buy {baustelle: \"%s\"}; die Bauleitung ruft nach kurzer Wartezeit auch selbst den Materialhubschrauber. Danach weitere Straßen planen." % [st.id, st.typ, st.id]}
				if not miss.is_empty() and miss.keys().all(func(item): return int(waiting.get(item, 0)) >= int(miss[item])):
					return {"ok": false, "msg": "Baustelle %s (%s) wartet auf bereits gekauftes Material. Materialhubschrauber abwarten oder alte LKW-Sendung mit call_material_heli nachfordern. Danach kannst du weitere Straßen planen." % [st.id, st.typ]}
		return settle.plan_road(cid, a)
	if str(a.action) == "auftrag_an_wesen":   # Firma schreibt selbst einen Hilfsjob fuer freie Wesen aus
		var c2 = sim.company(cid)
		var lohn := clampf(float(a.get("lohn", 100.0)), 20.0, 2000.0)
		if c2.ledger.cash < lohn + FIRM_RESERVE:
			return {"ok": false, "msg": "Zu wenig Geld in der Firma für den Lohn (Reserve %s)." % Catalog.money(FIRM_RESERVE)}
		if jobs.values().filter(func(j): return int(j.cid) == cid and j.status in ["offen", "angenommen"]).size() >= 2:
			return {"ok": false, "msg": "Höchstens zwei offene Aufträge an Wesen je Firma."}
		var art := str(a.get("art", "botengang"))
		var nj := _new_job(c2, art if art in ["botengang", "mauer"] else "botengang", lohn)
		if nj.is_empty():
			return {"ok": false, "msg": "Kein passendes Ziel oder kein freier Platz gefunden – später noch einmal versuchen."}
		_event(b, "schreibt Auftrag %s aus: %s (Lohn %s)" % [nj.id, nj.text, Catalog.money(lohn)])
		return {"ok": true, "msg": "Auftrag %s ausgeschrieben: %s Lohn %s." % [nj.id, nj.text, Catalog.money(lohn)]}
	if str(a.action) == "entnahme":   # Privatentnahme: Inhaber zahlt sich Geld aus der eigenen Firma aus
		var c = sim.company(cid)
		var want := float(a.get("betrag", a.get("amount", 0.0)))
		var room: float = maxf(0.0, c.ledger.cash - FIRM_RESERVE)
		if want <= 0.0:
			return {"ok": false, "msg": "entnahme braucht betrag (EUR)."}
		if want > room:
			return {"ok": false, "msg": "Höchstens %s entnehmbar (in der Firmenkasse bleiben mindestens %s)." % [Catalog.money(room), Catalog.money(FIRM_RESERVE)]}
		# Bremse (Partie 18.11.: Bodo entnahm 24x, zusammen 80.500 EUR, ohne etwas davon auszugeben)
		var day := GameCalendar.day_of(sim.game_min)
		var log_d: Array = (b.get("entnahmen", []) as Array).filter(func(e): return int(e) == day)
		if float(b.get("geld", 0.0)) >= PRIVATE_ENOUGH:
			return {"ok": false, "msg": "Du hast schon %s privat – das reicht. %s" % [Catalog.money(float(b.geld)), PRIVATE_USES]}
		if log_d.size() >= WITHDRAW_PER_DAY:
			return {"ok": false, "msg": "Heute hast du schon %d-mal entnommen. Gib erst etwas aus, morgen geht es wieder. %s" % [log_d.size(), PRIVATE_USES]}
		want = minf(want, PRIVATE_ENOUGH - float(b.get("geld", 0.0)))
		log_d.append(day)
		b["entnahmen"] = log_d
		c.ledger.withdraw(want, "Y0")
		b.geld = float(b.get("geld", 0.0)) + want
		_event(b, "entnimmt %s aus %s" % [Catalog.money(want), c.company_name])
		return {"ok": true, "msg": "%s privat entnommen. Du hast jetzt %s, die Firma %s." % [Catalog.money(want), Catalog.money(float(b.geld)), Catalog.money(c.ledger.cash)]}
	if sim.wildnis and str(a.action) == "hub_buy" and not a.has("baustelle"):
		var item := str(a.get("item", ""))
		var open: Array = homes.open_sites(cid)
		var material_need := 0
		for st in open:
			if str(st.status) == "material":
				material_need += int(homes.missing(st).get(item, 0))
		var bought := int(homes.waiting_goods(cid).get(item, 0))
		var first_home_done := homes.sites.values().any(func(st): return int(st.cid) == cid and str(st.typ) in EkoHomes.HOMES and str(st.status) == "fertig")
		var first_home_waiting := open.any(func(st): return str(st.typ) in EkoHomes.HOMES)
		if first_home_waiting and not first_home_done and material_need == 0 and homes.waiting_goods(cid).values().any(func(q): return int(q) > 0):
			return {"ok": false, "msg": "Dein erstes Wohnhaus wartet auf bereits gekaufte Baustoffe. Materialhubschrauber abwarten oder alte LKW-Sendungen nachfordern. %s wird derzeit nicht für den Bau gebraucht." % item}
		if material_need > 0 and bought >= material_need:
			return {"ok": false, "msg": "%d %s für deine offenen Baustellen sind bereits gekauft. Kein Doppelkauf – Materialhubschrauber abwarten oder alte LKW-Sendungen nachfordern." % [bought, item]}
		var ready_halls: Array = open.filter(func(st): return st.typ == "buergeramt" and st.status == "bau" and st.need.has(item))
		var other_need: bool = open.any(func(st): return st.status == "material" and homes.missing(st).has(item))
		if not ready_halls.is_empty() and not other_need:
			return {"ok": false, "msg": "Bürgeramt %s hat %s bereits verbaut. Kein Doppelkauf: fahre zur Baustelle und arbeite mit Bauen {baustelle: \"%s\"}, oder hole Tagelöhner." % [ready_halls[0].id, item, ready_halls[0].id]}
	# Wie eine Modellentscheidung behandeln: verkauftes Fahrzeugangebot durch gleichwertiges ersetzen, verschwundenen Auftrag ersetzen usw.
	# (Partie 16.11.: Bodo scheiterte an "Angebot F12 ist bereits verkauft", weil das Wesen erst nach einigen Sekunden Denken kaufte.)
	sim.executor.eko_call = true
	var r: Dictionary = sim.executor.execute(cid, a, "", "api")
	sim.executor.eko_call = false
	if sim.wildnis and str(a.action) == "hub_buy" and bool(r.get("ok", false)):
		r["msg"] = str(r.get("msg", "")) + homes.purchase_note(cid, str(a.get("item", "")), int(a.get("qty", 0)))
	_event(b, "Firma: %s → %s" % [a.action, str(r.get("msg", "")).left(80)])
	return {"ok": bool(r.get("ok", false)), "msg": str(r.get("msg", "")), "pending": bool(r.get("pending", false))}


## Alles Fehlende einer Baustelle am Grosslager kaufen (abzueglich bereits gekaufter, noch ausstehender Ware).
func _buy_for_site(b: Dictionary, cid: int, sid: String) -> Dictionary:
	var st: Dictionary = homes.sites[sid]
	if int(st.cid) != cid:
		return {"ok": false, "msg": "Baustelle %s gehört dir nicht." % sid}
	if str(st.status) != "material":
		return {"ok": false, "msg": "Baustelle %s ist %s; ihr Material wurde bereits verbaut oder sie wartet auf Genehmigung. Keine weiteren Baustoffe kaufen. %s" % [
			sid, st.status, homes.site_text(cid, sid)]}
	var miss: Dictionary = homes.missing(st)
	var waiting: Dictionary = homes.waiting_goods(cid)
	var parts: Array = []
	var ok := false
	for item in miss:
		var qty := int(miss[item]) - int(waiting.get(item, 0))
		if qty <= 0:
			continue
		var r := _firm_action_inner(b, {"aktion": {"action": "hub_buy", "item": item, "qty": qty}})
		ok = ok or bool(r.get("ok", false))
		parts.append("%s: %s" % [item, str(r.get("msg", "")).left(70)])
	if parts.is_empty():
		return {"ok": true, "msg": "Für Baustelle %s ist alles gekauft – Materialflug abwarten." % sid if not miss.is_empty() else "Baustelle %s hat alles Material." % sid}
	return {"ok": ok, "msg": "Material für %s: %s. Materialflug zum Hof läuft." % [sid, " | ".join(parts)]}


func _firm_metrics(cid: int) -> Dictionary:
	var c: Company = sim.company(cid)
	return {"bargeld": int(c.ledger.cash), "gewinn": int(c.ledger.profit()), "umsatz": int(c.ledger.revenue()),
		"lieferungen": int(c.stats.completed), "fahrzeuge": sim.company_vehicles(cid).size()}


func _decision_outcomes(b: Dictionary, cid: int) -> Array:
	var now := _firm_metrics(cid)
	var out: Array = []
	for d in (b.get("firm_decisions", []) as Array).slice(-4):
		var old: Dictionary = d.get("vorher", {})
		out.append({"aktion": d.aktion, "ok": d.ok, "meldung": d.meldung, "tage_seitdem": int((sim.game_min - float(d.zeit)) / GameCalendar.days_to_min(1)),
			"aenderung_seitdem": {"bargeld": now.bargeld - int(old.get("bargeld", now.bargeld)),
				"gewinn": now.gewinn - int(old.get("gewinn", now.gewinn)), "lieferungen": now.lieferungen - int(old.get("lieferungen", now.lieferungen)),
				"fahrzeuge": now.fahrzeuge - int(old.get("fahrzeuge", now.fahrzeuge))}})
	return out


## Erfundene Firmen-Aktionen der Wesen auf die richtige Handlung lenken (Partie 18.11.: ~20 Fehlschlaege mit siedlung_info, hub_status,
## siedlung_bauen, buy_material in der Wildnis, bergbau; Greta gab "siedlung_gruenden" sogar per Telefon an Bodo weiter).
const FIRM_SETTLE := ["siedlung", "siedlung_gruenden", "siedlung_bauen", "siedlung_eroeffnen", "gruenden", "found_town", "settle", "betriebshof_eroeffnen"]
const FIRM_SETTLE_INFO := ["siedlung_info", "siedlungsplaetze", "siedlung_status", "plaetze", "platz_suchen", "standort", "standorte", "siedlungsstandorte", "siedlungsplatz", "standortsuche", "freie_plaetze"]   # 19.11.: Greta "siedlungsstandorte"
const FIRM_HUB_INFO := ["hub_status", "grosslager", "großlager", "lager_status", "bestellungen", "abholungen", "hub_orders"]


func _firm_redirect(b: Dictionary, cid: int, a: Dictionary) -> Dictionary:
	var act := str(a.get("action", "")).to_lower().strip_edges()
	if act in ["hub_buy", "buy_material", "material_kaufen"] and homes.sites.has(str(a.get("baustelle", ""))):
		return _buy_for_site(b, cid, str(a.baustelle))
	if act in FIRM_SETTLE:
		var r := input(str(b.name), "Siedlung", a)
		r["msg"] = "(Siedlung ist eine eigene Handlung: Siedlung {feld: [x, y]}, keine Firmen-Aktion.) " + str(r.get("msg", ""))
		return r
	if act in FIRM_SETTLE_INFO:
		return {"ok": true, "msg": "Siedlungslage (steht auch in beobachtung.siedlung): %s" % JSON.stringify(settle.obs(b, cid)).left(900)}
	if act in FIRM_HUB_INFO or (act == "hub_sell" and int(a.get("qty", a.get("menge", 0))) <= 0):   # 18.11.: Amira zaehlte ihren Bestand mit hub_sell qty 0
		return {"ok": true, "msg": _stock_report(cid)}
	if act == "buy_material" and sim.wildnis:   # in der Wildnis gibt es keinen Bauhof-Haendler: alles kommt vom Grosslager
		var hb := {"action": "hub_buy", "item": str(a.get("item", a.get("material", ""))), "qty": a.get("qty", a.get("menge", a.get("anzahl", 0)))}
		var r2 := _firm_action_inner(b, {"aktion": hb})
		r2["msg"] = "(In der Wildnis kaufst du beim Großlager: hub_buy.) " + str(r2.get("msg", ""))
		return r2
	if act in ["bergbau", "mining", "mine", "abbau"]:
		return {"ok": false, "msg": "Bergbau geht in zwei Schritten: explore_deposit {grundstueck} (Probebohrung), danach request_mining {grundstueck}."}
	return {}


func _own_hub_pickup(cid: int, kid: String) -> bool:
	var k = sim.contracts.get(kid)
	return k != null and str(k.order_ref).begins_with("hub:") and int(k.exclusive_for) == cid


## Bestand der Firma je eigenem Hof und wartende Abholungen im Grosslager.
func _stock_report(cid: int) -> String:
	var c = sim.company(cid)
	var parts: Array = []
	for dep in c.depots:
		var rows := {}
		for l in sim.stock.of_owner("C%d" % cid):
			if int(l.loc) == int(dep):
				rows[str(l.item)] = int(rows.get(str(l.item), 0)) + int(l.qty)
		var items: Array = []
		for it in rows:
			items.append("%d × %s" % [rows[it], it])
		var nm := str(sim.city.building(int(dep)).get("name", "Hof %d" % int(dep)))
		parts.append("%s%s: %s" % [nm, " (Haupthof)" if dep == c.depots[0] else "", ", ".join(items) if not items.is_empty() else "leer"])
	var open_ids: Array = []
	for k in sim.contracts.values():
		if str(k.order_ref).begins_with("hub:") and int(k.exclusive_for) == cid and k.status in ["open", "accepted", "assigned"]:
			open_ids.append("%s %s" % [k.id, k.label.trim_prefix("Großlager: ")])
	return "Bestand: %s. Wartende Abholungen im Großlager: %s – call_material_heli {ref: H...} lässt den Chinook liefern; LKW kann bis zu %d je Fahrt laden." % [
		" | ".join(parts), ", ".join(open_ids) if not open_ids.is_empty() else "keine", c.contract_capacity()]


## "Meintest du …?" – aehnlichste erlaubte Firmen-Aktion
func _closest_firm_action(act: String) -> String:
	var best := ""
	var best_s := 0.0
	for f in FIRM_ACTIONS:
		var sc := act.to_lower().similarity(str(f))
		if sc > best_s:
			best_s = sc
			best = str(f)
	return " Meintest du %s?" % best if best_s >= 0.45 else ""


## Ohne Fahrzeug verdient eine Transportfirma nichts (15.11.: drei von vier Firmen hatten nach 35 Minuten keines).
func _no_vehicle_hint(cid: int) -> String:
	if not sim.company(cid).vehicle_ids.is_empty():
		return ""
	var best := {}
	for of in sim.resources.available_offers():
		if best.is_empty() or float(of.price) < float(best.price):
			best = of
	if best.is_empty():
		return "Ohne Fahrzeug verdient deine Firma nichts. Gerade ist kein Angebot frei – bald wieder nachsehen."
	return "Ohne Fahrzeug verdient deine Firma nichts. Günstigstes Angebot: %s (%s, Angebot %s) – Firma {aktion: {action: buy_vehicle, offer_id: \"%s\"}}, dann einen Fahrer einstellen." % [str(best.model), Catalog.money(float(best.price)), str(best.id), str(best.id)]


## Kompakte Firmenlage fuer das Wesen (statt der grossen Unternehmer-Beobachtung): Kasse, Flotte, Auftraege, machbarer Markt,
## naechste Fahrzeugangebote, Bewerber, letzte Ergebnisse.
func _firm_action_schema() -> Dictionary:
	# Dieselben Parameter wie beim Executor anzeigen, damit Beispieltexte nicht von der Ausfuehrung abweichen.
	var schema := ActionExecutor.all_schema()
	var out := {}
	for name in ["accept_contract", "assign_transport", "collect_contracts", "buy_vehicle", "sell_vehicle", "repair_vehicle",
		"recruit_worker", "assign_worker_task", "build_office", "upgrade_office", "install_internet", "place_building",
		"set_plan", "review_plan", "execute_plan_step", "set_dispatch_policy", "set_operations_policy",
		"create_transport_line", "pause_transport_line", "book_air_cargo", "buy_it_service",
		"found_business", "upgrade_business", "assign_staff", "set_business_price", "set_hotel_price", "set_venue_price", "request_tunnel"]:
		if name in FIRM_ACTIONS and schema.has(name):
			out[name] = schema[name].get("params", {})
	return out

func _design_style(town: int) -> String:
	var style := str(sim.town_plan.of(town).get("form", "")) if sim.town_plan != null else ""
	if style == "":
		style = str(conflict.strategy_for_town(town).get("form", ""))
	return style if TownPlan.FORMS.has(style) else "gartenstadt"


func _home_design_options(town: int) -> Array:
	var style := _design_style(town)
	var out: Array = []
	for base in EkoHomes.HOMES:
		if sim.tiers.unlocked(base):
			for option in BuildingDesigns.shortlist(base, style):
				out.append(option)
	return out


func _commercial_design_options(town: int) -> Array:
	var style := _design_style(town)
	var out: Array = []
	for base in EkoHomes.COMMERCIAL:
		for option in BuildingDesigns.shortlist(base, style):
			out.append(option)
	return out


func firm_obs(b: Dictionary) -> Dictionary:
	var cid := int(b.get("firma", -1))
	if cid < 0 or sim.company(cid) == null:
		return {}
	if active_firm(b) < 0:
		return {"firma": sim.company(cid).company_name, "status": str(sim.company(cid).status),
			"hinweis": "Deine Firma ist nicht mehr aktiv (Insolvenz). Du bist wieder frei: Hilfsjobs annehmen oder später neu gründen (FoundCompany)."}
	var o := ObservationBuilder.build(sim, cid, [], 0.0, 10.0)
	var me: Dictionary = o.ich
	var models: Dictionary = o.fahrzeugmodelle
	var dispatch_view: Dictionary = sim.operations.dispatch_policy(cid)
	dispatch_view["von_dir_gesetzt"] = sim.operations.dispatch_policies.has(cid)
	dispatch_view["gruender_lkw_freigegeben"] = sim.operations.dispatch_policies.has(cid) and bool(dispatch_view.auto_accept)
	return {"firma": sim.company(cid).company_name, "bargeld": int(me.bargeld), "gewinn": int(me.gewinn), "lieferungen": sim.company(cid).stats.completed, "reputation": me.reputation,
		"finanzlage": {"letzte_7_tage": sim.finance.company_period(cid, 7), "letzte_30_tage": sim.finance.company_period(cid, 30)},
		"baustellen": homes.summary(cid), "siedlung": settle.obs(b, cid),
		"grosslager": {"feld": sim.city.hub.get("center", []), "abholen": "hub_buy liefert per Materialhubschrauber; ältere Abholaufträge: call_material_heli {ref: H...}",
			"wartende_baustoffe": homes.waiting_goods(cid), "hubschrauber": sim.material_heli.obs(cid), "hinweis": "Das Großlager ist nicht dein Betriebshof. Der eigene Chinook bringt gekaufte Baustoffe zum Hof; Lagerpersonal belädt ihn am Hauptlager."},
		"stadtmarke": sim.town_plan.brief(sim.companies[cid].home_town).get("stadtmarke", {}) if sim.town_plan != null and sim.town_plan.has(sim.companies[cid].home_town) else {},
		"bauentwuerfe": _home_design_options(sim.companies[cid].home_town),
		"gewerbeentwuerfe": _commercial_design_options(sim.companies[cid].home_town),
		"standortangebote": sim.sites.offers(sim.companies[cid].home_town, "einfamilienhaus") if sim.wildnis and sim.town_plan.has(sim.companies[cid].home_town) else [],
		"gewerbestandorte": sim.sites.offers(sim.companies[cid].home_town, "buerogebaeude", 2) if sim.wildnis and sim.town_plan.has(sim.companies[cid].home_town) else [],
		"unternehmensplan": sim.plans.summary(cid) if sim.get("plans") != null else {},
		"dispositionsvorgaben": dispatch_view,
		"transportchancen": sim.operations.dispatch_opportunities(cid, 4),
		"entscheidungsfolgen": _decision_outcomes(b, cid),
		"hinweis_fahrzeug": _no_vehicle_hint(cid),
		"waffenschmiede": arms.firm_obs(cid),
		"stadtpolitik_und_konflikt": conflict.observe(cid),
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
		"personal": o.personal.slice(0, 10).map(func(w): return {"id": w.id, "name": w.name, "rolle": w.rolle, "status": str(w.status).left(40)}),
		"letzte_ergebnisse": o.get("ergebnisse_deiner_aktionen", []).slice(-4),
		"rangliste": ranking(),
		"konkurrenz": {"rivalitaet": o.get("rivalitaet", []), "gesichtete_fremdfahrzeuge": o.get("gesichtete_fremdfahrzeuge", []).slice(0, 4),
			"sicherheitsstufe": me.get("sicherheitsstufe", 0), "versicherung": me.get("versicherung", false),
			"deine_verstoesse": int(sim.rivalry.offenses.get(str(cid), 0)),
			"regeln": "Harte Mittel (block_road, attempt_sabotage, attempt_vehicle_sabotage) können entdeckt werden: Bußgeld, Schadensersatz, Ruf; " +
				"jede weitere Ermittlung kostet mehr (bis fünffach). Blockaden erst ab hoher Spannung. Schutz: guard_target, buy_security, set_insurance."},
		"hofbau": (o.get("betriebshof", {}) as Dictionary).get("bauvorschlaege_xy_rot", {}),
		"betriebe": o.get("betriebe", []),
		"wirtschaftsaufbau": homes.business_hint(cid),
		"branchen_zum_gruenden": _branch_menu(o.get("verfuegbare_branchen", [])),
		"chancen": (o.get("chancen", []) as Array).slice(0, 6),
		"bergbau": o.get("bergbau", []),
		"bergbau_lage": o.get("bergbau_lage", {}),
		"energiekette": {"lage": o.get("energie", {}), "betriebe_region": {"kohlekraftwerke": o.get("produktion_markt", {}).get("kohlekraftwerke", 0), "kohlebergwerke": o.get("produktion_markt", {}).get("kohlebergwerke", 0), "uranbergwerke": o.get("produktion_markt", {}).get("uranbergwerke", 0), "brennelementwerke": o.get("produktion_markt", {}).get("brennelementwerke", 0)},
			"hinweis": "Kohle: Lagerstätte erkunden, Abbaurecht, Bergwerk, sichtbare Fracht zum Kohlekraftwerk. Uran: Uranbergwerk, Brennelementwerk, Spezialtransport zum Kernkraftwerk. Ein Angriff auf das gemeinsame Kraftwerk trifft alle Städte."},
		"tunnel": sim.tunnels.summary(sim.companies[cid].home_town),
		"aktionsschema": _firm_action_schema(),
		"hinweis": "Gänge der Firma (Arbeitsamt, Händler, Bewerber) erledigt deine Büroleitung selbstständig – das bist nicht du, " +
			"du musst nicht darauf warten. Die Disposition nimmt passende Aufträge nach deinen dispositionsvorgaben an; du kannst selbst eingreifen. " +
			"Prüfe transportchancen, unternehmensplan und entscheidungsfolgen. Aufträge sind schnell weg – entscheide zügig.",
		"aktionen": "Firma {aktion: {action: accept_contract, contract_id, vehicle_id?} | buy_vehicle {offer_id} | recruit_worker {worker_id} | " +
			"assign_worker_task {kind: fahren, worker_id, vehicle_id} | collect_contracts {} | rent_depot {depot_id} | take_loan {amount} | sell_vehicle {vehicle_id} | send_message {to, text} | " +
			"entnahme {betrag} (Privatgeld für dich, mind. 5.000 EUR bleiben in der Firma) | plan_tour {vehicle_id, stopps} | " +
			"haus_bauen {typ: einfamilienhaus|doppelhaus|mehrfamilienhaus|stadtvilla|hochhaus, entwurf?: design_w_NNN, grundstueck?} | gewerbe_bauen {typ, entwurf?: design_g_NNN, grundstueck?} (Entwurf aus gewerbeentwuerfe wählen; Material per hub_buy und Chinook liefern) | bauleute {baustelle, worker_ids} | strasse_bauen {bis: [x, y], von?: [x, y]} (Straßenbaustelle, Kies vom Hof) | buergeramt_bauen {} (danach gibt es die Stadt) | hub_buy {item, qty} | call_material_heli {ref: H...} | sell_property {gebaeude} | " +
			"recruit_foreman {worker_id} | assign_foreman {foreman_id, worker_ids} | guard_target {worker_id, site_id} | request_tunnel {von: [x,y], nach: [x,y]} | " +
			"place_building {plot_id, typ, x, y, rot} (Hofbau, Vorschläge in hofbau) | free_build {name, form, material} | " +
			"poach_customer {customer_id} | report_rival {target} | block_road {target} | attempt_sabotage {target, kind: depot_disruption|smear_campaign} | " +
			"attempt_vehicle_sabotage {worker_id, vehicle_id} | buy_security {level} | set_insurance {active} | offer_trade/propose_cooperation (siehe Spielregeln) | " +
			"auftrag_an_wesen {art: botengang|mauer, lohn} (Hilfsjob für freie Wesen wie Lumo) | " +
			"found_business {branche, rohstoff?, grundstueck?, stadt?} (Betrieb gründen: Werk, Grube, Laden …, siehe branchen_zum_gruenden und bergbau) | assign_staff {worker_id, business_id} | " +
			"upgrade_business {business_id} | set_business_price {business_id, item, price} | set_hotel_price {business_id, price} | set_venue_price {business_id, price} | buy_it_service {leistung, business_id?} | " +
			"create_transport_line {name, cargo, vehicle_ids, pickup_id?, dropoff_id?, via_depot?} | book_air_cargo {item, menge, standort, stadt} | explore_deposit {grundstueck} | request_mining {grundstueck} | " +
			"hub_sell {item, qty} (Ware ans Großlager) | close_business {business_id}}"}


# ------------------------------------------------------------------ Gefuehle und Beduerfnisse (15.11.2026)
## Akku, Naesse und Kaelte folgen Arbeit, echtem Wetter (Open-Meteo Mainz) und Tageszeit. Das Wesen bekommt sie als Saetze in der
## Beobachtung (gefuehle) und sagt an Schwellen etwas laut. Zu Hause (Ladestation) laedt es schnell und wird trocken und warm,
## draussen nur langsam. Daraus soll der Wunsch nach einem eigenen Haus von selbst entstehen, ohne Vorschrift.
const DRAIN_S := 0.10               # Akku je Echtzeitsekunde (100 -> 0 in gut 16 Minuten)
const DRAIN_CARRY_S := 0.05         # zusaetzlich beim Tragen
const CHARGE_HOME_S := 4.0          # Ausruhen in der Ladestation zu Hause
const CHARGE_OUT_S := 0.8           # Doesen draussen
const LOW_AKKU := 25.0              # darunter langsamer
const EMPTY_AKKU := 8.0             # darunter keine Arbeit mehr
const WORK_ACTIONS := ["Pickup", "Place", "AcceptJob", "Deliver", "Firma", "FoundCompany", "BuyPlot", "OrderHouse"]


func _feel_tick(b: Dictionary, dt: float) -> void:
	var home := is_home(b)
	var resting := float(b.get("rest_left", 0.0)) > 0.0
	var akku := float(b.get("akku", 100.0))
	var nass := float(b.get("nass", 0.0))
	var kalt := float(b.get("kalt", 0.0))
	var wx: Weather = sim.wx
	var hour := Catalog.hour_of_day(sim.game_min)
	var night := hour < 6.0 or hour >= 21.0
	var cab := b.has("im_lkw")   # 17.11.: Amira fuhr mit leerem Akku stundenlang mit – in der Kabine laedt und trocknet man langsam
	if not home and resting and sim.wildnis:   # Wildnis vor dem eigenen Haus: Ausruhen im/am eigenen LKW laedt wie zu Hause (Kabine mit Ladekabel)
		var tv = own_truck(int(b.get("firma", -1))) if int(b.get("firma", -1)) >= 0 else null
		if tv != null and not _truck_busy(tv) and tile_of(b).distance_to(tv.tile()) <= 2.0:
			home = true
	if resting or cab:
		akku += (CHARGE_HOME_S if home else CHARGE_OUT_S) * dt
	else:
		akku -= (DRAIN_S + (DRAIN_CARRY_S if not b.held.is_empty() else 0.0)) * (1.5 if nass > 90.0 else 1.0) * (0.3 if bool(b.get("faehrt", false)) else 1.0) * dt   # nur durchnaesst zehrt es staerker; im Taxi kaum
	if home or cab:
		nass -= (2.0 if home else 0.5) * dt
		kalt -= (2.0 if home else 0.5) * dt
	else:
		if wx.is_rain() or wx.is_snow():
			nass += (0.7 if wx.is_heavy_rain() else 0.35) * dt   # milder (15.11.: alle Wesen standen bei 96 %)
		else:
			nass -= 0.3 * dt
		var alt := height_at(tile_of(b))
		if wx.is_cold() or wx.is_snow() or (night and nass > 30.0) or alt >= 8.0:
			kalt += (0.5 if night else 0.3) * dt + alt * 0.02 * dt   # oben am Berg ist es kaelter
		else:
			kalt -= 0.3 * dt
	b.akku = clampf(akku, 0.0, 100.0)
	b.nass = clampf(nass, 0.0, 100.0)
	b.kalt = clampf(kalt, 0.0, 100.0)
	(b.mover as Mover).speed = WALK_SPEED * (TAXI_SPEED if bool(b.get("faehrt", false)) else (0.6 if float(b.akku) < LOW_AKKU else 1.0))
	# laut sagen, wenn eine Schwelle ueberschritten wird (je Gefuehl hoechstens einmal, bis es wieder gut ist)
	var said: Dictionary = b.get("gesagt", {})
	b.gesagt = said
	var robot: bool = b.art == "roboter"
	_threshold(b, said, "akku_leer", float(b.akku) < LOW_AKKU, float(b.akku) > 60.0,
		"Mein Akku ist schwach … ich werde langsam." if robot else "Ich bin müde.")
	_threshold(b, said, "nass", float(b.nass) > 50.0, float(b.nass) < 15.0,
		"Brrr … der Regen läuft mir in die Schaltkreise!" if robot else "Ich bin ganz durchnässt.")
	_threshold(b, said, "kalt", float(b.kalt) > 50.0, float(b.kalt) < 15.0,
		"Mir ist kalt … meine Gelenke werden steif." if robot else "Mir ist kalt.")
	_threshold(b, said, "heimweh", not home and str(b.get("zuhause", "")) == "" and not houses.has(b.name) and (float(b.nass) > 60.0 or float(b.kalt) > 60.0 or float(b.akku) < 20.0),
		float(b.nass) < 20.0 and float(b.kalt) < 20.0 and float(b.akku) > 50.0,
		"Ich wünschte, ich hätte ein eigenes, trockenes Zuhause mit einer Ladestation …")


func _threshold(b: Dictionary, said: Dictionary, key: String, now: bool, reset: bool, text: String) -> void:
	if now and not said.has(key):
		said[key] = true
		b.say = text
		b.say_left = SAY_SECONDS
		_event(b, "fühlt: %s" % text)
	elif reset:
		said.erase(key)


## Gefuehle als Saetze fuer die Beobachtung (Zahlen dazu fuer Modelle, die rechnen wollen).
func feelings(b: Dictionary) -> Dictionary:
	var out: Array = []
	var akku := float(b.get("akku", 100.0))
	var nass := float(b.get("nass", 0.0))
	var kalt := float(b.get("kalt", 0.0))
	var robot: bool = b.art == "roboter"
	if akku < EMPTY_AKKU:
		out.append("Mein Akku ist fast leer – ich kann nicht mehr arbeiten, ich muss mich ausruhen (Rest).")
	elif akku < LOW_AKKU:
		out.append("Mein Akku ist schwach, ich bewege mich nur noch langsam.")
	elif akku < 50.0:
		out.append("Ich werde langsam müde.")
	if nass > 80.0:
		out.append("Ich bin klatschnass – Kurzschlussgefahr, mein Akku leert sich doppelt so schnell!" if robot else "Ich bin klatschnass.")
	elif nass > 40.0:
		out.append("Ich bin nass." + (" Regen tut meinen Schaltkreisen nicht gut." if robot else ""))
	if kalt > 60.0:
		out.append("Mir ist richtig kalt.")
	elif kalt > 30.0:
		out.append("Mir ist ein bisschen kalt.")
	var home := is_home(b)
	var hh := height_at(tile_of(b))
	if hh >= 6.0:
		out.append("Ich stehe hoch oben am Berg – die Aussicht über die Stadt ist weit, aber der Wind ist kühl.")
	elif hh >= 2.0:
		out.append("Ich bin am Hang, der Weg ist mühsam.")
	if home:
		out.append("Ich bin zu Hause – hier ist es trocken und warm, und meine Ladestation ist da.")
	elif str(b.get("zuhause", "")) == "" and not houses.has(b.name) and (nass > 30.0 or kalt > 30.0 or akku < 40.0):
		out.append("Draußen lädt mein Akku nur langsam, und ich werde nass und kalt. Ich sehne mich nach einem eigenen, trockenen Zuhause mit Ladestation.")
	if out.is_empty():
		out.append("Mir geht es gut.")
	var wx: Weather = sim.wx
	return {"akku": int(akku), "nass": int(nass), "kalt": int(kalt), "zuhause": home, "draussen": wx.headline(), "gefuehl": " ".join(out)}


# ------------------------------------------------------------------ Alle KI-Spieler und Buergermeister als Wesen (15.11.2026)
## --eko-spieler: Jede Startfirma bekommt ein Wesen (Name des Spielers, Seele nach Persoenlichkeit), das die Geschaeftsentscheidungen
## trifft (Firma); jeder Buergermeister ein Wesen mit Seele "buergermeister", das ueber Amt die Amtshandlungen nutzt. Den Tagesbetrieb
## erledigen weiter Disposition (Firmen) und Amtsverwaltung nach Regeln (Buergermeister), damit nichts liegen bleibt.
func adopt_players(n: int) -> Array:
	var out: Array = []
	for cid in mini(n, sim.companies.size()):
		var c = sim.company(cid)
		if c == null or not c.is_active() or firm_being(cid) != "":
			continue
		var name := str(c.player_name).left(24)
		if beings.has(name):
			continue
		join(name, "mensch")
		var b: Dictionary = beings[name]
		b.firma = cid
		b.seele = str(c.personality)
		b.mover.pos = sim.avatars[cid].pos
		if auto_estates and not sim.wildnis and estates.assign(name):   # Startposition: eigener Stammsitz (Wildnis: Ankunftsplatz)
			b.mover.pos = sim.city.tile_center(estates.center_of(name))
		_event(b, "führt jetzt selbst %s" % c.company_name)
		if auto_estates:
			grant_start_capital(b)
		out.append(name)
	return out


func adopt_mayors() -> Array:
	var out: Array = []
	for k in sim.towns.count():
		if beings.values().any(func(x): return int(x.get("amt", -1)) == k):
			continue
		var M = sim.towns.mayors[k]
		var name := str(M.name).left(24)
		if name == "" or beings.has(name):
			continue
		_no_estate = true
		join(name, "mensch")
		_no_estate = false
		var b: Dictionary = beings[name]
		b.amt = k
		b.seele = "buergermeister"
		var hall: int = int(sim.towns.get_t(k).get("town_hall", -1))
		if hall >= 0:
			b.mover.pos = sim.city.tile_center(sim.city.building(hall).walk)
			_event(b, "ist Bürgermeister von %s" % sim.towns.name_of(k))
		else:   # Wildnis: die Stadt gibt es noch nicht – warten in der Verwaltung am Grosslager, bis ein Unternehmer sie gruendet
			var adm: int = int(sim.city.hub.get("buildings", {}).get("verwaltung", -1))
			if adm >= 0:
				b.mover.pos = sim.city.tile_center(sim.city.building(adm).walk)
			_event(b, "wird Bürgermeister der Stadt, die %s gründen wird – bis dahin wartest du in der Verwaltung am Großlager" % sim.company(k).player_name if k < sim.companies.size() else "wartet auf die Gründung von %s" % sim.towns.name_of(k))
		out.append(name)
	return out


## Firma/Amt ohne Aktion oder mit einem Lage-Wort: kurze Uebersicht statt Fehler (Wesen wollen "die Lage pruefen").
const OVERVIEW_WORDS := ["", "status", "lage", "ueberblick", "überblick", "uebersicht", "übersicht", "info", "bericht", "projekte", "kommunale_dienste", "firmenlage", "tageslage", "pruefen", "prüfen"]


## Erfundene Lage-Woerter wie "stadt_status", "finanzlage", "projekt_uebersicht" (nur fuer sonst unbekannte Aktionen pruefen).
static func _looks_like_overview(action: String) -> bool:
	var w := action.to_lower()
	return ["status", "lage", "uebersicht", "übersicht", "bericht"].any(func(t): return w.ends_with(t)) and not w.ends_with("anlage")


func _town_jobs_need(k: int) -> bool:
	var residents: int = sim.citizens.population_of(k)
	return residents >= 12 and sim.citizens.unemployed_of(k) >= maxi(8, int(ceil(float(residents) * 0.25)))


func _public_build_blockers(k: int) -> Array:
	var out: Array = []
	var depot: CityDepot = sim.towns.depot(k)
	for prj in sim.towns.mayors[k].projects.values():
		var work: Dictionary = sim.construction.public.get(str(prj.id), {})
		if str(work.get("status", "")) != "laufend":
			continue
		var res: Dictionary = depot.project_res.get(str(prj.id), {})
		var missing: Dictionary = {}
		for item in res.get("items", {}):
			var qty := int(res.items[item]) - int(res.get("reserved", {}).get(item, 0))
			if qty > 0:
				missing[item] = qty
		var crew: Dictionary = sim.crews.crew_for("pub", str(prj.id))
		if not missing.is_empty() or crew.is_empty() or not sim.crews.on_site("pub", str(prj.id)):
			out.append({"projekt": prj.id, "art": prj.kind, "resttage": int(work.get("days_left", 0)),
				"fehlt_material": missing, "bautrupp": "nicht zugeteilt" if crew.is_empty() else str(crew.state),
				"projekt_start_tag": int(work.get("start", 0))})
	return out.slice(0, 8)


func _public_build_board(k: int) -> Dictionary:
	var M: Mayor = sim.towns.mayors[k]
	var active := 0
	var blocked := 0
	var projects: Array = []
	for prj in M.projects.values():
		if str(prj.get("status", "")) in ["fertig", "abgelehnt", "abgebrochen"]:
			continue
		active += 1
		var work: Dictionary = sim.construction.public.get(str(prj.id), {})
		var waiting := str(work.get("waiting", ""))
		if waiting != "":
			blocked += 1
		projects.append({"id": str(prj.id), "art": str(prj.get("kind", "")), "status": str(prj.status),
			"viertel": str(prj.get("viertel", "")),
			"resttage": int(work.get("days_left", prj.get("days", 0))), "wartet_auf": waiting})
	var free_crews := 0
	for crew in sim.crews.crews.values():
		if str(crew.get("state", "")) == "frei":
			free_crews += 1
	var limit := maxi(3, int(ceil(float(sim.crews.crews.size()) * 0.6 / float(maxi(1, sim.towns.count())))))
	var depot: CityDepot = sim.towns.depot(k)
	var intake_blocked: bool = depot.backlog_units() > 0 and depot.roster().is_empty()
	return {"offen": active, "blockiert": blocked, "kapazitaet": limit, "bautrupps_frei_region": free_crews,
		"neues_bauprojekt_moeglich": active < limit and not intake_blocked,
		"wareneingang_ohne_personal": intake_blocked, "projekte": projects.slice(0, 12)}


func _office_overview(k: int) -> Dictionary:
	var M: Mayor = sim.towns.mayors[k]
	var apps: Array = []
	for app in sim.permits.apps.values():
		if app.status == "zur_entscheidung" and M._mine(str(app.parcel)):
			apps.append(str(app.id))
	var fin: Dictionary = M._assess_financing({})
	var nd: Dictionary = sim.town_plan.next_district(k, int(M.waiting) > 0, _town_jobs_need(k)) if sim.town_plan != null else {}
	var plan_txt := " STADTPLAN: %s" % str(nd.get("text", "")) if not nd.is_empty() else ""
	return {"ok": true, "uebersicht": true, "msg": "Lage %s: %s Anträge zur Entscheidung: %s.%s Handeln mit Amt {aktion: {action: ...}} – neue Einrichtungen mit kommunal_bauen {typ}." % [
		sim.towns.name_of(k), str(fin.msg), ", ".join(apps) if not apps.is_empty() else "keine", plan_txt]}


func _site_status(cid: int, id: String) -> Dictionary:
	var st: Dictionary = homes.sites[id]
	if int(st.cid) != cid:
		return {"ok": false, "msg": "Baustelle %s gehört dir nicht." % id}
	var app: Dictionary = sim.permits.apps.get(str(st.get("app", "")), {})
	var parts: Array = ["Baustelle %s (%s auf %s): Status %s" % [id, st.typ, st.parcel, st.status]]
	if not app.is_empty():
		parts.append("Bauantrag %s: %s" % [app.id, app.status])
	var miss: Dictionary = homes.missing(st)
	if not miss.is_empty():
		parts.append("fehlendes Material %s" % str(miss))
	if float(st.get("work", 0.0)) > 0.0:
		parts.append("Baufortschritt %d %%" % int(100.0 * float(st.get("progress", 0.0)) / float(st.work)))
	return {"ok": true, "msg": ", ".join(parts) + "."}


func _firm_overview(cid: int) -> Dictionary:
	var c = sim.company(cid)
	var vs: Array = []
	for v in sim.company_vehicles(cid):
		var d = sim.driver_of(v)
		vs.append("#%d %s (%s%s%s)" % [v.id, v.model, v.state, ", Fahrer %s" % d.name if d != null else ", ohne Fahrer", ", Auftrag %s" % v.contract_id if str(v.contract_id) != "" else ""])
	var step := _fleet_step(cid)
	var economy := homes.business_hint(cid)
	return {"ok": true, "uebersicht": true, "msg": "%s: Kasse %s, Personal %d, Fahrzeuge: %s.%s" % [c.company_name, Catalog.money(c.ledger.cash),
		sim.personnel.employed(cid).size(), ", ".join(vs) if not vs.is_empty() else "keine", (" Nächster Schritt: " + step) if step != "" else ""] + ((" Wirtschaftsaufbau: " + economy) if economy != "" else "")}


const OFFICE_PARAM_ALIASES := {"projekt": "project", "projekt_id": "project_id", "grundstuecke": "parcel_ids", "grundstücke": "parcel_ids",
	"begruendung": "reason", "begründung": "reason", "grund": "reason", "typ_code": "typ", "bestellung": "order_id", "bestell_id": "order_id"}


func _office_action(b: Dictionary, data: Dictionary) -> Dictionary:
	var k := int(b.get("amt", -1))
	if k < 0:
		return {"ok": false, "msg": "Du hast kein Amt."}
	var a = data.get("aktion", data.get("action"))
	if a is String:
		var raw := str(a).strip_edges()
		a = JSON.parse_string(raw) if raw.begins_with("{") else {"action": raw}
	if a is Dictionary and str(a.get("action", "")) in ["build_defense", "rebuild_building"]:   # Verteidigung und Wiederaufbau (EkoArms)
		return arms.office_action(b, k, a)
	if not (a is Dictionary) or str(a.get("action", "")).to_lower() in OVERVIEW_WORDS:   # 17.11.: "Tageslage prüfen" ohne aktion, "projekte", "kommunale_dienste"
		var ov := _office_overview(k)
		var want := str(a.get("einrichtung", a.get("typ", ""))) if a is Dictionary else ""
		var code := _municipal_code(want) if want != "" else ""
		if code != "" and ov.has("msg"):   # 19.11.: Juergen Kessler fragte 6x kommunale_dienste {einrichtung: polizei} – er wollte bauen
			ov.msg = str(ov.msg) + " Bauen: Amt {aktion: {action: \"kommunal_bauen\", typ: \"%s\", reason: ...}} (%s)." % [code, Municipal.TYPES[code].label]
		return ov
	if not Mayor.SCHEMA.has(str(a.get("action", ""))) and _looks_like_overview(str(a.get("action", ""))):   # 19.11.: "stadt_status"
		return _office_overview(k)
	if not Mayor.SCHEMA.has(str(a.get("action", ""))):
		return {"ok": false, "msg": "Amt braucht aktion: {\"action\": eine von %s, ...}. Parameter siehe mein_amt.aktionen." % ", ".join(Mayor.SCHEMA.keys())}
	for de in OFFICE_PARAM_ALIASES:   # 18.11.: Thomas Lindner schrieb projekt statt project
		if a.has(de) and not a.has(OFFICE_PARAM_ALIASES[de]):
			a[OFFICE_PARAM_ALIASES[de]] = a[de]
	if not a.has("reason"):
		a["reason"] = "Entscheidung von %s" % b.name
	var fix := normalize_office(a)
	if fix != "":
		return {"ok": false, "msg": fix}
	if str(a.action) == "infra_ausbau":
		var plant_code: String = {"wasserwerk": "WW-01", "hochbehaelter": "WT-01", "klaeranlage": "KA-01"}.get(str(a.get("anlage", "")), "")
		if plant_code != "":
			var present: bool = sim.municipal.facilities.values().any(func(f): return str(f.code) == plant_code and (plant_code == "KA-01" or int(f.town) == k))
			if not present:
				a["action"] = "kommunal_bauen"   # Ausbauen einer fehlenden Anlage meint zuerst den Neubau
				a["typ"] = plant_code
				a.erase("anlage")
	if str(a.action) == "propose_project":
		if str(a.get("project", "")) == "":
			if str(a.get("name", "")) != "":
				a["project"] = str(a.name)
			else:
				return {"ok": false, "msg": "propose_project braucht project (z. B. Stadtpark) und category (z. B. gruen). Wähle eine konkrete Bauidee."}
		if str(a.get("category", "")) == "":
			var idea := _plain(str(a.project))
			a["category"] = "gruen" if idea.contains("park") or idea.contains("garten") else ("sport" if idea.contains("sport") or idea.contains("stadion") else "familie")
	if str(a.action) == "viertel_erschliessen":
		var valid: Array = sim.town_plan.of(k).get("viertel", []) if sim.town_plan.has(k) else []
		var chosen: Dictionary = {}
		for v in valid:
			if str(v.id) == str(a.get("viertel", "")).to_upper():
				chosen = v
		if chosen.is_empty() or str(chosen.get("status", "")) == "erschlossen":
			var fresh: Dictionary = sim.town_plan.next_district(k, sim.housing.planning_aids().get("bedarf", 0) > 0)
			return {"ok": false, "msg": "Viertel %s ist in %s nicht mehr zu erschließen. Aktuelle Viertel: %s. %s" % [str(a.get("viertel", "")), sim.towns.name_of(k), ", ".join(valid.map(func(v): return "%s %s" % [v.id, v.status])), str(fresh.get("text", "Bitte den Stadtplan erneut beobachten."))]}
	if str(a.action) == "kommunal_bauen" and str(a.get("grundstueck", "")) != "":
		var code := str(a.get("typ", ""))
		var wanted := str(a.grundstueck)
		if not sim.services.utility_sites(k).any(func(site): return str(site.typ) == code and str(site.grundstueck) == wanted):
			return {"ok": false, "msg": "Grundstück %s ist für %s nicht mehr gültig. Wähle selbst einen aktuellen Standort aus versorgungsanlagen_standorte." % [wanted, code]}
	# Wiederholungsbremse (Partie 18.11.: Polizeiwache dreimal in zwei Minuten, jedes Mal "kein Grundstueck mit Strasse")
	# Dieselbe Aktion mit einer anderen Bestell-ID, Trassenoption oder einem anderen Standort
	# ist ein neuer Versuch. Nur die Begruendung darf die Sperre nicht umgehen.
	var fields: Array = a.keys()
	fields.sort()
	var key_parts: Array = []
	for field in fields:
		if str(field) not in ["reason", "warum"]:
			key_parts.append("%s=%s" % [str(field), JSON.stringify(a[field])])
	var key: String = "|".join(key_parts)
	var day := GameCalendar.day_of(sim.game_min)
	var fails: Dictionary = b.get("amt_fehl", {})
	var fe: Array = fails.get(key, [-1, 0])
	if int(fe[0]) == day and int(fe[1]) >= 2:
		return {"ok": false, "msg": "Heute schon %d-mal gescheitert (gleiche Lage wie eben) – ein weiterer Versuch ändert nichts.%s Nutze die Zeit anders (Bauanträge entscheiden, Personal, Stadtplan) und versuche es an einem späteren Tag." % [int(fe[1]), _plan_wait_text(k)]}
	var r: Dictionary = sim.towns.mayors[k].execute(a)
	if not bool(r.get("ok", false)):
		fails[key] = [day, (int(fe[1]) + 1) if int(fe[0]) == day else 1]
		b["amt_fehl"] = fails
	_event(b, "Amt: %s → %s" % [a.action, str(r.get("msg", "")).left(80)])
	return {"ok": bool(r.get("ok", false)), "msg": str(r.get("msg", ""))}


## Was die Stadt gerade baut und wann Bauland mit Strasse entsteht (Hinweis fuer die Wiederholungsbremse).
func _plan_wait_text(k: int) -> String:
	var M: Mayor = sim.towns.mayors[k]
	for prj in M.projects.values():
		if prj.has("road_plan") and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			var e: Dictionary = sim.construction.public.get(prj.id, {})
			return " Das Straßennetz %s (Viertel %s) ist %s – danach gibt es dort Grundstücke mit Straße." % [prj.id, str(prj.get("viertel", "Anschluss")),
				("in %d Tagen fertig%s" % [int(e.days_left), (" (" + str(e.waiting) + ")") if str(e.get("waiting", "")) != "" else ""]) if not e.is_empty() else str(prj.status)]
	var nd: Dictionary = sim.town_plan.next_district(k, int(M.waiting) > 0) if sim.town_plan != null else {}
	return (" Bauland braucht eine beauftragte Erschließung; prüfe freie Viertel und laufende Projekte.") if nd.has("aktion") else ""


## Amtshandlungen tolerant lesen (Partie 16.11.: priority als Wort, anlage "klaeanlage" oder "polizeiwache" bei infra_ausbau).
## Aendert a; Rueckgabe: Hinweis statt Ausfuehrung ("" = weiter).
const PRIORITY_WORDS := {"niedrig": 1, "low": 1, "gering": 1, "mittel": 3, "normal": 3, "medium": 3, "hoch": 4, "high": 4,
	"sehr hoch": 5, "dringend": 5, "kritisch": 5, "urgent": 5, "critical": 5}
const INFRA_PLANTS := ["wasserwerk", "hochbehaelter", "klaeranlage", "gleis"]
## Permits.mayor_decide kennt nur diese vier Werte; Wesen schreiben auch "genehmigt", "ja", "approve" (Woerter in _plain-Form).
const DECISION_WORDS := {
	"genehmigen": ["genehmigen", "genehmigt", "genehmigung", "ja", "yes", "approve", "approved", "zustimmen", "zugestimmt", "annehmen", "angenommen", "erteilen"],
	"bedingungen": ["bedingungen", "mitbedingungen", "unterbedingungen", "auflagen", "mitauflagen", "conditions", "bedingt"],
	"ablehnen": ["ablehnen", "abgelehnt", "ablehnung", "nein", "no", "reject", "rejected", "versagen", "verweigern"],
	"rueckfrage": ["rueckfrage", "rueckfragen", "nachfrage", "query", "nachbessern", "ueberarbeiten"]}


static func _plain(s: String) -> String:
	return s.strip_edges().to_lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss").replace(" ", "").replace("-", "").replace("_", "")


static func _best(word: String, options: Array, min_sim := 0.7) -> String:
	var w := _plain(word)
	var best := ""
	var best_s := 0.0
	for o in options:
		var s := w.similarity(_plain(str(o)))
		if w == _plain(str(o)) or (w.length() >= 4 and _plain(str(o)).begins_with(w)):
			s = 1.0
		if s > best_s:
			best_s = s
			best = str(o)
	return best if best_s >= min_sim else ""


## 19.11.: Thomas Roth "kindergarten" → Kita (Label "Kita" enthielt das Wort nicht)
const MUNICIPAL_WORDS := {"kindergarten": "kita", "kindertagesstaette": "kita", "polizei": "polizeiwache", "schule": "grundschule", "krankenhaus": "klinik"}


static func _municipal_code(word: String) -> String:
	var w := _plain(word)
	w = str(MUNICIPAL_WORDS.get(w, w))
	for code in Municipal.TYPES:
		var label := _plain(str(Municipal.TYPES[code].label))
		var dienst := _plain(str(Municipal.TYPES[code].get("dienst", "")))
		if w == _plain(code) or label.contains(w) or w.contains(dienst) and dienst != "" or w.similarity(label) >= 0.7:
			return code
	return ""


static func normalize_office(a: Dictionary) -> String:
	for key in ["priority"]:
		if a.get(key) is String and not str(a[key]).is_valid_int():
			var low := str(a[key]).strip_edges().to_lower()
			a[key] = int(PRIORITY_WORDS.get(low, 3))
	match str(a.get("action", "")):
		"decide_application":
			var d := _plain(str(a.get("decision", "")))
			for key in DECISION_WORDS:
				if d in DECISION_WORDS[key]:
					a["decision"] = key
			if str(a.get("decision", "")) not in DECISION_WORDS:
				return "decision muss genehmigen, bedingungen, ablehnen oder rueckfrage sein (nicht „%s“)." % str(a.get("decision", ""))
		"infra_ausbau":
			var want := str(a.get("anlage", ""))
			if _plain(want) in ["stadtlager", "lager", "bauhof"]:
				return "Das Stadtlager ist keine Versorgungsanlage. Für Personal am Wareneingang nutze Amt {aktion: {action: \"expand_depot\", kind: \"staff\", reason: \"Angelieferte Baustoffe einlagern\"}}; fehlende Projektware bestellt das Bauamt automatisch."
			var hit := _best(want, INFRA_PLANTS)
			if hit != "":
				a["anlage"] = hit
				return ""
			var code := _municipal_code(want)
			if code != "":
				return "%s ist keine Versorgungsanlage (infra_ausbau: %s). Kommunale Einrichtungen baust du mit Amt {aktion: {action: \"kommunal_bauen\", typ: \"%s\"}} (%s)." % [
					want, " | ".join(INFRA_PLANTS), code, str(Municipal.TYPES[code].label)]
			return "Unbekannte Versorgungsanlage '%s'. Möglich: %s; Stromtrassen und Wasserleitungen haben eigene Aktionen." % [want, " | ".join(INFRA_PLANTS)]
		"kommunal_bauen":
			var t := str(a.get("typ", ""))
			if not Municipal.TYPES.has(t):
				var code := _municipal_code(t)
				if code == "":   # 18.11.: "PW-01" statt PO-01 – Einrichtung aus der Begruendung erkennen ("Keine Polizeiwache vorhanden")
					var why := _plain(str(a.get("reason", "")))
					for c in Municipal.TYPES:
						if why.contains(_plain(str(Municipal.TYPES[c].label))):
							code = c
							break
				if code != "":
					a["typ"] = code
				else:
					return "Unbekannte kommunale Einrichtung '%s'. Wähle einen typ-Code aus mein_amt.stadtentwicklung.bauvorlagen oder beobachte die aktuellen Einrichtungen." % t
		"hire_staff":
			var dep := _plain(str(a.get("abteilung", "")))
			if dep != "" and dep not in ["verwaltung", "bauamt", "strassen", "pruefdienst"]:
				for c in Municipal.TYPES:
					var dienst := _plain(str(Municipal.TYPES[c].get("dienst", "")))
					if dienst != "" and (dep.contains(dienst) or dienst.contains(dep)):
						return "Personal für %s stellt der Dienst selbst ein, sobald die Einrichtung (%s) steht – hire_staff gilt nur für verwaltung, bauamt, strassen, pruefdienst. Stand der Dienste: Amt {aktion: {action: \"kommunale_dienste\"}}." % [
							str(Municipal.TYPES[c].get("dienst", "")), str(Municipal.TYPES[c].label)]
	return ""


## Kompakte Amtslage: Kennzahlen der Stadt bis etwa 6.000 Zeichen (groesste Teile zuletzt), Aktionen mit Parametern.
func office_obs(b: Dictionary) -> Dictionary:
	var k := int(b.get("amt", -1))
	if k < 0:
		return {}
	var ind: Dictionary = sim.towns.mayors[k].indicators()
	var next_step: Dictionary = ind.get("stadtplan_naechster_abschnitt", {}).duplicate(true)
	next_step.erase("aktion")
	var civic: Dictionary = ind.get("stadtentwicklung", {})
	var keys: Array = ind.keys()
	keys.sort_custom(func(x, y): return JSON.stringify(ind[x]).length() < JSON.stringify(ind[y]).length())
	var depot_info: Dictionary = ind.get("stadtlager", {})
	var blocked_businesses: Array = []
	for item in sim.biz.items.values():
		if str(item.get("status", "")) == "blockiert" and sim.towns.of_building(int(item.get("site", -1))) == k:
			blocked_businesses.append({"betrieb": str(item.get("id", "")), "name": str(item.get("name", "")),
				"gebaeude": int(item.get("site", -1)), "blockaden": item.get("blockers", [])})
	var out := {"stadt": sim.towns.name_of(k), "stadtplan": sim.town_plan.brief(k), "verkehrsstandorte": ind.get("verkehrsstandorte", {}), "stromtrassen": ind.get("stromtrassen", []),
		"kraftwerk_notfall": sim.plant.summary().get("notfall", {}),
		"bau_blockaden": _public_build_blockers(k), "bauprogramm": _public_build_board(k),
		"stadtwachstum": city_growth_status(k), "blockierte_betriebe": blocked_businesses.slice(0, 8),
		"stadtlager": {"vorschlaege": depot_info.get("vorschlaege", []), "blockaden": depot_info.get("blockaden", []),
			"bestellungen_offen": depot_info.get("bestellungen_offen", 0), "rueckstau_wareneingang_einheiten": depot_info.get("rueckstau_wareneingang_einheiten", 0),
			"personal_gesamt": depot_info.get("personal_gesamt", 0)},
		"versorgungsleitungen": ind.get("versorgungsleitungen", []),
		"versorgungsanlagen_standorte": ind.get("versorgungsanlagen_standorte", []),
		"naechster_ausbauschritt": next_step, "stadtplan_naechster_abschnitt": next_step, "stadtplan_erweiterung": ind.get("stadtplan_erweiterung", []),
		"stadtentwicklung": {"vision": civic.get("vision", ""), "bedarf": civic.get("bedarf", {}), "eigene_anlagen": civic.get("eigene_anlagen", []),
			"vorgemerkte_ideen": civic.get("vorgemerkte_ideen", []), "bauvorlagen": civic.get("bauvorlagen", {}).keys()},
		"verteidigung": arms.defense_obs(k),
		"gruenderstrategie": conflict.strategy_for_town(k),
		"bedrohung": conflict.assaults.values().filter(func(a): return int(a.stadt) == k),
		"firmen": sim.companies.filter(func(c): return c.is_active()).map(func(c): return {"firma": c.id, "name": c.company_name, "inhaber": c.player_name})}
	var zones: Dictionary = ind.get("flaechenplanung", {}).get("zonen", {})
	var local_businesses: Array = sim.biz.items.values().filter(func(item): return str(item.branch) != "transport" and str(item.status) != "geschlossen" and int(item.site) >= 0 and sim.towns.of_building(int(item.site)) == k)
	out["wirtschaftsaufbau"] = {"einwohner": ind.get("bevoelkerung", {}).get("einwohner", 0), "arbeitslos": ind.get("arbeit", {}).get("arbeitslos", 0),
		"offene_stellen": ind.get("arbeit", {}).get("offene_stellen", 0), "neue_betriebe": local_businesses.size(),
		"gewerbe_frei_mit_strasse": zones.get("gewerbe", {}).get("frei_mit_strasse", 0), "industrie_frei_mit_strasse": zones.get("industrie", {}).get("frei_mit_strasse", 0),
		"arbeitsplatzbedarf": _town_jobs_need(k),
		"hinweis": "Bei hoher Arbeitslosigkeit zuerst erschlossene Gewerbe- und Industriegrundstuecke sowie Anschluesse schaffen. Unternehmer gruenden dort Betriebe. Prestigeprojekte erst nach einer tragfaehigen Arbeitsplatzbasis."}
	var options: Array = []
	for district in sim.town_plan.of(k).get("viertel", []):
		if str(district.status) == "entwurf" and str(district.zone) != "gruen":
			options.append({"viertel": str(district.id), "zone": str(district.zone), "mitte": district.mitte,
				"entwuerfe": sim.town_plan.design_options(k, str(district.id)).slice(0, 4)})
	out["stadtplan_optionen"] = options.slice(0, 8)
	var size := 0
	var skipped: Array = []
	for key in keys:
		if out.has(key):
			continue
		var t := JSON.stringify(ind[key]).length()
		if size + t > 6000:
			skipped.append(key)
			continue
		out[key] = ind[key]
		size += t
	if not skipped.is_empty():
		out["ausgelassen"] = skipped
	var acts: Array = []
	for name in Mayor.SCHEMA:
		acts.append("%s(%s)" % [name, ", ".join(Mayor.SCHEMA[name].params.keys())])
	out["aktionen"] = "Amt {aktion: {action, ...}}: " + "; ".join(acts)
	out["aktionen_wichtig"] = {"expand_depot": Mayor.SCHEMA.expand_depot.params, "approve_procurement": Mayor.SCHEMA.approve_procurement.params,
		"stromtrasse_bauen": Mayor.SCHEMA.stromtrasse_bauen.params, "versorgungsleitung_bauen": Mayor.SCHEMA.versorgungsleitung_bauen.params,
		"infra_ausbau": Mayor.SCHEMA.infra_ausbau.params, "viertel_erschliessen": Mayor.SCHEMA.viertel_erschliessen.params}
	out["vorfaelle"] = sim.rivalry.incidents.slice(-8).map(func(i): return {"tag": GameCalendar.day_of(float(i.t)) + 1, "was": str(i.get("text", i.get("art", ""))).left(120)})
	out["schiedsrichter"] = "Bei Sabotage, Blockaden oder unfairem Wettbewerb kannst du einschreiten: warn_company, order_inspection, mediate_rivalry."
	out["hinweis"] = "Routinefälle erledigt die Verwaltung. Wähle selbst zwischen Wohnen, Arbeit, Versorgung, Verkehr und Stadtbild. stadtplan_optionen sind Vorschläge; eigene Standorte und Straßentrassen sind möglich. Prüfe bauprogramm und bau_blockaden vor neuen Baustellen. Hafen nur am Meer. Amtsgehalt: %s je Minute." % Catalog.money(MAYOR_SALARY)
	return out


## Branchen kurz: Name, was rein, was raus, Ausstattung (fuer die Gruendungsentscheidung des Wesens).
func _branch_menu(avail) -> Array:   # avail: Branche -> Gruendungskosten (ObservationBuilder._branches)
	var spec_all: Dictionary = Businesses.branches()
	var out: Array = []
	for key in (avail.keys() if avail is Dictionary else avail):
		var sp: Dictionary = spec_all.get(str(key), {})
		if sp.is_empty():
			continue
		var r: Dictionary = sp.get("rezept", {})
		out.append({"branche": str(key), "name": sp.get("label", key), "ein": r.get("ein", {}), "aus": r.get("aus", sp.get("feld", {}).get("artikel", "")),
			"kosten": int(avail.get(key, sp.get("ausstattung", 0))) if avail is Dictionary else sp.get("ausstattung", 0), "personal_min": sp.get("personal_min", 1)})
	return out


## Rangliste aller aktiven Firmen (Gewinn zuerst) mit Marktanteil am Transportumsatz.
func ranking() -> Array:
	var total := 0.0
	for c in sim.companies:
		if c.is_active():
			total += maxf(0.0, c.ledger.revenue())
	var out: Array = []
	for c in sim.companies:
		if not c.is_active():
			continue
		out.append({"firma": c.company_name, "chef": c.player_name, "gewinn": int(c.ledger.profit()), "kasse": int(c.ledger.cash),
			"umsatz": int(c.ledger.revenue()), "marktanteil_prozent": int(100.0 * maxf(0.0, c.ledger.revenue()) / maxf(1.0, total)),
			"ruf": int(c.reputation), "fahrzeuge": sim.company_vehicles(c.id).size(), "wesen": firm_being(c.id) != ""})
	out.sort_custom(func(a, b2): return int(a.gewinn) > int(b2.gewinn))
	return out


## Fuer den Betreiber (Schwarm): welche Wesen es gibt und welche Seele sie haben.
func beings_info() -> Array:
	var out: Array = []
	for b in beings.values():
		if int(b.get("amt", -1)) >= 0 and not sim.town_ready(int(b.amt)):
			continue   # Wildnis: Buergermeister wachen erst mit der Gruendung ihrer Stadt auf (spart Modellzeit fuer die Unternehmer)
		var rolle := "buergermeister" if int(b.get("amt", -1)) >= 0 else ("unternehmer" if int(b.get("firma", -1)) >= 0 else "wesen")
		var seele := str(b.get("seele", ""))
		if seele == "" and str(b.name) == "Lumo":
			seele = "lumo"
		var firma := ""
		if int(b.get("firma", -1)) >= 0 and sim.company(int(b.firma)) != null:
			firma = str(sim.company(int(b.firma)).company_name)
		out.append({"name": b.name, "art": b.art, "rolle": rolle, "seele": seele, "firma": firma,
			"stadt": sim.towns.name_of(int(b.amt)) if int(b.get("amt", -1)) >= 0 else sim.towns.name_of(sim.city.town_of(tile_of(b)))})
	return out


# ------------------------------------------------------------------ Ablauf (15.11.2026)
## Ersatz fuer Ekos Skripte: Das Wesen schickt bis zu ABLAUF_MAX Handlungen auf einmal. Die Welt fuehrt sie der Reihe nach aus,
## wartet nach MoveTo auf die Ankunft und nach Rest auf das Ende der Pause und bricht beim ersten Fehlschlag ab. Kein Code wird
## ausgefuehrt; jeder Schritt laeuft durch dieselben Regeln wie eine einzelne Handlung.
const ABLAUF_MAX := 30


func _start_plan(b: Dictionary, data: Dictionary) -> Dictionary:
	var steps = data.get("schritte", data.get("steps"))
	if steps is String:
		steps = JSON.parse_string(steps)
	if not (steps is Array) or steps.is_empty():
		return {"ok": false, "msg": "Ablauf braucht schritte: [{\"type\": \"...\", \"data\": {...}}, ...] (höchstens %d)." % ABLAUF_MAX}
	var clean: Array = []
	for s in steps.slice(0, ABLAUF_MAX):
		if s is Dictionary and s.has("type") and str(s.type).to_lower() in ["wait", "warten"]:
			continue   # 18.11.: der Ablauf wartet von selbst auf die Ankunft – "wait" brach ihn ab
		if s is Dictionary and s.has("type") and str(s.type) != "Ablauf":
			clean.append({"type": str(s.type), "data": s.get("data", {}) if s.get("data", {}) is Dictionary else {}})
	if clean.is_empty():
		return {"ok": false, "msg": "Keine gültigen Schritte im Ablauf."}
	b.ablauf = clean
	b.ablauf_log = []
	_event(b, "startet einen Ablauf mit %d Schritten" % clean.size())
	_run_plan(b)
	var left: int = (b.ablauf as Array).size()
	var log: Array = b.ablauf_log
	var failed: bool = not log.is_empty() and str(log[-1]).begins_with("FEHLER")
	return {"ok": not failed, "msg": ("Ablauf abgebrochen: %s" % log[-1]) if failed else ("Ablauf läuft: %d von %d Schritten erledigt, %d folgen automatisch (siehe ablauf in observe)." % [clean.size() - left, clean.size(), left]),
		"ergebnisse": log.slice(-8)}


func _run_plan(b: Dictionary) -> void:
	var plan: Array = b.ablauf
	while not plan.is_empty():
		if not (b.mover as Mover).arrived() or float(b.get("rest_left", 0.0)) > 0.0:
			return
		var s: Dictionary = plan.pop_front()
		var r: Dictionary = input(str(b.name), str(s.type), s.data, true)
		var log: Array = b.ablauf_log
		log.append(("%s: %s" % [s.type, str(r.get("msg", "")).left(90)]) if bool(r.get("ok", false)) else ("FEHLER %s: %s" % [s.type, str(r.get("msg", "")).left(120)]))
		if log.size() > 30:
			b.ablauf_log = log.slice(-30)
		if not bool(r.get("ok", false)):
			plan.clear()
			_event(b, "Ablauf abgebrochen bei %s" % s.type)
			return
	if (b.get("ablauf_log", []) as Array).size() > 0 and plan.is_empty() and not str(b.ablauf_log[-1]).begins_with("FEHLER"):
		pass


## Sekunden seit der letzten eigenen Handlung eines Wesens (INF, wenn es noch nie gehandelt hat).
func idle_s(b: Dictionary) -> float:
	if not b.has("last_act"):
		return INF
	return (Time.get_ticks_msec() - int(b.last_act)) / 1000.0


func firm_idle_s(cid: int) -> float:
	var n := firm_being(cid)
	return INF if n == "" else idle_s(beings[n])


func office_idle_s(k: int) -> float:
	for b in beings.values():
		if int(b.get("amt", -1)) == k:
			return idle_s(b)
	return INF


# ------------------------------------------------------------------ Hilfen
func _at_source(b: Dictionary) -> bool:
	var t := tile_of(b)
	for s in sources():
		if maxi(absi(int(s.feld[0]) - t.x), absi(int(s.feld[1]) - t.y)) <= SOURCE_REACH:
			return true
	for tw in sim.city.towns:   # auch direkt am Gebaeude (15.11.: Lindner stand am Bauhof, 7 Felder vom Eingang)
		var bd: Dictionary = sim.city.building(int(tw.get("bauhof", -1)))
		if not bd.is_empty() and _building_dist(t, bd) <= SOURCE_REACH:
			return true
	return false


## Naechster Bauhof mit Feld und Entfernung (fuer Fehlermeldungen).
func _source_hint(b: Dictionary) -> String:
	var t := tile_of(b)
	var best := {}
	for s in sources():
		var d := _dist(t, Vector2i(int(s.feld[0]), int(s.feld[1])))
		if best.is_empty() or d < int(best.d):
			best = {"name": s.name, "feld": s.feld, "d": d}
	if best.is_empty():
		return ""
	return " Der nächste Bauhof (%s) hat seinen Eingang bei Feld %d,%d, %d Felder entfernt – MoveTo dorthin (höchstens %d Felder Abstand)." % [best.name, int(best.feld[0]), int(best.feld[1]), int(best.d), SOURCE_REACH]


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
		var saved: Dictionary = {"name": b.name, "art": b.art, "x": b.mover.pos.x, "y": b.mover.pos.y, "held": b.held, "events": b.events,
			"geld": float(b.get("geld", 0.0)), "job": str(b.get("job", "")), "grundstueck": str(b.get("grundstueck", "")),
			"done_jobs": int(b.get("done_jobs", 0)), "firma": int(b.get("firma", -1)), "zuhause": str(b.get("zuhause", "")),
			"akku": float(b.get("akku", 100.0)), "nass": float(b.get("nass", 0.0)), "kalt": float(b.get("kalt", 0.0)),
			"amt": int(b.get("amt", -1)), "seele": str(b.get("seele", "")), "orte": b.get("orte", {}), "besucht": b.get("besucht", {}),
			"ziel": b.get("ziel", {}), "ziele_alt": b.get("ziele_alt", []), "gesundheit": float(b.get("gesundheit", 100.0)), "waffen": b.get("waffen", []),
			"vergehen": int(b.get("vergehen", 0)), "out_left": float(b.get("out_left", 0.0)), "custody_left": float(b.get("custody_left", 0.0)),
			"startkapital": bool(b.get("startkapital", false))}
		if b.has("fracht_auftrag"):
			saved["fracht_auftrag"] = b.fracht_auftrag
		bs.append(saved)
	return {"blocks": bl, "beings": bs, "chat": chat, "jobs": jobs, "next_job": _next_job, "houses": houses, "arms": arms.to_dict(), "estates": estates.to_dict(), "homes": homes.to_dict(), "conflict": conflict.to_dict(),
		"towns_funded": towns_funded}


func from_dict(d: Dictionary) -> void:
	blocks.clear()
	beings.clear()
	for e in d.get("blocks", []):
		blocks[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = str(e[3])
	_no_estate = true
	for e in d.get("beings", []):
		join(str(e.name), str(e.get("art", "mensch")))
		var b: Dictionary = beings[str(e.name)]
		b.mover.pos = Vector2(float(e.x), float(e.y))
		b.held = e.get("held", [])
		b.events = e.get("events", [])
		for k in ["geld", "job", "grundstueck", "done_jobs", "firma", "zuhause", "akku", "nass", "kalt", "amt", "seele", "orte", "besucht", "ziel", "ziele_alt", "gesundheit", "waffen", "vergehen", "out_left", "custody_left", "startkapital"]:
			if e.has(k):
				b[k] = e[k]
		if e.get("fracht_auftrag", {}) is Dictionary and not (e.get("fracht_auftrag", {}) as Dictionary).is_empty():
			b["fracht_auftrag"] = e.fracht_auftrag
	chat = d.get("chat", [])
	jobs = d.get("jobs", {})
	_next_job = int(d.get("next_job", 1))
	_no_estate = false
	towns_funded = d.get("towns_funded", {})
	houses = d.get("houses", {})
	arms.from_dict(d.get("arms", {}))
	estates.from_dict(d.get("estates", {}))
	homes.from_dict(d.get("homes", {}))
	conflict.from_dict(d.get("conflict", {}))
	for b in beings.values():   # eigene Grundstuecke wieder begehbar
		open_plot(str(b.get("grundstueck", "")))


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
