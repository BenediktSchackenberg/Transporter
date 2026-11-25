extends SceneTree
## Warum hat ein Betrieb keinen Anschluss? Je blockiertem Betrieb: Gebaeude, Strassenfeld davor, Stadt, Netze an diesem Feld,
## naechstes Leitungsfeld je Art und ob das Strassenfeld ueberhaupt Strasse ist.
##   godot --headless --path . -s tests/probe_biz_utilities.gd -- <spielstand.json> [tage vorher simulieren]
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var W = s.water
	var days := int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 0
	var end := s.game_min + days * GameCalendar.day_game_min
	while s.game_min < end:
		s.step(1.0)
	if days > 0:
		print("nach %d Spieltagen" % days)
	for k in s.towns.count():
		var M: Mayor = s.towns.mayor(k)
		var links: Array = M.projects.values().filter(func(p): return str(p.get("ref", "")) == "anschluss").map(func(p): return "%s %s %d Felder" % [p.id, p.status, (p.road_plan as Array).size()])
		print("Stadt %d: road_link %s | Anschlussprojekte %s" % [k, JSON.stringify(s.eko.settle.road_link(k)), str(links)])
		for art in ["wasser", "abwasser"]:
			print("   Leitungsoptionen %s: %s" % [art, str(W.main_options(k, art).map(func(o): return "%s %d Felder" % [o.get("id", "?"), (o.get("cells", []) as Array).size()]))])
	var list: Array = s.biz.items.values()
	print("Staedte: %s" % str(s.city.towns.map(func(t): return [t.id, t.get("name", ""), t.center])))
	print("Betriebe: %d" % list.size())
	for b in list:
		var bl: Array = b.get("blockers", [])
		var bid := int(b.site)
		var bd: Dictionary = s.city.building(bid)
		var k: int = s.city.town_of_building(bid)
		var road := Vector2i(bd.get("road", Vector2i(-1, -1)))
		var wmain: Dictionary = W.main_cells(k, "wasser")
		var smain: Dictionary = W.main_cells(k, "abwasser")
		print("%s %s (Firma %d, Stadt %d) Gebaeude %d bei %s, Strassenfeld %s (Strasse: %s, Stadt des Feldes %d)" % [b.id, b.get("branch", "?"), int(b.owner), k, bid,
			"%d,%d town=%s" % [int(bd.get("x", -1)), int(bd.get("y", -1)), str(bd.get("town", "-"))], str(road), s.city.is_road(road), s.city.town_of(road)])
		print("   blockiert: %s" % JSON.stringify(bl))
		print("   Wasser: Leitung am Feld %s, Druck %s, naechstes Leitungsfeld %s | Abwasser: Leitung am Feld %s, naechstes %s | Quellen %s" % [
			wmain.has(W._cell_key(road)), W.building_on_net(k, bid), _nearest(W, wmain, road), smain.has(W._cell_key(road)), _nearest(W, smain, road), str(W.sources_of(k))])
		print("   Strom verteilt: %s | Parzelle: %s" % [s.grid.net.distributed(k, bid), JSON.stringify(s.parcels.of_building(bid).get("erschliessung", {}))])
	quit()


func _nearest(W, cells: Dictionary, from: Vector2i) -> String:
	var best := -1
	var at := ""
	for key in cells:
		var c: Vector2i = key if key is Vector2i else Vector2i(int(str(key).split(":")[0]), int(str(key).split(":")[1]))
		var dd: int = absi(c.x - from.x) + absi(c.y - from.y)
		if best < 0 or dd < best:
			best = dd
			at = str(c)
	return "%s (%d Felder)" % [at, best] if best >= 0 else "keins"
