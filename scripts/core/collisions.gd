class_name Collisions
extends RefCounted
## Benedikt 18.11.2026: "kein Objekt darf durch das Objekt von einem anderen einfach durchfahren; wenn ein Auto oder ein Lkw
## zusammenstossen, muss es einen Unfall geben – das Fahrzeug ist dann kaputt; gleiches gilt, wenn es durch ein Gebaeude faehrt.
## Objekte koennen so beschaedigt werden, aber das soll die KI entscheiden, wenn sie die andere KI angreifen will."
##
## - blocked(): wer auf ein anderes Fahrzeug auffaehrt, wartet; Querverkehr: wer schon in der Kreuzung ist, hat Vorrang, sonst rechts
##   vor links; Gegenverkehr ohne eigene Spur (Gelaende-Lkw, Spur 0): der Gelaende-Lkw weicht aus (Simulation plant um).
##   Frueher fuhr man nach 6 s Blockade einfach durch – das gibt es nicht mehr.
## - check_accidents(): beruehren sich zwei Fahrzeuge trotzdem (unter CRASH Weltpixeln), ist es ein Unfall: Firmenfahrzeuge werden
##   beschaedigt und fallen aus, andere Autos bleiben eine Weile als Unfallwagen stehen.
## - Rammen (Entscheidung eines Wesens, EkoWorld "Rammen"): ram_hit() beschaedigt Ziel und eigenes Fahrzeug, die Spannung steigt.

const NEAR := 26.0          # Weltpixel: so weit voraus wird geschaut
const FOLLOW := 22.0        # Abstand zum Vordermann
const LANE := 7.0           # seitlicher Abstand, ab dem ein Fahrzeug auf einer anderen Spur ist
const CRASH := 9.0          # Beruehrung = Unfall
const WRECK_S := 90.0       # so lange steht ein verunglueckter Wagen (Sim-Sekunden)
const RAM_REACH := 22.0
const STEP_LOOK := 12.0
const JAM_S := 20.0         # gegenseitige Blockade: nach so vielen Sekunden wird aufgeloest
const OVERTAKE_S := 5.0     # so lange hinter einem stehenden Fahrzeug, dann wird ueberholt     # so weit (Weltpixel) wird der naechste Schritt vorausberechnet

var sim
var last_blocker: Mover = null
var stats := {"unfaelle": 0, "rammstoesse": 0}
var log: Array = []         # letzte Unfaelle {t, text}
var _cool := {}             # Paar-Schluessel -> sim_time (kein Doppelunfall)


func setup(simulation) -> void:
	sim = simulation


## Muss m warten? hash: Feld -> [Mover] (Simulation._hash).
func blocked(m: Mover, hash: Dictionary) -> bool:
	last_blocker = null
	if m.arrived() or m.pass_until > sim.sim_time:
		return false
	var hit := _blocked(m, hash)
	if hit and m.wait_time > JAM_S and last_blocker != null and last_blocker.wait_time > JAM_S and m.get_instance_id() < last_blocker.get_instance_id():
		m.pass_until = sim.sim_time + 3.0   # gegenseitige Blockade: der mit der kleineren Kennung loest sie kurz auf (kein Unfall)
		return false
	return hit


func _blocked(m: Mover, hash: Dictionary) -> bool:
	var nt := m.next_tile()
	var cur := m.tile()
	var right := Vector2(-m.heading.y, m.heading.x)
	var nt_c: Vector2 = sim.city.tile_center(nt)
	var seen := {}
	for t in _around(cur, nt):   # Nachbarfelder mit: das Verzeichnis ist vom Schrittbeginn, andere sind inzwischen weitergefahren
		for o in hash.get(t, []):
			if o == m or seen.has(o):
				continue
			seen[o] = true
			var rel: Vector2 = o.pos - m.pos
			var along := rel.dot(m.heading)
			if rel.length() < CRASH and m.heading.dot(o.heading) >= 0.5 and absf(rel.dot(m.heading)) < 1.5 and m.get_instance_id() > o.get_instance_id():
				last_blocker = o   # dicht auf gleicher Hoehe in gleicher Richtung: einer wartet, bis Abstand da ist
				return true
			if along <= 0.0 or rel.length() > NEAR:
				continue
			var side := absf(rel.cross(m.heading))
			var d := m.heading.dot(o.heading)
			var standing: bool = o.arrived() or _is_wreck(o)
			if standing and not _is_wreck(o) and (o.tile() == m.goal or nt == m.goal):
				continue   # Stellplatz/Rampe am eigenen Ziel: dort duerfen mehrere stehen
			if standing and m.wait_time > OVERTAKE_S:
				continue   # an stehendem Fahrzeug/Unfallwagen vorbeifahren (18.11.: Liefer-Lkw wartete ewig hinter einem ladenden Lkw)
			if standing or d >= 0.5:   # Vordermann oder stehendes Hindernis in der eigenen Spur
				if along < FOLLOW and side < LANE:
					last_blocker = o
					return true
			elif d <= -0.5:   # Gegenverkehr: nur ohne eigene Spur ein Problem
				if side < LANE * 0.8 and along < NEAR:
					if m.lane == 0.0 and (o.lane != 0.0 or m.get_instance_id() > o.get_instance_id()):
						last_blocker = o   # Gelaende-Lkw weicht aus (Simulation plant um)
						return true
			else:   # Querverkehr
				if o.pos.distance_to(nt_c) < 16.0:
					last_blocker = o   # ist schon in der Kreuzung
					return true
				if rel.dot(right) > 0.0 and along < NEAR and m.wait_time < 12.0:
					last_blocker = o   # rechts vor links (nach 12 s Patt faehrt, wer frei hat)
					return true
	return _step_hits(m, hash)


## Allgemeine Regel (Abbiegen, Spurwechsel, Einscheren): kein Schritt, der naeher als CRASH an ein anderes Fahrzeug fuehrt.
## Bei Gleichstand wartet das Fahrzeug mit der hoeheren Kennung (sonst warteten beide).
func _step_hits(m: Mover, hash: Dictionary) -> bool:
	if m.path_i >= m.path.size():
		return false
	var tgt := m.point_for(m.path_i)
	var to := tgt - m.pos
	if to.length() < 0.01:
		return false
	var np := m.pos + to.normalized() * minf(STEP_LOOK, to.length())
	var npt := Vector2i(floori(np.x / 32.0), floori(np.y / 32.0))
	var seen := {}
	for t in _around(m.tile(), npt):
		for o in hash.get(t, []):
			if o == m or seen.has(o):
				continue
			seen[o] = true
			if o.arrived() and not _is_wreck(o) and (o.tile() == m.goal or npt == m.goal):
				continue
			if (o.arrived() or _is_wreck(o)) and m.wait_time > OVERTAKE_S:
				continue   # Ueberholen eines stehenden Fahrzeugs
			var dn := np.distance_to(o.pos)
			if dn < CRASH + 1.0 and dn < m.pos.distance_to(o.pos) and (o.arrived() or _is_wreck(o) or m.get_instance_id() > o.get_instance_id()):
				last_blocker = o
				return true
	return false


func _around(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		out.append(a + d)
	if b != a:
		out.append(b)
	return out


func _is_wreck(o) -> bool:
	return o.wreck_until > sim.sim_time


## Nach der Bewegung: Beruehrungen sind Unfaelle (oder ein gewolltes Rammen).
func check_accidents(hash: Dictionary, describe: Dictionary) -> void:
	for t in hash:
		var list: Array = hash[t]
		if list.size() < 2:
			continue
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: Mover = list[i]
				var b: Mover = list[j]
				if a.pos.distance_to(b.pos) >= CRASH:
					continue
				if a.heading.dot(b.heading) <= -0.5 and absf((b.pos - a.pos).cross(a.heading)) >= 4.0:
					continue   # Gegenverkehr nebeneinander (Spurwechsel beim Abbiegen) – kein Zusammenstoss
				if a.arrived() or b.arrived() or a.tile() == a.goal or b.tile() == b.goal or _is_wreck(a) or _is_wreck(b) 						or a.pass_until > sim.sim_time or b.pass_until > sim.sim_time:
					continue   # Stellplatz, Rampe, Ziel: dort stehen Fahrzeuge dicht beieinander
				var key := "%d|%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
				if sim.sim_time - float(_cool.get(key, -999.0)) < WRECK_S * 2.0:
					continue
				_cool[key] = sim.sim_time
				if a is FleetVehicle and not (a as FleetVehicle).ram.is_empty() and int(a.ram.get("vehicle", -1)) == _vid(b):
					ram_hit(a)
				elif b is FleetVehicle and not (b as FleetVehicle).ram.is_empty() and int(b.ram.get("vehicle", -1)) == _vid(a):
					ram_hit(b)
				else:
					_accident(a, b, describe)


func _vid(m) -> int:
	return int(m.id) if m is FleetVehicle else -1


func _accident(a: Mover, b: Mover, describe: Dictionary) -> void:
	stats.unfaelle = int(stats.unfaelle) + 1
	var text := "Unfall: %s und %s stoßen zusammen" % [str(describe.get(a, "ein Fahrzeug")), str(describe.get(b, "ein Fahrzeug"))]
	for m in [a, b]:
		_damage(m, randf_range(25.0, 45.0), "Unfall")
	log.append({"t": sim.game_min, "text": text})
	if log.size() > 30:
		log.pop_front()
	sim.log_event(text + ".", "bad")


func _damage(m: Mover, dmg: float, why: String) -> void:
	m.wreck_until = sim.sim_time + WRECK_S
	if m is FleetVehicle:
		var v: FleetVehicle = m
		v.condition = maxf(0.0, float(v.condition) - dmg)
		v.ram = {}
		sim.break_vehicle(v, why)
		if sim.eko != null:
			for o in sim.eko.beings.values():
				if int(sim.eko.active_firm(o)) == int(v.owner):
					sim.eko._event(o, "%s: %s hatte einen %s (Zustand %d %%) – Werkstatt nötig." % [why, v.display_name(), why, int(v.condition)])


## Gewolltes Rammen hat getroffen: Ziel und eigenes Fahrzeug beschaedigt, Spannung zwischen den Firmen steigt.
func ram_hit(v: FleetVehicle) -> String:
	var r: Dictionary = v.ram
	v.ram = {}
	stats.rammstoesse = int(stats.rammstoesse) + 1
	var by := {"name": sim.company(int(v.owner)).company_name}
	var msg := ""
	var victim := -1
	if r.has("vehicle"):
		var t: FleetVehicle = sim.vehicles.get(int(r.vehicle))
		if t != null:
			t.wreck_until = sim.sim_time + WRECK_S
			msg = sim.eko.arms.damage_vehicle(t, 55.0, by)
			if t.state != "broken":
				sim.break_vehicle(t, "gerammt")
			victim = int(t.owner)
	elif r.has("building"):
		var bd: Dictionary = sim.city.building(int(r.building))
		if not bd.is_empty():
			msg = sim.eko.arms.damage_building(bd, 35.0, by, v.tile())
			victim = int(sim.depot_owner.get(int(r.building), -1))
	var own: String = sim.eko.arms.damage_vehicle(v, 25.0, {"name": "Rammstoß"})
	v.wreck_until = sim.sim_time + 8.0
	v.set_path([v.tile()] as Array[Vector2i])
	v.state = "idle"
	if victim >= 0 and victim != int(v.owner):
		sim.rivalry.add_tension(int(v.owner), victim, "rammen", msg)
	var text := "%s rammt: %s. Eigenes Fahrzeug: %s." % [by.name, msg, own]
	log.append({"t": sim.game_min, "text": text})
	sim.log_event(text, "bad", int(v.owner))
	return text
