extends SceneTree
## Masse genau: wie viel Token stecken in meinem steinbauten-Feld der Beobachtung?
func _initialize() -> void:
	var players: Array = []
	for i in 2:
		players.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Color.WHITE, "avatar_style": i, "personality": "kostenoptimierer"})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(4242, players, 128, 0.5)
	s.estate.permits_enabled = false
	s.estate.auctions_enabled = false
	s.prod.instant_build = true
	s.mining.enabled = false
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	var obs: Dictionary = ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var with_stone: String = ctl.user_prompt(obs)
	var stone_field: String = JSON.stringify(obs.get("steinbauten", {}))
	obs.erase("steinbauten")
	var without_stone: String = ctl.user_prompt(obs)
	print("mit steinbauten: %d Zeichen = %d Token" % [with_stone.length(), with_stone.length() / 4])
	print("ohne steinbauten: %d Zeichen = %d Token" % [without_stone.length(), without_stone.length() / 4])
	print("Delta: %d Zeichen = %d Token" % [with_stone.length() - without_stone.length(), (with_stone.length() - without_stone.length()) / 4])
	print("Feldinhalt: ", stone_field)
	ctl.free()
	quit(0)
