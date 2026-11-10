extends SceneTree
## Auftrag 20: Arbeitsmarkt je Stadt fuer kommunales Personal (Arbeitslose nach Bildung, Kurse) und Besetzung der Einrichtungen.
## Aufruf: Godot --headless --path . -s tests/probe_municipal.gd -- --days=4

func _init() -> void:
	var days := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = int(a.substr(7))
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i],
			"avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	for i in int(days * 600):
		s.step(0.1)
		if i % 600 == 0:
			for f in s.rescue.hospitals():
				if s.rescue.beds(f) > 0 and not has_meta("beds"):
					set_meta("beds", true)
					print("Krankenhaus betriebsbereit ab Tag ", GameCalendar.day_of(s.game_min))
	var day: int = GameCalendar.day_of(s.game_min)
	for t in s.towns.list:
		var k := int(t.id)
		var pop := 0
		var jobless := [0, 0, 0, 0]
		var course := 0
		for p in s.citizens.people:
			if s.citizens.home_town(p) != k:
				continue
			pop += 1
			if p.employer == "":
				if p.has("course_until"):
					course += 1
				elif not PublicSafety.absent(p, day):
					jobless[clampi(int(p.get("education", 0)), 0, 3)] += 1
		print("Stadt %d %s: Buerger %d, arbeitslos nach Bildung 0-3 %s, im Kurs %d" % [k, t.name, pop, str(jobless), course])
		for f in s.municipal.of_town(k):
			print("   ", f.name, " Personal ", s.municipal.staff_count(f.id), " Bedarf ", f.staff_need)
	print("Rettungsdienst: ", s.rescue.summary(), " Notfaelle-Statistik: ", s.rescue.stats)
	print("Feuerwehr: ", s.fire.summary())
	for m in s.rescue.missions.values():
		print("  Notfall %s Tag %d Stadt %d Hilfsfrist %.1f Ziel %s" % [m.id, GameCalendar.day_of(float(m.alarm)), int(m.town), float(m.get("hilfsfrist", -1)), m.hospital if m.hospital != "" else "Arztpraxis"])
	for f in s.rescue.hospitals():
		print("Krankenhaus ", f.name, " Betten ", s.rescue.beds(f), "/", f.capacity, " Personal ", s.municipal.staff_count(f.id), " Bedarf ", f.staff_need)
	quit()
