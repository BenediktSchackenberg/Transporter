class_name Rivalry
extends RefCounted
## Wettbewerb und Sabotage als reine Spielmechanik.
## Legal: Fahrer abwerben, Stammkunden abwerben, knappe Depots/Fahrer wegschnappen.
## Regelwidrig: Betriebsstoerung, Rufschaedigung -> Kosten, Abklingzeit, Entdeckungsrisiko,
## Bussgeld + Schadensersatz + Reputationsverlust. Gegenmassnahmen: Sicherheitsdienst, Versicherung.
## Schutzfrist pro Opfer und begrenzte Dauer verhindern, dass jemand dauerhaft handlungsunfaehig wird.

const POACH_COOLDOWN := 120.0
const REPORT_COOLDOWN := 2880.0         # Spielminuten zwischen zwei Anzeigen derselben Firma
const REPORT_TARGET_COOLDOWN := 4320.0  # dieselbe Zielfirma wird nicht haeufiger angezeigt
const REPORT_FALSE_FINE := 400.0        # unbegruendete Anzeige
const REPORT_ARREARS_FINE := 600.0      # Zahlungsrueckstand wird festgestellt

## Spannung je Firmenpaar (0-100) aus echten Vorfaellen; sinkt taeglich und durch Kooperation (Auftrag 12, docs/RIVALRY_DRAMA.md).
const TENSION := {
	"stammkunde_bedient": 4.0,      # Auftrag beim Stammkunden des anderen angenommen
	"abwerbeversuch": 5.0,
	"fahrer_abgeworben": 15.0,
	"kunde_abgeworben": 15.0,
	"ueberboten": 8.0,              # Grundstuecksgebot
	"anzeige": 20.0,                # Anzeige mit Beanstandung
	"anzeige_unbegruendet": 12.0,
	"sabotage_entdeckt": 35.0,
	"blockade": 25.0,               # Strassenblockade, Taeter ermittelt
	"geschaeft": -6.0,              # angenommenes Angebot
	"buendnis": -15.0,
}
const TENSION_DECAY_PER_DAY := 4.0
## Eskalationsleiter: ab welchem Wert eine Stufe naheliegt (1 Stichelei, 2 Provokation, 3 Anzeige, 4 Blockade, 5 Sabotage).
const STAGES := [15.0, 30.0, 50.0, 70.0, 85.0]
const STAGE_NAMES := ["ruhig", "Stichelei", "Provokation", "Anzeige", "Blockade", "Sabotage"]
const MAX_INCIDENTS := 80
## Strassenblockade (Stufe 4): Paletten auf eine Strasse nahe am Hof des Rivalen. Verboten: die Polizei raeumt, ermittelt meist den Taeter.
const BLOCK_COST := 600.0               # Paletten, Ware, Helfer
const BLOCK_CLEAR_MIN := Vector2(60.0, 150.0)   # Polizei raeumt nach so vielen Spielminuten
const BLOCK_FINE := 2500.0
const BLOCK_REP := 8.0
const BLOCK_DETECT := 0.7               # + 0.1 je Sicherheitsstufe des Opfers (Kameras)
const BLOCK_COOLDOWN := 1440.0          # hoechstens eine Blockade je Firma und Tag
const BLOCK_TARGET_COOLDOWN := 1440.0   # dasselbe Opfer hoechstens einmal je Tag
const BLOCK_DIST := Vector2i(2, 7)      # Strassenschritte vom Hof des Rivalen
const BLOCK_KEEP_CLEAR := 5             # Abstand zu Polizei, Arztpraxen, Klinik

var sim
var cooldowns := {}     # "art:firma" -> Spielminute
var tension := {}       # Social.pair_key -> 0..100
var incidents: Array = []   # {t, a, b, art, delta, text}; a = Verursacher, b = Betroffener
var blockades: Array = []   # {cell: [x, y], by, target, placed, clear_at}


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
		add_tension(cid, target, "sabotage_entdeckt", s.name)
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
		add_tension(cid, target, "abwerbeversuch", w.name)
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
	add_tension(cid, target, "fahrer_abgeworben", w.name)
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
		add_tension(cid, loyal, "kunde_abgeworben", b.name)
		return {"ok": true, "msg": "%s ist jetzt dein Stammkunde." % b.name}
	return {"ok": true, "msg": "%s bleibt bei %s (Reputation zu niedrig oder Pech)." % [b.name, t.company_name]}


## Anzeige beim Buergermeister: Das Amt prueft die Zielfirma sofort (Steuer, Zahlungsrueckstaende, verwahrloste Einrichtungen).
## Gibt es Beanstandungen, tragen sie die Folgen (Nachforderung, Bussgeld, Auflage, Rufverlust). Gibt es keine, zahlt der Anzeigende ein
## Bussgeld und verliert Ruf und Vertrauen: wer ohne Anlass anzeigt, schadet sich selbst.
func report_rival(cid: int, target: int, reason: String = "") -> Dictionary:
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	if t == null or target == cid:
		return {"ok": false, "msg": "Ungültiges Ziel."}
	if not t.is_active() and t.status != "warnung":
		return {"ok": false, "msg": "%s steht bereits unter Insolvenzverwaltung." % t.company_name}
	var key := "report:%d" % cid
	var tkey := "reported:%d" % target
	if _cooldown_left(key) > 0.0:
		return {"ok": false, "msg": "Die nächste Anzeige ist erst in %d Spielminuten möglich." % int(_cooldown_left(key))}
	if _cooldown_left(tkey) > 0.0:
		return {"ok": false, "msg": "%s wurde kürzlich geprüft (noch %d Spielminuten)." % [t.company_name, int(_cooldown_left(tkey))]}
	cooldowns[key] = sim.game_min + REPORT_COOLDOWN
	cooldowns[tkey] = sim.game_min + REPORT_TARGET_COOLDOWN
	var findings: Array = []
	var audit: Dictionary = sim.public_sector.audit(t, GameCalendar.month_of(sim.game_min))
	if float(audit.arrears) > 0.01:
		findings.append("Steuernachforderung %s" % Catalog.money(float(audit.arrears)))
	if sim.insolvency.has_arrears(t) or t.ledger.cash < 0.0:
		var fine := minf(REPORT_ARREARS_FINE, maxf(0.0, t.ledger.cash))
		if fine > 0.01:
			t.ledger.book("fines", -fine, true, "Zahlungsrückstand nach Anzeige", sim.game_min)
		findings.append("Zahlungsrückstand")
	var orders: int = sim.oversight.inspect_company_now(target)
	if orders > 0:
		findings.append("%d Auflage(n) der Gewerbeaufsicht" % orders)
	if findings.is_empty():
		var f2 := minf(REPORT_FALSE_FINE, maxf(0.0, c.ledger.cash))
		if f2 > 0.01:
			c.ledger.book("fines", -f2, true, "Unbegründete Anzeige gegen " + t.company_name, sim.game_min)
		c.reputation = maxf(0.0, c.reputation - 3.0)
		sim.social.add_trust(cid, target, -20.0)
		add_tension(cid, target, "anzeige_unbegruendet", reason)
		sim.log_event("Anzeige von %s gegen %s: ohne Beanstandung, der Anzeigende zahlt %s Bußgeld." % [c.company_name, t.company_name, Catalog.money(f2)], "warn", cid)
		sim.notify(target, "Eine Anzeige gegen dich wurde geprüft und blieb ohne Beanstandung.")
		return {"ok": true, "msg": "Das Amt fand nichts. Unbegründete Anzeige: %s Bußgeld, Ruf −3." % Catalog.money(f2)}
	t.reputation = maxf(0.0, t.reputation - 3.0)
	add_tension(cid, target, "anzeige", ", ".join(findings))
	t.add_key_event("Nach Anzeige geprüft: " + ", ".join(findings), sim.game_min)
	sim.log_event("Anzeige von %s: %s wird geprüft – %s." % [c.company_name, t.company_name, ", ".join(findings)], "bad", target)
	sim.notify(target, "Nach einer Anzeige hat das Amt dich geprüft: %s." % ", ".join(findings))
	return {"ok": true, "msg": "Prüfung bei %s: %s." % [t.company_name, ", ".join(findings)]}


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


# ------------------------------------------------------------------ Strassenblockade
func check_block(cid: int, target: int) -> String:
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	if t == null or target == cid or t.depots.is_empty():
		return "Ungültiges Ziel."
	var v := get_tension(cid, target)
	if v < STAGES[3]:
		return "Spannung mit %s erst %d – eine Blockade kommt erst ab %d (Stufe Blockade) in Frage." % [t.company_name, int(v), int(STAGES[3])]
	if _cooldown_left("block:%d" % cid) > 0.0:
		return "Nur eine Blockade je Tag: wieder in %d Spielminuten." % int(_cooldown_left("block:%d" % cid))
	if _cooldown_left("blocked:%d" % target) > 0.0:
		return "%s wurde heute schon blockiert." % t.company_name
	if c.ledger.cash < BLOCK_COST:
		return "Nicht genug Bargeld (%s für Paletten und Helfer)." % Catalog.money(BLOCK_COST)
	if block_cell(target).x < 0:
		return "Keine geeignete Straße nahe am Hof von %s (Umfahrung oder Abstand zu Polizei/Ärzten fehlt)." % t.company_name
	return ""


## Strassenzelle 2-7 Schritte vom Hof entfernt, die eine Umfahrung zulaesst und weit genug von Polizei, Aerzten und Klinik liegt.
func block_cell(target: int) -> Vector2i:
	var start: Vector2i = sim.depot_road(target)
	var protected: Array = []
	for b in sim.city.buildings:
		if b.role in ["police", "doctor"] or b.type == "clinic":
			protected.append(b.road)
	var dist := {start: 0}
	var queue: Array = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		var d: int = dist[p]
		if d >= BLOCK_DIST.x and _block_ok(p, start, protected):
			return p
		if d >= BLOCK_DIST.y:
			continue
		for q in _road_neighbors(p):
			if not dist.has(q) and not sim.nav.is_blocked_road(q):
				dist[q] = d + 1
				queue.append(q)
	return Vector2i(-1, -1)


func _road_neighbors(p: Vector2i) -> Array:
	var out: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if sim.city.is_road(p + dv):
			out.append(p + dv)
	return out


func _block_ok(p: Vector2i, start: Vector2i, protected: Array) -> bool:
	if sim.nav.is_blocked_road(p) or sim.city.road_mask(p) not in [5, 10]:
		return false   # nur gerade Strassenstuecke, keine Kreuzungen
	for r in protected:
		if absi(r.x - p.x) + absi(r.y - p.y) < BLOCK_KEEP_CLEAR:
			return false
	# Umfahrung: vom Hof aus muessen beide Enden des Stuecks weiter erreichbar sein
	sim.nav.road.set_point_solid(p, true)
	var ok := true
	for q in _road_neighbors(p):
		if q != start and sim.nav.road_path(start, q).is_empty():
			ok = false
	sim.nav.road.set_point_solid(p, false)
	return ok


func block_road(cid: int, target: int) -> Dictionary:
	var err := check_block(cid, target)
	if err != "":
		return {"ok": false, "msg": err}
	var now: float = sim.game_min
	var c: Company = sim.company(cid)
	var t: Company = sim.company(target)
	var cell := block_cell(target)
	var clear_at: float = now + sim.rng.randf_range(BLOCK_CLEAR_MIN.x, BLOCK_CLEAR_MIN.y)
	c.ledger.book("sabotage", -BLOCK_COST, true, "Paletten-Blockade gegen " + t.company_name, now)
	cooldowns["block:%d" % cid] = now + BLOCK_COOLDOWN
	cooldowns["blocked:%d" % target] = now + BLOCK_TARGET_COOLDOWN
	sim.nav.add_roadwork(cell, clear_at)
	var txt := "Paletten blockieren eine Straße im %s nahe %s" % [Catalog.DISTRICTS[sim.city.district_of(cell)], t.company_name]
	sim.traffic_events.append({"kind": "blockade", "cells": [cell], "until": clear_at, "text": txt})
	blockades.append({"cell": [cell.x, cell.y], "by": cid, "target": target, "placed": now, "clear_at": clear_at})
	sim.log_event("Verkehr: %s – die Polizei ist unterwegs." % txt, "bad", target)
	sim.notify(target, "Jemand hat die Straße bei (%d,%d) nahe deinem Hof mit Paletten zugestellt. Deine Fahrzeuge fahren Umwege." % [cell.x, cell.y])
	sim.bark(target, "sabotage")
	return {"ok": true, "msg": "Paletten liegen bei (%d,%d) vor dem Hof von %s. Die Polizei räumt in ein bis zwei Stunden und ermittelt." % [cell.x, cell.y, t.company_name]}


func blockade_at(p: Vector2i) -> bool:
	return blockades.any(func(b): return int(b.cell[0]) == p.x and int(b.cell[1]) == p.y)


## Polizei raeumt faellige Blockaden und ermittelt den Taeter.
func tick(now: float) -> void:
	for b in blockades.duplicate():
		if now < float(b.clear_at):
			continue
		blockades.erase(b)
		var cell := Vector2i(int(b.cell[0]), int(b.cell[1]))
		if sim.nav.roadworks.has(cell):
			sim.nav.roadworks.erase(cell)
			sim.nav.road.set_point_solid(cell, false)
		for e in sim.traffic_events.duplicate():
			if e.kind == "blockade" and cell in e.cells:
				sim.traffic_events.erase(e)
		var c: Company = sim.company(int(b.by))
		var t: Company = sim.company(int(b.target))
		if sim.rng.randf() < BLOCK_DETECT + 0.1 * t.security_level:
			var fine := minf(BLOCK_FINE, maxf(0.0, c.ledger.cash))
			if fine > 0.01:
				c.ledger.book("fines", -fine, true, "Bußgeld Straßenblockade", now)
			c.reputation = maxf(0.0, c.reputation - BLOCK_REP)
			sim.social.add_trust(c.id, t.id, -30.0)
			add_tension(c.id, t.id, "blockade", "Straße (%d,%d)" % [cell.x, cell.y])
			c.add_key_event("Blockade gegen %s ermittelt" % t.company_name, now)
			sim.log_event("Polizei räumt die Paletten-Blockade: %s war es (Bußgeld %s, Ruf −%d)." % [c.company_name, Catalog.money(fine), int(BLOCK_REP)], "bad", c.id)
			sim.notify(t.id, "Die Polizei hat die Blockade geräumt. Täter: %s." % c.company_name)
			sim.notify(c.id, "Die Polizei hat deine Blockade geräumt und dich ermittelt: Bußgeld %s, Ruf −%d." % [Catalog.money(fine), int(BLOCK_REP)])
		else:
			sim.log_event("Polizei räumt die Paletten-Blockade vor dem Hof von %s; Täter unbekannt." % t.company_name, "warn", t.id)
			sim.notify(t.id, "Die Polizei hat die Blockade geräumt; der Täter ist unbekannt.")


# ------------------------------------------------------------------ Spannung
func get_tension(a: int, b: int) -> float:
	return float(tension.get(Social.pair_key(a, b), 0.0))


static func stage_of(value: float) -> int:
	var s := 0
	for th in STAGES:
		if value >= th:
			s += 1
	return s


## Vorfall zwischen Verursacher a und Betroffenem b verbuchen (art aus TENSION).
func add_tension(a: int, b: int, art: String, text: String = "") -> void:
	if a == b or a < 0 or b < 0 or not TENSION.has(art):
		return
	var key := Social.pair_key(a, b)
	var before := float(tension.get(key, 0.0))
	var after := clampf(before + float(TENSION[art]), 0.0, 100.0)
	tension[key] = after
	incidents.append({"t": sim.game_min, "a": a, "b": b, "art": art, "delta": snappedf(after - before, 0.1), "text": text})
	if incidents.size() > MAX_INCIDENTS:
		incidents.pop_front()
	var st := stage_of(after)
	if st > stage_of(before):
		sim.log_event("Spannung zwischen %s und %s steigt: %s (%d)." % [sim.company(a).company_name, sim.company(b).company_name, STAGE_NAMES[st], int(after)], "warn")


func on_day() -> void:
	for key in tension.keys():
		var v := float(tension[key]) - TENSION_DECAY_PER_DAY
		if v <= 0.0:
			tension.erase(key)
		else:
			tension[key] = v


func _incidents_of(a: int, b: int, n: int) -> Array:
	return incidents.filter(func(i): return (int(i.a) == a and int(i.b) == b) or (int(i.a) == b and int(i.b) == a)).slice(-n)


func _incident_view(i: Dictionary, cid: int) -> Dictionary:
	return {"zeit": Catalog.game_minutes_to_text(float(i.t)), "art": i.art, "durch": "dich" if int(i.a) == cid else ("gegen dich" if int(i.b) == cid else int(i.a)), "text": i.text}


## Beobachtung fuer eine Firma: Spannung zu jedem Konkurrenten mit Stufe und letzten Vorfaellen.
func summary_of(cid: int) -> Array:
	var out: Array = []
	for o in sim.companies:
		if o.id == cid:
			continue
		var v := get_tension(cid, o.id)
		if v <= 0.0:
			continue
		out.append({"firma": o.id, "name": o.company_name, "spannung": int(v), "stufe": STAGE_NAMES[stage_of(v)],
			"vorfaelle": _incidents_of(cid, o.id, 3).map(func(i): return _incident_view(i, cid))})
	out.sort_custom(func(x, y): return x.spannung > y.spannung)
	return out


## Beobachtung fuer den Buergermeister: angespannteste Paare, Vorfaelle der letzten 7 Tage, mittlere Unruhe.
func mayor_summary() -> Dictionary:
	var pairs: Array = []
	var total := 0.0
	for key in tension:
		var ids: PackedStringArray = str(key).split("-")
		var a := int(ids[0])
		var b := int(ids[1])
		var v := float(tension[key])
		total += v
		pairs.append({"firmen": [a, b], "namen": [sim.company(a).company_name, sim.company(b).company_name], "spannung": int(v), "stufe": STAGE_NAMES[stage_of(v)]})
	pairs.sort_custom(func(x, y): return x.spannung > y.spannung)
	var week: Array = incidents.filter(func(i): return sim.game_min - float(i.t) < GameCalendar.days_to_min(7) and float(i.delta) > 0.0)
	var n: int = sim.companies.size()
	var pair_count := maxi(1, n * (n - 1) / 2)
	return {"paare": pairs.slice(0, 5), "vorfaelle_7_tage": week.size(), "unruhe": snappedf(total / float(pair_count), 0.1),
		"letzte": week.slice(-4).map(func(i): return {"zeit": Catalog.game_minutes_to_text(float(i.t)), "art": i.art, "verursacher": int(i.a), "betroffen": int(i.b)})}


func to_dict() -> Dictionary:
	return {"cooldowns": cooldowns, "tension": tension, "incidents": incidents, "blockades": blockades}


func from_dict(d: Dictionary) -> void:
	cooldowns = d.cooldowns
	tension = d.get("tension", {})
	incidents = d.get("incidents", [])
	blockades = d.get("blockades", [])
	for b in blockades:
		sim.nav.add_roadwork(Vector2i(int(b.cell[0]), int(b.cell[1])), float(b.clear_at))
