class_name RegionalCouncil
extends RefCounted
## Regionalrat (Auftrag 20, Etappe 10, docs/PUBLIC_SERVICES.md). Die Buergermeister aller Staedte treffen sich alle 30 Tage im
## Ratsgebaeude nahe der Kartenmitte (beim Grosslager):
##  - Anreise sichtbar im Dienstwagen; die Sitzung beginnt, wenn alle da sind (spaetestens 3 Spielstunden nach Abfahrt).
##  - Antraege: jede Stadt bringt hoechstens einen ein (Regel-Buergermeister nach Lage, KI-Buergermeister ueber die Aktion
##    regionalrat_antrag). Arten: verbindung (Strasse zwischen zwei Orten, ueber RegionalProjects gebaut), kh_ausbau (Betten des
##    Kreiskrankenhauses +50 %), drehleiter (gemeinsame Drehleiter fuer eine Wache), zweckverband (Kreiskrankenhaus in gemeinsame
##    Traegerschaft: Unterhalt nach Einwohnern geteilt - Eigentumsfrage), kkw_anteile (Aenderung der Kraftwerksanteile).
##  - Abstimmung: Mehrheit = 3 von 4 Stimmen (bei n Staedten aufgerundet 75 %), Eigentumsfragen einstimmig; die Kraftwerksanteile
##    bleiben fest 25/25/25/25 (Antrag unzulaessig).
##  - Verhandlung: faellt ein Antrag durch, bietet die antragstellende Stadt bis zu zweimal an, 15 Prozentpunkte mehr der Kosten zu
##    tragen (zulasten der Gegenstimmen), sofern ihre Kasse das deckt; dann neue Abstimmung.
##  - Stimmverhalten: Zustimmung, wenn der Nutzen fuer die eigene Stadt reicht und der Kostenanteil hoechstens die Haelfte der
##    verfuegbaren Mittel ist; ohne Kostenanteil stimmen Staedte zu, solange der Antrag ihnen nicht schadet.
##  - Finanzierung: Beschluesse werden sofort bezahlt (Anteile von den Stadtkassen an die Dienstleister bzw. an die Baufirma ueber
##    RegionalProjects); Wirkung wird sofort umgesetzt, Strassen werden sichtbar gebaut.

const EVERY := 30
const FIRST := 15
const WAIT_MIN := 180.0
const MAJORITY := 0.75
const CONCESSION := 0.15
const COSTS := {"kh_ausbau": 600000.0, "drehleiter": 750000.0, "zweckverband": 0.0}
const KINDS := ["verbindung", "kh_ausbau", "drehleiter", "zweckverband", "kkw_anteile", "autobahn", "bahn_takt", "zweites_gleis"]
const RAIL_WAIT_DOUBLE := 120.0   # Wartezeit am Signal (Spielminuten seit Beginn) auf einem Abschnitt, ab der Regel-Buergermeister ein zweites Gleis beantragen
const RAIL_CROWD := 120           # Wartende am eigenen Bahnsteig, ab denen Regel-Buergermeister einen weiteren Triebwagen beantragen
const OWNERSHIP := ["zweckverband"]

var sim
var hall := -1             # Ratsgebaeude (Gebaeude-ID)
var meeting := {}          # laufende Sitzung {id, day, phase, cars: {k: Fahrzeug-ID}, until}
var queued := {}           # Stadt -> Antrag der KI {kind, partner, reason}
var history: Array = []    # [{id, day, antraege: [{kind, by, cost, shares, votes, result, rounds, text}]}]
var _next := 1
var _day := -1


func setup(simulation) -> void:
	sim = simulation
	if enabled():
		sim.day_changed.connect(on_day)


func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region() and not sim.city.hub.is_empty()


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func required_yes(n: int, kind: String) -> int:
	return n if kind in OWNERSHIP else ceili(MAJORITY * float(n) - 0.0001)


# ------------------------------------------------------------------ Ratsgebaeude
func ensure_hall() -> void:
	if hall >= 0:
		return
	var hc: Array = sim.city.hub.center
	var c := Vector2i(int(hc[0]), int(hc[1]))
	for r in range(6, 60, 2):
		for dy in range(-r, r + 1, 2):
			for dx in [-r, r]:
				for q in [c + Vector2i(dx, dy), c + Vector2i(dy, dx)]:
					var rect := Rect2i(q, Vector2i(3, 3))
					if sim.civic._cells_free(rect) and sim.civic._touches_road(rect):
						var b: Dictionary = sim.events._add_building("council_hall", rect, "Regionalrat")
						if not b.is_empty():
							b["role"] = "council"
							hall = int(b.id)
							sim.events.buildings_added.emit([b.id])
							sim.log_event("Das Ratsgebäude des Regionalrats steht nahe dem Großlager.", "info")
							return


func hall_road() -> Vector2i:
	return sim.city.building(hall).road


# ------------------------------------------------------------------ Ablauf
func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	ensure_hall()
	if hall >= 0 and meeting.is_empty() and day >= FIRST and (day - FIRST) % EVERY == 0:
		convene()


## Sitzung einberufen: Dienstwagen aller Buergermeister fahren zum Ratsgebaeude.
func convene() -> void:
	ensure_hall()
	if hall < 0:
		return
	meeting = {"id": "RR%d" % _next, "day": _today(), "phase": "anreise", "cars": {}, "until": sim.game_min + WAIT_MIN}
	_next += 1
	for t in sim.towns.list:
		var k := int(t.id)
		var from: Vector2i = sim.city.building(int(t.town_hall)).road
		var v: Dictionary = sim.fleet._spawn("dienstwagen", from, hall_road(), INF, from, "%s fährt zum Regionalrat" % sim.towns.mayor(k).name)
		v["town"] = k
		if sim.civic.profiles.has(k):
			v["color"] = sim.civic.profiles[k].color
		meeting.cars[k] = int(v.id)
	sim.log_event("Regionalrat %s: Die Bürgermeister reisen an." % meeting.id, "info")


func _car(id: int) -> Dictionary:
	for v in sim.fleet.vehicles:
		if int(v.id) == id:
			return v
	return {}


func update(_dt: float) -> void:
	if meeting.is_empty():
		return
	match str(meeting.phase):
		"anreise":
			var all := true
			for k in meeting.cars:
				var v := _car(int(meeting.cars[k]))
				if not v.is_empty() and not v.mover.arrived():
					all = false
			if all or sim.game_min >= float(meeting.until):
				session()
		"abreise":
			var done := true
			for k in meeting.cars:
				var v := _car(int(meeting.cars[k]))
				if v.is_empty():
					continue
				if v.mover.arrived():
					sim.fleet.vehicles.erase(v)
				else:
					done = false
			if done:
				meeting = {}


## Sitzung: Antraege sammeln, verhandeln, abstimmen, beschlossene umsetzen; danach Abreise.
func session() -> void:
	var rec := {"id": meeting.id, "day": _today(), "antraege": []}
	for t in sim.towns.list:
		var k := int(t.id)
		var a: Dictionary = queued.get(k, {})
		if a.is_empty():
			a = rule_proposal(k)
		if a.is_empty():
			continue
		a["by"] = k
		rec.antraege.append(decide(a))
	queued.clear()
	history.append(rec)
	if history.size() > 24:
		history.pop_front()
	meeting.phase = "abreise"
	for k in meeting.cars:
		var v := _car(int(meeting.cars[k]))
		if not v.is_empty():
			v.label = "%s fährt zurück" % sim.towns.mayor(int(k)).name
			sim.fleet.reroute(v, sim.city.building(int(sim.towns.get_t(int(k)).town_hall)).road)
	sim.log_event("Regionalrat %s: %d Anträge, %d beschlossen." % [rec.id, rec.antraege.size(), rec.antraege.filter(func(x): return x.result == "beschlossen").size()], "info")


# ------------------------------------------------------------------ Antraege
## KI-Buergermeister: Antrag fuer die naechste Sitzung vormerken.
func queue_proposal(k: int, kind: String, partner: int = -1, reason: String = "") -> Dictionary:
	if kind not in KINDS:
		return {"ok": false, "msg": "Unbekannte Antragsart %s (%s)." % [kind, ", ".join(KINDS)]}
	queued[k] = {"kind": kind, "partner": partner, "reason": reason.left(200)}
	return {"ok": true, "msg": "Antrag %s für die nächste Sitzung des Regionalrats vorgemerkt." % kind}


func _hospital() -> Dictionary:
	for f in sim.municipal.facilities.values():
		if f.code == "KH-01":
			return f
	return {}


## Regel-Buergermeister: hoechstens ein Antrag nach Lage der eigenen Stadt.
func rule_proposal(k: int) -> Dictionary:
	var R: RegionalProjects = sim.regional
	if not R.has_highway() and R.traffic_mean(14) >= RegionalProjects.HIGHWAY_TRAFFIC and float(R.traffic_shares().get(str(k), 0.0)) >= 1.0 / float(maxi(1, sim.towns.count())):
		return {"kind": "autobahn", "reason": "Überlandverkehr %.0f Fahrzeugsekunden je Tag (Schwelle %.0f); %s nutzt die Strecken überdurchschnittlich" % [
			R.traffic_mean(14), RegionalProjects.HIGHWAY_TRAFFIC, sim.towns.name_of(k)]}
	var kh := _hospital()
	if not kh.is_empty() and sim.rescue.beds(kh) > 0 and float(sim.rescue.occupied(kh)) >= 0.8 * float(sim.rescue.beds(kh)) and int(kh.town) == k:
		return {"kind": "kh_ausbau", "reason": "Krankenhaus zu 80 % belegt"}
	if not kh.is_empty() and int(kh.town) == k and not kh.has("shares") and sim.towns.count() > 1:
		return {"kind": "zweckverband", "reason": "Das Kreiskrankenhaus versorgt alle Städte; der Unterhalt soll geteilt werden."}
	if int(sim.fire.stats.ausgebrannt) > 0 and not sim.municipal.vehicles.values().any(func(v): return str(v.type) == "DLK 23"):
		return {"kind": "drehleiter", "reason": "Gebäude sind ausgebrannt; die Region hat keine Drehleiter."}
	var T: RailTraffic = sim.trains   # Auftrag 22 Phase 6 Schritt 5: Bahnausbau nach Lage
	if T != null and not T.path.is_empty() and T.stop_of_town(k) >= 0:
		if T.waiting_at(T.stop_of_town(k)) >= RAIL_CROWD and T.trains.size() + T.ordered.size() < RailTraffic.MAX_TRAINS:
			return {"kind": "bahn_takt", "reason": "%d Fahrgäste warten am Bahnsteig von %s" % [T.waiting_at(T.stop_of_town(k)), sim.towns.name_of(k)]}
		var dp: Dictionary = T.plan_double()
		if dp.get("ok", false) and float(dp.wartezeit_min) >= RAIL_WAIT_DOUBLE and k in [int(T.stops[int(dp.block)].town), int(T.stops[int(dp.block) + 1].town)]:
			return {"kind": "zweites_gleis", "reason": "Züge warten %.0f Minuten vor dem eingleisigen Abschnitt %s – %s" % [float(dp.wartezeit_min), dp.von, dp.nach]}
	for t in sim.towns.list:
		var p := int(t.id)
		if p != k and p not in sim.regional.linked(k) and not sim.regional.items.values().any(func(r): return r.status in ["vorgeschlagen", "beschlossen", "im_bau"] and int(p) in [int(r.from), int(r.to)] and k in [int(r.from), int(r.to)]):
			return {"kind": "verbindung", "partner": p, "reason": "kürzere Wege nach %s" % sim.towns.name_of(p)}
	return {}


func _pop_shares(towns: Array) -> Dictionary:
	var total := 0.0
	var pops := {}
	for k in towns:
		pops[k] = float(maxi(1, sim.citizens.population_of(int(k))))
		total += float(pops[k])
	var out := {}
	for k in towns:
		out[str(k)] = float(pops[k]) / total
	return out


## Nutzen eines Antrags fuer eine Stadt (0..1).
func benefit(a: Dictionary, k: int) -> float:
	match str(a.kind):
		"verbindung":
			return 1.0 if k in [int(a.by), int(a.get("partner", -1))] else 0.0
		"kh_ausbau":
			var kh := _hospital()
			return 0.6 if not kh.is_empty() and float(sim.rescue.occupied(kh)) >= 0.5 * float(maxi(1, sim.rescue.beds(kh))) else 0.2
		"drehleiter":
			return 0.8 if k == int(a.by) else 0.3
		"zweckverband":
			var kh2 := _hospital()
			return 1.0 if not kh2.is_empty() and int(kh2.town) == k else 0.4   # Mitsprache und gesicherte Betten
		"bahn_takt", "zweites_gleis":   # Staedte an der Linie: Nutzen nach Fahrgaesten am eigenen Bahnsteig
			var T: RailTraffic = sim.trains
			var s := T.stop_of_town(k) if T != null else -1
			return 0.0 if s < 0 else minf(1.0, 0.4 + float(T.waiting_at(s)) / 100.0)
		"autobahn":   # Nutzen nach eigenem Anteil am Ueberlandverkehr; Grundnutzen Erreichbarkeit
			return minf(1.0, 0.3 + 0.7 * float(sim.regional.traffic_shares().get(str(k), 0.0)) * float(sim.towns.count()))
	return 0.0


func vote_of(a: Dictionary, k: int, shares: Dictionary) -> bool:
	var share := float(shares.get(str(k), 0.0))
	var cost := float(a.cost) * share
	var upkeep := float(a.get("upkeep", 0.0)) * share * 30.0
	var b := benefit(a, k)
	if cost + upkeep <= 0.0:
		return b >= 0.0
	return b >= 0.3 and cost + upkeep <= 0.5 * sim.towns.mayor(k).available_budget()


func decide(a: Dictionary) -> Dictionary:
	var by := int(a.by)
	var n: int = sim.towns.count()
	var res := {"kind": a.kind, "by": by, "von": sim.towns.name_of(by), "reason": str(a.get("reason", "")), "rounds": 0, "votes": {}, "result": "abgelehnt", "text": ""}
	if a.kind == "kkw_anteile":
		res.text = "unzulässig: Die Anteile am Kernkraftwerk bleiben fest 25/25/25/25."
		return res
	var towns: Array = sim.towns.list.map(func(t): return int(t.id))
	var shares := {}
	match str(a.kind):
		"verbindung":
			var pl: Dictionary = sim.regional.plan_link(by, int(a.get("partner", -1)))
			if not pl.get("ok", false):
				res.text = "nicht machbar: %s" % str(pl.get("msg", ""))
				return res
			a["cost"] = float(pl.kosten)
			shares = {str(by): 0.5, str(int(a.partner)): 0.5}
		"autobahn":
			if sim.regional.has_highway():
				res.text = "die Region hat bereits eine Autobahn"
				return res
			var hp: Dictionary = sim.regional.plan_highway()
			if not hp.get("ok", false):
				res.text = "nicht machbar: %s" % str(hp.get("msg", ""))
				return res
			a["cost"] = float(hp.kosten) * (1.0 - RegionalProjects.HIGHWAY_FEDERAL)   # Anteil der Staedte; den Rest traegt der Bund
			res["bund"] = float(hp.kosten) * RegionalProjects.HIGHWAY_FEDERAL
			shares = sim.regional.traffic_shares()
		"bahn_takt":
			var T: RailTraffic = sim.trains
			if T == null or T.path.is_empty() or T.trains.size() + T.ordered.size() >= RailTraffic.MAX_TRAINS:
				res.text = "nicht möglich: keine Linie oder schon %d Triebwagen" % RailTraffic.MAX_TRAINS
				return res
			a["cost"] = RailTraffic.TRAIN_PRICE * (1.0 - RailTraffic.LAND_SHARE)
			res["land"] = RailTraffic.TRAIN_PRICE * RailTraffic.LAND_SHARE
			shares = _pop_shares(towns)
		"zweites_gleis":
			var dp: Dictionary = sim.trains.plan_double() if sim.trains != null else {"ok": false, "msg": "keine Linie"}
			if not dp.get("ok", false):
				res.text = "nicht möglich: %s" % str(dp.get("msg", ""))
				return res
			a["cost"] = float(dp.kosten) * (1.0 - RailTraffic.LAND_SHARE)
			res["land"] = float(dp.kosten) * RailTraffic.LAND_SHARE
			shares = _pop_shares(towns)
		"zweckverband":
			var kh := _hospital()
			if kh.is_empty() or kh.has("shares"):
				res.text = "kein Kreiskrankenhaus in Einzelträgerschaft"
				return res
			a["cost"] = 0.0
			a["upkeep"] = float(kh.upkeep)
			shares = _pop_shares(towns)
		_:
			a["cost"] = float(COSTS.get(a.kind, 0.0))
			shares = _pop_shares(towns)
	res["cost"] = float(a.cost)
	var need := required_yes(n, str(a.kind))
	for rnd in 3:
		var yes := 0
		var votes := {}
		for k in towns:
			var y := vote_of(a, int(k), shares)
			votes[str(k)] = "ja" if y else "nein"
			if y:
				yes += 1
		res.votes = votes
		res.rounds = rnd + 1
		res["shares"] = shares.duplicate()
		if yes >= need:
			res.result = "beschlossen"
			break
		if rnd == 2 or float(a.cost) <= 0.0:
			break
		# Verhandlung: Antragsteller uebernimmt mehr, die Gegenstimmen weniger
		var no: Array = towns.filter(func(k): return votes[str(k)] == "nein" and int(k) != by)
		if no.is_empty():
			break
		var give := CONCESSION
		var mine := float(shares.get(str(by), 0.0)) + give
		if float(a.cost) * mine > sim.towns.mayor(by).available_budget():
			break
		shares[str(by)] = mine
		for k in no:
			shares[str(k)] = maxf(0.0, float(shares.get(str(k), 0.0)) - give / float(no.size()))
		var tot := 0.0
		for k in shares:
			tot += float(shares[k])
		for k in shares:
			shares[k] = float(shares[k]) / tot
	res.text = "%s: %d von %d Ja-Stimmen nötig, %s nach %d Runde(n)" % [_label(str(a.kind)), need, n, res.result, int(res.rounds)]
	if res.result == "beschlossen":
		_apply(a, res)
	sim.log_event("Regionalrat: Antrag %s (%s) – %s." % [_label(str(a.kind)), sim.towns.name_of(by), res.text], "info")
	return res


func _label(kind: String) -> String:
	return {"autobahn": "Autobahn", "verbindung": "Verbindungsstraße", "kh_ausbau": "Ausbau Kreiskrankenhaus", "drehleiter": "gemeinsame Drehleiter",
		"zweckverband": "Zweckverband Kreiskrankenhaus", "kkw_anteile": "Kraftwerksanteile", "bahn_takt": "weiterer Triebwagen (Regionalbahn)",
		"zweites_gleis": "zweites Gleis (Regionalbahn)"}.get(kind, kind)


func _pay(shares: Dictionary, cost: float, ressort: String) -> void:
	for k in shares:
		var amt := cost * float(shares[k])
		if amt > 0.0:
			sim.economy.transfer(Towns.account_of(int(k)), "S0", amt)
			sim.public_sector.departments[ressort] = float(sim.public_sector.departments.get(ressort, 0.0)) + amt


func _apply(a: Dictionary, res: Dictionary) -> void:
	var M: Municipal = sim.municipal
	match str(a.kind):
		"autobahn":
			var hr: Dictionary = sim.regional.propose_highway(int(a.by), res.shares, "Beschluss Regionalrat: " + str(a.get("reason", "")))
			res["ref"] = str(hr.get("ref", hr.get("msg", "")))
		"verbindung":
			var r: Dictionary = sim.regional.propose(int(a.by), "verbindung", int(a.partner), res.shares, "Beschluss Regionalrat")
			if r.get("ok", false):
				sim.regional.decide(str(r.ref), int(a.partner), true, "Beschluss Regionalrat")
			res["ref"] = str(r.get("ref", r.get("msg", "")))
		"kh_ausbau":
			var kh := _hospital()
			_pay(res.shares, float(a.cost), "Gesundheit")
			kh.capacity = int(kh.capacity) + maxi(2, int(kh.capacity) / 2)
			for b in kh.staff_need:
				kh.staff_need[b] = int(ceil(float(kh.staff_need[b]) * 1.5))
		"drehleiter":
			var st: Array = M.of_town(int(a.by), "feuerwehr")
			if st.is_empty():
				return
			_pay(res.shares, float(a.cost), "Sicherheit")
			M.add_vehicle(st[0].id, "DLK 23")
		"zweckverband":
			var kh := _hospital()
			kh["shares"] = res.shares.duplicate()
			kh.owner = "region"
		"bahn_takt":
			_pay(res.shares, float(a.cost), "Verkehr")
			sim.economy.transfer("X0", "S0", float(res.get("land", 0.0)))   # Landesanteil an den Hersteller
			res["ref"] = str(sim.trains.order_train().get("msg", ""))
		"zweites_gleis":
			res["ref"] = str(sim.trains.start_double(res.shares, str(a.get("reason", ""))).get("ref", ""))


# ------------------------------------------------------------------ Uebersicht, Speichern
func summary() -> Dictionary:
	return {"ratsgebaeude": hall >= 0, "naechste_sitzung_tag": FIRST + EVERY * maxi(0, ceili(float(_today() - FIRST) / float(EVERY))),
		"laufend": meeting.get("phase", ""), "letzte": history.back() if not history.is_empty() else {}, "vorgemerkt": queued.duplicate()}


func to_dict() -> Dictionary:
	return {"hall": hall, "history": history.duplicate(true), "queued": queued.duplicate(), "next": _next, "day": _day}


## Laden: eine laufende Sitzung wird nicht fortgesetzt (Dienstwagen gibt es nach dem Laden nicht mehr); naechster Termin regulaer.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	hall = int(d.get("hall", -1))
	history = d.get("history", [])
	_next = int(d.get("next", 1))
	_day = int(d.get("day", -1))
	for k in d.get("queued", {}):
		queued[int(k)] = d.queued[k]
	if hall >= 0 and sim.city.building(hall).size() > 0:
		sim.city.building(hall)["role"] = "council"
