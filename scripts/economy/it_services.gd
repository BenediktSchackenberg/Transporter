class_name ItServices
extends RefCounted
## IT als Dienstleistungsbranche (Auftrag 14, Etappe 5; docs/ENTREPRENEURS.md Abschnitt 6 "IT").
##
## Ein IT-Betrieb (Branche "it") schliesst Vertraege mit Betrieben anderer (oder eigener) Unternehmen. Leistungen aus
## config/branches.json (it.dienste): Umfang = Vertragsplatz, Kapazitaet = Personal x vertraege_je_person, Laufzeit, Monatspreis.
## Hardware (Computer) wird physisch geliefert: bei Vertragsschluss ein Liefervertrag vom IT-Betrieb zum Kunden (Kunde zahlt).
## Leistung: monatlich geprueft (Betrieb laeuft, Personal reicht, Strom da). Nur erbrachte Monate werden bezahlt und wirken;
## sonst "gestoert" (keine Zahlung, kein Vorteil). Interne Vertraege (gleiches Unternehmen) kosten nichts.
## Vorteile sind gemessen und begrenzt: Buero-IT senkt Buero- und Internetkosten, Lagerverwaltung senkt den Verderb.

const DURATION_DAYS := 90
const MAX_DISRUPTED := 2          # nach so vielen gestoerten Monaten in Folge endet der Vertrag

var sim
var contracts := {}               # "IT<n>" -> Vertrag
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(on_month)


static func spec() -> Dictionary:
	return Businesses.branches().get("it", {})


static func products() -> Dictionary:
	return spec().get("dienste", {})


func providers() -> Array:
	return sim.biz.items.values().filter(func(b): return b.branch == "it" and b.status in Businesses.RUNNING and not sim.biz.frozen(int(b.owner)))


func active_of(provider_id: String) -> Array:
	return contracts.values().filter(func(k): return k.provider == provider_id and k.status in ["aktiv", "gestoert"])


func capacity_of(b: Dictionary) -> int:
	return sim.biz.staff_of(b.id).size() * int(spec().get("vertraege_je_person", 4))


func fee_of(b: Dictionary, product: String) -> float:
	return float(b.get("prices", {}).get(product, products()[product].preis_monat))


## Angebote fuer die KI: je Leistung der guenstigste Anbieter mit freier Kapazitaet und Hardware.
func offers() -> Dictionary:
	var out := {}
	for p in products():
		var best := INF
		for b in providers():
			if active_of(b.id).size() < capacity_of(b) and sim.stock.available("computer", "C%d" % int(b.owner), int(b.site)) >= int(products()[p].hardware):
				best = minf(best, fee_of(b, p))
		if best < INF:
			out[p] = int(best)
	return out


## Vertrag schliessen: Kunde (Unternehmen, optional Betrieb fuer die Lagerverwaltung) waehlt den guenstigsten Anbieter mit Kapazitaet.
func buy(cid: int, product: String, client_biz: String) -> Dictionary:
	if not products().has(product):
		return {"ok": false, "msg": "Unbekannte IT-Leistung '%s'. Verfügbar: %s" % [product, ", ".join(products().keys())]}
	var P: Dictionary = products()[product]
	if bool(P.get("je_betrieb", false)):
		var cb: Dictionary = sim.biz.get_b(client_biz)
		if cb.is_empty() or int(cb.owner) != cid:
			return {"ok": false, "msg": "Für %s einen eigenen Betrieb angeben (business_id)." % P.name}
	else:
		client_biz = ""
	if contracts.values().any(func(k): return int(k.client) == cid and k.product == product and k.client_biz == client_biz and k.status in ["aktiv", "gestoert"]):
		return {"ok": false, "msg": "Dafür besteht bereits ein IT-Vertrag."}
	var best := {}
	for b in providers():
		if active_of(b.id).size() >= capacity_of(b):
			continue
		if sim.stock.available("computer", "C%d" % int(b.owner), int(b.site)) < int(P.hardware):
			continue
		if best.is_empty() or fee_of(b, product) < fee_of(best, product):
			best = b
	if best.is_empty():
		return {"ok": false, "msg": "Kein IT-Betrieb mit freier Kapazität und Hardware für %s." % P.name}
	var id := "IT%d" % _next
	_next += 1
	var day := GameCalendar.day_of(sim.game_min)
	var k := {"id": id, "provider": best.id, "provider_cid": int(best.owner), "client": cid, "client_biz": client_biz, "product": product,
		"fee": fee_of(best, product), "start": day, "end": day + DURATION_DAYS, "status": "aktiv", "ok_month": false, "disrupted": 0, "paid": 0.0}
	contracts[id] = k
	# Hardware wird geliefert (Liefervertrag vom IT-Betrieb zum Standort des Kunden; der Kunde zahlt Geraet und Fracht)
	var c = sim.company(cid)
	var site := int(sim.biz.get_b(client_biz).site) if client_biz != "" else (int(c.depots[0]) if not c.depots.is_empty() else int(best.site))
	if site != int(best.site):
		var unit := float(Production.art("computer").get("basispreis", 0.0))
		sim.prod._deal("C%d" % cid, site, client_biz, {"biz": best.id, "acct": "C%d" % int(best.owner), "cid": int(best.owner), "loc": int(best.site), "avail": int(P.hardware), "price": unit},
			"computer", int(P.hardware), unit if int(best.owner) != cid else 0.0, sim.prod.freight(int(best.site), site, "computer", int(P.hardware)))
	else:
		sim.stock.consume("computer", int(P.hardware), "C%d" % int(best.owner), int(best.site), "Installation %s" % id, sim.game_min)
	sim.biz.note(best.id, "Neuer Vertrag %s: %s für %s (%s/Monat)" % [id, P.name, c.company_name, Catalog.money(float(k.fee))], "Betrieb")
	return {"ok": true, "msg": "IT-Vertrag %s: %s von %s, %s je Monat, %d Tage." % [id, P.name, best.name, Catalog.money(float(k.fee)), DURATION_DAYS], "ref": id}


func _performs(k: Dictionary) -> bool:
	var b: Dictionary = sim.biz.get_b(str(k.provider))
	if b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
		return false
	if float(b.energy_kw) > 0.0 and not sim.grid.supplied.has(b.id):
		return false   # IT-Dienste fallen ohne Strom aus
	return active_of(b.id).size() <= capacity_of(b)


## Taeglich: Leistungsstand fuer die Wirkung; Hardware-Nachschub des Anbieters.
func on_day(_day: int) -> void:
	for k in contracts.values():
		if k.status in ["aktiv", "gestoert"]:
			k.ok_today = _performs(k)
	for b in providers():
		sim.prod._ensure_input(b, "computer", int(spec().get("hardware_lager", 4)), 1)


## Monatlich: erbrachte Leistung wird bezahlt; gestoerte Monate nicht. Ablauf und Verlaengerung.
func on_month(_m: int) -> void:
	var day := GameCalendar.day_of(sim.game_min)
	for k in contracts.values():
		if k.status not in ["aktiv", "gestoert"]:
			continue
		if _performs(k):
			k.status = "aktiv"
			k.disrupted = 0
			if int(k.client) != int(k.provider_cid):
				var fee := minf(float(k.fee), maxf(0.0, sim.company(int(k.client)).ledger.cash))
				sim.company(int(k.client)).ledger.book("trade_expense", -fee, true, "IT %s" % k.id, sim.game_min, "C0", str(k.client_biz))
				sim.company(int(k.provider_cid)).ledger.book("trade_income", fee, true, "IT-Leistung %s" % k.id, sim.game_min, "C0", str(k.provider))
				k.paid = float(k.paid) + fee
		else:
			k.status = "gestoert"
			k.disrupted = int(k.disrupted) + 1
			sim.biz.note(str(k.provider), "Vertrag %s gestört: Leistung nicht erbracht, keine Zahlung" % k.id, "Betrieb")
		if int(k.disrupted) >= MAX_DISRUPTED:
			k.status = "beendet"
		elif day >= int(k.end):
			k.end = day + DURATION_DAYS   # stillschweigende Verlaengerung


## Wirkung Buero-IT: Faktor auf Buero- und Internetkosten des Unternehmens (nur bei erbrachter Leistung).
func office_factor(cid: int) -> float:
	for k in contracts.values():
		if int(k.client) == cid and k.product == "buero_it" and k.status == "aktiv" and bool(k.get("ok_today", true)):
			return 1.0 - float(products().buero_it.wirkung)
	return 1.0


## Wirkung Lagerverwaltung: Faktor auf den Verderb eines Betriebs.
func spoil_factor(biz_id: String) -> float:
	for k in contracts.values():
		if k.client_biz == biz_id and k.product == "lagerverwaltung" and k.status == "aktiv" and bool(k.get("ok_today", true)):
			return 1.0 - float(products().lagerverwaltung.wirkung)
	return 1.0


func has_contract(biz_id: String) -> bool:
	return contracts.values().any(func(k): return k.client_biz == biz_id and k.status in ["aktiv", "gestoert"])


func summary_of_provider(b: Dictionary) -> Dictionary:
	return {"vertraege": active_of(b.id).size(), "kapazitaet": capacity_of(b), "computer": sim.stock.qty("computer", "C%d" % int(b.owner), int(b.site))}


func to_dict() -> Dictionary:
	return {"contracts": contracts, "next": _next}


func from_dict(d: Dictionary) -> void:
	contracts = d.get("contracts", {})
	for k in contracts.values():
		for f in ["client", "provider_cid", "start", "end", "disrupted"]:
			k[f] = int(k[f])
	_next = int(d.get("next", 1))
