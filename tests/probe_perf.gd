extends SceneTree
## Diagnose: Zeit je Teilsystem bei grosser Karte (nicht Teil der Testliste).
func _t(label: String, f: Callable, reps: int) -> void:
	var t := Time.get_ticks_usec()
	for i in reps:
		f.call()
	print("%-22s %8.3f ms je Aufruf" % [label, (Time.get_ticks_usec() - t) / 1000.0 / reps])

func _initialize() -> void:
	var sz := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 512
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	var s := Simulation.new()
	s.setup(4242, pl, sz, 1.0)
	for i in 600:
		s.step(0.5)
	print("size ", sz, " traffic ", s.traffic.size(), " residents ", s.residents.people.size(), " workers ", s.personnel.workers.size())
	_t("step(0.5)", func(): s.step(0.5), 40)
	_t("_rebuild_hash", func(): s._rebuild_hash(), 40)
	_t("traffic update", func(): for m in s.traffic: s._update_traffic_car(m, 0.5), 40)
	_t("personnel.update", func(): s.personnel.update(0.5), 40)
	_t("_minute_tick", func(): s._minute_tick(), 40)
	var now: float = s.game_min
	_t("market.tick", func(): s.market.tick(now), 40)
	_t("social.tick", func(): s.social.tick(now), 40)
	_t("personnel.minute", func(): s.personnel.minute_tick(now), 40)
	_t("resources.minute", func(): s.resources.minute_tick(now), 40)
	_t("estate.minute", func(): s.estate.minute_tick(now), 40)
	_t("events.minute", func(): s.events.minute_tick(now), 40)
	_t("world_events.minute", func(): s.world_events.minute_tick(now), 40)
	_t("residents.minute", func(): s.residents.minute_tick(now), 40)
	print("contracts ", s.contracts.size(), " offers ", s.resources.available_offers().size(), " supplies ", s.resources.supplies.size(), " open ", s.market.open_contracts().size())
	_t("available_offers", func(): s.resources.available_offers(), 40)
	_t("visible_people", func(): s.residents.visible_people(), 40)
	quit()
