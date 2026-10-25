class_name ExperimentBook
extends RefCounted
## Wirtschaftliche Experimente der KI innerhalb der echten Simulation (sie kosten Zeit, Geld und Kapazitaet).
## Ein Experiment hat Fragestellung, Varianten, Budget, Zeitraum und Messgroessen. Aktionen werden ueber die
## Felder "experiment" und "variante" einer Variante zugeordnet; gemessen wird an den betroffenen Auftraegen
## (Erloes, zurechenbare Treibstoffkosten, Marge, Dauer, Puenktlichkeit). Wenige oder widerspruechliche
## Beobachtungen fuehren zu einer ausdruecklich unsicheren Schlussfolgerung.

const MIN_PER_VARIANT := 3

var sim
var experiments := {}     # ID -> Experiment
var tags := {}            # Auftrags-ID -> [Experiment-ID, Variante]
var next_id := 1


func setup(simulation) -> void:
	sim = simulation


func start(cid: int, a: Dictionary) -> Dictionary:
	var variants = a.get("varianten", [])
	if not variants is Array or variants.size() < 1 or variants.size() > 4:
		return {"ok": false, "msg": "1–4 Varianten angeben (z. B. ['einzeln', 'sammeltour'])."}
	var running := experiments.values().filter(func(x): return x.company == cid and x.status == "laufend").size()
	if running >= 2:
		return {"ok": false, "msg": "Höchstens 2 laufende Experimente gleichzeitig."}
	var hours := clampf(float(a.get("dauer_h", 12)), 1.0, 72.0)
	var x := {"id": "X%d" % next_id, "company": cid, "frage": str(a.get("frage", "")).left(200),
		"varianten": variants.map(func(v): return str(v).left(30)), "budget": maxf(0.0, float(a.get("budget", 0))),
		"messgroessen": a.get("messgroessen", ["marge", "dauer", "puenktlich"]), "start": sim.game_min,
		"ende": sim.game_min + hours * 60.0, "status": "laufend", "ergebnis": "", "ausgaben": 0.0}
	next_id += 1
	experiments[x.id] = x
	sim.log_event("%s startet Experiment %s: %s" % [sim.company(cid).player_name, x.id, x.frage], "plan", cid)
	return {"ok": true, "msg": "Experiment %s läuft bis %s. Aktionen mit experiment='%s' und variante=%s kennzeichnen." % [
		x.id, Catalog.game_minutes_to_text(x.ende), x.id, str(x.varianten)]}


## Vom Executor nach erfolgreichen Auftrags-/Tour-Aktionen aufgerufen.
func tag(cid: int, action: Dictionary, contract_ids: Array) -> String:
	var xid := str(action.get("experiment", ""))
	if xid == "":
		return ""
	var x: Dictionary = experiments.get(xid, {})
	if x.is_empty() or x.company != cid or x.status != "laufend":
		return " (Experiment %s unbekannt oder beendet – nicht zugeordnet)" % xid
	var variant := str(action.get("variante", x.varianten[0]))
	if variant not in x.varianten:
		return " (Variante %s gehört nicht zu %s)" % [variant, xid]
	for kid in contract_ids:
		tags[kid] = [xid, variant]
	return " [Experiment %s/%s]" % [xid, variant]


func metrics(xid: String) -> Dictionary:
	var x: Dictionary = experiments[xid]
	var per := {}
	for v in x.varianten:
		per[v] = {"n": 0, "offen": 0, "erloes": 0.0, "treibstoff": 0.0, "dauer": 0.0, "puenktlich": 0, "gescheitert": 0}
	var spent := 0.0
	for kid in tags:
		if tags[kid][0] != xid:
			continue
		var m: Dictionary = per[tags[kid][1]]
		var k: Contract = sim.contracts.get(kid)
		if k == null:
			continue
		spent += k.fuel_cost
		if k.status == "delivered":
			m.n += 1
			m.erloes += k.paid
			m.treibstoff += k.fuel_cost
			m.dauer += k.done_at - k.accepted_at
			if k.paid >= k.reward - 0.01:
				m.puenktlich += 1
		elif k.status == "failed":
			m.n += 1
			m.gescheitert += 1
			m.treibstoff += k.fuel_cost
			m.erloes -= k.reward * Catalog.FAIL_PENALTY_SHARE
		else:
			m.offen += 1
	x.ausgaben = spent
	var out := {}
	for v in per:
		var m: Dictionary = per[v]
		var n: int = maxi(1, m.n)
		out[v] = {"abgeschlossen": m.n, "offen": m.offen, "marge_je_auftrag": snappedf((m.erloes - m.treibstoff) / n, 1.0),
			"erloes_je_auftrag": snappedf(m.erloes / n, 1.0), "treibstoff_je_auftrag": snappedf(m.treibstoff / n, 1.0),
			"dauer_min": snappedf(m.dauer / n, 1.0), "puenktlich_quote": snappedf(float(m.puenktlich) / n, 0.01), "gescheitert": m.gescheitert}
	return out


func finish(cid: int, xid: String) -> Dictionary:
	var x: Dictionary = experiments.get(xid, {})
	if x.is_empty() or x.company != cid:
		return {"ok": false, "msg": "Experiment %s gehört dir nicht." % xid}
	if x.status != "laufend":
		return {"ok": false, "msg": "Experiment %s ist bereits ausgewertet." % xid}
	_evaluate(x)
	return {"ok": true, "msg": x.ergebnis}


## Auswertung mit ausdruecklicher Unsicherheit.
func _evaluate(x: Dictionary) -> void:
	var m := metrics(x.id)
	var lines: Array = []
	var enough := true
	var best := ""
	var best_val := -INF
	var vals: Array = []
	for v in m:
		lines.append("%s: n=%d, Marge Ø %s, Dauer Ø %d min, pünktlich %d %%" % [v, m[v].abgeschlossen, Catalog.money(m[v].marge_je_auftrag),
			int(m[v].dauer_min), int(m[v].puenktlich_quote * 100)])
		if m[v].abgeschlossen < MIN_PER_VARIANT:
			enough = false
		vals.append(float(m[v].marge_je_auftrag))
		if float(m[v].marge_je_auftrag) > best_val:
			best_val = float(m[v].marge_je_auftrag)
			best = v
	var spread: float = (vals.max() - vals.min()) if vals.size() > 1 else 0.0
	var verdict := ""
	if not enough:
		verdict = "UNSICHER: zu wenige Beobachtungen (mind. %d je Variante)." % MIN_PER_VARIANT
	elif vals.size() > 1 and spread < absf(best_val) * 0.1:
		verdict = "Kein klarer Unterschied (Abstand < 10 %)."
	else:
		verdict = "Vorläufig besser: %s." % best
	var over: String = " Budget überschritten (%s von %s)." % [Catalog.money(x.ausgaben), Catalog.money(x.budget)] if x.budget > 0.0 and x.ausgaben > x.budget else ""
	x.status = "ausgewertet"
	x.ergebnis = "Experiment %s – %s %s | %s%s" % [x.id, x.frage, verdict, "; ".join(lines), over]
	sim.memory.upsert(x.company, {"inhalt": x.ergebnis.left(220), "bereich": ["experiment"] + x.varianten,
		"art": "tatsache" if enough and not verdict.begins_with("Kein") else "vermutung",
		"vertrauen": 0.7 if enough else 0.25, "belege": m.values().reduce(func(acc, v): return acc + int(v.abgeschlossen), 0)}, "engine")
	sim.notify(x.company, x.ergebnis)
	sim.log_event("%s wertet Experiment %s aus: %s" % [sim.company(x.company).player_name, x.id, verdict], "plan", x.company)


func tick() -> void:
	for x in experiments.values():
		if x.status == "laufend":
			metrics(x.id)
			if sim.game_min >= float(x.ende) or (x.budget > 0.0 and x.ausgaben > x.budget):
				_evaluate(x)


func summary(cid: int) -> Array:
	return experiments.values().filter(func(x): return x.company == cid and (x.status == "laufend" or sim.game_min - float(x.ende) < 600.0)) \
		.map(func(x): return {"id": x.id, "frage": x.frage, "status": x.status, "varianten": x.varianten, "budget": x.budget,
			"ausgaben": int(x.ausgaben), "ende": Catalog.game_minutes_to_text(x.ende), "zwischenstand": metrics(x.id),
			"ergebnis": x.ergebnis})


func to_dict() -> Dictionary:
	return {"experiments": experiments, "tags": tags, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	experiments = d.get("experiments", {})
	for x in experiments.values():
		x.company = int(x.company)
	tags = d.get("tags", {})
	next_id = int(d.get("next_id", 1))
