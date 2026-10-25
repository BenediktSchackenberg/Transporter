class_name Personnel
extends RefCounted
## Arbeitskraefte als knappe Ressource, Arbeitsauftraege, Vorarbeiter und Arbeiter-Sabotage.
##
## Arbeitsmarkt: verfuegbare Arbeiter stehen sichtbar an konkreten Orten (Personalbuero: Fahrer, Waechter,
## Vorarbeiter; Hafen: Lagerarbeiter; Werkstaetten: Mechaniker). Ein Arbeiter hat hoechstens einen Arbeitgeber.
## Hierarchie: Unternehmer (KI) vergibt Ziele/Aufgaben/Budgets -> Vorarbeiter verteilt und kontrolliert ->
## Arbeiter fuehrt aus. Vorarbeiter wissen nur, was ihre Arbeiter per Funk melden oder was in ihrem Bereich passiert.

const SABOTAGE_COST := 800.0
const SABOTAGE_COOLDOWN := 180.0       # Spielminuten je Unternehmen
const VEHICLE_PROTECTION := 240.0      # Spielminuten je Zielfahrzeug
const SABOTAGE_FINE := 1500.0
const SABOTAGE_COMPENSATION := 1000.0
const SEEN_TTL := 90.0                 # Sichtungen gelten 90 Spielminuten
const REPORT_EVERY := 120.0

var sim
var workers := {}                      # ID -> Worker
var tasks := {}                        # ID -> WorkerTask
var next_worker := 1
var next_task := 1
var seen := {}                         # Firma -> {Fahrzeug-ID(str): {owner, model, state, x, y, t, quelle}}
var cooldowns := {}
var force_outcome := ""                # nur fuer Tests: success | fail | caught
var shortage_until := 0.0              # Arbeitskraeftemangel (Ereignisregler)


func setup(simulation) -> void:
	sim = simulation
	for c in sim.companies:
		seen[c.id] = {}
	var kinds := ["driver", "driver", "loader", "mechanic", "guard", "driver", "foreman", "loader", "mechanic", "driver"]
	for i in 4 + 3 * sim.companies.size():
		spawn_available(kinds[i % kinds.size()])


# ------------------------------------------------------------------ Arbeitsmarkt
func pool_building(kind: String) -> Dictionary:
	var role := "staffing"
	if kind == "mechanic":
		role = "workshop"
	var best := {}
	for b in sim.city.buildings:
		if kind == "loader" and b.type == "port_office":
			return b
		if b.role == role and (best.is_empty() or sim.rng.randf() < 0.5):
			best = b
	return best


func spawn_available(kind: String) -> Worker:
	var rng: RandomNumberGenerator = sim.rng
	var w := Worker.new()
	w.id = "W%d" % next_worker
	next_worker += 1
	w.name = sim._driver_name()
	match kind:
		"driver":
			w.skills.fahren = rng.randi_range(1, 3)
			w.skills.verladen = rng.randi_range(0, 1)
		"loader":
			w.skills.verladen = rng.randi_range(2, 3)
			w.skills.fahren = rng.randi_range(0, 1)
			w.skills.bewachen = rng.randi_range(0, 1)
		"mechanic":
			w.skills.reparieren = rng.randi_range(2, 3)
			w.skills.fahren = 1
		"guard":
			w.skills.bewachen = rng.randi_range(2, 3)
			w.skills.verladen = 1
		"foreman":
			w.role = "foreman"
			w.skills["organisation"] = rng.randi_range(1, 3)
			w.skills.fahren = 1
	var total := 0
	for k in w.skills:
		total += int(w.skills[k])
	w.wage = 10.0 + 1.6 * total + rng.randi_range(0, 3)
	if w.role == "foreman":
		w.wage = 26.0 + 4.0 * w.org_level()
	w.hire_fee = roundf(w.wage * (60.0 if w.role == "foreman" else 25.0))
	w.reliability = rng.randf_range(0.65, 0.95)
	w.loyalty = rng.randf_range(40.0, 60.0)
	w.experience = rng.randf_range(0.0, 30.0)
	var b := pool_building(kind)
	w.home = b.walk + Vector2i(rng.randi_range(-1, 1), 1)
	if not sim.city.walkable(w.home):
		w.home = b.walk
	w.pos = sim.city.tile_center(w.home) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-4, 4))
	workers[w.id] = w
	return w


func available() -> Array:
	return workers.values().filter(func(w): return w.employer == -1 and not w.lost)   # -2 = voruebergehend nicht am Markt


func employed(cid: int) -> Array:
	return workers.values().filter(func(w): return w.employer == cid and not w.lost)


func driver_of(vid: int) -> Worker:
	for w in workers.values():
		if w.vehicle_id == vid and not w.lost and w.employer >= 0:
			return w
	return null


## Startpersonal (gleich fuer alle): ein Fahrer im Startfahrzeug und ein Allrounder.
func start_staff(cid: int, vehicle_id: int) -> void:
	var d := _new_employee(cid, {"fahren": 2, "verladen": 1}, 14.0)
	d.vehicle_id = vehicle_id
	d.pos = sim.vehicles[vehicle_id].pos
	var a := _new_employee(cid, {"fahren": 1, "verladen": 1, "reparieren": 1, "bewachen": 1}, 15.0)
	a.pos = sim.city.tile_center(sim.city.building(sim.companies[cid].depots[0]).walk)


func _new_employee(cid: int, skills: Dictionary, wage: float) -> Worker:
	var w := Worker.new()
	w.id = "W%d" % next_worker
	next_worker += 1
	w.name = sim._driver_name()
	for k in skills:
		w.skills[k] = skills[k]
	w.wage = wage
	w.hire_fee = 0.0
	w.reliability = 0.85
	w.experience = 20.0
	w.employer = cid
	workers[w.id] = w
	return w


func hire(cid: int, w: Worker) -> void:
	w.employer = cid
	w.loyalty = 50.0
	w.foreman = ""
	w.leaving = false
	var c: Company = sim.company(cid)
	if w.hire_fee > 0.0:
		c.ledger.book("hire_fees", -w.hire_fee, true, "Anwerbung %s (%s)" % [w.name, w.id], sim.game_min)
	# zum Hauptdepot gehen (sichtbar)
	create_task(cid, "gehen", {"site": c.depots[0]}, w.id, "", 2, "auto")


## Mitarbeiter verlaesst den Arbeitgeber und steht wieder am Arbeitsmarkt zur Verfuegung (Kuendigung, Insolvenz).
func release(w: Worker) -> void:
	for t in tasks.values():
		if t.worker_id == w.id and not t.is_final():
			cancel_task(t, "Mitarbeiter ausgeschieden")
	if w.vehicle_id >= 0 and sim.vehicles.has(w.vehicle_id):
		w.pos = sim.vehicles[w.vehicle_id].pos
	for f in workers.values():
		f.supervised.erase(w.id)
	for s in w.supervised:
		if workers.has(s):
			workers[s].foreman = ""
	w.supervised.clear()
	w.employer = -1
	w.vehicle_id = -1
	w.task_id = ""
	w.foreman = ""
	w.leaving = false
	w.path.clear()


func lose_worker(w: Worker, reason: String) -> void:
	var cid := w.employer
	w.lost = true
	w.leaving = false
	for t in tasks.values():
		if t.worker_id == w.id and not t.is_final():
			t.status = "abgebrochen"
			t.report = "Arbeiter %s verloren (%s)" % [w.name, reason]
	w.task_id = ""
	w.vehicle_id = -1
	for f in workers.values():
		f.supervised.erase(w.id)
	for s in w.supervised:
		if workers.has(s):
			workers[s].foreman = ""
	w.supervised.clear()
	w.path.clear()
	if cid >= 0:
		sim.company(cid).add_key_event("Personalverlust: %s (%s)" % [w.name, reason], sim.game_min)
	w.employer = -1


# ------------------------------------------------------------------ Aufgaben
## Gibt "" zurueck, wenn der Arbeiter die Aufgabe uebernehmen kann, sonst den Grund.
func can_take(w: Worker, kind: String) -> String:
	if w.lost:
		return "%s ist nicht mehr verfügbar." % w.name
	if w.role == "foreman":
		return "%s ist Vorarbeiter und führt selbst keine Aufgaben aus." % w.name
	if w.task_id != "" and tasks.has(w.task_id) and not tasks[w.task_id].is_final() and tasks[w.task_id].kind != "gehen":
		return "%s ist mit Aufgabe %s beschäftigt." % [w.name, w.task_id]
	if w.vehicle_id >= 0 and kind != "fahren":
		var v: FleetVehicle = sim.vehicles.get(w.vehicle_id)
		if v and v.state not in ["idle"]:
			return "%s fährt gerade #%d." % [w.name, w.vehicle_id]
	if w.rest_until > sim.game_min:
		return "%s macht Pause (bis %s)." % [w.name, Catalog.game_minutes_to_text(w.rest_until)]
	if w.fatigue >= 90.0:
		return "%s ist erschöpft (%d %%) und muss sich ausruhen." % [w.name, int(w.fatigue)]
	var need: String = WorkerTask.SKILL.get(kind, "")
	if need != "" and int(w.skills.get(need, 0)) < 1:
		return "%s hat keine Fähigkeit „%s“." % [w.name, need]
	return ""


func create_task(cid: int, kind: String, target: Dictionary, worker_id: String, foreman_id: String,
		priority: int, origin: String) -> WorkerTask:
	var t := WorkerTask.new()
	t.id = "T%d" % next_task
	next_task += 1
	t.company = cid
	t.kind = kind
	t.target = target
	t.priority = clampi(priority, 1, 3)
	t.created = sim.game_min
	t.foreman_id = foreman_id
	t.report = "erteilt (%s)" % origin
	tasks[t.id] = t
	if origin == "Vorarbeiter":
		sim.decisions.note(cid, "foreman", "Vorarbeiter %s erteilt %s (%s)" % [foreman_id, t.id, kind], {"task_id": t.id})
	if worker_id != "":
		_bind(t, workers[worker_id])
	return t


func _bind(t: WorkerTask, w: Worker) -> void:
	var old: WorkerTask = tasks.get(w.task_id)
	if old and not old.is_final() and old.kind == "gehen":
		old.status = "abgebrochen"   # reiner Weg wird durch die neue Aufgabe ersetzt
		old.report = "durch %s ersetzt" % t.id
	if w.vehicle_id >= 0 and t.kind != "fahren":
		var v: FleetVehicle = sim.vehicles.get(w.vehicle_id)
		if v:
			w.pos = v.pos   # steigt aus
		w.vehicle_id = -1
	t.worker_id = w.id
	t.status = "zugewiesen"
	w.task_id = t.id


func cancel_task(t: WorkerTask, reason: String) -> void:
	if t.is_final():
		return
	t.status = "abgebrochen"
	t.report = reason
	_release(t)


func _release(t: WorkerTask) -> void:
	var w: Worker = workers.get(t.worker_id)
	if w and w.task_id == t.id:
		w.task_id = ""
		w.path.clear()
	var v: FleetVehicle = sim.vehicles.get(int(t.target.get("vehicle_id", -1)))
	if v and v.held_by == t.id:
		v.held_by = ""


func _finish(t: WorkerTask, status: String, report: String) -> void:
	t.status = status
	t.report = report
	if status == "abgeschlossen":
		t.progress = 1.0
		var w: Worker = workers.get(t.worker_id)
		if w:
			w.experience = minf(100.0, w.experience + 3.0)
	_release(t)
	var w2: Worker = workers.get(t.worker_id)
	var who: String = w2.name if w2 else "?"
	sim.notify(t.company, "Aufgabe %s (%s, %s): %s – %s" % [t.id, t.describe(), who, status, report])


func task_cell(t: WorkerTask, w: Worker) -> Vector2i:
	var c: Company = sim.company(t.company)
	match t.kind:
		"fahren", "reparieren", "sabotage":
			if t.target.get("werkstatt", false):
				return sim.city.building(sim.company(t.company).depots[0]).walk   # eigene Werkstatt auf dem Hof
			var v: FleetVehicle = sim.vehicles.get(int(t.target.get("vehicle_id", -1)))
			return v.tile() if v else Vector2i(-1, -1)
		"bewachen":
			if t.target.has("vehicle_id"):
				var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
				return v.tile() if v else Vector2i(-1, -1)
			return sim.city.building(int(t.target.site)).walk
		"verladen":
			return sim.city.building(int(t.target.building)).walk
		"bauen", "schulung":
			return sim.city.building(int(t.target.building)).walk   # Zugang zum Grundstueck
		"auskundschaften":
			var rival: Company = sim.company(int(t.target.company))
			return sim.city.building(rival.depots[0]).walk + Vector2i(2, 2)
		"unterstuetzen":
			var o: Worker = workers.get(str(t.target.worker_id))
			return o.tile() if o else Vector2i(-1, -1)
		"gehen":
			if t.target.has("building"):
				return sim.city.building(int(t.target.building)).walk
			return sim.city.building(int(t.target.get("site", c.depots[0]))).walk
	return Vector2i(-1, -1)


func _walk(w: Worker, cell: Vector2i) -> bool:
	var target := cell
	if not sim.city.walkable(target):
		target = _walkable_near(cell)
	var p: Array[Vector2i] = sim.nav.walk_path(w.tile(), target)
	if p.is_empty():
		return false
	w.set_path(p)
	return true


func _walkable_near(cell: Vector2i) -> Vector2i:
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := cell + Vector2i(dx, dy)
				if sim.city.walkable(q):
					return q
	return cell


# ------------------------------------------------------------------ Simulation
func update(dt: float) -> void:
	for w in workers.values():
		if w.lost:
			continue
		if w.vehicle_id >= 0 and sim.vehicles.has(w.vehicle_id):
			w.pos = sim.vehicles[w.vehicle_id].pos
		var t: WorkerTask = tasks.get(w.task_id)
		if t != null and not t.is_final():
			_progress(t, w, dt)
		if not w.arrived():
			w.advance(dt, 0.75 if w.fatigue > 85.0 else 1.0)


func _progress(t: WorkerTask, w: Worker, dt: float) -> void:
	match t.status:
		"zugewiesen":
			t.cell = task_cell(t, w)
			if t.cell.x < 0:
				_finish(t, "fehlgeschlagen", "Ziel existiert nicht mehr")
				return
			if w.tile().distance_to(t.cell) <= 1.5 or w.vehicle_id >= 0 and t.kind == "fahren" and w.vehicle_id == int(t.target.vehicle_id):
				_start_work(t, w)
			elif _walk(w, t.cell):
				t.status = "unterwegs"
				t.report = "unterwegs nach %s" % str(t.cell)
			else:
				t.status = "blockiert"
				t.report = "kein Fußweg zum Einsatzort"
		"unterwegs":
			# bewegliche Ziele (Fahrzeuge, Kollegen) nachverfolgen
			if t.kind in ["fahren", "reparieren", "sabotage", "unterstuetzen"] or t.target.has("vehicle_id"):
				var c2 := task_cell(t, w)
				if c2.x < 0:
					_finish(t, "fehlgeschlagen", "Ziel existiert nicht mehr")
					return
				if c2.distance_to(t.cell) > 2.0 and int(sim.sim_time * 10.0) % 20 == 0:
					t.cell = c2
					_walk(w, c2)
			if w.arrived() or w.tile().distance_to(t.cell) <= 1.5:
				_start_work(t, w)
				if t.status == "unterwegs" and w.arrived():
					# Ziel (Fahrzeug/Kollege) hat sich bewegt: zur aktuellen Position nachgehen
					var c3 := task_cell(t, w)
					if c3.x >= 0 and c3 != w.tile():
						t.cell = c3
						_walk(w, c3)
		"in Bearbeitung":
			_work(t, w, dt)
		"blockiert":
			if int(sim.sim_time * 10.0) % 50 == 0:   # alle 5 Sim-Sekunden erneut versuchen
				t.status = "zugewiesen"


func _vehicle_reachable(v: FleetVehicle, w: Worker) -> bool:
	return v != null and v.state in ["idle", "loading", "unloading", "broken", "repairing"] and w.pos.distance_to(v.pos) <= 80.0


func _start_work(t: WorkerTask, w: Worker) -> void:
	var c: Company = sim.company(t.company)
	match t.kind:
		"fahren":
			var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
			if v == null or v.owner != t.company:
				_finish(t, "fehlgeschlagen", "Fahrzeug gehört nicht (mehr) der Firma")
				return
			var other := driver_of(v.id)
			if other != null and other != w:
				_finish(t, "fehlgeschlagen", "%s fährt #%d bereits" % [other.name, v.id])
				return
			if not _vehicle_reachable(v, w):
				t.status = "unterwegs"   # Fahrzeug faehrt noch, hinterhergehen
				return
			w.vehicle_id = v.id
			w.pos = v.pos
			var kid := str(t.target.get("contract_id", ""))
			if kid == "":
				_finish(t, "abgeschlossen", "%s ist in #%d eingestiegen und fahrbereit" % [w.name, v.id])
				return
			var k: Contract = sim.contracts.get(kid)
			if k and k.status in ["accepted", "assigned", "in_transit"] and k.owner == t.company:
				sim.executor._assign(t.company, v.id, kid)
			t.status = "in Bearbeitung"
			t.report = "fährt Auftrag %s" % kid
		"reparieren":
			var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
			if v == null or v.owner != t.company:
				_finish(t, "fehlgeschlagen", "Fahrzeug nicht mehr vorhanden")
				return
			var in_shop: bool = t.target.get("werkstatt", false)
			if in_shop and (w.tile().distance_to(t.cell) > 2.0 or sim.estate.on_plot(t.company, v.pos) < 0 or v.state not in ["idle", "broken"]):
				t.status = "unterwegs"   # Mechaniker oder Fahrzeug noch nicht auf dem Hof
				return
			if not in_shop and not _vehicle_reachable(v, w):
				t.status = "unterwegs"
				return
			var parts := maxi(1, ceili((100.0 - v.condition) / 20.0))
			if c.parts < parts:
				t.status = "blockiert"
				t.report = "Ersatzteile fehlen (%d nötig, %d vorhanden)" % [parts, c.parts]
				return
			if t.target.get("werkstatt", false):
				var busy := tasks.values().filter(func(o): return o != t and o.company == t.company and o.kind == "reparieren" \
					and o.status == "in Bearbeitung" and o.target.get("werkstatt", false)).size()
				if busy >= sim.estate.workshop_bays(t.company):
					t.status = "blockiert"
					t.report = "Werkstattplatz belegt – wartet"
					return
			c.parts -= parts
			v.held_by = t.id
			t.work_needed = maxf(8.0, (100.0 - v.condition) * 0.8 / (0.5 + 0.5 * int(w.skills.reparieren)))
			if t.target.get("werkstatt", false):
				t.work_needed *= 0.5   # Werkstatt: Hebebuehne, Werkzeug
			_maybe_delay(t, w)
			t.status = "in Bearbeitung"
			t.report = "repariert #%d (%d Ersatzteile verbraucht)" % [v.id, parts]
		"bewachen":
			t.status = "in Bearbeitung"
			t.report = "bewacht"
		"verladen":
			t.work_needed = 120.0
			t.status = "in Bearbeitung"
			t.report = "hilft beim Verladen"
		"auskundschaften":
			t.work_needed = 60.0
			t.status = "in Bearbeitung"
			t.report = "beobachtet"
		"sabotage":
			var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
			if v == null or not _vehicle_reachable(v, w):
				_finish(t, "fehlgeschlagen", "Zielfahrzeug ist weggefahren oder nicht erreichbar (Kosten bleiben)")
				return
			t.work_needed = 10.0
			t.status = "in Bearbeitung"
			t.report = "macht sich am Fahrzeug zu schaffen"
		"unterstuetzen":
			t.status = "in Bearbeitung"
			t.report = "unterstützt %s" % str(t.target.worker_id)
		"gehen":
			_finish(t, "abgeschlossen", "angekommen")
		"bauen":
			t.status = "in Bearbeitung"
			t.report = "arbeitet auf der Baustelle"
		"schulung":
			t.work_needed = 120.0
			t.status = "in Bearbeitung"
			t.report = "in Schulung (%s)" % t.target.get("skill", "")


func _maybe_delay(t: WorkerTask, w: Worker) -> void:
	if sim.rng.randf() < (1.0 - w.reliability) * 0.5:
		t.work_needed *= 1.5
		t.report += " – verzögert sich"


func _helpers(t: WorkerTask) -> int:
	var n := 0
	for o in tasks.values():
		if o.kind == "unterstuetzen" and o.status == "in Bearbeitung" and str(o.target.get("worker_id", "")) == t.worker_id:
			n += 1
	return mini(n, 2)


func _work(t: WorkerTask, w: Worker, dt: float) -> void:
	var minutes := dt * Catalog.GAME_MIN_PER_SIM_SEC
	match t.kind:
		"fahren":
			var k: Contract = sim.contracts.get(str(t.target.get("contract_id", "")))
			if k == null or k.status in ["failed", "cancelled", "expired"]:
				_finish(t, "fehlgeschlagen", "Auftrag gescheitert oder entfallen")
			elif k.status == "delivered":
				_finish(t, "abgeschlossen", "Auftrag %s ausgeliefert (%s)" % [k.id, Catalog.money(k.paid)])
			elif w.vehicle_id < 0:
				_finish(t, "abgebrochen", "Fahrer hat das Fahrzeug verlassen")
		"reparieren":
			var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
			if v == null:
				_finish(t, "fehlgeschlagen", "Fahrzeug nicht mehr vorhanden")
				return
			t.progress += minutes * (1.0 + 0.5 * _helpers(t)) / t.work_needed
			if t.progress >= 1.0:
				v.condition = 100.0
				v.held_by = ""
				sim.resume_vehicle(v)
				_finish(t, "abgeschlossen", "#%d repariert" % v.id)
		"schulung":
			t.progress += minutes / t.work_needed
			if t.progress >= 1.0:
				var sk := str(t.target.get("skill", ""))
				w.skills[sk] = mini(3, int(w.skills.get(sk, 0)) + 1)
				_finish(t, "abgeschlossen", "%s jetzt Stufe %d" % [sk, w.skills[sk]])
		"verladen", "auskundschaften":
			var before := t.progress
			t.progress += minutes / t.work_needed
			if t.kind == "auskundschaften" and int(before * 4.0) != int(t.progress * 4.0):
				_scout_report(t, w)
			if t.progress >= 1.0:
				_finish(t, "abgeschlossen", "Einsatz beendet")
		"sabotage":
			t.progress += minutes / t.work_needed
			if t.progress >= 1.0:
				_resolve_sabotage(t, w)
		"unterstuetzen":
			var o: Worker = workers.get(str(t.target.worker_id))
			if o == null or o.lost or o.task_id == "" or not tasks.has(o.task_id) or tasks[o.task_id].is_final():
				_finish(t, "abgeschlossen", "unterstützte Aufgabe beendet")


## Beim Verladen helfende eigene Arbeiter am Gebaeude verkuerzen die Ladezeit (Faktor fuer Simulation).
func loading_factor(cid: int, building_id: int, driver: Worker) -> float:
	var f := 1.15 - (0.1 * int(driver.skills.verladen) if driver else 0.0)
	for t in tasks.values():
		if t.company == cid and t.kind == "verladen" and t.status == "in Bearbeitung" and int(t.target.building) == building_id:
			f *= 0.5
	return maxf(0.35, f)


# ------------------------------------------------------------------ Sabotage durch Arbeiter
## Wahrscheinlichkeiten nachvollziehbar: Entdeckung steigt durch Wachen, Zeugen und Sicherheitsstufe,
## sinkt durch Erfahrung/Technikgeschick des Saboteurs. Ausgaenge: Erfolg, Fehlschlag, Erwischt.
func sabotage_odds(w: Worker, v: FleetVehicle) -> Dictionary:
	var victim: Company = sim.company(v.owner)
	var guards := 0.0
	var witnesses := 0
	for o in workers.values():
		if o.lost or o.employer != v.owner or o.pos.distance_to(v.pos) > 128.0:
			continue
		var t: WorkerTask = tasks.get(o.task_id)
		if t and t.kind == "bewachen" and t.status == "in Bearbeitung":
			guards += (0.25 + 0.08 * int(o.skills.bewachen)) * (1.0 - o.fatigue / 200.0)
		else:
			witnesses += 1
	if sim.avatars[v.owner].pos.distance_to(v.pos) <= 128.0:
		witnesses += 1
	var detect: float = 0.15 + guards + minf(0.18, 0.06 * witnesses) + 0.1 * victim.security_level + sim.estate.security_bonus(v) \
		- w.experience / 400.0 - 0.04 * int(w.skills.reparieren)
	var success := 0.5 + 0.1 * int(w.skills.reparieren) + w.experience / 300.0 - 0.1 * victim.security_level
	return {"detect": clampf(detect, 0.05, 0.9), "success": clampf(success, 0.1, 0.9), "guards": snappedf(guards, 0.01),
		"witnesses": witnesses}


func _resolve_sabotage(t: WorkerTask, w: Worker) -> void:
	var v: FleetVehicle = sim.vehicles.get(int(t.target.vehicle_id))
	if v == null or not _vehicle_reachable(v, w):
		_finish(t, "fehlgeschlagen", "Zielfahrzeug war nicht mehr erreichbar")
		return
	var c: Company = sim.company(t.company)
	var victim: Company = sim.company(v.owner)
	var odds := sabotage_odds(w, v)
	var outcome := force_outcome
	if outcome == "":
		if sim.rng.randf() < odds.detect:
			outcome = "caught"
		elif sim.rng.randf() < odds.success:
			outcome = "success"
		else:
			outcome = "fail"
	cooldowns["veh:%d" % v.id] = sim.game_min + VEHICLE_PROTECTION
	match outcome:
		"caught":
			var name := w.name
			c.ledger.book("fines", -(SABOTAGE_FINE + SABOTAGE_COMPENSATION), true, "Bußgeld/Schadensersatz Sabotage", sim.game_min)
			victim.ledger.book("compensation", SABOTAGE_COMPENSATION, true, "Schadensersatz von " + c.company_name, sim.game_min)
			c.reputation = maxf(0.0, c.reputation - 10.0)
			c.stats.sabotage_caught += 1
			sim.social.add_trust(c.id, victim.id, -40.0)
			if sim.social.has_pact(c.id, victim.id):
				c.reputation = maxf(0.0, c.reputation - Catalog.PACT_BREACH_REP)
				sim.social.break_pact(c.id, victim.id)
			_finish(t, "fehlgeschlagen", "%s wurde erwischt" % name)
			lose_worker(w, "bei Sabotage erwischt")
			sim.log_event("%s wurde bei der Sabotage an #%d (%s) erwischt – %s verliert den Arbeiter dauerhaft, Bußgeld %s." % [
				name, v.id, victim.company_name, c.company_name, Catalog.money(SABOTAGE_FINE + SABOTAGE_COMPENSATION)], "bad", c.id)
			sim.notify(victim.id, "Saboteur %s von %s an Fahrzeug #%d gestellt. Schadensersatz %s erhalten." % [name, c.company_name, v.id, Catalog.money(SABOTAGE_COMPENSATION)])
			sim.sfx.emit("alert")
		"success":
			v.condition = maxf(5.0, v.condition - 35.0)
			sim.break_vehicle(v, "sabotiert")
			c.stats.sabotage_ok += 1
			victim.add_key_event("Fahrzeug #%d sabotiert" % v.id, sim.game_min)
			if victim.insurance:
				victim.ledger.book("insurance_payout", 800.0, true, "Versicherung: Fahrzeugschaden", sim.game_min)
			_finish(t, "abgeschlossen", "#%d von %s ist außer Betrieb" % [v.id, victim.company_name])
			sim.log_event("Fahrzeug #%d von %s wurde beschädigt (Täter unbekannt)." % [v.id, victim.company_name], "bad", victim.id)
			sim.sfx.emit("sabotage")
		_:
			_finish(t, "fehlgeschlagen", "Sabotage an #%d misslang, %s blieb unentdeckt" % [v.id, w.name])


# ------------------------------------------------------------------ Sichtungen & Vorarbeiter
## Eigene Figuren, Fahrzeuge und Depots sehen fremde Fahrzeuge in ihrer Naehe.
func update_seen() -> void:
	for c in sim.companies:
		var eyes: Array = [sim.avatars[c.id].pos]
		for w in employed(c.id):
			eyes.append(w.pos)
		for site in c.depots:
			eyes.append(sim.city.tile_center(sim.city.building(site).road))
		var known: Dictionary = seen[c.id]
		for v in sim.vehicles.values():
			if v.owner == c.id:
				continue
			for e in eyes:
				if e.distance_to(v.pos) <= 256.0:
					known[str(v.id)] = {"id": v.id, "owner": v.owner, "model": v.model, "state": v.state, "x": v.tile().x,
						"y": v.tile().y, "t": sim.game_min, "quelle": "gesehen"}
					break
		for k in known.keys():
			if sim.game_min - float(known[k].t) > SEEN_TTL or not sim.vehicles.has(int(k)):
				known.erase(k)


func _scout_report(t: WorkerTask, w: Worker) -> void:
	var rival: Company = sim.company(int(t.target.company))
	var depot: Vector2 = sim.city.tile_center(sim.city.building(rival.depots[0]).road)
	var parked: Array = []
	for v in sim.vehicles.values():
		if v.owner == rival.id and v.pos.distance_to(depot) <= 192.0:
			parked.append("#%d %s (%s)" % [v.id, v.model, FleetVehicle.STATE_TEXT.get(v.state, v.state)])
			seen[t.company][str(v.id)] = {"id": v.id, "owner": v.owner, "model": v.model, "state": v.state, "x": v.tile().x,
				"y": v.tile().y, "t": sim.game_min, "quelle": "Kundschafter %s" % w.name}
	var guards := 0
	for o in employed(rival.id):
		var ot: WorkerTask = tasks.get(o.task_id)
		if ot and ot.kind == "bewachen" and o.pos.distance_to(depot) <= 192.0:
			guards += 1
	sim.notify(t.company, "Kundschafter %s am Depot von %s: %s; Wachen: %d." % [w.name, rival.company_name,
		", ".join(parked) if not parked.is_empty() else "keine Fahrzeuge zu sehen", guards])


## Vorarbeiter: verteilt Aufgaben, erkennt Stoerungen in ihrem Bereich, teilt Ersatz ein, berichtet.
func foremen_tick() -> void:
	for f in workers.values():
		if f.role != "foreman" or f.lost or f.employer < 0:
			continue
		var cid: int = f.employer
		var c: Company = sim.company(cid)
		if f.station.x < 0:
			f.station = sim.city.building(c.depots[0]).walk
		if f.arrived() and f.tile().distance_to(f.station) > 2.0:
			_walk(f, f.station)
		var team: Array = f.supervised.filter(func(id): return workers.has(id) and not workers[id].lost).map(func(id): return workers[id])
		var radius: float = f.control_radius() * 32.0
		var center: Vector2 = sim.city.tile_center(f.station)
		# 1) offene Aufgaben dieses Vorarbeiters verteilen
		for t in tasks.values():
			if t.foreman_id == f.id and t.worker_id == "" and not t.is_final():
				var pick := _best_for(team, t)
				if pick:
					_bind(t, pick)
					t.report = "von %s an %s verteilt" % [f.name, pick.name]
					sim.log_event("Vorarbeiter %s teilt %s (%s) %s zu." % [f.name, t.id, t.kind, pick.name], "foreman", cid)
				else:
					t.status = "blockiert"
					t.report = "%s: kein geeigneter Arbeiter frei" % f.name
					_note(f, "Für %s (%s) ist kein geeigneter Arbeiter frei." % [t.id, t.kind])
		# 2) blockierte Aufgaben des Teams an Ersatz geben
		if f.orders.get("reassign_blocked", true):
			for w in team:
				var t: WorkerTask = tasks.get(w.task_id)
				if t and t.status == "blockiert" and (w.fatigue >= 90.0 or t.report.begins_with("kein Fußweg")):
					var alt := _best_for(team.filter(func(x): return x != w), t)
					if alt:
						w.task_id = ""
						_bind(t, alt)
						_note(f, "%s übernimmt %s für %s." % [alt.name, t.id, w.name])
		# 3) Fahrzeuge im Bereich oder mit Fahrer aus dem Team (bei "fristgerecht": dringendste Frist zuerst)
		var fleet: Array = sim.company_vehicles(cid)
		if f.orders.get("prioritaet", "") == "fristgerecht":
			fleet.sort_custom(func(x, y): return _next_deadline(x) < _next_deadline(y))
		for v in fleet:
			var drv := driver_of(v.id)
			var in_area: bool = v.pos.distance_to(center) <= radius or (drv != null and drv.id in f.supervised)
			if not in_area:
				continue
			if v.state == "broken" and v.held_by == "" and not _has_task_for(v.id, "reparieren"):
				var mech := _best_for(team, _probe("reparieren"))
				var needed := maxi(1, ceili((100.0 - v.condition) / 20.0))
				if mech and c.parts < needed and f.orders.get("darf_teile_kaufen", false):
					_foreman_buy_parts(f, cid, needed - c.parts)
				if f.orders.get("auto_repair", true) and mech and c.parts >= needed:
					var t := create_task(cid, "reparieren", {"vehicle_id": v.id}, mech.id, f.id, 1, "Vorarbeiter")
					_note(f, "#%d ist beschädigt – %s repariert (%s)." % [v.id, mech.name, t.id])
				elif f.orders.get("auto_repair", true) and float(f.orders.get("repair_budget", 0.0)) >= Catalog.TOW_FEE + 300.0:
					f.orders.repair_budget = float(f.orders.repair_budget) - Catalog.TOW_FEE - 300.0
					sim.tow_to_workshop(v)
					sim.decisions.note(cid, "foreman", "Vorarbeiter %s lässt #%d abschleppen (Budget)" % [f.name, v.id], {"vehicle_id": v.id})
					_note(f, "#%d ist beschädigt – ich lasse es zur Werkstatt schleppen (Budget übrig %s)." % [v.id, Catalog.money(f.orders.repair_budget)])
				else:
					_note(f, "#%d ist beschädigt – kein Mechaniker/keine Teile, keine Freigabe für Werkstatt." % v.id)
			elif drv == null and not v.stops.is_empty() and not _has_task_for(v.id, "fahren"):
				var d := _best_for(team, _probe("fahren"))
				if f.orders.get("auto_driver", true) and d:
					create_task(cid, "fahren", {"vehicle_id": v.id}, d.id, f.id, 1, "Vorarbeiter")
					_note(f, "#%d hat Aufträge, aber keinen Fahrer – %s steigt ein." % [v.id, d.name])
				else:
					_note(f, "Für #%d (Auftrag %s) fehlt ein Fahrer." % [v.id, v.stops[0].contract_id])
			elif drv and drv.fatigue >= 95.0 and v.state == "idle":
				var fresh := _best_for(team.filter(func(x): return x.fatigue < 50.0), _probe("fahren"))
				if fresh and f.orders.get("auto_driver", true):
					drv.vehicle_id = -1
					create_task(cid, "fahren", {"vehicle_id": v.id}, fresh.id, f.id, 1, "Vorarbeiter")
					_note(f, "%s ist erschöpft – %s löst ab an #%d." % [drv.name, fresh.name, v.id])
		if sim.game_min >= f.report_due or f.report_notes.size() >= 3:
			send_report(f)


func _next_deadline(v: FleetVehicle) -> float:
	var best := INF
	for st in v.stops:
		var k: Contract = sim.contracts.get(st.contract_id)
		if k:
			best = minf(best, k.deadline)
	return best


## Routinekauf innerhalb des Budgets (keine Investition). Wird protokolliert.
func _foreman_buy_parts(f: Worker, cid: int, amount: int) -> void:
	var best := {}
	for s in sim.resources.supplies.values():
		if s.kind == "parts" and float(s.stock) >= amount and (best.is_empty() or float(s.price) < float(best.price)):
			best = s
	if best.is_empty():
		return
	var cost := float(best.price) * amount
	if cost > float(f.orders.get("repair_budget", 0.0)):
		_note(f, "Für Ersatzteile (%s) fehlt Budget – Freigabe nötig." % Catalog.money(cost))
		return
	var r: Dictionary = sim.resources.buy_supplies(cid, best.id, amount)
	if r.ok:
		f.orders.repair_budget = float(f.orders.repair_budget) - cost
		f.spent += cost
		_note(f, "Ich habe %d Ersatzteile für %s gekauft (Budget übrig %s)." % [amount, Catalog.money(cost), Catalog.money(f.orders.repair_budget)])
		sim.decisions.note(cid, "foreman", "Vorarbeiter %s kauft %d Ersatzteile (%s) im Rahmen des Budgets" % [f.name, amount, Catalog.money(cost)])


func _probe(kind: String) -> WorkerTask:
	var t := WorkerTask.new()
	t.kind = kind
	return t


func _has_task_for(vid: int, kind: String) -> bool:
	for t in tasks.values():
		if t.kind == kind and not t.is_final() and int(t.target.get("vehicle_id", -1)) == vid:
			return true
	return false


func _best_for(team: Array, t: WorkerTask) -> Worker:
	var need: String = WorkerTask.SKILL.get(t.kind, "")
	var best: Worker = null
	var best_score := -INF
	for w in team:
		if can_take(w, t.kind) != "":
			continue
		if w.vehicle_id >= 0 and t.kind != "fahren":
			continue
		var score: float = (int(w.skills.get(need, 0)) * 10.0 if need != "" else 0.0) - w.fatigue * 0.1
		if t.cell.x >= 0:
			score -= w.tile().distance_to(t.cell) * 0.2
		if score > best_score:
			best_score = score
			best = w
	return best


func _note(f: Worker, text: String) -> void:
	if text not in f.report_notes:
		f.report_notes.append(text)


func send_report(f: Worker) -> void:
	var cid: int = f.employer
	var done := 0
	var open := 0
	for t in tasks.values():
		if t.company == cid and (t.worker_id in f.supervised or t.foreman_id == f.id):
			if t.status == "abgeschlossen" and sim.game_min - t.created < REPORT_EVERY * 2:
				done += 1
			elif not t.is_final():
				open += 1
	var text := "Vorarbeiter %s%s: %d Aufgaben erledigt, %d offen, Budget übrig %s. %s" % [f.name,
		(" (Ziel: %s)" % f.orders.ziel) if str(f.orders.get("ziel", "")) != "" else "", done, open, Catalog.money(f.orders.get("repair_budget", 0.0)),
		" ".join(f.report_notes) if not f.report_notes.is_empty() else "Keine Störungen im Bereich."]
	f.report_notes.clear()
	f.report_due = sim.game_min + REPORT_EVERY
	sim.notify(cid, text)
	sim.log_event(text, "report", cid)


func minute_tick(now: float) -> void:
	for w in workers.values():
		if w.lost or w.employer < 0:
			continue
		var t: WorkerTask = tasks.get(w.task_id)
		var v: FleetVehicle = sim.vehicles.get(w.vehicle_id)
		if v and v.state in ["to_pickup", "to_dropoff", "returning", "to_workshop"]:
			w.fatigue = minf(100.0, w.fatigue + 0.12)
		elif t and t.status == "in Bearbeitung":
			w.fatigue = minf(100.0, w.fatigue + (0.05 if t.kind == "bewachen" else 0.1))
		elif not w.arrived():
			w.fatigue = minf(100.0, w.fatigue + 0.05)
		else:
			w.fatigue = maxf(0.0, w.fatigue - 0.2 * sim.estate.recovery_factor(w))
		if sim.minute_index % 1440 == 0:
			w.loyalty = minf(100.0, w.loyalty + 1.0)
	if sim.minute_index % 5 == 0:
		update_seen()
	if sim.minute_index % 10 == 0:
		foremen_tick()
	if sim.minute_index % 90 == 0 and now >= shortage_until and available().size() < 4 + 2 * sim.companies.size():
		var kinds := ["driver", "loader", "mechanic", "guard", "driver", "foreman"]
		spawn_available(kinds[sim.rng.randi() % kinds.size()])


func wages_per_hour(cid: int) -> float:
	var s := 0.0
	for w in employed(cid):
		s += w.wage
	return s


func to_dict() -> Dictionary:
	var ws: Array = []
	for w in workers.values():
		ws.append(w.to_dict())
	var ts: Array = []
	for t in tasks.values():
		ts.append(t.to_dict())
	var sn := {}
	for cid in seen:
		sn[str(cid)] = seen[cid]
	return {"workers": ws, "tasks": ts, "next_worker": next_worker, "next_task": next_task, "seen": sn,
		"cooldowns": cooldowns, "shortage_until": shortage_until}


func from_dict(d: Dictionary) -> void:
	workers.clear()
	for wd in d.workers:
		var w := Worker.from_dict(wd)
		workers[w.id] = w
	tasks.clear()
	for td in d.tasks:
		var t := WorkerTask.from_dict(td)
		tasks[t.id] = t
	next_worker = int(d.next_worker)
	next_task = int(d.next_task)
	seen.clear()
	for cid in d.seen:
		seen[int(cid)] = d.seen[cid]
	cooldowns = d.cooldowns
	shortage_until = float(d.get("shortage_until", 0.0))
