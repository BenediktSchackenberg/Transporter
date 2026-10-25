class_name Rivalry
extends RefCounted
## Wettbewerb und Sabotage als reine Spielmechanik.
## Legal: Fahrer abwerben, Stammkunden abwerben, knappe Depots/Fahrer wegschnappen.
## Regelwidrig: Betriebsstoerung, Rufschaedigung -> Kosten, Abklingzeit, Entdeckungsrisiko,
## Bussgeld + Schadensersatz + Reputationsverlust. Gegenmassnahmen: Sicherheitsdienst, Versicherung.
## Schutzfrist pro Opfer und begrenzte Dauer verhindern, dass jemand dauerhaft handlungsunfaehig wird.

const POACH_COOLDOWN := 120.0

var sim
var cooldowns := {}     # "art:firma" -> Spielminute


func setup(simulation) -> void:
	sim = simulation


func _cooldown_left(key: String) -> float:
	return maxf(0.0, cooldowns.get(key, 0.0) - sim.game_min)


func check_sabotage(cid: int, target: int, kind: String) -> String:
	if not Catalog.SABOTAGE.has(kind):
		return "Unbekannte Sabotageart '%s'. Erlaubt: %s" % [kind, ", ".join(Catalog.SABOTAGE.keys())]
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	if t == null or target == cid:
		return "Ungültiges Ziel."
	var s: Dictionary = Catalog.SABOTAGE[kind]
	if sim.game_min < c.sabotage_ready_at:
		return "Sabotage-Abklingzeit läuft noch %d Spielminuten." % int(c.sabotage_ready_at - sim.game_min)
	if sim.game_min < t.protected_until:
		return "%s steht noch %d Spielminuten unter Schutzfrist." % [t.company_name, int(t.protected_until - sim.game_min)]
	if c.ledger.cash < s.cost:
		return "Nicht genug Bargeld (%s benötigt)." % Catalog.money(s.cost)
	return ""


func execute_sabotage(cid: int, target: int, kind: String) -> Dictionary:
	var err := check_sabotage(cid, target, kind)
	if err != "":
		return {"ok": false, "msg": err}
	var now: float = sim.game_min
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	var s: Dictionary = Catalog.SABOTAGE[kind]
	c.ledger.book("sabotage", -s.cost, true, "%s gegen %s" % [s.name, t.company_name], now)
	c.sabotage_ready_at = now + Catalog.SABOTAGE_COOLDOWN_MIN
	var success: bool = sim.rng.randf() < maxf(0.1, s.success - 0.2 * t.security_level)
	var detected: bool = sim.rng.randf() < s.detect + 0.2 * t.security_level
	var result := ""
	if success:
		t.protected_until = now + Catalog.SABOTAGE_PROTECTION_MIN
		if kind == "depot_disruption":
			t.disrupted_until = now + s.duration_min
			sim.log_event("Betriebsstörung im Depot von %s! (%d Spielminuten)" % [t.company_name, int(s.duration_min)], "bad", target)
		else:
			t.reputation = maxf(0.0, t.reputation - s.rep_damage)
			sim.log_event("Gerüchte über %s machen die Runde (Reputation −%d)." % [t.company_name, int(s.rep_damage)], "bad", target)
		if t.insurance:
			t.ledger.book("insurance_payout", s.insurance_payout, true, "Versicherung: " + s.name, now)
		t.add_key_event("Opfer von Sabotage: " + s.name, now)
		sim.bark(target, "sabotage")
		sim.notify(target, "Sabotage gegen dich: %s.%s" % [s.name, " Die Versicherung zahlt %s." % Catalog.money(s.insurance_payout) if t.insurance else ""])
		c.stats.sabotage_ok += 1
		result = "%s gegen %s war erfolgreich." % [s.name, t.company_name]
	else:
		result = "%s gegen %s ist fehlgeschlagen." % [s.name, t.company_name]
	if detected:
		c.ledger.book("fines", -(s.fine + s.compensation), true, "Bußgeld/Schadensersatz " + s.name, now)
		t.ledger.book("compensation", s.compensation, true, "Schadensersatz von " + c.company_name, now)
		c.reputation = maxf(0.0, c.reputation - s.rep_loss)
		sim.social.add_trust(cid, target, -40.0)
		var breach: bool = sim.social.has_pact(cid, target)
		if breach:
			c.reputation = maxf(0.0, c.reputation - Catalog.PACT_BREACH_REP)
			sim.social.break_pact(cid, target)
			sim.social.add_trust(cid, target, -60.0)
		c.stats.sabotage_caught += 1
		var txt := "%s wurde bei %s gegen %s erwischt: Bußgeld %s, Schadensersatz %s%s." % [c.company_name, s.name,
			t.company_name, Catalog.money(s.fine), Catalog.money(s.compensation), ", Paktbruch!" if breach else ""]
		sim.log_event(txt, "bad", cid)
		c.add_key_event("Bei Sabotage erwischt (%s)" % s.name, now)
		sim.notify(target, "Der Täter wurde ermittelt: %s." % c.company_name)
		result += " Du wurdest erwischt: Bußgeld und Schadensersatz."
	sim.sfx.emit("sabotage")
	return {"ok": true, "msg": result}


## Legal: einen Arbeiter des Konkurrenten mit hoeherem Lohn abwerben. Chance haengt von Lohnabstand und Loyalitaet ab.
## Ein Arbeiter hat immer nur einen Arbeitgeber; Fahrer wechseln erst nach der laufenden Fahrt.
func poach_worker(cid: int, target: int, wage: float) -> Dictionary:
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	if t == null or target == cid:
		return {"ok": false, "msg": "Ungültiges Ziel."}
	var key := "poach_worker:%d" % cid
	if _cooldown_left(key) > 0.0:
		return {"ok": false, "msg": "Abwerben erst wieder in %d Spielminuten möglich." % int(_cooldown_left(key))}
	var candidates: Array = sim.personnel.employed(target).filter(func(w): return not w.leaving and w.role == "worker")
	if candidates.size() < 2:
		return {"ok": false, "msg": "%s hat zu wenig Personal – den letzten Arbeiter darf man nicht abwerben." % t.company_name}
	if c.ledger.cash < Catalog.POACH_FEE:
		return {"ok": false, "msg": "Nicht genug Bargeld für die Abwerbegebühr."}
	candidates.sort_custom(func(x, y): return x.loyalty < y.loyalty)
	var w: Worker = candidates[0]
	if wage < w.wage + 2.0:
		return {"ok": false, "msg": "Angebot zu niedrig: %s verdient %.0f EUR/h." % [w.name, w.wage]}
	cooldowns[key] = sim.game_min + POACH_COOLDOWN
	c.ledger.book("hire_fees", -Catalog.POACH_FEE, true, "Abwerbeversuch", sim.game_min)
	var chance := clampf((wage - w.wage) / w.wage * 2.5 - (w.loyalty - 50.0) / 100.0, 0.0, 0.85)
	if sim.rng.randf() >= chance:
		w.loyalty = minf(100.0, w.loyalty + 5.0)
		sim.notify(target, "%s hat versucht, deinen Arbeiter %s abzuwerben." % [c.company_name, w.name])
		return {"ok": true, "msg": "%s hat das Angebot abgelehnt (Chance war %d %%)." % [w.name, int(chance * 100)]}
	for task in sim.personnel.tasks.values():
		if task.worker_id == w.id and not task.is_final():
			sim.personnel.cancel_task(task, "Arbeiter abgeworben")
	w.wage = wage
	w.loyalty = 40.0
	w.foreman = ""
	var v: FleetVehicle = sim.vehicles.get(w.vehicle_id)
	if v and v.state != "idle":
		w.leaving = true
		w.transfer_to = cid
	else:
		w.vehicle_id = -1
		w.employer = cid
	sim.log_event("%s wirbt %s von %s ab (%.0f EUR/h)." % [c.company_name, w.name, t.company_name, wage], "warn", cid)
	sim.notify(target, "%s hat deinen Arbeiter %s abgeworben%s." % [c.company_name, w.name, " (wechselt nach der aktuellen Fahrt)" if w.leaving else ""])
	return {"ok": true, "msg": "%s (%s) wechselt zu dir." % [w.name, w.id]}


func poach_customer(cid: int, building_id: int) -> Dictionary:
	var c: Company = sim.company(cid)
	var b: Dictionary = sim.city.building(building_id)
	var loyal: int = sim.loyal_company(building_id)
	if b.is_empty() or loyal < 0:
		return {"ok": false, "msg": "Gebäude %d ist kein Stammkunde einer Firma." % building_id}
	if loyal == cid:
		return {"ok": false, "msg": "%s ist bereits dein Stammkunde." % b.name}
	var key := "poach_customer:%d" % cid
	if _cooldown_left(key) > 0.0:
		return {"ok": false, "msg": "Kundenwerbung erst wieder in %d Spielminuten möglich." % int(_cooldown_left(key))}
	if c.ledger.cash < 800.0:
		return {"ok": false, "msg": "Nicht genug Bargeld (800 EUR Marketing)."}
	cooldowns[key] = sim.game_min + POACH_COOLDOWN
	c.ledger.book("marketing", -800.0, true, "Kundenwerbung " + b.name, sim.game_min)
	var t: Company = sim.company(loyal)
	if c.reputation >= t.reputation - 5.0 and sim.rng.randf() < 0.6:
		sim.customers[building_id].loyal = cid
		sim.customers[building_id].streak = {}
		sim.log_event("%s wirbt %s als Stammkunden von %s ab." % [c.company_name, b.name, t.company_name], "warn", cid)
		sim.notify(loyal, "%s hat deinen Stammkunden %s abgeworben." % [c.company_name, b.name])
		return {"ok": true, "msg": "%s ist jetzt dein Stammkunde." % b.name}
	return {"ok": true, "msg": "%s bleibt bei %s (Reputation zu niedrig oder Pech)." % [b.name, t.company_name]}


func buy_security(cid: int, level: int) -> Dictionary:
	var c: Company = sim.company(cid)
	if level < 0 or level > 2:
		return {"ok": false, "msg": "Sicherheitsstufe muss 0, 1 oder 2 sein."}
	if level <= c.security_level:
		c.security_level = level
		return {"ok": true, "msg": "Sicherheitsstufe auf %d gesetzt." % level}
	var cost: float = Catalog.SECURITY_INSTALL[level] - Catalog.SECURITY_INSTALL[c.security_level]
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Nicht genug Bargeld (%s)." % Catalog.money(cost)}
	c.ledger.book("security", -cost, true, "Sicherheitstechnik Stufe %d" % level, sim.game_min)
	c.security_level = level
	return {"ok": true, "msg": "Sicherheitsstufe %d aktiv (laufend %s/Tag)." % [level, Catalog.money(Catalog.SECURITY_PER_DAY[level])]}


func to_dict() -> Dictionary:
	return {"cooldowns": cooldowns}


func from_dict(d: Dictionary) -> void:
	cooldowns = d.cooldowns
