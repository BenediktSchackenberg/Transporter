class_name RuleBrain
extends RefCounted
## Regelbasierte Entscheidungen auf Basis derselben Beobachtung, die auch das Sprachmodell bekommt.
## Verwendet fuer (1) den DEMO-Adapter und (2) den sichtbar markierten Ersatzmodus bei API-Ausfall.
## Keine KI – einfache, persoenlichkeitsabhaengige Heuristiken, die trotzdem auf Gewinn spielen.

const LINES := {
	"kostenoptimierer": ["Jeder Kilometer kostet. Ich fahre nur, was sich rechnet.", "Solide Zahlen schlagen große Sprüche.",
		"Wer spart, hat in der Not.", "Effizienz ist kein Zufall."],
	"wachstum": ["Ich kaufe die Stadt Straße für Straße.", "Zu langsam, Leute! Meine Flotte wächst.",
		"Große Aufträge? Her damit.", "Wer nicht wächst, verschwindet."],
	"netzwerker": ["Gemeinsam fahren wir alle besser. Wer hat freie Kapazität?", "Ich biete faire Partnerschaften an.",
		"Vertrauen ist die beste Währung.", "Lasst uns Aufträge teilen statt Preise zu ruinieren."],
	"risikospieler": ["Na, schon nervös? Ich hab da so meine Pläne …", "Glück ist, wenn man es erzwingt.",
		"Eure Fahrzeuge stehen übrigens sehr … ungeschützt herum.", "Hohe Risiken, hohe Gewinne!"],
}
const BUFFER := {"kostenoptimierer": 20000.0, "wachstum": 6000.0, "netzwerker": 12000.0, "risikospieler": 9000.0}
const MAX_ACTIONS := 6


static func decide(obs: Dictionary, personality: String, rng: RandomNumberGenerator) -> Dictionary:
	if obs.is_empty():
		return {"summary": "Ich warte ab.", "actions": [{"action": "wait"}], "memory": ""}
	var me: Dictionary = obs.ich
	var models: Dictionary = obs.fahrzeugmodelle
	var res: Dictionary = obs.ressourcen
	var actions: Array = []
	var reasons: Array = []
	var cash := float(me.bargeld)
	var buffer: float = BUFFER.get(personality, 12000.0)
	var planned: Array = obs.figur.geplante_aktionen
	var load: PackedStringArray = str(me.buero.laufende_auftraege).split("/")
	var active := load[0].to_int()
	var capacity := load[1].to_int()
	var busy_vehicles := {}      # Fahrzeuge mit offener Fahr-/Reparaturaufgabe
	for t in obs.aufgaben:
		if t.status not in ["abgeschlossen", "fehlgeschlagen", "abgebrochen"] and t.ziel.has("vehicle_id"):
			busy_vehicles[int(t.ziel.vehicle_id)] = t.art
	var free_staff: Array = obs.personal.filter(func(w): return w.rolle == "Arbeiter" and str(w.status).begins_with("bereit") \
		and int(w.fahrzeug) < 0 and int(w.erschoepfung) < 85)
	var attacked := false
	for e in obs.ergebnisse_deiner_aktionen + obs.ereignisse:
		var tx := str(e)
		if tx.contains("Sabotage gegen dich") or tx.contains("sabotiert") or tx.contains("Saboteur") or tx.contains("abgeworben"):
			attacked = true
	# 1) Ausfaelle und Verschleiss: Mechaniker vor Ort (mit Teilen), sonst Werkstatt
	for v in obs.fahrzeuge:
		var needs: bool = v.status == "Panne" or (int(v.zustand) < 45 and v.status == "bereit")
		if not needs or busy_vehicles.has(int(v.id)):
			continue
		var parts_needed := maxi(1, ceili((100.0 - float(v.zustand)) / 20.0))
		var mech := _pick(free_staff, "reparieren", v.pos)
		if not mech.is_empty() and int(me.vorraete.ersatzteile) >= parts_needed:
			actions.append({"action": "repair_vehicle", "vehicle_id": v.id, "worker_id": mech.id})
			free_staff.erase(mech)
			busy_vehicles[int(v.id)] = "reparieren"
			reasons.append("schicke %s zur Reparatur von #%d" % [mech.name, v.id])
		elif not mech.is_empty() and cash > 3000.0:
			var src := _supply(res, "Ersatzteile", parts_needed)
			if not src.is_empty():
				actions.append({"action": "buy_supplies", "resource_id": src.id, "amount": parts_needed + 2})
				reasons.append("kaufe Ersatzteile für #%d" % v.id)
		elif v.status == "Panne" or v.fahrer != null:
			actions.append({"action": "repair_vehicle", "vehicle_id": v.id})
			busy_vehicles[int(v.id)] = "werkstatt"
			reasons.append("lasse #%d in der Werkstatt reparieren" % v.id)
	# 2) Fahrzeuge ohne Fahrer besetzen, notfalls Fahrer anwerben
	for v in obs.fahrzeuge:
		if v.fahrer != null or busy_vehicles.has(int(v.id)) or v.status == "Panne":
			continue
		var d := _pick(free_staff, "fahren", v.pos)
		if not d.is_empty():
			actions.append({"action": "assign_worker_task", "kind": "fahren", "worker_id": d.id, "vehicle_id": v.id})
			free_staff.erase(d)
			busy_vehicles[int(v.id)] = "fahren"
			reasons.append("setze %s ans Steuer von #%d" % [d.name, v.id])
		elif "recruit_worker" not in planned:
			var cand := _best_candidate(res.arbeitskraefte, "fahren")
			if not cand.is_empty() and cash > float(cand.anwerbung) + 3000.0:
				actions.append({"action": "recruit_worker", "worker_id": cand.id})
				planned.append("recruit_worker")
				reasons.append("werbe Fahrer %s an, weil #%d keinen Fahrer hat" % [cand.name, v.id])
	# 3) angenommene, noch nicht disponierte Auftraege zuweisen
	var ready: Array = obs.fahrzeuge.filter(func(v): return v.status in ["bereit", "fährt zum Depot"] \
		and v.warteschlange.is_empty() and v.fahrer != null and not busy_vehicles.has(int(v.id)) and int(v.zustand) >= 45)
	for k in obs.meine_auftraege:
		if k.status != "accepted":
			continue
		var v := _best_vehicle(ready, k.menge, k.anforderungen.contains("Kühlung"), k.anforderungen.contains("LKW"), models)
		if not v.is_empty():
			actions.append({"action": "assign_transport", "vehicle_id": v.id, "contract_id": k.id})
			ready.erase(v)
	# 4) freie Fahrzeuge mit lohnenden Marktauftraegen versorgen (im Rahmen der Buero-Kapazitaet)
	var market: Array = obs.markt.duplicate()
	var unserved := 0
	for v in ready:
		if active >= capacity:
			unserved += 1
			continue
		var best := _best_contract(market, v, models[v.modell], float(me.reputation))
		if best.is_empty():
			unserved += 1
			continue
		actions.append({"action": "accept_contract", "contract_id": best.id, "vehicle_id": v.id})
		market.erase(best)
		active += 1
		reasons.append("nehme %s für #%d an (%d EUR, %s)" % [best.id, v.id, best.verguetung, best.bezeichnung])
	# 4b) Angebote an mich pruefen
	for o in obs.angebote_an_dich:
		var accept := false
		match o.art:
			"payment":
				accept = true
			"cooperation":
				accept = personality != "risikospieler" or rng.randf() < 0.4
			"transfer_contract":
				accept = not ready.is_empty() and o.beschreibung.contains("zahlt") \
					and _price(o.beschreibung) <= float(o.get("auftrag_verguetung", 0)) * 0.3
			"sell_vehicle":
				accept = cash > 30000.0 and _price(o.beschreibung) < 9000.0 and _free_slots(me) > 0
			"capacity_rental":
				accept = market.size() > ready.size() + 1 and cash > _price(o.beschreibung) * 3.0
			"storage_share", "split_contract":
				accept = not ready.is_empty() and personality != "risikospieler"
		actions.append({"action": "accept_trade" if accept else "reject_trade", "offer_id": o.id})
		if accept:
			reasons.append("nehme Angebot %s an" % o.id)
	# 5) neue Auftraege sammeln, wenn der bekannte Markt nicht reicht
	if (unserved > 0 or market.size() < 4) and int(obs.unbekannte_offene_auftraege) > 0 \
			and "collect_contracts" not in planned and active < capacity:
		actions.append({"action": "collect_contracts"})
		planned.append("collect_contracts")
		reasons.append("hole neue Aufträge an der Jobbörse")
	# 6) Treibstoff guenstig auf Vorrat statt teuer nachtanken
	# Treibstoff kommt erst nach Zapfen und Lieferung im Depot an: Vorrat plus unterwegs zaehlen, frueh bestellen,
	# und eine feste Nachtank-Regel der Engine nutzen (Routine, spart KI-Anfragen).
	var fuel_have := int(me.vorraete.treibstoff_l) + int(me.vorraete.get("treibstoff_unterwegs_l", 0))
	var fuel_vehicles := maxi(1, obs.fahrzeuge.size())
	if not bool(me.vorraete.get("nachtank_regel", false)) and "schedule_refueling" not in planned and cash > 3000.0:
		actions.append({"action": "schedule_refueling", "below_l": 250 * fuel_vehicles, "buy_l": 500 * mini(2, fuel_vehicles)})
		planned.append("schedule_refueling")
		reasons.append("lege eine feste Nachtank-Regel an")
	if fuel_have < 300 * fuel_vehicles and cash > 3000.0:
		var fuel := _supply(res, "Treibstoff", 400)
		if not fuel.is_empty() and float(fuel.preis) < float(res.nachtanken_ohne_vorrat_preis_l):
			actions.append({"action": "buy_supplies", "resource_id": fuel.id, "amount": 400 * mini(2, fuel_vehicles)})
			reasons.append("bestelle Treibstoff früh (%.2f EUR/l, Lieferung dauert)" % fuel.preis)
	var growth: Array = []   # Investitionen laufen als Plan mit einzeln ausgefuehrten Schritten
	var yard: Dictionary = obs.get("betriebshof", {})
	var yard_sug: Dictionary = yard.get("bauvorschlaege_xy_rot", {})
	var plot_id := int(me.depots[0].id)
	# 7) Wachstum: Fahrzeug aus dem Haendlerbestand + Fahrer
	var good_jobs := market.filter(func(k): return k.verguetung > 250).size()
	if ready.is_empty() and good_jobs >= 3 and _free_slots(me) > 0 and active < capacity and "buy_vehicle" not in planned:
		var wanted := ["van", "transporter", "cargobike"]
		if personality == "wachstum" and good_jobs >= 6:
			wanted = ["truck", "transporter", "van"]
		var offer := _cheapest_offer(res.fahrzeugangebote, wanted)
		if not offer.is_empty() and cash > float(offer.preis) + buffer:
			growth.append({"action": "buy_vehicle", "offer_id": offer.id})
			if free_staff.filter(func(w): return int(w.faehigkeiten.get("fahren", 0)) > 0).is_empty() and "recruit_worker" not in planned:
				var cand := _best_candidate(res.arbeitskraefte, "fahren")
				if not cand.is_empty():
					growth.append({"action": "recruit_worker", "worker_id": cand.id})
					planned.append("recruit_worker")
	elif _free_slots(me) == 0 and not _has_facility(yard, "stellplatz", true) and yard_sug.has("stellplatz") \
			and cash > 1500.0 + buffer:
		growth.append(_place(plot_id, "stellplatz", yard_sug))
	elif _free_slots(me) == 0 and cash > 30000.0 + buffer and personality in ["wachstum", "netzwerker"] \
			and not obs.freie_depotstandorte.is_empty():
		growth.append({"action": "rent_depot", "depot_id": obs.freie_depotstandorte[0].id})
	# 8) Buero: Firmensitz auf dem eigenen Grundstueck bauen/ausbauen, Internet einrichten
	var office: Dictionary = me.buero
	var office_buffer := buffer * 0.5
	var yard_office: Array = yard.get("einrichtungen", []).filter(func(f): return f.typ == "buero")
	if office.bueros.is_empty() and yard_office.is_empty() and yard_sug.has("buero"):
		if (active >= capacity or obs.fahrzeuge.size() >= 2) and cash > 5600.0 + office_buffer:
			growth.append(_place(plot_id, "buero", yard_sug))
	elif not yard_office.is_empty() and yard_office[0].status == "fertig" and active >= capacity and int(yard_office[0].stufe) < 4 \
			and cash > float(Estate.FACILITIES.buero.upgrade[int(yard_office[0].stufe)]) + office_buffer:
		growth.append({"action": "upgrade_building", "building_id": yard_office[0].id})
	elif office.bueros.is_empty() and yard_office.is_empty():
		if (active >= capacity or obs.fahrzeuge.size() >= 2) and cash > Catalog.OFFICE_HQ_COST + office_buffer \
				and "build_office" not in planned:
			for place in obs.orte:
				if place.art == "Bürostandort" and str(place.name).begins_with("Bürohaus"):
					growth.append({"action": "build_office", "site_id": place.id})
					break
	elif yard_office.is_empty() and active >= capacity and int(office.zentrale_stufe) < 3 and "upgrade_office" not in planned \
			and cash > float(Catalog.OFFICE_UPGRADE_COST[int(office.zentrale_stufe)]) + office_buffer:
		growth.append({"action": "upgrade_office"})
	elif int(office.internet) == 0 and cash > Catalog.INTERNET_COST[0] + office_buffer and "install_internet" not in planned:
		growth.append({"action": "install_internet"})
	# 8b) Betriebshof: Lager, Werkstatt, vermietbare Bueros – nur mit Reserve
	var fleet_n: int = obs.fahrzeuge.size()
	if growth.is_empty():
		for want in [["lager", 3, 10000.0], ["werkstatt", 4, 12000.0], ["mietbuero", 4, 30000.0]]:
			if fleet_n >= int(want[1]) and not _has_facility(yard, want[0], true) and yard_sug.has(want[0]) and cash > float(want[2]) + buffer:
				growth.append(_place(plot_id, want[0], yard_sug))
				break
	var vermietung: Dictionary = yard.get("vermietung", {})
	for f in yard.get("einrichtungen", []):
		if f.typ == "mietbuero" and f.status == "fertig" and f.id not in vermietung.get("angebote", []):
			actions.append({"action": "offer_office_rental", "building_id": f.id, "einheiten": 2 * int(f.stufe), "miete_pro_tag": 60, "mindest_tage": 3})
			reasons.append("biete Büroflächen in %s zur Miete an" % f.id)
	for t in vermietung.get("interessenten", []):
		actions.append({"action": "accept_tenant", "tenant_id": t.id})
		reasons.append("nehme Mieter %s an" % t.name)
	# 9) Vorarbeiter fuer groessere Belegschaften
	var workers_n: int = obs.personal.filter(func(w): return w.rolle == "Arbeiter").size()
	var foremen: Array = obs.personal.filter(func(w): return w.rolle == "Vorarbeiter")
	if foremen.is_empty() and workers_n >= 4 and "recruit_foreman" not in planned:
		var cand := _best_candidate(res.arbeitskraefte.filter(func(w): return w.rolle == "Vorarbeiter"), "organisation")
		if not cand.is_empty() and cash > float(cand.anwerbung) + buffer:
			growth.append({"action": "recruit_foreman", "worker_id": cand.id})
	for f in foremen:
		var team: Array = obs.personal.filter(func(w): return w.rolle == "Arbeiter" and str(w.vorarbeiter) == "").map(func(w): return w.id)
		if not team.is_empty() and f.betreut.size() < int(f.kapazitaet):
			actions.append({"action": "assign_foreman", "foreman_id": f.id, "worker_ids": team, "site_id": int(me.depots[0].id)})
			reasons.append("unterstelle %d Arbeiter dem Vorarbeiter %s" % [team.size(), f.name])	# 9b) Plan: Investitionen als Schritte festlegen bzw. den naechsten Schritt ausfuehren
	var plan: Dictionary = obs.plan
	if plan.status in ["kein Plan", "neu_planen", "abgeschlossen"] and not growth.is_empty():
		var steps: Array = []
		for i in growth.size():
			steps.append({"id": "S%d" % (i + 1), "text": _step_text(growth[i], models), "aktion": growth[i],
				"abhaengig_von": [] if i == 0 else ["S%d" % i]})
		actions.append({"action": "set_plan", "ziel": "Kapazität ausbauen: %s" % ", ".join(steps.map(func(st): return st.text)),
			"nutzen": "mehr gleichzeitig fahrbare Aufträge (%d gute Aufträge im Markt)" % good_jobs,
			"risiken": "Investition bindet Bargeld; Auslastung muss folgen",
			"abbruch": [{"typ": "bargeld_unter", "wert": buffer * 0.5}, {"typ": "arbeiter_verloren", "wert": 0}],
			"schritte": steps})
		actions.append({"action": "execute_plan_step", "step_id": "S1"})
		reasons.append("plane: " + steps[0].text)
	elif plan.status == "aktiv" and not plan.jetzt_ausfuehrbar.is_empty():
		actions.append({"action": "execute_plan_step", "step_id": plan.jetzt_ausfuehrbar[0]})
		reasons.append("führe Planschritt %s aus" % plan.jetzt_ausfuehrbar[0])

	# 10) Schutz nach Angriffen
	if attacked:
		var guarding: Array = obs.aufgaben.filter(func(t): return t.art == "bewachen" and t.status not in ["abgeschlossen", "abgebrochen", "fehlgeschlagen"])
		var g := _pick(free_staff, "bewachen", null)
		if guarding.is_empty() and not g.is_empty() and workers_n >= 3:
			actions.append({"action": "guard_target", "worker_id": g.id, "site_id": int(me.depots[0].id)})
			free_staff.erase(g)
			reasons.append("lasse %s das Depot bewachen" % g.name)
		if int(me.sicherheitsstufe) < 1 and cash > 10000.0:
			actions.append({"action": "buy_security", "level": 1})
			reasons.append("verstärke nach dem Angriff die Betriebssicherheit")
		if not me.versicherung and cash > 15000.0:
			actions.append({"action": "set_insurance", "active": true})
	# 11) Konkurrenz: Kooperation, Kundschafter, Abwerbung, Sabotage
	var rivals: Array = obs.konkurrenten
	if not rivals.is_empty() and actions.size() < MAX_ACTIONS:
		var r: Dictionary = rivals[rng.randi() % rivals.size()]
		var roll := rng.randf()
		match personality:
			"netzwerker":
				if unserved > 0 and market.is_empty() and roll < 0.3 and not ready.is_empty():
					actions.append({"action": "offer_trade", "to": r.id, "kind": "capacity_rental", "vehicle_id": ready[0].id,
						"duration_hours": 4, "price": 300, "strafe": 80, "note": "Freie Kapazität mit Fahrer."})
					reasons.append("biete %s Fahrzeug #%d zur Miete an" % [r.name, ready[0].id])
				elif not r.pakt_mit_dir and roll < 0.25:
					actions.append({"action": "propose_cooperation", "to": r.id, "duration_hours": 12,
						"note": "Fairer Wettbewerb, keine Sabotage, gemeinsame Auftragsteilung."})
					reasons.append("schlage %s eine Kooperation vor" % r.name)
				elif roll < 0.5:
					_offer_unserved(obs, r, actions, reasons)
			"wachstum":
				if int(r.personal) >= 3 and roll < 0.08 and cash > 5000.0:
					actions.append({"action": "poach_worker", "target": r.id, "wage": 30})
					reasons.append("werbe einen Arbeiter von %s ab" % r.name)
				elif not obs.fremde_stammkunden.is_empty() and roll < 0.2:
					actions.append({"action": "poach_customer", "customer_id": obs.fremde_stammkunden[0].kunde_id})
			"risikospieler":
				_risky_moves(obs, free_staff, cash, roll, actions, reasons)
			_:
				if roll < 0.2:
					_offer_unserved(obs, r, actions, reasons)
	# 11b) Insolvenzauktionen: Fahrzeuge deutlich unter Wert ersteigern, wenn Geld und Stellplatz da sind
	if _free_slots(me) > 0 and actions.size() < MAX_ACTIONS and rng.randf() < 0.5:
		for au in obs.get("auktionen", []):
			if au.art == "Fahrzeug" and int(au.wert) > 0:
				var offer := maxf(float(au.hoechstgebot) * 1.06, float(au.wert) * 0.6)
				if offer < float(au.wert) * 0.8 and cash > offer + buffer + 3000.0:
					actions.append({"action": "bid_auction", "auction_id": au.id, "amount": int(ceil(offer))})
					reasons.append("biete %d EUR auf %s" % [int(ceil(offer)), au.bezeichnung])
					break
	# 12) Gespraeche (kurz, mit Anlass)
	if rng.randf() < 0.2 and actions.size() < MAX_ACTIONS:
		var pool: Array = LINES.get(personality, LINES.kostenoptimierer)
		actions.append({"action": "send_message", "to": "all", "text": pool[rng.randi() % pool.size()]})
	# Nie grundlos warten: ohne andere Handlung wenigstens Aufträge sammeln
	if actions.filter(func(a): return a.action != "send_message").is_empty():
		if int(obs.unbekannte_offene_auftraege) > 0 and "collect_contracts" not in planned:
			actions.append({"action": "collect_contracts"})
			reasons.append("sammle neue Aufträge, statt zu warten")
		else:
			actions.append({"action": "wait"})
			reasons.append("warte, weil alle Fahrzeuge beschäftigt sind oder nichts Lohnendes verfügbar ist")
	var summary := "Ich " + (", ".join(reasons.slice(0, 3)) if not reasons.is_empty() else "disponiere meine Flotte") + "."
	var goal := "Flotte auslasten und pünktlich liefern"
	if office.bueros.is_empty():
		goal = "Zentrale eröffnen, um mehr Aufträge gleichzeitig zu fahren"
	elif active >= capacity:
		goal = "Büro ausbauen – Kapazität ist ausgeschöpft"
	if attacked:
		goal = "Betrieb absichern und Ausfälle beheben"
	return {"summary": summary, "goal": goal, "actions": actions.slice(0, MAX_ACTIONS), "memory": "Strategie: %s" % personality}


## Risikospieler: erst auskundschaften, dann mit dem entbehrlichsten Arbeiter ein stehendes Fremdfahrzeug angreifen.
static func _risky_moves(obs: Dictionary, free_staff: Array, cash: float, roll: float, actions: Array, reasons: Array) -> void:
	var cooling := false
	for e in obs.ergebnisse_deiner_aktionen:
		if str(e).contains("Abklingzeit"):
			cooling = true
	var targets: Array = obs.gesichtete_fremdfahrzeuge.filter(func(v): return v.state in ["idle", "loading", "unloading"])
	var expendable: Dictionary = {}
	var lowest := 99
	for w in free_staff:
		var total := 0
		for k in w.faehigkeiten:
			total += int(w.faehigkeiten[k])
		if total < lowest and int(w.faehigkeiten.get("fahren", 0)) < 2:
			lowest = total
			expendable = w
	if expendable.is_empty() or free_staff.size() < 2:
		return
	if not targets.is_empty() and not cooling and cash > 8000.0 and roll < 0.3:
		var v: Dictionary = targets[0]
		actions.append({"action": "attempt_vehicle_sabotage", "worker_id": expendable.id, "vehicle_id": v.id})
		reasons.append("riskiere mit %s einen Anschlag auf #%d" % [expendable.name, v.id])
	elif targets.is_empty() and roll < 0.35:
		var r: Dictionary = obs.konkurrenten[0]
		actions.append({"action": "assign_worker_task", "kind": "auskundschaften", "worker_id": expendable.id, "company": r.id})
		reasons.append("schicke %s zum Depot von %s, um zu sehen, was dort steht" % [expendable.name, r.name])


static func _step_text(a: Dictionary, models: Dictionary) -> String:
	match a.action:
		"buy_vehicle": return "Fahrzeug kaufen (%s)" % a.offer_id
		"recruit_worker": return "Fahrer anwerben (%s)" % a.worker_id
		"recruit_foreman": return "Vorarbeiter anwerben (%s)" % a.worker_id
		"build_office": return "Zentrale eröffnen"
		"place_building": return "%s auf dem Betriebshof bauen" % Estate.FACILITIES.get(a.typ, {}).get("name", a.typ)
		"upgrade_building": return "%s ausbauen" % a.building_id
		"upgrade_office": return "Zentrale ausbauen"
		"install_internet": return "Internet einrichten"
		"rent_depot": return "Depot %d mieten" % a.depot_id
	return a.action


static func _dist(a, b) -> float:
	if a == null or b == null:
		return 0.0
	return absf(float(a[0]) - float(b[0])) + absf(float(a[1]) - float(b[1]))


static func _pick(staff: Array, skill: String, pos) -> Dictionary:
	var best := {}
	var best_score := -INF
	for w in staff:
		var lvl := int(w.faehigkeiten.get(skill, 0))
		if lvl < 1:
			continue
		var score := lvl * 10.0 - _dist(w.pos, pos) * 0.1 - float(w.erschoepfung) * 0.1
		if score > best_score:
			best_score = score
			best = w
	return best


static func _best_candidate(pool: Array, skill: String) -> Dictionary:
	var best := {}
	for w in pool:
		if int(w.faehigkeiten.get(skill, 0)) < 1:
			continue
		if best.is_empty() or int(w.faehigkeiten[skill]) * 100 - float(w.lohn_h) > int(best.faehigkeiten[skill]) * 100 - float(best.lohn_h):
			best = w
	return best


static func _supply(res: Dictionary, kind_prefix: String, amount: float) -> Dictionary:
	var best := {}
	for s in res.betriebsmittel:
		if str(s.art).begins_with(kind_prefix) and float(s.bestand) >= amount and (best.is_empty() or float(s.preis) < float(best.preis)):
			best = s
	return best


static func _cheapest_offer(offers: Array, models: Array) -> Dictionary:
	var best := {}
	for o in offers:
		if o.modell in models and int(o.zustand) >= 60 and (best.is_empty() or float(o.preis) < float(best.preis)):
			best = o
	return best


static func _best_contract(market: Array, v: Dictionary, spec: Dictionary, rep: float) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for k in market:
		if k.menge > spec.kapazitaet or (k.kuehlung and not spec.kuehlung) or (k.schwer and not spec.schwer):
			continue
		if rep < k.min_reputation:
			continue
		var tiles := float(k.strecke) + _dist(k.von_pos, v.pos)
		var minutes_needed := tiles * 1.4 / float(spec.tempo) * 2.0 + 60.0   # Umwege, Ampeln, Laden
		if minutes_needed > k.frist_in_min:
			continue
		var margin := float(k.verguetung) - tiles * float(spec.kosten_pro_tile) * 1.1
		var score := margin / (tiles + 30.0)
		if margin > 30.0 and score > best_score:
			best_score = score
			best = k
	return best


static func _best_vehicle(vs: Array, qty: int, cold: bool, heavy: bool, models: Dictionary) -> Dictionary:
	var best := {}
	for v in vs:
		var m: Dictionary = models[v.modell]
		if m.kapazitaet >= qty and (not cold or m.kuehlung) and (not heavy or m.schwer):
			if best.is_empty() or m.kapazitaet < models[best.modell].kapazitaet:
				best = v
	return best


static func _price(desc: String) -> float:
	# "... zahlt 1.234 EUR" -> 1234
	var m := RegEx.create_from_string("(-?[0-9.]+) EUR").search(desc)
	return m.get_string(1).replace(".", "").to_float() if m else 0.0


static func _has_facility(yard: Dictionary, typ: String, include_building: bool) -> bool:
	return yard.get("einrichtungen", []).any(func(f): return f.typ == typ and (include_building or f.status == "fertig"))


static func _place(plot_id: int, typ: String, sug: Dictionary) -> Dictionary:
	var xy: Array = sug[typ]
	return {"action": "place_building", "plot_id": plot_id, "typ": typ, "x": xy[0], "y": xy[1], "rot": xy[2], "bau": "extern"}


static func _free_slots(me: Dictionary) -> int:
	var parts: PackedStringArray = str(me.stellplaetze).split("/")
	return parts[1].to_int() - parts[0].to_int()


## Auftraege, fuer die kein passendes Fahrzeug existiert, an einen Konkurrenten weitergeben.
static func _offer_unserved(obs: Dictionary, r: Dictionary, actions: Array, reasons: Array) -> void:
	for k in obs.meine_auftraege:
		if k.status != "accepted":
			continue
		var fits := false
		for v in obs.fahrzeuge:
			var m: Dictionary = obs.fahrzeugmodelle[v.modell]
			if m.kapazitaet >= k.menge and (not k.anforderungen.contains("Kühlung") or m.kuehlung) \
					and (not k.anforderungen.contains("LKW") or m.schwer):
				fits = true
		if not fits or k.frist_in_min < 200:
			actions.append({"action": "offer_trade", "to": r.id, "kind": "transfer_contract", "contract_id": k.id,
				"price": int(k.verguetung * 0.15), "note": "Ich habe gerade keine Kapazität dafür."})
			actions.append({"action": "send_message", "to": str(r.id), "private": true,
				"text": "Ich biete dir Auftrag %s an (%d EUR Vergütung) – du zahlst mir nur 15 %% Vermittlung." % [k.id, k.verguetung]})
			reasons.append("gebe Auftrag %s an %s ab" % [k.id, r.name])
			return
