class_name RealEstate
extends RefCounted
## Immobilienbetrieb der Unternehmer (Auftrag 14, Etappe 3): Wohngebaeude vom privaten Vermietersektor (V0) kaufen und vermieten.
##
## Kauf: alle Wohnungen des Vermietersektors in einem Gebaeude (die uebrigen gehoeren meist Buergern) zum Preis von PRICE_MONTHS Monatsmieten; der Erloes geht an die privaten
## Eigentuemer (Haushaltssektor H0). Buchwert: 30 % Grund (keine Abschreibung), 70 % Gebaeude (Abschreibung je Monat).
## Miete: Die Einheiten gehoeren danach "C<n>"; Mieter zahlen nach den bestehenden Mietregeln (Housing) genau einmal an die Firma
## (Kostenstelle des Immobilienbetriebs). Je Monat Instandhaltung und Grundsteuer auf die Sollmiete, auch bei Leerstand.
## Verkauf: zurueck an den Vermietersektor zum aktuellen Wert x SELL_FACTOR; Differenz zum Buchwert ist Ergebnis aus Anlagenabgang.

const PRICE_MONTHS := 144.0         # 12 Jahresmieten
const LAND_SHARE := 0.3
const DEPRECIATION_MONTH := 0.004   # Gebaeudeanteil, rund 5 % im Jahr
const MAINTENANCE := 0.20           # Anteil der Sollmiete je Monat (an S0)
const PROPERTY_TAX := 0.10          # Anteil der Sollmiete je Monat (an P0)
const SELL_FACTOR := 0.95

var sim


func setup(simulation) -> void:
	sim = simulation
	sim.month_changed.connect(on_month)


## Wohnungen eines Gebaeudes (optional nur eines Eigentuemers).
func units_of(building: int, owner: String = "") -> Array:
	return sim.housing.units.values().filter(func(u): return int(u.building) == building and (owner == "" or str(u.owner) == owner))


func _occupied(units: Array) -> int:
	var occ: Dictionary = sim.housing._citizen_occupants()
	return units.filter(func(u): return str(u.tenant) != "" or occ.has(u.id)).size()


func rent_month(units: Array) -> float:
	var r := 0.0
	for u in units:
		r += float(u.rent)
	return r


func value_of(units: Array) -> float:
	return roundf(rent_month(units) * PRICE_MONTHS)


## Kaeufliche Gebaeude: alle Einheiten gehoeren dem Vermietersektor. Fuer die KI knapp: Gebaeude, Einheiten, belegt, Miete, Preis.
func offers(limit: int = 3) -> Array:
	var by := {}
	for u in sim.housing.units.values():
		by[int(u.building)] = true
	var out: Array = []
	for bid in by:
		var us := units_of(int(bid), Housing.LANDLORD)
		if us.is_empty():
			continue
		out.append({"gebaeude": int(bid), "einheiten": us.size(), "belegt": _occupied(us), "miete_monat": int(rent_month(us)), "preis": int(value_of(us))})
	out.sort_custom(func(a, b): return float(a.belegt) / float(a.einheiten) > float(b.belegt) / float(b.einheiten) or (float(a.belegt) / float(a.einheiten) == float(b.belegt) / float(b.einheiten) and a.preis < b.preis))
	return out.slice(0, limit)


## Immobilienbetrieb der Company (wird beim ersten Kauf am Hauptsitz eroeffnet; nie Standard-Kostenstelle).
func business_of(cid: int, create: bool) -> Dictionary:
	var b: Dictionary = sim.biz.find(cid, "immobilien")
	if b.is_empty() and create:
		var c = sim.company(cid)
		b = sim.biz.create(cid, "immobilien", int(c.depots[0]) if not c.depots.is_empty() else -1, "", "aktiv")
		b["props"] = {}
		sim.biz.note(b.id, "Immobilienbetrieb eröffnet", "Unternehmer")
	if not b.is_empty() and not b.has("props"):
		b["props"] = {}
	return b


func cc_of(cid: int) -> String:
	return str(business_of(cid, false).get("id", ""))


func buy(cid: int, building: int, reason: String = "") -> Dictionary:
	var us := units_of(building, Housing.LANDLORD)
	if us.is_empty():
		return {"ok": false, "msg": "In Gebäude %d stehen keine Wohnungen des Vermietermarkts zum Verkauf." % building}
	if business_of(cid, false).get("props", {}).has(str(building)):
		return {"ok": false, "msg": "Du besitzt in Gebäude %d bereits Wohnungen." % building}
	var price := value_of(us)
	var c = sim.company(cid)
	if c.ledger.cash < price:
		return {"ok": false, "msg": "Kaufpreis %s, Bargeld reicht nicht (Kredit möglich: take_loan)." % Catalog.money(price)}
	var b := business_of(cid, true)
	c.ledger.invest(price, "H0")   # Erloes an die privaten Eigentuemer
	var land := price * LAND_SHARE
	c.land_book += land
	c.property_book += price - land
	b.props[str(building)] = {"price": price, "land": land, "book": price - land, "day": GameCalendar.day_of(sim.game_min)}
	for u in us:
		u.owner = "C%d" % cid
	var occ := _occupied(us)
	sim.biz.note(b.id, "Gekauft: Gebäude %d (%d Wohnungen, %d belegt) für %s%s" % [building, us.size(), occ, Catalog.money(price), (" – " + reason) if reason != "" else ""], "Unternehmer")
	sim.log_event("%s kauft das Wohngebäude %d (%d Wohnungen) für %s." % [c.company_name, building, us.size(), Catalog.money(price)], "info", cid)
	return {"ok": true, "msg": "Gebäude %d gekauft (%d Wohnungen, %d belegt, Sollmiete %s/Monat)." % [building, us.size(), occ, Catalog.money(rent_month(us))], "ref": b.id}


func sell(cid: int, building: int) -> Dictionary:
	var b := business_of(cid, false)
	if b.is_empty() or not b.props.has(str(building)):
		return {"ok": false, "msg": "Gebäude %d gehört dir nicht." % building}
	var c = sim.company(cid)
	var p: Dictionary = b.props[str(building)]
	var own := units_of(building, "C%d" % cid)
	var proceeds := roundf(value_of(own) * SELL_FACTOR)
	var book := float(p.land) + float(p.book)
	c.ledger.divest(proceeds, "H0")
	c.land_book = maxf(0.0, c.land_book - float(p.land))
	c.property_book = maxf(0.0, c.property_book - float(p.book))
	c.ledger.book("asset_result", proceeds - book, false, "Verkauf Gebäude %d" % building, sim.game_min, "", b.id)
	for u in own:
		u.owner = Housing.LANDLORD
	b.props.erase(str(building))
	sim.biz.note(b.id, "Verkauft: Gebäude %d für %s (Buchwert %s)" % [building, Catalog.money(proceeds), Catalog.money(book)], "Unternehmer")
	return {"ok": true, "msg": "Gebäude %d verkauft für %s." % [building, Catalog.money(proceeds)]}


## Monat: Instandhaltung und Grundsteuer auf die Sollmiete (auch leerstehender Wohnungen), Abschreibung des Gebaeudeanteils.
func on_month(_m: int) -> void:
	for b in sim.biz.items.values():
		if b.branch != "immobilien" or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		var c = sim.company(int(b.owner))
		for key in b.get("props", {}):
			var p: Dictionary = b.props[key]
			var rent := rent_month(units_of(int(key), "C%d" % int(b.owner)))
			c.ledger.book("property_costs", -rent * MAINTENANCE, true, "Instandhaltung Gebäude %s" % key, sim.game_min, "S0", b.id)
			c.ledger.book("property_costs", -rent * PROPERTY_TAX, true, "Grundsteuer Gebäude %s" % key, sim.game_min, "P0", b.id)
			var dep := minf(float(p.price) * (1.0 - LAND_SHARE) * DEPRECIATION_MONTH, float(p.book))
			p.book = float(p.book) - dep
			c.property_book = maxf(0.0, c.property_book - dep)
			c.ledger.book("depreciation", -dep, false, "Abschreibung Gebäude %s" % key, sim.game_min, "", b.id)


## Kurzuebersicht je Gebaeude fuer Ansicht und Beobachtung.
func detail(b: Dictionary) -> Dictionary:
	var out := {}
	for key in b.get("props", {}):
		var us := units_of(int(key), "C%d" % int(b.owner))
		out[key] = {"einheiten": us.size(), "belegt": _occupied(us), "miete_monat": int(rent_month(us)), "buchwert": int(float(b.props[key].land) + float(b.props[key].book))}
	return {"gebaeude": out}
