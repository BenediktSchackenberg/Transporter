extends SceneTree
## Wirtschaftslabor (kein Pass/Fail): vergleicht Stellgroessen ueber mehrere Seeds und gibt Kennzahlen je Szenario aus.
##   Godot_console.exe --headless --path . -s tests/lab_economy.gd -- --days=30 --seeds=21,22 [--only=Basis]
## Szenarien setzen Startwerte: reserve = Reservequote der Banken, vat = kommunaler Umsatzsteueranteil, policy = Leitzins.
## Der Rat und die Zentralbank passen Steuersatz und Zins danach weiter an (Startwerte, keine festen Werte).
## Ein Spieltag = 60 Sim-s; 30 Spieltage und 2 Seeds je Szenario dauern mehrere Minuten, daher wenige Szenarien.
const SCENARIOS := [
	{"name": "Basis"},
	{"name": "Reserve 30 %", "reserve": 0.30},
	{"name": "Steuer 40 %", "vat": 0.40},
	{"name": "Leitzins 8 %", "policy": 0.08},
]


func _initialize() -> void:
	var days := 30
	var seeds: Array = [21]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		elif str(a).begins_with("--seeds="):
			seeds = str(a).trim_prefix("--seeds=").split(",")
		elif str(a).begins_with("--only="):
			only = str(a).trim_prefix("--only=")
	print("Szenario | Seed | Geldmenge | Kredite | Inflation % | Leitzins % | Stadtkasse | Zufriedenheit | Arbeitslose | Wohnungslose | Insolvente | Erhaltung")
	for sc in SCENARIOS:
		if only != "" and sc.name != only:
			continue
		for sd in seeds:
			print(run_one(sc, int(sd), days))
	quit()


func run_one(sc: Dictionary, seed_value: int, days: int) -> String:
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_value, ps)
	if sc.has("reserve"):
		s.banking.reserve_ratio = float(sc.reserve)
	if sc.has("vat"):
		s.public_sector.vat_rate = float(sc.vat)
	if sc.has("policy"):
		s.central_bank.policy_rate = float(sc.policy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for step in days * 600:
		if step % 200 == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				for a in RuleBrain.decide(obs, c.personality, rng).actions:
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
	var Z: Dictionary = s.central_bank.summary()
	var closed := s.companies.filter(func(c): return c.status in ["insolvenz", "verwertung", "geschlossen"]).size()
	return "%s | %d | %d | %d | %.1f | %.2f | %d | %.1f | %d | %d | %d | %.2f" % [sc.name, seed_value, int(Z.geldmenge), int(Z.kreditvolumen),
		float(Z.inflation) * 100.0, float(Z.leitzins) * 100.0, int(s.economy.accounts.P0), s.contentment.mean, s.citizens.unemployed_total(),
		s.housing.homeless_count(), closed, s.economy.conservation_error()]
