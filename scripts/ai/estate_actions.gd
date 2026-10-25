class_name EstateActions
extends RefCounted
## KI-Aktionen fuer Grundstueck und Betriebshof. Liefert {} zurueck, wenn die Aktion nicht hierher gehoert.

const SCHEMA := {
	"inspect_plot": {"params": {"plot_id": "int?"}, "desc": "Grundstück, Einrichtungen, Kapazitäten, gültige Bauplätze und Erweiterungsflächen ansehen."},
	"expand_plot": {"params": {"plot_id": "int", "art": "string?"}, "desc": "Angrenzende Fläche kaufen (art=kaufen, Grund und Boden) oder pachten (art=pachten)."},
	"place_building": {"params": {"plot_id": "int", "typ": "string", "x": "int", "y": "int", "rot": "int?", "bau": "string?"},
		"desc": "Einrichtung auf eigenem Grundstück errichten (rot 0|90; bau=extern: Baufirma +40 %, Material geliefert | eigen: günstiger, Material selbst anliefern, Arbeiter mit assign_building_staff). Bauvorschläge siehe betriebshof.bauvorschlaege_xy_rot ([x, y, rot])."},
	"upgrade_building": {"params": {"building_id": "string"}, "desc": "Einrichtung ausbauen (Büro bis Stufe 4, Werkstatt/Rampe/Mietbüro bis 2)."},
	"remove_building": {"params": {"building_id": "string"}, "desc": "Einrichtung zurückbauen (Restbuchwert wird abgeschrieben, 15 % Abrisskosten)."},
	"assign_parking": {"params": {"vehicle_id": "int", "building_id": "string"}, "desc": "Fahrzeug einem Stellplatz/einer Halle zuordnen (Halle schützt vor Sabotage)."},
	"assign_loading_bay": {"params": {"vehicle_id": "int", "building_id": "string"}, "desc": "Bevorzugte Laderampe für ein Fahrzeug festlegen."},
	"schedule_maintenance": {"params": {"vehicle_id": "int", "worker_id": "string?"},
		"desc": "Wartung in der eigenen Werkstatt: Fahrzeug fährt auf den Hof, Mechaniker repariert dort doppelt so schnell (Ersatzteile + freier Werkstattplatz nötig)."},
	"purchase_fuel_stock": {"params": {"amount": "number"}, "desc": "Treibstoff für den eigenen Tank liefern lassen (günstigste Tankstelle + 5 % Lieferung; Tankgröße beachten)."},
	"offer_office_rental": {"params": {"building_id": "string", "einheiten": "int", "miete_pro_tag": "number", "mindest_tage": "number?"},
		"desc": "Freie vermietbare Büroeinheiten ausschreiben; Interessenten melden sich je nach Lage und Preis."},
	"accept_tenant": {"params": {"tenant_id": "string"}, "desc": "Mietinteressenten annehmen (Mietvertrag)."},
	"assign_building_staff": {"params": {"building_id": "string", "worker_ids": "array"},
		"desc": "Eigene Arbeiter einer Baustelle (Eigenbau) oder einer Laderampe (Verladen) zuteilen."},
	"wash_vehicle": {"params": {"vehicle_id": "int"}, "desc": "Fahrzeug auf dem Waschplatz waschen (20 min, 30 EUR)."},
	"train_worker": {"params": {"worker_id": "string", "faehigkeit": "string"}, "desc": "Weiterbildung im Schulungsraum (120 min, 800 EUR): Fähigkeit +1 (max. 3)."},
}

var sim
var ex


func setup(simulation, executor) -> void:
	sim = simulation
	ex = executor


func run(cid: int, name: String, a: Dictionary) -> Dictionary:
	var E: Estate = sim.estate
	var c: Company = sim.company(cid)
	match name:
		"inspect_plot":
			var s := E.summary(cid)
			return {"ok": true, "msg": "Grundstücke %s; Kapazität %s; Einrichtungen %d; Bauvorschläge für %s." % [str(s.grundstuecke),
				str(s.kapazitaet), s.einrichtungen.size(), ", ".join(s.bauvorschlaege_xy_rot.keys())]}
		"expand_plot":
			return E.expand(cid, ActionExecutor._i(a.plot_id), "pachten" if str(a.get("art", "kaufen")) == "pachten" else "kaufen")
		"place_building":
			return E.place(cid, ActionExecutor._i(a.plot_id), str(a.typ), ActionExecutor._i(a.x), ActionExecutor._i(a.y),
				90 if ActionExecutor._i(a.get("rot", 0)) == 90 else 0, str(a.get("bau", "extern")))
		"upgrade_building":
			return E.upgrade(cid, str(a.building_id))
		"remove_building":
			return E.remove(cid, str(a.building_id))
		"assign_parking", "assign_loading_bay":
			var v: FleetVehicle = ex._own_vehicle(cid, ActionExecutor._i(a.vehicle_id))
			var f: Dictionary = E.facilities.get(str(a.building_id), {})
			var want: Array = ["stellplatz", "garage"] if name == "assign_parking" else ["laderampe"]
			if v == null or f.is_empty() or f.owner != cid or f.typ not in want or f.status != "fertig":
				return {"ok": false, "msg": "Fahrzeug oder %s ungültig." % ("Stellplatz" if name == "assign_parking" else "Laderampe")}
			if name == "assign_parking":
				var used: int = sim.vehicles.values().filter(func(x): return x.parking == f.id and x != v).size()
				if used >= 2:
					return {"ok": false, "msg": "%s ist voll belegt (2 Plätze)." % f.id}
				v.parking = f.id
			else:
				v.bay_pref = f.id
			return {"ok": true, "msg": "#%d → %s (%s)." % [v.id, f.id, Estate.FACILITIES[f.typ].name]}
		"schedule_maintenance":
			var v: FleetVehicle = ex._own_vehicle(cid, ActionExecutor._i(a.vehicle_id))
			if v == null:
				return {"ok": false, "msg": "Fahrzeug gehört dir nicht."}
			if E.workshop_bays(cid) == 0:
				return {"ok": false, "msg": "Keine eigene Werkstatt (place_building typ=werkstatt) – sonst repair_vehicle nutzen."}
			if v.state not in ["idle", "returning", "broken"] or not v.stops.is_empty():
				return {"ok": false, "msg": "#%d ist im Einsatz." % v.id}
			var wid := str(a.get("worker_id", "")) if a.get("worker_id") != null else ""
			if wid == "":
				var best: Worker = null
				for w in sim.personnel.employed(cid):
					if int(w.skills.reparieren) > 0 and sim.personnel.can_take(w, "reparieren") == "" and (best == null or int(w.skills.reparieren) > int(best.skills.reparieren)):
						best = w
				if best == null:
					return {"ok": false, "msg": "Kein freier Mechaniker."}
				wid = best.id
			if v.state != "broken" and E.on_plot(cid, v.pos) < 0:
				if sim.driver_of(v) == null:
					return {"ok": false, "msg": "#%d hat keinen Fahrer für die Fahrt zum Hof." % v.id}
				sim.route(v, sim.depot_road(cid), "returning")
			var r: Dictionary = ex.worker_actions.run(cid, "assign_worker_task", {"kind": "reparieren", "vehicle_id": v.id, "worker_id": wid, "priority": 1}, true)
			if r.ok:
				sim.personnel.tasks[r.task_id].target["werkstatt"] = true
				r.msg += " (Werkstatt auf dem Hof)"
			return r
		"purchase_fuel_stock":
			var amount := floorf(ActionExecutor._f(a.amount))
			if amount <= 0.0:
				return {"ok": false, "msg": "Menge muss positiv sein."}
			if c.fuel + amount > c.fuel_cap:
				return {"ok": false, "msg": "Tank fasst nur %d l (Vorrat %d l) – Betriebstankstelle bauen." % [int(c.fuel_cap), int(c.fuel)]}
			var best := {}
			for s in sim.resources.supplies.values():
				if s.kind == "fuel" and float(s.stock) >= amount and (best.is_empty() or sim.resources.fuel_price(s) < sim.resources.fuel_price(best)):
					best = s
			if best.is_empty():
				return {"ok": false, "msg": "Keine Tankstelle hat %d l vorrätig." % int(amount)}
			var r: Dictionary = sim.resources.buy_supplies(cid, best.id, amount)
			if r.ok:
				var fee: float = amount * sim.resources.fuel_price(best) * 0.05
				c.ledger.book("supplies", -fee, true, "Tanklieferung", sim.game_min)
				r.msg += " Lieferung %s." % Catalog.money(fee)
			return r
		"offer_office_rental":
			return E.offer_rental(cid, str(a.building_id), ActionExecutor._i(a.einheiten), ActionExecutor._f(a.miete_pro_tag),
				ActionExecutor._f(a.get("mindest_tage", 2)) if a.get("mindest_tage") != null else 2.0)
		"accept_tenant":
			return E.accept_tenant(cid, str(a.tenant_id))
		"assign_building_staff":
			var f: Dictionary = E.facilities.get(str(a.building_id), {})
			if f.is_empty() or f.owner != cid:
				return {"ok": false, "msg": "Gebäude %s gehört dir nicht." % a.building_id}
			var ids: Array = a.worker_ids if a.worker_ids is Array else []
			var done: Array = []
			for raw in ids:
				var kind := "bauen" if f.status in ["im_bau"] else ("verladen" if f.typ == "laderampe" else "")
				if kind == "":
					return {"ok": false, "msg": "%s ist weder Baustelle (Eigenbau) noch Laderampe." % f.id}
				var target := {"kind": kind, "worker_id": str(raw), "building_id": f.plot}
				var r: Dictionary = ex.worker_actions.run(cid, "assign_worker_task", target, true)
				if r.ok:
					if kind == "bauen":
						sim.personnel.tasks[r.task_id].target["facility"] = f.id
					done.append(str(raw))
			return {"ok": not done.is_empty(), "msg": "%d Arbeiter %s zugeteilt: %s." % [done.size(), f.id, ", ".join(done)]}
		"wash_vehicle":
			var v: FleetVehicle = ex._own_vehicle(cid, ActionExecutor._i(a.vehicle_id))
			if v == null or E.done(cid, "waschplatz").is_empty():
				return {"ok": false, "msg": "Fahrzeug ungültig oder kein Waschplatz."}
			if v.state != "idle" or E.on_plot(cid, v.pos) < 0:
				return {"ok": false, "msg": "#%d muss frei auf dem eigenen Hof stehen." % v.id}
			c.ledger.book("supplies", -30.0, true, "Wäsche #%d" % v.id, sim.game_min)
			v.state = "washing"
			v.timer = 20.0
			v.clean_until = sim.game_min + 20.0 + 1440.0
			return {"ok": true, "msg": "#%d wird gewaschen (20 min)." % v.id}
		"train_worker":
			var w: Worker = sim.personnel.workers.get(str(a.worker_id))
			var skill := str(a.faehigkeit)
			if w == null or w.employer != cid or w.lost:
				return {"ok": false, "msg": "Arbeiter gehört dir nicht."}
			if E.done(cid, "schulung").is_empty():
				return {"ok": false, "msg": "Kein Schulungsraum."}
			if skill not in Worker.SKILLS or int(w.skills.get(skill, 0)) >= 3:
				return {"ok": false, "msg": "Fähigkeit unbekannt oder bereits Stufe 3."}
			if c.ledger.cash < 800.0:
				return {"ok": false, "msg": "Schulung kostet 800 EUR."}
			var r: Dictionary = ex.worker_actions.run(cid, "assign_worker_task", {"kind": "schulung", "worker_id": w.id, "building_id": c.depots[0]}, true)
			if r.ok:
				c.ledger.book("training", -800.0, true, "Schulung %s (%s)" % [w.name, skill], sim.game_min)
				sim.personnel.tasks[r.task_id].target["skill"] = skill
			return r
	return {}
