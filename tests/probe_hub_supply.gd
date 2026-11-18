extends SceneTree
## Messung 18.11.: warum bekommt das Grosslager im Spielstand keinen Kies-Nachschub?
func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://saves/quicksave.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var H: CentralHub = s.hub
	print("enabled ", H.enabled, " loc ", H.loc, " frei ", H.free_capacity(), " Kasse L0 ", s.economy.accounts.get(CentralHub.ACCT, 0.0))
	for item in ["kies", "holz", "ziegel", "beton"]:
		print(item, ": Lager ", s.stock.qty(item, CentralHub.ACCT, H.loc), " unterwegs ", H.incoming.get(item, 0), " Ziel ", H.GOODS[item].t, " Produzenten ", H._from_producers(item))
	print("Kartenrand-Strassen: ", s.fleet._edges.size(), " Zulieferer unterwegs: ", s.fleet.vehicles.filter(func(v): return v.kind == "zulieferer").size())
	print("Zulieferungs-Deals: ", H.deals.values().filter(func(x): return str(x.kind) == "zulieferung").map(func(x): return "%s %s %s" % [x.id, x.item, x.status]))
	var hb: Dictionary = s.city.building(H.loc)
	if not s.fleet._edges.is_empty():
		var m := Mover.new()
		m.pos = s.city.tile_center(s.fleet._edges[0])
		print("Weg Rand->Grosslager: ", s.route(m, hb.road), " Rand ", s.fleet._edges[0], " Lager-Zufahrt ", hb.road)
	H.on_day(GameCalendar.day_of(s.game_min) + 1)
	print("nach on_day: Zulieferer ", s.fleet.vehicles.filter(func(v): return v.kind == "zulieferer").size(), " unterwegs kies ", H.incoming.get("kies", 0))
	quit()
