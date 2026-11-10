class_name FireService
extends RefCounted
## Feuerwehr (Auftrag 20, Etappen 4 und 13, docs/PUBLIC_SERVICES.md). Baut auf den kommunalen Einrichtungen (Municipal) auf:
##  - Einsatzarten (KINDS) mit Alarm- und Ausrueckeordnung: je Einsatzart die noetigen Fahrzeugrollen (Pflicht) und Ergaenzungen
##    (wenn frei: Drehleiter beim Wohnungsbrand, Tanklöschfahrzeug und Einsatzleitung beim Industriebrand). Die Rollen tragen die
##    Fahrzeuge (Municipal.VEHICLES.roles); ein Rettungswagen oder Bus kann nie loeschen.
##  - Braende: Entstehung je Tag und Gebaeude, deterministisch aus Gebaeude-ID und Tag; Ursache und Einsatzart haengen vom Gebaeude ab.
##    Technische Einsaetze (Verkehrsunfall, technische Hilfe, Unwetter, Wasserschaden, Gefahrstoff, Fahrzeugbrand) je Stadt und Tag.
##  - Alarm an die naechste Wache der Stadt, die alle Pflichtrollen frei hat und genug Einsatzkraefte im Dienst (Wachabteilungen,
##    Tagdienst, Ehrenamtliche, Erschoepfung); sonst Nachbarschaftshilfe, sofern sie vor dem Ausbrennen ankommt (Kosten erstattet).
##  - Ausruecken: Berufsfeuerwehr 2, Freiwillige 8 Spielminuten; mit Leitstelle in der Stadt (FW-03/04) 1 Minute schneller.
##  - Das Feuer waechst, bis geloescht wird; Loeschleistung = Fahrzeuge vor Ort + Einsatzkraefte (Lehrgang: mehr), Tank und Fuehrung
##    verstaerken. Technische Einsaetze brauchen Arbeitszeit; bis zum Eintreffen waechst ihr Schaden (Gebaeude, Strasse).
##  - Nach dem Einsatz: Erschoepfung der Einsatzkraefte, Gebaeudeschaden -> Reparaturauftrag an das Handwerk (S0).
##  - Personal: Funktionen (Wachleiter, Zugfuehrer, Gruppenfuehrer, Maschinist, Geraetewart, Disponent, Feuerwehrtechniker),
##    Lehrgaenge im Ausbildungszentrum (FW-06).
##  - Flughafenbrand: uebernimmt die Flughafenfeuerwehr (FW-05) mit Flugfeldloeschfahrzeugen; Warenschaden rechnet der Flughafen ab.
## Alle Geldfluesse sind Ueberweisungen zwischen bestehenden Konten (Geldkonservierung).

const BASE_RISK := 0.0012              # Brandwahrscheinlichkeit je Gebaeude und Tag
const RISK := {"restaurant": 2.5, "kneipe": 2.5, "disco": 2.0, "hotel": 1.5, "factory": 2.5, "workshop": 2.0, "warehouse": 1.5, "farm": 1.8,
	"freight_shed": 1.3, "gas_station": 1.5}
const CAUSE_OF := {"restaurant": "Küchenbrand", "kneipe": "Küchenbrand", "hotel": "Küchenbrand", "factory": "Maschinenbrand",
	"workshop": "Funkenflug bei Schweißarbeiten", "farm": "Selbstentzündung von Heu", "gas_station": "Kraftstoff entzündet", "warehouse": "Defekte Lagertechnik"}
const KIND_OF := {"restaurant": "Küchenbrand", "kneipe": "Küchenbrand", "hotel": "Küchenbrand", "bakery": "Küchenbrand",
	"factory": "Industriebrand", "workshop": "Industriebrand", "gas_station": "Industriebrand", "shipyard": "Industriebrand",
	"warehouse": "Lagerhallenbrand", "freight_shed": "Lagerhallenbrand", "farm": "Lagerhallenbrand", "airport_cargo": "Lagerhallenbrand",
	"house": "Wohnungsbrand", "semi": "Wohnungsbrand", "villa": "Wohnungsbrand", "apartment": "Wohnungsbrand", "highrise": "Wohnungsbrand"}
const TALL := ["apartment", "highrise", "hotel", "office"]   # Drehleiter fuer den zweiten Rettungsweg

## Alarm- und Ausrueckeordnung. need: Pflichtrollen, je Eintrag Alternativen (ein Fahrzeug je Eintrag); opt: Ergaenzungen, wenn frei.
## work: Arbeitszeit vor Ort (Spielminuten) bei technischen Einsaetzen; harm: Schaden je Minute bis zum Arbeitsbeginn.
const KINDS := {
	"Wohnungsbrand": {"fire": true, "need": [["loeschen"]], "opt": ["hoehe", "fuehrung"]},
	"Küchenbrand": {"fire": true, "need": [["loeschen"]], "opt": []},
	"Gebäudebrand": {"fire": true, "need": [["loeschen"]], "opt": ["hoehe"]},
	"Industriebrand": {"fire": true, "need": [["loeschen"]], "opt": ["wasser", "fuehrung", "loeschen"]},
	"Lagerhallenbrand": {"fire": true, "need": [["loeschen"]], "opt": ["wasser", "fuehrung"]},
	"Fahrzeugbrand": {"fire": true, "need": [["loeschen_klein", "loeschen"]], "opt": [], "max": 40.0},
	"Flughafenbrand": {"fire": true, "need": [["flugfeld"]], "opt": ["flugfeld", "fuehrung"]},
	"Verkehrsunfall": {"fire": false, "need": [["thl"]], "opt": ["fuehrung", "loeschen_klein"], "work": 35.0, "patient": true},
	"Technische Hilfeleistung": {"fire": false, "need": [["thl"]], "opt": [], "work": 25.0},
	"Unwetterschaden": {"fire": false, "need": [["thl", "logistik"]], "opt": ["logistik"], "work": 50.0, "harm_road": 0.05},
	"Wasserschaden": {"fire": false, "need": [["logistik", "thl"]], "opt": [], "work": 40.0, "harm": 0.04},
	"Gefahrstoffeinsatz": {"fire": false, "need": [["gefahrstoff"], ["loeschen", "loeschen_klein"]], "opt": ["fuehrung"], "work": 70.0, "harm": 0.03},
}
## Technische Einsaetze je Stadt und Tag (Grundwahrscheinlichkeit; Wetter verstaerkt).
const DAILY := {"Verkehrsunfall": 0.05, "Technische Hilfeleistung": 0.04, "Fahrzeugbrand": 0.015, "Wasserschaden": 0.02,
	"Unwetterschaden": 0.0, "Gefahrstoffeinsatz": 0.008}
const START_INTENSITY := 10.0
const GROW_PER_MIN := 2.0              # Brandstaerke-Zuwachs je Spielminute bis zum Loeschangriff
const DAMAGE_PER_MIN := 0.015          # Schadenspunkte je Spielminute und Brandstaerke-Punkt
const BURN_OUT_MIN := 150.0            # ohne Loeschen brennt ein normales Gebaeude nach dieser Zeit aus
const LARGE := ["factory", "warehouse", "freight_shed", "farm", "hotel", "port_office", "airport_cargo", "shipyard"]
const BURN_OUT_LARGE := 480.0          # Grossbrand: grosse Gebaeude brennen stundenlang (Nachbarwehren kommen noch rechtzeitig)
const DAMAGE_LARGE := 0.35             # ... und verlieren je Minute anteilig weniger
const MAX_DAMAGE := 90.0
const TURNOUT_PRO := 2.0               # Ausrueckzeit Berufsfeuerwehr (Spielminuten)
const TURNOUT_VOL := 8.0               # Ausrueckzeit Freiwillige Feuerwehr
const LEITSTELLE_GAIN := 1.0           # Leitstelle in der Stadt: Alarmierung eine Minute schneller
const CREW := 2                        # Mindestbesatzung je ausrueckendem Fahrzeug im Spiel
const EXT_PER_CREW := 1.0              # Loeschleistung je Einsatzkraft (Brandstaerke je Spielminute)
const EXT_TRAINED := 1.5               # ... mit Lehrgang (Ausbildungszentrum)
const WATER_BONUS := 1.5               # Tankloeschfahrzeug vor Ort: Loeschwasser reicht durch
const LEAD_BONUS := 1.2                # Einsatzleitung vor Ort: koordinierter Angriff, schnellere technische Hilfe
const HEIGHT_DAMAGE := 0.8             # Drehleiter beim Wohnungsbrand: zweiter Rettungsweg, weniger Schaden
const HELP_FEE := 1500.0               # Nachbarschaftshilfe: Pauschale an die helfende Stadt
const HELP_PER_MIN := 20.0             # ... plus je Einsatzminute
const REPAIR_PER_POINT := 350.0        # Reparaturkosten je Schadenspunkt
const CONDITION_PER_POINT := 0.8       # Zustandsverlust (BuildingCare) je Schadenspunkt
const SPEED := 3.6                     # Kacheln je Sim-Sekunde (Sonderrechte)
const KEEP_DONE := 60
const TIRE_PER_MIN := 0.4              # Erschoepfung je Einsatzminute (0..100)
const TIRED := 80.0                    # ab hier nicht einsetzbar (Ruhezeit)
const RECOVER_PER_DAY := 50.0
const SHIFT_MIN_STAFF := 6             # ab so vielen Hauptamtlichen: drei Wachabteilungen im 24-Stunden-Dienst, sonst Tagdienst 7-17 Uhr
const COURSE_DAYS := 10                # Lehrgang im Ausbildungszentrum

var sim
var fires := {}           # "B<n>" -> Einsatz {id, kind, fire, building, cell, town, cause, start, intensity, damage, status, station, vehicle, vehicles, task, helper, phase, ...}
var repairs := {}         # "R<n>" -> {id, building, town, fire, damage, cost, payer, until, status}
var movers := {}          # Fahrzeug-ID (Municipal) -> Mover (nur Darstellung/Fahrt, nicht gespeichert: nach dem Laden stehen alle in der Wache)
var stats := {"braende": 0, "geloescht": 0, "ausgebrannt": 0, "nachbarschaftshilfe": 0, "schaden": 0.0, "reparaturen": 0, "reparaturkosten": 0.0,
	"technisch": 0, "lehrgaenge": 0}
var random_fires := true  # Tests schalten zufaellige Braende ab und zuenden gezielt (ignite)
var random_incidents := true
var _next := {"B": 1, "R": 1}
var _day := -1


func setup(simulation) -> void:
	sim = simulation
	if sim.municipal == null or not sim.municipal.enabled():
		return
	sim.day_changed.connect(on_day)


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


func _id(p: String) -> String:
	var n := int(_next[p])
	_next[p] = n + 1
	return "%s%d" % [p, n]


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


static func is_station(f: Dictionary) -> bool:
	return str(f.code).begins_with("FW-") and not bool(Municipal.TYPES[f.code].get("ausbildung", false))


# ------------------------------------------------------------------ Entstehung
func risk_of(b: Dictionary) -> float:
	var r := BASE_RISK * float(RISK.get(str(b.type), 1.0))
	var cond: float = sim.care.get_condition(int(b.id)) if sim.care != null else 70.0
	if cond < 40.0:
		r *= 2.0                       # marode Elektrik
	if sim.wx.is_hot() and not sim.wx.is_rain():
		r *= 1.5                       # Hitze und Trockenheit
	return r


func cause_of(b: Dictionary) -> String:
	if CAUSE_OF.has(str(b.type)):
		return str(CAUSE_OF[b.type])
	if sim.care != null and sim.care.get_condition(int(b.id)) < 40.0:
		return "Defekte Elektrik"
	return ["Vergessene Kerze", "Defektes Elektrogerät", "Zigarette", "Überhitzter Akku"][absi(hash([b.id, _today()])) % 4]


static func kind_of(b: Dictionary) -> String:
	return str(KIND_OF.get(str(b.type), "Gebäudebrand"))


func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	var burning := {}
	for f in fires.values():
		if f.status == "brennt" and int(f.building) >= 0:
			burning[int(f.building)] = true
	for r in repairs.values():
		if r.status == "offen":
			burning[int(r.building)] = true   # in Reparatur: kein neuer Brand
	var start: Array = []
	for b in sim.city.buildings:
		if not random_fires:
			break
		if b.role != "customer" or burning.has(int(b.id)):
			continue
		if Citizens.roll(int(b.id), day, 4401) < risk_of(b):
			start.append(int(b.id))
	for bid in start:
		ignite(int(bid))
	if random_fires and random_incidents:   # Tests schalten mit random_fires alle Zufallseinsaetze ab
		_incidents(day)
	_repairs_day(day)
	_staff_day(day)


## Technische Einsaetze und Fahrzeugbraende je Stadt (deterministisch aus Stadt, Tag und Art). Ort: Strasse vor einem Gebaeude der Stadt.
func _incidents(day: int) -> void:
	var by_town := {}
	for b in sim.city.buildings:
		if b.has("road") and str(b.get("role", "")) in ["customer", "municipal"]:
			var k: int = sim.towns.of_building(int(b.id))
			if not by_town.has(k):
				by_town[k] = []
			by_town[k].append(b)
	var ki := 0
	for kind in DAILY:
		ki += 1
		var p := float(DAILY[kind])
		if kind == "Unwetterschaden" and (sim.wx.is_strong_wind() or sim.wx.is_heavy_rain()):
			p = 0.3
		elif kind == "Wasserschaden" and sim.wx.is_heavy_rain():
			p *= 3.0
		elif kind == "Verkehrsunfall" and (sim.wx.is_snow() or sim.wx.is_fog()):
			p *= 2.0
		if p <= 0.0:
			continue
		for t in sim.towns.list:
			var k := int(t.id)
			var list: Array = by_town.get(k, [])
			if list.is_empty() or Citizens.roll(k * 31 + ki, day, 4402) >= p:
				continue
			if kind == "Gefahrstoffeinsatz":
				list = list.filter(func(b): return str(b.type) in ["factory", "workshop", "gas_station", "warehouse"])
				if list.is_empty():
					continue
			var b: Dictionary = list[absi(hash([k, ki, day])) % list.size()]
			var on_building: bool = kind in ["Wasserschaden", "Gefahrstoffeinsatz", "Technische Hilfeleistung"] and str(b.role) == "customer"
			open_incident(kind, b.road, k, int(b.id) if on_building else -1)


## Brand in einem Gebaeude ausloesen (auch fuer Tests und Ereignisse). Alarmiert sofort die Feuerwehr.
func ignite(bid: int, cause: String = "", kind: String = "") -> Dictionary:
	var b: Dictionary = sim.city.building(bid)
	if b.is_empty():
		return {}
	var k: int = sim.towns.of_building(bid)
	var large: bool = str(b.type) in LARGE
	var f := _new(kind if kind != "" else kind_of(b), b.road, k, bid)
	f.cause = cause if cause != "" else cause_of(b)
	f.large = large
	f.burn_out = BURN_OUT_LARGE if large else BURN_OUT_MIN
	f.tall = str(b.type) in TALL
	stats.braende = int(stats.braende) + 1
	sim.log_event("%s in %s (%s): %s." % [f.kind, f.name, sim.towns.name_of(k), f.cause], "warn")
	sim.activity.add("stadt", -1, "stadt", "%s: %s" % [f.kind, f.name], f.cause, b.road)
	_alarm(f)
	return f


## Einsatz ohne Gebaeudebrand (Verkehrsunfall, technische Hilfe, Unwetter, Wasserschaden, Gefahrstoff, Fahrzeugbrand, Flughafenbrand).
## bid >= 0: betroffenes Gebaeude (Wasserschaden, Gefahrstoff); data: Zusatzangaben (z. B. Flughafen).
func open_incident(kind: String, cell: Vector2i, k: int, bid: int = -1, data: Dictionary = {}) -> Dictionary:
	var f := _new(kind, cell, k, bid)
	f.cause = str(data.get("cause", kind))
	for key in data:
		f[key] = data[key]
	if bool(KINDS[kind].fire):
		stats.braende = int(stats.braende) + 1
		f.burn_out = BURN_OUT_LARGE if kind == "Flughafenbrand" else BURN_OUT_MIN
	else:
		stats.technisch = int(stats.technisch) + 1
	sim.log_event("%s in %s (%s)." % [kind, f.name, sim.towns.name_of(k)], "warn" if bool(KINDS[kind].fire) else "info")
	sim.activity.add("stadt", -1, "stadt", "%s: %s" % [kind, f.name], f.cause, cell)
	if bool(KINDS[kind].get("patient", false)):
		_patient(f)
	_alarm(f)
	return f


func _new(kind: String, cell: Vector2i, k: int, bid: int) -> Dictionary:
	var b: Dictionary = sim.city.building(bid) if bid >= 0 else {}
	var name := str(b.get("name", b.get("type", ""))) if not b.is_empty() else "Straße bei %d/%d" % [cell.x, cell.y]
	var f := {"id": _id("B"), "kind": kind, "fire": bool(KINDS[kind].fire), "building": bid, "cell": [cell.x, cell.y], "town": k,
		"cause": kind, "start": sim.game_min, "intensity": START_INTENSITY if bool(KINDS[kind].fire) else 0.0, "damage": 0.0,
		"status": "brennt" if bool(KINDS[kind].fire) else "laeuft", "station": "", "vehicle": "", "vehicles": [], "task": "", "helper": false,
		"phase": "alarm", "alarm_at": sim.game_min, "turnout_until": 0.0, "last": sim.game_min, "name": name, "large": false,
		"burn_out": BURN_OUT_MIN, "work_left": float(KINDS[kind].get("work", 0.0)), "tall": false}
	fires[f.id] = f
	return f


## Verkehrsunfall: ein Buerger der Stadt ist verletzt -> Rettungsdienst (Etappe 5) parallel zur Feuerwehr.
func _patient(f: Dictionary) -> void:
	if sim.rescue == null or not sim.rescue.enabled():
		return
	var k := int(f.town)
	var list: Array = sim.citizens.people.filter(func(p): return sim.citizens.home_town(p) == k and not PublicSafety.absent(p, _today()))
	if list.is_empty():
		return
	var p: Dictionary = list[absi(hash([f.id, k])) % list.size()]
	f["mission"] = sim.rescue.emergency(p, _cell(f))


func _cell(f: Dictionary) -> Vector2i:
	return Vector2i(int(f.cell[0]), int(f.cell[1]))


# ------------------------------------------------------------------ Alarmierung
## Wache mit allen Pflichtrollen frei und genug Kraeften im Dienst: zuerst die schnellste der eigenen Stadt, sonst Nachbarschaftshilfe.
func _alarm(f: Dictionary) -> void:
	var M: Municipal = sim.municipal
	var target := _cell(f)
	var best := {}
	var best_pick: Array = []
	var best_d := INF
	var left: float = float(f.start) + float(f.get("burn_out", BURN_OUT_MIN)) - sim.game_min
	for own in [true, false]:
		for st in M.facilities.values():
			if not is_station(st) or st.status != "in_betrieb" or (int(st.town) == int(f.town)) != own:
				continue
			var pick := select_vehicles(st, str(f.kind))
			if pick.is_empty() or _crew_free(st) < CREW:
				continue
			var d := eta(st, target)
			if d < best_d and (own or not bool(f.fire) or d < left):   # Nachbarwehr beim Brand nur, wenn sie vor dem Ausbrennen ankommt
				best_d = d
				best = st
				best_pick = pick
		if not best.is_empty():
			break
	if best.is_empty():
		f.phase = "wartet"
		f["waited"] = true
		return
	var crew_need := mini(_crew_free(best), CREW * best_pick.size())
	var types: Array = best_pick.map(func(vid): return str(M.vehicles[vid].type))
	var t: Dictionary = M.open_task(best.id, "einsatz", target, 3, crew_need, types, {"einsatz": f.id, "art": f.kind})
	var r: Dictionary = M.dispatch(t.id, on_duty, best_pick)
	if not r.ok:
		M.finish(t.id, "nicht ausgerückt: " + str(r.msg))
		f.phase = "wartet"
		f["waited"] = true
		return
	f.station = best.id
	f.task = t.id
	f.vehicles = t.vehicles.duplicate()
	f.vehicle = str(t.vehicles[0])
	f.helper = int(best.town) != int(f.town)
	f.turnout_until = sim.game_min + _turnout(best)
	f.phase = "ausruecken"
	if f.helper:
		stats.nachbarschaftshilfe = int(stats.nachbarschaftshilfe) + 1
		sim.log_event("Nachbarschaftshilfe: %s (%s) rückt nach %s aus (%s)." % [best.name, sim.towns.name_of(int(best.town)), sim.towns.name_of(int(f.town)), f.kind], "info")
	var labels: Array = f.vehicles.map(func(vid): return str(M.vehicles[vid].type))
	var vol: bool = _pros_on_duty(best) < CREW
	sim.activity.add("stadt", -1, "stadt", "%s rückt aus: %s" % [best.name, f.kind], "%s – %s%s" % [f.name, ", ".join(labels),
		", Freiwillige werden alarmiert" if vol else ""], target)


## Fahrzeuge einer Wache nach der Ausrueckeordnung: je Pflichtrolle ein freies Fahrzeug (sonst leer), dazu freie Ergaenzungen.
func select_vehicles(st: Dictionary, kind: String) -> Array:
	var M: Municipal = sim.municipal
	var free: Array = st.vehicles.filter(func(vid): return M.vehicles.has(vid) and M.vehicles[vid].status == "bereit")
	var used := {}
	var out: Array = []
	for alts in KINDS[kind].need:
		var hit := ""
		for role in alts:   # Alternativen in Reihenfolge der Eignung (z. B. erst Kleinloeschfahrzeug fuer den Pkw-Brand)
			for vid in free:
				if not used.has(vid) and role in Municipal.VEHICLES[M.vehicles[vid].type].get("roles", []):
					hit = vid
					break
			if hit != "":
				break
		if hit == "":
			return []
		used[hit] = true
		out.append(hit)
	for role in KINDS[kind].opt:
		for vid in free:
			if not used.has(vid) and role in Municipal.VEHICLES[M.vehicles[vid].type].get("roles", []):
				used[vid] = true
				out.append(vid)
				break
	return out


func _leitstelle(k: int) -> bool:
	return sim.municipal.of_town(k, "feuerwehr").any(func(s): return s.status == "in_betrieb" and bool(Municipal.TYPES[s.code].get("leitstelle", false)))


func _turnout(st: Dictionary) -> float:
	var x := TURNOUT_VOL if _pros_on_duty(st) < CREW else TURNOUT_PRO
	if _leitstelle(int(st.town)):
		x = maxf(0.5, x - LEITSTELLE_GAIN)
	return x


## Ankunft in Spielminuten: Ausruecken + Fahrt ueber die Strasse mit Sonderrechten.
func eta(st: Dictionary, target: Vector2i) -> float:
	var tiles: int = sim.nav.path_length(sim.city.building(int(st.building)).road, target)
	if tiles < 0:
		return INF
	return _turnout(st) + float(tiles) / SPEED * Catalog.GAME_MIN_PER_SIM_SEC


# ------------------------------------------------------------------ Personal: Dienstplan, Erschoepfung, Funktionen, Lehrgaenge
## Einsatzbereit: nicht erschoepft; an grossen Wachen Hauptamtliche nur in ihrer Wachabteilung, Ehrenamtliche immer alarmierbar.
## Kleine Wachen (Tagdienst): die Hauptamtlichen sind ausserhalb der Dienstzeit wie Ehrenamtliche alarmierbar (Ausrueckzeit Freiwillige).
func on_duty(p: Dictionary, st: Dictionary) -> bool:
	if float(p.get("erschoepfung", 0.0)) >= TIRED:
		return false
	if str(p.get("dienst", "")) != str(st.id):
		return true   # ehrenamtlich
	if sim.municipal.staff_count(st.id) >= SHIFT_MIN_STAFF:
		return in_shift(p)
	return true


## Wachabteilung im Dienst (drei Abteilungen, 24 Stunden Dienst, 48 Stunden frei).
func in_shift(p: Dictionary) -> bool:
	return (int(p.id) + _today()) % 3 == 0


## Hauptamtliche auf der Wache (rueckt in 2 Minuten aus): Wachabteilung bzw. Tagdienst 7-17 Uhr.
func _pros_on_duty(st: Dictionary) -> int:
	var shifts: bool = sim.municipal.staff_count(st.id) >= SHIFT_MIN_STAFF
	var h: float = GameCalendar.hour_of(sim.game_min)
	var day_shift: bool = h >= 7.0 and h < 17.0
	return sim.municipal.staff_of(st.id).filter(func(p): return float(p.get("erschoepfung", 0.0)) < TIRED and not PublicSafety.absent(p, _today()) and (in_shift(p) if shifts else day_shift)).size()


func _crew_free(st: Dictionary) -> int:
	var M: Municipal = sim.municipal
	var busy := {}
	for t in M.tasks.values():
		if t.status == "unterwegs" and str(t.facility) == str(st.id):
			for pid in t.staff:
				busy[int(pid)] = true
	var day := _today()
	return (M.staff_of(st.id) + M.volunteers_of(st.id)).filter(func(p): return not busy.has(int(p.id)) and not PublicSafety.absent(p, day) and on_duty(p, st)).size()


## Funktionen der Hauptamtlichen je Wache (nach Dienstalter = Buerger-ID): Wachleiter, Zugfuehrer, Gruppenfuehrer, Maschinisten je
## Fahrzeug, Geraetewart, Disponenten der Leitstelle, Feuerwehrtechniker der Werkstatt; die uebrigen sind Feuerwehrleute.
const FUNKTIONEN := ["Wachleiter", "Zugführer", "Gruppenführer", "Maschinist", "Gerätewart", "Disponent", "Feuerwehrtechniker", "Feuerwehrmann/-frau"]


func assign_functions(st: Dictionary) -> void:
	var staff: Array = sim.municipal.staff_of(st.id)
	staff.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var t: Dictionary = Municipal.TYPES[st.code]
	var plan: Array = []
	if staff.size() >= 4:
		plan.append("Wachleiter")
	for i in staff.size() / 15:
		plan.append("Zugführer")
	for i in maxi(1 if staff.size() >= 2 else 0, staff.size() / 6):
		plan.append("Gruppenführer")
	if bool(t.get("leitstelle", false)):
		plan += ["Disponent", "Disponent"]
	if bool(t.get("werkstatt", false)):
		plan.append("Feuerwehrtechniker")
	if staff.size() >= 6:
		plan.append("Gerätewart")
	for i in st.vehicles.size():
		plan.append("Maschinist")
	for i in staff.size():
		staff[i]["funktion"] = str(plan[i]) if i < plan.size() else "Feuerwehrmann/-frau"


func _staff_day(day: int) -> void:
	var M: Municipal = sim.municipal
	var school := M.facilities.values().filter(func(s): return bool(Municipal.TYPES[s.code].get("ausbildung", false)) and s.status == "in_betrieb" and M.staff_count(s.id) > 0)
	var seats := 0
	for s in school:
		seats += int(s.capacity)
	var in_course := 0
	var queue: Array = []
	for st in M.facilities.values():
		if not is_station(st):
			continue
		if st.status == "in_betrieb":
			assign_functions(st)
		for p in M.staff_of(st.id) + M.volunteers_of(st.id):
			p["erschoepfung"] = maxf(0.0, float(p.get("erschoepfung", 0.0)) - RECOVER_PER_DAY)
			var until := int(p.get("lehrgang_bis", -1))
			if until >= 0 and day >= until:
				p["lehrgang"] = true
				p.erase("lehrgang_bis")
				stats.lehrgaenge = int(stats.lehrgaenge) + 1
			elif until >= 0:
				in_course += 1
			elif not bool(p.get("lehrgang", false)):
				queue.append(p)
	queue.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for p in queue.slice(0, maxi(0, seats - in_course)):
		p["lehrgang_bis"] = day + COURSE_DAYS


# ------------------------------------------------------------------ Ablauf je Simulationsschritt
func update(dt: float) -> void:
	if fires.is_empty():
		return
	var now: float = sim.game_min
	for f in fires.values():
		if f.status not in ["brennt", "laeuft"] and f.phase != "rueckfahrt":
			continue
		var mins := now - float(f.last)
		f.last = now
		if f.status == "brennt":
			_burn(f, mins)
		elif f.status == "laeuft":
			_harm(f, mins)
		match str(f.phase):
			"wartet":
				if now - float(f.alarm_at) >= 10.0:
					f.alarm_at = now
					_alarm(f)            # alle 10 Spielminuten erneut alarmieren
			"ausruecken":
				if now >= float(f.turnout_until):
					f.phase = "anfahrt"
					for vid in f.vehicles:
						sim.route(mover_of(vid), _cell(f))
			"anfahrt":
				var all_there := true
				for vid in f.vehicles:
					var m := mover_of(vid)
					if not m.arrived():
						m.advance(dt, 1.0)
						all_there = false
				if mover_of(f.vehicle).arrived():
					f.phase = "loeschen" if bool(f.fire) else "arbeiten"
					f["attack"] = now
					sim.activity.add("stadt", -1, "stadt", "%s: %s" % ["Löschangriff" if bool(f.fire) else "Einsatzstelle erreicht", f.name],
						"Brandstärke %d" % int(f.intensity) if bool(f.fire) else str(f.kind), _cell(f))
			"loeschen":
				_drive_rest(f, dt)
				f.intensity = maxf(0.0, float(f.intensity) - power(f) * mins)
				if float(f.intensity) <= 0.0:
					_extinguished(f, "gelöscht")
			"arbeiten":
				_drive_rest(f, dt)
				f.work_left = maxf(0.0, float(f.work_left) - mins * _lead(f))
				if float(f.work_left) <= 0.0:
					_done(f, "abgeschlossen")
			"rueckfahrt":
				var home := true
				for vid in f.vehicles:
					var m := mover_of(vid)
					if not m.arrived():
						m.advance(dt, 1.0)
						home = false
				if home:
					f.phase = "fertig"
					_tire(f)
					sim.municipal.finish(f.task, "%s %s: %s" % [f.kind, f.id, f.status])


func _drive_rest(f: Dictionary, dt: float) -> void:
	for vid in f.vehicles:
		var m := mover_of(vid)
		if not m.arrived():
			m.advance(dt, 1.0)


func _here(f: Dictionary) -> Array:
	return f.vehicles.filter(func(vid): return mover_of(vid).arrived() and sim.municipal.vehicles.has(vid))


func _has_role(vids: Array, role: String) -> bool:
	return vids.any(func(vid): return role in Municipal.VEHICLES[sim.municipal.vehicles[vid].type].get("roles", []))


func _lead(f: Dictionary) -> float:
	return LEAD_BONUS if _has_role(_here(f), "fuehrung") else 1.0


## Loeschleistung je Spielminute: Fahrzeuge vor Ort + Einsatzkraefte (mit Lehrgang mehr), Tank und Fuehrung verstaerken.
func power(f: Dictionary) -> float:
	var here := _here(f)
	var x := 0.0
	for vid in here:
		x += float(Municipal.VEHICLES[sim.municipal.vehicles[vid].type].get("power", 0.0))
	for p in _crew_people(f):
		x += EXT_TRAINED if bool(p.get("lehrgang", false)) else EXT_PER_CREW
	if _has_role(here, "wasser"):
		x *= WATER_BONUS
	return x * _lead(f)


func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var v: Dictionary = M.vehicles[vid]
		var m := Mover.new()
		m.speed = SPEED
		m.pos = sim.city.tile_center(sim.city.building(M.building_of(str(v.facility))).road)
		movers[vid] = m
	return movers[vid]


## Fahrzeuge auf der Strasse fuer die Kartenansicht: {vid, mover, siren}.
func on_road() -> Array:
	var out: Array = []
	for f in fires.values():
		if f.phase not in ["anfahrt", "loeschen", "arbeiten", "rueckfahrt"]:
			continue
		for vid in f.vehicles:
			if movers.has(vid) and sim.municipal.vehicles.has(vid):
				out.append({"vid": vid, "mover": movers[vid], "siren": f.phase != "rueckfahrt"})
	return out


func _burn(f: Dictionary, mins: float) -> void:
	if f.phase != "loeschen":
		f.intensity = minf(float(KINDS[f.kind].get("max", 100.0)), float(f.intensity) + GROW_PER_MIN * mins)
	if int(f.building) >= 0:
		var k := DAMAGE_LARGE if bool(f.get("large", false)) else 1.0
		if f.kind == "Wohnungsbrand" and bool(f.get("tall", false)) and _has_role(_here(f), "hoehe"):
			k *= HEIGHT_DAMAGE
		f.damage = minf(MAX_DAMAGE, float(f.damage) + DAMAGE_PER_MIN * float(f.intensity) * mins * k)
	if f.phase in ["wartet", "ausruecken", "anfahrt"] and sim.game_min - float(f.start) >= float(f.get("burn_out", BURN_OUT_MIN)):
		if int(f.building) >= 0:
			f.damage = MAX_DAMAGE
		_extinguished(f, "ausgebrannt")


## Technische Einsaetze: bis zum Arbeitsbeginn waechst der Schaden (Wasser im Gebaeude, Sturmschaden an der Strasse).
func _harm(f: Dictionary, mins: float) -> void:
	if f.phase == "arbeiten":
		return
	var k: Dictionary = KINDS[f.kind]
	if int(f.building) >= 0 and k.has("harm"):
		f.damage = minf(MAX_DAMAGE, float(f.damage) + float(k.harm) * mins)
	if k.has("harm_road") and sim.road_care != null:
		var seg := RoadCare.seg_of(_cell(f))
		if sim.road_care.cond.has(seg):
			sim.road_care.cond[seg] = maxf(0.0, float(sim.road_care.cond[seg]) - float(k.harm_road) * mins)
			f.damage = float(f.damage) + float(k.harm_road) * mins


func _extinguished(f: Dictionary, how: String) -> void:
	f.status = how
	f.intensity = 0.0
	f["end"] = sim.game_min
	stats.schaden = float(stats.schaden) + float(f.damage)
	if how == "ausgebrannt":
		stats.ausgebrannt = int(stats.ausgebrannt) + 1
	else:
		stats.geloescht = int(stats.geloescht) + 1
	var bid := int(f.building)
	if bid >= 0 and sim.care != null and sim.care.condition.has(bid):
		sim.care.condition[bid] = clampf(float(sim.care.condition[bid]) - float(f.damage) * CONDITION_PER_POINT, 0.0, 100.0)
	sim.log_event("%s %s (%s, %s): Schaden %d %%. %s" % [f.name, how, f.kind, sim.towns.name_of(int(f.town)), int(f.damage),
		"Löschzeit %d Minuten nach Alarm." % int(sim.game_min - float(f.start)) if how == "gelöscht" else "Keine Feuerwehr war rechtzeitig verfügbar."], "warn" if how == "ausgebrannt" else "info")
	_close(f)


func _done(f: Dictionary, how: String) -> void:
	f.status = how
	f["end"] = sim.game_min
	stats.schaden = float(stats.schaden) + float(f.damage)
	sim.log_event("%s (%s, %s) abgearbeitet nach %d Minuten." % [f.kind, f.name, sim.towns.name_of(int(f.town)), int(sim.game_min - float(f.start))], "info")
	_close(f)


func _close(f: Dictionary) -> void:
	if f.helper:
		var minutes: float = sim.game_min - float(f.start)
		var fee: float = HELP_FEE + HELP_PER_MIN * minutes
		var helper_town := int(sim.municipal.facilities[f.station].town)
		sim.economy.transfer(Towns.account_of(int(f.town)), Towns.account_of(helper_town), fee)
		f["help_fee"] = fee
	if int(f.building) >= 0 and float(f.damage) >= 1.0 and not bool(f.get("airport", false)):
		_open_repair(f)
	if bool(f.get("airport", false)) and sim.airport != null:
		sim.airport.fire_done_by_service(sim.game_min)   # Warenschaden und Abrechnung am Frachtterminal
	if f.vehicle != "":
		f.phase = "rueckfahrt"
		var home: int = sim.municipal.building_of(str(f.station))
		for vid in f.vehicles:
			sim.route(mover_of(vid), sim.city.building(home).road)
	else:
		f.phase = "fertig"
	_prune()


## Erschoepfung der eingesetzten Kraefte nach Einsatzdauer.
func _tire(f: Dictionary) -> void:
	var mins: float = maxf(10.0, sim.game_min - float(f.start))
	for p in _crew_people(f):
		p["erschoepfung"] = minf(100.0, float(p.get("erschoepfung", 0.0)) + TIRE_PER_MIN * mins)


## Eingesetzte Kraefte (Hauptamtliche und Ehrenamtliche der ausrueckenden Wache) laut Aufgabe.
func _crew_people(f: Dictionary) -> Array:
	var t: Dictionary = sim.municipal.tasks.get(f.task, {})
	if t.is_empty() or str(f.station) == "":
		return []
	var ids := {}
	for pid in t.get("staff", []):
		ids[int(pid)] = true
	var M: Municipal = sim.municipal
	return (M.staff_of(f.station) + M.volunteers_of(f.station)).filter(func(p): return ids.has(int(p.id)))


# ------------------------------------------------------------------ Flughafen (FW-05)
func airport_station() -> Dictionary:
	for st in sim.municipal.facilities.values():
		if bool(Municipal.TYPES[st.code].get("flughafen", false)) and st.status == "in_betrieb":
			return st
	return {}


# ------------------------------------------------------------------ Reparatur
func payer_of(bid: int) -> String:
	var b: Dictionary = sim.city.building(bid)
	if str(b.get("role", "")) == "municipal":
		return Towns.account_of(sim.towns.of_building(bid))
	return "H0"


func _open_repair(f: Dictionary) -> void:
	var r := {"id": _id("R"), "building": int(f.building), "town": int(f.town), "fire": f.id, "damage": float(f.damage),
		"cost": snappedf(float(f.damage) * REPAIR_PER_POINT, 1.0), "payer": payer_of(int(f.building)),
		"until": _today() + 1 + int(float(f.damage) / 15.0), "status": "offen", "name": f.name}
	repairs[r.id] = r
	sim.activity.add("stadt", -1, "reparatur", "Reparaturauftrag: %s" % f.name, "%s, Schaden %d %%, %d Tage, %s" % [f.kind, int(r.damage), int(r.until) - _today(), _eur(r.cost)],
		sim.city.building(int(f.building)).road)


func _repairs_day(day: int) -> void:
	for r in repairs.values():
		if r.status != "offen" or day < int(r.until):
			continue
		sim.economy.transfer(str(r.payer), "S0", float(r.cost))
		var bid := int(r.building)
		if sim.care != null and sim.care.condition.has(bid):
			sim.care.condition[bid] = clampf(float(sim.care.condition[bid]) + float(r.damage) * CONDITION_PER_POINT, 0.0, 100.0)
		r.status = "fertig"
		stats.reparaturen = int(stats.reparaturen) + 1
		stats.reparaturkosten = float(stats.reparaturkosten) + float(r.cost)
		sim.log_event("Schaden an %s repariert (%s)." % [r.name, _eur(r.cost)], "info")


func damaged(bid: int) -> bool:
	return repairs.values().any(func(r): return r.status == "offen" and int(r.building) == bid)


static func _eur(x: float) -> String:
	return "%d €" % int(round(x))


func _prune() -> void:
	var done: Array = fires.values().filter(func(f): return f.phase == "fertig")
	if done.size() > KEEP_DONE:
		done.sort_custom(func(a, b): return float(a.get("end", 0.0)) < float(b.get("end", 0.0)))
		for i in done.size() - KEEP_DONE:
			fires.erase(done[i].id)
	var rd: Array = repairs.values().filter(func(r): return r.status == "fertig")
	if rd.size() > KEEP_DONE:
		for i in rd.size() - KEEP_DONE:
			repairs.erase(rd[i].id)


# ------------------------------------------------------------------ Uebersicht, Speichern
func active() -> Array:
	return fires.values().filter(func(f): return f.status in ["brennt", "laeuft"])


## Einsaetze der letzten `days` Tage einer Stadt (Last fuer den Ausbau der Wache).
func load_of(k: int, days: int = 30) -> int:
	var d0 := _today() - days
	return fires.values().filter(func(f): return int(f.town) == k and GameCalendar.day_of(float(f.start)) >= d0).size()


func summary(k: int = -1) -> Dictionary:
	var act: Array = active().filter(func(f): return k < 0 or int(f.town) == k)
	return {"aktiv": act.map(func(f): return "%s: %s (%s%s, %s)" % [f.kind, f.name, f.cause,
			", Stärke %d" % int(f.intensity) if bool(f.fire) else "", f.phase]),
		"brennt": act.filter(func(f): return bool(f.fire)).map(func(f): return "%s (%s, Stärke %d, Schaden %d %%, %s)" % [f.name, f.cause, int(f.intensity), int(f.damage), f.phase]),
		"reparaturen_offen": repairs.values().filter(func(r): return r.status == "offen" and (k < 0 or int(r.town) == k)).size(),
		"gesamt": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"fires": fires.duplicate(true), "repairs": repairs.duplicate(true), "stats": stats.duplicate(), "next": _next.duplicate(), "day": _day}


## Laden: laufende Einsaetze stehen in der Wache neu an (Fahrzeugposition wird nicht gespeichert): Einsatz wird neu alarmiert.
## Staende vor Etappe 13 (ohne Einsatzart): Art aus dem Gebaeude, Einsatzort vor dem Gebaeude.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	fires = d.get("fires", {})
	repairs = d.get("repairs", {})
	for key in d.get("stats", {}):
		stats[key] = d.stats[key]
	_day = int(d.get("day", -1))
	for k in d.get("next", {}):
		_next[k] = int(d.next[k])
	for f in fires.values():
		f.building = int(f.building)
		f.town = int(f.town)
		if not f.has("kind"):
			var b: Dictionary = sim.city.building(int(f.building))
			f["kind"] = kind_of(b)
			f["fire"] = true
			f["cell"] = [int(b.road.x), int(b.road.y)] if b.has("road") else [0, 0]
			f["vehicles"] = [f.vehicle] if str(f.vehicle) != "" else []
			f["work_left"] = 0.0
		if f.phase in ["ausruecken", "anfahrt", "loeschen", "arbeiten", "rueckfahrt"]:
			if f.task != "" and sim.municipal.tasks.has(f.task):
				sim.municipal.finish(f.task, "nach dem Laden neu alarmiert")
			f.vehicle = ""
			f.vehicles = []
			f.task = ""
			if f.status in ["brennt", "laeuft"]:
				f.phase = "wartet"
				f.alarm_at = 0.0
			else:
				f.phase = "fertig"
	for r in repairs.values():
		r.building = int(r.building)
		r.until = int(r.until)
