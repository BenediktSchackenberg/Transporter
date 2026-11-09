class_name Tourism
extends RefCounted
## Besucher sind Reisegruppen, keine Einwohner. Ihr begrenztes Reisegeld liegt auf einem eigenen
## Gegenkonto und wird nach dem Aufenthalt an die Herkunft zurueckgegeben.

const BEDS_PER_ROOM := 2
const ROAD_TILES_PER_DAY := 180
const BREAKFAST_PRICE := 8.0
const NIGHT_TAX := 2.0
const VENUES := {"strandbar": {"price": 14.0, "capacity": 24, "from": 12, "to": 17},
	"kneipe": {"price": 12.0, "capacity": 20, "from": 18, "to": 22},
	"disco": {"price": 25.0, "capacity": 50, "from": 21, "to": 24}}

var sim: Simulation
var trips := {} # U<n> -> Reise mit Herkunft, Budget, Hotel, Weg, Belegung und Status
var stats := {} # Stadt-ID -> Ankuenfte, Abreisen, Uebernachtungen, Ausgaben, Zufriedenheit
var _next := 1
var venue_visits := {} # YYYY-Spieltag: Betriebs-ID -> bezahlte Gaeste


func setup(s: Simulation) -> void:
	sim = s
	sim.day_changed.connect(on_day)
	for k in sim.towns.count():
		stats[k] = {"ankuenfte": 0, "abreisen": 0, "uebernachtungen": 0, "ausgaben": 0.0, "zufriedenheit": 0.0, "bewertungen": 0, "nachtleben": 0}


func rooms(b: Dictionary) -> int:
	return int(BusinessStages.stage_def(b).get("zimmer", 10)) if b.branch == "hotel" else 0


func occupied(bid: String, day: int) -> int:
	var count := 0
	for t in trips.values():
		if t.hotel == bid and t.status not in ["storniert", "abgereist"] and day >= int(t.arrival_day) and day < int(t.departure_day):
			count += int(t.rooms)
	return count


func occupancy(bid: String) -> float:
	var b: Dictionary = sim.biz.get_b(bid)
	return float(occupied(bid, GameCalendar.day_of(sim.game_min))) / maxf(1.0, float(rooms(b))) if not b.is_empty() else 0.0


func detail(b: Dictionary) -> Dictionary:
	if VENUES.has(str(b.branch)):
		return {"besucher_tag": int(b.get("visitors_today", 0)), "eintritt": int(b.get("entry_price", VENUES[str(b.branch)].price)),
			"getraenke": sim.stock.available("fassgetraenk", "C%d" % int(b.owner), int(b.site))}
	var day := GameCalendar.day_of(sim.game_min)
	return {"zimmer": rooms(b), "belegt": occupied(str(b.id), day), "gebucht_morgen": occupied(str(b.id), day + 1),
		"zimmerpreis": int(b.get("room_price", 65.0)), "gaeste_heute": int(summary(sim.towns.of_building(int(b.site))).aktive_gaeste)}


func set_price(cid: int, bid: String, price: float) -> Dictionary:
	var b: Dictionary = sim.biz.get_b(bid)
	if b.is_empty() or b.branch != "hotel" or int(b.owner) != cid or b.status not in Businesses.RUNNING:
		return {"ok": false, "msg": "Kein eigenes laufendes Hotel"}
	if price < 25.0 or price > 350.0:
		return {"ok": false, "msg": "Zimmerpreis muss zwischen 25 und 350 EUR liegen"}
	b["room_price"] = snappedf(price, 0.01)
	sim.biz.note(bid, "Zimmerpreis: %s pro Nacht" % Catalog.money(price), "Unternehmer")
	return {"ok": true, "msg": "Zimmerpreis auf %s pro Nacht gesetzt" % Catalog.money(price)}


func set_venue_price(cid: int, bid: String, price: float) -> Dictionary:
	var b: Dictionary = sim.biz.get_b(bid)
	if b.is_empty() or not VENUES.has(str(b.branch)) or int(b.owner) != cid or b.status not in Businesses.RUNNING:
		return {"ok": false, "msg": "Kein eigener laufender Freizeitbetrieb"}
	if price < 5.0 or price > 100.0:
		return {"ok": false, "msg": "Eintrittspreis muss zwischen 5 und 100 EUR liegen"}
	b["entry_price"] = snappedf(price, 0.01)
	sim.biz.note(bid, "Eintritt und Getränk: %s" % Catalog.money(price), "Unternehmer")
	return {"ok": true, "msg": "Eintritt auf %s gesetzt" % Catalog.money(price)}


## Herkunft -1 = Ausland X0; sonst Bewohner-ID einer anderen Stadt, finanziert aus dessen vorhandenem Guthaben.
## Fluggaeste nutzen den regelmaessigen Flug und dessen Sitzkapazitaet; Inlandsgaeste die befahrbare Strassenroute.
func book(bid: String, persons: int, nights: int, budget: float, person_id: int = -1) -> Dictionary:
	var b: Dictionary = sim.biz.get_b(bid)
	if b.is_empty() or b.branch != "hotel" or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
		return {"ok": false, "msg": "Hotel nicht betriebsbereit"}
	if sim.biz.staff_of(bid).is_empty():
		return {"ok": false, "msg": "Hotel ohne Personal"}
	if persons < 1 or persons > 8 or nights < 1 or nights > 14 or budget <= 0.0:
		return {"ok": false, "msg": "Ungueltige Gruppengroesse, Dauer oder Reisekasse"}
	var town := sim.towns.of_building(int(b.site))
	var guest := {}
	var mode := "flug"
	var path: Array[Vector2i] = []
	var travel_days := 1
	if person_id >= 0:
		guest = sim.population.person_index().get(person_id, {})
		if guest.is_empty() or sim.citizens.home_town(guest) == town or float(guest.get("balance", 0.0)) < budget:
			return {"ok": false, "msg": "Bewohner fehlt, wohnt am Zielort oder hat zu wenig Guthaben"}
		var origin := sim.citizens.home_town(guest)
		if origin < 0 or origin >= sim.towns.count():
			return {"ok": false, "msg": "Herkunftsstadt unbekannt"}
		path = sim.nav.road_path(sim.towns.get_t(origin).center, sim.city.building(int(b.site)).road)
		if path.is_empty():
			return {"ok": false, "msg": "Keine befahrbare Strassenroute zum Hotel"}
		travel_days = maxi(1, ceili(float(path.size()) / ROAD_TILES_PER_DAY))
		mode = "strasse"
	else:
		var airport: Airport = sim.towns.airport(town)
		if not airport.enabled:
			return {"ok": false, "msg": "Kein betriebsfaehiger Ankunftsflughafen"}
		var day0 := GameCalendar.day_of(sim.game_min) + 1
		var reserved := 0
		for t in trips.values():
			if t.mode == "flug" and int(t.arrival_day) == day0 and int(t.town) == town and t.status not in ["storniert", "abgereist"]:
				reserved += int(t.persons)
		if reserved + persons > airport.seats():
			return {"ok": false, "msg": "Keine freien Flugplaetze fuer diesen Ankunftstag"}
	var arrival := GameCalendar.day_of(sim.game_min) + travel_days
	var departure := arrival + nights
	var need := ceili(float(persons) / BEDS_PER_ROOM)
	var price := float(b.get("room_price", 65.0))
	if budget < price * float(need * nights):
		return {"ok": false, "msg": "Reisekasse reicht nicht fuer die Zimmer"}
	for day in range(arrival, departure):
		if occupied(bid, day) + need > rooms(b):
			return {"ok": false, "msg": "Fuer den Zeitraum sind nicht genug Zimmer frei"}
	var id := "U%d" % _next
	_next += 1
	sim.economy.accounts[id] = 0.0
	if guest.is_empty():
		sim.economy.transfer("X0", id, budget)
	else:
		sim.population.pay_out(id, [[guest, budget]])
	var route: Array = path.map(func(p): return [p.x, p.y])
	trips[id] = {"id": id, "person": person_id, "origin": "X0" if guest.is_empty() else "R0", "persons": persons,
		"budget_start": budget, "hotel": bid, "town": town, "mode": mode, "route": route, "arrival_day": arrival,
		"departure_day": departure, "rooms": need, "price": price, "paid_nights": 0, "breakfasts": 0, "venue_count": 0,
		"kind": "Familie" if persons >= 3 else ("Paar" if persons == 2 else "Einzelgast"),
		"status": "unterwegs", "position": 0, "booked_min": sim.game_min}
	return {"ok": true, "ref": id, "arrival_day": arrival, "departure_day": departure, "mode": mode}


func cancel(id: String) -> bool:
	var t: Dictionary = trips.get(id, {})
	if t.is_empty() or t.status != "unterwegs":
		return false
	t.status = "storniert"
	_refund(t)
	return true


func on_day(day: int) -> void:
	_prune(day)
	_restock_hotels()
	for b in sim.biz.items.values():
		if VENUES.has(str(b.branch)):
			b["visitors_today"] = 0
	_generate_demand(day)
	for t in trips.values():
		if t.status in ["storniert", "abgereist"]:
			continue
		var b: Dictionary = sim.biz.get_b(str(t.hotel))
		if t.status == "im_hotel" and (b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.staff_of(str(t.hotel)).is_empty()):
			t.status = "abgereist"
			stats[int(t.town)].abreisen += int(t.persons)
			_refund(t)
			continue
		if t.status == "unterwegs" and day >= int(t.arrival_day):
			if b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.staff_of(str(t.hotel)).is_empty():
				cancel(str(t.id))
				continue
			t.status = "im_hotel"
			stats[int(t.town)].ankuenfte += int(t.persons)
			sim.log_event("%s: %s (%d Gäste) checkt in %s ein." % [sim.towns.name_of(int(t.town)), t.kind, int(t.persons), b.name], "info", int(b.owner))
		if t.status != "im_hotel":
			continue
		if day > int(t.arrival_day) and int(t.paid_nights) < int(t.departure_day) - int(t.arrival_day):
			var due := float(t.price) * float(t.rooms)
			if not _pay(t, b, due, "Hoteluebernachtung"):
				t.departure_day = day
			else:
				t.paid_nights += 1
				stats[int(t.town)].uebernachtungen += int(t.persons)
				var tax := minf(float(sim.economy.accounts[t.id]), NIGHT_TAX * float(t.persons))
				if tax > 0.0:
					sim.economy.transfer(t.id, Towns.account_of(int(t.town)), tax)
					stats[int(t.town)].ausgaben += tax
				_breakfast(t, b)
		if day >= int(t.departure_day):
			t.status = "abgereist"
			stats[int(t.town)].abreisen += int(t.persons)
			_rate(t)
			_refund(t)
	_visit_venues(day)


func tick() -> void:
	for t in trips.values():
		if t.status != "unterwegs" or t.mode != "strasse" or t.route.is_empty():
			continue
		var end_min := GameCalendar.day_start(int(t.arrival_day))
		var fraction := clampf((sim.game_min - float(t.get("booked_min", sim.game_min))) / maxf(1.0, end_min - float(t.get("booked_min", sim.game_min))), 0.0, 1.0)
		t.position = mini(t.route.size() - 1, int(fraction * float(t.route.size())))


func position_of(t: Dictionary) -> Vector2i:
	if t.mode == "strasse" and t.status == "unterwegs" and not t.route.is_empty():
		var p: Array = t.route[clampi(int(t.position), 0, t.route.size() - 1)]
		return Vector2i(int(p[0]), int(p[1]))
	var b: Dictionary = sim.biz.get_b(str(t.hotel))
	if b.is_empty():
		return Vector2i.ZERO
	if t.status == "unterwegs":
		var air: Dictionary = sim.city.towns[int(t.town)].airport if sim.city.towns.size() > int(t.town) else sim.city.airport
		return sim.city.building(int(air.get("terminal", b.site))).walk
	if str(t.get("venue", "")) != "" and sim.game_min >= float(t.get("venue_from", 0.0)) and sim.game_min < float(t.get("venue_until", 0.0)):
		var venue: Dictionary = sim.biz.get_b(str(t.venue))
		if not venue.is_empty():
			return sim.city.building(int(venue.site)).walk
	return sim.city.building(int(b.site)).walk


func _visit_venues(day: int) -> void:
	var venues: Array = sim.biz.items.values().filter(func(b): return VENUES.has(str(b.branch)) and b.status in Businesses.RUNNING and not sim.biz.staff_of(str(b.id)).is_empty())
	for t in trips.values():
		if t.status != "im_hotel" or int(t.get("last_visit_day", -1)) == day:
			continue
		for step in venues.size():
			var b: Dictionary = venues[(day + int(str(t.id).trim_prefix("U")) + step) % venues.size()]
			if sim.towns.of_building(int(b.site)) != int(t.town):
				continue
			if _visit(t, b, day):
				break
	# Einheimische benutzen dieselben Betriebe und bezahlen aus ihrem persoenlichen Guthaben.
	for b in venues:
		var town := sim.towns.of_building(int(b.site))
		var price := float(b.get("entry_price", VENUES[str(b.branch)].price))
		for p in sim.citizens.people:
			if int(b.get("visitors_today", 0)) >= 3 or sim.citizens.home_town(p) != town or float(p.get("balance", 0.0)) < price + 20.0:
				continue
			if sim.stock.available("fassgetraenk", "C%d" % int(b.owner), int(b.site)) <= 0:
				break
			p.balance = float(p.balance) - price
			sim.company(int(b.owner)).ledger.book("sales", price, true, "Besuch %s" % b.name, sim.game_min, Population.ACCOUNT, str(b.id))
			sim.stock.consume("fassgetraenk", 1, "C%d" % int(b.owner), int(b.site), "Gastronomie", sim.game_min)
			b["visitors_today"] = int(b.get("visitors_today", 0)) + 1
			stats[town].ausgaben += price
			stats[town]["nachtleben"] = int(stats[town].get("nachtleben", 0)) + 1


func _visit(t: Dictionary, b: Dictionary, day: int) -> bool:
	var spec: Dictionary = VENUES[str(b.branch)]
	var price := float(b.get("entry_price", spec.price)) * float(t.persons)
	var key := "%d:%s" % [day, str(b.id)]
	if int(venue_visits.get(key, 0)) + int(t.persons) > int(spec.capacity) or sim.stock.available("fassgetraenk", "C%d" % int(b.owner), int(b.site)) < int(t.persons):
		return false
	if not _pay(t, b, price, "Besuch %s" % b.name):
		return false
	sim.stock.consume("fassgetraenk", int(t.persons), "C%d" % int(b.owner), int(b.site), "Gastronomie", sim.game_min)
	venue_visits[key] = int(venue_visits.get(key, 0)) + int(t.persons)
	b["visitors_today"] = int(b.get("visitors_today", 0)) + int(t.persons)
	t["last_visit_day"] = day
	t["venue_count"] = int(t.get("venue_count", 0)) + 1
	t["venue"] = str(b.id)
	t["venue_from"] = GameCalendar.day_start(day) + float(spec.from) * 60.0
	t["venue_until"] = GameCalendar.day_start(day) + float(spec.to) * 60.0
	stats[int(t.town)]["nachtleben"] = int(stats[int(t.town)].get("nachtleben", 0)) + int(t.persons)
	return true


func _generate_demand(day: int) -> void:
	for b in sim.biz.items.values():
		if b.branch != "hotel" or b.status not in Businesses.RUNNING or sim.biz.staff_of(str(b.id)).is_empty():
			continue
		var town := sim.towns.of_building(int(b.site))
		var has_future := trips.values().any(func(t): return t.hotel == b.id and int(t.arrival_day) == day + 1 and t.status not in ["storniert", "abgereist"])
		if has_future:
			continue
		var price := float(b.get("room_price", 65.0))
		var persons := 1 + posmod(day + int(b.site), 3) + (mini(3, sim.civic.attraction(town) / 2) if sim.civic != null and sim.civic.enabled() else 0)   # Auftrag 19: Sehenswuerdigkeiten
		var nights := 1 + posmod(day + int(b.owner), 3)
		book(str(b.id), persons, nights, price * ceili(float(persons) / BEDS_PER_ROOM) * nights + 120.0)
		for p in sim.citizens.people:
			if sim.citizens.home_town(p) != town and float(p.get("balance", 0.0)) >= price + 120.0:
				if book(str(b.id), 1, 1, price + 100.0, int(p.id)).ok:
					break


func _pay(t: Dictionary, b: Dictionary, amount: float, service: String) -> bool:
	if float(sim.economy.accounts.get(str(t.id), 0.0)) + 0.001 < amount:
		return false
	sim.company(int(b.owner)).ledger.book("sales", amount, true, service, sim.game_min, str(t.id), str(b.id))
	stats[int(t.town)].ausgaben += amount
	return true


func _breakfast(t: Dictionary, b: Dictionary) -> void:
	var acct := "C%d" % int(b.owner)
	var site := int(b.site)
	var n := int(t.persons)
	if sim.stock.available("brot", acct, site) < n or sim.stock.available("fassgetraenk", acct, site) < n:
		sim.biz.block(str(b.id), "fruehstueck", "Fruehstueck fehlt: Brot oder Getraenke nicht geliefert")
		return
	if float(sim.economy.accounts.get(str(t.id), 0.0)) < BREAKFAST_PRICE * n:
		return
	sim.stock.consume("brot", n, acct, site, "Hotelfruehstueck", sim.game_min)
	sim.stock.consume("fassgetraenk", n, acct, site, "Hotelfruehstueck", sim.game_min)
	_pay(t, b, BREAKFAST_PRICE * n, "Hotelfruehstueck")
	t["breakfasts"] = int(t.get("breakfasts", 0)) + 1
	sim.biz.unblock(str(b.id), "fruehstueck")


func _rate(t: Dictionary) -> void:
	var town := int(t.town)
	var st: Dictionary = stats[town]
	var nights := maxi(1, int(t.departure_day) - int(t.arrival_day))
	var score := clampf(55.0 + 30.0 * float(t.paid_nights) / nights + 8.0 * float(t.get("breakfasts", 0)) / nights +
		4.0 * float(t.get("venue_count", 0)), 0.0, 100.0)
	var n := int(st.get("bewertungen", 0))
	st["zufriedenheit"] = snappedf((float(st.get("zufriedenheit", 0.0)) * n + score) / (n + 1), 0.1)
	st["bewertungen"] = n + 1
	sim.log_event("%s: %s reist ab und bewertet den Aufenthalt mit %d/100." % [sim.towns.name_of(town), t.kind, int(score)], "info", -1)


func _prune(day: int) -> void:
	for id in trips.keys():
		var t: Dictionary = trips[id]
		if t.status in ["storniert", "abgereist"] and int(t.departure_day) < day - 30:
			if absf(float(sim.economy.accounts.get(id, 0.0))) < 0.001:
				sim.economy.accounts.erase(id)
			trips.erase(id)
	for key in venue_visits.keys():
		if int(str(key).get_slice(":", 0)) < day - 7:
			venue_visits.erase(key)


func _restock_hotels() -> void:
	for b in sim.biz.items.values():
		if b.branch != "hotel" and not VENUES.has(str(b.branch)) or b.status not in Businesses.RUNNING:
			continue
		var acct := "C%d" % int(b.owner)
		for item in (["brot", "fassgetraenk"] if b.branch == "hotel" else ["fassgetraenk"]):
			var have := sim.stock.available(item, acct, int(b.site)) + sim.prod.incoming(acct, item, int(b.site))
			if have < 8:
				sim.prod.order(acct, int(b.site), str(b.id), item, 24 - have, 30.0, true)


func _refund(t: Dictionary) -> void:
	var left := float(sim.economy.accounts.get(str(t.id), 0.0))
	if left <= 0.0:
		return
	if str(t.origin) == "R0":
		var p: Dictionary = sim.population.person_index().get(int(t.person), {})
		if not p.is_empty():
			sim.population.pay_in(str(t.id), [[p, left]])
			return
	sim.economy.transfer(str(t.id), "X0" if str(t.origin) == "R0" else str(t.origin), left)


func summary(town: int) -> Dictionary:
	var out: Dictionary = stats.get(town, {}).duplicate()
	out["aktive_gaeste"] = trips.values().filter(func(t): return int(t.town) == town and t.status == "im_hotel").reduce(func(total, t): return total + int(t.persons), 0)
	return out


func to_dict() -> Dictionary:
	return {"trips": trips.duplicate(true), "stats": stats.duplicate(true), "next": _next, "venue_visits": venue_visits.duplicate()}


func from_dict(d: Dictionary) -> void:
	trips = d.get("trips", {}).duplicate(true)
	_next = int(d.get("next", 1))
	venue_visits = d.get("venue_visits", {}).duplicate()
	for k in d.get("stats", {}):
		stats[int(k)] = d.stats[k].duplicate(true)
