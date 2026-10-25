class_name WorldEvents
extends RefCounted
## Automatischer Ereignismanager: Die Stadt entwickelt sich ohne Zutun des Zuschauers. Jedes Ereignis entsteht EINMAL aus einer
## nachpruefbaren Ursache (Wetter, Tagesablauf, Lagerbestaende, Wartung, Personal, Baufortschritt, Angebot/Nachfrage, Handlungen
## der Unternehmen), veraendert danach echte Zustaende der Simulation und endet nach einer Bedingung oder Dauer.
## Abklingzeiten je Ursache, hoechstens MAX_SEVERE gleichzeitige schwere Stoerungen und eine ruhige Phase danach.
## Alle Folgen sind simulierte Spielereignisse – keine Aussagen ueber reale Vorfaelle in Mainz.

const MAX_SEVERE := 2
const QUIET_AFTER_SEVERE := 90.0      # Spielminuten ohne neue schwere Stoerung nach dem Ende einer schweren

## Wetterereignisse: Schwere, Abklingzeit, Hoechstdauer, Nachfrage-/Bedarfsfaktoren, Wirkung (Text), Quellen
const WEATHER_EVENTS := {
	"starkregen": {"sev": 2, "cool": 300.0, "dur": 480.0, "title": "Starkregen", "need": {"baustoffe": 1.3, "pakete": 1.15},
		"effects": ["Fahrten deutlich langsamer", "Verladen im Freien viel länger (überdachte Plätze helfen)", "mehr Bedarf an Abdichtmaterial und Ersatzlieferungen", "zeitweise Straßenprobleme möglich"],
		"end": "Starkregen lässt nach"},
	"sturm": {"sev": 2, "cool": 300.0, "dur": 480.0, "title": "Sturmböen", "need": {"baustoffe": 1.25},
		"effects": ["Außenarbeiten und Bau verzögert", "zusätzlicher Sicherungsbedarf", "Reparaturanfragen von Kunden"],
		"end": "Böen unter dem Schwellenwert"},
	"glaette": {"sev": 2, "cool": 360.0, "dur": 480.0, "title": "Glättegefahr", "need": {},
		"effects": ["Fahrten langsamer", "höheres Pannenrisiko, besonders ohne Wartung"], "end": "kein Frost mit Feuchtigkeit mehr"},
	"hitze": {"sev": 1, "cool": 240.0, "dur": 600.0, "title": "Hitze", "need": {"getraenke": 1.6, "lebensmittel": 1.2},
		"effects": ["mehr Getränkelieferungen", "höherer Kühlbedarf", "Fahrzeuge stärker belastet"], "end": "Temperatur sinkt unter den Schwellenwert"},
	"winter": {"sev": 1, "cool": 240.0, "dur": 600.0, "title": "Kälte/Winterwetter", "need": {"baustoffe": 1.2, "maschinenteile": 1.15},
		"effects": ["Wintermaterial und Wartung gefragt", "höheres Pannenrisiko ungewarteter Fahrzeuge"], "end": "Temperatur steigt über den Schwellenwert"},
	"nebel": {"sev": 1, "cool": 240.0, "dur": 360.0, "title": "Nebel", "need": {},
		"effects": ["vorsichtigere Fahrweise", "Lieferzeitprognosen unsicherer"], "end": "Nebel löst sich auf"},
}

var sim
var next_ok := {}                 # Ursache -> fruehester Beginn (Spielminute)
var quiet_until := 0.0
var _need := {}                   # Ware -> Bedarfsfaktor (aktive Ereignisse)
var _demand := {}                 # Ware -> Verguetungsfaktor (aktive Ereignisse)
var _boost := {}                  # Ware -> Ereignis-ID mit dem staerksten Bedarfsfaktor
var _active_keys := {}            # Schluessel (Typ[:Objekt]) -> Ereignis-ID


func setup(simulation) -> void:
	sim = simulation


# ------------------------------------------------------------------ Abfragen
func need_factor(cargo: String) -> float:
	return float(_need.get(cargo, 1.0))


func demand_factor(cargo: String) -> float:
	return float(_demand.get(cargo, 1.0))


func boost_cause(cargo: String) -> String:
	return str(_boost.get(cargo, ""))


func title_of(id: String) -> String:
	var e: Dictionary = sim.events.get_event(id)
	return "%s (%s)" % [e.text, id] if not e.is_empty() else id


func severe_active() -> int:
	return sim.events.events.filter(func(e): return e.status == "aktiv" and int(e.get("schwere", 0)) >= 2).size()


func _can(cause: String, severity: int, now: float) -> bool:
	if now < float(next_ok.get(cause, 0.0)):
		return false
	return severity < 2 or (severe_active() < MAX_SEVERE and now >= quiet_until)


func _active(key: String) -> bool:
	return _active_keys.has(key)


func _rebuild_cache() -> void:
	_need.clear()
	_demand.clear()
	_boost.clear()
	_active_keys.clear()
	for e in sim.events.events:
		if e.status != "aktiv" or not e.get("auto", false):
			continue
		_active_keys[str(e.get("key", e.typ))] = e.id
		for cargo in e.get("need", {}):
			if float(e.need[cargo]) > float(_need.get(cargo, 1.0)):
				_need[cargo] = float(e.need[cargo])
				_boost[cargo] = e.id
		for cargo in e.get("demand", {}):
			_demand[cargo] = maxf(float(_demand.get(cargo, 1.0)), float(e.demand[cargo]))


## Legt ein Ereignis an (genau einmal je Ursache) und vermerkt Abklingzeit und Quellen.
func _make(key: String, typ: String, cause: String, text: String, severity: int, duration: float, cooldown: float, o: Dictionary = {}) -> Dictionary:
	var e: Dictionary = sim.events.create(typ, cause, text, severity, duration, o)
	e["key"] = key
	next_ok[key.split(":")[0] if o.get("cool_by_type", true) else key] = sim.game_min + cooldown
	_rebuild_cache()
	return e


# ------------------------------------------------------------------ Takt
func minute_tick(now: float) -> void:
	_rebuild_cache()
	_weather(now)
	var m: int = sim.minute_index
	if m % 5 == 0:
		_workload(now)
		_market(now)
	if m % 15 == 0:
		_freight(now)
		_openings(now)
		_bulk(now)
	if m % 30 == 0:
		_shortage(now)


## Beendet-Pruefung fuer automatische Ereignisse (Dauer wird vom EventDirector geprueft).
func ended(e: Dictionary, now: float) -> bool:
	var key := str(e.get("ende_key", ""))
	var parts := key.split(":")
	match parts[0]:
		"wetter":
			return not _flag(parts[1])
		"fahrzeug":
			var v: FleetVehicle = sim.vehicles.get(int(parts[1]))
			return v == null or v.state != "broken"
		"bau":
			var f: Dictionary = sim.estate.facilities.get(parts[1], {})
			return f.is_empty() or f.status == "fertig" or sim.wx.build_factor() >= 1.0
		"auftrag":
			for kid in e.data.get("contracts", []):
				var k: Contract = sim.contracts.get(str(kid))
				if k != null and k.status not in ["delivered", "failed", "expired", "cancelled"]:
					return false
			return true
		"kunde":
			var p: Dictionary = sim.residents.people.get(parts[1], {})
			return p.is_empty() or p.state == "ruhig" or p.contract == ""
		"markt":
			return float(sim.market.saturation[int(parts[1])]) > 0.92
	return false


func on_end(e: Dictionary, now: float) -> void:
	if int(e.get("schwere", 0)) >= 2:
		quiet_until = now + QUIET_AFTER_SEVERE   # ruhigere Phase
	_rebuild_cache()


func _flag(flag: String) -> bool:
	var w: Weather = sim.wx
	match flag:
		"starkregen": return w.is_heavy_rain()
		"sturm": return w.is_strong_wind()
		"glaette": return w.is_icy()
		"hitze": return w.is_hot() and bool(w.cur.is_day)
		"winter": return (w.is_snow() or w.is_cold()) and not w.is_icy()
		"nebel": return w.is_fog()
	return false


# ------------------------------------------------------------------ Ursache: Wetter
func _weather(now: float) -> void:
	for flag in WEATHER_EVENTS:
		var spec: Dictionary = WEATHER_EVENTS[flag]
		if not _flag(flag) or _active(flag) or not _can(flag, int(spec.sev), now):
			continue
		var w: Weather = sim.wx
		var src := "%s, Modelldaten" % ("Wetterdienst" if w.cur.source == "open-meteo" else "simuliertes Ersatzwetter")
		var cond := "%s, %.0f °C, %.1f mm/h, Böen %.0f km/h" % [w.cur.text, float(w.cur.temp), float(w.cur.precip_mm_h), float(w.cur.gust)]
		var e := _make(flag, flag, "Wetter: " + cond, "%s in Mainz (simulierte Auswirkungen)" % spec.title, int(spec.sev), float(spec.dur),
			float(spec.cool), {"conditions": cond, "places": ["ganze Stadt"], "effects": spec.effects, "sources": [src, "Verkehrsmeldungen", "Auftragsmarkt"],
			"end": spec.end, "end_key": "wetter:" + flag, "need": spec.need, "demand": spec.need})
		if flag == "starkregen":
			_flooding(e, now)
		elif flag == "sturm":
			_storm_requests(e, now)


## Einmaliger Wurf bei Beginn: Starkregen kann eine Strasse zeitweise unpassierbar machen (hoechstens 3 Sperrungen gleichzeitig).
func _flooding(e: Dictionary, now: float) -> void:
	var closures: int = sim.traffic_events.filter(func(t): return t.kind in ["baustelle", "sperrung", "ueberflutung"]).size()
	if closures >= 3 or sim.rng.randf() > 0.6:
		return
	var p: Vector2i = sim._straight_road()
	if p.x < 0:
		return
	var cells: Array = sim.events._segment(p)
	if cells.is_empty():
		return
	var until: float = now + sim.rng.randf_range(60.0, 120.0)
	for c in cells:
		sim.nav.add_roadwork(c, until)
	var where: String = Catalog.DISTRICTS[sim.city.district_of(cells[0])]
	var txt := "Überflutete Straße im %s (%d Abschnitte) bis %s" % [where, cells.size(), Catalog.game_minutes_to_text(until)]
	sim.traffic_events.append({"kind": "ueberflutung", "cells": cells, "until": until, "text": txt})
	e.orte.append(where)
	e.wirkung.append(txt)
	e.data["flooded"] = cells.size()
	sim.log_event("Verkehr: " + txt, "warn")


## Sturm: zwei Kunden melden Schaeden und fragen Reparaturmaterial an.
func _storm_requests(e: Dictionary, now: float) -> void:
	var made := 0
	for p in sim.residents.people.values():
		if made >= 2:
			break
		var b: Dictionary = sim.city.building(p.building)
		if b.type in ["house", "semi", "villa", "shop"] and p.contract == "" and now >= float(p.cooldown_until) and sim.rng.randf() < 0.05:
			var k: Contract = sim.residents.request(p, now, -1, e.id, "", {"cargo": "baustoffe", "q": [4, 9],
				"concern": "meldet Sturmschäden und braucht Reparaturmaterial"})
			if k:
				made += 1
				e.data["contracts"] = e.data.get("contracts", []) + [k.id]
	if made > 0:
		e.wirkung.append("%d Kunden melden Sturmschäden (Reparaturaufträge)" % made)


# ------------------------------------------------------------------ Ursache: Fahrzeug, Bau, Personal, Markt, Kunden
func note_breakdown(v: FleetVehicle, reason: String) -> void:
	var key := "panne:%d" % v.id
	if _active(key):
		return
	var cause := "Wartungsrückstand (Fahrzeugzustand %d %%)" % int(v.condition) if v.condition < 60.0 else "Verschleiß im Betrieb"
	if sim.wx.is_cold() or sim.wx.is_hot() or sim.wx.is_icy():
		cause += " bei Extremwetter (%s)" % sim.wx.cur.text
	if reason == "sabotiert":
		cause = "Sabotage"
	var e := _make(key, "fahrzeugausfall", cause, "%s ausgefallen" % v.display_name(), 1, 150.0, 0.0,
		{"conditions": cause, "places": [Catalog.DISTRICTS[sim.city.district_of(v.tile())]], "effects": ["Fahrzeug steht, Auftrag verzögert", "Mechaniker oder Abschleppdienst nötig"],
		"sources": ["Fahrzeugmeldung an die Disposition"], "end": "Fahrzeug repariert oder abgeschleppt", "end_key": "fahrzeug:%d" % v.id,
		"data": {"company": v.owner, "vehicle_id": v.id}, "cool_by_type": false})
	e["company"] = v.owner


func note_construction_delay(f: Dictionary) -> void:
	var key := "bau:%s" % f.id
	if _active(key):
		return
	var w: Weather = sim.wx
	var cause := "Wetter: %s (Bautempo ×%.1f)" % [w.cur.text, w.build_factor()]
	var e := _make(key, "baustelle_verzoegert", cause, "Baustelle verzögert: %s" % Estate.FACILITIES[f.typ].name, 1, 480.0, 0.0,
		{"conditions": cause, "places": ["Betriebshof von %s" % sim.company(int(f.owner)).company_name],
		"effects": ["Bauzeit verlängert sich"], "sources": ["Bauleitung"], "end": "Wetter erlaubt wieder normales Arbeiten",
		"end_key": "bau:%s" % f.id, "data": {"company": int(f.owner), "facility": f.id}, "cool_by_type": false})
	e["company"] = int(f.owner)


func note_customer_disappointed(p: Dictionary, k: Contract, why: String) -> void:
	if k == null or k.owner < 0:
		return   # nie angenommene Anfragen sind kein Ereignis: die Stimmung sinkt, mehr nicht
	var by := " (Auftrag %s von %s)" % [k.id, sim.company(k.owner).company_name]
	var b: Dictionary = sim.city.building(p.building)
	var e := _make("kunde:%s" % p.id, "kunde_enttaeuscht", why + by, "%s (%s, %s) ist enttäuscht" % [p.name, p.role, b.name], 1, 240.0, 0.0,
		{"conditions": why + by, "places": [b.name], "effects": ["Stimmung der Kundin/des Kunden sinkt", "Nächste Anfrage wird dringlicher und besser bezahlt"],
		"sources": ["Kundenanruf"], "end": "Kunde stellt eine neue Anfrage oder beruhigt sich", "end_key": "kunde:%s" % p.id, "cool_by_type": false})
	if k != null and k.owner >= 0:
		e["company"] = k.owner


func note_tenant(l: Dictionary, what: String, k: Contract) -> void:
	var e := _make("miete:%s:%s" % [l.id, what], "bueroeinzug" if what.contains("Einzug") else "mieterbedarf", "Mietvertrag %s: %s" % [l.id, what],
		"%s: %s" % [l.tenant, what], 1, 480.0, 0.0, {"conditions": "Mieter %s in Büro von %s" % [l.tenant, sim.company(int(l.owner)).company_name],
		"places": [sim.city.building(k.dropoff).name], "effects": ["Neuer Transportauftrag %s (%s)" % [k.id, k.cargo_name()]],
		"sources": ["Auftragsmarkt"], "end": "Auftrag erledigt", "end_key": "auftrag:", "data": {"contracts": [k.id]}, "cool_by_type": false})
	e["ende_key"] = "auftrag:"
	k.cause = e.id


## Fahrer-Engpass: erschoepfte Fahrer ruhen sich aus (nur Untaetige), solange es mehrere gibt.
func _workload(now: float) -> void:
	for c in sim.companies:
		var drivers: Array = sim.personnel.workers.values().filter(func(w): return w.employer == c.id and not w.lost and w.role == "worker" and int(w.skills.get("fahren", 0)) > 0)
		var tired: Array = drivers.filter(func(w): return w.fatigue >= 80.0)
		var key := "fahrerengpass:%d" % c.id
		if drivers.size() < 2 or tired.size() < 2 or float(tired.size()) / drivers.size() < 0.6 or _active(key) or not _can(key, 1, now):
			continue
		var resting: Array = []
		for w in tired:
			if sim.personnel.can_take(w, "fahren") == "" or w.fatigue >= 90.0:
				w.rest_until = now + 45.0
				resting.append(w.name)
		if resting.is_empty():
			continue
		var cause := "Personalbelastung: %d von %d Fahrern über 80 %% Erschöpfung" % [tired.size(), drivers.size()]
		var e := _make(key, "fahrerengpass", cause, "Fahrerengpass bei %s" % c.company_name, 1, 45.0, 240.0,
			{"conditions": cause, "places": ["Betriebshof von %s" % c.company_name], "effects": ["%s erhalten bis %s keine neuen Aufgaben (Pause)" % [", ".join(resting), Catalog.game_minutes_to_text(now + 45.0)]],
			"sources": ["Personalmeldung"], "end": "Pause beendet", "data": {"company": c.id}, "cool_by_type": false})
		e["company"] = c.id


## Angebot und Nachfrage: viele Annahmen in einem Viertel druecken die Preise.
func _market(now: float) -> void:
	for d in sim.market.saturation.size():
		var key := "preisverfall:%d" % d
		if float(sim.market.saturation[d]) < 0.82 and not _active(key) and _can(key, 1, now):
			var cause := "viele Auftragsannahmen im %s (Sättigung %d %%)" % [Catalog.DISTRICTS[d], int(float(sim.market.saturation[d]) * 100.0)]
			_make(key, "preisverfall", cause, "Preisverfall im %s" % Catalog.DISTRICTS[d], 1, 600.0, 360.0,
				{"conditions": cause, "places": [Catalog.DISTRICTS[d]], "effects": ["Vergütungen aus diesem Viertel sinken, bis sich der Markt erholt"],
				"sources": ["Auftragsmarkt (Preise)"], "end": "Sättigung erholt sich", "end_key": "markt:%d" % d, "cool_by_type": false})


## Lagerbestaende der Kunden: sind viele fast leer, steigt die Verguetung dieser Ware.
func _shortage(now: float) -> void:
	var counts := {}
	for p in sim.residents.people.values():
		if p.contract == "" and float(p.pressure) >= 0.85 and p.need >= 0:
			var b: Dictionary = sim.city.building(p.building)
			var cargo: String = Residents.PROFILES[Residents.prof(b.type)].needs[p.need].cargo
			counts[cargo] = int(counts.get(cargo, 0)) + 1
	var top := ""
	for cargo in counts:
		if top == "" or counts[cargo] > counts[top]:
			top = cargo
	if top == "" or counts[top] < 25 or _active("nachfrageschub") or not _can("nachfrageschub", 1, now):
		return
	var cause := "Lagerbestände von %d Kunden fast leer (%s)" % [counts[top], Catalog.CARGO[top].name]
	_make("nachfrageschub", "nachfrageschub", cause, "Nachfrageschub: %s" % Catalog.CARGO[top].name, 1, 240.0, 720.0,
		{"conditions": cause, "places": ["ganze Stadt"], "effects": ["Vergütung für %s ×1,3" % Catalog.CARGO[top].name],
		"sources": ["Auftragsmarkt (Preise)"], "end": "Dauer abgelaufen", "demand": {top: 1.3}})


# ------------------------------------------------------------------ Ursache: Handel (Frachtterminal, Eroeffnung, Grossauftrag)
func _freight(now: float) -> void:
	if now < 240.0 or _active("fracht") or not _can("fracht", 1, now):
		return
	var terms: Array = sim.city.buildings.filter(func(b): return b.type in ["airport_cargo", "freight_shed", "port_office"] and not b.out.is_empty())
	if terms.is_empty() or sim.rng.randf() > 0.5:
		return
	var t: Dictionary = terms[sim.rng.randi() % terms.size()]
	var ids: Array = []
	var e := _make("fracht", "fracht", "Fracht eingetroffen: Terminal hat mehr Ware als Abnehmer", "Zusätzliche Warenlieferung am %s" % t.name, 1, 600.0, 480.0,
		{"conditions": "Frachteingang am Terminal übersteigt die Abholungen", "places": [t.name], "effects": [], "sources": ["Auftragsmarkt (Jobbörse)", "Terminal-Aushang"],
		"end": "alle Sendungen abgeholt oder verfallen", "end_key": "auftrag:"})
	e["ende_key"] = "auftrag:"
	for i in 3:
		var cargo: String = t.out[sim.rng.randi() % t.out.size()]
		var dst: int = sim.market._pick_dest(t.id, sim.market.receivers.get(cargo, []), sim.rng.randf_range(40.0, 120.0))
		if dst < 0:
			continue
		var k: Contract = sim.market.build_contract(t.id, dst, cargo, "", 3, 12, now)
		if k:
			k.cause = e.id
			k.reward = roundf(k.reward * 1.15 / 10.0) * 10.0
			ids.append(k.id)
	e.data["contracts"] = ids
	e.wirkung.append("%d zusätzliche Sendungen ausgehängt" % ids.size())
	e.text = "Zusätzliche Warenlieferung am %s: %d Sendungen warten auf Weitertransport" % [t.name, ids.size()]


## Neues Geschaeft: eroeffnet an einem freien Platz, Kunde stellt sofort einen Eroeffnungsbedarf.
func _openings(now: float) -> void:
	if now < 480.0 or _active("eroeffnung") or not _can("eroeffnung", 1, now) or sim.rng.randf() > 0.4:
		return
	var c: CityData = sim.city
	var r := Rect2i()
	var found := false
	for i in 400:
		r = Rect2i(sim.rng.randi_range(6, c.size - 12), sim.rng.randi_range(6, c.size - 12), 2, 2)
		if c.district_of(r.position) in [0, 1, 4] and sim.events._free(r):
			found = true
			break
	if not found:
		return
	var name: String = "Neueröffnung %s" % ["Feinkost", "Blumenhaus", "Fahrradladen", "Kiosk", "Bioladen"][sim.rng.randi() % 5]
	var b: Dictionary = sim.events._add_building("shop", r, name)
	if b.is_empty():
		return
	sim.market.refresh()
	sim.residents.add_for_buildings([b.id])
	sim.events.buildings_added.emit([b.id])
	var p: Dictionary = {}
	for q in sim.residents.people.values():
		if q.building == b.id:
			p = q
	var e := _make("eroeffnung", "eroeffnung", "Nachfrage im Viertel: neues Geschäft eröffnet", "%s eröffnet im %s" % [name, Catalog.DISTRICTS[b.district]], 1, 600.0, 900.0,
		{"conditions": "freie Fläche an der Straße, Nachfrage im Viertel", "places": [name], "effects": ["neuer Kunde mit Eröffnungsbedarf"],
		"sources": ["Auftragsmarkt"], "end": "Eröffnungsbedarf geliefert", "end_key": "auftrag:", "cool_by_type": false})
	e["ende_key"] = "auftrag:"
	if not p.is_empty():
		var k: Contract = sim.residents.request(p, now, -1, e.id, "", {"cargo": "pakete", "q": [6, 12], "concern": "eröffnet gerade und braucht die Erstausstattung"})
		if k:
			e.data["contracts"] = [k.id]


## Grossauftrag: Baustelle oder Fabrik mit fast leerem Lager braucht kurzfristig viel Material.
func _bulk(now: float) -> void:
	if now < 300.0 or _active("grossauftrag") or not _can("grossauftrag", 1, now):
		return
	for p in sim.residents.people.values():
		var b: Dictionary = sim.city.building(p.building)
		if b.type in ["construction", "factory"] and p.contract == "" and float(p.pressure) >= 0.9 and now >= float(p.cooldown_until):
			var e := _make("grossauftrag", "grossauftrag", "Lagerbestand von %s fast leer, Projekt unter Zeitdruck" % b.name, "Großauftrag von %s" % b.name, 1, 480.0, 720.0,
				{"conditions": "Lager von %s unter 10 %%, Projekt unter Zeitdruck" % b.name, "places": [b.name], "effects": ["Großauftrag mit Schwerlastfahrzeug, ×2 Vergütung"],
				"sources": ["Auftragsmarkt (Jobbörse)"], "end": "Auftrag erledigt oder abgelaufen", "end_key": "auftrag:", "demand": {}})
			e["ende_key"] = "auftrag:"
			var k: Contract = sim.residents.request(p, now, -1, e.id, "", {"cargo": "baustoffe", "q": [60, 80],
				"concern": "hat kurzfristig ein Großprojekt und braucht eine große Materiallieferung"})
			if k:
				k.needs_heavy = true
				k.size_class = "groß"
				k.reward = roundf(k.reward * 2.2 / 10.0) * 10.0
				k.deadline = now + 720.0
				k.offer_until = now + 240.0
				e.data["contracts"] = [k.id]
			else:
				e.status = "beendet"
			return


func to_dict() -> Dictionary:
	return {"next_ok": next_ok, "quiet_until": quiet_until}


func from_dict(d: Dictionary) -> void:
	next_ok = d.get("next_ok", {})
	quiet_until = float(d.get("quiet_until", 0.0))
