extends SceneTree
## Reale Regel-KI und oeffentliche Baukette ueber mehrere Spieltage beobachten.
## Godot --headless --path . -s tests/probe_utility_decisions.gd -- --days=24 --seed=21

func _initialize() -> void:
	var days := 24
	var seed_value := 21
	var town_count := 4
	var map_size := Catalog.MAP_SIZE
	var skip_wild := false
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--days="):
			days = int(str(arg).trim_prefix("--days="))
		elif str(arg).begins_with("--seed="):
			seed_value = int(str(arg).trim_prefix("--seed="))
		elif str(arg).begins_with("--towns="):
			town_count = int(str(arg).trim_prefix("--towns="))
		elif str(arg).begins_with("--map="):
			map_size = int(str(arg).trim_prefix("--map="))
		elif str(arg) == "--no-wild":
			skip_wild = true
	var players: Array = []
	for k in town_count:
		players.append({"player_name": "Spieler %d" % k, "company_name": "Firma %d" % k,
			"color": Catalog.COMPANY_COLORS[k], "avatar_style": k, "personality": Catalog.PERSONALITIES.keys()[k]})
	RegionGenerator.neubeginn = false
	RegionGenerator.wildnis = false
	var sim := Simulation.new()
	sim.world_mode = "region"
	sim.start_profile = "unternehmer"
	sim.setup(seed_value, players, map_size, 0.5)
	var plant: Dictionary = sim.city.building(sim.plant.building)
	print("ANLAGE seed=%d id=%d typ=%s sprite=%s feld=%s" % [seed_value, sim.plant.building, plant.type, plant.sprite, str(Vector2i(plant.x, plant.y))])
	var last_day := -1
	while GameCalendar.day_of(sim.game_min) < days:
		var today := GameCalendar.day_of(sim.game_min)
		if today != last_day:
			last_day = today
			for k in sim.towns.count():
				var mayor: Mayor = sim.towns.mayor(k)
				var ind: Dictionary = mayor.indicators()
				var chosen: Dictionary = MayorBrain.decide(ind)
				for action in chosen.actions:
					var result: Dictionary = mayor.execute(action)
					if str(action.action) in ["stromtrasse_bauen", "versorgungsleitung_bauen", "kommunal_bauen", "stromstoerung_priorisieren", "approve_procurement", "expand_depot"]:
						print("TAG %d ORT %d %s %s -> %s %s" % [today, k, action.action, str(action.get("option", action.get("typ", action.get("order_id", "")))), str(result.get("ok", false)), str(result.get("msg", "")).left(125)])
			if today % 4 == 0:
				var connected: Array = []
				var pipes: Array = []
				for k in sim.towns.count():
					connected.append(sim.grid.net.connected(k))
					pipes.append([sim.water.main_cells(k, "wasser").size(), sim.water.main_cells(k, "abwasser").size()])
				print("STAND %d strom=%s trassen=%d geplant=%d leitungen=%s baustellen=%d" % [today, str(connected), sim.grid.net.edges.size(), sim.grid.net.planned.size(), str(pipes), sim.construction.public.size()])
				for id in sim.grid.net.planned:
					var owner := int(str(id).trim_prefix("T").get_slice("P", 0)) if str(id).begins_with("T") else 0
					var project: Dictionary = sim.towns.mayor(owner).projects.get(str(id), {})
					var work: Dictionary = sim.construction.public.get(str(id), {})
					var depot: CityDepot = sim.towns.depot(owner)
					var reserved: Dictionary = depot.project_res.get(str(id), {})
					var orders: Array = depot.orders.values().filter(func(o): return str(o.item) in ["stahl", "beton"])
					var order_lines: Array = []
					for order in orders:
						var contract: Contract = sim.contracts.get(str(order.get("contract", "")))
						order_lines.append("%s %s %d %s gut=%s an=%s transport=%s" % [order.id, order.item, order.qty, order.status,
							str(order.get("qty_received", "")), str(order.get("arrived", "")), contract.status if contract != null else "-"])
					print("  TRASSE %s ort=%d status=%s bau=%s rest=%s wartet=%s material=%s" % [id, owner,
						str(project.get("status", "-")), str(work.get("status", "-")), str(work.get("days_left", "-")),
						str(work.get("waiting", "-")), str(project.get("material", {}))])
					print("    LAGER personal=%d kapazitaet=%d reserviert=%s bestand=%s bestellungen=%s" % [depot.roster().size(), depot.dock_capacity(), str(reserved.get("reserved", {})),
						str({"stahl": depot.stock_of("stahl"), "beton": depot.stock_of("beton")}),
						str(order_lines)])
		sim.step(0.5)
	var end_connections: Array = []
	for k in sim.towns.count():
		end_connections.append(sim.grid.net.connected(k))
	print("ENDE tag=%d strom=%s trassen=%d geplant=%d wasserprojekte=%d" % [days, str(end_connections), sim.grid.net.edges.size(), sim.grid.net.planned.size(), sim.water.main_projects.size()])
	if skip_wild:
		quit()
		return
	RegionGenerator.neubeginn = true
	RegionGenerator.wildnis = true
	var wild := Simulation.new()
	wild.neubeginn = true
	wild.wildnis = true
	wild.world_mode = "region"
	wild.start_profile = "unternehmer"
	wild.setup(seed_value, players, map_size, 0.5)
	var wb: Dictionary = wild.city.building(wild.plant.building)
	print("WILDNIS kraftwerk=%s sprite=%s feld=%s depot=%d anschluesse=%d" % [wb.type, wb.sprite, str(Vector2i(wb.x, wb.y)), wild.city_depot.building, wild.grid.net.edges.size()])
	quit()
