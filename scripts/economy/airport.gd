class_name Airport
extends RefCounted
## Flughafen-Betrieb (Auftrag 16, Etappe E2 – Fluganimation): die Flugbewegung ist eine deterministische Funktion
## der Spielzeit. Ein kleines Flugzeug erscheint am Kartenrand, setzt auf der Startbahn auf, rollt zum Vorfeld,
## steht kurz (Abfertigung, Etappe E2-Wirtschaft setzt darauf auf) und fliegt wieder ab. Die Geometrie (Startbahn,
## Vorfeld) kommt aus city_data.airport (deterministisch aus dem Seed). Position und Hohe sind reine Funktionen der
## Spieluhr, daher bleibt der Flug bei Speichern/Laden ohne weiteren Zustand nahtlos fortlaufend.

const PERIOD := 60.0           # Spielminuten je Flugbewegung (Regelverkehr, ~30 s Echtzeit)
const EDGE_OFF := 8.0          # wie weit auessel der Karte Flugzeuge eintreffen/verschwinden (Feld)

var sim
var enabled := false
var track := {}                # {size, run_x0, run_x1, run_y, apron:[x,y]} – alles in Feld-Koordinaten


func setup(simulation) -> void:
	sim = simulation
	var a: Dictionary = sim.city.airport
	if a.is_empty():
		return
	enabled = true
	# Stehplatz: der erste genannte Vorfeldpunkt, der frei ist (die Nennpunkte können unter Gebäuden liegen),
	# sonst eine freie Vorfeldzelle in der Reihe unter den Gebäuden.
	var spot: Array = []
	for p in a.apron:
		var c := Vector2i(int(p[0]), int(p[1]))
		if sim.city.inside(c) and sim.city.building_at[sim.city.idx(c)] == -1:
			spot = [c.x, c.y]
			break
	if spot.is_empty():
		var ry: int = int(a.run_y)
		for xx in range(int(a.run_x0), int(a.run_x1) + 1):
			var c := Vector2i(xx, ry + 4)
			if sim.city.inside(c) and sim.city.g(c) == CityData.G.APRON and sim.city.building_at[sim.city.idx(c)] == -1:
				spot = [c.x, c.y]
				break
	if spot.is_empty() and not a.apron.is_empty():
		spot = [int(a.apron[0][0]), int(a.apron[0][1])]
	track = {
		"size": sim.city.size,
		"run_x0": int(a.run_x0), "run_x1": int(a.run_x1), "run_y": int(a.run_y),
		"apron": spot,
	}


## Flugzeug zu Spielzeit now: {pos: Vector2 (Feld), h: Hoehe (Feld), dir: 0..3, on_ground}. leer = nicht vorhanden.
func state(now: float) -> Dictionary:
	if not enabled:
		return {}
	var t := fmod(float(now), PERIOD) / PERIOD
	var rx0: float = float(track.run_x0)
	var rx1: float = float(track.run_x1)
	var ry: float = float(track.run_y)
	var ax: float = float(track.apron[0])
	var ay: float = float(track.apron[1])
	var edge: float = float(track.size) + EDGE_OFF
	# Key-Points [t, x, y, h]: Anflug vom Kartenrand, Touchdown, Rollen, Vorfeld (stehend), Rollen, Abflug.
	# Der letzte Punkt gleicht dem ersten, damit sich die Periode nahtlos wiederholt.
	var kp: Array = [
		[0.00, edge, ry - 14.0, 11.0],
		[0.30, rx1 + 8.0, ry - 5.0, 5.5],
		[0.42, rx1, ry, 0.0],
		[0.55, rx0 + 1.0, ry, 0.0],
		[0.65, ax, ay, 0.0],
		[0.85, ax, ay, 0.0],
		[0.90, rx0 + 1.0, ry, 0.0],
		[0.96, rx1 + 3.0, ry, 0.4],
		[1.00, edge, ry - 14.0, 11.0],
	]
	var i := 0
	while i < kp.size() - 1 and kp[i + 1][0] < t:
		i += 1
	var a_kp: Array = kp[mini(i, kp.size() - 2)]
	var b_kp: Array = kp[mini(i + 1, kp.size() - 1)]
	var k := clampf((t - a_kp[0]) / maxf(b_kp[0] - a_kp[0], 0.001), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)          # weiche Bewegung
	var x: float = float(a_kp[1]) + (float(b_kp[1]) - float(a_kp[1])) * k
	var y: float = float(a_kp[2]) + (float(b_kp[2]) - float(a_kp[2])) * k
	var h: float = float(a_kp[3]) + (float(b_kp[3]) - float(a_kp[3])) * k
	var dx: float = float(b_kp[1]) - float(a_kp[1])
	var dy: float = float(b_kp[2]) - float(a_kp[2])
	var dir: int
	if absf(dx) >= absf(dy):
		dir = 0 if dx >= 0.0 else 2
	else:
		dir = 1 if dy >= 0.0 else 3
	return {"pos": Vector2(x, y), "h": h, "dir": dir, "on_ground": h < 0.3}


## Flugbewegungen seit Beginn (Kennzahl fuer E2/E3): naehere an der Uhr, gerundet.
func movements_since_start(now: float) -> int:
	if not enabled or now <= 0.0:
		return 0
	return int(float(now) / PERIOD) + 1


## Die Startbahn als [x0, x1, y] in Feldern (fuer die Darstellung/Abnahme).
func runway() -> Array:
	return [int(track.run_x0), int(track.run_x1), int(track.run_y)] if enabled else []


func to_dict() -> Dictionary:
	return {"enabled": enabled}   # die Flugbewegung selbst ist reine Funktion der Uhr


func from_dict(_d: Dictionary) -> void:
	pass
