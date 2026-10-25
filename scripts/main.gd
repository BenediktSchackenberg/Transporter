extends Node
## Einstieg: Setup-Menue -> Partie -> Endauswertung. Zusaetzlich ein Autotest-Modus fuer verkuerzte Testpartien:
##   Godot.exe --path . -- --autotest --players=4 --seconds=60 --speed=16 [--fault=0.1] [--interval=3]
##     [--provider=openai --base-url=http://127.0.0.1:8765/v1 --model=mock --api-key-env=VAR]
##     [--screenshot=user://shot.png --shot-at=20] [--headless-ok]
## Exit-Code 0 = Partie endete automatisch, Gewinner korrekt, Bilanzidentitaet gehalten.

var menu: SetupMenu
var session: GameSession
var args := {}
var _shot_done := false


func _ready() -> void:
	get_window().title = "Pixel Transport Rivals"
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.has("autotest") and args.has("load"):
		print("AUTOTEST: lade Spielstand ", GameSession.SAVE_PATH)
		_load()
	elif args.has("autotest"):
		_start_autotest()
	else:
		_show_menu()
		if args.has("screenshot"):
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(args["screenshot"])
			get_tree().quit()


func _show_menu() -> void:
	if session:
		session.queue_free()
		session = null
	menu = SetupMenu.new()
	add_child(menu)
	menu.start_requested.connect(_start)
	menu.load_requested.connect(func(_p): _load())


func _start(cfg: Dictionary, loaded: Dictionary = {}) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if session:
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	session.start(cfg, loaded)
	if args.has("no-residents"):
		session.sim.residents.enabled = false   # Diagnose: Vergleich ohne Kundenanfragen
	if args.has("autotest"):
		_apply_test_overrides(session.sim)
	session.menu_requested.connect(_show_menu)
	session.load_requested.connect(_load)
	if args.has("autotest"):
		session.finished.connect(_autotest_finished)


## Sichtpruefung per Autotest: --wx=rain|storm|hot|snow|fog|wind  --hour=22 (Tageszeit)
func _apply_test_overrides(sim: Simulation) -> void:
	if str(args.get("scenario", "")) == "yard":
		_scenario_yard(sim)
	if args.has("hour"):
		sim.game_min = (float(args.hour) - Catalog.START_HOUR) * 60.0
	if args.has("wx"):
		var presets := {"rain": [11.0, 63, 1.2, 25.0, 0.0], "storm": [11.0, 65, 3.0, 80.0, 0.0], "hot": [31.0, 0, 0.0, 15.0, 0.0],
			"snow": [-1.0, 73, 0.4, 20.0, 0.5], "fog": [6.0, 45, 0.0, 8.0, 0.0], "wind": [14.0, 3, 0.0, 75.0, 0.0], "clear": [16.0, 0, 0.0, 10.0, 0.0]}
		var p: Array = presets.get(str(args.wx), presets.clear)
		var data := {"current": {"time": "2026-10-25T12:00", "interval": 900, "temperature_2m": p[0], "weather_code": p[1], "precipitation": p[2] / 4.0,
			"wind_speed_10m": 12.0, "wind_gusts_10m": p[3], "snowfall": p[4], "cloud_cover": 80, "is_day": 1}}
		sim.apply_weather(sim.wx.parse_forecast(data), Time.get_unix_time_from_system())


## Sichtpruefung: Unternehmen 0 baut einen Betriebshof aus, Arbeiter bauen, ein Fahrzeug wird repariert.
func _scenario_yard(sim: Simulation) -> void:
	var c: Company = sim.company(0)
	c.ledger.inject(60000.0)
	var plot: Dictionary = sim.estate.plot_of(0)[0]
	var ids: Array = []
	for typ in ["lager", "werkstatt", "laderampe", "pausenraum", "stellplatz"]:
		var sugg: Dictionary = sim.estate.suggestions(0, plot.id)
		if not sugg.has(typ):
			continue
		var s: Array = sugg[typ]
		var r := sim.executor.execute(0, {"action": "place_building", "plot_id": plot.id, "typ": typ, "x": s[0], "y": s[1], "rot": s[2], "bau": "eigen"})
		if r.ok:
			ids.append(r.building_id)
	for i in ids.size():
		var f: Dictionary = sim.estate.facilities[ids[i]]
		f.mat = f.mat_needed
		if i < 2:   # die ersten sind fertig, die uebrigen im Bau
			f.status = "fertig"
			f.progress = 1.0
		else:
			f.progress = 0.35
	sim.estate._refresh_company(0)
	var workers: Array = sim.personnel.employed(0).filter(func(w): return w.role == "worker" and w.vehicle_id < 0)
	var wids: Array = workers.map(func(w): return w.id)
	for i in range(2, ids.size()):
		if not wids.is_empty():
			print("SZENARIO Bau: ", sim.executor.execute(0, {"action": "assign_building_staff", "building_id": ids[i], "worker_ids": [wids.pop_back()]}).msg)
	var v: FleetVehicle = sim.company_vehicles(0)[0]
	sim.break_vehicle(v, "Test")
	if not wids.is_empty():
		print("SZENARIO Reparatur: ", sim.executor.execute(0, {"action": "repair_vehicle", "vehicle_id": v.id, "worker_id": wids.pop_back()}).msg)


func _load() -> void:
	var d := GameSession.read_save()
	if d.is_empty():
		return
	var cfg: Dictionary = d.cfg
	for p in cfg.players:
		p["api_key"] = CredentialStore.read_key("slot%d" % int(p.slot)) if p.provider in ["openai", "ionos"] and p.get("save_key", false) else ""
	_start(cfg, d)


func _start_autotest() -> void:
	var n := int(args.get("players", "4"))
	var players: Array = []
	var personalities: Array = Catalog.PERSONALITIES.keys()
	for i in n:
		players.append({"slot": i, "player_name": SetupMenu.DEFAULT_NAMES[i][0], "company_name": SetupMenu.DEFAULT_NAMES[i][1],
			"color_idx": i, "avatar_style": i, "personality": personalities[i % personalities.size()],
			"provider": args.get("provider", "demo"), "base_url": args.get("base-url", ""), "model": args.get("model", "demo"),
			"api_key": OS.get_environment(args.get("api-key-env", "")) if args.has("api-key-env") else "",
			"interval": float(args.get("interval", "3")), "max_requests": 500, "max_tokens": 2000000,
			"max_tokens_per_request": 900, "fallback": true, "timeout": float(args.get("timeout", "20")), "strategy": ""})
	var cfg := {"seed": int(args.get("seed", "777")), "duration_min": 240, "duration_seconds": float(args.get("seconds", "60")),
		"speed_idx": GameSession.SPEEDS.find(int(args.get("speed", "16"))), "demo_fault_rate": float(args.get("fault", "0.1")),
		"map_size": int(args.get("map", str(Catalog.MAP_SIZE))), "players": players,
		"weather": args.get("weather", "sim"), "weather_replay": args.get("weather-replay", "")}
	print("AUTOTEST: %d Spieler, %s s aktive Echtzeit, %sx, Anbieter %s" % [n, args.get("seconds", "60"), args.get("speed", "16"), args.get("provider", "demo")])
	_start(cfg)


func _process(_delta: float) -> void:
	if session and args.has("save-at") and not args.has("_saved") and session.active_seconds >= float(args["save-at"]):
		args["_saved"] = true
		session.save_game()
		print("AUTOTEST: gespeichert bei %.1f s, Spielzeit %s, Gewinne %s" % [session.active_seconds,
			Catalog.game_minutes_to_text(session.sim.game_min), str(session.sim.companies.map(func(c): return snappedf(c.ledger.profit(), 0.01)))])
	if session and args.has("screenshot") and not _shot_done and session.active_seconds >= float(args.get("shot-at", "15")):
		_shot_done = true
		if args.has("shot-zoom"):
			session.city_view.camera.zoom = Vector2.ONE * float(args["shot-zoom"])
		if args.has("shot-tile"):
			var xy: PackedStringArray = str(args["shot-tile"]).split(",")
			session.set_follow(false)
			session.city_view.set_camera_world(Vector2(float(xy[0]) * 32.0 + 16.0, float(xy[1]) * 32.0 + 16.0))
		if args.has("shot-follow"):
			var f: String = args["shot-follow"]
			if f == "worker":   # einem arbeitenden Arbeiter folgen (Sichtpruefung)
				for t in session.sim.personnel.tasks.values():
					if t.status == "in Bearbeitung" and t.kind != "fahren":
						f = t.worker_id
						break
			if f == "person":   # einer wartenden Kundenfigur folgen (Sichtpruefung)
				for pp in session.sim.residents.people.values():
					if pp.state == "wartet":
						f = pp.id
						break
			if f.begins_with("plot"):   # Betriebshof einer Firma zeigen, z. B. plot0
				var p: Dictionary = session.sim.estate.plots[session.sim.companies[int(f.substr(4))].depots[0]]
				session.set_follow(false)
				session.city_view.set_camera_world(Vector2((p.x + p.w * 0.5) * 32, (p.y + p.h * 0.5) * 32))
			else:
				session.follow({"kind": "worker", "id": f} if f.begins_with("W") else ({"kind": "person", "id": f} if f.begins_with("P") else {"kind": "avatar", "id": int(f)}))
		session.hud.show_tab(str(args.get("tab", "Aktivitäten")), int(args.get("econ", "0")))   # schliesst auch versehentlich geoeffnete Fenster
		for i in 90:   # Kamera schwenken lassen
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["screenshot"])
		print("AUTOTEST: Screenshot gespeichert: ", ProjectSettings.globalize_path(args["screenshot"]))


func _autotest_finished(s: GameSession) -> void:
	var rank := s.sim.ranking()
	var ok := true
	var best := -INF
	for c in s.sim.companies:
		best = maxf(best, c.ledger.profit())
		var err := absf(c.ledger.cash + s.sim.book_assets(c.id) - c.ledger.debt - c.ledger.start_capital - c.ledger.profit())
		if err > 0.01:
			ok = false
			print("AUTOTEST FEHLER: Bilanzidentität verletzt bei %s (%.4f)" % [c.company_name, err])
	if not is_equal_approx(snappedf(rank[0].ledger.profit(), 0.01), snappedf(best, 0.01)):
		ok = false
		print("AUTOTEST FEHLER: Sieger hat nicht den höchsten Gewinn")
	if s.active_seconds > s.duration_seconds + 1.0:
		ok = false
		print("AUTOTEST FEHLER: Partie lief zu lange")
	print("AUTOTEST ERGEBNIS (%s, %.1f s aktiv, Spielzeit %s):" % [s.end_reason, s.active_seconds, Catalog.game_minutes_to_text(s.sim.game_min)])
	for i in rank.size():
		var c: Company = rank[i]
		var ctl: AgentController = s.controllers[c.id]
		print("  %d. %-20s Gewinn %10.2f  Umsatz %10.2f  Ruf %5.1f  Aufträge %3d  Geschäfte %d  Sabotage %d/%d  Anfragen %d ok %d fehl %d ungültig %d  Aktionen %d/%d%s" % [
			i + 1, c.company_name, c.ledger.profit(), c.ledger.revenue(), c.reputation, c.stats.completed, c.stats.deals,
			c.stats.sabotage_ok, c.stats.sabotage_caught, ctl.stats.requests, ctl.stats.ok, ctl.stats.errors, ctl.stats.invalid,
			ctl.stats.actions_ok, ctl.stats.actions_rejected, "  [ERSATZMODUS]" if ctl.fallback_active else ""])
	print("  Nachrichten: %d · Frames: %d · max. Frame %.0f ms · Frames >100 ms: %d" % [s.sim.social.next_msg - 1,
		s.frame_stats.frames, s.frame_stats.max_ms, s.frame_stats.over_100ms])
	var by_type := {}
	for e in s.sim.events.events:
		if e.get("auto", false):
			by_type[e.typ] = int(by_type.get(e.typ, 0)) + 1
	var ppl: Array = s.sim.residents.people.values()
	var asked: int = ppl.filter(func(p): return p.done + p.failed > 0 or p.state == "wartet").size()
	print("  Stadt: %d Kundenfiguren, %d mit Anliegen, %d Anliegen erfüllt, %d gescheitert · automatische Ereignisse: %s · Wetter: %s (%s)" % [
		ppl.size(), asked, ppl.map(func(p): return p.done).reduce(func(a, b): return a + b, 0),
		ppl.map(func(p): return p.failed).reduce(func(a, b): return a + b, 0), str(by_type), s.sim.wx.headline(), s.sim.wx.cur.source])
	var fs: Dictionary = s.frame_stats
	var nf := maxf(1.0, float(fs.frames))
	print("  Zeit je Bild: Simulation %.2f ms · Stadtansicht %.2f ms · Entitäten %.2f ms · Oberfläche %.2f ms · gesamt %.2f ms" % [
		fs.sim_ms / nf, fs.city_ms / nf, fs.entity_ms / nf, fs.hud_ms / nf, fs.sum_ms / nf])
	print("  Leistung: Knoten %d · Draw-Calls %d · Objekte im Bild %d · Prozesszeit %.1f ms · Renderzeit %.1f ms · Speicher %.0f MB" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	print("AUTOTEST ", "OK" if ok else "FEHLGESCHLAGEN")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)
