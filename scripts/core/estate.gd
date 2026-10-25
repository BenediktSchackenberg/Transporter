class_name Estate
extends RefCounted
## Firmengrundstuecke und Betriebseinrichtungen.
## Jede Firma startet mit einem gleich grossen, leeren Grundstueck (Zufahrt, offene Stellflaeche fuer 2 Fahrzeuge).
## Einrichtungen werden auf dem Grundstueck platziert (Position, Drehung), gebaut (Geld, Material, Arbeitskraft, Zeit)
## und veraendern echte Kapazitaeten: Stellplaetze, Laderampen, Lager, Werkstattplaetze, Tank, Erholung, Sicherheit,
## Auftragskapazitaet (Buero/Disposition) und vermietbare Bueroeinheiten.
## Buchhaltung: Bau = Investition (Abschreibung 1 %/Tag), Grundstueckskauf = Grund und Boden (keine Abschreibung),
## Rueckbau schreibt den Restbuchwert ab, Betriebskosten und Mieteinnahmen sind erfolgswirksam.

const FACILITIES := {
	"buero": {"name": "Unternehmerbüro", "w": 2, "h": 2, "cost": 4000.0, "build": 120.0, "mat": 6, "upkeep": 60.0, "max_level": 4,
		"upgrade": [0.0, 5000.0, 9000.0, 14000.0], "drive": false, "nutzen": "Firmensitz; Stufe = Auftragskapazität +3 je Stufe; Stufe 4: 2 vermietbare Einheiten"},
	"disposition": {"name": "Disposition", "w": 2, "h": 2, "cost": 3500.0, "build": 90.0, "mat": 4, "upkeep": 40.0, "max_level": 1,
		"drive": false, "nutzen": "+2 Auftragskapazität, Vorarbeiter-Reichweite +4"},
	"stellplatz": {"name": "Lkw-Stellplätze", "w": 2, "h": 2, "cost": 900.0, "build": 30.0, "mat": 2, "upkeep": 5.0, "max_level": 1,
		"drive": true, "nutzen": "2 Stellplätze"},
	"garage": {"name": "Fahrzeughalle", "w": 2, "h": 2, "cost": 3500.0, "build": 90.0, "mat": 5, "upkeep": 25.0, "max_level": 1,
		"drive": true, "nutzen": "2 geschützte Stellplätze (Sabotage-Entdeckung +30 %)"},
	"werkstatt": {"name": "Werkstatt", "w": 3, "h": 2, "cost": 6000.0, "build": 150.0, "mat": 8, "upkeep": 50.0, "max_level": 2,
		"upgrade": [0.0, 0.0, 4500.0], "drive": true, "nutzen": "Reparaturplatz je Stufe; Mechaniker arbeiten hier doppelt so schnell"},
	"laderampe": {"name": "Laderampe", "w": 2, "h": 1, "cost": 2500.0, "build": 60.0, "mat": 3, "upkeep": 15.0, "max_level": 2,
		"upgrade": [0.0, 0.0, 2000.0], "drive": true, "nutzen": "Ladeplatz je Stufe am eigenen Lager, Ladezeit ×0,6"},
	"lager": {"name": "Lagerhalle", "w": 3, "h": 3, "cost": 7000.0, "build": 180.0, "mat": 10, "upkeep": 45.0, "max_level": 1,
		"drive": false, "nutzen": "+60 Lagerplätze"},
	"kuehllager": {"name": "Kühllager", "w": 3, "h": 2, "cost": 9000.0, "build": 180.0, "mat": 8, "upkeep": 120.0, "max_level": 1,
		"drive": false, "nutzen": "+25 gekühlte Lagerplätze (nötig für Kühlware)"},
	"tankstelle": {"name": "Betriebstankstelle", "w": 2, "h": 2, "cost": 5000.0, "build": 120.0, "mat": 5, "upkeep": 30.0, "max_level": 1,
		"drive": true, "nutzen": "+3000 l Tank für günstig eingekauften Treibstoff"},
	"ladepunkt": {"name": "Ladepunkte", "w": 1, "h": 2, "cost": 1500.0, "build": 40.0, "mat": 1, "upkeep": 5.0, "max_level": 1,
		"drive": true, "nutzen": "Vorbereitung für Elektrofahrzeuge (derzeit ohne E-Fahrzeuge keine Wirkung)"},
	"pausenraum": {"name": "Personal- und Pausenräume", "w": 2, "h": 2, "cost": 2500.0, "build": 60.0, "mat": 3, "upkeep": 20.0, "max_level": 1,
		"drive": false, "nutzen": "Arbeiter erholen sich auf dem Hof doppelt so schnell"},
	"schulung": {"name": "Schulungsraum", "w": 2, "h": 2, "cost": 3000.0, "build": 60.0, "mat": 3, "upkeep": 20.0, "max_level": 1,
		"drive": false, "nutzen": "Weiterbildung (train_worker): Fähigkeit +1"},
	"sicherheit": {"name": "Sicherheitsanlage (Licht, Zaun, Tor)", "w": 1, "h": 1, "cost": 1200.0, "build": 30.0, "mat": 1, "upkeep": 10.0,
		"max_level": 1, "drive": false, "nutzen": "Sabotage-Entdeckung auf dem Hof +15 % je Anlage (max. 2)"},
	"waschplatz": {"name": "Waschplatz", "w": 2, "h": 2, "cost": 2000.0, "build": 45.0, "mat": 2, "upkeep": 15.0, "max_level": 1,
		"drive": true, "nutzen": "Wäsche (wash_vehicle): +5 % Vergütung bei Büros, Restaurants, Villen, Hotels für 1 Tag"},
	"mietbuero": {"name": "Vermietbare Büroflächen", "w": 3, "h": 2, "cost": 8000.0, "build": 180.0, "mat": 8, "upkeep": 40.0,
		"max_level": 2, "upgrade": [0.0, 0.0, 6000.0], "drive": false, "nutzen": "2 vermietbare Einheiten je Stufe"},
}
const EXTERNAL_SURCHARGE := 0.4      # Baufirma: +40 % Kosten, Material wird geliefert
const OPEN_SLOTS := 2                # offene Stellflaeche des leeren Startgrundstuecks
const OPEN_STORAGE := 20             # offene Lagerflaeche
const LAND_PRICE_PER_TILE := 120.0
const LAND_RENT_PER_TILE := 2.5      # pro Spieltag
const REF_RENT := 70.0               # Vergleichsmiete je Bueroeinheit und Tag (Innenstadt)

var sim
var plots := {}          # Grundstuecks-ID (= Gebaeude-ID der Flaeche) -> Grundstueck
var facilities := {}     # "B<n>" -> Einrichtung
var listings := {}       # Einrichtungs-ID -> {einheiten, miete, mindest_tage}
var tenants := {}        # "M<n>" -> Mietinteressent
var leases := {}         # "L<n>" -> Mietvertrag
var next_id := 1
var _cache := {}         # Grundstueck -> Bauvorschlaege


func setup(simulation) -> void:
	sim = simulation
	for b in sim.city.buildings:
		if b.role == "plot":
			plots[b.id] = {"id": b.id, "owner": -1, "mode": "", "rent": 0.0, "price": LAND_PRICE_PER_TILE * b.w * b.h,
				"parent": int(b.get("parent", -1)), "x": b.x, "y": b.y, "w": b.w, "h": b.h,
				"entrance": [b.entrance.x, b.entrance.y] if b.has("entrance") else [b.x, b.y + b.h - 1]}


func is_plot(site: int) -> bool:
	return plots.has(site)


func plot_of(cid: int) -> Array:
	return plots.values().filter(func(p): return p.owner == cid)


## Startgrundstueck vergeben (kostenlos, fuer alle gleich).
func grant_start(cid: int, site: int) -> void:
	plots[site].owner = cid
	plots[site].mode = "start"
	_refresh_company(cid)


# ------------------------------------------------------------------ Kapazitaeten
func done(cid: int, typ: String) -> Array:
	return facilities.values().filter(func(f): return f.owner == cid and f.typ == typ and f.status == "fertig")


func count(cid: int, typ: String) -> int:
	var n := 0
	for f in done(cid, typ):
		n += int(f.level)
	return n


func _refresh_company(cid: int) -> void:
	var c: Company = sim.company(cid)
	c.parking_slots = OPEN_SLOTS * plot_of(cid).filter(func(p): return p.mode == "start").size() \
		+ 2 * done(cid, "stellplatz").size() + 2 * done(cid, "garage").size()
	var hq := 0
	for f in done(cid, "buero"):
		hq = maxi(hq, int(f.level))
	c.plot_office_level = hq
	c.dispositions = done(cid, "disposition").size()
	c.fuel_cap = 1000.0 + 3000.0 * done(cid, "tankstelle").size()
	c.plot_count = plot_of(cid).filter(func(p): return int(p.parent) < 0).size()
	_cache.clear()


func storage_cap(site: int, cold: bool = false) -> int:
	var owner: int = plots[site].owner
	var fs: Array = facilities.values().filter(func(f): return f.plot == _root(site) and f.status == "fertig")
	if cold:
		return 25 * fs.filter(func(f): return f.typ == "kuehllager").size()
	return OPEN_STORAGE + 60 * fs.filter(func(f): return f.typ == "lager").size() + 25 * fs.filter(func(f): return f.typ == "kuehllager").size()


func _root(site: int) -> int:
	var p: Dictionary = plots.get(site, {})
	return int(p.parent) if int(p.get("parent", -1)) >= 0 and plots[int(p.parent)].owner == p.owner else site


func loading_bays(site: int) -> int:
	var n := 0
	for f in facilities.values():
		if f.plot == _root(site) and f.typ == "laderampe" and f.status == "fertig":
			n += int(f.level)
	return maxi(1, n)   # ohne Rampe: eine offene Ladeflaeche


## Ueberdachte Ladeplaetze: Rampe, Lagerhalle, Kuehllager oder Fahrzeughalle auf dem eigenen Hof (fertig gebaut).
func is_covered(site: int) -> bool:
	return facilities.values().any(func(f): return f.plot == _root(site) and f.typ in ["laderampe", "lager", "kuehllager", "garage"] and f.status == "fertig")


func has_ramp(site: int) -> bool:
	return facilities.values().any(func(f): return f.plot == _root(site) and f.typ == "laderampe" and f.status == "fertig")


func workshop_bays(cid: int) -> int:
	return count(cid, "werkstatt")


func on_plot(cid: int, pos: Vector2) -> int:
	var t := CityData.to_tile(pos)
	for p in plot_of(cid):
		if t.x >= p.x - 2 and t.x <= p.x + p.w + 1 and t.y >= p.y - 2 and t.y <= p.y + p.h + 1:   # inkl. Zufahrt/Gehweg
			return p.id
	return -1


func recovery_factor(w: Worker) -> float:
	return 2.0 if w.employer >= 0 and on_plot(w.employer, w.pos) >= 0 and done(w.employer, "pausenraum").size() > 0 else 1.0


func security_bonus(v: FleetVehicle) -> float:
	if on_plot(v.owner, v.pos) < 0:
		return 0.0
	var bonus := 0.15 * mini(2, done(v.owner, "sicherheit").size())
	if v.state == "idle" and done(v.owner, "garage").size() > 0:
		bonus += 0.3
	return bonus


# ------------------------------------------------------------------ Platzierung
func _cells(f: Dictionary) -> Array:
	var out: Array = []
	for y in int(f.h):
		for x in int(f.w):
			out.append(Vector2i(int(f.x) + x, int(f.y) + y))
	return out


## Zelle vor der Einrichtung (Zufahrt): unten bei Drehung 0, rechts bei Drehung 90.
func front_cell(f: Dictionary) -> Vector2i:
	if int(f.rot) == 90:
		return Vector2i(int(f.x) + int(f.w), int(f.y) + int(f.h) / 2)
	return Vector2i(int(f.x) + int(f.w) / 2, int(f.y) + int(f.h))


func _plot_rects(cid: int, root: int) -> Array:
	return plots.values().filter(func(p): return p.owner == cid and (p.id == root or int(p.parent) == root))


func _inside_any(cell: Vector2i, rects: Array) -> bool:
	for p in rects:
		if cell.x >= p.x and cell.x < p.x + p.w and cell.y >= p.y and cell.y < p.y + p.h:
			return true
	return false


## Prueft Eigentum, Grenzen, Kollisionen und Erreichbarkeit aller anfahrbaren Einrichtungen von der Einfahrt.
func validate_place(cid: int, plot_id: int, typ: String, x: int, y: int, rot: int, ignore_id: String = "") -> String:
	var p: Dictionary = plots.get(plot_id, {})
	if p.is_empty() or p.owner != cid:
		return "Grundstück %d gehört dir nicht." % plot_id
	if not FACILITIES.has(typ):
		return "Unbekannter Gebäudetyp '%s'. Erlaubt: %s" % [typ, ", ".join(FACILITIES.keys())]
	if typ == "sicherheit" and facilities.values().filter(func(f): return f.owner == cid and f.typ == "sicherheit").size() >= 2:
		return "Maximal 2 Sicherheitsanlagen."
	if typ == "buero" and facilities.values().any(func(f): return f.owner == cid and f.typ == "buero" and f.id != ignore_id):
		return "Es gibt bereits ein Unternehmerbüro (upgrade_building nutzen)."
	var spec: Dictionary = FACILITIES[typ]
	var w: int = spec.w if rot == 0 else spec.h
	var h: int = spec.h if rot == 0 else spec.w
	var root := _root(plot_id)
	var rects := _plot_rects(cid, root)
	var nf := {"x": x, "y": y, "w": w, "h": h, "rot": rot, "typ": typ}
	var entrance := Vector2i(int(plots[root].entrance[0]), int(plots[root].entrance[1]))
	var occupied := {}
	for f in facilities.values():
		if f.plot == root and f.id != ignore_id:
			for c in _cells(f):
				occupied[c] = true
	for c in _cells(nf):
		if not _inside_any(c, rects):
			return "Gebäude ragt über die Grundstücksgrenze (%d,%d)." % [c.x, c.y]
		if occupied.has(c):
			return "Fläche (%d,%d) ist bereits bebaut." % [c.x, c.y]
		if c == entrance:
			return "Die Einfahrt muss frei bleiben."
		occupied[c] = true
	# Erreichbarkeit: Fahrgasse von der Einfahrt zu jeder anfahrbaren Einrichtung (inkl. neuer)
	var targets: Array = []
	for f in facilities.values():
		if f.plot == root and f.id != ignore_id and FACILITIES[f.typ].drive:
			targets.append(front_cell(f))
	if spec.drive:
		targets.append(front_cell(nf))
	var seen := {entrance: true}
	var stack: Array = [entrance]
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = q + d
			if not seen.has(n) and _inside_any(n, rects) and not occupied.has(n):
				seen[n] = true
				stack.append(n)
	for t in targets:
		var tt: Vector2i = t
		if not seen.has(tt):
			return "Zufahrt blockiert: Vorplatz (%d,%d) wäre von der Einfahrt nicht erreichbar." % [tt.x, tt.y]
	return ""


## Gueltige Bauplaetze je Gebaeudetyp (fuer die KI-Beobachtung, gecacht bis zur naechsten Aenderung).
func suggestions(cid: int, plot_id: int) -> Dictionary:
	var key := "%d:%d" % [cid, plot_id]
	if _cache.has(key):
		return _cache[key]
	var out := {}
	var root := _root(plot_id)
	var rects := _plot_rects(cid, root)
	for typ in FACILITIES:
		var found: Array = []
		for p in rects:
			for y in range(p.y, p.y + p.h):
				for x in range(p.x, p.x + p.w):
					for rot in [0, 90]:
						if found.is_empty() and validate_place(cid, root, typ, x, y, rot) == "":
							found.append([x, y, rot])
		if not found.is_empty():
			out[typ] = found[0]   # [x, y, rot]
	_cache[key] = out
	return out


# ------------------------------------------------------------------ Bauen
func place(cid: int, plot_id: int, typ: String, x: int, y: int, rot: int, mode: String) -> Dictionary:
	var err := validate_place(cid, plot_id, typ, x, y, rot)
	if err != "":
		return {"ok": false, "msg": err}
	var spec: Dictionary = FACILITIES[typ]
	var ext := mode != "eigen"
	var cost: float = spec.cost * (1.0 + (EXTERNAL_SURCHARGE if ext else 0.0))
	var c: Company = sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Bau kostet %s (%s)." % [Catalog.money(cost), "Baufirma" if ext else "Eigenbau"]}
	# Stueckliste: eigenes Material zuerst (liegt am Grundstueck oder beim Bauhof), Rest vom Bauhof kaufen
	var need: Dictionary = Trader.bom(int(spec.mat))
	var local := {}
	var ship := {}
	var buy := {}
	var plot_loc := _root(plot_id)
	var owner_s := "C%d" % cid
	for it in need:
		var use_local := mini(int(need[it]), sim.stock.qty(it, owner_s, plot_loc))
		var rest: int = int(need[it]) - use_local
		var use_bh := mini(rest, sim.stock.qty(it, owner_s, sim.trader.bauhof))
		local[it] = use_local
		ship[it] = rest
		buy[it] = rest - use_bh
	for it in buy:
		if int(buy[it]) > sim.trader.stock_of(it):
			return {"ok": false, "msg": "Der Bauhof hat nicht genug %s (benötigt %d, vorrätig %d). Nachschub ist bestellt." % [Trader.MATERIALS[it].name, int(buy[it]), sim.trader.stock_of(it)]}
	var nominal: float = sim.trader.nominal_value(need)
	var share := minf(nominal, 0.45 * cost)
	var bought_nominal: float = sim.trader.nominal_value(buy.duplicate())
	var buy_paid: float = share * bought_nominal / maxf(nominal, 0.01)
	var paid: float = cost - (share - buy_paid)   # eigenes Material wurde bereits als Aufwand gebucht
	if c.ledger.cash < paid:
		return {"ok": false, "msg": "Bau kostet %s (%s)." % [Catalog.money(paid), "Baufirma" if ext else "Eigenbau"]}
	if buy_paid > 0.0:
		c.ledger.invest(buy_paid, "T0")
		sim.trader.transfer_for_build(cid, buy, buy_paid)
	c.ledger.invest(paid - buy_paid, "S0")
	cost = paid
	c.property_cost += cost
	c.property_book += cost
	var f := {"id": "B%d" % next_id, "owner": cid, "plot": _root(plot_id), "typ": typ, "x": x, "y": y,
		"w": spec.w if rot == 0 else spec.h, "h": spec.h if rot == 0 else spec.w, "rot": rot, "level": 1,
		"status": "im_bau", "progress": 0.0, "work": float(spec.build), "mat_needed": int(spec.mat),
		"mat": int(spec.mat) if ext else 0, "mode": "extern" if ext else "eigen", "invest": cost, "target_level": 1,
		"mat_contract": "", "busy": [], "material_due": sim.game_min + 60.0 if ext else 0.0}
	next_id += 1
	f["mats"] = need
	f["ship"] = ship
	if ext:
		f.mat = 0   # Lieferung durch Baufirma nach 60 Spielminuten
	facilities[f.id] = f
	if not ext:
		var from_bauhof := 0
		for it in ship:
			from_bauhof += int(ship[it])
		if from_bauhof > 0:
			f.mat_contract = sim.trader.make_shipment(cid, ship, plot_loc, f.id, int(f.mat_needed))
		else:
			f.mat = int(f.mat_needed)   # alles liegt schon am Grundstueck
	_cache.clear()
	sim.log_event("%s beginnt Bau: %s (%s)." % [c.company_name, spec.name, f.mode], "info", cid)
	return {"ok": true, "msg": "Baustelle %s (%s) bei (%d,%d)%s, Kosten %s. %s" % [f.id, spec.name, x, y, " gedreht" if rot == 90 else "",
		Catalog.money(cost), "Material wird nach 60 min geliefert." if ext else "Material per eigenem Transport %s anliefern, Arbeiter mit assign_building_staff einteilen." % f.mat_contract], "building_id": f.id}


## Eigenbau: interner Materialtransport (kein Umsatz) vom naechsten Baustofflieferanten zum Grundstueck.
func _material_contract(cid: int, f: Dictionary) -> String:
	var plot_b: Dictionary = sim.city.building(f.plot)
	var best := {}
	var best_d := INF
	for b in sim.city.buildings:
		if "baustoffe" in b.out:
			var d := Vector2(b.road - plot_b.road).length()
			if d < best_d:
				best_d = d
				best = b
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = best.id
	k.dropoff = f.plot
	k.cargo = "baustoffe"
	k.label = "Baustoffe für eigene Baustelle %s" % f.id
	k.qty = int(f.mat_needed)
	k.reward = 0.0
	k.internal = f.id
	k.owner = cid
	k.status = "accepted"
	k.created = sim.game_min
	k.accepted_at = sim.game_min
	k.deadline = sim.game_min + 99999.0
	k.offer_until = k.deadline
	k.distance = absi(best.road.x - plot_b.road.x) + absi(best.road.y - plot_b.road.y)
	sim.contracts[k.id] = k
	sim.company(cid).known[k.id] = true
	return k.id


## Lieferung eines internen Materialauftrags (vom Simulationskern aufgerufen, kein Umsatz).
func material_delivered(k: Contract) -> void:
	sim.trader.shipment_delivered(k.internal)   # Ware vom Bauhof an den Zielort (nichts zu tun bei reinen Baustellenauftraegen ohne Handel)
	if k.internal.begins_with("S"):   # reiner Handelstransport ohne Baustelle
		return
	var f: Dictionary = facilities.get(k.internal, {})
	if not f.is_empty():
		f.mat = int(f.mat_needed)
		sim.notify(f.owner, "Material für Baustelle %s angeliefert." % f.id)


func upgrade(cid: int, fid: String) -> Dictionary:
	var f: Dictionary = facilities.get(fid, {})
	if f.is_empty() or f.owner != cid:
		return {"ok": false, "msg": "Gebäude %s gehört dir nicht." % fid}
	var spec: Dictionary = FACILITIES[f.typ]
	if f.status != "fertig":
		return {"ok": false, "msg": "%s ist noch nicht fertig." % fid}
	if int(f.level) >= int(spec.max_level):
		return {"ok": false, "msg": "%s ist voll ausgebaut." % spec.name}
	var cost: float = spec.upgrade[int(f.level)]
	if sim.company(cid).ledger.cash < cost:
		return {"ok": false, "msg": "Ausbau kostet %s." % Catalog.money(cost)}
	var c: Company = sim.company(cid)
	c.ledger.invest(cost)
	c.property_cost += cost
	c.property_book += cost
	f.invest = float(f.invest) + cost
	f.status = "ausbau"
	f.target_level = int(f.level) + 1
	f.progress = 0.0
	f.work = float(spec.build) * 0.7
	f.mat = int(spec.mat)   # Ausbau: Material wird geliefert
	return {"ok": true, "msg": "%s wird auf Stufe %d ausgebaut (%s, bleibt bis dahin auf Stufe %d nutzbar)." % [spec.name, f.target_level, Catalog.money(cost), f.level]}


func remove(cid: int, fid: String) -> Dictionary:
	var f: Dictionary = facilities.get(fid, {})
	if f.is_empty() or f.owner != cid:
		return {"ok": false, "msg": "Gebäude %s gehört dir nicht." % fid}
	if f.typ == "buero" and leases.values().any(func(l): return l.office == fid and l.status == "aktiv"):
		return {"ok": false, "msg": "Vermietete Flächen können nicht abgerissen werden."}
	if f.typ in ["stellplatz", "garage"] and sim.company(cid).vehicle_ids.size() > sim.company(cid).fleet_limit() - 2:
		return {"ok": false, "msg": "Ohne diese Stellplätze wäre nicht genug Platz für die Flotte."}
	var c: Company = sim.company(cid)
	# Restbuchwert anteilig abschreiben (Buchverlust), Abriss kostet 15 % der Investition
	var share: float = float(f.invest) / maxf(c.property_cost, 1.0)
	var book_part: float = c.property_book * share
	c.property_book -= book_part
	c.property_cost -= float(f.invest)
	c.ledger.book("asset_result", -book_part, false, "Rückbau %s" % FACILITIES[f.typ].name, sim.game_min)
	c.ledger.book("property_costs", -float(f.invest) * 0.15, true, "Abrisskosten %s" % FACILITIES[f.typ].name, sim.game_min)
	sim.stock.add("altmaterial", maxi(1, int(FACILITIES[f.typ].mat) * 2), "C%d" % cid, int(f.plot), "Rückbau %s" % fid, sim.game_min)
	facilities.erase(fid)
	_refresh_company(cid)
	return {"ok": true, "msg": "%s zurückgebaut (Buchverlust %s, Abriss %s)." % [FACILITIES[f.typ].name, Catalog.money(book_part), Catalog.money(float(f.invest) * 0.15)]}


func expand(cid: int, plot_id: int, mode: String) -> Dictionary:
	var p: Dictionary = plots.get(plot_id, {})
	if p.is_empty() or p.owner >= 0:
		return {"ok": false, "msg": "Grundstück %d ist nicht verfügbar." % plot_id}
	if int(p.parent) >= 0 and plots[int(p.parent)].owner != cid:
		return {"ok": false, "msg": "Erweiterungsfläche %d grenzt nicht an dein Grundstück." % plot_id}
	var c: Company = sim.company(cid)
	if mode == "kaufen":
		if c.ledger.cash < float(p.price):
			return {"ok": false, "msg": "Kaufpreis %s." % Catalog.money(p.price)}
		c.ledger.invest(float(p.price), "P0")
		c.land_book += float(p.price)
	else:
		p.rent = LAND_RENT_PER_TILE * p.w * p.h
	p.owner = cid
	p.mode = "kauf" if mode == "kaufen" else "miete"
	if int(p.parent) < 0:
		sim.depot_owner[plot_id] = cid
		c.depots.append(plot_id)
	_cache.clear()
	sim.log_event("%s %s Grundstück %d (%d×%d)." % [c.company_name, "kauft" if mode == "kaufen" else "pachtet", plot_id, p.w, p.h], "info", cid)
	return {"ok": true, "msg": "Grundstück %d %s: %d×%d Tiles%s." % [plot_id, "gekauft" if mode == "kaufen" else "gepachtet", p.w, p.h,
		"" if mode == "kaufen" else ", Pacht %s/Tag" % Catalog.money(p.rent)]}


# ------------------------------------------------------------------ Vermietung
func rentable_units(fid: String) -> int:
	var f: Dictionary = facilities.get(fid, {})
	if f.is_empty() or f.status not in ["fertig", "ausbau"]:
		return 0
	if f.typ == "mietbuero":
		return 2 * int(f.level)
	if f.typ == "buero" and int(f.level) >= 4:
		return 2
	return 0


func leased_units(fid: String) -> int:
	var n := 0
	for l in leases.values():
		if l.office == fid and l.status == "aktiv":
			n += int(l.units)
	return n


func offer_rental(cid: int, fid: String, units: int, rent: float, min_days: float) -> Dictionary:
	var f: Dictionary = facilities.get(fid, {})
	if f.is_empty() or f.owner != cid:
		return {"ok": false, "msg": "Gebäude %s gehört dir nicht." % fid}
	var free := rentable_units(fid) - leased_units(fid)
	if units <= 0 or units > free:
		return {"ok": false, "msg": "%s hat %d freie vermietbare Einheiten (eigene Flächen sind nicht vermietbar)." % [fid, free]}
	listings[fid] = {"einheiten": units, "miete": maxf(1.0, rent), "mindest_tage": clampf(min_days, 1.0, 10.0), "owner": cid}
	return {"ok": true, "msg": "%d Einheiten in %s für %s/Tag je Einheit ausgeschrieben." % [units, fid, Catalog.money(rent)]}


func accept_tenant(cid: int, tid: String) -> Dictionary:
	var t: Dictionary = tenants.get(tid, {})
	if t.is_empty() or t.status != "interessiert":
		return {"ok": false, "msg": "Kein Mietinteressent %s." % tid}
	var f: Dictionary = facilities.get(t.office, {})
	if f.is_empty() or f.owner != cid:
		return {"ok": false, "msg": "Interessent %s betrifft nicht deine Fläche." % tid}
	if int(t.units) > rentable_units(t.office) - leased_units(t.office):
		t.status = "abgesprungen"
		return {"ok": false, "msg": "Nicht mehr genug freie Einheiten."}
	var l := {"id": "L%d" % next_id, "office": t.office, "tenant": t.name, "units": t.units, "rent": t.rent, "owner": cid,
		"start": sim.game_min, "end": sim.game_min + float(t.days) * 1440.0, "status": "aktiv"}
	next_id += 1
	leases[l.id] = l
	t.status = "vertrag"
	sim.log_event("%s vermietet %d Einheiten an %s (%s/Tag)." % [sim.company(cid).company_name, t.units, t.name, Catalog.money(t.rent * t.units)], "good", cid)
	sim.company(cid).add_key_event("Mieter %s eingezogen" % t.name, sim.game_min)
	_spawn_tenant_order(l, "Umzug (Einzug)")
	return {"ok": true, "msg": "Mietvertrag %s mit %s: %d Einheiten, %s/Tag, %d Tage." % [l.id, t.name, t.units, Catalog.money(t.rent * t.units), int(t.days)]}


## Mieter erzeugen echte Transportbedarfe (oeffentliche Auftraege, die jede Firma annehmen kann).
func _spawn_tenant_order(l: Dictionary, what: String) -> void:
	var f: Dictionary = facilities[l.office]
	var src := {}
	for b in sim.city.buildings:
		if b.type in ["warehouse", "shop"] and (src.is_empty() or sim.rng.randf() < 0.05):
			src = b
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	var moving_out := what.begins_with("Umzug (Auszug")
	k.pickup = f.plot if moving_out else src.id
	k.dropoff = src.id if moving_out else f.plot
	k.cargo = "moebel" if what.begins_with("Umzug") else ["pakete", "elektronik", "moebel"][sim.rng.randi() % 3]
	k.label = "%s: %s" % [l.tenant, what]
	k.qty = sim.rng.randi_range(3, 12)
	k.distance = absi(sim.city.building(k.pickup).road.x - sim.city.building(k.dropoff).road.x) + absi(sim.city.building(k.pickup).road.y - sim.city.building(k.dropoff).road.y)
	k.reward = roundf((80.0 + k.distance * 3.2 * (1.0 + k.qty / 8.0)) / 10.0) * 10.0
	k.created = sim.game_min
	k.deadline = sim.game_min + 480.0
	k.offer_until = sim.game_min + 180.0
	k.needs_heavy = k.qty >= int(Catalog.CARGO[k.cargo].heavy_from)
	sim.contracts[k.id] = k
	sim.world_events.note_tenant(l, what, k)


func minute_tick(now: float) -> void:
	# Bau
	for f in facilities.values():
		if f.status not in ["im_bau", "ausbau"]:
			continue
		if f.mode == "extern" and int(f.mat) < int(f.mat_needed) and now >= float(f.material_due):
			for it in f.get("ship", {}):   # Baufirma bringt das Material vom Bauhof zur Baustelle
				sim.stock.move(it, int(f.ship[it]), "C%d" % f.owner, sim.trader.bauhof, "C%d" % f.owner, int(f.plot), "Lieferung der Baufirma", now)
			f.mat = int(f.mat_needed)
		if int(f.mat) < int(f.mat_needed):
			continue
		var rate := 1.5 if f.mode == "extern" or f.status == "ausbau" else 0.0
		for t in sim.personnel.tasks.values():
			if t.kind == "bauen" and t.status == "in Bearbeitung" and str(t.target.get("facility", "")) == f.id:
				rate += 1.0
		var weather_rate: float = sim.wx.build_factor()
		if weather_rate < 1.0 and not f.get("weather_delayed", false):
			f["weather_delayed"] = true   # einmal je Baustelle melden, nicht in jeder Minute
			sim.world_events.note_construction_delay(f)
		f.progress = minf(1.0, float(f.progress) + rate * weather_rate / float(f.work))
		if float(f.progress) >= 1.0:
			if f.status == "ausbau":
				f.level = int(f.target_level)
			else:
				for it in f.get("mats", {}):   # Material wird beim Bau verbraucht
					sim.stock.consume(it, int(f.mats[it]), "C%d" % f.owner, int(f.plot), "Bauverbrauch %s" % f.id, now)
			f.status = "fertig"
			_refresh_company(f.owner)
			for t in sim.personnel.tasks.values():
				if t.kind == "bauen" and str(t.target.get("facility", "")) == f.id and not t.is_final():
					sim.personnel._finish(t, "abgeschlossen", "Bau fertig")
			sim.notify(f.owner, "%s %s ist fertig (Stufe %d)." % [FACILITIES[f.typ].name, f.id, f.level])
			sim.log_event("%s: %s fertiggestellt." % [sim.company(f.owner).company_name, FACILITIES[f.typ].name], "good", f.owner)
			sim.decisions.note(f.owner, "auto", "%s %s fertiggestellt" % [FACILITIES[f.typ].name, f.id], {"building_id": f.id})
	# Betriebskosten, Pacht, Mieten
	for c in sim.companies:
		var upkeep := 0.0
		for f in facilities.values():
			if f.owner == c.id and f.status == "fertig":
				upkeep += float(FACILITIES[f.typ].upkeep) * (0.6 + 0.4 * int(f.level))
		for p in plot_of(c.id):
			upkeep += float(p.rent)
		for l in leases.values():
			if l.owner == c.id and l.status == "aktiv":
				upkeep += 12.0 * int(l.units)   # Nebenkosten/Instandhaltung je vermieteter Einheit
		c.ledger.book("property_costs", -upkeep / 1440.0, true, "Betriebskosten Gelände", now)
	for l in leases.values():
		if l.status != "aktiv":
			continue
		var c: Company = sim.company(l.owner)
		c.ledger.book("rent_income", float(l.rent) * int(l.units) / 1440.0, true, "Miete " + l.tenant, now)
		if sim.minute_index % 240 == 0 and sim.rng.randf() < 0.25:
			_spawn_tenant_order(l, ["Büromaterial", "Technik", "Möbel"][sim.rng.randi() % 3])
		if now >= float(l.end):
			if sim.rng.randf() < 0.5:
				l.end = now + 1440.0 * 2.0
				sim.notify(l.owner, "Mieter %s verlängert um 2 Tage." % l.tenant)
			else:
				l.status = "beendet"
				_spawn_tenant_order(l, "Umzug (Auszug)")
				sim.notify(l.owner, "Mieter %s zieht aus – Einheiten wieder frei." % l.tenant)
	# Mietinteressenten (Lage, Preis, Groesse)
	if sim.minute_index % 60 == 0:
		for fid in listings:
			var li: Dictionary = listings[fid]
			var f: Dictionary = facilities.get(fid, {})
			if f.is_empty():
				continue
			var free := rentable_units(fid) - leased_units(fid)
			if free <= 0 or tenants.values().any(func(t): return t.office == fid and t.status == "interessiert"):
				continue
			var district: int = sim.city.building(f.plot).district
			var attr: float = [1.0, 0.6, 0.5, 0.6, 0.8, 0.4][district]
			var p_interest := clampf(0.5 * attr * REF_RENT * attr / float(li.miete), 0.02, 0.85)
			if sim.rng.randf() < p_interest:
				var t := {"id": "M%d" % next_id, "office": fid, "name": "%s %s" % [["Kanzlei", "Agentur", "Praxis", "Studio", "Startup"][sim.rng.randi() % 5],
					CityGenerator.SURNAMES[sim.rng.randi() % CityGenerator.SURNAMES.size()]], "units": mini(free, sim.rng.randi_range(1, 2)),
					"rent": li.miete, "days": li.mindest_tage + sim.rng.randi_range(0, 2), "status": "interessiert", "since": now}
				next_id += 1
				tenants[t.id] = t
				sim.notify(f.owner, "Mietinteressent %s (%s): %d Einheiten zu %s/Tag, %d Tage." % [t.id, t.name, t.units, Catalog.money(t.rent), int(t.days)])
	for t in tenants.values():
		if t.status == "interessiert" and now - float(t.since) > 240.0:
			t.status = "abgesprungen"


# ------------------------------------------------------------------ Beobachtung
## Statischer Gebaeudekatalog fuer den Systemprompt (nicht in jeder Beobachtung wiederholen).
static func catalog_text() -> String:
	return "
".join(FACILITIES.keys().map(func(k): return "  %s (%dx%d, %s, %d min): %s" % [k, FACILITIES[k].w, FACILITIES[k].h,
		Catalog.money(FACILITIES[k].cost), int(FACILITIES[k].build), FACILITIES[k].nutzen]))


func summary(cid: int) -> Dictionary:
	var own: Array = plot_of(cid)
	var plots_out: Array = []
	for p in own:
		plots_out.append({"id": p.id, "art": p.mode, "flaeche": [p.x, p.y, p.w, p.h], "einfahrt": p.entrance})
	var fac: Array = facilities.values().filter(func(f): return f.owner == cid).map(func(f): return {"id": f.id, "typ": f.typ,
		"pos": [f.x, f.y], "rot": f.rot, "stufe": f.level, "status": f.status, "fortschritt": snappedf(float(f.progress), 0.01),
		"material": "%d/%d" % [f.mat, f.mat_needed], "materialauftrag": f.mat_contract})
	var neighbours: Array = plots.values().filter(func(p): return p.owner < 0 and own.any(func(o): return o.id == int(p.parent))) \
		.map(func(p): return {"id": p.id, "flaeche": [p.x, p.y, p.w, p.h], "kaufpreis": p.price, "pacht_tag": LAND_RENT_PER_TILE * p.w * p.h})
	var root: int = sim.company(cid).depots[0]
	var c: Company = sim.company(cid)
	var out := {"grundstuecke": plots_out, "einrichtungen": fac, "erweiterbar": neighbours,
		"kapazitaet": {"stellplaetze": c.fleet_limit(), "laderampen": loading_bays(root), "lager": storage_cap(root) if is_plot(root) else 0,
			"kuehllager": storage_cap(root, true) if is_plot(root) else 0, "werkstattplaetze": workshop_bays(cid), "tank_l": int(c.fuel_cap)},
		"bauvorschlaege_xy_rot": suggestions(cid, root) if is_plot(root) else {},
		"vermietung": {"angebote": listings.keys().filter(func(id): return listings[id].owner == cid),
			"interessenten": tenants.values().filter(func(t): return t.status == "interessiert" and facilities.get(t.office, {}).get("owner", -1) == cid),
			"vertraege": leases.values().filter(func(l): return l.owner == cid and l.status == "aktiv")}}
	if out.vermietung.values().all(func(x): return x.is_empty()):
		out.erase("vermietung")
	if fac.is_empty():
		out.erase("einrichtungen")
	return out


func to_dict() -> Dictionary:
	var ps := {}
	for id in plots:
		ps[str(id)] = plots[id]
	return {"plots": ps, "facilities": facilities, "listings": listings, "tenants": tenants, "leases": leases, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	for id in d.get("plots", {}):
		var p: Dictionary = d.plots[id]
		for k in ["id", "owner", "parent", "x", "y", "w", "h"]:
			p[k] = int(p[k])
		plots[int(id)] = p
	facilities = d.get("facilities", {})
	for f in facilities.values():
		for k in ["owner", "plot", "x", "y", "w", "h", "rot", "level", "mat", "mat_needed", "target_level"]:
			f[k] = int(f[k])
	listings = d.get("listings", {})
	tenants = d.get("tenants", {})
	leases = d.get("leases", {})
	for l in leases.values():
		l.owner = int(l.owner)
		l.units = int(l.units)
	next_id = int(d.get("next_id", 1))
	for c in sim.companies:
		_refresh_company(c.id)
