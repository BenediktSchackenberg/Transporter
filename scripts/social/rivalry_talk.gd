class_name RivalryTalk
extends RefCounted
## Gespraechsregie der Rivalitaet (Auftrag 12, Etappe 3): waehlt regelmaessig das angespannteste Firmenpaar und laesst die
## naechste Zeile sprechen. Die Regeln liefern nummerierte, gueltige Reaktionen (Worte und Taten der Eskalationsleiter);
## ein Sprachmodell (TalkAgent) darf nur daraus waehlen und den Satz formulieren. Ohne Modell oder bei Stoerung waehlen
## Regeln je Persoenlichkeit. Jede Zeile erscheint als Sprechblase und oeffentliche Nachricht; die Tat wird sofort ausgefuehrt.
## Standardmaessig aus (`enabled`), damit Tests und Wiederholungen unveraendert bleiben; das Spiel schaltet sie ein.

signal turn_ready(turn: Dictionary)

## Takte in Spieltagen (ein Spieltag = 24 Stadtstunden, siehe GameCalendar); umgerechnet mit GameCalendar.days_to_min.
const PERIOD_DAYS := 0.25         # hoechstens vier Zeilen je Spieltag (alle Paare zusammen)
const PAIR_GAP_DAYS := 0.5        # dasselbe Paar spricht hoechstens zweimal je Spieltag
const MIN_TENSION := 15.0         # ab Stufe Stichelei
const ANSWER_WITHIN_DAYS := 2.0   # wer angegriffen wurde, antwortet binnen zwei Spieltagen (auch unter MIN_TENSION)
const PENDING_MAX_DAYS := 3.0     # Sicherung: das Modell bekommt hoechstens so lange (Echtzeit-Zeitlimit hat der TalkAgent)
const LINE_LIMIT := 120
const OUTCOME_DAYS := 3          # Folgen einer Eskalation werden nach drei Tagen gemessen
const LEARN_MIN_SAMPLES := 2
const LEARNED_DEEDS := ["kunde_abwerben", "fahrer_abwerben", "anzeigen", "blockieren", "sabotieren"]   # nur Taten, keine Worte
const LEARN_AVOID := -2.0         # gelernte Bilanz darunter: Regeln meiden diese Tat
const PROVOKE_DAYS := 1.0         # ohne laufenden Streit stichelt ein angriffslustiger Typ einmal je Spieltag
const PROVOKERS := ["risikospieler", "wachstum"]

## Reaktionen: Richtung und kurze Erklaerung fuer Modell und Anzeige.
const KINDS := {
	"deeskalieren": {"richtung": "deeskalation", "info": "beschwichtigen (Spannung −5)"},
	"kooperation": {"richtung": "kooperation", "info": "Kooperationspakt anbieten (bei Annahme Spannung −15)"},
	"sticheln": {"richtung": "eskalation", "info": "öffentlich sticheln (Spannung +4, Ruf −0,5)"},
	"kunde_abwerben": {"richtung": "eskalation", "info": "einen Stammkunden abwerben (800 EUR, legal)"},
	"fahrer_abwerben": {"richtung": "eskalation", "info": "einen Arbeiter mit mehr Lohn abwerben (legal)"},
	"anzeigen": {"richtung": "eskalation", "info": "beim Bürgermeister anzeigen (ohne Beanstandung zahlst du)"},
	"blockieren": {"richtung": "eskalation", "info": "Straße vor dem Hof mit Paletten blockieren (verboten, 600 EUR, Polizei ermittelt meist: 2500 EUR Bußgeld)"},
	"sabotieren": {"richtung": "eskalation", "info": "Rufschädigung (verboten, kann entdeckt werden)"},
	"polizei_rufen": {"richtung": "deeskalation", "info": "Polizei rufen: die Blockade vor deinem Hof wird in gut einer Stunde geräumt"},
	"buendnis_dritter": {"richtung": "kooperation", "info": "Bündnis mit einem Dritten anbieten, der ebenfalls Ärger mit dem Gegenüber hat"},
}
## Bevorzugte Reaktionen je Persoenlichkeit (die erste verfuegbare gewinnt); Stufe = Eskalationsstufe des Paares.
const PREFS := {
	"netzwerker": ["polizei_rufen", "kooperation", "buendnis_dritter", "deeskalieren"],
	"kostenoptimierer": ["polizei_rufen", "anzeigen", "deeskalieren", "sticheln"],
	"wachstum": ["polizei_rufen", "anzeigen", "kunde_abwerben", "fahrer_abwerben", "sticheln", "deeskalieren"],
	"risikospieler": ["sabotieren", "blockieren", "kunde_abwerben", "sticheln", "fahrer_abwerben", "deeskalieren"],
}
const LINES := {
	"deeskalieren": ["%s, lass uns das nicht hochkochen. Die Stadt ist groß genug für uns beide.", "Schwamm drüber, %s. Wir haben beide Touren zu fahren.", "%s, ich will keinen Streit. Konzentrieren wir uns aufs Geschäft."],
	"kooperation": ["%s, statt uns zu bekriegen: Wie wäre ein Pakt? Ich schicke dir ein Angebot.", "Hör zu, %s – zusammen fahren wir die anderen in Grund und Boden. Angebot ist raus.", "%s, ich biete dir eine Zusammenarbeit an. Denk drüber nach."],
	"sticheln": ["Na, %s, wieder ein Lkw auf dem Standstreifen? Kein Wunder, dass die Kunden zu mir kommen.", "%s fährt so pünktlich wie ein Fahrplan an Feiertagen.", "Ich hab gehört, bei %s liefern sie jetzt per Brieftaube. Schneller wär's."],
	"kunde_abwerben": ["%s, deine Stammkunden mögen pünktliche Lieferungen. Ich biete ihnen welche.", "Deine Kunden haben gefragt, ob es auch zuverlässiger geht, %s. Es geht."],
	"fahrer_abwerben": ["%s, deine Leute verdienen mehr. Bei mir bekommen sie es.", "Gute Fahrer gehen dahin, wo man sie schätzt, %s."],
	"anzeigen": ["%s, das lasse ich prüfen. Das Amt soll sich deine Bücher ansehen.", "Genug, %s. Ich habe dich beim Bürgermeister angezeigt."],
	"blockieren": ["Hoppla, %s – da sind mir wohl ein paar Paletten vom Laster gefallen.", "%s, deine Ausfahrt sieht heute etwas voll aus, oder?"],
	"sabotieren": ["Man hört ja so einiges über %s in der Stadt …", "%s, Gerüchte verbreiten sich schneller als deine Lkw."],
	"polizei_rufen": ["Das reicht, %s. Die Polizei räumt deine Paletten weg.", "Polizei ist verständigt, %s. Mal sehen, wer da Ärger bekommt."],
	"buendnis_dritter": ["%s hat sich mit uns beiden angelegt – lass uns zusammenhalten.", "Gegen %s sind wir gemeinsam stärker. Ich schicke dir ein Angebot."],
}

var sim
var enabled := false
var lines: Array = []             # {t, from, to, text, art, richtung, ok, ergebnis, source}
var last_pair := {}               # Social.pair_key -> Spielminute der letzten Zeile
var last_run := 0.0
var pending: Dictionary = {}      # wartender Zug fuer das Modell
var use_model := false            # TalkAgent ist verbunden und bereit
var stats := {"zeilen": 0, "eskalation": 0, "deeskalation": 0, "kooperation": 0, "modell": 0, "regeln": 0}
var _next_turn := 1
var last_provoke := 0.0
var outcomes: Array = []          # offene Messungen {cid, other, art, t, rep, kosten, rep_avg}
var learned := {}                 # "Firma:art" -> {n, summe, letzte}


func setup(simulation) -> void:
	sim = simulation


func minute_tick(now: float) -> void:
	if not enabled or sim == null:
		return
	_measure(now)
	if not pending.is_empty():
		if now - float(pending.t) > GameCalendar.days_to_min(PENDING_MAX_DAYS):
			var p := pending
			pending = {}
			_apply(p, rule_choice(p), "", "Regeln (Modell zu langsam)")
		return
	if now - last_run < GameCalendar.days_to_min(PERIOD_DAYS):
		return
	last_run = now
	var turn := next_turn(now)
	if turn.is_empty() and now - last_provoke >= GameCalendar.days_to_min(PROVOKE_DAYS):
		last_provoke = now
		turn = provoke_turn(now)
	if turn.is_empty():
		return
	if use_model:
		pending = turn
		turn_ready.emit(turn)
	else:
		_apply(turn, rule_choice(turn), "", "Regeln")


## Naechster Zug: angespanntestes Paar ohne kuerzliche Zeile; es spricht, wer zuletzt geschwiegen hat (anfangs der Betroffene).
func next_turn(now: float) -> Dictionary:
	var best_key := ""
	var best := -1.0
	var keys: Array = sim.rivalry.tension.keys()
	for key in last_pair:
		if not key in keys and now - float(last_pair[key]) < GameCalendar.days_to_min(ANSWER_WITHIN_DAYS):
			keys.append(key)   # angesprochen, auch wenn der Tagesabbau die Spannung schon geloescht hat
	for key in keys:
		var v := float(sim.rivalry.tension.get(key, 0.0))
		var addressed := now - float(last_pair.get(key, -INF)) < GameCalendar.days_to_min(ANSWER_WITHIN_DAYS) and _last_escalated(key)   # angegriffen: das Gegenueber antwortet
		var score := v + (100.0 if addressed else 0.0)
		if (v >= MIN_TENSION or addressed) and score > best and now - float(last_pair.get(key, -INF)) >= GameCalendar.days_to_min(PAIR_GAP_DAYS):
			var ids: PackedStringArray = str(key).split("-")
			if sim.company(int(ids[0])).is_active() and sim.company(int(ids[1])).is_active():
				best = score
				best_key = key
	if best_key == "":
		return {}
	var ids: PackedStringArray = best_key.split("-")
	var a := int(ids[0])
	var b := int(ids[1])
	var speaker := b
	var prev := lines.filter(func(l): return Social.pair_key(int(l.from), int(l.to)) == best_key)
	if not prev.is_empty():
		speaker = b if int(prev[-1].from) == a else a
	else:
		for i in range(sim.rivalry.incidents.size() - 1, -1, -1):
			var inc: Dictionary = sim.rivalry.incidents[i]
			if Social.pair_key(int(inc.a), int(inc.b)) == best_key and float(inc.delta) > 0.0:
				speaker = int(inc.b)
				break
	var other := a if speaker == b else b
	var v: float = sim.rivalry.get_tension(a, b)
	var turn := {"id": _next_turn, "t": now, "from": speaker, "to": other, "spannung": int(v),
		"stufe": Rivalry.STAGE_NAMES[Rivalry.stage_of(v)], "stufe_nr": Rivalry.stage_of(v), "kandidaten": candidates(speaker, other, v)}
	_next_turn += 1
	return turn


## Provokation ohne Anlass: ein angriffslustiger Unternehmer nimmt sich den umsatzstaerksten Konkurrenten (ohne Pakt) vor.
## Nur eskalierende Reaktionen werden angeboten; reihum unter den Provokateuren.
func provoke_turn(now: float) -> Dictionary:
	var ps: Array = sim.companies.filter(func(c): return c.is_active() and c.personality in PROVOKERS)
	if ps.is_empty():
		return {}
	var c: Company = ps[_next_turn % ps.size()]
	var target: Company = null
	for o in sim.companies:
		if o.id != c.id and o.is_active() and not sim.social.has_pact(c.id, o.id) and (target == null or o.ledger.revenue() > target.ledger.revenue()):
			target = o
	if target == null:
		return {}
	var v: float = sim.rivalry.get_tension(c.id, target.id)
	var cands: Array = candidates(c.id, target.id, v).filter(func(k): return k.richtung == "eskalation")
	for i in cands.size():
		cands[i].nr = i + 1
	var turn := {"id": _next_turn, "t": now, "from": c.id, "to": target.id, "spannung": int(v), "stufe": Rivalry.STAGE_NAMES[Rivalry.stage_of(v)],
		"stufe_nr": Rivalry.stage_of(v), "anlass": "Provokation ohne Anlass: %s ist der umsatzstärkste Konkurrent" % target.company_name, "kandidaten": cands}
	_next_turn += 1
	return turn


## Gueltige Reaktionen des Sprechers; jede Tat wird vorab geprueft, damit nur Moegliches angeboten wird.
## Unter einem Stillhalteabkommen werden nur beruhigende Worte angeboten. Gelernte Erfahrung steht an jeder Tat.
func candidates(cid: int, other: int, tension_v: float) -> Array:
	var stage := Rivalry.stage_of(tension_v)
	if sim.rivalry.has_truce(cid, other):
		stage = 0
	var c: Company = sim.company(cid)
	var out: Array = []
	var add := func(art: String, extra: Dictionary = {}):
		var e := {"nr": out.size() + 1, "art": art, "richtung": KINDS[art].richtung, "folgen": KINDS[art].info}
		var l: Dictionary = learned.get("%d:%s" % [cid, art], {})
		if not l.is_empty():
			e["erfahrung"] = "%d-mal, Bilanz im Mittel %+.1f (Ruf gegenüber Durchschnitt, Konfliktkosten je 1000 EUR)" % [int(l.n), float(l.summe) / float(l.n)]
		e.merge(extra)
		out.append(e)
	add.call("deeskalieren")
	if not sim.social.has_pact(cid, other) and sim.social.get_trust(cid, other) > -60.0:
		add.call("kooperation")
	if stage >= 1 or not sim.rivalry.has_truce(cid, other):
		add.call("sticheln")
	if _blockade_against(cid) >= 0:
		add.call("polizei_rufen")
	if stage >= 2:
		var cust := _loyal_customer_of(other)
		if cust >= 0 and c.ledger.cash >= 800.0 + 2000.0:
			add.call("kunde_abwerben", {"kunde": cust})
		if sim.personnel.employed(other).filter(func(w): return w.role == "worker" and not w.leaving).size() >= 2 and c.ledger.cash >= Catalog.POACH_FEE + 2000.0:
			add.call("fahrer_abwerben")
	if stage >= 3 and sim.rivalry._cooldown_left("report:%d" % cid) <= 0.0 and sim.rivalry._cooldown_left("reported:%d" % other) <= 0.0:
		add.call("anzeigen")
	if stage >= 4 and sim.rivalry.check_block(cid, other) == "":
		add.call("blockieren")
	if stage >= 5 and sim.rivalry.check_sabotage(cid, other, "smear_campaign") == "":
		add.call("sabotieren")
	var third := _third_party(cid, other)
	if stage >= 2 and third >= 0:
		add.call("buendnis_dritter", {"partner": third})
	return out


func _loyal_customer_of(cid: int) -> int:
	for b in sim.customers:
		if int(sim.customers[b].get("loyal", -1)) == cid:
			return int(b)
	return -1


func _blockade_against(cid: int) -> int:
	for i in sim.rivalry.blockades.size():
		if int(sim.rivalry.blockades[i].target) == cid:
			return i
	return -1


## Dritte Firma, die selbst mit dem Gegenueber im Streit liegt und mit dem Sprecher nicht.
func _third_party(cid: int, other: int) -> int:
	for x in sim.companies:
		if x.id in [cid, other] or not x.is_active() or sim.social.has_pact(cid, x.id):
			continue
		if sim.rivalry.get_tension(x.id, other) >= 30.0 and sim.rivalry.get_tension(cid, x.id) < MIN_TENSION:
			return x.id
	return -1


## Regelwahl: erste verfuegbare Reaktion aus der Vorliebe der Persoenlichkeit. Kooperative Typen eskalieren erst,
## wenn das Gegenueber zuletzt selbst eskaliert hat (Tit for Tat).
func rule_choice(turn: Dictionary) -> int:
	var c: Company = sim.company(int(turn.from))
	var prefs: Array = PREFS.get(c.personality, PREFS.kostenoptimierer)
	var arts := {}
	for k in turn.kandidaten:
		arts[k.art] = int(k.nr)
	var provoked := _last_line_escalated(int(turn.to), int(turn.from))
	for art in prefs:
		if not arts.has(art):
			continue
		if c.personality in ["netzwerker", "kostenoptimierer"] and KINDS[art].richtung == "eskalation" and not provoked:
			continue
		if bad_experience(c.id, art):
			continue   # gelernt: diese Tat hat sich fuer die Firma nicht gelohnt
		return int(arts[art])
	return int(arts.get("deeskalieren", 1))


func _last_escalated(key: String) -> bool:
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		if Social.pair_key(int(l.from), int(l.to)) == key:
			return l.richtung == "eskalation"
	return false


func _last_line_escalated(from: int, to: int) -> bool:
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		if int(l.from) == from and int(l.to) == to:
			return l.richtung == "eskalation"
	return false


## Antwort des Modells uebernehmen (Wahl wird geprueft; ungueltig -> Regeln).
func resolve(turn_id: int, wahl: int, text: String, source: String) -> bool:
	if pending.is_empty() or int(pending.id) != turn_id:
		return false
	var p := pending
	pending = {}
	var valid: bool = p.kandidaten.any(func(k): return int(k.nr) == wahl)
	_apply(p, wahl if valid else rule_choice(p), text if valid else "", source if valid else "Regeln (ungültige Wahl)")
	return valid


## Modell gestoert: wartenden Zug sofort mit Regeln entscheiden.
func fail_pending(reason: String) -> void:
	if pending.is_empty():
		return
	var p := pending
	pending = {}
	_apply(p, rule_choice(p), "", "Regeln (%s)" % reason)


func _apply(turn: Dictionary, wahl: int, text: String, source: String) -> void:
	var cand: Dictionary = {}
	for k in turn.kandidaten:
		if int(k.nr) == wahl:
			cand = k
	if cand.is_empty():
		return
	var cid := int(turn.from)
	var other := int(turn.to)
	var art := str(cand.art)
	var o: Company = sim.company(other)
	if text.strip_edges() == "":
		var pool: Array = LINES[art]
		text = pool[(cid * 7 + int(turn.id)) % pool.size()] % o.company_name
	text = text.strip_edges().replace("\n", " ").left(200)
	var me: Company = sim.company(cid)
	var snap := {"cid": cid, "other": other, "art": art, "t": sim.game_min, "rep": me.reputation, "kosten": _conflict_costs(me), "rep_avg": _avg_rep(cid)}
	var res := execute(cid, other, cand)
	var to_whom := int(cand.get("partner", other)) if art == "buendnis_dritter" else other
	var err: String = sim.social.send_message(cid, to_whom, text, false)
	if err != "":
		sim.avatars[cid].say(text, false)   # Nachrichtenbudget erschoepft: nur Sprechblase
	var line := {"t": sim.game_min, "from": cid, "to": other, "text": text, "art": art, "richtung": cand.richtung,
		"ok": bool(res.ok), "ergebnis": str(res.msg).left(160), "source": source}
	lines.append(line)
	if lines.size() > LINE_LIMIT:
		lines.pop_front()
	last_pair[Social.pair_key(cid, other)] = sim.game_min
	stats.zeilen += 1
	stats[cand.richtung] = int(stats.get(cand.richtung, 0)) + 1
	stats["modell" if source == "Claude" else "regeln"] += 1
	sim.log_event("%s → %s: „%s“ [%s%s]" % [sim.company(cid).company_name, o.company_name, text, art, "" if res.ok else ", gescheitert"], "ai", cid)
	sim.memory.add_event(cid, "rivalitaet", "Gegenüber %s: %s (%s)" % [o.company_name, art, str(res.msg).left(100)])
	if res.ok and art in LEARNED_DEEDS:
		outcomes.append(snap)   # Stand vor der Tat: sofortige Folgen (Bussgeld, Ruf) zaehlen mit


## Ausgaben fuer Konflikte (Bussgelder, Sabotage/Blockade, Abwerbung, Kundenwerbung) abzueglich erhaltenem Schadensersatz.
static func _conflict_costs(c: Company) -> float:
	var t: Dictionary = c.ledger.totals
	return -(float(t.get("fines", 0.0)) + float(t.get("sabotage", 0.0)) + float(t.get("hire_fees", 0.0)) + float(t.get("marketing", 0.0))) - float(t.get("compensation", 0.0))


func _avg_rep(except: int) -> float:
	var s := 0.0
	var n := 0
	for c in sim.companies:
		if c.id != except and c.is_active():
			s += c.reputation
			n += 1
	return s / maxf(1.0, float(n))


func bad_experience(cid: int, art: String) -> bool:
	var l: Dictionary = learned.get("%d:%s" % [cid, art], {})
	return int(l.get("n", 0)) >= LEARN_MIN_SAMPLES and float(l.summe) / float(l.n) < LEARN_AVOID


## Folgen nach OUTCOME_DAYS messen: Rufaenderung gegenueber dem Durchschnitt der anderen, minus Konfliktkosten je 1000 EUR.
## Ergebnis ins Gedaechtnis der Firma und in die gelernte Bilanz je Tat.
func _measure(now: float) -> void:
	for o in outcomes.duplicate():
		if now - float(o.t) < GameCalendar.days_to_min(OUTCOME_DAYS):
			continue
		outcomes.erase(o)
		var c: Company = sim.company(int(o.cid))
		var rep_rel := (c.reputation - float(o.rep)) - (_avg_rep(c.id) - float(o.rep_avg))
		var cost := _conflict_costs(c) - float(o.kosten)
		var score := snappedf(rep_rel - cost / 1000.0, 0.1)
		var key := "%d:%s" % [c.id, o.art]
		var l: Dictionary = learned.get(key, {"n": 0, "summe": 0.0})
		l.n = int(l.n) + 1
		l.summe = float(l.summe) + score
		l["letzte"] = score
		learned[key] = l
		var txt := "Folgen von %s gegen %s nach %d Tagen: Ruf %+.1f gegenüber dem Durchschnitt, Konfliktkosten %s, Bilanz %+.1f." % [o.art,
			sim.company(int(o.other)).company_name, OUTCOME_DAYS, rep_rel, Catalog.money(cost), score]
		sim.memory.add_event(c.id, "erfahrung", txt)


## Tat zur Zeile ausfuehren; Worte allein (Stichelei, Beschwichtigung) verschieben nur die Spannung.
func execute(cid: int, other: int, cand: Dictionary) -> Dictionary:
	var R: Rivalry = sim.rivalry
	match str(cand.art):
		"deeskalieren":
			R.add_tension(cid, other, "beschwichtigt", "")
			return {"ok": true, "msg": "Spannung sinkt."}
		"sticheln":
			R.add_tension(cid, other, "stichelei", "")
			var c: Company = sim.company(cid)
			c.reputation = maxf(0.0, c.reputation - 0.5)
			return {"ok": true, "msg": "Stichelei."}
		"kooperation":
			return sim.social.create_offer(cid, other, "cooperation", {"duration_hours": 24.0, "note": "Frieden statt Streit"})
		"buendnis_dritter":
			return sim.social.create_offer(cid, int(cand.partner), "cooperation", {"duration_hours": 24.0, "note": "Gemeinsam gegen " + sim.company(other).company_name})
		"kunde_abwerben":
			return R.poach_customer(cid, int(cand.kunde))
		"fahrer_abwerben":
			var ws: Array = sim.personnel.employed(other).filter(func(w): return w.role == "worker" and not w.leaving)
			var top := 0.0
			for w in ws:
				top = maxf(top, float(w.wage))
			return R.poach_worker(cid, other, top + 4.0)
		"anzeigen":
			return R.report_rival(cid, other, "Streit eskaliert")
		"blockieren":
			return R.block_road(cid, other)
		"sabotieren":
			return R.execute_sabotage(cid, other, "smear_campaign")
		"polizei_rufen":
			var i := _blockade_against(cid)
			if i < 0:
				return {"ok": false, "msg": "Keine Blockade vor deinem Hof."}
			R.blockades[i].clear_at = minf(float(R.blockades[i].clear_at), sim.game_min + GameCalendar.days_to_min(Rivalry.POLICE_CALL_DAYS))
			return {"ok": true, "msg": "Die Polizei räumt in gut einer Stunde."}
	return {"ok": false, "msg": "Unbekannte Reaktion."}


## Letzte Zeilen eines Paares (fuer Modell, Anzeige und Beobachtung).
func pair_lines(a: int, b: int, n: int) -> Array:
	var key := Social.pair_key(a, b)
	return lines.filter(func(l): return Social.pair_key(int(l.from), int(l.to)) == key).slice(-n)


func to_dict() -> Dictionary:
	return {"enabled": enabled, "lines": lines.slice(-LINE_LIMIT), "last_pair": last_pair, "last_run": last_run, "last_provoke": last_provoke, "outcomes": outcomes, "learned": learned, "stats": stats.duplicate(), "next_turn": _next_turn}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	enabled = bool(d.get("enabled", false))
	lines = d.get("lines", [])
	last_pair = d.get("last_pair", {})
	last_run = float(d.get("last_run", 0.0))
	last_provoke = float(d.get("last_provoke", 0.0))
	outcomes = d.get("outcomes", [])
	learned = d.get("learned", {})
	stats = d.get("stats", stats)
	_next_turn = int(d.get("next_turn", 1))
