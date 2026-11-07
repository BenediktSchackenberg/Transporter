extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sim := Simulation.new()
	sim.world_mode = "region"
	sim.start_profile = "unternehmer"
	sim.region_town_count = 2
	var players: Array = []
	for i in 2:
		players.append({"player_name": "Test %d" % i, "company_name": "Firma %d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	sim.setup(4242, players, 512, 0.0)
	sim.prod.instant_build = true
	var found: Dictionary = sim.biz.found(0, "hotel", "Tourismustest", {"stadt": "0"})
	print("HOTEL_GRUENDUNG ", JSON.stringify(found))
	if not found.ok:
		quit(1)
		return
	var b: Dictionary = sim.biz.get_b(str(found.ref))
	print("HOTEL_STATUS ", b.status, " SITE ", b.site, " TOWN ", sim.towns.of_building(int(b.site)))
	sim.company(0).ledger.inject(100000.0)
	for branch in ["strandbar", "kneipe", "disco"]:
		var vr: Dictionary = sim.biz.found(0, branch, "Freizeitangebot", {"stadt": "0"})
		print("FREIZEIT ", branch, " ", vr)
		if vr.ok:
			var vb: Dictionary = sim.biz.get_b(str(vr.ref))
			var vw := sim.personnel.spawn_available("allround")
			sim.personnel.hire(0, vw)
			sim.biz.assign(0, vw.id, str(vb.id))
			sim.stock.add("fassgetraenk", 20, "C0", int(vb.site), "Testware", sim.game_min)
	var w := sim.personnel.spawn_available("allround")
	sim.personnel.hire(0, w)
	print("PERSONAL ", sim.biz.assign(0, w.id, str(b.id)))
	var first: Dictionary = sim.tourism.book(str(b.id), 3, 2, 500.0)
	print("BUCHUNG ", first)
	for p in sim.citizens.people:
		if sim.citizens.home_town(p) == 1:
			sim.population.pay_in("X0", [[p, 250.0]])
			var inland: Dictionary = sim.tourism.book(str(b.id), 1, 1, 160.0, int(p.id))
			print("BINNENREISE ", inland)
			break
	if not first.ok:
		quit(2)
		return
	var id := str(first.ref)
	for d in range(int(first.arrival_day), int(first.departure_day) + 1):
		sim.game_min = GameCalendar.day_start(d)
		sim.tourism.on_day(d)
		print("REISETAG ", d, " ", sim.tourism.trips[id].status, " GELD ", sim.economy.accounts[id])
	print("STATS ", sim.tourism.summary(0), " BALANCE ", sim.economy.accounts[id])
	if sim.tourism.trips[id].status != "abgereist" or absf(float(sim.economy.accounts[id])) > 0.01:
		quit(3)
		return
	quit(0)
