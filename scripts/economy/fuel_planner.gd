class_name FuelPlanner
extends RefCounted
## Planungshilfe fuer Treibstoff: Tankstellen vergleichen und feste Nachtank-Regeln (Routine der Engine).
##
## Alle Zahlen stammen aus bekannten Daten (Preis, Bestand, belegte Saeulen, Entfernung). Annahmen sind ausgewiesen:
## Umweg = Hin- und Rueckweg ab Hauptdepot, Kosten je Tile aus dem Fahrzeugmodell "Transporter", Wartezeit grob nach freien Saeulen.

const DETOUR_COST_PER_TILE := 0.35     # EUR je Tile (Annahme: Mischung aus Kraftstoff und Zeit)
const WAIT_COST_PER_MIN := 1.2         # EUR je Wartemin (Annahme: Fahrer und Fahrzeug stehen)


## Vergleich aller Tankstellen mit Bestand: guenstigster Gesamtpreis zuerst. Gibt [{id, name, preis, entfernung, wartezeit_min, gesamt, bestand}].
static func compare(sim: Simulation, cid: int, liters: float, origin: Vector2i = Vector2i(-1, -1)) -> Array:
	var c := sim.company(cid)
	var home: Vector2i = sim.city.building(c.depots[0]).road if origin.x < 0 else origin
	var out: Array = []
	for sid in sim.resources.supplies:
		var s: Dictionary = sim.resources.supplies[sid]
		if s.kind != "fuel" or float(s.stock) < liters:
			continue
		var b: Dictionary = sim.city.building(s.building)
		var dist := absi(b.road.x - home.x) + absi(b.road.y - home.y)
		var price: float = sim.resources.fuel_price(s)
		var free := int(s.pumps) - sim.resources.pumps_busy(s)
		var wait := 0.0
		if free <= 0 and not s.busy.is_empty():
			wait = maxf(0.0, float(s.busy.min()) - sim.game_min)
		var total := price * liters + 2.0 * dist * DETOUR_COST_PER_TILE + wait * WAIT_COST_PER_MIN
		out.append({"id": sid, "name": b.name, "preis": price, "entfernung": dist, "wartezeit_min": wait, "gesamt": total, "bestand": int(s.stock)})
	out.sort_custom(func(a, b): return a.gesamt < b.gesamt)
	return out


static func compare_text(sim: Simulation, cid: int, liters: float) -> Dictionary:
	var opts := compare(sim, cid, liters)
	if opts.is_empty():
		return {"ok": false, "msg": "Keine Tankstelle hat %d l vorrätig. Notpreis beim Nachtanken: %.2f EUR/l." % [int(liters), sim.resources.emergency_fuel_price()]}
	var lines: Array = []
	for o in opts.slice(0, 3):
		lines.append("%s (%s): %.2f EUR/l, %d Tiles entfernt, Wartezeit ca. %d min → insgesamt %s für %d l" % [o.id, o.name, o.preis, o.entfernung,
			int(o.wartezeit_min), Catalog.money(o.gesamt), int(liters)])
	var saving: float = (sim.resources.emergency_fuel_price() - float(opts[0].preis)) * liters
	return {"ok": true, "best": opts[0].id, "msg": "Beste Wahl %s. Alternativen: %s. Annahmen: Umweg %.2f EUR/Tile, Warten %.1f EUR/min. Gegenüber dem Notpreis sparst du etwa %s." % [
		opts[0].id, " | ".join(lines), DETOUR_COST_PER_TILE, WAIT_COST_PER_MIN, Catalog.money(saving)]}


## Feste Regel: faellt der eigene Vorrat unter below_l, kauft die Engine buy_l Liter (an der gewaehlten oder guenstigsten Tankstelle).
static func set_rule(sim: Simulation, cid: int, below_l: float, buy_l: float, station: String) -> Dictionary:
	var c := sim.company(cid)
	if not is_finite(below_l) or not is_finite(buy_l):
		return {"ok": false, "msg": "Tankregel braucht endliche Mengen."}
	if below_l <= 0.0 or buy_l <= 0.0:
		c.fuel_rule = {}
		return {"ok": true, "msg": "Feste Nachtank-Regel gelöscht."}
	if not is_finite(below_l) or not is_finite(buy_l) or buy_l > c.fuel_cap or below_l > c.fuel_cap:
		return {"ok": false, "msg": "Tank fasst nur %d l." % int(c.fuel_cap)}
	if station != "" and (not sim.resources.supplies.has(station) or sim.resources.supplies[station].kind != "fuel"):
		return {"ok": false, "msg": "Unbekannte Tankstelle %s." % station}
	c.fuel_rule = {"below": below_l, "buy": buy_l, "station": station}
	return {"ok": true, "msg": "Regel gespeichert: unter %d l bestellt die Engine %d l als Tankwagenlieferung%s." % [int(below_l), int(buy_l),
		(" bei " + station) if station != "" else " an der günstigsten Tankstelle"]}


## Alle 30 Spielminuten: Regeln ausfuehren (Routine, keine KI-Anfrage noetig).
static func run_rules(sim: Simulation) -> void:
	for c in sim.companies:
		if c.fuel_rule.is_empty() or not c.is_active() or c.fuel + sim.resources.pending_fuel(c.id) >= float(c.fuel_rule.below):
			continue
		var want := minf(float(c.fuel_rule.buy), c.fuel_cap - c.fuel - sim.resources.pending_fuel(c.id))
		if want < 50.0:
			continue
		var sid: String = str(c.fuel_rule.station)
		if sid == "" or not sim.resources.supplies.has(sid) or float(sim.resources.supplies[sid].stock) < want:
			var opts := compare(sim, c.id, want)
			if opts.is_empty():
				continue
			sid = opts[0].id
		var r: Dictionary = sim.resources.buy_supplies(c.id, sid, want)
		if r.ok:
			sim.log_event("%s bestellt automatisch Treibstoff: %s" % [c.company_name, r.msg], "info", c.id)
