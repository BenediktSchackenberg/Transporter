class_name MaterialHeli
extends RefCounted
## Ein schwerer Materialhubschrauber je KI-Unternehmer. Die Ware bleibt am
## Abholort reserviert, bis der sichtbare Flug am Ziel entladen wurde.

const CAPACITY := 800
const PAD_SIDE := 4
const LOAD_MIN := 8.0
const UNLOAD_MIN := 6.0

var sim: Simulation
var helis := {}              # Firmen-ID (String) -> {pad, phase, job, started, until, from, to}
var jobs := {}               # MH<n> -> Frachtauftrag
var queue: Array = []        # Aufträge in Buchungsreihenfolge
var next_id := 1


func setup(s: Simulation) -> void:
	sim = s
	ensure_fleet()


func ensure_fleet() -> void:
	if sim.hub == null or not sim.hub.enabled:
		return
	for c in sim.companies:
		var key := str(c.id)
		if helis.has(key):
			continue
		var pad := _find_pad()
		if pad.x < 0:
			continue
		helis[key] = {"pad": [pad.x, pad.y], "phase": "parked", "job": "", "started": sim.game_min, "until": sim.game_min,
			"from": [pad.x, pad.y], "to": [pad.x, pad.y],
			"crew": ["Lademeister", "Staplerfahrer", "Frachtarbeiter"]}


func _find_pad() -> Vector2i:
	var h: Dictionary = sim.city.hub
	if h.is_empty():
		return Vector2i(-1, -1)
	var rr: Array = h.rect
	var area := Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
	var parking: Array = h.get("parking", [])
	var pref := Vector2i(int(parking[0]), int(parking[1])) if parking.size() >= 2 else area.get_center()
	var candidates: Array = []
	for y in range(area.position.y + 1, area.end.y - PAD_SIDE):
		for x in range(area.position.x + 1, area.end.x - PAD_SIDE):
			var p := Vector2i(x, y)
			if _pad_free(Rect2i(p, Vector2i(PAD_SIDE, PAD_SIDE))):
				candidates.append(p)
	candidates.sort_custom(func(a, b): return (a - pref).length_squared() < (b - pref).length_squared())
	for p in candidates:
		var r := Rect2i(p, Vector2i(PAD_SIDE, PAD_SIDE)).grow(1)
		if not helis.values().any(func(v): return r.intersects(Rect2i(Vector2i(int(v.pad[0]), int(v.pad[1])), Vector2i(PAD_SIDE, PAD_SIDE)))):
			return p
	return Vector2i(-1, -1)


func _pad_free(r: Rect2i) -> bool:
	var c: CityData = sim.city
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not c.inside(q) or c.g(q) not in [CityData.G.CONCRETE, CityData.G.PARKING, CityData.G.PLAZA] or c.building_at[c.idx(q)] >= 0 or c.is_road(q):
				return false
	return true


func has_heli(cid: int) -> bool:
	ensure_fleet()
	return helis.has(str(cid))


func fee(from_building: int, to_building: int, qty: int) -> float:
	var a: Dictionary = sim.city.building(from_building)
	var b: Dictionary = sim.city.building(to_building)
	if a.is_empty() or b.is_empty():
		return INF
	var dist: float = Vector2(a.road).distance_to(Vector2(b.road))
	return snappedf(120.0 + dist * 2.2 + float(qty) * 0.18, 1.0)


func can_book_company(cid: int, source: int, dest: int, qty: int) -> bool:
	return has_heli(cid) and qty > 0 and qty <= CAPACITY and fee(source, dest, qty) < INF


func queue_hub(cid: int, deal: Dictionary) -> Dictionary:
	var dest := int(deal.dest)
	var qty := int(deal.qty)
	if not can_book_company(cid, sim.hub.loc, dest, qty):
		return {"ok": false, "msg": "Kein Materialhubschrauber oder Ladung über %d Einheiten." % CAPACITY}
	var cost := fee(sim.hub.loc, dest, qty)
	if sim.company(cid).ledger.cash < cost:
		return {"ok": false, "msg": "Für den Materialflug fehlen %s." % Catalog.money(cost)}
	sim.company(cid).ledger.book("transport", -cost, true, "Materialflug %s" % str(deal.id), sim.game_min, "S0")
	var id := _add(cid, "hub", str(deal.id), str(deal.item), qty, sim.hub.loc, dest, "C%d" % cid)
	deal.status = "helikopter"
	deal["heli"] = id
	var k: Contract = sim.contracts.get(str(deal.get("contract", "")))
	if k != null and k.status == "open":
		k.status = "cancelled"
		deal.contract = ""
	sim.log_event("%s ruft den Materialhubschrauber: %d × %s zum Betriebshof (Flug %s)." % [sim.company(cid).company_name, qty, deal.item, id], "info", cid)
	return {"ok": true, "msg": "Materialhubschrauber %s gebucht. %d × %s werden sichtbar zum Betriebshof geflogen; Fracht %s." % [id, qty, deal.item, Catalog.money(cost)], "flug": id}


func call_hub(cid: int, ref: String) -> Dictionary:
	var d: Dictionary = sim.hub.deals.get(ref, {})
	if d.is_empty() or str(d.get("party", "")) != "C%d" % cid or str(d.get("kind", "")) != "kauf" or str(d.get("status", "")) != "abholbereit":
		return {"ok": false, "msg": "Keine eigene, noch am Großlager liegende Sendung %s." % ref}
	var k: Contract = sim.contracts.get(str(d.get("contract", "")))
	if k != null and k.status != "open":
		return {"ok": false, "msg": "Sendung %s ist bereits einem LKW zugeteilt." % ref}
	if not sim.stock.has_reservation("hub:" + ref):
		return {"ok": false, "msg": "Die Ware ist nicht mehr am Großlager reserviert."}
	return queue_hub(cid, d)


func queue_city(town: int, order: Dictionary) -> bool:
	var cid := -1
	for c in sim.companies:
		if c.home_town == town:
			cid = c.id
			break
	var dp: CityDepot = sim.towns.depot(town)
	if cid < 0 or not has_heli(cid) or int(order.qty) > CAPACITY or dp.building < 0 or sim.city.building(int(order.loc)).is_empty():
		return false
	var id := _add(cid, "city", str(order.id), str(order.item), int(order.qty), int(order.loc), dp.building, str(order.supplier))
	order.status = "heli_wartet"
	order["heli"] = id
	return true


func queue_peer(buyer: int, offer: Dictionary) -> Dictionary:
	var seller := int(offer.from)
	var src := int(offer.site_id)
	var c: Company = sim.company(buyer)
	if c == null or c.depots.is_empty() or not can_book_company(buyer, src, int(c.depots[0]), int(offer.menge)):
		return {"ok": false, "msg": "Für diese Menge oder Strecke steht kein Materialhubschrauber bereit."}
	var cost := fee(src, int(c.depots[0]), int(offer.menge))
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Materialflug kostet zusätzlich %s." % Catalog.money(cost)}
	c.ledger.book("transport", -cost, true, "Materialabholung bei %s" % sim.company(seller).company_name, sim.game_min, "S0")
	var id := _add(buyer, "peer", str(offer.id), str(offer.item), int(offer.menge), src, int(c.depots[0]), "C%d" % buyer)
	offer["heli"] = id
	offer["material_status"] = "unterwegs"
	return {"ok": true, "flug": id}


func _add(cid: int, kind: String, ref: String, item: String, qty: int, source: int, dest: int, owner: String) -> String:
	var id := "MH%d" % next_id
	next_id += 1
	jobs[id] = {"id": id, "cid": cid, "kind": kind, "ref": ref, "item": item, "qty": qty, "source": source, "dest": dest,
		"owner": owner, "status": "wartet", "created": sim.game_min}
	queue.append(id)
	return id


func update(_dt: float) -> void:
	ensure_fleet()
	for key in helis:
		var h: Dictionary = helis[key]
		for _guard in 6:
			if str(h.phase) == "parked":
				var id := _next_for(int(key))
				if id == "":
					break
				_start(h, jobs[id])
			if sim.game_min < float(h.until):
				break
			_advance(h)


func _next_for(cid: int) -> String:
	for id in queue:
		if jobs.has(id) and int(jobs[id].cid) == cid and str(jobs[id].status) == "wartet":
			return str(id)
	return ""


func _start(h: Dictionary, j: Dictionary) -> void:
	h.job = str(j.id)
	j.status = "aktiv"
	var pad := Vector2i(int(h.pad[0]), int(h.pad[1]))
	var src := pad if int(j.source) == sim.hub.loc else _landing(int(j.source))
	var dst := _landing(int(j.dest))
	h.from = [src.x, src.y]
	h.to = [dst.x, dst.y]
	h.started = sim.game_min
	if src == pad:
		h.phase = "loading"
		h.until = sim.game_min + LOAD_MIN
	else:
		h.phase = "to_pickup"
		h.until = sim.game_min + _travel(pad, src)
	sim.log_event("Materialhubschrauber %s: Lagerpersonal bereitet %d × %s vor." % [j.id, int(j.qty), str(j.item)], "info", int(j.cid))


func _advance(h: Dictionary) -> void:
	var j: Dictionary = jobs.get(str(h.job), {})
	if j.is_empty():
		h.phase = "parked"
		h.job = ""
		return
	var t := float(h.until)
	h.started = t
	match str(h.phase):
		"to_pickup":
			h.phase = "loading"
			h.until = t + LOAD_MIN
		"loading":
			h.phase = "outbound"
			h.until = t + _travel(Vector2i(int(h.from[0]), int(h.from[1])), Vector2i(int(h.to[0]), int(h.to[1])))
			sim.log_event("Materialhubschrauber %s hebt mit %d × %s ab." % [j.id, int(j.qty), str(j.item)], "info", int(j.cid))
		"outbound":
			h.phase = "unloading"
			h.until = t + UNLOAD_MIN
		"unloading":
			_deliver(j)
			h.phase = "returning"
			h.until = t + _travel(Vector2i(int(h.to[0]), int(h.to[1])), Vector2i(int(h.pad[0]), int(h.pad[1])))
		"returning":
			h.phase = "parked"
			h.job = ""
			h.until = t
			queue.erase(str(j.id))
			jobs.erase(str(j.id))


func _deliver(j: Dictionary) -> void:
	var moved := 0
	match str(j.kind):
		"hub":
			moved = sim.stock.move_reserved("hub:" + str(j.ref), str(j.owner), int(j.dest), "Materialflug %s" % j.id, sim.game_min)
			var deal: Dictionary = sim.hub.deals.get(str(j.ref), {})
			if not deal.is_empty():
				deal.status = "geliefert" if moved > 0 else "storniert"
				deal["done"] = GameCalendar.day_of(sim.game_min)
		"city":
			var dp: CityDepot = sim.towns.depot(sim.towns.of_building(int(j.dest)))
			var order: Dictionary = dp.orders.get(str(j.ref), {})
			if not order.is_empty():
				var fee_paid := minf(float(order.freight), maxf(0.0, float(sim.economy.accounts.get(dp.owner(), 0.0))))
				sim.economy.transfer(dp.owner(), "S0", fee_paid)
				order.freight_paid = fee_paid
				dp.stats.freight = float(dp.stats.freight) + fee_paid
				dp._receive(order, "order:" + str(j.ref))
				moved = int(order.qty_received)
		"peer":
			moved = sim.stock.move_reserved("peer:" + str(j.ref), str(j.owner), int(j.dest), "KI-Materialhandel %s" % j.id, sim.game_min)
			var offer: Dictionary = sim.social.offers.get(str(j.ref), {})
			if not offer.is_empty():
				offer["material_status"] = "geliefert" if moved > 0 else "fehlgeschlagen"
	j.status = "geliefert" if moved > 0 else "fehlgeschlagen"
	sim.log_event("Materialhubschrauber %s landet: %d × %s am Ziel entladen." % [j.id, moved, str(j.item)], "good" if moved > 0 else "warn", int(j.cid))
	sim.agent_event.emit(int(j.cid), "Materialflug %s: %d × %s angekommen" % [j.id, moved, str(j.item)])


func _travel(a: Vector2i, b: Vector2i) -> float:
	return maxf(8.0, Vector2(a).distance_to(Vector2(b)) * 0.17)


func _landing(building_id: int) -> Vector2i:
	var b: Dictionary = sim.city.building(building_id)
	if b.is_empty():
		return Vector2i.ZERO
	var ctr := Vector2i(int(b.x) + int(b.w) / 2, int(b.y) + int(b.h) / 2)
	for rad in range(2, 8):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var q := ctr + Vector2i(dx, dy)
				if sim.city.inside(q) and sim.city.g(q) != CityData.G.WATER and not sim.city.is_road(q) and sim.city.building_at[sim.city.idx(q)] < 0 and sim.city.walkable(q):
					return q
	return b.road


func flight_state(cid: int) -> Dictionary:
	var h: Dictionary = helis.get(str(cid), {})
	if h.is_empty():
		return {}
	var pad := Vector2(float(h.pad[0]) + 2.0, float(h.pad[1]) + 2.0)
	var from := Vector2(float(h.from[0]) + 0.5, float(h.from[1]) + 0.5)
	var to := Vector2(float(h.to[0]) + 0.5, float(h.to[1]) + 0.5)
	var progress := clampf((sim.game_min - float(h.started)) / maxf(1.0, float(h.until) - float(h.started)), 0.0, 1.0)
	var pos := pad
	var height := 0.0
	match str(h.phase):
		"to_pickup":
			pos = pad.lerp(from, progress)
			height = 1.0 + 5.0 * sin(PI * progress)
		"loading":
			pos = from
			height = 0.3
		"outbound":
			pos = from.lerp(to, progress)
			height = 1.0 + 6.0 * sin(PI * progress)
		"unloading":
			pos = to
			height = 0.3
		"returning":
			pos = to.lerp(pad, progress)
			height = 1.0 + 5.0 * sin(PI * progress)
	return {"pos": pos, "height": height, "phase": str(h.phase), "job": str(h.job), "cargo": str(h.phase) in ["outbound", "unloading"],
		"pad": pad, "from": from, "to": to, "progress": progress}


func obs(cid: int) -> Dictionary:
	var h: Dictionary = helis.get(str(cid), {})
	if h.is_empty():
		return {}
	var active: Dictionary = jobs.get(str(h.job), {})
	return {"modell": "Chinook-Materialhubschrauber", "landeplatz_hauptlager": h.pad, "phase": h.phase,
		"ladung": {"artikel": active.item, "menge": active.qty, "ziel": active.dest} if not active.is_empty() else {},
		"wartende_fluege": queue.filter(func(id): return jobs.has(id) and int(jobs[id].cid) == cid).size(), "kapazitaet": CAPACITY, "lagerpersonal": h.crew}


func to_dict() -> Dictionary:
	return {"helis": helis, "jobs": jobs, "queue": queue, "next": next_id}


func from_dict(d: Dictionary) -> void:
	if not d.is_empty():
		helis = d.get("helis", {})
		jobs = d.get("jobs", {})
		queue = d.get("queue", [])
		next_id = int(d.get("next", 1))
	ensure_fleet()
	# Alte Spielstände: bereits gekaufte, unberührte Ware am Großlager darf
	# nach dem Laden mit dem neuen Dienst abgeholt werden.
	for deal in sim.hub.deals.values():
		if str(deal.get("kind", "")) != "kauf" or str(deal.get("status", "")) != "abholbereit" or not str(deal.get("party", "")).begins_with("C"):
			continue
		var cid := int(str(deal.party).substr(1))
		var contract: Contract = sim.contracts.get(str(deal.get("contract", "")))
		if contract != null and contract.status != "open":
			continue
		if sim.stock.has_reservation("hub:" + str(deal.id)) and can_book_company(cid, sim.hub.loc, int(deal.dest), int(deal.qty)):
			queue_hub(cid, deal)
