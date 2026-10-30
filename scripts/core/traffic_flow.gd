class_name TrafficFlow
extends RefCounted
## Verkehr mit Kapazitaet (Auftrag 5, Abschnitt 5): Jede Strassenzelle fasst nur wenige Fahrzeuge, Kreuzungen weniger.
## Ist eine Zelle ueberfuellt, fahren alle Fahrzeuge darin langsamer (Rueckstau entsteht von selbst, die Zeit geht tatsaechlich verloren).
## Gemessen werden verlorene Fahrzeugsekunden je Zelle und Tageszeit sowie die mittlere Geschwindigkeit. Gespeichert werden Massnahmen, Ausbaustufen und die staerksten Engpaesse.

const ROAD_CAPACITY := 3            # Fahrzeuge je Strassenzelle
const JUNCTION_CAPACITY := 2        # Fahrzeuge je Kreuzung/Einmuendung
const MIN_FACTOR := 0.2             # so langsam wird ein Fahrzeug im dichtesten Stau hoechstens
const RECURRING_DAYS := 3           # so viele Tage mit Stau in derselben Zelle gelten als wiederkehrender Engpass
const JUNCTION_MASKS := [7, 11, 13, 14, 15]
const MAX_BONUS := 2                # so viele Ausbauten verkraftet eine Zelle
const MEASURES := {
	"ampel": {"label": "Ampelsteuerung verbessern", "cost": 12000.0, "days": 2, "junction": true},
	"ausbau": {"label": "Strassenabschnitt ausbauen", "cost": 40000.0, "days": 6, "junction": false},
}

var sim: Simulation
var lost_by_cell := {}              # Vector2i -> verlorene Fahrzeugsekunden insgesamt
var jam_days := {}                  # Vector2i -> Tage, an denen die Zelle ueberfuellt war
var lost_by_hour := PackedFloat32Array()
var moving_by_hour := PackedFloat32Array()   # Fahrzeugsekunden in Bewegung je Tageszeit
var lost_total := 0.0
var moving_total := 0.0
var bonus := {}                     # Vector2i -> zusaetzliche Kapazitaet durch fertige Massnahmen
var measures := {}                  # "V<n>" -> Verkehrsmassnahme der Buergermeisterebene (siehe propose)
var _next := 1
var _today := {}                    # Vector2i -> true, heute ueberfuellt
var _day := 0


func _init() -> void:
	lost_by_hour.resize(24)
	moving_by_hour.resize(24)


func setup(s: Simulation) -> void:
	sim = s
	_day = GameCalendar.day_of(s.game_min)


func capacity_of(cell: Vector2i) -> int:
	var cap := base_capacity(cell) + int(bonus.get(cell, 0))
	if _under_works(cell):
		cap = maxi(1, cap - 1)   # waehrend der Bauarbeiten steht eine Spur weniger zur Verfuegung
	return cap


func base_capacity(cell: Vector2i) -> int:
	return JUNCTION_CAPACITY if is_junction(cell) else ROAD_CAPACITY


func is_junction(cell: Vector2i) -> bool:
	return sim.city.road_mask(cell) in JUNCTION_MASKS


func _under_works(cell: Vector2i) -> bool:
	for m in measures.values():
		if m.status == "im_bau" and m.kind == "ausbau" and m.cell == cell:
			return true
	return false


## Tempofaktor (0.2..1) fuer ein Fahrzeug auf der Zelle; 1.0 solange die Kapazitaet reicht.
func factor(cell: Vector2i) -> float:
	var n: int = sim._hash.get(cell, []).size()
	var cap := capacity_of(cell)
	if n <= cap:
		return 1.0
	return maxf(MIN_FACTOR, float(cap) / float(n))


## Verbucht einen Schritt eines fahrenden Fahrzeugs: verlorene Zeit = dt * (1 - Faktor).
func record(cell: Vector2i, f: float, dt: float) -> void:
	var hour := int(fposmod(sim.game_min, 1440.0) / 60.0)
	moving_total += dt
	moving_by_hour[hour] += dt
	if f >= 1.0:
		return
	var lost := dt * (1.0 - f)
	lost_total += lost
	lost_by_hour[hour] += lost
	lost_by_cell[cell] = float(lost_by_cell.get(cell, 0.0)) + lost
	_today[cell] = true


func on_day() -> void:
	var day := GameCalendar.day_of(sim.game_min)
	if day == _day:
		return
	_day = day
	_progress(day)
	for cell in _today:
		jam_days[cell] = int(jam_days.get(cell, 0)) + 1
	_today.clear()


## Mittlere Geschwindigkeit als Anteil der freien Fahrt (1.0 = kein Zeitverlust).
func avg_speed() -> float:
	return 1.0 if moving_total <= 0.0 else 1.0 - lost_total / moving_total


## Anteil verlorener Zeit nach Tageszeit (0..1), 24 Werte.
func delay_by_hour() -> Array:
	var out: Array = []
	for h in 24:
		out.append(0.0 if moving_by_hour[h] <= 0.0 else lost_by_hour[h] / moving_by_hour[h])
	return out


## Zellen mit dem groessten Zeitverlust: [{cell, lost, days, recurring}]
func hotspots(n: int = 5) -> Array:
	var cells: Array = lost_by_cell.keys()
	cells.sort_custom(func(a, b): return lost_by_cell[a] > lost_by_cell[b])
	var out: Array = []
	for c in cells.slice(0, n):
		var days: int = jam_days.get(c, 0)
		out.append({"cell": c, "lost": lost_by_cell[c], "days": days, "recurring": days >= RECURRING_DAYS})
	return out


## Verkehrsmassnahme der Buergermeisterebene: begruendet durch einen wiederkehrenden Engpass, bezahlt aus der Stadtkasse (Mittel werden
## reserviert), wirksam erst nach der Bauzeit. Ein einzelner kurzer Stau rechtfertigt keine Massnahme.
func propose(kind: String, cell: Vector2i, reason: String) -> Dictionary:
	if not MEASURES.has(kind):
		return {"ok": false, "msg": "Unbekannte Massnahme %s (ampel oder ausbau)." % kind}
	var spec: Dictionary = MEASURES[kind]
	if not sim.city.is_road(cell):
		return {"ok": false, "msg": "Auf (%d,%d) liegt keine Strasse." % [cell.x, cell.y]}
	if spec.junction and not is_junction(cell):
		return {"ok": false, "msg": "Ampelsteuerung gibt es nur an Kreuzungen; (%d,%d) ist keine." % [cell.x, cell.y]}
	if int(jam_days.get(cell, 0)) < RECURRING_DAYS:
		return {"ok": false, "msg": "Kein wiederkehrender Engpass auf (%d,%d): Stau an %d Tagen, nötig sind %d. Ein einzelner Stau rechtfertigt keinen Ausbau." % [cell.x, cell.y, int(jam_days.get(cell, 0)), RECURRING_DAYS]}
	if int(bonus.get(cell, 0)) >= MAX_BONUS:
		return {"ok": false, "msg": "Die Zelle ist bereits ausgebaut (Höchststufe)."}
	for m in measures.values():
		if m.cell == cell and m.status == "im_bau":
			return {"ok": false, "msg": "Auf (%d,%d) wird schon gebaut (%s)." % [cell.x, cell.y, m.id]}
	var cost: float = spec.cost
	if cost > sim.mayor.available_budget():
		return {"ok": false, "msg": "Kosten %s übersteigen die verfügbaren Mittel %s." % [Catalog.money(cost), Catalog.money(sim.mayor.available_budget())]}
	sim.mayor.commitments += cost
	var day := GameCalendar.day_of(sim.game_min)
	var m := {"id": "V%d" % _next, "kind": kind, "cell": cell, "cost": cost, "status": "im_bau", "start_day": day, "finish_day": day + int(spec.days),
		"reason": reason.left(240), "lost_start": float(lost_by_cell.get(cell, 0.0)), "lost_finish": 0.0, "factor_before": avg_speed()}
	_next += 1
	measures[m.id] = m
	return {"ok": true, "msg": "%s auf (%d,%d): %s reserviert, fertig in %d Tagen." % [spec.label, cell.x, cell.y, Catalog.money(cost), int(spec.days)], "ref": m.id}


func _progress(day: int) -> void:
	for m in measures.values():
		if m.status != "im_bau" or day < int(m.finish_day):
			continue
		m.status = "fertig"
		m.lost_finish = float(lost_by_cell.get(m.cell, 0.0))
		m.done_day = day
		bonus[m.cell] = int(bonus.get(m.cell, 0)) + 1
		sim.mayor.commitments = maxf(0.0, sim.mayor.commitments - float(m.cost))
		sim.economy.transfer("P0", "S0", float(m.cost))   # Bezahlung der Baufirmen und Materiallieferanten
		sim.log_event("Verkehrsmassnahme %s fertig: %s auf (%d,%d), Kapazität dort jetzt %d." % [m.id, MEASURES[m.kind].label, m.cell.x, m.cell.y, capacity_of(m.cell)], "good")


## Vorher/Nachher einer Massnahme: verlorene Fahrzeugsekunden je Tag auf der Zelle.
func effect(m: Dictionary) -> Dictionary:
	var day := GameCalendar.day_of(sim.game_min)
	var before := float(m.lost_start) / maxf(1.0, float(m.start_day))
	if m.status != "fertig":
		return {"vorher": before, "nachher": -1.0, "tage": 0}
	var days := day - int(m.done_day)
	var after := -1.0
	if days >= 1:
		after = (float(lost_by_cell.get(m.cell, 0.0)) - float(m.lost_finish)) / float(days)
	return {"vorher": before, "nachher": after, "tage": days}


func to_dict() -> Dictionary:
	var top: Array = lost_by_cell.keys()
	top.sort_custom(func(a, b): return lost_by_cell[a] > lost_by_cell[b])
	var lost := {}
	var days := {}
	for c in top.slice(0, 200):
		lost["%d,%d" % [c.x, c.y]] = snappedf(lost_by_cell[c], 0.1)
		if jam_days.has(c):
			days["%d,%d" % [c.x, c.y]] = jam_days[c]
	var bo := {}
	for c in bonus:
		bo["%d,%d" % [c.x, c.y]] = bonus[c]
	var ms := {}
	for id in measures:
		var m: Dictionary = measures[id].duplicate()
		m.cell = [m.cell.x, m.cell.y]
		ms[id] = m
	return {"lost": lost, "days": days, "bonus": bo, "measures": ms, "next": _next, "lost_total": lost_total, "moving_total": moving_total}


static func _cell_of(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in d.get("lost", {}):
		lost_by_cell[_cell_of(k)] = float(d.lost[k])
	for k in d.get("days", {}):
		jam_days[_cell_of(k)] = int(d.days[k])
	for k in d.get("bonus", {}):
		bonus[_cell_of(k)] = int(d.bonus[k])
	for id in d.get("measures", {}):
		var m: Dictionary = d.measures[id].duplicate()
		m.cell = Vector2i(int(m.cell[0]), int(m.cell[1]))
		measures[id] = m
	_next = int(d.get("next", 1))
	lost_total = float(d.get("lost_total", 0.0))
	moving_total = float(d.get("moving_total", 0.0))
	_day = GameCalendar.day_of(sim.game_min)
