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
const CAPACITY := 240              # Ladeeinheiten je Schiff und Richtung auf Stufe 1 (Holzanleger)
## Hafenstufen (Etappe E): Ausbau als Stadtprojekt des Buergermeisters (Baufirma, Material aus dem Stadtlager), danach mehr Ladung je Schiff.
const STAGES := [
	{"name": "Holzanleger", "ladung": 240},
	{"name": "Kaimauer mit Kran", "ladung": 400, "kosten": 60000.0, "tage": 14, "material": {"betonfertigteil": 40, "schotter": 30, "verbindung": 12}},
	{"name": "Containerhafen", "ladung": 600, "kosten": 140000.0, "tage": 22, "material": {"betonfertigteil": 90, "schotter": 60, "verbindung": 30}},
]
const SHIP_NAMES := ["Möwe", "Nordstern", "Seeadler", "Bernstein", "Wellenreiter", "Abendrot", "Kormoran", "Lotte"]

var sim
var enabled := false
var building := -1                 # Hafenlager (Anlieferpunkt fuer Importware, Verladestelle fuer Ausfuhren)
var manifest: Array = []           # wartende Einfuhren {kind, ref, item, qty, since}
var export_wait := {}              # Artikel -> Menge am Kai fuer das naechste Schiff
var ship := {}                     # aktuelles bzw. letztes Schiff {id, name, day, status, gelöscht, geladen}
var stats := {"schiffe": 0, "einheiten_ein": 0, "einheiten_aus": 0, "zurueckgestellt": 0}
var _next := 1
var stage := 1                     # Hafenstufe (1..STAGES.size())


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
## Waren des Stadtlagers (CityGoods) nach Mengeneinheit: ein Tankcontainer fasst 1000 l, ein Rohr-/Kabelbund 100 m usw.
const CITY_UNIT_LOAD := {"l": 1000, "m": 100, "m²": 50, "t": 10, "Pack": 50, "Eimer": 40, "Stk": 10}
static func units_of(item: String, qty: int) -> int:
	var per := int(Production.art(item).get("je_ladeeinheit", 1))
	if Production.art(item).is_empty() and CityGoods.exists(item):
		per = int(CITY_UNIT_LOAD.get(str(CityGoods.get_item(item).get("unit", "")), 1))
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
	# Loeschen, in zwei Wegen: zuerst alle Posten, die ganz in die Ladung passen (in Reihenfolge des
	# Eingangs), danach wird der Restplatz mit den uebergroessen Posten anteilig gefuellt. Ein einzelner
	# uebergrosser Posten darf kleinere nicht verdraengen, und ein Posten, der eine Ladung ueberragt, wird
	# auf JEDEM Schiff anteilig geloest (z. B. 560m Rohr fuer eine Erschliessung bei 240 Ladeeinheiten).
	var room := capacity()
	var rest: Array = []
	for m in manifest:
		if units_of(str(m.item), int(m.qty)) <= room:
			room -= units_of(str(m.item), int(m.qty))
			_unload(m)
			ship.geloescht[m.item] = int(ship.geloescht.get(m.item, 0)) + int(m.qty)
			stats.einheiten_ein = int(stats.einheiten_ein) + units_of(str(m.item), int(m.qty))
		else:
			rest.append(m)
	for m in rest.duplicate():
		if room <= 0:
			break
		var qty := int(m.qty)
		var u := units_of(str(m.item), qty)
		if u <= room:
			room -= u
			_unload(m)
			ship.geloescht[m.item] = int(ship.geloescht.get(m.item, 0)) + qty
			stats.einheiten_ein = int(stats.einheiten_ein) + u
			rest.erase(m)
			continue
		var fit := int(float(qty) * float(room) / float(u))
		if fit <= 0:
			continue
		room -= units_of(str(m.item), fit)
		_unload(m, fit)
		ship.geloescht[m.item] = int(ship.geloescht.get(m.item, 0)) + fit
		stats.einheiten_ein = int(stats.einheiten_ein) + units_of(str(m.item), fit)
		m.qty = qty - fit
	stats.zurueckgestellt = int(stats.zurueckgestellt) + rest.size()
	manifest = rest
	# Laden: Ausfuhrware vom Kai, bis das Schiff voll ist
	room = capacity()
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


## Ware ins Ziel uebergeben. `fit` ist die tatsaechlich geloeste (anteilige) Menge; der Rest bleibt im Manifest.
func _unload(m: Dictionary, fit: int = -1) -> void:
	var qty := int(m.qty) if fit <= 0 else fit
	# Bestellungen von Stadtlager und Bauhof gelten erst mit dem letzten Teil als angekommen (on_ship uebernimmt die ganze Bestellung)
	var complete := qty >= int(m.qty)
	match str(m.kind):
		"depot":
			if complete:
				sim.city_depot.on_ship(str(m.ref))
		"trader":
			if complete:
				sim.trader.on_ship(str(m.ref))
		_:
			sim.stock.add(str(m.item), qty, Production.IMPORT, building, "Schiff %s" % ship.id, sim.game_min)


func _list(d: Dictionary) -> String:
	if d.is_empty():
		return "nichts"
	var parts: Array = []
	for k in d:
		parts.append("%d × %s" % [int(d[k]), Production.item_name(str(k)) if not Production.art(str(k)).is_empty() else str(k)])
	return ", ".join(parts)


func capacity() -> int:
	return int(STAGES[clampi(stage, 1, STAGES.size()) - 1].ladung)


func stage_name() -> String:
	return str(STAGES[clampi(stage, 1, STAGES.size()) - 1].name)


func expansion_running() -> bool:
	return sim.mayor.projects.values().any(func(p): return p.kind == "hafenausbau" and p.status != "fertig")


## Naechste Hafenstufe als Stadtprojekt ausschreiben (Kosten reserviert die Stadtkasse, eine Baufirma baut mit Material aus dem Stadtlager).
func expand(by: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "msg": "Kein Hafen in dieser Stadt."}
	if stage >= STAGES.size():
		return {"ok": false, "msg": "Der Hafen ist schon %s (höchste Stufe)." % stage_name()}
	if expansion_running():
		return {"ok": false, "msg": "Ein Hafenausbau läuft bereits."}
	var nd: Dictionary = STAGES[stage]
	if sim.mayor.available_budget() < float(nd.kosten):
		return {"ok": false, "msg": "Verfügbare Stadtkasse reicht nicht (%s nötig)." % Catalog.money(float(nd.kosten))}
	var prj: Dictionary = sim.mayor.add_works_project("hafenausbau", "S%d" % (stage + 1), float(nd.kosten), int(nd.tage), nd.material, "Hafenausbau (%s)" % by)
	sim.log_event("%s lässt den Hafen ausbauen: %s → %s (%d statt %d Ladeeinheiten je Schiff), ausgeschrieben als %s (%s)." % [by, stage_name(), nd.name, int(nd.ladung), capacity(), prj.id, Catalog.money(float(nd.kosten))], "info")
	sim.activity.add("stadt", -1, "bau", "Hafenausbau zu %s ausgeschrieben" % nd.name, by, sim.city.building(building).road)
	return {"ok": true, "msg": "Hafenausbau zu %s als Projekt %s ausgeschrieben (etwa %d Tage)." % [nd.name, prj.id, int(nd.tage)], "ref": prj.id}


## Vom Bausystem bei Fertigstellung des Projekts aufgerufen.
func finish_expansion() -> void:
	stage = mini(stage + 1, STAGES.size())
	sim.log_event("Hafen ausgebaut: jetzt %s, %d Ladeeinheiten je Schiff." % [stage_name(), capacity()], "good")


## Rueckstau der Einfuhren in Schiffsladungen (fuer Buergermeister und Ansicht).
func backlog_ships() -> float:
	return snappedf(float(waiting_units()) / float(capacity()), 0.1)


func summary() -> Dictionary:
	var nd: Dictionary = STAGES[stage] if stage < STAGES.size() else {}
	return {"stufe": stage, "stufe_name": stage_name(), "ladung_je_schiff": capacity(), "rueckstau_schiffsladungen": backlog_ships(), "ausbau_laeuft": expansion_running(),
		"ausbau": {} if nd.is_empty() else {"ziel": nd.name, "ladung": int(nd.ladung), "kosten": int(nd.kosten), "tage": int(nd.tage)},
		"aktiv": enabled, "schiff": ship.duplicate(true), "naechstes_in_tagen": INTERVAL_DAYS - GameCalendar.day_of(sim.game_min) % INTERVAL_DAYS,
		"wartende_einfuhren": manifest.size(), "wartende_einheiten": waiting_units(), "ausfuhr_am_kai": export_wait.duplicate(), "statistik": stats.duplicate()}


func to_dict() -> Dictionary:
	return {"stage": stage, "manifest": manifest.duplicate(true), "export_wait": export_wait.duplicate(), "ship": ship.duplicate(true), "stats": stats.duplicate(), "next": _next}


func from_dict(d: Dictionary) -> void:
	stage = int(d.get("stage", 1))
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
