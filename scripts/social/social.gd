class_name Social
extends RefCounted
## Nachrichten, verbindliche Geschaeftsangebote, Kooperationspakte und Vertrauen.
## Eine Nachricht allein uebertraegt nie Besitz: Dafuer braucht es ein Angebot (offer_trade)
## und dessen Annahme (accept_trade); erst dann prueft und bucht die Engine die Transaktion.

const OFFER_KINDS := ["sell_vehicle", "buy_vehicle", "transfer_contract", "payment", "cooperation",
	"capacity_rental", "storage_share", "split_contract"]
const MAX_ROUNDS := 3     # Angebot + hoechstens 2 Gegenangebote, dann Entscheidung oder Abbruch

var sim
var messages: Array = []       # {id, t, from, to, text, private}
var offers := {}               # id -> Angebot
var pacts := {}                # "a-b" -> bis Spielminute
var trust := {}                # "a>b" -> -100..100
var _msg_times := {}           # Firmen-ID -> [Spielminuten]
var _convo := {}               # "a-b" -> [Spielminuten]
var next_offer := 1
var agreements := {}           # laufende verbindliche Vertraege (Vermietung, Lager, Teilauftrag)
var next_agreement := 1
var next_msg := 1


func setup(simulation) -> void:
	sim = simulation


static func pair_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


func has_pact(a: int, b: int) -> bool:
	return pacts.get(pair_key(a, b), -1.0) > sim.game_min


func get_trust(a: int, b: int) -> float:
	return trust.get("%d>%d" % [a, b], 0.0)


func add_trust(a: int, b: int, delta: float) -> void:
	for k in ["%d>%d" % [a, b], "%d>%d" % [b, a]]:
		trust[k] = clampf(trust.get(k, 0.0) + delta, -100.0, 100.0)


## Gibt "" bei Erfolg zurueck, sonst eine Fehlermeldung (Budget, Laenge, Empfaenger).
func check_message(from: int, to: int, text: String) -> String:
	if text.strip_edges() == "":
		return "Leere Nachricht."
	if to != -1 and (sim.company(to) == null or to == from):
		return "Unbekannter Empfänger."
	var now: float = sim.game_min
	var times: Array = _msg_times.get(from, []).filter(func(t): return now - t < 60.0)
	if times.size() >= Catalog.MESSAGES_PER_HOUR:
		return "Nachrichtenbudget erschöpft (max. %d pro Spielstunde). Bitte erst wieder handeln." % Catalog.MESSAGES_PER_HOUR
	if to != -1:
		var conv: Array = _convo.get(pair_key(from, to), []).filter(func(t): return now - t < 120.0)
		if conv.size() >= Catalog.CONVERSATION_ROUNDS:
			return "Gesprächsrunden mit diesem Spieler ausgeschöpft. Das Gespräch ist vorerst beendet."
	return ""


func send_message(from: int, to: int, text: String, private: bool) -> String:
	var err := check_message(from, to, text)
	if err != "":
		return err
	text = text.strip_edges().left(220)
	var now: float = sim.game_min
	if not _msg_times.has(from):
		_msg_times[from] = []
	_msg_times[from].append(now)
	_msg_times[from] = _msg_times[from].filter(func(t): return now - t < 60.0)
	if to != -1:
		var key := pair_key(from, to)
		if not _convo.has(key):
			_convo[key] = []
		_convo[key].append(now)
		_convo[key] = _convo[key].filter(func(t): return now - t < 120.0)
	private = private and to != -1
	var m := {"id": next_msg, "t": now, "from": from, "to": to, "text": text, "private": private}
	next_msg += 1
	messages.append(m)
	if messages.size() > 300:
		messages.pop_front()
	var a: Avatar = sim.avatars[from]
	if private:
		a.say("[vertraulich an %s]" % sim.company(to).player_name, true)
	else:
		a.say(text, false)
	sim.sfx.emit("message")
	for c in sim.companies:
		if c.id != from and (to == -1 or to == c.id):
			sim.agent_event.emit(c.id, "Nachricht von %s" % sim.company(from).player_name)
	return ""


## Nachrichten, die eine Firma sehen darf: oeffentliche und an sie gerichtete/von ihr gesendete private.
func visible_messages(cid: int, since: float) -> Array:
	return messages.filter(func(m): return m.t >= since and (not m.private or m.to == cid or m.from == cid))


func open_offers_from(cid: int) -> int:
	return offers.values().filter(func(o): return o.from == cid and o.status == "open").size()


func create_offer(from: int, to: int, kind: String, p: Dictionary) -> Dictionary:
	if kind not in OFFER_KINDS:
		return {"ok": false, "msg": "Unbekannte Angebotsart '%s'. Erlaubt: %s" % [kind, ", ".join(OFFER_KINDS)]}
	if sim.company(to) == null or to == from:
		return {"ok": false, "msg": "Unbekannter Empfänger."}
	if open_offers_from(from) >= Catalog.MAX_OPEN_OFFERS:
		return {"ok": false, "msg": "Zu viele offene Angebote (max. %d)." % Catalog.MAX_OPEN_OFFERS}
	var o := {"id": "G%d" % next_offer, "from": from, "to": to, "kind": kind, "status": "open",
		"price": float(p.get("price", 0.0)), "vehicle_id": int(p.get("vehicle_id", -1)),
		"contract_id": str(p.get("contract_id", "")), "duration_hours": clampf(float(p.get("duration_hours", 8.0)), 1.0, 24.0),
		"note": str(p.get("note", "")).left(160), "created": sim.game_min,
		"expires": sim.game_min + Catalog.OFFER_EXPIRY_MIN, "strafe": maxf(0.0, float(p.get("strafe", 0.0))),
		"site_id": int(p.get("site_id", -1)), "plaetze": int(p.get("plaetze", 0)), "menge": int(p.get("menge", 0)),
		"awaiting": to, "round": 1}
	if kind != "transfer_contract" and o.price < 0.0:
		return {"ok": false, "msg": "Preis darf nicht negativ sein."}
	# Vorpruefung jetzt (endgueltige Pruefung bei Annahme)
	var err := _validate(o, false)
	if err != "":
		return {"ok": false, "msg": err}
	next_offer += 1
	offers[o.id] = o
	sim.log_event("%s → %s: Angebot %s (%s)" % [sim.company(from).company_name, sim.company(to).company_name,
		o.id, describe(o)], "deal", from)
	sim.agent_event.emit(to, "Neues Angebot %s von %s" % [o.id, sim.company(from).player_name])
	return {"ok": true, "msg": "Angebot %s an %s gesendet." % [o.id, sim.company(to).player_name], "id": o.id}


func describe(o: Dictionary) -> String:
	match o.kind:
		"sell_vehicle":
			return "verkauft Fahrzeug #%d für %s" % [o.vehicle_id, Catalog.money(o.price)]
		"buy_vehicle":
			return "kauft Fahrzeug #%d für %s" % [o.vehicle_id, Catalog.money(o.price)]
		"transfer_contract":
			return "gibt Auftrag %s ab, Empfänger zahlt %s" % [o.contract_id, Catalog.money(o.price)]
		"payment":
			return "zahlt %s" % Catalog.money(o.price)
		"cooperation":
			return "Kooperationspakt für %d Spielstunden" % int(o.duration_hours)
		"capacity_rental":
			return "vermietet #%d mit Fahrer für %d h, Miete %s, Überziehung %s/h" % [o.vehicle_id, int(o.duration_hours), Catalog.money(o.price), Catalog.money(o.strafe)]
		"storage_share":
			return "überlässt %d Lagerplätze in Depot %d für %d h, Preis %s" % [o.plaetze, o.site_id, int(o.duration_hours), Catalog.money(o.price)]
		"split_contract":
			return "vergibt %d Einheiten von %s als Unterauftrag, zahlt %s bei Lieferung, Strafe bei Verfehlung %s" % [o.menge, o.contract_id, Catalog.money(o.price), Catalog.money(o.strafe)]
	return o.kind


## Prueft ein Angebot gegen den aktuellen Zustand. final = bei Annahme.
func _validate(o: Dictionary, final: bool) -> String:
	var a: Company = sim.company(o.from)
	var b: Company = sim.company(o.to)
	match o.kind:
		"sell_vehicle", "buy_vehicle":
			var seller: Company = a if o.kind == "sell_vehicle" else b
			var buyer: Company = b if o.kind == "sell_vehicle" else a
			var v: FleetVehicle = sim.vehicles.get(o.vehicle_id)
			if v == null or v.owner != seller.id:
				return "Fahrzeug #%d gehört nicht %s." % [o.vehicle_id, seller.company_name]
			if final and (v.state not in ["idle", "returning"] or not v.stops.is_empty() or not v.load.is_empty()):
				return "Fahrzeug #%d ist im Einsatz und kann gerade nicht übergeben werden." % o.vehicle_id
			if seller.vehicle_ids.size() <= 1:
				return "Das letzte Fahrzeug einer Firma kann nicht verkauft werden."
			if final and buyer.vehicle_ids.size() >= buyer.fleet_limit():
				return "%s hat keinen freien Depotplatz." % buyer.company_name
			if final and buyer.ledger.cash < o.price:
				return "%s hat nicht genug Bargeld." % buyer.company_name
		"transfer_contract":
			var k: Contract = sim.contracts.get(o.contract_id)
			if k == null or k.owner != a.id or k.status != "accepted":
				return "Auftrag %s gehört nicht %s oder ist bereits disponiert." % [o.contract_id, a.company_name]
			if final and b.reputation < k.min_rep:
				return "%s erfüllt die Mindestreputation nicht." % b.company_name
			if final and o.price > 0.0 and b.ledger.cash < o.price:
				return "%s hat nicht genug Bargeld." % b.company_name
			if final and o.price < 0.0 and a.ledger.cash < -o.price:
				return "%s hat nicht genug Bargeld." % a.company_name
		"payment":
			if final and a.ledger.cash < o.price:
				return "%s hat nicht genug Bargeld." % a.company_name
		"cooperation":
			if has_pact(a.id, b.id):
				return "Es besteht bereits ein Pakt."
		"capacity_rental":
			var v: FleetVehicle = sim.vehicles.get(o.vehicle_id)
			if v == null or v.owner != a.id:
				return "Fahrzeug #%d gehört nicht %s." % [o.vehicle_id, a.company_name]
			if v.operator >= 0 or _vehicle_promised(v.id, o.id):
				return "#%d ist bereits vermietet oder anderweitig zugesagt." % v.id
			if sim.driver_of(v) == null:
				return "#%d hat keinen Fahrer." % v.id
			if final and (not v.stops.is_empty() or not v.load.is_empty() or v.state not in ["idle", "returning"]):
				return "#%d ist noch im Einsatz." % v.id
			if final and b.ledger.cash < o.price:
				return "%s hat nicht genug Bargeld." % b.company_name
		"storage_share":
			if o.site_id not in a.depots:
				return "Depot %d gehört nicht %s." % [o.site_id, a.company_name]
			var free: int = sim.logistics.storage_cap(o.site_id) - sim.logistics.storage_used(o.site_id) - _shared_places(o.site_id, o.id)
			if o.plaetze <= 0 or o.plaetze > free:
				return "In Depot %d sind nur %d Plätze frei (inkl. Zusagen)." % [o.site_id, maxi(0, free)]
			if final and b.ledger.cash < o.price:
				return "%s hat nicht genug Bargeld." % b.company_name
		"split_contract":
			var k: Contract = sim.contracts.get(o.contract_id)
			if k == null or k.owner != a.id or k.status not in ["accepted", "assigned", "in_transit"]:
				return "Auftrag %s ist kein laufender Auftrag von %s." % [o.contract_id, a.company_name]
			var avail: int = sim.logistics.available(k, Logistics.PICKUP) - _split_reserved(k.id, o.id)
			if o.menge <= 0 or o.menge > avail:
				return "Von %s sind nur noch %d Einheiten an der Abholung unverplant." % [k.id, maxi(0, avail)]
			if final and b.reputation < k.min_rep:
				return "%s erfüllt die Mindestreputation nicht." % b.company_name
			if final and a.ledger.cash < o.price:
				return "%s kann den Unterauftrag nicht bezahlen." % a.company_name
	return ""


## Zusagen: dieselbe Kapazitaet darf nicht mehrfach gleichzeitig versprochen werden.
func _vehicle_promised(vid: int, except_offer: String) -> bool:
	for o in offers.values():
		if o.id != except_offer and o.status == "open" and o.kind == "capacity_rental" and o.vehicle_id == vid:
			return true
	return false


func _shared_places(site: int, except_offer: String) -> int:
	var n := 0
	for o in offers.values():
		if o.id != except_offer and o.status == "open" and o.kind == "storage_share" and o.site_id == site:
			n += o.plaetze
	for g in agreements.values():
		if g.status == "aktiv" and g.kind == "storage_share" and g.site_id == site:
			n += int(g.plaetze)
	return n


func _split_reserved(kid: String, except_offer: String) -> int:
	var n := 0
	for o in offers.values():
		if o.id != except_offer and o.status == "open" and o.kind == "split_contract" and o.contract_id == kid:
			n += o.menge
	for g in agreements.values():
		if g.status == "aktiv" and g.kind == "split_contract" and g.contract_id == kid:
			n += int(g.menge) - int(g.geliefert)
	return n


## Lager, das eine Firma (als Mitnutzer) verwenden darf: freie Plaetze aus aktiven Vertraegen.
func storage_rights(cid: int, site: int) -> int:
	var n := 0
	for g in agreements.values():
		if g.status == "aktiv" and g.kind == "storage_share" and g.site_id == site and g.to == cid:
			n += int(g.plaetze)
	return n


## Restmenge, die ein Subunternehmer fuer einen fremden Auftrag noch laden darf.
func split_quota(cid: int, kid: String) -> int:
	var n := 0
	for g in agreements.values():
		if g.status == "aktiv" and g.kind == "split_contract" and g.contract_id == kid and g.to == cid:
			n += int(g.menge) - int(g.geladen)
	return n


func agreement_for_delivery(cid: int, kid: String) -> Dictionary:
	for g in agreements.values():
		if g.status == "aktiv" and g.kind == "split_contract" and g.contract_id == kid and g.to == cid:
			return g
	return {}


## Gegenangebot: gleiche Vertragsart, geaenderte Konditionen; die Gegenseite muss nun annehmen.
func counter_offer(by: int, offer_id: String, p: Dictionary) -> Dictionary:
	var o: Dictionary = offers.get(offer_id, {})
	if o.is_empty() or o.status != "open" or int(o.awaiting) != by:
		return {"ok": false, "msg": "Kein offenes Angebot %s, auf das du antworten kannst." % offer_id}
	if int(o.round) >= MAX_ROUNDS:
		o.status = "abgebrochen"
		sim.notify(o.from if by == o.to else o.to, "Verhandlung %s nach %d Runden ohne Einigung beendet." % [offer_id, MAX_ROUNDS])
		return {"ok": false, "msg": "Maximal %d Verhandlungsrunden – Verhandlung beendet. Annehmen oder ablehnen." % MAX_ROUNDS}
	var c := o.duplicate()
	c.id = "G%d" % next_offer
	next_offer += 1
	for k in ["price", "duration_hours", "strafe", "plaetze", "menge"]:
		if p.get(k) != null:
			c[k] = float(p[k]) if k in ["price", "duration_hours", "strafe"] else int(p[k])
	c.note = str(p.get("note", "")).left(160)
	c.round = int(o.round) + 1
	c.awaiting = o.to if by == o.from else o.from
	c.created = sim.game_min
	c.expires = sim.game_min + Catalog.OFFER_EXPIRY_MIN
	c.counter_of = o.id
	o.status = "gegenangebot"   # das Original zaehlt bei der Reservierungspruefung nicht mehr mit
	var err := _validate(c, false)
	if err != "":
		o.status = "open"
		return {"ok": false, "msg": "Gegenangebot ungültig: " + err}
	offers[c.id] = c
	sim.log_event("%s: Gegenangebot %s zu %s (%s, Runde %d)" % [sim.company(by).company_name, c.id, o.id, describe(c), c.round], "deal", by)
	sim.agent_event.emit(int(c.awaiting), "Gegenangebot %s von %s" % [c.id, sim.company(by).player_name])
	return {"ok": true, "msg": "Gegenangebot %s gesendet (Runde %d/%d)." % [c.id, c.round, MAX_ROUNDS], "id": c.id}


func accept_offer(by: int, offer_id: String) -> Dictionary:
	var o: Dictionary = offers.get(offer_id, {})
	if o.is_empty():
		return {"ok": false, "msg": "Angebot %s existiert nicht." % offer_id}
	if int(o.get("awaiting", o.to)) != by:
		return {"ok": false, "msg": "Angebot %s wartet nicht auf deine Annahme." % offer_id}
	if o.status != "open":
		return {"ok": false, "msg": "Angebot %s ist nicht mehr offen (%s)." % [offer_id, o.status]}
	var err := _validate(o, true)
	if err != "":
		o.status = "invalid"
		sim.notify(o.from, "Dein Angebot %s scheiterte bei Annahme: %s" % [offer_id, err])
		return {"ok": false, "msg": "Angebot ungültig: " + err}
	_execute(o)
	o.status = "accepted"
	var a: Company = sim.company(o.from)
	var b: Company = sim.company(o.to)
	a.stats.deals += 1
	b.stats.deals += 1
	add_trust(a.id, b.id, 8.0)
	var txt := "Geschäft abgeschlossen: %s %s an %s." % [a.company_name, describe(o), b.company_name]
	sim.log_event(txt, "deal", by)
	a.add_key_event("Geschäft mit %s: %s" % [b.company_name, describe(o)], sim.game_min)
	b.add_key_event("Geschäft mit %s: %s" % [a.company_name, describe(o)], sim.game_min)
	var other: int = o.from if by == o.to else o.to
	sim.notify(other, "%s hat Angebot %s angenommen." % [sim.company(by).player_name, offer_id])
	sim.sfx.emit("deal")
	return {"ok": true, "msg": txt}


func reject_offer(by: int, offer_id: String) -> Dictionary:
	var o: Dictionary = offers.get(offer_id, {})
	if o.is_empty() or int(o.get("awaiting", o.to)) != by or o.status != "open":
		return {"ok": false, "msg": "Kein offenes Angebot %s an dich." % offer_id}
	o.status = "rejected"
	add_trust(o.from, o.to, -2.0)
	sim.notify(o.from if by == o.to else o.to, "%s hat Angebot %s abgelehnt." % [sim.company(by).player_name, offer_id])
	return {"ok": true, "msg": "Angebot %s abgelehnt." % offer_id}


func _execute(o: Dictionary) -> void:
	var now: float = sim.game_min
	var a: Company = sim.company(o.from)
	var b: Company = sim.company(o.to)
	match o.kind:
		"sell_vehicle", "buy_vehicle":
			var seller: Company = a if o.kind == "sell_vehicle" else b
			var buyer: Company = b if o.kind == "sell_vehicle" else a
			var v: FleetVehicle = sim.vehicles[o.vehicle_id]
			# Verkaeufer: Abgang zum Buchwert, Ergebnis = Preis - Buchwert
			seller.ledger.divest(o.price, "C0")
			seller.ledger.book("asset_result", o.price - v.book_value, false, "Verkauf #%d an %s" % [v.id, buyer.company_name], now)
			sim.remove_vehicle(v)
			# Kaeufer: Investition zum Kaufpreis, neue Abschreibungsbasis
			buyer.ledger.invest(o.price, "C0")
			var nv: FleetVehicle = sim.add_vehicle(buyer.id, v.model, o.price, v.tile())
			nv.condition = v.condition
		"transfer_contract":
			var k: Contract = sim.contracts[o.contract_id]
			k.owner = b.id
			_pay(b, a, o.price, "Auftragsübernahme " + k.id)
		"payment":
			_pay(a, b, o.price, "Zahlung")
		"cooperation":
			pacts[pair_key(a.id, b.id)] = now + o.duration_hours * 60.0
			add_trust(a.id, b.id, 12.0)
		"capacity_rental", "storage_share", "split_contract":
			var g := {"id": "V%d" % next_agreement, "kind": o.kind, "from": a.id, "to": b.id, "offer": o.id,
				"vehicle_id": o.vehicle_id, "site_id": o.site_id, "plaetze": o.plaetze, "contract_id": o.contract_id,
				"menge": o.menge, "geladen": 0, "geliefert": 0, "price": o.price, "strafe": o.strafe, "start": now,
				"end": now + o.duration_hours * 60.0, "status": "aktiv", "strafen_gezahlt": 0.0}
			next_agreement += 1
			agreements[g.id] = g
			if o.kind == "capacity_rental":
				sim.vehicles[o.vehicle_id].operator = b.id
				_pay(b, a, o.price, "Fahrzeugmiete #%d" % o.vehicle_id)
			elif o.kind == "storage_share":
				_pay(b, a, o.price, "Lagermitbenutzung Depot %d" % o.site_id)
			else:
				g.end = sim.contracts[o.contract_id].deadline


## payer zahlt receiver amount (negativ = umgekehrt). Fuer beide erfolgswirksam (Nullsumme).
func _pay(payer: Company, receiver: Company, amount: float, note: String) -> void:
	if amount < 0.0:
		_pay(receiver, payer, -amount, note)
		return
	payer.ledger.book("trade_expense", -amount, true, note + " an " + receiver.company_name, sim.game_min)
	receiver.ledger.book("trade_income", amount, true, note + " von " + payer.company_name, sim.game_min)


func break_pact(a: int, b: int) -> void:
	pacts.erase(pair_key(a, b))


## Vertragsfolgen: Rueckgabe, Ueberziehung, Bezahlung bei Erfuellung, Vertragsstrafen bei Bruch.
func _agreements_tick(now: float) -> void:
	for g in agreements.values():
		if g.status != "aktiv":
			continue
		var a: Company = sim.company(g.from)
		var b: Company = sim.company(g.to)
		match g.kind:
			"capacity_rental":
				var v: FleetVehicle = sim.vehicles.get(g.vehicle_id)
				if v == null:
					g.status = "beendet"
					continue
				if now >= float(g.end):
					if v.stops.is_empty() and v.load.is_empty():
						v.operator = -1
						g.status = "erfüllt" if float(g.strafen_gezahlt) == 0.0 else "überzogen"
						sim.route(v, sim.nearest_depot_road(a.id, v.tile()), "returning")
						sim.notify(a.id, "Vermietung %s beendet, #%d kehrt zurück." % [g.id, v.id])
						sim.notify(b.id, "Mietzeit für #%d (%s) ist abgelaufen." % [v.id, g.id])
						_track(b, g.status == "erfüllt")
					elif sim.minute_index % 60 == 0 and float(g.strafe) > 0.0:
						_penalty(b, a, float(g.strafe), "Überziehung Miete #%d" % v.id, g)
			"storage_share":
				if now >= float(g.end):
					var left := 0
					for kid in sim.storage.get(g.site_id, {}):
						var k: Contract = sim.contracts.get(kid)
						if k and (k.owner == b.id or agreement_for_delivery(b.id, kid).size() > 0):
							left += int(sim.storage[g.site_id][kid])
					if left == 0:
						g.status = "erfüllt" if float(g.strafen_gezahlt) == 0.0 else "überzogen"
						_track(b, g.status == "erfüllt")
					elif sim.minute_index % 60 == 0:
						_penalty(b, a, maxf(float(g.strafe), 50.0), "Restware im Lager %d" % g.site_id, g)
			"split_contract":
				var k: Contract = sim.contracts.get(g.contract_id)
				if int(g.geliefert) >= int(g.menge):
					g.status = "erfüllt"
					_pay(a, b, float(g.price), "Unterauftrag %s" % g.contract_id)
					sim.notify(b.id, "Unterauftrag %s erfüllt: %s erhalten." % [g.id, Catalog.money(g.price)])
					sim.notify(a.id, "Unterauftrag %s von %s erfüllt (%d Einheiten)." % [g.id, b.company_name, g.menge])
					_track(b, true)
					add_trust(a.id, b.id, 6.0)
				elif k == null or k.status in ["failed", "cancelled", "expired"] or now > float(g.end):
					g.status = "gebrochen"
					_penalty(b, a, float(g.strafe), "Unterauftrag %s nicht erfüllt" % g.contract_id, g)
					for veh in sim.company_vehicles(b.id):
						veh.stops = veh.stops.filter(func(st): return st.contract_id != g.contract_id or st.art == "abladen")
						sim.logistics.sync_view(veh)
					_track(b, false)
					add_trust(a.id, b.id, -15.0)


func _penalty(payer: Company, receiver: Company, amount: float, note: String, g: Dictionary) -> void:
	if amount <= 0.0:
		return
	payer.ledger.book("penalties", -amount, true, note, sim.game_min)
	receiver.ledger.book("compensation", amount, true, note, sim.game_min)
	g.strafen_gezahlt = float(g.strafen_gezahlt) + amount
	sim.notify(payer.id, "Vertragsstrafe %s: %s" % [Catalog.money(amount), note])
	sim.decisions.note(payer.id, "auto", "Vertragsstrafe %s (%s)" % [Catalog.money(amount), note], {"agreement": g.id})


func _track(c: Company, kept: bool) -> void:
	var key := "contracts_kept" if kept else "contracts_broken"
	c.stats[key] = int(c.stats.get(key, 0)) + 1


func agreements_of(cid: int) -> Array:
	return agreements.values().filter(func(g): return (g.from == cid or g.to == cid) and (g.status == "aktiv" or sim.game_min - float(g.end) < 240.0))


func tick(now: float) -> void:
	_agreements_tick(now)
	for o in offers.values():
		if o.status == "open" and now > o.expires:
			o.status = "expired"
	for id in offers.keys():
		if offers[id].status != "open" and now - offers[id].expires > 240.0:
			offers.erase(id)


func to_dict() -> Dictionary:
	return {"messages": messages.slice(-150), "offers": offers, "pacts": pacts, "trust": trust, "agreements": agreements,
		"next_agreement": next_agreement,
		"next_offer": next_offer, "next_msg": next_msg}


func from_dict(d: Dictionary) -> void:
	messages = d.messages
	for m in messages:
		m.from = int(m.from)
		m.to = int(m.to)
	offers = d.offers
	for o in offers.values():
		o.from = int(o.from)
		o.to = int(o.to)
		o.vehicle_id = int(o.vehicle_id)
		o.awaiting = int(o.get("awaiting", o.to))
		o.round = int(o.get("round", 1))
		o.site_id = int(o.get("site_id", -1))
		o.plaetze = int(o.get("plaetze", 0))
		o.menge = int(o.get("menge", 0))
	pacts = d.pacts
	agreements = d.get("agreements", {})
	for g in agreements.values():
		for k in ["from", "to", "vehicle_id", "site_id", "plaetze", "menge", "geladen", "geliefert"]:
			g[k] = int(g[k])
	next_agreement = int(d.get("next_agreement", 1))
	trust = d.trust
	next_offer = int(d.next_offer)
	next_msg = int(d.next_msg)
