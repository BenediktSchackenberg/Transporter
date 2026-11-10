class_name Education
extends RefCounted
## Bildung (Auftrag 20, Etappe 8, docs/PUBLIC_SERVICES.md): Kinder, Plaetze in Kitas und Schulen, Lehrkraefte, Qualifikation ueber Zeit.
##  - Kinder: Erwachsene zwischen 22 und 45 Jahren haben mit festen Anteilen 0, 1 oder 2 Kinder (einmal bestimmt, deterministisch aus
##    der Buerger-ID; Geburtstag in der Vergangenheit verteilt). Kinder altern mit dem Spielkalender; sie ziehen mit den Eltern weg.
##  - Kita (1-5 Jahre) und Schule (6-17 Jahre): Plaetze der Einrichtungen der Wohnstadt (Municipal KI-01/SC-01, Plaetze nach
##    Einwohnerzahl). Betreuungs-/Schulquote = Plaetze / Kinder (hoechstens 1). Unterrichtsqualitaet = Lehrkraefte / Bedarf.
##  - Lernstand je Kind: jeden Monat in der Schule + Schulquote x Qualitaet (ohne Schulplatz: Heimunterricht 0,2).
##  - Schulabschluss mit 18: das Kind wird ein neuer Buerger der Stadt (wohnt bei den Eltern, sucht Arbeit). Bildung nach Lernstand:
##    Lernstand >= 90 % der 12 Schuljahre -> Stufe 2, >= 50 % -> Stufe 1, sonst 0. So wirken Schulen ueber die Jahre auf den Arbeitsmarkt.
##  - Kitas erleichtern Familienzuzug (Faktor auf den Zuzug des Buergermeisters).
##  - Engpaesse (Kinder ohne Platz) stehen in der Uebersicht und im Lagebericht des Buergermeisters (Neubau: Etappe 11).

const SHARES := [0.55, 0.30, 0.15]     # 0, 1, 2 Kinder
const PARENT_AGE := [22, 45]
const KITA_AGE := [1, 5]
const SCHOOL_AGE := [6, 17]
const SCHOOL_YEARS := 12
const HOME_LEARNING := 0.2
const DAYS_PER_YEAR := 360

var sim
var learned := {}        # "Eltern-ID:i" -> Lernstand (Schuljahre, 0..12)
var stats := {"abschluesse": 0, "abschluss_bildung": [0, 0, 0], "ohne_schulplatz_monate": 0}
var _month := -1


func setup(simulation) -> void:
	sim = simulation
	if sim.municipal != null and sim.municipal.enabled():
		sim.month_changed.connect(on_month)


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


## Kinder eines Buergers (Geburtstage in Spieltagen). Einmal bestimmt und am Buerger gespeichert.
func children_of(p: Dictionary) -> Array:
	if p.has("kinder"):
		return p.kinder
	var kids: Array = []
	var age := int(p.get("age", 30))
	if age >= int(PARENT_AGE[0]) and age <= int(PARENT_AGE[1]):
		var r := Citizens.roll(int(p.id), 0, 8801)
		var n := 0 if r < float(SHARES[0]) else (1 if r < float(SHARES[0]) + float(SHARES[1]) else 2)
		for i in n:
			var kid_age := 1.0 + Citizens.roll(int(p.id), i, 8802) * float(mini(16, age - 21))
			kids.append(_today() - int(kid_age * DAYS_PER_YEAR))
	p["kinder"] = kids
	return kids


func age_years(birth: int) -> float:
	return float(_today() - birth) / float(DAYS_PER_YEAR)


## Kinder je Stadt und Altersgruppe.
func kids(k: int) -> Dictionary:
	var out := {"kita": 0, "schule": 0}
	for p in sim.citizens.people:
		if sim.citizens.home_town(p) != k:
			continue
		for b in children_of(p):
			var a := age_years(int(b))
			if a >= float(KITA_AGE[0]) and a < float(KITA_AGE[1]) + 1.0:
				out.kita = int(out.kita) + 1
			elif a >= float(SCHOOL_AGE[0]) and a < float(SCHOOL_AGE[1]) + 1.0:
				out.schule = int(out.schule) + 1
	return out


func places(k: int, code: String) -> int:
	var n := 0
	for f in sim.municipal.of_town(k):
		if f.code == code and f.status == "in_betrieb":
			n += int(f.capacity)
	return n


## Unterrichtsqualitaet: Lehrkraefte / Bedarf der Schulen der Stadt (0..1).
func quality(k: int) -> float:
	var need := 0
	var have := 0
	for f in sim.municipal.of_town(k):
		if f.code == "SC-01" and f.status == "in_betrieb":
			need += int(f.staff_need.get("lehrkraft", 0))
			have += sim.municipal.staff_count(f.id, "lehrkraft")
	return 0.0 if need == 0 else minf(1.0, float(have) / float(need))


func coverage(k: int, code: String) -> float:
	var kd := kids(k)
	var n := int(kd.kita if code == "KI-01" else kd.schule)
	return 1.0 if n == 0 else minf(1.0, float(places(k, code)) / float(n))


func family_factor(k: int) -> float:
	return 1.0 + 0.15 * coverage(k, "KI-01") if places(k, "KI-01") > 0 else 1.0


# ------------------------------------------------------------------ Monat: Lernen, Abschluss
func on_month(month: int) -> void:
	if month == _month:
		return
	_month = month
	var cov := {}
	var q := {}
	for t in sim.towns.list:
		var k := int(t.id)
		cov[k] = coverage(k, "SC-01")
		q[k] = quality(k)
	var graduates: Array = []
	for p in sim.citizens.people:
		var k: int = sim.citizens.home_town(p)
		var kids_p: Array = children_of(p)
		for i in kids_p.size():
			var a := age_years(int(kids_p[i]))
			var key := "%d:%d" % [int(p.id), i]
			if a >= float(SCHOOL_AGE[0]) and a < float(SCHOOL_AGE[1]) + 1.0:
				var gain := float(cov.get(k, 0.0)) * float(q.get(k, 0.0))
				learned[key] = float(learned.get(key, 0.0)) + maxf(HOME_LEARNING, gain) / 12.0
				if float(cov.get(k, 0.0)) < 1.0:
					stats.ohne_schulplatz_monate = int(stats.ohne_schulplatz_monate) + 1
			elif a >= 18.0 and not learned.has(key + ":fertig"):
				graduates.append([p, i, key])
	for g in graduates:
		_graduate(g[0], int(g[1]), str(g[2]), month)


func _graduate(parent: Dictionary, i: int, key: String, month: int) -> void:
	var share := float(learned.get(key, 0.0)) / float(SCHOOL_YEARS)
	var edu := 2 if share >= 0.9 else (1 if share >= 0.5 else 0)
	learned[key + ":fertig"] = true
	learned.erase(key)
	sim.citizens.immigrate(1, month, str(parent.get("home", "")))
	var kid: Dictionary = sim.citizens.people[sim.citizens.people.size() - 1]
	kid.age = 18
	kid.education = edu
	kid.name = "%s %s" % [str(kid.name).split(" ")[0], str(parent.name).split(" ")[-1]]
	kid["kinder"] = []
	stats.abschluesse = int(stats.abschluesse) + 1
	stats.abschluss_bildung[edu] = int(stats.abschluss_bildung[edu]) + 1
	sim.log_event("%s (Kind von %s) schließt die Schule ab: Bildungsstufe %d (Lernstand %d %%)." % [kid.name, parent.name, edu, roundi(share * 100.0)], "info")


# ------------------------------------------------------------------ Uebersicht, Speichern
func summary(k: int) -> Dictionary:
	var kd := kids(k)
	return {"kinder_kita": int(kd.kita), "kitaplaetze": places(k, "KI-01"), "kinder_schule": int(kd.schule), "schulplaetze": places(k, "SC-01"),
		"lehrkraefte_quote": snappedf(quality(k), 0.01), "ohne_kitaplatz": maxi(0, int(kd.kita) - places(k, "KI-01")),
		"ohne_schulplatz": maxi(0, int(kd.schule) - places(k, "SC-01")), "abschluesse": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"learned": learned.duplicate(), "stats": stats.duplicate(true), "month": _month}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	learned = d.get("learned", {})
	stats = d.get("stats", stats)
	_month = int(d.get("month", -1))
