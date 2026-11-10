class_name ServicePlanner
extends RefCounted
## Entscheidungen der Buergermeister ueber die kommunalen Dienste (Auftrag 20, Etappe 11, docs/PUBLIC_SERVICES.md).
##  - Bedarfsanalyse je Stadt aus den Fachsystemen: Kinder ohne Schul-/Kitaplatz, Hilfsfrist, ausgebrannte oder wartende Braende,
##    Anbindung (Bus), Deponiefuellstand (Recycling), Einrichtungen ohne Personal.
##  - Massnahmen: Neubau (build: Bauplatz der Stadtentwicklung, Ratsbeschluss, Ausschreibung, Baufirma und Bautrupp bauen sichtbar;
##    bei der Abnahme entsteht die Einrichtung mit eigenem Bild), Fahrzeugkauf (buy_vehicle: Kaufpreis an den Haendler S0),
##    Schliessung (close: Personal frei, keine Kosten mehr). Baukosten skalieren mit der Ortsgroesse wie die Sachkosten.
##  - Alle 5 Tage entscheidet das Bauamt nach Regeln ueber die Grundversorgung (hoechstens eine Massnahme je Stadt); KI-Buergermeister
##    handeln zusaetzlich ueber ihre Aktionen kommunal_bauen, kommunal_fahrzeug, kommunal_schliessen und regionalrat_antrag. Jede Entscheidung steht mit Begruendung im Protokoll.

const EVERY := 5
const BUILD_DAYS := {"FW-01": 20, "RW-01": 14, "KH-01": 40, "BH-01": 14, "VB-01": 16, "SC-01": 30, "KI-01": 16, "RC-01": 14}
const IDLE_CLOSE_DAYS := 30
const RESERVE_DAYS := 60            # Ruecklage fuer den laufenden Dienstbetrieb vor einem Neubau

var sim
var builds := {}          # Projekt-ID -> {town, code, rect, parcel, reason, by, day}
var log: Array = []       # [{day, town, text, by}]
var auto := true          # Regel-Buergermeister entscheiden selbst
var saving := {}          # Stadt -> Monat der letzten Spar-Meldung
var _day := -1


func setup(simulation) -> void:
	sim = simulation
	if sim.municipal != null and sim.municipal.enabled():
		sim.day_changed.connect(on_day)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _note(k: int, text: String, by: String) -> void:
	log.append({"day": _today(), "town": k, "text": text, "by": by})
	if log.size() > 200:
		log.pop_front()
	sim.log_event("%s: %s" % [sim.towns.name_of(k), text], "info")


func build_cost(code: String, k: int) -> float:
	var t: Dictionary = Municipal.TYPES[code]
	var pop: int = sim.municipal.served(code, k)
	return snappedf(float(t.cost) * (0.08 + 0.92 * minf(1.0, float(pop) / Municipal.REF_POP)), 100.0)   # Dorfschule statt Stadtschule: kleine Orte bauen kleiner


# ------------------------------------------------------------------ Bedarf
func needs(k: int) -> Array:
	var out: Array = []
	var M: Municipal = sim.municipal
	var has := func(code: String) -> bool: return M.of_town(k).any(func(f): return f.code == code and f.status == "in_betrieb") or _planned(k, code)
	var es: Dictionary = sim.education.summary(k)
	if int(es.ohne_schulplatz) > 0 and not has.call("SC-01"):
		out.append({"massnahme": "bauen", "typ": "SC-01", "grund": "%d Schulkinder ohne Schulplatz" % int(es.ohne_schulplatz), "prio": 1})
	if int(es.ohne_kitaplatz) >= 3 and not has.call("KI-01"):
		out.append({"massnahme": "bauen", "typ": "KI-01", "grund": "%d Kinder ohne Kitaplatz" % int(es.ohne_kitaplatz), "prio": 2})
	var rs: Dictionary = sim.rescue.summary(k)
	if int(rs.notfaelle) >= 3 and float(rs.hilfsfrist_eingehalten_anteil) < 0.5:
		var rw: Array = M.of_town(k, "rettung").filter(func(f): return f.code == "RW-01")
		if not rw.is_empty() and rw[0].vehicles.filter(func(v): return str(M.vehicles[v].type) == "RTW").size() < 2:
			out.append({"massnahme": "fahrzeug", "einrichtung": rw[0].id, "fahrzeug": "RTW", "grund": "Hilfsfrist nur in %d %% eingehalten" % roundi(float(rs.hilfsfrist_eingehalten_anteil) * 100.0), "prio": 1})
	var burnt: int = sim.fire.fires.values().filter(func(f): return int(f.town) == k and f.status == "ausgebrannt" and _today() - GameCalendar.day_of(float(f.start)) <= 30).size()
	if burnt > 0:
		var fw: Array = M.of_town(k, "feuerwehr")
		if not fw.is_empty() and fw[0].vehicles.filter(func(v): return str(M.vehicles[v].type) == "HLF 20").size() < 2:
			out.append({"massnahme": "fahrzeug", "einrichtung": fw[0].id, "fahrzeug": "HLF 20", "grund": "%d Gebäude in 30 Tagen ausgebrannt" % burnt, "prio": 1})
	if sim.citizens.population_of(k) >= 60 and not has.call("VB-01"):
		out.append({"massnahme": "bauen", "typ": "VB-01", "grund": "keine Busanbindung bei %d Einwohnern" % sim.citizens.population_of(k), "prio": 3})
	if sim.waste.fill_share() >= 0.5 and not M.facilities.values().any(func(f): return f.code == "RC-01") and not _planned(-1, "RC-01"):
		out.append({"massnahme": "bauen", "typ": "RC-01", "grund": "Deponie zu %d %% gefüllt" % roundi(sim.waste.fill_share() * 100.0), "prio": 2})
	for f in M.of_town(k):
		if f.status == "in_betrieb" and M.staff_count(f.id) == 0 and M.volunteers_of(f.id).is_empty() and _today() - int(f.opened) >= IDLE_CLOSE_DAYS \
				and f.code not in Municipal.START_KIT and f.code != "KH-01":
			out.append({"massnahme": "schliessen", "einrichtung": f.id, "grund": "%s seit %d Tagen ohne Personal" % [f.name, _today() - int(f.opened)], "prio": 3})
	out.sort_custom(func(a, b): return int(a.prio) < int(b.prio))
	return out


func _planned(k: int, code: String) -> bool:
	return builds.values().any(func(b): return str(b.code) == code and (k < 0 or int(b.town) == k))


# ------------------------------------------------------------------ Massnahmen
func build(k: int, code: String, reason: String, by: String) -> Dictionary:
	if not Municipal.TYPES.has(code):
		return {"ok": false, "msg": "Unbekannter Typ %s (%s)." % [code, ", ".join(Municipal.TYPES.keys())]}
	if _planned(k, code):
		return {"ok": false, "msg": "%s ist in %s schon geplant." % [Municipal.TYPES[code].label, sim.towns.name_of(k)]}
	var M: Mayor = sim.towns.mayor(k)
	var cost := build_cost(code, k)
	var reserve: float = RESERVE_DAYS * sim.municipal.daily_cost(k)   # laufende Dienste muessen bezahlbar bleiben
	if M.available_budget() < cost + reserve:
		return {"ok": false, "budget": true, "msg": "Verfügbare Mittel %s reichen nicht für %s (%s) plus Rücklage für %d Tage Dienstbetrieb (%s)." % [
			Catalog.money(M.available_budget()), Municipal.TYPES[code].label, Catalog.money(cost), RESERVE_DAYS, Catalog.money(reserve)]}
	var info: Array = CityGenerator.TYPES[Municipal.TYPES[code].building]
	var site: Dictionary = sim.civic._find_site(k, int(info[1]), int(info[2]))
	if site.is_empty():
		return {"ok": false, "msg": "Kein freies städtisches Grundstück für %s (%d×%d Felder)." % [Municipal.TYPES[code].label, int(info[1]), int(info[2])]}
	var vote: Dictionary = M.civic_vote("oeffentlich_bau", cost)
	if not vote.passed:
		_note(k, "Der Rat lehnt %s ab (%s)." % [Municipal.TYPES[code].label, str(vote.text)], by)
		return {"ok": false, "msg": "Rat lehnt ab: %s" % str(vote.text)}
	var prj: Dictionary = M.add_civic_project("DIENST", [site.parcel], cost, int(BUILD_DAYS.get(code, 20)), {}, "%s: %s" % [Municipal.TYPES[code].label, reason])
	prj.kind = "dienst"
	prj["dienst"] = code
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": _today() - 1, "bids": [], "by": by}
	var p: Dictionary = sim.parcels.parcel(str(site.parcel))
	p.state = "im_bau"
	p.use = "dienst"
	p.project = prj.id
	sim.parcels.touch(str(site.parcel))
	builds[prj.id] = {"town": k, "code": code, "rect": site.rect, "parcel": site.parcel, "reason": reason, "by": by, "day": _today()}
	_note(k, "beschließt Neubau %s (%s, %s); Ausschreibung läuft." % [Municipal.TYPES[code].label, reason, Catalog.money(cost)], by)
	return {"ok": true, "msg": "Neubau %s beschlossen und ausgeschrieben (Projekt %s, %s)." % [Municipal.TYPES[code].label, prj.id, Catalog.money(cost)], "ref": prj.id}


## Abnahme durch die Baufirma (Construction._finish_public): Gebaeude errichten und Einrichtung in Betrieb nehmen.
func on_finished(prj: Dictionary) -> void:
	var b: Dictionary = builds.get(str(prj.id), {})
	if b.is_empty():
		return
	builds.erase(str(prj.id))
	var k := int(b.town)
	var code := str(b.code)
	var r := Rect2i(int(b.rect[0]), int(b.rect[1]), int(b.rect[2]), int(b.rect[3]))
	var bt: String = Municipal.TYPES[code].building
	var bld: Dictionary = sim.events._add_building(bt, r, Municipal.TYPES[code].label)
	var p: Dictionary = sim.parcels.parcel(str(b.parcel))
	if bld.is_empty():
		_note(k, "Abnahme %s: Bauplatz nicht mehr frei – Gebäude konnte nicht errichtet werden." % Municipal.TYPES[code].label, "Bauamt")
		if not p.is_empty():
			p.state = "frei"
		return
	if not p.is_empty():
		p.state = "bebaut"
		p.building = int(bld.id)
		sim.parcels.touch(str(b.parcel))
	var f: Dictionary = sim.municipal.register(k, code, int(bld.id))
	sim.events.buildings_added.emit([bld.id])
	if code == "VB-01":
		sim.transit.plan_line(f.id)
	_note(k, "eröffnet %s." % f.name, "Bauamt")


func buy_vehicle(fid: String, vtype: String, reason: String, by: String) -> Dictionary:
	var M: Municipal = sim.municipal
	var f: Dictionary = M.facilities.get(fid, {})
	if f.is_empty() or not Municipal.VEHICLES.has(vtype):
		return {"ok": false, "msg": "Unbekannte Einrichtung oder Fahrzeugtyp (%s)." % ", ".join(Municipal.VEHICLES.keys())}
	var k := int(f.town)
	var price := float(Municipal.VEHICLES[vtype].price)
	if sim.towns.mayor(k).available_budget() < price:
		return {"ok": false, "msg": "Verfügbare Mittel reichen nicht für %s (%s)." % [vtype, Catalog.money(price)]}
	sim.economy.transfer(Towns.account_of(k), "S0", price)
	var v := M.add_vehicle(fid, vtype)
	_note(k, "kauft %s (%s, %s)." % [v.label, reason, Catalog.money(price)], by)
	return {"ok": true, "msg": "%s gekauft (%s)." % [v.label, Catalog.money(price)]}


func close(fid: String, reason: String, by: String) -> Dictionary:
	var M: Municipal = sim.municipal
	var f: Dictionary = M.facilities.get(fid, {})
	if f.is_empty() or f.status != "in_betrieb":
		return {"ok": false, "msg": "Einrichtung %s ist nicht in Betrieb." % fid}
	f.status = "geschlossen"
	for p in M.staff_of(fid):
		p.employer = ""
		p.wage = 0.0
		p.erase("dienst")
		p.erase("beruf")
	for vid in f.vehicles:
		M.vehicles[vid].status = "ausser_dienst"
	_note(int(f.town), "schließt %s (%s)." % [f.name, reason], by)
	return {"ok": true, "msg": "%s geschlossen." % f.name}


# ------------------------------------------------------------------ Regel-Buergermeister
func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	if not auto or day % EVERY != 0:
		return
	for t in sim.towns.list:
		var k := int(t.id)   # Grundversorgung nach Regeln fuer jede Stadt; KI-Buergermeister koennen zusaetzlich ueber ihre Aktionen handeln
		for n in needs(k):
			var r := act(k, n, "Bürgermeister %s (Regeln)" % sim.towns.mayor(k).name)
			if r.get("ok", false):
				break
			if r.get("budget", false) and int(n.prio) == 1:
				if int(saving.get(k, -1)) != day / 30:
					saving[k] = day / 30
					_note(k, "spart für %s (%s): %s" % [Municipal.TYPES.get(str(n.get("typ", "")), {}).get("label", n.massnahme), n.grund, r.msg], "Bürgermeister %s (Regeln)" % sim.towns.mayor(k).name)
				break   # dringendster Bedarf noch nicht bezahlbar: sparen statt Geld fuer Nachrangiges ausgeben


func act(k: int, n: Dictionary, by: String) -> Dictionary:
	match str(n.massnahme):
		"bauen":
			return build(k, str(n.typ), str(n.grund), by)
		"fahrzeug":
			return buy_vehicle(str(n.einrichtung), str(n.fahrzeug), str(n.grund), by)
		"schliessen":
			return close(str(n.einrichtung), str(n.grund), by)
	return {"ok": false, "msg": "unbekannte Maßnahme"}


# ------------------------------------------------------------------ Lagebericht fuer die KI, Uebersicht, Speichern
func mayor_obs(k: int) -> Dictionary:
	return {"einrichtungen": sim.municipal.summary(k), "bedarf": needs(k), "feuerwehr": sim.fire.summary(k), "rettungsdienst": sim.rescue.summary(k),
		"winterdienst": sim.winter.summary(k), "bus": sim.transit.summary(k), "bildung": sim.education.summary(k), "recycling": sim.recycling.summary(k),
		"neubauten_geplant": builds.values().filter(func(b): return int(b.town) == k).map(func(b): return "%s (%s)" % [Municipal.TYPES[b.code].label, b.reason]),
		"baukosten": Municipal.TYPES.keys().map(func(c): return "%s %s: %s" % [c, Municipal.TYPES[c].label, Catalog.money(build_cost(c, k))]),
		"regionalrat": sim.council.summary() if sim.council != null else {}}


func to_dict() -> Dictionary:
	return {"builds": builds.duplicate(true), "log": log.duplicate(true), "day": _day}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	builds = d.get("builds", {})
	log = d.get("log", [])
	_day = int(d.get("day", -1))
	for b in builds.values():
		b.town = int(b.town)
