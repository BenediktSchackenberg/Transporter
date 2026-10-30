class_name TrafficFlow
extends RefCounted
## Verkehr mit Kapazitaet (Auftrag 5, Abschnitt 5): Jede Strassenzelle fasst nur wenige Fahrzeuge, Kreuzungen weniger.
## Ist eine Zelle ueberfuellt, fahren alle Fahrzeuge darin langsamer (Rueckstau entsteht von selbst, die Zeit geht tatsaechlich verloren).
## Gemessen werden verlorene Fahrzeugsekunden je Zelle und Tageszeit sowie die mittlere Geschwindigkeit. Die Daten sind Diagnose und werden nicht gespeichert.

const ROAD_CAPACITY := 3            # Fahrzeuge je Strassenzelle
const JUNCTION_CAPACITY := 2        # Fahrzeuge je Kreuzung/Einmuendung
const MIN_FACTOR := 0.2             # so langsam wird ein Fahrzeug im dichtesten Stau hoechstens
const RECURRING_DAYS := 3           # so viele Tage mit Stau in derselben Zelle gelten als wiederkehrender Engpass
const JUNCTION_MASKS := [7, 11, 13, 14, 15]

var sim: Simulation
var lost_by_cell := {}              # Vector2i -> verlorene Fahrzeugsekunden insgesamt
var jam_days := {}                  # Vector2i -> Tage, an denen die Zelle ueberfuellt war
var lost_by_hour := PackedFloat32Array()
var moving_by_hour := PackedFloat32Array()   # Fahrzeugsekunden in Bewegung je Tageszeit
var lost_total := 0.0
var moving_total := 0.0
var _today := {}                    # Vector2i -> true, heute ueberfuellt
var _day := 0


func _init() -> void:
	lost_by_hour.resize(24)
	moving_by_hour.resize(24)


func setup(s: Simulation) -> void:
	sim = s
	_day = GameCalendar.day_of(s.game_min)


func capacity_of(cell: Vector2i) -> int:
	return JUNCTION_CAPACITY if sim.city.road_mask(cell) in JUNCTION_MASKS else ROAD_CAPACITY


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
