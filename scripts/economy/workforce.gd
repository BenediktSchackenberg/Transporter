class_name Workforce
extends RefCounted
## Gesundheit und Erholung, geplante Pausen, Weiterbildung und Ersatzpersonal ueber die Vermittlung (Auftrag 3).
##
## Gesundheit 0..100: Dauererschoepfung zehrt sie auf, Ruhe baut sie wieder auf. Faellt sie unter 30, wird der Mitarbeiter krank
## (mehrere Spielstunden keine Aufgaben). Niedrige Gesundheit drueckt die Motivation (siehe Households).

const TICK_MIN := 10                  # Spielminuten zwischen zwei Gesundheitsschritten
const SICK_BELOW := 30.0
const SICK_HOURS := 6.0
const REST_MAX_HOURS := 12.0
const TRAIN_COST := 1200.0
const TRAIN_HOURS := 4.0
const TRAIN_MAX_SKILL := 2            # ohne Schulungsraum (mit Schulungsraum bis 3)
const AGENCY_FEE := 600.0
const AGENCY_DELAY_MIN := 120.0       # ein Spieltag
const AGENCY_MAX_PENDING := 2

var sim: Simulation
var pending: Array = []               # {cid, kind, due}


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)


## Alle TICK_MIN Spielminuten aus dem Minutentakt aufrufen.
func minute_tick() -> void:
	var now := sim.game_min
	for w in sim.personnel.workers.values():
		if w.lost or w.employer < 0:
			continue
		var resting: bool = w.rest_until > now
		if resting:
			w.fatigue = maxf(0.0, w.fatigue - 2.0)
			w.health = minf(100.0, w.health + 0.5)
		elif w.fatigue >= 85.0:
			w.health = maxf(0.0, w.health - 0.25)
		elif w.fatigue >= 70.0:
			w.health = maxf(0.0, w.health - 0.05)
		elif w.fatigue < 30.0:
			w.health = minf(100.0, w.health + 0.15)
		if w.health < SICK_BELOW and not resting:
			w.rest_until = now + SICK_HOURS * 60.0
			w.health = 45.0
			sim.notify(w.employer, "%s ist krank geworden und fällt etwa %d Stunden aus." % [w.name, int(SICK_HOURS)])
			sim.log_event("%s meldet sich krank (%s)." % [w.name, sim.company(w.employer).company_name], "info", w.employer)


func _busy(w: Worker) -> String:
	if w.vehicle_id >= 0:
		return "%s sitzt im Fahrzeug #%d." % [w.name, w.vehicle_id]
	var t: WorkerTask = sim.personnel.tasks.get(w.task_id)
	if t != null and not t.is_final() and t.kind != "gehen":
		return "%s arbeitet an Aufgabe %s." % [w.name, t.id]
	return ""


func _own(cid: int, wid: String) -> Worker:
	var w: Worker = sim.personnel.workers.get(wid)
	return w if w != null and w.employer == cid and not w.lost else null


## Pause einplanen: der Mitarbeiter bekommt keine neuen Aufgaben und erholt sich schneller.
func schedule_rest(cid: int, wid: String, hours: float) -> Dictionary:
	var w := _own(cid, wid)
	if w == null:
		return {"ok": false, "msg": "%s arbeitet nicht für dich." % wid}
	var busy := _busy(w)
	if busy != "":
		return {"ok": false, "msg": busy + " Erst Aufgabe beenden oder abbrechen."}
	hours = clampf(hours, 0.5, REST_MAX_HOURS)
	w.rest_until = sim.game_min + hours * 60.0
	return {"ok": true, "msg": "%s ruht %.1f Stunden (Erschöpfung %d %%, Gesundheit %d)." % [w.name, hours, int(w.fatigue), int(w.health)]}


## Externe Weiterbildung (ohne Schulungsraum): Faehigkeit +1 bis Stufe 2, Mitarbeiter fehlt einige Stunden.
func offer_training(cid: int, wid: String, skill: String) -> Dictionary:
	var w := _own(cid, wid)
	if w == null:
		return {"ok": false, "msg": "%s arbeitet nicht für dich." % wid}
	if skill not in Worker.SKILLS:
		return {"ok": false, "msg": "Unbekannte Fähigkeit (%s)." % ", ".join(Worker.SKILLS)}
	var busy := _busy(w)
	if busy != "":
		return {"ok": false, "msg": busy}
	if int(w.skills.get(skill, 0)) >= TRAIN_MAX_SKILL:
		return {"ok": false, "msg": "%s beherrscht %s bereits auf Stufe %d (mehr nur im eigenen Schulungsraum)." % [w.name, skill, int(w.skills[skill])]}
	var c := sim.company(cid)
	if c.ledger.cash < TRAIN_COST:
		return {"ok": false, "msg": "Weiterbildung kostet %s." % Catalog.money(TRAIN_COST)}
	c.ledger.book("training", -TRAIN_COST, true, "Weiterbildung %s (%s)" % [w.name, skill], sim.game_min)
	w.skills[skill] = int(w.skills.get(skill, 0)) + 1
	w.rest_until = sim.game_min + TRAIN_HOURS * 60.0
	w.motivation = minf(100.0, w.motivation + 6.0)
	w.experience = minf(100.0, w.experience + 5.0)
	return {"ok": true, "msg": "%s bildet sich in %s weiter (jetzt Stufe %d), fehlt %d Stunden. Der Marktlohn steigt entsprechend." % [w.name, skill, int(w.skills[skill]), int(TRAIN_HOURS)]}


## Ersatz ueber die Vermittlung: nach einem Spieltag wird ein passender Arbeitnehmer angestellt (Vermittlungsgebuehr sofort).
func request_replacement(cid: int, kind: String) -> Dictionary:
	if kind not in ["driver", "loader", "mechanic", "guard", "foreman"]:
		return {"ok": false, "msg": "Rolle: driver, loader, mechanic, guard oder foreman."}
	var open: int = pending.filter(func(p): return p.cid == cid).size()
	if open >= AGENCY_MAX_PENDING:
		return {"ok": false, "msg": "Es laufen schon %d Vermittlungen." % open}
	var c := sim.company(cid)
	var fee := AGENCY_FEE * (2.0 if kind == "foreman" else 1.0)
	if c.ledger.cash < fee:
		return {"ok": false, "msg": "Vermittlungsgebühr %s." % Catalog.money(fee)}
	c.ledger.book("hire_fees", -fee, true, "Vermittlung %s" % kind, sim.game_min)
	pending.append({"cid": cid, "kind": kind, "due": sim.game_min + AGENCY_DELAY_MIN})
	return {"ok": true, "msg": "Die Vermittlung sucht einen %s, Ankunft in etwa einem Spieltag (Gebühr %s, danach Anwerbegebühr und Lohn)." % [kind, Catalog.money(fee)]}


func on_day(_day: int) -> void:
	for p in pending.duplicate():
		if sim.game_min < float(p.due):
			continue
		pending.erase(p)
		var c := sim.company(int(p.cid))
		if not c.is_active():
			continue
		var w: Worker = sim.personnel.spawn_available(str(p.kind))
		if c.ledger.cash < w.hire_fee:
			sim.notify(c.id, "Die Vermittlung hat %s gefunden, aber die Anwerbegebühr %s fehlt." % [w.name, Catalog.money(w.hire_fee)])
			continue
		sim.personnel.hire(c.id, w)
		sim.log_event("Die Vermittlung stellt %s als %s bei %s ein." % [w.name, p.kind, c.company_name], "info", c.id)
		sim.notify(c.id, "Ersatz eingetroffen: %s (%s)." % [w.name, w.skill_text()])


func summary_of(cid: int) -> Dictionary:
	var sick := 0
	var tired := 0
	var h := 0.0
	var staff: Array = sim.personnel.employed(cid)
	for w in staff:
		h += w.health
		if w.rest_until > sim.game_min and w.health < 60.0:
			sick += 1
		if w.fatigue >= 70.0:
			tired += 1
	return {"gesundheit_mittel": int(h / maxf(staff.size(), 1)), "erschoepft": tired, "krank_oder_in_pause": sick,
		"vermittlungen_offen": pending.filter(func(p): return p.cid == cid).size()}


func to_dict() -> Dictionary:
	return {"pending": pending}


func from_dict(d: Dictionary) -> void:
	pending = d.get("pending", [])
	for p in pending:
		p.cid = int(p.cid)
