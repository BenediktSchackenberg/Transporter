class_name AirNetwork
extends RefCounted
## Regionaler Flugverkehr zwischen den Staedten (Auftrag 17, Abschnitt 10). Nur in der Region (mehrere Flughaefen); erweitert die
## Flughaefen (Airport je Ort) um echte Fluege. Betreiber ist der regionale Dienstleister "Regionalflug" (Konto A0, kein Spielerplatz).
##
## Strecken: Nachbarstaedte in Ortsreihenfolge (zusammenhaengendes Startnetz), je Strecke ein Flugzeug im Pendelbetrieb.
## Flugablauf (Zustand je Flug, Darstellung folgt ihm): abfertigung (Beladung/Einstieg) -> rollen -> in_der_luft -> gelandet ->
## entladen -> fertig. Fracht: Buchung reserviert die Ware am Abgangsort (Anlieferung zum Flughafen braucht Fahrzeit), geladen wird nur,
## was angeliefert und vor Abflug gebucht ist (Kapazitaet je Flug); die Ware steht erst nach der Entladung im Frachtterminal des Ziels
## (Eigentum bleibt beim Versender). Passagiere: Bewohner mit Reisegrund, Ticket aus dem eigenen Guthaben; sie bleiben dieselben Personen
## (Reisestatus), kehren nach dem Aufenthalt zurueck. Kosten: Kraftstoff (an X0), Landegebuehr an die Zielstadt, Abfertigung an die
## Abgangsstadt. Ohne Geld fliegt der Betreiber nicht (unrentable Strecke ruht).

const ACCOUNT := "A0"
const START_CAPITAL := 60000.0       # Startkapital des Betreibers (Investor von ausserhalb: X0 -> A0, im Geldbuch verbucht)
const SEATS := 12
const CARGO_UNITS := 20              # Ladeeinheiten je Flug
const TURN_MIN := 25.0               # Abfertigung am Boden (Spielminuten)
const TAXI_MIN := 4.0
const UNLOAD_MIN := 8.0
const TICKET := 55.0
const MIN_PAX := 3                    # Abflug erst ab 3 Reisenden oder angelieferter Fracht ...
const MAX_WAIT := 100.0              # ... oder wenn die aelteste Buchung so lange (Spielminuten) wartet
const CARGO_BASE := 30.0
const CARGO_UNIT := 6.0
const FUEL_BASE := 45.0
const FUEL_PER_CELL := 0.35
const LANDING_FEE := 60.0
const HANDLING_FEE := 25.0
const TRIP_CHANCE := 0.004           # je Bewohner und Tag: Reise in eine Nachbarstadt (Besuch, Arzt, Geschaeft)
const STAY_DAYS := 2
const REASONS := ["Familienbesuch", "Geschäftsreise", "Arzttermin", "Einkauf", "Behördengang"]

var sim
var enabled := false
var routes: Array = []               # [{id, a, b, cells, minutes}]
var planes: Array = []               # [{id, route, at (Ort), flight ("" am Boden)}]
var flights := {}                    # "F<n>" -> {id, plane, route, from, to, status, t0 (Abflug), t_air, t_land, t_done, cargo: [Buchungs-IDs], pax: [Buchungs-IDs]}
var bookings := {}                   # "L<n>" -> Fracht {kind cargo, cid, item, qty, units, from, to, loc, ready_min, status, fee, flight}
                                     # "Y<n>" -> Reise {kind pax, person, from, to, reason, status, flight, return_day, back}
var stats := {"fluege": 0, "passagiere": 0, "fracht_einheiten": 0, "erloese": 0.0, "kosten": 0.0, "ausgefallen": 0}
var _next := 1
var _rng := RandomNumberGenerator.new()


func setup(simulation) -> void:
	sim = simulation
	if not sim.towns.is_region():
		return
	enabled = true
	sim.economy.accounts[ACCOUNT] = 0.0
	sim.economy.transfer("X0", ACCOUNT, START_CAPITAL)
	for k in sim.towns.count() - 1:
		_add_route(k, k + 1)
	for r in routes:
		planes.append({"id": "FZ%d" % (planes.size() + 1), "route": r.id, "at": int(r.a), "flight": "", "next_dep": 30.0 + 15.0 * planes.size()})
	sim.day_changed.connect(on_day)


func _add_route(a: int, b: int) -> void:
	var ta: Dictionary = sim.towns.airport(a).track
	var tb: Dictionary = sim.towns.airport(b).track
	if ta.is_empty() or tb.is_empty():
		return
	var d := Vector2(int(ta.run_x1), int(ta.run_y)).distance_to(Vector2(int(tb.run_x1), int(tb.run_y)))
	routes.append({"id": "S%d" % (routes.size() + 1), "a": a, "b": b, "cells": int(d), "minutes": snappedf(12.0 + d * 0.12, 0.5)})


func route_between(a: int, b: int) -> Dictionary:
	for r in routes:
		if (int(r.a) == a and int(r.b) == b) or (int(r.a) == b and int(r.b) == a):
			return r
	return {}


func cash() -> float:
	return float(sim.economy.accounts.get(ACCOUNT, 0.0))


# ------------------------------------------------------------------ Buchungen
## Luftfracht: Ware der Firma an einem Standort ihrer Stadt in die Nachbarstadt. Die Ware wird reserviert und zum Flughafen gebracht
## (Anlieferung = Fahrzeit auf der Strasse), dann mit dem naechsten Flug mit freier Kapazitaet befoerdert.
func book_cargo(cid: int, item: String, qty: int, from_loc: int, to_town: int) -> Dictionary:
	if not enabled:
		return {"ok": false, "msg": "Kein Flugnetz."}
	var c = sim.company(cid)
	var from_town: int = sim.towns.of_building(from_loc)
	var r := route_between(from_town, to_town)
	if r.is_empty():
		return {"ok": false, "msg": "Keine Direktverbindung %s – %s." % [sim.towns.name_of(from_town), sim.towns.name_of(to_town)]}
	var acct := "C%d" % cid
	if sim.stock.available(item, acct, from_loc) < qty or qty <= 0:
		return {"ok": false, "msg": "Nicht genug %s am Standort %d." % [item, from_loc]}
	var units := Harbor.units_of(item, qty)
	if units > CARGO_UNITS:
		return {"ok": false, "msg": "Höchstens %d Ladeeinheiten je Flug (%d gebucht)." % [CARGO_UNITS, units]}
	var fee := snappedf(CARGO_BASE + CARGO_UNIT * float(units), 1.0)
	if c.ledger.cash < fee:
		return {"ok": false, "msg": "Frachtentgelt %s nicht gedeckt." % Catalog.money(fee)}
	var id := "L%d" % _next
	_next += 1
	if not sim.stock.reserve("air:" + id, item, qty, acct, from_loc):
		return {"ok": false, "msg": "Reservierung fehlgeschlagen."}
	c.ledger.book("trade_expense", -fee, true, "Luftfracht %s nach %s" % [id, sim.towns.name_of(to_town)], sim.game_min, ACCOUNT)
	stats.erloese = float(stats.erloese) + fee
	var road: Array = sim.nav.road_path(sim.city.building(from_loc).road, sim.city.building(_cargo_building(from_town)).road)
	var ready: float = sim.game_min + maxf(5.0, float(road.size()) * 0.4)   # Zubringer zum Frachtterminal
	bookings[id] = {"id": id, "kind": "cargo", "cid": cid, "item": item, "qty": qty, "units": units, "from": from_town, "to": to_town, "loc": from_loc,
		"ready_min": ready, "status": "anlieferung", "fee": fee, "flight": ""}
	sim.log_event("%s bucht Luftfracht %s: %d %s von %s nach %s (%s)." % [c.company_name, id, qty, Production.item_name(item), sim.towns.name_of(from_town), sim.towns.name_of(to_town), Catalog.money(fee)], "info", cid)
	return {"ok": true, "msg": "Luftfracht %s gebucht (%s, bereit am Flughafen in %d min)." % [id, Catalog.money(fee), int(ready - sim.game_min)], "ref": id}


func _cargo_building(town: int) -> int:
	var a: Dictionary = sim.city.towns[town].get("airport", {})
	return int(a.get("cargo", a.get("terminal", -1)))


## Flugreise eines Bewohners in eine Nachbarstadt (Ticket aus seinem Guthaben). Rueckflug wird nach dem Aufenthalt gebucht.
func book_trip(person: Dictionary, to_town: int, reason: String, back: bool = false) -> Dictionary:
	var from_town: int = int(person.get("reise_ort", sim.citizens.home_town(person)))
	var r := route_between(from_town, to_town)
	if r.is_empty():
		return {"ok": false, "msg": "Keine Direktverbindung."}
	if float(person.get("balance", 0.0)) < TICKET:
		return {"ok": false, "msg": "Ticket nicht bezahlbar."}
	person.balance = float(person.balance) - TICKET
	sim.economy.transfer(Population.ACCOUNT, ACCOUNT, TICKET)
	stats.erloese = float(stats.erloese) + TICKET
	var id := "Y%d" % _next
	_next += 1
	bookings[id] = {"id": id, "kind": "pax", "person": int(person.id), "from": from_town, "to": to_town, "reason": reason, "status": "gebucht", "flight": "", "back": back, "since": sim.game_min}
	person["reise"] = id
	return {"ok": true, "msg": "Reise %s gebucht." % id, "ref": id}


# ------------------------------------------------------------------ Ablauf
## Je Spielminute (Simulation._minute_tick): Fluege fortschalten, neue Abfluege starten.
func tick(now: float) -> void:
	if not enabled:
		return
	for b in bookings.values():
		if b.kind == "cargo" and b.status == "anlieferung" and now >= float(b.ready_min):
			b.status = "bereit"
			b["since"] = now
	for f in flights.values():
		_advance(f, now)
	for p in planes:
		if p.flight == "" and now >= float(p.next_dep):
			var r := _route(str(p.route))
			var here := int(p.at)
			var there := int(r.b) if here == int(r.a) else int(r.a)
			if _due(here, there, now) or (_waiting(here, there).is_empty() and _due(there, here, now)):
				_depart(p, now)   # mit Ladung, oder leer zur anderen Seite, wo Buchungen zu lange warten (Umsetzflug)
			else:
				p.next_dep = now + 10.0


func _route(id: String) -> Dictionary:
	for x in routes:
		if x.id == id:
			return x
	return {}


## Wartende Buchungen einer Richtung (Fracht angeliefert bzw. Reisende gebucht).
func _waiting(from: int, to: int) -> Array:
	return bookings.values().filter(func(b): return int(b.from) == from and int(b.to) == to and str(b.flight) == "" and ((b.kind == "cargo" and b.status == "bereit") or (b.kind == "pax" and b.status == "gebucht")))


## Lohnt ein Abflug? Ab MIN_PAX Reisenden, bei angelieferter Fracht oder wenn die aelteste Buchung MAX_WAIT wartet.
func _due(from: int, to: int, now: float) -> bool:
	var w := _waiting(from, to)
	if w.is_empty():
		return false
	if w.any(func(b): return b.kind == "cargo") or w.filter(func(b): return b.kind == "pax").size() >= MIN_PAX:
		return true
	var oldest := now
	for b in w:
		oldest = minf(oldest, float(b.get("since", now)))
	return now - oldest >= MAX_WAIT


func _depart(p: Dictionary, now: float) -> void:
	var r: Dictionary = {}
	for x in routes:
		if x.id == p.route:
			r = x
	var from := int(p.at)
	var to := int(r.b) if from == int(r.a) else int(r.a)
	var fuel := FUEL_BASE + FUEL_PER_CELL * float(r.cells)
	var fees := LANDING_FEE + HANDLING_FEE
	if cash() < fuel + fees:
		p.next_dep = now + 60.0
		stats.ausgefallen = int(stats.ausgefallen) + 1
		return   # Betreiber zahlungsunfaehig: Flug faellt aus (keine kostenlose Befoerderung)
	var id := "F%d" % _next
	_next += 1
	var f := {"id": id, "plane": p.id, "route": r.id, "from": from, "to": to, "status": "abfertigung", "t0": now + TURN_MIN,
		"t_air": now + TURN_MIN + TAXI_MIN, "t_land": now + TURN_MIN + TAXI_MIN + float(r.minutes), "t_done": now + TURN_MIN + TAXI_MIN + float(r.minutes) + TAXI_MIN + UNLOAD_MIN,
		"cargo": [], "pax": [], "units": 0}
	flights[id] = f
	p.flight = id


## Zustandswechsel eines Flugs zur Spielzeit now.
func _advance(f: Dictionary, now: float) -> void:
	match str(f.status):
		"abfertigung":
			if now >= float(f.t0):
				_board(f)
				f.status = "rollen"
		"rollen":
			if now >= float(f.t_air):
				f.status = "in_der_luft"
				_pay_costs(f)
		"in_der_luft":
			if now >= float(f.t_land):
				f.status = "gelandet"
		"gelandet":
			if now >= float(f.t_land) + TAXI_MIN:
				f.status = "entladen"
		"entladen":
			if now >= float(f.t_done):
				_unload(f)
				f.status = "fertig"
				stats.fluege = int(stats.fluege) + 1
				for p in planes:
					if p.flight == f.id:
						p.flight = ""
						p.at = int(f.to)
						p.next_dep = now + 5.0


## Einstieg und Beladung: nur angelieferte Fracht und gebuchte Reisende dieser Richtung, bis die Kapazitaet erreicht ist.
func _board(f: Dictionary) -> void:
	var ids: Array = bookings.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = bookings[id]
		if int(b.from) != int(f.from) or int(b.to) != int(f.to) or str(b.flight) != "":
			continue
		if b.kind == "cargo" and b.status == "bereit" and int(f.units) + int(b.units) <= CARGO_UNITS:
			b.flight = f.id
			b.status = "an_bord"
			f.cargo.append(id)
			f.units = int(f.units) + int(b.units)
		elif b.kind == "pax" and b.status == "gebucht" and f.pax.size() < SEATS:
			b.flight = f.id
			b.status = "an_bord"
			f.pax.append(id)
			var p: Dictionary = sim.population.person_index().get(int(b.person), {})
			if not p.is_empty():
				p["unterwegs"] = f.id


func _pay_costs(f: Dictionary) -> void:
	var r: Dictionary = {}
	for x in routes:
		if x.id == f.route:
			r = x
	var fuel := FUEL_BASE + FUEL_PER_CELL * float(r.cells)
	sim.economy.transfer(ACCOUNT, "X0", fuel)                                  # Kerosin (Import)
	sim.economy.transfer(ACCOUNT, Towns.account_of(int(f.from)), HANDLING_FEE)   # Abfertigung an die Abgangsstadt
	sim.economy.transfer(ACCOUNT, Towns.account_of(int(f.to)), LANDING_FEE)      # Landegebuehr an die Zielstadt
	stats.kosten = float(stats.kosten) + fuel + HANDLING_FEE + LANDING_FEE


## Entladen: Fracht ins Frachtterminal der Zielstadt (Eigentum Versender), Reisende kommen an.
func _unload(f: Dictionary) -> void:
	var dest := _cargo_building(int(f.to))
	for id in f.cargo:
		var b: Dictionary = bookings[id]
		sim.stock.move_reserved("air:" + id, "C%d" % int(b.cid), dest, "Luftfracht %s angekommen" % id, sim.game_min)
		b.status = "angekommen"
		b["loc_to"] = dest
		stats.fracht_einheiten = int(stats.fracht_einheiten) + int(b.units)
	var idx: Dictionary = sim.population.person_index()
	for id in f.pax:
		var b: Dictionary = bookings[id]
		b.status = "angekommen"
		stats.passagiere = int(stats.passagiere) + 1
		var p: Dictionary = idx.get(int(b.person), {})
		if p.is_empty():
			continue
		p.erase("unterwegs")
		if bool(b.back):
			p.erase("reise_ort")   # wieder zu Hause
			p.erase("reise")
		else:
			p["reise_ort"] = int(f.to)
			b["return_day"] = GameCalendar.day_of(sim.game_min) + STAY_DAYS


## Taeglich: Rueckreisen buchen, neue Reisen einiger Bewohner (Grund, Ziel = Nachbarstadt mit Direktverbindung).
func on_day(day: int) -> void:
	var idx: Dictionary = sim.population.person_index()
	for b in bookings.values():
		if b.kind == "pax" and b.status == "angekommen" and not bool(b.back) and day >= int(b.get("return_day", day + 1)):
			var p: Dictionary = idx.get(int(b.person), {})
			b.status = "abgeschlossen"
			if not p.is_empty():
				var home: int = sim.citizens.home_town(p)
				var rb := book_trip(p, home, "Rückreise", true)
				if not rb.ok:
					p.erase("reise_ort")   # ohne Rueckflug: faehrt mit dem Bus/Auto zurueck (Strasse)
					p.erase("reise")
	_rng.seed = hash([sim.city.seed_value, day, "reisen"])
	for p in sim.citizens.people:
		if p.has("reise") or float(p.get("balance", 0.0)) < 150.0 or _rng.randf() >= TRIP_CHANCE:
			continue
		var home: int = sim.citizens.home_town(p)
		var dests: Array = []
		for r in routes:
			if int(r.a) == home:
				dests.append(int(r.b))
			elif int(r.b) == home:
				dests.append(int(r.a))
		if dests.is_empty():
			continue
		book_trip(p, dests[_rng.randi() % dests.size()], REASONS[_rng.randi() % REASONS.size()])


# ------------------------------------------------------------------ Darstellung und Uebersicht
## Flugzeugposition (Felder) und Hoehe fuer AirView: am Boden auf dem Vorfeld bzw. der Bahn, in der Luft auf einer Linie zwischen den
## Flughaefen mit Steig-/Sinkbogen. {pos, h, dir, on_ground} oder {}.
func plane_state(p: Dictionary, now: float) -> Dictionary:
	var f: Dictionary = flights.get(str(p.flight), {})
	if f.is_empty():
		var tr: Dictionary = sim.towns.airport(int(p.at)).track
		return {"pos": Vector2(float(tr.apron[0]), float(tr.apron[1])), "h": 0.0, "dir": 0, "on_ground": true} if not tr.is_empty() else {}
	var ta: Dictionary = sim.towns.airport(int(f.from)).track
	var tb: Dictionary = sim.towns.airport(int(f.to)).track
	var a_apron := Vector2(float(ta.apron[0]), float(ta.apron[1]))
	var a_end := Vector2(float(ta.run_x1), float(ta.run_y))
	var b_start := Vector2(float(tb.run_x0) + 1.0, float(tb.run_y))
	var b_apron := Vector2(float(tb.apron[0]), float(tb.apron[1]))
	match str(f.status):
		"abfertigung":
			return {"pos": a_apron, "h": 0.0, "dir": 0, "on_ground": true}
		"rollen":
			var k := clampf((now - float(f.t0)) / TAXI_MIN, 0.0, 1.0)
			return {"pos": a_apron.lerp(a_end, k), "h": 0.0, "dir": 0, "on_ground": true}
		"in_der_luft":
			var k2 := clampf((now - float(f.t_air)) / maxf(1.0, float(f.t_land) - float(f.t_air)), 0.0, 1.0)
			var pos := a_end.lerp(b_start, k2)
			var h := 11.0 * sin(PI * k2)
			return {"pos": pos, "h": h, "dir": AirView._dir_of(a_end, b_start), "on_ground": h < 0.3}
		"gelandet", "entladen":
			var k3 := clampf((now - float(f.t_land)) / TAXI_MIN, 0.0, 1.0)
			return {"pos": b_start.lerp(b_apron, k3), "h": 0.0, "dir": 2, "on_ground": true}
	return {"pos": b_apron, "h": 0.0, "dir": 0, "on_ground": true}


func summary() -> Dictionary:
	return {"betreiber": "Regionalflug", "kasse": int(cash()), "strecken": routes.map(func(r): return "%s – %s (%d min)" % [sim.towns.name_of(int(r.a)), sim.towns.name_of(int(r.b)), int(r.minutes)]),
		"fluege_unterwegs": flights.values().filter(func(f): return f.status != "fertig").map(func(f): return {"id": f.id, "von": sim.towns.name_of(int(f.from)), "nach": sim.towns.name_of(int(f.to)), "status": f.status, "passagiere": f.pax.size(), "fracht_le": int(f.units)}),
		"statistik": stats.duplicate()}


func to_dict() -> Dictionary:
	# fertige Fluege nicht aufheben (nur die letzten 20 fuer die Anzeige)
	var keep := {}
	var done: Array = flights.values().filter(func(f): return f.status == "fertig").map(func(f): return f.id)
	for id in flights:
		if flights[id].status != "fertig" or id in done.slice(-20):
			keep[id] = flights[id]
	return {"enabled": enabled, "routes": routes.duplicate(true), "planes": planes.duplicate(true), "flights": keep.duplicate(true), "bookings": bookings.duplicate(true), "stats": stats.duplicate(), "next": _next}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or not enabled:
		return
	routes = d.get("routes", routes).duplicate(true)
	planes = d.get("planes", planes).duplicate(true)
	flights = d.get("flights", {}).duplicate(true)
	bookings = d.get("bookings", {}).duplicate(true)
	stats = d.get("stats", stats)
	_next = int(d.get("next", 1))
	for p in planes:
		p.at = int(p.at)
	for b in bookings.values():
		for k in ["cid", "qty", "units", "from", "to", "loc", "person"]:
			if b.has(k):
				b[k] = int(b[k])
	for f in flights.values():
		f.from = int(f.from)
		f.to = int(f.to)
		f.units = int(f.units)
