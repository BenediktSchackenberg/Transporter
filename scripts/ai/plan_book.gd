class_name PlanBook
extends RefCounted
## Strukturierte Plaene der KI-Unternehmer. Die KI entscheidet ueber Ziel und Schritte (set_plan);
## die Engine prueft Abhaengigkeiten und Mittel, fuehrt nur ausdruecklich freigegebene Schritte aus
## (execute_plan_step), verfolgt laufende Schritte (Aufgaben, Besuche) und markiert den Plan zur Neuplanung,
## wenn eine Abbruchbedingung eintritt oder eine Voraussetzung entfaellt. Es gibt keine eingebaute
## "maximiere Gewinn"-Routine: Ohne Plan und Aktionen der KI passiert strategisch nichts.

const MAX_STEPS := 10
const CONDITIONS := ["bargeld_unter", "ruf_unter", "restzeit_unter_min", "auftrag_gescheitert", "arbeiter_verloren",
	"fahrzeug_ausgefallen"]

var sim
var plans := {}          # Firma -> aktueller Plan
var history := {}        # Firma -> fruehere Plaene (max. 5)
var next_id := 1


func setup(simulation) -> void:
	sim = simulation


func current(cid: int) -> Dictionary:
	return plans.get(cid, {})


func set_plan(cid: int, a: Dictionary) -> Dictionary:
	var raw_steps = a.get("schritte", [])
	if not raw_steps is Array or raw_steps.is_empty() or raw_steps.size() > MAX_STEPS:
		return {"ok": false, "msg": "Ein Plan braucht 1–%d Schritte (schritte)." % MAX_STEPS}
	var steps: Array = []
	var ids := {}
	for i in raw_steps.size():
		var r = raw_steps[i]
		if not r is Dictionary:
			return {"ok": false, "msg": "Schritt %d muss ein Objekt sein." % (i + 1)}
		var sid := str(r.get("id", "S%d" % (i + 1)))
		if ids.has(sid):
			return {"ok": false, "msg": "Schritt-ID %s doppelt." % sid}
		ids[sid] = true
		var step := {"id": sid, "text": str(r.get("text", "")).left(160), "abhaengig_von": [], "braucht": {},
			"status": "offen", "ergebnis": "", "action_key": "", "task_id": ""}
		var deps = r.get("abhaengig_von", [])
		if deps is Array:
			for d in deps:
				step.abhaengig_von.append(str(d))
		if r.get("braucht") is Dictionary:
			step.braucht = r.braucht
		if r.get("aktion") is Dictionary:
			var act: Dictionary = r.aktion
			var err := ActionExecutor.validate_schema(str(act.get("action", "")), act)
			if err != "" or str(act.get("action", "")) in ["set_plan", "execute_plan_step"]:
				return {"ok": false, "msg": "Schritt %s: ungültige Aktion (%s)." % [sid, err if err != "" else "nicht erlaubt"]}
			step["aktion"] = act
		steps.append(step)
	for st in steps:
		for d in st.abhaengig_von:
			if not ids.has(d):
				return {"ok": false, "msg": "Schritt %s hängt von unbekanntem Schritt %s ab." % [st.id, d]}
	var conds: Array = []
	var raw_c = a.get("abbruch", [])
	if raw_c is Array:
		for cnd in raw_c:
			if cnd is Dictionary and str(cnd.get("typ", "")) in CONDITIONS:
				conds.append({"typ": str(cnd.typ), "wert": float(cnd.get("wert", 0))})
	var old := current(cid)
	if not old.is_empty():
		_archive(cid, old, "ersetzt")
	var p := {"id": "P%d" % next_id, "ziel": str(a.get("ziel", "")).left(200), "nutzen": str(a.get("nutzen", "")).left(200),
		"risiken": str(a.get("risiken", "")).left(200), "abbruch": conds, "schritte": steps, "status": "aktiv",
		"hinweis": "", "erstellt": sim.game_min, "ausgaben_bei_start": -sim.company(cid).ledger.costs(),
		"gewinn_bei_start": sim.company(cid).ledger.profit(), "lost_at_start": _lost(cid), "failed_at_start": sim.company(cid).stats.failed}
	next_id += 1
	plans[cid] = p
	sim.log_event("%s legt Plan %s fest: %s (%d Schritte)." % [sim.company(cid).player_name, p.id, p.ziel, steps.size()], "plan", cid)
	return {"ok": true, "msg": "Plan %s aktiv: %d Schritte." % [p.id, steps.size()]}


func update_step(cid: int, sid: String, status: String, ergebnis: String) -> Dictionary:
	var st := _step(cid, sid)
	if st.is_empty():
		return {"ok": false, "msg": "Kein Schritt %s im aktuellen Plan." % sid}
	if status not in ["offen", "erledigt", "uebersprungen", "blockiert"]:
		return {"ok": false, "msg": "Status muss offen, erledigt, uebersprungen oder blockiert sein."}
	st.status = status
	if ergebnis != "":
		st.ergebnis = ergebnis.left(160)
	_check_done(cid)
	return {"ok": true, "msg": "Schritt %s: %s." % [sid, status]}


## Fuehrt die im Schritt hinterlegte Aktion aus (Herkunft "plan"). Abhaengigkeiten und Mittel werden geprueft.
func execute_step(cid: int, sid: String, key: String) -> Dictionary:
	var p := current(cid)
	var st := _step(cid, sid)
	if st.is_empty():
		return {"ok": false, "msg": "Kein Schritt %s im aktuellen Plan." % sid}
	if p.status != "aktiv":
		return {"ok": false, "msg": "Plan %s ist %s – erst neu planen." % [p.id, p.status]}
	if st.status not in ["offen", "blockiert"]:
		return {"ok": false, "msg": "Schritt %s ist bereits %s." % [sid, st.status]}
	if not st.has("aktion"):
		return {"ok": false, "msg": "Schritt %s hat keine ausführbare Aktion (nur mit update_plan_step abhaken)." % sid}
	for d in st.abhaengig_von:
		var dep := _step(cid, d)
		if dep.status not in ["erledigt", "uebersprungen"]:
			return {"ok": false, "msg": "Schritt %s wartet auf %s (%s)." % [sid, d, dep.status]}
	var money := float(st.braucht.get("geld", 0.0))
	if money > sim.company(cid).ledger.cash:
		st.status = "blockiert"
		st.ergebnis = "zu wenig Bargeld (%s benötigt)" % Catalog.money(money)
		return {"ok": false, "msg": "Schritt %s: %s." % [sid, st.ergebnis]}
	var r: Dictionary = sim.executor.execute(cid, st.aktion, key, "plan", {"plan": p.id, "step": sid})
	st.action_key = key
	if not r.ok:
		st.status = "blockiert"
		st.ergebnis = str(r.msg).left(160)
		p.status = "neu_planen"
		p.hinweis = "Schritt %s scheiterte: %s" % [sid, st.ergebnis]
		sim.notify(cid, "Plan %s: %s" % [p.id, p.hinweis])
	elif r.has("task_id") or r.get("pending", false):
		st.status = "laeuft"
		st.task_id = str(r.get("task_id", ""))
		st.ergebnis = str(r.msg).left(160)
	else:
		st.status = "erledigt"
		st.ergebnis = str(r.msg).left(160)
	_check_done(cid)
	return {"ok": r.ok, "msg": "Planschritt %s: %s" % [sid, r.msg]}


func cancel(cid: int, reason: String) -> Dictionary:
	var p := current(cid)
	if p.is_empty():
		return {"ok": false, "msg": "Kein aktiver Plan."}
	_archive(cid, p, "abgebrochen: " + reason.left(120))
	plans.erase(cid)
	return {"ok": true, "msg": "Plan %s abgebrochen (bereits entstandene Kosten bleiben)." % p.id}


## Besuch abgeschlossen (Ausfuehrung bei Ankunft): laufenden Schritt aktualisieren.
func visit_done(cid: int, key: String, r: Dictionary) -> void:
	var p := current(cid)
	if p.is_empty() or key == "":
		return
	for st in p.schritte:
		if st.action_key == key and st.status == "laeuft" and st.task_id == "":
			st.status = "erledigt" if r.ok else "blockiert"
			st.ergebnis = ("vor Ort: " + str(r.msg)).left(160)
			if not r.ok:
				p.status = "neu_planen"
				p.hinweis = "Schritt %s scheiterte vor Ort: %s" % [st.id, r.msg]
				sim.notify(cid, "Plan %s: %s" % [p.id, p.hinweis])
	_check_done(cid)


## Alle 5 Spielminuten: Abbruchbedingungen, laufende Aufgaben, entfallene Voraussetzungen.
func tick() -> void:
	for cid in plans.keys():
		var p: Dictionary = plans[cid]
		if p.status != "aktiv":
			continue
		var c: Company = sim.company(cid)
		for cnd in p.abbruch:
			var hit := false
			match cnd.typ:
				"bargeld_unter": hit = c.ledger.cash < cnd.wert
				"ruf_unter": hit = c.reputation < cnd.wert
				"restzeit_unter_min": hit = sim.remaining_real_min < cnd.wert
				"auftrag_gescheitert": hit = c.stats.failed > int(p.failed_at_start)
				"arbeiter_verloren": hit = _lost(cid) > int(p.lost_at_start)
				"fahrzeug_ausgefallen": hit = sim.company_vehicles(cid).any(func(v): return v.state == "broken")
			if hit:
				_replan(cid, "Abbruchbedingung erreicht: %s %s" % [cnd.typ, str(cnd.wert) if cnd.wert != 0 else ""])
				break
		for st in p.schritte:
			if st.status == "laeuft" and st.task_id != "":
				var t: WorkerTask = sim.personnel.tasks.get(st.task_id)
				if t and t.is_final():
					st.status = "erledigt" if t.status == "abgeschlossen" else "blockiert"
					st.ergebnis = "%s: %s" % [t.status, t.report]
					if st.status == "blockiert":
						_replan(cid, "Schritt %s: Aufgabe %s %s" % [st.id, t.id, t.status])
			elif st.status == "offen" and st.has("aktion"):
				var gone := _missing_reference(cid, st.aktion)
				if gone != "":
					st.status = "blockiert"
					st.ergebnis = "Voraussetzung entfallen: " + gone
					_replan(cid, "Schritt %s: %s" % [st.id, st.ergebnis])
		_check_done(cid)


func _missing_reference(cid: int, act: Dictionary) -> String:
	if act.get("contract_id") != null:
		var k: Contract = sim.contracts.get(str(act.contract_id))
		if k == null or k.status in ["failed", "expired", "cancelled", "delivered"] or (k.owner >= 0 and k.owner != cid):
			return "Auftrag %s nicht mehr verfügbar" % act.contract_id
	if act.get("vehicle_id") != null and str(act.get("action", "")) != "attempt_vehicle_sabotage":
		var v: FleetVehicle = sim.vehicles.get(int(act.vehicle_id))
		if v == null or v.owner != cid:
			return "Fahrzeug #%s nicht mehr vorhanden" % str(act.vehicle_id)
	if act.get("worker_id") != null:
		var w: Worker = sim.personnel.workers.get(str(act.worker_id))
		var recruit := str(act.get("action", "")) in ["recruit_worker", "recruit_foreman"]
		if w == null or w.lost or (recruit and w.employer >= 0) or (not recruit and w.employer != cid):
			return "Arbeiter %s nicht verfügbar" % str(act.worker_id)
	if act.get("offer_id") != null and str(act.get("action", "")) == "buy_vehicle":
		if sim.resources.offers.get(str(act.offer_id), {}).get("status", "") != "verfügbar":
			return "Fahrzeugangebot %s verkauft" % act.offer_id
	return ""


func _replan(cid: int, why: String) -> void:
	var p: Dictionary = plans[cid]
	if p.status == "neu_planen":
		return
	p.status = "neu_planen"
	p.hinweis = why
	sim.log_event("%s: Plan %s muss überprüft werden – %s" % [sim.company(cid).player_name, p.id, why], "plan", cid)
	sim.notify(cid, "Plan %s überprüfen: %s" % [p.id, why])


func _check_done(cid: int) -> void:
	var p := current(cid)
	if p.is_empty() or p.status != "aktiv":
		return
	if p.schritte.all(func(st): return st.status in ["erledigt", "uebersprungen"]):
		p.status = "abgeschlossen"
		p.hinweis = "Alle Schritte erledigt. Gewinnänderung seit Planstart: %s" % Catalog.money(sim.company(cid).ledger.profit() - float(p.gewinn_bei_start))
		sim.log_event("%s schließt Plan %s ab. %s" % [sim.company(cid).player_name, p.id, p.hinweis], "plan", cid)
		sim.notify(cid, "Plan %s abgeschlossen. %s" % [p.id, p.hinweis])


func _archive(cid: int, p: Dictionary, outcome: String) -> void:
	var h: Array = history.get(cid, [])
	var copy := p.duplicate(true)
	copy["ausgang"] = outcome
	copy["gewinn_aenderung"] = sim.company(cid).ledger.profit() - float(p.gewinn_bei_start)
	h.append(copy)
	history[cid] = h.slice(-5)


func _step(cid: int, sid: String) -> Dictionary:
	for st in current(cid).get("schritte", []):
		if st.id == sid:
			return st
	return {}


func _lost(cid: int) -> int:
	return sim.company(cid).key_events.filter(func(e): return str(e).contains("Personalverlust")).size()


## Kompakte Sicht fuer die Beobachtung.
func summary(cid: int) -> Dictionary:
	var p := current(cid)
	if p.is_empty():
		return {"status": "kein Plan"}
	var runnable: Array = []
	for st in p.schritte:
		if st.status in ["offen", "blockiert"] and st.has("aktion") \
				and st.abhaengig_von.all(func(d): return _step(cid, d).get("status", "") in ["erledigt", "uebersprungen"]):
			runnable.append(st.id)
	return {"id": p.id, "ziel": p.ziel, "status": p.status, "hinweis": p.hinweis, "nutzen": p.nutzen, "risiken": p.risiken,
		"abbruch": p.abbruch, "schritte": p.schritte.map(func(st): return {"id": st.id, "text": st.text, "status": st.status,
			"ergebnis": st.ergebnis, "abhaengig_von": st.abhaengig_von, "aktion": st.get("aktion", {}).get("action", "")}),
		"jetzt_ausfuehrbar": runnable, "gewinn_seit_start": int(sim.company(cid).ledger.profit() - float(p.gewinn_bei_start))}


func to_dict() -> Dictionary:
	var ps := {}
	for cid in plans:
		ps[str(cid)] = plans[cid]
	var hs := {}
	for cid in history:
		hs[str(cid)] = history[cid]
	return {"plans": ps, "history": hs, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	plans.clear()
	for cid in d.get("plans", {}):
		plans[int(cid)] = d.plans[cid]
	history.clear()
	for cid in d.get("history", {}):
		history[int(cid)] = d.history[cid]
	next_id = int(d.get("next_id", 1))
