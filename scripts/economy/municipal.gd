class_name Municipal
extends RefCounted
## Kommunale Einrichtungen (Auftrag 20, Etappe 1, docs/PUBLIC_SERVICES.md): ein gemeinsames Modell fuer Feuerwachen, Rettungswachen,
## Krankenhaeuser, Bauhoefe, Verkehrsbetriebe, Schulen, Kitas und Recyclinghoefe. Jede Einrichtung hat ein echtes Gebaeude, einen
## Typcode, einen Namen aus Stadt und Lage, Stadtstil und visuellen Seed, Personal (echte Buerger, Arbeitgeber "kommunal"),
## Unterhalt aus der Stadtkasse, Fahrzeuge mit Fahrer und Einsatzaufgaben. Die Fachsysteme (Feuerwehr, Rettung, ...) bauen darauf auf.
## Loehne zahlt Citizens._pay (Arbeitgeber "kommunal", Konto der Wohnstadt); hier nur Sach- und Fahrzeugkosten.
## Startausstattung je Stadt (Feuerwache, Rettungswache) entsteht am ersten Spieltag als Laufzeitgebaeude (EventDirector), damit
## Spielstaende ohne dieses System beim Laden unveraendert bleiben und neue Staende die Gebaeude genau wieder anlegen.

const EMPLOYER := "kommunal"
const HIRE_PER_DAY := 3               # Neueinstellungen je Einrichtung und Tag (Bewerbungsverfahren)
const REF_POP := 1000.0               # Personal laut TYPES.staff gilt fuer eine Stadt dieser Groesse; kleinere Orte brauchen anteilig weniger
const VOLUNTEER_STIPEND := 4.0        # Aufwandsentschaedigung je Ehrenamtlichem und Tag (Sachkosten)
const KEEP_CLOSED_TASKS := 200
const STATUS := ["in_betrieb", "geschlossen"]
const VEHICLE_STATUS := ["bereit", "im_einsatz", "werkstatt", "ausser_dienst"]

## Berufe: Stundenlohn (Basis, Bildungszuschlag kommt aus Population.wage_factor) und Mindestbildung (0..3).
const BERUFE := {
	"feuerwehr": {"label": "Feuerwehrleute", "wage": 16.0, "bildung": 1},
	"rettung": {"label": "Notfallsanitäter", "wage": 17.0, "bildung": 2},
	"notarzt": {"label": "Notärzte", "wage": 26.0, "bildung": 3},
	"pflege": {"label": "Pflegekräfte", "wage": 15.0, "bildung": 2},
	"arzt": {"label": "Ärzte", "wage": 26.0, "bildung": 3},
	"bauhof": {"label": "Bauhofmitarbeiter", "wage": 14.0, "bildung": 0},
	"fahrdienst": {"label": "Busfahrer", "wage": 14.0, "bildung": 1},
	"lehrkraft": {"label": "Lehrkräfte", "wage": 19.0, "bildung": 2},   # Stufe 3 ist selten und geht an die Kliniken
	"erzieher": {"label": "Erzieher", "wage": 14.0, "bildung": 2},
	"recycling": {"label": "Wertstoffwerker", "wage": 13.0, "bildung": 0},
}

## Einrichtungstypen. building: Gebaeudetyp in CityGenerator.TYPES; upkeep: Sachkosten je Tag; capacity: typabhaengige Leistung
## (gleichzeitige Einsaetze, Betten, Plaetze, Linien); power/water: Bedarf je Tag (kWh, m3); vehicles: Startfuhrpark.
## staff: hauptamtliches Personal bei REF_POP Einwohnern, min_staff: Mindestbesetzung (sonst je Beruf 1);
## volunteers: Ehrenamtliche (Freiwillige Feuerwehr: Buerger mit eigenem Beruf, alarmierbar, ohne Lohn);
## vehicles_from_pop: Fahrzeuge, die erst ab dieser Einwohnerzahl zur Erstausstattung gehoeren.
const TYPES := {
	"FW-01": {"label": "Freiwillige Feuerwehr", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_station", "cost": 420000.0,
		"upkeep": 140.0, "capacity": 2, "staff": {"feuerwehr": 8}, "min_staff": {"feuerwehr": 1}, "volunteers": 8, "power": 60.0, "water": 12.0,
		"vehicles": ["HLF 20", "DLK 23"], "vehicles_from_pop": {"DLK 23": 500}},
	"RW-01": {"label": "Rettungswache", "dienst": "rettung", "ressort": "Gesundheit", "building": "rescue_station", "cost": 260000.0,
		"upkeep": 90.0, "capacity": 2, "staff": {"rettung": 5, "notarzt": 1}, "min_staff": {"rettung": 2}, "power": 30.0, "water": 4.0,
		"vehicles": ["RTW", "NEF"], "vehicles_from_pop": {"NEF": 500}},
	"KH-01": {"label": "Krankenhaus", "dienst": "rettung", "ressort": "Gesundheit", "building": "hospital", "cost": 2400000.0,
		"upkeep": 900.0, "capacity": 40, "staff": {"arzt": 6, "pflege": 20}, "min_staff": {"arzt": 1, "pflege": 2}, "regional": true,
		"min_capacity": 6, "power": 400.0, "water": 60.0, "vehicles": []},
	"BH-01": {"label": "Bauhof", "dienst": "bauhof", "ressort": "Verkehr", "building": "municipal_yard", "cost": 300000.0,
		"upkeep": 110.0, "capacity": 2, "staff": {"bauhof": 6}, "min_staff": {"bauhof": 2}, "power": 40.0, "water": 6.0,
		"vehicles": ["Kipper", "Streuwagen"]},
	"VB-01": {"label": "Busbetriebshof", "dienst": "oepnv", "ressort": "Verkehr", "building": "bus_depot", "cost": 380000.0,
		"upkeep": 120.0, "capacity": 2, "staff": {"fahrdienst": 6}, "power": 50.0, "water": 6.0, "vehicles": ["Linienbus", "Linienbus"]},
	"SC-01": {"label": "Grundschule", "dienst": "bildung", "ressort": "Bildung", "building": "public_school", "cost": 1200000.0,
		"upkeep": 260.0, "capacity": 240, "min_capacity": 20, "staff": {"lehrkraft": 12}, "power": 120.0, "water": 20.0, "vehicles": []},
	"KI-01": {"label": "Kita", "dienst": "bildung", "ressort": "Bildung", "building": "public_kita", "cost": 600000.0,
		"upkeep": 110.0, "capacity": 60, "min_capacity": 10, "staff": {"erzieher": 6}, "power": 40.0, "water": 10.0, "vehicles": []},
	"RC-01": {"label": "Recyclinghof", "dienst": "recycling", "ressort": "Umwelt", "building": "recycling_yard", "cost": 350000.0,
		"upkeep": 100.0, "capacity": 2, "staff": {"recycling": 4}, "power": 80.0, "water": 4.0, "vehicles": ["Wertstoffwagen"]},
	# Ausbaustufen der Feuerwehr (Etappe 13): capacity = Stellplaetze. Hauptamtliche in drei Wachabteilungen (24-Stunden-Dienst), sobald
	# genug Personal da ist (FireService.on_duty); FW-03/04 mit Leitstelle (schnellere Alarmierung), FW-04 mit Werkstatt.
	"FW-02": {"label": "Feuerwache", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_station_m", "cost": 1600000.0,
		"upkeep": 260.0, "capacity": 4, "staff": {"feuerwehr": 18}, "min_staff": {"feuerwehr": 6}, "volunteers": 10, "power": 110.0, "water": 20.0,
		"vehicles": ["HLF 20", "LF 10", "TLF 3000", "ELW 1"], "vehicles_from_pop": {"ELW 1": 800}},
	"FW-03": {"label": "Hauptfeuerwache", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_station_l", "cost": 4500000.0,
		"upkeep": 520.0, "capacity": 7, "staff": {"feuerwehr": 30}, "min_staff": {"feuerwehr": 10}, "power": 220.0, "water": 35.0,
		"vehicles": ["KdoW", "ELW 1", "HLF 20", "HLF 20", "DLK 23", "TLF 3000", "RW"], "leitstelle": true},
	"FW-04": {"label": "Berufsfeuerwehr-Zentrale", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_hq", "cost": 9000000.0,
		"upkeep": 900.0, "capacity": 10, "staff": {"feuerwehr": 45}, "min_staff": {"feuerwehr": 16}, "power": 400.0, "water": 60.0,
		"vehicles": ["KdoW", "ELW 1", "HLF 20", "HLF 20", "LF 10", "DLK 23", "TLF 3000", "RW", "GW-L"], "leitstelle": true, "werkstatt": true},
	"FW-05": {"label": "Flughafenfeuerwehr", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_airport", "cost": 2200000.0,
		"upkeep": 300.0, "capacity": 3, "staff": {"feuerwehr": 12}, "min_staff": {"feuerwehr": 4}, "power": 120.0, "water": 30.0,
		"vehicles": ["FLF", "FLF", "HLF 20"], "flughafen": true},
	"FW-06": {"label": "Feuerwehrausbildungszentrum", "dienst": "feuerwehr", "ressort": "Sicherheit", "building": "fire_school", "cost": 2500000.0,
		"upkeep": 280.0, "capacity": 12, "staff": {"feuerwehr": 4}, "min_staff": {"feuerwehr": 2}, "regional": true, "power": 90.0, "water": 15.0,
		"vehicles": [], "ausbildung": true},
}

## Fahrzeugtypen: Kurzbezeichnung -> Beschreibung, Besatzung, Kosten je Tag, Kaufpreis, Sprite-Familie (Etappe 3).
const VEHICLES := {
	# Feuerwehr: roles = Aufgaben laut Alarm- und Ausrueckeordnung (FireService.KINDS), power = Loeschleistung (Brandstaerke je Minute)
	"HLF 20": {"label": "Hilfeleistungslöschfahrzeug", "crew": 6, "cost": 45.0, "price": 420000.0, "sprite": "fw_hlf", "roles": ["loeschen", "thl"], "power": 3.0},
	"DLK 23": {"label": "Drehleiter", "crew": 2, "cost": 55.0, "price": 750000.0, "sprite": "fw_dlk", "roles": ["hoehe"], "power": 0.5},
	"KdoW": {"label": "Kommandowagen", "crew": 1, "cost": 12.0, "price": 60000.0, "sprite": "fw_kdow", "roles": ["fuehrung"], "power": 0.0},
	"ELW 1": {"label": "Einsatzleitwagen", "crew": 2, "cost": 20.0, "price": 180000.0, "sprite": "fw_elw", "roles": ["fuehrung"], "power": 0.0},
	"KLF": {"label": "Kleinlöschfahrzeug", "crew": 3, "cost": 18.0, "price": 120000.0, "sprite": "fw_klf", "roles": ["loeschen_klein"], "power": 1.5},
	"LF 10": {"label": "Löschgruppenfahrzeug", "crew": 6, "cost": 35.0, "price": 330000.0, "sprite": "fw_lf10", "roles": ["loeschen"], "power": 2.5},
	"TLF 3000": {"label": "Tanklöschfahrzeug", "crew": 3, "cost": 38.0, "price": 360000.0, "sprite": "fw_tlf", "roles": ["loeschen", "wasser"], "power": 4.0},
	"GW-L": {"label": "Gerätewagen Logistik", "crew": 2, "cost": 25.0, "price": 200000.0, "sprite": "fw_gwl", "roles": ["logistik", "gefahrstoff"], "power": 0.0},
	"RW": {"label": "Rüstwagen", "crew": 3, "cost": 32.0, "price": 450000.0, "sprite": "fw_rw", "roles": ["thl", "thl_schwer", "gefahrstoff"], "power": 0.0},
	"FLF": {"label": "Flugfeldlöschfahrzeug", "crew": 3, "cost": 70.0, "price": 950000.0, "sprite": "fw_flf", "roles": ["flugfeld", "loeschen"], "power": 8.0},
	"RTW": {"label": "Rettungswagen", "crew": 2, "cost": 30.0, "price": 160000.0, "sprite": "rd_rtw"},
	"NEF": {"label": "Notarzteinsatzfahrzeug", "crew": 2, "cost": 20.0, "price": 90000.0, "sprite": "rd_nef"},
	"Kipper": {"label": "Kipper", "crew": 2, "cost": 25.0, "price": 120000.0, "sprite": "bh_kipper"},
	"Streuwagen": {"label": "Streu- und Räumfahrzeug", "crew": 1, "cost": 30.0, "price": 180000.0, "sprite": "bh_streu"},
	"Linienbus": {"label": "Linienbus", "crew": 1, "cost": 40.0, "price": 280000.0, "sprite": "bus"},
	"Wertstoffwagen": {"label": "Wertstoffsammelfahrzeug", "crew": 2, "cost": 35.0, "price": 230000.0, "sprite": "rc_wagen"},
}

## Stadtstile (tools/vox/public.py): Wandmaterial, Dachform, Fenster und Gruen; je Typ 6 Grundvarianten in jedem Stil.
const STYLES := {
	"backstein": "Backstein, traditionell",
	"modern": "modern, Glas und Beton",
	"gruen": "grün, Holz",
	"industrie": "Industrie, Stahl und Wellblech",
}
const STYLE_OF_CHARACTER := {"Marktflecken": "backstein", "Handwerkerort": "industrie", "Fischerdorf": "gruen", "Bauerndorf": "gruen"}
const START_KIT := ["FW-01", "RW-01", "BH-01"]
const REGIONAL_KIT := ["KH-01", "FW-06", "FW-05"]   # einmal je Region: Kreiskrankenhaus und Ausbildungszentrum in der einwohnerstaerksten Stadt,
                                                  # Flughafenfeuerwehr in der Wache des Flughafens (nur wenn es einen gibt)

var sim
var facilities := {}     # "M<n>" -> Einrichtung
var vehicles := {}       # "MV<n>" -> Fahrzeug
var tasks := {}          # "E<n>" -> Aufgabe/Einsatz
var started := false     # Startausstattung angelegt (oder versucht)
var regional_started := false   # regionale Startausstattung (Kreiskrankenhaus) angelegt oder versucht
var kit_tried := {}      # "Stadt|Typcode" -> true: Startausstattung versucht (spaeter hinzugekommene Typen auch fuer alte Staende)
var stats := {"eingestellt": 0, "abgang": 0, "kosten": 0.0, "einsaetze": 0}
var _next := {"M": 1, "MV": 1, "E": 1}


func setup(simulation) -> void:
	sim = simulation
	if not enabled():
		return
	sim.day_changed.connect(on_day)


## Nur in der Region (wie die Stadtentwicklung); Einzelstadt und Kuestenort bleiben vorerst wie bisher.
func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region()


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _id(prefix: String) -> String:
	var n := int(_next[prefix])
	_next[prefix] = n + 1
	return "%s%d" % [prefix, n]


# ------------------------------------------------------------------ Stil, Name, Seed
func style_of(k: int) -> String:
	return str(STYLE_OF_CHARACTER.get(str(sim.towns.get_t(k).get("charakter", "")), "modern"))


## Lage einer Zelle relativ zur Stadtmitte: Mitte, Nord, Nordost, ... (fuer Namen wie "Feuerwache Nord").
func lage(k: int, cell: Vector2i) -> String:
	var c: Vector2i = sim.towns.get_t(k).center
	var d := cell - c
	if absi(d.x) + absi(d.y) < 10:
		return "Mitte"
	var ns := "Nord" if d.y < -absi(d.x) / 2 else ("Süd" if d.y > absi(d.x) / 2 else "")
	var ow := "ost" if d.x > absi(d.y) / 2 else ("west" if d.x < -absi(d.y) / 2 else "")
	if ns == "":
		return ow.capitalize()
	return ns + ow


func _name(k: int, code: String, cell: Vector2i) -> String:
	var base := "%s %s" % [TYPES[code].label, lage(k, cell)]
	var n := 1
	var name := base
	while facilities.values().any(func(f): return int(f.town) == k and str(f.name) == name):
		n += 1
		name = "%s %d" % [base, n]
	return name


## Bildname aus Typ, Grundvariante und Stil (CityGenerator.TYPES, tools/vox/public.py): pub_<kuerzel>_<v>_<stil>.
static func sprite_of(f: Dictionary) -> String:
	var first := str(CityGenerator.TYPES[TYPES[f.code].building][0][0])   # z. B. pub_fw_0_backstein
	return "%s_%d_%s" % [first.left(first.find("_", 4)), int(f.variant), str(f.style)]


## Grundvariante aus dem Seed; schon vergebene Kombinationen aus Typ und Stil werden uebersprungen, solange noch eine frei ist
## (zehn Feuerwachen in der Region sehen verschieden aus).
func pick_variant(code: String, st: String, sd: int) -> int:
	var used := {}
	for f in facilities.values():
		if str(f.code) == code and str(f.style) == st:
			used[int(f.variant)] = int(used.get(int(f.variant), 0)) + 1
	var least := 1 << 30
	for v in 6:
		least = mini(least, int(used.get(v, 0)))
	for i in 6:
		var v := (sd + i) % 6
		if int(used.get(v, 0)) <= least:
			return v
	return sd % 6


static func visual_seed(world_seed: int, k: int, code: String, cell: Vector2i) -> int:
	return absi(hash([world_seed, k, code, cell.x, cell.y]))


# ------------------------------------------------------------------ Einrichtungen
## Neue Einrichtung auf einem fertigen Gebaeude registrieren (Startausstattung, spaeter Bau ueber die Buergermeister-Pipeline).
func register(k: int, code: String, building_id: int) -> Dictionary:
	var t: Dictionary = TYPES[code]
	var b: Dictionary = sim.city.building(building_id)
	var cell := Vector2i(int(b.x), int(b.y))
	var sd := visual_seed(int(sim.city.seed_value), k, code, cell)
	var st := style_of(k)
	var v := pick_variant(code, st, sd)
	var f := {"id": _id("M"), "code": code, "town": k, "name": _name(k, code, cell), "building": building_id, "cell": [cell.x, cell.y],
		"style": st, "seed": sd, "variant": v, "size": [int(b.w), int(b.h)], "cost": float(t.cost), "upkeep": float(t.upkeep),
		"capacity": capacity_for(code, served(code, k)), "staff_need": staff_need(code, served(code, k)), "volunteer_need": int(t.get("volunteers", 0)), "power": float(t.power), "water": float(t.water),
		"condition": 100.0, "inventory": {}, "owner": Towns.owner_of(k), "status": "in_betrieb", "opened": _today(), "vehicles": []}
	facilities[f.id] = f
	b["role"] = "municipal"
	b["town"] = k
	b["name"] = "%s, %s" % [f.name, sim.towns.name_of(k)]
	b["sprite"] = sprite_of(f)
	for ab in sim.events.added_buildings:   # Laden legt das Gebaeude mit genau diesem Bild wieder an
		if int(ab.x) == int(b.x) and int(ab.y) == int(b.y) and str(ab.type) == str(b.type):
			ab["sprite"] = b.sprite
	var nr := 1
	for vt in t.vehicles:
		if _pop(k) >= int(t.get("vehicles_from_pop", {}).get(vt, 0)):
			add_vehicle(f.id, str(vt), nr)
			nr += 1
	sim.log_event("%s: %s in Betrieb genommen (%s)." % [sim.towns.name_of(k), f.name, STYLES[f.style]], "info")
	return f


func _pop(k: int) -> int:
	return sim.citizens.population_of(k)


## Einwohner, fuer die eine Einrichtung zustaendig ist: regionale Typen versorgen die ganze Region.
func served(code: String, k: int) -> int:
	return sim.citizens.population() if bool(TYPES[code].get("regional", false)) else _pop(k)


## Plaetze/Betten nach versorgter Bevoelkerung (Werte gelten fuer REF_POP), mindestens min_capacity.
static func capacity_for(code: String, pop: int) -> int:
	var t: Dictionary = TYPES[code]
	return maxi(int(t.get("min_capacity", t.capacity)), roundi(float(t.capacity) * float(pop) / REF_POP)) if t.has("min_capacity") else int(t.capacity)


## Hauptamtlicher Bedarf je Beruf fuer eine Stadt mit `pop` Einwohnern.
static func staff_need(code: String, pop: int) -> Dictionary:
	var t: Dictionary = TYPES[code]
	var mins: Dictionary = t.get("min_staff", {})
	var out := {}
	for b in t.staff:
		out[b] = maxi(int(mins.get(b, 1 if mins.is_empty() else 0)), roundi(float(t.staff[b]) * float(pop) / REF_POP))
	return out


func add_vehicle(fid: String, vtype: String, nr: int = 0) -> Dictionary:
	var f: Dictionary = facilities[fid]
	if nr <= 0:
		nr = (f.vehicles as Array).size() + 1
	var v := {"id": _id("MV"), "type": vtype, "label": "%s – %s – Fahrzeug %d" % [vtype, f.name, nr], "facility": fid, "driver": -1,
		"status": "bereit", "condition": 100.0, "cost": float(VEHICLES[vtype].cost), "task": ""}
	vehicles[v.id] = v
	f.vehicles.append(v.id)
	return v


func of_town(k: int, dienst: String = "") -> Array:
	return facilities.values().filter(func(f): return int(f.town) == k and (dienst == "" or str(TYPES[f.code].dienst) == dienst))


func building_of(fid: String) -> int:
	return int(facilities.get(fid, {}).get("building", -1))


# ------------------------------------------------------------------ Startausstattung
## Je Stadt eine Feuerwache und eine Rettungswache auf freiem staedtischem Bauland nahe dem Rathaus.
func ensure_start() -> void:
	if started:
		return
	started = true
	ensure_kit()


## Fehlende Typen der Startausstattung je Stadt einmal nachbauen (z. B. Bauhof fuer Spielstaende vor Etappe 6).
func ensure_kit() -> void:
	for t in sim.towns.list:
		var k := int(t.id)
		for code in START_KIT:
			var key := "%d|%s" % [k, code]
			if kit_tried.has(key):
				continue
			kit_tried[key] = true
			if not of_town(k).any(func(f): return str(f.code) == code):
				_place(k, code)


## Regionale Einrichtungen (Kreiskrankenhaus): einmal je Region, in der einwohnerstaerksten Stadt mit passendem Bauplatz.
## Auch fuer Spielstaende, die vor Etappe 5 entstanden sind (eigenes Merkmal).
func ensure_regional() -> void:
	if regional_started and REGIONAL_KIT.all(func(c): return kit_tried.has("R|" + c)):
		return
	if regional_started:
		kit_tried["R|KH-01"] = true   # Spielstand vor Etappe 13: Kreiskrankenhaus wurde schon versucht
	regional_started = true
	var order: Array = sim.towns.list.map(func(t): return int(t.id))
	order.sort_custom(func(a, b): return _pop(a) > _pop(b))
	for code in REGIONAL_KIT:
		if kit_tried.has("R|" + code):
			continue
		kit_tried["R|" + code] = true
		if facilities.values().any(func(f): return str(f.code) == code):
			continue
		if code == "FW-05":
			_airport_fire()
			continue
		for k in order:
			var f := _place(k, code)
			if not f.is_empty():
				_share_regional(f)
				break


## Flughafenfeuerwehr (Etappe 13): die vorhandene Wache am Flughafen (gleiche Grundflaeche 3x2) wird Einrichtung FW-05 der Stadt des
## Flughafens, mit Personal, Flugfeldloeschfahrzeugen und eigenem Bild; Flughafenbraende uebernimmt danach die Feuerwehr (FireService).
func _airport_fire() -> void:
	var a = sim.airport
	if a == null or not a.enabled or int(a.fire_station) < 0 or sim.city.building(int(a.fire_station)).is_empty():
		return
	var bid := int(a.fire_station)
	register(sim.towns.of_building(bid), "FW-05", bid)


## Regionale Einrichtung (Kreiskrankenhaus): Traeger ist der Landkreis, die Kosten tragen alle Staedte nach Einwohneranteilen.
func _share_regional(f: Dictionary) -> void:
	var total := 0.0
	for t in sim.towns.list:
		total += float(maxi(1, _pop(int(t.id))))
	var sh := {}
	for t in sim.towns.list:
		sh[str(int(t.id))] = float(maxi(1, _pop(int(t.id)))) / total
	f["shares"] = sh
	f.owner = "region"


func _place(k: int, code: String) -> Dictionary:
	var bt: String = TYPES[code].building
	var info: Array = CityGenerator.TYPES[bt]
	var site: Dictionary = sim.civic._find_site(k, int(info[1]), int(info[2]))
	if site.is_empty():
		sim.log_event("%s: kein Bauplatz für %s gefunden." % [sim.towns.name_of(k), TYPES[code].label], "warn")
		return {}
	var r := Rect2i(int(site.rect[0]), int(site.rect[1]), int(site.rect[2]), int(site.rect[3]))
	var b: Dictionary = sim.events._add_building(bt, r, TYPES[code].label)
	if b.is_empty():
		return {}
	var p: Dictionary = sim.parcels.parcel(str(site.parcel))
	if not p.is_empty():
		p.state = "bebaut"
		p.use = bt
		p.building = int(b.id)
		sim.parcels.touch(str(site.parcel))
	var f := register(k, code, int(b.id))
	sim.events.buildings_added.emit([b.id])
	return f


# ------------------------------------------------------------------ Tag: Personal, Fahrer, Kosten
func on_day(day: int) -> void:
	if not started:
		ensure_start()
	if not regional_started or not REGIONAL_KIT.all(func(c): return kit_tried.has("R|" + c)):
		ensure_regional()
	if kit_tried.size() < sim.towns.count() * START_KIT.size():
		ensure_kit()
	var by_id := _staff_index()
	var vol := _volunteer_index()
	for f in facilities.values():
		if f.status != "in_betrieb":
			continue
		var need := staff_need(f.code, served(f.code, int(f.town)))
		f.capacity = maxi(int(f.capacity), capacity_for(f.code, served(f.code, int(f.town))))
		for b in need:   # waechst mit der Stadt; schrumpft sie, wird niemand entlassen, nur nicht nachbesetzt
			f.staff_need[b] = maxi(int(f.staff_need.get(b, 0)), int(need[b]))
		_hire(f, by_id)
		_volunteers(f, vol)
		_drivers(f, by_id)
	_costs()


## Buerger-ID -> Person fuer alle kommunal Beschaeftigten; Abgaenge (Kuendigung, Wegzug, Haft) werden hier erkannt.
func _staff_index() -> Dictionary:
	var by_id := {}
	for p in sim.citizens.people:
		if p.employer == EMPLOYER:
			if facilities.has(str(p.get("dienst", ""))):
				by_id[int(p.id)] = p
			else:
				p.employer = ""   # Einrichtung gibt es nicht mehr
				p.wage = 0.0
		elif p.has("dienst"):
			p.erase("dienst")
			p.erase("beruf")
			stats.abgang = int(stats.abgang) + 1
	return by_id


func staff_of(fid: String, by_id: Dictionary = {}) -> Array:
	if by_id.is_empty():
		by_id = _staff_index()
	return by_id.values().filter(func(p): return str(p.dienst) == fid)


func staff_count(fid: String, beruf: String = "") -> int:
	return staff_of(fid).filter(func(p): return beruf == "" or str(p.beruf) == beruf).size()


## Besetzungsgrad 0..1 (Fachsysteme skalieren ihre Leistung damit).
func staffing(fid: String) -> float:
	var f: Dictionary = facilities.get(fid, {})
	var need := 0
	for b in f.get("staff_need", {}):
		need += int(f.staff_need[b])
	return 1.0 if need == 0 else minf(1.0, float(staff_count(fid)) / float(need))


func _hire(f: Dictionary, by_id: Dictionary) -> void:
	var have := {}
	for p in by_id.values():
		if str(p.dienst) == str(f.id):
			have[p.beruf] = int(have.get(p.beruf, 0)) + 1
	var hired := 0
	var day := _today()
	for beruf in f.staff_need:
		var missing := int(f.staff_need[beruf]) - int(have.get(beruf, 0))
		if missing <= 0:
			continue
		for p in _candidates(-1 if bool(TYPES[f.code].get("regional", false)) else int(f.town), beruf, day):
			if hired >= HIRE_PER_DAY or missing <= 0:
				break
			var old := str(p.employer)
			if old != "":
				sim.activity.add("stadt", -1, "personal", "%s wechselt zu %s" % [p.name, f.name],
					"vorher %s" % Citizens.EMPLOYERS[old].label, _cell(f))
			p.erase("ehrenamt")   # aus dem Ehrenamt ins Hauptamt
			sim.citizens._employ(p, EMPLOYER, 0.5)
			p.wage = snappedf(float(BERUFE[beruf].wage) * Population.wage_factor(p), 0.1)
			p["dienst"] = f.id
			p["beruf"] = beruf
			by_id[int(p.id)] = p
			hired += 1
			missing -= 1
			stats.eingestellt = int(stats.eingestellt) + 1
			sim.activity.add("stadt", -1, "personal", "%s stellt %s ein (%s)" % [f.name, p.name, BERUFE[beruf].label],
				sim.towns.name_of(int(f.town)), _cell(f))
	if hired > 0:
		sim.citizens.cap[EMPLOYER] = sim.citizens.employed_count(EMPLOYER)


## Bewerber fuer einen Beruf: zuerst Arbeitslose der Stadt, dann Beschaeftigte privater Arbeitgeber mit niedrigerem Lohn
## (Stellenwechsel in den oeffentlichen Dienst; der alte Arbeitgeber besetzt im Monatsabschluss nach).
func _candidates(k: int, beruf: String, day: int) -> Array:
	var free: Array = []
	var switch: Array = []
	var wage := float(BERUFE[beruf].wage)
	for p in sim.citizens.people:
		if p.has("course_until") or PublicSafety.absent(p, day) or int(p.get("education", 0)) < int(BERUFE[beruf].bildung):
			continue
		if k >= 0 and sim.citizens.home_town(p) != k:
			continue
		if p.employer == "":
			free.append(p)
		elif p.employer != EMPLOYER and str(Citizens.EMPLOYERS[p.employer].payer) == "S0" and float(p.wage) < wage * Population.wage_factor(p):
			switch.append(p)
	return free + switch


## Ehrenamtliche (Freiwillige Feuerwehr): Buerger der Stadt behalten ihren Beruf und werden im Einsatz alarmiert.
func _volunteer_index() -> Dictionary:
	var by_fac := {}
	for p in sim.citizens.people:
		if not p.has("ehrenamt"):
			continue
		if not facilities.has(str(p.ehrenamt)) or p.employer == EMPLOYER:
			p.erase("ehrenamt")
			continue
		var fid := str(p.ehrenamt)
		if not by_fac.has(fid):
			by_fac[fid] = []
		by_fac[fid].append(p)
	return by_fac


func volunteers_of(fid: String) -> Array:
	return _volunteer_index().get(fid, [])


func _volunteers(f: Dictionary, vol: Dictionary) -> void:
	var have: Array = vol.get(f.id, [])
	var missing := int(f.get("volunteer_need", 0)) - have.size()
	if missing <= 0:
		return
	var n := 0
	for p in sim.citizens.people:
		if n >= mini(missing, HIRE_PER_DAY):
			break
		if p.has("ehrenamt") or p.employer == EMPLOYER or PublicSafety.absent(p, _today()) or sim.citizens.home_town(p) != int(f.town):
			continue
		if int(p.get("age", 30)) < 18 or int(p.get("age", 30)) > 60:
			continue
		p["ehrenamt"] = f.id
		have.append(p)
		n += 1
	vol[f.id] = have
	if n > 0:
		sim.activity.add("stadt", -1, "personal", "%d neue Ehrenamtliche bei %s" % [n, f.name], sim.towns.name_of(int(f.town)), _cell(f))


## Jedes Fahrzeug bekommt einen Fahrer aus dem Personal der Einrichtung (einer je Fahrzeug, solange Personal reicht).
func _drivers(f: Dictionary, by_id: Dictionary) -> void:
	var staff: Array = by_id.values().filter(func(p): return str(p.dienst) == str(f.id))
	var used := {}
	for vid in f.vehicles:
		var v: Dictionary = vehicles[vid]
		if by_id.has(int(v.driver)) and str(by_id[int(v.driver)].dienst) == str(f.id):
			used[int(v.driver)] = true
		else:
			v.driver = -1
	for vid in f.vehicles:
		var v: Dictionary = vehicles[vid]
		if int(v.driver) >= 0:
			continue
		for p in staff:
			if not used.has(int(p.id)):
				v.driver = int(p.id)
				used[int(p.id)] = true
				break


## Laufende Kosten der Dienste einer Stadt je Tag (Sach- und Fahrzeugkosten nach Anteilen plus Loehne des Personals).
func daily_cost(k: int) -> float:
	var x := 0.0
	for f in facilities.values():
		if f.status != "in_betrieb":
			continue
		var share := float(f.get("shares", {"%d" % int(f.town): 1.0}).get(str(k), 0.0))
		if share <= 0.0:
			continue
		var c := float(f.upkeep) * (0.3 + 0.7 * minf(1.0, float(_pop(int(f.town))) / REF_POP))
		for vid in f.vehicles:
			c += float(vehicles[vid].cost)
		for p in staff_of(f.id):
			c += float(p.wage) * Citizens.HOURS_PER_MONTH / 30.0
		x += c * share
	return x


## Sachkosten und Fahrzeugkosten je Tag aus der Stadtkasse an die Dienstleister (S0); Ressort laut Typ.
func _costs() -> void:
	for f in facilities.values():
		if f.status != "in_betrieb":
			continue
		var x := float(f.upkeep) * (0.3 + 0.7 * minf(1.0, float(_pop(int(f.town))) / REF_POP))   # kleine Orte: kleinere Wache, weniger Sachkosten
		x += VOLUNTEER_STIPEND * float(volunteers_of(f.id).size())
		for vid in f.vehicles:
			if vehicles[vid].status != "ausser_dienst":
				x += float(vehicles[vid].cost)
		var shares: Dictionary = f.get("shares", {"%d" % int(f.town): 1.0})   # Zweckverband (Regionalrat): Kosten nach Anteilen
		for sk in shares:
			sim.economy.transfer(Towns.account_of(int(sk)), "S0", x * float(shares[sk]))
		var dep: Dictionary = sim.public_sector.departments
		var ressort := str(TYPES[f.code].ressort)
		dep[ressort] = float(dep.get(ressort, 0.0)) + x
		stats.kosten = float(stats.kosten) + x


# ------------------------------------------------------------------ Aufgaben/Einsaetze
## Neue Aufgabe fuer eine Einrichtung. need_vehicles: Liste von Fahrzeugtypen (z. B. ["HLF 20"]); cell: Einsatzort.
func open_task(fid: String, kind: String, cell: Vector2i, priority: int = 1, need_staff: int = 1, need_vehicles: Array = [], data: Dictionary = {}) -> Dictionary:
	var t := {"id": _id("E"), "facility": fid, "kind": kind, "cell": [cell.x, cell.y], "priority": priority, "need_staff": need_staff,
		"need_vehicles": need_vehicles.duplicate(), "vehicles": [], "staff": [], "progress": 0.0, "status": "offen", "result": "",
		"day": _today(), "data": data}
	tasks[t.id] = t
	stats.einsaetze = int(stats.einsaetze) + 1
	return t


## Freie Fahrzeuge und Personal zuteilen. Schlaegt fehl (Aufgabe bleibt offen), wenn ein Fahrzeugtyp fehlt oder zu wenig Personal da ist.
func dispatch(tid: String, crew_ok: Callable = Callable(), pick: Array = []) -> Dictionary:
	var t: Dictionary = tasks.get(tid, {})
	if t.is_empty() or t.status != "offen":
		return {"ok": false, "msg": "Aufgabe %s ist nicht offen." % tid}
	var f: Dictionary = facilities[t.facility]
	var picked: Array = pick.duplicate()
	for vt in ([] if not pick.is_empty() else t.need_vehicles):
		var found := ""
		for vid in f.vehicles:
			var v: Dictionary = vehicles[vid]
			if str(v.type) == str(vt) and v.status == "bereit" and not picked.has(vid):
				found = vid
				break
		if found == "":
			return {"ok": false, "msg": "%s: kein freies Fahrzeug %s." % [f.name, vt]}
		picked.append(found)
	var busy := {}
	for o in tasks.values():
		if o.status == "unterwegs" and str(o.facility) == str(f.id):
			for pid in o.staff:
				busy[int(pid)] = true
	var crew: Array = (staff_of(f.id) + volunteers_of(f.id)).filter(func(p): return not busy.has(int(p.id)) and not PublicSafety.absent(p, _today()) and (not crew_ok.is_valid() or crew_ok.call(p, f)))
	if crew.size() < int(t.need_staff):
		return {"ok": false, "msg": "%s: zu wenig Personal (%d von %d)." % [f.name, crew.size(), int(t.need_staff)]}
	t.staff = crew.slice(0, int(t.need_staff)).map(func(p): return int(p.id))
	t.vehicles = picked
	for vid in picked:
		vehicles[vid].status = "im_einsatz"
		vehicles[vid].task = tid
	t.status = "unterwegs"
	return {"ok": true, "msg": "%s rückt aus." % f.name}


func finish(tid: String, result: String) -> void:
	var t: Dictionary = tasks.get(tid, {})
	if t.is_empty() or t.status in ["erledigt", "abgebrochen"]:
		return
	for vid in t.vehicles:
		if vehicles.has(vid):
			vehicles[vid].status = "bereit"
			vehicles[vid].task = ""
	t.status = "erledigt"
	t.progress = 1.0
	t.result = result
	t["done_day"] = _today()
	_prune()


func _prune() -> void:
	var closed: Array = tasks.values().filter(func(t): return t.status in ["erledigt", "abgebrochen"])
	if closed.size() <= KEEP_CLOSED_TASKS:
		return
	closed.sort_custom(func(a, b): return int(a.get("done_day", a.day)) < int(b.get("done_day", b.day)))
	for i in closed.size() - KEEP_CLOSED_TASKS:
		tasks.erase(closed[i].id)


func _cell(f: Dictionary) -> Vector2i:
	return Vector2i(int(f.cell[0]), int(f.cell[1]))


# ------------------------------------------------------------------ Uebersicht, Speichern
func summary(k: int = -1) -> Array:
	var out: Array = []
	for f in facilities.values():
		if k >= 0 and int(f.town) != k:
			continue
		var need := 0
		for b in f.staff_need:
			need += int(f.staff_need[b])
		out.append({"id": f.id, "code": f.code, "name": f.name, "stadt": sim.towns.name_of(int(f.town)), "status": f.status,
			"stil": STYLES[f.style], "personal": "%d/%d" % [staff_count(f.id), need], "ehrenamtlich": volunteers_of(f.id).size(), "fahrzeuge": f.vehicles.map(func(v): return "%s (%s)" % [vehicles[v].type, vehicles[v].status]),
			"kosten_tag": snappedf(float(f.upkeep) + f.vehicles.reduce(func(a, v): return a + float(vehicles[v].cost), 0.0), 1.0)})
	return out


func to_dict() -> Dictionary:
	return {"facilities": facilities.duplicate(true), "vehicles": vehicles.duplicate(true), "tasks": tasks.duplicate(true), "started": started,
		"regional_started": regional_started, "kit_tried": kit_tried.duplicate(),
		"stats": stats.duplicate(), "next": _next.duplicate()}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	facilities = d.get("facilities", {})
	vehicles = d.get("vehicles", {})
	tasks = d.get("tasks", {})
	started = bool(d.get("started", false))
	regional_started = bool(d.get("regional_started", false))
	kit_tried = d.get("kit_tried", {})
	stats = d.get("stats", stats)
	for k in d.get("next", {}):
		_next[k] = int(d.next[k])
	for f in facilities.values():   # Gebaeude wurden vom EventDirector neu angelegt (Rolle "customer"): Zuordnung wiederherstellen
		var b: Dictionary = sim.city.building(int(f.building))
		if not b.is_empty():
			b["role"] = "municipal"
			b["town"] = int(f.town)
			b["name"] = "%s, %s" % [f.name, sim.towns.name_of(int(f.town))]
			b["sprite"] = sprite_of(f)
