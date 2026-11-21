extends SceneTree
## Ein friedlicher KI-Spieler soll beim Angriff sofort reagieren, bevor der
## Angreifer die Stadt erreicht. Gewinntrend und Alarm muessen sichtbar sein.

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FEHLER: ", label)

func _initialize() -> void:
	var players := []
	for i in 2:
		players.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i,
			"color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var sim := Simulation.new()
	sim.world_mode = "region"
	sim.start_profile = "unternehmer"
	sim.setup(4242, players, 256, 0.5)
	var world: EkoWorld = sim.eko
	var attack_worker := Worker.new()
	attack_worker.id = "TEST_ATTACK"
	attack_worker.name = "Angreifer"
	attack_worker.employer = 0
	attack_worker.pos = sim.city.tile_center(sim.towns.list[0].center)
	sim.personnel.workers[attack_worker.id] = attack_worker
	for i in 2:
		var guard := Worker.new()
		guard.id = "TEST_GUARD_%d" % i
		guard.name = "Wache %d" % i
		guard.employer = 1
		guard.pos = sim.city.tile_center(sim.towns.list[1].center)
		sim.personnel.workers[guard.id] = guard
	world.arms.designs["Testschwert"] = {"typ": "nahkampf", "schaden": 12}
	world.arms.arsenal["0"] = [{"design": "Testschwert"}]
	check(bool(world.conflict.action({}, 0, {"action": "set_city_strategy", "haltung": "krieg"}).ok), "Angreifer waehlt Krieg")
	check(bool(world.conflict.action({}, 0, {"action": "mobilize_worker", "worker_id": attack_worker.id, "weapon": "Testschwert"}).ok), "Angreifer mobilisiert Bewaffneten")
	var result: Dictionary = world.conflict.action({}, 0, {"action": "order_assault", "target": 1})
	check(bool(result.get("ok", false)), "Angriff auf die Nachbarstadt wird gestartet")
	if bool(result.get("ok", false)):
		var guards: Array = world.conflict.troops.values().filter(func(t): return int(t.cid) == 1 and str(t.mode) == "schutz")
		check(guards.size() >= 1, "Friedlicher Spieler mobilisiert vor Ankunft eigene Wachen")
		check(str(world.conflict.strategy(1).haltung) == "frieden", "Selbstverteidigung erzwingt keinen Krieg")
		world.join("Verteidiger")
		world.beings.Verteidiger.firma = 1
		check(int(world.urgency(world.beings.Verteidiger).prioritaet) == 2, "Unternehmer erhaelt sofort einen Angriffsalarm")
		check(world.firm_obs(world.beings.Verteidiger).finanzlage.has("letzte_7_tage"), "Unternehmer sieht den Gewinntrend")
		var mayors: Array = world.adopt_mayors()
		var defender_mayor := {}
		for name in mayors:
			if int(world.beings[name].amt) == 1:
				defender_mayor = world.beings[name]
				break
		check(not defender_mayor.is_empty() and int(world.urgency(defender_mayor).prioritaet) == 2, "Buergermeister erhaelt den Angriffsalarm")
	print("KI-Verteidigung: %d Prüfungen, %d Fehler" % [checks, failures])
	quit(1 if failures > 0 else 0)
