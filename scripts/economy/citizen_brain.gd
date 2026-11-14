class_name CitizenBrain
extends RefCounted
## Buerger-KI (Auftrag 23, Phase 4, docs/LIVING_WORLD.md): jeder Buerger plant seinen Tag selbst aus seinem echten Zustand.
##
## Grundlage sind die vorhandenen Daten (Wohnung, Arbeitgeber, Lohn, Weiterbildung, Alter) und die Welt (Wochentag, Wetter,
## Oeffnungszeiten, Gebaeude im eigenen Ort). Daraus entsteht ein Tagesplan aus Abschnitten [von, bis, Taetigkeit]:
##  - Arbeit in Schichten nach Arbeitgeber (Handel spaeter, Industrie frueh, Polizei/Pflege im Wechsel, Wochenende frei ausser Handel
##    am Samstag und Schichtdiensten), Mittagspause fuer Buerojobs, gelegentlich ein Arzttermin statt des Arbeitsbeginns.
##  - Arbeitslose gehen vormittags zur Arbeitsvermittlung, Teilnehmer einer Weiterbildung zur Schule.
##  - Besorgungen nach der Arbeit bzw. am Samstagvormittag (nur offene Laeden), abends Gastronomie (eher freitags und samstags, nur mit
##    Einkommen), Spaziergaenge am Markt oder Hafen (nicht bei Regen), sonntags Ausflug, bei Hitze an den Hafen.
## Ziele liegen im eigenen Ort und sind die naechstgelegenen offenen Gebaeude (drei Naechste im Wechsel, damit sich die Leute verteilen).
## Findet ein Wunsch kein offenes Ziel im Ort, zaehlt er als unversorgt (Signal an den Buergermeister); die Person bleibt zu Hause.
## Die Plaene sind je Person und Tag stabil (Zufall aus Citizens.roll), werden je Tag einmal berechnet und erzeugen keine Buchungen.

const KINDS := {
	"home": "Zu Hause", "sleep": "Schläft", "work": "Zur Arbeit", "lunch": "Mittagspause", "course": "Zur Weiterbildung",
	"jobs": "Zur Arbeitsvermittlung", "shopping": "Einkaufen für den Haushalt", "doctor": "Arzttermin",
	"restaurant": "Restaurantbesuch nach der Arbeit", "walk": "Spaziergang", "harbor": "Ausflug an den Hafen",
	"krank": "Krankgemeldet (erschöpft)", "beschwerde": "Beschwerde im Rathaus", "jobsuche": "Sucht eine neue Stelle",
}
## Schichtbeginn (frueheste, spaeteste Stunde) und Dauer je Arbeitgeber; "wechsel": Frueh-, Spaet- und Nachtschicht im Wechsel.
const SHIFTS := {
	"rathaus": [7.5, 9.0, 8.0], "schule_klinik": [7.0, 8.0, 8.0], "gesundheit": [7.0, 9.0, 8.0, "wechsel"], "polizei": [6.0, 6.0, 8.0, "wechsel"],
	"baufirma": [6.5, 7.5, 8.5], "handel": [8.0, 10.0, 8.0, "samstag"], "industrie": [6.0, 7.5, 8.0], "stadtlager": [6.0, 8.0, 8.0],
	"hafen": [6.0, 8.0, 8.0], "kommunal": [6.0, 7.5, 8.0, "wechsel"],
}
const OFFICE_JOBS := ["rathaus", "schule_klinik", "gesundheit"]
const PLACE_TYPES := {
	"shopping": ["shop", "supermarket", "bakery", "butcher", "pharmacy"],
	"lunch": ["bakery", "restaurant", "cafe", "shop"],
	"restaurant": ["restaurant", "cafe", "kneipe", "hotel", "strandbar"],
	"doctor": ["doctor", "clinic"],
	"school": ["school"],
	"walk": ["fountain", "townhall"],
	"harbor": ["port_office"],
	"beschwerde": ["townhall"],
	"jobsuche": ["job_board", "staffing"],
}
## Oeffnungszeiten fuer Typen ohne Profil in Residents.PROFILES
const DEFAULT_HOURS := [7.0, 22.0]

var sim
var _plans := {}            # Personen-ID -> [Tag, Plan]
var _cands := {}            # "art|ort" -> [Gebaeude-IDs]
var _cand_rev := -1


func _init(simulation) -> void:
	sim = simulation


## Tagesplan einer Person: [[von, bis, art], ...]; spaetere Abschnitte gehen frueheren vor (Arzttermin, Mittagspause).
func day_plan(p: Dictionary, day: int) -> Array:
	var id := int(p.id)
	var cached: Array = _plans.get(id, [])
	if not cached.is_empty() and int(cached[0]) == day and str(cached[2]) == _state_key(p):
		return cached[1]
	var plan := _make_plan(p, day)
	_plans[id] = [day, plan, _state_key(p)]
	return plan


func _state_key(p: Dictionary) -> String:
	var g: Dictionary = p.get("gemuet", {})
	return "%s|%s|%d|%d" % [str(p.get("employer", "")), str(p.get("home", "")), int(p.has("course_until")), int(g.get("stand", 0))]


func _make_plan(p: Dictionary, day: int) -> Array:
	var id := int(p.id)
	var wd := posmod(day, 7)   # 0 = Montag
	var weekend := wd >= 5
	var r := func(k: int) -> float: return Citizens.roll(id, day, 900 + k)
	var me := func(k: int) -> float: return Citizens.roll(id, 0, 950 + k)   # persoenliche Gewohnheit, jeden Tag gleich
	var out: Array = []
	var employer := str(p.get("employer", ""))
	var free_from := 9.5   # ab wann Besorgungen moeglich sind
	var g: Dictionary = p.get("gemuet", {})
	var energy := float(g.get("energie", 80.0))
	var frust := float(g.get("frust", 20.0))
	var anger := float(g.get("aerger", 0.0))
	if employer != "" and energy < SICK_BELOW:
		var sh0 := _shift(employer, id, day, wd, me)
		if not sh0.is_empty():
			return [[0.0, 24.0, "krank"]]   # erschoepft: meldet sich krank und bleibt zu Hause
	if employer != "":
		var sh := _shift(employer, id, day, wd, me)
		if not sh.is_empty():
			out.append([sh[0], sh[1], "work"])
			free_from = float(sh[1])
			if employer in OFFICE_JOBS and sh[0] < 11.5 and sh[1] > 13.5 and r.call(1) < 0.4:
				out.append([12.0, 12.75, "lunch"])
	elif p.has("course_until"):
		if not weekend:
			out.append([8.0, 14.5, "course"])
			free_from = 14.5
	elif not weekend and r.call(2) < 0.6:
		var s: float = 8.5 + 1.5 * r.call(3)
		out.append([s, s + 1.25, "jobs"])
		free_from = s + 1.5
	if (wd == 5 and r.call(4) < 0.7) or (not weekend and r.call(4) < 0.35):
		var s2: float = 9.5 + 1.5 * r.call(5) if wd == 5 or out.is_empty() else minf(free_from + 0.25, 19.0)
		out.append([s2, s2 + 0.75 + 0.5 * r.call(6), "shopping"])
	if r.call(7) < (0.025 if energy > 30.0 else 0.12) and not weekend:
		out.append([8.0 + r.call(8), 9.25 + r.call(8), "doctor"])
	if employer != "" and frust > QUIT_FRUST and not weekend and r.call(15) < 0.5:   # unzufrieden: sucht nach der Arbeit eine neue Stelle
		var s5: float = minf(free_from + 0.25, 17.0)
		out.append([s5, s5 + 0.75, "jobsuche"])
	if anger > ANGRY_ABOVE and wd < 5 and r.call(16) < 0.4:   # veraergert: Beschwerde im Rathaus
		var s6: float = 9.0 + r.call(17) if employer == "" else minf(free_from + 0.5, 15.5)
		out.append([s6, s6 + 0.75, "beschwerde"])
	if energy < TIRED_BELOW:
		return out   # muede: abends kein Ausgehen
	var evening := 0.45 if wd in [4, 5] else 0.18
	if float(p.get("wage", 0.0)) > 0.0 and r.call(9) < evening:
		var s3: float = 18.0 + r.call(10)
		out.append([s3, minf(21.25, s3 + 1.5 + r.call(11)), "restaurant"])
	elif r.call(12) < (0.55 if wd == 6 else 0.25):
		var s4: float = 14.0 + 2.0 * r.call(13) if wd == 6 else maxf(free_from + 0.5, 17.0 + r.call(13))
		out.append([s4, minf(21.0, s4 + 1.0 + r.call(14)), "harbor" if me.call(3) < 0.4 else "walk"])
	return out


## Schicht [Beginn, Ende] oder [] (frei). Wechselschicht: Frueh/Spaet/Nacht nach Person und Woche, zwei freie Tage je Woche versetzt.
func _shift(employer: String, id: int, day: int, wd: int, me: Callable) -> Array:
	var s: Array = SHIFTS.get(employer, [7.0, 9.0, 8.0])
	var mode := str(s[3]) if s.size() > 3 else ""
	if mode == "wechsel":
		var off := posmod(id, 7)
		if wd == off or wd == posmod(off + 1, 7):
			return []
		var turn := posmod(id + day / 7, 3)
		var start: float = [6.0, 14.0, 22.0][turn]
		return [start, minf(24.0, start + float(s[2]))] if turn < 2 else [start, 24.0]
	if wd == 6 or (wd == 5 and mode != "samstag"):
		return []
	var begin := float(s[0]) + (float(s[1]) - float(s[0])) * float(me.call(1))
	begin = snappedf(begin, 0.25)
	return [begin, begin + float(s[2])]


## Taetigkeit zur Stunde h: {art, von, bis}; ausserhalb aller Abschnitte zu Hause (nachts: schlaeft).
func activity(p: Dictionary, h: float, day: int) -> Dictionary:
	var found := {}
	for e in day_plan(p, day):
		if h >= float(e[0]) and h < float(e[1]):
			found = {"art": str(e[2]), "von": float(e[0]), "bis": float(e[1])}
	if found.is_empty():
		# Nachtschicht vom Vortag (22-6 Uhr)
		if h < 6.0:
			for e in day_plan(p, day - 1):
				if str(e[2]) == "work" and float(e[0]) >= 22.0:
					return {"art": "work", "von": 0.0, "bis": 6.0}
		var wake := 5.5 + 1.5 * Citizens.roll(int(p.id), 0, 960)
		return {"art": "sleep" if h < wake or h >= 22.0 else "home", "von": 0.0, "bis": 24.0}
	return found


## Ziel zur Stunde: {building, purpose, cell, art} oder {} (Auslandsreise). Wird fuer Fussgaenger und Auswahlanzeige genutzt.
func plan(p: Dictionary, hour: float, day: int) -> Dictionary:
	var unit: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	var home := int(unit.get("building", -1))
	var act := activity(p, hour, day)
	var art := str(act.art)
	if art in ["walk", "harbor"] and sim.wx != null and (sim.wx.is_rain() or sim.wx.is_snow()):
		art = "home"   # bei Regen bleibt man drinnen
	if art == "krank":
		art = "home"
	if art in ["home", "sleep"]:
		if home >= 0:
			if str(act.art) == "krank":
				return _result(home, KINDS.krank, "krank")
			return _result(home, "Nach Hause" if art == "sleep" or hour >= 20.0 or hour < 6.0 else KINDS.home, art)
		art = "jobs" if str(p.get("employer", "")) == "" else "work"   # ohne Wohnung: tagsueber unterwegs
	var town := _town_of(p, home)
	var near: Vector2i = sim.city.building(home).walk if home >= 0 else Vector2i(-1, -1)
	var bid := -1
	match art:
		"work":
			bid = _workplace(p, town)
		"course":
			bid = _nearest("school", town, near, int(p.id), hour, false)
		"jobs", "jobsuche":
			bid = _job_office(town, near)
		_:
			bid = _nearest(art, town, near, int(p.id), hour, true)
	if bid < 0:
		sim.citizens.note_unserved(town, art)
		unserved_people[int(p.id)] = int(unserved_people.get(int(p.id), 0)) + 1
		if home >= 0:
			return _result(home, KINDS.home, "home")
		return {}
	var purpose: String = KINDS.get(art, art)
	if str(act.art) == "krank":
		purpose = KINDS.krank
	if art == "work":
		purpose = "Zur Arbeit: " + str(Citizens.EMPLOYERS.get(str(p.employer), {}).get("label", p.employer))
	return _result(bid, purpose, art)


func _result(bid: int, purpose: String, art: String) -> Dictionary:
	return {"building": bid, "purpose": purpose, "cell": sim.city.building(bid).walk, "art": art}


func _town_of(p: Dictionary, home: int) -> int:
	if not sim.towns.is_region():
		return 0
	if home >= 0:
		return sim.towns.of_building(home)
	return sim.citizens.home_town(p)


## Fester Arbeitsplatz im Wohnort (gleiche Person, gleicher Ort, gleiches Gebaeude), Rueckfall: ganze Karte.
func _workplace(p: Dictionary, town: int) -> int:
	var employer := str(p.get("employer", ""))
	var types: Array = {"rathaus": ["townhall"], "schule_klinik": ["school", "kindergarten", "clinic"], "polizei": ["police"],
		"gesundheit": ["doctor", "clinic"], "baufirma": ["construction", "warehouse", "freight_shed"], "handel": ["shop", "restaurant", "kneipe", "hotel"],
		"industrie": ["factory", "brewery", "bakery", "workshop"], "stadtlager": ["warehouse"], "hafen": ["port_office", "warehouse"],
		"kommunal": ["freight_shed", "townhall"]}.get(employer, ["office"])
	var ids := _candidates("work:" + employer, types, town)
	if ids.is_empty():   # z. B. noch keine Schule im Ort: Dienst im Rathaus bzw. in einem Buero oder Laden des Orts
		ids = _candidates("work:any", ["townhall", "office", "shop"], town)
	if ids.is_empty():
		ids = _candidates("work:" + employer, types, -1)
	return int(ids[posmod(int(p.id), ids.size())]) if not ids.is_empty() else -1


func _job_office(town: int, near: Vector2i) -> int:
	var ids := _candidates("jobs", ["job_board", "staffing"], town, true)
	if ids.is_empty():
		ids = _candidates("jobs", ["job_board", "staffing", "office"], -1, true)
	return _closest(ids, near, 0)


## Naechstgelegenes (offenes) Ziel der Art im Ort; die Person waehlt aus den drei naechsten (nach ID), damit sich Besucher verteilen.
func _nearest(art: String, town: int, near: Vector2i, id: int, hour: float, need_open: bool) -> int:
	var types: Array = PLACE_TYPES.get(art, ["shop"])
	var ids := _candidates(art, types, town)
	if need_open:
		ids = ids.filter(func(b): return _open(str(sim.city.building(int(b)).type), hour))
	return _closest(ids, near, posmod(id, 3))


func _closest(ids: Array, near: Vector2i, pick: int) -> int:
	if ids.is_empty():
		return -1
	if near.x < 0:
		return int(ids[0])
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a, b):
		var pa: Vector2i = sim.city.building(int(a)).walk
		var pb: Vector2i = sim.city.building(int(b)).walk
		return absi(pa.x - near.x) + absi(pa.y - near.y) < absi(pb.x - near.x) + absi(pb.y - near.y))
	return int(sorted[mini(pick, sorted.size() - 1)])


static func _open(type: String, hour: float) -> bool:
	if Residents.PROFILES.has(type):
		return Residents.is_open(type, hour)
	return hour >= float(DEFAULT_HOURS[0]) and hour < float(DEFAULT_HOURS[1])


## Gebaeude-IDs nach Typ (oder Rolle) im Ort (town < 0: alle), je Gebaeudebestand zwischengespeichert.
func _candidates(key: String, types: Array, town: int, by_role: bool = false) -> Array:
	if _cand_rev != sim.city.buildings.size():
		_cands.clear()
		_cand_rev = sim.city.buildings.size()
	var k := "%s|%d" % [key, town]
	if not _cands.has(k):
		var region: bool = sim.towns.is_region()
		var out: Array = []
		for b in sim.city.buildings:
			if not (b.type in types or (by_role and str(b.get("role", "")) in types)):
				continue
			if b.type in ["plot", "free_plot"] or not sim.city.walkable(b.walk):
				continue
			if town >= 0 and region and sim.towns.of_building(int(b.id)) != town:
				continue
			out.append(int(b.id))
		_cands[k] = out
	return _cands[k]


# ------------------------------------------------------------------ Gemuet (Auftrag 23)
## Jede Figur fuehrt ein Gemuet aus ihrer echten Lage: Energie (Arbeitsstunden, Nachtschicht, Pendelweg, Schlaf, freie Tage),
## Jobfrust (Lohn unter dem Schnitt, Pendelweg, Schichtdienst, Muedigkeit, Unglueck) und Aerger (unversorgte Wuensche, Unglueck,
## Arbeitslosigkeit, Erschoepfung). Gruende werden mitgeschrieben. Daraus folgen Entscheidungen im Tagesplan (krank, frueh heim,
## Jobsuche, Beschwerde) und im Monat (Citizens._dynamics: Frustrierte wechseln oder kuendigen eher).
const SICK_BELOW := 12.0
const TIRED_BELOW := 35.0
const QUIT_FRUST := 65.0
const ANGRY_ABOVE := 60.0

var _wage_mean := 0.0
var unserved_people := {}   # Personen-ID -> unversorgte Wuensche heute (aus plan())


func on_day(day: int) -> void:
	var paid: Array = sim.citizens.people.filter(func(q): return float(q.get("wage", 0.0)) > 0.0)
	_wage_mean = 0.0
	for q in paid:
		_wage_mean += float(q.wage)
	_wage_mean /= maxf(1.0, float(paid.size()))
	for p in sim.citizens.people:
		_update_mood(p, day)
	unserved_people.clear()


func _update_mood(p: Dictionary, day: int) -> void:
	var g: Dictionary = p.get("gemuet", {"energie": 70.0 + 20.0 * Citizens.roll(int(p.id), 0, 970), "frust": 20.0, "aerger": 0.0, "nacht_folge": 0})
	var why: Array = []
	var yesterday := day_plan(p, day - 1)
	var work_h := 0.0
	var night := false
	var sick := false
	for e in yesterday:
		if str(e[2]) == "work":
			work_h += float(e[1]) - float(e[0])
			night = night or float(e[0]) >= 21.0
		sick = sick or str(e[2]) == "krank"
	var commute := _commute(p)
	var energy := float(g.energie)
	if work_h > 0.0:
		energy -= work_h * 4.2 + commute / 12.0
		if night:
			energy -= 8.0
			g["nacht_folge"] = int(g.get("nacht_folge", 0)) + 1
		else:
			g["nacht_folge"] = 0
		energy += 22.0 if night else 30.0   # Schlaf (nach der Nachtschicht schlechter)
	else:
		energy += 22.0 if not sick else 30.0   # freier Tag bzw. Krankentag
		g["nacht_folge"] = 0
	energy = clampf(energy, 0.0, 100.0)
	if int(g.nacht_folge) >= 2:
		why.append("müde: %d Nachtschichten in Folge" % int(g.nacht_folge))
	elif energy < TIRED_BELOW and work_h > 0.0:
		why.append("müde: lange Schichten%s" % (", weiter Arbeitsweg" if commute > 60.0 else ""))
	var frust := float(g.frust)
	if str(p.get("employer", "")) != "":
		var wage := float(p.get("wage", 0.0))
		var gap := clampf((_wage_mean - wage) / maxf(1.0, _wage_mean), 0.0, 1.0)
		var glueck := float(p.get("needs", {}).get("glueck", 50.0))
		var target := 15.0 + 60.0 * gap + clampf(commute / 4.0, 0.0, 20.0) + (12.0 if night else 0.0) + (12.0 if energy < TIRED_BELOW else 0.0) + 0.4 * maxf(0.0, 50.0 - glueck)
		frust += (target - frust) * 0.12
		if gap > 0.15:
			why.append("Lohn %.0f EUR/h unter dem Schnitt (%.0f)" % [wage, _wage_mean])
		if commute > 60.0:
			why.append("Arbeitsweg %d Felder" % int(commute))
	else:
		frust *= 0.9
	var anger := float(g.aerger) * 0.85
	var miss := int(unserved_people.get(int(p.id), 0))
	if miss > 0:
		anger += 9.0 * float(miss)
		why.append("nichts Offenes im Ort gefunden")
	if float(p.get("needs", {}).get("glueck", 50.0)) < 35.0:
		anger += 4.0
		why.append("unglücklich (Geld/Wohnen)")
	if str(p.get("employer", "")) == "" and int(p.get("jobless_months", 0)) >= 2:
		anger += 4.0
		why.append("seit %d Monaten arbeitslos" % int(p.jobless_months))
	if energy < SICK_BELOW:
		anger += 3.0
	g["energie"] = snappedf(energy, 0.1)
	g["frust"] = snappedf(clampf(frust, 0.0, 100.0), 0.1)
	g["aerger"] = snappedf(clampf(anger, 0.0, 100.0), 0.1)
	g["gruende"] = why.slice(0, 3)
	g["stand"] = int(energy < SICK_BELOW) + 2 * int(energy < TIRED_BELOW) + 4 * int(float(g.frust) > QUIT_FRUST) + 8 * int(float(g.aerger) > ANGRY_ABOVE)
	p["gemuet"] = g


## Pendelweg in Feldern (Luftlinie Wohnung -> Arbeitsplatz).
func _commute(p: Dictionary) -> float:
	var unit: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	if unit.is_empty() or str(p.get("employer", "")) == "":
		return 0.0
	var home := int(unit.building)
	var w := _workplace(p, _town_of(p, home))
	if w < 0:
		return 0.0
	var a: Vector2i = sim.city.building(home).walk
	var b: Vector2i = sim.city.building(w).walk
	return float(absi(a.x - b.x) + absi(a.y - b.y))


## Kurzform fuer Anzeige: "müde", "verärgert", "will kündigen", "erschöpft" oder "".
static func mood_label(p: Dictionary) -> String:
	var g: Dictionary = p.get("gemuet", {})
	if g.is_empty():
		return ""
	var out: Array = []
	if float(g.energie) < SICK_BELOW:
		out.append("erschöpft")
	elif float(g.energie) < TIRED_BELOW:
		out.append("müde")
	if float(g.aerger) > ANGRY_ABOVE:
		out.append("verärgert")
	if float(g.frust) > QUIT_FRUST and str(p.get("employer", "")) != "":
		out.append("will kündigen")
	return ", ".join(out)
