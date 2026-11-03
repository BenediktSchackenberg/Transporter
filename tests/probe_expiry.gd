extends SceneTree
## Messlauf: warum verfallen Marktauftraege ungenutzt? Ordnet verfallene Auftraege nach Eigenschaften ein.
##   Godot_console.exe --headless --path . -s tests/probe_expiry.gd -- --seed=21 --days=20


func _initialize() -> void:
	var seed_value := 21
	var days := 20.0
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seed="):
			seed_value = int(s.trim_prefix("--seed="))
		elif s.begins_with("--days="):
			days = float(s.trim_prefix("--days="))
	GameCalendar.configure(60.0)
	var spec := {"seed": seed_value, "map": 128, "steps": int(days * 600.0), "brains": Catalog.PERSONALITIES.keys().slice(0, 4), "events": []}
	var s: Simulation = Arena._setup(spec, 0)
	var rngs: Array = []
	for c in s.companies:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 100 + c.id
		rngs.append(rng)
	var seen := {}
	var flags := {}
	for step in int(spec.steps):
		if step % Arena.ACT_EVERY == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				_classify(obs, flags)
				for a in RuleBrain.decide(obs, c.personality, rngs[c.id]).actions.slice(0, Arena.DEFAULT_ACTIONS):
					s.executor.execute(c.id, a, "", "fallback")
		for k in s.contracts.values():
			if not seen.has(k.id):
				seen[k.id] = k.to_dict()
		s.step(0.1)
	var by := {}
	var rep_max := 0.0
	for c in s.companies:
		rep_max = maxf(rep_max, float(c.reputation))
	for id in seen:
		var k = s.contracts.get(id)
		if k == null or k.status != "expired":
			continue
		var d: Dictionary = seen[id]
		var tags: Array = []
		if d.needs_cold: tags.append("kuehl")
		if d.needs_heavy: tags.append("schwer")
		if d.qty > 18: tags.append("menge>18")
		if d.min_rep > 0.0: tags.append("rep>0")
		if d.get("payer", "") != "": tags.append("stadt")
		if d.get("requester", "") != "": tags.append("kunde")
		if d.distance > 60: tags.append("weit>60")
		if d.reward < 200.0: tags.append("billig<200")
		var key := "+".join(tags) if not tags.is_empty() else "ohne Besonderheit"
		var f: Dictionary = flags.get(id, {})
		key += "  => " + ("Auftrag nie sichtbar" if f.is_empty() else ("OK fuer freies Fahrzeug, aber nicht genommen" if f.get("passt", false) else ("Flotte passt, aber keins frei/Filter" if f.get("flotte", false) else "kein passendes Fahrzeug")))
		var e: Array = by.get(key, [0, 0.0, 0.0])
		e[0] += 1
		e[1] += float(d.reward)
		e[2] += float(d.offer_until) - float(d.created)
		by[key] = e
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b): return by[a][0] > by[b][0])
	print("Verfallene Auftraege nach Eigenschaft (Anzahl, mittlere Verguetung, mittlere Marktdauer min):")
	for key in keys:
		var e: Array = by[key]
		print("  %3d  %6.0f  %5.0f  %s" % [e[0], e[1] / e[0], e[2] / e[0], key])
	var tot := 0
	for id in seen:
		if s.contracts.has(id) and s.contracts[id].status == "expired":
			tot += 1
	print("Gesamt verfallen: ", tot, " von ", seen.size())
	quit()


func _classify(obs: Dictionary, flags: Dictionary) -> void:
	var models: Dictionary = obs.fahrzeugmodelle
	var ready: Array = obs.fahrzeuge.filter(func(v): return v.status in ["bereit", "fährt zum Depot"] and v.fahrer != null and int(v.zustand) >= 45)
	for k in obs.markt:
		var f: Dictionary = flags.get(k.id, {})
		for v in obs.fahrzeuge:
			var m: Dictionary = models[v.modell]
			if k.menge <= m.kapazitaet and (not k.kuehlung or m.kuehlung) and (not k.schwer or m.schwer):
				f["flotte"] = true
		for v in ready:
			if not RuleBrain._best_contract([k], v, models[v.modell], float(obs.ich.reputation)).is_empty():
				f["passt"] = true
		flags[k.id] = f
