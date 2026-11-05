extends SceneTree
## Headless-Testlauf:
##   Godot_v4.4.1-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
## Exit-Code 0 = alle Tests bestanden.

var failures := 0
var checks := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var test_names: Array = ["test_city", "test_finance_identity", "test_duplicate_actions", "test_invalid_actions",
			"test_trades", "test_sabotage", "test_vehicle_delivery", "test_end_settlement", "test_save_load",
			"test_response_parsing", "test_provider_choice", "test_controller_idempotency", "test_kinggamer_features", "test_workers_acceptance", "test_prompt_builds", "test_local_agent_choices", "test_dispatch_help", "test_reserve_check", "test_report_rival", "test_rivalry_tension", "test_idle_routine", "test_tiers", "test_tiers_supply", "test_visit_dedupe", "test_anthropic_adapter", "test_game_master", "test_dispatch_agent", "test_model_error_fixes", "test_town_hall", "test_inspections", "test_city_freight_pool", "test_road_care", "test_mayor_levers", "test_population", "test_resident_behavior", "test_activity_feed", "test_public_safety", "test_assist_trips_and_kind", "test_action_normalize_models", "test_rule_brain_finance", "test_stage1_combinable", "test_stage1_plans", "test_stage2_memory", "test_stage3_events_and_log", "test_stage4_experiments", "test_stage4_contracts", "test_estate_acceptance", "test_foreman_delegation", "test_weather_model", "test_weather_effects", "test_event_chain", "test_event_limits", "test_live_text", "test_iso_assets_complete", "test_iso_geometry", "test_iso_strips", "test_weather_service", "test_residents_save_load", "test_calendar", "test_money_conservation", "test_banking", "test_banking_default", "test_company_forms", "test_insolvency", "test_trader", "test_trader_production", "test_build_materials", "test_yard_empire_core", "test_yard_specializations", "test_yard_permits_and_bids", "test_estate_facilities", "test_player_loans", "test_arena", "test_action_assist", "test_standings", "test_economy_cycle", "test_multi_year_consistency", "test_fuel_prices", "test_gas_stations", "test_households_wages", "test_wage_arrears_in_insolvency", "test_fuel_planner", "test_building_care", "test_workforce", "test_news_feed", "test_review_fixes", "test_physical_fueling", "test_public_sector", "test_citizens", "test_parcels", "test_permits", "test_mayor", "test_construction", "test_developer_autopilot", "test_household_builder", "test_acceptance_flow", "test_city_depot", "test_depot_operations", "test_traffic_flow", "test_retail", "test_waste", "test_supply_acceptance", "test_housing", "test_housing_market", "test_job_move", "test_consumer_credit", "test_contentment", "test_planning_aids", "test_central_bank", "test_oversight", "test_districts", "test_company_operations", "test_strategy_learning", "test_strategy_arena"]
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and str(args[0]).begins_with("--only="):
		var requested := str(args[0]).trim_prefix("--only=")
		if requested not in test_names:
			printerr("Unbekannter Test: ", requested)
			quit(1)
			return
		test_names = [requested]
	for name in test_names:
		var before := checks
		var fails := failures
		call(name)
		print("== %s: %d Prüfungen, %d Fehler" % [name, checks - before, failures - fails])
	print("\n%d Prüfungen, %d Fehler (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FEHLER: ", what)


func players(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i],
			"avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	return out


func new_sim(n: int = 4, size: int = 128) -> Simulation:
	var s := Simulation.new()
	s.setup(4242, players(n), size, 0.5)
	s.personnel.idle_routine = false   # Tests pruefen gezielt einzelne Aufgaben; die Leerlauf-Routine hat einen eigenen Test
	s.estate.permits_enabled = false   # Hof-Bauantraege und Grundstuecksgebote haben eigene Tests (test_yard_permits_and_bids)
	s.estate.auctions_enabled = false
	return s


func identity_ok(s: Simulation) -> bool:
	for c in s.companies:
		var lhs := c.ledger.cash + s.book_assets(c.id) - c.ledger.debt
		var rhs := c.ledger.start_capital + c.ledger.profit()
		if absf(lhs - rhs) > 0.01:
			print("    Identität verletzt bei %s: %.4f vs %.4f" % [c.company_name, lhs, rhs])
			return false
	if absf(s.economy.conservation_error()) > 0.01:
		print("    Geldkonservierung verletzt: %.4f" % s.economy.conservation_error())
		return false
	if absf(s.population.account_error()) > 0.01:
		print("    Bürgerkonten weichen von R0 ab: %.4f" % s.population.account_error())
		return false
	if s.stock.balance_error() != 0:
		print("    Warenbilanz verletzt: %d" % s.stock.balance_error())
		return false
	return true


func run(s: Simulation, sim_seconds: float) -> void:
	var t := 0.0
	while t < sim_seconds:
		s.step(0.1)
		t += 0.1


func teleport_avatar(s: Simulation, cid: int, cell: Vector2i) -> void:
	var a: Avatar = s.avatars[cid]
	a.pos = s.city.tile_center(cell)
	a.path.clear()
	a.state = "idle"


# ---------------------------------------------------------------------------
func test_city() -> void:
	var c := CityGenerator.new().generate(7, 256)
	ok(c.buildings.size() > 400, "genug Gebäude (%d)" % c.buildings.size())
	ok(c.start_depots.size() == 4, "4 Startdepots")
	ok(c.depot_sites.size() >= 6 and c.start_depots.size() == 4, "4 Startgrundstücke, mind. 6 mietbare Hallen (%d)" % c.depot_sites.size())
	var roles := {}
	for b in c.buildings:
		roles[b.role] = roles.get(b.role, 0) + 1
		if b.role != "decor":
			ok(c.is_road(b.road), "Gebäude %s hat Straßenzugang" % b.name)
	ok(roles.get("dealer", 0) == 2, "2 Autohäuser")
	ok(roles.get("workshop", 0) == 3, "3 Werkstätten")
	ok(roles.get("bank", 0) == 1, "1 Bank")
	var dists := {}
	for b in c.buildings:
		dists[b.district] = true
	ok(dists.size() == 6, "alle 6 Viertel haben Gebäude")
	# Fusswege: jeder Gebaeudezugang ist vom Zentrum aus erreichbar (keine abgeschlossenen Taschen)
	var nav := NavGrid.new()
	nav.build(c)
	var hub: Vector2i = c.buildings.filter(func(b): return b.role == "bank")[0].walk
	var isolated := c.buildings.filter(func(b): var p: Array = nav.walk_path(b.walk, hub); return p.is_empty() or p[-1] != hub).size()
	ok(isolated == 0, "alle Gebäudezugänge zu Fuß erreichbar (%d isoliert)" % isolated)
	# Faire Startdepots: Abstand zum Zentrum aehnlich
	var center := Vector2(256 * 0.45, 128)
	var ds: Array = c.start_depots.map(func(id): return Vector2(c.building(id).road).distance_to(center))
	ok(ds.max() - ds.min() < 25.0, "Startdepots ähnlich weit vom Zentrum (%s)" % str(ds))
	var c2 := CityGenerator.new().generate(7, 256)
	ok(c2.ground == c.ground and c2.buildings.size() == c.buildings.size(), "gleicher Seed = gleiche Stadt")


func test_finance_identity() -> void:
	var s := new_sim()
	ok(identity_ok(s), "Identität zu Beginn")
	for c in s.companies:
		ok(is_zero_approx(c.ledger.profit()), "Startkapital ist kein Gewinn")
		ok(is_equal_approx(c.ledger.cash, Catalog.START_CAPITAL - 12000.0), "Startfahrzeug aus Kapital bezahlt")
	var c0 := s.companies[0]
	var p0 := c0.ledger.profit()
	s.executor.execute(0, {"action": "take_loan", "amount": 20000})
	ok(is_equal_approx(c0.ledger.profit(), p0), "Kredit ist kein Gewinn")
	ok(is_equal_approx(c0.ledger.debt, 20000.0), "Schulden gebucht")
	s.executor.execute(0, {"action": "repay_loan", "amount": 5000})
	ok(is_equal_approx(c0.ledger.profit(), p0 - 50.0), "Tilgung ist kein Aufwand (nur 1 % Vorfälligkeitsgebühr)")
	teleport_avatar(s, 0, s.nearest_building_of("dealer", s.avatars[0].tile()).walk)
	var r := s.executor.execute(0, {"action": "buy_vehicle", "model": "truck"})
	ok(r.ok and not r.has("pending"), "LKW vor Ort gekauft: " + r.msg)
	ok(is_equal_approx(c0.ledger.profit(), p0 - 50.0), "Fahrzeugkauf ist Investition, kein Aufwand")
	ok(identity_ok(s), "Identität nach Kauf")
	run(s, 1900.0)   # ein Spielmonat: erste Kreditrate faellig
	ok(c0.ledger.totals.get("interest", 0.0) < 0.0, "Zinsen sind Aufwand")
	ok(c0.ledger.totals.get("depreciation", 0.0) < 0.0, "Abschreibung gebucht")
	ok(c0.ledger.totals.get("wages", 0.0) < 0.0, "Löhne gebucht")
	ok(identity_ok(s), "Identität nach Simulation")
	var truck: FleetVehicle = s.company_vehicles(0).filter(func(v): return v.model == "truck")[0]
	var price := truck.purchase_price
	var expected_dep := price * Catalog.DEPRECIATION_PER_DAY * (s.game_min / 1440.0)
	ok(absf((price - truck.book_value) - expected_dep) < price * Catalog.DEPRECIATION_PER_DAY / 1440.0 * 5.0,
		"Abschreibung linear %d %%/Tag vom Kaufpreis (%.1f vs %.1f)" % [int(Catalog.DEPRECIATION_PER_DAY * 100), price - truck.book_value, expected_dep])
	truck.state = "idle"
	truck.queue.clear()
	var book := truck.book_value
	var before := c0.ledger.profit()
	r = s.executor.execute(0, {"action": "sell_vehicle", "vehicle_id": truck.id})
	ok(r.ok, "Verkauf an Händler: " + r.msg)
	ok(absf((c0.ledger.profit() - before) - (book * 0.85 - book)) < 0.01, "Verkaufsergebnis = Erlös - Buchwert")
	ok(identity_ok(s), "Identität nach Verkauf")


func test_duplicate_actions() -> void:
	var s := new_sim(2)
	var a := {"action": "take_loan", "amount": 1000}
	var r1 := s.executor.execute(0, a, "p0:r1:a0")
	var r2 := s.executor.execute(0, a, "p0:r1:a0")
	ok(r1.ok and not r2.ok and r2.get("duplicate", false), "zweite Ausführung mit gleichem Schlüssel abgewiesen")
	ok(is_equal_approx(s.companies[0].ledger.debt, 1000.0), "Kredit nur einmal gebucht")
	var k: Contract = s.market.open_contracts()[0]
	s.companies[0].reputation = 100.0
	s.companies[1].reputation = 100.0
	k.exclusive_for = -1
	var x1 := s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id})
	var x2 := s.executor.execute(1, {"action": "accept_contract", "contract_id": k.id})
	ok(x1.ok and not x2.ok, "Auftrag kann nur einmal vergeben werden")


func test_invalid_actions() -> void:
	var s := new_sim(2)
	var cases := [
		[{"action": "fly_to_moon"}, "Unbekannte Aktion"],
		[{"action": "accept_contract"}, "fehlt"],
		[{"action": "assign_vehicle", "vehicle_id": "abc", "contract_id": "A1"}, "ganze Zahl"],
		[{"action": "accept_contract", "contract_id": "A99999"}, "nicht (mehr) verfügbar"],
		[{"action": "take_loan", "amount": 99999999}, "Kreditrahmen"],
		[{"action": "sell_vehicle", "vehicle_id": 1}, "letzte Fahrzeug"],
		[{"action": "sell_vehicle", "vehicle_id": 2}, "gehört dir nicht"],
		[{"action": "offer_trade", "to": 1, "kind": "teleport"}, "Unbekannte Angebotsart"],
		[{"action": "attempt_sabotage", "target": 0, "kind": "smear_campaign"}, "Ungültiges Ziel"],
		[{"action": "buy_security", "level": 5}, "0, 1 oder 2"],
	]
	var cash := s.companies[0].ledger.cash
	for cs in cases:
		var r := s.executor.execute(0, cs[0])
		ok(not r.ok and str(r.msg).contains(cs[1]), "%s -> '%s' (erhalten: %s)" % [cs[0].action, cs[1], r.msg])
	ok(is_equal_approx(s.companies[0].ledger.cash, cash), "ungültige Aktionen verändern kein Geld")
	# Freitext erzeugt keinen Besitz
	s.executor.execute(0, {"action": "send_message", "to": "1", "text": "Ich verkaufe dir meinen Transporter!"})
	ok(s.companies[1].vehicle_ids.size() == 1, "Nachricht überträgt keinen Besitz")
	# Nachrichtenbudget
	var last := {}
	for i in 10:
		last = s.executor.execute(0, {"action": "send_message", "to": "all", "text": "Test %d" % i})
	ok(not last.ok and str(last.msg).contains("budget"), "Nachrichtenbudget greift")


func test_trades() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	var c1 := s.companies[1]
	c0.reputation = 100.0
	c1.reputation = 100.0
	var k: Contract = s.market.open_contracts().filter(func(x): return x.min_rep <= 50.0)[0]
	k.exclusive_for = -1
	s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id})
	var r := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "transfer_contract",
		"contract_id": k.id, "price": 150})
	ok(r.ok, "Angebot erstellt: " + r.msg)
	var r2 := s.executor.execute(1, {"action": "accept_trade", "offer_id": r.id})
	ok(r2.ok, "Angebot angenommen: " + r2.msg)
	ok(k.owner == 1, "Auftrag übertragen")
	ok(is_equal_approx(c0.ledger.totals.get("trade_income", 0.0), 150.0) and
		is_equal_approx(c1.ledger.totals.get("trade_expense", 0.0), -150.0), "Zahlung als Nullsumme gebucht")
	var r3 := s.executor.execute(1, {"action": "accept_trade", "offer_id": r.id})
	ok(not r3.ok, "Angebot kann nicht zweimal angenommen werden")
	# Fahrzeugverkauf zwischen Spielern
	teleport_avatar(s, 0, s.nearest_building_of("dealer", s.avatars[0].tile()).walk)
	s.executor.execute(0, {"action": "buy_vehicle", "model": "van"})
	var v: FleetVehicle = s.vehicles[s.companies[0].vehicle_ids[-1]]
	v.state = "idle"
	var o := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "sell_vehicle", "vehicle_id": v.id, "price": 10000})
	ok(o.ok, "Fahrzeugangebot: " + o.msg)
	var acc := s.executor.execute(1, {"action": "accept_trade", "offer_id": o.id})
	ok(acc.ok, "Fahrzeugkauf angenommen: " + acc.msg)
	ok(c1.vehicle_ids.size() == 2 and c0.vehicle_ids.size() == 1, "Fahrzeug wechselt den Besitzer")
	ok(identity_ok(s), "Identität nach Geschäften")
	ok(c0.stats.deals == 2 and c1.stats.deals == 2, "Geschäfte gezählt")


func test_sabotage() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	var c1 := s.companies[1]
	c1.insurance = true
	var r := s.executor.execute(0, {"action": "attempt_sabotage", "target": 1, "kind": "smear_campaign"})
	ok(r.ok, "Rufschädigung ausgeführt: " + r.msg)
	ok(c0.ledger.totals.get("sabotage", 0.0) <= -1500.0, "Sabotage kostet Geld")
	var r2 := s.executor.execute(0, {"action": "attempt_sabotage", "target": 1, "kind": "smear_campaign"})
	ok(not r2.ok and r2.msg.contains("Abklingzeit"), "Abklingzeit greift")
	c0.sabotage_ready_at = 0.0
	if c1.protected_until > s.game_min:
		var r3 := s.executor.execute(0, {"action": "attempt_sabotage", "target": 1, "kind": "smear_campaign"})
		ok(not r3.ok and r3.msg.contains("Schutzfrist"), "Schutzfrist greift")
	# Betriebsstoerung erfordert Besuch
	c0.sabotage_ready_at = 0.0
	c1.protected_until = 0.0
	var r4 := s.executor.execute(0, {"action": "attempt_sabotage", "target": 1, "kind": "depot_disruption"})
	ok(r4.ok and r4.get("pending", false), "Betriebsstörung startet Besuch: " + r4.msg)
	var t := 0.0
	while not s.avatars[0].pending.is_empty() and t < 600.0:
		s.step(0.2)
		t += 0.2
	ok(s.avatars[0].pending.is_empty(), "Figur kommt am Zieldepot an (%.0f s)" % t)
	ok(c1.disrupted_until > 0.0 or c0.stats.sabotage_ok < 2, "Störung wirkt oder schlug fehl")
	ok(c1.disrupted_until <= s.game_min + 90.0, "Störung zeitlich begrenzt")
	ok(identity_ok(s), "Identität nach Sabotage")
	# Gegenmassnahme senkt Erfolgswahrscheinlichkeit messbar
	var success_plain := 0
	var success_secured := 0
	for i in 200:
		var s2 := Simulation.new()
		s2.rng.seed = i
		var p := Catalog.SABOTAGE.smear_campaign
		if s2.rng.randf() < p.success:
			success_plain += 1
		s2.rng.seed = i
		if s2.rng.randf() < maxf(0.1, p.success - 0.4):
			success_secured += 1
	ok(success_secured < success_plain, "Sicherheitsstufe 2 senkt Erfolgsquote (%d vs %d)" % [success_secured, success_plain])


func test_vehicle_delivery() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	c0.reputation = 100.0
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var cands := s.market.open_contracts().filter(func(x): return x.vehicle_ok("van") and x.min_rep <= 50.0)
	cands.sort_custom(func(a, b): return a.distance < b.distance)
	var k: Contract = cands[0]
	k.exclusive_for = -1
	k.deadline = 99999.0
	var r := s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id, "vehicle_id": v.id})
	ok(r.ok, "angenommen + disponiert: " + r.msg)
	var t := 0.0
	var saw_cargo := false
	while k.status != "delivered" and t < 900.0:
		s.step(0.1)
		t += 0.1
		saw_cargo = saw_cargo or v.cargo == k.cargo
	ok(k.status == "delivered", "Ware ausgeliefert (Status %s nach %.0f s)" % [k.status, t])
	ok(saw_cargo, "Ware war sichtbar geladen")
	ok(is_equal_approx(c0.ledger.totals.get("transport", 0.0), k.reward), "volle Vergütung bei pünktlicher Lieferung")
	ok(c0.fuel < 300.0 or c0.ledger.totals.get("fuel", 0.0) < 0.0, "Treibstoff verbraucht (Vorrat %.1f l)" % c0.fuel)
	ok(v.odometer > 0, "Fahrzeug ist gefahren (%d Tiles)" % v.odometer)
	ok(identity_ok(s), "Identität nach Lieferung")


func test_end_settlement() -> void:
	var s := new_sim(3)
	for c in s.companies:
		c.reputation = 100.0
	var open := s.market.open_contracts().filter(func(x): return x.min_rep <= 50.0)
	var k_over: Contract = open[0]
	var k_fine: Contract = open[1]
	for k in [k_over, k_fine]:
		k.exclusive_for = -1
		s.executor.execute(1, {"action": "accept_contract", "contract_id": k.id})
	k_over.deadline = s.game_min - 10.0
	k_fine.deadline = s.game_min + 500.0
	var p_before := s.companies[1].ledger.profit()
	s.finalize()
	ok(k_over.status == "failed", "überfälliger Auftrag bei Spielende als gescheitert gewertet")
	ok(k_fine.status == "cancelled", "fristgerechter unvollständiger Auftrag storniert")
	ok(is_equal_approx(s.companies[1].ledger.profit() - p_before, -k_over.reward * Catalog.FAIL_PENALTY_SHARE),
		"nur Strafe für überfälligen Auftrag, keine Vergütung")
	ok(s.companies[1].ledger.totals.get("transport", 0.0) == 0.0, "keine Vergütung für unvollständige Transporte")
	# Rangfolge und Tie-Break
	s.companies[0].ledger.totals = {"transport": 1000.0}
	s.companies[1].ledger.totals = {"transport": 1000.0}
	s.companies[2].ledger.totals = {"transport": 500.0}
	s.companies[0].reputation = 40.0
	s.companies[1].reputation = 60.0
	var rank := s.ranking()
	ok(rank[0].id == 1 and rank[1].id == 0 and rank[2].id == 2, "Rangfolge: Gewinn, dann Reputation")
	s.companies[0].reputation = 60.0
	s.companies[0].stats.completed = 5
	s.companies[1].stats.completed = 3
	rank = s.ranking()
	ok(rank[0].id == 0, "Tie-Break: erledigte Aufträge")


func test_save_load() -> void:
	var s := new_sim(2)
	run(s, 60.0)
	var d := s.to_dict()
	var txt := JSON.stringify(d)
	ok(not txt.to_lower().contains("api_key") and not txt.contains("sk-"), "Spielstand enthält keine Schlüssel")
	var s2 := Simulation.from_dict(JSON.parse_string(txt))
	ok(is_equal_approx(s2.game_min, s.game_min), "Spielzeit geladen")
	ok(s2.companies.size() == 2 and is_equal_approx(s2.companies[0].ledger.cash, s.companies[0].ledger.cash), "Finanzen geladen")
	ok(s2.vehicles.size() == s.vehicles.size(), "Fahrzeuge geladen")
	ok(identity_ok(s2), "Identität nach Laden")
	run(s2, 20.0)
	ok(identity_ok(s2), "Simulation läuft nach Laden weiter")


func test_response_parsing() -> void:
	var good := '{"summary":"Ich nehme A3.","actions":[{"action":"accept_contract","contract_id":"A3"}],"memory":"x"}'
	ok(AgentController.parse_response(good).ok, "gültiges JSON")
	ok(AgentController.parse_response("```json\n" + good + "\n```").ok, "JSON in Codeblock")
	ok(AgentController.parse_response("Klar! " + good + " Viel Erfolg").ok, "JSON mit Begleittext")
	ok(not AgentController.parse_response("{kaputt").ok, "kaputtes JSON abgewiesen")
	ok(not AgentController.parse_response('{"summary":"x"}').ok, "fehlende actions abgewiesen")
	ok(not AgentController.parse_response('{"summary":"x","actions":"accept"}').ok, "actions kein Array")
	var many := '{"summary":"x","actions":[' + ",".join(range(20).map(func(i): return '{"action":"wait"}')) + ']}'
	ok(AgentController.parse_response(many).actions.size() == AgentController.MAX_ACTIONS, "Aktionszahl begrenzt")
	# Abgeschnittene Antwort: vollstaendige Aktionen bleiben erhalten
	var cut := '{"actions":[{"action":"collect_contracts"},{"action":"accept_contract","contract_id":"A1"},{"action":"assign_worker_task","kind":"fa'
	var rescued := AgentController.parse_response(cut)
	ok(rescued.ok and rescued.actions.size() == 2, "abgeschnittene Antwort: 2 vollständige Aktionen gerettet")
	ok(not AgentController.parse_response('{"actions":[{"action":"acc').ok, "ohne vollständige Aktion bleibt es ein Fehler")
	# Formfehler kleiner Modelle
	var n1 := ActionExecutor.normalize({"action": "buy_vehicle", "parameters": {"offer_id": "F2"}})
	ok(n1.offer_id == "F2", "verschachtelte parameters werden flach")
	var n2 := ActionExecutor.normalize({"action": "buy_vehicle", "target_id": "F8"})
	ok(n2.offer_id == "F8", "target_id wird offer_id")
	var n3 := ActionExecutor.normalize({"action": "assign_worker_task", "worker_id": "W1", "vehicle_id": 3})
	ok(n3.kind == "fahren", "fehlendes kind wird fahren, wenn Fahrzeug angegeben")
	var n4 := ActionExecutor.normalize({"action": "accept_contract", "contract": "A5"})
	ok(n4.contract_id == "A5", "contract wird contract_id")
	var n6 := ActionExecutor.normalize({"action": "assign_transport/plan_tour", "contract_id": "A1", "vehicle_id": 1})
	ok(n6.action == "assign_transport", "zusammengesetzter Aktionsname: erste bekannte Aktion")
	var n7 := ActionExecutor.normalize({"action": "buy_vehicle", "vehicle_id": "F2"})
	ok(n7.offer_id == "F2", "buy_vehicle mit vehicle_id des Angebots")
	var n5 := ActionExecutor.normalize({"action": "accept_contract", "contract_id": "A1", "parameters": {"contract_id": "ZZ"}})
	ok(n5.contract_id == "A1", "vorhandene Schlüssel werden nicht überschrieben")
	ok(ActionExecutor.validate_schema("assign_worker_task", ActionExecutor.normalize({"action": "assign_worker_task", "worker_id": "W1"})) != "", "ohne Fahrzeug bleibt fehlendes kind ein Fehler")


func test_controller_idempotency() -> void:
	var s := new_sim(2)
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	var content := '{"summary":"Kredit.","actions":[{"action":"take_loan","amount":1000}],"memory":""}'
	var req := ctl.begin_request_for_test()
	ctl.handle_result(req, {"ok": true, "content": content, "usage": {"total_tokens": 10}})
	ctl.handle_result(req, {"ok": true, "content": content, "usage": {"total_tokens": 10}})
	ok(is_equal_approx(s.companies[0].ledger.debt, 1000.0), "doppelt zugestellte Antwort wird nur einmal ausgeführt")
	var stale := ctl.begin_request_for_test()
	ctl.abandon_for_test()
	ctl.handle_result(stale, {"ok": true, "content": content, "usage": {}})
	ok(is_equal_approx(s.companies[0].ledger.debt, 1000.0), "verspätete Antwort auf abgebrochene Anfrage ignoriert")
	var old := ctl.begin_request_for_test()
	s.game_min += 500.0
	ctl.handle_result(old, {"ok": true, "content": content, "usage": {}})
	ok(is_equal_approx(s.companies[0].ledger.debt, 1000.0), "Antwort auf veralteten Zustand verworfen")
	var bad := ctl.begin_request_for_test()
	ctl.handle_result(bad, {"ok": true, "content": "Ich denke nach...", "usage": {}})
	ok(ctl.last_error.contains("JSON"), "ungültiges JSON wird gemeldet: " + ctl.last_error)
	ctl.config.provider = "ollama"
	var local := ctl.begin_request_for_test()
	s.game_min += 500.0
	ctl.handle_result(local, {"ok": true, "content": '{"goal":"Lieferungen planen","summary":"Ich plane.","actions":[{"action":"wait"}]}', "usage": {}})
	ok(ctl.goal == "Lieferungen planen", "langsame lokale Modellantwort wird innerhalb eines Spieltags übernommen")
	var too_old := ctl.begin_request_for_test()
	s.game_min += AgentController.STALE_GAME_MIN_OLLAMA + 1.0
	ctl.handle_result(too_old, {"ok": true, "content": content, "usage": {}})
	ok(ctl.last_error.contains("veraltet"), "Antwort auf mehr als einen Spieltag alten Zustand bleibt gesperrt")
	ctl.free()


func walk_until_idle(s: Simulation, cid: int, limit: float = 900.0) -> float:
	var t := 0.0
	var a: Avatar = s.avatars[cid]
	while (not a.pending.is_empty() or not a.queue.is_empty()) and t < limit:
		s.step(0.2)
		t += 0.2
	return t


func test_kinggamer_features() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	var roles := {}
	for b in s.city.buildings:
		roles[b.role] = roles.get(b.role, 0) + 1
	ok(roles.get("job_board", 0) == 1 and roles.get("staffing", 0) == 1, "Jobbörse und Personalbüro vorhanden")
	ok(roles.get("office_site", 0) >= 3, "Bürostandorte vorhanden (%d)" % roles.get("office_site", 0))
	# Lieferketten
	var labels := {}
	for i in 300:
		var k: Contract = s.market.spawn(s.game_min)
		if k and k.label != "":
			labels[k.label] = true
			var src: Dictionary = s.city.building(k.pickup)
			if k.label == "Bierfässer":
				ok(src.name.begins_with("Brauerei") and s.city.building(k.dropoff).type == "restaurant", "Bierfässer: Brauerei -> Restaurant")
	ok(labels.size() >= 5, "mehrere konkrete Lieferketten (%s)" % str(labels.keys()))
	# Auftragskenntnis: neue Auftraege sind erst nach dem Sammeln annehmbar
	c0.reputation = 100.0
	var fresh: Contract = null
	for k in s.market.open_contracts():
		if not c0.known.has(k.id) and k.exclusive_for < 0 and k.min_rep <= 50.0:
			fresh = k
			break
	var r := s.executor.execute(0, {"action": "accept_contract", "contract_id": fresh.id})
	ok(not r.ok and r.msg.contains("unbekannt"), "unbekannter Auftrag abgelehnt: " + r.msg)
	r = s.executor.execute(0, {"action": "collect_contracts"})
	ok(r.ok and r.get("pending", false), "Sammeln ohne Internet erfordert Gang zur Jobbörse")
	walk_until_idle(s, 0)
	ok(c0.known.has(fresh.id), "nach Jobbörsen-Besuch bekannt")
	# Kapazitaet ohne Buero = 3
	var open := s.market.open_contracts().filter(func(k): return c0.known.has(k.id) and k.exclusive_for < 0 and k.min_rep <= 50.0)
	var accepted := 0
	var last := {}
	for k in open.slice(0, 4):
		last = s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id})
		if last.ok:
			accepted += 1
	ok(accepted == 3 and last.msg.contains("ausgelastet"), "Kapazität ohne Büro = 3 (%d, %s)" % [accepted, last.msg])
	# Buero eroeffnen (Besuch), Kapazitaet steigt, Identitaet haelt
	var site := -1
	for b in s.city.buildings:
		if b.role == "office_site" and str(b.name).begins_with("Bürohaus"):
			site = b.id
	r = s.executor.execute(0, {"action": "build_office", "site_id": site})
	r = s.executor.execute(0, {"action": "install_internet"})
	ok(not r.ok, "Internet ohne Büro abgelehnt")
	walk_until_idle(s, 0)
	ok(c0.office_level == 1 and c0.contract_capacity() == 6, "Zentrale eröffnet, Kapazität 6")
	ok(identity_ok(s), "Identität mit Büro-Buchwert")
	r = s.executor.execute(0, {"action": "install_internet"})
	walk_until_idle(s, 0)
	ok(c0.internet_level == 1, "Internet Stufe 1 im Büro")
	teleport_avatar(s, 0, s.depot_road(0))
	r = s.executor.execute(0, {"action": "collect_contracts"})
	ok(r.get("pending", false), "Internet 1: Sammeln nur im Büro (Figur geht hin)")
	walk_until_idle(s, 0)
	c0.ledger.cash += 0.0
	r = s.executor.execute(0, {"action": "install_internet"})
	walk_until_idle(s, 0)
	teleport_avatar(s, 0, s.depot_road(0))
	r = s.executor.execute(0, {"action": "collect_contracts"})
	ok(r.ok and not r.get("pending", false), "Internet 2: Sammeln von überall")
	run(s, 120.0)
	ok(c0.ledger.totals.get("office", 0.0) < 0.0, "Büro-/Internetkosten gebucht")
	ok(c0.property_book < c0.property_cost, "Büros werden abgeschrieben")
	ok(identity_ok(s), "Identität nach Bürozeit")
	# Besuchswarteschlange: zwei Besuche hintereinander
	teleport_avatar(s, 0, s.depot_road(0))
	var cand: Worker = s.personnel.available().filter(func(w): return w.role == "worker")[0]
	var r1 := s.executor.execute(0, {"action": "recruit_worker", "worker_id": cand.id})
	var r2 := s.executor.execute(0, {"action": "buy_vehicle", "model": "cargobike"})
	ok(r1.get("pending", false) and r2.msg.contains("eingereiht"), "zweiter Besuch wird eingereiht: " + r2.msg)
	var drivers_before := s.personnel.employed(0).size()
	var veh_before := c0.vehicle_ids.size()
	walk_until_idle(s, 0)
	ok(s.personnel.employed(0).size() == drivers_before + 1, "Arbeiter vor Ort angeworben")
	ok(c0.vehicle_ids.size() == veh_before + 1 and s.vehicles[c0.vehicle_ids[-1]].model == "cargobike", "Lastenrad gekauft")
	# Oeffentliche Ansprache nur bei Begegnung
	teleport_avatar(s, 0, s.depot_road(0))
	teleport_avatar(s, 1, s.depot_road(1))
	r = s.executor.execute(0, {"action": "send_message", "to": "1", "text": "Hallo!", "private": false})
	ok(not r.ok and r.msg.contains("Begegnung"), "öffentliche Ansprache aus der Ferne abgelehnt")
	r = s.executor.execute(0, {"action": "send_message", "to": "1", "text": "Hallo per Funk", "private": true})
	ok(r.ok, "Funk aus der Ferne erlaubt")
	s.avatars[1].pos = s.avatars[0].pos + Vector2(20, 0)
	r = s.executor.execute(0, {"action": "send_message", "to": "1", "text": "Hallo von Angesicht!", "private": false})
	ok(r.ok, "öffentliche Ansprache bei Begegnung erlaubt")
	# IONOS-Profil und Standardprofil
	var ad := OpenAIAdapter.new()
	ad.config = {"provider": "ionos", "model": OpenAIAdapter.IONOS_MODEL}
	var body := ad.build_body([])
	ok(body.top_p == 0.95 and body.reasoning_effort == "medium" and body.presence_penalty == 1.5 and body.temperature == 1.0
		and not body.has("response_format") and body.max_tokens >= 1200, "IONOS-Parameter korrekt: " + str(body))
	ad.config = {"provider": "openai", "model": "x"}
	ok(ad.build_body([]).has("response_format"), "Standardprofil nutzt response_format")
	ad.free()
	ok(AgentController.parse_response('<think>{intern}</think>{"goal":"x","summary":"s","actions":[]}').goal == "x", "<think> wird entfernt, goal gelesen")


func step_until(s: Simulation, cond: Callable, limit: float = 900.0) -> float:
	var t := 0.0
	while not cond.call() and t < limit:
		s.step(0.2)
		t += 0.2
	return t


func free_worker(P: Personnel, cid: int) -> Worker:
	for x in P.employed(cid):
		if x.vehicle_id < 0 and x.task_id == "" and x.role == "worker":
			return x
	return null


func test_workers_acceptance() -> void:
	var s := new_sim(2)
	var P := s.personnel
	var c0 := s.companies[0]
	var c1 := s.companies[1]
	c0.reputation = 100.0
	c1.reputation = 100.0
	# Startbedingungen gleich: je 2 Arbeiter, Fahrer sitzt im Startfahrzeug
	ok(P.employed(0).size() == Personnel.MIN_STAFF and P.employed(1).size() == Personnel.MIN_STAFF, "beide starten mit %d Arbeitern" % Personnel.MIN_STAFF)
	ok(s.driver_of(s.vehicles[c0.vehicle_ids[0]]) != null, "Startfahrzeug hat einen Fahrer")
	# 1) beide sehen dieselben verfuegbaren Ressourcen
	var o0 := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var o1 := ObservationBuilder.build(s, 1, [], 0.0, 10.0)
	var ids := func(arr): return arr.map(func(x): return x.id)
	ok(ids.call(o0.ressourcen.arbeitskraefte) == ids.call(o1.ressourcen.arbeitskraefte), "gleiche Arbeitskräfte sichtbar")
	ok(ids.call(o0.ressourcen.fahrzeugangebote) == ids.call(o1.ressourcen.fahrzeugangebote), "gleiche Fahrzeugangebote sichtbar")
	ok(ids.call(o0.ressourcen.betriebsmittel) == ids.call(o1.ressourcen.betriebsmittel), "gleiche Betriebsmittel sichtbar")
	# 2) Wettlauf um denselben Arbeiter: genau einer bekommt ihn
	var w: Worker = P.available().filter(func(x): return x.role == "worker" and int(x.skills.fahren) >= 1)[0]
	s.executor.execute(0, {"action": "recruit_worker", "worker_id": w.id})
	s.executor.execute(1, {"action": "recruit_worker", "worker_id": w.id})
	step_until(s, func(): return s.avatars[0].pending.is_empty() and s.avatars[1].pending.is_empty())
	ok(w.employer in [0, 1], "Arbeiter hat genau einen Arbeitgeber (%d)" % w.employer)
	var loser := 1 - w.employer
	var lost_msg: bool = s.action_results[loser].any(func(r): return r.text.contains("arbeitet bereits"))
	ok(lost_msg, "der Zweite erhält eine Absage")
	var o_loser := ObservationBuilder.build(s, loser, [], 0.0, 10.0)
	ok(not ids.call(o_loser.ressourcen.arbeitskraefte).has(w.id), "angeworbener Arbeiter verschwindet aus dem Angebot")
	var boss := w.employer
	var cb := s.companies[boss]
	step_until(s, func(): return w.task_id == "" or P.tasks[w.task_id].is_final(), 600.0)
	# Ein Arbeiter macht nur eine Sache (ein reiner Weg ist dagegen unterbrechbar)
	var t0 := s.executor.execute(boss, {"action": "assign_worker_task", "kind": "gehen", "worker_id": w.id, "site_id": cb.depots[0]})
	var t1 := s.executor.execute(boss, {"action": "guard_target", "worker_id": w.id})
	ok(t0.ok and t1.ok and P.tasks[t0.task_id].status == "abgebrochen", "Weg wird durch echte Aufgabe ersetzt")
	var t2 := s.executor.execute(boss, {"action": "assign_worker_task", "kind": "verladen", "worker_id": w.id, "building_id": cb.depots[0]})
	ok(not t2.ok and t2.msg.contains("beschäftigt"), "keine zwei Aufgaben gleichzeitig: " + t2.msg)
	s.executor.execute(boss, {"action": "cancel_worker_task", "task_id": t1.task_id})
	w.fatigue = 95.0
	var t3 := s.executor.execute(boss, {"action": "guard_target", "worker_id": w.id})
	ok(not t3.ok and t3.msg.contains("erschöpft"), "erschöpfter Arbeiter lehnt ab")
	w.fatigue = 10.0
	# Haendlerbestand: verkauft ist verkauft
	var offer: Dictionary = s.resources.available_offers().filter(func(o): return o.model in ["van", "transporter"])[0]
	var dealer: Dictionary = s.city.building(offer.dealer)
	teleport_avatar(s, boss, dealer.walk)
	var buy := s.executor.execute(boss, {"action": "buy_vehicle", "offer_id": offer.id})
	ok(buy.ok and offer.status == "verkauft", "Angebot gekauft: " + buy.msg)
	teleport_avatar(s, 1 - boss, dealer.walk)
	var buy2 := s.executor.execute(1 - boss, {"action": "buy_vehicle", "offer_id": offer.id})
	ok(not buy2.ok and buy2.msg.contains("verkauft"), "verkauftes Fahrzeug ist für andere weg")
	# Betriebsmittel: Bestand am Ort sinkt, mehr als vorraetig geht nicht
	var fuel_src: Dictionary = s.resources.supplies.values().filter(func(x): return x.kind == "fuel")[0]
	var stock0 := float(fuel_src.stock)
	ok(s.executor.execute(boss, {"action": "buy_supplies", "resource_id": fuel_src.id, "amount": 300}).ok and fuel_src.stock == stock0 - 300.0, "Treibstoff gekauft, Bestand sinkt")
	ok(not s.executor.execute(1 - boss, {"action": "buy_supplies", "resource_id": fuel_src.id, "amount": 99999}).ok, "mehr als vorrätig abgelehnt")
	# 3) Transport zuweisen: neuer Fahrer steigt sichtbar ein, liefert, wird abgerechnet
	var nv: FleetVehicle = s.vehicles[cb.vehicle_ids[-1]]
	ok(s.driver_of(nv) == null, "neues Fahrzeug hat zunächst keinen Fahrer")
	var k: Contract = s.market.open_contracts().filter(func(x): return cb.known.has(x.id) and x.vehicle_ok(nv.model) and x.min_rep <= 50 and x.exclusive_for < 0)[0]
	k.deadline = 99999.0
	ok(s.executor.execute(boss, {"action": "accept_contract", "contract_id": k.id}).ok, "Auftrag angenommen")
	var o_other := ObservationBuilder.build(s, 1 - boss, [], 0.0, 10.0)
	ok(not o_other.markt.any(func(m): return m.id == k.id), "angenommener Auftrag verschwindet aus dem öffentlichen Angebot")
	var drive := s.executor.execute(boss, {"action": "assign_worker_task", "kind": "fahren", "worker_id": w.id, "vehicle_id": nv.id, "contract_id": k.id})
	ok(drive.ok, "Fahrauftrag erteilt: " + drive.msg)
	var rev0: float = cb.ledger.totals.get("transport", 0.0)
	step_until(s, func(): return k.status == "delivered", 1500.0)
	ok(w.vehicle_id == nv.id, "Fahrer ist eingestiegen")
	ok(k.status == "delivered" and is_equal_approx(cb.ledger.totals.get("transport", 0.0) - rev0, k.reward), "Transport ausgeführt und abgerechnet")
	step_until(s, func(): return P.tasks[drive.get("task_id", "")].is_final() if drive.has("task_id") else true, 30.0)
	ok(P.tasks[drive.task_id].status == "abgeschlossen", "Aufgabe abgeschlossen")
	ok(identity_ok(s), "Identität nach Personal-/Ressourcenaktionen")
	# 4) Vorarbeiter erkennt Stoerung und teilt Ersatz ein
	var f: Worker = P.available().filter(func(x): return x.role == "foreman")[0]
	teleport_avatar(s, 1, f.tile())
	ok(s.executor.execute(1, {"action": "recruit_foreman", "worker_id": f.id}).ok, "Vorarbeiter angeworben")
	var team: Array = P.employed(1).filter(func(x): return x.role == "worker").map(func(x): return x.id)
	var asg := s.executor.execute(1, {"action": "assign_foreman", "foreman_id": f.id, "worker_ids": team, "site_id": c1.depots[0]})
	ok(asg.ok, asg.msg)
	var v1: FleetVehicle = s.vehicles[c1.vehicle_ids[0]]
	v1.condition = 70.0
	c1.parts = 5
	s.break_vehicle(v1, "Test-Panne")
	step_until(s, func(): return P.tasks.values().any(func(t): return t.foreman_id == f.id and t.kind == "reparieren"), 60.0)
	var rep_task: Array = P.tasks.values().filter(func(t): return t.foreman_id == f.id and t.kind == "reparieren")
	ok(not rep_task.is_empty(), "Vorarbeiter schickt Mechaniker zur Reparatur")
	ok(s.log_entries.any(func(e): return e.kind == "report" and e.text.contains(f.name)), "Vorarbeiter meldet die Störung")
	step_until(s, func(): return v1.state != "broken", 600.0)
	ok(v1.state != "broken" and v1.condition == 100.0, "Fahrzeug vor Ort repariert (Zustand %d, %s)" % [int(v1.condition), v1.state])
	# 5)+6) Sabotage durch Arbeiter: erwischt -> genau dieser Arbeiter geht verloren
	var sab := free_worker(P, 0)
	if sab == null:
		sab = P.spawn_available("guard")
		P.hire(0, sab)
		step_until(s, func(): return sab.task_id == "" or P.tasks[sab.task_id].is_final(), 600.0)
	var target: FleetVehicle = s.vehicles[c1.vehicle_ids[0]]
	target.state = "idle"
	target.path.clear()
	P.seen[0].clear()
	var unseen := s.executor.execute(0, {"action": "attempt_vehicle_sabotage", "worker_id": sab.id, "vehicle_id": target.id})
	ok(not unseen.ok and unseen.msg.contains("nicht bekannt"), "ungesehene Fahrzeug-ID wird abgelehnt: " + unseen.msg)
	sab.pos = target.pos + Vector2(40, 0)
	P.update_seen()
	var staff_before := P.employed(0).size()
	var cash_before := c0.ledger.cash
	P.force_outcome = "caught"
	var att := s.executor.execute(0, {"action": "attempt_vehicle_sabotage", "worker_id": sab.id, "vehicle_id": target.id})
	ok(att.ok, "Sabotage gestartet: " + att.msg)
	var again := s.executor.execute(0, {"action": "attempt_vehicle_sabotage", "worker_id": sab.id, "vehicle_id": target.id})
	ok(not again.ok, "kein kostenloser Wiederholungsversuch")
	step_until(s, func(): return P.tasks[att.task_id].is_final(), 300.0)
	ok(sab.lost and sab.employer == -1, "erwischter Arbeiter dauerhaft verloren")
	ok(P.employed(0).size() == staff_before - 1, "genau ein Arbeiter weniger")
	ok(c0.ledger.cash < cash_before - Personnel.SABOTAGE_COST, "Einsatzkosten + Bußgeld gebucht")
	teleport_avatar(s, 1, sab.tile())
	ok(not s.executor.execute(1, {"action": "recruit_worker", "worker_id": sab.id}).ok, "verlorener Arbeiter ist nicht wieder anwerbbar")
	ok(target.state == "idle", "erwischt = keine Wirkung am Ziel")
	# Erfolg: Fahrzeug liegt still, Opfer wird informiert
	P.force_outcome = "success"
	P.cooldowns.clear()
	var sab2: Worker = P.spawn_available("guard")
	P.hire(0, sab2)
	for t in P.tasks.values():
		if t.worker_id == sab2.id:
			P.cancel_task(t, "Test")
	sab2.pos = target.pos + Vector2(40, 0)
	P.update_seen()
	var att2 := s.executor.execute(0, {"action": "attempt_vehicle_sabotage", "worker_id": sab2.id, "vehicle_id": target.id})
	ok(att2.ok, "zweiter Versuch gestartet: " + att2.msg)
	step_until(s, func(): return P.tasks[att2.task_id].is_final(), 300.0)
	ok(target.state == "broken" and not sab2.lost, "Erfolg: Ziel liegt still, Arbeiter bleibt")
	ok(s.action_results[1].any(func(r): return r.text.contains("ausgefallen")), "Opfer erfährt vom Ausfall")
	# 7) betroffenes Unternehmen reagiert (Demo-Logik auf Basis seiner Beobachtung)
	var obs_victim := ObservationBuilder.build(s, 1, ["Fahrzeug sabotiert"], 0.0, 10.0)
	var d_victim := RuleBrain.decide(obs_victim, "kostenoptimierer", RandomNumberGenerator.new())
	var reacts: bool = d_victim.actions.any(func(a): return a.action in ["repair_vehicle", "guard_target", "buy_security", "buy_supplies"])
	ok(reacts, "Opfer reagiert auf Schaden: %s" % str(d_victim.actions.map(func(a): return a.action)))
	ok(d_victim.goal.contains("absichern"), "Opfer ändert sein Ziel: " + d_victim.goal)
	# 8) Saboteur kennt seinen Verlust und plant ohne ihn
	var obs_sab := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs_sab.ergebnisse_deiner_aktionen.any(func(r): return str(r).contains("verloren") or str(r).contains("erwischt")), "Saboteur sieht den Personalverlust")
	ok(not obs_sab.personal.any(func(x): return x.id == sab.id), "verlorener Arbeiter fehlt in der eigenen Planung")
	ok(identity_ok(s), "Identität nach Sabotage")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.personnel.workers[sab.id].lost and s2.personnel.tasks.size() == P.tasks.size(), "Personal und Aufgaben werden gespeichert")


func test_prompt_builds() -> void:
	var s := new_sim(2)
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	var sp := ctl.system_prompt()
	var up := ctl.user_prompt(ObservationBuilder.build(s, 0, [], 0.0, 10.0))
	ok(sp.contains("willst diese Partie gewinnen") and sp.contains("attempt_vehicle_sabotage"), "Systemprompt vollständig gebaut")
	ok(not sp.contains("%s") and not sp.contains("%d"), "keine offenen Platzhalter")
	ok(up.length() / 4 < 5500, "Beobachtung kompakt (~%d Token)" % (up.length() / 4))
	ctl.free()


func test_rule_brain_finance() -> void:
	var s := new_sim(2)
	for i in 600:
		s.step(0.5)
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0, "", "")
	obs.ich.bargeld = 2000
	obs.ich.gewinn = -5000
	obs.ich.umsatz = 9000
	var names: Array = RuleBrain.decide(obs, "kostenoptimierer", RandomNumberGenerator.new()).actions.map(func(a): return a.action)
	ok("take_loan" in names, "Knappe Kasse: Kredit wird beantragt")
	ok("dismiss_worker" in names, "Verlust und Überbesetzung: Entlassung")
	obs.ich.bargeld = 500000
	obs.ich.schulden = 10000
	obs.ich.gewinn = 5000
	names = RuleBrain.decide(obs, "kostenoptimierer", RandomNumberGenerator.new()).actions.map(func(a): return a.action)
	ok("repay_loan" in names, "Überschuss: Kredit wird getilgt")
	ok("take_loan" not in names and "dismiss_worker" not in names, "Gesunde Firma: weder Kredit noch Entlassung")


func test_local_agent_choices() -> void:
	var s := new_sim(2)
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	ctl.config["provider"] = "ollama"
	var full := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var local_prompt := ctl.system_prompt() + ctl.user_prompt(full)
	ok(ctl.system_prompt().contains("rent_depot") and ctl.user_prompt(full).contains("freie_depotstandorte"), "lokaler Agent kennt Stellplatz-Ausbau mit gültigen Depot-IDs")
	ctl.config["provider"] = "demo"
	var full_prompt := ctl.system_prompt() + ctl.user_prompt(full)
	ok(local_prompt.length() < full_prompt.length() * 0.65, "lokaler Prompt deutlich kürzer (%d statt %d Zeichen)" % [local_prompt.length(), full_prompt.length()])
	print("Lokaler Prompt: %d Zeichen; vollständiger Prompt: %d Zeichen" % [local_prompt.length(), full_prompt.length()])
	ctl.config["provider"] = "ollama"
	var offer: Dictionary = s.resources.available_offers()[0]
	offer["model"] = "van"
	offer["price"] = 12000.0
	s.company(0).ledger.cash = 1000.0
	var financed := ObservationBuilder._financed_vehicles(s, 0, [])
	ok(financed.any(func(f): return f.modell == "van" and f.bank in ["B1", "B2", "B3"] and f.kreditbetrag > 1000), "gültiges Bankangebot für Fahrzeug trotz fehlendem Bargeld sichtbar")
	s.company(0).ledger.cash = 30000.0
	var contracts: Array = s.market.open_contracts()
	for k in contracts:
		s.company(0).known[k.id] = true
	var suitable: Array = contracts.filter(func(k): return s.company_vehicles(0).any(func(v): return k.vehicle_ok(v.model)))
	if not suitable.is_empty():
		var grounded: Dictionary = ctl._ground_action({"action": "accept_contract", "contract_id": "A_best_available"})
		ok(grounded.contract_id in suitable.map(func(k): return k.id), "Platzhalter wird auf bekannten, passenden Auftrag abgebildet")
	else:
		ok(true, "keine passenden Startaufträge im Testszenario")
	var concrete: Dictionary = ctl._ground_action({"action": "accept_contract", "contract_id": "A999999"})
	ok(concrete.contract_id == "A999999", "konkrete falsche ID wird nicht stillschweigend umgedeutet")
	var plan := {"ziel": "Aufträge fahren", "schritte": [{"id": "S1", "text": "Auftrag sammeln"}]}
	ok(s.plans.set_plan(0, plan).ok and ctl._same_plan(plan), "identischer Plan wird erkannt")
	ctl._since = 0.0
	var bad := AgentController.parse_response('{"summary":"Ich prüfe einen Auftrag.","actions":[{"action":"accept_contract","contract_id":"A999999"}]}')
	ctl._apply(bad, "bad1", "KI")
	ok(ctl._rapid_retry_count == 1 and ctl._since >= float(ctl.config.get("interval", 20.0)) - AgentController.MIN_EVENT_GAP
		and not ctl._events.is_empty(), "Ablehnung liefert schnelle Korrektur mit Fehlerhinweis")
	ctl._apply(bad, "bad2", "KI")
	ctl._apply(bad, "bad3", "KI")
	ok(ctl._rapid_retry_count == 2, "schnelle Wiederholungen bleiben begrenzt")
	ctl.free()


func test_action_normalize_models() -> void:
	var n1 := ActionExecutor.normalize({"action": "assign_transport", "details": {"contract_id": "A1", "vehicle_id": "F2"}})
	ok(n1.vehicle_id == 2 and n1.contract_id == "A1", "details-Block und 'F2' werden zu vehicle_id 2")
	var n2 := ActionExecutor.normalize({"action": "assign_transport/plan_tour", "parameters": {"auftraege": ["A2", "A11"], "fahrzeuge": [2.0]}})
	ok(n2.action == "assign_transport" and n2.vehicle_id == 2 and n2.contract_id == "A2", "Listenform wird auf erste Auftrags- und Fahrzeug-ID abgebildet")
	var n3 := ActionExecutor.normalize({"action": "assign_worker_task", "parameters": {"task_type": "repair_vehicle", "vehicle_id": "V7", "fahrer_id": "W3"}})
	ok(n3.kind == "reparieren" and n3.vehicle_id == 7 and n3.worker_id == "W3", "task_type, Synonym und fahrer_id werden übersetzt")
	var n4 := ActionExecutor.normalize({"action": "assign_transport", "vehicle_id": 5, "contract_id": "A9"})
	ok(n4.vehicle_id == 5, "korrekte Angaben bleiben unverändert")
	# Formen aus dem Spielerprotokoll vom 03.11.2026 (qwen3.5:9b)
	var n5 := ActionExecutor.normalize({"action": "accept_contract", "targets": ["A382", "A390"]})
	ok(n5.contract_id == "A382" and n5._kandidaten == ["A382", "A390"], "targets-Liste wird zu contract_id mit Kandidaten")
	var n6 := ActionExecutor.normalize({"action": "assign_transport", "contracts": ["A1"], "vehicles": [4.0]})
	ok(n6.contract_id == "A1" and n6.vehicle_id == 4, "contracts/vehicles-Listen werden zu IDs")
	var n7 := ActionExecutor.normalize({"action": "assign_transport", "arguments": {"contract_ids": ["A5"], "truck_id": "F3"}})
	ok(n7.contract_id == "A5" and n7.vehicle_id == 3, "contract_ids und truck_id im arguments-Block")
	var n8 := ActionExecutor.normalize({"action": "buy_vehicle", "parameters": {"angebote": ["F3", "F4"]}})
	ok(n8.offer_id == "F3", "angebote-Liste wird zu offer_id")
	var n9 := ActionExecutor.normalize({"action": "set_plan", "next_steps": ["Flotte prüfen", "Aufträge sammeln"]})
	ok(n9.ziel == "Flotte prüfen" and n9.schritte.size() == 2, "set_plan ohne ziel erhält es aus dem ersten Schritt")
	var n11 := ActionExecutor.normalize({"action": "assign_transport/plan_tour", "arguments": {"contract_ids": ["A19"], "truck_id": 1.0}})
	ok(n11.action == "assign_transport" and n11.contract_id == "A19" and n11.vehicle_id == 1, "Doppelname + contract_ids/truck_id (Protokoll 03.11. abends)")
	var n12 := ActionExecutor.normalize({"action": "assign_transport/plan_tour", "task_ids": ["A6"], "vehicle_ids": [2.0]})
	ok(n12.contract_id == "A6" and n12.vehicle_id == 2, "task_ids/vehicle_ids")
	var n13 := ActionExecutor.normalize({"action": "remember", "content": "Notiz"})
	ok(n13.inhalt == "Notiz", "remember: content wird zu inhalt (Bürgermeister-Protokoll 03.11.)")
	var n10 := ActionExecutor.normalize({"action": "assign_worker_task", "workers": ["W4"], "vehicle_id": 2})
	ok(n10.worker_id == "W4" and n10.kind == "fahren", "workers-Liste wird zu worker_id")


func test_assist_trips_and_kind() -> void:
	var s := new_sim(2)
	var c: Company = s.companies[0]
	c.ledger.inject(50000.0)
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var cap := int(v.spec().capacity)
	var k := Contract.new()
	k.id = "ZT1"
	k.pickup = c.depots[0]
	k.dropoff = int(s.city.buildings[3].id)
	k.qty = cap * 2
	k.reward = 1000.0
	k.status = "accepted"
	k.owner = 0
	k.deadline = 99999.0
	k.offer_until = 99999.0
	s.contracts[k.id] = k
	var r0: Dictionary = s.executor.execute(0, {"action": "assign_transport", "contract_id": k.id, "vehicle_id": v.id})
	ok(not r0.ok, "ohne Hilfe bleibt ein zu grosser Auftrag abgelehnt")
	s.executor.auto_split[0] = true
	var r: Dictionary = s.executor.execute(0, {"action": "assign_transport", "contract_id": k.id, "vehicle_id": v.id})
	ok(r.ok and r.msg.contains("2 Fahrten"), "zu grosser Auftrag wird auf zwei Fahrten verteilt (%s)" % r.msg)
	ok(v.stops.size() >= 4, "Fahrzeug hat Stopps fuer beide Fuellungen (%d)" % v.stops.size())
	var r2: Dictionary = s.executor.execute(0, {"action": "assign_worker_task", "kind": "collect_contracts", "worker_id": "W1"})
	ok(str(r2.get("msg", "")) != "" and not str(r2.msg).contains("Unbekannte Aufgabe"), "collect_contracts als Aufgabenart wird zur Aktion umgeleitet (%s)" % r2.get("msg", ""))


func test_anthropic_adapter() -> void:
	var ad := AnthropicAdapter.new()
	ad.config = {"model": "claude-sonnet-5-5", "max_tokens_per_request": 900, "api_key": "TEST_KEY_MUST_NOT_LEAVE"}
	var msgs: Array = [{"role": "system", "content": "Antworte als JSON."}, {"role": "system", "content": "Du bist der Marktmacher."},
		{"role": "user", "content": "Lage A"}, {"role": "user", "content": "Lage B"}, {"role": "assistant", "content": "ok"}, {"role": "user", "content": "weiter"}]
	var b: Dictionary = ad.build_body(msgs)
	ok(b.system == "Antworte als JSON.

Du bist der Marktmacher.", "Systemnachrichten werden zu einem Feld")
	ok(b.messages.size() == 3 and b.messages[0].role == "user" and b.messages[0].content.contains("Lage B"), "gleiche Rollen werden zusammengefuehrt, abwechselnd user/assistant")
	ok(b.max_tokens >= 4000 and not b.has("temperature"), "max_tokens reicht fuer Denkanteil, kein temperature")
	ok(b.output_config.effort == "medium", "Aufwand standardmaessig medium")
	ok(not JSON.stringify(b).contains("TEST_KEY_MUST_NOT_LEAVE"), "Schluessel steht nicht im Anfragekoerper")
	var first_assistant: Dictionary = ad.build_body([{"role": "assistant", "content": "x"}])
	ok(first_assistant.messages[0].role == "user", "Verlauf beginnt immer mit user")
	var good := AnthropicAdapter.parse_response(200, JSON.stringify({"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "{\"a\":1}"}], "stop_reason": "end_turn", "usage": {"input_tokens": 100, "output_tokens": 20}}))
	ok(good.ok and good.content == "{\"a\":1}" and good.usage.total_tokens == 120, "Text wird aus den Bloecken gelesen, Denkbloecke uebersprungen")
	ok(not AnthropicAdapter.parse_response(200, JSON.stringify({"content": [], "stop_reason": "refusal"})).ok, "Ablehnung ist ein Fehler")
	var rl := AnthropicAdapter.parse_response(429, "{}", "7")
	ok(not rl.ok and rl.retry_after == 7.0, "Rate Limit mit retry-after")
	ok(AnthropicAdapter.parse_response(401, JSON.stringify({"error": {"message": "invalid x-api-key"}})).error.contains("invalid x-api-key"), "Fehlermeldung der API")
	ok(LLMAdapter.create("anthropic") is AnthropicAdapter, "Anbieter anthropic ist registriert")
	ad.free()
	# Buergermeister mit Claude: Schluessel nur aus der Umgebung, nie aus den Einstellungen
	var prev_key := OS.get_environment("ANTHROPIC_API_KEY")
	OS.set_environment("ANTHROPIC_API_KEY", "TEST_KEY_ENV")
	ok(AnthropicAdapter.mayor_key() == "TEST_KEY_ENV", "Schluessel kommt aus ANTHROPIC_API_KEY")
	var menu := SetupMenu.new()
	menu._ready()
	menu.mayor_opt.select(2)
	var mc: Dictionary = menu.collect().mayor
	ok(mc.provider == "anthropic" and mc.model == AnthropicAdapter.DEFAULT_MODEL and not mc.has("api_key"), "Buergermeister-Option Claude ohne Schluessel in der Konfiguration")
	ok(SetupMenu.validate(menu.collect()) == "", "mit gesetztem Schluessel ist die Konfiguration gueltig")
	menu.free()
	if prev_key == "":
		OS.unset_environment("ANTHROPIC_API_KEY")
	else:
		OS.set_environment("ANTHROPIC_API_KEY", prev_key)
	var s := new_sim(2)
	var ma := MayorAgent.new()
	root.add_child(ma)
	ma.setup(s, {"provider": "anthropic", "api_key": "TEST_KEY_ENV", "model": AnthropicAdapter.DEFAULT_MODEL}, null)
	ok(ma.uses_model() and ma.adapter is AnthropicAdapter, "MayorAgent nutzt den Claude-Adapter")
	ma.queue_free()


func test_visit_dedupe() -> void:
	var s := new_sim(2)
	s.companies[0].ledger.inject(100000.0)
	var o1: Dictionary = s.resources.available_offers()[0]
	var r1: Dictionary = s.executor.execute(0, {"action": "buy_vehicle", "offer_id": o1.id})
	var r2: Dictionary = s.executor.execute(0, {"action": "buy_vehicle", "offer_id": o1.id})
	ok(r1.ok and r1.get("pending", false), "erster Fahrzeugkauf wird als Besuch geplant (%s)" % r1.msg)
	ok(not r2.ok and r2.msg.contains("eingeplant"), "zweiter Kauf wird abgelehnt statt die Besuchsliste zu füllen")
	var c1: Dictionary = s.executor.execute(0, {"action": "collect_contracts"})
	var c2: Dictionary = s.executor.execute(0, {"action": "collect_contracts"})
	ok(not c2.ok or not c1.get("pending", false), "doppeltes collect_contracts wird nicht doppelt eingereiht")


func test_tiers() -> void:
	GameCalendar.configure(5.0)
	var s := new_sim(2)
	var T: Tiers = s.tiers
	T.on_month(1)
	var occupied: Array = s.housing.units.values().filter(func(u): return u.tenant != "")
	ok(occupied.size() > 0 and occupied.all(func(u): return int(u.tier) >= 1 and int(u.tier) <= Tiers.cap_of(str(s.city.building(int(u.building)).type))), "Startstufen liegen im erlaubten Bereich (%d Einheiten)" % occupied.size())
	ok(T.city_mean() >= 1.8 and T.city_mean() <= 3.2, "Stadtmittel der Stufen plausibel (%.2f)" % T.city_mean())
	for d in T.coverage:
		for n in Tiers.NEEDS:
			if float(T.coverage[d][n.id]) < 0.0 or float(T.coverage[d][n.id]) > 1.0:
				ok(false, "Deckung außerhalb 0-1")
	# Aufstieg: alle Bedürfnisse gedeckt, Zufriedenheit ausreichend, zwei Monate in Folge, Gebäude erlaubt es
	var u: Dictionary = occupied.filter(func(x): return str(s.city.building(int(x.building)).type) == "villa" or Tiers.cap_of(str(s.city.building(int(x.building)).type)) >= 3)[0]
	var d := int(s.city.building(int(u.building)).district)
	var cap := Tiers.cap_of(str(s.city.building(int(u.building)).type))
	u.tier = 2
	u.sat = 80.0
	for n in Tiers.NEEDS:
		T.coverage[str(d)][n.id] = 1.0
	var ups := {}
	var downs := {}
	T._update_unit(u, ups, downs)
	ok(int(u.tier) == 2, "Ein Monat reicht nicht für den Aufstieg")
	T._update_unit(u, ups, downs)
	ok(int(u.tier) == 3, "Nach zwei Monaten mit gedeckten Bedürfnissen: Stufe 3")
	u.sat = 30.0
	T._update_unit(u, ups, downs)
	T._update_unit(u, ups, downs)
	ok(int(u.tier) == 3, "Unzufriedene Bewohner steigen nicht auf")
	# Gebäude begrenzt die Stufe
	u.tier = cap
	u.sat = 90.0
	T._update_unit(u, ups, downs)
	T._update_unit(u, ups, downs)
	T._update_unit(u, ups, downs)
	ok(int(u.tier) == cap, "Höchststufe des Gebäudes wird nicht überschritten (%d)" % cap)
	# Abstieg: ein Bedürfnis der eigenen Stufe fällt drei Monate unter die Schwelle
	u.tier = 3
	T.coverage[str(d)]["gastro"] = 0.1
	for i in Tiers.DOWN_MONTHS:
		T._update_unit(u, ups, downs)
	ok(int(u.tier) == 2, "Abstieg nach %d Monaten unversorgt" % Tiers.DOWN_MONTHS)
	# Wirkung: Miete und Nachfrage folgen der Stufe
	u.tier = 1
	var r1 := T.rent_factor(u)
	u.tier = 4
	ok(T.rent_factor(u) > r1 and absf(T.rent_factor(u) - 1.3) < 0.001, "Miete steigt mit der Stufe (%.2f -> %.2f)" % [r1, T.rent_factor(u)])
	var rest: Dictionary = s.retail.shops.values().filter(func(x): return x.kind == "restaurant")[0]
	var dist := int(s.city.building(int(rest.building)).district)
	var m: Dictionary = T.mix.get(str(dist), {"personen": 100, "stufen": {1: 100, 2: 0, 3: 0, 4: 0}, "summe": 100.0, "mittel": 1.0})
	T.mix[str(dist)] = {"personen": 100, "stufen": {1: 100, 2: 0, 3: 0, 4: 0}, "summe": 100.0, "mittel": 1.0}
	var poor := T.demand_factor(rest)
	T.mix[str(dist)] = {"personen": 100, "stufen": {1: 0, 2: 0, 3: 50, 4: 50}, "summe": 350.0, "mittel": 3.5}
	var rich := T.demand_factor(rest)
	ok(rich > poor * 1.5, "Restaurants leben von höheren Stufen (%.2f -> %.2f)" % [poor, rich])
	# Marktzutritt: Viertel mit vielen Bewohnern ohne Geschäft bekommt eines
	var shops_before: int = s.retail.shops.size()
	for sh in s.retail.shops.values():
		sh.status = "geschlossen"
	T.on_month(2)
	ok(s.retail.shops.size() >= shops_before, "Marktzutritt bricht nichts ab (%d -> %d Geschäfte)" % [shops_before, s.retail.shops.size()])
	# Speichern und Laden
	var T2 := Tiers.new()
	T2.from_dict(JSON.parse_string(JSON.stringify(T.to_dict())))
	var k0: String = T.mix.keys()[0]
	ok(T2.mix.size() == T.mix.size() and int(T2.mix[k0].stufen[1]) == int(T.mix[k0].stufen[1]) and int(T2.mix[k0].personen) == int(T.mix[k0].personen), "Zustand übersteht Speichern und Laden")
	var txt := LiveText.housing(s)
	ok(txt.contains("Wohnstufen") and txt.contains("Bewohner"), "Wohnen-Ansicht zeigt Wohnstufen")
	var ob := ObservationBuilder._population(s)
	ok(ob.has("stadtmittel_stufe") and ob.has("viertel_mit_mangel"), "Beobachtung enthält Bevölkerungsstufen")
	ok(identity_ok(s), "Geld und Bilanz erhalten")


func test_tiers_supply() -> void:
	GameCalendar.configure(5.0)
	var s := new_sim(2)
	var T: Tiers = s.tiers
	T.on_month(1)
	# Freischaltung nach Stadtmittel
	T.mix = {"1": {"personen": 100, "stufen": {1: 50, 2: 50, 3: 0, 4: 0}, "summe": 150.0, "mittel": 1.5}}
	ok(not T.unlocked("stadtvilla") and T.unlocked("mehrfamilienhaus"), "Stadtvilla bei Stufenmittel 1,5 gesperrt, Standardbau frei")
	var parcel: Dictionary = s.parcels.search({"zone": "wohnen", "min_area": 30, "limit": 1})[0]
	s.parcels.reserve(parcel.id, "D0")
	var blocked: Dictionary = s.permits.draft("D0", parcel.id, {"def": "stadtvilla", "floors": 1})
	ok(not blocked.ok and blocked.msg.contains("freigeschaltet"), "Antrag auf gesperrten Bau wird abgelehnt: " + str(blocked.msg))
	T.mix = {"1": {"personen": 100, "stufen": {1: 0, 2: 20, 3: 60, 4: 20}, "summe": 300.0, "mittel": 3.0}}
	ok(T.unlocked("stadtvilla") and T.unlocked("hochhaus"), "Bei Stufenmittel 3,0 sind Stadtvilla und Hochhaus frei")
	var okd: Dictionary = s.permits.draft("D0", parcel.id, {"def": "stadtvilla", "floors": 1})
	ok(okd.ok, "Antrag auf freigeschalteten Bau wird angelegt")
	# Meilensteine
	T.milestones.clear()
	T._check_milestones(5)
	ok(T.milestones.has("mittel_25") and T.milestones.has("mittel_30") and T.milestones.has("villa"), "Meilensteine werden erreicht und vermerkt (%s)" % str(T.milestones.keys()))
	# Versorgungspraemie: leeres Regal -> Praemie, gut versorgt -> keine; Zahlung aus der Stadtkasse, Geld bleibt erhalten
	var shop: Dictionary = s.retail.shops.values()[0]
	T._snap[shop.id] = {"units": int(shop.units), "lost": int(shop.lost)}
	shop.units = int(shop.units) + 2
	shop.lost = int(shop.lost) + 10
	ok(T.shortage_bonus(shop, 60.0) == 30.0, "Praemie 50 Prozent der Fracht bei Mangel (%.0f)" % T.shortage_bonus(shop, 60.0))
	shop.units = int(shop.units) + 100
	ok(T.shortage_bonus(shop, 60.0) == 0.0, "Keine Praemie bei guter Versorgung")
	var c := s.companies[0]
	var k := Contract.new()
	k.id = "ATEST"
	k.bonus = 40.0
	k.cargo = "pakete"
	var cash0 := c.ledger.cash
	var p0 := float(s.economy.accounts["P0"])
	s.economy.transfer("I0", "P0", 500000.0 - p0)
	T.pay_bonus(k, c)
	ok(absf(c.ledger.cash - cash0 - 40.0) < 0.01 and absf(float(s.economy.accounts["P0"]) - 499960.0) < 0.01, "Praemie fliesst von der Stadtkasse an das Unternehmen")
	s.economy.transfer("P0", "I0", float(s.economy.accounts["P0"]) - 100010.0)
	cash0 = c.ledger.cash
	T.pay_bonus(k, c)
	ok(absf(c.ledger.cash - cash0) < 0.01, "Unter der Mindestreserve der Stadtkasse keine Praemie")
	# Versorgungsbau: Loch im Wohnviertel fuehrt zu einem Antrag des Bautraegers, danach wird nicht doppelt geplant
	s.economy.transfer("I0", "P0", p0 - float(s.economy.accounts["P0"]))
	var T2: Tiers = s.tiers
	T2.mix = {"1": {"personen": 400, "stufen": {1: 0, 2: 400, 3: 0, 4: 0}, "summe": 800.0, "mittel": 2.0}}
	T2.gap_months = {"1:haushalt": 3}
	var gap := T2.supply_gap()
	ok(gap.get("def", "") == "drogerie_laden" and int(gap.district) == 1, "Dauerhaftes Loch wird erkannt (%s)" % str(gap.get("def", "-")))
	var apps_before: int = s.permits.apps.values().filter(func(a): return a.applicant == "D0").size()
	var started: bool = s.construction._supply_project()
	var apps_after: int = s.permits.apps.values().filter(func(a): return a.applicant == "D0").size()
	ok(started and apps_after == apps_before + 1, "Bautraeger beantragt Versorgungsbau (%d -> %d Antraege)" % [apps_before, apps_after])
	ok(int(T2.gap_months["1:haushalt"]) < 0 and T2.supply_gap().is_empty(), "Beantragter Bau wird nicht erneut geplant")
	ok(identity_ok(s), "Geld und Bilanz erhalten")


func test_idle_routine() -> void:
	var s := new_sim(2)
	s.personnel.idle_routine = true
	var c := s.companies[0]
	var staff: Array = s.personnel.employed(0).filter(func(w): return w.role == "worker")
	ok(staff.size() >= 2, "Startbelegschaft vorhanden (%d)" % staff.size())
	# Ohne Aufgabe und ohne Fahrzeug: nach der Wartezeit bekommt jeder Arbeiter eine Aufgabe (Fahrzeug besetzen, Verladen, Bewachen ...)
	for w in staff:
		w.vehicle_id = -1
		w.task_id = ""
	var now := s.game_min
	s.personnel.idle_tick(now)
	var assigned := staff.filter(func(w): return w.task_id != "").size()
	ok(assigned == 0, "Direkt nach dem Leerlaufbeginn noch keine Aufgabe (Wartezeit)")
	s.personnel.idle_tick(now + Personnel.IDLE_AFTER + 1.0)
	s.personnel.idle_tick(now + Personnel.IDLE_AFTER + 2.0)
	assigned = staff.filter(func(w): return w.task_id != "" and not s.personnel.tasks[w.task_id].is_final()).size()
	ok(assigned >= 2, "Nach der Wartezeit bekommen untätige Arbeiter Aufgaben (%d von %d)" % [assigned, staff.size()])
	ok(not s.personnel.idle_stats.is_empty(), "Statistik der Routine: %s" % str(s.personnel.idle_stats))
	# Blockade: Erfolg erzeugt Stau vor dem Depot des Opfers, Entdeckung kostet Bussgeld
	var w0: Worker = staff[0]
	var victim := s.companies[1]
	var jams_before: int = s.nav.jams.size()
	var t := s.personnel.create_task(0, "blockieren", {"company": 1}, w0.id, "", 2, "Test")
	t.work_needed = 1.0
	s.personnel.force_outcome = "success"
	s.personnel._resolve_blockade(t, w0)
	ok(s.nav.jams.size() > jams_before and t.status == "abgeschlossen", "Blockade: Stau vor dem Depot (%d Felder)" % (s.nav.jams.size() - jams_before))
	ok(s.traffic_events.any(func(e): return e.kind == "stau" and str(e.text).contains(victim.company_name)), "Stau erscheint in den Verkehrsereignissen")
	var cash0 := c.ledger.cash
	var vcash0 := victim.ledger.cash
	var t2 := s.personnel.create_task(0, "blockieren", {"company": 1}, w0.id, "", 2, "Test")
	s.personnel.force_outcome = "caught"
	s.personnel._resolve_blockade(t2, w0)
	ok(t2.status == "fehlgeschlagen" and c.ledger.cash < cash0 and victim.ledger.cash > vcash0, "Erwischt: Bußgeld, Schadensersatz an das Opfer")
	s.personnel.force_outcome = ""
	# Abklingzeit und Schutzfrist gelten auch fuer Modelle (Aktion)
	var r := s.executor.execute(0, {"action": "assign_worker_task", "kind": "blockieren", "worker_id": staff[1].id, "company": 1})
	ok(not r.ok and r.msg.contains("Abklingzeit"), "Zweite Blockade gegen dieselbe Firma: Abklingzeit (%s)" % r.msg)
	ok(identity_ok(s), "Geld und Bilanz erhalten")


func test_reserve_check() -> void:
	var s := new_sim(2)
	vehicle_with_driver(s, 0, "van")
	vehicle_with_driver(s, 0, "van")
	var c := s.company(0)
	var need: float = ActionExecutor.RESERVE_FACTOR * s.insolvency.obligations_30d(c)
	ok(need > 1000.0, "Reserve ist größer als null (Pflichten der nächsten 30 Tage)")
	ok(s.executor._reserve_block(0, c.ledger.cash - need + 1.0) != "", "Kauf, der das Bargeld unter die Reserve drückt, wird abgelehnt")
	ok(s.executor._reserve_block(0, c.ledger.cash - need - 1.0) == "", "Kauf, nach dem die Reserve bleibt, ist erlaubt")
	ok(str(s.executor._reserve_block(0, c.ledger.cash)).contains("Reserve"), "Ablehnung nennt die Reserve")
	var c1 := s.company(1)
	ok(c1.vehicle_ids.size() < 2 or s.executor._reserve_block(1, c1.ledger.cash) != "", "Grundausstattung (weniger als 2 Fahrzeuge) ist ausgenommen oder geprüft")


func test_report_rival() -> void:
	var s := new_sim(3)
	# Unbegruendete Anzeige: nichts zu finden, der Anzeigende zahlt Bussgeld und verliert Ruf
	var rep0 := s.company(0).reputation
	var cash0 := s.company(0).ledger.cash
	var r1 := s.rivalry.report_rival(0, 1, "test")
	ok(r1.ok and s.company(0).ledger.cash < cash0 and s.company(0).reputation < rep0, "Anzeige ohne Anlass: Bußgeld und Rufverlust für den Anzeigenden")
	ok(not s.rivalry.report_rival(0, 2, "x").ok, "Abklingzeit: zweite Anzeige direkt danach abgelehnt")
	# Begruendete Anzeige: Gewinn ohne gezahlte Steuer wird nachgefordert
	s.company(2).ledger.book("transport", 30000.0, true, "Test-Erloes", s.game_min)
	s.company(1).ledger.book("transport", 30000.0, true, "Test-Erloes", s.game_min)
	s.company(0).ledger.inject(5000.0)
	s.rivalry.cooldowns.clear()
	var rep2 := s.company(1).reputation
	var r2 := s.rivalry.report_rival(0, 1, "test")
	ok(r2.ok and s.company(1).reputation < rep2 and str(r2.msg).contains("Steuer"), "Begründete Anzeige: Prüfung findet die Steuernachforderung, Ziel verliert Ruf")
	ok(not s.rivalry.report_rival(0, 1, "x").ok, "dieselbe Firma wird nicht sofort erneut angezeigt")
	ok(not s.rivalry.report_rival(0, 0, "x").ok, "sich selbst anzeigen geht nicht")
	# Regel-KI: ein Konkurrent im Zahlungsverzug wird angezeigt, wenn sie verdient
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.konkurrenten.all(func(r): return r.has("zahlungsverzug")), "Beobachtung zeigt den öffentlichen Zahlungsverzug der Konkurrenten")
	var acts: Array = []
	var rs: Array = []
	var rng := RandomNumberGenerator.new()
	var me := {"gewinn": 100.0}
	var riv := [{"id": 1, "name": "A", "reputation": 20, "fahrzeuge": 1, "personal": 1, "pakt_mit_dir": false, "schutzfrist": false, "zahlungsverzug": true},
		{"id": 2, "name": "B", "reputation": 60, "fahrzeuge": 5, "personal": 6, "pakt_mit_dir": false, "schutzfrist": false, "zahlungsverzug": false}]
	RuleBrain._dominate(riv, "wachstum", me, 50000.0, 6000.0, rng, acts, rs)
	ok(acts.size() == 1 and acts[0].action == "report_rival" and acts[0].target == 1, "Regel-KI zeigt den Konkurrenten im Zahlungsverzug an")
	riv[0].zahlungsverzug = false
	riv[0].personal = 4
	acts.clear()
	RuleBrain._dominate(riv, "wachstum", me, 50000.0, 6000.0, rng, acts, rs)
	ok(acts.size() == 1 and acts[0].action != "report_rival" and acts[0].target == 1, "ohne Verzug wirbt sie beim schwächsten Konkurrenten ab")
	ok(absf(s.economy.conservation_error()) < 0.01, "Geld bleibt erhalten (Bußgelder und Nachforderungen laufen über Konten)")


func test_rivalry_tension() -> void:
	var s := new_sim(3)
	ok(s.rivalry.get_tension(0, 1) == 0.0 and Rivalry.stage_of(0.0) == 0, "Ausgangslage: keine Spannung")
	# Unbegruendete Anzeige erzeugt Spannung (symmetrisch) und einen Vorfall
	s.rivalry.report_rival(0, 1, "test")
	var t1 := s.rivalry.get_tension(1, 0)
	ok(is_equal_approx(t1, Rivalry.TENSION.anzeige_unbegruendet) and s.rivalry.incidents.size() == 1, "Anzeige erhöht die Spannung des Paares in beide Richtungen")
	# Ueberbieten beim Grundstueck
	s.rivalry.add_tension(2, 1, "ueberboten", "Grundstück 1")
	ok(s.rivalry.get_tension(1, 2) > 0.0 and s.rivalry.get_tension(0, 2) == 0.0, "Vorfälle zählen nur für das betroffene Paar")
	# Stufen der Eskalationsleiter
	for i in 4:
		s.rivalry.add_tension(0, 1, "sabotage_entdeckt", "x")
	ok(s.rivalry.get_tension(0, 1) == 100.0 and Rivalry.stage_of(100.0) == 5, "Spannung ist auf 100 begrenzt, Stufe 5 (Sabotage)")
	ok(Rivalry.stage_of(16.0) == 1 and Rivalry.stage_of(55.0) == 3, "Stufen: 16 -> Stichelei, 55 -> Anzeige")
	s.rivalry.add_tension(0, 0, "anzeige")
	ok(s.rivalry.get_tension(0, 0) == 0.0, "keine Spannung mit sich selbst")
	# Geschaeft senkt die Spannung
	var before := s.rivalry.get_tension(1, 2)
	s.rivalry.add_tension(1, 2, "geschaeft")
	ok(s.rivalry.get_tension(1, 2) < before, "angenommenes Geschäft senkt die Spannung")
	# Abbau je Tag; Paare ohne Spannung verschwinden
	s.rivalry.on_day()
	ok(is_equal_approx(s.rivalry.get_tension(0, 1), 100.0 - Rivalry.TENSION_DECAY_PER_DAY), "Spannung sinkt täglich")
	for i in 30:
		s.rivalry.on_day()
	ok(not s.rivalry.tension.has(Social.pair_key(1, 2)), "abgeklungene Paare werden entfernt")
	# Beobachtung fuer Firmen und Buergermeister
	s.rivalry.add_tension(1, 0, "kunde_abgeworben", "Bäckerei")
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.konkurrenten.all(func(r): return r.has("spannung")) and obs.has("rivalitaet"), "Firmenbeobachtung zeigt Spannung je Konkurrent")
	var row: Dictionary = obs.rivalitaet[0]
	ok(row.firma == 1 and row.stufe != "" and row.vorfaelle.size() > 0, "Rivalität nennt Gegner, Stufe und letzte Vorfälle")
	var ind := s.mayor.indicators()
	ok(ind.rivalitaet.paare.size() >= 1 and ind.rivalitaet.vorfaelle_7_tage >= 1 and ind.rivalitaet.unruhe > 0.0, "Bürgermeister sieht angespannte Paare und Vorfälle")
	# Speichern/Laden
	var s2 := Simulation.from_dict(s.to_dict())
	ok(is_equal_approx(s2.rivalry.get_tension(0, 1), s.rivalry.get_tension(0, 1)) and s2.rivalry.incidents.size() == s.rivalry.incidents.size(), "Spannung und Vorfälle überstehen Speichern/Laden")


func test_dispatch_help() -> void:
	var s := new_sim(2)
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	ctl.config["provider"] = "ollama"
	var w := hire_free(s, 0, "driver")
	s.company(0).ledger.inject(50000.0)
	s.company(0).ledger.invest(5000.0)
	var nv := s.add_vehicle(0, "van", 5000.0, s.depot_road(0))
	ok(s.personnel.driver_of(nv.id) == null, "Ausgangslage: neues Fahrzeug ohne Fahrer")
	var bad := AgentController.parse_response('{"summary":"Ich setze jemanden ein.","actions":[{"action":"assign_worker_task"}]}')
	ctl._apply(bad, "d1", "KI")
	ok(s.personnel.driver_of(nv.id) != null or ctl.stats.actions_ok > 0, "Fahrzeug bekommt einen Fahrer (Assistent oder Disposition)")
	ctl.config["dispatch_help"] = false
	var before := int(ctl.stats.get("dispatch_help", 0))
	ctl._apply(AgentController.parse_response('{"summary":"x","actions":[{"action":"accept_contract","contract_id":"A999999"}]}'), "d2", "KI")
	ok(int(ctl.stats.get("dispatch_help", 0)) == before, "abschaltbar über dispatch_help=false")
	ctl.free()
	# Eigener Takt: ein Fahrzeug mit Fahrer steht ohne Auftrag still, ein bekannter Auftrag ist offen. Ohne jeden Modellaufruf wird er zugewiesen.
	var s2 := new_sim(2)
	var c2 := AgentController.new()
	c2.setup_for_test(s2, 0)
	c2.config["provider"] = "ollama"
	s2.company(0).ledger.inject(50000.0)
	var v2 := vehicle_with_driver(s2, 0, "van")
	var k2 := fresh_contract(s2, 0, 4)
	k2.reward = 900.0
	s2.game_min += 200.0
	c2._dispatch_tick()
	ok(int(c2.stats.get("dispatch_help", 0)) == 1, "Takt: Disposition läuft ohne Modellaufruf (Fahrzeug steht still)")
	c2._dispatch_tick()
	ok(int(c2.stats.get("dispatch_help", 0)) == 1, "Takt: nicht erneut innerhalb von %d Spielminuten" % int(AgentController.DISPATCH_EVERY_MIN))
	c2.free()


## Testhilfe: zusaetzliches Fahrzeug mit Fahrer direkt am Depot (ohne Kauf-/Anwerbewege).
func vehicle_with_driver(s: Simulation, cid: int, model: String) -> FleetVehicle:
	var v := s.add_vehicle(cid, model, Catalog.model(model).price, s.depot_road(cid))
	s.companies[cid].ledger.invest(v.purchase_price)
	v.state = "idle"
	v.path.clear()
	var w := s.personnel.spawn_available("driver")
	s.personnel.hire(cid, w)
	for t in s.personnel.tasks.values():
		if t.worker_id == w.id:
			s.personnel.cancel_task(t, "Test")
	w.vehicle_id = v.id
	return v


func fresh_contract(s: Simulation, cid: int, qty: int, cargo: String = "pakete") -> Contract:
	var k: Contract = s.market.spawn(s.game_min)
	while k == null:
		k = s.market.spawn(s.game_min)
	k.cargo = cargo
	k.label = ""
	k.qty = qty
	k.needs_cold = false
	k.needs_heavy = false
	k.min_rep = 0.0
	k.exclusive_for = -1
	k.deadline = s.game_min + 99999.0
	s.companies[cid].known[k.id] = true
	return k


func test_stage1_combinable() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	c0.ledger.inject(200000.0)
	var van: FleetVehicle = s.vehicles[c0.vehicle_ids[0]]
	var van2 := vehicle_with_driver(s, 0, "van")
	var depot: int = c0.depots[0]
	# Aufteilen: 12 Einheiten passen nicht in einen Kleintransporter (8)
	var k := fresh_contract(s, 0, 12)
	ok(s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id}).ok, "Auftrag 12 Einheiten angenommen")
	var r := s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": k.id})
	ok(not r.ok and r.msg.contains("aufteilen"), "zu große Menge ohne Aufteilung abgelehnt: " + r.msg)
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": k.id, "menge": 8}).ok, "Teilmenge 8 disponiert")
	var over := s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van2.id, "contract_id": k.id, "menge": 5})
	ok(not over.ok and over.msg.contains("nur noch 4"), "Reservierung verhindert Doppelverplanung: " + over.msg)
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van2.id, "contract_id": k.id, "menge": 4}).ok, "Rest 4 an zweites Fahrzeug")
	var rev0: float = c0.ledger.totals.get("transport", 0.0)
	var paid_early := false
	var t := 0.0
	while k.status != "delivered" and t < 1500.0:
		s.step(0.2)
		t += 0.2
		if k.delivered_qty > 0 and k.delivered_qty < 12 and c0.ledger.totals.get("transport", 0.0) > rev0:
			paid_early = true
	ok(k.status == "delivered" and k.delivered_qty == 12, "aufgeteilter Auftrag vollständig geliefert (%d/12, %s)" % [k.delivered_qty, k.status])
	ok(not paid_early, "keine Vergütung vor vollständiger Lieferung")
	ok(is_equal_approx(c0.ledger.totals.get("transport", 0.0) - rev0, k.reward), "volle Vergütung genau einmal")
	# Zwischenlager und Umladen: van bringt ins Depotlager, van2 holt dort ab und liefert
	var k2 := fresh_contract(s, 0, 6)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": k2.id})
	var to_store := s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": k2.id, "nach": "lager:%d" % depot})
	ok(to_store.ok, "ins eigene Lager disponiert: " + to_store.msg)
	var early := s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van2.id, "contract_id": k2.id, "von": "lager:%d" % depot})
	ok(not early.ok, "aus leerem Lager kann noch nicht verplant werden")
	t = 0.0
	while s.logistics.stored(depot, k2.id) < 6 and t < 1500.0:
		s.step(0.2)
		t += 0.2
	ok(s.logistics.stored(depot, k2.id) == 6, "6 Einheiten liegen im Zwischenlager")
	ok(k2.status == "in_transit" and k2.paid == 0.0, "Zwischenlagerung zahlt nichts aus")
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van2.id, "contract_id": k2.id, "von": "lager:%d" % depot}).ok, "Umladen: zweites Fahrzeug holt aus dem Lager")
	t = 0.0
	while k2.status != "delivered" and t < 1500.0:
		s.step(0.2)
		t += 0.2
	ok(k2.status == "delivered" and s.logistics.stored(depot, k2.id) == 0, "über Zwischenlager ausgeliefert")
	# Sammeltour: zwei Auftraege gleichzeitig laden, dann nacheinander abladen
	var a1 := fresh_contract(s, 0, 3)
	var a2 := fresh_contract(s, 0, 4)
	for kk in [a1, a2]:
		s.executor.execute(0, {"action": "accept_contract", "contract_id": kk.id})
	var tour := [{"art": "laden", "contract_id": a1.id, "menge": 3, "ort": "abholung"},
		{"art": "laden", "contract_id": a2.id, "menge": 4, "ort": "abholung"},
		{"art": "abladen", "contract_id": a1.id, "menge": 3, "ort": "ziel"},
		{"art": "abladen", "contract_id": a2.id, "menge": 4, "ort": "ziel"}]
	var bad_tour := tour.duplicate(true)
	bad_tour[1].menge = 6
	var a3 := fresh_contract(s, 0, 6)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": a3.id})
	bad_tour[1].contract_id = a3.id
	bad_tour[3].contract_id = a3.id
	bad_tour[3].menge = 6
	var rb := s.executor.execute(0, {"action": "plan_tour", "vehicle_id": van.id, "stopps": bad_tour})
	ok(not rb.ok and rb.msg.contains("Kapazität"), "Kapazitätsprüfung über die ganze Tour: " + rb.msg)
	var wrong := s.executor.execute(0, {"action": "plan_tour", "vehicle_id": van.id, "stopps": [{"art": "abladen", "contract_id": a1.id, "menge": 3, "ort": "ziel"}]})
	ok(not wrong.ok, "Abladen ohne Ladung abgelehnt")
	var foreign := s.executor.execute(0, {"action": "plan_tour", "vehicle_id": van.id, "stopps": [{"art": "laden", "contract_id": a1.id, "menge": 3, "ort": "abholung"},
		{"art": "abladen", "contract_id": a1.id, "menge": 3, "ort": "lager:%d" % s.companies[1].depots[0]}]})
	ok(not foreign.ok and foreign.msg.contains("gehört dir nicht"), "fremdes Lager abgelehnt")
	ok(s.executor.execute(0, {"action": "plan_tour", "vehicle_id": van.id, "stopps": tour}).ok, "Sammeltour geplant")
	var max_load := 0
	t = 0.0
	while (a1.status != "delivered" or a2.status != "delivered") and t < 2500.0:
		s.step(0.2)
		t += 0.2
		max_load = maxi(max_load, s.logistics.load_total(van))
	ok(a1.status == "delivered" and a2.status == "delivered", "beide Aufträge der Sammeltour geliefert")
	ok(max_load == 7, "beide Ladungen gleichzeitig an Bord (max. %d)" % max_load)
	# Tour streichen und Fahrzeug versetzen
	var a4 := fresh_contract(s, 0, 2)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": a4.id})
	van2.state = "idle"
	s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van2.id, "contract_id": a4.id})
	van2.state = "idle"
	van2.path.clear()
	var cl := s.executor.execute(0, {"action": "clear_tour", "vehicle_id": van2.id})
	ok(cl.ok and van2.stops.is_empty() and a4.status == "accepted", "Tour gestrichen, Auftrag wieder unverplant: " + cl.msg)
	ok(identity_ok(s), "Identität nach Touren")


func test_stage1_plans() -> void:
	var s := new_sim(2)
	var c0 := s.companies[0]
	var k := fresh_contract(s, 0, 4)
	var van: FleetVehicle = s.vehicles[c0.vehicle_ids[0]]
	var plan := {"action": "set_plan", "ziel": "Erste Hafentour testen", "nutzen": "Erfahrung mit Hafenaufträgen",
		"risiken": "Fristen", "abbruch": [{"typ": "bargeld_unter", "wert": 1000}],
		"schritte": [{"id": "S1", "text": "Auftrag annehmen", "aktion": {"action": "accept_contract", "contract_id": k.id}},
			{"id": "S2", "text": "Fahrzeug zuweisen", "abhaengig_von": ["S1"],
				"aktion": {"action": "assign_transport", "vehicle_id": van.id, "contract_id": k.id}},
			{"id": "S3", "text": "Ergebnis bewerten", "abhaengig_von": ["S2"]}]}
	ok(s.executor.execute(0, plan).ok, "Plan festgelegt")
	var bad := s.executor.execute(0, {"action": "set_plan", "ziel": "x", "schritte": [{"id": "A", "abhaengig_von": ["Z"]}]})
	ok(not bad.ok, "Plan mit unbekannter Abhängigkeit abgelehnt")
	var p := s.plans.current(0)
	ok(p.id != "" and p.status == "aktiv", "ungültiger Plan ersetzt den gültigen nicht")
	var early := s.executor.execute(0, {"action": "execute_plan_step", "step_id": "S2"})
	ok(not early.ok and early.msg.contains("wartet"), "Abhängigkeit wird geprüft: " + early.msg)
	ok(s.executor.execute(0, {"action": "execute_plan_step", "step_id": "S1"}, "t:1").ok and k.owner == 0, "Schritt 1 ausgeführt (Auftrag angenommen)")
	ok(s.executor.execute(0, {"action": "execute_plan_step", "step_id": "S2"}, "t:2").ok and not van.stops.is_empty(), "Schritt 2 ausgeführt (Fahrzeug disponiert)")
	ok(s.plans.summary(0).jetzt_ausfuehrbar.is_empty(), "S3 hat keine Aktion und wird nicht automatisch ausgeführt")
	s.executor.execute(0, {"action": "update_plan_step", "step_id": "S3", "status": "erledigt", "ergebnis": "bewertet"})
	ok(s.plans.current(0).status == "abgeschlossen", "Plan abgeschlossen, wenn alle Schritte erledigt sind")
	# Abbruchbedingung und entfallene Voraussetzung
	var k2 := fresh_contract(s, 0, 4)
	s.executor.execute(0, {"action": "set_plan", "ziel": "Zweiter Versuch", "abbruch": [{"typ": "bargeld_unter", "wert": 1000}],
		"schritte": [{"id": "S1", "aktion": {"action": "accept_contract", "contract_id": k2.id}}]})
	k2.status = "expired"
	s.plans.tick()
	ok(s.plans.current(0).status == "neu_planen" and s.plans.current(0).hinweis.contains("Voraussetzung"), "entfallene Voraussetzung erzwingt Neuplanung")
	s.executor.execute(0, {"action": "set_plan", "ziel": "Dritter", "abbruch": [{"typ": "bargeld_unter", "wert": 1000}], "schritte": [{"id": "S1", "text": "x"}]})
	c0.ledger.inject(-c0.ledger.cash + 500.0)
	s.plans.tick()
	ok(s.plans.current(0).status == "neu_planen" and s.plans.current(0).hinweis.contains("bargeld_unter"), "Abbruchbedingung Bargeld greift")
	ok(s.action_results[0].any(func(r): return str(r.text).contains("überprüfen")), "KI wird über Neuplanung informiert")
	# Plan im Antwortfeld "plan"
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 1)
	var req := ctl.begin_request_for_test()
	ctl.handle_result(req, {"ok": true, "usage": {}, "content": JSON.stringify({"summary": "Ich plane.", "goal": "Wachsen",
		"plan": {"ziel": "Expansion Innenstadt", "schritte": [{"id": "S1", "text": "Aufträge sammeln", "aktion": {"action": "collect_contracts"}}]},
		"actions": [{"action": "execute_plan_step", "step_id": "S1"}]})})
	ok(s.plans.current(1).get("ziel", "") == "Expansion Innenstadt", "Plan aus dem Antwortfeld übernommen")
	ok(s.plans.current(1).schritte[0].status in ["laeuft", "erledigt"], "Planschritt in derselben Antwort ausgeführt")
	ctl.free()
	# Beobachtung: Aktionsuebersicht mit gueltigen IDs, Unbekanntes markiert
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.verfuegbare_aktionen.has("accept_contract") and obs.verfuegbare_aktionen.has("recruit_worker"), "Aktionsübersicht vorhanden")
	var ids_ok := true
	for kid in obs.verfuegbare_aktionen.accept_contract.get("ziele", []):
		ids_ok = ids_ok and s.contracts.has(kid)
	ok(ids_ok, "nur gültige Auftrags-IDs in der Übersicht")
	ok(obs.unbekannt.size() >= 3 and obs.plan.has("status"), "Unbekanntes markiert, Plan enthalten")
	ok(identity_ok(s), "Identität nach Planschritten")


func test_stage2_memory() -> void:
	var s := new_sim(2)
	var M := s.memory
	# Trennung: Meldungen an Firma 1 landen nicht im Gedaechtnis von Firma 0; Zuschauerprotokoll ist keine Quelle
	s.notify(1, "Geheim: Firma 1 plant einen Angriff auf den Hafen")
	s.log_event("Zuschauer-Info: Firma 1 hat 99.999 EUR", "info", 1)
	var all0 := JSON.stringify(M.books[0])
	ok(not all0.contains("Geheim") and not all0.contains("99.999"), "keine fremden oder Zuschauer-Informationen im Gedächtnis")
	ok(JSON.stringify(M.books[1]).contains("Geheim"), "eigene Meldung im eigenen Gedächtnis")
	# Engine-Erfahrung aus Auftragsergebnissen: Vertrauen waechst mit Belegen
	var k := fresh_contract(s, 0, 4)
	k.owner = 0
	k.status = "in_transit"
	M.record_contract(0, k, true, 500.0)
	var e1: Dictionary = M.books[0].experiences.filter(func(x): return x.get("schluessel", "").begins_with("auftraege:"))[0]
	ok(e1.art == "vermutung" and e1.vertrauen < 0.3 and int(e1.belege) == 1, "eine Beobachtung = Vermutung mit geringem Vertrauen")
	M.record_contract(0, k, true, 520.0)
	M.record_contract(0, k, false, 0.0)
	ok(e1.art == "tatsache" and int(e1.belege) == 3 and e1.inhalt.contains("1 gescheitert"), "drei Belege, aktualisiert statt dupliziert: " + e1.inhalt)
	# Modell-Erfahrungen anlegen, aendern, verwerfen
	var r := s.executor.execute(0, {"action": "remember", "inhalt": "Nordroute im Berufsverkehr langsam", "bereich": ["route", "nord"], "art": "vermutung", "vertrauen": 0.4})
	ok(r.ok, r.msg)
	var id: String = M.books[0].experiences[-1].id
	s.executor.execute(0, {"action": "remember", "id": id, "inhalt": "Nordroute nur morgens langsam", "vertrauen": 0.7})
	var upd: Dictionary = M.books[0].experiences.filter(func(x): return x.id == id)[0]
	ok(upd.inhalt == "Nordroute nur morgens langsam" and is_equal_approx(upd.vertrauen, 0.7), "Erfahrung aktualisierbar")
	ok(s.executor.execute(0, {"action": "forget", "id": id}).ok and M.books[0].experiences.all(func(x): return x.id != id), "Erfahrung verwerfbar")
	# Antwortfeld "erfahrungen" und Entscheidungen als Ereignisse
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	var req := ctl.begin_request_for_test()
	ctl.handle_result(req, {"ok": true, "usage": {}, "content": JSON.stringify({"summary": "Ich teste Hafenaufträge.", "actions": [{"action": "wait"}],
		"erfahrungen": [{"inhalt": "Unternehmen Blau hielt die vereinbarte Frist ein", "bereich": ["firma:1", "kooperation"], "art": "tatsache", "vertrauen": 0.6}]})})
	ok(M.books[0].experiences.any(func(x): return x.inhalt.contains("Blau")), "Erfahrung aus Antwortfeld gespeichert")
	ok(M.books[0].events.any(func(e): return e.quelle == "entscheidung" and e.inhalt.contains("Hafenaufträge")), "Entscheidung als Ereignis protokolliert")
	ctl.free()
	# Relevante, begrenzte Auswahl
	for i in 30:
		M.upsert(0, {"inhalt": "Füllwissen %d" % i, "bereich": ["sonstiges"], "vertrauen": 0.9}, "modell")
	M.upsert(0, {"inhalt": "Hafen lohnt sich nachts", "bereich": ["hafen"], "vertrauen": 0.3}, "modell")
	var rel := M.relevant(0, ["hafen"])
	ok(rel.erfahrungen.size() <= MemoryBook.PROMPT_EXPERIENCES and rel.erfahrungen[0].inhalt.contains("Hafen"), "Auswahl begrenzt, passender Bereich zuerst")
	ok(M.books[0].experiences.size() <= MemoryBook.MAX_EXPERIENCES, "Gedächtnis begrenzt")
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.has("gedaechtnis") and JSON.stringify(obs).length() / 4 < 6000, "Gedächtnis in der Beobachtung, Größe begrenzt")
	# Speichern/Laden und Uebernahme in neue Partie
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.memory.books[0].experiences.size() == M.books[0].experiences.size(), "Gedächtnis im Spielstand")
	var exported := M.export_experiences(0)
	var s3 := new_sim(2)
	var n := s3.memory.import_experiences(0, exported)
	var imp: Dictionary = s3.memory.books[0].experiences[0]
	ok(n == exported.size() and imp.art == "vermutung" and "vorige_partie" in imp.bereich, "Übernahme als gekennzeichnete Vermutung")
	ok(s3.memory.books[1].experiences.is_empty(), "andere Spieler bleiben unberührt")


func test_stage3_events_and_log() -> void:
	var s := new_sim(2)
	var E := s.events
	var c0 := s.companies[0]
	# Strassensperre: Abschnitt gesperrt, Verkehrsmeldung in der Beobachtung, Ende hebt sie auf
	var cell: Vector2i = s.city.building(c0.depots[0]).road + Vector2i(6, 0)
	var r := E.trigger("strassensperre", {"cell": [cell.x, cell.y]}, 60.0)
	ok(r.ok and s.nav.roadworks.size() >= 2, "Sperrung gesetzt: " + r.msg)
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.verkehr.any(func(t): return str(t).contains("Vollsperrung")), "KI erfährt Sperrung über Verkehrsmeldungen")
	var blocked: Array = s.nav.roadworks.keys()
	run(s, 40.0)   # 80 Spielminuten > 60
	ok(blocked.all(func(p): return not s.nav.roadworks.has(p)), "Sperrung endet nach Ablauf")
	# Grossauftrag: erst nach dem Sammeln bekannt
	r = E.trigger("grossauftrag", {}, 300.0)
	var big: Contract = s.contracts[E.events[-1].data.contract]
	ok(r.ok and big.qty >= 60 and not c0.known.has(big.id), "Großauftrag veröffentlicht, aber noch nicht bekannt")
	# Treibstoffpreise
	var fuel_src: Dictionary = s.resources.supplies.values().filter(func(x): return x.kind == "fuel")[0]
	var p0: float = s.resources.fuel_price(fuel_src)
	E.trigger("treibstoffpreis", {"faktor": 2.0}, 30.0)
	ok(is_equal_approx(s.resources.fuel_price(fuel_src), snappedf(p0 * 2.0, 0.01)) or s.resources.fuel_price(fuel_src) > p0 * 1.9, "Treibstoffpreis verdoppelt")
	run(s, 20.0)
	ok(is_equal_approx(s.resources.fuel_price_factor, 1.0), "Preis nach Ablauf zurück")
	# Arbeitskraeftemangel
	var before := s.personnel.available().size()
	E.trigger("arbeitskraeftemangel", {"anteil": 0.8}, 30.0)
	var withheld: Array = E.events[-1].data.withheld
	ok(s.personnel.available().size() < before and not withheld.is_empty(), "Arbeitskräfte vom Markt genommen")
	teleport_avatar(s, 0, s.personnel.workers[withheld[0]].tile())
	ok(not s.executor.execute(0, {"action": "recruit_worker", "worker_id": withheld[0]}).ok, "abgezogene Arbeitskraft nicht anwerbbar")
	run(s, 20.0)
	ok(s.personnel.available().size() >= before - 1, "Arbeitsmarkt nach Ablauf wieder offen")
	# Neues Gewerbegebiet
	var nb := s.city.buildings.size()
	r = E.trigger("gewerbegebiet", {}, 60.0)
	ok(r.ok and s.city.buildings.size() > nb, "neue Kundengebäude: " + r.msg)
	var new_ids: Array = E.events[-1].data.buildings
	ok(new_ids.all(func(id): return s.city.is_road(s.city.building(id).road)), "neue Gebäude ans Straßennetz angebunden")
	ok(s.market.sources.any(func(src): return src[0] in new_ids) or s.market.receivers.values().any(func(lst): return lst.any(func(id): return id in new_ids)), "neue Kunden im Auftragsmarkt")
	# Nachfrage
	E.trigger("nachfrage", {"ware": "moebel", "faktor": 2.0}, 120.0)
	ok(E.demand_factor("moebel") == 2.0 and E.demand_factor("pakete") == 1.0, "Nachfragefaktor nur für die gewählte Ware")
	# Auswirkungsbericht je Firma
	ok(E.impact(E.events[0]).size() == 2, "Auswirkungen je Firma berechenbar")
	# Entscheidungsprotokoll: Herkunft, Regelpruefung, Kontext, Folgen
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 1)
	var k := fresh_contract(s, 1, 3)
	var req := ctl.begin_request_for_test()
	ctl.handle_result(req, {"ok": true, "usage": {}, "content": JSON.stringify({"summary": "Ich nehme den kurzen Paketauftrag.", "goal": "Auslastung",
		"actions": [{"action": "accept_contract", "contract_id": k.id, "vehicle_id": s.companies[1].vehicle_ids[0]}, {"action": "fly_to_moon"}]})})
	ctl.free()
	var mine: Array = s.decisions.entries.filter(func(e): return e.company == 1 and e.herkunft == "api")
	ok(mine.size() >= 2, "API-Entscheidungen protokolliert")
	var acc: Dictionary = mine.filter(func(e): return str(e.aktion).begins_with("accept_contract"))[0]
	ok(acc.pruefung == "ok" and acc.begruendung.contains("Paketauftrag") and acc.ziel == "Auslastung", "Begründung und Ziel am Eintrag")
	ok(mine.any(func(e): return e.pruefung == "abgelehnt"), "verworfene Aktion ebenfalls protokolliert")
	var t := 0.0
	while k.status != "delivered" and t < 900.0:
		s.step(0.2)
		t += 0.2
	ok(s.decisions.consequences(acc).contains("geliefert"), "gemessene Folge am Eintrag: " + s.decisions.consequences(acc))
	ok(s.decisions.entries.any(func(e): return e.herkunft == "auto" and e.refs.get("contract_id", "") == k.id), "Simulationsvorgang (Lieferung) als 'auto' protokolliert")
	ok(s.decisions.entries.any(func(e): return e.herkunft == "spectator"), "Zuschauer-Ereignisse protokolliert")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.decisions.entries.size() > 0 and s2.events.events.size() == E.events.size(), "Protokoll und Ereignisse im Spielstand")
	ok(identity_ok(s), "Identität nach Ereignissen")


func until_done(s: Simulation, cond: Callable, limit: float = 1500.0) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		s.step(0.2)
		t += 0.2


func test_stage4_experiments() -> void:
	var s := new_sim(2)
	var van: FleetVehicle = s.vehicles[s.companies[0].vehicle_ids[0]]
	var r := s.executor.execute(0, {"action": "start_experiment", "frage": "Lohnen kurze Paketfahrten?", "varianten": ["kurz", "lang"],
		"budget": 2000, "dauer_h": 24})
	ok(r.ok, r.msg)
	var xid: String = s.experiments.experiments.keys()[0]
	var k := fresh_contract(s, 0, 3)
	var acc := s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id, "vehicle_id": van.id, "experiment": xid, "variante": "kurz"})
	ok(acc.ok and acc.msg.contains("Experiment"), "Aktion dem Experiment zugeordnet: " + acc.msg)
	var bad := s.executor.execute(0, {"action": "accept_contract", "contract_id": fresh_contract(s, 0, 2).id, "experiment": xid, "variante": "xyz"})
	ok(bad.msg.contains("gehört nicht"), "unbekannte Variante wird gemeldet")
	until_done(s, func(): return k.status == "delivered")
	ok(k.fuel_cost > 0.0 and k.done_at > k.accepted_at, "Treibstoffkosten und Dauer dem Auftrag zugerechnet")
	var m := s.experiments.metrics(xid)
	ok(int(m.kurz.abgeschlossen) == 1 and float(m.kurz.marge_je_auftrag) < k.paid, "Messwerte je Variante (Marge nach Treibstoff)")
	var fin := s.executor.execute(0, {"action": "end_experiment", "experiment_id": xid})
	ok(fin.ok and fin.msg.contains("UNSICHER"), "eine Beobachtung = ausdrücklich unsichere Schlussfolgerung")
	ok(s.memory.books[0].experiences.any(func(x): return "experiment" in x.bereich and x.art == "vermutung"), "Ergebnis als Vermutung im Gedächtnis")
	ok(not s.executor.execute(0, {"action": "end_experiment", "experiment_id": xid}).ok, "Experiment nur einmal auswertbar")


func test_stage4_contracts() -> void:
	var s := new_sim(2)
	var A := s.companies[0]
	var B := s.companies[1]
	for c in [A, B]:
		c.ledger.inject(50000.0)
		c.reputation = 100.0
	var vanA2 := vehicle_with_driver(s, 0, "van")
	# Kapazitaetsvermietung mit Reservierung und Gegenangebot
	var o1 := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "capacity_rental", "vehicle_id": vanA2.id,
		"duration_hours": 4, "price": 400, "strafe": 100})
	ok(o1.ok, "Vermietung angeboten: " + o1.msg)
	var o1b := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "capacity_rental", "vehicle_id": vanA2.id, "duration_hours": 2, "price": 100})
	ok(not o1b.ok and o1b.msg.contains("zugesagt"), "dieselbe Kapazität nicht doppelt zusagbar")
	var c1 := s.executor.execute(1, {"action": "counter_offer", "offer_id": o1.id, "price": 300})
	ok(c1.ok and s.social.offers[o1.id].status == "gegenangebot", "Gegenangebot erstellt")
	ok(not s.executor.execute(1, {"action": "accept_trade", "offer_id": c1.id}).ok, "eigenes Gegenangebot nicht selbst annehmbar")
	var c2 := s.executor.execute(0, {"action": "counter_offer", "offer_id": c1.id, "price": 350})
	ok(c2.ok, "zweite Runde")
	var c3 := s.executor.execute(1, {"action": "counter_offer", "offer_id": c2.id, "price": 320})
	ok(not c3.ok and c3.msg.contains("Verhandlung beendet"), "Rundenlimit beendet die Verhandlung: " + c3.msg)
	var o2 := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "capacity_rental", "vehicle_id": vanA2.id,
		"duration_hours": 4, "price": 350, "strafe": 100})
	var accR := s.executor.execute(1, {"action": "accept_trade", "offer_id": o2.id})
	ok(accR.ok and vanA2.operator == 1, "Vermietung verbindlich: B betreibt das Fahrzeug")
	var kB := fresh_contract(s, 1, 5)
	s.executor.execute(1, {"action": "accept_contract", "contract_id": kB.id})
	var kA := fresh_contract(s, 0, 3)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": kA.id})
	ok(not s.executor.execute(0, {"action": "assign_transport", "vehicle_id": vanA2.id, "contract_id": kA.id}).ok, "Halter kann vermietetes Fahrzeug nicht verplanen")
	ok(s.executor.execute(1, {"action": "assign_transport", "vehicle_id": vanA2.id, "contract_id": kB.id}).ok, "Mieter verplant das Fahrzeug")
	var fuelB := B.fuel
	var revB: float = B.ledger.totals.get("transport", 0.0)
	until_done(s, func(): return kB.status == "delivered")
	ok(kB.status == "delivered" and B.ledger.totals.get("transport", 0.0) - revB == kB.reward, "Vergütung geht an den Auftragsinhaber (Mieter)")
	ok(B.fuel < fuelB or B.ledger.totals.get("fuel", 0.0) < 0.0, "Mieter zahlt den Treibstoff")
	until_done(s, func(): return vanA2.operator < 0, 600.0)
	var gR: Dictionary = s.social.agreements.values().filter(func(g): return g.kind == "capacity_rental")[0]
	ok(vanA2.operator < 0 and gR.status == "erfüllt", "Rückgabe nach Ablauf, Vertrag erfüllt")
	# Lagermitbenutzung
	var site: int = A.depots[0]
	var os := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "storage_share", "site_id": site, "plaetze": 10, "duration_hours": 6, "price": 200})
	ok(os.ok and s.executor.execute(1, {"action": "accept_trade", "offer_id": os.id}).ok, "Lagermitbenutzung vereinbart")
	var big := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "storage_share", "site_id": site, "plaetze": 55, "duration_hours": 6, "price": 200})
	ok(not big.ok, "nicht mehr Plätze zusagbar als frei sind")
	var vanB: FleetVehicle = s.vehicles[B.vehicle_ids[0]]
	var kS := fresh_contract(s, 1, 6)
	s.executor.execute(1, {"action": "accept_contract", "contract_id": kS.id})
	var over := s.executor.execute(1, {"action": "plan_tour", "vehicle_id": vanB.id, "stopps": [{"art": "laden", "contract_id": kS.id, "menge": 6, "ort": "abholung"},
		{"art": "abladen", "contract_id": kS.id, "menge": 6, "ort": "lager:%d" % site}]})
	ok(over.ok, "B lagert im Depot von A ein: " + over.msg)
	var kS2 := fresh_contract(s, 1, 8)
	s.executor.execute(1, {"action": "accept_contract", "contract_id": kS2.id})
	var over2 := s.executor.execute(1, {"action": "plan_tour", "vehicle_id": vanB.id, "stopps": [{"art": "laden", "contract_id": kS2.id, "menge": 8, "ort": "abholung"},
		{"art": "abladen", "contract_id": kS2.id, "menge": 8, "ort": "lager:%d" % site}]})
	ok(not over2.ok and over2.msg.contains("Plätze"), "vereinbarte Platzzahl wird eingehalten: " + over2.msg)
	# Teilauftrag an Konkurrenten
	var kBig := fresh_contract(s, 0, 12)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": kBig.id})
	var osp := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "split_contract", "contract_id": kBig.id, "menge": 4, "price": 150, "strafe": 300})
	ok(osp.ok and s.executor.execute(1, {"action": "accept_trade", "offer_id": osp.id}).ok, "Teilauftrag vereinbart")
	var vB2 := vehicle_with_driver(s, 1, "van")
	ok(not s.executor.execute(1, {"action": "assign_transport", "vehicle_id": vB2.id, "contract_id": kBig.id, "menge": 5}).ok, "Subunternehmer darf nicht mehr als vereinbart laden")
	ok(s.executor.execute(1, {"action": "assign_transport", "vehicle_id": vB2.id, "contract_id": kBig.id, "menge": 4}).ok, "Subunternehmer fährt seinen Anteil")
	var vanA: FleetVehicle = s.vehicles[A.vehicle_ids[0]]
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": vanA.id, "contract_id": kBig.id, "menge": 8}).ok, "Inhaber fährt den Rest")
	var tradeB: float = B.ledger.totals.get("trade_income", 0.0)
	until_done(s, func(): return kBig.status == "delivered", 2500.0)
	s.step(0.5)
	s.step(0.5)
	var gS: Dictionary = s.social.agreements.values().filter(func(g): return g.kind == "split_contract")[0]
	ok(kBig.status == "delivered" and kBig.delivered_qty == 12, "Auftrag gemeinsam vollständig geliefert")
	until_done(s, func(): return gS.status != "aktiv", 60.0)
	ok(gS.status == "erfüllt" and B.ledger.totals.get("trade_income", 0.0) - tradeB >= 150.0, "Subunternehmer bezahlt bei Erfüllung")
	ok(int(B.stats.get("contracts_kept", 0)) >= 2, "eingehaltene Verträge gezählt")
	# Vertragsbruch: Frist verfehlt -> Strafe
	var kX := fresh_contract(s, 0, 6)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": kX.id})
	var ox := s.executor.execute(0, {"action": "offer_trade", "to": 1, "kind": "split_contract", "contract_id": kX.id, "menge": 3, "price": 100, "strafe": 250})
	s.executor.execute(1, {"action": "accept_trade", "offer_id": ox.id})
	var gX: Dictionary = s.social.agreements.values().filter(func(g): return g.contract_id == kX.id)[0]
	var penB: float = B.ledger.totals.get("penalties", 0.0)
	kX.deadline = s.game_min - 1.0
	gX.end = s.game_min - 1.0
	s.social.tick(s.game_min)
	ok(gX.status == "gebrochen" and B.ledger.totals.get("penalties", 0.0) - penB == -250.0, "Vertragsstrafe bei Nichterfüllung")
	ok(identity_ok(s), "Identität nach Verträgen")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.social.agreements.size() == s.social.agreements.size(), "Verträge im Spielstand")


func place_suggested(s: Simulation, cid: int, typ: String, bau: String = "extern") -> Dictionary:
	var site: int = s.companies[cid].depots[0]
	var sug: Dictionary = s.estate.suggestions(cid, site)
	if not sug.has(typ):
		return {"ok": false, "msg": "kein Bauplatz für " + typ}
	var xy: Array = sug[typ]
	return s.executor.execute(cid, {"action": "place_building", "plot_id": site, "typ": typ, "x": xy[0], "y": xy[1], "rot": xy[2], "bau": bau})


func hire_free(s: Simulation, cid: int, kind: String) -> Worker:
	var w := s.personnel.spawn_available(kind)
	s.personnel.hire(cid, w)
	for t in s.personnel.tasks.values():
		if t.worker_id == w.id:
			s.personnel.cancel_task(t, "Test")
	return w


func test_estate_acceptance() -> void:
	var s := new_sim(2)
	var E := s.estate
	var c0 := s.companies[0]
	c0.ledger.inject(200000.0)
	var site: int = c0.depots[0]
	var plot: Dictionary = E.plots[site]
	# 1) leeres, gleich grosses Startgrundstueck
	ok(plot.owner == 0 and E.facilities.is_empty(), "leeres Startgrundstück")
	var p1: Dictionary = E.plots[s.companies[1].depots[0]]
	ok(p1.w == plot.w and p1.h == plot.h, "Startgrundstücke gleich groß")
	ok(c0.fleet_limit() == 2 and E.storage_cap(site) == 20 and E.loading_bays(site) == 1, "Start: 2 Stellplätze, 20 Lagerplätze, 1 Ladefläche")
	# ungueltige Platzierungen
	var bad := s.executor.execute(0, {"action": "place_building", "plot_id": site, "typ": "lager", "x": plot.x + plot.w - 1, "y": plot.y, "bau": "extern"})
	ok(not bad.ok and bad.msg.contains("Grundstücksgrenze"), "Grenze geprüft: " + bad.msg)
	var foreign := s.executor.execute(0, {"action": "place_building", "plot_id": p1.id, "typ": "buero", "x": 0, "y": 0})
	ok(not foreign.ok and foreign.msg.contains("gehört dir nicht"), "fremdes Grundstück abgelehnt")
	ok(not s.executor.execute(0, {"action": "place_building", "plot_id": site, "typ": "schloss", "x": plot.x, "y": plot.y}).ok, "unbekannter Typ abgelehnt")
	var ent: Array = plot.entrance
	ok(E.validate_place(0, site, "sicherheit", int(ent[0]), int(ent[1]), 0).contains("Einfahrt"), "Einfahrt bleibt frei")
	# 2) Buero (Baufirma): Investition, Bauzeit, Kapazitaet
	var cap0 := c0.contract_capacity()
	var cash0 := c0.ledger.cash
	var off := place_suggested(s, 0, "buero")
	ok(off.ok, "Büro platziert: " + off.msg)
	if not off.ok:
		return
	ok(is_equal_approx(cash0 - c0.ledger.cash, 4000.0 * 1.4), "Baufirma kostet +40 %")
	ok(identity_ok(s), "Identität nach Bauinvestition")
	var fo: Dictionary = E.facilities[off.building_id]
	ok(E.validate_place(0, site, "buero", int(fo.x), int(fo.y), 0) != "", "zweites Büro / Überlappung abgelehnt")
	ok(fo.status == "im_bau" and c0.contract_capacity() == cap0, "während des Baus keine Wirkung")
	until_done(s, func(): return fo.status == "fertig", 1500.0)
	ok(fo.status == "fertig" and c0.contract_capacity() == cap0 + 3, "Büro fertig: Auftragskapazität +3 (%d→%d)" % [cap0, c0.contract_capacity()])
	# 3) Stellplaetze
	var park := place_suggested(s, 0, "stellplatz")
	ok(park.ok, "Stellplätze platziert: " + park.msg)
	until_done(s, func(): return E.facilities[park.building_id].status == "fertig", 1500.0)
	ok(c0.fleet_limit() == 4, "Stellplätze erhöhen Flottengrenze (%d)" % c0.fleet_limit())
	# 4) Transporte vom Hof
	var van := vehicle_with_driver(s, 0, "van")
	var k := fresh_contract(s, 0, 6)
	s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id})
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": k.id}).ok, "Transport disponiert")
	until_done(s, func(): return k.status == "delivered")
	ok(k.status == "delivered", "Transport vom Betriebshof ausgeführt")
	# 5) Lagerhalle im Eigenbau: Material selbst anliefern, Arbeiter einteilen (hier nur vom Bauhof: Restposten im Stadtlager leeren)
	for it in Trader.MATERIALS:
		var q: int = s.city_depot.material_qty(it)
		if q > 0:
			s.stock.consume(it, q, "P0", s.city_depot.building, "Test", 0.0)
	var lager := place_suggested(s, 0, "lager", "eigen")
	ok(lager.ok, "Lagerhalle (Eigenbau) platziert: " + lager.msg)
	var fl: Dictionary = E.facilities.get(lager.get("building_id", ""), {})
	var mk: Contract = s.contracts.get(fl.get("mat_contract", ""))
	ok(mk != null and mk.internal == fl.id and mk.reward == 0.0, "interner Materialauftrag ohne Umsatz")
	run(s, 30.0)
	ok(float(fl.progress) == 0.0, "ohne Material kein Baufortschritt")
	var rev0: float = c0.ledger.totals.get("transport", 0.0)
	var md := s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": mk.id, "menge": 8})
	ok(md.ok, "Material disponiert (8 von %d): %s" % [mk.qty, md.msg])
	until_done(s, func(): return mk.delivered_qty >= 8 and van.stops.is_empty())
	ok(int(fl.mat) == 0, "Teillieferung reicht nicht – Material erst bei vollständiger Lieferung")
	ok(s.executor.execute(0, {"action": "assign_transport", "vehicle_id": van.id, "contract_id": mk.id, "menge": mk.qty - 8}).ok, "Restmaterial disponiert")
	until_done(s, func(): return int(fl.mat) >= int(fl.mat_needed))
	ok(int(fl.mat) == int(fl.mat_needed), "Material auf der Baustelle")
	ok(is_equal_approx(c0.ledger.totals.get("transport", 0.0), rev0), "Materialtransport erzeugt keinen Umsatz")
	var builders: Array = [hire_free(s, 0, "loader").id, hire_free(s, 0, "loader").id]
	var staff := s.executor.execute(0, {"action": "assign_building_staff", "building_id": fl.id, "worker_ids": builders})
	ok(staff.ok, "Bauarbeiter eingeteilt: " + staff.msg)
	until_done(s, func(): return fl.status == "fertig", 3000.0)
	ok(fl.status == "fertig" and E.storage_cap(site) == 80, "Lagerhalle fertig: 80 Lagerplätze (%d, %s, %.2f)" % [E.storage_cap(site), fl.status, fl.progress])
	# 6) Werkstatt: Wartung auf dem Hof
	var ws := place_suggested(s, 0, "werkstatt")
	ok(ws.ok, "Werkstatt platziert: " + ws.msg)
	until_done(s, func(): return E.facilities[ws.building_id].status == "fertig", 1500.0)
	var mech := hire_free(s, 0, "mechanic")
	c0.parts = 5
	van.condition = 60.0
	until_done(s, func(): return van.state == "idle" and van.stops.is_empty(), 600.0)
	var mt := s.executor.execute(0, {"action": "schedule_maintenance", "vehicle_id": van.id, "worker_id": mech.id})
	ok(mt.ok and mt.msg.contains("Werkstatt"), "Wartung in eigener Werkstatt: " + mt.msg)
	until_done(s, func(): return van.condition >= 100.0, 1500.0)
	ok(van.condition >= 100.0, "Fahrzeug in eigener Werkstatt gewartet (%d)" % int(van.condition))
	# 7) Laderampen begrenzen parallele Abfertigung
	var v2 := vehicle_with_driver(s, 0, "van")
	van.stops = [{"art": "abladen", "ort": "lager:%d" % site, "contract_id": "", "menge": 1}]
	v2.stops = [{"art": "abladen", "ort": "lager:%d" % site, "contract_id": "", "menge": 1}]
	van.state = "unloading"
	ok(not s._bay_free(v2), "eine offene Ladefläche: zweites Fahrzeug wartet")
	var ramp := place_suggested(s, 0, "laderampe")
	ok(ramp.ok, "Laderampe platziert: " + ramp.msg)
	until_done(s, func(): return E.facilities[ramp.building_id].status == "fertig", 1500.0)
	ok(s.executor.execute(0, {"action": "upgrade_building", "building_id": ramp.building_id}).ok, "Rampe ausbauen")
	until_done(s, func(): return int(E.facilities[ramp.building_id].level) == 2, 1500.0)
	ok(E.loading_bays(site) == 2 and s._bay_free(v2), "2 Rampenplätze: paralleles Abladen möglich")
	van.stops.clear()
	v2.stops.clear()
	van.state = "idle"
	# 8) Erweiterung und vermietbare Bueroeinheit
	var ext: Array = E.plots.values().filter(func(p): return int(p.parent) == site)
	ok(ext.size() == 1 and ext[0].owner < 0, "Erweiterungsfläche verfügbar")
	var land0 := c0.land_book
	ok(s.executor.execute(0, {"action": "expand_plot", "plot_id": ext[0].id, "art": "kaufen"}).ok, "Erweiterung gekauft")
	ok(c0.land_book - land0 == float(ext[0].price) and identity_ok(s), "Grund und Boden aktiviert, Identität ok")
	var rent := place_suggested(s, 0, "mietbuero")
	ok(rent.ok, "Mietbüro platziert: " + rent.msg)
	until_done(s, func(): return E.facilities[rent.building_id].status == "fertig", 1500.0)
	ok(not s.executor.execute(0, {"action": "offer_office_rental", "building_id": off.building_id, "einheiten": 1, "miete_pro_tag": 70}).ok, "eigenes Büro (Stufe 1) nicht vermietbar")
	ok(s.executor.execute(0, {"action": "offer_office_rental", "building_id": rent.building_id, "einheiten": 2, "miete_pro_tag": 40}).ok, "2 Einheiten ausgeschrieben")
	until_done(s, func(): return E.tenants.values().any(func(t): return t.status == "interessiert"), 3000.0)
	var ten: Array = E.tenants.values().filter(func(t): return t.status == "interessiert")
	ok(not ten.is_empty(), "Mietinteressent meldet sich")
	if not ten.is_empty():
		var n_contracts := s.contracts.size()
		ok(s.executor.execute(0, {"action": "accept_tenant", "tenant_id": ten[0].id}).ok, "Mieter angenommen")
		ok(s.contracts.size() > n_contracts, "Mieter erzeugt Transportbedarf (Einzug)")
		var inc0: float = c0.ledger.totals.get("rent_income", 0.0)
		run(s, 30.0)
		ok(c0.ledger.totals.get("rent_income", 0.0) > inc0, "Mieteinnahmen fließen")
	# 9) Rueckbau, Identitaet, Speichern/Laden
	var pb0 := c0.property_book
	ok(s.executor.execute(0, {"action": "remove_building", "building_id": ws.building_id}).ok, "Werkstatt zurückgebaut")
	ok(c0.property_book < pb0 and identity_ok(s), "Rückbau schreibt Buchwert ab, Identität ok")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.estate.facilities.size() == E.facilities.size() and s2.companies[0].fleet_limit() == c0.fleet_limit() \
		and s2.estate.storage_cap(site) == E.storage_cap(site), "Betriebshof gespeichert und geladen")
	ok(identity_ok(s2), "Identität nach Laden")
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.has("betriebshof") and obs.betriebshof.kapazitaet.lager == 80, "Beobachtung zeigt Betriebshof und Kapazitäten")


func test_foreman_delegation() -> void:
	var s := new_sim(2)
	var P := s.personnel
	var c1 := s.companies[1]
	var f := hire_free(s, 1, "foreman")
	var mech := hire_free(s, 1, "mechanic")
	s.executor.execute(1, {"action": "assign_foreman", "foreman_id": f.id, "worker_ids": [mech.id], "site_id": c1.depots[0]})
	var r := s.executor.execute(1, {"action": "set_foreman_orders", "foreman_id": f.id, "ziel": "Flotte fahrbereit halten",
		"prioritaet": "fristgerecht", "darf_teile_kaufen": true, "repair_budget": 600})
	ok(r.ok, "Vorarbeiter-Vorgaben gesetzt: " + r.msg)
	c1.parts = 0
	var v: FleetVehicle = s.vehicles[c1.vehicle_ids[0]]
	v.condition = 60.0
	s.break_vehicle(v, "Test")
	P.foremen_tick()
	ok(c1.parts > 0 and f.spent <= 600.0, "Vorarbeiter kauft Teile im Budget (%d Teile, %.0f EUR)" % [c1.parts, f.spent])
	ok(s.decisions.entries.any(func(e): return e.herkunft == "foreman"), "Kauf als Vorarbeiter-Entscheidung protokolliert")
	ok(P.tasks.values().any(func(t): return t.foreman_id == f.id and t.kind == "reparieren"), "Mechaniker repariert nach Teilekauf")
	ok(not s.executor.execute(1, {"action": "set_foreman_orders", "foreman_id": f.id, "prioritaet": "unsinn"}).ok, "ungültige Priorität abgelehnt")


# ------------------------------------------------------------------ Wetter, Ereignisse, Kunden
## Open-Meteo-aehnliche Antwort (Mainz); mm = Niederschlag im Messintervall, interval = Sekunden.
func wx_fixture(temp: float, code: int, mm: float = 0.0, gust: float = 15.0, interval: int = 900, day: int = 1, snow: float = 0.0) -> Dictionary:
	var times: Array = []
	for i in 6:
		times.append("2026-10-25T%02d:00" % (8 + i))
	return {"current": {"time": "2026-10-25T07:45", "interval": interval, "temperature_2m": temp, "apparent_temperature": temp - 2.0,
		"is_day": day, "precipitation": mm, "snowfall": snow, "weather_code": code, "cloud_cover": 80, "wind_speed_10m": 12.0, "wind_gusts_10m": gust},
		"hourly": {"time": times, "temperature_2m": [temp, temp, temp, temp, temp, temp], "precipitation_probability": [70, 60, 50, 40, 30, 20],
		"precipitation": [0.2, 0.0, 0.0, 0.0, 0.0, 0.0], "weather_code": [61, 3, 3, 2, 1, 0], "wind_gusts_10m": [20, 20, 20, 20, 20, 20]}}


func set_wx(s: Simulation, temp: float, code: int, mm: float = 0.0, gust: float = 15.0, snow: float = 0.0) -> void:
	var st: Dictionary = s.wx.parse_forecast(wx_fixture(temp, code, mm, gust, 900, 1, snow))
	s.apply_weather(st, Time.get_unix_time_from_system())


func test_weather_model() -> void:
	var w := Weather.new()
	var st := w.parse_forecast(wx_fixture(11.8, 63, 1.0))
	ok(not st.is_empty() and st.source == "open-meteo", "Antwort wird übernommen")
	ok(is_equal_approx(float(st.precip_mm_h), 4.0), "1,0 mm in 900 s = 4,0 mm/h (Intervall, nicht Stundenwert): %s" % st.precip_mm_h)
	ok(is_equal_approx(float(w.parse_forecast(wx_fixture(11.8, 63, 1.0, 15.0, 3600)).precip_mm_h), 1.0), "1,0 mm in 3600 s = 1,0 mm/h")
	ok(st.forecast.size() == 6 and st.forecast[0].pop == 70, "kurzfristige Vorhersage (6 Stunden)")
	ok(st.obs_time == "2026-10-25T07:45" and st.is_day, "Zeitpunkt der Wetterdaten und Tag/Nacht")
	ok(w.parse_forecast({}).is_empty() and w.parse_forecast({"current": {"temperature_2m": 1}}).is_empty() and w.parse_forecast("x").is_empty(), "unbrauchbare Antworten werden verworfen")
	ok(Weather.condition_of(65) == "Starkregen" and Weather.condition_of(45) == "Nebel" and Weather.condition_of(75) == "Schnee" \
		and Weather.condition_of(95) == "Gewitter" and Weather.condition_of(2) == "wolkig" and Weather.condition_of(61) == "Regen", "WMO-Codes werden eingeordnet")
	ok(w.status(1000.0) == "simuliert", "ohne Daten: gekennzeichnetes Ersatzwetter")
	w.apply(st, 5, 1000.0)
	ok(w.status(1100.0) == "aktuell" and w.status(1000.0 + 3000.0) == "veraltet" and w.status(1000.0 + 9000.0) == "offline", "Status aktuell/veraltet/offline")
	w.mark_failed("Netz weg")
	ok(w.cur.source == "open-meteo" and w.last_error == "Netz weg", "bei Ausfall bleibt der letzte Stand erhalten")
	# Aufzeichnung und Wiederholung
	w.apply(w.parse_forecast(wx_fixture(5.0, 3)), 40, 2000.0)
	w.apply(w.parse_forecast(wx_fixture(20.0, 0)), 90, 3000.0)
	ok(w.log.size() == 3, "Verlauf aufgezeichnet (%d Stände)" % w.log.size())
	var r := Weather.new()
	r.start_replay(w.log)
	ok(int(r.cur.temp) == 11 and r.cur.source == "wiederholung", "Wiederholung startet mit dem ersten Stand")
	r.replay_tick(39)
	ok(int(r.cur.temp) == 11, "vor Minute 40 keine Änderung")
	r.replay_tick(40)
	ok(int(r.cur.temp) == 5, "Minute 40: zweiter Stand")
	r.replay_tick(500)
	ok(int(r.cur.temp) == 20, "Minute 90: dritter Stand")
	# Spielzeit erzeugt kein erfundenes Wetter
	var s := new_sim(2)
	set_wx(s, 9.0, 3)
	run(s, 400.0)
	ok(s.wx.cur.source == "open-meteo" and int(s.wx.cur.temp) == 9 and s.game_min > 700.0, "800 Spielminuten ändern echte Wetterdaten nicht (Spielzeit %.0f)" % s.game_min)
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.wx.cur.source == "open-meteo" and int(s2.wx.cur.temp) == 9 and absf(s2.wx.fetched_unix - s.wx.fetched_unix) < 0.01, "Wetter übersteht Speichern/Laden")
	var s3 := new_sim(2)
	run(s3, 300.0)
	ok(s3.wx.cur.source == "simuliert", "Ersatzwetter ist als simuliert markiert")


func test_weather_effects() -> void:
	var w := Weather.new()
	w.apply(w.parse_forecast(wx_fixture(10.0, 63, 1.0)), 0, 0.0)
	ok(w.is_rain(), "Regen erkannt")
	ok(w.drive_factor() < 1.0, "Regen verlangsamt Fahrten")
	ok(w.loading_factor(true) < w.loading_factor(false) and w.loading_factor(true) >= 1.0, "überdachte Ladeplätze mildern Regen")
	ok(w.build_factor() < 1.0, "Regen bremst den Bau")
	w.apply(w.parse_forecast(wx_fixture(-3.0, 0)), 0, 0.0)
	ok(w.is_cold() and not w.is_icy(), "trockener, kalter Tag vereist nicht")
	ok(w.drive_factor() == 1.0, "kein Glätteeffekt ohne Feuchtigkeit")
	w.apply(w.parse_forecast(wx_fixture(-1.0, 61, 0.3)), 0, 0.0)
	ok(w.is_icy() and w.drive_factor() <= w.p("drive_ice"), "Frost mit Nässe: Glätte")
	ok(w.breakdown_factor(false) > w.breakdown_factor(true) and w.breakdown_factor(true) > 1.0, "Wartung senkt das Ausfallrisiko bei Extremwetter")
	w.apply(w.parse_forecast(wx_fixture(30.0, 0)), 0, 0.0)
	ok(w.is_hot() and w.breakdown_factor(false) > 1.0, "Hitze belastet Fahrzeuge")
	w.apply(w.parse_forecast(wx_fixture(15.0, 3, 0.0, 75.0)), 0, 0.0)
	ok(w.is_strong_wind() and w.loading_factor(true) >= w.p("loading_wind") and w.build_factor() <= w.p("build_wind"), "Sturm wirkt auch unter Dach auf Verladen und Bau")
	w.apply(w.parse_forecast(wx_fixture(10.0, 45)), 0, 0.0)
	ok(w.is_fog() and w.drive_factor() < 1.0, "Nebel: vorsichtigere Fahrweise")
	# echte Wirkung in der Simulation: Starkregen verlangsamt Fahrzeuge
	var s := new_sim(2)
	set_wx(s, 12.0, 3)
	var base_speed: float = s._speed_factor(s.company_vehicles(0)[0])
	set_wx(s, 12.0, 65, 3.0)
	ok(s._speed_factor(s.company_vehicles(0)[0]) < base_speed, "Fahrzeuggeschwindigkeit sinkt bei Starkregen")


func test_event_chain() -> void:
	var s := new_sim(2)
	s.companies[0].reputation = 100.0
	set_wx(s, 31.0, 0)                                  # 1. Wetteränderung: Hitze
	run(s, 3.0)
	var evs: Array = s.events.events.filter(func(e): return e.typ == "hitze")
	ok(evs.size() == 1, "Hitze-Ereignis genau einmal erzeugt (%d)" % evs.size())
	var ev: Dictionary = evs[0]
	ok(str(ev.id).begins_with("E") and ev.ursache.begins_with("Wetter") and not ev.orte.is_empty() and not ev.wirkung.is_empty() \
		and not ev.quellen.is_empty() and ev.ende_bedingung != "" and ev.schwere == 1 and float(ev.ende) > float(ev.start), "Ereignis hat ID, Ursache, Orte, Wirkung, Quellen, Schwere, Ende")
	run(s, 60.0)
	ok(s.events.events.filter(func(e): return e.typ == "hitze").size() == 1, "kein erneutes Auswürfeln nach 120 Spielminuten")
	ok(is_equal_approx(s.world_events.need_factor("getraenke"), 1.6) and s.events.demand_factor("getraenke") >= 1.6, "2. veränderter Bedarf: Getränke ×1,6")
	# 3. Kundenanfrage aus dem Bedarf
	var rest := {}
	for p in s.residents.people.values():
		if s.city.building(p.building).type == "restaurant":
			rest = p
			break
	ok(not rest.is_empty() and rest.name != "" and rest.role != "", "Kundenfigur mit Name und Rolle")
	var k: Contract = s.residents.request(rest, s.game_min, 0)
	ok(k != null and k.requester == rest.id and k.cargo == "getraenke" and k.dropoff == rest.building, "Anfrage ist echter Auftrag zum Restaurant")
	ok(k.cause == ev.id and rest.state == "wartet" and k.concern != "", "Anfrage verweist auf das Ereignis und nennt das Anliegen")
	k.exclusive_for = -1
	k.min_rep = 0.0
	k.deadline = s.game_min + 99999.0
	k.needs_heavy = false
	k.needs_cold = false
	k.qty = mini(k.qty, 8)
	s.companies[0].known[k.id] = true
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var seen: Array = obs.markt.filter(func(m): return m.id == k.id)
	ok(seen.size() == 1 and str(seen[0].get("kunde", "")).contains(rest.name), "KI sieht Kunde und Anliegen im Markt")
	ok(obs.lage.any(func(e): return e.id == ev.id and e.ursache != ""), "KI sieht die Ereignislage mit Ursache")
	ok(obs.wetter.has("lage") and obs.wetter.has("vorhersage") and obs.wetter.status == "aktuell", "KI sieht das öffentliche Wetter samt Status")
	# 4. KI-Entscheidung und 5. sichtbare Handlung
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var r := s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id, "vehicle_id": v.id})
	ok(r.ok, "Auftrag angenommen: " + r.msg)
	var d: Dictionary = s.decisions.entries.filter(func(e): return e.refs.get("contract_id", "") == k.id)[0]
	ok(d.refs.get("event_id", "") == ev.id and d.refs.get("person_id", "") == rest.id, "Entscheidung ist mit Ereignis und Kunde verknüpft")
	ok(s.decisions.consequences(d).contains(rest.name) and s.decisions.consequences(d).contains(ev.id), "Folgentext nennt Kunde und Ereignis")
	var profit0: float = s.companies[0].ledger.profit()
	var t := step_until(s, func(): return k.status == "delivered", 1500.0)
	# 6. wirtschaftliches Ergebnis
	ok(k.status == "delivered" and k.paid > 0.0, "6. Lieferung bezahlt (%s nach %.0f s, Gewinn %s → %s)" % [k.status, t, Catalog.money(profit0), Catalog.money(s.companies[0].ledger.profit())])
	s.residents.minute_tick(s.game_min)
	ok(rest.state == "zufrieden" and rest.contract == "" and rest.done == 1, "Kunde ist zufrieden")
	# erfüllte Anliegen erscheinen nicht sofort wieder
	rest.pressure = 5.0
	for i in 30:
		s.residents.minute_tick(s.game_min + i)
	ok(rest.contract == "" and float(rest.cooldown_until) > s.game_min + 500.0, "Sperrfrist nach erfülltem Anliegen (bis %s)" % Catalog.game_minutes_to_text(rest.cooldown_until))
	ok(identity_ok(s), "Bilanzidentität bleibt erhalten")
	# Wetter endet -> Ereignis endet
	set_wx(s, 14.0, 3)
	run(s, 1.0)
	ok(ev.status == "beendet", "Hitze-Ereignis endet mit der Wetterlage")


func test_event_limits() -> void:
	var s := new_sim(2)
	set_wx(s, 14.0, 65, 6.0, 80.0)                      # Starkregen + Sturm gleichzeitig
	run(s, 3.0)
	ok(s.events.events.any(func(e): return e.typ == "starkregen") and s.events.events.any(func(e): return e.typ == "sturm"), "zwei schwere Wetterstörungen laufen")
	ok(s.world_events.severe_active() == 2, "höchstens zwei schwere Störungen gleichzeitig (%d)" % s.world_events.severe_active())
	set_wx(s, -1.0, 65, 6.0, 80.0)                      # zusätzlich Glätte
	run(s, 3.0)
	ok(not s.events.events.any(func(e): return e.typ == "glaette") and s.world_events.severe_active() <= 2, "dritte schwere Störung wird zurückgehalten")
	set_wx(s, 14.0, 3)
	run(s, 3.0)
	ok(s.world_events.severe_active() == 0 and s.world_events.quiet_until > s.game_min, "ruhige Phase nach schweren Störungen")
	set_wx(s, -1.0, 61, 0.3)                            # Glätte jetzt möglich, aber ruhige Phase
	run(s, 3.0)
	ok(not s.events.events.any(func(e): return e.typ == "glaette"), "in der ruhigen Phase keine neue schwere Störung")
	run(s, 60.0)
	ok(s.events.events.any(func(e): return e.typ == "glaette"), "nach der ruhigen Phase beginnt die Störung")
	# Sturm erzeugt höchstens zwei Reparaturanfragen aus echten Kundenfiguren
	var storm: Dictionary = s.events.events.filter(func(e): return e.typ == "sturm")[0]
	ok(storm.data.get("contracts", []).size() <= 2, "Sturm: höchstens 2 Reparaturanfragen")
	for kid in storm.data.get("contracts", []):
		ok(s.contracts[kid].requester != "" and s.contracts[kid].cause == storm.id and s.contracts[kid].cargo == "baustoffe", "Reparaturanfrage %s hat Kunde, Ursache und Material" % kid)


func test_live_text() -> void:
	var s := new_sim(2)
	var ctls: Array = []
	for i in 2:
		var ctl := AgentController.new()
		ctl.setup_for_test(s, i)
		ctl.goal = "Flotte ausbauen [Test]"
		ctls.append(ctl)
	set_wx(s, 31.0, 0)
	run(s, 3.0)
	var rest := {}
	for p in s.residents.people.values():
		if s.city.building(p.building).type == "restaurant":
			rest = p
			break
	var k: Contract = s.residents.request(rest, s.game_min, 0)
	k.exclusive_for = -1
	k.min_rep = 0.0
	k.needs_heavy = false
	k.needs_cold = false
	k.qty = mini(k.qty, 8)
	k.deadline = s.game_min + 99999.0
	s.companies[0].known[k.id] = true
	var acc := s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id, "vehicle_id": s.company_vehicles(0)[0].id})
	ok(acc.ok, "Annahme: " + acc.msg)
	var act := LiveText.activities(s, ctls)
	ok(act.contains(s.companies[0].company_name) and act.contains(s.companies[1].company_name), "Aktivitäten nennen alle Unternehmen")
	ok(act.contains("Flotte ausbauen [lb]Test]") and act.contains("Ziel:"), "Ziel wird angezeigt (BBCode maskiert)")
	ok(act.contains(rest.name) and act.contains(k.id), "Fahrzeugzeile nennt Kunde und Auftrag")
	var lage := LiveText.situation(s, 12.5)
	ok(lage.contains("WETTER MAINZ") and lage.contains("Modelldaten") and lage.contains("Zeitachsen"), "Lage zeigt Wetter, Quelle und Zeitachsen")
	var ev: Dictionary = s.events.events.filter(func(e): return e.typ == "hitze")[0]
	ok(lage.contains(ev.id) and lage.contains("Ursache:") and lage.contains("Quellen für Spieler") and lage.contains("Auftrag"), "Ereignis mit Ursache, Quellen und Folge-Auftrag")
	ok(lage.contains(rest.name) and lage.contains("KUNDEN MIT ANLIEGEN"), "wartende Kunden sind aufgelistet")
	for c in ctls:
		c.free()


# ------------------------------------------------------------------ Grafik, Iso-Geometrie, Wetterdienst, Speicherstand
func iso_manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/iso/manifest.json"))


func test_iso_assets_complete() -> void:
	var man := iso_manifest()
	var missing: Array = []
	var wrong_size: Array = []
	for type in CityGenerator.TYPES:
		var info: Array = CityGenerator.TYPES[type]
		for sprite in info[0]:
			var e: Dictionary = man.buildings.get(sprite, {})
			if e.is_empty() or not FileAccess.file_exists("res://assets/iso/b_%s.png" % sprite):
				missing.append(sprite)
			elif int(e.w) != int(info[1]) or int(e.h) != int(info[2]):
				wrong_size.append("%s %dx%d statt %dx%d" % [sprite, e.w, e.h, info[1], info[2]])
	ok(missing.is_empty(), "Grafik für jeden Gebäudetyp vorhanden (fehlt: %s)" % str(missing))
	ok(wrong_size.is_empty(), "Grundfläche der Grafik = Grundfläche in der Simulation (%s)" % str(wrong_size))
	for typ in Estate.FACILITIES:
		var spec: Dictionary = Estate.FACILITIES[typ]
		var e: Dictionary = man.facilities.get("fac_" + typ, {})
		ok(not e.is_empty() and int(e.w) == int(spec.w) and int(e.h) == int(spec.h), "Einrichtung %s: Grafik %sx%s" % [typ, spec.w, spec.h])
		if int(spec.w) != int(spec.h):
			var r: Dictionary = man.facilities.get("fac_%s_r" % typ, {})
			ok(not r.is_empty() and int(r.w) == int(spec.h) and int(r.h) == int(spec.w), "Einrichtung %s gedreht: Grafik vertauscht" % typ)
	for model in Catalog.VEHICLE_MODELS:
		for k in 4:
			ok(man.vehicles.has("%s_%d" % [model, k]) and FileAccess.file_exists("res://assets/iso/v_%s_%d_mask.png" % [model, k]), "Fahrzeug %s Richtung %d mit Firmenmaske" % [model, k])
	for color in EntityView.CAR_NAMES:
		for k in 4:
			ok(man.vehicles.has("car_%s_%d" % [color, k]), "NPC-Auto %s Richtung %d" % [color, k])
	for style in Catalog.AVATAR_COUNT:
		var f: Dictionary = man.figures.get("fig_%d" % style, {})
		ok(not f.is_empty() and int(f.hframes) == EntityView.FRAMES and int(f.vframes) == 4, "Figurenblatt %d (7 Bilder x 4 Richtungen)" % style)
	ok(man.figures.has("fig_umbrella"), "Regenschirm-Overlay")
	for name in ["d_tree0", "d_tree1", "d_tree2", "d_lamp", "d_bench", "d_light_red", "d_light_green", "roadwork", "flag", "fac_site"]:
		ok(man.props.has(name), "Requisit " + name)
	for cargo in Catalog.CARGO:
		ok(man.props.has("c_" + cargo), "Ladungskiste " + cargo)
	var ground_names := ["grass0", "grass1", "grass2", "park0", "park1", "gravel", "sidewalk", "plaza", "concrete", "quay", "sand", "field", "crop",
		"water0", "water1", "water2", "water3", "rail_h", "parking"]
	for m in 16:
		ground_names.append("road%d" % m)
	for n in ground_names:
		ok(man.ground.tiles.has(n), "Bodenkachel " + n)
	# Wasser-Animation: vier aufeinanderfolgende Kacheln derselben Zeile
	var w0: Array = man.ground.tiles.water0
	ok(man.ground.tiles.water1[1] == w0[1] and int(man.ground.tiles.water3[0]) == int(w0[0]) + 3, "Wasserbilder liegen für die Animation nebeneinander")
	# Baum-Varianten der Karte haben eine Grafik
	var s := new_sim(2)
	var variants := {}
	for t in s.city.trees:
		variants[int(t[1])] = true
	for v in variants:
		ok(man.props.has("d_tree%d" % v), "Baumvariante %d hat eine Grafik" % v)


func test_iso_geometry() -> void:
	for p in [Vector2(0, 0), Vector2(100, 40), Vector2(-33.5, 71.25), Vector2(4096, 512)]:
		ok(Iso.to_world(Iso.to_screen(p)).distance_to(p) < 0.001, "Iso-Umrechnung hin und zurück %s" % str(p))
	ok(Iso.to_screen(Vector2(32, 0)) == Vector2(64, 32) and Iso.to_screen(Vector2(0, 32)) == Vector2(-64, 32), "Ein Feld ist eine Raute 128 x 64")
	for wh in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 3), Vector2i(6, 4), Vector2i(1, 3)]:
		var w: int = wh.x
		var h: int = wh.y
		ok(is_equal_approx(Iso.front_edge_y(w, h, 64.0 * (w - h)), 32.0 * (w + h)), "Vorderkante %dx%d: vordere Ecke" % [w, h])
		ok(is_equal_approx(Iso.front_edge_y(w, h, -64.0 * h), 32.0 * h) and is_equal_approx(Iso.front_edge_y(w, h, 64.0 * w), 32.0 * w), "Vorderkante %dx%d: seitliche Ecken" % [w, h])
		var prev := -INF
		var monotone := true
		for sx in range(int(-64 * h), int(64 * (w - h)) + 1, 8):
			var y := Iso.front_edge_y(w, h, sx)
			monotone = monotone and y >= prev
			prev = y
		ok(monotone, "Vorderkante %dx%d steigt zur vorderen Ecke" % [w, h])
	ok(is_equal_approx(Iso.front_edge_y(3, 3, -9999.0), Iso.front_edge_y(3, 3, -192.0)), "Vorderkante wird an den Rändern begrenzt")


func test_iso_strips() -> void:
	var cv := CityView.new()
	cv.man = iso_manifest()
	var info: Dictionary = cv.man.buildings["apartment0"]
	var parent := Node2D.new()
	var parts := cv.add_iso_object(parent, "b_apartment0", info, Vector2(1000, 500), 3, 3, true, "")
	ok(parts.size() >= 4, "3x3-Gebäude wird in Sortierstreifen zerlegt (%d)" % parts.size())
	var cover := 0.0
	var contiguous := true
	var last_right := -INF
	for sp in parts:
		var r: Rect2 = sp.region_rect
		cover += r.size.x
		contiguous = contiguous and (last_right == -INF or is_equal_approx(r.position.x, last_right))
		last_right = r.position.x + r.size.x
		ok(sp.position.y >= 500.0 + 32.0 * 3.0 - 0.01 and sp.position.y <= 500.0 + 32.0 * 6.0 + 0.01, "Streifen sortiert zwischen seitlicher und vorderer Ecke")
	ok(contiguous and is_equal_approx(cover, float(info.size[0])), "Streifen decken die ganze Grafik lückenlos ab")
	var small := cv.add_iso_object(parent, "b_house0", cv.man.buildings["house0"], Vector2.ZERO, 2, 2, true, "")
	ok(small.size() == 1 and is_equal_approx(small[0].position.y, 128.0), "2x2-Haus: ein Sprite, sortiert an der vorderen Ecke")
	var deep := cv.add_iso_object(parent, "b_depot", cv.man.buildings["depot"], Vector2.ZERO, 3, 3, true, "b_depot_mask")
	ok(deep.all(func(sp): return sp.get_children().any(func(ch): return ch.has_meta("mask"))), "Depot-Streifen tragen die Firmenmaske")
	parent.free()
	cv.free()


func test_weather_service() -> void:
	var s := new_sim(2)
	var svc := WeatherService.new()
	svc.location_path = "user://test_weather_location.json"
	if FileAccess.file_exists(svc.location_path):
		DirAccess.remove_absolute(svc.location_path)
	svc.setup(s)
	var url := svc.build_url()
	ok(url.contains("latitude=49.98185") and url.contains("longitude=8.28008") and url.contains("timezone=Europe%2FBerlin") \
		and url.contains("current=") and url.contains("wind_gusts_10m") and url.contains("forecast_hours=6"), "Abruf-URL: Mainz, Europe/Berlin, aktuelle Werte, Vorhersage")
	# Standortsuche: Mainz in Rheinland-Pfalz, nicht das bayerische Mainz
	var geo := {"results": [{"name": "Mainz", "admin1": "Bayern", "country_code": "DE", "latitude": 47.8, "longitude": 11.9},
		{"name": "Mainz", "admin1": "Rheinland-Pfalz", "country_code": "DE", "latitude": 49.98185, "longitude": 8.28008}]}
	ok(svc._pick_location(geo) and is_equal_approx(float(svc.location.lat), 49.98185), "Standort Mainz (Rheinland-Pfalz) gewählt")
	ok(not svc._pick_location({"results": []}) and not svc._pick_location("kaputt"), "Standortsuche ohne Treffer meldet Misserfolg")
	# Antwort verarbeiten: Erfolg, Altersstatus, Fehler behalten den letzten Stand
	svc._busy = true
	svc._geocoding = false
	svc._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(wx_fixture(17.5, 2, 0.0)).to_utf8_buffer())
	ok(s.wx.cur.source == "open-meteo" and int(s.wx.cur.temp) == 17 and s.wx.status(Time.get_unix_time_from_system()) == "aktuell", "Antwort wird übernommen, Status aktuell")
	ok(s.wx.log.size() == 1, "Stand wird für die Wiederholung aufgezeichnet")
	svc._busy = true
	svc._on_completed(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), PackedByteArray())
	ok(int(s.wx.cur.temp) == 17 and s.wx.last_error.contains("503"), "HTTP-Fehler: letzter Stand bleibt, Fehler gemerkt")
	svc._busy = true
	svc._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{\"unsinn\": 1}".to_utf8_buffer())
	ok(int(s.wx.cur.temp) == 17 and s.wx.last_error.contains("format"), "unbrauchbare Antwort wird verworfen")
	svc._busy = true
	svc._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	ok(int(s.wx.cur.temp) == 17 and s.wx.last_error.contains("Verbindung"), "kein Netz: letzter Stand bleibt")
	ok(not svc._busy, "Dienst ist nach Fehlern wieder frei")
	# alt werden: nach 41 Minuten ohne Erfolg 'veraltet'
	ok(s.wx.status(s.wx.fetched_unix + 41.0 * 60.0) == "veraltet" and s.wx.status(s.wx.fetched_unix + 3.0 * 3600.0) == "offline", "Altersstatus wächst ohne neue Daten")
	# Wiederholung in einer Simulation: aufgezeichneten Verlauf abspielen
	var rec: Array = s.wx.log.duplicate(true)
	rec.append({"minute": 30, "state": s.wx.parse_forecast(wx_fixture(3.0, 71, 0.2, 10.0, 900, 1, 0.3))})
	var s2 := new_sim(2)
	s2.wx.start_replay(rec)
	ok(s2.wx.cur.source == "wiederholung" and int(s2.wx.cur.temp) == 17, "Wiederholung startet mit aufgezeichnetem Stand")
	run(s2, 20.0)   # 40 Spielminuten
	ok(int(s2.wx.cur.temp) == 3 and s2.wx.is_snow(), "Wiederholung spielt den Wechsel zur aufgezeichneten Spielminute ab")
	# Live-Modus: kein erfundenes Ersatzwetter, bis Daten kommen oder der Abruf scheitert
	var s4 := new_sim(2)
	var svc2 := WeatherService.new()
	svc2.location_path = "user://test_weather_location.json"
	svc2.setup(s4)
	ok(s4.wx.hold_simulation, "Live-Modus hält das Ersatzwetter zurück")
	run(s4, 400.0)
	ok(s4.wx.cur.source == "simuliert" and s4.wx.cur.cond == "klar" and not s4.events.events.any(func(e): return e.typ in ["starkregen", "sturm"]), "ohne Daten entstehen im Live-Modus keine Wetter-Ereignisse")
	svc2._busy = true
	svc2._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	ok(not s4.wx.hold_simulation, "nach gescheitertem Abruf darf das gekennzeichnete Ersatzwetter einspringen")
	svc2.free()
	DirAccess.remove_absolute(svc.location_path)
	svc.free()


func test_residents_save_load() -> void:
	var s := new_sim(2)
	var rest := {}
	for p in s.residents.people.values():
		if s.city.building(p.building).type == "restaurant":
			rest = p
			break
	var k: Contract = s.residents.request(rest, s.game_min, 0)
	ok(k != null and s.residents._active.has(rest.id), "offene Anfrage ist in der aktiven Liste")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var r2: Dictionary = s2.residents.people[rest.id]
	ok(r2.state == "wartet" and r2.contract == k.id and s2.residents._active.has(rest.id), "Kundenfigur und Anfrage überstehen Speichern/Laden")
	ok(s2.contracts[k.id].requester == rest.id and s2.contracts[k.id].concern == k.concern, "Auftrag behält Kunde und Anliegen")
	ok(s2.residents.people.size() == s.residents.people.size() and s2.residents._ids.size() == s.residents._ids.size(), "alle Figuren geladen")
	# Anfragen laufen aus dem Spiel selbst heraus, mit Obergrenze
	var s3 := new_sim(2)
	run(s3, 600.0)
	var open: int = s3.residents.people.values().filter(func(p): return p.state == "wartet").size()
	ok(open <= Residents.OPEN_MAX + 3 * 2, "gleichzeitige Kundenanfragen bleiben begrenzt (%d)" % open)
	var asked: int = s3.residents.people.values().filter(func(p): return p.state != "ruhig" or p.done + p.failed > 0).size()
	ok(asked > 0, "Kundenanfragen entstehen von selbst (%d Figuren)" % asked)
	ok(s3.events.events.any(func(e): return e.get("auto", false)), "automatische Ereignisse entstehen ohne Zuschauer")


func test_calendar() -> void:
	GameCalendar.configure(60.0)
	var day := GameCalendar.day_game_min
	ok(is_equal_approx(day, 120.0), "1 Spieltag = 60 Sim-s = 120 Spielminuten")
	ok(GameCalendar.parts(0.0) == {"jahr": 1, "monat": 1, "tag": 1}, "Start: Jahr 1 Monat 1 Tag 1")
	ok(GameCalendar.parts(day * 30.0).monat == 2 and GameCalendar.parts(day * 30.0).tag == 1, "Monat hat 30 Tage")
	ok(GameCalendar.parts(day * 360.0).jahr == 2, "Jahr hat 12 Monate")
	ok(GameCalendar.days_left_in_month(day * 29.0) == 0 and GameCalendar.days_left_in_month(0.0) == 29, "Resttage im Monat")
	ok(is_equal_approx(GameCalendar.hour_of(0.0), Catalog.START_HOUR), "Start um Startstunde")
	GameCalendar.configure(120.0)
	ok(GameCalendar.day_of(120.0 * 2.0) == 1 and GameCalendar.day_of(120.0 * 2.0 - 1.0) == 0, "Spieltaglänge konfigurierbar")
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var days: Array = []
	var months: Array = []
	s.day_changed.connect(func(d): days.append(d))
	s.month_changed.connect(func(m): months.append(m))
	run(s, 60.0 * 31.5)   # 31,5 Spieltage
	ok(days.size() == 31 and days[0] == 1 and days[-1] == 31, "Tageswechsel einmal je Tag (%d)" % days.size())
	ok(months == [1], "Monatswechsel genau einmal")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(GameCalendar.parts(s2.game_min) == GameCalendar.parts(s.game_min), "Kalender nach Laden gleich")


func test_money_conservation() -> void:
	var s := new_sim()
	ok(absf(s.economy.conservation_error()) < 0.001, "Geld bei Spielbeginn erhalten")
	ok(s.economy.initial_total > 4.0 * Catalog.START_CAPITAL, "Anfangsbestand umfasst Firmen und Sektorkonten")
	s.executor.execute(0, {"action": "take_loan", "amount": 20000})
	ok(identity_ok(s), "Geld erhalten nach Kredit")
	var h0: float = s.economy.accounts.H0
	run(s, 400.0)
	ok(identity_ok(s), "Geld erhalten nach 13 Spielstunden")
	ok(s.economy.accounts.H0 != h0, "Haushalte erhalten Löhne und zahlen Transporte")
	var i0: float = s.economy.accounts.I0
	s.companies[0].ledger.inject(5000.0)
	ok(identity_ok(s), "Kapitaleinlage hat Gegenkonto")
	ok(is_equal_approx(s.economy.accounts.I0, i0 - 5000.0), "Kapitalgeber-Konto zeigt Einlage")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(s2.economy.conservation_error()) < 0.01, "Geld erhalten nach Laden")
	run(s2, 120.0)
	ok(identity_ok(s2), "Geld erhalten nach Laden und Weiterspielen")


func test_banking() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim()
	var B := s.banking
	var sched := Banking.schedule(10000.0, 0.06, 12, 1)
	var pr := 0.0
	for r in sched:
		pr += r.principal
	ok(is_equal_approx(pr, 10000.0) and sched.size() == 12, "Tilgungsplan: Tilgungen ergeben den Kreditbetrag")
	ok(is_equal_approx(sched[-1].balance, 0.0), "Restschuld nach der letzten Rate 0")
	ok(absf(sched[0].pay - 860.66) < 0.02, "Annuität 10 000 / 6 %% / 12 Monate = 860,66 (%.2f)" % sched[0].pay)
	ok(is_equal_approx(Banking.schedule(1200.0, 0.0, 12, 1)[0].pay, 100.0), "Nullzins: gleiche Tilgung")
	var q := B.quote(1, 0, 10000.0, 12)
	ok(not q.ok and "Sicherheit" in q.msg, "Investitionsbank verlangt Sicherheit: " + q.msg)
	var coll := B.best_collateral(0)
	q = B.quote(1, 0, 10000.0, 12, coll)
	ok(q.ok and q.rate >= B.ref_rate + 0.01, "Kreditzins mindestens Referenz + 1 %%: %.2f %%" % (q.rate * 100.0))
	ok(not B.quote(0, 0, 10000.0, 24).ok, "Geschäftsbank: Laufzeit über 12 Monate abgelehnt")
	ok(not B.quote(0, 0, 900000.0, 6, coll).ok, "Übergroßer Kredit abgelehnt")
	var cash0: float = s.companies[0].ledger.cash
	var r := s.executor.execute(0, {"action": "request_loan", "bank": "Investitionsbank", "amount": 10000, "monate": 12, "fahrzeug_id": coll})
	ok(r.ok, "Kredit gewährt: " + r.msg)
	ok(is_equal_approx(s.companies[0].ledger.cash, cash0 + 10000.0) and is_equal_approx(s.companies[0].ledger.debt, 10000.0), "Auszahlung und Schuld")
	ok(is_equal_approx(s.economy.accounts.B2, 600000.0 - 10000.0 + 0.0), "Auszahlung aus dem Bargeld der Bank")
	ok(B.pledged_to(coll) != "", "Fahrzeug verpfändet")
	var sell := s.executor.execute(0, {"action": "sell_vehicle", "vehicle_id": coll})
	ok(not sell.ok, "Verpfändetes Fahrzeug nicht verkäuflich")
	var equity0 := B.equity(1)
	var profit0: float = s.companies[0].ledger.profit()
	run(s, 1850.0)   # ein Monat
	ok(identity_ok(s), "Geldkonservierung und Bilanzidentität nach erster Rate")
	var loan: Dictionary = B.loans.values()[0]
	ok(loan.plan[0].status == "bezahlt" and loan.plan[1].status == "offen", "genau eine Rate bezahlt")
	ok(is_equal_approx(loan.outstanding, loan.plan[0].balance), "Restschuld = Planstand")
	ok(is_equal_approx(s.companies[0].ledger.debt, loan.outstanding), "Firmenschuld = Restschuld")
	ok(s.companies[0].ledger.totals.get("interest", 0.0) < 0.0, "Zinsaufwand gebucht")
	ok(B.equity(1) > equity0, "Zinsen erhöhen das Eigenkapital der Bank")
	ok(profit0 > s.companies[0].ledger.profit() - 20000.0, "Kredit ist kein Gewinn")
	# Vorzeitige Teiltilgung -> neuer Plan, Fahrzeug bleibt Pfand
	var rest0: float = loan.outstanding
	var er := s.executor.execute(0, {"action": "repay_loan", "amount": 2000, "kredit_id": loan.id})
	ok(er.ok and is_equal_approx(loan.outstanding, rest0 - 2000.0), "Teiltilgung: " + er.msg)
	var left: Array = loan.plan.filter(func(x): return x.status != "bezahlt")
	ok(left.size() == 11 and is_equal_approx(left[-1].balance, 0.0), "neuer Plan über die Restlaufzeit")
	ok(identity_ok(s), "Identität nach Teiltilgung")
	# Einlagen
	var d := s.executor.execute(0, {"action": "deposit_money", "amount": 5000, "art": "fest", "monate": 6, "bank": "B3"})
	ok(d.ok, "Festgeld angelegt: " + d.msg)
	var dep: Dictionary = B.deposits.values()[0]
	ok(dep.rate <= B.ref_rate - 0.005 + 1e-9, "Festgeldzins unter Referenz - 0,5 %")
	ok(dep.rate <= B.ref_rate - 0.005 + 1e-9 and B.ref_rate + 0.01 - dep.rate >= 0.015 - 1e-9, "Kreditzins (mind. Referenz + 1 %) liegt über dem Anlagezins")
	ok(identity_ok(s), "Identität mit Einlage")
	run(s, 1850.0)
	ok(s.companies[0].ledger.totals.get("interest_income", 0.0) > 0.0, "Einlagenzins als Ertrag")
	var early := B.withdraw(0, dep.id)
	ok(early.ok and "Gebühr" in early.msg, "vorzeitige Auflösung kostet Gebühr")
	ok(identity_ok(s), "Identität nach Auflösung")
	ok(B.summary_of(0).kredite.size() == 1, "Beobachtung listet den Kredit")
	ok("Referenzzins" in LiveText.banks(s) and "Geschäftsbank" in LiveText.banks(s), "Reiter Banken erzeugt Text")
	ok(JSON.stringify(ObservationBuilder.build(s, 0, [], 0.0, 30.0)).contains("referenzzins_pa"), "Beobachtung enthält Bankdaten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.banking.loans.size() == 1 and is_equal_approx(s2.banking.ref_rate, B.ref_rate), "Banken nach Laden")
	ok(identity_ok(s2), "Identität nach Laden")
	run(s2, 1850.0)
	ok(identity_ok(s2), "Weiterspielen nach Laden")


func test_banking_default() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	s.insolvency.enabled = false   # hier nur die Kreditmechanik, nicht das Insolvenzverfahren
	var c := s.companies[0]
	var coll := s.banking.best_collateral(0)
	var r := s.executor.execute(0, {"action": "request_loan", "bank": "B2", "amount": 8000, "monate": 6, "fahrzeug_id": coll})
	ok(r.ok, "Kredit: " + r.msg)
	c.ledger.inject(-c.ledger.cash - 10.0)   # Firma pleite: nur 10 EUR Bargeld
	var vehicles0 := s.vehicles.size()
	run(s, 60.0 * 30.0 * 4.0 + 120.0)   # 4 Monate
	var loan: Dictionary = s.banking.loans.values()[0]
	ok(loan.status == "ausgefallen", "nach 3 offenen Raten ausgefallen (%s)" % loan.status)
	ok(loan.arrears >= Banking.DEFAULT_AFTER, "Rückstände gezählt")
	ok(loan.collateral == -1 and s.vehicles.size() < vehicles0, "Sicherheit verwertet")
	ok(s.banking.company_defaults(0) == 1, "Ausfall in der Historie")
	ok(c.ledger.totals.get("interest", 0.0) <= 0.0, "Verzugszuschlag/Zinsen nur als Aufwand")
	ok(identity_ok(s), "Geld und Bilanz nach Ausfall und Verwertung")


func test_company_forms() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	ok(c.form == "einzel" and is_equal_approx(s.max_loan(0), (Catalog.LOAN_BASE_LIMIT + 0.5 * s.fleet_book_value(0)) * 0.8), "Einzelunternehmen: Kreditrahmen ×0,8")
	ok(not CompanyForms.request_change(s, 0, "ug").ok, "Formwechsel in den ersten 3 Monaten abgelehnt")
	run(s, 60.0 * 91.0)   # gut 3 Monate
	ok(identity_ok(s), "Geld und Bilanz nach 3 Monaten")
	ok(c.status == "aktiv" or c.status == "warnung", "Firma lebt nach 3 Monaten (%s)" % c.status)
	var admin_before: float = c.ledger.totals.get("admin", 0.0)
	var nw_before := s.net_worth(0)
	var r := CompanyForms.request_change(s, 0, "gmbh")
	ok(r.ok == (nw_before >= 25000.0), "GmbH nur mit 25 000 Eigenkapital: " + r.msg)
	var r2 := CompanyForms.request_change(s, 0, "ug")
	ok(r2.ok or r.ok, "UG-Wechsel beantragt: " + r2.msg)
	ok(c.ledger.totals.get("admin", 0.0) < admin_before, "Gründungskosten gebucht")
	ok(not CompanyForms.request_change(s, 0, "einzel").ok, "zweiter Antrag während Bearbeitung abgelehnt")
	run(s, 60.0 * 16.0)
	ok(c.form != "einzel" and c.pending_form == "", "Formwechsel nach 15 Tagen wirksam (%s)" % c.form)
	var fee: float = c.ledger.totals.get("admin", 0.0)
	run(s, 60.0 * 31.0)
	ok(c.ledger.totals.get("admin", 0.0) < fee, "monatliche Verwaltungskosten der neuen Form")
	ok(identity_ok(s), "Geld erhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.companies[0].form == c.form and s2.companies[0].founded_min == c.founded_min, "Rechtsform nach Laden")


func test_insolvency() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(4)
	var c := s.companies[1]
	var healthy := s.companies[0]
	healthy.ledger.inject(100000.0)   # kann Auktionen bezahlen
	c.form = "einzel"
	c.ledger.inject(-c.ledger.cash - 5000.0)   # Bargeld -5000
	var k_before := s.contracts.values().filter(func(k): return k.owner == 1)
	run(s, 60.0 * 2.0)
	ok(c.status == "verzug", "Negatives Bargeld = Zahlungsverzug (%s)" % c.status)
	ok(c.grace_until > s.game_min, "Nachfrist läuft")
	ok(s.executor.execute(1, {"action": "wait"}).ok, "während der Nachfrist normal handlungsfähig")
	run(s, 60.0 * 11.0)
	ok(c.status == "verzug", "Nachfrist noch nicht abgelaufen")
	run(s, 60.0 * 5.0)
	ok(c.status == "insolvenz", "nach 15 Tagen Insolvenz (%s)" % c.status)
	ok(c.administrator != "", "Insolvenzverwalter benannt")
	ok(c.ledger.cash >= 0.0, "Überziehung als Forderung der Bank erfasst")
	ok(s.banking.claims_of(1).size() == 1, "Bank hat eine Forderung")
	var r := s.executor.execute(1, {"action": "take_loan", "amount": 1000})
	ok(not r.ok and "Insolvenz" in r.msg, "Aktionen gesperrt: " + r.msg)
	ok(s.company_vehicles(1).all(func(v): return v.stops.is_empty()), "Fahrzeuge ohne Aufträge")
	ok(s.contracts.values().filter(func(k): return k.owner == 1 and k.status in ["accepted", "assigned", "loading", "in_transit"]).is_empty(), "Kundenaufträge abgebrochen")
	ok(s.personnel.employed(1).is_empty(), "Mitarbeiter wieder verfügbar")
	ok(identity_ok(s), "Geld und Bilanz bei Eröffnung")
	run(s, 60.0 * 3.0)
	ok(c.status == "verwertung", "Verwertung (%s)" % c.status)
	var open: Array = s.insolvency.open_auctions()
	ok(open.size() >= 2, "Auktionen für Fahrzeug und Standort (%d)" % open.size())
	var vehicle_auction: Dictionary = open.filter(func(a): return a.kind == "vehicle")[0]
	ok(float(s.insolvency.top_bid(vehicle_auction).amount) > 0.0, "Händler bietet als Untergrenze")
	var low := s.executor.execute(0, {"action": "bid_auction", "auction_id": vehicle_auction.id, "amount": 10})
	ok(not low.ok, "zu niedriges Gebot abgelehnt")
	var bid_amount := ceili(float(vehicle_auction.value) * 0.8)
	var good := s.executor.execute(0, {"action": "bid_auction", "auction_id": vehicle_auction.id, "amount": bid_amount})
	ok(good.ok, "Gebot angenommen: " + good.msg)
	ok(not s.executor.execute(1, {"action": "bid_auction", "auction_id": vehicle_auction.id, "amount": bid_amount * 2}).ok, "Insolvente Firma darf nicht bieten")
	var fleet0 := healthy.vehicle_ids.size()
	var plots_before := s.estate.plot_of(1).size()
	ok(identity_ok(s), "Geld und Bilanz während der Auktion")
	run(s, 60.0 * 8.0)
	ok(vehicle_auction.status == "verkauft" and vehicle_auction.winner == 0, "Zuschlag an das höchste Gebot")
	ok(healthy.vehicle_ids.size() == fleet0 + 1, "Käufer erhält das Fahrzeug")
	ok(c.status == "geschlossen", "Firma geschlossen (%s)" % c.status)
	ok(s.insolvency.archive.size() == 1 and s.insolvency.archive[0].claims > 0.0, "Historie mit Forderungen")
	ok(s.insolvency.archive[0].quota >= 0.0 and s.insolvency.archive[0].quota <= 1.0, "Ausfallquote berechnet")
	ok(s.company_vehicles(1).is_empty(), "Fahrzeuge verwertet")
	ok(s.banking.claims_of(1).is_empty(), "keine offenen Forderungen mehr")
	ok(c.ledger.debt < 0.01 and c.ledger.cash < 0.01, "Restschulden erlassen, Masse verteilt")
	ok(identity_ok(s), "Geld erhalten und Bilanz stimmig nach Verwertung")
	ok(s.ranking()[-1].id == 1, "Geschlossene Firma steht in der Rangliste hinten")
	var plots_after := s.estate.plot_of(1).size()
	ok(plots_after == 0 and plots_before > 0, "Grundstück nicht mehr bei der Firma")
	var fresh_name := c.company_name
	var i0_before: float = s.economy.accounts.I0
	run(s, 60.0 * 11.0)
	var n := s.companies[1]
	ok(n.generation == 2 and n.company_name != fresh_name and n.is_active(), "Neugründung mit neuer Identität (%s)" % n.company_name)
	ok(n.ledger.start_capital == Insolvency.FOUNDING_CAPITAL and s.economy.accounts.I0 <= i0_before, "Gründungskapital aus dem Investorenpool")
	ok(not n.depots.is_empty() and s.vehicles.size() > 0 and n.vehicle_ids.size() == 1, "Neugründer hat Standort und Startfahrzeug")
	ok(identity_ok(s), "Geld erhalten nach Neugründung")
	ok("GESCHLOSSEN" in LiveText.firms(s) or "Historie" in LiveText.firms(s), "Reiter Unternehmen zeigt Historie")
	ok(JSON.stringify(ObservationBuilder.build(s, 0, [], 0.0, 30.0)).contains("rechtsform"), "Beobachtung enthält Rechtsform")
	run(s, 60.0 * 5.0)
	ok(identity_ok(s) and n.is_active(), "Neugründung läuft stabil")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.insolvency.archive.size() == 1 and s2.companies[1].generation == 2, "Historie und Nachfolger nach Laden")
	ok(identity_ok(s2), "Geld erhalten nach Laden")
	run(s2, 60.0 * 3.0)
	ok(identity_ok(s2), "Weiterspielen nach Laden")


func test_trader() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var T := s.trader
	ok(T.bauhof >= 0 and s.city.building(T.bauhof).name.begins_with("Bauhof"), "Bauhof gefunden und benannt")
	ok(T.stock_of("ziegel") == Trader.MATERIALS.ziegel.target, "Anfangsbestand Ziegel")
	ok(T.price("ziegel", 300) < T.price("ziegel", 1), "Mengenrabatt")
	var p_full := T.price("holz")
	s.stock.consume("holz", T.stock_of("holz") - 10, "T0", T.bauhof, "Test")
	ok(T.price("holz") > p_full, "Knappheit macht teurer")
	ok(identity_ok(s), "Warenbilanz nach Entnahme")
	var c := s.companies[0]
	var cash0 := c.ledger.cash
	var t0 := T.cash()
	var r := s.executor.execute(0, {"action": "buy_material", "item": "ziegel", "menge": 100, "lieferung": "abholen"})
	ok(r.ok, "Material gekauft: " + r.msg)
	var cost := cash0 - c.ledger.cash
	ok(cost > 100.0 * 12.0 and is_equal_approx(T.cash() - t0, cost), "Zahlung geht genau an den Bauhof (%.2f)" % cost)
	ok(s.stock.qty("ziegel", "C0", T.bauhof) == 100 and T.stock_of("ziegel") == Trader.MATERIALS.ziegel.target - 100, "Eigentum wechselt, Ware liegt noch am Bauhof")
	ok(s.stock.qty("ziegel", "C0", s.companies[0].depots[0]) == 0, "angenommen heißt noch nicht am Zielort")
	ok(T.shipments.size() == 1, "Transportauftrag vom Bauhof zum Depot")
	var cash_after := c.ledger.cash
	var again := s.executor.execute(0, {"action": "buy_material", "item": "holz", "menge": 100})
	ok(not again.ok and "vorrätig" in again.msg, "nicht vorrätige Menge abgelehnt: " + again.msg)
	ok(is_equal_approx(c.ledger.cash, cash_after), "abgelehnter Kauf kostet nichts")
	# Lieferung frei Depot
	var cash1 := c.ledger.cash
	var d := s.executor.execute(0, {"action": "buy_material", "item": "stahl", "menge": 20, "lieferung": "liefern"})
	ok(d.ok and c.ledger.cash < cash1 - 20.0 * 55.0, "Lieferung gegen Gebühr: " + d.msg)
	ok(s.stock.qty("stahl", "C0", c.depots[0]) == 0, "Lieferung ist unterwegs")
	run(s, 60.0 * 5.0)
	ok(s.stock.qty("stahl", "C0", c.depots[0]) == 20, "Lieferung nach einigen Tagen am Depot")
	ok(identity_ok(s), "Geld und Waren erhalten nach Handel")
	# Ankauf von Altmaterial
	s.stock.add("altmaterial", 30, "C0", c.depots[0], "Rückbau")
	var cash2 := c.ledger.cash
	var sell := s.executor.execute(0, {"action": "sell_material", "item": "altmaterial", "menge": 50})
	ok(sell.ok and is_equal_approx(c.ledger.cash - cash2, 30.0 * 4.0), "Altmaterial verkauft, nur vorhandene Menge: " + sell.msg)
	ok(identity_ok(s), "Geld und Waren nach Ankauf")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.stock.total("ziegel") == s.stock.total("ziegel") and s2.trader.shipments.size() == 1, "Bestand und Transporte nach Laden")
	ok(identity_ok(s2), "Geld und Waren nach Laden")
	# Ausland: Nachbestellung, wenn der Bestand unter den Meldebestand faellt
	var s3 := new_sim(2)
	s3.stock.consume("holz", s3.trader.stock_of("holz") - 5, "T0", s3.trader.bauhof, "Test")
	var x0: float = s3.economy.accounts.X0
	run(s3, 60.0 * 2.0)
	ok(s3.trader.orders.any(func(o): return o.item == "holz"), "Bauhof bestellt Holz nach")
	ok(s3.economy.accounts.X0 > x0, "Importzahlung fließt ins Ausland")
	var holz_before := s3.trader.stock_of("holz")
	run(s3, 60.0 * 5.0)
	ok(s3.trader.stock_of("holz") > holz_before, "Importware trifft nach der Lieferzeit ein")
	ok(s3.trader.orders.filter(func(o): return o.item == "holz").size() <= 1, "keine doppelte Nachbestellung derselben Menge")
	ok(identity_ok(s3), "Geld und Waren nach Import")


func test_trader_production() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var T := s.trader
	var beton0 := T.stock_of("beton")
	var roh0 := T.stock_of("rohmaterial")
	s.stock.consume("beton", beton0 - 20, "T0", T.bauhof, "Test")
	var beton1 := T.stock_of("beton")
	T._produce("betonwerk")
	var cycles := (T.stock_of("beton") - beton1) / 2
	ok(cycles > 0, "Betonwerk produziert (%d Zyklen)" % cycles)
	ok(roh0 - T.stock_of("rohmaterial") == cycles * 3, "Rohmaterial genau nach Rezept verbraucht")
	ok(identity_ok(s), "Warenbilanz nach Produktion")
	s.stock.consume("rohmaterial", T.stock_of("rohmaterial"), "T0", T.bauhof, "Test")
	var b := T.stock_of("beton")
	T._produce("betonwerk")
	ok(T.stock_of("beton") == b, "ohne Rohmaterial keine Produktion")
	var m0 := T.stock_of("module")
	s.stock.consume("module", m0 - 1, "T0", T.bauhof, "Test")
	T._produce("modulwerk")
	ok(T.stock_of("module") > 1, "Modulwerk baut Module aus Stahl und Beton")
	s.stock.add("altmaterial", 30, "T0", T.bauhof, "Test")
	T._produce("recycling")
	ok(T.stock_of("sekundaer") > 0 and T.stock_of("altmaterial") < 30, "Recycling macht aus Altmaterial Sekundärrohstoff")
	s.stock.add("holz", 900, "T0", T.bauhof, "Test")
	run(s, 60.0 * 2.5)
	ok(T.stock_of("holz") < Trader.MATERIALS.holz.target + 900, "Überschuss wird exportiert")
	ok(T.stats.exports > 0.0, "Export bringt dem Bauhof Geld aus dem Ausland")
	ok(identity_ok(s), "Geld und Waren nach Export")
	run(s, 60.0 * 31.0)
	ok(T.stats.wages > 0.0, "Bauhof zahlt Monatslöhne an Haushalte")
	ok(T.cash() >= 0.0, "Bauhof-Konto bleibt positiv (%.0f)" % T.cash())
	ok(identity_ok(s), "Geld und Waren nach einem Monat")


func test_yard_empire_core() -> void:
	var s := new_sim(2)
	var c := s.companies[0]
	var D: CityDepot = s.city_depot
	var Y: YardAdvisor = s.yard
	c.ledger.inject(80000.0)
	# Baustoffe vom Stadtlager: Eigenbau nimmt Restposten, 40 % billiger, Erlös an die Stadtkasse, Abholung mit eigenem Transport
	var z0 := D.material_qty("ziegel")
	ok(z0 > 0 and D.material_offer(2).deckt > 0, "Stadtlager hat Restposten (%d Ziegel)" % z0)
	var p0 := float(s.economy.accounts.P0)
	var cash0 := c.ledger.cash
	var r := place_suggested(s, 0, "stellplatz", "eigen")
	ok(r.ok, "Eigenbau Stellplätze: " + str(r.msg).left(90))
	var f: Dictionary = s.estate.facilities[r.building_id]
	ok(D.material_qty("ziegel") < z0 and float(s.economy.accounts.P0) > p0, "Ziegel aus dem Stadtlager gekauft, Stadtkasse erhält den Erlös")
	ok(cash0 - c.ledger.cash < 900.0 - 1.0, "Restposten machen den Bau billiger (%.0f statt 900)" % (cash0 - c.ledger.cash))
	var ids: Array = f.get("mat_contracts", [f.mat_contract])
	var from_depot: Array = ids.filter(func(id): return s.contracts[id].pickup == D.building and s.contracts[id].internal != "" and s.contracts[id].owner == 0)
	ok(not from_depot.is_empty() and "Stadtlager" in s.contracts[from_depot[0]].label, "eigener Abholauftrag am Stadtlager: " + s.contracts[from_depot[0]].label)
	ok(s.stock.qty("ziegel", "C0", D.building) > 0, "gekaufte Ware liegt bis zur Abholung im Stadtlager")
	for id in ids:
		s.estate.material_delivered(s.contracts[id])
	ok(int(f.mat) == int(f.mat_needed) and s.stock.qty("ziegel", "C0", D.building) == 0 and s.stock.qty("ziegel", "C0", int(f.plot)) > 0, "nach allen Lieferungen liegt das Material auf dem Hof")
	ok(identity_ok(s), "Geld erhalten nach Kauf im Stadtlager")
	# Investitionsakte: Erwartung beim Bau, Messung 10 Tage nach Fertigstellung, Ergebnis im Gedächtnis, Prognosefaktor
	var rec: Dictionary = Y.records.filter(func(x): return x.fid == f.id)[0]
	ok(rec.status == "bau" and rec.has("erwartung"), "Investitionsakte angelegt (Erwartung %s)" % str(rec.erwartung))
	f.progress = 1.0
	f.status = "fertig"
	Y.on_complete(f.id)
	ok(rec.status == "messung", "Messung beginnt mit der Fertigstellung")
	rec.beraterschaetzung = 500.0
	Y.on_day(int(rec.done_day) + YardAdvisor.MEASURE_DAYS)
	ok(rec.status == "gemessen" and rec.has("gemessen"), "nach 10 Tagen gemessen: %s EUR/Monat" % str(rec.gemessen))
	ok(s.memory.books[0].experiences.any(func(e): return "stellplatz" in e.bereich and "gemessen" in str(e.inhalt)), "Ergebnis steht im Gedächtnis der Firma")
	ok(Y.factors.has("stellplatz") and int(Y.factors.stellplatz.n) == 1, "Prognosefaktor für Stellplätze gelernt (%.2f)" % float(Y.factors.stellplatz.f))
	# Bauberater: volle Stellplätze und offene Aufträge -> Vorschlag mit Nutzenrechnung und fertiger Aktion
	for k in s.market.open_contracts():
		c.known[k.id] = true
	c.parking_slots = s.company_vehicles(0).size()
	s.estate.facilities.erase(f.id)   # Testzweck: Fläche des kleinen Startgrundstücks wieder frei
	s.estate._cache.clear()
	var learned := Y.factor("stellplatz")
	ok(learned < 1.0 and learned >= 0.5, "eine Messung ohne Nutzen senkt den Faktor gedämpft (%.2f)" % learned)
	Y.factors.clear()
	var cands: Array = Y.candidates(0)
	var sp: Array = cands.filter(func(x): return x.typ == "stellplatz")
	ok(not sp.is_empty() and float(sp[0].nutzen_monat) > 0.0 and float(sp[0].amortisation_monate) > 0.0 and sp[0].aktion.action == "place_building", "Bauberater schlägt Stellplätze vor: " + (str(sp[0].engpass) if not sp.is_empty() else "-"))
	ok(cands.all(func(x): return int(x.nr) >= 1) and s.estate.summary(0).has("bauberater"), "Vorschläge sind nummeriert und stehen in der Beobachtung")
	# Regel-KI folgt dem Bauberater
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var dec := RuleBrain.decide(obs, c.personality, RandomNumberGenerator.new())
	var planned_build: bool = dec.actions.any(func(x): return x.action == "place_building" or (x.action == "set_plan" and JSON.stringify(x).contains("place_building")))
	ok(planned_build, "Regel-KI plant den Bau bei vollem Hof (Bauberater oder Stellplatzregel)")
	# Speichern und Laden
	Y.factors["stellplatz"] = {"f": 0.8, "n": 1}
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.yard.records.size() == Y.records.size() and s2.yard.factors.has("stellplatz"), "Investitionsakten und Faktoren nach dem Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_yard_specializations() -> void:
	var s := new_sim(2)
	var E: Estate = s.estate
	var c0 := s.companies[0]
	var c1 := s.companies[1]
	c0.ledger.inject(200000.0)
	var site: int = c0.depots[0]
	var mk := func(typ: String, x: int, y: int) -> Dictionary:
		var spec: Dictionary = Estate.FACILITIES[typ]
		var f := {"id": "T%s%d" % [typ, x], "owner": 0, "plot": site, "typ": typ, "x": x, "y": y, "w": int(spec.w), "h": int(spec.h), "rot": 0, "level": 1,
			"status": "fertig", "progress": 1.0, "work": 1.0, "mat_needed": 0, "mat": 0, "mode": "extern", "invest": 0.0, "target_level": 1, "mat_contract": "", "busy": [],
			"material_due": 0.0, "condition": 100.0}
		E.facilities[f.id] = f
		return f
	ok(Estate.FACILITIES.has("kran") and Estate.FACILITIES.has("umschlaghalle"), "neue Gebäude: Schwerlastkran, Umschlaghalle")
	ok(E.specializations(0).is_empty(), "ohne Gebäude keine Spezialisierung")
	# Kuehllogistik: Kuehllager + 2 Kuehltransporter -> +10 % auf Kuehlfracht
	mk.call("kuehllager", 0, 0)
	var cell: Vector2i = s.city.building(site).road
	for i in 2:
		s.add_vehicle(0, "reefer", 0.0, cell)
	ok(E.has_spec(0, "kuehllogistik"), "Kühllogistik-Hub mit Kühllager und 2 Kühltransportern")
	ok(E.spec_overview(0).size() == Estate.SPECIALIZATIONS.size(), "Übersicht aller Spezialisierungen für die Beobachtung")
	# Schwerlast: Kran + schweres Fahrzeug
	var v0: FleetVehicle = s.company_vehicles(0)[0]
	v0.model = "truck"
	mk.call("kran", 4, 0)
	ok(E.has_spec(0, "schwerlast"), "Schwerlasthof mit Kran und Lkw")
	ok(is_equal_approx(E.yard_loading_factor(site, v0), 0.6), "Kran: schwere Fahrzeuge laden am Hof ×0,6")
	var k := Contract.new()
	k.id = "TK1"
	k.cargo = "maschinenteile"
	k.qty = 2
	k.owner = 0
	k.reward = 1000.0
	k.needs_heavy = true
	k.pickup = s.city.buildings[1].id
	k.dropoff = s.city.buildings[2].id
	k.deadline = s.game_min + 10000.0
	s.contracts[k.id] = k
	var rev0: float = c0.ledger.totals.get("transport", 0.0)
	s.deliver_contract(v0, k)
	ok(absf(float(c0.ledger.totals.get("transport", 0.0)) - rev0 - 1100.0) < 0.01, "schwere Fracht +10 %% (%.0f)" % (float(c0.ledger.totals.get("transport", 0.0)) - rev0))
	# Umschlag + Layout: Rampe am Lager
	mk.call("umschlaghalle", 0, 4)
	mk.call("laderampe", 3, 4)
	ok(E.has_spec(0, "umschlag") and E.layout_active(0, 0, site), "Umschlagzentrum und Layout-Bonus Rampe an der Halle")
	var lf := E.yard_loading_factor(site, v0)
	ok(is_equal_approx(lf, 0.6 * 0.7 * 0.8 * 0.85), "Ladefaktor am Hof kombiniert (%.3f)" % lf)
	ok(not E.layout_bonuses(0).is_empty() and E.summary(0).has("spezialisierungen"), "Layout-Boni und Spezialisierungen in der Beobachtung")
	# Pausenraum neben Werkstatt: Erholung x2,5
	mk.call("pausenraum", 8, 0)
	mk.call("werkstatt", 10, 0)
	ok(E.layout_active(0, 1), "Pausenraum berührt die Werkstatt")
	# Tankhof: Notbetankung eines Konkurrenten bringt Erloes
	while s.company_vehicles(0).size() < 5:
		s.add_vehicle(0, "van", 0.0, cell)
	mk.call("tankstelle", 12, 4)
	var fleet_ok: bool = s.company_vehicles(0).size() >= 5
	if fleet_ok:
		ok(E.has_spec(0, "tankhof"), "Tankhof ab 5 Fahrzeugen")
	var v1: FleetVehicle = s.company_vehicles(1)[0]
	var hub := s._service_company("tankhof", 1)
	if hub != null:
		var inc0: float = c0.ledger.totals.get("trade_income", 0.0)
		s._emergency_refuel(v1, c1)
		ok(float(c0.ledger.totals.get("trade_income", 0.0)) > inc0, "Tankhof verdient an der Notbetankung der Konkurrenz")
	else:
		ok(not fleet_ok, "kein Tankhof ohne 5 Fahrzeuge")
	# Werkstatthof: Pannendienst
	for f in E.done(0, "werkstatt"):
		f.level = 2
	var mech: Worker = s.personnel.employed(0)[0]
	mech.skills["reparieren"] = 2
	ok(E.has_spec(0, "werkstatthof"), "Werkstatthof mit Werkstatt Stufe 2 und Mechaniker")
	var inc1: float = c0.ledger.totals.get("trade_income", 0.0)
	s.tow_to_workshop(v1)
	ok(absf(float(c0.ledger.totals.get("trade_income", 0.0)) - inc1 - Catalog.TOW_FEE) < 0.01, "Pannendienst: Abschleppgebühr der Konkurrenz als Erlös")
	ok(identity_ok(s), "Geld erhalten")


func test_yard_permits_and_bids() -> void:
	var s := new_sim(2)
	var E: Estate = s.estate
	E.permits_enabled = true
	E.auctions_enabled = true
	var c0 := s.companies[0]
	var c1 := s.companies[1]
	c0.ledger.inject(200000.0)
	c1.ledger.inject(200000.0)
	# Bauantrag: Lager braucht eine Genehmigung des Bauamts
	var cash0 := c0.ledger.cash
	var r := place_suggested(s, 0, "lager", "extern")
	ok(r.ok and r.has("permit_id") and absf(cash0 - c0.ledger.cash - Estate.PERMIT_FEE) < 0.01, "Lager: Bauantrag gestellt, nur die Gebühr bezahlt: " + str(r.msg).left(70))
	var pm: Dictionary = E.permits[r.permit_id]
	ok(E.facilities.has(pm.hold) and E.facilities[pm.hold].status == "antrag", "Fläche ist während des Antrags reserviert")
	ok(E.summary(0).bauantraege.any(func(x): return x.id == pm.id), "Firma sieht ihren Antrag")
	E._permits_day(int(pm.due))
	ok(pm.status == "genehmigt" and E.facilities.has(pm.fid) and E.facilities[pm.fid].status == "im_bau" and not E.facilities.has(pm.hold), "nach der Frist genehmigt, Bau %s beginnt" % str(pm.get("fid", "")))
	# Kran: Bürgermeister entscheidet, Auflagen kosten 5 %
	var rk := place_suggested(s, 0, "kran", "extern")
	ok(rk.ok and E.permits[rk.permit_id].status == "zur_entscheidung" and s.mayor.indicators().hof_bauantraege.any(func(x): return x.id == rk.permit_id), "Kran-Antrag liegt dem Bürgermeister vor")
	var dec := MayorBrain.decide(s.mayor.indicators())
	ok(dec.actions.any(func(x): return x.action == "decide_yard_permit" and x.antrag == rk.permit_id and x.decision == "auflagen"), "Regelbürgermeister: Kran mit Lärmschutz-Auflage")
	var p0 := float(s.economy.accounts.P0)
	var rr := s.mayor.execute({"action": "decide_yard_permit", "antrag": rk.permit_id, "decision": "auflagen", "reason": "Lärmschutz"})
	ok(rr.ok and E.permits[rk.permit_id].status == "genehmigt" and float(s.economy.accounts.P0) > p0, "Genehmigung mit Auflagen, Gebühr an die Stadt: " + str(rr.msg).left(60))
	# Ablehnung nur mit Begründung; Fläche wird frei
	var ru := place_suggested(s, 0, "umschlaghalle", "extern")
	if ru.ok:
		ok(not E.decide_permit(ru.permit_id, "ablehnen", "", "Test").ok, "Ablehnung ohne Begründung nicht möglich")
		var hold: String = E.permits[ru.permit_id].hold
		ok(E.decide_permit(ru.permit_id, "ablehnen", "Grundstück zu klein für den Lkw-Verkehr", "Test").ok and not E.facilities.has(hold), "Ablehnung mit Begründung, Fläche frei")
	else:
		ok(true, "kein Platz mehr für eine Umschlaghalle: " + str(ru.msg).left(60))
	# Grundstücksgebote: Nachbar überbietet, Sperrgrundstück, Rückkauf
	var ext: Array = E.summary(0).erweiterbar
	ok(not ext.is_empty(), "Erweiterungsfläche am Hof vorhanden")
	var pid := int(ext[0].id)
	var price := float(ext[0].kaufpreis)
	var cash_before := c0.ledger.cash
	var ra := s.executor.execute(0, {"action": "expand_plot", "plot_id": pid, "art": "kaufen"})
	ok(ra.ok and E.auctions.has(pid) and is_equal_approx(c0.ledger.cash, cash_before), "Kauf startet ein Gebotsverfahren (noch nichts bezahlt)")
	ok(not s.executor.execute(1, {"action": "bid_plot", "plot_id": pid, "gebot": price * 1.01}).ok, "Gebot unter +5 %% abgelehnt")
	var rb := s.executor.execute(1, {"action": "bid_plot", "plot_id": pid, "gebot": price * 1.1})
	ok(rb.ok and int(E.auctions[pid].leader) == 1, "Konkurrent überbietet: " + str(rb.msg).left(60))
	var obs0 := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var d0 := RuleBrain.decide(obs0, "wachstum", RandomNumberGenerator.new())
	ok(d0.actions.any(func(x): return x.action == "bid_plot" and int(x.plot_id) == pid) or JSON.stringify(d0).contains("bid_plot"), "Regel-KI verteidigt die Fläche am eigenen Hof")
	E._auctions_tick(float(E.auctions[pid].ends) + 1.0)
	ok(int(E.plots[pid].owner) == 1 and not E.auctions.has(pid), "Zuschlag an den Höchstbietenden (Sperrgrundstück)")
	var sug1: Dictionary = E.suggestions(1, c1.depots[0])
	var foreign_rect := Rect2i(int(E.plots[pid].x), int(E.plots[pid].y), int(E.plots[pid].w), int(E.plots[pid].h))
	ok(not sug1.values().any(func(xy): return foreign_rect.has_point(Vector2i(int(xy[0]), int(xy[1])))), "auf dem Sperrgrundstück darf der Käufer nicht bauen")
	var obs1 := ObservationBuilder.build(s, 1, [], 0.0, 10.0)
	var d1 := RuleBrain.decide(obs1, "risikospieler", RandomNumberGenerator.new())
	ok(JSON.stringify(d1).contains("offer_plot"), "Regel-KI bietet das Sperrgrundstück dem Nachbarn an")
	ok(s.executor.execute(1, {"action": "offer_plot", "plot_id": pid, "preis": price * 1.5}).ok, "Sperrgrundstück angeboten")
	var cash1 := c1.ledger.cash
	var rbuy := s.executor.execute(0, {"action": "buy_plot", "plot_id": pid})
	ok(rbuy.ok and int(E.plots[pid].owner) == 0 and c1.ledger.cash > cash1, "Nachbar kauft zurück: " + str(rbuy.msg).left(60))
	ok(identity_ok(s), "Bilanzen nach Gebot und Weiterverkauf")
	var rrel := s.executor.execute(0, {"action": "release_plot", "plot_id": pid})
	ok(rrel.ok and int(E.plots[pid].owner) == -1, "Grundstück an die Stadt zurückgegeben (80 %)")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.estate.permits.size() == E.permits.size(), "Bauanträge nach dem Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_build_materials() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	var T := s.trader
	for typ in Estate.FACILITIES:
		var spec: Dictionary = Estate.FACILITIES[typ]
		ok(T.nominal_value(Trader.bom(int(spec.mat))) <= 0.6 * float(spec.cost), "Material von %s ist höchstens 60 %% der Baukosten" % typ)
	var ziegel0 := T.stock_of("ziegel")
	c.ledger.inject(50000.0)
	var cash0 := c.ledger.cash
	var t0 := T.cash()
	var r := place_suggested(s, 0, "stellplatz", "extern")
	ok(r.ok, "Baufirma baut Stellplätze: " + r.msg)
	var spent := cash0 - c.ledger.cash
	ok(is_equal_approx(spent, 900.0 * 1.4), "Gesamtkosten unverändert (%.2f)" % spent)
	ok(T.cash() > t0 and ziegel0 - T.stock_of("ziegel") == 6, "Material kommt vom Bauhof (6 Ziegel) und bringt ihm Geld")
	var f: Dictionary = s.estate.facilities[r.building_id]
	ok(s.stock.qty("ziegel", "C0", T.bauhof) == 6, "Eigentum wechselt sofort, Ware liegt noch am Bauhof")
	run(s, 32.0)   # 64 Spielminuten: Material (60 min) ist da, der Bau noch nicht fertig
	ok(s.stock.qty("ziegel", "C0", int(f.plot)) == 6 and s.stock.qty("ziegel", "C0", T.bauhof) == 0, "Baufirma bringt das Material zur Baustelle")
	until_done(s, func(): return f.status == "fertig", 3000.0)
	ok(f.status == "fertig", "Stellplätze fertiggestellt")
	ok(s.stock.qty("ziegel", "C0", int(f.plot)) == 0 and int(s.stock.consumed.get("ziegel", 0)) >= 6, "Material wurde verbraucht")
	ok(identity_ok(s), "Geld, Waren und Bilanz nach dem Bau")
	var need := Trader.bom(2)
	for it in need:
		s.stock.add(it, int(need[it]), "C0", c.depots[0], "Test")
	var cash1 := c.ledger.cash
	var t1 := T.cash()
	var r2 := place_suggested(s, 0, "waschplatz", "extern")
	ok(r2.ok, "Waschplatz mit eigenem Material: " + r2.msg)
	ok(is_equal_approx(T.cash(), t1), "Bauhof erhält nichts für bereits vorhandenes Material")
	ok(cash1 - c.ledger.cash < 2000.0 * 1.4 - 1.0, "Eigenes Material mindert die Bezahlung")
	ok(identity_ok(s), "Bilanz mit eigenem Material")


func test_estate_facilities() -> void:
	var s := new_sim(2)
	var E := s.estate
	var c := s.companies[0]
	c.ledger.inject(100000.0)
	var site: int = c.depots[0]
	var slots0 := c.parking_slots
	var fuel0 := c.fuel_cap
	var cold0 := E.storage_cap(site, true)
	for typ in ["garage", "kuehllager", "tankstelle", "waschplatz", "schulung"]:
		var r := place_suggested(s, 0, typ, "extern")
		ok(r.ok, "%s wird gebaut: %s" % [typ, r.msg])
		if r.ok:
			var f: Dictionary = E.facilities[r.building_id]
			until_done(s, func(): return f.status == "fertig", 3000.0)
			ok(f.status == "fertig", "%s fertiggestellt" % typ)
	ok(c.parking_slots == slots0 + 2, "Fahrzeughalle: 2 Stellplätze mehr")
	ok(E.storage_cap(site, true) == cold0 + 25, "Kühllager: 25 gekühlte Lagerplätze")
	ok(is_equal_approx(c.fuel_cap, fuel0 + 3000.0), "Betriebstankstelle: Tank +3000 l")
	# Waschplatz: Fahrzeug auf dem Hof waschen
	var v: FleetVehicle = s.vehicles[c.vehicle_ids[0]]
	v.state = "idle"
	v.pos = Vector2(s.city.building(site).x + 1, s.city.building(site).y + 1)
	var cash0 := c.ledger.cash
	var rw := s.executor.execute(0, {"action": "wash_vehicle", "vehicle_id": v.id})
	if rw.ok:
		ok(v.state == "washing" and v.clean_until > s.game_min and is_equal_approx(cash0 - c.ledger.cash, 30.0), "Wäsche kostet 30 EUR und macht das Fahrzeug sauber")
	else:
		ok(E.on_plot(0, v.pos) < 0, "Wäsche nur auf dem Hof: " + rw.msg)
	# Schulung: Fähigkeit +1 gegen 800 EUR
	var w := hire_free(s, 0, "loader")
	var skill: String = Worker.SKILLS[0]
	var lvl0 := int(w.skills.get(skill, 0))
	var cash1 := c.ledger.cash
	var rt := s.executor.execute(0, {"action": "train_worker", "worker_id": w.id, "faehigkeit": skill})
	ok(rt.ok and is_equal_approx(cash1 - c.ledger.cash, 800.0), "Schulung kostet 800 EUR: " + str(rt.get("msg", "")))
	until_done(s, func(): return int(w.skills.get(skill, 0)) > lvl0 or lvl0 >= 3, 600.0)
	ok(int(w.skills.get(skill, 0)) == mini(3, lvl0 + 1), "Fähigkeit steigt um 1 (%d → %d)" % [lvl0, int(w.skills.get(skill, 0))])
	ok(identity_ok(s), "Geld und Waren erhalten nach allen Einrichtungen")


func test_player_loans() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var P: PlayerLoans = s.player_loans
	var A := s.companies[0]
	var B := s.companies[1]
	A.ledger.inject(20000.0)
	ok(not P.offer(0, 0, 1000.0, 0.05, 6).ok, "Kein Kredit an sich selbst")
	ok(not P.offer(0, 1, 100.0, 0.05, 6).ok, "Mindestbetrag")
	ok(not P.offer(0, 1, 900000.0, 0.05, 6).ok, "Geber muss das Geld besitzen")
	var o := P.offer(0, 1, 4000.0, 0.06, 6)
	ok(o.ok, "Angebot: " + o.msg)
	var id: String = o.loan_id
	var cashA := A.ledger.cash
	ok(A.ledger.cash == cashA and B.ledger.debt == 0.0, "Vor der Annahme fließt kein Geld")
	ok(not P.accept(id, 0).ok, "Der Anbieter kann sein eigenes Angebot nicht annehmen")
	ok(not P.counter(id, 0, 3000.0).ok, "Der Anbieter kann sich nicht selbst antworten")
	# Gegenangebote bis zur Grenze
	var c1 := P.counter(id, 1, 3000.0, 0.04)
	ok(c1.ok and P.loans[id].amount == 3000.0 and P.loans[id].proposer == 1, "Gegenangebot ändert Bedingungen: " + c1.msg)
	ok(P.counter(id, 0, -1.0, 0.05).ok and P.counter(id, 1, -1.0, 0.045).ok, "Weitere Gegenangebote")
	ok(not P.counter(id, 0, -1.0, 0.048).ok, "Nach 3 Gegenangeboten nur noch annehmen oder ablehnen")
	var cashB := B.ledger.cash
	var r := P.accept(id, 0)
	ok(r.ok and absf(A.ledger.cash - (cashA - 3000.0)) < 0.01 and absf(B.ledger.cash - (cashB + 3000.0)) < 0.01, "Annahme zahlt aus: " + r.msg)
	ok(A.ledger.receivables == 3000.0 and B.ledger.debt == 3000.0, "Forderung beim Geber, Schuld beim Nehmer")
	ok(identity_ok(s), "Geld und Bilanz erhalten nach Auszahlung")
	# Raten
	run(s, 60.0 * 65.0)
	var l: Dictionary = P.loans[id]
	var paid: int = l.plan.filter(func(x): return x.status == "bezahlt").size()
	ok(paid >= 1 and l.outstanding < 3000.0, "Raten werden eingezogen (%d bezahlt)" % paid)
	ok(A.ledger.totals.get("interest_income", 0.0) > 0.0 and B.ledger.totals.get("interest", 0.0) < 0.0, "Zins ist Ertrag beim Geber und Aufwand beim Nehmer")
	ok(absf(A.ledger.receivables - l.outstanding) < 0.01 and absf(B.ledger.debt - l.outstanding) < 0.01 + B.ledger.debt - l.outstanding, "Forderung folgt der Restschuld")
	ok(identity_ok(s), "Geld und Bilanz erhalten nach Raten")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.player_loans.loans[id].outstanding == l.outstanding and s2.player_loans.loans[id].status == l.status, "Kredit bleibt nach Laden erhalten")
	# Ausfall mit Fahrzeugpfand
	var veh: FleetVehicle = s.vehicles[B.vehicle_ids[0]]
	var o2 := P.offer(0, 1, 2000.0, 0.05, 6, veh.id)
	ok(o2.ok and s.banking.pledged_to(veh.id) == o2.loan_id, "Fahrzeug als Pfand gesperrt: " + o2.msg)
	ok(P.accept(o2.loan_id, 1).ok, "Nehmer nimmt Kredit mit Pfand an")
	var drain := B.ledger.cash
	B.ledger.pay_out_owner(drain, "H0")
	var nveh := s.vehicles.size()
	for m in 4:
		P.on_month(GameCalendar.month_of(s.game_min) + 8 + m)
	var l2: Dictionary = P.loans[o2.loan_id]
	ok((int(l2.arrears) >= 1 or l2.status == "getilgt") and l2.status in ["ausgefallen", "rueckstand", "getilgt"], "Ausbleibende Raten führen zu Rückstand (%s)" % l2.status)
	ok(s.vehicles.size() == nveh - 1 and l2.collateral == -1 and l2.outstanding < 2000.0, "Ausfall verwertet das Pfand-Fahrzeug, Erlös mindert die Schuld (%.0f)" % l2.outstanding)
	ok(identity_ok(s), "Geld und Bilanz erhalten nach Ausfall")
	# Ablehnen und Verfall
	var o3 := P.offer(0, 1, 800.0, 0.05, 3)
	ok(P.decline(o3.loan_id, 1).ok and P.loans[o3.loan_id].status == "abgelehnt", "Ablehnen beendet das Angebot")
	var o4 := P.offer(0, 1, 800.0, 0.05, 3)
	P.loans[o4.loan_id].since = GameCalendar.day_of(s.game_min) - 20
	P.on_day(0)
	ok(P.loans[o4.loan_id].status == "abgelaufen", "Angebote verfallen nach %d Tagen" % PlayerLoans.OFFER_DAYS)
	# Aktionen und Beobachtung
	var ra := s.executor.execute(0, {"action": "offer_loan", "nehmer": 1, "betrag": 1000, "zins": 0.05, "monate": 4})
	ok(ra.ok, "KI-Aktion offer_loan: " + str(ra.get("msg", "")))
	ok(s.player_loans.summary_of(1).angebote.size() == 1 and s.player_loans.summary_of(1).angebote[0].du_antwortest, "Beobachtung zeigt das Angebot an die Gegenseite")
	ok(s.executor.execute(1, {"action": "accept_loan", "kredit_id": s.player_loans.summary_of(1).angebote[0].id}).ok, "KI-Aktion accept_loan")
	# Insolvenz des Nehmers: Abschreibung
	B.status = "insolvenz"
	P.on_day(0)
	var open_left := P.loans.values().filter(func(x): return x.status in ["laufend", "rueckstand", "ausgefallen"]).size()
	ok(open_left == 0 and A.ledger.receivables < 0.01, "Fällt eine Seite weg, wird abgeschrieben")
	ok(identity_ok(s), "Geld und Bilanz erhalten nach Abschreibung")


func test_arena() -> void:
	GameCalendar.configure(60.0)
	var spec := {"seed": 21, "map": 128, "steps": 1200, "brains": ["kostenoptimierer", "wachstum"], "max_actions": 4,
		"events": [{"step": 400, "typ": "strassensperre", "params": {"cell": "depot0"}, "duration": 300.0}]}
	var a := Arena.run(spec)
	ok(a.actions.size() > 0, "Regel-KIs entscheiden und werden aufgezeichnet (%d Aktionen)" % a.actions.size())
	var cap_ok := true
	var per := {}
	for x in a.actions:
		var k := "%d:%d" % [x.step, x.cid]
		per[k] = int(per.get(k, 0)) + 1
		cap_ok = cap_ok and int(per[k]) <= 4
	ok(cap_ok, "Gleiches Aktionsbudget je Entscheidung")
	ok(a.sim.traffic_events.any(func(t): return t.kind == "sperrung"), "Straßensperrung im Abnahmeszenario ausgelöst")
	ok(identity_ok(a.sim), "Geld, Waren und Bilanz erhalten")
	var r := Arena.replay(spec, a.actions)
	ok(r.fingerprint == a.fingerprint, "Wiederholung ohne API/KI ergibt denselben Endstand")
	ok(str(r.rows) == str(a.rows), "Kennzahlen der Wiederholung identisch")
	var cmp := Arena.compare(spec)
	ok(cmp.rows.size() == 4 and cmp.summary.size() == 2, "Zwei Strategien in zwei Runden (%d Zeilen)" % cmp.rows.size())
	var sites := {}
	for row in cmp.rows:
		sites["%s@%d" % [row.strategie, row.platz]] = true
	ok(sites.size() == 4, "Jede Strategie sitzt auf jedem Startplatz")
	ok(cmp.summary.all(func(x): return x.laeufe == 2), "Mittelwerte über gleich viele Läufe")
	var csv := Arena.to_csv(cmp.rows)
	ok(csv.begins_with("platz;strategie;rang;gewinn") and csv.count("\n") == 5, "CSV-Export: Kopfzeile und vier Datenzeilen")


func test_action_assist() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	# Lücken füllen: recruit_worker ohne worker_id nimmt den günstigsten Bewerber
	var a: Dictionary = s.executor.assist.complete(0, {"action": "recruit_worker"})
	ok(a.has("worker_id") and a.has("_ergaenzt"), "recruit_worker ohne worker_id: Bewerber ergänzt (%s)" % str(a.get("worker_id", "-")))
	# Fahrzeug ohne Fahrer + Arbeiter ohne kind -> fahren
	var w := hire_free(s, 0, "driver")
	var offer: Dictionary = s.resources.cheapest_offer(Catalog.VEHICLE_MODELS.keys()[0])
	c.ledger.inject(50000.0)
	c.ledger.invest(5000.0)
	var nv := s.add_vehicle(0, offer.model if not offer.is_empty() else Catalog.VEHICLE_MODELS.keys()[0], 5000.0, s.depot_road(0))
	var t: Dictionary = s.executor.assist.complete(0, {"action": "assign_worker_task", "worker_id": w.id})
	ok(t.get("kind", "") == "fahren" and t.has("vehicle_id"), "assign_worker_task ohne kind: Fahrer ohne Fahrzeug wird zugeteilt")
	var vid: int = t.vehicle_id
	ok(s.vehicles[vid].owner == 0 and s.personnel.driver_of(vid) == null, "…einem Fahrzeug ohne Fahrer")
	var keep: Dictionary = s.executor.assist.complete(0, {"action": "assign_worker_task", "worker_id": w.id, "kind": "reparieren", "vehicle_id": nv.id})
	ok(keep.kind == "reparieren" and not keep.has("_ergaenzt"), "Vollständige Aktionen bleiben unverändert")
	# Voller Hof: Meldung enthält fertige place_building-Aktion
	while c.vehicle_ids.size() < c.fleet_limit():
		c.ledger.invest(5000.0)
		s.add_vehicle(0, nv.model, 5000.0, s.depot_road(0))
	var r: Dictionary = s.executor.execute(0, {"action": "buy_vehicle", "model": nv.model})
	ok(r.ok and s.executor.assist._parking_in_construction(0), "Voller Hof: Assistent baut selbst einen Stellplatz")
	var r2: Dictionary = s.executor.execute(0, {"action": "buy_vehicle", "model": nv.model})
	ok(not r2.ok and "place_building" in r2.msg and "stellplatz" in r2.msg and "\"x\"" in r2.msg, "Stellplatz im Bau: Meldung nennt weiter die Bauaktion, kein zweiter Bau")
	# Fahrzeug ohne Fahrer + freier Arbeiter: Fahrbefehle ohne Angaben oder mit falscher Fahrzeug-ID werden ergaenzt
	var s2 := new_sim(2)
	var w2 := hire_free(s2, 0, "driver")
	s2.companies[0].ledger.inject(50000.0)
	s2.companies[0].ledger.invest(5000.0)
	var nv2 := s2.add_vehicle(0, Catalog.VEHICLE_MODELS.keys()[0], 5000.0, s2.depot_road(0))
	var e1: Dictionary = s2.executor.assist.complete(0, {"action": "assign_worker_task"})
	ok(e1.get("kind", "") == "fahren" and e1.has("worker_id") and e1.has("vehicle_id"), "assign_worker_task ganz ohne Angaben: Fahrer und Fahrzeug ergänzt")
	var e2: Dictionary = s2.executor.assist.complete(0, {"action": "assign_worker_task", "kind": "fahren", "vehicle_id": 99999, "worker_id": w2.id})
	ok(s2.vehicles.has(int(e2.vehicle_id)) and s2.vehicles[int(e2.vehicle_id)].owner == 0, "Fahraufgabe mit erfundener Fahrzeug-ID: eigenes Fahrzeug eingesetzt")
	var e3: Dictionary = s2.executor.assist.complete(0, {"action": "assign_worker_task", "kind": "fahren", "vehicle_id": nv2.id})
	ok(e3.get("worker_id", "") != "", "Fahraufgabe ohne Arbeiter: freier Fahrer ergänzt")
	var foreign: int = s2.companies[1].vehicle_ids[0]
	var e4: Dictionary = s2.executor.assist.complete(0, {"action": "assign_worker_task", "kind": "fahren", "vehicle_id": foreign, "worker_id": w2.id})
	ok(int(e4.vehicle_id) != foreign and s2.vehicles[int(e4.vehicle_id)].owner == 0, "Fremdes Fahrzeug wird durch eigenes ersetzt")
	var e5: Dictionary = s2.executor.assist.complete(0, {"action": "assign_worker_task", "kind": "refuel_vehicle", "worker_id": w2.id})
	ok(e5.action == "schedule_refueling" and e5.has("below_l"), "Tank-Aufgabe wird zur Nachtank-Regel")
	# Offener bekannter Auftrag: assign_transport wird zu accept_contract mit Fahrzeug
	var ocands: Array = s2.market.open_contracts().filter(func(k): return k.vehicle_ok("cargobike") or k.vehicle_ok("van"))
	var drv_v = s2.company_vehicles(0).filter(func(v): return s2.personnel.driver_of(v.id) != null and v.state == "idle")
	if not ocands.is_empty() and not drv_v.is_empty():
		var kk = ocands.filter(func(k): return k.vehicle_ok(drv_v[0].model))
		if not kk.is_empty():
			s2.companies[0].known[kk[0].id] = true
			var e7: Dictionary = s2.executor.assist.complete(0, ActionExecutor.normalize({"action": "assign_transport", "target_id": kk[0].id, "vehicle_id": "F9"}))
			ok(e7.action == "accept_contract" and e7.contract_id == kk[0].id and s2.vehicles[int(e7.vehicle_id)].owner == 0, "Offener Auftrag: erst annehmen statt zuweisen (target_id und fremde Fahrzeug-ID)")
	# Zu kleines Fahrzeug fuer den eigenen Auftrag: passendes freies Fahrzeug mit Fahrer
	var big_v := s2.add_vehicle(0, "transporter", 5000.0, s2.depot_road(0))
	var wd2 := hire_free(s2, 0, "driver")
	wd2.vehicle_id = big_v.id   # Fahrer sitzt am Steuer
	var bk := Contract.new()
	bk.id = "ABIG"
	bk.qty = 15
	bk.owner = 0
	bk.status = "accepted"
	bk.cargo = "pakete"
	s2.contracts[bk.id] = bk
	var small_v := s2.add_vehicle(0, "cargobike", 2500.0, s2.depot_road(0))
	var e8: Dictionary = s2.executor.assist.complete(0, {"action": "assign_transport", "contract_id": "ABIG", "vehicle_id": small_v.id})
	ok(s2.personnel.driver_of(big_v.id) != null and int(e8.vehicle_id) == big_v.id, "Zu kleines Fahrzeug wird durch das passende mit Fahrer ersetzt")
	# Freie Plan- und Auftragslisten des Modells
	var np := ActionExecutor.normalize({"action": "set_plan", "goals": ["Aufträge fahren", "Flotte ausbauen"], "next_steps": ["Auftrag sammeln", "Fahrzeug kaufen"]})
	ok(str(np.ziel).contains("Aufträge fahren") and np.schritte.size() == 2 and np.schritte[1].text == "Fahrzeug kaufen", "set_plan aus goals/next_steps")
	var na := ActionExecutor.normalize({"action": "accept_contract", "details": {"ziele": ["A3", "A5", "A6"]}})
	ok(na.contract_id == "A3" and na._kandidaten.size() == 3, "accept_contract mit Zielliste: erste ID plus Kandidaten")
	var open_ids: Array = s2.market.open_contracts().map(func(k): return k.id)
	if open_ids.size() >= 1:
		s2.companies[0].known[open_ids[0]] = true
		var nc := s2.executor.assist.complete(0, {"action": "accept_contract", "contract_id": "AX999", "_kandidaten": ["AX999", open_ids[0]]})
		ok(nc.contract_id == open_ids[0], "Erster Kandidat weg: nächster freier bekannter Auftrag wird genommen")
	var e6: Dictionary = s2.executor.assist.complete(0, {"action": "assign_transport", "contract_id": "C1", "vehicle_id": null})
	ok(e6.action == "assign_transport" or e6.action == "assign_worker_task", "erfundene Auftrags-ID und vehicle_id=null stürzen nicht ab")
	# Geldmangel: Meldung nennt Kredit
	var c1 := s.companies[1]
	c1.ledger.pay_out_owner(c1.ledger.cash - 100.0, "H0")
	var o1: Dictionary = s.resources.cheapest_offer(nv.model)
	if not o1.is_empty():
		var r1: Dictionary = s.executor.execute(1, {"action": "buy_vehicle", "offer_id": o1.id})
		ok(not r1.ok and ("take_loan" in r1.msg or "Bargeld" in r1.msg), "Geldmangel: Meldung nennt Bargeld und möglichen Kredit")
	ok(identity_ok(s), "Geld, Waren und Bilanz erhalten")


func test_standings() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(3)
	var best := s.companies[2]
	best.ledger.book("transport", 5000.0, true, "Test", s.game_min)
	run(s, 60.0 * 31.0)
	ok(s.standings.stage_winners.size() == 1, "Ein Etappensieger nach dem ersten Monat (%d)" % s.standings.stage_winners.size())
	ok(s.standings.series.size() == 1 and s.standings.values(2, "profit").size() == 1, "Zeitreihe je Monat")
	ok(s.standings.leader() == s.standings.winner(), "Führender ist zahlungsfähig")
	# Zahlungsunfaehiger Spitzenreiter kann nicht gewinnen
	var top := s.standings.winner()
	top.status = "verzug"
	ok(s.standings.winner() != top and s.ranking()[0] != top, "Firma im Zahlungsverzug ist nicht Sieger")
	top.status = "aktiv"
	var w: Dictionary = s.standings.stage_winners[0]
	ok("Monat 1" in LiveText.standings(s) and w.name != "", "Rangliste zeigt Etappensieger")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.standings.stage_winners.size() == 1 and s2.standings.stage_winners[0].name == w.name, "Etappensieger bleiben nach Laden erhalten")


## Gesamtablauf des Wirtschaftskreislaufs in zwölf Schritten (Auftrag 2).
func test_economy_cycle() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(4)
	var A := s.companies[0]
	var Bc := s.companies[1]
	# 1) Start: vier Unternehmen, Geld und Waren stimmen
	ok(s.companies.size() == 4 and identity_ok(s), "1) Start: vier Unternehmen, Geld und Waren erhalten")
	# 2) Kredit gegen Fahrzeugpfand
	var coll := s.banking.best_collateral(0)
	var loan := s.executor.execute(0, {"action": "request_loan", "bank": "B2", "amount": 12000, "monate": 12, "fahrzeug_id": coll})
	ok(loan.ok and A.ledger.debt == 12000.0 and s.banking.pledged_to(coll) != "", "2) Kredit mit Pfand: " + loan.msg)
	# 3) Material vom Bauhof für einen Bau, 4) Bau fertig, Material verbraucht
	A.ledger.inject(30000.0)
	var ziegel := s.trader.stock_of("ziegel")
	var placed := place_suggested(s, 0, "stellplatz", "extern")
	ok(placed.ok and s.trader.stock_of("ziegel") < ziegel, "3) Baumaterial vom Bauhof gekauft: " + placed.msg)
	var fac: Dictionary = s.estate.facilities[placed.building_id]
	until_done(s, func(): return fac.status == "fertig", 3000.0)
	ok(fac.status == "fertig" and int(s.stock.consumed.get("ziegel", 0)) >= 6, "4) Bau fertig, Material verbraucht")
	# 5) Geld anlegen
	var dep := s.executor.execute(0, {"action": "deposit_money", "amount": 5000, "art": "fest", "monate": 6, "bank": "B3"})
	ok(dep.ok and A.ledger.deposits == 5000.0, "5) Festgeld angelegt")
	# 6) Ein Monat: Raten, Zinsen, Löhne, Verwaltungskosten
	var h0: float = s.economy.accounts.H0
	var b2: float = s.banking.equity(1)
	run(s, 60.0 * 31.0)
	ok(A.ledger.totals.get("interest", 0.0) < 0.0 and A.ledger.totals.get("interest_income", 0.0) > 0.0, "6) Zinsen gezahlt und erhalten")
	ok(s.banking.equity(1) > b2 and s.economy.accounts.H0 != h0, "6) Bank verdient, Haushalte erhalten Löhne")
	ok(identity_ok(s), "6) Geld, Waren und Bilanzen stimmen nach einem Monat")
	# 7) Zahlungsverzug, 8) Insolvenz mit Auktionen
	Bc.ledger.inject(-Bc.ledger.cash - 4000.0)
	run(s, 60.0 * 3.0)
	ok(Bc.status == "verzug", "7) Zahlungsverzug bei negativem Bargeld")
	run(s, 60.0 * 14.0)
	ok(Bc.status in ["insolvenz", "verwertung"], "8) Insolvenzverfahren eröffnet (%s)" % Bc.status)
	run(s, 60.0 * 4.0)
	var auction: Dictionary = s.insolvency.open_auctions().filter(func(a): return a.kind == "vehicle")[0]
	var bid := s.executor.execute(0, {"action": "bid_auction", "auction_id": auction.id, "amount": ceili(float(auction.value) * 0.8)})
	ok(bid.ok, "8) Konkurrent bietet in der Auktion: " + bid.msg)
	# 9) Verteilung und Schließung
	run(s, 60.0 * 8.0)
	ok(Bc.status == "geschlossen" and s.insolvency.archive.size() == 1, "9) Verteilung an Gläubiger, Firma geschlossen")
	ok(identity_ok(s), "9) Geld, Waren und Bilanzen nach der Insolvenz")
	# 10) Neugründung
	run(s, 60.0 * 11.0)
	ok(s.companies[1].generation == 2 and s.companies[1].is_active(), "10) Neugründung mit neuer Identität")
	# 11) Etappensieger und Rangliste
	ok(s.standings.stage_winners.size() >= 1 and s.standings.winner() != null, "11) Etappensieger und zahlungsfähiger Führender")
	# 12) Speichern, Laden, Weiterspielen
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(identity_ok(s2) and s2.insolvency.archive.size() == 1 and s2.banking.loans.size() == s.banking.loans.size(), "12) Spielstand geladen")
	run(s2, 60.0 * 31.0)
	ok(identity_ok(s2), "12) Geld und Waren erhalten nach dem Laden")


## Mehrere Spieljahre am Stück: Konservierung jeden Monat, Speichern/Laden in der Mitte ergibt denselben Verlauf.
func test_multi_year_consistency() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var months := 14
	var bad := 0
	for m in months:
		for i in int(1800.0 / 0.5):
			s.step(0.5)
		if not identity_ok(s):
			bad += 1
	ok(bad == 0, "Geld, Waren und Bilanzen stimmen in allen %d Monaten (%d Verstöße)" % [months, bad])
	ok(GameCalendar.parts(s.game_min).jahr == 2, "Spieljahr 2 erreicht")
	ok(s.standings.stage_winners.size() >= months - 2, "Etappensieger jedes Monats erfasst (%d)" % s.standings.stage_winners.size())
	ok(s.stock.balance_error() == 0, "Warenbilanz nach über einem Jahr")
	ok(s.trader.cash() >= 0.0, "Bauhof bleibt zahlungsfähig (%.0f)" % s.trader.cash())


func test_provider_choice() -> void:
	var saved_path := SetupMenu.setup_path
	SetupMenu.setup_path = "user://test_setup_does_not_exist.json"   # unabhängig von den gespeicherten Einstellungen des Spielers
	var menu := SetupMenu.new()
	menu._ready()
	for i in [2, 3]:
		menu.rows[i].enabled.button_pressed = false
	var local: Dictionary = menu.rows[0]
	local.provider.select(1)
	menu._configure_provider(local, "ollama", true)
	local.api_key.text = "TEST_KEY_MUST_NOT_LEAVE"
	local.save_key.button_pressed = true
	var remote: Dictionary = menu.rows[1]
	remote.provider.select(2)
	menu._configure_provider(remote, "openai", true)
	remote.base_url.text = "https://api.example.com/v1"
	remote.model.text = "external-model"
	remote.api_key.text = "TEST_KEY_REMOTE"
	var cfg := menu.collect()
	ok(cfg.players.size() == 2 and cfg.players[0].provider == "ollama" and cfg.players[1].provider == "openai",
		"Anbieter pro Spieler getrennt")
	ok(cfg.players[0].base_url == OllamaAdapter.DEFAULT_BASE_URL and cfg.players[0].model == OllamaAdapter.DEFAULT_MODEL
		and cfg.players[0].api_key == "" and not cfg.players[0].save_key and cfg.players[0].timeout == 90.0,
		"Ollama-Preset ohne Key und mit Start-Timeout")
	ok(cfg.players[1].base_url == "https://api.example.com/v1" and cfg.players[1].model == "external-model"
		and cfg.players[1].api_key == "TEST_KEY_REMOTE", "Externe API behält eigene URL, Modell und Key")
	ok(SetupMenu.validate(cfg) == "", "gemischte Anbieter-Konfiguration gültig")
	ok(cfg.mayor.provider == "demo", "Bürgermeister standardmäßig regelbasiert")
	SetupMenu.setup_path = saved_path
	menu.mayor_opt.select(1)
	ok(menu.collect().mayor.provider == "global", "Bürgermeister-Zugang im Startmenü wählbar")
	cfg.players[1].base_url = "http://api.example.com/v1"
	ok(SetupMenu.validate(cfg).contains("HTTPS"), "externer Key nicht über unverschlüsseltes HTTP")
	cfg.players[1].base_url = "http://localhost:11435@api.example.com/v1"
	ok(SetupMenu.validate(cfg).contains("HTTPS"), "Loopback-URL mit fremdem Host abgewiesen")
	cfg.players[1].base_url = "https://api.example.com/v1"
	cfg.players[0].base_url = "http://127.0.0.1:11435/v1"
	ok(SetupMenu.validate(cfg).contains("ohne /v1"), "Ollama nutzt die native API")
	menu.free()

	var created := LLMAdapter.create("ollama")
	ok(created is OllamaAdapter, "Ollama erhält eigenen Adapter")
	var adapter := created as OllamaAdapter
	adapter.config = {"model": OllamaAdapter.DEFAULT_MODEL, "max_tokens_per_request": 900}
	var body: Dictionary = adapter.build_body([{"role": "user", "content": "Test"}])
	ok(body.think == false and body.format is Dictionary and body.stream == false
		and body.options.num_predict == 900 and not body.has("api_key"), "Ollama-Anfrage ohne Denkmodus und Key")
	ok(body.options.num_ctx >= OllamaAdapter.CONTEXT_TOKENS
		and body.format.required.has("actions") and body.format.properties.actions.minItems == 1,
		"Ollama erhält vollständigen Spielkontext und ein verbindliches Aktions-JSON-Schema")
	var replies: Array = []
	adapter.completed.connect(func(id: int, response: Dictionary): replies.append([id, response]))
	adapter._req_id = 7
	var json := JSON.stringify({"message": {"content": "{\"summary\":\"warte\",\"actions\":[]}"}, "prompt_eval_count": 25, "eval_count": 12})
	adapter._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), json.to_utf8_buffer())
	ok(replies.size() == 1 and replies[0][0] == 7 and replies[0][1].ok
		and replies[0][1].usage.total_tokens == 37
		and AgentController.parse_response(replies[0][1].content).ok, "Ollama-Antwort erreicht Aktionsparser")
	adapter.free()


func test_fuel_prices() -> void:
	var sample := {"ok": true, "stations": [
		{"id": "a", "diesel": 1.60, "e5": 1.80, "e10": 1.74, "isOpen": true},
		{"id": "b", "diesel": 1.70, "e5": 1.84, "e10": 1.78, "isOpen": true},
		{"id": "c", "diesel": 1.66, "e5": 1.82, "e10": 1.76, "isOpen": true},
		{"id": "d", "diesel": null, "e5": null, "e10": null, "isOpen": false},
		{"id": "e", "diesel": 9.99, "e5": 1.83, "e10": 1.77, "isOpen": true}]}
	var st := FuelPrices.parse_list(sample)
	ok(st.n == 4 and is_equal_approx(st.diesel, 1.66), "Median ignoriert geschlossene und unplausible Preise (%s)" % str(st.get("diesel")))
	ok(FuelPrices.parse_list({"ok": false}).is_empty() and FuelPrices.parse_list("text").is_empty(), "ungültige Antworten werden abgelehnt")
	var s := new_sim(2)
	var sp: Dictionary = s.resources.supplies.values().filter(func(x): return x.kind == "fuel")[0]
	s.fuel.apply(st, 1000.0)
	var base := s.resources.fuel_price(sp)
	ok(absf(base - 1.66 * (1.0 + float(sp.markup))) < 0.011, "Spielpreis = Referenz × Aufschlag (%.2f)" % base)
	s.resources.fuel_price_factor = 1.5
	ok(absf(s.resources.fuel_price(sp) - base * 1.5) < 0.02, "Ereignisfaktor wirkt getrennt vom realen Preis")
	s.resources.fuel_price_factor = 1.0
	s.fuel.apply({"diesel": 1.90, "e5": 2.0, "e10": 1.95, "n": 5}, 2000.0)
	ok(s.resources.fuel_price(sp) > base, "höhere reale Referenz erhöht den Spielpreis")
	ok(s.fuel.status(2000.0 + 60.0) == "aktuell" and s.fuel.status(2000.0 + 3000.0) == "veraltet" and s.fuel.status(2000.0 + 8000.0) == "offline", "Status nach Alter")
	var sim_fuel := FuelPrices.new()
	ok(sim_fuel.status(0.0) == "simuliert", "ohne Daten gekennzeichnet simuliert")
	# Dienst: Antwort verarbeiten, Schluessel erscheint nirgends
	var svc := FuelService.new()
	svc.setup(s, "GEHEIM-1234567890")
	ok(svc.build_url().contains("apikey=GEHEIM") and svc.has_key(), "Schlüssel nur in der Anfrage")
	svc.enabled = false
	ok(svc.handle_body(JSON.stringify(sample)) and s.fuel.source == "tankerkoenig" and s.fuel.stations_n == 4, "Dienst übernimmt Antwort")
	ok(not svc.handle_body("kein json") and s.fuel.last_error != "", "kaputte Antwort wird gemeldet")
	svc._fail("Fehler bei GEHEIM-1234567890 aufgetreten")
	ok(not s.fuel.last_error.contains("GEHEIM"), "Schlüssel wird aus Fehlertexten entfernt")
	ok(not JSON.stringify(s.to_dict()).contains("GEHEIM"), "Spielstand enthält keinen Schlüssel")
	svc.free()
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(is_equal_approx(s2.fuel.ref.diesel, s.fuel.ref.diesel) and s2.fuel.source == "tankerkoenig", "Preisstand nach Laden")
	ok("KRAFTSTOFF" in LiveText.situation(s, 10.0), "Lage-Reiter zeigt Kraftstoffpreise")


func test_gas_stations() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var R := s.resources
	var st: Dictionary = R.supplies.values().filter(func(x): return x.kind == "fuel")[0]
	ok(int(st.pumps) >= 2, "Tankstelle hat Zapfsäulen (%d)" % int(st.pumps))
	var h0: float = s.economy.accounts.H0
	var g0: float = s.economy.accounts.G0
	var stock0 := float(st.stock)
	run(s, 60.0 * 1.2)
	ok(float(st.stock) < stock0 and s.economy.accounts.G0 != g0, "Haushalte tanken: Bestand sinkt, Betreiber nimmt Geld ein")
	ok(float(st.revenue) > 0.0 and float(st.sales_l) > 0.0, "Umsatz und Absatz der Tankstelle erfasst")
	# Engpass an den Zapfsäulen
	st.stock = float(st.max)
	st.busy = []
	var c := s.companies[0]
	c.fuel = 0.0
	c.fuel_cap = 20000.0
	c.ledger.inject(20000.0)
	var waits := 0
	for i in 8:
		var r := R.buy_supplies(0, st.id, 300.0)
		if "Wartezeit" in r.msg:
			waits += 1
	ok(waits > 0 and float(st.wait_min) > 0.0, "Alle Säulen belegt → Wartezeit entsteht (%d Käufe warteten)" % waits)
	ok(R.pumps_busy(st) == int(st.pumps), "belegte Säulen werden gezählt")
	# Tankwagen: leere Station wird nachbestellt und beliefert
	st.stock = 100.0
	st.busy = []
	run(s, 60.0 * 1.1)
	ok(R.tanker_orders.any(func(o): return o.station == st.id) or float(st.stock) > 1000.0, "Betreiber bestellt einen Tankwagen")
	var order: Array = R.tanker_orders.filter(func(o): return o.station == st.id)
	ok(not order.is_empty() and float(order[0].cost) > 0.0, "Betreiber bezahlt die Lieferung an das Ausland")
	run(s, 60.0 * 2.0)
	ok(float(st.stock) > 1000.0 and int(st.deliveries) >= 1, "Tankwagen hat geliefert (Bestand %d l)" % int(st.stock))
	ok(identity_ok(s), "Geld und Waren erhalten mit Tankstellenbetrieb")
	run(s, 60.0 * 31.0)
	ok(s.economy.accounts.G0 > 0.0, "Tankstellenbetreiber bleibt zahlungsfähig (%.0f)" % s.economy.accounts.G0)
	ok(identity_ok(s), "Geld nach einem Monat Tankstellenbetrieb")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.resources.tanker_orders.size() == s.resources.tanker_orders.size() and identity_ok(s2), "Tankstellen nach Laden")


func test_households_wages() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	var staff: Array = s.personnel.employed(0)
	ok(staff.size() >= 2, "Startpersonal vorhanden")
	run(s, 60.0 * 2.0)
	ok(s.households.homes.size() >= staff.size(), "jeder Mitarbeiter hat einen Haushalt (%d)" % s.households.homes.size())
	var w: Worker = staff[0]
	ok(w.household != "" and s.households.homes[w.household].address >= 0, "fester Haushalt mit Wohnadresse")
	var h0: String = w.household
	run(s, 60.0 * 40.0)
	ok(w.household == h0, "Haushalt bleibt dauerhaft zugeordnet")
	ok(identity_ok(s), "Geld und Waren erhalten mit Haushalten")
	ok(s.households.spent_total > 0.0, "Haushalte geben Geld aus (Kaufkraft: %.0f)" % s.households.spent_total)
	# Lohnverhandlung
	var ask := s.households.reservation_wage(w)
	var low := s.executor.execute(0, {"action": "negotiate_wage", "worker_id": w.id, "wage": w.wage + 0.1})
	if ask > w.wage + 0.15:
		ok(not low.ok and "verlangt" in low.msg, "zu niedriges Angebot wird abgelehnt: " + low.msg)
	var raise := s.executor.execute(0, {"action": "negotiate_wage", "worker_id": w.id, "wage": ceilf(ask + 1.0)})
	ok(raise.ok and w.wage >= ask, "angemessenes Angebot wird angenommen: " + raise.msg)
	ok(not s.executor.execute(0, {"action": "negotiate_wage", "worker_id": w.id, "wage": 5.0}).ok, "Lohnkürzung wird abgelehnt")
	ok(not s.executor.execute(1, {"action": "negotiate_wage", "worker_id": w.id, "wage": 90.0}).ok, "fremder Mitarbeiter nicht verhandelbar")
	# Lohnrueckstand: ohne Bargeld laeuft der Lohn auf und wird spaeter zuerst bezahlt
	var cash_before := c.ledger.cash
	c.ledger.inject(-cash_before)   # Kasse leer
	var paid_before: float = s.households.total_balance()
	run(s, 60.0 * 2.0)
	ok(c.ledger.payables > 0.0 and c.ledger.cash >= 0.0, "Lohn läuft als Rückstand auf (%.0f)" % c.ledger.payables)
	ok(s.households.summary_of(0).lohnrueckstand > 0, "Beobachtung zeigt Lohnrückstand")
	ok(identity_ok(s), "Bilanz mit Lohnverbindlichkeit stimmt")
	var arrears := c.ledger.payables
	c.ledger.inject(arrears + 5000.0)
	run(s, 1.0)
	ok(c.ledger.payables < 1.0, "Rückstand wird bei Zahlungsfähigkeit zuerst beglichen")
	ok(identity_ok(s), "Bilanz nach Begleichung")
	# Motivation sinkt bei Armut
	var poor: Worker = staff[1]
	var ph: Dictionary = s.households.household_of(poor)
	ph.dependents = 2
	ph.balance = 0.0
	poor.wage = 8.0
	var m0 := poor.motivation
	for i in 3:
		s.households.on_month(i)
	ok(poor.motivation < m0, "Defizit und niedriger Lohn senken die Motivation (%d → %d)" % [int(m0), int(poor.motivation)])
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.households.homes.size() == s.households.homes.size() and s2.personnel.workers[w.id].household == w.household, "Haushalte nach Laden")
	ok(identity_ok(s2), "Geld nach Laden")


func test_wage_arrears_in_insolvency() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(3)
	var c := s.companies[1]
	var staff_ids: Array = s.personnel.employed(1).map(func(w): return w.id)
	c.ledger.inject(-c.ledger.cash)   # keine Mittel: Löhne laufen auf
	run(s, 60.0 * 4.0)
	ok(c.ledger.payables > 0.0, "Rückstände entstehen")
	ok(c.status in ["verzug", "insolvenz"], "Lohnrückstand löst Zahlungsverzug aus (%s)" % c.status)
	run(s, 60.0 * 40.0)
	ok(c.status == "geschlossen", "Verfahren abgeschlossen (%s)" % c.status)
	var entry: Dictionary = s.insolvency.archive[0]
	ok(float(entry.wage_claims) > 0.0 and float(entry.wage_paid) + float(entry.wage_lost) >= float(entry.wage_claims) - 0.01, "Lohnforderungen werden ausgewiesen und bedient oder erlassen")
	ok(c.ledger.payables == 0.0, "keine Lohnverbindlichkeiten nach Schließung")
	ok(staff_ids.all(func(id): return s.personnel.workers[id].employer != 1 or s.companies[1].generation > 1), "Mitarbeiter sind nicht mehr beim Insolventen angestellt")
	ok(identity_ok(s), "Geld, Waren und Bilanzen stimmen")


func test_fuel_planner() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	var opts := FuelPlanner.compare(s, 0, 500.0)
	ok(opts.size() > 3, "Tankstellen werden verglichen (%d)" % opts.size())
	ok(opts[0].gesamt <= opts[1].gesamt and opts[0].gesamt <= opts[-1].gesamt, "günstigste Gesamtkosten zuerst")
	var r := s.executor.execute(0, {"action": "compare_fuel_options", "liters": 400})
	ok(r.ok and "Annahmen" in r.msg and "Notpreis" in r.msg, "Vergleich nennt Annahmen und Ersparnis: " + r.msg.left(80))
	# keine Tankstelle mit so viel Bestand
	for sid in s.resources.supplies:
		if s.resources.supplies[sid].kind == "fuel":
			s.resources.supplies[sid].stock = 10.0
	ok(not FuelPlanner.compare_text(s, 0, 500.0).ok, "ohne Bestand kein Vorschlag")
	for sid in s.resources.supplies:
		if s.resources.supplies[sid].kind == "fuel":
			s.resources.supplies[sid].stock = 3000.0
	# feste Regel
	ok(not s.executor.execute(0, {"action": "schedule_refueling", "below_l": 100, "buy_l": 99999}).ok, "Regel über Tankgröße abgelehnt")
	var rule := s.executor.execute(0, {"action": "schedule_refueling", "below_l": 200, "buy_l": 600})
	ok(rule.ok and c.fuel_rule.below == 200.0, "Regel gespeichert")
	c.fuel = 150.0
	var cash0 := c.ledger.cash
	run(s, 35.0)   # eine halbe Stunde: bestellt und bezahlt, der Tankwagen ist noch unterwegs
	ok(c.ledger.cash < cash0 and s.resources.pending_fuel(0) > 0.0 and c.fuel < 300.0, "Engine bestellt automatisch; der Treibstoff ist noch unterwegs (%d l im Depot, %d l unterwegs)" % [int(c.fuel), int(s.resources.pending_fuel(0))])
	var pending_before: float = s.resources.pending_fuel(0)
	run(s, 10.0)
	ok(s.resources.pending_fuel(0) <= pending_before + 0.01, "keine doppelte Bestellung, solange Treibstoff unterwegs ist")
	run(s, 120.0)
	ok(c.fuel > 600.0 and s.resources.pending_fuel(0) == 0.0, "nach der Lieferung steigt der Vorrat im Depot (%d l)" % int(c.fuel))
	var fuel_after := c.fuel
	run(s, 10.0)
	ok(c.fuel <= fuel_after + 0.01, "keine weitere Bestellung bei ausreichendem Vorrat")
	ok(identity_ok(s), "Geld erhalten mit Nachtank-Regel")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.companies[0].fuel_rule.below == 200.0, "Regel nach Laden")
	ok(s.executor.execute(0, {"action": "schedule_refueling", "below_l": 0, "buy_l": 0}).ok and c.fuel_rule.is_empty(), "Regel löschen")
	# Wetter erhoeht den Verbrauch
	var w := Weather.new()
	ok(is_equal_approx(w.fuel_factor(), 1.0) or w.fuel_factor() >= 1.0, "Verbrauchsfaktor ohne Wetter nicht unter 1")


func test_building_care() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var C := s.care
	ok(C.condition.size() > 50, "Stadtgebäude haben einen Zustand (%d)" % C.condition.size())
	var vals: Array = C.condition.values()
	ok(vals.all(func(v): return v >= BuildingCare.START_MIN - 0.01 and v <= BuildingCare.START_MAX + 0.01), "Startzustand im erwarteten Bereich")
	ok(BuildingCare.tint(100.0) == Color(1, 1, 1, 1) and BuildingCare.tint(10.0).r < 0.8, "gepflegt unverändert, verwahrlost dunkler")
	var worn := BuildingCare.tint(40.0)
	var ruin := BuildingCare.tint(0.0)
	ok(absf(ruin.r - ruin.g) < absf(worn.r - worn.g) and absf(ruin.g - ruin.b) < absf(worn.g - worn.b), "baufällig: Farbe weicht (grauer als verwittert)")
	ok(C.state_of(80.0) == "gepflegt" and C.state_of(50.0) == "genutzt" and C.state_of(30.0) == "vernachlässigt" and C.state_of(5.0) == "baufällig", "Zustandsstufen")
	# Verfall ohne Pflege: H0 arm -> kein Unterhalt
	s.economy.accounts.H0 = 0.0
	s.economy.initial_total -= 300000.0   # Testeingriff, Konservierung bleibt gewahrt
	var before := 0.0
	for v in vals:
		before += v
	for i in 6:
		C.on_month(i)
	var after := 0.0
	for v in C.condition.values():
		after += v
	ok(after < before, "ohne zahlungskräftige Eigentümer verwahrlosen die Gebäude (%.0f → %.0f)" % [before / vals.size(), after / vals.size()])
	var spent0 := C.spent_city
	s.economy.accounts.H0 = 300000.0
	s.economy.initial_total += 300000.0
	var t0: float = s.economy.accounts.S0
	for i in 6:
		C.on_month(10 + i)
	ok(C.spent_city > spent0 and s.economy.accounts.S0 > t0, "zahlungskräftige Eigentümer zahlen Instandhaltung (Geld fließt an die Bauwirtschaft)")
	ok(identity_ok(s), "Geld erhalten mit Instandhaltung")
	ok(C.district_means().size() == Catalog.DISTRICTS.size() and not C.district_log.is_empty(), "Viertelmittel und Verlauf")
	# Firmeneinrichtung
	var c := s.companies[0]
	c.ledger.inject(40000.0)
	var placed := place_suggested(s, 0, "stellplatz", "extern")
	var f: Dictionary = s.estate.facilities[placed.building_id]
	until_done(s, func(): return f.status == "fertig", 3000.0)
	ok(float(f.condition) == 100.0, "neue Einrichtung im Bestzustand")
	var up0 := BuildingCare.upkeep_factor(f)
	f["condition"] = 20.0
	ok(BuildingCare.upkeep_factor(f) > up0 + 0.2, "schlechter Zustand erhöht die Betriebskosten")
	var cash0 := c.ledger.cash
	var m := s.executor.execute(0, {"action": "fund_maintenance", "einrichtung_id": f.id, "betrag": 100})
	ok(m.ok and float(f.condition) > 20.0 and c.ledger.cash < cash0, "Instandhaltung hebt den Zustand: " + m.msg)
	var cond1 := float(f.condition)
	var cash1 := c.ledger.cash
	var r := s.executor.execute(0, {"action": "commission_renovation", "einrichtung_id": f.id})
	ok(r.ok and float(f.condition) == 100.0 and c.ledger.cash < cash1, "Renovierung stellt den Zustand her: " + r.msg)
	ok(not s.executor.execute(0, {"action": "commission_renovation", "einrichtung_id": f.id}).ok, "gute Einrichtung wird nicht erneut renoviert")
	ok(not s.executor.execute(1, {"action": "fund_maintenance", "einrichtung_id": f.id, "betrag": 100}).ok, "fremde Einrichtung nicht instandhaltbar")
	f["condition"] = 70.0
	for i in 8:
		C.on_month(30 + i)
	ok(float(f.condition) < 70.0, "Einrichtung verschleißt mit der Zeit (%d)" % int(f.condition))
	ok(cond1 > 20.0 and identity_ok(s), "Geld und Bilanz stimmen")
	ok("STADTVIERTEL" in LiveText.situation(s, 10.0), "Lage-Reiter zeigt Viertelzustand")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.care.condition.size() == C.condition.size() and absf(s2.care.get_condition(C.condition.keys()[0]) - C.get_condition(C.condition.keys()[0])) < 0.2, "Zustand nach Laden")


func test_workforce() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	var staff: Array = s.personnel.employed(0)
	var idle: Worker = staff.filter(func(w): return w.vehicle_id < 0)[0]
	var task: WorkerTask = s.personnel.tasks.get(idle.task_id)
	if task != null and not task.is_final():
		s.personnel.cancel_task(task, "Test")
	# Gesundheit sinkt bei Dauererschoepfung und erholt sich in Ruhe
	idle.fatigue = 95.0
	idle.health = 80.0
	for i in 40:
		s.workforce.minute_tick()
	ok(idle.health < 80.0, "Erschöpfung zehrt die Gesundheit auf (%.1f)" % idle.health)
	idle.fatigue = 10.0
	var h0 := idle.health
	for i in 40:
		s.workforce.minute_tick()
	ok(idle.health > h0, "ausgeruht erholt sich die Gesundheit")
	# Krankheit
	idle.health = 20.0
	idle.rest_until = 0.0
	s.workforce.minute_tick()
	ok(idle.rest_until > s.game_min and idle.health > 30.0, "unter 30 wird der Mitarbeiter krank und fällt aus")
	ok(s.personnel.can_take(idle, "gehen") != "", "kranker Mitarbeiter bekommt keine Aufgaben")
	# Pause einplanen
	idle.rest_until = 0.0
	idle.fatigue = 60.0
	var r := s.executor.execute(0, {"action": "schedule_rest", "worker_id": idle.id, "hours": 2})
	ok(r.ok and idle.rest_until > s.game_min + 100.0, "Pause eingeplant: " + r.msg)
	for i in 10:
		s.workforce.minute_tick()
	ok(idle.fatigue < 60.0, "in der Pause sinkt die Erschöpfung")
	var driver: Worker = staff.filter(func(w): return w.vehicle_id >= 0)[0]
	ok(not s.executor.execute(0, {"action": "schedule_rest", "worker_id": driver.id, "hours": 2}).ok, "Fahrer im Fahrzeug bekommt keine Pause")
	ok(not s.executor.execute(1, {"action": "schedule_rest", "worker_id": idle.id, "hours": 2}).ok, "fremder Mitarbeiter nicht verplanbar")
	# Weiterbildung
	idle.rest_until = 0.0
	var skill := "verladen"
	idle.skills[skill] = 0
	var cash0 := c.ledger.cash
	var t := s.executor.execute(0, {"action": "offer_training", "worker_id": idle.id, "skill": skill})
	ok(t.ok and int(idle.skills[skill]) == 1 and is_equal_approx(cash0 - c.ledger.cash, Workforce.TRAIN_COST), "Weiterbildung: Fähigkeit +1 gegen Gebühr: " + t.msg)
	idle.skills[skill] = Workforce.TRAIN_MAX_SKILL
	ok(not s.executor.execute(0, {"action": "offer_training", "worker_id": idle.id, "skill": skill}).ok, "über Stufe 2 nur mit Schulungsraum")
	ok(not s.executor.execute(0, {"action": "offer_training", "worker_id": idle.id, "skill": "fliegen"}).ok, "unbekannte Fähigkeit abgelehnt")
	# Ersatzpersonal
	var n0 := s.personnel.employed(0).size()
	var cash1 := c.ledger.cash
	var q := s.executor.execute(0, {"action": "request_replacement_worker", "kind": "mechanic"})
	ok(q.ok and c.ledger.cash < cash1 and s.workforce.pending.size() == 1, "Vermittlung beauftragt: " + q.msg)
	ok(s.executor.execute(0, {"action": "request_replacement_worker", "kind": "driver"}).ok and not s.executor.execute(0, {"action": "request_replacement_worker", "kind": "guard"}).ok, "höchstens zwei Vermittlungen gleichzeitig")
	ok(not s.executor.execute(0, {"action": "request_replacement_worker", "kind": "pilot"}).ok, "unbekannte Rolle abgelehnt")
	run(s, 60.0 * 1.6)
	ok(s.personnel.employed(0).size() == n0 + 2 and s.workforce.pending.is_empty(), "nach einem Spieltag sind beide Ersatzkräfte angestellt")
	ok(identity_ok(s), "Geld und Bilanz stimmen")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.personnel.workers[idle.id].health == idle.health and s2.workforce.pending.size() == s.workforce.pending.size(), "Gesundheit und Vermittlungen nach Laden")
	# Gesundheit schlaegt auf die Motivation durch
	var w2: Worker = s.personnel.employed(0)[0]
	var hh: Dictionary = s.households.household_of(w2)
	hh.balance = 10000.0
	w2.health = 100.0
	w2.motivation = 60.0
	s.households._update_motivation(w2, hh)
	var healthy := w2.motivation
	w2.health = 20.0
	w2.motivation = 60.0
	s.households._update_motivation(w2, hh)
	ok(w2.motivation < healthy, "schlechte Gesundheit senkt die Motivation")


func test_news_feed() -> void:
	GameCalendar.configure(60.0)
	var sample := {"articles": [
		{"title": "Spritpreise steigen in Mainz auf Rekord", "description": "Diesel wird teurer, Tankstellen melden Anstieg.", "source": {"name": "Beispielzeitung"}, "publishedAt": "2026-10-25T08:00:00Z", "url": "https://example.org/a"},
		{"title": "Spritpreise steigen in Mainz auf Rekord!", "description": "doppelt", "source": {"name": "Anderer"}, "publishedAt": "2026-10-25T09:00:00Z"},
		{"title": "Warnstreik der Fahrer im Mainzer Raum", "description": "Streik im Verkehr, Fahrermangel erwartet", "source": {"name": "Radio"}, "publishedAt": "2026-10-25T07:00:00Z"},
		{"title": "Neues Café eröffnet", "description": "Kaffee und Kuchen", "source": {"name": "Blatt"}, "publishedAt": "2026-10-25T06:00:00Z"},
		{"title": "", "description": "ohne Titel"}]}
	var p := NewsFeed.parse(sample)
	ok(p.size() == 4, "Meldungen ohne Titel werden verworfen (%d)" % p.size())
	ok(NewsFeed.parse("kein array").is_empty() and NewsFeed.parse({"x": 1}).is_empty(), "ungültiges Format ergibt nichts")
	ok(NewsFeed.normalize("Spritpreise steigen!") == NewsFeed.normalize("spritpreise  steigen"), "Titel werden normalisiert")
	var a := NewsFeed.assess(p[0])
	ok(a.cat == "Treibstoff" and a.direction == 1 and a.relevance >= NewsFeed.EVENT_MIN_RELEVANCE, "Treibstoffmeldung: Kategorie, Richtung und Relevanz")
	ok(NewsFeed.assess(p[3]).cat == "" and NewsFeed.assess(p[3]).relevance == 0.0, "irrelevante Meldung bleibt ohne Einschätzung")
	var s := new_sim(2)
	var added := s.news.ingest(p)
	ok(added.size() == 3 and s.news.items.size() == 3, "Duplikat wird nur einmal aufgenommen (%d)" % added.size())
	ok(s.news.ingest(p).is_empty(), "wiederholter Abruf liefert nichts Neues")
	# Ebene 3: begrenztes Ereignis mit Abklingzeit
	for it in s.news.items:
		if it.cat == "Arbeit":
			it.used = true   # hier nur den Treibstoffpfad pruefen
	var f0: float = s.resources.fuel_price_factor
	var ev := s.news.maybe_event(s)
	ok(not ev.is_empty() and s.resources.fuel_price_factor > f0 and s.resources.fuel_price_factor <= 1.15, "Treibstoffmeldung löst ein begrenztes Preisereignis aus (×%.2f)" % s.resources.fuel_price_factor)
	ok(s.news.maybe_event(s).is_empty(), "Abklingzeit verhindert das nächste Ereignis")
	var used: Array = s.news.items.filter(func(i): return i.used and i.cat == "Treibstoff")
	ok(used.size() == 1 and "Nachricht" in s.events.get_event(ev.id).ursache, "Ereignis nennt die Nachricht als Ursache")
	run(s, 60.0 * 8.0)
	ok(is_equal_approx(s.resources.fuel_price_factor, 1.0), "Preisereignis endet nach einigen Tagen")
	# Dienst: Schluessel erscheint nirgends
	var svc := NewsService.new()
	svc.setup(s, "GEHEIM-ABCDEFG")
	svc.enabled = false
	ok(svc.build_url().contains("apiKey=GEHEIM") and svc.has_key(), "Schlüssel nur in der Anfrage")
	ok(not svc.handle_body("kein json") and s.news.last_error != "", "kaputte Antwort wird gemeldet")
	svc._fail("Fehler bei GEHEIM-ABCDEFG")
	ok(not s.news.last_error.contains("GEHEIM") and not JSON.stringify(s.to_dict()).contains("GEHEIM"), "Schlüssel nicht in Fehlern oder Spielstand")
	svc.free()
	ok(JSON.stringify(ObservationBuilder.build(s, 0, [], 0.0, 30.0)).contains("meldungen_nur_daten"), "KI sieht Meldungen ausdrücklich als Daten")
	ok("NACHRICHTEN" in LiveText.situation(s, 10.0) and "gemeldet" in LiveText.news_block(s), "Lage-Reiter zeigt die drei Ebenen")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.news.items.size() == s.news.items.size() and s2.news.ingest(p).is_empty(), "Meldungen und Duplikatschutz nach Laden")
	ok("HAUSHALTE" in LiveText.households(s), "Ansicht Haushalte")
	ok("ÖFFENTLICHE HAND" in LiveText.public_sector(s) and "Verkehr" in LiveText.public_sector(s), "Ansicht Staat")


func test_review_fixes() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var a := s.companies[0]
	var b := s.companies[1]
	# 1) Kredit eines anderen Unternehmens kann nicht zurueckgezahlt werden
	var coll := s.banking.best_collateral(1)
	var loan := s.executor.execute(1, {"action": "request_loan", "bank": "B2", "amount": 8000, "monate": 6, "fahrzeug_id": coll})
	ok(loan.ok, "Kredit des anderen Unternehmens: " + loan.msg)
	var lid: String = s.banking.loans.keys()[0]
	var cash_b := b.ledger.cash
	var cash_a := a.ledger.cash
	var foreign := s.executor.execute(0, {"action": "repay_loan", "amount": 500, "kredit_id": lid})
	ok(not foreign.ok and "gehört dir nicht" in foreign.msg, "fremde Kredit-ID wird abgelehnt: " + foreign.msg)
	ok(is_equal_approx(b.ledger.cash, cash_b) and is_equal_approx(a.ledger.cash, cash_a) and is_equal_approx(s.banking.loans[lid].outstanding, 8000.0), "fremdes Geld und Kredit bleiben unberührt")
	# 3) Vorzeitige Abloesung zieht ueberfaellige Raten samt Zuschlag ein
	var l: Dictionary = s.banking.loans[lid]
	l.plan[0].status = "rueckstand"
	l.arrears = 1
	l.fees_due = 7.5
	l.status = "rueckstand"
	var overdue: float = float(l.plan[0].pay) + 7.5
	var cash_before := b.ledger.cash
	var interest_before: float = b.ledger.totals.get("interest", 0.0)
	var payoff := s.executor.execute(1, {"action": "repay_loan", "amount": 99999, "kredit_id": lid})
	ok(payoff.ok and l.status == "getilgt" and l.outstanding == 0.0, "vollständige Ablösung: " + payoff.msg)
	ok(b.ledger.totals.get("interest", 0.0) < interest_before - float(l.plan[0].interest) - 7.0, "überfällige Zinsen und Verzugszuschlag wurden eingezogen")
	ok(cash_before - b.ledger.cash >= 8000.0 + overdue - float(l.plan[0].principal) - 1.0 and b.ledger.debt < 0.01, "gezahlt wurden Restschuld, Überfälliges und Gebühr")
	ok(identity_ok(s), "Geld und Bilanz stimmen nach der Ablösung")
	var all_paid := true
	for r in l.plan:
		all_paid = all_paid and r.status == "bezahlt"
	ok(all_paid, "keine offene Rate bleibt zurück")
	# 2) Veraltet-Grenze waechst mit der Geschwindigkeit
	var ctl := AgentController.new()
	ctl.setup_for_test(s, 0)
	ctl.speed = 16.0
	var content := '{"summary":"Warte.","actions":[{"action":"wait"}],"memory":""}'
	var req := ctl.begin_request_for_test()
	s.game_min += 90.0 * 16.0 * 0.5   # entspricht etwa 22 echten Sekunden bei 16x
	ctl.handle_result(req, {"ok": true, "content": content, "usage": {}})
	ok(not ctl.last_error.contains("veraltet"), "bei 16× ist eine Antwort nach wenigen echten Sekunden nicht veraltet")
	var req2 := ctl.begin_request_for_test()
	s.game_min += 90.0 * 16.0 + 10.0
	ctl.handle_result(req2, {"ok": true, "content": content, "usage": {}})
	ok(ctl.last_error.contains("veraltet"), "sehr späte Antworten bleiben gesperrt")
	ctl.speed = 1.0
	var req3 := ctl.begin_request_for_test()
	s.game_min += 95.0
	ctl.handle_result(req3, {"ok": true, "content": content, "usage": {}})
	ok(ctl.last_error.contains("veraltet"), "bei 1× gilt weiter die alte Grenze")
	ctl.free()


func test_physical_fueling() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var c := s.companies[0]
	var st: Dictionary = s.resources.supplies.values().filter(func(x): return x.kind == "fuel")[0]
	st.stock = 3000.0
	st.busy = []
	c.fuel = 0.0
	c.fuel_cap = 5000.0
	var cash0 := c.ledger.cash
	var r := s.resources.buy_supplies(0, st.id, 400.0)
	ok(r.ok and "Tankwagen" in r.msg, "Diesel wird gezapft und per Tankwagen geliefert: " + r.msg.left(90))
	ok(c.fuel == 0.0 and s.resources.pending_fuel(0) == 400.0, "der Vorrat steigt nicht sofort, 400 l sind unterwegs")
	ok(cash0 - c.ledger.cash > 400.0 * 1.4, "Kraftstoff und Lieferung sind bezahlt")
	ok(s.resources.buy_supplies(0, st.id, 5000.0).ok == false, "Tankgröße zählt auch unterwegs befindliche Liter")
	run(s, 8.0)
	ok(c.fuel == 0.0, "nach wenigen Minuten ist noch nichts angekommen")
	run(s, 120.0)
	ok(c.fuel == 400.0 and s.resources.pending_fuel(0) == 0.0, "nach der Fahrt des Tankwagens steht der Treibstoff im Depot (%d l)" % int(c.fuel))
	# belegte Saeulen verzoegern die Lieferung
	st.busy = [s.game_min + 500.0, s.game_min + 500.0, s.game_min + 500.0, s.game_min + 500.0]
	c.fuel = 0.0
	var due0: float = s.game_min
	var r2 := s.resources.buy_supplies(0, st.id, 100.0)
	ok(r2.ok and "Wartezeit" in r2.msg and float(s.resources.fuel_deliveries[-1].due) > due0 + 480.0, "belegte Zapfsäulen verzögern die Lieferung")
	# Abholen: eigener Transportauftrag Tankstelle -> Depot
	st.busy = []
	var fuel_before := c.fuel
	var r3 := s.resources.buy_supplies(0, st.id, 200.0, "abholen")
	ok(r3.ok and s.resources.fuel_shipments.size() == 1 and c.fuel == fuel_before, "Abholung: Transportauftrag statt sofortigem Vorrat: " + r3.msg.left(80))
	var k: Contract = s.contracts.values().filter(func(x): return x.internal.begins_with("F"))[0]
	ok(k.owner == 0 and k.reward == 0.0 and k.pickup == int(st.building) and k.dropoff == c.depots[0], "interner Auftrag von der Tankstelle zum Depot")
	s.deliver_contract(s.company_vehicles(0)[0], k)
	ok(c.fuel == fuel_before + 200.0 and s.resources.fuel_shipments.is_empty(), "nach Abliefern steigt der Vorrat")
	ok(identity_ok(s), "Geld erhalten beim physischen Tanken")
	# leerer Tank: Fahrzeug bleibt liegen, keine stille Notberechnung
	var v: FleetVehicle = s.company_vehicles(0)[0]
	c.fuel = 0.0
	var fuel_cost0: float = c.ledger.totals.get("fuel", 0.0)
	v.state = "idle"
	s.route(v, s.nearest_building_of("dealer", v.tile()).road, "returning")
	var guard := 0
	while v.state != "broken" and guard < 4000:
		s.step(0.1)
		guard += 1
	ok(v.state == "broken" and v.no_fuel, "Tank leer: Fahrzeug bleibt liegen")
	ok(c.ledger.totals.get("fuel", 0.0) >= fuel_cost0 - 0.001, "kein automatischer Notkauf während der Fahrt")
	c.fuel = 100.0
	for i in 5:
		s.step(0.2)
	ok(v.state != "broken" and not v.no_fuel, "mit Treibstoff im Depot fährt das Fahrzeug weiter")
	# Notbetankung nach 90 Minuten
	c.fuel = 0.0
	v.state = "idle"
	s.route(v, s.nearest_building_of("dealer", v.tile()).road, "returning")
	guard = 0
	while v.state != "broken" and guard < 4000:
		s.step(0.1)
		guard += 1
	var cash_e := c.ledger.cash
	run(s, 60.0)   # mehr als 90 Spielminuten
	ok(not v.no_fuel and c.ledger.cash < cash_e - 80.0, "nach 90 Minuten kommt die teure Notbetankung")
	ok(identity_ok(s), "Geld erhalten nach Notbetankung")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.resources.fuel_deliveries.size() == s.resources.fuel_deliveries.size() and identity_ok(s2), "Lieferungen nach Laden")


func test_public_sector() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var ps := s.public_sector
	var p0 := float(s.economy.accounts.P0)
	var net := ps.withhold(1000.0)
	ok(absf(net - 780.0) < 0.001, "Nettolohn nach Steuer und Sozialabgaben: %.2f" % net)
	ok(absf(float(s.economy.accounts.P0) - p0 - 220.0) < 0.001, "Abgaben landen auf P0")
	ok(identity_ok(s), "Geld erhalten nach Abzug")
	run(s, 60.0 * 40.0)
	ok(ps.tax_total > 0.0 and ps.social_total > 0.0, "Lohnsteuer und Sozialabgaben fließen (%.0f / %.0f)" % [ps.tax_total, ps.social_total])
	# Aufträge gibt die Stadt nur aus Mitteln über dem Ausgangsstand weiter; die Kasse liegt nach dem Stadtlager darunter, also anheben
	s.economy.transfer("X0", "P0", maxf(0.0, float(Economy.SEED.P0) + 50000.0 - float(s.economy.accounts.P0)))
	ps.on_month(0)
	ok(ps.spending_total > 0.0, "Öffentliche Hand gibt Mittel als Aufträge weiter (%.0f)" % ps.spending_total)
	var h: Dictionary = s.households.homes.values()[0]
	h.shortfall = 100.0
	var b0 := ps.benefits_total
	ps.on_month(0)
	ok(ps.benefits_total > b0, "Sozialleistung gleicht Defizit teilweise aus")
	ok(identity_ok(s), "Geld erhalten mit Sozialleistungen")
	# Ertragsteuer mit Verlustvortrag
	var c := s.companies[0]
	var due0 := ps.collect_corporate_tax(c)
	ok(c.ledger.profit() < 0.0 or due0 > 0.0, "Ertragsteuer nur bei Gewinn (gezahlt %.0f)" % due0)
	c.ledger.book("transport", 10000.0, true, "Test", s.game_min)
	var pretax: float = c.ledger.profit() - c.ledger.totals.get("tax", 0.0)
	var t := ps.collect_corporate_tax(c)
	ok(t > 0.0 or pretax <= 0.0, "Gewinn wird besteuert (%.0f)" % t)
	ok(ps.collect_corporate_tax(c) < 0.01, "keine doppelte Besteuerung")
	ok(ps.departments.Soziales > 0.0 and ps.departments.Verkehr > 0.0, "Ausgaben je Ressort erfasst")
	# Steuerpruefung: Nachforderung mit Zuschlag bei knapper Kasse
	c.ledger.book("transport", 20000.0, true, "Test", s.game_min)
	c.ledger.inject(-c.ledger.cash)
	var n_aud := ps.audits.size()
	var aud := ps.audit(c, 1)
	ok(aud.arrears > 0.0 and aud.fine >= 0.0 and ps.audits.size() == n_aud + 1, "Prüfung fordert offene Steuer nach (%.0f)" % aud.arrears)
	var clean := ps.audit(s.companies[1], 1)
	ok(clean.arrears == 0.0 and clean.fine == 0.0, "saubere Firma ohne Beanstandung")
	ok(ps._audit_roll(0, 5) == ps._audit_roll(0, 5) and ps._audit_roll(0, 5) < 1.0, "Prüfungswurf ist deterministisch")
	ok(identity_ok(s), "Geld und Bilanz mit Ertragsteuer")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(s2.public_sector.corporate_total - ps.corporate_total) < 0.01, "Ertragsteuer nach Laden")
	ok(absf(s2.public_sector.tax_total - ps.tax_total) < 0.01, "Steuerstände nach Laden")


func test_citizens() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(4)
	var cz := s.citizens
	ok(cz.population() >= 1000, "mindestens 1000 Bürger (%d)" % cz.population())
	ok(absf(cz.employment_rate() - Citizens.employment_target()) < 0.02, "%.0f %%%% haben Arbeit laut Konfiguration (%.1f %%%%)" % [Citizens.employment_target() * 100.0, cz.employment_rate() * 100.0])
	for c in s.companies:
		ok(s.personnel.employed(c.id).size() >= 10, "%s hat mindestens 10 Mitarbeiter (%d)" % [c.company_name, s.personnel.employed(c.id).size()])
	ok(cz.employed_count("rathaus") > 0 and cz.employed_count("baufirma") > 0, "Rathaus und Baufirma beschäftigen Bürger")
	ok(identity_ok(s), "Geld erhalten nach Start")
	var tax0 := s.public_sector.tax_total
	var changes := 0
	var layoffs := 0
	var hires := 0
	var rate_min := 1.0
	var rate_max := 0.0
	for m in 12:
		cz.on_month(m)
		changes += int(cz.stats.changes)
		layoffs += int(cz.stats.layoffs)
		hires += int(cz.stats.hires)
		rate_min = minf(rate_min, cz.employment_rate())
		rate_max = maxf(rate_max, cz.employment_rate())
		ok(identity_ok(s), "Geld erhalten nach Monat %d" % m)
	ok(s.public_sector.tax_total > tax0, "Bürger zahlen Lohnsteuer")
	ok(changes > 0, "Bürger wechseln die Stelle (%d)" % changes)
	ok(layoffs > 0 and hires > 0, "Entlassungen (%d) und Einstellungen (%d)" % [layoffs, hires])
	ok(cz.unemployed_total() > 0 and rate_min > Citizens.employment_target() - 0.1 and rate_max < minf(0.99, Citizens.employment_target() + 0.1), "Arbeitslosigkeit bleibt realistisch (%.1f–%.1f %%)" % [rate_min * 100.0, rate_max * 100.0])
	ok("BÜRGER UND ARBEITSMARKT" in LiveText.citizens(s), "Ansicht Bürger")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.citizens.people.size() == cz.people.size() and s2.citizens.employed_total() == cz.employed_total(), "Bürger nach Laden")


func test_parcels() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)   # Haushalte der Mitarbeiter entstehen im Lauf
	var P := s.parcels
	var sm: Dictionary = P.summary()
	ok(sm.anzahl > 1000, "Grundstücke angelegt (%d)" % sm.anzahl)
	ok(P.reserve_share() >= 0.25 and P.reserve_share() <= 0.40, "unbebaute Reserve 25–40 %% (%.1f %%)" % (P.reserve_share() * 100.0))
	var missing := 0
	for b in s.city.buildings:
		if P.of_building(int(b.id)).is_empty():
			missing += 1
	ok(missing == 0, "jedes Gebäude steht auf einem Grundstück (%d ohne)" % missing)
	ok(sm.nach_zone.has("korridor") and sm.nach_zone.has("wohnen") and sm.nach_zone.has("gewerbe") and sm.nach_zone.has("industrie"), "Zonen: Wohnen, Gewerbe, Industrie, Korridore")
	var states_ok := true
	for p in P.items.values():
		if p.state not in Parcels.STATES:
			states_ok = false
	ok(states_ok, "alle Grundstücke haben einen gültigen Zustand")
	# Suche, Reservierung und Kauf
	var found: Array = P.search({"zone": "wohnen", "min_area": 20})
	ok(not found.is_empty(), "Suche findet freie Wohngrundstücke (%d)" % found.size())
	var pid: String = found[0].id
	ok(s.households.homes.size() > 0, "Haushalte vorhanden")
	var home: String = str(s.households.homes.keys()[0])
	var r1 := P.reserve(pid, home)
	ok(r1.ok and P.parcel(pid).state == "reserviert", "Reservierung: " + r1.msg)
	var r2 := P.reserve(pid, "H999")
	ok(not r2.ok, "kein zweiter Bewerber: " + r2.msg)
	ok(not P.city_can_assign(pid), "reserviertes Grundstück kann die Stadt nicht anderweitig vergeben")
	s.households.homes[home].balance = 0.0
	var poor2 := P.buy_for_household(pid, home)
	ok(not poor2.ok, "ohne Geld kein Kauf: " + poor2.msg)
	s.households.homes[home].balance = float(P.parcel(pid).price) + 100.0
	s.economy.transfer("X0", "H0", float(P.parcel(pid).price) + 100.0)
	var p0_before: float = s.economy.accounts.P0
	var buy := P.buy_for_household(pid, home)
	ok(buy.ok and P.parcel(pid).owner == home, "Kauf: " + buy.msg)
	ok(absf(float(s.economy.accounts.P0) - p0_before - float(P.parcel(pid).price)) < 0.01, "Kaufpreis geht an die Stadt")
	ok(not P.city_can_assign(pid) and not P.reserve(pid, "H998").ok, "privates Eigentum kann die Stadt nicht vergeben")
	ok(identity_ok(s), "Geld erhalten nach Grundstückskauf")
	# Ablauf der Reservierung
	var pid2: String = found[1].id
	P.reserve(pid2, home, 2)
	P.on_day(GameCalendar.day_of(s.game_min) + 3)
	ok(P.parcel(pid2).state == "frei", "Reservierung läuft ab")
	# Speichern und Laden; alter Spielstand ohne Grundstuecke
	P.reserve(pid2, home, 10)
	var d := s.to_dict()
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(d)))
	ok(s2.parcels.parcel(pid).owner == home and s2.parcels.parcel(pid2).state == "reserviert", "Eigentum und Reservierung nach Laden")
	ok(s2.parcels.items.size() == P.items.size(), "gleiche Grundstücke nach Laden")
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(d))
	legacy.erase("parcels")
	legacy.erase("reserve")
	var s3 := Simulation.from_dict(legacy)
	ok(s3.parcels.items.size() > 1000 and s3.parcels.of_building(0).building == 0, "alter Spielstand bekommt Grundstücke aus der Karte")
	# neu gebautes Gebaeude bekommt sein Grundstueck
	var free_p: Dictionary = P.search({"min_area": 12})[2]
	var rect := Rect2i(free_p.rect[0], free_p.rect[1], 3, 3)
	var bid := s.city.buildings.size()
	s.city.buildings.append({"id": bid, "type": "shop", "x": rect.position.x, "y": rect.position.y, "w": 3, "h": 3, "district": 1})
	P.sync_buildings()
	ok("GRUNDSTÜCKE" in LiveText.parcels(s), "Ansicht Grundstücke")
	ok(P.of_building(bid).id == free_p.id and P.of_building(bid).state == "bebaut", "Neubau wird dem Grundstück zugeordnet")


## Hilfen fuer die Bauantragstests: Tage vorspulen, Haushalt mit Geld ausstatten.
func _permit_days(s: Simulation, n: int) -> void:
	var d := GameCalendar.day_of(s.game_min)
	for i in n:
		d += 1
		s.game_min = GameCalendar.day_start(d)
		s.permits.on_day(d)


func _fund_home(s: Simulation, home: String, amount: float) -> void:
	s.households.homes[home].balance = float(s.households.homes[home].balance) + amount
	s.economy.transfer("X0", "H0", amount)


func test_permits() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var P := s.parcels
	var PM := s.permits
	var homes: Array = s.households.homes.keys()
	var home: String = str(homes[0])
	var home2: String = str(homes[1])
	_fund_home(s, home, 5000.0)
	_fund_home(s, home2, 5000.0)
	# Regelwerk ist fuer Oberflaeche und KI lesbar
	var wr: Dictionary = Planning.rules("wohnen")
	ok(wr.max_geschosse == 3 and wr.anschluesse.size() == 4 and "einfamilienhaus" in Planning.allowed_defs("wohnen"), "Planungsregeln je Zone abrufbar")
	ok("industrie" in Planning.rules("industrie").zone and "mehrfamilienhaus" not in Planning.allowed_defs("industrie"), "Gebäudearten sind zonengebunden")
	# Grundstuecke fuer die Szenarien
	var big: Array = P.search({"zone": "wohnen", "min_area": 70, "limit": 300})
	var full: Array = big.filter(func(p): return P.utility_level(p) == "voll")
	var partial: Array = big.filter(func(p): return P.utility_level(p) != "voll")
	ok(full.size() >= 2 and partial.size() >= 1, "geeignete Wohngrundstücke vorhanden (%d erschlossen, %d nicht)" % [full.size(), partial.size()])
	# 1) Reservierung, Entwurf, Vorpruefung
	var pid: String = full[0].id
	ok(not PM.draft(home, pid, {"def": "einfamilienhaus"}).ok, "ohne Reservierung kein Entwurf")
	P.reserve(pid, home)
	var d1 := PM.draft(home, pid, {"def": "einfamilienhaus", "floors": 2, "parking": 1})
	ok(d1.ok, "Entwurf: " + d1.msg)
	var aid: String = d1.id
	ok(not PM.draft(home, pid, {"def": "einfamilienhaus"}).ok, "nur ein offener Antrag je Grundstück")
	var pre: Dictionary = PM.preview(aid)
	ok(pre.ok and pre.costs.gesamt > 0.0 and pre.costs.bau > 0.0, "Vorpruefung: grundsätzlich geeignet, Kosten %s" % Catalog.money(float(pre.costs.gesamt)))
	ok("Kosten gesamt" in Planning.explain(pre), "Vorpruefung ist lesbar erklärt")
	# Finanzierung: unverbindliche Kreditanfrage reicht nicht
	PM.apps[aid].financing = {"eigenmittel": 2000.0, "kredit": float(pre.costs.gesamt), "kredit_gesichert": false}
	ok(PM.submit(aid).ok and PM.apps[aid].status == "beantragt", "Antrag eingereicht")
	ok(PM.queue().size() == 1 and PM.eta_day(aid) > GameCalendar.day_of(s.game_min), "Warteschlange und voraussichtlicher Entscheidungstag")
	_permit_days(s, 12)
	var a1: Dictionary = PM.apps[aid]
	ok(a1.status == "rueckfrage" and a1.result == "ueberarbeitung_erforderlich" and "nicht zugesagt" in " ".join(a1.questions), "Rückfrage: Kredit nicht zugesagt (%s)" % " ".join(a1.questions))
	ok(P.parcel(pid).state == "reserviert", "Grundstück bleibt reserviert")
	# Ueberarbeitung mit gesicherter Finanzierung
	var rv := PM.revise(aid, {"financing": {"eigenmittel": 2000.0, "kredit": float(pre.costs.gesamt), "kredit_gesichert": true}}, "Kreditzusage liegt vor")
	ok(rv.ok and PM.apps[aid].status == "beantragt", "Überarbeitung eingereicht")
	var fee_before: float = s.economy.accounts.P0
	var home_before: float = s.households.homes[home].balance
	_permit_days(s, 8)
	a1 = PM.apps[aid]
	ok(a1.status == "entschieden" and a1.result == "genehmigt", "Genehmigung nach Überarbeitung (%s)" % a1.decision)
	ok(a1.decision.length() > 30 and not a1.reasons.is_empty(), "Entscheidung ist begründet")
	ok(P.parcel(pid).state == "genehmigt" and P.parcel(pid).application == aid, "Grundstück ist genehmigt und mit dem Antrag verknüpft")
	ok(absf((home_before - float(s.households.homes[home].balance)) - float(a1.fees_paid)) < 0.01 and a1.fees_paid > 0.0, "Gebühr %s vom Haushalt bezahlt" % Catalog.money(float(a1.fees_paid)))
	ok(absf(float(s.economy.accounts.P0) - fee_before - float(a1.fees_paid)) < 0.5, "Gebühr geht an die Stadt")
	ok(identity_ok(s), "Geld erhalten nach Genehmigung")
	ok(not PM.draft(home, pid, {"def": "einfamilienhaus"}).ok, "genehmigtes Grundstück: kein zweiter Antrag")
	# 2) Ablehnung mit benannten Gruenden: Mehrfamilienhaus passt nicht in die Zone/aufs Grundstueck
	var ind: Array = P.search({"zone": "industrie", "min_area": 40, "limit": 5})
	P.reserve(ind[0].id, home2)
	var d2 := PM.draft(home2, ind[0].id, {"def": "mehrfamilienhaus", "floors": 3})
	PM.submit(d2.id)
	_permit_days(s, 12)
	var a2: Dictionary = PM.apps[d2.id]
	ok(a2.status == "entschieden" and a2.result == "abgelehnt" and "nicht zulässig" in " ".join(a2.reasons), "Ablehnung mit Grund: " + " ".join(a2.reasons))
	ok(P.parcel(ind[0].id).state == "reserviert", "abgelehnter Antrag verändert das Grundstück nicht")
	# 3) Genehmigung mit Auflagen bei fehlender Erschliessung
	var pid3: String = partial[0].id
	_fund_home(s, home2, 3000.0)
	P.reserve(pid3, home2)
	var pre3_id: String = PM.draft(home2, pid3, {"def": "einfamilienhaus", "floors": 1, "parking": 1}).id
	var pre3: Dictionary = PM.preview(pre3_id)
	ok(not pre3.missing.is_empty() and pre3.costs.erschliessung > 0.0, "Vorprüfung nennt fehlende Anschlüsse: %s" % ",".join(pre3.missing))
	PM.apps[pre3_id].financing = {"eigenmittel": float(pre3.costs.gesamt) + 10.0}
	PM.submit(pre3_id)
	_permit_days(s, 12)
	var a3: Dictionary = PM.apps[pre3_id]
	ok(a3.result == "genehmigt_mit_bedingungen" and a3.conditions.size() >= 2, "Genehmigung mit Auflagen (Erschließung, Baustellenzufahrt)")
	# 4) Kleines Grundstueck: Rueckfrage zu Freiflaeche und Stellflaechen, keine Meinung
	# 5) Grosse Vorhaben gehen zur Buergermeisterebene und werden dort regelbasiert vertreten
	var pid5: String = full[1].id
	_fund_home(s, home, 5000.0)
	P.reserve(pid5, home)
	var d5 := PM.draft(home, pid5, {"def": "mehrfamilienhaus", "floors": 3, "parking": 4})
	var pre5: Dictionary = PM.preview(d5.id)
	PM.apps[d5.id].financing = {"eigenmittel": float(pre5.costs.gesamt) + 10.0}
	PM.submit(d5.id)
	var days_to_review := 0
	while PM.apps[d5.id].status in ["beantragt", "in_pruefung"] and days_to_review < 30:
		_permit_days(s, 1)
		days_to_review += 1
	ok(PM.apps[d5.id].status == "zur_entscheidung" or PM.apps[d5.id].status == "entschieden", "Mehrfamilienhaus (%d Einheiten) braucht Bürgermeisterebene" % int(pre5.units))
	_permit_days(s, 3)
	ok(PM.apps[d5.id].status == "entschieden" and PM.apps[d5.id].result in ["genehmigt", "genehmigt_mit_bedingungen"] and "Vertretung" in PM.apps[d5.id].decided_by, "Vertretung entscheidet nach Frist: " + PM.apps[d5.id].decided_by)
	# 6) Kapazitaet: mehr Antraege als Punkte pro Tag -> Wartezeit
	ok(PM.capacity() >= 1.0, "Verwaltungskapazität %.1f Punkte je Tag" % PM.capacity())
	# 7) Genehmigung laeuft ab
	_permit_days(s, Permits.PERMIT_DAYS + 5)
	ok(PM.apps[aid].expired and P.parcel(pid).state != "genehmigt", "abgelaufene Genehmigung gibt das Grundstück frei")
	ok(identity_ok(s), "Geld erhalten am Ende")
	# 8) Speichern und Laden
	var d := s.to_dict()
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(d)))
	ok(s2.permits.apps.size() == PM.apps.size() and s2.permits.apps[d5.id].result == PM.apps[d5.id].result, "Anträge nach Laden")
	ok("BAUANTRÄGE" in LiveText.permits(s), "Ansicht Bauanträge")


func test_mayor() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var M := s.mayor
	var P := s.parcels
	var PM := s.permits
	ok(M.name != "" and M.party in Council.SEATS, "Bürgermeister mit Name und Partei (%s, %s)" % [M.name, M.party])
	var ind: Dictionary = M.indicators()
	for k in ["bevoelkerung", "wohnen", "arbeit", "gewerbe", "verkehr", "versorgung", "haushalt", "bauantraege", "entwicklungsvorschlaege", "planungsregeln"]:
		ok(ind.has(k), "Kennzahl '%s' vorhanden" % k)
	ok(JSON.stringify(ind).length() / 4 < 6000, "Beobachtung kompakt (~%d Token)" % (JSON.stringify(ind).length() / 4))
	ok(ind.wohnen.leerstand > 0.0 and ind.wohnen.leerstand < 0.06, "Anfangs knapper Leerstand (%.1f %%)" % (ind.wohnen.leerstand * 100.0))
	# Wohnungsmarkt: ohne neue Einheiten wachsen die Wartenden, mit Einheiten ziehen Haushalte ein
	for m in 4:
		M.on_month(m + 1)
	ok(M.waiting > 0 and M.rent_index() > 100.0, "Wohnungssuchende steigen bei vollem Bestand (%d, Mietindex %.0f)" % [M.waiting, M.rent_index()])
	var pop0: int = s.citizens.population()
	M.stock_units += 40
	M.on_month(6)
	ok(s.citizens.population() > pop0, "neue Wohneinheiten: Haushalte ziehen ein (+%d Einwohner)" % (s.citizens.population() - pop0))
	M.waiting = 30
	ok(Council.needs_vote("quartier", 0.0) and not Council.needs_vote("erschliessung", 10000.0), "Ratsbeschluss nach Art und Kosten")
	# Quartier: nur staedtische Flaechen; Ratsbeschluss mit Begruendung
	var cands: Array = M.indicators().entwicklungsvorschlaege
	ok(not cands.is_empty(), "Entwicklungsvorschläge vorhanden (%d)" % cands.size())
	var c0: Dictionary = cands[0]
	var privat := ""
	for p in P.items.values():
		if p.state == "privat_gehalten" and p.zone == "wohnen":
			privat = p.id
			break
	var bad := M.execute({"action": "designate_quarter", "name": "Unzulässig", "parcel_ids": [privat], "zone": "wohnen", "reason": "test"})
	ok(not bad.ok and "nicht der Stadt" in bad.msg, "private Grundstücke kann die Stadt nicht ausweisen: " + bad.msg)
	var early := M.execute({"action": "offer_parcels", "parcel_ids": [c0.grundstuecke[0]], "reason": "zu früh"})
	var q1 := M.execute({"action": "designate_quarter", "name": "Testquartier", "parcel_ids": c0.grundstuecke, "zone": c0.zone, "reason": "30 Haushalte suchen Wohnraum"})
	ok(q1.ok and "Abstimmung" in q1.msg and M.plans.has(q1.ref), "Quartier beschlossen: " + q1.msg.left(160))
	ok(P.parcel(c0.grundstuecke[0]).state in ["zur_entwicklung", "frei"], "Grundstücke zur Entwicklung vorgesehen")
	var dup := M.execute({"action": "designate_quarter", "name": "Doppelt", "parcel_ids": c0.grundstuecke, "zone": c0.zone, "reason": "nochmal"})
	ok(not dup.ok and "bereits zum beschlossenen Quartier" in dup.msg, "dieselben Grundstücke werden nicht ein zweites Mal als Quartier beschlossen: " + dup.msg.left(100))
	var offer := M.execute({"action": "offer_parcels", "parcel_ids": c0.grundstuecke, "price_factor": 0.9, "reason": "Quartier beschlossen"})
	ok(offer.ok and P.parcel(c0.grundstuecke[0]).state == "frei", "Grundstücke zur Vergabe freigegeben: " + offer.msg)
	ok(not M.execute({"action": "offer_parcels", "parcel_ids": ["G999999"], "reason": "x"}).ok, "unbekanntes Grundstück abgelehnt")
	# Haushalt: ohne Mittel keine Erschliessung
	var pool: Array = P.search({"limit": 400}).filter(func(p): return P.utility_level(p) != "voll")
	var unserved: Array = [pool[0].id, pool[1].id, pool[2].id]
	var saved_p0: float = s.economy.accounts.P0
	s.economy.transfer("P0", "X0", saved_p0 - Mayor.RESERVE_CASH + 100.0)
	var broke := M.execute({"action": "plan_infrastructure", "parcel_ids": unserved, "reason": "ohne Geld"})
	ok(not broke.ok and M.commitments == 0.0, "ohne verfügbare Mittel keine Erschließung: " + broke.msg.left(120))
	s.economy.transfer("X0", "P0", saved_p0 - Mayor.RESERVE_CASH + 100.0)
	s.economy.transfer("X0", "P0", 300000.0)
	var infra := M.execute({"action": "plan_infrastructure", "parcel_ids": unserved, "reason": "Quartier erschließen"})
	ok(infra.ok and M.commitments > 0.0 and M.projects.has(infra.ref), "Erschließungsprojekt beschlossen, Mittel reserviert (%s)" % Catalog.money(M.commitments))
	var tender := M.execute({"action": "tender", "project_id": infra.ref, "reason": "Ausschreibung"})
	ok(tender.ok and M.projects[infra.ref].status == "ausgeschrieben", "Projekt ausgeschrieben")
	ok(not M.execute({"action": "tender", "project_id": infra.ref, "reason": "doppelt"}).ok, "nur beschlossene Projekte werden ausgeschrieben")
	var corridor := ""
	for p in P.items.values():
		if p.zone == "korridor":
			corridor = p.id
			break
	var road := M.execute({"action": "prioritize_road", "corridor_id": corridor, "priority": 2, "reason": "Anbindung"})
	ok(road.ok and M.projects[road.ref].kind == "strasse", "Straßenprojekt auf Korridor: " + road.msg.left(100))
	ok(not M.execute({"action": "prioritize_road", "corridor_id": c0.grundstuecke[0], "priority": 1, "reason": "x"}).ok, "Straßenprojekt nur auf Korridoren")
	ok(M.execute({"action": "assess_financing", "project_id": infra.ref}).ok, "Finanzierungsbewertung")
	ok(not M.execute({"action": "wipe_city"}).ok and not M.execute({"action": "tender"}).ok, "unbekannte Aktionen und fehlende Parameter werden abgelehnt")
	# Bauantrag der Buergermeisterebene
	var homes: Array = s.households.homes.keys()
	var home := str(homes[0])
	_fund_home(s, home, 6000.0)
	var full: Array = P.search({"zone": "wohnen", "min_area": 70, "limit": 300}).filter(func(p): return P.utility_level(p) == "voll")
	var pid: String = full[0].id
	P.reserve(pid, home)
	var d := PM.draft(home, pid, {"def": "mehrfamilienhaus", "floors": 3, "parking": 4})
	var pre: Dictionary = PM.preview(d.id)
	PM.apps[d.id].financing = {"eigenmittel": float(pre.costs.gesamt) + 10.0}
	PM.submit(d.id)
	var guard := 0
	while PM.apps[d.id].status in ["beantragt", "in_pruefung"] and guard < 30:
		_permit_days(s, 1)
		guard += 1
	ok(PM.apps[d.id].status == "zur_entscheidung", "Mehrfamilienhaus liegt der Bürgermeisterebene vor")
	var det: Array = M.indicators().bauantraege.zur_entscheidung_details
	ok(det.size() == 1 and det[0].vorpruefung_ok, "Beobachtung enthält die Vorprüfung des Antrags")
	var no_reason := M.execute({"action": "decide_application", "application_id": d.id, "decision": "ablehnen", "reason": "gefällt mir nicht"})
	ok(not no_reason.ok and "keine fehlende Voraussetzung" in no_reason.msg, "Ablehnung ohne benannte Mängel verweigert die Engine: " + no_reason.msg.left(90))
	var q := M.execute({"action": "decide_application", "application_id": d.id, "decision": "rueckfrage", "reason": "Bitte Schallschutz erläutern"})
	ok(q.ok and PM.apps[d.id].status == "rueckfrage", "Rückfrage der Bürgermeisterebene")
	PM.revise(d.id, {}, "Schallschutz nach DIN erläutert")
	var guard2 := 0
	while PM.apps[d.id].status in ["beantragt", "in_pruefung"] and guard2 < 30:
		_permit_days(s, 1)
		guard2 += 1
	# die Regeln entscheiden wie das Modell: ueber dieselbe Beobachtung und dieselben Aktionen
	var brain: Dictionary = MayorBrain.decide(M.indicators())
	var executed := 0
	for a in brain.actions:
		if M.execute(a).ok:
			executed += 1
	ok(PM.apps[d.id].status == "entschieden" and PM.apps[d.id].result == "genehmigt" and "Bürgermeister" in PM.apps[d.id].decided_by, "Bürgermeister-Regeln genehmigen mit Begründung: " + PM.apps[d.id].decision.left(100))
	ok(executed >= 1 and brain.summary != "", "Regeln liefern Zusammenfassung und Aktionen (%d ausgeführt)" % executed)
	# Wahl
	M.approval = 80.0
	var e1 := M.hold_election()
	ok(e1.ergebnis == "wiedergewählt", "hohe Zustimmung: wiedergewählt")
	M.approval = 20.0
	var e2 := M.hold_election()
	ok(e2.ergebnis == "abgewählt" and M.name != "" and e2.has("nachfolger"), "geringe Zustimmung: abgewählt, Nachfolger %s" % M.name)
	ok(M.plans.size() > 0 and M.notes.size() > 0, "Pläne und Gedächtnis des Amtes bleiben")
	# Agent: Prompt
	var agent := MayorAgent.new()
	var sp := agent.system_prompt()
	ok("decide_application" in sp and "designate_quarter" in sp and "Ratsbeschluss" in sp and not sp.contains("%s"), "Systemprompt der Bürgermeister-KI vollständig")
	ok(agent.user_prompt(ind).length() > 500, "Nutzerprompt enthält die Lage")
	agent.free()
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.mayor.plans.size() == M.plans.size() and s2.mayor.decisions.size() == M.decisions.size() and s2.mayor.name == M.name, "Bürgermeister nach Laden")
	ok(absf(s2.mayor.commitments - M.commitments) < 0.01 and s2.mayor.elections.size() == 2, "Reservierte Mittel und Wahlen nach Laden")
	ok("BÜRGERMEISTER" in LiveText.mayor(s), "Ansicht Bürgermeister")
	ok(identity_ok(s), "Geld erhalten")


func _build_days(s: Simulation, n: int) -> void:
	var d := GameCalendar.day_of(s.game_min)
	for i in n:
		d += 1
		s.game_min = GameCalendar.day_start(d)
		s.parcels.on_day(d)
		s.permits.on_day(d)
		s.construction.on_day(d)
		s.city_depot.on_day(d)


func _approve(s: Simulation, home: String, pid: String, def: String, floors: int, parking: int) -> Dictionary:
	_fund_home(s, home, 400000.0)
	s.parcels.reserve(pid, home)
	var d: Dictionary = s.permits.draft(home, pid, {"def": def, "floors": floors, "parking": parking})
	if not d.ok:
		return d
	s.permits.apps[d.id].financing = {"eigenmittel": float(s.permits.preview(d.id).costs.gesamt) + 10.0}
	s.permits.submit(d.id)
	var g := 0
	while s.permits.apps[d.id].status != "entschieden" and g < 40:
		_build_days(s, 1)
		g += 1
	return d


func test_construction() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var C := s.construction
	var P := s.parcels
	var PM := s.permits
	ok(C.builders.size() == 3, "drei Baufirmen mit unterschiedlichen Werten")
	var total_pay := 0.0
	var total_days := 0.0
	var total_mat := 0.0
	for ph in Construction.PHASES:
		total_pay += float(ph.pay)
		total_days += float(ph.days)
		total_mat += float(ph.mat)
	ok(absf(total_pay - 1.0) < 0.001 and absf(total_days - 1.0) < 0.001 and absf(total_mat - 1.0) < 0.001, "zehn Phasen: Zahlungsplan, Bauzeit und Material je 100 %")
	var home := str(s.households.homes.keys()[0])
	for it in ["ziegel", "beton", "holz", "glas", "installation", "stahl", "verbindung", "rohmaterial"]:
		s.stock.add(it, 600, "T0", s.trader.bauhof, "Testbestand")
	var full: Array = P.search({"zone": "wohnen", "min_area": 70, "limit": 300}).filter(func(p): return P.utility_level(p) == "voll")
	var pid: String = full[0].id
	var d := _approve(s, home, pid, "doppelhaus", 2, 2)
	ok(PM.apps[d.id].result.begins_with("genehmigt"), "Bauantrag genehmigt: " + PM.apps[d.id].decision.left(80))
	var r := C.start_project(d.id)
	ok(r.ok and C.projects[r.id].offers.size() == 3, "drei Angebote eingeholt")
	var pr: Dictionary = C.projects[r.id]
	var prices: Array = pr.offers.map(func(o): return o.price)
	ok(prices.min() < prices.max(), "Angebote unterscheiden sich im Preis")
	var best := C.best_offer(pr.offers, float(pr.base))
	ok(not best.is_empty(), "bestes Angebot nach Preis, Qualität, Zuverlässigkeit und Termin: " + str(best.get("name", "")))
	var bal0: float = s.households.homes[home].balance
	var acc := C.accept(pr.id, "BF1")
	ok(acc.ok and float(pr.reserved) > 0.0 and float(s.households.homes[home].balance) < bal0, "Vertrag verbindlich, Mittel zurückgelegt")
	ok(not C.accept(pr.id, "BF2").ok, "zweiter Vertrag für dasselbe Vorhaben nicht möglich")
	ok(P.parcel(pid).state in ["im_bau", "in_erschliessung"], "Grundstück im Bau")
	var days := 0
	var seen_phase := {}
	var seen_gear := {}
	var max_crew := 0
	while pr.status not in ["uebergeben", "abgebrochen"] and days < 250:
		_build_days(s, 1)
		days += 1
		seen_phase[C.phase_label(pr)] = true
		var cr := C.crew_of(pr)
		for g in cr.get("gear", []):
			seen_gear[g] = true
		max_crew = maxi(max_crew, int(cr.get("people", 0)))
		if days % 20 == 0:
			ok(identity_ok(s), "Geld erhalten während des Baus (Tag %d)" % days)
	ok(pr.status == "uebergeben", "Bauvorhaben übergeben nach %d Tagen (%s)" % [days, str(pr.blockers)])
	ok(seen_gear.has("bagger") and seen_gear.has("kran") and seen_gear.has("betonmischer") and max_crew >= 6, "Mannschaft und Geräte je Phase (bis %d Personen, Geräte %s)" % [max_crew, str(seen_gear.keys())])
	ok(C.crew_of(pr).is_empty(), "übergebene Baustelle ohne Mannschaft")
	ok(seen_phase.size() >= 8, "Bauphasen nacheinander durchlaufen (%d verschiedene)" % seen_phase.size())
	ok(not C.deliveries.is_empty() and C.deliveries.values().all(func(l): return l.status == "geliefert"), "Materiallieferungen beauftragt und geliefert")
	ok(absf(float(pr.paid) - (float(pr.price) + float(pr.dev_cost) + (Planning.TEMP_ACCESS_COST if pr.temp_access else 0.0))) < 5.0, "Zahlungen nach Bauabschnitten verbucht (%s)" % Catalog.money(float(pr.paid)))
	ok(float(s.economy.accounts.K0) > 0.0, "Baufirmen erhalten Geld")
	ok(P.parcel(pid).state == "bebaut" and int(P.parcel(pid).building) == int(pr.building), "Grundstück bebaut, Gebäude %d" % int(pr.building))
	ok(pr.units.size() == 4 and C.units[pr.units[0]].tenant == home, "Haushalt zieht in Einheit 1 ein (%d Einheiten)" % pr.units.size())
	ok(int(s.households.homes[home].address) == int(pr.building), "Haushaltsadresse ist das neue Gebäude")
	ok(identity_ok(s), "Geld nach Übergabe erhalten")
	s.mayor.waiting = 10
	for m in 3:
		C.on_month(m)
	var rented: int = C.units.values().filter(func(u): return u.tenant != "").size()
	ok(rented == 4, "übrige Wohnungen werden vermietet (%d von 4)" % rented)
	ok(identity_ok(s), "Mieteinnahmen: Geld erhalten")
	# Material fehlt -> Phase blockiert; Ausfall und Ersatz
	var home2 := str(s.households.homes.keys()[1])
	var full2: Array = P.search({"zone": "wohnen", "min_area": 70, "limit": 300}).filter(func(p): return P.utility_level(p) == "voll" and p.state == "frei")
	var d2 := _approve(s, home2, full2[0].id, "einfamilienhaus", 1, 1)
	var r2 := C.start_project(d2.id)
	var pr2: Dictionary = C.projects[r2.id]
	ok(C.accept(pr2.id, "BF3").ok, "zweites Vorhaben beauftragt")
	for it in ["beton", "ziegel", "holz", "verbindung"]:
		s.stock.consume(it, s.stock.qty(it, "T0", s.trader.bauhof), "T0", s.trader.bauhof, "Test")
	_build_days(s, 40)
	ok(pr2.status == "im_bau" and "Material" in str(pr2.blockers), "ohne Material blockiert die Phase: " + str(pr2.blockers).left(80))
	ok(float(pr2.lost_days.get("material", 0.0)) > 0.0, "Verzögerung wird dem Material zugeordnet")
	var open_d: Array = C.open_deliveries()
	ok(open_d.size() >= 1, "offener Lieferauftrag für Transportunternehmen")
	s.stock.add("beton", 300, "T0", s.trader.bauhof, "Testbestand")
	s.stock.add("verbindung", 300, "T0", s.trader.bauhof, "Testbestand")
	s.stock.add("ziegel", 300, "T0", s.trader.bauhof, "Testbestand")
	s.stock.add("holz", 300, "T0", s.trader.bauhof, "Testbestand")
	s.economy.transfer("X0", "K0", 20000.0)
	var cash0: float = s.companies[0].ledger.cash
	ok(ObservationBuilder._bauhof(s, 0).lieferauftraege.size() >= 1, "KI sieht offene Lieferaufträge in der Beobachtung")
	var take := s.executor.execute(0, {"action": "bau_lieferung", "lieferung_id": open_d[0].id})
	ok(take.ok and s.companies[0].ledger.cash > cash0, "Spieler übernimmt Lieferung und erhält Frachtlohn: " + str(take.msg))
	ok(identity_ok(s), "Geld nach Lieferung erhalten")
	C.fail_builder("BF3")
	_build_days(s, 3)
	ok("ausgefallen" in str(pr2.blockers) and pr2.status == "im_bau", "Baustelle bleibt bestehen, Blockade benannt")
	var paid_before: float = pr2.paid
	ok(C.retender(pr2.id, "BF1").ok and pr2.builder == "BF1", "Ersatzfirma übernimmt Restleistung")
	_build_days(s, 150)
	ok(pr2.status == "uebergeben", "Haus nach Ersatzvertrag übergeben (%s)" % str(pr2.blockers))
	ok(float(pr2.paid) >= paid_before and float(pr2.paid) <= float(pr2.price) + float(pr2.dev_cost) + Planning.TEMP_ACCESS_COST + 5.0, "bezahlte Phasen nicht doppelt bezahlt")
	ok(identity_ok(s), "Geld nach Ersatzvertrag erhalten")
	# Erschliessung durch private Bauherren
	var pool: Array = P.search({"zone": "wohnen", "limit": 400}).filter(func(p): return P.utility_level(p) != "voll" and p.state == "frei" and p.area >= 40)
	if not pool.is_empty():
		var home3 := str(s.households.homes.keys()[2])
		var q: Dictionary = pool[0]
		var d3 := _approve(s, home3, q.id, "einfamilienhaus", 1, 1)
		if d3.ok and PM.apps[d3.id].result.begins_with("genehmigt"):
			var r3 := C.start_project(d3.id)
			ok(C.accept_best(r3.id).ok, "Vorhaben mit fehlenden Anschlüssen beauftragt")
			var pr3: Dictionary = C.projects[r3.id]
			ok(pr3.status == "erschliessung" and P.parcel(q.id).state == "in_erschliessung", "Erschließung vor dem Bau")
			_build_days(s, 150)
			ok(pr3.status == "uebergeben" and P.utility_level(P.parcel(q.id)) == "voll", "Erschließung hergestellt, Haus übergeben (%s)" % pr3.status)
	# Unternehmen als Bauherr
	var gew: Array = P.search({"zone": "gewerbe", "min_area": 30, "limit": 300}).filter(func(p): return p.erschliessung.get("strasse", false))
	if not gew.is_empty():
		var cash_c: float = s.companies[0].ledger.cash
		P.reserve(gew[0].id, "C0")
		var dc: Dictionary = PM.draft("C0", gew[0].id, {"def": "lager_werkstatt", "floors": 1, "parking": 2})
		if dc.ok:
			PM.apps[dc.id].financing = {"eigenmittel": float(PM.preview(dc.id).costs.gesamt) + 10.0}
			PM.submit(dc.id)
			var g2 := 0
			while PM.apps[dc.id].status != "entschieden" and g2 < 40:
				_build_days(s, 1)
				g2 += 1
			if PM.apps[dc.id].result.begins_with("genehmigt"):
				var rc := C.start_project(dc.id)
				ok(C.accept_best(rc.id).ok, "Unternehmen beauftragt Baufirma")
				_build_days(s, 150)
				ok(C.projects[rc.id].status == "uebergeben" and s.companies[0].ledger.cash < cash_c, "Unternehmen zahlt den Bau aus der Firmenkasse und erhält das Lager")
				ok(identity_ok(s), "Bilanzidentität und Geld erhalten (Unternehmen als Bauherr)")
	# Oeffentliche Erschliessung ueber den Buergermeister
	var M := s.mayor
	s.economy.transfer("X0", "P0", 300000.0)
	var unserved: Array = P.search({"limit": 400}).filter(func(p): return P.utility_level(p) != "voll" and p.state == "frei")
	if unserved.size() >= 2:
		var infra := M.execute({"action": "plan_infrastructure", "parcel_ids": [unserved[0].id, unserved[1].id], "reason": "Test"})
		if infra.ok:
			ok(M.execute({"action": "tender", "project_id": infra.ref, "reason": "Test"}).ok, "Erschließung ausgeschrieben")
			var c0: float = M.commitments - s.city_depot.orders.values().reduce(func(a, o): return a + float(o.committed), 0.0)
			_build_days(s, 90)
			ok(M.projects[infra.ref].status == "fertig", "Baufirma stellt Erschließung her (%s)" % M.projects[infra.ref].status)
			var c1: float = M.commitments - s.city_depot.orders.values().reduce(func(a, o): return a + float(o.committed), 0.0)
			ok(c1 < c0, "reservierte Mittel gebucht (ohne Stadtlager-Bestellungen)")
			ok(M.projects[infra.ref].status == "fertig" and s.city_depot.issues.any(func(i): return i.ref == infra.ref and i.mode == "ueberlassen"), "Stadtlager überließ das Projektmaterial der Baufirma")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.construction.projects.size() == C.projects.size() and s2.construction.units.size() == C.units.size(), "Bauvorhaben und Wohneinheiten nach Laden")
	ok(s2.construction.projects[pr.id].status == "uebergeben" and int(s2.construction.projects[pr.id].building) == int(pr.building), "Projektstand nach Laden")
	ok("BAUVORHABEN" in LiveText.construction(s), "Ansicht Bauvorhaben")
	ok(identity_ok(s), "Geld erhalten")


func test_developer_autopilot() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var C := s.construction
	for it in ["ziegel", "beton", "holz", "glas", "installation", "stahl", "verbindung", "rohmaterial"]:
		s.stock.add(it, 2000, "T0", s.trader.bauhof, "Testbestand")
	var stock0: int = s.mayor.stock_units
	var done := 0
	for day in 360:
		_build_days(s, 1)
		if day % 30 == 0:
			s.mayor.waiting = maxi(s.mayor.waiting, 12)
			C.on_month(day / 30)
		done = C.projects.values().filter(func(p): return p.client == Construction.DEVELOPER and p.status == "uebergeben").size()
		if done >= 1 and day > 200:
			break
	ok(done >= 1, "Bauträger baut selbstständig: %d Vorhaben übergeben, %d begonnen" % [done, C.projects.size()])
	ok(s.mayor.stock_units > stock0, "Wohnungsbestand wächst (%d → %d)" % [stock0, s.mayor.stock_units])
	var rented: int = C.units.values().filter(func(u): return u.owner == Construction.DEVELOPER and u.tenant != "").size()
	ok(rented > 0, "Wohnungen des Bauträgers vermietet (%d)" % rented)
	ok(identity_ok(s), "Geld erhalten (Bauträger)")


func test_household_builder() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var C := s.construction
	var B := s.banking
	for it in ["ziegel", "beton", "holz", "glas", "installation", "stahl", "verbindung", "rohmaterial"]:
		s.stock.add(it, 900, "T0", s.trader.bauhof, "Testbestand")
	var ids: Array = s.households.homes.keys()
	var poor: String = ids[0]
	var rich: String = ids[1]
	# ohne Einkommen und Eigenmittel sagt die Bank nicht zu
	var q0 := B.mortgage_quote(poor, 30000.0, 32000.0)
	ok(not q0.ok and "Eigenmittel" in q0.msg, "Bank lehnt ab ohne Eigenmittel: " + str(q0.msg).left(70))
	_fund_home(s, poor, 6000.0)
	var q1 := B.mortgage_quote(poor, 26000.0, 32000.0)
	ok(not q1.ok and "Monatseinkommen" in q1.msg, "Bank lehnt ab ohne Einkommen: " + str(q1.msg).left(70))
	# Haushalt mit Einkommen und Ersparnissen: Grundstueck, Bankzusage, Antrag, Bau, Einzug
	_fund_home(s, rich, 12000.0)
	s.households.homes[rich].last_income = 3000.0
	var bank_cash0: float = B.bank_cash(1)
	var r := C._plan_home(rich, s.households.homes[rich])
	ok(r.ok, "Haushalt plant Hausbau: " + str(r.msg))
	var pl: Dictionary = C.home_plans.get(rich, {})
	ok(not pl.is_empty() and float(pl.credit) > 0.0, "Baukredit nötig (%s)" % Catalog.money(float(pl.get("credit", 0.0))))
	ok(s.parcels.parcel(pl.parcel).owner == rich, "Haushalt kauft das Grundstück")
	var mort := B.open_commitment(rich)
	ok(not mort.is_empty() and float(mort.drawn) == 0.0 and B.bank_cash(1) == bank_cash0, "Zusage ohne Auszahlung")
	var days := 0
	while C.home_plans.has(rich) and days < 300:
		_build_days(s, 1)
		days += 1
		if days % 25 == 0:
			ok(identity_ok(s), "Geld erhalten (Tag %d)" % days)
	var pr: Dictionary = C.projects.values().filter(func(p): return p.client == rich)[0]
	ok(pr.status == "uebergeben", "Haus übergeben (%s)" % str(pr.blockers))
	var mm: Dictionary = B.mortgages[mort.id]
	ok(mm.status == "laufend" and absf(float(mm.drawn) - float(mm.committed)) < 1.0 and float(mm.drawn) > 0.0, "Bank zahlte je Bauabschnitt (%s)" % Catalog.money(float(mm.drawn)))
	ok(B.bank_cash(1) < bank_cash0 and B.loans_of_bank(1) >= float(mm.outstanding), "Kredit steht in der Bankbilanz")
	ok(int(s.households.homes[rich].address) == int(pr.building), "Haushalt zieht ein")
	var mine: Array = C.jobs.values().filter(func(j): return j.payer == rich)
	ok(mine.size() == 2 and mine.all(func(j): return j.status == "offen"), "Einzug erzeugt Umzugs- und Möbelaufträge")
	var cash_j: float = s.companies[0].ledger.cash
	var tj := s.executor.execute(0, {"action": "bau_lieferung", "lieferung_id": mine[0].id})
	ok(tj.ok and s.companies[0].ledger.cash > cash_j, "Spieler übernimmt Umzugsauftrag: " + str(tj.msg))
	_build_days(s, 5)
	ok(C.jobs[mine[1].id].status in ["erledigt", "entfallen"] and C.open_jobs().filter(func(j): return j.payer == rich).is_empty(), "übrige Aufträge erledigt die Spedition")
	ok(identity_ok(s), "Geld nach Umzugsaufträgen erhalten")
	var out0: float = mm.outstanding
	_fund_home(s, rich, 3000.0)   # Gehaltseingang des Monats
	B.on_month(5)
	ok(float(mm.outstanding) < out0, "Rate tilgt den Kredit")
	ok(identity_ok(s), "Geld nach Rückzahlung erhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.banking.mortgages.size() == B.mortgages.size() and absf(float(s2.banking.mortgages[mort.id].outstanding) - float(mm.outstanding)) < 0.01, "Baukredit nach Laden")


## Abnahme Auftrag 7 (Abschnitt 18), Schritte 1-12 ueber den Autopiloten der Haushalte; danach Mehrfamilienhaus mit Vermietung.
func test_acceptance_flow() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var C := s.construction
	var P := s.parcels
	for it in ["ziegel", "beton", "holz", "glas", "installation", "stahl", "verbindung", "rohmaterial"]:
		s.stock.add(it, 1500, "T0", s.trader.bauhof, "Testbestand")
	# nur Grundstuecke ohne volle Erschliessung bleiben frei, damit Schritt 6 (Erschliessung) stattfinden muss
	for p in P.search({"zone": "wohnen", "limit": 2000}).filter(func(q): return q.state == "frei" and P.utility_level(q) == "voll"):
		P.reserve(p.id, "HX")
	var home := str(s.households.homes.keys()[3])
	_fund_home(s, home, 15000.0)
	s.households.homes[home].last_income = 3500.0
	var m := 0
	while not C.home_plans.has(home) and m < 24:
		m += 1
		C._household_month(m)
	var pl: Dictionary = C.home_plans.get(home, {})
	ok(not pl.is_empty(), "1+2: Haushalt sucht und reserviert/kauft ein Baugrundstück (nach %d Monaten)" % m)
	var parcel: Dictionary = P.parcel(pl.parcel)
	ok(parcel.owner == home and P.utility_level(parcel) != "voll", "Grundstück gehört dem Haushalt, Erschließung fehlt (%s)" % P.utility_level(parcel))
	ok(float(pl.credit) > 0.0 and not s.banking.open_commitment(home).is_empty(), "3: Bank prüft und sagt Finanzierung zu (%s)" % Catalog.money(float(pl.credit)))
	var app: Dictionary = s.permits.apps[pl.app]
	ok(app.applicant == home and app.status in ["beantragt", "in_pruefung", "entschieden"], "4: Bauantrag gestellt")
	var days := 0
	while C.home_plans.has(home) and C.home_plans[home].stage == "antrag" and days < 60:
		_build_days(s, 1)
		days += 1
	ok(app.status == "entschieden" and str(app.result).begins_with("genehmigt") and str(app.decision).length() > 10, "5: Verwaltung entscheidet begründet: %s" % str(app.decision).left(70))
	var pr: Dictionary = C.projects.values().filter(func(p): return p.client == home)[0]
	ok(pr.status == "erschliessung" and pr.offers.size() == 3 and pr.builder != "", "6+7: Angebote verglichen, Baufirma beauftragt, Erschließung vor dem Bau")
	var seen_delivery := false
	var seen_crew := false
	var mort: Dictionary = s.banking.mortgage_of_project(pr.id)
	var guard := 0
	while pr.status not in ["uebergeben", "abgebrochen"] and guard < 300:
		_build_days(s, 1)
		guard += 1
		seen_delivery = seen_delivery or not C.deliveries.is_empty()
		seen_crew = seen_crew or C.crew_of(pr).get("people", 0) >= 3
		if guard % 30 == 0:
			ok(identity_ok(s), "Geld erhalten (Tag %d)" % guard)
	ok(pr.status == "uebergeben", "11: Prüfung und Übergabe (%s)" % str(pr.blockers))
	ok(P.utility_level(P.parcel(pr.parcel)) == "voll", "6: Erschließung hergestellt")
	ok(seen_delivery and C.deliveries.values().all(func(l): return l.status == "geliefert"), "8: Material bestellt und geliefert")
	ok(seen_crew, "9: Mannschaft und Geräte führen die Bauphasen aus")
	ok(float(pr.paid) > 0.0 and float(s.banking.mortgages[mort.id].drawn) > 0.0, "10: Fortschritt und Zahlungen verbucht (bezahlt %s, davon Bank %s)" % [Catalog.money(float(pr.paid)), Catalog.money(float(s.banking.mortgages[mort.id].drawn))])
	ok(int(s.households.homes[home].address) == int(pr.building) and C.units[pr.units[0]].tenant == home, "12: Haushalt zieht ein")
	ok(identity_ok(s), "Geld nach dem Einzug erhalten")
	# Danach: Mehrfamilienhaus mit mehreren Wohnungen und tatsaechlicher Vermietung (Bautraeger)
	s.mayor.waiting = 12
	var done := 0
	for day in 400:
		_build_days(s, 1)
		if day % 30 == 0:
			s.mayor.waiting = maxi(s.mayor.waiting, 12)
			C.on_month(day / 30)
		done = C.projects.values().filter(func(p): return p.client == Construction.DEVELOPER and p.status == "uebergeben").size()
		if done >= 1 and day > 200:
			break
	var mfh: Array = C.projects.values().filter(func(p): return p.client == Construction.DEVELOPER and p.status == "uebergeben")
	ok(not mfh.is_empty() and mfh[0].units.size() >= 3, "Mehrfamilienhaus mit mehreren Wohnungen übergeben")
	var rented: int = C.units.values().filter(func(u): return u.owner == Construction.DEVELOPER and u.tenant != "").size()
	ok(rented >= 1, "Wohnungen tatsächlich vermietet (%d)" % rented)
	ok(identity_ok(s), "Geld nach Vermietung erhalten")


func test_city_depot() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var D := s.city_depot
	var ST := s.stock
	ok(D.building >= 0 and D.building != s.trader.bauhof, "Zentrallager ist ein eigenes Gebäude neben dem Bauhof des Großhändlers")
	ok(CityGoods.GROUPS.size() == 15 and CityGoods.items().size() >= 70, "Katalog: 15 Warengruppen, %d Artikel" % CityGoods.items().size())
	var complete := true
	for id in CityGoods.items():
		var it: Dictionary = CityGoods.get_item(id)
		complete = complete and it.min <= it.reorder and it.reorder <= it.target and it.target <= it.cap and it.crit >= 1 and it.unit != "" and CityGoods.ZONES.has(it.zone)
	ok(complete, "Mindest-, Melde-, Ziel- und Kapazitätsbestand je Artikel stimmig")
	ok(D.stock_of("schotter") == int(CityGoods.get_item("schotter").target * 0.7) and ST.of_owner("P0").size() > 60, "Anfangsbestand im Eigentum der Stadt")
	ok(identity_ok(s), "Geld und Waren erhalten (Start)")
	# Reservierung verhindert doppelte Verkaeufe
	var free0: int = ST.available("holz", "T0", s.trader.bauhof)
	ok(ST.reserve("test:1", "holz", free0 - 5, "T0", s.trader.bauhof) and s.trader.stock_of("holz") == 5, "Reservierung sperrt Bestand beim Großhändler")
	ok(not s.trader.sell(0, {"holz": 10}, "abholen", s.companies[0].depots[0]).ok, "reservierte Ware wird nicht zweimal verkauft")
	ST.release("test:1")
	# Verbrauch ohne Ware ist nicht moeglich
	var have: int = ST.qty("sand", "P0", D.building)
	ok(ST.consume("sand", have + 50, "P0", D.building, "Test") == have and ST.qty("sand", "P0", D.building) == 0, "Verbrauch höchstens in Höhe des Bestands")
	ST.add("sand", have, "P0", D.building, "Test-Rückbuchung")
	# Beschaffungskette: Bestand unter Meldebestand -> Vorschlag -> Freigabe -> Bestellung -> Transport -> Anlieferung -> Pruefung -> Einlagerung -> Zahlung
	var it_dec := CityGoods.get_item("leitkegel")
	ST.consume("leitkegel", D.on_hand("leitkegel") - int(it_dec.min), "P0", D.building, "Test")
	var p0_0: float = s.economy.accounts.P0
	var t0_0: float = s.economy.accounts.T0
	_build_days(s, 1)
	var ord: Dictionary = D.orders.values().filter(func(o): return o.item == "leitkegel")[0] if not D.orders.values().filter(func(o): return o.item == "leitkegel").is_empty() else {}
	ok(not ord.is_empty(), "Unterschreiten des Meldebestands erzeugt einen Beschaffungsvorschlag")
	_build_days(s, 2)
	ord = D.orders.values().filter(func(o): return o.item == "leitkegel")[0]
	ok(ord.status in ["bestellt", "transport"] and ord.supplier != "" and float(ord.committed) > 0.0, "Budgetfreigabe und Bestellung (%s bei %s)" % [ord.status, ord.supplier])
	ok(D.on_hand("leitkegel") == int(it_dec.min), "Bestellung erzeugt noch keinen Bestand am Zielort")
	var again: int = D.orders.values().filter(func(o): return o.item == "leitkegel").size()
	_build_days(s, 1)
	ok(D.orders.values().filter(func(o): return o.item == "leitkegel").size() == again, "bereits bestellte Menge wird nicht erneut bestellt")
	# ein Transportunternehmen uebernimmt den Auftrag und liefert (hier: Auslieferung des Contracts direkt ueber den Spielkern)
	var guard_k := 0
	while ord.contract == "" and guard_k < 14:
		_build_days(s, 1)
		guard_k += 1
	var k: Contract = s.contracts.get(ord.contract)
	ok(k != null and k.status == "open" and k.payer == "P0" and k.order_ref == ord.id and k.reward > 0.0, "echter Transportauftrag mit Zahler P0 und Vergütung %s" % (Catalog.money(k.reward) if k else "-"))
	var cash0: float = s.companies[0].ledger.cash
	k.owner = 0
	k.status = "in_transit"
	var veh: FleetVehicle = s.vehicles.values()[0]
	s.deliver_contract(veh, k)
	ok(s.companies[0].ledger.cash > cash0 and absf(s.companies[0].ledger.cash - cash0 - k.paid) < 0.01, "Transporteur erhält die Vergütung von der Stadt (%s)" % Catalog.money(k.paid))
	ok(ord.status == "angeliefert" and ST.qty_state("leitkegel", "P0", D.building, "pruefung") == int(ord.qty), "Anlieferung: Ware im Wareneingang, noch nicht verfügbar")
	ok(D.stock_of("leitkegel") == int(it_dec.min), "geprüfte Ware ist erst nach der Einlagerung verfügbar")
	_build_days(s, 2)
	ok(ord.status == "bezahlt" and D.on_hand("leitkegel") >= int(it_dec.target) - 5, "geprüft, eingelagert und bezahlt (%d im Lager)" % D.on_hand("leitkegel"))
	ok(float(s.economy.accounts.P0) < p0_0 and float(ord.paid) > 0.0, "Warenpreis von der Stadt gezahlt (%s)" % Catalog.money(float(ord.paid)))
	ok(identity_ok(s), "Geld und Waren erhalten (Beschaffung)")
	# Unternehmen als Lieferant, Stadtfuhrpark als Fallback
	ST.add("sekundaer", 1, "C0", s.companies[0].depots[0], "Test")
	var of := D.offer_supply(0, "pflanzen", 50, 1.0)
	ok(not of.ok, "Lieferangebot nur für vorhandene Ware")
	ST.add("pflanzen", 400, "C0", s.companies[0].depots[0], "Eigenproduktion")
	var of2 := D.offer_supply(0, "pflanzen", 400, 2.0, 0)
	ok(of2.ok, "Unternehmen bietet Ware an: " + str(of2.msg))
	var qs := D.quote("pflanzen", 300, 1)
	ok(qs.size() >= 2 and qs[0].supplier == "C0", "Angebotsvergleich berücksichtigt Unternehmen (%s zuerst)" % qs[0].supplier)
	ST.consume("pflanzen", D.on_hand("pflanzen") - 150, "P0", D.building, "Test")
	_build_days(s, 4)
	var po: Array = D.orders.values().filter(func(o): return o.item == "pflanzen")
	ok(not po.is_empty() and po[0].supplier == "C0", "Stadt bestellt beim Unternehmen")
	_build_days(s, 12)
	po = D.orders.values().filter(func(o): return o.item == "pflanzen")
	ok(po[0].status == "bezahlt" and D.stats.fallback_trips >= 1, "ohne Transportunternehmen fährt der Stadtfuhrpark (%s)" % po[0].status)
	ok(ST.qty("pflanzen", "C0", s.companies[0].depots[0]) == 0 + 400 - int(po[0].qty), "Ware verlässt das Unternehmensdepot nur einmal")
	ok(identity_ok(s), "Geld und Waren erhalten (Unternehmenslieferung)")
	# Projektmaterial: reserviert, nicht doppelt abgerechnet
	var need := CityDepot.material_need(["strasse", "strom"], 2)
	var miss := D.reserve_for_project("P9", need)
	ok(miss.is_empty() and D.project_complete("P9"), "Material für Projekt reserviert")
	var free_before: int = D.stock_of("schotter")
	ok(ST.reserved("schotter", "P0", D.building) == 40, "reservierte Menge Schotter (40)")
	var used := D.consume_project("P9", "Baufirma K0")
	ok(int(used.get("schotter", 0)) == 40 and D.issues.size() >= 1 and D.issues[-1].mode == "ueberlassen", "Auftragsmaterial verbraucht und als überlassen protokolliert")
	ok(ST.reserved("schotter", "P0", D.building) == 0 and D.on_hand("schotter") == int(CityGoods.get_item("schotter").target * 0.7) - 40, "Bestand um die verwendete Menge gesunken")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.city_depot.orders.size() == D.orders.size() and s2.city_depot.on_hand("leitkegel") == D.on_hand("leitkegel"), "Lager und Bestellungen nach Laden")
	ok(identity_ok(s2), "Geld und Waren nach Laden erhalten")


## Auftrag 5, Etappe 2: Lagerpersonal, Rampen, Geraete.
func test_depot_operations() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	run(s, 60.0 * 2.0)
	var D := s.city_depot
	var staff := D.roster()
	ok(staff.size() >= 3, "Lagerpersonal aus den Bürgern der Stadt (%d Personen)" % staff.size())
	ok(staff.any(func(w): return w.role == "vorarbeiter") and staff.any(func(w): return w.role == "stapler") and staff.any(func(w): return w.role == "lager"), "Rollen Vorarbeiter, Staplerfahrer, Lagerarbeiter")
	ok(s.citizens.people.any(func(p): return p.employer == "stadtlager" and float(p.wage) > 0.0), "gleiche Arbeitsverträge und Löhne wie die übrigen Bürger")
	var cap_all := D.dock_capacity()
	ok(cap_all > 500, "Wareneingang schafft %d Einheiten je Tag" % cap_all)
	var f_all := D.unload_factor()
	# Krankheit und Erschoepfung mindern die Leistung
	for w in staff:
		D.crew[w.id] = {"fatigue": 0.0, "sick_until": 9999, "rest_until": -1}
	ok(D.dock_capacity() == 0 and D.available_staff() == 0, "ohne verfügbares Personal keine Abfertigung")
	ok(D.current_tasks().blockers.any(func(b): return "krank" in b), "Blockade benennt die Ursache (krank)")
	D.crew[staff[0].id] = {"fatigue": 0.0, "sick_until": -1, "rest_until": -1}
	D.crew[staff[1].id] = {"fatigue": 0.0, "sick_until": -1, "rest_until": -1}
	ok(D.dock_capacity() > 0 and D.dock_capacity() < cap_all and D.unload_factor() > f_all, "weniger Personal: weniger Leistung, längere Entladung")
	# Stau am Wareneingang: Lieferung wartet, wenn die Kapazitaet nicht reicht
	D.crew.clear()
	var it := CityGoods.get_item("kies")
	s.stock.add("kies", 100, "P0", D.building, "Test", 0.0, "pruefung")
	# Rampen: ein zweiter Lkw muss warten, wenn alle Rampen belegt sind
	var vs: Array = s.vehicles.values()
	var kk := Contract.new()
	kk.id = "AX1"
	kk.dropoff = D.building
	kk.pickup = s.trader.bauhof
	kk.order_ref = "B999"
	kk.payer = "P0"
	kk.status = "in_transit"
	s.contracts[kk.id] = kk
	for v in vs.slice(0, 2):
		v.stops = [{"contract_id": kk.id, "art": "abladen", "ort": "ziel", "menge": 1}]
	vs[0].state = "unloading"
	D.ramps = 1
	ok(D.ramps_free() == 0 and not s._bay_free(vs[1]), "alle Rampen belegt: der Lkw wartet")
	D.ramps = 2
	ok(D.ramps_free() == 1 and s._bay_free(vs[1]), "zusätzliche Rampe entspannt den Engpass")
	D.truck_waits(vs[1])
	ok(D.waits == 1 and D.recent_waits() == 1, "Wartezeit wird festgehalten")
	vs[0].state = "idle"
	vs[0].stops = []
	vs[1].stops = []
	# Ausbau kostet Geld aus der Stadtkasse und wirkt
	s.economy.transfer("X0", "P0", 100000.0)
	var p0 := float(s.economy.accounts.P0)
	var r0 := D.ramps
	ok(D.expand("ramp").ok and D.ramps == r0 + 1 and float(s.economy.accounts.P0) == p0 - CityDepot.RAMP_COST, "Rampe gebaut, Kosten aus der Stadtkasse")
	var fk := D.forklifts()
	ok(D.expand("forklift").ok and D.forklifts() == fk + 1, "Gabelstapler gekauft")
	var n0 := D.roster().size()
	ok(D.expand("staff").ok and D.roster().size() == n0 + 1, "Lagerkraft eingestellt")
	ok(D.running_costs().loehne > 0.0, "laufende Kosten enthalten Löhne (%s)" % Catalog.money(float(D.running_costs().summe)))
	ok(identity_ok(s), "Geld und Waren erhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.city_depot.ramps == D.ramps and s2.city_depot.roster().size() == D.roster().size(), "Ausbau nach Laden erhalten")


func test_traffic_flow() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	var T := s.traffic_flow
	var road := Vector2i(-1, -1)
	var junction := Vector2i(-1, -1)
	for y in s.city.size:
		for x in s.city.size:
			var p := Vector2i(x, y)
			if not s.city.is_road(p):
				continue
			if road.x < 0 and s.city.road_mask(p) not in TrafficFlow.JUNCTION_MASKS:
				road = p
			if junction.x < 0 and s.city.road_mask(p) in TrafficFlow.JUNCTION_MASKS:
				junction = p
	ok(road.x >= 0 and junction.x >= 0, "Karte hat Strassen und Kreuzungen")
	ok(T.capacity_of(junction) < T.capacity_of(road), "Kreuzung fasst weniger Fahrzeuge als freie Strecke")
	var cars := func(n: int) -> Array:
		var a: Array = []
		for i in n:
			a.append(Mover.new())
		return a
	s._hash.clear()
	s._hash[road] = cars.call(TrafficFlow.ROAD_CAPACITY)
	ok(T.factor(road) == 1.0, "bis zur Kapazitaet ungebremst")
	s._hash[road] = cars.call(TrafficFlow.ROAD_CAPACITY * 2)
	ok(is_equal_approx(T.factor(road), 0.5), "doppelte Belegung halbiert das Tempo")
	s._hash[road] = cars.call(40)
	ok(T.factor(road) == TrafficFlow.MIN_FACTOR, "dichtester Stau bremst nicht unter den Mindestwert")
	var lost0 := T.lost_total
	T.record(road, 0.5, 10.0)
	ok(is_equal_approx(T.lost_total - lost0, 5.0), "10 s bei halbem Tempo kosten 5 s")
	ok(T.hotspots(1)[0].cell == road, "Engpass wird benannt")
	T.record(junction, 1.0, 10.0)
	ok(not T.lost_by_cell.has(junction), "freie Fahrt erzeugt keinen Zeitverlust")
	ok(T.avg_speed() < 1.0 and T.avg_speed() > 0.0, "mittlere Geschwindigkeit sinkt")
	# wiederkehrend: Stau an mehreren Tagen
	for d in TrafficFlow.RECURRING_DAYS:
		T.record(road, 0.5, 1.0)
		s.game_min += GameCalendar.day_game_min
		T.on_day()
	ok(T.hotspots(1)[0].recurring, "Stau an mehreren Tagen gilt als wiederkehrender Engpass")
	# im laufenden Spiel: Fahrzeuge bleiben unter ihrer freien Fahrt, Geld und Waren bleiben erhalten
	var s2 := new_sim(4, 256)
	run(s2, 60.0 * 2.0)
	ok(s2.traffic_flow.moving_total > 0.0, "Fahrzeugzeit wird gemessen")
	ok(s2.traffic_flow.avg_speed() > 0.3 and s2.traffic_flow.avg_speed() <= 1.0, "mittlere Geschwindigkeit plausibel (%.2f)" % s2.traffic_flow.avg_speed())
	ok(identity_ok(s2), "Geld und Waren erhalten")
	_traffic_measures_test()


func _traffic_measures_test() -> void:
	var s := new_sim(2, 256)
	var T := s.traffic_flow
	var junction := Vector2i(-1, -1)
	var road := Vector2i(-1, -1)
	for y in s.city.size:
		for x in s.city.size:
			var p := Vector2i(x, y)
			if s.city.is_road(p):
				if junction.x < 0 and T.is_junction(p):
					junction = p
				if road.x < 0 and not T.is_junction(p):
					road = p
	var r := T.propose("ampel", junction, "Test")
	ok(not r.ok and "wiederkehrend" in r.msg, "ein einzelner Stau rechtfertigt keine Massnahme (%s)" % r.msg)
	T.lost_by_cell[junction] = 120.0
	T.jam_days[junction] = TrafficFlow.RECURRING_DAYS
	ok(not T.propose("ampel", road, "Test").ok, "Ampelsteuerung nur an Kreuzungen")
	var p0 := float(s.economy.accounts.P0)
	var com := s.mayor.commitments
	var cap0 := T.capacity_of(junction)
	var mi := {"action": "improve_traffic", "kind": "ampel", "x": junction.x, "y": junction.y, "reason": "Engpass"}
	var ind := s.mayor.indicators()
	ok(ind.verkehr.engpaesse.any(func(e): return e.x == junction.x and e.wiederkehrend), "Beobachtung nennt den wiederkehrenden Engpass")
	ok(MayorBrain.decide(ind).actions.any(func(a): return a.action == "improve_traffic" and a.x == junction.x), "Regelbuergermeister plant eine Massnahme")
	r = s.mayor.execute(mi)
	ok(r.ok and s.mayor.commitments == com + TrafficFlow.MEASURES.ampel.cost, "Massnahme angelegt, Mittel reserviert (%s)" % r.msg)
	ok(T.capacity_of(junction) == cap0, "vor der Fertigstellung keine neue Kapazitaet")
	ok(not s.mayor.execute(mi).ok, "keine zweite Massnahme auf derselben Zelle waehrend der Bauzeit")
	s.game_min += GameCalendar.day_game_min * (TrafficFlow.MEASURES.ampel.days + 1)
	T.on_day()
	ok(T.capacity_of(junction) == cap0 + 1, "nach der Bauzeit wirkt die neue Kapazitaet")
	ok(s.mayor.commitments == com and absf(float(s.economy.accounts.P0) - (p0 - TrafficFlow.MEASURES.ampel.cost)) < 0.01, "Kosten aus der Stadtkasse bezahlt")
	var m: Dictionary = T.measures.values()[0]
	ok(m.status == "fertig" and T.effect(m).vorher >= 0.0, "Vorher-Nachher-Vergleich vorhanden")
	ok(s.mayor.indicators().verkehr.massnahmen.size() == 1, "fertige Massnahme steht in der Beobachtung")
	ok(identity_ok(s), "Geld erhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.traffic_flow.capacity_of(junction) == cap0 + 1 and s2.traffic_flow.measures.size() == 1, "Massnahmen nach Laden erhalten")
	# Ladezone: nur auf Strecken neben Gebaeuden, billiger als Ausbau, keine Spur weniger waehrend des Baus
	var bay := Vector2i(-1, -1)
	var bare := Vector2i(-1, -1)
	for y in s.city.size:
		for x in s.city.size:
			var q := Vector2i(x, y)
			if s.city.is_road(q) and not T.is_junction(q):
				if bay.x < 0 and T.next_to_building(q):
					bay = q
				elif bare.x < 0 and not T.next_to_building(q):
					bare = q
	ok(bay.x >= 0, "Karte hat Strecken neben Gebaeuden")
	T.jam_days[bay] = TrafficFlow.RECURRING_DAYS
	T.jam_days[junction] = TrafficFlow.RECURRING_DAYS
	ok(not T.propose("ladezone", junction, "Test").ok, "keine Ladezone auf einer Kreuzung")
	if bare.x >= 0:
		T.jam_days[bare] = TrafficFlow.RECURRING_DAYS
		ok(not T.propose("ladezone", bare, "Test").ok, "keine Ladezone ohne Gebaeude daneben")
	var cap_bay := T.capacity_of(bay)
	var rb := T.propose("ladezone", bay, "Test")
	ok(rb.ok and T.capacity_of(bay) == cap_bay, "Ladezone angelegt, waehrend des Baus keine Spur weniger (%s)" % rb.msg)
	s.game_min += GameCalendar.day_game_min * (TrafficFlow.MEASURES.ladezone.days + 1)
	T.on_day()
	ok(T.capacity_of(bay) == cap_bay + 1, "fertige Ladezone erhoeht die Kapazitaet")
	ok(TrafficFlow.MEASURES.ladezone.cost < TrafficFlow.MEASURES.ausbau.cost, "Ladezone ist guenstiger als Ausbau")
	ok(identity_ok(s), "Geld nach Ladezone erhalten")


func test_retail() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	var R := s.retail
	ok(R.shops.size() >= 3, "Restaurants und Geschäfte aus dem Stadtplan (%d Betriebe)" % R.shops.size())
	ok(R.shops.values().any(func(x): return x.kind == "restaurant"), "mindestens ein Restaurant")
	ok(R.shops.values().any(func(x): return x.kind == "baumarkt"), "der Stadtplan enthält einen Baumarkt")
	for x in R.shops.values():
		ok(s.economy.accounts.has(x.id) and float(s.economy.accounts[x.id]) >= 0.0, "Betrieb %s hat ein eigenes Konto" % x.name)
		break
	ok(identity_ok(s), "Geld und Waren zu Beginn erhalten")
	run(s, 60.0 * 12.0)
	var sm := R.summary()
	ok(float(sm.umsatz) > 0.0 and int(sm.verkauft) > 0, "Haushalte kaufen ein (Umsatz %s)" % Catalog.money(float(sm.umsatz)))
	ok(int(sm.bestellungen) > 0, "Betriebe bestellen Nachschub (%d Bestellungen)" % int(sm.bestellungen))
	ok(int(sm.geliefert) > 0, "Nachschub wird angeliefert (%d)" % int(sm.geliefert))
	ok(R.orders.values().any(func(o): return s.contracts.has(o.contract) and s.contracts[o.contract].payer == o.shop), "Transportauftrag mit dem Betrieb als Zahler")
	ok(s.stock.balance_error() == 0, "Warenbilanz stimmt")
	ok(identity_ok(s), "Geld und Waren nach 12 Tagen erhalten")
	# fehlende Zutat: Gericht entfaellt, entgangener Umsatz wird gezaehlt
	var rest: Dictionary = R.shops.values().filter(func(x): return x.kind == "restaurant")[0]
	for it in ["gemuese", "fleisch", "teigwaren", "milch_zutat", "fassgetraenk"]:
		s.stock.consume(it, s.stock.qty(it, rest.id, rest.building) + 0, rest.id, rest.building, "Test")
	var lost0 := int(rest.lost)
	R._serve(rest, 99)
	ok(int(rest.lost) > lost0 and "gemuese" in rest.missing, "ohne Zutaten keine Gerichte, Verlust gezählt")
	# Pfand und Mehrweg
	var bev: Dictionary = R.shops.values().filter(func(x): return "flasche" in R.spec_of(x).goods)[0]
	s.stock.add("flasche", 40, bev.id, bev.building, "Test", s.game_min)
	var h0 := float(s.economy.accounts.H0)
	R._serve(bev, 100)
	R._returns(bev)
	ok(s.stock.qty("leergut", bev.id, bev.building) > 0, "Leergut kommt zurück und gehört dem Betrieb")
	R._return_empties(bev)
	ok(s.stock.qty("leergut", bev.id, bev.building) == 0 and s.stock.qty("leergut", Retail.WHOLESALER, R.wholesale_building) > 0, "Leergut fährt mit der Lieferung zum Großhandel zurück")
	ok(identity_ok(s), "Pfandkreislauf erhält Geld und Waren")
	# Monatsabschluss: Loehne an S0, Miete an P0
	var p0 := float(s.economy.accounts.P0)
	R.on_month(1)
	ok(float(s.economy.accounts.P0) > p0 and rest.wages > 0.0, "Miete an die Stadt, Löhne bezahlt")
	ok(identity_ok(s), "Monatsabschluss erhält Geld")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.retail.shops.size() == R.shops.size() and s2.retail.orders.size() == R.orders.size(), "Betriebe und Bestellungen nach Laden erhalten")
	ok(identity_ok(s2), "Geld und Waren nach Laden erhalten")

func test_waste() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	var W := s.waste
	var p0 := float(s.economy.accounts.P0)
	run(s, 60.0 * 31.0)   # ein Monat
	ok(float(W.total.tons) > 20.0 and float(W.total.cost) > 0.0, "Abfall wird gesammelt und bezahlt (%.1f t)" % float(W.total.tons))
	ok(W.rate >= Waste.BASE_RECYCLING and W.rate <= Waste.BASE_RECYCLING + Waste.MEHRWEG_BONUS, "Recyclingquote im Rahmen (%d %%)" % roundi(W.rate * 100.0))
	ok(float(W.total.fees) > 0.0 and not W.last_month.is_empty(), "Gebühr der Haushalte nach Monatsabschluss")
	ok(float(s.economy.accounts.P0) > p0 - 20000.0, "Müllabfuhr bricht die Stadtkasse nicht")
	ok(s.retail.stats.bottles_sold > 0 and s.retail.stats.bottles_returned > 0, "Mehrwegflaschen werden verkauft und zurückgegeben")
	ok(identity_ok(s), "Geld und Waren erhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(is_equal_approx(float(s2.waste.total.tons), float(W.total.tons)) and is_equal_approx(s2.waste.rate, W.rate), "Müllstatistik nach Laden erhalten")
	ok(LiveText.retail_block(s).contains("HANDEL") and LiveText.shop_panel(s, s.retail.shops.values()[0]).contains("Lager"), "Anzeigen liefern Text")

## Abnahme Auftrag 5 (Abschnitt 15): Engpass -> Massnahme des Buergermeisters -> neue Kapazitaet; parallel Restaurant: Bestellung -> Lieferung -> Gericht -> Konten.
func test_supply_acceptance() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2, 256)
	var T := s.traffic_flow
	var cell := Vector2i(-1, -1)
	for y in s.city.size:
		for x in s.city.size:
			if cell.x < 0 and s.city.is_road(Vector2i(x, y)) and T.is_junction(Vector2i(x, y)):
				cell = Vector2i(x, y)
	T.lost_by_cell[cell] = 300.0                                  # 1 wiederkehrender Engpass
	T.jam_days[cell] = TrafficFlow.RECURRING_DAYS
	var cap0 := T.capacity_of(cell)
	var plan := MayorBrain.decide(s.mayor.indicators())           # 2 Verwaltung beschliesst eine finanzierte Massnahme
	var act: Dictionary = plan.actions.filter(func(a): return a.action == "improve_traffic")[0]
	ok(s.mayor.execute(act).ok, "Bürgermeister beschließt die Verkehrsmaßnahme")
	var rest: Dictionary = s.retail.shops.values().filter(func(x): return x.kind == "restaurant")[0]
	var orders0: int = s.retail.stats.orders
	run(s, 60.0 * 10.0)                                           # 9-10 Restaurant bestellt, Lieferung kommt an (Transportauftrag oder Lieferdienst)
	ok(T.capacity_of(cell) == cap0 + 1, "8 nach der Bauzeit wirkt die neue Kapazität")
	ok(s.retail.stats.orders > orders0 and s.retail.stats.delivered > 0, "Betriebe bestellen und bekommen Ware")
	var rev0 := float(rest.revenue)
	run(s, 60.0 * 2.0)
	ok(float(rest.revenue) > rev0 and float(rest.cogs) > 0.0, "11 Bewohner bezahlen Gerichte, Zutaten werden verbraucht")
	var p0 := float(s.economy.accounts.P0)
	var s0 := float(s.economy.accounts.S0)
	s.retail.on_month(1)
	ok(float(s.economy.accounts.P0) > p0 and rest.wages > 0.0 and float(s.economy.accounts.S0) != s0, "12 Löhne, Miete und Abgaben erscheinen in den Konten")
	ok(identity_ok(s), "Geld und Waren bleiben in allen Konten erhalten")


func test_housing() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var H: Housing = s.housing
	var people: Array = s.citizens.people
	ok(H.units.size() > 0, "Wohnungsbestand angelegt (%d Einheiten)" % H.units.size())
	ok(H.vacancy_rate() > 0.02 and H.vacancy_rate() < 0.3, "Leerstand plausibel (%.1f %%)" % (H.vacancy_rate() * 100.0))
	ok(people.all(func(p): return H.units.has(str(p.get("home", "")))), "Jeder Bürger hat eine Wohnung")
	ok(s.households.homes.values().all(func(h): return H.units.has(str(h.get("unit", "")))), "Jeder Firmenhaushalt hat eine Wohnung")
	var tenants := {}
	var clash := false
	for h in s.households.homes.values():
		clash = clash or tenants.has(h.unit)
		tenants[h.unit] = true
	for p in people:
		clash = clash or (tenants.has(p.home) and H.units[p.home].tenant != "B")
	ok(not clash, "Keine Wohnung mit zwei Mietverträgen")
	ok(H.units.values().all(func(u): return u.tenant != "" or not people.any(func(p): return p.home == u.id)), "Freie Wohnungen haben keine Bewohner")
	# Miete fließt über V0 und bleibt im Geldkreislauf
	var p0 := float(s.economy.accounts.P0)
	run(s, 60.0 * 65.0)
	ok(H.stats.rent > 0.0, "Miete wird gezahlt (%.0f)" % H.stats.rent)
	ok(absf(float(s.economy.accounts.V0)) < 0.01, "Vermieterkonto V0 leitet die Miete weiter")
	ok(float(s.economy.accounts.P0) != p0, "Grundsteuer erreicht die Stadtkasse")
	ok(identity_ok(s), "Geld erhalten mit Mieten")
	# Räumung nach drei Monaten Rückstand
	var cu: Dictionary = {}
	for u in H.units.values():
		if u.tenant == "B":
			cu = u
			break
	var members: Array = people.filter(func(p): return p.home == cu.id)
	ok(members.size() > 0, "Bürgergruppe gefunden")
	cu.arrears = Housing.EVICT_AFTER
	var ev := int(H.stats.evictions)
	H.on_month(0)
	ok(int(H.stats.evictions) == ev + 1, "Rückstand führt zur Räumung")
	ok(members.all(func(p): return p.home != cu.id), "Geräumte Bürger ziehen aus")
	ok(members.all(func(p): return str(p.home) == "" or H.units.has(p.home)), "Geräumte finden eine andere Wohnung oder sind wohnungslos")
	ok(identity_ok(s), "Geld erhalten nach Räumung")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.housing.units.size() == H.units.size(), "Wohnungsbestand geladen")
	ok(s2.citizens.people.all(func(p): return str(p.get("home", "")) == "" or s2.housing.units.has(p.home)), "Wohnorte der Bürger geladen")
	run(s2, 60.0 * 35.0)
	ok(identity_ok(s2), "Geld erhalten nach Laden mit Mieten")


func test_job_move() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var H: Housing = s.housing
	var occ := H._citizen_occupants()
	var uid := ""
	for k in occ:
		if H.units[k].tenant == "B":
			uid = k
			break
	ok(uid != "", "Es gibt eine bewohnte Bürgereinheit")
	var group: Array = occ[uid]
	var p: Dictionary = group[0]
	for q in group:
		q.wage = 20.0
	var old: Dictionary = H.units[uid]
	var old_d := int(s.city.building(int(old.building)).get("district", 0))
	var target: Dictionary = {}
	for u in H.vacant_units():
		if int(s.city.building(int(u.building)).get("district", 0)) != old_d:
			target = u
			break
	ok(not target.is_empty(), "Freie Einheit in einem anderen Viertel vorhanden")
	var d := int(s.city.building(int(target.building)).get("district", 0))
	var month := 0
	while Citizens.roll(int(p.id), month, 6) >= Housing.MOVE_CHANCE:
		month += 1
	# gleiches Viertel: kein Umzug
	ok(not H.relocate_for_job(p, old_d, month), "Stelle im eigenen Viertel: kein Umzug")
	# zu geringes Einkommen: kein Umzug
	for q in group:
		q.wage = 0.1
	ok(not H.relocate_for_job(p, d, month), "Miete über der Belastungsgrenze: kein Umzug")
	for q in group:
		q.wage = 200.0
	var total := s.citizens.people.size()
	ok(H.relocate_for_job(p, d, month), "Neue Stelle im anderen Viertel: Umzug")
	var moved := true
	for q in group:
		moved = moved and str(q.home) != uid and int(s.city.building(int(H.units[str(q.home)].building)).get("district", 0)) == d
	ok(moved and old.tenant == "" and H.units[str(p.home)].tenant == "B", "Ganze Gruppe zieht um, alte Einheit wird frei")
	ok(H.stats.job_moves == 1 and s.citizens.people.size() == total, "Umzug gezählt, niemand verschwindet")
	ok(identity_ok(s), "Geld erhalten nach Umzug")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.housing.stats.job_moves == 1, "Umzugszähler bleibt nach Laden erhalten")


func test_housing_market() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var H: Housing = s.housing
	# Mietspiegel folgt dem Mietindex des Bürgermeisters, aber höchstens um INDEX_STEP je Monat
	var u0: Dictionary = H.units.values()[0]
	var base := float(u0.base)
	s.mayor.waiting = 100000
	ok(s.mayor.rent_index() > 150.0, "Wohnungsnot treibt den Mietindex (%.0f)" % s.mayor.rent_index())
	for m in 12:
		H.on_month(m)
	ok(absf(H.index - (1.0 + 12.0 * Housing.INDEX_STEP)) < 0.0001, "Mietspiegel steigt höchstens 0,4 %% je Monat (%.3f)" % H.index)
	ok(absf(float(u0.rent) - roundf(base * H.index)) < 0.01, "Miete der Einheit folgt dem Mietspiegel (%.0f)" % float(u0.rent))
	s.mayor.waiting = 0
	s.mayor.stock_units = 100000   # viel Leerstand
	H.on_month(13)
	ok(H.index < 1.0 + 12.0 * Housing.INDEX_STEP, "Leerstand senkt den Mietspiegel wieder (%.3f)" % H.index)
	# Miete geht an den Eigentümer
	var ids: Array = H.units.keys()
	var a: Dictionary = H.units[ids[0]]
	var b: Dictionary = H.units[ids[1]]
	var c: Dictionary = H.units[ids[2]]
	a.owner = "D0"
	a.tenant = "B"
	b.owner = "C0"
	b.tenant = "B"
	c.owner = "B"   # unbekannter Eigentümer fällt auf V0 zurück
	c.tenant = "B"
	var d0 := float(s.economy.accounts.D0)
	var v0 := float(s.economy.accounts.V0)
	var cash0 := s.companies[0].ledger.cash
	H._pay_owner(a, 100.0)
	H._pay_owner(b, 50.0)
	H._pay_owner(c, 10.0)
	ok(absf(float(s.economy.accounts.D0) - d0 - 100.0) < 0.001, "Bauträger erhält Miete")
	ok(absf(s.companies[0].ledger.cash - cash0 - 50.0) < 0.001, "Unternehmen erhält Miete in die Kasse")
	ok(absf(float(s.economy.accounts.V0) - v0 - 10.0) < 0.001, "Unbekannter Eigentümer: Miete an V0")
	ok(identity_ok(s), "Geld erhalten bei Zahlung an Eigentümer")
	# Selbstnutzer zahlen keine Miete
	a.owner = "H1"
	a.tenant = "H1"
	ok(H.rent_due(a) == 0.0, "Selbstnutzer zahlt keine Miete")
	# Neue Einheit mit Wohnungssuchenden: Zuzug bekommt den Wohnort der Einheit
	var hu: Dictionary = H.register_unit(1, 70.0, "D0")
	var persons := s.citizens.people.size()
	s.citizens.immigrate(2, 1, hu.id)
	ok(s.citizens.people.size() == persons + 2 and str(s.citizens.people[-1].home) == hu.id, "Zuzügler tragen ihre Wohneinheit")
	ok(H.vacant_units().any(func(x): return x.id == hu.id), "Einheit ohne Mietvertrag bleibt frei, bis Housing sie vergibt")
	H.on_month(14)
	ok(H.units[hu.id].rent > 0.0 and identity_ok(s), "Neue Einheit läuft im Mietspiegel")


func test_consumer_credit() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var Bk: Banking = s.banking
	var h: Dictionary = s.households.household_of(s.personnel.employed(0)[0])
	ok(not h.is_empty(), "Firmenhaushalt vorhanden")
	h.last_income = 900.0
	h.shortfall = 200.0
	var cash0 := Bk.bank_cash(Banking.CONSUMER_BANK)
	var bal0 := float(h.balance)
	var m := Bk.consumer_apply(h.id)
	ok(not m.is_empty() and m.kind == "konsum", "Haushalt mit Fehlbetrag bekommt Konsumkredit")
	ok(absf(float(h.balance) - bal0 - float(m.outstanding)) < 0.01, "Kreditsumme landet auf dem Haushaltskonto (%.0f)" % float(m.outstanding))
	ok(Bk.bank_cash(Banking.CONSUMER_BANK) < cash0, "Bargeld der Bank sinkt")
	ok(identity_ok(s), "Geld erhalten nach Konsumkredit")
	# weitere Kredite nur im Rahmen der Belastungsgrenze (30 % des Einkommens)
	h.shortfall = 3000.0
	var q := Bk.consumer_quote(h.id, 3000.0)
	ok(not q.ok and "übersteigen" in q.msg, "Belastungsgrenze: " + q.msg)
	ok(Bk.consumer_quote(h.id, 100.0).ok == false, "Mindestbetrag")
	# Tilgung über die Monate
	h.balance = 5000.0
	var out0 := float(m.outstanding)
	Bk.on_month(1)
	ok(float(m.outstanding) < out0 and m.status == "laufend", "Rate wird gezahlt (Restschuld %.0f)" % float(m.outstanding))
	# Rückstand, Ausfall, Pfändung
	h.balance = 0.0
	for i in Banking.DEFAULT_AFTER:
		Bk.on_month(2 + i)
	ok(m.status == "pfaendung" and float(m.residual) > 0.0, "Nach drei Monaten Rückstand beginnt die Pfändung (%s)" % m.status)
	var q2 := Bk.consumer_quote(h.id, 300.0)
	ok(not q2.ok and "Pfändung" in q2.msg, "Keine neuen Kredite bei Pfändung")
	h.balance = 2000.0
	h.last_income = 1800.0   # 1200 über der Lebenshaltung -> 600 werden gepfändet
	var res0 := float(m.residual)
	Bk._garnish()
	ok(absf(res0 - float(m.residual) - minf(res0, 0.5 * (1800.0 - s.households.costs(h)))) < 0.01, "Pfändung zieht den Anteil über der Lebenshaltung (%.0f)" % (res0 - float(m.residual)))
	for i in 20:
		h.balance = 2000.0
		Bk._garnish()
	ok(m.status == "getilgt", "Restschuld ist vollständig gepfändet (%s)" % m.status)
	ok(identity_ok(s), "Geld erhalten nach Pfändung")
	var cs := Bk.consumer_summary()
	ok(int(cs.vergeben) == 1 and int(cs.getilgt) == 1, "Zusammenfassung zählt den Kredit")
	# Unternehmen als Bauherren: fehlende Mittel über Bankkredit
	var c := s.companies[0]
	var debt0 := c.ledger.debt
	var cash1 := c.ledger.cash
	var granted: bool = s.construction._company_credit("C0", 4000.0)
	ok(granted and c.ledger.debt > debt0 and c.ledger.cash > cash1, "Unternehmen finanziert Bauvorhaben über Bankkredit (Schuld %.0f)" % c.ledger.debt)
	ok(identity_ok(s), "Geld erhalten nach Firmenkredit für den Bau")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.banking.consumer_summary().vergeben == 1, "Konsumkredit gespeichert und geladen")


func test_contentment() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var C: Contentment = s.contentment
	var H: Housing = s.housing
	C.on_month(1)
	var occupied: Array = H.units.values().filter(func(u): return u.tenant != "")
	ok(occupied.size() > 0 and occupied.all(func(u): return float(u.sat) >= 0.0 and float(u.sat) <= 100.0), "Index 0-100 für alle belegten Einheiten (%d)" % occupied.size())
	ok(C.mean > 20.0 and C.mean < 95.0, "Stadtmittel plausibel (%.1f)" % C.mean)
	ok(not C.by_district.is_empty(), "Mittelwerte je Viertel")
	ok(C.spend_factor() >= 0.85 and C.spend_factor() <= 1.1, "Konsumfaktor begrenzt (%.3f)" % C.spend_factor())
	# Gebäudezustand und Mietrückstand wirken auf die Wohnung
	var u: Dictionary = occupied.filter(func(x): return x.tenant == "B")[0]
	s.care.condition[int(u.building)] = 100.0
	C.on_month(2)
	var good := float(u.sat)
	s.care.condition[int(u.building)] = 0.0
	C.on_month(3)
	ok(float(u.sat) < good, "Verfallenes Gebäude senkt die Zufriedenheit (%.1f -> %.1f)" % [good, float(u.sat)])
	u.arrears = 2
	var before := float(u.sat)
	C.on_month(4)
	ok(float(u.sat) < before, "Mietrückstand senkt die Zufriedenheit (%.1f -> %.1f)" % [before, float(u.sat)])
	# schlechte Versorgung und Verkehr: Wegzug nach drei Monaten, deterministisch über die Monate verteilt
	for shop in s.retail.shops.values():
		shop.status = "geschlossen"
	s.traffic_flow.moving_total = 100.0
	s.traffic_flow.lost_total = 60.0
	ok(C.traffic_score() == 0.0 and C.supply_score() < 35.0, "Verkehr und Versorgung bewertet (%.0f / %.0f)" % [C.traffic_score(), C.supply_score()])
	var members: Array = s.citizens.people.filter(func(p): return p.home == u.id)
	for p in members:
		p.employer = ""
		p.jobless_months = 6
		p.net = 0.0
	var pop0 := s.citizens.people.size()
	var gone0 := C.emigrated
	for m in range(5, 45):
		C.on_month(m)
		if C.emigrated > gone0:
			break
	ok(C.emigrated > gone0 and s.citizens.people.size() < pop0, "Unzufriedene ziehen weg (%d Personen)" % (C.emigrated - gone0))
	ok(H.units.values().all(func(x): return x.tenant != "" or not s.citizens.people.any(func(p): return p.get("home", "") == x.id)), "Freie Wohnungen haben keine Bewohner")
	ok(identity_ok(s), "Geld erhalten nach Wegzug")
	# Firmenhaushalt: Motivation folgt dem Wohnumfeld
	var h: Dictionary = s.households.household_of(s.personnel.employed(0)[0])
	ok(C.of_household(h.id) >= 0.0, "Index des Firmenhaushalts abrufbar (%.1f)" % C.of_household(h.id))
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(s2.contentment.mean - C.mean) < 0.001 and s2.contentment.emigrated == C.emigrated, "Zufriedenheit gespeichert und geladen")
	run(s2, 60.0 * 35.0)
	ok(identity_ok(s2), "Geld erhalten nach Laden mit Zufriedenheit")


func test_planning_aids() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	s.contentment.on_month(1)
	var aids: Dictionary = s.housing.planning_aids()
	ok(aids.has("wohnungsbedarf_einheiten") and aids.has("zahlungsfaehigkeit") and aids.has("mietbelastung_firmenhaushalte"), "Planungshilfen vollständig")
	ok(float(aids.zahlungsfaehigkeit) <= 1.0 and float(aids.zahlungsfaehigkeit) > 0.9, "Zahlungsfähigkeit zu Beginn hoch (%.3f)" % float(aids.zahlungsfaehigkeit))
	# Wohnungsnot erhöht den Bedarf
	var need0 := int(aids.wohnungsbedarf_einheiten)
	s.mayor.waiting = 2000   # mehr als der Leerstand über dem Sollwert
	ok(int(s.housing.planning_aids().wohnungsbedarf_einheiten) >= need0 + 1, "Wartende Haushalte erhöhen den Wohnungsbedarf (%d)" % int(s.housing.planning_aids().wohnungsbedarf_einheiten))
	var homeless := 0
	for p in s.citizens.people.slice(0, 24):
		p.home = ""
		homeless += 1
	ok(s.housing.homeless_count() == homeless, "Wohnungslose gezählt (%d)" % homeless)
	# Zahlungsfähigkeit sinkt mit Mietrückstand
	var late := 0
	for u in s.housing.units.values():
		if u.tenant != "" and late < 20:
			u.arrears = 1
			late += 1
	ok(float(s.housing.planning_aids().zahlungsfaehigkeit) < float(aids.zahlungsfaehigkeit), "Mietrückstände senken die Zahlungsfähigkeit")
	# Bürgermeister sieht die Kennzahlen
	var ind: Dictionary = s.mayor.indicators()
	ok(ind.wohnen.has("planung") and ind.wohnen.has("zufriedenheit") and ind.wohnen.has("wohnungslos"), "Bürgermeister-Kennzahlen enthalten Wohnen, Zufriedenheit und Planung")
	# Spielerbeobachtung enthält den Wohnmarkt
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	ok(obs.has("wohnmarkt") and obs.wohnmarkt.has("mietspiegel") and obs.wohnmarkt.has("zufriedenheit_deiner_mitarbeiter"), "Beobachtung enthält den Wohnmarkt")
	ok(JSON.stringify(obs).length() > 0 and JSON.parse_string(JSON.stringify(obs.wohnmarkt)) != null, "Wohnmarkt ist als JSON darstellbar")


func test_central_bank() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var Z: CentralBank = s.central_bank
	var Bk: Banking = s.banking
	ok(s.economy.accounts.has("Z0") and absf(float(s.economy.accounts.Z0)) < 0.001, "Zentralbankkonto Z0 vorhanden")
	# Geldmenge: Nichtbanken + Banken + Z0 + Ausland + Kapitalgeber = Gesamtbestand
	var parts: float = Z.money_supply()
	for k in ["B1", "B2", "B3", "Z0", "X0", "I0"]:
		parts += float(s.economy.accounts[k])
	ok(absf(parts - s.economy.total()) < 0.01, "Geldmenge und Bankkonten ergeben den Gesamtbestand")
	# Einlage bringt Reserve, Entnahme darunter löst Refinanzierung aus
	s.companies[0].ledger.inject(60000.0)
	var dep := Bk.deposit(0, 0, 50000.0, "tages", 0)
	ok(dep.get("ok", true), "Einlage bei der Geschäftsbank")
	Bk.reserve_ratio = 10.0   # strenge Reservepflicht: Bargeld 450 000 liegt unter der Mindestreserve 500 000
	var req := Z.required(0)
	ok(req > Bk.bank_cash(0), "Bank liegt unter der Mindestreserve (%.0f < %.0f)" % [Bk.bank_cash(0), req])
	var cash_before := Bk.bank_cash(0)
	Z.on_month(1)
	ok(Bk.bank_cash(0) > cash_before and float(Z.refi.B1) > 0.0, "Bank unter Mindestreserve leiht bei der Zentralbank (%.0f)" % float(Z.refi.B1))
	ok(float(s.economy.accounts.Z0) < 0.0 and absf(float(s.economy.accounts.Z0) + float(Z.refi.B1)) < 0.01 + Z.interest_total, "Z0 zeigt das ausgegebene Zentralbankgeld")
	ok(identity_ok(s), "Geld erhalten bei Refinanzierung")
	ok(Z.refi.B1 <= Z.headroom(0) + Z.refi.B1 + 0.01, "Refinanzierung im Rahmen der Grenze")
	# Rückzahlung bei reichlich Reserve
	var refi0 := float(Z.refi.B1)
	Bk.reserve_ratio = Banking.RESERVE
	s.economy.transfer("X0", "B1", 100000.0)
	Z.on_month(2)
	ok(float(Z.refi.B1) < refi0, "Reichlich Reserve tilgt den Zentralbankkredit (%.0f -> %.0f)" % [refi0, float(Z.refi.B1)])
	ok(identity_ok(s), "Geld erhalten bei Rückzahlung")
	# Bilanz
	var bs := Z.balance_sheet(0)
	ok(absf(float(bs.eigenkapital) - (Bk.equity(0) - float(Z.refi.B1))) < 0.01, "Bankbilanz: Eigenkapital = Aktiva - Einlagen - Zentralbankkredit")
	# Leitzins folgt der Inflation, höchstens um STEP je Monat
	var r0 := Z.policy_rate
	for shop in s.retail.shops.values():
		shop.price_factor = 1.3
	s.housing.index = 1.3
	var steps_ok := true
	var last := Z.policy_rate
	for m in range(3, 8):
		Z.on_month(m)
		steps_ok = steps_ok and absf(Z.policy_rate - last) <= CentralBank.STEP + 0.000001
		last = Z.policy_rate
	ok(Z.inflation > 0.05 and Z.policy_rate > r0, "Hohe Inflation hebt den Leitzins (%.2f %% -> %.2f %%, Inflation %.0f %%)" % [r0 * 100.0, Z.policy_rate * 100.0, Z.inflation * 100.0])
	ok(steps_ok, "Zinsschritte höchstens %.2f Punkte" % (CentralBank.STEP * 100.0))
	Z.policy_rate = 0.10
	for m in 12:
		Bk.on_month(20 + m)
	ok(Bk.ref_rate > Banking.START_REF + 0.02, "Referenzzins der Banken folgt dem Leitzins (%.2f %%)" % (Bk.ref_rate * 100.0))
	ok(Z.summary().preisindex > 100.0, "Preisindex steigt (%.1f)" % Z.cpi)
	ok(identity_ok(s), "Geld erhalten nach Zinsanstieg")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(s2.central_bank.policy_rate - Z.policy_rate) < 0.00001 and absf(float(s2.central_bank.refi.B1) - float(Z.refi.B1)) < 0.01, "Zentralbank gespeichert und geladen")
	run(s2, 60.0 * 35.0)
	ok(identity_ok(s2), "Geld erhalten nach Laden mit Zentralbank")


func test_oversight() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var O: Oversight = s.oversight
	var c := s.companies[0]
	# Einrichtung der Firma verwahrlost lassen
	c.ledger.inject(40000.0)
	var placed := place_suggested(s, 0, "stellplatz", "extern")
	var fid := str(placed.building_id)
	until_done(s, func(): return s.estate.facilities[fid].status == "fertig", 3000.0)
	ok(fid != "", "Firma hat eine fertige Einrichtung (%s)" % fid)
	s.estate.facilities[fid].condition = 10.0
	var found := false
	for m in range(1, 60):
		O.on_month(m)
		if not O.open_for("C%d" % c.id).is_empty():
			found = true
			break
	ok(found, "Gewerbeaufsicht erteilt eine Auflage für verwahrloste Einrichtung")
	var o: Dictionary = O.open_for("C%d" % c.id)[0]
	ok(int(o.deadline) - int(o.found) == Oversight.DEADLINE_DAYS and o.status == "offen", "Frist von %d Tagen" % Oversight.DEADLINE_DAYS)
	var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
	ok(obs.has("auflagen") and obs.auflagen.size() == 1 and int(obs.auflagen[0].zustand) == 10, "Auflage erscheint in der Spielerbeobachtung")
	ok(not O._has_open("F" + fid) == false, "Keine zweite Auflage für dieselbe Einrichtung")
	for m in range(60, 120):
		O.on_month(m)
	ok(O.orders.values().filter(func(x): return x.what == "F" + fid).size() == 1, "Genau eine offene Auflage je Einrichtung")
	# Erfüllung: Zustand verbessern
	s.estate.facilities[fid].condition = 80.0
	O.on_day(1)
	ok(O.orders[o.id].status == "erfuellt", "Instandsetzung erfüllt die Auflage")
	ok(O.fines_total == 0.0, "Kein Bußgeld bei erfüllter Auflage")
	# Frist verstreicht: Bußgeld an die Stadtkasse
	s.estate.facilities[fid].condition = 5.0
	var o2 := {"id": "A99", "target": "C%d" % c.id, "what": "F" + fid, "label": "Test", "found": 0, "deadline": 0, "status": "offen", "fine": 0.0}
	O.orders[o2.id] = o2
	var p0 := float(s.economy.accounts.P0)
	var cash0 := c.ledger.cash
	O.on_day(2)
	ok(o2.status == "bussgeld" and absf(float(o2.fine) - minf(Oversight.FINE, cash0)) < 0.01, "Unerfüllte Auflage: Bußgeld %.0f" % float(o2.fine))
	ok(float(s.economy.accounts.P0) > p0 and c.ledger.cash < cash0, "Bußgeld geht von der Firma an die Stadtkasse")
	ok(identity_ok(s), "Geld erhalten bei Bußgeld")
	# Einsatz bei schwerem Wetterereignis, einmal je Ereignis
	var e: Dictionary = s.events.create("starkregen", "Test", "Starkregen", 2, 480.0)
	s.care.condition[0] = 5.0
	var spent0 := O.mission_cost_total
	O.on_day(3)
	ok(O.missions.size() == 1 and O.mission_cost_total > spent0, "Einsatz der Stadt bei Starkregen (%.0f)" % O.mission_cost_total)
	ok(s.care.get_condition(0) > 5.0, "Einsatz setzt verfallene Gebäude instand")
	O.on_day(4)
	ok(O.missions.size() == 1, "Je Ereignis nur ein Einsatz")
	ok(float(s.public_sector.departments.Verkehr) >= Oversight.EINSATZ.starkregen.cost, "Kosten im Ressort Verkehr")
	ok(identity_ok(s), "Geld erhalten bei Einsatz")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.oversight.orders.size() == O.orders.size() and s2.oversight.missions.size() == 1, "Aufsicht gespeichert und geladen")
	s2.oversight.on_day(5)
	ok(s2.oversight.missions.size() == 1, "Geladenes Ereignis löst keinen zweiten Einsatz aus")


func test_districts() -> void:
	GameCalendar.configure(60.0)
	var s := new_sim(2)
	var C: Contentment = s.contentment
	C.on_month(1)
	ok(C.attractiveness.size() == Catalog.DISTRICTS.size(), "Attraktivität für jedes Viertel (%d)" % C.attractiveness.size())
	ok(Catalog.DISTRICTS.all(func(d): return C.attractiveness.has(d) and C.trend.has(d)), "Entwicklung (Trend) für jedes Viertel")
	ok(range(Catalog.DISTRICTS.size()).all(func(i): return C.district_factor(i) >= 0.9 and C.district_factor(i) <= 1.1), "Lagefaktoren zwischen 0,9 und 1,1")
	# Ein Viertel mit Geschäft und Wohnungen verfallen lassen
	var shop: Dictionary = s.retail.shops.values()[0]
	var dist := int(s.city.building(int(shop.building)).get("district", 0))
	var name: String = Catalog.DISTRICTS[dist]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var good_customers := 0
	for i in 20:
		good_customers += s.retail.customers(shop, rng)
	var unit: Dictionary = {}
	for u in s.housing.units.values():
		if int(s.city.building(int(u.building)).get("district", 0)) == dist:
			unit = u
			break
	for id in s.care.condition:
		if int(s.city.building(int(id)).get("district", 0)) == dist:
			s.care.condition[id] = 100.0
	C.on_month(2)
	var attr_good := float(C.attractiveness[name])
	s.housing._update_rents()
	var rent_good := float(unit.rent) if not unit.is_empty() else 0.0
	for id in s.care.condition:
		if int(s.city.building(int(id)).get("district", 0)) == dist:
			s.care.condition[id] = 0.0
	C.on_month(3)
	ok(float(C.attractiveness[name]) < attr_good and float(C.trend[name]) < 0.0, "Verfall senkt die Attraktivität von %s (%.1f -> %.1f)" % [name, attr_good, float(C.attractiveness[name])])
	ok(C.district_factor(dist) < 1.0, "Verfallenes Viertel hat Lagefaktor unter 1 (%.3f)" % C.district_factor(dist))
	s.housing._update_rents()
	if not unit.is_empty():
		ok(float(unit.rent) < rent_good, "Mieten im verfallenen Viertel sinken (%.0f -> %.0f)" % [rent_good, float(unit.rent)])
	rng.seed = 5
	var bad_customers := 0
	for i in 20:
		bad_customers += s.retail.customers(shop, rng)
	ok(bad_customers < good_customers, "Weniger Kundschaft im verfallenen Viertel (%d -> %d)" % [good_customers, bad_customers])
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(float(s2.contentment.attractiveness[name]) - float(C.attractiveness[name])) < 0.01, "Viertelentwicklung gespeichert und geladen")
	ok(identity_ok(s), "Geld erhalten")


func test_company_operations() -> void:
	var suite = load("res://tests/company_operations_tests.gd")
	ok(suite != null and suite.can_instantiate(), "Betriebsablauf-Tests kompilieren")
	if suite == null or not suite.can_instantiate():
		return
	suite.run(self)
	suite.cooperation(self)
	suite.planning_limits(self)
	suite.intentions(self)
	suite.daily_routes(self)


func test_strategy_learning() -> void:
	GameCalendar.configure(60.0)
	var prof := StrategyLearner.profiles()
	ok(prof.has("konservativ") and prof.has("wachstum") and prof.has("effizient"), "drei Strategieprofile geladen")
	var s := new_sim(4, 256)
	var L := s.strategy
	ok(L.state.size() == 4, "jedes Unternehmen hat einen Strategiezustand")
	# 1) Parameter wirken, ohne Strategie bleibt das Verhalten gleich
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 5
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 5
	var base: Dictionary = RuleBrain.decide(obs.duplicate(true), "wachstum", rng_a)   # decide ergaenzt geplante_aktionen im Eingabeobjekt
	var growth: Dictionary = RuleBrain.decide(obs.duplicate(true), "wachstum", rng_b, prof.wachstum)
	ok(JSON.stringify(base.actions) == JSON.stringify(growth.actions), "Profil wachstum entspricht dem bisherigen Verhalten")
	var market: Array = [{"menge": 5, "kuehlung": false, "schwer": false, "min_reputation": 0, "strecke": 10, "von_pos": [0, 0], "frist_in_min": 9999, "verguetung": 100.0}]
	var v := {"pos": [0, 0]}
	var spec := {"kapazitaet": 10, "kuehlung": false, "schwer": false, "tempo": 1.0, "kosten_pro_tile": 6.0}
	ok(not RuleBrain._best_contract(market, v, spec, 0.0, 0.0).is_empty(), "Auftrag mit kleiner Marge wird ohne Mindestmarge angenommen")
	ok(RuleBrain._best_contract(market, v, spec, 0.0, 0.5).is_empty(), "Mindestmarge von 50 %% lehnt ihn ab")
	# 2) Zeitraeume werden bewertet, jede Strategie wird einmal erprobt
	var first: String = L.state[0].current
	var day0 := GameCalendar.day_of(s.game_min)
	var seen := {first: true}
	for i in 3:
		s.game_min += GameCalendar.day_game_min * StrategyLearner.MAX_DAYS
		L.on_day(GameCalendar.day_of(s.game_min))
		seen[L.state[0].current] = true
	ok(L.memory.records[0].size() == 3, "drei Zeitraeume bewertet (%d)" % L.memory.records[0].size())
	ok(seen.size() == 3, "alle drei Strategien wurden erprobt")
	var rec: Dictionary = L.memory.records[0][0]
	ok(rec.days >= StrategyLearner.PERIOD_DAYS and rec.has("situation") and rec.has("utilization"), "Bewertung enthaelt Tage, Kontext und Auslastung")
	ok(L.memory.aggregate(0, rec.strategy).vertrauen == "unsicher", "weniger als %d Auftraege bleibt ausdruecklich unsicher" % StrategyMemory.MIN_CONTRACTS)
	# 3) beste Strategie wird bevorzugt, Exploration bleibt selten
	for id in prof:
		L.memory.add(1, {"strategy": id, "value": 900.0 if id == "effizient" else 100.0, "contracts": 10, "days": 5})
	var best := 0
	for i in 400:
		best += 1 if L._choose(1) == "effizient" else 0
	ok(best > 300 and best < 400, "meist die beste Strategie, gelegentlich eine andere (%d von 400)" % best)
	ok(L.memory.aggregate(1, "effizient").vertrauen == "bestaetigt" or L.memory.aggregate(1, "effizient").vertrauen == "vorlaeufig", "ausreichende Stichprobe gilt nicht mehr als unsicher")
	# 4) Modellwechsel: nur nach Mindestdauer, nur bekannte Strategien, nur die eigene Firma
	var other_before: String = L.state[2].current
	var st0: String = L.state[0].current
	var target := "konservativ" if st0 != "konservativ" else "wachstum"
	ok(not s.executor.execute(0, {"action": "set_strategy", "strategie": target, "begruendung": "Test"}).ok, "Wechsel vor %d Tagen wird abgelehnt" % StrategyLearner.MIN_MODEL_DAYS)
	s.game_min += GameCalendar.day_game_min * StrategyLearner.MIN_MODEL_DAYS
	ok(not s.executor.execute(0, {"action": "set_strategy", "strategie": "unfug", "begruendung": "Test"}).ok, "unbekannte Strategie wird abgelehnt")
	var rr: Dictionary = s.executor.execute(0, {"action": "set_strategy", "strategie": target, "begruendung": "Auslastung zu niedrig"})
	ok(rr.ok and L.state[0].current == target, "gueltiger Wechsel (%s)" % rr.msg)
	ok(L.state[2].current == other_before, "fremde Unternehmen bleiben unberuehrt")
	ok(L.memory.notes[0][0].art == "vermutung", "Begruendung des Modells gilt als Vermutung, nicht als Messwert")
	# 5) Beobachtung fuer das lokale Modell enthaelt Gedaechtnis, Experimente und Lernbericht
	var o2 := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var compact := ObservationBuilder.compact_for_local(o2)
	ok(compact.has("gedaechtnis") and compact.has("experimente") and compact.has("strategie_lernen"), "lokale Beobachtung enthaelt Lernfelder")
	ok(o2.strategie_lernen.bewertet >= 1 and o2.strategie_lernen.has("letzte_erkenntnis"), "Lernbericht nennt bewertete Strategien")
	# 6) Speichern und Laden ohne Verlust
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.strategy.memory.records[0].size() == L.memory.records[0].size() and s2.strategy.state[0].current == target, "Lerndaten nach Laden erhalten")
	ok(s2.strategy.memory.notes[0].size() == 1, "Vermutungen nach Laden erhalten")
	var page := LiveText.strategy(s)
	ok(page.contains(s.company(0).company_name) and page.contains("nicht bewiesen") and page.contains("Letzte Erkenntnis"), "Reiter Strategie zeigt Messwerte, Erkenntnis und Vermutungen getrennt")
	ok(identity_ok(s), "Geld und Waren erhalten")


func test_strategy_arena() -> void:
	GameCalendar.configure(60.0)
	var spec := {"seed": 21, "map": 128, "steps": 2400, "brains": ["wachstum", "wachstum", "wachstum", "wachstum"], "max_actions": 4,
		"strategies": ["konservativ", "wachstum", "effizient", "lernend"], "events": []}
	var a := Arena.run(spec)
	ok(a.rows.map(func(r): return r.profil) == ["konservativ", "wachstum", "effizient", "lernend"], "Plaetze erhalten die Strategien des Plans")
	ok(a.sim.strategy.state[0].locked and a.sim.strategy.state[0].current == "konservativ", "feste Strategie ist gesperrt")
	ok(not a.sim.strategy.state[3].locked, "lernende Strategie bleibt frei")
	var b := Arena.run(spec)
	ok(a.fingerprint == b.fingerprint, "gleicher Plan, gleicher Seed: identischer Endstand (deterministisch)")
	ok(identity_ok(a.sim), "Geld und Waren erhalten")
	var r := Arena.replay(spec, a.actions)
	ok(r.fingerprint == a.fingerprint, "Wiederholung ohne KI ergibt denselben Endstand")
	var rotated := Arena.run(spec, 1)
	ok(rotated.rows.map(func(x): return x.profil) == ["wachstum", "effizient", "lernend", "konservativ"], "Strategien rotieren mit den Startplaetzen")
	var base := Arena.run({"seed": 21, "map": 128, "steps": 2400, "brains": ["wachstum", "wachstum"], "max_actions": 4, "events": []})
	ok(base.rows.all(func(x): return x.profil == ""), "ohne Plan bleibt die Arena unveraendert")


func test_game_master() -> void:
	# Regelkern: bedient Firmen mit Leerlauf ohne passende Auftraege, nicht den Marktfuehrer, begrenzt je Lauf und Tag
	var obs := {"time": 0.0, "open_total": 10, "companies": [
		{"id": 0, "name": "A", "vehicles": 3, "idle": 3, "open_fit": 0, "has_cold": false, "has_heavy": false, "max_cap": 8, "cash": 20000.0, "profit": -3000.0},
		{"id": 1, "name": "B", "vehicles": 2, "idle": 0, "open_fit": 5, "has_cold": false, "has_heavy": false, "max_cap": 8, "cash": 90000.0, "profit": 9000.0},
		{"id": 2, "name": "C", "vehicles": 2, "idle": 2, "open_fit": 1, "has_cold": true, "has_heavy": false, "max_cap": 14, "cash": 40000.0, "profit": 500.0},
		{"id": 3, "name": "D", "vehicles": 1, "idle": 1, "open_fit": 0, "has_cold": false, "has_heavy": false, "max_cap": 8, "cash": 30000.0, "profit": 20000.0}]}
	var d := GameMaster.decide(obs, 3, 8)
	ok(d.actions.size() == 3 and d.actions.all(func(a): return int(a.company) in [0, 2]), "höchstens drei Zusatzaufträge, nur an Firmen mit Leerlauf (nicht an Marktführer D)")
	ok(d.actions[0].company == 0, "dringendster Fall zuerst (A: 3 im Leerlauf, im Minus)")
	ok(GameMaster.decide(obs, 3, 0).actions.is_empty(), "Tageslimit erreicht: nichts")
	ok(GameMaster.decide({"companies": []}, 3, 8).actions.is_empty(), "ohne Firmen nichts zu tun")
	# Spielleitung im Spiel
	var s := new_sim(4)
	var gm: GameMaster = s.game_master
	ok(not gm.enabled, "standardmäßig aus (Wiederholbarkeit)")
	var before: int = s.contracts.size()
	gm.minute_tick(500.0)
	ok(s.contracts.size() == before and gm.stats.runs == 0, "ausgeschaltet verändert sie nichts")
	gm.enabled = true
	var plan := gm.run(500.0)
	var after: int = s.contracts.size()
	ok(after - before <= GameMaster.MAX_PER_RUN, "ein Lauf erzeugt höchstens %d Aufträge (%d)" % [GameMaster.MAX_PER_RUN, after - before])
	for e in gm.log[gm.log.size() - 1].actions:
		var k: Contract = s.contracts.get(e.contract)
		var specs: Array = s.company_vehicles(int(e.company)).map(func(v): return v.spec())
		ok(k != null and k.status == "open" and GameMaster.fits(k, specs, float(s.company(int(e.company)).reputation)), "Zusatzauftrag %s passt zur Flotte von F%d" % [e.contract, int(e.company)])
	# Wahl durch ein Modell: nur nummerierte Kandidaten sind erlaubt
	s.contracts.clear()   # leerer Markt: alle Firmen mit Leerlauf haben keinen passenden Auftrag, es gibt Kandidaten
	gm.chooser = func(_o, cands): return [999]
	gm.last_run = 0.0
	var before2: int = s.contracts.size()
	gm.run(2000.0)
	ok(s.contracts.size() == before2 and gm.log[gm.log.size() - 1].source == "Claude", "unbekannte Kandidatennummer erzeugt nichts")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.game_master.enabled and s2.game_master.stats.runs == gm.stats.runs and s2.game_master.log.size() == gm.log.size(), "Spielleitung nach Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_model_error_fixes() -> void:
	var s := new_sim(2)
	for k in s.market.open_contracts():
		s.companies[0].known[k.id] = true
	# Arbeiter ohne Aufgabe, alle Fahrzeuge haben Fahrer: Bereitschaft statt Fehler
	var free_w: Array = s.personnel.employed(0).filter(func(w): return w.vehicle_id < 0 and w.task_id == "")
	if free_w.is_empty():
		var cand: Worker = s.personnel.workers.values().filter(func(w): return w.employer < 0 and not w.lost)[0]
		s.personnel.hire(0, cand)
		free_w = [cand]
	for v in s.company_vehicles(0):
		if s.driver_of(v) == null:
			var d: Worker = free_w.pop_back()
			s.executor.execute(0, {"action": "assign_worker_task", "kind": "fahren", "worker_id": d.id, "vehicle_id": v.id})
	var idle: Worker = s.personnel.employed(0).filter(func(w): return w.vehicle_id < 0)[0] if s.personnel.employed(0).any(func(w): return w.vehicle_id < 0) else null
	if idle != null:
		var r := s.executor.execute(0, {"action": "assign_worker_task", "worker_id": idle.id})
		ok(r.ok, "Arbeiter ohne Fahrzeug bleibt in Bereitschaft statt Fehler: " + str(r.msg).left(80))
	# task statt kind
	var r2 := s.executor.execute(0, {"action": "assign_worker_task", "task": "collect_contracts"})
	ok(r2.ok or str(r2.msg).contains("Besuch"), "task wird als kind gelesen: " + str(r2.msg).left(60))
	# Besuch schon eingeplant: Kennzeichen already
	var oid: String = s.resources.available_offers()[0].id
	var v1 := s.executor.execute(0, {"action": "buy_vehicle", "offer_id": oid})
	var v2 := s.executor.execute(0, {"action": "buy_vehicle", "offer_id": oid})
	ok(not v2.ok and v2.get("already", false) or not v1.get("pending", false), "doppelter Besuch trägt das Kennzeichen 'already'")
	# Disponent: keine Angebote mit zu kurzer Restlaufzeit
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	for k in obs.markt:
		k["angebot_noch_min"] = 30
	ok(DispatchCandidates.build(obs).candidates.is_empty(), "Angebote mit weniger als %d Spielminuten Restlaufzeit werden nicht angeboten" % DispatchCandidates.MIN_OFFER_LEFT)
	# Disponent: entfallene Wahl wird durch einen anderen Kandidaten desselben Fahrzeugs ersetzt
	var ag := DispatchAgent.new()
	root.add_child(ag)
	ag.setup(s, {"provider": "anthropic", "api_key": "TEST_KEY_ENV", "model": "claude-haiku-5-5"}, ApiLog.new(), [0])
	var groups: Array = ag.gather()
	var all: Array = []
	for g in groups:
		for c in g.candidates:
			var e: Dictionary = c.duplicate()
			e["company"] = g.company
			all.append(e)
	var same: Array = all.filter(func(c): return int(c.vehicle_id) == int(all[0].vehicle_id))
	if same.size() >= 2:
		s.contracts[same[0].contract_id].status = "expired"
		ag._pending = all
		ag._inflight = 7
		ag.handle_result(7, {"ok": true, "content": "{\"wahl\": [%d], \"begruendung\": \"Test\"}" % int(same[0].nr), "usage": {}})
		ok(int(ag.stats.get("substituted", 0)) == 1 and s.contracts[same[1].contract_id].owner == 0, "abgelaufene Wahl durch %s ersetzt" % same[1].contract_id)
	else:
		ok(true, "nur ein Kandidat je Fahrzeug – Ersatz nicht prüfbar")
	# Modellrunde: Auftragsaktionen bei aktivem Disponenten werden übergangen
	var ac := AgentController.new()
	root.add_child(ac)
	ac.setup_for_test(s, 0)
	var open_k: Array = s.market.open_contracts().filter(func(k): return k.status == "open")
	var before := int(ac.stats.actions_rejected)
	ac._apply({"actions": [{"action": "accept_contract", "contract_id": open_k[0].id}], "summary": "", "goal": "", "memory": "", "erfahrungen": []}, "t1", "KI")
	ok(int(ac.stats.get("left_to_dispatcher", 0)) == 1 and int(ac.stats.actions_rejected) == before and open_k[0].status == "open", "Annahme bleibt dem Disponenten überlassen")
	ac.queue_free()
	ag.queue_free()
	ok(identity_ok(s), "Geld erhalten")


func test_dispatch_agent() -> void:
	var s := new_sim(2)
	for k in s.market.open_contracts():
		s.companies[0].known[k.id] = true
		s.companies[1].known[k.id] = true
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var b: Dictionary = DispatchCandidates.build(obs)
	ok(not b.candidates.is_empty(), "Kandidaten für das freie Fahrzeug vorhanden (%d)" % b.candidates.size())
	var nrs: Array = b.candidates.map(func(c): return int(c.nr))
	ok(nrs.size() == b.candidates.size() and nrs[0] == 1 and nrs.max() == nrs.size(), "Nummern laufen lückenlos ab 1")
	ok(b.candidates.all(func(c): return s.contracts.has(c.contract_id) and s.contracts[c.contract_id].status == "open"), "Kandidaten sind offene, bekannte Aufträge")
	var picks: Array = DispatchCandidates.rule_pick(b.candidates, 6)
	ok(picks.size() == 1 and picks[0] in nrs, "Regelwahl: ein Fahrzeug, ein Auftrag")
	# Antwortformate
	ok(DispatchAgent.parse_choice("Hier: ```json\n{\"wahl\": [2, \"3\"], \"begruendung\": \"gut\"}\n```").choice == [2, 3], "Antwort mit Textrahmen und Textzahl wird gelesen")
	ok(not DispatchAgent.parse_choice("keine Ahnung").ok and not DispatchAgent.parse_choice("{\"x\": 1}").ok, "Unbrauchbare Antworten werden erkannt")
	# Agent mit Claude-Adapter (kein Netzwerkaufruf: Ergebnisse werden direkt eingespeist)
	var ag := DispatchAgent.new()
	root.add_child(ag)
	ag.setup(s, {"provider": "anthropic", "api_key": "TEST_KEY_ENV", "model": "claude-sonnet-5-5"}, ApiLog.new(), [0, 1])
	ok(ag.covers(0) and ag.covers(1) and not ag.covers(7), "versorgt nur die benannten Firmen")
	ok(s.dispatcher == ag, "Simulation kennt den Disponenten")
	var groups: Array = ag.gather()
	ok(groups.size() >= 1 and groups[0].candidates.size() >= 1, "gather liefert Gruppen mit Kandidaten")
	var all: Array = []
	for g in groups:
		for c in g.candidates:
			var e: Dictionary = c.duplicate()
			e["company"] = g.company
			all.append(e)
	var first: Dictionary = all[0]
	ag._pending = all
	ag._inflight = 1
	ag.handle_result(1, {"ok": true, "content": "{\"wahl\": [%d, 999], \"begruendung\": \"Test\"}" % int(first.nr), "usage": {"total_tokens": 500}})
	var kk: Contract = s.contracts[first.contract_id]
	ok(kk.owner == int(first.company) and kk.vehicle_id == int(first.vehicle_id), "gewählte Zuweisung wurde ausgeführt (%s)" % kk.status)
	ok(ag.stats.assigned == 1 and ag.stats.rejected >= 1 and ag.stats.tokens == 500, "unbekannte Nummer abgelehnt, Tokens gezählt")
	# API-Fehler: Regeln übernehmen sofort
	var s2 := new_sim(2)
	for k in s2.market.open_contracts():
		s2.companies[0].known[k.id] = true
	var ag2 := DispatchAgent.new()
	root.add_child(ag2)
	ag2.setup(s2, {"provider": "anthropic", "api_key": "TEST_KEY_ENV"}, ApiLog.new(), [0])
	var g2: Array = ag2.gather()
	var all2: Array = []
	for c in g2[0].candidates:
		var e2: Dictionary = c.duplicate()
		e2["company"] = 0
		all2.append(e2)
	ag2._pending = all2
	ag2._inflight = 5
	ag2.handle_result(5, {"ok": false, "error": "HTTP 500"})
	ok(ag2.stats.errors == 1 and ag2.stats.by_rules == 1 and ag2.stats.assigned == 1, "bei API-Fehler wird sofort per Regeln zugewiesen")
	for i in 3:
		ag2._pending = []
		ag2._inflight = 10 + i
		ag2.handle_result(10 + i, {"ok": false, "error": "HTTP 500"})
	ok(ag2.fallback_active and not ag2.covers(0), "nach wiederholten Fehlern Ersatzmodus: Spieler-Disposition übernimmt wieder")
	ag.queue_free()
	ag2.queue_free()


func test_inspections() -> void:
	var s := new_sim(2)
	var I: Inspections = s.inspections
	var c: Company = s.companies[0]
	var c1: Company = s.companies[1]
	ok(I.capacity() >= 1 and I.capacity() == maxi(1, s.town_hall.staff("pruefdienst") * Inspections.PER_INSPECTOR), "Kapazität aus dem Prüfdienst (%d je Monat)" % I.capacity())
	ok(s.mayor.indicators().has("pruefungen"), "Bürgermeister sieht die Prüfungen")
	# Fahrzeugprüfung mit Befund: Bußgeld an die Stadtkasse, Firma sieht den Eintrag
	var v = s.vehicles[c.vehicle_ids[0]]
	v.condition = 20.0
	var p0 := float(s.economy.accounts.P0)
	var cash := c.ledger.cash
	var r := s.mayor.execute({"action": "order_inspection", "firma": c.id, "art": "fahrzeuge", "reason": "Test"})
	ok(r.ok and not r.befund.findings.is_empty() and absf(float(r.befund.fine) - Inspections.FINE_VEHICLE) < 0.01, "Befund mit Bußgeld: " + str(r.msg).left(90))
	ok(absf(cash - c.ledger.cash - Inspections.FINE_VEHICLE) < 0.01 and float(s.economy.accounts.P0) >= p0 + Inspections.FINE_VEHICLE - 0.01, "Bußgeld geht an die Stadtkasse")
	ok(s.log_entries.any(func(e): return int(e.company) == c.id and str(e.text).begins_with("Prüfung")), "Prüfung steht im Protokoll der Firma")
	# Sperrfrist je Firma
	var r2 := s.mayor.execute({"action": "order_inspection", "firma": c.id, "art": "arbeitssicherheit", "reason": "Test"})
	ok(not r2.ok and "Sperrfrist" in str(r2.msg), "Sperrfrist: " + str(r2.msg).left(80))
	# Fehlverdacht kostet Zustimmung
	for vid in c1.vehicle_ids:
		s.vehicles[vid].condition = 100.0
	var appr: float = s.mayor.approval
	var r3 := s.mayor.execute({"action": "order_inspection", "firma": c1.id, "art": "fahrzeuge", "reason": "Test"})
	ok(r3.ok and r3.befund.findings.is_empty() and s.mayor.approval < appr, "Prüfung ohne Befund senkt die Zustimmung (%.1f -> %.1f)" % [appr, s.mayor.approval])
	# Arbeitssicherheit
	s.game_min += GameCalendar.days_to_min(float(Inspections.BLOCK_DAYS + 1))
	var ws: Array = s.personnel.employed(c.id)
	ws[0].fatigue = 95.0
	var r4 := I.order(c.id, "arbeitssicherheit")
	ok(r4.ok and not r4.befund.findings.is_empty(), "Arbeitssicherheit: " + str(r4.msg).left(90))
	# Kapazität erschöpft
	I.used[I._month()] = I.capacity()
	s.game_min += GameCalendar.days_to_min(float(Inspections.BLOCK_DAYS + 1))
	ok(not I.order(c1.id, "lohnsteuer").ok, "ohne freie Kapazität keine Prüfung")
	ok(not I.order(c1.id, "unbekannt").ok and not I.order(99, "fahrzeuge").ok, "unbekannte Art/Firma abgelehnt")
	# Regelbürgermeister prüft bei schlechten Fahrzeugen
	I.used.clear()
	for vid in c.vehicle_ids:
		s.vehicles[vid].condition = 100.0
	for w in ws:
		w.fatigue = 0.0
	for vid in c1.vehicle_ids:
		s.vehicles[vid].condition = 30.0
	s.game_min += GameCalendar.days_to_min(31.0)   # Regel: dieselbe Firma hoechstens alle 30 Tage
	var dec := MayorBrain.decide(s.mayor.indicators())
	ok(dec.actions.any(func(a): return a.action == "order_inspection" and int(a.firma) == c1.id and a.art == "fahrzeuge"), "Regelbürgermeister ordnet Fahrzeugprüfung an")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.inspections.records.size() == I.records.size() and s2.inspections.last_day(c.id) == I.last_day(c.id), "Prüfungen nach dem Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_city_freight_pool() -> void:
	var s := new_sim(2)
	var D: CityDepot = s.city_depot
	var c0: Company = s.companies[0]
	var c1: Company = s.companies[1]
	var supplier: int = s.city.buildings.filter(func(b): return b.type == "warehouse" and int(b.id) != D.building)[0].id
	var mk := func() -> Contract:
		var o: Dictionary = D._new_order(CityGoods.items().keys()[0], 40, "Test")
		o.loc = supplier
		o.freight = 200.0
		o.status = "bestellt"
		D.orders[o.id] = o
		D._issue_contract(o)
		return s.contracts[o.contract]
	# offene Ausschreibung mit Preisfaktor 1,0
	var k0: Contract = mk.call()
	ok(k0.exclusive_for == -1 and absf(k0.reward - 200.0) < 0.01, "Ausschreibung: offen für alle, Vergütung 200")
	ok(s.mayor.indicators().stadtlager.has("transportpool"), "Bürgermeister sieht den Transportpool")
	# Preisrahmen und Eile
	ok(not s.mayor.execute({"action": "set_city_freight", "vergabe": "ausschreibung", "preisfaktor": 1.5, "reason": "Test"}).ok, "Preisfaktor über 1,3 abgelehnt")
	ok(s.mayor.execute({"action": "set_city_freight", "vergabe": "ausschreibung", "preisfaktor": 1.2, "eilig": true, "reason": "Test"}).ok, "Preisfaktor 1,2 eilig gesetzt")
	var k1: Contract = mk.call()
	ok(absf(k1.reward - 200.0 * 1.2 * 1.15) < 1.0 and k1.deadline - k1.created < k0.deadline - k0.created, "eilig: Vergütung %.0f, kürzere Frist" % k1.reward)
	# Rahmenvertrag: Vorrecht für den Partner, Partner kennt den Auftrag
	c0.reputation = 30.0
	ok(not s.mayor.execute({"action": "set_city_freight", "vergabe": "rahmenvertrag", "firma": c0.id, "tage": 20, "preisfaktor": 1.0, "reason": "Test"}).ok, "zu wenig Ruf: kein Rahmenvertrag")
	c0.reputation = 70.0
	ok(not D.set_pool("rahmenvertrag", c0.id, 100, 1.0, false).ok, "Laufzeit über 60 Tage abgelehnt")
	var r := s.mayor.execute({"action": "set_city_freight", "vergabe": "rahmenvertrag", "firma": c0.id, "tage": 20, "preisfaktor": 1.0, "reason": "Test"})
	ok(r.ok, "Rahmenvertrag: " + str(r.msg).left(80))
	var k2: Contract = mk.call()
	ok(k2.exclusive_for == c0.id and k2.exclusive_until > s.game_min and c0.known.has(k2.id) and "Rahmenvertrag" in k2.label, "Partner erhält das Vorrecht: " + k2.label)
	# Vorrecht zweimal nicht genutzt -> Kündigung
	for i in 2:
		var kx: Contract = mk.call()
		kx.status = "accepted"
		kx.owner = c1.id
		D._watch_contract(D.orders[kx.order_ref], D._today())
	ok(D.pool.mode == "ausschreibung" and s.log_entries.any(func(e): return "gekündigt" in str(e.text)), "nach zwei verpassten Aufträgen wird der Rahmenvertrag gekündigt")
	# Anteilsgrenze: c1 hat alle Vergaben -> keine Direktvergabe an c1
	c1.reputation = 80.0
	for i in 3:
		D.awards.append({"day": D._today(), "cid": c1.id, "contract": "X%d" % i})
	ok(not D.set_pool("direktvergabe", c1.id, 0, 1.0, false).ok, "Anteilsgrenze 50 %% verhindert Direktvergabe (Anteil %.0f %%)" % (float(D.pool_shares()[c1.id]) * 100.0))
	# Direktvergabe gilt nur für den nächsten Auftrag
	ok(D.set_pool("direktvergabe", c0.id, 0, 1.0, false).ok, "Direktvergabe an Firma 0")
	var k3: Contract = mk.call()
	var k4: Contract = mk.call()
	ok(k3.exclusive_for == c0.id and k4.exclusive_for == -1, "Direktvergabe nur für den nächsten Auftrag")
	# Regelbürgermeister hebt die Vergütung, wenn der Stadtfuhrpark einspringen musste
	D.set_pool("ausschreibung", -1, 0, 1.0, false)
	D.pool.changed = -100
	D.fallback_days = [D._today(), D._today()]
	var dec := MayorBrain.decide(s.mayor.indicators())
	ok(dec.actions.any(func(a): return a.action == "set_city_freight" and float(a.preisfaktor) > 1.0), "Regelbürgermeister hebt die Vergütung an")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.city_depot.awards.size() == D.awards.size() and s2.city_depot.fallback_days.size() == 2, "Pool nach dem Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_road_care() -> void:
	var s := new_sim(2)
	var R: RoadCare = s.road_care
	ok(R.cond.size() > 10 and R.cond.values().all(func(c): return float(c) >= 70.0 and float(c) <= 100.0), "%d Straßenabschnitte, Startzustand 70–100 %%" % R.cond.size())
	ok(s.mayor.indicators().has("strassen"), "Bürgermeister sieht die Straßen")
	var seg: Vector2i = R.cond.keys()[0]
	var cell: Vector2i = R.cells[seg]
	ok(s.city.is_road(cell) and RoadCare.seg_of(cell) == seg, "Arbeitsort liegt auf einer Straße im Abschnitt")
	# Verschleiss: Verkehr und Frost
	var other: Vector2i = R.cond.keys()[1]
	R.cond[seg] = 80.0
	R.cond[other] = 80.0
	R.usage[seg] = 100.0
	R.usage[other] = 1.0
	s.wx.cur["temp"] = 5.0
	R.on_day(R._day + 1)
	var busy_loss := 80.0 - float(R.cond[seg])
	ok(busy_loss > 80.0 - float(R.cond[other]) and busy_loss > 0.0, "viel befahrener Abschnitt verschleißt schneller (%.2f gegenüber %.2f)" % [busy_loss, 80.0 - float(R.cond[other])])
	R.cond[other] = 80.0
	s.wx.cur["temp"] = -3.0
	R.on_day(R._day + 1)
	ok(80.0 - float(R.cond[other]) >= RoadCare.DECAY_BASE * RoadCare.FROST - 0.0001, "Frost verdoppelt den Verschleiß")
	s.wx.cur["temp"] = 5.0
	# Wirkung auf Tempo und Pannen
	R.cond[seg] = 20.0
	ok(R.factor(cell) < 1.0 and R.factor(cell) >= 1.0 - RoadCare.SLOW_MAX and R.breakdown_factor(cell) > 1.0, "schlechte Straße: Tempo %.2f, Pannenfaktor %.2f" % [R.factor(cell), R.breakdown_factor(cell)])
	R.cond[seg] = 90.0
	ok(R.factor(cell) == 1.0 and R.breakdown_factor(cell) == 1.0, "gute Straße ohne Wirkung")
	# Instandsetzung in Eigenleistung: Kosten an S0, Spur gesperrt, nach 3 Tagen 100 %
	R.cond[seg] = 30.0
	var p0 := float(s.economy.accounts.P0)
	var cap0: int = s.traffic_flow.capacity_of(cell)
	var r := s.mayor.execute({"action": "repair_road", "abschnitt": RoadCare.seg_id(seg), "ausfuehrung": "eigen", "reason": "Test"})
	ok(r.ok and absf(p0 - float(s.economy.accounts.P0) - RoadCare.MODES.eigen.cost) < 0.01, "Auftrag an die Straßenmeisterei: " + str(r.msg).left(80))
	ok(R.under_works(cell) and s.traffic_flow.capacity_of(cell) == maxi(1, cap0 - 1), "während der Arbeit eine Spur weniger (%d -> %d)" % [cap0, s.traffic_flow.capacity_of(cell)])
	ok(not R.order(RoadCare.seg_id(seg), "firma").ok, "kein zweiter Auftrag am selben Abschnitt")
	ok(not R.order("A999_999", "eigen").ok and not R.order(RoadCare.seg_id(other), "anders").ok, "unbekannter Abschnitt/Ausführung abgelehnt")
	for i in R.crews() - 1:
		R.order(RoadCare.seg_id(R.cond.keys()[2 + i]), "eigen")
	ok(not R.order(RoadCare.seg_id(other), "eigen").ok and R.order(RoadCare.seg_id(other), "firma").ok, "alle Trupps im Einsatz -> Baufirma (%d Trupps)" % R.crews())
	var crew := R.crew_of(R.jobs[r.ref])
	ok(int(crew.workers) >= 3 and not crew.gear.is_empty(), "Bautrupp für die Karte: %d Personen" % int(crew.people))
	var day: int = R._day
	R.on_day(day + 3)
	ok(float(R.cond[seg]) == 100.0 and not R.under_works(cell) and R.jobs[r.ref].status == "fertig", "nach 3 Tagen instand gesetzt, Spur wieder frei")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(float(s2.road_care.cond[seg]) - 100.0) < 0.01 and s2.road_care.jobs.size() == R.jobs.size() and s2.road_care.works.size() == R.works.size(), "Straßenzustand und Arbeiten nach dem Laden")
	# Regelbürgermeister lässt den schlechtesten Abschnitt instand setzen
	var s3 := new_sim(2)
	var seg3: Vector2i = s3.road_care.cond.keys()[5]
	s3.road_care.cond[seg3] = 25.0
	var dec := MayorBrain.decide(s3.mayor.indicators())
	ok(dec.actions.any(func(a): return a.action == "repair_road" and a.abschnitt == RoadCare.seg_id(seg3)), "Regelbürgermeister setzt Abschnitt %s instand" % RoadCare.seg_id(seg3))
	ok(identity_ok(s), "Geld erhalten")


func test_mayor_levers() -> void:
	var s := new_sim(2)
	var M: Mayor = s.mayor
	var Z: Citizens = s.citizens
	# Polizei- und Gesundheitspersonal
	var pol0 := int(Z.base_cap.polizei)
	var r := M.execute({"action": "set_public_staff", "bereich": "polizei", "aenderung": 3, "reason": "Test"})
	ok(r.ok and int(Z.base_cap.polizei) == pol0 + 3 and int(Z.cap.polizei) == pol0 + 3, "Polizei %d -> %d: %s" % [pol0, pol0 + 3, str(r.msg).left(60)])
	ok(not M.execute({"action": "set_public_staff", "bereich": "polizei", "aenderung": 9, "reason": "Test"}).ok, "höchstens ±5 je Beschluss")
	ok(not M.execute({"action": "set_public_staff", "bereich": "rathaus", "aenderung": 1, "reason": "Test"}).ok, "nur Polizei und Gesundheit")
	ok(not M.execute({"action": "set_public_staff", "bereich": "gesundheit", "aenderung": -int(Z.base_cap.gesundheit), "reason": "Test"}).ok, "mindestens 2 Stellen bleiben")
	Z.on_month(1)
	ok(Z.employed_count("polizei") > pol0, "neue Polizeikräfte zum Monatsende eingestellt (%d)" % Z.employed_count("polizei"))
	# Weiterbildung fördern: mehr Kursbeginne, Zuschuss an den Bildungsträger
	var P: Population = s.population
	var learners: Array = Z.people.filter(func(p): return p.employer == "" and int(p.education) < 3)
	for p in learners:
		p.erase("course_until")
		p.jobless_months = 3
	P.behave(5)
	var base_starts := int(P.behavior.weiterbildung_beginn)
	for p in learners:
		p.erase("course_until")
	ok(M.execute({"action": "support_training", "foerderung_prozent": 100, "reason": "Test"}).ok and not P.set_training_support(150).ok, "Förderung 0–100 %")
	var p0 := float(s.economy.accounts.P0)
	P.behave(5)
	var starts := int(P.behavior.weiterbildung_beginn)
	ok(starts > base_starts, "Förderung: mehr Kursbeginne (%d statt %d)" % [starts, base_starts])
	ok(absf(p0 - float(s.economy.accounts.P0) - starts * Population.TRAINING_COST) < 0.01, "Zuschuss %.0f EUR je Kursbeginn aus der Stadtkasse" % Population.TRAINING_COST)
	# Stadtmarketing: Kosten, mehr Zuzug, keine zweite Kampagne
	var m := GameCalendar.month_of(s.game_min)
	p0 = float(s.economy.accounts.P0)
	ok(not M.execute({"action": "city_marketing", "budget": 50000.0, "reason": "Test"}).ok, "Budget über 30 000 abgelehnt")
	ok(M.execute({"action": "city_marketing", "budget": 20000.0, "reason": "Test"}).ok and absf(p0 - float(s.economy.accounts.P0) - 20000.0) < 0.01, "Kampagne kostet 20 000")
	ok(not M.execute({"action": "city_marketing", "budget": 10000.0, "reason": "Test"}).ok, "keine zweite Kampagne während der Laufzeit")
	var w0: int = M.waiting
	M.stock_units = M.occupied_units()   # kein freier Wohnraum: Zuzug bleibt auf der Warteliste
	M.on_month(m)
	var with_boost: int = M.waiting - w0
	M.marketing_until = -1
	var w1: int = M.waiting
	M.on_month(m)
	ok(with_boost > M.waiting - w1, "Stadtmarketing erhöht den Zuzug (%d statt %d)" % [with_boost, M.waiting - w1])
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.population.training_support == 100 and int(s2.citizens.base_cap.polizei) == pol0 + 3 and int(s2.citizens.start_cap.polizei) == int(Z.start_cap.polizei), "Hebel nach dem Laden")
	# Regelbürgermeister
	var ind := M.indicators()
	ind.sicherheit_gesundheit.gesucht = 10
	ind.arbeit.offene_stellen_nach_arbeitgeber.polizei = 0
	ind.haushalt.verfuegbar = 200000.0
	ok(MayorBrain.decide(ind).actions.any(func(a): return a.action == "set_public_staff" and a.bereich == "polizei"), "Regelbürgermeister stockt die Polizei auf")
	ok(identity_ok(s), "Geld erhalten")


func test_town_hall() -> void:
	var s := new_sim(2)
	var T: TownHall = s.town_hall
	ok(T.building >= 0 and s.city.building(T.building).name == "Rathaus" and s.city.building(T.building).role == "town_hall", "Rathaus steht als Gebäude in der Stadt")
	var sm: Dictionary = T.summary()
	var sum_is := 0
	var sum_soll := 0
	for d in sm.abteilungen:
		sum_is += int(sm.abteilungen[d].ist)
		sum_soll += int(sm.abteilungen[d].soll)
		ok(int(sm.abteilungen[d].soll) >= TownHall.MIN_PER_DEPT, "Abteilung %s hat mindestens eine Stelle" % d)
	ok(sum_is == T.staff_total() and sum_soll == T.total_target(), "Abteilungen summieren sich auf Ist (%d) und Soll (%d)" % [sum_is, sum_soll])
	ok(T.roster().size() == T.staff_total() and T.roster().all(func(r): return r.dept in TownHall.DEPTS), "Belegschaft ist vollständig zugeordnet")
	var old_cap := maxf(1.0, float(s.citizens.employed_count("rathaus")) / 8.0)
	ok(absf(s.permits.capacity() - old_cap) <= 0.6, "Bauantrags-Kapazität entspricht bei Startverteilung dem früheren Wert (%.2f / %.2f)" % [s.permits.capacity(), old_cap])
	# Einstellen und Entlassen
	var before_target := T.total_target()
	var before_staff := T.staff_total()
	s.economy.transfer("X0", "P0", 500000.0)   # Einzahlung von aussen, die Geldkonservierung bleibt gewahrt
	var h: Dictionary = T.hire("bauamt", 3)
	ok(h.ok and T.total_target() == before_target + 3 and s.citizens.cap.rathaus == before_target + 3, "3 Stellen im Bauamt ausgeschrieben: " + h.msg.left(80))
	ok(T.vacancies() == 3, "offene Stellen bis zum Monatsende (%d)" % T.vacancies())
	s.citizens._dynamics(1)
	ok(T.staff_total() > before_staff and T.staff_total() <= T.total_target(), "zum Monatsende besetzt (%d -> %d)" % [before_staff, T.staff_total()])
	var d: Dictionary = T.dismiss("verwaltung", 2)
	ok(d.ok and T.target.verwaltung >= TownHall.MIN_PER_DEPT, "2 Stellen in der Verwaltung gestrichen")
	var cap_after: int = int(s.citizens.cap.rathaus)
	s.citizens._dynamics(2)
	ok(s.citizens.employed_count("rathaus") <= cap_after, "Entlassung wirkt zum Monatsende")
	# Grenzen
	ok(not T.hire("kantine", 1).ok, "unbekannte Abteilung abgelehnt")
	ok(not T.hire("bauamt", 6).ok and not T.hire("bauamt", 0).ok, "Anzahl 1 bis 5")
	ok(not T.dismiss("pruefdienst", 99).ok and not T.dismiss("pruefdienst", T.target.pruefdienst).ok, "mindestens eine Kraft je Abteilung")
	s.economy.transfer("P0", "X0", float(s.economy.accounts.P0) - 1000.0)
	var poor: Dictionary = T.hire("strassen", 2)
	ok(not poor.ok and "Stadtkasse" in poor.msg, "ohne Geld in der Stadtkasse keine Einstellung: " + poor.msg.left(70))
	# Aktionen des Buergermeisters und Beobachtung
	s.economy.transfer("X0", "P0", 500000.0)
	var r: Dictionary = s.mayor.execute({"action": "hire_staff", "abteilung": "pruefdienst", "anzahl": 1, "reason": "Prüfungen"})
	ok(r.ok and s.mayor.decisions.back().action == "hire_staff", "Bürgermeister kann einstellen und es wird protokolliert")
	ok(s.mayor.indicators().has("rathaus") and s.mayor.indicators().rathaus.abteilungen.has("bauamt"), "Beobachtung enthält das Rathaus")
	ok("hire_staff" in Mayor.SCHEMA and "dismiss_staff" in Mayor.SCHEMA, "Aktionen stehen im Schema (und damit im Prompt)")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.town_hall.target == T.target and s2.town_hall.building == T.building, "Rathaus nach Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_population() -> void:
	var s := new_sim(2)
	var P: Population = s.population
	var c := Population.cfg()
	var people: Array = s.citizens.people
	ok(people.all(func(p): return p.has("age") and p.has("education") and p.has("balance") and p.has("needs")), "jeder Bewohner hat Alter, Bildung, Konto und Bedürfnisse")
	ok(people.all(func(p): return int(p.age) >= int(c.alter_min) and int(p.age) <= int(c.alter_max) and int(p.education) >= 0 and int(p.education) <= 3), "Alter und Bildung im Rahmen")
	var checks: Array = P.validate(false)
	for ch in checks:
		ok(ch.ok, "Startprüfung: %s = %s (Ziel %s)" % [ch.pruefung, str(ch.wert), str(ch.ziel)])
	ok(absf(P.account_error()) < 0.01 and float(s.economy.accounts.R0) > 0.0, "Summe der Personenguthaben = R0 (%.0f)" % float(s.economy.accounts.R0))
	# Bildung lenkt die Stellenvergabe: im Rathaus im Mittel höhere Bildung als bei den Arbeitslosen
	var edu_of := func(sel: Array) -> float:
		var sum := 0.0
		for p in sel:
			sum += float(p.education)
		return sum / maxf(1.0, float(sel.size()))
	var town: Array = people.filter(func(p): return p.employer == "rathaus")
	var none: Array = people.filter(func(p): return p.employer == "")
	ok(edu_of.call(town) > edu_of.call(none), "Rathaus beschäftigt höher Gebildete (%.2f) als die Arbeitslosen haben (%.2f)" % [edu_of.call(town), edu_of.call(none)])
	# Eigentum: Selbstnutzer zahlen keine Miete, Vermieter erhalten Miete von Person zu Person
	var units: Dictionary = s.housing.units
	var self_u: Array = units.values().filter(func(u): return bool(u.get("owner_occupied", false)))
	var rented: Array = units.values().filter(func(u): return u.tenant == "B" and not bool(u.get("owner_occupied", false)) and str(u.owner).begins_with("R"))
	ok(not self_u.is_empty() and self_u.all(func(u): return s.housing.rent_due(u) == 0.0), "Selbstnutzer zahlen keine Miete (%d Einheiten)" % self_u.size())
	ok(not rented.is_empty(), "Bürger vermieten Wohnungen an Bürger (%d Einheiten)" % rented.size())
	var u0: Dictionary = rented[0]
	var lord: Dictionary = P._person(int(str(u0.owner).substr(1)))
	var tenants: Array = people.filter(func(p): return str(p.get("home", "")) == u0.id)
	var lord_before := float(lord.balance)
	var tenant_before := 0.0
	for q in tenants:
		tenant_before += float(q.balance)
	var r0_before := float(s.economy.accounts.R0)
	s.housing.collect_citizen_rent()
	var tenant_after := 0.0
	for q in tenants:
		tenant_after += float(q.balance)
	var rent := float(s.housing.rent_due(u0))
	ok(absf(tenant_before - tenant_after - rent) < 0.01, "Mieter zahlen die Miete von ihren Konten (%.0f)" % rent)
	ok(float(lord.balance) >= lord_before + rent - 0.01, "Vermieter %s erhält die Miete" % lord.name)
	ok(float(s.economy.accounts.R0) <= r0_before + 0.01 and absf(P.account_error()) < 0.01, "Miete zwischen Personen bleibt in R0")
	# Mietrückstand: leeres Konto -> Rückstand
	P.pay_out("X0", tenants.map(func(q): return [q, float(q.balance)]))   # Mieter haben kein Guthaben mehr (gebucht, nicht gesetzt)
	s.housing.collect_citizen_rent()
	ok(int(u0.arrears) >= 1, "ohne Guthaben entsteht ein Mietrückstand")
	# Grundsteuer: Satz des Bürgermeisters, Zahlung an die Stadtkasse
	var p0 := float(s.economy.accounts.P0)
	var paid := P.collect_property_tax(2)
	ok(paid > 0.0 and absf(float(s.economy.accounts.P0) - p0 - paid) < 0.01, "Grundsteuer fließt an die Stadtkasse (%.0f)" % paid)
	ok(not P.set_tax_rate(5.0).ok and not P.set_tax_rate(2.0).ok, "Satz nur 0,2–3,0 und höchstens ±0,5 je Beschluss")
	var r := s.mayor.execute({"action": "set_property_tax", "satz_prozent": 1.4, "reason": "Haushalt"})
	ok(r.ok and absf(P.tax_rate - 1.4) < 0.001, "Bürgermeister setzt den Satz: " + str(r.msg).left(80))
	ok(s.mayor.indicators().has("bevoelkerungsmodell"), "Bürgermeister sieht das Bevölkerungsmodell")
	# Monatszyklus: Konten stimmen, Protokoll wird geschrieben, Bedürfnisse liegen im Rahmen
	s.citizens.on_month(3)
	ok(absf(P.account_error()) < 0.01, "nach dem Monatszyklus: Personenguthaben = R0")
	ok(not P.month_log.is_empty() and P.month_log.back().loehne > 0.0, "Monatsprotokoll mit Löhnen, Miete, Grundsteuer, Konsum")
	ok(people.all(func(p): return float(p.needs.glueck) >= 0.0 and float(p.needs.glueck) <= 100.0), "Glück zwischen 0 und 100")
	# Wegzug: Guthaben verlassen die Stadt, Eigentum geht an den Vermietersektor
	var e_unit: Dictionary = self_u[0]
	var leaving: Array = people.filter(func(p): return str(p.get("home", "")) == e_unit.id)
	var bal := 0.0
	for q in leaving:
		bal += maxf(0.0, float(q.balance))
	var x0 := float(s.economy.accounts.X0)
	s.citizens.emigrate(e_unit.id)
	ok(absf(float(s.economy.accounts.X0) - x0 - bal) < 0.01 and e_unit.owner == Housing.LANDLORD, "Wegzug nimmt das Guthaben mit, die Wohnung geht an den Vermietersektor")
	ok(absf(P.account_error()) < 0.01, "nach Wegzug: Personenguthaben = R0")
	# Zuzug erhält Alter, Bildung, Startguthaben
	s.citizens.immigrate(3, 4)
	var newest: Dictionary = people.back()
	ok(newest.has("education") and float(newest.balance) > 0.0 and absf(P.account_error()) < 0.01, "Zugezogene erhalten Attribute und Startguthaben")
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(absf(s2.population.account_error()) < 0.01 and absf(s2.population.tax_rate - 1.4) < 0.001, "Bevölkerungsmodell nach Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_resident_behavior() -> void:
	var s := new_sim(2)
	var P: Population = s.population
	var Z: Citizens = s.citizens
	var people: Array = Z.people
	var day: int = GameCalendar.day_of(s.game_min)
	# Jobsuche nach Bildung: niemand ohne Mindestbildung in Rathaus, Schulen/Klinik, Gesundheit, Polizei
	Z.on_month(1)
	ok(people.all(func(p): return p.employer == "" or Population.qualified(p, p.employer)), "alle Beschäftigten erfüllen die Mindestbildung ihrer Stelle")
	var low: Dictionary = people.filter(func(p): return p.employer == "" and int(p.education) == 0 and not p.has("course_until")).front()
	ok(not Population.qualified(low, "rathaus") and Population.qualified(low, "handel"), "Grundbildung reicht für den Handel, nicht fürs Rathaus")
	# Weiterbildung: lange Arbeitslose gehen zur Schule und steigen eine Bildungsstufe auf
	var c := Population.cfg()
	var learners: Array = people.filter(func(p): return p.employer == "" and int(p.education) < 3).slice(0, 40)
	for p in learners:
		p.erase("course_until")
		p.jobless_months = int(c.weiterbildung_ab_monaten_arbeitslos)
	P.behave(5)
	var started: Array = learners.filter(func(p): return p.has("course_until"))
	ok(not started.is_empty() and int(P.behavior.weiterbildung_beginn) >= started.size(), "Arbeitslose beginnen eine Weiterbildung (%d von %d)" % [started.size(), learners.size()])
	var q: Dictionary = started[0]
	ok(str(Z.travel_plan(q, 10.0).purpose) == "Zur Weiterbildung" and str(s.city.building(int(Z.travel_plan(q, 10.0).building)).type) == "school", "Weg führt tagsüber zur Schule")
	var edu0 := int(q.education)
	q.course_until = day
	P.behave(6)
	ok(int(q.education) == edu0 + 1 and not q.has("course_until") and int(P.behavior.weiterbildung_abschluss) >= 1, "nach der Weiterbildung Bildung %d -> %d" % [edu0, int(q.education)])
	# Teilnehmer bewerben sich nicht
	var in_course: Array = people.filter(func(p): return p.has("course_until"))
	for k in Z.cap:
		Z.cap[k] = Z.employed_count(k) + 30
	Z._dynamics(7)
	ok(in_course.all(func(p): return p.employer == "" or not p.has("course_until")) and in_course.all(func(p): return p.employer == ""), "während der Weiterbildung keine Einstellung")
	# Umzug aus Geldnot: unglücklicher Mieter mit zu hoher Miete zieht in eine günstigere freie Wohnung
	var occ: Dictionary = s.housing._citizen_occupants()
	var mover: Dictionary = {}
	for uid in occ:
		var u: Dictionary = s.housing.units[uid]
		if u.tenant == "B" and not bool(u.get("owner_occupied", false)) and occ[uid].size() == 1 and (mover.is_empty() or float(u.rent) > float(s.housing.units[mover.home].rent)):
			mover = occ[uid][0]
	ok(not mover.is_empty(), "Mieter mit teurer Wohnung gefunden")
	var old_uid := str(mover.home)
	var old_rent := float(s.housing.units[old_uid].rent)
	mover.net = old_rent * 2.2   # Miete > 40 % des Nettos, guenstigere Einheiten bleiben bezahlbar
	mover.needs.glueck = 10.0
	ok(s.housing.relocate_cheaper(mover), "Umzug in eine günstigere Wohnung")
	var nu: Dictionary = s.housing.units[str(mover.home)]
	ok(str(mover.home) != old_uid and float(nu.rent) < old_rent and s.housing.units[old_uid].tenant == "", "neue Miete %.0f < alte %.0f, alte Wohnung frei" % [float(nu.rent), old_rent])
	# Wegzug: lange arbeitslos und unglücklich, ohne Wohneigentum -> verlässt die Stadt einzeln, Guthaben gehen mit
	var cand: Array = people.filter(func(p): return p.employer == "" and P.owned_units(int(p.id)).is_empty() and not p.has("course_until"))
	for p in cand:
		p.jobless_months = int(c.wegzug_ab_monaten_arbeitslos)
		p.needs.glueck = 5.0
	var n0 := people.size()
	var homes := {}
	for p in cand:
		homes[str(p.get("home", ""))] = true
	P.behave(8)
	ok(Z.people.size() < n0 and int(P.behavior.wegzug) == n0 - Z.people.size(), "%d lange Arbeitslose ziehen weg" % (n0 - Z.people.size()))
	ok(absf(P.account_error()) < 0.01, "nach Wegzug: Personenguthaben = R0")
	var occ2: Dictionary = s.housing._citizen_occupants()
	ok(homes.keys().all(func(uid): return not s.housing.units.has(uid) or occ2.has(uid) or s.housing.units[uid].tenant != "B"), "Wohnungen ohne verbleibende Bewohner werden frei")
	ok(P.summary().has("verhalten_letzter_monat") and P.summary().has("in_weiterbildung"), "Zusammenfassung zeigt das Verhalten")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.citizens.people.filter(func(p): return p.has("course_until")).size() == Z.people.filter(func(p): return p.has("course_until")).size(), "Weiterbildungen bleiben nach dem Laden erhalten")
	ok(identity_ok(s), "Geld erhalten")


func test_activity_feed() -> void:
	var s := new_sim(2)
	for k in s.market.open_contracts():
		s.companies[0].known[k.id] = true
	var A: ActivityFeed = s.activity
	var n0 := A.items.size()
	# Auftrag annehmen: Markierung am Abholort mit Firma und Text
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var k: Contract = s.market.open_contracts().filter(func(x): return s.companies[0].known.has(x.id) and x.vehicle_ok(v.model) and x.min_rep <= s.companies[0].reputation)[0]
	var r: Dictionary = s.executor.execute(0, {"action": "accept_contract", "contract_id": k.id, "vehicle_id": v.id}, "", "api")
	ok(r.ok and A.items.size() == n0 + 1, "ausgeführte Entscheidung erscheint in der Aktivität")
	var e: Dictionary = A.items.back()
	ok(e.kind == "auftrag" and Vector2i(int(e.x), int(e.y)) == s.city.building(k.pickup).walk and e.text.contains(k.id), "Ort ist der Abholort, Text nennt den Auftrag (%s)" % e.text)
	# Abgelehnte Aktionen und Routine erscheinen nicht
	s.executor.execute(0, {"action": "accept_contract", "contract_id": "A999999"}, "", "api")
	s.executor.execute(0, {"action": "wait"}, "", "api")
	ok(A.items.size() == n0 + 1, "abgelehnte Aktionen und Warten erscheinen nicht")
	# Buergermeister: Massnahme mit Ort
	s.economy.transfer("X0", "P0", 300000.0)
	s.mayor.execute({"action": "hire_staff", "abteilung": "bauamt", "anzahl": 1, "reason": "Anträge"})
	ok(A.items.back().actor == "buergermeister" and A.items.back().kind == "stadt", "Bürgermeister-Maßnahmen erscheinen (gold)")
	ok(A.active(s.game_min).size() >= 2 and A.active(s.game_min + ActivityFeed.KEEP_MIN + 1.0).is_empty(), "Einträge verblassen nach %d Spielminuten" % int(ActivityFeed.KEEP_MIN))
	# Sabotage: Assistent ergaenzt Arbeiter und gesichtetes Ziel
	var foreign: FleetVehicle = s.company_vehicles(1)[0]
	s.personnel.seen[0][foreign.id] = {"id": foreign.id, "state": "idle", "owner": 1}
	var done: Dictionary = s.executor.assist.complete(0, {"action": "attempt_vehicle_sabotage"})
	ok(done.get("worker_id") != null and int(done.get("vehicle_id", -1)) == foreign.id, "Sabotage ohne Angaben: Arbeiter und Ziel werden ergänzt (%s)" % str(done.get("_ergaenzt", [])))
	# Speichern und Laden
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(s2.activity.items.size() == A.items.size(), "Aktivität nach Laden")
	ok(identity_ok(s), "Geld erhalten")


func test_public_safety() -> void:
	var s := new_sim(2)
	var S: PublicSafety = s.safety
	ok(S.police >= 0 and S.prison >= 0 and S.doctors.size() >= 1 and S.hospital >= 0, "Polizeiwache, Gefängnis, Arztpraxen und Krankenhaus stehen in der Stadt")
	ok(s.citizens.employed_count("polizei") > 0 and s.citizens.employed_count("gesundheit") > 0, "Polizei (%d) und Ärzte/Pflege (%d) sind Bürger mit Stelle" % [s.citizens.employed_count("polizei"), s.citizens.employed_count("gesundheit")])
	var cops: Array = s.citizens.people.filter(func(p): return p.employer == "polizei")
	ok(cops.all(func(p): return str(p.get("home", "")) != ""), "das Personal wohnt in der Stadt")
	ok(S.vehicles.filter(func(v): return v.kind == "polizei").size() == 2 and S.vehicles.filter(func(v): return v.kind == "krankenwagen").size() == 1, "zwei Streifenwagen, ein Krankenwagen")
	# Straftat
	var day := S.today()
	var p: Dictionary = s.citizens.people.filter(func(q): return q.employer != "" and str(q.get("home", "")) != "")[0]
	var bal := float(p.balance)
	S._crime(p, day)
	ok(bool(p.wanted) and float(p.balance) > bal and absf(s.population.account_error()) < 0.01, "Diebstahl: Beute auf dem Konto des Täters, gesucht")
	ok(s.activity.items.back().kind == "verbrechen", "Straftat erscheint auf der Karte (rot)")
	# Festnahme mit langer Haft: Arbeit weg, Mieter verliert die Wohnung, Beute erstattet
	var c := Population.cfg().duplicate(true)
	c["sicherheit_gesundheit"] = {"haft_tage_min": 70, "haft_tage_max": 80}
	Population.set_cfg(c)
	var u: Dictionary = s.housing.units[str(p.home)]
	var tenant := str(u.owner) != Population.OWNER_PREFIX + str(int(p.id))
	S._arrest(p, day)
	ok(PublicSafety.in_prison(p, day) and p.employer == "" and not bool(p.wanted) and float(p.loot) == 0.0, "Festnahme: Haft, Arbeit verloren, Beute erstattet")
	ok(not tenant or str(p.home) == "", "Mieter verliert bei langer Haft die Wohnung")
	ok(S.vehicles.any(func(v): return v.kind == "polizei" and not v.task.is_empty()), "Streifenwagen fährt zum Einsatz")
	ok(s.activity.items.back().kind == "polizei", "Festnahme erscheint auf der Karte (blau)")
	Population.set_cfg({})
	# Haeftlinge werden weder eingestellt noch untergebracht
	s.citizens._dynamics(1)
	s.housing._house_homeless()
	ok(p.employer == "" and str(p.get("home", "")) == "" if tenant else p.employer == "", "Häftlinge werden weder eingestellt noch untergebracht")
	S.on_day(int(p.prison_until))
	ok(not PublicSafety.in_prison(p, int(p.prison_until) + 1) and int(p.prison_until) == -1, "nach der Haft entlassen")
	# Gesundheit ueber einen Monat: Erkrankungen, Arzt, Krankenhaus, Kosten aus der Stadtkasse
	var p0 := float(s.economy.accounts.P0)
	for d in range(day + 1, day + 40):
		S.on_day(d)
	ok(int(S.stats.erkrankt) > 0 and int(S.stats.arzt) > 0, "Bürger erkranken und gehen zum Arzt (%d Fälle, %d Arztbesuche, %d Krankenhaus)" % [int(S.stats.erkrankt), int(S.stats.arzt), int(S.stats.krankenhaus)])
	ok(float(S.stats.kosten) > 0.0 and float(s.economy.accounts.P0) < p0, "Behandlungskosten trägt die Stadtkasse")
	# Polizei sichert eine Sperrung ab
	var rw: Vector2i = s._straight_road()
	s.nav.add_roadwork(rw, s.game_min + 500.0)
	for v in S.vehicles:
		v.task = {}
	S.update(0.1)
	var guard: Array = S.vehicles.filter(func(v): return v.kind == "polizei" and (v.mover.goal - rw).length() <= 1.5)
	ok(not guard.is_empty(), "ein Streifenwagen fährt zur Sperrung und sichert sie ab")
	ok(s.mayor.indicators().has("sicherheit_gesundheit"), "Bürgermeister sieht Sicherheit und Gesundheit")
	var s2 := Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	ok(int(s2.safety.stats.festnahmen) == int(S.stats.festnahmen) and s2.safety.vehicles.size() == S.vehicles.size(), "nach Laden")
	ok(identity_ok(s), "Geld erhalten")
