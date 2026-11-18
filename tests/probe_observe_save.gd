extends SceneTree
## Messung 18.11.: Kosten von observe und Teilen (Spielstand als Argument).
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var E: EkoWorld = s.eko
	for name in E.beings:
		var B: Dictionary = E.beings[name]
		var line := ""
		for rep in 3:
			var t0 := Time.get_ticks_usec()
			E.observe(name)
			line += "%.0f " % ((Time.get_ticks_usec() - t0) / 1000.0)
		var parts := {"next_steps": func(): return E.next_steps(B), "firm_obs": func(): return E.firm_obs(B), "office_obs": func(): return E.office_obs(B), "home_obs": func(): return E._home_obs(B)}
		var pl := ""
		for k in parts:
			var ta := Time.get_ticks_usec()
			parts[k].call()
			pl += "%s %.0f · " % [k, (Time.get_ticks_usec() - ta) / 1000.0]
		print("%s: observe ms %s | %s" % [name, line, pl])
	var step_max := 0.0
	var tot := 0.0
	for i in 600:
		var t1 := Time.get_ticks_usec()
		s.step(0.1)
		var dt := (Time.get_ticks_usec() - t1) / 1000.0
		tot += dt
		step_max = maxf(step_max, dt)
	print("600 Sim-Schritte: %.0f ms gesamt, Mittel %.1f ms, max %.0f ms" % [tot, tot / 600.0, step_max])
	var td := Time.get_ticks_usec()
	s._on_day_probe() if s.has_method("_on_day_probe") else null
	var day := GameCalendar.day_of(s.game_min)
	var tday := Time.get_ticks_usec()
	s.day_changed.emit(day + 1)
	print("Tageswechsel: %.0f ms" % ((Time.get_ticks_usec() - tday) / 1000.0))
	quit()
