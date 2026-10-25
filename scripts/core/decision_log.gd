class_name DecisionLog
extends RefCounted
## Entscheidungsprotokoll fuer Zuschauer. Jede beabsichtigte Aktion wird mit Regelpruefung und tatsaechlicher
## Ausfuehrung festgehalten und ueber IDs (Aktion, Aufgabe, Auftrag, Fahrzeug, Arbeiter, Plan) mit spaeteren,
## gemessenen Folgen verknuepft. Herkunft: api (Modell), plan (Planschritt), fallback (Ersatz/Demo),
## foreman (Vorarbeiter-Routine), auto (Simulation), spectator (Ereignisregler).
## Es werden nur kurze, vom Modell ausdruecklich formulierte Begruendungen gespeichert – keine Gedankenketten.

const MAX := 600
const ORIGIN_TEXT := {"api": "Strategie (API-Modell)", "plan": "Planschritt", "fallback": "Ersatzmodus/Demo",
	"foreman": "Vorarbeiter-Routine", "auto": "Simulation", "spectator": "Zuschauer-Ereignis", "world": "Stadt (automatisch)"}

var sim
var entries: Array = []
var next_id := 1
var context := {}        # Firma -> {wahrgenommen, ziel, begruendung} der gerade verarbeiteten Antwort


func setup(simulation) -> void:
	sim = simulation


func set_context(cid: int, perceived: Array, goal: String, reason: String) -> void:
	context[cid] = {"wahrgenommen": perceived.slice(-3).map(func(e): return str(e).left(100)), "ziel": goal.left(120),
		"begruendung": reason.left(240)}


func clear_context(cid: int) -> void:
	context.erase(cid)


func record(cid: int, origin: String, action: Dictionary, result: Dictionary, key: String) -> void:
	var ctx: Dictionary = context.get(cid, {}) if origin in ["api", "plan", "fallback"] else {}
	var refs := {}
	for k in ["contract_id", "vehicle_id", "worker_id", "offer_id", "step_id", "task_id"]:
		if action.get(k) != null:
			refs[k] = action[k]
	if result.has("task_id"):
		refs["task_id"] = result.task_id
	var rk: Contract = sim.contracts.get(str(refs.get("contract_id", "")))
	if rk != null:   # Ursachenkette: Ereignis -> Kundenanfrage -> Entscheidung
		if rk.cause != "":
			refs["event_id"] = rk.cause
		if rk.requester != "":
			refs["person_id"] = rk.requester
	if str(action.get("action", "")) == "buy_vehicle" and result.ok and not result.get("pending", false):
		refs["vehicle_id"] = sim.next_vehicle_id - 1
	var e := {"id": "D%d" % next_id, "t": sim.game_min, "step": sim.step_count, "company": cid, "herkunft": origin,
		"wahrgenommen": ctx.get("wahrgenommen", []), "ziel": ctx.get("ziel", ""), "begruendung": ctx.get("begruendung", ""),
		"aktion": _compact(action), "pruefung": "ok" if result.ok else "abgelehnt", "ergebnis": str(result.get("msg", "")).left(200),
		"ausgefuehrt": "vorgemerkt (Besuch)" if result.get("pending", false) else ("ausgeführt" if result.ok else "nicht ausgeführt"),
		"key": key, "refs": refs, "plan": sim.plans.current(cid).get("id", "")}
	next_id += 1
	entries.append(e)
	if entries.size() > MAX:
		entries.pop_front()


## Vorgang ohne KI-Entscheidung (Vorarbeiter, Simulation, Zuschauer).
func note(cid: int, origin: String, text: String, refs: Dictionary = {}) -> void:
	entries.append({"id": "D%d" % next_id, "t": sim.game_min, "step": sim.step_count, "company": cid, "herkunft": origin,
		"wahrgenommen": [], "ziel": "", "begruendung": "", "aktion": "", "pruefung": "–", "ergebnis": text.left(200),
		"ausgefuehrt": text.left(120), "key": "", "refs": refs, "plan": ""})
	next_id += 1
	if entries.size() > MAX:
		entries.pop_front()


## Spaeter messbare Folgen (aus dem aktuellen Zustand berechnet, nicht behauptet).
func consequences(e: Dictionary) -> String:
	var refs: Dictionary = e.refs
	var parts: Array = []
	if refs.has("contract_id"):
		var k: Contract = sim.contracts.get(str(refs.contract_id))
		if k:
			match k.status:
				"delivered": parts.append("Auftrag %s geliefert: +%s" % [k.id, Catalog.money(k.paid)])
				"failed": parts.append("Auftrag %s gescheitert: −%s Strafe" % [k.id, Catalog.money(k.reward * Catalog.FAIL_PENALTY_SHARE)])
				"cancelled": parts.append("Auftrag %s bei Spielende unvollständig: keine Vergütung" % k.id)
				_: parts.append("Auftrag %s: %s (%d/%d geliefert)" % [k.id, k.status, k.delivered_qty, k.qty])
		elif e.pruefung == "ok":
			parts.append("Auftrag %s abgeschlossen und archiviert" % refs.contract_id)
	if refs.has("person_id") or refs.has("event_id"):
		var why: Array = []
		var person: Dictionary = sim.residents.people.get(str(refs.get("person_id", "")), {})
		if not person.is_empty():
			why.append("Kunde %s (%s)" % [person.name, person.role])
		if refs.has("event_id"):
			why.append("ausgelöst durch %s" % sim.world_events.title_of(str(refs.event_id)))
		parts.append(", ".join(why))
	if refs.has("task_id"):
		var t: WorkerTask = sim.personnel.tasks.get(str(refs.task_id))
		if t:
			parts.append("Aufgabe %s: %s (%s)%s" % [t.id, t.status, t.report.left(60), (", Kosten " + Catalog.money(t.cost)) if t.cost > 0 else ""])
	if refs.has("vehicle_id") and str(e.aktion).begins_with("buy_vehicle"):
		var v: FleetVehicle = sim.vehicles.get(int(refs.vehicle_id))
		if v:
			parts.append("#%d: %d Tiles gefahren, Buchwert %s" % [v.id, v.odometer, Catalog.money(v.book_value)])
	if str(e.aktion).begins_with("set_plan") or str(e.aktion).begins_with("execute_plan_step"):
		var p: Dictionary = sim.plans.current(e.company)
		if p.get("id", "") == e.plan:
			parts.append("Plan %s %s, Gewinnänderung seit Start %s" % [p.id, p.status, Catalog.money(sim.company(e.company).ledger.profit() - float(p.gewinn_bei_start))])
		else:
			for h in sim.plans.history.get(e.company, []):
				if h.id == e.plan:
					parts.append("Plan %s %s, Gewinnänderung %s" % [h.id, h.ausgang, Catalog.money(h.gewinn_aenderung)])
	return "; ".join(parts)


static func _compact(a: Dictionary) -> String:
	var s := str(a.get("action", ""))
	var args: Array = []
	for k in a:
		if k != "action" and k not in ["schritte", "stopps", "text", "note", "nutzen", "risiken", "abbruch"]:
			args.append("%s=%s" % [k, str(a[k]).left(30)])
	if a.has("stopps"):
		args.append("%d Stopps" % a.stopps.size())
	if a.has("schritte"):
		args.append("%d Schritte" % a.schritte.size())
	return "%s(%s)" % [s, ", ".join(args)]


func to_dict() -> Dictionary:
	return {"entries": entries.slice(-300), "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	entries = d.get("entries", [])
	next_id = int(d.get("next_id", 1))
