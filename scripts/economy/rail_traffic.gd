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
## Schritt 4 Bahnuebergaenge und Stoerungen: Naht ein Zug (CLOSE_AHEAD Felder davor bis zum Zugende), ist die Schranke zu
## (NavGrid.barriers): Strassenfahrzeuge warten davor. Taeglich koennen Abschnitte gestoert werden (Sturm: umgestuerzter Baum,
## sonst selten Signal- oder Weichenstoerung). Ein gestoerter Block wird nicht befahren; ein Zug darin bleibt stehen. Ein Bahntrupp
## (CityFleet "bahntrupp") faehrt vom naechsten Bahnhof zur Stelle und repariert dort; die Kosten traegt N0. Wartende, deren Weg
## ueber einen gestoerten Block fuehrt, fahren mit dem Auto (Fahrtkosten H0 -> S0).
## Schritt 5 Ausbau: Der Regionalrat kann einen weiteren Triebwagen (Taktverdichtung, hoechstens MAX_TRAINS, Lieferzeit
## TRAIN_DAYS) oder ein zweites Gleis auf dem Abschnitt mit der meisten Wartezeit beschliessen; das Land traegt LAND_SHARE
## (Regionalisierungsmittel/GVFG), die Staedte den Rest nach Einwohnern. Das zweite Gleis baut eine Baufirma (Projekt "gleis");
## danach hat der Abschnitt je Richtung ein Gleis (Blockschluessel je Richtung), Zuege begegnen sich dort ohne Halt.
## Phase 7 Schritt 1 Gueterzug: GZ1 (Diesellok + Containertragwagen) faehrt vom Gueterbahnhof am Grosslager ueber das
## Anschlussgleis zur Weiche und abwechselnd zu den Bahnhoefen der einen und der anderen Seite (Halt zum Entladen), dann zurueck,
## Ausfahrt an der Weiche, Beladen am Gueterbahnhof. Auf der Hauptstrecke gelten dieselben Bloecke und Bahnhofsgleise wie fuer die
## Regionalbahn; das Anschlussgleis ist ein eigener Block (Schluessel BRANCH). Hoechstens MAX_TRAINS Zuege (Gueterzug zaehlt mit):
## mit zwei Gleisen je Bahnhof koennen sich drei Zuege auf einer eingleisigen Linie nie gegenseitig blockieren, vier schon.
## Phase 7 Schritt 2 Ladung: Stadtlager-Bestellungen aus dem Grosslager stehen in freight_queue. Der Gueterzug laedt am
## Gueterbahnhof die Sendungen der Stadt mit der meisten wartenden Ware (bis FREIGHT_CAPACITY Einheiten), faehrt hin, entlaedt
## (CityDepot.rail_arrived: Stadt-Lkw fuer die letzte Meile) und kommt zurueck. Ohne Ladung wartet er am Gueterbahnhof.
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
const MAX_TRAINS := 3           # alle Zuege der Linie (Regionalbahn und Gueterzug)
const BRANCH := -1              # Blockschluessel des Anschlussgleises
const FREIGHT_CARS := 5         # Lok + vier Wagen
const UNLOAD_MIN := 10.0        # Halt zum Entladen am Bahnhof
const LOAD_MIN := 20.0          # Beladen am Gueterbahnhof
const FREIGHT_CAPACITY := 160   # Einheiten je Gueterzug (vier Wagen)
const IDLE_CHECK_MIN := 30.0    # ohne Ladung: so oft neu pruefen
const YIELD_MIN := 30.0         # Vorrang der Regionalbahn: so lange vor deren Abfahrt faehrt der Gueterzug nicht in ihren Abschnitt
const RESYNC_MIN := 60.0        # Verspaetung am Endbahnhof, ab der die Regionalbahn den naechsten Takt faehrt
const FREIGHT_PATIENCE := 240.0 # wartet der Gueterzug laenger, faehrt er in die naechste freie Luecke (Fahrdienstleiter; Probe: sonst 0 Fahrten in 30 Tagen)
const DOUBLE_OFFSET := 8.0      # Gleisabstand zur Mitte im zweigleisigen Abschnitt (Weltmass)
const TRAIN_PRICE := 1600000.0  # Triebwagen (zwei Wagen)
const TRAIN_DAYS := 20          # Lieferzeit
const LAND_SHARE := 0.75        # Anteil des Landes an Fahrzeugen und Streckenausbau
const TRACK_EUR_CELL := 700.0   # zweites Gleis je Feld (Unterbau, Schotter, Schwellen, Schienen, Weichen)
const TRACK_CELLS_PER_DAY := 12
const TRACK_DAYS_MIN := 15
const CLOSE_AHEAD := 6.0      # Schranke schliesst so viele Felder vor der Zugspitze (2 Spielminuten)
const CLOSE_TAIL := 3.6       # ... und oeffnet, wenn das Zugende so weit vorbei ist
const ROAD_EUR_CELL := 0.01   # Ausweichen auf die Strasse: Fahrtkosten je Feld (Auto)
## Stoerungen: Wahrscheinlichkeit je Block und Tag, Arbeit vor Ort (Spielminuten), Kosten
const DISRUPT := {
	"Baum auf dem Gleis": {"p_storm": 0.15, "p": 0.0, "min": 60.0, "eur": 1200.0},
	"Signalstörung": {"p_storm": 0.0, "p": 0.008, "min": 30.0, "eur": 800.0},
	"Weichenstörung": {"p_storm": 0.0, "p": 0.004, "min": 45.0, "eur": 1500.0},
}

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
var crossings: Array = []     # [{idx (Fahrweg), cell: Vector2i}] Bahnuebergaenge der Linie (abgeleitet)
var closed := {}              # Vector2i -> true: derzeit geschlossene Schranken (abgeleitet)
var disruptions := {}         # Block -> {art, cell: [x, y], road: [x, y], since, vehicle, town}
var rng := RandomNumberGenerator.new()
var double_blocks := {}       # Block -> true: zweigleisig
var planned_tracks := {}      # Projekt-ID -> Block (zweites Gleis im Bau)
var ordered: Array = []       # [Liefertag] bestellte Triebwagen
var _double_cells := {}       # abgeleitet: Fahrweg-Zellen zweigleisiger Bloecke
var fpath: Array = []         # Gueterbahnhof -> Weiche: Ladegleis + Anschlussgleis (Vector2i, abgeleitet)
var fstop := 0.0              # Halteposition am Gueterbahnhof (Index in fpath)
var junction := -1            # Index der Weiche im Fahrweg der Linie
var fcrossings: Array = []    # Bahnuebergaenge des Anschlussgleises [{idx, cell}]
var freight_queue: Array = [] # [{town, order, item, qty, day}] Sendungen am Gueterbahnhof


func setup(simulation) -> void:
	sim = simulation
	rng.seed = hash("regionalbahn") ^ int(sim.rng.seed)
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
	for i in path.size():
		if sim.city.is_road(path[i]):
			crossings.append({"idx": i, "cell": path[i]})
	if trains.is_empty():
		_start_trains()
	_ensure_staff()
	_index_double()
	_ensure_freight()
	return true


## Gueterbahnhof: Weg Ladegleis -> Anschluss -> Weiche; Gueterzug anlegen, sobald es den Bahnhof gibt.
func _ensure_freight() -> void:
	var R: RailNet = sim.rail
	if not fpath.is_empty() or not R.has_freight():
		return
	var F: Dictionary = R.freight
	var tr: Array = F.track.map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var e0 := Vector2i(int(F.ends[0][0]), int(F.ends[0][1]))
	var end := Vector2i(int(F.end[0]), int(F.end[1]))
	if end == e0:
		tr.reverse()   # Ladegleis so, dass es am Anschluss-Ende aufhoert
	fpath = tr
	fstop = float(tr.size() - 1) * 0.5
	for a in F.branch:
		fpath.append(Vector2i(int(a[0]), int(a[1])))
	junction = path.find(Vector2i(int(F.junction[0]), int(F.junction[1])))
	fcrossings.clear()
	for i in fpath.size():
		if sim.city.is_road(fpath[i]):
			fcrossings.append({"idx": i, "cell": fpath[i]})
	if junction < 0:
		fpath.clear()
		return
	if not trains.any(func(t): return str(t.get("kind", "")) == "gueter") and trains.size() < MAX_TRAINS:
		var now: float = sim.game_min
		trains.append({"id": "GZ1", "kind": "gueter", "phase": "lager", "fpos": fstop, "pos": float(junction), "dir": 1, "state": "halt", "stop": 0,
			"target": 0, "until": now + LOAD_MIN, "planned": now + LOAD_MIN, "delay": 0.0, "track": 0, "trips": 0, "cells": 0.0, "side": 1, "ladung": 0})
		var f: Dictionary = sim.municipal.facilities.get(facility, {}) if sim.municipal != null else {}
		if not f.is_empty():
			f.staff_need["lokfuehrer"] = maxi(int(f.staff_need.get("lokfuehrer", 0)), trains.size() + 1)
		sim.log_event("Eisenbahn: Güterzug GZ1 nimmt am Güterbahnhof den Betrieb auf.", "info")


func is_freight(t: Dictionary) -> bool:
	return str(t.get("kind", "")) == "gueter"


func on_main(t: Dictionary) -> bool:
	return str(t.get("phase", "strecke")) == "strecke"


## Block, in dem die Weiche liegt (zwischen Halt j und j+1).
func junction_block() -> int:
	for b in stops.size() - 1:
		if float(stops[b].pos) < float(junction) and float(junction) < float(stops[b + 1].pos):
			return b
	return -1


## Gueterzug auf Ladegleis und Anschluss: Beladen, Fahrt zur Weiche, Einfahrt in die Strecke (Block und Zielbahnhof frei),
## Rueckfahrt von der Weiche zum Gueterbahnhof.
func _freight_branch(t: Dictionary, dmin: float, now: float) -> void:
	var last := float(fpath.size() - 1)
	match str(t.phase):
		"lager":
			if now < float(t.until):
				return
			if t.get("cargo", []).is_empty() and not _load(t):
				t["grund"] = "wartet auf Ladung"
				t.until = now + IDLE_CHECK_MIN
				return
			if blocks.has(BRANCH) and str(blocks[BRANCH]) != str(t.id):
				t["grund"] = "Anschlussgleis belegt"
				return
			blocks[BRANCH] = t.id
			t.phase = "anschluss"
			t.state = "fahrt"
			t.erase("grund")
		"anschluss":   # Richtung Weiche bis zum Einfahrsignal
			var sig := last - float(FREIGHT_CARS) * CAR_LEN * 0.5 - 1.0
			t.fpos = minf(sig, float(t.fpos) + SPEED * dmin)
			t.cells = float(t.cells) + SPEED * dmin
			_cells_acc += SPEED * dmin
			if float(t.fpos) >= sig:
				t.phase = "einfahrt"
				t.state = "wartet"
		"einfahrt":
			_freight_enter(t, now)
			if str(t.phase) == "einfahrt" and junction_block() >= 0:   # Wartezeit vor dem Abschnitt der Weiche (Grundlage fuer das zweite Gleis)
				var bw: Dictionary = stats.get("block_wartezeit", {})
				bw[str(junction_block())] = float(bw.get(str(junction_block()), 0.0)) + dmin
				stats["block_wartezeit"] = bw
		"rueck":   # von der Weiche zum Gueterbahnhof
			t.fpos = maxf(fstop, float(t.fpos) - SPEED * dmin)
			t.cells = float(t.cells) + SPEED * dmin
			_cells_acc += SPEED * dmin
			if float(t.fpos) <= fstop:
				blocks.erase(BRANCH)
				t.phase = "lager"
				t.state = "halt"
				t.until = now + LOAD_MIN
				t.trips = int(t.trips) + 1
				stats["gueter_touren"] = int(stats.get("gueter_touren", 0)) + 1
				t.erase("ziel")


# ------------------------------------------------------------------ Ladung (Phase 7 Schritt 2)
func accepts_freight(town: int) -> bool:
	return not fpath.is_empty() and stop_of_town(town) >= 0 and trains.any(func(t): return is_freight(t))


func queue_freight(town: int, order_id: String, item: String, qty: int) -> void:
	freight_queue.append({"town": town, "order": order_id, "item": item, "qty": qty, "day": GameCalendar.day_of(sim.game_min)})


func unqueue(order_id: String) -> void:
	freight_queue = freight_queue.filter(func(x): return str(x.order) != order_id)


func queued_units(town: int = -1) -> int:
	var n := 0
	for x in freight_queue:
		if town < 0 or int(x.town) == town:
			n += int(x.qty)
	return n


## Beladen: Stadt mit der meisten wartenden Ware, Sendungen in Reihenfolge bis zur Kapazitaet (eine groessere Sendung allein geht immer).
func _load(t: Dictionary) -> bool:
	if freight_queue.is_empty():
		return false
	var by := {}
	for x in freight_queue:
		if stop_of_town(int(x.town)) >= 0:
			by[int(x.town)] = int(by.get(int(x.town), 0)) + int(x.qty)
	if by.is_empty():
		return false
	var best: int = by.keys()[0]
	for k in by:
		if int(by[k]) > int(by[best]):
			best = k
	var cargo: Array = []
	var units := 0
	for x in freight_queue.duplicate():
		if int(x.town) != best:
			continue
		if not cargo.is_empty() and units + int(x.qty) > FREIGHT_CAPACITY:
			continue
		cargo.append(x)
		units += int(x.qty)
		freight_queue.erase(x)
		var o: Dictionary = sim.towns.depot(best).orders.get(str(x.order), {})
		if not o.is_empty():
			o.status = "bahn"
			sim.towns.depot(best)._log(o, "im Güterzug %s verladen" % t.id)
	t["cargo"] = cargo
	t.ladung = units
	t["ziel"] = stop_of_town(best)
	stats["gueter_einheiten"] = int(stats.get("gueter_einheiten", 0)) + units
	sim.log_event("Güterzug %s lädt %d Einheiten für %s (%d Sendungen)." % [t.id, units, sim.towns.name_of(best), cargo.size()], "info")
	return true


func _unload(t: Dictionary, s: int) -> void:
	var k := int(stops[s].town)
	var st: Dictionary = sim.rail.station_of(k)
	var road: Vector2i = sim.city.building(int(st.building)).road if not st.is_empty() else Vector2i.ZERO
	for x in t.get("cargo", []):
		sim.towns.depot(int(x.town)).rail_arrived(str(x.order), road)
	if not t.get("cargo", []).is_empty():
		sim.log_event("Güterzug %s entlädt %d Einheiten in %s." % [t.id, int(t.ladung), sim.towns.name_of(k)], "good")
	t["cargo"] = []
	t.ladung = 0


## Halte auf einer Seite der Weiche (d > 0: groessere Position), von der Weiche aus nach aussen.
func _side_stops(d: int) -> Array:
	var out: Array = []
	for i in stops.size():
		if (float(stops[i].pos) - float(junction)) * float(d) > 0.0:
			out.append(i)
	if d < 0:
		out.reverse()
	return out


## Vorrang der Regionalbahn: Steht oder wartet an einem Ende des Blocks b eine Regionalbahn, die demnaechst (YIELD_MIN) in b
## einfahren will, laesst der Gueterzug ihr den Vortritt (Messung 13.11.: ohne Vorrang bis 200 min Verspaetung der Regionalbahn).
## Auch eine Regionalbahn, die gerade auf einen Endbahnhof von b zufaehrt und danach in b weiterfahren will, hat Vorrang (sonst
## blieben bis 750 min Verspaetung, Probe 30 Tage).
func _rb_wants(b: int, now: float) -> bool:
	for o in trains:
		if is_freight(o):
			continue
		var s := int(o.target) if str(o.state) == "fahrt" else int(o.stop)
		var d := int(o.dir)
		if s + d < 0 or s + d >= stops.size():
			d = -d
		if _block(s, s + d) != b:
			continue
		if str(o.state) == "fahrt" or float(o.until) <= now + YIELD_MIN:
			return true
	return false


## Ziel der naechsten Tour: reihum alle Bahnhoefe (Schritt 2 waehlt nach Ladung).
func _next_target(t: Dictionary) -> int:
	var z := (int(t.get("ziel", -1)) + 1) % stops.size()
	t["ziel"] = z
	return z


func _freight_enter(t: Dictionary, now: float) -> void:
	if not t.has("ziel"):
		_next_target(t)
	if int(t.ziel) < 0 or int(t.ziel) >= stops.size():
		t.ziel = 0
	var J := junction_block()
	var d := 1 if float(stops[int(t.ziel)].pos) > float(junction) else -1
	var tgt := J + 1 if d > 0 else J
	var frm := J if d > 0 else J + 1
	var why := ""
	if facility != "" and drivers() <= trains.find(t):
		why = "kein Triebfahrzeugführer"
	elif disruptions.has(J):
		why = "Störung: %s" % disruptions[J].art
	elif not _block_free(J, tgt - frm, str(t.id)):
		why = "Block belegt"
	elif not double_blocks.has(J) and now - float(t.get("wait_since", now)) < FREIGHT_PATIENCE and _rb_wants(J, now):
		why = "Vorrang Regionalbahn"
	elif _occupancy(tgt, str(t.id)).size() >= capacity(tgt):
		why = "Zielbahnhof belegt"
	if why != "":
		t["grund"] = why
		if not t.has("wait_since"):
			t["wait_since"] = now
		return
	t.erase("wait_since")
	blocks.erase(BRANCH)
	blocks[_bkey(J, tgt - frm)] = t.id
	t.phase = "strecke"
	t.state = "fahrt"
	t.pos = float(junction)
	t.dir = d
	t.stop = frm
	t.target = tgt
	t.erase("grund")
	t.erase("exit_at")
	t.ladung = 40   # Schritt 2 fuellt das mit echter Ware
	stats["gueter_einfahrten"] = int(stats.get("gueter_einfahrten", 0)) + 1


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
	var storm: bool = sim.wx != null and sim.wx.is_strong_wind()
	for b in stops.size() - 1:
		for art in DISRUPT:
			var pr := float(DISRUPT[art].p_storm if storm else DISRUPT[art].p)
			if pr > 0.0 and rng.randf() < pr:
				disrupt(b, art)
	for b in disruptions.keys():   # Spielstand: Trupp neu losschicken, falls er fehlt
		var vid := int(disruptions[b].vehicle)
		if not sim.fleet.vehicles.any(func(v): return int(v.id) == vid and v.kind == "bahntrupp"):
			_dispatch_crew(b)
	_road_fallback()
	_deliver()
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
		if is_freight(t) and not on_main(t):
			_freight_branch(t, dmin, now)
			continue
		match str(t.state):
			"halt", "wartet":
				if now >= float(t.until):
					_depart(t, now)
				if str(t.state) == "wartet":
					stats.wartezeit = float(stats.wartezeit) + dmin
					if t.has("wartet_block"):
						var bw: Dictionary = stats.get("block_wartezeit", {})
						bw[str(int(t.wartet_block))] = float(bw.get(str(int(t.wartet_block)), 0.0)) + dmin
						stats["block_wartezeit"] = bw
				else:
					t.erase("wartet_block")
			"fahrt":
				_move(t, dmin, now)
	_update_crossings()


## Schranken: geschlossen, solange sich ein fahrender Zug im Bereich [Spitze + CLOSE_AHEAD, Ende - CLOSE_TAIL] befindet.
func _update_crossings() -> void:
	var now_closed := {}
	for t in trains:
		if is_freight(t) and not on_main(t):
			if str(t.phase) in ["anschluss", "rueck"]:
				var df := 1.0 if str(t.phase) == "anschluss" else -1.0
				var hf := float(FREIGHT_CARS) * CAR_LEN * 0.5
				for c in fcrossings:
					var relf := (float(c.idx) - float(t.fpos)) * df
					if relf <= hf + CLOSE_AHEAD and relf >= -hf - CLOSE_TAIL:
						now_closed[c.cell] = true
			continue
		if str(t.state) != "fahrt":
			continue
		var goal_pos := float(t.exit_at) if t.has("exit_at") else float(stops[int(t.target)].pos)
		var d := signf(goal_pos - float(t.pos))
		var head := float(FREIGHT_CARS if is_freight(t) else CARS) * CAR_LEN * 0.5
		for c in crossings:
			var rel := (float(c.idx) - float(t.pos)) * d
			if rel <= head + CLOSE_AHEAD and rel >= -head - CLOSE_TAIL:
				now_closed[c.cell] = true
	var nav = sim.nav
	for q in closed:
		if not now_closed.has(q):
			nav.barriers.erase(q)
	for q in now_closed:
		if not closed.has(q):
			nav.barriers[q] = true
			stats["schranken"] = int(stats.get("schranken", 0)) + 1
	closed = now_closed


# ------------------------------------------------------------------ Ausbau (Schritt 5)
## Zweites Gleis: Abschnitt mit der meisten Wartezeit (sonst der laengste), noch eingleisig und nicht im Bau.
func plan_double() -> Dictionary:
	if not ensure() or stops.size() < 2:
		return {"ok": false, "msg": "Keine Bahnlinie."}
	var bw: Dictionary = stats.get("block_wartezeit", {})
	var best := -1
	var score := -1.0
	for b in stops.size() - 1:
		if double_blocks.has(b) or planned_tracks.values().has(b):
			continue
		var cells := float(stops[b + 1].from) - float(stops[b].to)
		var sc := float(bw.get(str(b), 0.0)) * 1000.0 + cells
		if sc > score:
			score = sc
			best = b
	if best < 0:
		return {"ok": false, "msg": "Alle Abschnitte sind schon zweigleisig oder im Bau."}
	var n := int(stops[best + 1].from) - int(stops[best].to) - 1
	var cost := snappedf(float(n) * TRACK_EUR_CELL, 100.0)
	return {"ok": true, "block": best, "felder": n, "kosten": cost, "tage": maxi(TRACK_DAYS_MIN, ceili(float(n) / float(TRACK_CELLS_PER_DAY))),
		"von": sim.towns.name_of(int(stops[best].town)), "nach": sim.towns.name_of(int(stops[best + 1].town)),
		"wartezeit_min": snappedf(float(bw.get(str(best), 0.0)), 1.0)}


## Beschluss zweites Gleis: Bauprojekt bei der groessten Stadt, Anteile der Staedte (Betraege), Land traegt LAND_SHARE.
func start_double(fractions: Dictionary, reason: String) -> Dictionary:
	var pl := plan_double()
	if not pl.ok:
		return pl
	var k := int(stops[0].town)
	for s in stops:
		if sim.citizens.population_of(int(s.town)) > sim.citizens.population_of(k):
			k = int(s.town)
	var M: Mayor = sim.towns.mayor(k)
	var cost := float(pl.kosten)
	var prj: Dictionary = M.add_works_project("gleis", "B%d" % int(pl.block), cost, int(pl.tage), {}, "Zweites Gleis %s – %s (%s)" % [pl.von, pl.nach, reason.left(80)])
	M.commitments = maxf(0.0, M.commitments - cost)
	prj["shares"] = {}
	for key in fractions:
		var amt := snappedf(cost * (1.0 - LAND_SHARE) * float(fractions[key]), 1.0)
		sim.towns.mayor(int(key)).commitments += amt
		prj.shares[str(key)] = amt
	prj["federal"] = snappedf(cost * LAND_SHARE, 1.0)
	prj["regional"] = "gleis"
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": GameCalendar.day_of(sim.game_min) - 1, "bids": [], "by": "Regionalbahn"}
	planned_tracks[str(prj.id)] = int(pl.block)
	sim.log_event("Regionalbahn: zweites Gleis %s – %s beschlossen (%d Felder, %s, Land %d %%) – ausgeschrieben als %s." % [pl.von, pl.nach, int(pl.felder),
		Catalog.money(cost), roundi(LAND_SHARE * 100.0), prj.id], "info")
	return {"ok": true, "msg": "Zweites Gleis ausgeschrieben (%s)." % prj.id, "ref": prj.id}


## Abnahme durch die Baufirma (Construction._finish_public).
func on_track_done(prj: Dictionary) -> void:
	if not planned_tracks.has(str(prj.id)):
		return
	var b := int(planned_tracks[str(prj.id)])
	planned_tracks.erase(str(prj.id))
	double_blocks[b] = true
	_index_double()
	sim.log_event("Regionalbahn: Abschnitt %s – %s ist zweigleisig – Züge begegnen sich ohne Halt." % [sim.towns.name_of(int(stops[b].town)),
		sim.towns.name_of(int(stops[b + 1].town))], "good")


func _index_double() -> void:
	_double_cells.clear()
	if path.is_empty():
		return
	for b in double_blocks:
		for i in range(int(stops[int(b)].to) + 1, int(stops[int(b) + 1].from)):
			_double_cells[path[i]] = true


func is_double_cell(q: Vector2i) -> bool:
	return _double_cells.has(q)


## Zellen eines geplanten zweiten Gleises (Darstellung der Baustelle) und Mitte fuer den Bautrupp.
func planned_cells(project_id: String) -> Array:
	if not planned_tracks.has(project_id) or path.is_empty():
		return []
	var b := int(planned_tracks[project_id])
	return path.slice(int(stops[b].to) + 1, int(stops[b + 1].from))


## Taktverdichtung: weiterer Triebwagen bestellt (Lieferung nach TRAIN_DAYS).
func order_train() -> Dictionary:
	if trains.size() + ordered.size() >= MAX_TRAINS:
		return {"ok": false, "msg": "Höchstens %d Triebwagen auf der Linie." % MAX_TRAINS}
	ordered.append(GameCalendar.day_of(sim.game_min) + TRAIN_DAYS)
	sim.log_event("Regionalbahn: weiterer Triebwagen bestellt, Lieferung in %d Tagen." % TRAIN_DAYS, "info")
	return {"ok": true, "msg": "Triebwagen bestellt."}


func _deliver() -> void:
	var today := GameCalendar.day_of(sim.game_min)
	for d in ordered.duplicate():
		if today < int(d):
			continue
		ordered.erase(d)
		var at := 0
		if _occupancy(0).size() >= capacity(0):
			at = stops.size() - 1
		var now: float = sim.game_min
		var id := "RB%d" % (trains.size() + 1)
		trains.append({"id": id, "pos": float(stops[at].pos), "dir": 1 if at == 0 else -1, "state": "halt", "stop": at, "target": at,
			"until": now + TURN, "planned": now + TURN, "delay": 0.0, "track": 1 if not _occupancy(at, id).is_empty() else 0, "trips": 0, "cells": 0.0})
		var f: Dictionary = sim.municipal.facilities.get(facility, {}) if sim.municipal != null else {}
		if not f.is_empty():   # je Zug ein Triebfahrzeugfuehrer mehr, ein Zugbegleiter mehr
			f.staff_need["lokfuehrer"] = maxi(int(f.staff_need.get("lokfuehrer", 0)), trains.size() + 1)
			f.staff_need["zugbegleiter"] = maxi(int(f.staff_need.get("zugbegleiter", 0)), trains.size())
		sim.log_event("Regionalbahn: Triebwagen %s geliefert und in Betrieb (dichterer Takt)." % id, "good")


## Ausbauoptionen fuer die Beobachtung der Buergermeister.
func expansion_options() -> Dictionary:
	var dbl := plan_double()
	return {"triebwagen": {"moeglich": trains.size() + ordered.size() < MAX_TRAINS, "preis": TRAIN_PRICE, "staedte_anteil": TRAIN_PRICE * (1.0 - LAND_SHARE),
			"lieferzeit_tage": TRAIN_DAYS, "antrag": "regionalrat_antrag art bahn_takt"},
		"zweites_gleis": {"moeglich": bool(dbl.ok), "abschnitt": "%s – %s" % [dbl.get("von", ""), dbl.get("nach", "")] if dbl.ok else "",
			"kosten": float(dbl.get("kosten", 0.0)), "staedte_anteil": float(dbl.get("kosten", 0.0)) * (1.0 - LAND_SHARE), "wartezeit_min": float(dbl.get("wartezeit_min", 0.0)),
			"antrag": "regionalrat_antrag art zweites_gleis"},
		"zweigleisig": double_blocks.keys().map(func(b): return "%s – %s" % [sim.towns.name_of(int(stops[int(b)].town)), sim.towns.name_of(int(stops[int(b) + 1].town))]),
		"im_bau": planned_tracks.keys(), "bestellt": ordered.size()}


static func repair_min(art: String) -> float:
	return float(DISRUPT.get(art, {"min": 40.0}).min)


## Stoerung auf Block b: Stelle auf dem Fahrweg, Strassenzufahrt, Bahntrupp vom naechsten Bahnhof.
func disrupt(b: int, art: String) -> bool:
	if disruptions.has(b) or b < 0 or b >= stops.size() - 1:
		return false
	var lo := int(stops[b].to) + 1
	var hi := int(stops[b + 1].from) - 1
	if hi <= lo:
		return false
	var idx := rng.randi_range(lo, hi)
	if art == "Signalstörung":
		idx = lo   # Ausfahrsignal am Bahnhofsende
	elif art == "Weichenstörung":
		idx = maxi(lo, int(stops[b].to))
	var cell: Vector2i = path[idx]
	var road := _road_near(cell)
	var town := int(stops[b].town) if absi(idx - int(stops[b].to)) <= absi(idx - int(stops[b + 1].from)) else int(stops[b + 1].town)
	disruptions[b] = {"art": art, "cell": [cell.x, cell.y], "idx": idx, "road": [road.x, road.y], "since": sim.game_min, "vehicle": -1, "town": town}
	stats["stoerungen"] = int(stats.get("stoerungen", 0)) + 1
	sim.log_event("Regionalbahn: %s zwischen %s und %s – Abschnitt gesperrt, Bahntrupp aus %s ist unterwegs." % [art,
		sim.towns.name_of(int(stops[b].town)), sim.towns.name_of(int(stops[b + 1].town)), sim.towns.name_of(town)], "warn")
	_dispatch_crew(b)
	return true


func _road_near(c: Vector2i) -> Vector2i:
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if sim.city.inside(q) and sim.city.is_road(q) and not closed.has(q):
					return q
	return c


func _dispatch_crew(b: int) -> void:
	var dz: Dictionary = disruptions[b]
	var st: Dictionary = sim.rail.station_of(int(dz.town))
	var home: Vector2i = sim.city.building(int(st.building)).road if not st.is_empty() else sim.fleet.depot_road()
	var road := Vector2i(int(dz.road[0]), int(dz.road[1]))
	var v: Dictionary = sim.fleet._spawn("bahntrupp", home, road, 0.0, home, "Bahntrupp %s: %s" % [sim.towns.name_of(int(dz.town)), dz.art])
	v["block"] = b
	v["art"] = dz.art
	dz.vehicle = int(v.id)


## Vom Bahntrupp nach getaner Arbeit gemeldet.
func repaired(b: int) -> void:
	if not disruptions.has(b):
		return
	var dz: Dictionary = disruptions[b]
	disruptions.erase(b)
	var eur := float(DISRUPT.get(str(dz.art), {"eur": 1000.0}).eur)
	sim.economy.transfer(ACCT, "S0", eur)
	stats.kosten = float(stats.kosten) + eur
	var dur: float = sim.game_min - float(dz.since)
	stats["ausfall_min"] = float(stats.get("ausfall_min", 0.0)) + dur
	sim.log_event("Regionalbahn: %s behoben (Bahntrupp %s, Sperrung %.0f Spielminuten, %s)." % [dz.art, sim.towns.name_of(int(dz.town)), dur,
		Catalog.money(eur)], "good")


## Wartende, deren Weg ueber einen gestoerten Block fuehrt, fahren mit dem Auto (ganze Personen; Bruchteile bleiben).
func _road_fallback() -> void:
	if disruptions.is_empty():
		return
	for a in stops.size():
		var q: Dictionary = waiting.get(_key(a), {})
		for b in stops.size():
			if a == b:
				continue
			var hit := false
			for blk in range(mini(a, b), maxi(a, b)):
				hit = hit or disruptions.has(blk)
			var n := int(floor(float(q.get(_key(b), 0.0))))
			if not hit or n <= 0:
				continue
			q[_key(b)] = float(q[_key(b)]) - float(n)
			var eur := float(n) * ROAD_EUR_CELL * absf(float(stops[b].pos) - float(stops[a].pos))
			sim.economy.transfer("H0", "S0", eur)
			stats["strasse"] = int(stats.get("strasse", 0)) + n

func _block(i: int, j: int) -> int:
	return mini(i, j)


## Belegungsschluessel: eingleisig der Block selbst, zweigleisig je Richtung ein eigenes Gleis.
func _bkey(b: int, d: int) -> int:
	return (1000 + b * 2 + (0 if d > 0 else 1)) if double_blocks.has(b) else b


func _block_free(b: int, d: int, own: String) -> bool:
	for key in [b, _bkey(b, d)]:   # alter Schluessel b gilt, solange ein Zug von vor dem Ausbau noch im Block ist
		if blocks.has(key) and str(blocks[key]) != own:
			return false
	return true


func _release(t: Dictionary) -> void:
	for key in blocks.keys():
		if str(blocks[key]) == str(t.id):
			blocks.erase(key)


## Belegung eines Bahnhofs: Zuege, die dort halten oder ihn als Ziel haben.
func _occupancy(s: int, except: String = "") -> Array:
	return trains.filter(func(t): return str(t.id) != except and on_main(t) and not t.has("exit_at") and ((str(t.state) != "fahrt" and int(t.stop) == s) or (str(t.state) == "fahrt" and int(t.target) == s)))


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
	var to_junction := is_freight(t) and b == junction_block() and (float(junction) - float(stops[s].pos)) * float(d) > 0.0
	if facility != "" and drivers() <= idx:
		why = "kein Triebfahrzeugführer"
	elif disruptions.has(b):
		why = "Störung: %s" % disruptions[b].art
	elif not _block_free(b, j - s, str(t.id)):
		why = "Block belegt"
	elif not to_junction and _occupancy(j, str(t.id)).size() >= capacity(j):
		why = "Zielbahnhof belegt"
	elif is_freight(t) and not double_blocks.has(b) and now - float(t.get("wait_since", now)) < FREIGHT_PATIENCE and _rb_wants(b, now):
		why = "Vorrang Regionalbahn"
	elif to_junction and blocks.has(BRANCH) and str(blocks[BRANCH]) != str(t.id):
		why = "Anschlussgleis belegt"
	if why != "":
		t.state = "wartet"
		t["grund"] = why
		if not t.has("wait_since"):
			t["wait_since"] = now
		if why in ["Block belegt", "Zielbahnhof belegt", "Vorrang Regionalbahn"]:
			var bw: Dictionary = stats.get("block_wartezeit", {})
			bw[str(b)] = float(bw.get(str(b), 0.0)) + 0.0   # Schluessel anlegen; Minuten zaehlt update()
			stats["block_wartezeit"] = bw
			t["wartet_block"] = b
		return
	t.erase("wait_since")
	blocks[_bkey(b, j - s)] = t.id
	if is_freight(t):
		if to_junction:
			t["exit_at"] = junction
			blocks[BRANCH] = t.id
	else:
		_board(t, s, d)   # Fahrgaeste in Fahrtrichtung steigen kurz vor der Abfahrt ein
	t.state = "fahrt"
	t.target = j
	t.erase("grund")
	t.delay = 0.0 if is_freight(t) else maxf(0.0, now - float(t.planned))
	var dist := absf(float(stops[j].pos) - float(t.pos))
	t.planned = float(t.planned) + dist / SPEED   # Soll-Ankunft


func _move(t: Dictionary, dmin: float, now: float) -> void:
	var j := int(t.target)
	var goal := float(stops[j].pos)
	if t.has("exit_at"):
		goal = float(t.exit_at)
	var step := SPEED * dmin
	var b := _block(int(t.stop), j)
	if disruptions.has(b):   # Stoerung im eigenen Block vor dem Zug: vor der Stelle anhalten
		var ahead := (float(disruptions[b].idx) - float(t.pos)) * signf(goal - float(t.pos))
		if ahead > 0.0 and ahead - (float(CARS) * CAR_LEN * 0.5 + 2.0) <= step:
			t["grund"] = "Störung: %s" % disruptions[b].art
			stats.wartezeit = float(stats.wartezeit) + dmin
			return
	t.erase("grund")
	var left := goal - float(t.pos)
	if absf(left) <= step:
		t.pos = goal
		t.cells = float(t.cells) + absf(left)
		stats.felder = float(stats.felder) + absf(left)
		_cells_acc += absf(left)
		if t.has("exit_at"):   # Gueterzug biegt an der Weiche ins Anschlussgleis
			for key in blocks.keys():
				if str(blocks[key]) == str(t.id) and int(key) != BRANCH:
					blocks.erase(key)
			t.erase("exit_at")
			t.phase = "rueck"
			t.state = "fahrt"
			t.fpos = float(fpath.size() - 1)
			return
		_arrive(t, now)
		return
	t.pos = float(t.pos) + signf(left) * step
	t.cells = float(t.cells) + step
	stats.felder = float(stats.felder) + step
	_cells_acc += step


func _arrive(t: Dictionary, now: float) -> void:
	var j := int(t.target)
	_release(t)
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
	if is_freight(t):
		t.delay = 0.0
		if j == int(t.get("ziel", -1)):   # Ziel der Tour: entladen, dann zurueck Richtung Weiche
			t.until = now + UNLOAD_MIN
			_unload(t, j)
			stats["gueter_halte"] = int(stats.get("gueter_halte", 0)) + 1
			t.dir = -int(t.dir)
		else:
			t.until = now   # Durchfahrt (nur Kreuzung/Blockwechsel)
		return
	var terminus := j == 0 or j == stops.size() - 1
	var dwell := DWELL
	if terminus:
		t.trips = int(t.trips) + 1
		stats.fahrten = int(stats.fahrten) + 1
		dwell = maxf(TURN_MIN, TURN - float(t.delay))   # Verspaetung in der Wendezeit aufholen
	t.until = now + dwell
	t.planned = float(t.planned) + (TURN if terminus else DWELL)
	if terminus and float(t.delay) > RESYNC_MIN:   # zu spaet: der Zug faehrt mit dem naechsten Takt weiter (Fahrplan neu aufgenommen)
		t.planned = now + dwell
		t.delay = 0.0
		stats["takt_neu"] = int(stats.get("takt_neu", 0)) + 1


# ------------------------------------------------------------------ Darstellung
## Weltposition (Weltmass, Feld = 32) und Fahrtrichtung an einer Stelle des Fahrwegs; im Bahnhof auf dem Ausweichgleis versetzt.
func world_at(pos: float, track: int = 0, lane: int = 0) -> Dictionary:
	var n := path.size()
	var p := clampf(pos, 0.0, float(n - 1))
	var i := int(floor(p))
	var j := mini(i + 1, n - 1)
	var f := p - float(i)
	var a: Vector2 = (Vector2(path[i]) + Vector2(0.5, 0.5)) * 32.0
	var b: Vector2 = (Vector2(path[j]) + Vector2(0.5, 0.5)) * 32.0
	var h: Vector2 = (b - a) if j != i else ((a - (Vector2(path[i - 1]) + Vector2(0.5, 0.5)) * 32.0) if i > 0 else Vector2(1, 0))
	var w := a.lerp(b, f)
	if _double_cells.has(path[i]) and lane != 0:   # zweigleisig: je Richtung ein Gleis (Versatz quer zur Fahrrichtung)
		var hn := h.normalized()
		w += Vector2(-hn.y, hn.x) * DOUBLE_OFFSET * float(lane)
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
	var n := FREIGHT_CARS if is_freight(t) else CARS
	if is_freight(t) and not on_main(t):   # auf Ladegleis/Anschluss: Richtung nach Fahrtrichtung auf dem Anschluss
		var df := -1.0 if str(t.phase) in ["rueck", "lager"] else 1.0
		for c in n:
			var pc := float(t.fpos) + df * (CAR_LEN * float(n - 1) * 0.5 - float(c) * CAR_LEN)
			var w := _interp(fpath, pc)
			w["heading"] = w.heading * df
			w["front"] = c == 0
			w["model"] = "gz_lok" if c == 0 else "gz_wagen"
			out.append(w)
		return out
	var d := float(t.dir)
	for c in n:
		var pc := float(t.pos) + d * (CAR_LEN * float(n - 1) * 0.5 - float(c) * CAR_LEN)
		var w := world_at(pc, int(t.track), int(t.dir))
		if is_freight(t):
			w["heading"] = w.heading * d
			w["model"] = "gz_lok" if c == 0 else "gz_wagen"
		else:
			w["heading"] = w.heading * d * (-1.0 if c == CARS - 1 and CARS > 1 else 1.0)
			w["model"] = "rb_triebwagen"
		w["front"] = c == 0
		out.append(w)
	return out


## Weltposition auf einer beliebigen Zellfolge (Anschlussgleis).
func _interp(arr: Array, pos: float) -> Dictionary:
	var nn := arr.size()
	var p := clampf(pos, 0.0, float(nn - 1))
	var i := int(floor(p))
	var j := mini(i + 1, nn - 1)
	var a: Vector2 = (Vector2(arr[i]) + Vector2(0.5, 0.5)) * 32.0
	var b: Vector2 = (Vector2(arr[j]) + Vector2(0.5, 0.5)) * 32.0
	var h: Vector2 = (b - a) if j != i else ((a - (Vector2(arr[i - 1]) + Vector2(0.5, 0.5)) * 32.0) if i > 0 else Vector2(1, 0))
	return {"world": a.lerp(b, p - float(i)), "heading": h.normalized() if h != Vector2.ZERO else Vector2(1, 0)}


## Signal an der Ausfahrt von Halt s in Richtung d: Fahrt (gruen), wenn der Block dahinter frei ist.
func signal_clear(s: int, d: int) -> bool:
	var j := s + d
	if j < 0 or j >= stops.size():
		return true
	return _block_free(_block(s, j), d, "") and not disruptions.has(_block(s, j))


func branch_clear() -> bool:
	return not blocks.has(BRANCH)


## Beide Staedte liegen an der Linie und der Betrieb laeuft (mindestens ein Zug mit Triebfahrzeugfuehrer).
func connects(a: int, b: int) -> bool:
	return a != b and not path.is_empty() and stop_of_town(a) >= 0 and stop_of_town(b) >= 0 and (facility == "" or drivers() > 0)


## Zielstation erreichbar ohne gestoerten Abschnitt.
func open_between(a: int, b: int) -> bool:
	var sa := stop_of_town(a)
	var sb := stop_of_town(b)
	for blk in range(mini(sa, sb), maxi(sa, sb)):
		if disruptions.has(blk):
			return false
	return true


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
		if is_freight(t) and not on_main(t):
			where = {"lager": "am Güterbahnhof (Beladen)", "anschluss": "auf dem Anschlussgleis", "einfahrt": "am Einfahrsignal der Weiche",
				"rueck": "auf dem Anschlussgleis zum Güterbahnhof"}.get(str(t.phase), "")
		elif str(t.state) == "fahrt" and t.has("exit_at"):
			where = "%s → Güterbahnhof" % sim.towns.name_of(int(stops[int(t.stop)].town))
		elif str(t.state) == "fahrt":
			where = "%s → %s" % [sim.towns.name_of(int(stops[int(t.stop)].town)), sim.towns.name_of(int(stops[int(t.target)].town))]
		else:
			where = "in %s" % sim.towns.name_of(int(stops[int(t.stop)].town))
		tl.append({"zug": t.id, "status": t.state, "ort": where, "verspaetung_min": snappedf(float(t.delay), 0.1), "grund": str(t.get("grund", "")),
			"fahrten": int(t.trips), "fahrgaeste": passengers(t), "art": "Güterzug" if is_freight(t) else "Regionalbahn", "ladung": int(t.get("ladung", 0))})
	var wt := {}
	for i in stops.size():
		wt[sim.towns.name_of(int(stops[i].town))] = waiting_at(i)
	return {"linie": stops.map(func(s): return sim.towns.name_of(int(s.town))), "zuege": tl, "laenge_felder": path.size(),
		"fahrzeit_min": snappedf(float(path.size()) / SPEED, 1.0), "statistik": stats.duplicate(), "wartende": wt,
		"personal": {"triebfahrzeugfuehrer": drivers(), "zugbegleiter": conductors()}, "gesellschaft_saldo": snappedf(float(sim.economy.accounts.get(ACCT, 0.0)), 1.0),
		"letzter_ausgleich": last_settle, "fahrpreis_beispiel": fare(0, stops.size() - 1) if stops.size() > 1 else 0.0,
		"stoerungen": disruptions.values().map(func(dz): return {"art": dz.art, "seit_min": snappedf(sim.game_min - float(dz.since), 1.0), "trupp_aus": sim.towns.name_of(int(dz.town))}),
		"schranken_zu": closed.size(), "ausbau": expansion_options(), "gueter_wartend": queued_units()}


func to_dict() -> Dictionary:
	return {"trains": trains, "blocks": blocks, "stats": stats, "waiting": waiting, "by_town": by_town, "last_settle": last_settle, "facility": facility,
		"cells_acc": _cells_acc, "disruptions": disruptions, "double_blocks": double_blocks, "planned_tracks": planned_tracks, "ordered": ordered,
		"freight_queue": freight_queue}


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
	double_blocks = {}
	for k in d.get("double_blocks", {}):
		double_blocks[int(k)] = true
	planned_tracks = {}
	var pt: Dictionary = d.get("planned_tracks", {})
	for k in pt:
		planned_tracks[str(k)] = int(pt[k])
	ordered = d.get("ordered", []).map(func(x): return int(x))
	freight_queue = d.get("freight_queue", [])
	disruptions = {}
	var dd: Dictionary = d.get("disruptions", {})
	for k in dd:
		disruptions[int(k)] = dd[k]
