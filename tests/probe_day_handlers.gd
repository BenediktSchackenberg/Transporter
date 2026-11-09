extends SceneTree
## Welche Empfaenger von day_changed kosten beim Tageswechsel die Zeit? Misst jeden Empfaenger einzeln (Tag 40).
## Aufruf: --headless --path . -s tests/probe_day_handlers.gd -- --days=40
func _init() -> void:
	var days := 40
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
	while s.game_min < days * 120.0 - 1.0:
		s.step(0.5)
	var conns: Array = s.day_changed.get_connections()
	for c in conns:
		s.day_changed.disconnect(c.callable)
	while s.game_min < days * 120.0 + 1.0:   # Tageswechsel ohne Empfaenger durchlaufen
		s.step(0.5)
	var day := GameCalendar.day_of(s.game_min)
	var res: Array = []
	var t_all := Time.get_ticks_usec()
	for c in conns:
		var cb: Callable = c.callable
		var t := Time.get_ticks_usec()
		cb.call(day)
		var obj = cb.get_object()
		res.append([(Time.get_ticks_usec() - t) / 1000.0, "%s.%s" % [obj.get_script().resource_path.get_file() if obj and obj.get_script() else str(obj), cb.get_method()]])
	print("Tag %d: %d Empfaenger, zusammen %.1f ms" % [day, conns.size(), (Time.get_ticks_usec() - t_all) / 1000.0])
	res.sort_custom(func(a, b): return a[0] > b[0])
	for r in res.slice(0, 15):
		print("  %7.1f ms  %s" % r)
	# Teilschritte der teuersten Empfaenger (einmal je Objekt, Methoden ohne Argument bzw. mit Tag)
	var subs := {"city_depot.gd": ["_crew_day:d", "_consume:d", "_propose:d", "_decide:d", "_advance_orders:d", "_inspect:d", "_top_up_projects", "_prune:d"]}
	for extra in OS.get_cmdline_user_args():
		if extra.begins_with("--sub="):
			var kv := extra.trim_prefix("--sub=").split(":", true, 1)
			subs[kv[0]] = kv[1].split(",")
	var seen := {}
	for c in conns:
		var obj = c.callable.get_object()
		var f: String = obj.get_script().resource_path.get_file() if obj and obj.get_script() else ""
		if not subs.has(f) or seen.has(f):
			continue
		seen[f] = true
		for m in subs[f]:
			var parts: PackedStringArray = str(m).split(":")
			var t := Time.get_ticks_usec()
			if parts.size() > 1:
				obj.call(parts[0], day)
			else:
				obj.call(parts[0])
			print("    %s.%s %.1f ms" % [f, parts[0], (Time.get_ticks_usec() - t) / 1000.0])
	quit()
