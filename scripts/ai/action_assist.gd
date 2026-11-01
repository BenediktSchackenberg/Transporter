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
	if name in ["assign_vehicle", "assign_transport", "assign_worker_task"]:
		# Erfundene oder fremde Fahrzeug-/Auftrags-IDs verwerfen, damit die Luecken unten sinnvoll gefuellt werden
		if out.has("vehicle_id") and not (out.vehicle_id is String and not str(out.vehicle_id).is_valid_int()):   # Unsinn bleibt Unsinn: Schema meldet ihn
			var ov: FleetVehicle = sim.vehicles.get(ActionExecutor._i(out.vehicle_id)) if out.vehicle_id != null else null
			if ov == null or ov.owner != cid:
				out.erase("vehicle_id")
				added.append("vehicle_id verworfen")
		if name != "assign_worker_task" and out.has("contract_id"):
			var oc: Contract = sim.contracts.get(str(out.contract_id))
			if oc == null:   # nur erfundene IDs; Unterauftraege anderer Firmen sind erlaubt
				out.erase("contract_id")
				added.append("contract_id verworfen")
	match name:
		"assign_worker_task":
			var kind_given := str(out.get("kind", ""))
			var kl := kind_given.to_lower()
			if kl.contains("fuel") or kl.contains("tank"):
				# Tanken ist keine Arbeiteraufgabe: feste Nachtank-Regel anlegen (falls noch keine besteht)
				var cf: Company = sim.company(cid)
				var nv := maxi(1, sim.company_vehicles(cid).size())
				if cf.fuel_rule.is_empty():
					return {"action": "schedule_refueling", "below_l": 250 * nv, "buy_l": 500 * mini(2, nv),
						"_ergaenzt": ["statt Tank-Aufgabe: Nachtank-Regel"]}
				return {"action": "wait", "_ergaenzt": ["Nachtank-Regel besteht bereits"]}
			if kl in ["transport", "deliver", "delivery", "lieferung", "liefern"]:
				out["kind"] = "fahren"
				kind_given = "fahren"
				added.append("kind=fahren")
			if kind_given == "" and not out.has("worker_id"):
				# Weder Art noch Arbeiter genannt: Fahrzeug ohne Fahrer mit freiem Arbeiter besetzen
				var v0 := _undriven_vehicle(cid)
				var w0 := _free_driver(cid)
				if v0 != null and w0 != null:
					out["kind"] = "fahren"
					out["worker_id"] = w0.id
					out["vehicle_id"] = v0.id
					added.append("kind=fahren")
					added.append("worker_id")
					added.append("vehicle_id")
					var k0 := _unassigned_contract(cid, v0)
					if k0 != "" and not out.has("contract_id"):
						out["contract_id"] = k0
						added.append("contract_id")
			elif kind_given == "" and out.has("worker_id"):
				var w: Worker = sim.personnel.workers.get(str(out.worker_id))
				if w != null and int(w.skills.get("fahren", 0)) < 1:
					var alt := _free_driver(cid)   # genannter Arbeiter kann nicht fahren: einen fahrtauglichen nehmen
					if alt != null:
						w = alt
						out["worker_id"] = alt.id
						added.append("worker_id getauscht")
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
			elif str(out.get("kind", "")) == "fahren":
				# Fahraufgabe mit fehlendem oder fremdem Fahrzeug / ohne Arbeiter: Luecken schliessen
				var vv: FleetVehicle = sim.vehicles.get(ActionExecutor._i(out.get("vehicle_id", -1))) if out.get("vehicle_id") != null else null
				if vv == null or vv.owner != cid:
					vv = _undriven_vehicle(cid)
					if vv != null:
						out["vehicle_id"] = vv.id
						added.append("vehicle_id")
				if vv != null and not out.has("worker_id") and not out.has("foreman_id"):
					var wd := _free_driver(cid)
					if wd != null:
						out["worker_id"] = wd.id
						added.append("worker_id")
		"assign_vehicle", "assign_transport":
			if not out.has("contract_id"):
				var v2: FleetVehicle = sim.vehicles.get(ActionExecutor._i(out.vehicle_id)) if out.has("vehicle_id") else _idle_vehicle(cid)
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
				else:
					# Kein Fahrzeug mit Fahrer frei: einen freien Arbeiter ans Steuer eines passenden Fahrzeugs setzen,
					# der Auftrag wird mit der Fahraufgabe zugewiesen.
					var k4: Contract = sim.contracts.get(str(out.contract_id))
					var v4 := _undriven_vehicle(cid, k4)
					var w4 := _free_driver(cid)
					if k4 != null and v4 != null and w4 != null:
						return {"action": "assign_worker_task", "kind": "fahren", "worker_id": w4.id, "vehicle_id": v4.id,
							"contract_id": k4.id, "_ergaenzt": ["statt assign_transport: Fahrer %s auf #%d" % [w4.name, v4.id]]}
		"buy_vehicle":
			var c: Company = sim.company(cid)
			if sim.company_vehicles(cid).size() >= c.fleet_limit() and c.ledger.cash > 6000.0 and not _parking_in_construction(cid):
				var site: int = c.depots[0]
				var sug: Dictionary = sim.estate.suggestions(cid, site)
				if sug.has("stellplatz"):
					var xy: Array = sug["stellplatz"]
					return {"action": "place_building", "plot_id": site, "typ": "stellplatz", "x": xy[0], "y": xy[1], "rot": xy[2],
						"_ergaenzt": ["statt buy_vehicle: Hof voll, Stellplatz gebaut"]}
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


## Fahrzeug ohne Fahrer (kein Arbeiter mit Fahraufgabe darauf); mit `k` eines, das die Anforderung des Auftrags erfuellt.
func _undriven_vehicle(cid: int, k: Contract = null) -> FleetVehicle:
	for v in sim.company_vehicles(cid):
		if v.state in ["idle", "returning"] and sim.personnel.driver_of(v.id) == null and (k == null or k.vehicle_ok(v.model)):
			return v
	return null


## Eigener Arbeiter, der fahren kann und gerade nichts zu tun hat (kein Fahrzeug, keine laufende Aufgabe).
func _free_driver(cid: int) -> Worker:
	var best: Worker = null
	for w in sim.personnel.employed(cid):
		if w.vehicle_id >= 0 or int(w.skills.get("fahren", 0)) < 1 or sim.personnel.can_take(w, "fahren") != "":
			continue
		if best == null or int(w.skills.get("fahren", 0)) > int(best.skills.get("fahren", 0)):
			best = w
	return best


func _parking_in_construction(cid: int) -> bool:
	for f in sim.estate.facilities.values():
		if f.owner == cid and f.typ == "stellplatz" and f.status == "im_bau":
			return true
	return false


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
