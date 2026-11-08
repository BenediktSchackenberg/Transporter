extends SceneTree
## Diagnose: Linienschiff nach Ankunft - Zustand im Hafen und in der Schiffsansicht.
func _initialize() -> void:
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(21, t.players(4))
	var cv := CityView.new()
	root.add_child(cv)
	cv.build(s)
	var H: Harbor = s.towns.harbor(0)
	for i in 30:
		s.step(0.1)
	H._staff_day()
	H._staff_day()
	for it in ["mehl", "saatgut", "stahl"]:
		H.ship_in("stock", "", it, 400)
	H._arrive(GameCalendar.day_of(s.game_min))
	print("Arbeiter ", H.workers().size(), " Posten ", H.queue.size(), " Leistung ", H.rate_per_min())
	print("Schiff: ", H.ship.get("name"), " Status ", H.ship.get("status"), " Tag ", H.ship.get("day"), " Spielminute ", s.game_min, " instant ", H.instant)
	cv.ship_view.update_view(0.1)
	var info: Dictionary = cv.ship_view._ports[0]
	var node = info.liner
	print("Liner sichtbar ", node.visible, " Welt ", node.world / 32.0, " Liegeplatz ", (info.berth as Vector2) / 32.0, " Rand ", (info.edge as Vector2) / 32.0)
	for i in 700:
		s.step(0.1)
	cv.ship_view.update_view(0.1)
	print("nach Schritten: Spielminute %.1f Tag %d, Schiff Tag %s Status %s, angelegt %s, Grund '%s', Liner %s bei %s" % [s.game_min, GameCalendar.day_of(s.game_min), str(H.ship.get("day")), str(H.ship.get("status")), str(H.docked(s.game_min)), H.idle_reason(), str(node.visible), str(node.world / 32.0)])
	print("day_start(0)=%.1f day_start(1)=%.1f" % [GameCalendar.day_start(0), GameCalendar.day_start(1)])
	quit()
