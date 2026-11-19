class_name EkoConflict
extends RefCounted
## Entscheidungen zwischen Unternehmern: Frieden, Schutz oder Krieg. Rekrutierte
## Mitarbeiter bleiben echte Worker; Waffen stammen aus der eigenen Schmiede.

const MAX_TROOPS := 6
const HIT_INTERVAL := 2.0
const EQUIP_COST := 250.0

var w
var strategies := {}  # Firmen-ID -> {form, wirtschaft, haltung, rival, begruendung}
var troops := {}      # Worker-ID -> {cid, weapon, mode, target, hit_left}
var assaults := {}    # Angreifer-ID -> {target, stadt, ziel, status, seit}
var defeated := {}    # Firmen-ID -> {by, zeit}
var fires: Array = [] # {feld, left, staerke}
var wall_damage := {} # Stadt-ID -> kumulierter Schaden bis zum sichtbaren Durchbruch


func setup(world) -> void:
	w = world


func strategy(cid: int) -> Dictionary:
	return strategies.get(str(cid), {"form": "", "wirtschaft": "", "haltung": "frieden", "rival": -1, "begruendung": ""})


func strategy_for_town(k: int) -> Dictionary:
	if w == null:
		return {}
	for c in w.sim.companies:
		if c.home_town == k and strategies.has(str(c.id)):
			return strategy(c.id)
	return {}


func has_worker(worker_id: String) -> bool:
	return troops.has(worker_id)


func action(b: Dictionary, cid: int, a: Dictionary) -> Dictionary:
	match str(a.action):
		"set_city_strategy":
			var old := strategy(cid).duplicate()
			var form := str(a.get("form", old.form))
			var posture := str(a.get("haltung", old.haltung))
			if form != "" and not TownPlan.FORMS.has(form):
				return {"ok": false, "msg": "form: %s" % ", ".join(TownPlan.FORMS.keys())}
			if posture not in ["frieden", "verteidigung", "krieg"]:
				return {"ok": false, "msg": "haltung: frieden, verteidigung oder krieg."}
			var rival := int(a.get("rival", old.rival))
			if rival == cid or rival >= w.sim.companies.size():
				return {"ok": false, "msg": "rival muss die ID einer anderen Firma oder -1 sein."}
			old.form = form
			old.haltung = posture
			old.rival = rival
			old.wirtschaft = str(a.get("wirtschaft", old.wirtschaft)).left(100)
			old.begruendung = str(a.get("begruendung", old.begruendung)).left(180)
			strategies[str(cid)] = old
			if posture != "krieg" and assaults.has(str(cid)):
				_retreat(cid)
			var k: int = w.sim.company(cid).home_town
			if form != "" and w.sim.town_plan.has(k):
				return {"ok": true, "msg": "Strategie gespeichert. Die bestehende Stadtform bleibt erhalten; künftige Entscheidungen sehen deine Absicht."}
			return {"ok": true, "msg": "Strategie gespeichert. Die Stadtform wird bei der Gründung berücksichtigt."}
		"mobilize_worker":
			return _mobilize(cid, str(a.get("worker_id", "")), str(a.get("weapon", "")))
		"demobilize_worker":
			return _demobilize(cid, str(a.get("worker_id", "")))
		"order_assault":
			return _assault(cid, int(a.get("target", -1)), str(a.get("asset", "")))
		"order_retreat":
			return _retreat(cid)
	return {"ok": false, "msg": "Unbekannte Konfliktaktion."}


func _mobilize(cid: int, worker_id: String, weapon: String) -> Dictionary:
	var worker: Worker = w.sim.personnel.workers.get(worker_id)
	if worker == null or worker.employer != cid or worker.lost or worker.role != "worker":
		return {"ok": false, "msg": "worker_id muss ein verfügbarer eigener Mitarbeiter sein."}
	var current_task: WorkerTask = w.sim.personnel.tasks.get(worker.task_id)
	if troops.has(worker_id) or worker.vehicle_id >= 0 or (current_task != null and not current_task.is_final() and not current_task.is_filler() and current_task.kind != "gehen"):
		return {"ok": false, "msg": "%s ist bereits im Einsatz oder unterwegs." % worker.name}
	if troops.values().filter(func(t): return int(t.cid) == cid).size() >= MAX_TROOPS:
		return {"ok": false, "msg": "Höchstens %d Mitarbeiter können gleichzeitig mobilisiert sein." % MAX_TROOPS}
	var item := {}
	if weapon != "":
		var stock: Array = w.arms.arsenal.get(str(cid), [])
		for it in stock:
			if str(it.design) == weapon and str(w.arms.designs.get(weapon, {}).get("typ", "")) in ["nahkampf", "fernkampf"]:
				item = it
				break
		if item.is_empty():
			return {"ok": false, "msg": "Diese Waffe ist nicht im Arsenal. Baue eine laufende Waffenschmiede, entwirf und fertige sie zuerst."}
	var c: Company = w.sim.company(cid)
	if c.ledger.cash < EQUIP_COST + EkoWorld.FIRM_RESERVE:
		return {"ok": false, "msg": "Ausrüstung kostet %s; die Firmenreserve bleibt erhalten." % Catalog.money(EQUIP_COST)}
	c.ledger.book("security", -EQUIP_COST, true, "Mobilisierung %s" % worker.name, w.sim.game_min, "K0")
	if current_task != null and not current_task.is_final():
		current_task.status = "abgebrochen"
		current_task.report = "für Stadtschutz mobilisiert"
	worker.task_id = ""
	worker.path.clear()
	if not item.is_empty():
		(w.arms.arsenal[str(cid)] as Array).erase(item)
	troops[worker_id] = {"cid": cid, "weapon": item, "mode": "schutz", "target": -1, "hit_left": HIT_INTERVAL}
	worker.duty_label = "Stadtwache" if item.is_empty() else "Stadtwache (%s)" % weapon
	w.sim.log_event("%s mobilisiert %s zur Verteidigung von %s." % [c.company_name, worker.name, w.sim.towns.name_of(c.home_town)], "info", cid)
	w.changed.emit()
	return {"ok": true, "msg": "%s ist mobilisiert. %s" % [worker.name, "Unbewaffnet – für einen Angriff braucht er eine Waffe aus der Waffenschmiede." if item.is_empty() else "Waffe: %s." % weapon]}


func _demobilize(cid: int, worker_id: String) -> Dictionary:
	if not troops.has(worker_id) or int(troops[worker_id].cid) != cid:
		return {"ok": false, "msg": "Dieser Mitarbeiter gehört nicht zu deiner Truppe."}
	_release(worker_id)
	return {"ok": true, "msg": "Mitarbeiter aus dem Dienst entlassen; Waffe zurück im Arsenal."}


func _release(worker_id: String) -> void:
	var t: Dictionary = troops.get(worker_id, {})
	if t.is_empty():
		return
	var worker: Worker = w.sim.personnel.workers.get(worker_id)
	if worker != null:
		worker.path.clear()
		worker.duty_label = ""
		if worker.health <= 0.0:
			worker.health = 20.0
			worker.rest_until = w.sim.game_min + GameCalendar.days_to_min(1)
	if not (t.weapon as Dictionary).is_empty() and worker != null and not worker.lost:
		var stock: Array = w.arms.arsenal.get(str(t.cid), [])
		stock.append(t.weapon)
		w.arms.arsenal[str(t.cid)] = stock
	troops.erase(worker_id)
	w.changed.emit()


func _assault(cid: int, target: int, asset: String) -> Dictionary:
	if str(strategy(cid).haltung) != "krieg":
		return {"ok": false, "msg": "Angriff nur mit Haltung krieg. Frieden und Verteidigung erlauben keine Offensive."}
	if target < 0 or target >= w.sim.companies.size() or target == cid or defeated.has(str(target)):
		return {"ok": false, "msg": "target muss eine aktive gegnerische Firma sein."}
	var enemy: Company = w.sim.company(target)
	var own: Company = w.sim.company(cid)
	if not enemy.is_active() or not w.sim.town_ready(enemy.home_town) or not w.sim.town_ready(own.home_town) or enemy.home_town == own.home_town:
		return {"ok": false, "msg": "Beide Firmen brauchen eine eigene gegründete Stadt."}
	if asset != "" and _asset_building(target, asset).is_empty() and _asset_vehicle(target, asset) == null and _asset_tower(target, asset).is_empty():
		return {"ok": false, "msg": "asset muss ein Gebäude der gegnerischen Stadt, kraftwerk, ein gegnerisches Fahrzeug oder ein Wachturm sein."}
	var armed := troops.keys().filter(func(id): return int(troops[id].cid) == cid and not (troops[id].weapon as Dictionary).is_empty())
	if armed.is_empty():
		return {"ok": false, "msg": "Mobilisiere mindestens einen Mitarbeiter mit einer Waffe aus deiner Waffenschmiede."}
	var center: Vector2i = w.sim.towns.list[enemy.home_town].center
	var named: Dictionary = _asset_building(target, asset) if asset != "" else {}
	if not named.is_empty():
		center = Vector2i(int(named.walk.x), int(named.walk.y))
	var vehicle = _asset_vehicle(target, asset) if asset != "" else null
	if vehicle != null:
		if str(vehicle.state) not in ["idle", "broken", "repairing"]:
			return {"ok": false, "msg": "Fahrzeugziele müssen stehen. Ein fahrender LKW ist kein festes Belagerungsziel."}
		center = vehicle.tile()
	var tower: Dictionary = _asset_tower(target, asset)
	if not tower.is_empty():
		center = Vector2i(int(tower.feld[0]), int(tower.feld[1]))
	var start: Vector2i = w.sim.towns.list[own.home_town].center
	var approach := _approach(center, start, [3, 5, 7]) if vehicle != null else _approach(center, start)
	var sent := 0
	for id in armed:
		var worker: Worker = w.sim.personnel.workers.get(str(id))
		if worker == null or worker.health <= 0.0:
			continue
		var path: Array[Vector2i] = w.sim.nav.walk_path(worker.tile(), approach)
		if path.is_empty():
			continue
		worker.set_path(path)
		troops[id].mode = "angriff"
		troops[id].target = target
		sent += 1
	if sent == 0:
		return {"ok": false, "msg": "Kein Fußweg zur gegnerischen Stadt. Prüfe Straßen und Stadtmauern."}
	assaults[str(cid)] = {"target": target, "stadt": enemy.home_town, "ziel": [approach.x, approach.y], "asset": asset, "status": "anruecken", "seit": w.sim.game_min}
	w.sim.log_event("%s rückt mit %d Bewaffneten gegen %s vor. %s kann Wachen mobilisieren und Mauern oder Wachtürme bauen." % [own.company_name, sent, w.sim.towns.name_of(enemy.home_town), enemy.company_name], "bad", cid)
	for b in w.beings.values():
		if int(b.get("firma", -1)) == target or int(b.get("amt", -1)) == enemy.home_town:
			w._event(b, "Alarm: %s greift deine Stadt an!" % own.company_name)
	w.changed.emit()
	return {"ok": true, "msg": "%d Bewaffnete marschieren sichtbar auf %s zu. Der Gegner wurde alarmiert." % [sent, enemy.company_name]}


func _approach(center: Vector2i, start: Vector2i, radii: Array = [29, 35, 42, 48]) -> Vector2i:
	var dir := Vector2(start - center).normalized()
	for radius in radii:
		var p := center + Vector2i(roundi(dir.x * radius), roundi(dir.y * radius))
		if w.sim.city.inside(p) and not w.sim.nav.walk.is_point_solid(p):
			return p
	return center


func _asset_building(target: int, asset: String) -> Dictionary:
	if asset == "":
		return {}
	if asset == "kraftwerk":
		return w.sim.city.building(w.sim.plant.building)   # gemeinsame Anlage: ein Angriff trifft alle Staedte, auch die eigene
	var bd: Dictionary = w.arms._building_by(asset)
	if bd.is_empty() or w.sim.towns.of_building(int(bd.id)) != w.sim.company(target).home_town:
		return {}
	return bd


func _asset_vehicle(target: int, asset: String):
	if not asset.begins_with("fahrzeug_"):
		return null
	var vid := asset.trim_prefix("fahrzeug_")
	if not vid.is_valid_int():
		return null
	var vehicle = w.sim.vehicles.get(int(vid))
	return vehicle if vehicle != null and int(vehicle.owner) == target else null


func _asset_tower(target: int, asset: String) -> Dictionary:
	if not asset.begins_with("wachturm_"):
		return {}
	var index := asset.trim_prefix("wachturm_")
	if not index.is_valid_int() or int(index) < 0 or int(index) >= w.arms.towers.size():
		return {}
	var tower: Dictionary = w.arms.towers[int(index)]
	return tower if int(tower.stadt) == w.sim.company(target).home_town else {}


func _retreat(cid: int) -> Dictionary:
	if not assaults.has(str(cid)):
		return {"ok": false, "msg": "Kein eigener Angriff läuft."}
	assaults.erase(str(cid))
	for id in troops:
		if int(troops[id].cid) == cid and str(troops[id].mode) == "angriff":
			troops[id].mode = "schutz"
			troops[id].target = -1
			var worker: Worker = w.sim.personnel.workers.get(str(id))
			if worker != null:
				worker.path.clear()
	w.sim.log_event("%s zieht die Angreifer zurück." % w.sim.company(cid).company_name, "info", cid)
	return {"ok": true, "msg": "Angriff abgebrochen. Die Truppe bleibt zur Verteidigung mobilisiert."}


func tick(dt: float) -> void:
	for f in fires.duplicate():
		f.left = float(f.left) - dt
		if float(f.left) <= 0.0:
			fires.erase(f)
	for id in troops.keys().duplicate():
		var worker: Worker = w.sim.personnel.workers.get(str(id))
		if worker == null or worker.lost or worker.employer != int(troops[id].cid) or not w.sim.company(int(troops[id].cid)).is_active():
			_release(str(id))
			continue
		if not worker.arrived():
			worker.advance(dt, 1.0)
	for key in assaults.keys().duplicate():
		_tick_assault(int(key), dt)


func _tick_assault(cid: int, dt: float) -> void:
	var a: Dictionary = assaults.get(str(cid), {})
	if a.is_empty():
		return
	var target: int = int(a.target)
	if not w.sim.company(target).is_active():
		_retreat(cid)
		return
	var attackers := troops.keys().filter(func(id): return int(troops[id].cid) == cid and str(troops[id].mode) == "angriff")
	if attackers.is_empty():
		_retreat(cid)
		return
	var arrived := attackers.filter(func(id): return (w.sim.personnel.workers.get(str(id)) as Worker).arrived())
	if arrived.is_empty():
		return
	if not _wall_intact(int(a.stadt)):
		var objective: Vector2i = _objective_cell(target, a)
		var key := "%d,%d" % [objective.x, objective.y]
		if str(a.get("objective", "")) != key:
			a.objective = key
			a.inside = false
		if not bool(a.get("inside", false)):
			var moved := 0
			for id in arrived:
				var worker: Worker = w.sim.personnel.workers.get(str(id))
				var path: Array[Vector2i] = w.sim.nav.walk_path(worker.tile(), objective)
				if not path.is_empty():
					worker.set_path(path)
					moved += 1
			if moved == 0:
				a.status = "blockiert"
				return
			a.inside = true
			a.status = "vordringen"
			return
	a.status = "gefecht"
	var k: int = int(a.stadt)
	var defense: Array = troops.keys().filter(func(id): return int(troops[id].cid) == target)
	if defense.is_empty(): # Auch eine friedliche Firma darf sich gegen einen Angriff schuetzen.
		for worker in w.sim.personnel.employed(target):
			if worker.role == "worker" and worker.vehicle_id < 0 and not troops.has(worker.id):
				var raised: Dictionary = _mobilize(target, worker.id, "")
				if bool(raised.get("ok", false)):
					var guard_path: Array[Vector2i] = w.sim.nav.walk_path(worker.tile(), Vector2i(int(a.ziel[0]), int(a.ziel[1])))
					if not guard_path.is_empty():
						worker.set_path(guard_path)
					break
		defense = troops.keys().filter(func(id): return int(troops[id].cid) == target)
	var towers: int = w.arms.towers.filter(func(t): return int(t.stadt) == k).size()
	var wall: bool = _wall_intact(k)
	for id in arrived:
		var t: Dictionary = troops[id]
		var soldier: Worker = w.sim.personnel.workers.get(str(id))
		t.hit_left = float(t.hit_left) - dt
		if float(t.hit_left) > 0.0:
			continue
		t.hit_left = HIT_INTERVAL
		if soldier == null:
			continue
		var counter: float = (float(defense.size()) * 5.0 + float(towers) * 8.0) / maxf(1.0, float(arrived.size()))
		if wall:
			counter += 2.0
		soldier.health = maxf(0.0, soldier.health - counter)
		if soldier.health <= 0.0:
			w.sim.log_event("%s wurde bei %s außer Gefecht gesetzt." % [soldier.name, w.sim.towns.name_of(k)], "bad", cid)
			_release(str(id))
			continue
		if not defense.is_empty():
			var guard: Worker = w.sim.personnel.workers.get(str(defense[0]))
			if guard != null:
				guard.health = maxf(0.0, guard.health - _power(t))
				if guard.health <= 0.0:
					w.sim.log_event("Stadtwache %s wurde außer Gefecht gesetzt." % guard.name, "bad", target)
					_release(str(defense[0]))
					defense.pop_front()
			continue
		_damage_city(cid, target, k, t, soldier.tile(), a)
		if not assaults.has(str(cid)):
			return


func _objective_cell(target: int, assault: Dictionary) -> Vector2i:
	var asset := str(assault.get("asset", ""))
	var vehicle = _asset_vehicle(target, asset)
	if vehicle != null:
		return vehicle.tile()
	var tower: Dictionary = _asset_tower(target, asset)
	if not tower.is_empty():
		return Vector2i(int(tower.feld[0]), int(tower.feld[1]))
	var named: Dictionary = _asset_building(target, asset)
	if not named.is_empty():
		return Vector2i(int(named.walk.x), int(named.walk.y))
	var c: Company = w.sim.company(target)
	if not c.depots.is_empty() and w.arms.condition_of(int(c.depots[0])) > 0.0:
		var depot: Dictionary = w.sim.city.building(int(c.depots[0]))
		if not depot.is_empty():
			return Vector2i(int(depot.walk.x), int(depot.walk.y))
	var hall: Dictionary = w.sim.city.building(int(w.sim.towns.list[int(assault.stadt)].town_hall))
	return Vector2i(int(hall.walk.x), int(hall.walk.y)) if not hall.is_empty() else w.sim.towns.list[int(assault.stadt)].center


func _power(t: Dictionary) -> float:
	var item: Dictionary = t.weapon
	var d: Dictionary = w.arms.designs.get(str(item.get("design", "")), {})
	return maxf(3.0, float(d.get("schaden", 6)) * 0.35)


func _damage_city(cid: int, target: int, k: int, t: Dictionary, from: Vector2i, assault: Dictionary) -> void:
	if _wall_intact(k):
		wall_damage[str(k)] = float(wall_damage.get(str(k), 0.0)) + _power(t)
		if float(wall_damage[str(k)]) >= 120.0:
			_breach_wall(k, from)
		return
	var asset := str(assault.get("asset", ""))
	var vehicle = _asset_vehicle(target, asset)
	if vehicle != null:
		var hit: String = w.arms.damage_vehicle(vehicle, _power(t), {"name": w.sim.company(cid).company_name})
		if hit.contains("zerstört"):
			var p: Vector2i = vehicle.tile()
			fires.append({"feld": [p.x, p.y], "left": 20.0, "staerke": 0.7})
			_retreat(cid)
		return
	var tower: Dictionary = _asset_tower(target, asset)
	if not tower.is_empty():
		tower["hp"] = maxf(0.0, float(tower.get("hp", 80.0)) - _power(t))
		if float(tower.hp) <= 0.0:
			var tp := Vector2i(int(tower.feld[0]), int(tower.feld[1]))
			w.arms.towers.erase(tower)
			fires.append({"feld": [tp.x, tp.y], "left": 20.0, "staerke": 0.8})
			w.arms.blasts.append({"feld": [tp.x, tp.y], "ms": Time.get_ticks_msec(), "radius": 2, "atom": false})
			w.sim.log_event("Wachturm bei %d,%d zerstört – die Stadt hat dort keinen Schutz mehr." % [tp.x, tp.y], "bad", target)
			w.changed.emit()
			_retreat(cid)
		return
	var hall_id: int = int(w.sim.towns.list[k].town_hall)
	var hall: Dictionary = w.sim.city.building(hall_id)
	var depot_id: int = int(w.sim.company(target).depots[0]) if not w.sim.company(target).depots.is_empty() else -1
	var depot: Dictionary = w.sim.city.building(depot_id)
	var named: Dictionary = _asset_building(target, asset)
	var bd: Dictionary = named if not named.is_empty() else (depot if not depot.is_empty() and w.arms.condition_of(depot_id) > 0.0 else hall)
	if bd.is_empty():
		return
	if w.arms.condition_of(int(bd.id)) <= 0.0:
		if not named.is_empty():
			_retreat(cid)
		return
	var dmg := _power(t)
	var result: String = w.arms.damage_building(bd, dmg, {"name": w.sim.company(cid).company_name}, from)
	if result.contains("zerstört"):
		var p := Vector2i(int(bd.walk.x), int(bd.walk.y))
		fires.append({"feld": [p.x, p.y], "left": 25.0, "staerke": 1.0})
		w.arms.blasts.append({"feld": [p.x, p.y], "ms": Time.get_ticks_msec(), "radius": 2, "atom": false})
		w.sim.log_event("Feuer und Trümmer bei %s. %s" % [bd.name, result], "bad", target)
		w.changed.emit()
		if not named.is_empty():
			_retreat(cid)
	if w.arms.condition_of(hall_id) <= 0.0 and (depot_id < 0 or w.arms.condition_of(depot_id) <= 0.0):
		defeated[str(target)] = {"by": cid, "zeit": w.sim.game_min}
		w.sim.company(target).status = "geschlossen"
		w.sim.company(target).status_reason = "Stadt im Krieg gefallen"
		w.sim.log_event("%s kapituliert: Rathaus und Betriebshof zerstört. %s gewinnt die Belagerung." % [w.sim.company(target).company_name, w.sim.company(cid).company_name], "bad", target)
		for id in troops.keys().duplicate():
			if int(troops[id].cid) == target:
				_release(str(id))
		_retreat(cid)


func _wall_intact(k: int) -> bool:
	var state: Dictionary = w.arms.walls.get(str(k), {})
	return bool(state.get("fertig", false)) and not bool(state.get("durchbruch", false))


func _breach_wall(k: int, at: Vector2i) -> void:
	var state: Dictionary = w.arms.walls.get(str(k), {})
	state["durchbruch"] = true
	var wall: Rect2i = w.arms._town_rect(k).grow(2)
	var best := Vector2i(-1, -1)
	var best_dist := 999999.0
	for x in range(wall.position.x, wall.end.x):
		for y in [wall.position.y, wall.end.y - 1]:
			var d := Vector2(at - Vector2i(x, y)).length_squared()
			if d < best_dist:
				best_dist = d
				best = Vector2i(x, y)
	for y in range(wall.position.y, wall.end.y):
		for x in [wall.position.x, wall.end.x - 1]:
			var d := Vector2(at - Vector2i(x, y)).length_squared()
			if d < best_dist:
				best_dist = d
				best = Vector2i(x, y)
	for p in w.blocks.keys().duplicate():
		var cell := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
		if EkoWorld._dist(cell, best) <= 1 and (cell.x == wall.position.x or cell.x == wall.end.x - 1 or cell.y == wall.position.y or cell.y == wall.end.y - 1):
			w.blocks.erase(p)
			w.sim.nav.walk.set_point_solid(cell, false)
	fires.append({"feld": [best.x, best.y], "left": 18.0, "staerke": 0.5})
	w.arms.blasts.append({"feld": [best.x, best.y], "ms": Time.get_ticks_msec(), "radius": 2, "atom": false})
	w.sim.log_event("Die Stadtmauer von %s ist bei %d,%d durchbrochen!" % [w.sim.towns.name_of(k), best.x, best.y], "bad")
	w.changed.emit()


func observe(cid: int) -> Dictionary:
	var c: Company = w.sim.company(cid)
	var k: int = c.home_town
	var rivals: Array = []
	for other in w.sim.companies:
		if other.id == cid or not other.is_active():
			continue
		var enemy_city: bool = w.sim.town_ready(other.home_town)
		var incoming := assaults.values().any(func(a): return int(a.target) == cid)
		rivals.append({"id": other.id, "firma": other.company_name, "stadt": w.sim.towns.name_of(other.home_town), "gegruendet": enemy_city,
			"truppen": troops.values().filter(func(t): return int(t.cid) == other.id).size(), "angriff_auf_mich": incoming})
	return {"strategie": strategy(cid), "stadt_gegruendet": w.sim.town_ready(k), "gegner": rivals,
		"eigene_truppen": troops.keys().filter(func(id): return int(troops[id].cid) == cid).map(func(id): return {"worker_id": id, "name": w.sim.personnel.workers[id].name, "waffe": troops[id].weapon.get("design", ""), "auftrag": troops[id].mode, "gesundheit": int(w.sim.personnel.workers[id].health)}),
		"angriff": assaults.get(str(cid), {}), "eigene_stadt_bedroht": assaults.values().any(func(a): return int(a.target) == cid),
		"mauer": w.arms.walls.get(str(k), {}), "wachtuerme": w.arms.towers.filter(func(t): return int(t.stadt) == k).size(),
		"angreifbare_wachtuerme": _tower_targets(rivals),
		"kraftwerk": w.sim.plant.summary(),
		"aktionen": "set_city_strategy {form?, wirtschaft?, haltung: frieden|verteidigung|krieg, rival?, begruendung?}; mobilize_worker {worker_id, weapon?}; demobilize_worker {worker_id}; order_assault {target, asset?}; order_retreat {}. asset: Gebäude der Rivalenstadt, kraftwerk, fahrzeug_<id> oder wachturm_<index>; ohne asset: Depot, dann Rathaus. Ein Kraftwerksangriff trifft die ganze Region und kann eine Sperrzone auslösen. Angriff braucht eigene Stadt, bewaffnete Truppe und Haltung krieg; Frieden bleibt möglich."}


func _tower_targets(rivals: Array) -> Array:
	var out: Array = []
	for i in w.arms.towers.size():
		var tw: Dictionary = w.arms.towers[i]
		for r in rivals:
			if w.sim.company(int(r.id)).home_town == int(tw.stadt):
				out.append({"asset": "wachturm_%d" % i, "firma": int(r.id), "feld": tw.feld, "zustand": int(tw.get("hp", 80.0))})
				break
	return out


func to_dict() -> Dictionary:
	return {"strategies": strategies, "troops": troops, "assaults": assaults, "defeated": defeated, "fires": fires, "wall_damage": wall_damage}


func from_dict(d: Dictionary) -> void:
	strategies = d.get("strategies", {})
	troops = d.get("troops", {})
	assaults = d.get("assaults", {})
	defeated = d.get("defeated", {})
	fires = d.get("fires", [])
	wall_damage = d.get("wall_damage", {})
	for id in troops.keys().duplicate():
		var soldier: Worker = w.sim.personnel.workers.get(str(id))
		if soldier == null:
			troops.erase(id)
			continue
		soldier.duty_label = "Stadtwache"
		if str(troops[id].mode) == "angriff" and assaults.has(str(troops[id].cid)):
			var goal: Array = assaults[str(troops[id].cid)].ziel
			var path: Array[Vector2i] = w.sim.nav.walk_path(soldier.tile(), Vector2i(int(goal[0]), int(goal[1])))
			if not path.is_empty():
				soldier.set_path(path)
