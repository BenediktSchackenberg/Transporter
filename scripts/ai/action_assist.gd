class_name ActionAssist
extends RefCounted
## Ergaenzt unvollstaendige Aktionen kleiner Sprachmodelle (z. B. ein lokales 9B-Modell), wenn die Absicht eindeutig ist:
## fehlende Parameter werden aus dem Zustand des eigenen Unternehmens abgeleitet. Es wird nie etwas geraten, was Geld kostet oder
## eine Wahl zwischen mehreren sinnvollen Moeglichkeiten verlangt; es werden nur Luecken gefuellt (Fahrzeug ohne Fahrer, Auftrag ohne
## Fahrzeug, offener Bewerber). Die ergaenzten Felder stehen in `_ergaenzt`, damit das Entscheidungsprotokoll sie ausweist.

var sim


func setup(simulation) -> void:
	sim = simulation


func complete(cid: int, a: Dictionary) -> Dictionary:
	var name := str(a.get("action", a.get("type", "")))
	var out := a.duplicate()
	var added: Array = []
	match name:
		"assign_worker_task":
			if not out.has("kind") and out.has("worker_id"):
				var w: Worker = sim.personnel.workers.get(str(out.worker_id))
				var v := _undriven_vehicle(cid) if w != null and w.employer == cid else null
				if v != null:
					out["kind"] = "fahren"
					out["vehicle_id"] = out.get("vehicle_id", v.id)
					added.append("kind=fahren")
					if not out.has("contract_id"):
						var k := _unassigned_contract(cid, v)
						if k != "":
							out["contract_id"] = k
							added.append("contract_id")
		"assign_vehicle", "assign_transport":
			if not out.has("contract_id"):
				var v2: FleetVehicle = sim.vehicles.get(int(out.vehicle_id)) if out.has("vehicle_id") else _idle_vehicle(cid)
				if v2 != null:
					var k2 := _unassigned_contract(cid, v2)
					if k2 != "":
						out["contract_id"] = k2
						added.append("contract_id")
			if not out.has("vehicle_id") and out.has("contract_id"):
				var v3 := _idle_vehicle(cid, str(out.contract_id))
				if v3 != null:
					out["vehicle_id"] = v3.id
					added.append("vehicle_id")
		"recruit_worker":
			if not out.has("worker_id"):
				var w2 := _best_applicant(false)
				if w2 != null:
					out["worker_id"] = w2.id
					added.append("worker_id")
		"recruit_foreman":
			if not out.has("worker_id"):
				var w3 := _best_applicant(true)
				if w3 != null:
					out["worker_id"] = w3.id
					added.append("worker_id")
	if not added.is_empty():
		out["_ergaenzt"] = added
	return out


## Fahrzeug ohne Fahrer (kein Arbeiter mit Fahraufgabe darauf).
func _undriven_vehicle(cid: int) -> FleetVehicle:
	for v in sim.company_vehicles(cid):
		if v.state in ["idle", "returning"] and sim.personnel.driver_of(v.id) == null:
			return v
	return null


## Fahrzeug mit Fahrer ohne Auftrag; mit `contract_id` eines, das die Anforderung erfuellt.
func _idle_vehicle(cid: int, contract_id: String = "") -> FleetVehicle:
	var k: Contract = sim.contracts.get(contract_id) if contract_id != "" else null
	for v in sim.company_vehicles(cid):
		if v.state == "idle" and v.stops.is_empty() and v.contract_id == "" and sim.personnel.driver_of(v.id) != null and (k == null or k.vehicle_ok(v.model)):
			return v
	return null


func _unassigned_contract(cid: int, v: FleetVehicle) -> String:
	var ids: Array = []
	for k in sim.contracts.values():
		if k.owner == cid and k.status == "accepted" and k.vehicle_ok(v.model):
			ids.append(k.id)
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""


## Guenstigster am Markt verfuegbarer Bewerber (Vorarbeiter oder Arbeiter).
func _best_applicant(foreman: bool) -> Worker:
	var best: Worker = null
	for w in sim.personnel.available():
		if (w.role == "foreman") != foreman or w.lost:
			continue
		if best == null or w.hire_fee < best.hire_fee:
			best = w
	return best
