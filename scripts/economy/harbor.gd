class_name Harbor
extends RefCounted
## Hafen als Tor der Aussenwirtschaft (Auftrag 15, Etappe C; nur im Kuestenort). Ein Linienschiff legt alle INTERVAL_DAYS Tage an,
## loescht die wartenden Einfuhren ins Hafenlager und laedt die am Kai liegende Ausfuhrware. Je Schiff passen hoechstens CAPACITY
## Ladeeinheiten in jede Richtung; was nicht passt, wartet auf das naechste Schiff.
## Einfuhren: Stadtlager-Bestellungen (kind "depot"), Bauhof-Nachschub (kind "trader") und Importware fuer Betriebe (kind "stock",
## liegt danach als Auslandsware X0 im Hafenlager und wird von dort gekauft). Ausfuhren: an das Ausland verkaufte Ware wird zum
## Hafenlager gefahren, bleibt dort X0-Bestand und verlaesst die Stadt erst mit dem Schiff.

signal ship_event(kind: String, ship: Dictionary)   # "ankunft" | "abfahrt" (Darstellung)

const INTERVAL_DAYS := 2
const CAPACITY := 240
const SHIP_NAMES := ["Möwe", "Nordstern", "Seeadler", "Bernstein", "Wellenreiter", "Abendrot", "Kormoran", "Lotte"]

var sim
var enabled := false
var building := -1                 # Hafenlager (Anlieferpunkt fuer Importware, Verladestelle fuer Ausfuhren)
var manifest: Array = []           # wartende Einfuhren {kind, ref, item, qty, since}
var export_wait := {}              # Artikel -> Menge am Kai fuer das naechste Schiff
var ship := {}                     # aktuelles bzw. letztes Schiff {id, name, day, status, gelöscht, geladen}
var stats := {"schiffe": 0, "einheiten_ein": 0, "einheiten_aus": 0, "zurueckgestellt": 0}
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	enabled = sim.city.world == "kueste"
	if not enabled:
		return
	for b in sim.city.buildings:
		if b.type == "warehouse" and str(b.name) == "Hafenlager":
			building = int(b.id)
	if building < 0:
		for b in sim.city.buildings:
			if b.type == "port_office":
				building = int(b.id)
	enabled = building >= 0
	sim.day_changed.connect(on_day)


## Ladeeinheiten einer Menge (Artikel der Produktion haben eigene Ladeeinheiten, sonst je Stueck).
static func units_of(item: String, qty: int) -> int:
	var per := int(Production.art(item).get("je_ladeeinheit", 1))
	return maxi(1, ceili(float(qty) / float(maxi(1, per))))


## Einfuhr fuer das naechste Schiff vormerken.
func ship_in(kind: String, ref: String, item: String, qty: int) -> void:
	manifest.append({"kind": kind, "ref": ref, "item": item, "qty": qty, "since": GameCalendar.day_of(sim.game_min)})


## Importware, die im Hafenlager frei verkaeuflich liegt (ohne Reservierungen und ohne wartende Ausfuhren).
func available(item: String) -> int:
	return maxi(0, sim.stock.available(item, Production.IMPORT, building) - int(export_wait.get(item, 0)))


## Betriebe fragen Importware nach, die nicht im Hafenlager liegt: das naechste Schiff bringt die Fehlmenge mit.
func demand(item: String, qty: int) -> void:
	var pending := 0
	for m in manifest:
		if m.kind == "stock" and m.item == item:
			pending += int(m.qty)
	if qty > pending:
		ship_in("stock", "", item, qty - pending)


## Ausfuhrware ist am Kai angekommen (X0-Bestand im Hafenlager) und wartet auf das Schiff.
func export_ready(item: String, qty: int) -> void:
	export_wait[item] = int(export_wait.get(item, 0)) + qty


func waiting_units() -> int:
	var u := 0
	for m in manifest:
		u += units_of(str(m.item), int(m.qty))
	return u


func on_day(day: int) -> void:
	if not ship.is_empty() and ship.status == "am_kai" and day > int(ship.day):
		ship.status = "abgefahren"
		ship_event.emit("abfahrt", ship)
	if day % INTERVAL_DAYS == 0:
		_arrive(day)


func _arrive(day: int) -> void:
	ship = {"id": "SH%d" % _next, "name": SHIP_NAMES[(_next - 1) % SHIP_NAMES.size()], "day": day, "status": "am_kai", "geloescht": {}, "geladen": {}}
	_next += 1
	stats.schiffe = int(stats.schiffe) + 1
	# Loeschen: wartende Einfuhren in Reihenfolge des Eingangs, bis das Schiff voll ist
	var room := CAPACITY
	var rest: Array = []
	for m in manifest:
		var u := units_of(str(m.item), int(m.qty))
		if u > room:
			rest.append(m)
			continue
		room -= u
		_unload(m)
		ship.geloescht[m.item] = int(ship.geloescht.get(m.item, 0)) + int(m.qty)
		stats.einheiten_ein = int(stats.einheiten_ein) + u
	stats.zurueckgestellt = int(stats.zurueckgestellt) + rest.size()
	manifest = rest
	# Laden: Ausfuhrware vom Kai, bis das Schiff voll ist
	room = CAPACITY
	for item in export_wait.keys():
		var q := int(export_wait[item])
		var fit := q if units_of(item, q) <= room else q * room / units_of(item, q)   # anteilig, was noch passt
		if fit <= 0 or room <= 0:
			continue
		var gone: int = sim.stock.consume(item, fit, Production.IMPORT, building, "Ausfuhr per Schiff %s" % ship.id, sim.game_min)
		room -= units_of(item, gone)
		export_wait[item] = q - gone
		if int(export_wait[item]) <= 0:
			export_wait.erase(item)
		ship.geladen[item] = int(ship.geladen.get(item, 0)) + gone
		stats.einheiten_aus = int(stats.einheiten_aus) + units_of(item, gone)
	var msg := "Schiff „%s“ im Hafen: %s gelöscht, %s geladen%s." % [ship.name, _list(ship.geloescht), _list(ship.geladen),
		"; %d Posten warten auf das nächste Schiff" % rest.size() if not rest.is_empty() else ""]
	sim.log_event(msg, "info")
	sim.activity.add("stadt", -1, "sonstiges", "Schiff %s am Kai" % ship.name, msg, sim.city.building(building).road)
	ship_event.emit("ankunft", ship)


func _unload(m: Dictionary) -> void:
	match str(m.kind):
		"depot":
			sim.city_depot.on_ship(str(m.ref))
		"trader":
			sim.trader.on_ship(str(m.ref))
		_:
			sim.stock.add(str(m.item), int(m.qty), Production.IMPORT, building, "Schiff %s" % ship.id, sim.game_min)


func _list(d: Dictionary) -> String:
	if d.is_empty():
		return "nichts"
	var parts: Array = []
	for k in d:
		parts.append("%d × %s" % [int(d[k]), Production.item_name(str(k)) if not Production.art(str(k)).is_empty() else str(k)])
	return ", ".join(parts)


func summary() -> Dictionary:
	return {"aktiv": enabled, "schiff": ship.duplicate(true), "naechstes_in_tagen": INTERVAL_DAYS - GameCalendar.day_of(sim.game_min) % INTERVAL_DAYS,
		"wartende_einfuhren": manifest.size(), "wartende_einheiten": waiting_units(), "ausfuhr_am_kai": export_wait.duplicate(), "statistik": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"manifest": manifest.duplicate(true), "export_wait": export_wait.duplicate(), "ship": ship.duplicate(true), "stats": stats.duplicate(), "next": _next}


func from_dict(d: Dictionary) -> void:
	manifest = d.get("manifest", []).duplicate(true)
	for m in manifest:
		m.qty = int(m.qty)
	export_wait = {}
	for k in d.get("export_wait", {}):
		export_wait[k] = int(d.export_wait[k])
	ship = d.get("ship", {}).duplicate(true)
	if ship.has("day"):
		ship.day = int(ship.day)
	stats = d.get("stats", stats).duplicate()
	_next = int(d.get("next", 1))
