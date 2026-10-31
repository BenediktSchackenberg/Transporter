class_name Arena
extends RefCounted
## Vergleichsmodus und exakte Wiederholung (Strategische Steuerung, Stufe 6).
##
## `run` spielt eine Partie ohne Oberflaeche: Regel-KIs (RuleBrain, je Persoenlichkeit) entscheiden alle ACT_EVERY Schritte und werden
## dabei aufgezeichnet. `compare` spielt dieselbe Partie mehrfach mit rotierenden Startpositionen (jede Strategie sitzt einmal auf jedem
## Platz), gleichem Startkapital und gleichem Aktionsbudget je Runde und mittelt die Kennzahlen je Strategie. `replay` fuehrt die
## aufgezeichneten Aktionen und Ereignisse ohne jede Entscheidungsinstanz (keine API-Aufrufe) erneut aus; der Fingerabdruck des Endstands
## ist identisch. `to_csv` exportiert die Kennzahlen.
## spec: {seed, map, steps, brains: [Persoenlichkeit, ...], max_actions, events: [{step, typ, params, duration}]}
## In Ereignisparametern steht "cell": "depot<N>" fuer die Zufahrt des Depots von Unternehmen N.

const ACT_EVERY := 200                # Schritte (20 Sim-s) zwischen zwei Entscheidungen
const DEFAULT_ACTIONS := 6            # Aktionsbudget je Entscheidung und Unternehmen


static func _players(brains: Array, rotation: int) -> Array:
	var out: Array = []
	for i in brains.size():
		out.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": brains[(i + rotation) % brains.size()]})
	return out


static func _setup(spec: Dictionary, rotation: int) -> Simulation:
	var s := Simulation.new()
	s.setup(int(spec.get("seed", 21)), _players(spec.brains, rotation), int(spec.get("map", 128)), 0.5)
	return s


static func _fire(s: Simulation, spec: Dictionary, step: int) -> void:
	for e in spec.get("events", []):
		if int(e.step) == step:
			var params: Dictionary = e.params.duplicate(true)
			if str(params.get("cell", "")).begins_with("depot"):
				var r: Vector2i = s.depot_road(int(str(params.cell).trim_prefix("depot")))
				params.cell = [r.x, r.y]
			s.events.trigger(str(e.typ), params, float(e.duration))


## Partie mit aufgezeichneten Entscheidungen. Gibt {sim, actions, rows, fingerprint} zurueck.
static func run(spec: Dictionary, rotation: int = 0) -> Dictionary:
	var s := _setup(spec, rotation)
	var actions: Array = []
	var rngs: Array = []
	for c in s.companies:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(spec.get("seed", 21)) * 100 + c.id
		rngs.append(rng)
	var budget := int(spec.get("max_actions", DEFAULT_ACTIONS))
	for step in int(spec.steps):
		_fire(s, spec, step)
		if step % ACT_EVERY == 0:
			for c in s.companies:
				var obs := ObservationBuilder.build(s, c.id, [], 0.0, 10.0)
				var todo: Array = RuleBrain.decide(obs, c.personality, rngs[c.id]).actions
				for a in todo.slice(0, budget):
					actions.append({"step": step, "cid": c.id, "action": a})
					s.executor.execute(c.id, a, "", "fallback")
		s.step(0.1)
	return {"sim": s, "actions": actions, "rows": metrics(s, rotation, spec.brains), "fingerprint": fingerprint(s)}


## Wiederholung ohne Entscheidungsinstanz: nur die aufgezeichneten Aktionen und Ereignisse.
static func replay(spec: Dictionary, actions: Array, rotation: int = 0) -> Dictionary:
	var s := _setup(spec, rotation)
	var i := 0
	for step in int(spec.steps):
		_fire(s, spec, step)
		while i < actions.size() and int(actions[i].step) == step:
			s.executor.execute(int(actions[i].cid), actions[i].action, "", "fallback")
			i += 1
		s.step(0.1)
	return {"sim": s, "rows": metrics(s, rotation, spec.brains), "fingerprint": fingerprint(s)}


## Kennzahlen je Unternehmen; `strategie` ist die Strategie, die diesen Platz belegt.
static func metrics(s: Simulation, rotation: int, brains: Array) -> Array:
	var rank := s.ranking()
	var rows: Array = []
	for c in s.companies:
		rows.append({"platz": c.id, "strategie": brains[(c.id + rotation) % brains.size()], "rang": rank.find(c) + 1,
			"gewinn": snappedf(c.ledger.profit(), 0.01), "bargeld": snappedf(c.ledger.cash, 0.01), "vermoegen": snappedf(s.net_worth(c.id), 0.01),
			"schulden": snappedf(c.ledger.debt, 0.01), "fahrzeuge": s.company_vehicles(c.id).size(), "umsatz": snappedf(c.ledger.revenue(), 0.01),
			"status": c.status})
	return rows


## Pruefsumme des Endstands (Schritte, Konten, Firmenbuecher) fuer den Vergleich zweier Laeufe.
static func fingerprint(s: Simulation) -> String:
	var parts: Array = [s.step_count, snappedf(s.game_min, 0.001)]
	for c in s.companies:
		parts.append([snappedf(c.ledger.cash, 0.01), snappedf(c.ledger.profit(), 0.01), snappedf(c.ledger.debt, 0.01), s.company_vehicles(c.id).size()])
	for k in s.economy.accounts:
		parts.append([k, snappedf(float(s.economy.accounts[k]), 0.01)])
	return str(hash(JSON.stringify(parts)))


## Mehrere Runden mit rotierenden Startpositionen; Mittelwerte je Strategie.
static func compare(spec: Dictionary) -> Dictionary:
	var n: int = spec.brains.size()
	var rows: Array = []
	for r in n:
		var res := run(spec, r)
		for row in res.rows:
			row["runde"] = r
			rows.append(row)
	var by := {}
	for row in rows:
		var b: Dictionary = by.get(row.strategie, {"strategie": row.strategie, "laeufe": 0, "gewinn": 0.0, "vermoegen": 0.0, "rang": 0.0, "siege": 0})
		b.laeufe += 1
		b.gewinn += float(row.gewinn)
		b.vermoegen += float(row.vermoegen)
		b.rang += float(row.rang)
		b.siege += 1 if int(row.rang) == 1 else 0
		by[row.strategie] = b
	var summary: Array = []
	for k in by:
		var b: Dictionary = by[k]
		var m := float(b.laeufe)
		summary.append({"strategie": k, "laeufe": b.laeufe, "gewinn": snappedf(b.gewinn / m, 0.01), "vermoegen": snappedf(b.vermoegen / m, 0.01),
			"rang": snappedf(b.rang / m, 0.01), "siege": b.siege})
	return {"rows": rows, "summary": summary}


static func to_csv(rows: Array) -> String:
	if rows.is_empty():
		return ""
	var keys: Array = rows[0].keys()
	var lines: Array = [";".join(keys)]
	for r in rows:
		lines.append(";".join(keys.map(func(k): return str(r[k]))))
	return "\n".join(lines) + "\n"
