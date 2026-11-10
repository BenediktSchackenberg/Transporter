class_name FireService
extends RefCounted
## Feuerwehr (Auftrag 20, Etappe 4, docs/PUBLIC_SERVICES.md). Baut auf den kommunalen Einrichtungen (Municipal) auf:
##  - Brandentstehung je Tag und Gebaeude, deterministisch aus Gebaeude-ID und Tag. Ursache und Risiko haengen vom Gebaeude ab:
##    Kuechen (Restaurant, Kneipe, Baeckerei), Maschinen (Fabrik, Werkstatt), Elektrik (schlechter Gebaeudezustand), Hitze und Trockenheit.
##  - Alarm an die naechste Feuerwache der Stadt mit freiem HLF und genug Einsatzkraeften (hauptamtlich + ehrenamtlich).
##    Ausruecken: Berufsfeuerwehr 2, Freiwillige 8 Spielminuten (Anfahrt der Ehrenamtlichen zum Geraetehaus).
##  - Nachbarschaftshilfe: hat die eigene Stadt keine einsatzbereite Wache, hilft die naechste Wache einer anderen Stadt, sofern sie
##    vor dem Ausbrennen ankommt (Fahrzeit ueber die Strasse); praktisch bei Grossbraenden grosser Gebaeude, die stundenlang brennen.
##    Die anfordernde Stadt erstattet die Kosten (Stadtkasse an Stadtkasse).
##  - Das Feuer waechst, bis geloescht wird; der Schaden waechst mit der Brandstaerke. Ohne Feuerwehr brennt das Gebaeude aus.
##  - Nach dem Loeschen sinkt der Gebaeudezustand (BuildingCare) um den Schaden; ein Reparaturauftrag geht an das Handwerk (S0):
##    Dauer nach Schadenshoehe, bezahlt vom Eigentuemer (Stadtgebaeude: Stadtkasse, sonst Hausbesitzer H0). Danach ist der Zustand wieder hergestellt.
## Alle Geldfluesse sind Ueberweisungen zwischen bestehenden Konten (Geldkonservierung).

const BASE_RISK := 0.0012              # Brandwahrscheinlichkeit je Gebaeude und Tag
const RISK := {"restaurant": 2.5, "kneipe": 2.5, "disco": 2.0, "hotel": 1.5, "factory": 2.5, "workshop": 2.0, "warehouse": 1.5, "farm": 1.8,
	"freight_shed": 1.3, "gas_station": 1.5}
const CAUSE_OF := {"restaurant": "Küchenbrand", "kneipe": "Küchenbrand", "hotel": "Küchenbrand", "factory": "Maschinenbrand",
	"workshop": "Funkenflug bei Schweißarbeiten", "farm": "Selbstentzündung von Heu", "gas_station": "Kraftstoff entzündet", "warehouse": "Defekte Lagertechnik"}
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
const CREW := 2                        # Mindestbesatzung eines HLF im Spiel
const EXT_PER_CREW := 1.0              # Loeschleistung je Einsatzkraft (Brandstaerke je Spielminute)
const EXT_HLF := 3.0                   # Loeschleistung des HLF (Pumpe, Wasser)
const HELP_FEE := 1500.0               # Nachbarschaftshilfe: Pauschale an die helfende Stadt
const HELP_PER_MIN := 20.0             # ... plus je Einsatzminute
const REPAIR_PER_POINT := 350.0        # Reparaturkosten je Schadenspunkt
const CONDITION_PER_POINT := 0.8       # Zustandsverlust (BuildingCare) je Schadenspunkt
const SPEED := 3.6                     # Kacheln je Sim-Sekunde (Sonderrechte)
const KEEP_DONE := 60

var sim
var fires := {}           # "B<n>" -> {id, building, town, cause, start, intensity, damage, status, station, vehicle, task, helper, phase, ...}
var repairs := {}         # "R<n>" -> {id, building, town, fire, damage, cost, payer, until, status}
var movers := {}          # Fahrzeug-ID (Municipal) -> Mover (nur Darstellung/Fahrt, nicht gespeichert: nach dem Laden stehen alle in der Wache)
var stats := {"braende": 0, "geloescht": 0, "ausgebrannt": 0, "nachbarschaftshilfe": 0, "schaden": 0.0, "reparaturen": 0, "reparaturkosten": 0.0}
var random_fires := true  # Tests schalten zufaellige Braende ab und zuenden gezielt (ignite)
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


# ------------------------------------------------------------------ Brandentstehung
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


func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	var burning := {}
	for f in fires.values():
		if f.status == "brennt":
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
	_repairs_day(day)


## Brand in einem Gebaeude ausloesen (auch fuer Tests und Ereignisse). Alarmiert sofort die Feuerwehr.
func ignite(bid: int, cause: String = "") -> Dictionary:
	var b: Dictionary = sim.city.building(bid)
	if b.is_empty():
		return {}
	var k: int = sim.towns.of_building(bid)
	var f := {"id": _id("B"), "building": bid, "town": k, "cause": cause if cause != "" else cause_of(b), "start": sim.game_min,
		"intensity": START_INTENSITY, "damage": 0.0, "status": "brennt", "station": "", "vehicle": "", "task": "", "helper": false,
		"phase": "alarm", "alarm_at": sim.game_min, "turnout_until": 0.0, "last": sim.game_min, "name": str(b.get("name", b.type)),
		"large": str(b.type) in LARGE, "burn_out": BURN_OUT_LARGE if str(b.type) in LARGE else BURN_OUT_MIN}
	fires[f.id] = f
	stats.braende = int(stats.braende) + 1
	sim.log_event("Brand in %s (%s): %s." % [f.name, sim.towns.name_of(k), f.cause], "warn")
	sim.activity.add("stadt", -1, "stadt", "Brand: %s" % f.name, f.cause, b.road)
	_alarm(f)
	return f


# ------------------------------------------------------------------ Alarmierung
## Naechste Wache mit freiem HLF und genug Einsatzkraeften: zuerst in der eigenen Stadt, sonst Nachbarschaftshilfe.
func _alarm(f: Dictionary) -> void:
	var M: Municipal = sim.municipal
	var b: Dictionary = sim.city.building(int(f.building))
	var target: Vector2i = b.road
	var best := {}
	var best_d := INF
	var left: float = float(f.start) + float(f.get("burn_out", BURN_OUT_MIN)) - sim.game_min
	for own in [true, false]:
		for st in M.facilities.values():
			if st.code != "FW-01" or st.status != "in_betrieb" or (int(st.town) == int(f.town)) != own:
				continue
			if _free_hlf(st).is_empty() or _crew_free(st) < CREW:
				continue
			var d := eta(st, target)
			if d < best_d and (own or d < left):   # Nachbarwehr nur, wenn sie vor dem Ausbrennen ankommt
				best_d = d
				best = st
		if not best.is_empty():
			break
	if best.is_empty():
		f.phase = "wartet"
		return
	var t: Dictionary = M.open_task(best.id, "brand", target, 3, CREW, ["HLF 20"], {"brand": f.id})
	var r: Dictionary = M.dispatch(t.id)
	if not r.ok:
		M.finish(t.id, "nicht ausgerückt: " + str(r.msg))
		f.phase = "wartet"
		return
	f.station = best.id
	f.task = t.id
	f.vehicle = str(t.vehicles[0])
	f.helper = int(best.town) != int(f.town)
	var vol: bool = M.staff_count(best.id) < CREW
	f.turnout_until = sim.game_min + (TURNOUT_VOL if vol else TURNOUT_PRO)
	f.phase = "ausruecken"
	if f.helper:
		stats.nachbarschaftshilfe = int(stats.nachbarschaftshilfe) + 1
		sim.log_event("Nachbarschaftshilfe: %s (%s) rückt zum Brand in %s aus." % [best.name, sim.towns.name_of(int(best.town)), sim.towns.name_of(int(f.town))], "info")
	sim.activity.add("stadt", -1, "stadt", "%s rückt aus: %s" % [best.name, f.name], "%s%s" % [f.cause, ", Freiwillige werden alarmiert" if vol else ""], target)


## Ankunft in Spielminuten: Ausruecken + Fahrt ueber die Strasse mit Sonderrechten.
func eta(st: Dictionary, target: Vector2i) -> float:
	var vol: bool = sim.municipal.staff_count(st.id) < CREW
	var tiles: int = sim.nav.path_length(sim.city.building(int(st.building)).road, target)
	if tiles < 0:
		return INF
	return (TURNOUT_VOL if vol else TURNOUT_PRO) + float(tiles) / SPEED * Catalog.GAME_MIN_PER_SIM_SEC


func _free_hlf(st: Dictionary) -> String:
	for vid in st.vehicles:
		var v: Dictionary = sim.municipal.vehicles[vid]
		if str(v.type) == "HLF 20" and v.status == "bereit":
			return vid
	return ""


func _crew_free(st: Dictionary) -> int:
	var M: Municipal = sim.municipal
	var busy := {}
	for t in M.tasks.values():
		if t.status == "unterwegs" and str(t.facility) == str(st.id):
			for pid in t.staff:
				busy[int(pid)] = true
	var day := _today()
	return (M.staff_of(st.id) + M.volunteers_of(st.id)).filter(func(p): return not busy.has(int(p.id)) and not PublicSafety.absent(p, day)).size()


func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var v: Dictionary = M.vehicles[vid]
		var m := Mover.new()
		m.speed = SPEED
		m.pos = sim.city.tile_center(sim.city.building(M.building_of(str(v.facility))).road)
		movers[vid] = m
	return movers[vid]


# ------------------------------------------------------------------ Ablauf je Simulationsschritt
func update(dt: float) -> void:
	if fires.is_empty():
		return
	var now: float = sim.game_min
	for f in fires.values():
		if f.status != "brennt" and f.phase != "rueckfahrt":
			continue
		var mins := now - float(f.last)
		f.last = now
		if f.status == "brennt":
			_burn(f, mins)
		match str(f.phase):
			"wartet":
				if now - float(f.alarm_at) >= 10.0:
					f.alarm_at = now
					_alarm(f)            # alle 10 Spielminuten erneut alarmieren
			"ausruecken":
				if now >= float(f.turnout_until):
					f.phase = "anfahrt"
					sim.route(mover_of(f.vehicle), sim.city.building(int(f.building)).road)
			"anfahrt":
				var m := mover_of(f.vehicle)
				if m.arrived():
					f.phase = "loeschen"
					f["attack"] = now
					sim.activity.add("stadt", -1, "stadt", "Löschangriff: %s" % f.name, "Brandstärke %d" % int(f.intensity), sim.city.building(int(f.building)).road)
				else:
					m.advance(dt, 1.0)
			"loeschen":
				var crew := float(sim.municipal.tasks[f.task].staff.size())
				f.intensity = maxf(0.0, float(f.intensity) - (EXT_HLF + EXT_PER_CREW * crew) * mins)
				if float(f.intensity) <= 0.0:
					_extinguished(f, "gelöscht")
			"rueckfahrt":
				var m := mover_of(f.vehicle)
				if m.arrived():
					f.phase = "fertig"
					sim.municipal.finish(f.task, "Brand %s: %s" % [f.id, f.status])
				else:
					m.advance(dt, 1.0)


func _burn(f: Dictionary, mins: float) -> void:
	if f.phase != "loeschen":
		f.intensity = minf(100.0, float(f.intensity) + GROW_PER_MIN * mins)
	f.damage = minf(MAX_DAMAGE, float(f.damage) + DAMAGE_PER_MIN * float(f.intensity) * mins * (DAMAGE_LARGE if bool(f.get("large", false)) else 1.0))
	if f.phase in ["wartet", "ausruecken", "anfahrt"] and sim.game_min - float(f.start) >= float(f.get("burn_out", BURN_OUT_MIN)):
		f.damage = MAX_DAMAGE
		_extinguished(f, "ausgebrannt")


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
	if sim.care != null and sim.care.condition.has(bid):
		sim.care.condition[bid] = clampf(float(sim.care.condition[bid]) - float(f.damage) * CONDITION_PER_POINT, 0.0, 100.0)
	sim.log_event("%s %s (%s): Schaden %d %%. %s" % [f.name, how, sim.towns.name_of(int(f.town)), int(f.damage),
		"Löschzeit %d Minuten nach Alarm." % int(sim.game_min - float(f.start)) if how == "gelöscht" else "Keine Feuerwehr war rechtzeitig verfügbar."], "warn" if how == "ausgebrannt" else "info")
	if f.helper:
		var minutes: float = sim.game_min - float(f.start)
		var fee: float = HELP_FEE + HELP_PER_MIN * minutes
		var helper_town := int(sim.municipal.facilities[f.station].town)
		sim.economy.transfer(Towns.account_of(int(f.town)), Towns.account_of(helper_town), fee)
		f["help_fee"] = fee
	if float(f.damage) >= 1.0:
		_open_repair(f)
	if f.vehicle != "":
		f.phase = "rueckfahrt"
		var home: int = sim.municipal.building_of(str(f.station))
		sim.route(mover_of(f.vehicle), sim.city.building(home).road)
	else:
		f.phase = "fertig"
	_prune()


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
	sim.activity.add("stadt", -1, "reparatur", "Reparaturauftrag: %s" % f.name, "Brandschaden %d %%, %d Tage, %s" % [int(r.damage), int(r.until) - _today(), _eur(r.cost)],
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
		sim.log_event("Brandschaden an %s repariert (%s)." % [r.name, _eur(r.cost)], "info")


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
	return fires.values().filter(func(f): return f.status == "brennt")


func summary(k: int = -1) -> Dictionary:
	var act: Array = active().filter(func(f): return k < 0 or int(f.town) == k)
	return {"brennt": act.map(func(f): return "%s (%s, Stärke %d, Schaden %d %%, %s)" % [f.name, f.cause, int(f.intensity), int(f.damage), f.phase]),
		"reparaturen_offen": repairs.values().filter(func(r): return r.status == "offen" and (k < 0 or int(r.town) == k)).size(),
		"gesamt": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"fires": fires.duplicate(true), "repairs": repairs.duplicate(true), "stats": stats.duplicate(), "next": _next.duplicate(), "day": _day}


## Laden: laufende Einsaetze stehen in der Wache neu an (Fahrzeugposition wird nicht gespeichert): Brand wird neu alarmiert.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	fires = d.get("fires", {})
	repairs = d.get("repairs", {})
	stats = d.get("stats", stats)
	_day = int(d.get("day", -1))
	for k in d.get("next", {}):
		_next[k] = int(d.next[k])
	for f in fires.values():
		f.building = int(f.building)
		f.town = int(f.town)
		if f.phase in ["ausruecken", "anfahrt", "loeschen", "rueckfahrt"]:
			if f.task != "" and sim.municipal.tasks.has(f.task):
				sim.municipal.finish(f.task, "nach dem Laden neu alarmiert")
			f.vehicle = ""
			f.task = ""
			if f.status == "brennt":
				f.phase = "wartet"
				f.alarm_at = 0.0
			else:
				f.phase = "fertig"
	for r in repairs.values():
		r.building = int(r.building)
		r.until = int(r.until)
