class_name RailTraffic
extends RefCounted
## Regionalbahn (Auftrag 22 Phase 6 Schritt 2, docs/INFRASTRUCTURE.md). Eine Linie faehrt alle Bahnhoefe in Streckenreihenfolge ab
## (RailNet: S1, S2, ... schliessen aneinander an). Zwei Triebwagen pendeln, je einer ab jedem Endbahnhof. Fahrweg = Zellfolge der
## Linie (Bahnhofsgleis, Strecke, naechstes Bahnhofsgleis, ...); Position eines Zugs = Abstand in Feldern entlang dieses Wegs.
## Blocksicherung: Jeder Streckenabschnitt zwischen zwei Halten ist ein Block, den hoechstens ein Zug belegt (beide Richtungen,
## eingleisig). Ein Zug faehrt erst ab, wenn der Block frei ist und im Zielbahnhof ein Gleis frei ist (Haupt- und Ausweichgleis);
## sonst zeigt das Ausfahrsignal Halt und er wartet (Verspaetung). So kreuzen die Zuege nur in Bahnhoefen.
## Fahrplan: Soll-Zeiten aus Fahrzeit (Laenge / SPEED) und Haltezeit; Ist minus Soll = Verspaetung, am Endbahnhof wird mit der
## Wendezeit aufgeholt. Bewegung kontinuierlich in Spielminuten (Simulation.step); gespeichert werden die Zuege, der Fahrweg wird
## aus dem Netz neu abgeleitet.

const SPEED := 3.0            # Felder je Spielminute (doppelt so schnell wie ein Lkw: CityFleet.SPEED 3 Felder/s = 1,5 Felder/Spielminute)
const DWELL := 4.0            # Halt an einem Zwischenbahnhof (Spielminuten)
const TURN := 12.0            # Wendezeit am Endbahnhof (Spielminuten), mindestens TURN_MIN bei Verspaetung
const TURN_MIN := 4.0
const TRAINS := 2
const CARS := 2               # Wagen je Triebwagen
const CAR_LEN := 2.6          # Laenge eines Wagens in Feldern (Darstellung)

var sim
var path: Array = []          # Vector2i: Fahrweg der Linie
var stops: Array = []         # [{town, pos (Feld-Index entlang path), from, to (Bereich des Bahnhofsgleises in path), loop_dir: Vector2i}]
var trains: Array = []        # [{id, pos, dir, state: halt|fahrt|wartet, stop, target, until, planned, delay, track (0 Haupt, 1 Ausweiche), trips, cells}]
var blocks := {}              # Block-Index (zwischen Halt i und i+1) -> Zug-ID
var stats := {"fahrten": 0, "felder": 0.0, "wartezeit": 0.0, "kreuzungen": 0}


func setup(simulation) -> void:
	sim = simulation


func enabled() -> bool:
	return sim != null and sim.rail != null and sim.rail.is_built() and not sim.rail.edges.is_empty()


## Fahrweg und Halte aus dem Netz (einmal, nach dem Bau bzw. nach dem Laden).
func ensure() -> bool:
	if not path.is_empty():
		return true
	if not enabled():
		return false
	var R: RailNet = sim.rail
	var chain: Array = [R.edges[0]]
	for i in range(1, R.edges.size()):   # zusammenhaengende Kette ab dem ersten Abschnitt
		if int(R.edges[i].a) != int(chain[-1].b):
			break
		chain.append(R.edges[i])
	var seq: Array = [int(chain[0].a)]
	for e in chain:
		seq.append(int(e.b))
	for i in seq.size():
		var st: Dictionary = R.stations[str(seq[i])]
		var entry: Array = chain[i - 1].cells[-1] if i > 0 else []
		var exit_e: Array = chain[i].cells[0] if i < chain.size() else []
		var tr: Array = st.track.map(func(a): return Vector2i(int(a[0]), int(a[1])))
		# Bahnhofsgleis so durchfahren, dass es am Ende der Ausfahrt endet (bzw. an der Einfahrt beginnt)
		var e0: Array = st.ends[0]
		var forward: bool
		if not entry.is_empty():
			forward = int(entry[0]) == int(e0[0]) and int(entry[1]) == int(e0[1])
		else:
			forward = not (int(exit_e[0]) == int(e0[0]) and int(exit_e[1]) == int(e0[1]))
		if not forward:
			tr.reverse()
		var from := path.size()
		path.append_array(tr)
		var stop_pos := float(from) + float(tr.size() - 1) * 0.5
		if not entry.is_empty() and not exit_e.is_empty() and int(entry[0]) == int(exit_e[0]) and int(entry[1]) == int(exit_e[1]):
			var back := tr.duplicate()   # Ein- und Ausfahrt am selben Ende: Kopfbahnhof, der Zug wendet am Prellbock
			back.reverse()
			path.append_array(back.slice(1))
			stop_pos = float(from + tr.size() - 1)
		var ld: Array = st.get("loop_dir", [0, 0])
		stops.append({"town": int(seq[i]), "pos": stop_pos, "from": from, "to": path.size() - 1, "loop_dir": Vector2i(int(ld[0]), int(ld[1])),
			"loop": not st.get("loop", []).is_empty()})
		if i < chain.size():
			for a in chain[i].cells:
				path.append(Vector2i(int(a[0]), int(a[1])))
	if trains.is_empty():
		_start_trains()
	return true


## Fahrplan: RB1 ab dem ersten, RB2 ab dem letzten Bahnhof. RB2 faehrt so viel spaeter ab, dass sich beide planmaessig im mittleren
## Bahnhof treffen (gleichzeitige Abfahrt liess sie sich mitten im Block begegnen: 150 Minuten Wartezeit je Umlauf, Probe 13.11.);
## die Linie ist fast symmetrisch, daher liegt auch die Rueckkreuzung in einem Bahnhof. Bei nur zwei Halten faehrt ein Zug.
func _start_trains() -> void:
	var now: float = sim.game_min
	var last := stops.size() - 1
	var n_trains := 1 if stops.size() <= 2 else mini(TRAINS, 2)
	var m := stops.size() / 2
	var t_a := (float(stops[m].pos) - float(stops[0].pos)) / SPEED + DWELL * float(m - 1)
	var t_b := (float(stops[last].pos) - float(stops[m].pos)) / SPEED + DWELL * float(last - m - 1)
	var offset := maxf(0.0, t_a - t_b)
	for n in n_trains:
		var at := 0 if n == 0 else last
		var dep := now + TURN + (offset if n == 1 else 0.0)
		trains.append({"id": "RB%d" % (n + 1), "pos": float(stops[at].pos), "dir": 1 if n == 0 else -1, "state": "halt", "stop": at, "target": at,
			"until": dep, "planned": dep, "delay": 0.0, "track": 0, "trips": 0, "cells": 0.0})


func update(dt: float) -> void:
	if not ensure():
		return
	var dmin := dt * Catalog.GAME_MIN_PER_SIM_SEC
	var now: float = sim.game_min
	for t in trains:
		match str(t.state):
			"halt", "wartet":
				if now >= float(t.until):
					_depart(t, now)
				if str(t.state) == "wartet":
					stats.wartezeit = float(stats.wartezeit) + dmin
			"fahrt":
				_move(t, dmin, now)


func _block(i: int, j: int) -> int:
	return mini(i, j)


## Belegung eines Bahnhofs: Zuege, die dort halten oder ihn als Ziel haben.
func _occupancy(s: int, except: String = "") -> Array:
	return trains.filter(func(t): return str(t.id) != except and ((str(t.state) != "fahrt" and int(t.stop) == s) or (str(t.state) == "fahrt" and int(t.target) == s)))


func capacity(s: int) -> int:
	return 2 if bool(stops[s].get("loop", false)) else 1


func _depart(t: Dictionary, now: float) -> void:
	var s := int(t.stop)
	var d := int(t.dir)
	if s + d < 0 or s + d >= stops.size():   # Endbahnhof: wenden
		d = -d
		t.dir = d
	var j := s + d
	var b := _block(s, j)
	var why := ""
	if blocks.has(b) and str(blocks[b]) != str(t.id):
		why = "Block belegt"
	elif _occupancy(j, str(t.id)).size() >= capacity(j):
		why = "Zielbahnhof belegt"
	if why != "":
		t.state = "wartet"
		t["grund"] = why
		return
	blocks[b] = t.id
	t.state = "fahrt"
	t.target = j
	t.erase("grund")
	t.delay = maxf(0.0, now - float(t.planned))
	var dist := absf(float(stops[j].pos) - float(t.pos))
	t.planned = float(t.planned) + dist / SPEED   # Soll-Ankunft


func _move(t: Dictionary, dmin: float, now: float) -> void:
	var j := int(t.target)
	var goal := float(stops[j].pos)
	var step := SPEED * dmin
	var left := goal - float(t.pos)
	if absf(left) <= step:
		t.pos = goal
		t.cells = float(t.cells) + absf(left)
		stats.felder = float(stats.felder) + absf(left)
		_arrive(t, now)
		return
	t.pos = float(t.pos) + signf(left) * step
	t.cells = float(t.cells) + step
	stats.felder = float(stats.felder) + step


func _arrive(t: Dictionary, now: float) -> void:
	var j := int(t.target)
	blocks.erase(_block(int(t.stop), j))
	var others := _occupancy(j, str(t.id)).filter(func(o): return str(o.state) != "fahrt")
	t.track = 1 if not others.is_empty() and others.any(func(o): return int(o.track) == 0) else 0
	if not others.is_empty():
		stats.kreuzungen = int(stats.kreuzungen) + 1
	t.stop = j
	t.state = "halt"
	t.delay = maxf(0.0, now - float(t.planned))
	var terminus := j == 0 or j == stops.size() - 1
	var dwell := DWELL
	if terminus:
		t.trips = int(t.trips) + 1
		stats.fahrten = int(stats.fahrten) + 1
		dwell = maxf(TURN_MIN, TURN - float(t.delay))   # Verspaetung in der Wendezeit aufholen
	t.until = now + dwell
	t.planned = float(t.planned) + (TURN if terminus else DWELL)


# ------------------------------------------------------------------ Darstellung
## Weltposition (Weltmass, Feld = 32) und Fahrtrichtung an einer Stelle des Fahrwegs; im Bahnhof auf dem Ausweichgleis versetzt.
func world_at(pos: float, track: int = 0) -> Dictionary:
	var n := path.size()
	var p := clampf(pos, 0.0, float(n - 1))
	var i := int(floor(p))
	var j := mini(i + 1, n - 1)
	var f := p - float(i)
	var a: Vector2 = (Vector2(path[i]) + Vector2(0.5, 0.5)) * 32.0
	var b: Vector2 = (Vector2(path[j]) + Vector2(0.5, 0.5)) * 32.0
	var h: Vector2 = (b - a) if j != i else ((a - (Vector2(path[i - 1]) + Vector2(0.5, 0.5)) * 32.0) if i > 0 else Vector2(1, 0))
	var w := a.lerp(b, f)
	if track == 1:
		for s in stops:
			if p >= float(s.from) and p <= float(s.to):
				var edge := minf(p - float(s.from), float(s.to) - p)   # Weiche: weich auf das Ausweichgleis
				w += Vector2(s.loop_dir) * 32.0 * clampf(edge, 0.0, 1.0)
				break
	return {"world": w, "heading": h.normalized() if h != Vector2.ZERO else Vector2(1, 0)}


## Wagen eines Zugs (pos = Zugmitte): Weltposition und Blickrichtung je Wagen, Kopf zuerst. Der letzte Wagen ist ein Steuerwagen
## und blickt nach hinten (Triebwagen mit Fuehrerstand an beiden Enden).
func cars_of(t: Dictionary) -> Array:
	var out: Array = []
	var d := float(t.dir)
	for c in CARS:
		var pc := float(t.pos) + d * (CAR_LEN * float(CARS - 1) * 0.5 - float(c) * CAR_LEN)
		var w := world_at(pc, int(t.track))
		w["heading"] = w.heading * d * (-1.0 if c == CARS - 1 and CARS > 1 else 1.0)
		w["front"] = c == 0
		out.append(w)
	return out


## Signal an der Ausfahrt von Halt s in Richtung d: Fahrt (gruen), wenn der Block dahinter frei ist.
func signal_clear(s: int, d: int) -> bool:
	var j := s + d
	if j < 0 or j >= stops.size():
		return true
	return not blocks.has(_block(s, j))


func stop_of_town(k: int) -> int:
	for i in stops.size():
		if int(stops[i].town) == k:
			return i
	return -1


func summary() -> Dictionary:
	ensure()
	var tl: Array = []
	for t in trains:
		var where := ""
		if str(t.state) == "fahrt":
			where = "%s → %s" % [sim.towns.name_of(int(stops[int(t.stop)].town)), sim.towns.name_of(int(stops[int(t.target)].town))]
		else:
			where = "in %s" % sim.towns.name_of(int(stops[int(t.stop)].town))
		tl.append({"zug": t.id, "status": t.state, "ort": where, "verspaetung_min": snappedf(float(t.delay), 0.1), "grund": str(t.get("grund", "")),
			"fahrten": int(t.trips)})
	return {"linie": stops.map(func(s): return sim.towns.name_of(int(s.town))), "zuege": tl, "laenge_felder": path.size(),
		"fahrzeit_min": snappedf(float(path.size()) / SPEED, 1.0), "statistik": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"trains": trains, "blocks": blocks, "stats": stats}


func from_dict(d: Dictionary) -> void:
	trains = d.get("trains", [])
	for t in trains:
		t.stop = int(t.stop)
		t.target = int(t.target)
		t.dir = int(t.dir)
		t.track = int(t.track)
	blocks = {}
	var bl: Dictionary = d.get("blocks", {})
	for k in bl:
		blocks[int(k)] = bl[k]
	stats = d.get("stats", stats)
