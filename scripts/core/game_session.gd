class_name GameSession
extends Node
## Eine laufende Partie: verbindet Simulation, KI-Controller, Darstellung und Oberflaeche.
## Zeitmodell: Die Partiedauer zaehlt nur aktive (nicht pausierte) Echtzeit und ist auf 240 Minuten
## begrenzt. Die Simulationsgeschwindigkeit beschleunigt nur die Spielwelt, nicht die Partiedauer.

signal finished(session: GameSession)
signal load_requested
signal menu_requested

const SPEEDS := [1, 2, 4, 8, 16]
const SAVE_PATH := "user://saves/quicksave.json"
const SUBSTEP := 0.1
const MAX_FRAME_DT := 0.25

var cfg := {}                     # Spielkonfiguration OHNE API-Keys
var sim: Simulation
var controllers: Array[AgentController] = []
var city_view: CityView
var entity_view: EntityView
var hud: HUD
var end_screen: EndScreen
var api_log := ApiLog.new()
var weather_service: WeatherService
var paused := false
var speed_idx := 1
var active_seconds := 0.0
var duration_seconds := 1800.0
var following := false
var ended := false
var end_reason := ""
var frame_stats := {"frames": 0, "max_ms": 0.0, "sum_ms": 0.0, "over_100ms": 0, "sim_ms": 0.0, "city_ms": 0.0, "entity_ms": 0.0, "hud_ms": 0.0}
var _sounds := {}
var _sound_cooldown := {}
var _dragging := false
var _sim_acc := 0.0                  # Rest-Simulationszeit (fester Schritt fuer reproduzierbare Ablaeufe)


func start(config: Dictionary, loaded: Dictionary = {}) -> void:
	cfg = config.duplicate(true)
	var keys := {}
	for p in cfg.players:
		keys[int(p.slot)] = p.get("api_key", "")
		p.erase("api_key")
	if loaded.is_empty():
		var players: Array = []
		for p in cfg.players:
			players.append({"player_name": p.player_name, "company_name": p.company_name,
				"color": Catalog.COMPANY_COLORS[int(p.color_idx)], "avatar_style": int(p.avatar_style),
				"personality": p.personality, "form": p.get("form", "einzel")})
		sim = Simulation.new()
		sim.setup(int(cfg.seed), players, int(cfg.get("map_size", Catalog.MAP_SIZE)))
	else:
		sim = Simulation.from_dict(loaded.sim)
		active_seconds = float(loaded.active_seconds)
		sim.executor.executed = loaded.get("executed", {})
	duration_seconds = maxf(0.0, float(cfg.get("duration_min", 30))) * 60.0   # 0 = Endlosmodus
	if cfg.has("duration_seconds"):
		duration_seconds = maxf(0.0, float(cfg.duration_seconds))
	speed_idx = int(cfg.get("speed_idx", 1))
	api_log.open(Time.get_datetime_string_from_system().replace(":", "-") + "_%d" % sim.city.seed_value)
	city_view = CityView.new()
	add_child(city_view)
	city_view.build(sim)
	entity_view = EntityView.new()
	city_view.add_child(entity_view)
	entity_view.build(sim, city_view)
	if loaded.is_empty() and cfg.get("carry_memory", false):
		# Uebernahme gespeicherter Erfahrungen: gleiche Regel fuer alle Spieler (Vergleichbarkeit)
		for i in cfg.players.size():
			var path := "user://memory/slot%d.json" % int(cfg.players[i].slot)
			if FileAccess.file_exists(path):
				var items = JSON.parse_string(FileAccess.get_file_as_string(path))
				var n := sim.memory.import_experiences(i, items if items is Array else [])
				sim.log_event("%s übernimmt %d Erfahrungen aus der vorigen Partie." % [sim.company(i).player_name, n], "plan", i)
	for i in cfg.players.size():
		var p: Dictionary = cfg.players[i]
		var pc := p.duplicate()
		pc["api_key"] = keys.get(int(p.slot), "")
		pc["demo_fault_rate"] = cfg.get("demo_fault_rate", 0.0)
		var ctl := AgentController.new()
		add_child(ctl)
		ctl.setup(sim, i, pc, api_log)
		if not loaded.is_empty() and i < loaded.controllers.size():
			ctl.from_dict(loaded.controllers[i])
		controllers.append(ctl)
	sim.insolvency.company_refounded.connect(_on_refounded)
	_setup_weather()
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	hud = HUD.new()
	ui.add_child(hud)
	hud.build(self)
	end_screen = EndScreen.new()
	end_screen.visible = false
	ui.add_child(end_screen)
	end_screen.menu_pressed.connect(back_to_menu)
	for n in ["click", "cash", "message", "alert", "horn", "sabotage", "deal", "end"]:
		var pl := AudioStreamPlayer.new()
		pl.stream = load("res://assets/sfx/%s.wav" % n)
		pl.volume_db = -14.0 if n in ["cash", "message"] else -9.0
		add_child(pl)
		_sounds[n] = pl
	sim.sfx.connect(play_sound)
	sim.logged.connect(_on_logged)
	if not loaded.is_empty():
		hud.show_toast("Spielstand geladen")
	api_log.write({"type": "match_start", "seed": sim.city.seed_value, "players": cfg.players, "duration_s": duration_seconds})


## Wetter: Live-Abruf (Standard), Wiederholung einer aufgezeichneten Partie oder nur simuliertes Ersatzwetter ("sim").
func _setup_weather() -> void:
	var replay_path := str(cfg.get("weather_replay", ""))
	if replay_path != "" and FileAccess.file_exists(replay_path):
		var rec = JSON.parse_string(FileAccess.get_file_as_string(replay_path))
		if rec is Array and not rec.is_empty():
			sim.wx.start_replay(rec)
			sim.log_event("Wetter: Wiederholung des aufgezeichneten Verlaufs (%d Stände)." % rec.size(), "info")
			return
	if str(cfg.get("weather", "live")) == "replay":
		sim.log_event("Wetter: keine Aufzeichnung gefunden – gekennzeichnetes Ersatzwetter.", "info")
	if str(cfg.get("weather", "live")) != "live":
		return
	weather_service = WeatherService.new()
	add_child(weather_service)
	weather_service.setup(sim)
	weather_service.updated.connect(func():
		api_log.write({"type": "weather", "minute": sim.minute_index, "state": sim.wx.cur}))
	weather_service.failed.connect(func(msg): api_log.write({"type": "weather_error", "minute": sim.minute_index, "error": msg}))


## Zuschauer-Ereignis ausloesen (wird fuer Wiederholungen mit Simulationsschritt aufgezeichnet).
func trigger_event(typ: String, params: Dictionary, duration_min: float) -> Dictionary:
	var r: Dictionary = sim.events.trigger(typ, params, duration_min)
	if r.ok:
		api_log.write({"type": "spectator_event", "step": sim.step_count, "typ": typ, "params": params, "dauer": duration_min})
	return r


func speed() -> int:
	return SPEEDS[speed_idx]


func set_speed_idx(i: int) -> void:
	speed_idx = clampi(i, 0, SPEEDS.size() - 1)
	play_sound("click")


func toggle_pause() -> void:
	paused = not paused
	play_sound("click")


func is_endless() -> bool:
	return duration_seconds <= 0.0


func remaining_seconds() -> float:
	return 1.0e9 if is_endless() else maxf(0.0, duration_seconds - active_seconds)


func play_sound(n: String) -> void:
	var now := Time.get_ticks_msec()
	if _sounds.has(n) and now - int(_sound_cooldown.get(n, 0)) > 150:
		_sound_cooldown[n] = now
		_sounds[n].play()


## Neuer Unternehmer auf einem Platz: Erinnerung und Persoenlichkeit des Controllers zuruecksetzen.
func _on_refounded(cid: int) -> void:
	if cid >= controllers.size():
		return
	var ctl := controllers[cid]
	ctl.goal = ""
	ctl.memory_note = ""
	ctl.summaries.clear()
	if ctl.adapter is DemoAdapter:
		ctl.adapter.personality = sim.company(cid).personality


func _on_logged(e: Dictionary) -> void:
	if e.kind in ["deal", "bad"] and (e.text.contains("Geschäft abgeschlossen") or e.text.contains("Sabotage") \
			or e.text.contains("Störung") or e.text.contains("erwischt")):
		hud.show_toast(e.text.left(110))


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	frame_stats.frames += 1
	frame_stats.sum_ms += ms
	if frame_stats.frames > 30:   # Ladephase nicht mitzaehlen
		frame_stats.max_ms = maxf(frame_stats.max_ms, ms)
		if ms > 100.0:
			frame_stats.over_100ms += 1
	var dt := minf(delta, MAX_FRAME_DT)
	var running := not paused and not ended
	sim.remaining_real_min = remaining_seconds() / 60.0
	for ctl in controllers:
		ctl.active = running and sim.company(ctl.cid).is_active()
		ctl.remaining_real_min = sim.remaining_real_min
	if running:
		active_seconds += dt
		_sim_acc += dt * speed()
		var t0 := Time.get_ticks_usec()
		while _sim_acc >= SUBSTEP:
			sim.step(SUBSTEP)
			_sim_acc -= SUBSTEP
		frame_stats.sim_ms += (Time.get_ticks_usec() - t0) / 1000.0
		if not is_endless() and active_seconds >= duration_seconds:
			end_match("Zeit abgelaufen")
	_camera_keys(delta)
	if following:
		var p := entity_view.selected_position()
		if p.x > -9000.0:
			city_view.camera.position = city_view.camera.position.lerp(Iso.to_screen(p), minf(1.0, delta * 6.0))
	var t1 := Time.get_ticks_usec()
	city_view.update_view(delta)
	var t2 := Time.get_ticks_usec()
	entity_view.update_view(delta, 0.0 if not running else float(speed()), city_view.camera.zoom.x)
	var t3 := Time.get_ticks_usec()
	hud.update_hud(delta)
	var t4 := Time.get_ticks_usec()
	frame_stats.city_ms += (t2 - t1) / 1000.0
	frame_stats.entity_ms += (t3 - t2) / 1000.0
	frame_stats.hud_ms += (t4 - t3) / 1000.0


func end_match(reason: String) -> void:
	if ended:
		return
	ended = true
	end_reason = reason
	sim.finalize()
	for ctl in controllers:
		ctl.active = false
		ctl.adapter.cancel()
	play_sound("end")
	var rank := sim.ranking()
	var result := {"reason": reason, "active_seconds": active_seconds, "game_time": Catalog.game_minutes_to_text(sim.game_min),
		"ranking": rank.map(func(c): return {"company": c.company_name, "player": c.player_name,
			"profit": snappedf(c.ledger.profit(), 0.01), "revenue": snappedf(c.ledger.revenue(), 0.01),
			"reputation": snappedf(c.reputation, 0.1), "completed": c.stats.completed, "deals": c.stats.deals,
			"sabotage_ok": c.stats.sabotage_ok, "sabotage_caught": c.stats.sabotage_caught,
			"identity_error": snappedf(c.ledger.cash + sim.book_assets(c.id) - c.ledger.debt - c.ledger.start_capital - c.ledger.profit(), 0.0001)}),
		"controllers": controllers.map(func(ctl): return {"player": ctl.cid, "demo": ctl.is_demo(), "stats": ctl.stats,
			"fallback": ctl.fallback_active, "last_error": ctl.last_error}),
		"frame_stats": frame_stats}
	api_log.write({"type": "match_end", "result": result})
	DirAccess.make_dir_recursive_absolute("user://memory")
	for i in cfg.players.size():
		var mf := FileAccess.open("user://memory/slot%d.json" % int(cfg.players[i].slot), FileAccess.WRITE)
		if mf:
			mf.store_string(JSON.stringify(sim.memory.export_experiences(i)))
	var wf := FileAccess.open("user://last_weather.json", FileAccess.WRITE)   # Aufzeichnung fuer Wiederholungen
	if wf:
		wf.store_string(JSON.stringify(sim.wx.log))
	var f := FileAccess.open("user://last_result.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "  "))
	end_screen.visible = true
	end_screen.show_results(sim, reason, controllers)
	finished.emit(self)


func save_game() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var data := {"version": 1, "cfg": cfg, "active_seconds": active_seconds, "sim": sim.to_dict(),
		"controllers": controllers.map(func(c): return c.to_dict()), "executed": sim.executor.executed}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		hud.show_toast("Speichern fehlgeschlagen")
		return
	f.store_string(JSON.stringify(data))
	hud.show_toast("Spielstand gespeichert (ohne API-Keys)")


static func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if d is Dictionary else {}


func back_to_menu() -> void:
	menu_requested.emit()


func follow(sel: Dictionary) -> void:
	entity_view.selected = sel
	following = true


func set_follow(on: bool) -> void:
	following = on and not entity_view.selected.is_empty()


func camera_to(p: Vector2) -> void:
	following = false
	city_view.set_camera_world(p)


func _camera_keys(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		following = false
		city_view.camera.position += dir.normalized() * 700.0 * delta / city_view.camera.zoom.x
	_clamp_camera()


func _clamp_camera() -> void:
	var size := sim.city.size * 32.0
	city_view.set_camera_world(city_view.camera_world().clamp(Vector2.ZERO, Vector2(size, size)))


func _unhandled_input(event: InputEvent) -> void:
	var cam := city_view.camera
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var levels := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
			var i := levels.find(cam.zoom.x)
			if i < 0:
				i = 3
			i = clampi(i + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, levels.size() - 1)
			var before := cam.get_global_mouse_position()
			cam.zoom = Vector2(levels[i], levels[i])
			if not following:
				cam.position += before - cam.get_global_mouse_position()
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var sel := entity_view.pick(cam.get_global_mouse_position())
			entity_view.selected = sel
			following = false
			play_sound("click")
	elif event is InputEventMouseMotion and _dragging:
		following = false
		cam.position -= event.relative / cam.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: toggle_pause()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: set_speed_idx(event.physical_keycode - KEY_1)
			KEY_F: set_follow(not following)
			KEY_ESCAPE: entity_view.selected = {}
			KEY_F5: save_game()
			KEY_TAB: hud.toggle_panels()
