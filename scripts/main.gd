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


## Haenger-Melder: eigener Thread prueft jede halbe Sekunde, ob Bilder fertig werden. Steht das Spiel laenger als 3 s,
## schreibt er die letzte Markierung des Hauptthreads (ProcTimer.text) nach user://logs/haenger.txt (Partie 09.11.: Haenger mit IONOS).
const HANG_S := 3.0
const _AFTER_PROCESS := preload("res://scripts/core/after_process_mark.gd")
var _wd: Thread
var _wd_stop := false


func _watchdog() -> void:
	var last := Engine.get_process_frames()
	var since := Time.get_ticks_msec()
	var reported := 0.0
	var tick := 0
	while not _wd_stop:
		OS.delay_msec(25)
		var f := Engine.get_process_frames()
		var now := Time.get_ticks_msec()
		_crumbs.append("%d Bild %d: %s" % [now, f, ProcTimer.text()])
		if _crumbs.size() > 12:
			_crumbs.pop_front()
		tick += 1
		if tick % 4 != 0:
			continue
		_breadcrumb()
		if f != last:
			if reported > 0.0:
				_hang_note("weiter nach %.1f s" % ((now - since) / 1000.0))
			last = f
			since = now
			reported = 0.0
			continue
		var stuck := (now - since) / 1000.0
		if stuck >= HANG_S and stuck - reported >= 10.0 or (reported == 0.0 and stuck >= HANG_S):
			reported = stuck
			_hang_note("steht seit %.1f s bei: %s" % [stuck, ProcTimer.text()])


## Brotkrume fuer fatale Abstuerze (Godot nennt dann keine Skriptzeile): Markierungen des Hauptthreads alle 25 ms, die letzten 12
## alle 0,1 s nach zuletzt.txt (Zeit in ms seit Start). Eigene Marken fuer die Zeit nach allen _process (Layout, _draw) und das
## Rendern, damit ein Absturz in der Engine nicht der zuletzt markierten Spiellogik zugeschrieben wird (Abstuerze 10.11.).
var _crumbs: Array = []


func _breadcrumb() -> void:
	var f := FileAccess.open("user://logs/zuletzt.txt", FileAccess.WRITE)
	if f != null:
		f.store_line(Time.get_datetime_string_from_system())
		for c in _crumbs:
			f.store_line(c)
		f.close()


func _hang_note(text: String) -> void:
	var path := "user://logs/haenger.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s %s" % [Time.get_datetime_string_from_system(), text])
	f.close()


func _mark_render() -> void:
	ProcTimer.mark("Rendern", -1)
	ProcTimer.sub("-")


func _mark_rendered() -> void:
	ProcTimer.mark("nach Rendern", -1)
	ProcTimer.sub("-")


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_mark_render)
	RenderingServer.frame_post_draw.disconnect(_mark_rendered)
	_wd_stop = true
	if _wd != null and _wd.is_started():
		_wd.wait_to_finish()


func _ready() -> void:
	get_window().title = "Pixel Transport Rivals"
	DirAccess.make_dir_recursive_absolute("user://logs")
	_wd = Thread.new()
	_wd.start(_watchdog)
	var after := Node.new()   # laeuft als letzter _process im Bild: danach folgen Layout, _draw und das Rendern
	after.name = "SpurNachProcess"
	after.process_priority = 100000
	after.set_script(_AFTER_PROCESS)
	add_child(after)
	RenderingServer.frame_pre_draw.connect(_mark_render)
	RenderingServer.frame_post_draw.connect(_mark_rendered)
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
	ProcTimer.mark("main", -1)
	ProcTimer.sub("Partie wird aufgebaut (Karte, Ansicht)")
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
		session.sim_budget_ms = 0.0   # Test misst die volle Simulationszeit
		_apply_test_overrides(session.sim)
	session.menu_requested.connect(_show_menu)
	session.load_requested.connect(_load)
	if args.has("autotest"):
		session.finished.connect(_autotest_finished)


## Sichtpruefung per Autotest: --wx=rain|storm|hot|snow|fog|wind  --hour=22 (Tageszeit)
func _apply_test_overrides(sim: Simulation) -> void:
	if str(args.get("scenario", "")) == "yard":
		_scenario_yard(sim)
	if str(args.get("scenario", "")) == "site":
		_scenario_site(sim, int(args.get("site-phase", "3")))
	if str(args.get("scenario", "")) == "depot":
		_scenario_depot(sim)
	if args.has("layer"):
		for i in int(args.layer):
			session.city_view.parcel_layer.cycle()
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
	ProcTimer.mark("main", -1)
	ProcTimer.sub("Partie wird aufgebaut (Karte, Ansicht)")
	var d := GameSession.read_save()
	if d.is_empty():
		return
	var cfg: Dictionary = d.cfg
	for p in cfg.players:
		p["api_key"] = CredentialStore.read_key("slot%d" % int(p.slot)) if p.provider in ["openai", "ionos", "anthropic"] and p.get("save_key", false) else ""
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
		"weather": args.get("weather", "sim"), "weather_replay": args.get("weather-replay", ""), "welt": args.get("welt", "region")}
	print("AUTOTEST: %d Spieler, %s s aktive Echtzeit, %sx, Anbieter %s" % [n, args.get("seconds", "60"), args.get("speed", "16"), args.get("provider", "demo")])
	_start(cfg)


const PROBE_LAYERS := ["keine", "site_view", "ambient_view", "mountain_view", "ship_view", "bridge_view", "air_view", "waste_view",
	"tourist_view", "estate_view", "depot_view", "parcel_layer", "entity_view", "activity_layer", "decor_node", "buildings_node", "ground", "keine"]
## Ruckler-Suche ab Sekunde 150, je Schritt 12 s. --draw-probe: blendet nacheinander je eine Ebene aus. --draw-probe=zoom: dasselbe fuer die Zoomstufen ZOOM_PROBE (kuerzere Liste).
## Gemessen wird Wanduhrzeit je Bild (Godot deckelt delta) plus Godots Zaehler fuer gezeichnete Objekte und Draw Calls.
const ZOOM_PROBE := [0.5, 0.3, 0.2]
const ZOOM_LAYERS := ["keine", "entity_view", "buildings_node", "decor_node", "ambient_view", "ground", "keine"]
var _probe := {"i": -1, "t": 0.0, "n": 0, "us": 0, "obj": 0.0, "dc": 0.0, "steps": []}
func _probe_node(name: String) -> CanvasItem:
	if name == "keine":
		return null
	if name in ["entity_view", "activity_layer"]:
		return session.get(name)
	return session.city_view.get(name)
func _draw_probe(delta: float) -> void:
	if session == null or session.active_seconds < 150.0:
		return
	if _probe.steps.is_empty():
		if str(args["draw-probe"]) == "zoom":
			for z in ZOOM_PROBE:
				for l in ZOOM_LAYERS:
					_probe.steps.append([z, l])
		else:
			for l in PROBE_LAYERS:
				_probe.steps.append([0.0, l])
	_probe.t += delta
	_probe.n += 1
	_probe.obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_probe.dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if _probe.i >= 0 and _probe.t < 12.0:
		return
	var now := Time.get_ticks_usec()
	if _probe.i >= 0:
		var st: Array = _probe.steps[_probe.i]
		var n := maxf(1.0, _probe.n)
		session.api_log.write({"type": "draw_probe", "zoom": st[0] if st[0] > 0.0 else session.city_view.camera.zoom.x, "ausgeblendet": st[1],
			"ms_je_bild": snappedf((now - int(_probe.us)) / 1000.0 / n, 0.1), "objekte": int(_probe.obj / n), "draw_calls": int(_probe.dc / n), "bilder": _probe.n})
		var old := _probe_node(st[1])
		if old != null:
			old.visible = true
	_probe.i += 1
	_probe.t = 0.0
	_probe.n = 0
	_probe.obj = 0.0
	_probe.dc = 0.0
	_probe.us = now
	if _probe.i >= _probe.steps.size():
		get_tree().quit()
		return
	var cur_step: Array = _probe.steps[_probe.i]
	if cur_step[0] > 0.0:
		session.city_view.camera.zoom = Vector2.ONE * float(cur_step[0])
	var cur := _probe_node(cur_step[1])
	if cur != null:
		cur.visible = false


func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	ProcTimer.mark("main")
	ProcTimer.sub("-")
	_process_timed(_delta)
	ProcTimer.add("main", _pt)


func _process_timed(_delta: float) -> void:
	if args.has("draw-probe"):
		_draw_probe(_delta)
	if session and args.has("hang-test") and not args.has("_hung") and session.active_seconds >= 5.0:   # Pruefung des Haenger-Melders
		args["_hung"] = true
		ProcTimer.sub("Leistungslog")
		OS.delay_msec(5000)
	if session and args.has("demo-mine") and not args.has("_mine"):   # Sichtpruefung Bergbau: Firma 0 eroeffnet ein Bergwerk mit Personal
		args["_mine"] = true
		var c0: Company = session.sim.companies[0]
		c0.ledger.inject(120000.0)
		var r: Dictionary = session.sim.executor.execute(0, {"action": "found_business", "branche": "bergwerk", "rohstoff": str(args["demo-mine"]) if str(args["demo-mine"]) != "true" else ""})
		print("AUTOTEST: Bergwerk ", r.get("msg", ""))
		if r.get("ok", false):
			var staff: Array = session.sim.personnel.employed(0)
			for i in mini(3, staff.size()):
				session.sim.biz.assign(0, staff[staff.size() - 1 - i].id, str(r.ref))
	if session and args.has("demo-access") and not args.has("_access"):   # Sichtpruefung Zufahrt: Firma 0 laesst eine Zufahrt bauen, 3 Bautage sofort
		args["_access"] = true
		var sim: Simulation = session.sim
		sim.companies[0].ledger.inject(120000.0)
		var far: Dictionary = sim.prod.remote_deposit("")
		var r: Dictionary = sim.executor.execute(0, {"action": "build_access", "grundstueck": str(far.get("grundstueck", ""))})
		print("AUTOTEST: Zufahrt ", r.get("msg", ""))
		if r.get("ok", false):
			var day := GameCalendar.day_of(sim.game_min)
			for k in 3:
				sim.access.on_day(day + 1 + k)
			var j: Dictionary = sim.access.jobs[str(r.ref)]
			var at: Array = j.cells[j.cells.size() - int(j.built)]
			args["shot-tile"] = "%d,%d" % [int(at[0]), int(at[1])]
	if session and args.has("demo-snow") and not args.has("_snow") and session.sim.municipal.started:   # Sichtpruefung Winterdienst: Schneefall, Kamera auf den ersten Bauhof
		args["_snow"] = true
		var st0: Dictionary = session.sim.wx.cur.duplicate()
		st0.cond = "Schnee"
		st0.temp = -3.0
		st0.snow_cm = 2.0
		st0.source = "demo"
		session.sim.wx.cur = st0
		session.sim.wx.hold_simulation = true
		for s0 in session.sim.road_care.cells:   # schon liegender Schnee, damit die Raeumung sofort sichtbar ist
			session.sim.winter.snow[s0] = 60.0
		var yard: Array = session.sim.municipal.of_town(0, "feuerwehr") if args.get("demo-snow") == "wache" else session.sim.municipal.of_town(0, "bauhof")
		if not yard.is_empty():
			var yb: Dictionary = session.sim.city.building(int(yard[0].building))
			args["shot-tile"] = "%d,%d" % [int(yb.x), int(yb.y)]
	if session and args.has("demo-fire") and not args.has("_fire") and session.sim.municipal.started:   # Sichtpruefung Feuerwehr: Brand nahe der ersten Wache
		args["_fire"] = true
		var st: Dictionary = session.sim.municipal.of_town(0, "feuerwehr")[0]
		var sc := Vector2i(int(st.cell[0]), int(st.cell[1]))
		for b in session.sim.city.buildings:
			var d := (Vector2i(int(b.x), int(b.y)) - sc).length()
			if b.role == "customer" and d >= 25.0 and d <= 45.0:
				session.sim.fire.ignite(int(b.id))
				args["shot-tile"] = "%d,%d" % [int(b.x), int(b.y)]
				break
	if session and args.has("demo-highway") and not args.has("_highway") and session.sim.towns.is_region():   # Sichtpruefung Autobahn (Auftrag 21)
		args["_highway"] = true
		var R: RegionalProjects = session.sim.regional
		for t in session.sim.towns.list:
			session.sim.economy.transfer("X0", Towns.account_of(int(t.id)), 150000.0)
		var res: Dictionary = session.sim.council.decide({"kind": "autobahn", "by": 0, "reason": "Sichtprüfung"})
		print("AUTOTEST Autobahn: ", res.text, " ", res.get("ref", ""))
		var hw: Array = R.items.values().filter(func(r): return str(r.kind) == "autobahn")
		if not hw.is_empty():
			var cs: Array = hw[0].cells
			var c: Array = cs[clampi(int(float(cs.size()) * float(args.get("highway-at", "0.04"))), 0, cs.size() - 1)]
			print("AUTOTEST Autobahn-Ansicht: im Baum %s, Felder %d, Ziel %s, erste %s" % [str(session.city_view.highway_view.is_inside_tree()), cs.size(), str(c), str(cs.slice(0, 4))])
			args["shot-tile"] = "%d,%d" % [int(c[0]), int(c[1])]
	if session and args.has("demo-ship") and not args.has("_ship") and session.sim.harbor.enabled:   # Sichtpruefung Hafen: Schiff legt sofort an
		args["_ship"] = true
		for k in session.sim.towns.count():   # alle Haefen der Region
			var H: Harbor = session.sim.towns.harbor(k)
			if not H.enabled:
				continue
			for it in ["mehl", "saatgut", "stahl"]:
				H.ship_in("stock", "", it, 400)   # genug Ladung, damit die Abfertigung eine Weile sichtbar ist
			H._staff_day()
			H._staff_day()   # Grundbesetzung, damit die Abfertigung sofort sichtbar ist
			H._arrive(GameCalendar.day_of(session.sim.game_min))
	if session and args.has("demo-sea") and not args.has("_sea") and session.sim.sea.enabled:   # Sichtpruefung Seeverkehr: Schiffe mitten auf der Fahrt
		args["_sea"] = true
		var S: SeaTraffic = session.sim.sea
		var frac := float(args["demo-sea"]) if str(args["demo-sea"]).is_valid_float() else 0.5
		for i in SeaTraffic.FLEET.size():
			var sd: Dictionary = SeaTraffic.FLEET[i]
			var a: int = S.ports[i % S.ports.size()]
			var b: int = S.ports[(i + 1) % S.ports.size()]
			var start: float = session.sim.game_min - SeaTraffic.TRIP_MIN * 6.0 * frac   # langsame Demo-Fahrt, Anteil frac schon zurueckgelegt
			S.legs[sd.id] = {"ship": sd.id, "kind": sd.kind, "name": sd.name, "from": a, "to": b, "depart": start, "arrive": start + SeaTraffic.TRIP_MIN * 6.0, "done": false}
	if session and args.has("demo-ambient") and not args.has("_ambient"):   # Sichtpruefung Kartenleben: Betriebe an vorhandenen Gebaeuden (nur Anzeige)
		args["_ambient"] = true
		var S: Simulation = session.sim
		var near: Array = S.city.buildings.filter(func(b): return S.towns.of_building(int(b.id)) == 0 and int(b.w) >= 2).slice(5, 12)
		var kinds := ["bergwerk", "stahlwerk", "restaurant", "feld", "tierhaltung"]
		for i in mini(kinds.size(), near.size()):
			var bz: Dictionary = S.biz.create(0, kinds[i], int(near[i].id), "", "demo")   # "demo": Produktion ignoriert ihn, die Ansicht zeigt ihn arbeitend
			bz["total"] = 4000
			bz["deposit"] = {"art": "eisenerz", "qualitaet": 0.9}   # Felder, die die Betriebsanzeige erwartet
			bz["field"] = {"phase": "wachsen", "day": 1, "area": 20, "cycles": 0, "last_yield": 0}
			if kinds[i] in ["feld", "tierhaltung"]:
				var pp: Array = S.parcels.search({"min_area": 20, "limit": 50}).filter(func(p): return S.towns.of_parcel(str(p.id)) == 0)
				if not pp.is_empty():
					bz["parcel"] = str(pp[i % pp.size()].id)
		session.city_view.ambient_view._scan_business()
	if session and args.has("demo-bridge") and not args.has("_bridge"):   # Sichtpruefung Bruecke: Zufahrt mit Bruecke, Bau bis zum Fortschritt (Zahl 0..1, "open" = freigegeben)
		args["_bridge"] = true
		_demo_bridge(session.sim, str(args["demo-bridge"]))
	if session and args.has("save-at") and not args.has("_saved") and session.active_seconds >= float(args["save-at"]):
		args["_saved"] = true
		session.save_game()
		print("AUTOTEST: gespeichert bei %.1f s, Spielzeit %s, Gewinne %s" % [session.active_seconds,
			Catalog.game_minutes_to_text(session.sim.game_min), str(session.sim.companies.map(func(c): return snappedf(c.ledger.profit(), 0.01)))])
	if session and args.has("screenshot") and not _shot_done and session.active_seconds >= float(args.get("shot-at", "15")):
		_shot_done = true
		if args.has("shot-zoom"):
			session.city_view.camera.zoom = Vector2.ONE * float(args["shot-zoom"])
		if args.has("shot-activity") and not session.sim.activity.items.is_empty():   # Kamera auf die neueste KI-Aktivitaet (Pruefung der Kartenebene)
			var e: Dictionary = session.sim.activity.items.back()
			session.set_follow(false)
			session.city_view.set_camera_world(Vector2(float(e.x) * 32.0 + 16.0, float(e.y) * 32.0 + 16.0))
		if args.has("shot-garbage"):   # Sichtpruefung Muellabfuhr: einem leerenden Muellwagen folgen, sonst der Deponie
			var target := {}
			for fv in session.sim.fleet.vehicles:
				if fv.kind == "muell" and (target.is_empty() or fv.phase == "leeren"):
					target = {"kind": "muell", "id": int(fv.id)}
			if str(args["shot-garbage"]) == "deponie" or target.is_empty():
				target = {"kind": "deponie", "id": session.sim.waste.landfill_pid}
			session.follow(target)
		if args.has("shot-mine"):   # Kamera auf ein Bergwerk (sonst einen Berg), Detailkarte offen
			var mv: MountainView = session.city_view.mountain_view
			var pid := ""
			for k in session.sim.prod.terrain:
				if pid == "" or not session.sim.prod.mine_on(k).is_empty():
					pid = k
					if not session.sim.prod.mine_on(k).is_empty():
						break
			if pid != "":
				var mp: Dictionary = session.sim.parcels.parcel(pid)
				session.set_follow(false)
				var mn = mv._nodes.get(pid)
				var focus := Vector2((float(mp.rect[0]) + float(mp.rect[2]) * 0.5) * 32.0, (float(mp.rect[1]) + float(mp.rect[3]) * 0.5) * 32.0)
				if mn != null and mn.active:
					focus = (Vector2(mn.face) + Vector2(mn.halde_cell)) * 16.0 + Vector2(16, 16)   # zwischen Abbaufront und Halde
				session.city_view.set_camera_world(focus)
				session.follow({"kind": "mountain", "id": pid})   # Kamera bleibt am Abbau
		if args.has("shot-ship"):   # Kamera auf den Liegeplatz des Linienschiffs
			var H0: Harbor = session.sim.towns.harbor(0)
			print("AUTOTEST Hafen 0: Spielminute %.1f, Schiff %s Tag %s Status %s, angelegt %s, Posten %d, Grund %s, Tagesbeginn %.1f" % [session.sim.game_min, str(H0.ship.get("name")), str(H0.ship.get("day")), str(H0.ship.get("status")), str(H0.docked(session.sim.game_min)), H0.queue.size(), H0.idle_reason(), GameCalendar.day_start(int(H0.ship.get("day", 0)))])
			session.set_follow(false)
			session.city_view.set_camera_world(session.city_view.ship_view.berth + Vector2(110, -110))   # nach rechts versetzt: Seitenleiste verdeckt den rechten Bildrand
		if args.has("shot-hub") and not session.sim.city.hub.is_empty():   # Kamera auf das zentrale Grosslager (Auftrag 19)
			var hc: Array = session.sim.city.hub.center
			session.set_follow(false)
			session.city_view.set_camera_world(Vector2(float(hc[0]) * 32.0, float(hc[1]) * 32.0))
		if args.has("shot-anlage") and session.sim.civic != null:   # Kamera auf eine Anlage der Buergermeister (Auftrag 19), Nr. = Reihenfolge
			var opened: Array = session.sim.civic.anlagen.values().filter(func(a): return a.status in ["eroeffnet", "im_bau"])
			print("AUTOTEST Anlagen: ", session.sim.civic.anlagen.values().map(func(a): return "%s %s %s" % [a.id, a.title, a.status]))
			if not opened.is_empty():
				var an: Dictionary = opened[clampi(int(args["shot-anlage"]) if str(args["shot-anlage"]).is_valid_int() else 0, 0, opened.size() - 1)]
				session.set_follow(false)
				session.city_view.set_camera_world(Vector2((float(an.rect[0]) + float(an.rect[2]) * 0.5) * 32.0, (float(an.rect[1]) + float(an.rect[3]) * 0.5) * 32.0))
				print("AUTOTEST Kamera auf ", an.title, " (", an.status, ")")
		if args.has("demo-fire"):
			print("AUTOTEST Feuerwehr: ", session.sim.fire.fires.values().map(func(f): return "%s %s %s Staerke %d Schaden %d" % [f.id, f.status, f.phase, int(f.intensity), int(f.damage)]))
		if args.has("shot-dienst") and session.sim.municipal != null:   # Kamera auf eine kommunale Einrichtung (Auftrag 20), Nr. = Reihenfolge
			var fs: Array = session.sim.municipal.facilities.values()
			print("AUTOTEST Einrichtungen: ", fs.map(func(f): return "%s %s %s" % [f.id, f.name, Municipal.sprite_of(f)]))
			if not fs.is_empty():
				var mf: Dictionary = fs[clampi(int(args["shot-dienst"]) if str(args["shot-dienst"]).is_valid_int() else 0, 0, fs.size() - 1)]
				var mb: Dictionary = session.sim.city.building(int(mf.building))
				session.set_follow(false)
				session.city_view.set_camera_world(Vector2((float(mb.x) + float(mb.w) * 0.5) * 32.0, (float(mb.y) + float(mb.h) * 0.5) * 32.0))
		if args.has("shot-town"):   # Kamera auf das Rathaus eines Orts (Ortskern)
			var th: Dictionary = session.sim.city.building(int(session.sim.towns.get_t(int(args["shot-town"])).town_hall))
			session.set_follow(false)
			session.city_view.set_camera_world(Vector2(float(th.x) * 32.0 + 80.0, float(th.y) * 32.0 + 80.0))
		if args.has("shot-placement"):   # Diagnoseansicht Platzierung einschalten
			session.city_view.placement_overlay.visible = true
		if args.has("shot-ambient"):   # Kamera auf das erste Kartenleben-Element einer Art (strand, boot, bergwerk, huette, traktor, passanten, kran, terrasse)
			for sp in session.city_view.ambient_view._spots:
				if sp.kind == str(args["shot-ambient"]):
					session.set_follow(false)
					session.city_view.set_camera_world(sp.world + Vector2(40, -40))
					break
		if args.has("shot-sea"):   # Kamera auf ein Schiff des Seeverkehrs (KS1 Kreuzfahrt, AT1 Autotransporter)
			var sn = session.city_view.ship_view._voyage_nodes.get(str(args["shot-sea"]))
			if sn != null:
				session.set_follow(false)
				session.city_view.set_camera_world(sn.world + Vector2(60, -60))
		if args.has("shot-crew"):   # Kamera auf das Fahrzeug eines Bautrupps (bevorzugt eines, das gerade baut)
			var pick := {}
			for fv in session.sim.fleet.vehicles:
				if fv.kind == "kolonne":
					var tc: Dictionary = session.sim.crews.crews.get(str(fv.get("crew", "")), {})
					if pick.is_empty() or tc.get("state", "") == str(args["shot-crew"]):
						pick = fv
			if not pick.is_empty():
				args.erase("shot-tile")
				session.set_follow(false)
				session.city_view.set_camera_world(pick.mover.pos)
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
		if args.has("_select_depot"):
			session.entity_view.selected = {"kind": "building", "id": session.sim.city_depot.building}
		session.hud.show_tab(str(args.get("tab", "Aktivitäten")), int(args.get("econ", "0")))   # schliesst auch versehentlich geoeffnete Fenster
		for i in 90:   # Kamera schwenken lassen
			await get_tree().process_frame
		if args.has("shot-tile"):   # Kamera kann waehrend des Wartens verschoben worden sein (Folgen): Ziel erneut setzen
			var xy2: PackedStringArray = str(args["shot-tile"]).split(",")
			session.set_follow(false)
			session.city_view.set_camera_world(Vector2(float(xy2[0]) * 32.0 + 16.0, float(xy2[1]) * 32.0 + 16.0))
			for i in 4:
				await get_tree().process_frame
		if args.has("shot-ui"):   # Leitstelle: je Angabe (Komma-getrennt) ein eigenes Bild <screenshot>_<Angabe>.png
			for spec in str(args["shot-ui"]).split(","):
				_apply_shot_ui(spec)
				for i in 30:
					await get_tree().process_frame
				var path := str(args["screenshot"]).get_basename() + "_" + spec.replace(":", "-") + ".png"
				get_viewport().get_texture().get_image().save_png(path)
				print("AUTOTEST: Screenshot gespeichert: ", ProjectSettings.globalize_path(path))
			return
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["screenshot"])
		print("AUTOTEST: Screenshot gespeichert: ", ProjectSettings.globalize_path(args["screenshot"]))


## Leitstelle fuer Screenshots: Bereich bzw. Detail oeffnen (ki, welt, gespraeche, firmen, firma:N[:tab], staedte, stadt:N, finanzen, technik, warum, suche:Text, zu)
func _apply_shot_ui(spec: String) -> void:
	var cc: ControlCenter = session.hud.control_center
	var parts: PackedStringArray = spec.split(":")
	match parts[0]:
		"firma":
			cc.open_area("firmen")
			cc.show_company(int(parts[1]), parts[2] if parts.size() > 2 else "ueberblick")
		"stadt":
			cc.open_area("staedte")
			cc.show_town(int(parts[1]))
		"gespraeche":
			cc.welt_tab = "gespraeche"
			cc.open_area("welt")
		"warum":
			cc.open_area("ki")
			var last := session.sim.decisions.entries.filter(func(d): return str(d.herkunft) in ["api", "fallback", "plan"] and str(d.pruefung) == "ok")
			if not last.is_empty():
				cc.show_decision(str(last[-1].id))
		"suche":
			cc.open_area("ki")
			cc.search.text = parts[1]
			cc._search(parts[1])
		"zu":
			cc.set_expanded(false)
		"sprung":   # erstes wichtiges Ereignis mit Ort: Kamera springt, Ring markiert den Ort
			for e in session.sim.center.query({"min_sev": 2}, 50):
				if not (e.cell as Array).is_empty():
					cc.jump_event(e)
					print("AUTOTEST Sprung zu ", e.title, " ", e.cell)
					break
		"skala":
			cc.set_ui_scale(float(parts[1]))
		_:
			cc.open_area(parts[0])


## Sichtpruefung der Baustellengrafik: ein Haushalt baut ein Mehrfamilienhaus; die Zeit wird bis zur gewuenschten Bauphase vorgespult.
func _scenario_site(sim: Simulation, phase: int) -> void:
	var P := sim.parcels
	var home := "H9000"
	sim.households.homes[home] = {"id": home, "members": [], "dependents": 0, "address": 0, "balance": 0.0, "shortfall": 0.0, "income": 0.0, "spent": 0.0,
		"deficit_months": 0, "low_months": 0, "asked": false}
	sim.households.homes[home].balance = float(sim.households.homes[home].balance) + 400000.0
	sim.economy.transfer("X0", "H0", 400000.0)
	for it in ["ziegel", "beton", "holz", "glas", "installation", "stahl", "verbindung", "rohmaterial"]:
		sim.stock.add(it, 2000, "T0", sim.trader.bauhof, "Szenario")
	# Grundstueck suchen, auf dem der Antrag genehmigt wird (Rasterstadt: Mehrfamilienhaus, Kuestenort: Einfamilienhaus auf kleinen Parzellen)
	var cands: Array = P.search({"zone": "wohnen", "min_area": 40, "limit": 400}).filter(func(q): return P.utility_level(q) != "keine")
	cands.sort_custom(func(a, b): return a.area > b.area)
	var pid := ""
	var d := {}
	for q in cands.slice(0, 12):
		P.reserve(q.id, home)
		var big: bool = int(q.area) >= 70 and P.utility_level(q) == "voll"
		var dd: Dictionary = sim.permits.draft(home, q.id, {"def": "mehrfamilienhaus" if big else "einfamilienhaus", "floors": 3 if big else 1, "parking": 4 if big else 1})
		if not dd.get("ok", false):
			P.release(q.id, home)
			continue
		sim.permits.apps[dd.id].financing = {"eigenmittel": float(sim.permits.preview(dd.id).costs.gesamt) + 10.0}
		sim.permits.submit(dd.id)
		var g := 0
		var dday := GameCalendar.day_of(sim.game_min)
		while sim.permits.apps[dd.id].status != "entschieden" and g < 30:
			g += 1
			dday += 1
			sim.game_min = GameCalendar.day_start(dday)
			sim.parcels.on_day(dday)
			sim.permits.on_day(dday)
		if str(sim.permits.apps[dd.id].get("result", "")).begins_with("genehmigt"):
			pid = q.id
			d = dd
			break
		P.release(q.id, home)
	if pid == "":
		print("SZENARIO site: kein genehmigungsfähiges Grundstück")
		return
	var day := GameCalendar.day_of(sim.game_min)
	var guard := 0
	var pr := {}
	while guard < 400:
		guard += 1
		day += 1
		sim.game_min = GameCalendar.day_start(day)
		sim.parcels.on_day(day)
		sim.permits.on_day(day)
		sim.construction.on_day(day)
		if pr.is_empty() and sim.permits.apps[d.id].status == "entschieden":
			var r: Dictionary = sim.construction.start_project(d.id)
			sim.construction.accept_best(r.id)
			pr = sim.construction.projects[r.id]
		if not pr.is_empty() and ((int(pr.phase) >= phase and sim.crews.on_site("bp", pr.id) and float(pr.progress) > 0.2) or pr.status == "uebergeben"):
			break   # Trupp ist auf der Baustelle und arbeitet
	var pc: Dictionary = sim.parcels.parcel(pid)
	args["shot-tile"] = "%d,%d" % [int(pc.rect[0]) + int(pc.rect[2]) / 2 + 2, int(pc.rect[1]) + int(pc.rect[3]) / 2 - 2]
	print("SZENARIO site: Phase %s, Fortschritt %.2f, Status %s" % [pr.get("phase"), pr.get("progress", 0.0), pr.get("status")])


## Sichtpruefung der Bruecke: Firma 0 laesst eine Zufahrt ueber den Fluss bauen, Material liegt bereit, die Zeit laeuft bis zum Fortschritt.
func _demo_bridge(sim: Simulation, target: String) -> void:
	sim.companies[0].ledger.inject(250000.0)
	sim.prod.deposit_of("x")
	var pid := ""
	for id in sim.prod._deposits:
		var pl: Dictionary = sim.access.plan(id)
		if pl.ok and not pl.bruecken.is_empty():
			pid = id
			break
	var r: Dictionary = sim.executor.execute(0, {"action": "build_access", "grundstueck": pid, "reason": "Sichtprüfung"})
	print("AUTOTEST: Antrag ", r.get("msg", "keine Lagerstätte jenseits des Flusses"))
	if not r.get("ok", false):
		return
	var dec: Dictionary = sim.mayor.execute({"action": "decide_access", "antrag": str(r.ref), "decision": "genehmigen", "bruecke": "stein", "reason": "Sichtprüfung"})
	print("AUTOTEST: Entscheidung ", dec.get("msg", ""))
	if sim.bridges.items.is_empty():
		return
	var b: Dictionary = sim.bridges.items.values()[0]
	var j: Dictionary = sim.access.jobs[str(r.ref)]
	for pid2 in [b.project, j.project]:
		var prj: Dictionary = sim.mayor.projects[pid2]
		for it in prj.material:
			sim.stock.add(it, int(prj.material[it]), "P0", sim.city_depot.building, "Szenario")
	var stop := 1.0 if target == "open" else clampf(float(target), 0.0, 0.99)
	var day := GameCalendar.day_of(sim.game_min)
	for k in 60:
		day += 1
		sim.game_min = GameCalendar.day_start(day)
		sim.construction._public_day(day)
		sim.access.on_day(day)
		if b.status == "freigegeben" or sim.bridges.progress(b) >= stop:
			break
	sim.game_min = GameCalendar.day_start(day) + GameCalendar.days_to_min(0.4)   # mitten im Arbeitstag: Wegebau-Front rueckt sichtbar vor
	var c: Array = b.cells[b.cells.size() / 2]
	if str(args.get("shot-works", "")) == "road":   # Kamera auf die Arbeitsfront des Wegebaus
		var fr: Dictionary = sim.access.front(j)
		c = [int(fr.cells[mini(int(fr.built) + 2, fr.cells.size() - 1)].x), int(fr.cells[mini(int(fr.built) + 2, fr.cells.size() - 1)].y)]
	args["shot-tile"] = "%d,%d" % [int(c[0]), int(c[1])]
	print("AUTOTEST: Brücke %s Phase %s, Fortschritt %.2f" % [b.id, sim.bridges.phase(b), sim.bridges.progress(b)])


## Sichtpruefung des Zentrallagers: Lieferungen im Wareneingang, Ausgabe fuer ein Projekt, Lkw an der Rampe und in der Warteschlange; das Lager ist ausgewaehlt.
func _scenario_depot(sim: Simulation) -> void:
	var D: CityDepot = sim.city_depot
	for item in ["kies", "schotter", "verkehrsschild", "kabel"]:
		var qty := 120 if item != "kabel" else 400
		sim.stock.add(item, qty, "P0", D.building, "Szenario", 0.0, "pruefung")
		var o := D._new_order(item, qty, "Szenario")
		o.status = "angeliefert"
		o.arrived = GameCalendar.day_of(sim.game_min)
		o["qty_received"] = qty
		o.supplier = "T0"
		D.orders[o.id] = o
	var miss := D.reserve_for_project("P7", CityDepot.material_need(["strasse"], 1))
	D.issues.append({"day": GameCalendar.day_of(sim.game_min), "item": "bordstein", "qty": 40, "to": "Baufirma", "mode": "ueberlassen", "ref": "P7"})
	var vs: Array = sim.vehicles.values()
	for i in mini(3, vs.size()):
		var k := Contract.new()
		k.id = "AS%d" % i
		k.dropoff = D.building
		k.pickup = sim.trader.bauhof
		k.order_ref = "B999"
		k.payer = "P0"
		k.cargo = "baustoffe"
		k.owner = vs[i].owner
		k.status = "in_transit"
		sim.contracts[k.id] = k
		vs[i].stops = [{"contract_id": k.id, "art": "abladen", "ort": "ziel", "menge": 1}]
		vs[i].state = "unloading" if i < 2 else "waiting_bay"
		vs[i].timer = 9999.0
	var b: Dictionary = sim.city.building(D.building)
	args["shot-tile"] = "%d,%d" % [int(b.x) + int(b.w) / 2, int(b.y) + int(b.h) / 2]
	args["_select_depot"] = true
	print("SZENARIO depot: Lager %d, Rampen %d, Personal %d" % [D.building, D.ramps, D.roster().size()])


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
	var accepted_quotes: int = s.sim.social.agreements.values().filter(func(g): return g.kind == "split_contract" and s.sim.operations.requests.values().any(func(r): return str(g.offer) in r.offers)).size()
	print("  Betrieb: Linien %d · Linienfrachten %d · zugestellt %d · Frachtanfragen %d · angenommene Preisangebote %d" % [
		s.sim.operations.lines.size(), s.sim.operations.jobs.size(), s.sim.operations.lines.values().reduce(func(total, line): return total + int(line.delivered), 0),
		s.sim.operations.requests.size(), accepted_quotes])
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
	var sim: Simulation = s.sim
	var accounts := ""
	var my: Mayor = sim.mayor
	print("  Stadtentwicklung: Bürgermeister %s (%s, %s) · Zustimmung %.0f %% · Einwohner %d · Wohnungssuchende %d · Pläne %d · Projekte %d · Entscheidungen %d (ausgeführt %d) · Anträge %d, davon entschieden %d · Grundstücke frei %d" % [
		my.name, my.party, "Modell" if s.mayor_agent.uses_model() else "Regeln", my.approval, sim.citizens.population(), my.waiting, my.plans.size(), my.projects.size(), my.decisions.size(),
		my.decisions.filter(func(d): return d.ok).size(), sim.permits.apps.size(), sim.permits.apps.values().filter(func(x): return x.status == "entschieden").size(), sim.parcels.summary().nach_status.get("frei", 0)])
	for k in sim.economy.accounts:
		accounts += " %s %d" % [k, int(sim.economy.accounts[k])]
	print("  Wirtschaft: Geld erhalten (Abweichung %.2f) · Waren (Abweichung %d) ·%s" % [sim.economy.conservation_error(), sim.stock.balance_error(), accounts])
	print("  Firmenstatus: %s · Insolvenzen %d · Etappensieger %d · Referenzzins %.2f %% · Kredite %d · Haushalte %d (Ausgaben %d)" % [
		", ".join(sim.companies.map(func(c): return "%s %s/%s" % [c.company_name, c.status, c.form])), sim.insolvency.archive.size(),
		sim.standings.stage_winners.size(), sim.banking.ref_rate * 100.0, sim.banking.loans.size(), sim.households.homes.size(), int(sim.households.spent_total)])
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
