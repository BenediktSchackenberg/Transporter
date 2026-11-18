extends SceneTree
## Messung 18.11.: werden die wegen fehlendem Anlieferort stornierten Importe wieder aufgenommen und geliefert?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var D: CityDepot = s.towns.depot(0)
	var count := func(st): return D.orders.values().filter(func(o): return str(o.status) == st).size()
	print("vorher: abgelehnt ", count.call("abgelehnt"), " bestellt ", count.call("bestellt"))
	var day := GameCalendar.day_of(s.game_min)
	for i in 6:
		D.on_day(day + 1 + i)
	var st := {}
	for o in D.orders.values():
		st[str(o.status)] = int(st.get(str(o.status), 0)) + 1
	print("nach 6 Tagen: ", st)
	quit()
