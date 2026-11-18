extends SceneTree
## Messung 18.11.: woran scheitert das Rathaus von Liorufer an jeder Stelle?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var site: Dictionary = s.eko.homes.sites.get("BS1", {})
	var p: Dictionary = s.parcels.parcel(str(site.parcel))
	var r := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
	print("Grundstueck ", site.parcel, " ", r, " townhall ", CityGenerator.TYPES["townhall"].slice(0, 3), " freight_shed ", CityGenerator.TYPES["freight_shed"].slice(0, 3))
	var C: CityData = s.city
	var why := {}
	var ctr := r.get_center()
	for dy in range(-14, 15, 2):
		for dx in range(-14, 15, 2):
			var pos := ctr + Vector2i(dx, dy) - Vector2i(2, 2)
			var reason := "ok"
			for y in range(pos.y, pos.y + 4):
				for x in range(pos.x, pos.x + 4):
					var q := Vector2i(x, y)
					if not C.inside(q): reason = "aussen"
					elif C.building_at[C.idx(q)] != -1: reason = "Gebaeude"
					elif C.g(q) == CityData.G.ROAD: reason = "Strasse"
					elif C.g(q) == CityData.G.WATER: reason = "Wasser"
					elif C.g(q) == CityData.G.RAIL: reason = "Gleis"
					elif s.access.reserved(q): reason = "reserviert"
			why[reason] = int(why.get(reason, 0)) + 1
	print("Gruende ueber 225 Proben: ", why)
	quit()
