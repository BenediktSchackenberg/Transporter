class_name Tourism
extends RefCounted
## Besucher sind Reisegruppen, keine Einwohner. Ihr begrenztes Reisegeld liegt auf einem eigenen
## Gegenkonto und wird nach dem Aufenthalt an die Herkunft zurueckgegeben.

const BEDS_PER_ROOM := 2
const ROAD_TILES_PER_DAY := 180
const MARKET_NIGHTLY_BUDGETS := [65.0, 90.0, 120.0, 155.0, 205.0, 285.0, 360.0]
const LOCAL_TRANSFER_HOURS := 1.0
const BREAKFAST_PRICE := 8.0
const NIGHT_TAX := 2.0
const TRANSFER_FARE_LOCAL := 12.0
const TRANSFER_FARE_INTERCITY := 22.0
const VENUES := {"strandbar": {"price": 14.0, "capacity": 24, "from": 12, "to": 17},
	"kneipe": {"price": 12.0, "capacity": 20, "from": 18, "to": 22},
	"disco": {"price": 25.0, "capacity": 50, "from": 21, "to": 24}}

var sim: Simulation
var trips := {} # U<n> -> Reise mit Herkunft, Budget, Hotel, Weg, Belegung und Status
var stats := {} # Stadt-ID -> Ankuenfte, Abreisen, Uebernachtungen, Ausgaben, Zufriedenheit
var hotel_reviews := {} # Hotel-ID -> {score, count}; die Gaeste bewerten das gebuchte Hotel
var _next := 1
var _last_market_day := -1
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
	var reviews: Dictionary = hotel_reviews.get(str(b.id), {})
	return {"zimmer": rooms(b), "belegt": occupied(str(b.id), day), "gebucht_morgen": occupied(str(b.id), day + 1),
		"zimmerpreis": int(b.get("room_price", 65.0)), "gaeste_heute": int(summary(sim.towns.of_building(int(b.site))).aktive_gaeste),
		"bewertung": float(reviews.get("score", 65.0)), "bewertungen": int(reviews.get("count", 0))}


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
		path = sim.nav.road_path(sim._nearest_road(sim.towns.get_t(origin).center), sim.city.building(int(b.site)).road)
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
		var air: Dictionary = sim.city.towns[town].airport if sim.city.towns.size() > town else sim.city.airport
		var terminal := int(air.get("terminal", -1))
		if terminal < 0 or sim.city.building(terminal).is_empty():
			return {"ok": false, "msg": "Ankunftsterminal fehlt"}
		path = sim.nav.road_path(sim.city.building(terminal).road, sim.city.building(int(b.site)).road)
		if path.is_empty():
			return {"ok": false, "msg": "Kein befahrbarer Transfer vom Flughafen zum Hotel"}
	var arrival := GameCalendar.day_of(sim.game_min) + travel_days
	var departure := arrival + nights
	var need := ceili(float(persons) / BEDS_PER_ROOM)
	var price := float(b.get("room_price", 65.0))
	var fare := float(persons) * (TRANSFER_FARE_LOCAL if mode == "flug" else TRANSFER_FARE_INTERCITY)
	if budget < price * float(need * nights) + fare:
		return {"ok": false, "msg": "Reisekasse reicht nicht fuer Zimmer und Transfer"}
	if not sim.fleet.can_send_tourist(persons):
		return {"ok": false, "msg": "Kein Reisebus mit freien Plaetzen verfuegbar"}
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
		"status": "unterwegs", "position": 0, "booked_min": sim.game_min, "transfer_fare": fare, "transfer_paid": false}
	trips[id]["arrival_route"] = _walk_route(sim.city.building(int(b.site)).road, sim.city.building(int(b.site)).walk)
	if mode == "strasse" and not _ensure_transfer(trips[id]):
		cancel(id)
		return {"ok": false, "msg": "Reisebus kann die Strassenroute nicht befahren"}
	return {"ok": true, "ref": id, "arrival_day": arrival, "departure_day": departure, "mode": mode}


func cancel(id: String) -> bool:
	var t: Dictionary = trips.get(id, {})
	if t.is_empty() or t.status != "unterwegs":
		return false
	t.status = "storniert"
	sim.fleet.cancel_tourist(id)
	_refund(t)
	return true


## Transfer belegt ein konkretes Fahrzeug auf einer gueltigen Strassenroute. Bei Laden eines Spielstands wird
## ein unterwegs befindlicher Bus von seiner zuletzt gespeicherten Position aus wiederhergestellt.
func _ensure_transfer(t: Dictionary) -> bool:
	if t.status != "unterwegs" or t.mode == "flug" and sim.game_min < GameCalendar.day_start(int(t.arrival_day)):
		return false
	if not sim.fleet.tourist_vehicle(str(t.id)).is_empty():
		return true
	var route: Array = t.get("route", [])
	if route.is_empty() and t.mode == "flug":
		var air: Dictionary = sim.city.towns[int(t.town)].airport if sim.city.towns.size() > int(t.town) else sim.city.airport
		var terminal := int(air.get("terminal", -1))
		var hotel: Dictionary = sim.biz.get_b(str(t.hotel))
		if terminal >= 0 and not hotel.is_empty():
			var path: Array[Vector2i] = sim.nav.road_path(sim.city.building(terminal).road, sim.city.building(int(hotel.site)).road)
			route = path.map(func(p): return [p.x, p.y])
			t["route"] = route
	if route.is_empty():
		return false
	if bool(t.get("transfer_paid", false)):
		route = route.slice(clampi(int(t.get("position", 0)), 0, route.size() - 1))
	var deadline := maxf(sim.game_min + 1.0, GameCalendar.day_start(int(t.arrival_day))) if t.mode == "strasse" else sim.game_min + local_transfer_minutes()
	if not sim.fleet.send_tourist(str(t.id), route, int(t.persons), deadline):
		return false
	if not bool(t.get("transfer_paid", false)):
		var fare := minf(float(t.get("transfer_fare", 0.0)), float(sim.economy.accounts.get(str(t.id), 0.0)))
		if fare > 0.0:
			sim.economy.transfer(str(t.id), Towns.account_of(int(t.town)), fare)
			var operating := minf(fare * 0.65, maxf(0.0, sim.towns.mayor(int(t.town)).cash()))
			if operating > 0.0:
				sim.economy.transfer(Towns.account_of(int(t.town)), "X0", operating)
			stats[int(t.town)].ausgaben += fare
		t["transfer_paid"] = true
		sim.log_event("%s: Reisebus mit %d Gästen fährt zu %s (%s Fahrpreis)." % [sim.towns.name_of(int(t.town)), int(t.persons), str(t.hotel), Catalog.money(fare)], "info")
	return true


func transfer_arrived(id: String) -> void:
	var t: Dictionary = trips.get(id, {})
	if t.is_empty() or t.status != "unterwegs":
		return
	var b: Dictionary = sim.biz.get_b(str(t.hotel))
	if b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.staff_of(str(t.hotel)).is_empty():
		cancel(id)
		return
	t.status = "im_hotel"
	stats[int(t.town)].ankuenfte += int(t.persons)
	sim.log_event("%s: Reisebus bringt %s (%d Gäste) zu %s; Check-in abgeschlossen." % [sim.towns.name_of(int(t.town)), t.kind, int(t.persons), b.name], "info", int(b.owner))


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
		if t.status == "unterwegs" and day >= int(t.departure_day):
			cancel(str(t.id))
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
			_ensure_transfer(t)
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
		if t.status != "unterwegs":
			continue
		if t.mode == "flug" and sim.game_min >= GameCalendar.day_start(int(t.arrival_day)):
			_ensure_transfer(t)
		var coach: Dictionary = sim.fleet.tourist_vehicle(str(t.id))
		if not coach.is_empty():
			var pos: Vector2i = coach.mover.tile()
			t.position = maxi(0, t.route.find([pos.x, pos.y]))
			continue
		if t.mode != "strasse" or t.route.is_empty():
			continue
		var end_min := GameCalendar.day_start(int(t.arrival_day))
		var fraction := clampf((sim.game_min - float(t.get("booked_min", sim.game_min))) / maxf(1.0, end_min - float(t.get("booked_min", sim.game_min))), 0.0, 1.0)
		t.position = mini(t.route.size() - 1, int(fraction * float(t.route.size())))


func position_of(t: Dictionary) -> Vector2i:
	if t.status == "unterwegs":
		var coach: Dictionary = sim.fleet.tourist_vehicle(str(t.id))
		if not coach.is_empty():
			return coach.mover.tile()
	if t.mode == "strasse" and t.status == "unterwegs" and not t.route.is_empty():
		var p: Array = t.route[clampi(int(t.position), 0, t.route.size() - 1)]
		return Vector2i(int(p[0]), int(p[1]))
	var b: Dictionary = sim.biz.get_b(str(t.hotel))
	if b.is_empty():
		return Vector2i.ZERO
	if t.status == "unterwegs":
		return _terminal_walk(int(t.town))
	var leg := _local_leg(t)
	if not leg.is_empty():
		return _route_cell(leg.route, float(leg.progress))
	# Alte Spielstaende haben bereits einen Besuchsplan, aber noch keine gespeicherte Fussroute.
	if str(t.get("venue", "")) != "" and t.get("venue_route", []).is_empty() and sim.game_min >= float(t.get("venue_from", 0.0)) and sim.game_min < float(t.get("venue_until", 0.0)):
		var venue: Dictionary = sim.biz.get_b(str(t.venue))
		if not venue.is_empty():
			return sim.city.building(int(venue.site)).walk
	return sim.city.building(int(b.site)).walk


## Die Kartenansicht nutzt die laufende Position zwischen zwei Wegpunkten; position_of bleibt fuer Zellen/Inspektion erhalten.
func visual_position_of(t: Dictionary) -> Vector2:
	if t.status == "unterwegs":
		var coach: Dictionary = sim.fleet.tourist_vehicle(str(t.id))
		if not coach.is_empty():
			return coach.mover.pos
	if t.mode == "strasse" and t.status == "unterwegs" and not t.route.is_empty():
		var end_min := GameCalendar.day_start(int(t.arrival_day))
		var fraction := clampf((sim.game_min - float(t.get("booked_min", sim.game_min))) / maxf(1.0, end_min - float(t.get("booked_min", sim.game_min))), 0.0, 1.0)
		return _route_world(t.route, fraction)
	var leg := _local_leg(t)
	if not leg.is_empty():
		return _route_world(leg.route, float(leg.progress))
	return sim.city.tile_center(position_of(t))


func _local_leg(t: Dictionary) -> Dictionary:
	if t.status != "im_hotel":
		return {}
	var now := sim.game_min
	var arrival_start := GameCalendar.day_start(int(t.arrival_day))
	var transfer_min := local_transfer_minutes()
	if now >= arrival_start and now < arrival_start + transfer_min * 2.0:
		var arrival_route: Array = t.get("arrival_route", [])
		if not arrival_route.is_empty():
			return {"route": arrival_route, "progress": clampf((now - arrival_start) / (transfer_min * 2.0), 0.0, 1.0)}
	var venue_route: Array = t.get("venue_route", [])
	if venue_route.is_empty():
		return {}
	var start := float(t.get("venue_from", 0.0))
	var finish := float(t.get("venue_until", 0.0))
	if now >= start - transfer_min and now < start:
		return {"route": venue_route, "progress": clampf((now - start + transfer_min) / transfer_min, 0.0, 1.0)}
	if now >= start and now < finish:
		return {"route": venue_route, "progress": 1.0}
	if now >= finish and now < finish + transfer_min:
		return {"route": venue_route, "progress": 1.0 - clampf((now - finish) / transfer_min, 0.0, 1.0)}
	return {}


static func local_transfer_minutes() -> float:
	return GameCalendar.day_game_min * LOCAL_TRANSFER_HOURS / 24.0


static func clock_min(day: int, hour: float) -> float:
	return GameCalendar.day_start(day) + (hour - Catalog.START_HOUR) * GameCalendar.day_game_min / 24.0


func _route_cell(route: Array, progress: float) -> Vector2i:
	var p: Array = route[clampi(int(roundf(progress * float(route.size() - 1))), 0, route.size() - 1)]
	return Vector2i(int(p[0]), int(p[1]))


func _route_world(route: Array, progress: float) -> Vector2:
	if route.is_empty():
		return Vector2.ZERO
	var index := clampf(progress, 0.0, 1.0) * float(route.size() - 1)
	var a: Array = route[clampi(int(floorf(index)), 0, route.size() - 1)]
	var b: Array = route[clampi(int(ceilf(index)), 0, route.size() - 1)]
	return sim.city.tile_center(Vector2i(int(a[0]), int(a[1]))).lerp(sim.city.tile_center(Vector2i(int(b[0]), int(b[1]))), index - floorf(index))


func _walk_route(from: Vector2i, to: Vector2i) -> Array:
	var path: Array[Vector2i] = sim.nav.walk_path(from, to)
	if path.is_empty() or path[-1] != to:
		return []
	return path.map(func(p): return [p.x, p.y])


func _terminal_walk(town: int) -> Vector2i:
	var air: Dictionary = sim.city.towns[town].airport if sim.city.towns.size() > town else sim.city.airport
	var terminal := int(air.get("terminal", -1))
	return sim.city.building(terminal).walk if terminal >= 0 and not sim.city.building(terminal).is_empty() else sim.towns.get_t(town).center


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
	var hotel: Dictionary = sim.biz.get_b(str(t.hotel))
	var route: Array = _walk_route(sim.city.building(int(hotel.site)).walk, sim.city.building(int(b.site)).walk) if not hotel.is_empty() else []
	if route.is_empty():
		return false
	if not _pay(t, b, price, "Besuch %s" % b.name):
		return false
	sim.stock.consume("fassgetraenk", int(t.persons), "C%d" % int(b.owner), int(b.site), "Gastronomie", sim.game_min)
	venue_visits[key] = int(venue_visits.get(key, 0)) + int(t.persons)
	b["visitors_today"] = int(b.get("visitors_today", 0)) + int(t.persons)
	t["last_visit_day"] = day
	t["venue_count"] = int(t.get("venue_count", 0)) + 1
	t["venue"] = str(b.id)
	t["venue_route"] = route
	t["venue_from"] = clock_min(day, float(spec.from))
	t["venue_until"] = clock_min(day, float(spec.to))
	stats[int(t.town)]["nachtleben"] = int(stats[int(t.town)].get("nachtleben", 0)) + int(t.persons)
	return true


func _generate_demand(day: int) -> void:
	if day <= _last_market_day:
		return
	_last_market_day = day
	var hotels: Array = sim.biz.items.values().filter(func(b): return b.branch == "hotel" and b.status in Businesses.RUNNING and not sim.biz.frozen(int(b.owner)) and not sim.biz.staff_of(str(b.id)).is_empty())
	if hotels.is_empty():
		return
	hotels.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var attraction_total := 0
	for town in sim.towns.count():
		attraction_total += sim.civic.attraction(town) if sim.civic != null and sim.civic.enabled() else 0
	var bad_weather := sim.wx != null and (sim.wx.is_heavy_rain() or sim.wx.is_strong_wind() or sim.wx.is_snow())
	var groups := clampi(1 + sim.towns.count() + int(attraction_total / 4) - (1 if bad_weather else 0), 1, 8)
	for slot in groups:
		var domestic := sim.towns.count() > 1 and slot % 3 == 2
		var persons := 1 if domestic else 1 + posmod(day * 7 + slot * 3 + sim.city.seed_value, 4)
		var nights := 1 + posmod(day + slot * 2, 3)
		var need := ceili(float(persons) / BEDS_PER_ROOM)
		var nightly_budget := float(MARKET_NIGHTLY_BUDGETS[posmod(day * 5 + slot * 3 + sim.city.seed_value, MARKET_NIGHTLY_BUDGETS.size())])
		var budget := nightly_budget * float(need * nights) + 55.0 * persons
		var ranked: Array = []
		for b in hotels:
			var town := sim.towns.of_building(int(b.site))
			var guest_id := -1
			var travel_days := 1
			var distance := 0
			if domestic:
				for p in sim.citizens.people:
					var origin := sim.citizens.home_town(p)
					if origin < 0 or origin == town or float(p.get("balance", 0.0)) < budget:
						continue
					var domestic_road := sim.nav.road_path(sim.towns.get_t(origin).center, sim.city.building(int(b.site)).road)
					if not domestic_road.is_empty():
						guest_id = int(p.id)
						distance = domestic_road.size()
						travel_days = maxi(1, ceili(float(distance) / ROAD_TILES_PER_DAY))
						break
				if guest_id < 0:
					continue
			else:
				var airport: Airport = sim.towns.airport(town)
				if not airport.enabled:
					continue
				var air: Dictionary = sim.city.towns[town].airport if sim.city.towns.size() > town else sim.city.airport
				var terminal := int(air.get("terminal", -1))
				if terminal < 0 or sim.city.building(terminal).is_empty():
					continue
				var airport_road := sim.nav.road_path(sim.city.building(terminal).road, sim.city.building(int(b.site)).road)
				if airport_road.is_empty():
					continue
				distance = airport_road.size()
			var price := float(b.get("room_price", 65.0))
			if price * need * nights + 25.0 * persons > budget:
				continue
			var available := true
			for stay_day in range(day + travel_days, day + travel_days + nights):
				if occupied(str(b.id), stay_day) + need > rooms(b):
					available = false
					break
			if not available:
				continue
			var reviews: Dictionary = hotel_reviews.get(str(b.id), {})
			var rating := float(reviews.get("score", 65.0))
			var attraction := sim.civic.attraction(town) if sim.civic != null and sim.civic.enabled() else 0
			var score := rating * 0.35 + float(attraction) * 3.5 + 35.0 * (nightly_budget - price) / maxf(60.0, nightly_budget) - minf(18.0, float(distance) * 0.12)
			ranked.append({"hotel": b, "person": guest_id, "score": score})
		ranked.sort_custom(func(a, b): return float(a.score) > float(b.score) or (float(a.score) == float(b.score) and str(a.hotel.id) < str(b.hotel.id)))
		for option in ranked:
			if book(str(option.hotel.id), persons, nights, budget, int(option.person)).ok:
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
	var hotel_id := str(t.hotel)
	var reviews: Dictionary = hotel_reviews.get(hotel_id, {"score": 65.0, "count": 0})
	var previous := int(reviews.get("count", 0))
	reviews["score"] = snappedf((float(reviews.get("score", 65.0)) * previous + score) / (previous + 1), 0.1)
	reviews["count"] = previous + 1
	hotel_reviews[hotel_id] = reviews
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
	return {"trips": trips.duplicate(true), "stats": stats.duplicate(true), "hotel_reviews": hotel_reviews.duplicate(true), "next": _next, "market_day": _last_market_day, "venue_visits": venue_visits.duplicate()}


func from_dict(d: Dictionary) -> void:
	trips = d.get("trips", {}).duplicate(true)
	_next = int(d.get("next", 1))
	_last_market_day = int(d.get("market_day", -1))
	venue_visits = d.get("venue_visits", {}).duplicate()
	hotel_reviews = d.get("hotel_reviews", {}).duplicate(true)
	for k in d.get("stats", {}):
		stats[int(k)] = d.stats[k].duplicate(true)
	for t in trips.values():
		var hotel: Dictionary = sim.biz.get_b(str(t.get("hotel", "")))
		if hotel.is_empty():
			continue
		var hotel_walk: Vector2i = sim.city.building(int(hotel.site)).walk
		if t.get("arrival_route", []).is_empty():
			var transfer_from: Vector2i = _terminal_walk(int(t.town)) if str(t.get("mode", "flug")) == "flug" else sim.city.building(int(hotel.site)).road
			t["arrival_route"] = _walk_route(transfer_from, hotel_walk)
		var venue: Dictionary = sim.biz.get_b(str(t.get("venue", "")))
		if venue.is_empty():
			continue
		var legacy_schedule: bool = not t.has("venue_route")
		if t.get("venue_route", []).is_empty():
			t["venue_route"] = _walk_route(hotel_walk, sim.city.building(int(venue.site)).walk)
		var visit_day := int(t.get("last_visit_day", -1))
		if legacy_schedule and visit_day >= 0:
			var spec: Dictionary = VENUES.get(str(venue.branch), {})
			if not spec.is_empty():
				t["venue_from"] = clock_min(visit_day, float(spec.from))
				t["venue_until"] = clock_min(visit_day, float(spec.to))
	for t in trips.values():
		if t.status == "unterwegs" and (t.mode == "strasse" or sim.game_min >= GameCalendar.day_start(int(t.arrival_day))):
			_ensure_transfer(t)
