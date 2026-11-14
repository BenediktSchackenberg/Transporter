class_name WorkerActions
extends RefCounted
## Aktionen rund um Personal, Ressourcen und Arbeiter-Sabotage. Wird vom ActionExecutor zuerst gefragt;
## liefert {} zurueck, wenn die Aktion nicht hierher gehoert.

const SPARE_STAFF := 2   # Leute ohne Fahrzeug ueber die Flottengroesse hinaus (Verlader, Mechaniker), bevor das Modell nicht weiter anwerben darf

const SCHEMA := {
	"inspect_resource": {"params": {"resource_id": "string"},
		"desc": "Details zu Arbeiter (W..), Fahrzeugangebot (F..), Bezugsquelle (S..), Auftrag (A..) oder Depotstandort (D<id>)."},
	"recruit_worker": {"params": {"worker_id": "string"}, "visit": true,
		"desc": "Verfügbaren Arbeiter anwerben; deine Figur geht zu ihm (wer zuerst kommt, bekommt ihn). Kostet Anwerbegebühr, danach Lohn."},
	"recruit_foreman": {"params": {"worker_id": "string"}, "visit": true, "desc": "Verfügbaren Vorarbeiter anwerben (teurer)."},
	"dismiss_worker": {"params": {"worker_id": "string"}, "desc": "Eigenen Arbeiter entlassen (offene Aufgaben werden abgebrochen)."},
	"assign_worker_task": {"params": {"kind": "string", "worker_id": "string?", "foreman_id": "string?", "vehicle_id": "int?",
		"contract_id": "string?", "site_id": "int?", "building_id": "int?", "company": "int?", "target_worker": "string?", "priority": "int?"},
		"desc": "Aufgabe erteilen: fahren(vehicle_id[,contract_id]), reparieren(vehicle_id), bewachen(site_id|vehicle_id), verladen(building_id), auskundschaften(company), unterstuetzen(target_worker), gehen(site_id|building_id). Ohne worker_id verteilt der Vorarbeiter (foreman_id)."},
	"cancel_worker_task": {"params": {"task_id": "string"}, "desc": "Aufgabe abbrechen (entstandene Kosten bleiben)."},
	"set_task_priority": {"params": {"task_id": "string", "priority": "int"}, "desc": "Priorität 1 (hoch) bis 3 (niedrig)."},
	"assign_foreman": {"params": {"foreman_id": "string", "worker_ids": "array", "site_id": "int?"},
		"desc": "Arbeiter einem Vorarbeiter unterstellen (max. 3 + 2×Organisation) und Standort (Depot) festlegen."},
	"set_foreman_orders": {"params": {"foreman_id": "string", "ziel": "string?", "prioritaet": "string?", "auto_driver": "bool?",
		"auto_repair": "bool?", "reassign_blocked": "bool?", "darf_teile_kaufen": "bool?", "repair_budget": "number?"},
		"desc": "Ziel und Befugnisse: prioritaet fristgerecht|kosten|auslastung; Fahrer einteilen, Reparaturen veranlassen, Aufgaben umverteilen, Ersatzteile kaufen; repair_budget = Geld für Routine. Investitionen/Sabotage nie."},
	"request_progress_report": {"params": {"foreman_id": "string"}, "desc": "Sofortigen Bericht des Vorarbeiters anfordern."},
	"hub_buy": {"params": {"item": "string", "qty": "int", "bahn": "bool?"},
		"desc": "Ware im zentralen Großlager kaufen (Preise unter grosslager). Bezahlt sofort; abholen musst du mit eigenem Fahrzeug (exklusiver Auftrag zum eigenen Depot). bahn true: Wagenplatz im Güterzug bis zum Bahnhof deiner Stadt buchen (60 % der Lkw-Fracht), dort holst du ab – kurzer Weg statt Fahrt zum Großlager."},
	"hub_sell": {"params": {"item": "string", "qty": "int"},
		"desc": "Ware aus deinem Depot an das Großlager verkaufen (Ankaufpreis). Du lieferst mit eigenem Fahrzeug, Zahlung bei Anlieferung."},
	"buy_supplies": {"params": {"resource_id": "string", "amount": "number", "lieferung": "string?"},
		"desc": "Treibstoff (Liter) an einer Tankstelle oder Ersatzteile in einer Werkstatt kaufen. Diesel wird gezapft (belegte Zapfsäulen = Wartezeit) und kommt erst später im Depot an: lieferung=liefern (Tankwagen, Gebühr, Standard) oder abholen (eigener Transportauftrag Tankstelle→Depot, ein Fahrzeug muss fahren). Ersatzteile sofort."},
	"guard_target": {"params": {"worker_id": "string", "site_id": "int?", "vehicle_id": "int?"},
		"desc": "Arbeiter bewacht ein eigenes Depot oder Fahrzeug (erhöht Entdeckungschance bei Sabotage)."},
	"attempt_vehicle_sabotage": {"params": {"worker_id": "string", "vehicle_id": "int"},
		"desc": "Regelwidrig! Eigener Arbeiter legt ein gesichtetes, stehendes Fremdfahrzeug lahm. 800 EUR, Abklingzeit. Wird er erwischt, ist er für die Partie verloren."},
	"schedule_rest": {"params": {"worker_id": "string", "hours": "number"},
		"desc": "Pause für einen eigenen Mitarbeiter einplanen (0,5–12 Stunden): keine neuen Aufgaben, schnellere Erholung. Nur wenn er gerade nichts tut."},
	"offer_training": {"params": {"worker_id": "string", "skill": "string"},
		"desc": "Externe Weiterbildung (1200 EUR, 4 Stunden Ausfall): Fähigkeit +1 bis Stufe 2 (fahren, verladen, reparieren, bewachen, malen), steigert Motivation und Marktlohn."},
	"request_replacement_worker": {"params": {"kind": "string"},
		"desc": "Personalvermittlung beauftragen (600 EUR, 1200 für Vorarbeiter): nach einem Spieltag wird ein passender driver|loader|mechanic|guard|foreman|maler angestellt."},
	"fund_maintenance": {"params": {"einrichtung_id": "string", "betrag": "number"},
		"desc": "Eigene Einrichtung (B..) instandhalten: der Betrag wird in Zustandspunkte umgesetzt. Verwahrloste Einrichtungen verursachen höhere Betriebskosten."},
	"commission_renovation": {"params": {"einrichtung_id": "string"},
		"desc": "Eigene Einrichtung vollständig renovieren (Zustand 100) durch eine Baufirma; Kosten nach Bedarf, +20 % Aufschlag."},
	"compare_fuel_options": {"params": {"liters": "number?"},
		"desc": "Tankstellen vergleichen: Preis, Entfernung zum Hauptdepot, Wartezeit an den Zapfsäulen, Gesamtkosten (Annahmen ausgewiesen) und Ersparnis gegenüber dem Notpreis."},
	"schedule_refueling": {"params": {"below_l": "number", "buy_l": "number", "station": "string?"},
		"desc": "Feste Nachtank-Regel: fällt dein Treibstoffvorrat unter below_l, kauft die Engine buy_l Liter (an station oder der günstigsten Tankstelle). below_l=0 löscht die Regel."},
	"negotiate_wage": {"params": {"worker_id": "string", "wage": "number"},
		"desc": "Lohn (EUR je Spielstunde) mit einem eigenen Mitarbeiter verhandeln. Er lehnt unter seinem Mindestlohn ab und nennt ihn; Kürzungen lehnt er ab. Unzufriedene Mitarbeiter (obs.personal_lage) kündigen irgendwann."},
	"poach_worker": {"params": {"target": "int", "wage": "number"}, "desc": "Arbeiter eines Konkurrenten mit höherem Lohn abwerben (legal, 600 EUR)."},
}

var sim
var ex     # ActionExecutor (fuer Besuche und Hilfsfunktionen)


func setup(simulation, executor) -> void:
	sim = simulation
	ex = executor


func _own_worker(cid: int, wid: String) -> Worker:
	var w: Worker = sim.personnel.workers.get(wid)
	return w if w != null and w.employer == cid and not w.lost else null


func run(cid: int, name: String, a: Dictionary, on_site: bool) -> Dictionary:
	var P: Personnel = sim.personnel
	var c: Company = sim.company(cid)
	match name:
		"inspect_resource":
			return sim.resources.inspect(cid, str(a.resource_id))
		"schedule_rest":
			return sim.workforce.schedule_rest(cid, str(a.worker_id), ActionExecutor._f(a.hours))
		"offer_training":
			return sim.workforce.offer_training(cid, str(a.worker_id), str(a.skill))
		"request_replacement_worker":
			return sim.workforce.request_replacement(cid, str(a.kind))
		"fund_maintenance":
			return sim.care.fund_maintenance(cid, str(a.einrichtung_id), ActionExecutor._f(a.betrag))
		"commission_renovation":
			return sim.care.renovate(cid, str(a.einrichtung_id))
		"compare_fuel_options":
			return FuelPlanner.compare_text(sim, cid, ActionExecutor._f(a.get("liters", 500)) if a.get("liters") != null else 500.0)
		"schedule_refueling":
			return FuelPlanner.set_rule(sim, cid, ActionExecutor._f(a.below_l), ActionExecutor._f(a.buy_l), str(a.get("station", "")) if a.get("station") != null else "")
		"negotiate_wage":
			return sim.households.negotiate(cid, str(a.worker_id), float(a.wage))
		"recruit_worker", "recruit_foreman":
			var w: Worker = P.workers.get(str(a.worker_id))
			if w == null:
				return {"ok": false, "msg": "Unbekannte Arbeiter-ID %s." % a.worker_id}
			if w.lost:
				return {"ok": false, "msg": "%s steht in dieser Partie nicht mehr zur Verfügung." % w.name}
			if w.employer >= 0:
				return {"ok": false, "msg": "%s arbeitet bereits für %s." % [w.name, sim.company(w.employer).company_name]}
			if w.employer == -2:
				return {"ok": false, "msg": "%s ist derzeit nicht am Arbeitsmarkt." % w.name}
			if (name == "recruit_foreman") != (w.role == "foreman"):
				return {"ok": false, "msg": "%s ist %s." % [w.name, "Vorarbeiter (recruit_foreman)" if w.role == "foreman" else "kein Vorarbeiter (recruit_worker)"]}
			if c.ledger.cash < w.hire_fee:
				return {"ok": false, "msg": "Anwerbung kostet %s." % Catalog.money(w.hire_fee)}
			# Modelle werben oft auf Vorrat an (Partie 08.11.: 18 Leute fuer 1 Fahrzeug, Lohnkosten > 400 EUR je Tag)
			var spare: int = P.employed(cid).filter(func(x): return x.vehicle_id < 0 and x.business == "").size()
			var fleet: int = sim.company_vehicles(cid).size()
			if ex._from_model() and name == "recruit_worker" and spare >= fleet + SPARE_STAFF:
				return {"ok": false, "msg": "Schon %d Leute ohne Fahrzeug bei %d Fahrzeugen – erst Fahrzeuge kaufen oder vorhandenes Personal einsetzen." % [spare, fleet]}
			if not on_site and not ex._near(cid, w.tile()):
				return ex._start_visit(cid, a, w.tile(), -1, "%s (%s)" % [w.name, w.id])
			P.hire(cid, w)
			sim.log_event("%s wirbt %s an (%s)." % [c.company_name, w.name, w.skill_text()], "info", cid)
			sim.bark(cid, "personal")
			return {"ok": true, "msg": "%s (%s) angeworben: %s, %.0f EUR/h. Geht zum Depot." % [w.name, w.id, w.skill_text(), w.wage]}
		"dismiss_worker":
			var w := _own_worker(cid, str(a.worker_id))
			if w == null:
				return {"ok": false, "msg": "Arbeiter %s gehört nicht zu dir." % a.worker_id}
			if P.employed(cid).size() <= 1:
				return {"ok": false, "msg": "Der letzte Arbeiter kann nicht entlassen werden."}
			var v: FleetVehicle = sim.vehicles.get(w.vehicle_id)
			if v and v.state != "idle":
				return {"ok": false, "msg": "%s fährt gerade." % w.name}
			for t in P.tasks.values():
				if t.worker_id == w.id and not t.is_final():
					P.cancel_task(t, "Arbeiter entlassen")
			w.vehicle_id = -1
			w.employer = -1
			w.foreman = ""
			for f in P.workers.values():
				f.supervised.erase(w.id)
			return {"ok": true, "msg": "%s entlassen und wieder auf dem Arbeitsmarkt." % w.name}
		"assign_worker_task":
			return _assign_task(cid, a)
		"guard_target":
			var b := a.duplicate()
			b["kind"] = "bewachen"
			return _assign_task(cid, b)
		"cancel_worker_task":
			var t: WorkerTask = P.tasks.get(str(a.task_id))
			if t == null or t.company != cid:
				return {"ok": false, "msg": "Aufgabe %s gehört nicht zu dir." % a.task_id}
			if t.is_final():
				return {"ok": false, "msg": "Aufgabe %s ist bereits %s." % [t.id, t.status]}
			P.cancel_task(t, "vom Unternehmer abgebrochen")
			return {"ok": true, "msg": "Aufgabe %s abgebrochen (bisherige Kosten %s bleiben)." % [t.id, Catalog.money(t.cost)]}
		"set_task_priority":
			var t: WorkerTask = P.tasks.get(str(a.task_id))
			if t == null or t.company != cid or t.is_final():
				return {"ok": false, "msg": "Keine offene eigene Aufgabe %s." % a.task_id}
			t.priority = clampi(ActionExecutor._i(a.priority), 1, 3)
			return {"ok": true, "msg": "Priorität von %s ist jetzt %d." % [t.id, t.priority]}
		"assign_foreman":
			var f := _own_worker(cid, str(a.foreman_id))
			if f == null or f.role != "foreman":
				return {"ok": false, "msg": "%s ist kein eigener Vorarbeiter." % a.foreman_id}
			var ids: Array = a.worker_ids if a.worker_ids is Array else []
			var added: Array = []
			for raw in ids:
				var w := _own_worker(cid, str(raw))
				if w == null or w.role == "foreman" or w.id in f.supervised:
					continue
				if f.supervised.size() >= f.capacity():
					break
				for other in P.workers.values():
					other.supervised.erase(w.id)
				f.supervised.append(w.id)
				w.foreman = f.id
				added.append(w.name)
			if a.get("site_id") != null:
				var site := ActionExecutor._i(a.site_id)
				if site not in c.depots and site not in c.offices:
					return {"ok": false, "msg": "Standort %d gehört nicht zu dir." % site}
				f.station = sim.city.building(site).walk
			return {"ok": true, "msg": "%s betreut jetzt %d Arbeiter (%s), Bereich %d Tiles um %s." % [f.name, f.supervised.size(),
				", ".join(added) if not added.is_empty() else "keine neuen", int(f.control_radius()), str(f.station)]}
		"set_foreman_orders":
			var f := _own_worker(cid, str(a.foreman_id))
			if f == null or f.role != "foreman":
				return {"ok": false, "msg": "%s ist kein eigener Vorarbeiter." % a.foreman_id}
			for k in ["auto_driver", "auto_repair", "reassign_blocked", "darf_teile_kaufen"]:
				if a.get(k) != null:
					f.orders[k] = ActionExecutor._b(a[k])
			if a.get("ziel") != null:
				f.orders.ziel = str(a.ziel).left(160)
			if a.get("prioritaet") != null:
				if str(a.prioritaet) not in ["fristgerecht", "kosten", "auslastung"]:
					return {"ok": false, "msg": "prioritaet muss fristgerecht, kosten oder auslastung sein."}
				f.orders.prioritaet = str(a.prioritaet)
			if a.get("repair_budget") != null:
				f.orders.repair_budget = maxf(0.0, ActionExecutor._f(a.repair_budget))
			return {"ok": true, "msg": "Befugnisse von %s: %s" % [f.name, str(f.orders)]}
		"request_progress_report":
			var f := _own_worker(cid, str(a.foreman_id))
			if f == null or f.role != "foreman":
				return {"ok": false, "msg": "%s ist kein eigener Vorarbeiter." % a.foreman_id}
			P.send_report(f)
			return {"ok": true, "msg": "Bericht von %s angefordert (siehe Ergebnisse)." % f.name}
		"hub_buy":
			var hc = sim.company(cid)
			if hc == null or hc.depots.is_empty():
				return {"ok": false, "msg": "Ohne Depot gibt es keinen Lieferort."}
			return sim.hub.buy("C%d" % cid, str(a.get("item", "")), ActionExecutor._i(a.get("qty", 0)), int(hc.depots[0]), "",
				str(a.get("bahn", "false")).to_lower() in ["true", "1", "ja"])
		"hub_sell":
			return sim.hub.sell(cid, str(a.get("item", "")), ActionExecutor._i(a.get("qty", 0)))
		"buy_supplies":
			return sim.resources.buy_supplies(cid, str(a.resource_id), ActionExecutor._f(a.amount), "abholen" if str(a.get("lieferung", "liefern")) == "abholen" else "liefern")
		"attempt_vehicle_sabotage":
			return _sabotage(cid, a)
		"poach_worker":
			return sim.rivalry.poach_worker(cid, ActionExecutor._i(a.target), ActionExecutor._f(a.wage))
	return {}


func _assign_task(cid: int, a: Dictionary) -> Dictionary:
	var P: Personnel = sim.personnel
	var c: Company = sim.company(cid)
	var kind := str(a.kind)
	if not WorkerTask.KINDS.has(kind) or kind == "sabotage":
		return {"ok": false, "msg": "Unbekannte Aufgabe '%s'. Erlaubt: %s (Sabotage über attempt_vehicle_sabotage)." % [kind,
			", ".join(WorkerTask.KINDS.keys().filter(func(k): return k != "sabotage"))]}
	var target := {}
	var note := ""
	match kind:
		"fahren", "reparieren":
			var v: FleetVehicle = sim.vehicles.get(ActionExecutor._i(a.get("vehicle_id", -1)) if a.get("vehicle_id") != null else -1)
			if v == null or v.owner != cid:
				return {"ok": false, "msg": "vehicle_id fehlt oder Fahrzeug gehört dir nicht."}
			target.vehicle_id = v.id
			if kind == "fahren" and a.get("contract_id") != null and str(a.contract_id) != "":
				var k: Contract = sim.contracts.get(str(a.contract_id))
				if k == null or k.owner != cid or k.status != "accepted":
					# Auftrag schon disponiert oder nicht angenommen: Fahrer trotzdem einteilen (die Disposition verteilt die Fahrten)
					note = " Auftrag %s ist nicht (mehr) unzugewiesen und wurde nicht verknüpft." % a.contract_id
				elif not k.vehicle_ok(v.model):
					note = " #%d passt nicht zu %s (%s) – nur der Fahrer wurde eingeteilt." % [v.id, k.id, k.requirement_text()]
				else:
					target.contract_id = k.id
		"bewachen":
			if a.get("vehicle_id") != null:
				var v: FleetVehicle = sim.vehicles.get(ActionExecutor._i(a.vehicle_id))
				if v == null or v.owner != cid:
					return {"ok": false, "msg": "Fahrzeug gehört dir nicht."}
				target.vehicle_id = v.id
			else:
				var site := ActionExecutor._i(a.get("site_id", c.depots[0]))
				if site not in c.depots:
					return {"ok": false, "msg": "Depot %d gehört dir nicht." % site}
				target.site = site
		"verladen", "bauen", "schulung":
			var b: Dictionary = sim.city.building(ActionExecutor._i(a.get("building_id", -1)) if a.get("building_id") != null else -1)
			if b.is_empty():
				return {"ok": false, "msg": "building_id fehlt oder ist unbekannt."}
			target.building = b.id
		"auskundschaften", "blockieren":
			var rc := ActionExecutor._i(a.get("company", -1)) if a.get("company") != null else -1
			if sim.company(rc) == null or rc == cid:
				return {"ok": false, "msg": "company muss eine gegnerische Firmen-ID sein."}
			if kind == "blockieren":
				if float(P.cooldowns.get("block:%d:%d" % [cid, rc], 0.0)) > sim.game_min:
					return {"ok": false, "msg": "Blockade gegen diese Firma hat Abklingzeit."}
				if sim.company(rc).protected_until > sim.game_min:
					return {"ok": false, "msg": "Die Firma steht unter Schutzfrist."}
			target.company = rc
		"unterstuetzen":
			var o := _own_worker(cid, str(a.get("target_worker", "")))
			if o == null:
				return {"ok": false, "msg": "target_worker muss ein eigener Arbeiter sein."}
			target.worker_id = o.id
		"gehen":
			if a.get("building_id") != null:
				var b: Dictionary = sim.city.building(ActionExecutor._i(a.building_id))
				if b.is_empty():
					return {"ok": false, "msg": "Unbekanntes Gebäude."}
				target.building = b.id
			else:
				target.site = ActionExecutor._i(a.get("site_id", c.depots[0]))
	var prio := ActionExecutor._i(a.get("priority", 2)) if a.get("priority") != null else 2
	var wid := str(a.get("worker_id", "")) if a.get("worker_id") != null else ""
	if wid == "":
		var fid := str(a.get("foreman_id", "")) if a.get("foreman_id") != null else ""
		var f := _own_worker(cid, fid)
		if f == null or f.role != "foreman":
			return {"ok": false, "msg": "worker_id fehlt (oder foreman_id eines eigenen Vorarbeiters zum Verteilen angeben)."}
		var t := P.create_task(cid, kind, target, "", f.id, prio, "Unternehmer über Vorarbeiter")
		return {"ok": true, "msg": "Aufgabe %s (%s) an Vorarbeiter %s zur Verteilung übergeben." % [t.id, kind, f.name], "task_id": t.id}
	var w := _own_worker(cid, wid)
	var err := "Arbeiter %s gehört nicht zu dir." % wid if w == null else P.can_take(w, kind)
	if err != "" and kind in ["fahren", "reparieren"] and target.has("vehicle_id") and ex._from_model():
		# Lokale Modelle verwechseln Arbeiter-IDs (Partie 11.11.: ~500 Fehler "gehört nicht zu dir", "keine Fähigkeit fahren",
		# "beschäftigt"). Ist ein eigener, freier und geeigneter Arbeiter da, uebernimmt der naechstgelegene.
		var v: FleetVehicle = sim.vehicles.get(int(target.vehicle_id))
		var sub := _substitute(cid, kind, v)
		if sub != null:
			note += " Ersatz: %s statt %s (%s)." % [sub.name, wid, err.trim_suffix(".")]
			w = sub
			err = ""
	if err != "":
		return {"ok": false, "msg": err}
	var t := P.create_task(cid, kind, target, w.id, "", prio, "Unternehmer")
	return {"ok": true, "msg": "Aufgabe %s: %s übernimmt %s.%s" % [t.id, w.name, t.describe(), note], "task_id": t.id}


## Naechstgelegener eigener Arbeiter, der die Aufgabe jetzt uebernehmen kann (oder null). Fahrer anderer Fahrzeuge bleiben, wo sie sind.
func _substitute(cid: int, kind: String, v: FleetVehicle) -> Worker:
	var best: Worker = null
	for x in sim.personnel.employed(cid):
		if x.business != "" or sim.personnel.can_take(x, kind) != "" or (kind == "fahren" and x.vehicle_id >= 0 and x.vehicle_id != v.id):
			continue
		if best == null or x.pos.distance_to(v.pos) < best.pos.distance_to(v.pos):
			best = x
	return best


func _sabotage(cid: int, a: Dictionary) -> Dictionary:
	var P: Personnel = sim.personnel
	var c: Company = sim.company(cid)
	var w := _own_worker(cid, str(a.worker_id))
	if w == null:
		return {"ok": false, "msg": "Arbeiter %s gehört nicht zu dir." % a.worker_id}
	var err := P.can_take(w, "sabotage")
	if err != "":
		return {"ok": false, "msg": err}
	var vid := ActionExecutor._i(a.vehicle_id)
	var seen: Dictionary = P.seen[cid].get(str(vid), {})
	if seen.is_empty():
		return {"ok": false, "msg": "Fahrzeug #%d ist dir nicht bekannt (nur gesichtete Fahrzeuge; Kundschafter schicken)." % vid}
	var v: FleetVehicle = sim.vehicles.get(vid)
	if v == null or v.owner == cid:
		return {"ok": false, "msg": "Ungültiges Ziel."}
	if sim.game_min < float(P.cooldowns.get("sab:%d" % cid, 0.0)):
		return {"ok": false, "msg": "Sabotage-Abklingzeit läuft noch %d Spielminuten." % int(P.cooldowns["sab:%d" % cid] - sim.game_min)}
	if sim.game_min < float(P.cooldowns.get("veh:%d" % vid, 0.0)):
		return {"ok": false, "msg": "#%d wurde kürzlich angegriffen und wird jetzt streng beobachtet." % vid}
	if v.state not in ["idle", "loading", "unloading"]:
		return {"ok": false, "msg": "#%d fährt gerade und ist nicht erreichbar." % vid}
	if c.ledger.cash < Personnel.SABOTAGE_COST:
		return {"ok": false, "msg": "Einsatzkosten %s nicht gedeckt." % Catalog.money(Personnel.SABOTAGE_COST)}
	c.ledger.book("sabotage", -Personnel.SABOTAGE_COST, true, "Sabotageeinsatz %s gegen #%d" % [w.name, vid], sim.game_min)
	P.cooldowns["sab:%d" % cid] = sim.game_min + Personnel.SABOTAGE_COOLDOWN
	var t := P.create_task(cid, "sabotage", {"vehicle_id": vid}, w.id, "", 1, "Unternehmer")
	t.cost = Personnel.SABOTAGE_COST
	var odds := P.sabotage_odds(w, v)
	return {"ok": true, "task_id": t.id, "msg": "Aufgabe %s: %s schleicht sich zu #%d. Geschätzt: Entdeckung %d %%, Erfolg %d %% (Stand jetzt)." % [
		t.id, w.name, vid, int(odds.detect * 100), int(odds.success * 100)]}
