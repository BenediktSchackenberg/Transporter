class_name RailTraffic
extends RefCounted
## Regionalbahn (Auftrag 22 Phase 6 Schritt 2, docs/INFRASTRUCTURE.md). Eine Linie faehrt alle Bahnhoefe in Streckenreihenfolge ab
## (RailNet: S1, S2, ... schliessen aneinander an). Zwei Triebwagen pendeln, je einer ab jedem Endbahnhof. Fahrweg = Zellfolge der
## Linie (Bahnhofsgleis, Strecke, naechstes Bahnhofsgleis, ...); Position eines Zugs = Abstand in Feldern entlang dieses Wegs.
## Blocksicherung: Jeder Streckenabschnitt zwischen zwei Halten ist ein Block, den hoechstens ein Zug belegt (beide Richtungen,
## eingleisig). Ein Zug faehrt erst ab, wenn der Block frei ist und im Zielbahnhof ein Gleis frei ist (Haupt- und Ausweichgleis);
## sonst zeigt das Ausfahrsignal Halt und er wartet (Verspaetung). So kreuzen die Zuege nur in Bahnhoefen.
## Schritt 3 Fahrgaeste und Betrieb: Taeglich entstehen Reisewuensche zwischen allen Haltepaaren (Ausflugs-/Einkaufsverkehr nach den
## Einwohnern beider Orte, dazu die Bahnpendler aus Commuting); sie warten am Bahnsteig (je Ziel), steigen beim Halt in Zuege in
## ihre Richtung (bis SEATS) und am Ziel aus. Fahrgeld (Grundpreis + je Feld) zahlen die Haushalte (H0) an die gemeinsame
## Regionalbahngesellschaft N0; ohne Zugbegleiter faehrt FARE_DODGE schwarz. N0 traegt die Betriebskosten je gefahrenem Feld
## (Diesel, Wartung an S0) und erhaelt den Landeszuschuss je Feld (Regionalisierungsmittel, X0). Monatsende: Ergebnis von N0 nach
## Einwohneranteilen an die Staedte bzw. von ihnen ausgeglichen (wie die Kraftwerksgesellschaft). Personal: Municipal BG-01
## (regional, Sitz im Bahnhof der groessten Stadt) mit Triebfahrzeugfuehrern und Zugbegleitern; Zug n faehrt nur, wenn mindestens
## n+1 Triebfahrzeugfuehrer angestellt sind.
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
const SEATS := 160            # Plaetze je Triebwagen (zwei Wagen)
const ACCT := "N0"            # Regionalbahngesellschaft (gemeinsam)
const FARE_BASE := 1.5        # EUR je Fahrt
const FARE_CELL := 0.004      # EUR je Feld Fahrweg (400 Felder = 3,10 EUR)
const FARE_DODGE := 0.25      # Anteil Schwarzfahrer ohne Zugbegleiter
const COST_CELL := 0.5        # Betriebskosten je gefahrenem Feld und Zug (Diesel, Wartung)
const SUBSIDY_CELL := 0.45    # Landeszuschuss je gefahrenem Feld und Zug (Regionalisierungsmittel; Personal erstattet das Land ueber BG-01)
const LEISURE := 0.0002       # Reisewuensche je Tag und Richtung = LEISURE x Einwohner A x Einwohner B
const COMMUTE_TRIPS := 0.3    # Fahrten je Bahnpendler, Tag und Richtung (Rest Homeoffice, Mitfahrt)
const STAFF_CODE := "BG-01"

var sim
var path: Array = []          # Vector2i: Fahrweg der Linie
var stops: Array = []         # [{town, pos (Feld-Index entlang path), from, to (Bereich des Bahnhofsgleises in path), loop_dir: Vector2i}]
var trains: Array = []        # [{id, pos, dir, state: halt|fahrt|wartet, stop, target, until, planned, delay, track (0 Haupt, 1 Ausweiche), trips, cells}]
var blocks := {}              # Block-Index (zwischen Halt i und i+1) -> Zug-ID
var stats := {"fahrten": 0, "felder": 0.0, "wartezeit": 0.0, "kreuzungen": 0, "fahrgaeste": 0, "erloes": 0.0, "schwarz": 0, "kosten": 0.0, "zuschuss": 0.0}
var waiting := {}             # Stadt (str) -> {Ziel-Stadt (str) -> Anzahl (float, Bruchteile sammeln sich)}
var by_town := {}             # Stadt (str) -> {ein, aus}
var last_settle := {}
var facility := ""            # Municipal BG-01
var _cells_acc := 0.0         # gefahrene Felder seit der letzten Abrechnung


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(func(_d): _on_day())
	sim.month_changed.connect(func(_m): settle())


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
	_ensure_staff()
	return true


## Betriebsstelle der Regionalbahn (Municipal BG-01) im Bahnhof der einwohnerstaerksten Stadt; sofort erstes Personal einstellen.
func _ensure_staff() -> void:
	var M = sim.municipal
	if M == null or not M.enabled():
		return
	if facility != "" and M.facilities.has(facility):
		return
	for f in M.facilities.values():
		if str(f.code) == STAFF_CODE:
			facility = f.id
			return
	var best := -1
	for s in stops:
		if best < 0 or sim.citizens.population_of(int(s.town)) > sim.citizens.population_of(best):
			best = int(s.town)
	var st: Dictionary = sim.rail.station_of(best)
	if st.is_empty():
		return
	var b: Dictionary = sim.city.building(int(st.building))
	var sprite := str(b.get("sprite", ""))
	var f: Dictionary = M.register(best, STAFF_CODE, int(st.building))
	b["sprite"] = sprite   # das Empfangsgebaeude behaelt sein Bild (Ausrichtung h/v)
	b["name"] = "%s (Betriebsstelle Regionalbahn)" % st.name
	for ab in sim.events.added_buildings:
		if int(ab.x) == int(b.x) and int(ab.y) == int(b.y):
			ab["sprite"] = sprite
	M._share_regional(f)
	facility = f.id
	M._hire(f, M._staff_index())


func drivers() -> int:
	return sim.municipal.staff_count(facility, "lokfuehrer") if facility != "" and sim.municipal != null else 0


func conductors() -> int:
	return sim.municipal.staff_count(facility, "zugbegleiter") if facility != "" and sim.municipal != null else 0


func _key(s: int) -> String:
	return str(int(stops[s].town))


## Taeglicher Reisebedarf je Haltepaar und Betriebsabrechnung (Kosten, Zuschuss).
func _on_day() -> void:
	if not ensure():
		return
	var pend: Dictionary = sim.commute.stats.get("bahn_paare", {}) if sim.commute != null else {}
	for a in stops.size():
		var ka := _key(a)
		var pa := float(sim.citizens.population_of(int(stops[a].town)))
		if not waiting.has(ka):
			waiting[ka] = {}
		for b in stops.size():
			if a == b:
				continue
			var kb := _key(b)
			var pb := float(sim.citizens.population_of(int(stops[b].town)))
			var n := LEISURE * pa * pb + COMMUTE_TRIPS * float(int(pend.get("%s|%s" % [ka, kb], 0)) + int(pend.get("%s|%s" % [kb, ka], 0)))
			waiting[ka][kb] = float(waiting[ka].get(kb, 0.0)) + n
	_book_operation()


## Betriebskosten und Landeszuschuss nach gefahrenen Feldern.
func _book_operation() -> void:
	if _cells_acc <= 0.0:
		return
	var cost := _cells_acc * COST_CELL
	var sub := _cells_acc * SUBSIDY_CELL
	sim.economy.transfer(ACCT, "S0", cost)
	sim.economy.transfer("X0", ACCT, sub)
	stats.kosten = float(stats.kosten) + cost
	stats.zuschuss = float(stats.zuschuss) + sub
	_cells_acc = 0.0


## Monatsausgleich der Regionalbahngesellschaft nach Einwohneranteilen.
func settle() -> void:
	_book_operation()
	var bal := float(sim.economy.accounts.get(ACCT, 0.0))
	if is_zero_approx(bal) or stops.is_empty():
		return
	var total := 0.0
	for s in stops:
		total += float(maxi(1, sim.citizens.population_of(int(s.town))))
	var parts := {}
	for s in stops:
		var k := int(s.town)
		var amt := bal * float(maxi(1, sim.citizens.population_of(k))) / total
		if amt >= 0.0:
			sim.economy.transfer(ACCT, Towns.account_of(k), amt)
		else:
			sim.economy.transfer(Towns.account_of(k), ACCT, -amt)
		parts[str(k)] = snappedf(amt, 0.01)
	last_settle = {"ergebnis": snappedf(bal, 0.01), "anteile": parts, "tag": GameCalendar.day_of(sim.game_min)}
	sim.log_event("Regionalbahngesellschaft: Monatsergebnis %s, %s nach Einwohneranteilen." % [Catalog.money(bal),
		"an die Städte ausgeschüttet" if bal >= 0.0 else "von den Städten ausgeglichen"], "info")


func fare(a: int, b: int) -> float:
	return snappedf(FARE_BASE + FARE_CELL * absf(float(stops[b].pos) - float(stops[a].pos)), 0.01)


## Abfahrt in s Richtung d: Wartende mit Ziel in Fahrtrichtung steigen ein (Platz SEATS) und zahlen.
func _board(t: Dictionary, s: int, d: int) -> void:
	var load: Dictionary = t.get("load", {})
	var ks := _key(s)
	var q: Dictionary = waiting.get(ks, {})
	var on := 0
	var revenue := 0.0
	var dodge := 0
	var seats := SEATS - _load_count(load)
	for b in stops.size():
		if seats <= 0:
			break
		if (b - s) * d <= 0:
			continue   # nicht in Fahrtrichtung
		var kb := _key(b)
		var n := mini(int(floor(float(q.get(kb, 0.0)))), seats)
		if n <= 0:
			continue
		q[kb] = float(q.get(kb, 0.0)) - float(n)
		load[kb] = int(load.get(kb, 0)) + n
		seats -= n
		on += n
		var payers := n
		if conductors() <= 0:
			var nd := roundi(float(n) * FARE_DODGE)
			dodge += nd
			payers -= nd
		revenue += float(payers) * fare(s, b)
	t["load"] = load
	if revenue > 0.0:
		sim.economy.transfer("H0", ACCT, revenue)
	stats.fahrgaeste = int(stats.fahrgaeste) + on
	stats.erloes = float(stats.erloes) + revenue
	stats.schwarz = int(stats.schwarz) + dodge
	_town_stat(ks, "ein", on)


static func _load_count(load: Dictionary) -> int:
	var n := 0
	for k in load:
		n += int(load[k])
	return n


func passengers(t: Dictionary) -> int:
	return _load_count(t.get("load", {}))


func waiting_at(s: int) -> int:
	var n := 0
	var q: Dictionary = waiting.get(_key(s), {})
	for k in q:
		n += int(floor(float(q[k])))
	return n


func _town_stat(k: String, what: String, n: int) -> void:
	if n <= 0:
		return
	if not by_town.has(k):
		by_town[k] = {"ein": 0, "aus": 0}
	by_town[k][what] = int(by_town[k][what]) + n


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
	var idx := trains.find(t)
	if facility != "" and drivers() <= idx:
		why = "kein Triebfahrzeugführer"
	elif blocks.has(b) and str(blocks[b]) != str(t.id):
		why = "Block belegt"
	elif _occupancy(j, str(t.id)).size() >= capacity(j):
		why = "Zielbahnhof belegt"
	if why != "":
		t.state = "wartet"
		t["grund"] = why
		return
	blocks[b] = t.id
	_board(t, s, d)   # Fahrgaeste in Fahrtrichtung steigen kurz vor der Abfahrt ein
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
		_cells_acc += absf(left)
		_arrive(t, now)
		return
	t.pos = float(t.pos) + signf(left) * step
	t.cells = float(t.cells) + step
	stats.felder = float(stats.felder) + step
	_cells_acc += step


func _arrive(t: Dictionary, now: float) -> void:
	var j := int(t.target)
	blocks.erase(_block(int(t.stop), j))
	var others := _occupancy(j, str(t.id)).filter(func(o): return str(o.state) != "fahrt")
	t.track = 1 if not others.is_empty() and others.any(func(o): return int(o.track) == 0) else 0
	if not others.is_empty():
		stats.kreuzungen = int(stats.kreuzungen) + 1
	t.stop = j
	var ks := _key(j)   # Aussteigen bei Ankunft
	var ld: Dictionary = t.get("load", {})
	_town_stat(ks, "aus", int(ld.get(ks, 0)))
	ld.erase(ks)
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


## Beide Staedte liegen an der Linie und der Betrieb laeuft (mindestens ein Zug mit Triebfahrzeugfuehrer).
func connects(a: int, b: int) -> bool:
	return a != b and not path.is_empty() and stop_of_town(a) >= 0 and stop_of_town(b) >= 0 and (facility == "" or drivers() > 0)


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
			"fahrten": int(t.trips), "fahrgaeste": passengers(t)})
	var wt := {}
	for i in stops.size():
		wt[sim.towns.name_of(int(stops[i].town))] = waiting_at(i)
	return {"linie": stops.map(func(s): return sim.towns.name_of(int(s.town))), "zuege": tl, "laenge_felder": path.size(),
		"fahrzeit_min": snappedf(float(path.size()) / SPEED, 1.0), "statistik": stats.duplicate(), "wartende": wt,
		"personal": {"triebfahrzeugfuehrer": drivers(), "zugbegleiter": conductors()}, "gesellschaft_saldo": snappedf(float(sim.economy.accounts.get(ACCT, 0.0)), 1.0),
		"letzter_ausgleich": last_settle, "fahrpreis_beispiel": fare(0, stops.size() - 1) if stops.size() > 1 else 0.0}


func to_dict() -> Dictionary:
	return {"trains": trains, "blocks": blocks, "stats": stats, "waiting": waiting, "by_town": by_town, "last_settle": last_settle, "facility": facility,
		"cells_acc": _cells_acc}


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
	var st0: Dictionary = stats.duplicate()
	st0.merge(d.get("stats", {}), true)
	stats = st0
	waiting = d.get("waiting", {})
	by_town = d.get("by_town", {})
	last_settle = d.get("last_settle", {})
	facility = str(d.get("facility", ""))
	_cells_acc = float(d.get("cells_acc", 0.0))
