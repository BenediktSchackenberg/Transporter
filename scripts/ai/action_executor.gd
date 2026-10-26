class_name ActionExecutor
extends RefCounted
## Prueft und fuehrt strukturierte KI-Aktionen aus. Einzige Stelle, an der KI-Entscheidungen
## den Spielzustand veraendern. Jede Aktion wird gegen den aktuellen Zustand geprueft;
## Geld, Besitz und Positionen kann die KI nur ueber diese Regeln veraendern.
##
## Fernaktionen (Disposition, Telefon, Bank): accept_contract (nur bekannte Auftraege), assign_vehicle, repair_vehicle,
##   sell_vehicle, dismiss_worker, cancel_depot, take_loan, repay_loan, send_message (Funk/Rundruf), offer_trade,
##   accept_trade, reject_trade, poach_worker, poach_customer, buy_security, set_insurance,
##   attempt_sabotage(smear_campaign), wait; collect_contracts mit Internet Stufe 2
## Besuchsaktionen (Figur muss hingehen; Ausfuehrung und erneute Pruefung bei Ankunft, Warteschlange bis 4):
##   collect_contracts (Jobboerse bzw. eigenes Buero mit Internet 1), recruit_worker/recruit_foreman (Ort des Arbeiters),
##   buy_vehicle (Autohaus), rent_depot (Standort), build_office (Buerostandort), upgrade_office (Zentrale),
##   install_internet (eigenes Buero), attempt_sabotage(depot_disruption) (Depot des Ziels),
##   propose_cooperation (Treffen), oeffentliche Ansprache eines Spielers (Begegnung), move_to

## Parameter: Typ, "?" = optional
const SCHEMA := {
	"wait": {"params": {}, "desc": "Bewusst nichts tun."},
	"move_to": {"params": {"target": "string"}, "desc": "Figur laufen lassen: 'building:<id>', 'player:<id>' oder 'depot'."},
	"accept_contract": {"params": {"contract_id": "string", "vehicle_id": "int?"},
		"desc": "Marktauftrag annehmen (optional direkt einem Fahrzeug zuweisen)."},
	"assign_vehicle": {"params": {"vehicle_id": "int", "contract_id": "string", "menge": "int?", "von": "string?", "nach": "string?"},
		"desc": "Fahrt Laden->Abladen anhängen. Standard: ganze Restmenge von 'abholung' nach 'ziel'. Mit menge/von/nach: Teilmengen, Zwischenlager ('lager:<Depot-ID>'), Umladen."},
	"assign_transport": {"params": {"vehicle_id": "int", "contract_id": "string", "menge": "int?", "von": "string?", "nach": "string?"},
		"desc": "Wie assign_vehicle."},
	"plan_tour": {"params": {"vehicle_id": "int", "stopps": "array"},
		"desc": "Tour aus Stopps [{art:'laden'|'abladen', contract_id, menge, ort:'abholung'|'ziel'|'lager:<Depot-ID>'}] anhängen: Sammeltouren, Rückfahrten, Umladen. Kapazität wird über die ganze Tour geprüft."},
	"clear_tour": {"params": {"vehicle_id": "int"}, "desc": "Noch nicht begonnene Stopps eines Fahrzeugs streichen (Ladung bleibt an Bord)."},
	"set_plan": {"params": {"ziel": "string", "schritte": "array", "nutzen": "string?", "risiken": "string?", "abbruch": "array?"},
		"desc": "Eigenen Plan festlegen: schritte=[{id, text, aktion?:{action,...}, abhaengig_von?:[ids], braucht?:{geld,arbeiter,fahrzeuge}}], abbruch=[{typ: bargeld_unter|ruf_unter|restzeit_unter_min|auftrag_gescheitert|arbeiter_verloren|fahrzeug_ausgefallen, wert}]."},
	"execute_plan_step": {"params": {"step_id": "string"}, "desc": "Hinterlegte Aktion eines Planschritts ausführen (Abhängigkeiten und Geld werden geprüft)."},
	"update_plan_step": {"params": {"step_id": "string", "status": "string", "ergebnis": "string?"},
		"desc": "Planschritt als erledigt/uebersprungen/offen/blockiert markieren (z. B. Prüf- oder Bewertungsschritte)."},
	"cancel_plan": {"params": {"grund": "string?"}, "desc": "Aktuellen Plan verwerfen."},
	"start_experiment": {"params": {"frage": "string", "varianten": "array", "budget": "number?", "dauer_h": "number?", "messgroessen": "array?"},
		"desc": "Begrenztes Experiment anlegen; danach Aktionen (accept_contract/assign_transport/plan_tour) mit experiment=<ID> und variante=<Name> kennzeichnen. Auswertung mit Stichprobengröße am Ende."},
	"end_experiment": {"params": {"experiment_id": "string"}, "desc": "Experiment vorzeitig auswerten."},
	"remember": {"params": {"inhalt": "string", "bereich": "array?", "art": "string?", "vertrauen": "number?", "id": "string?"},
		"desc": "Erfahrung im eigenen Gedächtnis anlegen oder (mit id) aktualisieren; art tatsache|vermutung, vertrauen 0–1."},
	"forget": {"params": {"id": "string"}, "desc": "Eigene Erfahrung verwerfen (z. B. widerlegt)."},
	"move_vehicle": {"params": {"vehicle_id": "int", "site_id": "int"}, "desc": "Fahrzeug (mit Fahrer, ohne Stopps) zu einem eigenen Depot versetzen."},
	"repair_vehicle": {"params": {"vehicle_id": "int", "worker_id": "string?"},
		"desc": "Mit worker_id: eigener Mechaniker repariert vor Ort (Ersatzteile nötig). Ohne: Werkstatt (teurer; liegengebliebene Fahrzeuge werden abgeschleppt)."},
	"buy_vehicle": {"params": {"offer_id": "string?", "model": "string?"}, "visit": true,
		"desc": "Fahrzeugangebot (F..) beim Autohaus kaufen; Figur geht hin. Begrenzter Bestand: Wer zuerst kommt, kauft."},
	"sell_vehicle": {"params": {"vehicle_id": "int"}, "desc": "Freies Fahrzeug an den Händler verkaufen (85 % des Buchwerts)."},
	"collect_contracts": {"params": {}, "visit": true,
		"desc": "Offene Aufträge kennenlernen: an der Jobbörse, mit Internet 1 im eigenen Büro, mit Internet 2 von überall."},
	"build_office": {"params": {"site_id": "int"}, "visit": true,
		"desc": "Büro an einem Bürostandort eröffnen (erstes = Zentrale 4500 EUR, Filialen ab 6000 EUR). Mehr gleichzeitige Aufträge."},
	"upgrade_office": {"params": {}, "visit": true, "desc": "Zentrale ausbauen (Stufe 2: 6000, 3: 10500 EUR), +3 Auftragskapazität."},
	"install_internet": {"params": {}, "visit": true,
		"desc": "Internet im eigenen Büro (Stufe 1: 2500, Stufe 2: 4500 EUR): Aufträge im Büro bzw. von überall sammeln."},
	"rent_depot": {"params": {"depot_id": "int"}, "visit": true,
		"desc": "Freien Depotstandort anmieten (+4 Stellplätze, 350 EUR/Tag). Figur geht hin."},
	"cancel_depot": {"params": {"depot_id": "int"}, "desc": "Zusätzliches Depot kündigen."},
	"take_loan": {"params": {"amount": "number", "monate": "number?", "bank": "string?"},
		"desc": "Kredit aufnehmen (Kurzform von request_loan; Standard: Geschäftsbank, 6 Monate, Sicherheit wird automatisch gewählt)."},
	"request_loan": {"params": {"bank": "string", "amount": "number", "monate": "number", "fahrzeug_id": "int?", "zweck": "string?"},
		"desc": "Kredit bei Geschäfts-, Investitions- oder Handelsbank beantragen. Annuität, Zins = Referenzzins + Aufschläge (siehe bank.angebote); Sicherheit = eigenes Fahrzeug (fahrzeug_id)."},
	"repay_loan": {"params": {"amount": "number", "kredit_id": "string?"}, "desc": "Kredit vorzeitig (teil)tilgen; 1 % Gebühr auf den getilgten Betrag."},
	"bid_auction": {"params": {"auction_id": "string", "amount": "number"},
		"desc": "Bei einer Insolvenzauktion (obs.auktionen) bieten; mindestens 5 % über dem Höchstgebot. Zahlung erst beim Zuschlag."},
	"buy_material": {"params": {"item": "string", "menge": "number", "lieferung": "string?", "depot_id": "int?"},
		"desc": "Material beim Bauhof kaufen (obs.bauhof.preise). lieferung=abholen (Transportauftrag Bauhof→Depot, Eigentum sofort bei dir) oder liefern (frei Depot gegen Gebühr). Eigenbau nutzt eigenes Material zuerst."},
	"sell_material": {"params": {"item": "string", "menge": "number", "depot_id": "int?"}, "desc": "Eigenes Material (z. B. Altmaterial vom Rückbau) an den Bauhof verkaufen."},
	"change_company_form": {"params": {"form": "string"}, "desc": "Rechtsform wechseln: einzel, ug oder gmbh (ab 3 Monaten, Mindest-Eigenkapital, Kosten, 15 Spieltage)."},
	"deposit_money": {"params": {"amount": "number", "art": "string", "monate": "number?", "bank": "string?"},
		"desc": "Geld anlegen: art tages (täglich verfügbar) oder fest (3–24 Monate, höherer Zins)."},
	"withdraw_deposit": {"params": {"einlage_id": "string"}, "desc": "Einlage zurückholen (Festgeld vorzeitig: Zinsverlust und 1 % Gebühr)."},
	"send_message": {"params": {"to": "string", "text": "string", "private": "bool?"},
		"desc": "Rundruf an 'all' oder Funk an Spieler-ID mit private=true. Einen Spieler öffentlich ansprechen (private=false) geht nur bei Begegnung (move_to player:<id>)."},
	"offer_trade": {"params": {"to": "int", "kind": "string", "vehicle_id": "int?", "contract_id": "string?",
		"price": "number?", "duration_hours": "number?", "note": "string?", "strafe": "number?", "site_id": "int?",
		"plaetze": "int?", "menge": "int?"},
		"desc": "Verbindliches Angebot: sell_vehicle, buy_vehicle, transfer_contract (Empfänger zahlt price), payment, capacity_rental (vehicle_id, duration_hours, price, strafe/h), storage_share (site_id, plaetze, duration_hours, price), split_contract (contract_id, menge, price bei Lieferung, strafe bei Verfehlung)."},
	"accept_trade": {"params": {"offer_id": "string"}, "desc": "An dich gerichtetes Angebot annehmen (wird erst dann verbindlich)."},
	"counter_offer": {"params": {"offer_id": "string", "price": "number?", "duration_hours": "number?", "strafe": "number?",
		"plaetze": "int?", "menge": "int?", "note": "string?"}, "desc": "Gegenangebot mit geänderten Konditionen (max. 3 Runden)."},
	"reject_trade": {"params": {"offer_id": "string"}, "desc": "Angebot ablehnen."},
	"propose_cooperation": {"params": {"to": "int", "duration_hours": "number?", "note": "string?"}, "visit": true,
		"desc": "Kooperationspakt anbieten; deine Figur geht zur Figur des anderen (Treffen)."},
	"offer_cooperation": {"params": {"to": "int", "duration_hours": "number?", "note": "string?"}, "visit": true,
		"desc": "Wie propose_cooperation."},
	"poach_customer": {"params": {"customer_id": "int"}, "desc": "Stammkunden eines Konkurrenten abwerben (legal, 800 EUR)."},
	"buy_security": {"params": {"level": "int"}, "desc": "Sicherheitsstufe 0-2 (schützt vor Sabotage)."},
	"set_insurance": {"params": {"active": "bool"}, "desc": "Versicherung gegen Sabotageschäden (600 EUR/Tag)."},
	"attempt_sabotage": {"params": {"target": "int", "kind": "string"},
		"desc": "Regelwidrig! depot_disruption (Figur geht zum Zieldepot) oder smear_campaign. Kann entdeckt werden."},
}

const ALIASES := {"assign_transport": "assign_vehicle", "offer_cooperation": "propose_cooperation"}

var sim
var executed := {}     # Idempotenzschluessel -> true (verhindert Doppelausfuehrung)
var worker_actions := WorkerActions.new()
var estate_actions := EstateActions.new()
var _cur_key := ""        # Schluessel/Herkunft der gerade ausgefuehrten Aktion (fuer Besuche und Protokoll)
var _cur_origin := "api"


func setup(simulation) -> void:
	sim = simulation
	worker_actions.setup(simulation, self)
	estate_actions.setup(simulation, self)


## Alle Aktionen mit Schema (allgemein + Personal/Ressourcen).
static func all_schema() -> Dictionary:
	var d := SCHEMA.duplicate()
	d.merge(WorkerActions.SCHEMA)
	d.merge(EstateActions.SCHEMA)
	return d


## Hauptzugang. key: eindeutiger Schluessel (z. B. "p1:r17:a2"); gleiche Schluessel werden nie zweimal ausgefuehrt.
## origin: "api" (Modellentscheidung), "plan" (Planschritt), "fallback" (Ersatzmodus), "foreman", "auto", "spectator"
## Haeufige Formfehler kleiner Modelle glaetten: verschachtelte "parameters", abweichende Schluesselnamen, fehlendes "kind".
## Vorhandene Schluessel werden nie ueberschrieben; inhaltliche Fehler bleiben Fehler.
const KEY_ALIASES := {"contract": "contract_id", "vehicle": "vehicle_id", "driver": "worker_id", "driver_id": "worker_id", "worker": "worker_id", "offer": "offer_id"}


static func normalize(action: Dictionary) -> Dictionary:
	var a := action.duplicate()
	for nest in ["parameters", "params", "args", "arguments"]:
		if a.get(nest) is Dictionary:
			for k in a[nest]:
				if not a.has(k):
					a[k] = a[nest][k]
	for k in KEY_ALIASES:
		if a.has(k) and not a.has(KEY_ALIASES[k]) and not a[k] is Dictionary and not a[k] is Array:
			a[KEY_ALIASES[k]] = a[k]
	var name := str(a.get("action", a.get("type", "")))
	# "assign_transport/plan_tour": Modell nennt mehrere Aktionen in einem Namen -> erste bekannte nehmen
	if not all_schema().has(name):
		for part in name.replace("|", "/").replace(",", "/").split("/"):
			if all_schema().has(part.strip_edges()):
				name = part.strip_edges()
				a["action"] = name
				break
	if name == "accept_contract" and not a.has("contract_id"):
		for k in ["id", "target_id", "target"]:
			if a.has(k):
				a["contract_id"] = a[k]
				break
	elif name == "buy_vehicle" and not a.has("offer_id") and not a.has("model"):
		for k in ["id", "target_id", "target", "vehicle_id"]:
			if a.has(k):
				a["offer_id"] = a[k]
				break
	elif name == "recruit_worker" and not a.has("worker_id"):
		for k in ["id", "target_id", "target"]:
			if a.has(k):
				a["worker_id"] = a[k]
				break
	elif name == "assign_worker_task" and not a.has("kind") and a.has("vehicle_id"):
		a["kind"] = "fahren"
	return a


func execute(cid: int, action: Dictionary, key: String = "", origin: String = "api", ctx: Dictionary = {}) -> Dictionary:
	action = normalize(action)
	if key != "" and executed.has(key):
		return {"ok": false, "duplicate": true, "msg": "Aktion wurde bereits ausgeführt (Wiederholung ignoriert)."}
	var name := str(action.get("action", action.get("type", "")))
	var check := validate_schema(name, action)
	if check == "" and not sim.company(cid).is_active() and name != "wait":
		check = "Das Unternehmen steht unter Insolvenzverwaltung (%s): Aktionen sind gesperrt." % sim.company(cid).status
	if check != "":
		var rej := _done(cid, key, name, {"ok": false, "msg": check})
		sim.decisions.record(cid, origin, action, rej, key)
		return rej
	var prev_key := _cur_key
	var prev_origin := _cur_origin
	_cur_key = key
	_cur_origin = origin
	var r := _do(cid, name, action, false)
	_cur_key = prev_key
	_cur_origin = prev_origin
	if r.ok and action.get("experiment") != null and name in ["accept_contract", "assign_vehicle", "assign_transport", "plan_tour"]:
		var kids: Array = [str(action.contract_id)] if action.get("contract_id") != null else []
		if name == "plan_tour":
			kids = action.stopps.map(func(st): return str(st.get("contract_id", "")))
		r.msg += sim.experiments.tag(cid, action, kids)
	r = _done(cid, key, name, r)
	sim.decisions.record(cid, origin, action, r, key)
	return r


func _done(cid: int, key: String, name: String, r: Dictionary) -> Dictionary:
	if key != "":
		executed[key] = true
	if name != "wait":
		sim.record_result(cid, "%s %s: %s" % ["OK" if r.ok else "ABGELEHNT", name, r.msg])
	return r


## Prueft Aktionsname, Pflichtparameter und Typen. Gibt "" oder eine Fehlermeldung zurueck.
static func validate_schema(name: String, a: Dictionary) -> String:
	var schema := all_schema()
	if not schema.has(name):
		return "Unbekannte Aktion '%s'." % name
	var params: Dictionary = schema[name].params
	for p in params:
		var t: String = params[p]
		var optional := t.ends_with("?")
		t = t.trim_suffix("?")
		if not a.has(p) or a[p] == null:
			if optional:
				continue
			return "Parameter '%s' fehlt für %s." % [p, name]
		var v = a[p]
		match t:
			"int":
				if not ((v is float and is_equal_approx(v, roundf(v))) or v is int or (v is String and v.is_valid_int())):
					return "Parameter '%s' muss eine ganze Zahl sein." % p
			"number":
				if not (v is float or v is int or (v is String and v.is_valid_float())):
					return "Parameter '%s' muss eine Zahl sein." % p
			"bool":
				if not (v is bool or (v is String and v.to_lower() in ["true", "false"])):
					return "Parameter '%s' muss true/false sein." % p
			"string":
				if not (v is String or v is float or v is int):
					return "Parameter '%s' muss ein Text sein." % p
			"array":
				if not v is Array:
					return "Parameter '%s' muss eine Liste sein." % p
	return ""


static func _i(v) -> int:
	return int(v) if not v is String else v.to_int()


static func _f(v) -> float:
	return float(v) if not v is String else v.to_float()


static func _b(v) -> bool:
	return v if v is bool else str(v).to_lower() == "true"


static func _s(v) -> String:
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return str(v)


func _do(cid: int, name: String, a: Dictionary, on_site: bool) -> Dictionary:
	name = ALIASES.get(name, name)
	if WorkerActions.SCHEMA.has(name):
		return worker_actions.run(cid, name, a, on_site)
	if EstateActions.SCHEMA.has(name):
		return estate_actions.run(cid, name, a)
	var c: Company = sim.company(cid)
	var L: Ledger = c.ledger
	match name:
		"wait":
			return {"ok": true, "msg": "abgewartet"}
		"set_plan":
			return sim.plans.set_plan(cid, a)
		"start_experiment":
			return sim.experiments.start(cid, a)
		"end_experiment":
			return sim.experiments.finish(cid, _s(a.experiment_id))
		"remember":
			var id: String = sim.memory.upsert(cid, a, "modell")
			return {"ok": true, "msg": "Erfahrung %s gespeichert." % id}
		"forget":
			return {"ok": sim.memory.forget(cid, _s(a.id)), "msg": "Erfahrung %s verworfen." % a.id}
		"execute_plan_step":
			var sid := _s(a.step_id)
			var sub := (_cur_key if _cur_key != "" else "plan:%d" % sim.step_count) + "/" + sid
			return sim.plans.execute_step(cid, sid, sub)
		"update_plan_step":
			return sim.plans.update_step(cid, _s(a.step_id), _s(a.status), _s(a.get("ergebnis", "")) if a.get("ergebnis") != null else "")
		"cancel_plan":
			return sim.plans.cancel(cid, _s(a.get("grund", "")) if a.get("grund") != null else "")
		"move_to":
			return _move_to(cid, _s(a.target))
		"accept_contract":
			return _accept_contract(cid, _s(a.contract_id), _i(a.get("vehicle_id", -1)) if a.get("vehicle_id") != null else -1)
		"assign_vehicle":
			return _assign(cid, _i(a.vehicle_id), _s(a.contract_id), _i(a.menge) if a.get("menge") != null else -1,
				_s(a.get("von", Logistics.PICKUP)), _s(a.get("nach", Logistics.DROP)))
		"plan_tour":
			var v := _operable_vehicle(cid, _i(a.vehicle_id))
			if v == null:
				return _no_vehicle(a.vehicle_id)
			if v.state in ["broken", "repairing", "to_workshop"]:
				return {"ok": false, "msg": "Fahrzeug #%d ist in Reparatur." % v.id}
			var stops: Array = []
			for raw in a.stopps:
				if not raw is Dictionary:
					return {"ok": false, "msg": "Jeder Stopp braucht art, contract_id, menge, ort."}
				stops.append({"art": _s(raw.get("art", "")), "contract_id": _s(raw.get("contract_id", "")),
					"menge": _i(raw.get("menge", 0)), "ort": _s(raw.get("ort", ""))})
			if stops.is_empty() or v.stops.size() + stops.size() > 12:
				return {"ok": false, "msg": "Tour muss 1–12 Stopps haben (inkl. bereits geplanter)."}
			var err: String = sim.logistics.validate(v, stops)
			if err != "":
				return {"ok": false, "msg": err}
			sim.logistics.add_stops(v, stops)
			return {"ok": true, "msg": "Tour für #%d geplant: %s.%s" % [v.id, ", ".join(stops.map(func(st): return "%s %d×%s@%s" % [st.art, st.menge, st.contract_id, st.ort])),
				"" if sim.driver_of(v) != null else " Achtung: kein Fahrer!"]}
		"clear_tour":
			var v := _operable_vehicle(cid, _i(a.vehicle_id))
			if v == null:
				return _no_vehicle(a.vehicle_id)
			var keep: Array = v.stops.slice(0, 1) if v.state in ["to_pickup", "to_dropoff", "loading", "unloading"] else []
			var dropped: int = v.stops.size() - keep.size()
			v.stops = keep
			for k in sim.contracts.values():
				if k.owner == cid and k.status == "assigned" and k.picked == 0 and not sim.vehicles.values().any(func(x): return x.stops.any(func(st): return st.contract_id == k.id)):
					k.status = "accepted"
			sim.logistics.sync_view(v)
			return {"ok": true, "msg": "%d geplante Stopps von #%d gestrichen; Ladung an Bord: %s." % [dropped, v.id, str(v.load)]}
		"move_vehicle":
			var v := _own_vehicle(cid, _i(a.vehicle_id))
			if v == null:
				return _no_vehicle(a.vehicle_id)
			var site := _i(a.site_id)
			if site not in c.depots:
				return {"ok": false, "msg": "Depot %d gehört dir nicht." % site}
			if not v.stops.is_empty() or v.state not in ["idle", "returning"]:
				return {"ok": false, "msg": "#%d ist beschäftigt." % v.id}
			if sim.driver_of(v) == null:
				return {"ok": false, "msg": "#%d hat keinen Fahrer." % v.id}
			sim.route(v, sim.city.building(site).road, "returning")
			return {"ok": true, "msg": "#%d fährt zu Depot %d." % [v.id, site]}
		"repair_vehicle":
			var v := _own_vehicle(cid, _i(a.vehicle_id))
			if v == null:
				return _no_vehicle(a.vehicle_id)
			if a.get("worker_id") != null and str(a.worker_id) != "":
				return worker_actions.run(cid, "assign_worker_task", {"kind": "reparieren", "vehicle_id": v.id,
					"worker_id": a.worker_id, "priority": 1}, on_site)
			if v.state == "broken":
				sim.tow_to_workshop(v)
				return {"ok": true, "msg": "#%d wird zur Werkstatt geschleppt (%s Abschleppen + Werkstattkosten)." % [v.id, Catalog.money(Catalog.TOW_FEE)]}
			if sim.driver_of(v) == null:
				return {"ok": false, "msg": "#%d hat keinen Fahrer für die Fahrt zur Werkstatt (Mechaniker per worker_id schicken oder Fahrer zuweisen)." % v.id}
			if v.state not in ["idle", "returning"]:
				return {"ok": false, "msg": "Fahrzeug #%d ist beschäftigt (%s)." % [v.id, FleetVehicle.STATE_TEXT.get(v.state, v.state)]}
			var ws: Dictionary = sim.nearest_building_of("workshop", v.tile())
			sim.route(v, ws.road, "to_workshop")
			return {"ok": true, "msg": "#%d fährt zur %s." % [v.id, ws.name]}
		"buy_vehicle":
			var offer: Dictionary = {}
			if a.get("offer_id") != null and str(a.offer_id) != "":
				offer = sim.resources.offers.get(str(a.offer_id), {})
				if offer.is_empty():
					return {"ok": false, "msg": "Unbekanntes Fahrzeugangebot %s." % a.offer_id}
			elif a.get("model") != null:
				offer = sim.resources.cheapest_offer(_s(a.model))
				if offer.is_empty():
					return {"ok": false, "msg": "Kein Angebot für Modell '%s' vorrätig. Angebote: siehe ressourcen.fahrzeugangebote." % a.model}
			else:
				return {"ok": false, "msg": "offer_id oder model angeben."}
			if offer.status != "verfügbar":
				return {"ok": false, "msg": "Angebot %s ist bereits verkauft." % offer.id}
			var spec := Catalog.model(offer.model)
			if c.vehicle_ids.size() >= c.fleet_limit():
				return {"ok": false, "msg": "Alle %d Stellplätze belegt – Stellplätze/Halle bauen (place_building) oder Depot anmieten." % c.fleet_limit()}
			if L.cash < offer.price:
				return {"ok": false, "msg": "Nicht genug Bargeld: %s benötigt, %s vorhanden." % [Catalog.money(offer.price), Catalog.money(L.cash)]}
			var dealer: Dictionary = sim.city.building(offer.dealer)
			if not on_site and not _near(cid, dealer.walk):
				var visit := a.duplicate()
				visit["offer_id"] = offer.id   # genau dieses Angebot bei Ankunft erneut pruefen
				return _start_visit(cid, visit, dealer.walk, -1, dealer.name)
			offer.status = "verkauft"
			L.invest(offer.price)
			var nv: FleetVehicle = sim.add_vehicle(cid, offer.model, offer.price, dealer.road)
			nv.condition = float(offer.condition)
			sim.log_event("%s kauft %s %s (%s)." % [c.company_name, "gebrauchten" if offer.condition < 100 else "neuen", spec.name, Catalog.money(offer.price)], "info", cid)
			c.add_key_event("Kauf: %s" % spec.name, sim.game_min)
			sim.bark(cid, "kauf")
			return {"ok": true, "msg": "%s #%d gekauft für %s (Zustand %d %%). Ohne Fahrer – Aufgabe 'fahren' an einen Arbeiter vergeben." % [
				spec.name, nv.id, Catalog.money(offer.price), offer.condition]}
		"sell_vehicle":
			var v := _own_vehicle(cid, _i(a.vehicle_id))
			if v == null:
				return _no_vehicle(a.vehicle_id)
			if v.state not in ["idle", "returning"] or not v.stops.is_empty() or not v.load.is_empty():
				return {"ok": false, "msg": "Fahrzeug #%d ist im Einsatz oder hat Aufträge in der Warteschlange." % v.id}
			if c.vehicle_ids.size() <= 1:
				return {"ok": false, "msg": "Das letzte Fahrzeug kann nicht verkauft werden."}
			if sim.banking.pledged_to(v.id) != "":
				return {"ok": false, "msg": "Fahrzeug #%d ist an die Bank verpfändet (Kredit %s)." % [v.id, sim.banking.pledged_to(v.id)]}
			var proceeds := v.book_value * Catalog.DEALER_BUYBACK
			L.divest(proceeds)
			L.book("asset_result", proceeds - v.book_value, false, "Verkauf #%d an Händler" % v.id, sim.game_min)
			sim.remove_vehicle(v)
			return {"ok": true, "msg": "#%d verkauft für %s (Buchwert %s)." % [v.id, Catalog.money(proceeds), Catalog.money(v.book_value)]}
		"rent_depot":
			var site := _i(a.depot_id)
			if site not in sim.city.depot_sites:
				return {"ok": false, "msg": "%d ist kein Depotstandort." % site}
			if sim.depot_owner.has(site):
				return {"ok": false, "msg": "Standort %d ist bereits vermietet." % site}
			if c.depots.size() > Catalog.MAX_EXTRA_DEPOTS:
				return {"ok": false, "msg": "Maximal %d Zusatzdepots." % Catalog.MAX_EXTRA_DEPOTS}
			if L.cash < Catalog.EXTRA_DEPOT_RENT:
				return {"ok": false, "msg": "Nicht genug Bargeld für die Kaution."}
			var b: Dictionary = sim.city.building(site)
			if not on_site and not _near(cid, b.walk):
				return _start_visit(cid, a, b.walk, -1, "zu " + b.name)
			c.depots.append(site)
			sim.depot_owner[site] = cid
			sim.log_event("%s mietet %s im %s." % [c.company_name, b.name, Catalog.DISTRICTS[b.district]], "info", cid)
			c.add_key_event("Depot angemietet (%s)" % Catalog.DISTRICTS[b.district], sim.game_min)
			return {"ok": true, "msg": "Depot %d angemietet (+%d Stellplätze)." % [site, Catalog.VEHICLES_PER_DEPOT]}
		"cancel_depot":
			var site := _i(a.depot_id)
			if site not in c.depots or site == c.depots[0]:
				return {"ok": false, "msg": "Nur eigene Zusatzdepots können gekündigt werden."}
			if c.vehicle_ids.size() > (c.depots.size() - 1) * Catalog.VEHICLES_PER_DEPOT:
				return {"ok": false, "msg": "Zu viele Fahrzeuge für weniger Stellplätze."}
			c.depots.erase(site)
			sim.depot_owner.erase(site)
			return {"ok": true, "msg": "Depot %d gekündigt." % site}
		"collect_contracts":
			return _collect(cid, a, on_site)
		"build_office":
			return _build_office(cid, a, _i(a.site_id), on_site)
		"upgrade_office":
			if c.office_level == 0:
				return {"ok": false, "msg": "Zuerst ein Büro eröffnen (build_office)."}
			if c.office_level >= 3:
				return {"ok": false, "msg": "Die Zentrale ist voll ausgebaut."}
			var cost: float = Catalog.OFFICE_UPGRADE_COST[c.office_level]
			if L.cash < cost:
				return {"ok": false, "msg": "Ausbau kostet %s." % Catalog.money(cost)}
			var hq: Dictionary = sim.city.building(c.offices[0])
			if not on_site and not _near(cid, hq.walk):
				return _start_visit(cid, a, hq.walk, -1, hq.name)
			L.invest(cost)
			c.property_cost += cost
			c.property_book += cost
			c.office_level += 1
			c.reputation = minf(100.0, c.reputation + 2.0)
			sim.log_event("%s baut die Zentrale auf Stufe %d aus." % [c.company_name, c.office_level], "info", cid)
			c.add_key_event("Zentrale Stufe %d" % c.office_level, sim.game_min)
			sim.bark(cid, "buero")
			return {"ok": true, "msg": "Zentrale Stufe %d – Auftragskapazität %d." % [c.office_level, c.contract_capacity()]}
		"install_internet":
			if office_sites(cid).is_empty():
				return {"ok": false, "msg": "Internet braucht ein eigenes Büro (Unternehmerbüro auf dem Betriebshof oder build_office)."}
			if c.internet_level >= 2:
				return {"ok": false, "msg": "Internet ist bereits voll ausgebaut."}
			var cost: float = Catalog.INTERNET_COST[c.internet_level]
			if L.cash < cost:
				return {"ok": false, "msg": "Internetausbau kostet %s." % Catalog.money(cost)}
			if not on_site and not _at_own_office(cid):
				var ob: Dictionary = _nearest_own_office(cid)
				return _start_visit(cid, a, ob.walk, -1, ob.name)
			L.book("office", -cost, true, "Internet Stufe %d" % (c.internet_level + 1), sim.game_min)
			c.internet_level += 1
			sim.log_event("%s richtet Internet Stufe %d ein." % [c.company_name, c.internet_level], "info", cid)
			sim.bark(cid, "internet")
			return {"ok": true, "msg": "Internet Stufe %d aktiv (%s)." % [c.internet_level,
				"Aufträge im eigenen Büro sammeln" if c.internet_level == 1 else "Aufträge von überall sammeln"]}
		"take_loan", "request_loan":
			var amount := _f(a.amount)
			if amount <= 0.0:
				return {"ok": false, "msg": "Betrag muss positiv sein."}
			var bank := Banking.bank_index(_s(a.get("bank", "B1")))
			if bank < 0:
				return {"ok": false, "msg": "Unbekannte Bank (B1 Geschäftsbank, B2 Investitionsbank, B3 Handelsbank)."}
			var months := _i(a.get("monate", 6)) if a.get("monate") != null else 6
			var coll := _i(a.fahrzeug_id) if a.get("fahrzeug_id") != null else -1
			if coll < 0 and amount > float(Banking.BANKS[bank].free_limit):
				coll = sim.banking.best_collateral(cid)
			var q: Dictionary = sim.banking.quote(bank, cid, amount, months, coll)
			if not q.ok:
				return {"ok": false, "msg": q.msg}
			var loan: Dictionary = sim.banking.grant(q, cid, coll, _s(a.get("zweck", "")))
			return {"ok": true, "msg": "Kredit %s: %s erhalten. %s Schulden: %s." % [loan.id, Catalog.money(amount), q.msg, Catalog.money(L.debt)]}
		"repay_loan":
			var asked := _s(a.get("kredit_id", ""))
			if asked != "":
				var target: Dictionary = sim.banking.loans.get(asked, {})
				if target.is_empty() or int(target.owner) != cid:
					return {"ok": false, "msg": "Kredit %s gehört dir nicht oder existiert nicht." % asked}
			var amount := minf(_f(a.amount), L.debt)
			if amount <= 0.0:
				return {"ok": false, "msg": "Keine Schulden oder Betrag ungültig."}
			var lid := _s(a.get("kredit_id", ""))
			if lid == "":
				var open: Array = sim.banking.loans.values().filter(func(l): return l.owner == cid and l.status in ["laufend", "rueckstand"])
				if open.is_empty():
					return {"ok": false, "msg": "Kein offener Kredit."}
				lid = open[0].id
			return sim.banking.early_repay(lid, amount, cid)
		"bid_auction":
			return sim.insolvency.bid(cid, _s(a.auction_id), _f(a.amount))
		"buy_material":
			var item := _s(a.item)
			var site: int = _i(a.depot_id) if a.get("depot_id") != null else int(c.depots[0])
			if site not in c.depots:
				return {"ok": false, "msg": "Ziel muss eines deiner Depots sein."}
			var mode := "liefern" if _s(a.get("lieferung", "abholen")) == "liefern" else "abholen"
			var res: Dictionary = sim.trader.sell(cid, {item: _i(a.menge)}, mode, site)
			if res.ok and mode == "abholen":
				res.msg += " Transportauftrag %s (Bauhof → Depot) ist angelegt." % sim.trader.make_shipment(cid, {item: _i(a.menge)}, site)
			return res
		"sell_material":
			var site2: int = _i(a.depot_id) if a.get("depot_id") != null else int(c.depots[0])
			return sim.trader.buy_back(cid, _s(a.item), _i(a.menge), site2)
		"change_company_form":
			return CompanyForms.request_change(sim, cid, _s(a.form))
		"deposit_money":
			var bank := Banking.bank_index(_s(a.get("bank", "B3")))
			if bank < 0:
				return {"ok": false, "msg": "Unbekannte Bank."}
			return sim.banking.deposit(cid, bank, _f(a.amount), _s(a.get("art", "tages")), _i(a.get("monate", 0)) if a.get("monate") != null else 0)
		"withdraw_deposit":
			return sim.banking.withdraw(cid, _s(a.einlage_id))
		"send_message":
			var to_s := _s(a.to).to_lower()
			var to := -1 if to_s in ["all", "alle", "-1"] else _i(to_s.trim_prefix("player:"))
			var private := _b(a.get("private", false)) if a.get("private") != null else false
			if to >= 0 and not private and sim.company(to) != null \
					and sim.avatars[cid].pos.distance_to(sim.avatars[to].pos) > Catalog.TALK_DISTANCE:
				return {"ok": false, "msg": "Öffentlich ansprechen geht nur bei einer Begegnung – private=true (Funk) nutzen oder mit move_to player:%d hingehen." % to}
			var err: String = sim.social.send_message(cid, to, _s(a.text), private)
			if err != "":
				return {"ok": false, "msg": err}
			return {"ok": true, "msg": "Nachricht gesendet."}
		"offer_trade":
			return sim.social.create_offer(cid, _i(a.to), _s(a.kind), a)
		"accept_trade":
			return sim.social.accept_offer(cid, _s(a.offer_id))
		"counter_offer":
			return sim.social.counter_offer(cid, _s(a.offer_id), a)
		"reject_trade":
			return sim.social.reject_offer(cid, _s(a.offer_id))
		"propose_cooperation":
			var to := _i(a.to)
			if sim.company(to) == null or to == cid:
				return {"ok": false, "msg": "Unbekannter Spieler."}
			if sim.social.has_pact(cid, to):
				return {"ok": false, "msg": "Es besteht bereits ein Pakt."}
			if not on_site and sim.avatars[cid].pos.distance_to(sim.avatars[to].pos) > 40.0:
				return _start_visit(cid, a, sim.avatars[to].tile(), to, "zu " + sim.company(to).player_name)
			var p := {"duration_hours": a.get("duration_hours", 8.0), "note": a.get("note", "")}
			return sim.social.create_offer(cid, to, "cooperation", p)
		"poach_customer":
			return sim.rivalry.poach_customer(cid, _i(a.customer_id))
		"buy_security":
			return sim.rivalry.buy_security(cid, _i(a.level))
		"set_insurance":
			c.insurance = _b(a.active)
			return {"ok": true, "msg": "Versicherung %s." % ("aktiv" if c.insurance else "gekündigt")}
		"attempt_sabotage":
			var target := _i(a.target)
			var kind := _s(a.kind)
			var err: String = sim.rivalry.check_sabotage(cid, target, kind)
			if err != "":
				return {"ok": false, "msg": err}
			if Catalog.SABOTAGE[kind].visit and not on_site:
				var tb: Dictionary = sim.city.building(sim.company(target).depots[0])
				if not _near(cid, tb.walk):
					return _start_visit(cid, a, tb.walk, -1, "zum Depot von " + sim.company(target).company_name)
			return sim.rivalry.execute_sabotage(cid, target, kind)
	return {"ok": false, "msg": "Nicht implementiert: " + name}


func _own_vehicle(cid: int, vid: int) -> FleetVehicle:
	var v: FleetVehicle = sim.vehicles.get(vid)
	return v if v != null and v.owner == cid and v.operator < 0 else null


## Fuer Disposition: eigenes Fahrzeug (nicht vermietet) oder gemietetes Fahrzeug.
func _operable_vehicle(cid: int, vid: int) -> FleetVehicle:
	var v: FleetVehicle = sim.vehicles.get(vid)
	return v if v != null and ((v.owner == cid and v.operator < 0) or v.operator == cid) else null


func _no_vehicle(vid) -> Dictionary:
	return {"ok": false, "msg": "Fahrzeug %s gehört dir nicht." % _s(vid)}


func _accept_contract(cid: int, kid: String, vid: int) -> Dictionary:
	var c: Company = sim.company(cid)
	var k: Contract = sim.contracts.get(kid)
	if k == null or k.status != "open":
		return {"ok": false, "msg": "Auftrag %s ist nicht (mehr) verfügbar." % kid}
	if k.exclusive_for >= 0 and k.exclusive_for != cid and k.exclusive_until > sim.game_min:
		return {"ok": false, "msg": "Auftrag %s ist noch exklusiv für einen Stammkunden-Partner reserviert." % kid}
	if not c.known.has(kid):
		return {"ok": false, "msg": "Auftrag %s ist dir unbekannt – zuerst collect_contracts (Jobbörse oder Büro mit Internet)." % kid}
	if c.reputation < k.min_rep:
		return {"ok": false, "msg": "Reputation %.0f zu niedrig (benötigt %.0f)." % [c.reputation, k.min_rep]}
	var active := active_contracts(cid)
	if active >= c.contract_capacity():
		return {"ok": false, "msg": "Büro ausgelastet (%d/%d laufende Aufträge) – Büro eröffnen oder ausbauen." % [active, c.contract_capacity()]}
	if vid >= 0:
		var v := _own_vehicle(cid, vid)
		if v == null:
			return _no_vehicle(vid)
		if not k.vehicle_ok(v.model):
			return {"ok": false, "msg": "Fahrzeug #%d erfüllt nicht: %s." % [vid, k.requirement_text()]}
	k.status = "accepted"
	k.owner = cid
	k.accepted_at = sim.game_min
	sim.market.on_accepted(k)
	var msg := "Auftrag %s angenommen (%s, Frist %s)." % [kid, Catalog.money(k.reward), Catalog.game_minutes_to_text(k.deadline)]
	if vid >= 0:
		var r := _assign(cid, vid, kid)
		msg += " " + r.msg
	return {"ok": true, "msg": msg}


func active_contracts(cid: int) -> int:
	return sim.contracts.values().filter(func(x): return x.owner == cid and x.status in ["accepted", "assigned", "loading", "in_transit"]).size()


## Fahrt Laden -> Abladen anhaengen. qty < 0: ganze verfuegbare Menge (muss in das Fahrzeug passen).
func _assign(cid: int, vid: int, kid: String, qty: int = -1, from: String = Logistics.PICKUP, to: String = Logistics.DROP) -> Dictionary:
	var v := _operable_vehicle(cid, vid)
	if v == null:
		return _no_vehicle(vid)
	var k: Contract = sim.contracts.get(kid)
	if k == null or k.status not in ["accepted", "assigned", "in_transit"] or (k.owner != cid and sim.social.split_quota(cid, kid) <= 0):
		return {"ok": false, "msg": "Auftrag %s ist nicht dein laufender Auftrag (oder Unterauftrag)." % kid}
	if v.state in ["broken", "repairing", "to_workshop"]:
		return {"ok": false, "msg": "Fahrzeug #%d ist in Reparatur." % vid}
	if v.stops.size() >= 10:
		return {"ok": false, "msg": "#%d hat schon 10 geplante Stopps." % vid}
	var avail: int = sim.logistics.available(k, from, null)
	if k.owner != cid:
		avail = mini(avail, sim.social.split_quota(cid, kid))
	if qty < 0:
		qty = avail
		if qty > int(v.spec().capacity):
			return {"ok": false, "msg": "%s hat %d Einheiten, #%d fasst %d – mit 'menge' aufteilen oder plan_tour nutzen." % [kid, qty, vid, v.spec().capacity]}
	if qty <= 0:
		return {"ok": false, "msg": "Bei %s ist von %s nichts mehr zu verplanen." % [from, kid]}
	var stops: Array = sim.logistics.direct_stops(k, qty, from, to)
	var err: String = sim.logistics.validate(v, stops)
	if err != "":
		return {"ok": false, "msg": err}
	sim.logistics.add_stops(v, stops)
	var note := "" if sim.driver_of(v) != null else " Achtung: #%d hat keinen Fahrer – Aufgabe 'fahren' vergeben!" % vid
	return {"ok": true, "msg": "%d × %s (%s) von %s nach %s an #%d disponiert.%s" % [qty, k.cargo_name(), kid, from, to, vid, note]}


func _near(cid: int, cell: Vector2i) -> bool:
	var t: Vector2i = sim.avatars[cid].tile()
	return absi(t.x - cell.x) + absi(t.y - cell.y) <= 2


func _move_to(cid: int, target: String) -> Dictionary:
	var a: Avatar = sim.avatars[cid]
	var cell := Vector2i(-1, -1)
	var follow := -1
	if target.begins_with("player:"):
		follow = target.trim_prefix("player:").to_int()
		if sim.company(follow) == null or follow == cid:
			return {"ok": false, "msg": "Unbekannter Spieler."}
		cell = sim.avatars[follow].tile()
	elif target.begins_with("building:"):
		var b: Dictionary = sim.city.building(target.trim_prefix("building:").to_int())
		if b.is_empty():
			return {"ok": false, "msg": "Unbekanntes Gebäude."}
		cell = b.walk
	elif target == "depot":
		cell = sim.city.building(sim.company(cid).depots[0]).walk
	else:
		return {"ok": false, "msg": "Ziel muss 'building:<id>', 'player:<id>' oder 'depot' sein."}
	a.pending = {"follow": follow} if follow >= 0 else {}
	a.queue.clear()   # ausdruecklicher Gang ersetzt geplante Besuche
	if not sim.walk_avatar(a, cell):
		return {"ok": false, "msg": "Kein Fußweg dorthin gefunden."}
	return {"ok": true, "msg": "Unterwegs."}


func _start_visit(cid: int, action: Dictionary, cell: Vector2i, follow: int, where: String) -> Dictionary:
	var a: Avatar = sim.avatars[cid]
	var visit := {"action": action.duplicate(), "follow": follow, "place": where, "cell": cell, "key": _cur_key, "origin": _cur_origin}
	if a.pending.has("action"):
		if a.queue.size() >= 3:
			return {"ok": false, "msg": "Die Figur hat schon 4 Besuche geplant. Erst abarbeiten lassen."}
		a.queue.append(visit)
		return {"ok": true, "pending": true, "msg": "Besuch (%s) eingereiht – Position %d." % [where, a.queue.size() + 1]}
	if not sim.walk_avatar(a, cell):
		return {"ok": false, "msg": "Kein Fußweg zu %s gefunden." % where}
	a.pending = visit
	return {"ok": true, "pending": true, "msg": "Figur geht zu %s; Ausführung bei Ankunft." % where}


## Naechsten eingereihten Besuch starten (nach Ankunft beim vorherigen).
func start_queued_visit(cid: int) -> void:
	var a: Avatar = sim.avatars[cid]
	while not a.queue.is_empty() and a.pending.is_empty():
		var visit: Dictionary = a.queue.pop_front()
		var target: Vector2i = visit.cell
		if visit.follow >= 0:
			target = sim.avatars[visit.follow].tile()
		if sim.walk_avatar(a, target):
			a.pending = visit


## Eigene Bueros: angemietete Bueroflaechen plus fertiges Unternehmerbuero auf dem Betriebshof.
func office_sites(cid: int) -> Array:
	var c: Company = sim.company(cid)
	return c.offices + ([c.depots[0]] if c.plot_office_level > 0 else [])


func _at_own_office(cid: int) -> bool:
	for site in office_sites(cid):
		if _near(cid, sim.city.building(site).walk):
			return true
	return false


func _nearest_own_office(cid: int) -> Dictionary:
	var best := {}
	var t: Vector2i = sim.avatars[cid].tile()
	for site in office_sites(cid):
		var b: Dictionary = sim.city.building(site)
		if best.is_empty() or Vector2(b.walk - t).length() < Vector2(best.walk - t).length():
			best = b
	return best


func _collect(cid: int, a: Dictionary, on_site: bool) -> Dictionary:
	var c: Company = sim.company(cid)
	var t: Vector2i = sim.avatars[cid].tile()
	var board: Dictionary = sim.nearest_building_of("job_board", t)
	var allowed := on_site or c.internet_level >= 2 or (c.internet_level >= 1 and _at_own_office(cid)) or _near(cid, board.walk)
	if not allowed:
		if c.internet_level >= 1:
			var ob := _nearest_own_office(cid)
			if Vector2(ob.walk - t).length() < Vector2(board.walk - t).length():
				return _start_visit(cid, a, ob.walk, -1, ob.name)
		return _start_visit(cid, a, board.walk, -1, board.name)
	var n := 0
	for k in sim.market.open_contracts():
		if k.exclusive_for >= 0 and k.exclusive_for != cid and k.exclusive_until > sim.game_min:
			continue
		if not c.known.has(k.id):
			c.known[k.id] = true
			n += 1
	sim.bark(cid, "jobboerse")
	return {"ok": true, "msg": "%d neue Aufträge gesammelt." % n}


func _build_office(cid: int, a: Dictionary, site: int, on_site: bool) -> Dictionary:
	var c: Company = sim.company(cid)
	var b: Dictionary = sim.city.building(site)
	if b.is_empty() or b.role != "office_site":
		return {"ok": false, "msg": "%d ist kein Bürostandort." % site}
	if site in c.offices:
		return {"ok": false, "msg": "Dort hast du bereits ein Büro."}
	var cost := Catalog.OFFICE_HQ_COST if c.offices.is_empty() else Catalog.OFFICE_BRANCH_COST + 3000.0 * (c.offices.size() - 1)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Büroeröffnung kostet %s." % Catalog.money(cost)}
	if not on_site and not _near(cid, b.walk):
		return _start_visit(cid, a, b.walk, -1, b.name)
	c.ledger.invest(cost)
	c.property_cost += cost
	c.property_book += cost
	c.offices.append(site)
	var hq := c.offices.size() == 1
	if hq:
		c.office_level = 1
	sim.log_event("%s eröffnet %s in %s." % [c.company_name, "die Zentrale" if hq else "eine Filiale", b.name], "info", cid)
	c.add_key_event(("Zentrale: " if hq else "Filiale: ") + b.name, sim.game_min)
	sim.bark(cid, "buero")
	return {"ok": true, "msg": "%s eröffnet – Auftragskapazität jetzt %d." % ["Zentrale" if hq else "Filiale", c.contract_capacity()]}


## Bei Ankunft der Figur: erneut pruefen und ausfuehren.
func complete_visit(cid: int, pending: Dictionary) -> void:
	if not pending.has("action"):
		return
	var a: Dictionary = pending.action
	var name := str(a.get("action", ""))
	var r := _do(cid, name, a, true)
	sim.record_result(cid, "%s %s (vor Ort): %s" % ["OK" if r.ok else "ABGELEHNT", name, r.msg])
	sim.plans.visit_done(cid, str(pending.get("key", "")), r)
	sim.decisions.record(cid, str(pending.get("origin", "api")), a, r, str(pending.get("key", "")) + "@vor_ort")
	sim.agent_event.emit(cid, "Besuch abgeschlossen: " + name)
