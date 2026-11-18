extends SceneTree
## Messung 18.11.: kommt der Kies-Liefer-Lkw im Spielstand an? Position und Wartezeit verfolgen.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var H: CentralHub = s.hub
	H.on_day(GameCalendar.day_of(s.game_min) + 1)
	var trucks: Array = s.fleet.vehicles.filter(func(v): return v.kind == "zulieferer")
	print("Lkw: ", trucks.size())
	if trucks.is_empty():
		quit()
		return
	var v: Dictionary = trucks.filter(func(t): return str(t.label).contains("Kies"))[0] if trucks.any(func(t): return str(t.label).contains("Kies")) else trucks[0]
	var m: Mover = v.mover
	print("Start ", m.tile(), " Ziel ", m.goal, " Wegfelder ", m.path.size())
	for i in 9000:
		s.step(0.1)
		if i == 8000:
			var nt := m.next_tile()
			print("naechstes Feld ", nt, " Schranke ", s.nav.barriers.has(nt), " gesperrt ", s.nav.is_blocked_road(nt), " Ampel/blockiert ", s._is_blocked(m))
			var cur = m
			for hop in 8:
				s._is_blocked(cur)
				var nxt = s.collisions.last_blocker
				if nxt == null:
					print("  Kette Ende bei Feld ", cur.tile(), " naechstes ", cur.next_tile() if not cur.arrived() else cur.tile(), " Schranke ", s.nav.barriers.has(cur.next_tile()) if not cur.arrived() else false, " Ampel? Kreuzung ", s.city.road_mask(cur.next_tile()) if not cur.arrived() else -1)
					break
				print("  ", hop, ": ", s._desc.get(nxt, "?"), " Feld ", nxt.tile(), " Richtung ", nxt.heading.snapped(Vector2(0.1, 0.1)), " angekommen ", nxt.arrived(), " wait %.0f" % nxt.wait_time, " naechstes ", nxt.next_tile() if not nxt.arrived() else nxt.tile(), (" Zustand " + nxt.state) if nxt is FleetVehicle else "")
				if nxt == m:
					print("  -> Kreis!")
					break
				cur = nxt
			var o = s.collisions.last_blocker
			if false:
				print("Blocker: Feld ", o.tile(), " angekommen ", o.arrived(), " wait ", o.wait_time, " Richtung ", o.heading, " Wrack ", o.wreck_until > s.sim_time, " Typ ", (o as Object).get_class(), " ", s._desc.get(o, "?"), " Ziel ", o.goal, " Abstand ", o.pos.distance_to(m.pos))
				if o is FleetVehicle:
					print("   Zustand ", o.state)
		if i % 200 == 0:
			print("t=%d s Feld %s Rest %d wait %.1f Phase %s Kies im Lager %d" % [i / 10, str(m.tile()), m.path.size() - m.path_i, m.wait_time, v.phase, s.stock.qty("kies", CentralHub.ACCT, H.loc)])
		if s.stock.qty("kies", CentralHub.ACCT, H.loc) > 0:
			print("angekommen nach %d s" % (i / 10))
			break
	print("Ende: Kies im Lager ", s.stock.qty("kies", CentralHub.ACCT, H.loc), " stock_of ", H.stock_of("kies"), " Deals ", H.deals.values().filter(func(x): return str(x.kind) == "zulieferung" and int(x.day) >= 0).map(func(x): return "%s %s %s" % [x.id, x.item, x.status]).slice(-4))
	print("Lkw-Ladungen: ", trucks.map(func(t): return str(t.get("deal", "")) + " " + str(t.label)))
	quit()
