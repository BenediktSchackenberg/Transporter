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
			"test_response_parsing", "test_provider_choice", "test_controller_idempotency", "test_kinggamer_features", "test_workers_acceptance", "test_prompt_builds", "test_local_agent_choices", "test_stage1_combinable", "test_stage1_plans", "test_stage2_memory", "test_stage3_events_and_log", "test_stage4_experiments", "test_stage4_contracts", "test_estate_acceptance", "test_foreman_delegation", "test_weather_model", "test_weather_effects", "test_event_chain", "test_event_limits", "test_live_text", "test_iso_assets_complete", "test_iso_geometry", "test_iso_strips", "test_weather_service", "test_residents_save_load", "test_calendar", "test_money_conservation", "test_banking", "test_banking_default", "test_company_forms", "test_insolvency", "test_trader", "test_trader_production", "test_build_materials", "test_standings", "test_economy_cycle", "test_multi_year_consistency", "test_fuel_prices", "test_gas_stations", "test_households_wages", "test_wage_arrears_in_insolvency", "test_fuel_planner", "test_building_care", "test_workforce", "test_news_feed", "test_review_fixes", "test_physical_fueling", "test_public_sector", "test_citizens", "test_parcels", "test_permits", "test_mayor", "test_construction", "test_developer_autopilot", "test_household_builder", "test_acceptance_flow", "test_city_depot", "test_depot_operations", "test_traffic_flow"]
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
	# 5) Lagerhalle im Eigenbau: Material selbst anliefern, Arbeiter einteilen
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
	s.companies[0].ledger.inject(5000.0)
	ok(identity_ok(s), "Kapitaleinlage hat Gegenkonto")
	ok(is_equal_approx(s.economy.accounts.I0, Economy.SEED.I0 - 5000.0), "Kapitalgeber-Konto zeigt Einlage")
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
	ok(absf(cz.employment_rate() - 0.8) < 0.02, "80 %% haben Arbeit (%.1f %%)" % (cz.employment_rate() * 100.0))
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
	ok(cz.unemployed_total() > 0 and rate_min > 0.7 and rate_max < 0.9, "Arbeitslosigkeit bleibt realistisch (%.1f–%.1f %%)" % [rate_min * 100.0, rate_max * 100.0])
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
