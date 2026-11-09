extends SceneTree
## Wie schnell wird die Regionskarte bebaut? Zaehlt alle 10 Spieltage Grundstuecke nach Zustand (ohne LLM-Firmen).
## Aufruf: --headless --path . -s tests/probe_buildout.gd -- --days=90
func _init() -> void:
	var days := 90
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.split("=")[1])
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(29912, ps, Catalog.MAP_SIZE, 0.5)
	var t0 := Time.get_ticks_msec()
	for d in days + 1:
		if d % 10 == 0:
			var st := {}
			var area := {}
			for p in s.parcels.items.values():
				var k := str(p.state)
				st[k] = int(st.get(k, 0)) + 1
				area[k] = int(area.get(k, 0)) + int(p.area)
			print("Tag %3d (%.0f s): Grundstuecke %s | Flaeche %s | Gebaeude %d | Betriebe %d" % [d, (Time.get_ticks_msec() - t0) / 1000.0, st, area, s.city.buildings.size(), s.biz.items.size()])
		for i in 120:
			s.step(0.5)
	quit()
