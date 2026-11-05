extends SceneTree
## Messung (kein Pass/Fail): Rivalitaet (Auftrag 12) im Regelspiel. Vier Regel-KI-Firmen (je eine Persoenlichkeit),
## Gespraechsregie an, Regel-Buergermeister alle 2 Spieltage. Je 10 Tage: Spannungen, Vorfaelle, Zeilen nach Richtung,
## Blockaden, Ruf und Kasse; am Ende die letzten Dialogzeilen.
##   Godot_console.exe --headless --path . -s tests/probe_rivalry.gd -- --days=40 [--talk=off]
func _initialize() -> void:
	var days := 40
	var talk := true
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a) == "--talk=off":
			talk = false
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	s.talk.enabled = talk
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var last_day := -1
	var mayor_day := -1
	var step := 0
	var blocks := 0
	var seen_blocks := {}
	while GameCalendar.day_of(s.game_min) < days:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
		step += 1
		for b in s.rivalry.blockades:
			var k := "%d:%s" % [int(b.by), str(b.placed)]
			if not seen_blocks.has(k):
				seen_blocks[k] = true
				blocks += 1
		var day: int = GameCalendar.day_of(s.game_min)
		if day != mayor_day and day % 2 == 0:
			mayor_day = day
			for a in MayorBrain.decide(s.mayor.indicators()).actions:
				s.mayor.execute(a)
		if day != last_day and day % 10 == 0:
			last_day = day
			var arts := {}
			for i in s.rivalry.incidents:
				arts[i.art] = int(arts.get(i.art, 0)) + 1
			var ms := s.rivalry.mayor_summary()
			print("== Tag %d  Unruhe %.1f  Paare %s  Vorfälle %s  Zeilen %s  Blockaden %d" % [day, float(ms.unruhe),
				str(ms.paare.map(func(p): return "%s:%d" % [str(p.firmen), int(p.spannung)])), str(arts), str(s.talk.stats), blocks])
			for c in s.companies:
				print("  %s %-16s Ruf %5.1f  Kasse %8d  Gewinn %8d" % [c.company_name, c.personality, c.reputation, int(c.ledger.cash), int(c.ledger.profit())])
	print("-- letzte Zeilen --")
	for l in s.talk.lines.slice(-12):
		print("  T%d %s -> %s [%s/%s%s] %s" % [GameCalendar.day_of(float(l.t)), s.company(int(l.from)).company_name, s.company(int(l.to)).company_name,
			l.art, l.richtung, "" if l.ok else " gescheitert", l.text])
	print("Geld erhalten: %.2f" % s.economy.conservation_error())
	quit()
