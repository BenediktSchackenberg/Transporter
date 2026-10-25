class_name ObservationBuilder
extends RefCounted
## Baut die kompakte Beobachtung fuer genau einen Spieler.
## Enthalten ist nur, was dieser Spieler nach den Regeln wissen darf: eigene Firmendaten vollstaendig,
## von Konkurrenten nur oeffentlich Sichtbares (Reputation, Flottengroesse, Depots, Stammkunden,
## oeffentliche Nachrichten) – keine fremden Finanzen, Plaene, Notizen oder API-Daten.

const MARKET_LIMIT := 10


static func build(sim: Simulation, cid: int, events: Array, since: float, remaining_real_min: float, goal: String = "",
		hint: String = "") -> Dictionary:
	var c := sim.company(cid)
	var L := c.ledger
	var now := sim.game_min
	var depot0: Vector2i = sim.depot_road(cid)
	var me := {
		"id": cid, "name": c.player_name, "firma": c.company_name,
		"bargeld": int(L.cash), "schulden": int(L.debt), "gewinn": int(L.profit()), "umsatz": int(L.revenue()),
		"kosten": int(L.costs()), "kreditrahmen_frei": int(sim.max_loan(cid) - L.debt), "einlagen": int(L.deposits),
		"reputation": snappedf(c.reputation, 0.1), "sicherheitsstufe": c.security_level, "versicherung": c.insurance,
		"stellplaetze": "%d/%d" % [c.vehicle_ids.size(), c.fleet_limit()],
		"depots": c.depots.map(func(s): return {"id": s, "viertel": Catalog.DISTRICTS[sim.city.building(s).district]}),
		"vorraete": {"treibstoff_l": int(c.fuel), "treibstoff_unterwegs_l": int(sim.resources.pending_fuel(cid)), "nachtank_regel": not c.fuel_rule.is_empty(), "ersatzteile": c.parts},
		"stammkunden": _loyal(sim, cid),
		"buero": {"zentrale_stufe": maxi(c.office_level, c.plot_office_level), "internet": c.internet_level,
			"bueros": sim.executor.office_sites(cid).map(func(s): return {"id": s, "name": sim.city.building(s).name}),
			"laufende_auftraege": "%d/%d" % [sim.executor.active_contracts(cid), c.contract_capacity()],
			"buchwert": int(c.property_book)},
	}
	if c.is_disrupted(now):
		me["betriebsstoerung_noch_min"] = int(c.disrupted_until - now)
	if now < c.sabotage_ready_at:
		me["sabotage_bereit_in_min"] = int(c.sabotage_ready_at - now)
	var fleet: Array = []
	for v in sim.company_vehicles(cid):
		var t: Vector2i = v.tile()
		fleet.append({"id": v.id, "modell": v.model, "status": FleetVehicle.STATE_TEXT.get(v.state, v.state),
			"zustand": int(v.condition), "tank_l": snappedf(v.fuel_l, 0.1), "tank_max_l": v.tank_capacity(),
			"tankauftrag": v.refueling, "tankdauer_rest_min": maxf(0.0, v.timer) if v.state in VehicleFuel.STATES else 0.0, "fahrer": sim.driver_of(v).id if sim.driver_of(v) else null, "auftrag": v.contract_id,
			"warteschlange": v.queue, "stopps": v.stops.slice(0, 6), "ladung": v.load,
			"kapazitaet_frei": int(v.spec().capacity) - sim.logistics.load_total(v),
			"vermietet_an": v.operator, "viertel": Catalog.DISTRICTS[sim.city.district_of(t)],
			"entfernung_zum_depot": absi(t.x - depot0.x) + absi(t.y - depot0.y), "buchwert": int(v.book_value),
			"pos": [t.x, t.y]})
	var mine: Array = []
	for k in sim.contracts.values():
		if k.owner == cid and k.status in ["accepted", "assigned", "loading", "in_transit"]:
			mine.append({"id": k.id, "status": k.status, "ware": k.cargo, "menge": k.qty,
				"von": _place(sim, k.pickup), "nach": _place(sim, k.dropoff), "verguetung": int(k.reward),
				"frist_in_min": int(k.deadline - now), "fahrzeug": k.vehicle_id, "anforderungen": k.requirement_text(),
				"bezeichnung": k.cargo_name(), "abgeholt": k.picked, "geliefert": k.delivered_qty,
				"an_abholung_unverplant": sim.logistics.available(k, Logistics.PICKUP)})
	var market: Array = []
	var unknown := 0
	for k in sim.market.open_contracts():
		if k.exclusive_for >= 0 and k.exclusive_for != cid and k.exclusive_until > now:
			continue
		if not c.known.has(k.id):
			unknown += 1   # nur gesammelte Auftraege (Jobboerse/Internet/Stammkunden) sind sichtbar
			continue
		var pick: Vector2i = sim.city.building(k.pickup).road
		var approach := absi(pick.x - depot0.x) + absi(pick.y - depot0.y)
		market.append({"id": k.id, "ware": k.cargo, "bezeichnung": k.cargo_name(), "menge": k.qty, "von": _place(sim, k.pickup), "von_pos": [pick.x, pick.y],
			"nach": _place(sim, k.dropoff), "strecke": k.distance, "anfahrt_vom_depot": approach,
			"verguetung": int(k.reward), "frist_in_min": int(k.deadline - now), "kuehlung": k.needs_cold,
			"schwer": k.needs_heavy, "min_reputation": int(k.min_rep),
			"exklusiv_fuer_dich": k.exclusive_for == cid and k.exclusive_until > now,
			"_score": k.reward / float(k.distance + approach + 30)})
		if k.requester != "":
			market[-1]["kunde"] = _customer(sim, k)
	market.sort_custom(func(a, b): return a._score > b._score)
	# Mischung: die lukrativsten Auftraege plus die, die mit der eigenen Flotte machbar sind
	var models_owned := {}
	for v in sim.company_vehicles(cid):
		models_owned[v.model] = true
	var doable := market.filter(func(m):
		for mid in models_owned:
			if sim.contracts[m.id].vehicle_ok(mid):
				return true
		return false)
	var picked: Array = market.slice(0, MARKET_LIMIT / 2)
	for m in doable:
		if picked.size() >= MARKET_LIMIT:
			break
		if m not in picked:
			picked.append(m)
	market = picked
	for m in market:
		m.erase("_score")
	var models := {}
	for id in Catalog.VEHICLE_MODELS:
		var m: Dictionary = Catalog.VEHICLE_MODELS[id]
		models[id] = {"name": m.name, "preis": int(m.price), "kapazitaet": m.capacity, "tempo": m.speed,
			"kosten_pro_tile": m.cost_per_tile, "kuehlung": m.refrigerated, "schwer": m.heavy}
	var rivals: Array = []
	for o in sim.companies:
		if o.id == cid:
			continue
		rivals.append({"id": o.id, "name": o.player_name, "firma": o.company_name, "reputation": int(o.reputation),
			"fahrzeuge": o.vehicle_ids.size(), "depots": o.depots.size(), "personal": sim.personnel.employed(o.id).size(),
			"erledigte_auftraege": o.stats.completed, "pakt_mit_dir": sim.social.has_pact(cid, o.id),
			"dein_vertrauen": int(sim.social.get_trust(cid, o.id)),
			"figur_im": Catalog.DISTRICTS[sim.city.district_of(sim.avatars[o.id].tile())],
			"schutzfrist": now < o.protected_until})
	var foreign_loyal: Array = []
	for b in sim.customers:
		var owner: int = sim.customers[b].loyal
		if owner >= 0 and owner != cid:
			foreign_loyal.append({"kunde_id": b, "name": sim.city.building(b).name, "bei": owner})
	var free_sites: Array = []
	for s in sim.city.depot_sites:
		if not sim.depot_owner.has(s):
			free_sites.append({"id": s, "viertel": Catalog.DISTRICTS[sim.city.building(s).district]})
	var msgs: Array = []
	for m in sim.social.visible_messages(cid, since).slice(-10):
		msgs.append({"zeit": Catalog.game_minutes_to_text(m.t), "von": m.from, "an": "alle" if m.to == -1 else m.to,
			"privat": m.private, "text": m.text})
	var offers_in: Array = []
	var offers_out: Array = []
	for o in sim.social.offers.values():
		var entry := {"id": o.id, "art": o.kind, "beschreibung": sim.social.describe(o), "status": o.status,
			"laeuft_ab_in_min": int(o.expires - now), "notiz": o.note}
		if o.kind == "transfer_contract" and sim.contracts.has(o.contract_id):
			entry["auftrag_verguetung"] = int(sim.contracts[o.contract_id].reward)
		if int(o.get("awaiting", o.to)) == cid and o.status == "open":
			entry["von"] = o.from
			offers_in.append(entry)
		elif o.from == cid and now - o.created < 120.0:
			entry["an"] = o.to
			offers_out.append(entry)
	var places: Array = []
	for b in sim.city.buildings:
		if b.role in ["job_board", "staffing", "dealer", "workshop", "bank", "office_site"]:
			var art: String = {"job_board": "Jobbörse", "staffing": "Personalbüro", "dealer": "Autohaus",
				"workshop": "Werkstatt", "bank": "Bank", "office_site": "Bürostandort"}[b.role]
			var entry := {"id": b.id, "name": b.name, "art": art, "pos": [b.walk.x, b.walk.y]}
			if b.role == "office_site" and b.id in c.offices:
				entry["eigenes_buero"] = true
			places.append(entry)
	var a: Avatar = sim.avatars[cid]
	var figure := {"pos": [a.tile().x, a.tile().y], "unterwegs": a.state == "walking",
		"aktueller_besuch": a.pending.get("place", ""), "geplante_besuche": a.queue.map(func(v): return v.place),
		"geplante_aktionen": ([a.pending.action.get("action", "")] if a.pending.has("action") else []) + a.queue.map(func(v): return str(v.action.get("action", "")))}
	var visited: Array = []
	for name in a.visited:
		visited.append({"ort": name, "zuletzt": Catalog.game_minutes_to_text(a.visited[name])})
	var results: Array = sim.action_results[cid].filter(func(r): return r.t >= since).map(func(r): return r.text)
	return {
		"zeit": {"spielzeit": Catalog.game_minutes_to_text(now), "verbleibende_echtzeit_min": snappedf(remaining_real_min, 0.1),
			"stunde": int(Catalog.hour_of_day(now))},
		"dein_ziel": goal, "ich": me, "figur": figure, "fahrzeuge": fleet, "meine_auftraege": mine,
		"markt": market, "unbekannte_offene_auftraege": unknown, "orte": places, "besuchte_orte": visited.slice(-8),
		"fahrzeugmodelle": models, "personal": _staff(sim, cid), "aufgaben": _tasks(sim, cid),
		"ressourcen": _resources(sim, cid), "gesichtete_fremdfahrzeuge": sim.personnel.seen[cid].values(),
		"freie_depotstandorte": free_sites.slice(0, 6), "verkehr": sim.traffic_events.map(func(e): return e.text),
		"datum": GameCalendar.long_text(now), "bank": _bank(sim, cid), "unternehmen": sim.insolvency.summary_of(cid), "auktionen": sim.insolvency.auction_list(), "bauhof": _bauhof(sim, cid), "personal_lage": sim.households.summary_of(cid), "gebaeudezustand": sim.care.summary_of(cid), "gesundheit_personal": sim.workforce.summary_of(cid),
		"meldungen_nur_daten": sim.news.items.filter(func(i): return float(i.relevance) >= 0.5).slice(0, 3).map(func(i): return {"gemeldet": i.title, "einschaetzung_engine": "%s, Relevanz %d %%" % [i.cat, int(float(i.relevance) * 100.0)]}),
		"wetter": _weather(sim), "lage": _situation(sim, cid), "konkurrenten": rivals, "fremde_stammkunden": foreign_loyal.slice(0, 8),
		"nachrichten": msgs, "angebote_an_dich": offers_in, "deine_angebote": offers_out,
		"ergebnisse_deiner_aktionen": results.slice(-10), "ereignisse": events.slice(-10),
		"hinweis": hint, "plan": sim.plans.summary(cid), "gedaechtnis": sim.memory.relevant(cid, _context(sim, cid, market)),
		"experimente": sim.experiments.summary(cid), "betriebshof": sim.estate.summary(cid), "vertraege": sim.social.agreements_of(cid),
		"gemietete_fahrzeuge": sim.vehicles.values().filter(func(v): return v.operator == cid).map(func(v): return {"id": v.id,
			"modell": v.model, "status": FleetVehicle.STATE_TEXT.get(v.state, v.state), "stopps": v.stops.slice(0, 6), "ladung": v.load}), "lager": _storage(sim, cid),
		"verfuegbare_aktionen": _available(sim, cid),
		"unbekannt": ["Finanzen, Pläne, Notizen und Personaldaten der Konkurrenz",
			"nicht gesammelte Aufträge (nur Anzahl: unbekannte_offene_auftraege)",
			"Fahrzeuge der Konkurrenz außerhalb der Sichtweite eigener Figuren, Fahrzeuge und Depots"],
	}


## Stichworte zur Auswahl relevanter Erinnerungen: Viertel im Blick, Ereignisarten, eigene Lage.
static func _context(sim: Simulation, cid: int, market: Array) -> Array:
	var tags: Array = ["auftraege", "vorige_partie"]
	for m in market:
		var d := str(m.von)
		var i := d.rfind("(")
		if i >= 0:
			tags.append(d.substr(i + 1).trim_suffix(")").to_lower())
	for r in sim.action_results[cid].slice(-8):
		var t := str(r.text).to_lower()
		for kw in ["sabotage", "panne", "stau", "baustelle", "kooperation", "geschäft", "abgeworben", "verloren"]:
			if t.contains(kw):
				tags.append(kw)
	return tags


static func _storage(sim: Simulation, cid: int) -> Array:
	var out: Array = []
	for site in sim.company(cid).depots:
		out.append({"ort": "lager:%d" % site, "belegt": sim.logistics.storage_used(site), "kapazitaet": sim.logistics.storage_cap(site),
			"inhalt": sim.storage.get(site, {})})
	return out


## Uebersicht: welche Aktionen jetzt sinnvoll moeglich sind und mit welchen gueltigen Ziel-IDs.
## Keine Bewertung – nur Zulaessigkeit nach den Spielregeln.
static func _available(sim: Simulation, cid: int) -> Dictionary:
	var c := sim.company(cid)
	var P := sim.personnel
	var out := {}
	var driven: Array = sim.company_vehicles(cid).filter(func(v): return sim.driver_of(v) != null and v.state not in ["broken", "repairing", "to_workshop"])
	var fuel_vehicles: Array = sim.vehicles.values().filter(func(v): return VehicleFuel.payer(v) == cid and v.tank_capacity() > 0.0)
	out["refuel_vehicle"] = {"fahrzeuge": fuel_vehicles.filter(func(v): return sim.driver_of(v) != null and v.state in ["idle", "returning", "to_pickup", "to_dropoff", "out_of_fuel"] and v.refueling.is_empty()).map(func(v): return v.id),
		"stationen": ["depot"] + sim.resources.supplies.values().filter(func(s): return s.kind == "fuel" and float(s.stock) > 0.0).map(func(s): return s.id)}
	out["request_fuel_rescue"] = {"fahrzeuge": fuel_vehicles.filter(func(v): return v.state == "out_of_fuel" and v.refueling.is_empty()).map(func(v): return v.id)}
	var known_open: Array = sim.market.open_contracts().filter(func(k): return c.known.has(k.id) and (k.exclusive_for < 0 or k.exclusive_for == cid or k.exclusive_until <= sim.game_min) and c.reputation >= k.min_rep)
	var active := sim.executor.active_contracts(cid)
	out["accept_contract"] = {"ziele": known_open.map(func(k): return k.id).slice(0, 12)} if active < c.contract_capacity() \
		else {"nicht_moeglich": "Auftragskapazität %d/%d erschöpft" % [active, c.contract_capacity()]}
	var mine: Array = sim.contracts.values().filter(func(k): return k.owner == cid and k.status in ["accepted", "assigned", "in_transit"])
	out["assign_transport/plan_tour"] = {"fahrzeuge": driven.map(func(v): return v.id), "auftraege": mine.map(func(k): return k.id)} \
		if not driven.is_empty() and not mine.is_empty() else {"nicht_moeglich": "kein Fahrzeug mit Fahrer oder kein laufender Auftrag"}
	var free: Array = P.employed(cid).filter(func(w): return P.can_take(w, "gehen") == "")
	out["assign_worker_task"] = {"freie_arbeiter": free.map(func(w): return w.id)} if not free.is_empty() else {"nicht_moeglich": "kein freier Arbeiter"}
	var no_driver: Array = sim.company_vehicles(cid).filter(func(v): return sim.driver_of(v) == null)
	if not no_driver.is_empty():
		out["fahrer_benoetigt_fuer"] = no_driver.map(func(v): return v.id)
	var broken: Array = sim.company_vehicles(cid).filter(func(v): return v.state == "broken" or v.condition < 45.0)
	if not broken.is_empty():
		out["repair_vehicle"] = {"fahrzeuge": broken.map(func(v): return v.id)}
	out["recruit_worker"] = {"ziele": P.available().filter(func(w): return w.role == "worker" and w.hire_fee <= c.ledger.cash).map(func(w): return w.id).slice(0, 8)}
	out["recruit_foreman"] = {"ziele": P.available().filter(func(w): return w.role == "foreman" and w.hire_fee <= c.ledger.cash).map(func(w): return w.id)}
	out["buy_vehicle"] = {"angebote": sim.resources.available_offers().filter(func(o): return o.price <= c.ledger.cash).map(func(o): return o.id).slice(0, 8),
		"mit_kredit": _financed_vehicles(sim, cid, known_open)} \
		if c.vehicle_ids.size() < c.fleet_limit() else {"nicht_moeglich": "alle Stellplätze belegt (rent_depot)"}
	out["collect_contracts"] = {"ort": "überall" if c.internet_level >= 2 else ("eigenes Büro" if c.internet_level == 1 else "Jobbörse")}
	var targets: Array = P.seen[cid].values().filter(func(e): return e.state in ["idle", "loading", "unloading"]).map(func(e): return e.id)
	var sab_cd := float(P.cooldowns.get("sab:%d" % cid, 0.0)) - sim.game_min
	out["attempt_vehicle_sabotage"] = {"gesichtete_ziele": targets} if sab_cd <= 0.0 else {"nicht_moeglich": "Abklingzeit %d min" % int(sab_cd)}
	out["offen_fuer_angebote"] = sim.social.offers.values().filter(func(o): return o.to == cid and o.status == "open").map(func(o): return o.id)
	return out


## Kreditoptionen sind konkrete Bankangebote. Die Gewinnschwelle ist eine grobe
## Tagesrechnung auf Basis bereits bekannter Auftraege, kein Kaufautomatismus.
static func _financed_vehicles(sim: Simulation, cid: int, known_open: Array) -> Array:
	var c := sim.company(cid)
	if c.vehicle_ids.size() >= c.fleet_limit():
		return []
	var offers: Array = sim.resources.available_offers()
	offers.sort_custom(func(a, b): return a.price < b.price)
	var out: Array = []
	var seen_models := {}
	for o in offers:
		if seen_models.has(str(o.model)):
			continue
		var reserve := maxf(3000.0, float(o.price) * 0.1)
		var gap := maxf(0.0, float(o.price) + reserve - c.ledger.cash)
		if gap < 500.0 or gap > sim.max_loan(cid) - c.ledger.debt:
			continue
		var best := {}
		for bank in Banking.BANKS.size():
			var B: Dictionary = Banking.BANKS[bank]
			var months := clampi(12, int(B.min_m), int(B.max_m))
			var collateral := sim.banking.best_collateral(cid) if gap > float(B.free_limit) else -1
			var q: Dictionary = sim.banking.quote(bank, cid, gap, months, collateral)
			if q.ok and (best.is_empty() or float(q.rate) < float(best.rate)):
				best = {"bank": B.id, "monate": months, "rate": q.rate, "rate_monat": q.monthly,
					"zinsen_gesamt": q.total_interest, "pfand_fahrzeug_id": collateral}
		if best.is_empty():
			continue
		seen_models[str(o.model)] = true
		var model: Dictionary = Catalog.model(str(o.model))
		var matching: Array = known_open.filter(func(k): return k.vehicle_ok(str(o.model)))
		var contribution := 0.0
		var example := ""
		for k in matching:
			var trip_cost := float(k.distance) * float(model.cost_per_tile) * 1.3
			var margin := float(k.reward) - trip_cost
			if margin > contribution:
				contribution = margin
				example = str(k.id)
		var free_driver: bool = sim.personnel.employed(cid).any(func(w): return w.role == "worker" and w.vehicle_id < 0 and sim.personnel.can_take(w, "gehen") == "")
		var new_wage := 0.0
		var hiring := 0.0
		var driver_possible := free_driver
		if not free_driver:
			var candidates: Array = sim.personnel.available().filter(func(w): return w.role == "worker")
			candidates.sort_custom(func(a, b): return a.wage < b.wage)
			if not candidates.is_empty():
				driver_possible = true
				new_wage = float(candidates[0].wage)
				hiring = float(candidates[0].hire_fee)
		var day_cost := float(o.price) * Catalog.DEPRECIATION_PER_DAY + new_wage * 24.0 + float(best.zinsen_gesamt) / float(best.monate * GameCalendar.DAYS_PER_MONTH)
		out.append({"offer_id": o.id, "modell": o.model, "preis": int(o.price), "kreditbetrag": ceili(gap),
			"barreserve_nach_kauf": int(reserve), "bank": best.bank, "monate": best.monate,
			"jahreszins_prozent": snappedf(float(best.rate) * 100.0, 0.1), "rate_monat": int(best.rate_monat),
			"pfand_fahrzeug_id": best.pfand_fahrzeug_id, "passende_bekannte_auftraege": matching.size(),
			"beispielauftrag_id": example, "beispiel_deckungsbeitrag_vor_fixkosten": int(contribution),
			"fahrer_besetzbar": driver_possible, "zusaetzlicher_fahrer_lohn_h": new_wage, "anwerbung": int(hiring), "fixkosten_pro_spieltag_ca": int(day_cost),
			"auftraege_pro_spieltag_fuer_fixkosten_ca": ceili(day_cost / contribution) if contribution > 0.0 else -1})
		if out.size() >= 6:
			break
	return out


## Lokales Modell bekommt die fuer Transportentscheidungen relevanten Fakten und
## exakte IDs. Der vollstaendige Zustand bleibt fuer andere Provider erhalten.
static func compact_for_local(obs: Dictionary) -> Dictionary:
	var keys := ["zeit", "dein_ziel", "ich", "figur", "fahrzeuge", "meine_auftraege", "markt",
		"unbekannte_offene_auftraege", "fahrzeugmodelle", "personal", "aufgaben", "ressourcen", "bank",
		"verfuegbare_aktionen", "freie_depotstandorte", "orte", "plan", "hinweis", "ereignisse", "lage", "angebote_an_dich"]
	var out := {}
	for key in keys:
		if obs.has(key):
			out[key] = obs[key]
	out["letzte_aktionsergebnisse"] = obs.get("ergebnisse_deiner_aktionen", []).slice(-5)
	return out


## Eigenes Personal vollstaendig sichtbar.
## Kundenfigur und Anliegen hinter einem Auftrag ("" wenn es ein normaler Marktauftrag ist).
static func _customer(sim: Simulation, k: Contract) -> String:
	if k.requester == "":
		return ""
	var p: Dictionary = sim.residents.people.get(k.requester, {})
	return "%s (%s): %s%s" % [p.get("name", "?"), p.get("role", ""), k.concern, (" · Anlass " + k.cause) if k.cause != "" else ""]


## Aktuelle Ereignislage: nur was die Spieler ueber regulaere Quellen erfahren (firmeneigene Ereignisse nur fuer die Firma).
static func _situation(sim: Simulation, cid: int) -> Array:
	var out: Array = []
	for e in sim.events.events:
		if e.status != "aktiv" or not e.get("auto", false) or int(e.get("company", cid)) != cid:
			continue
		out.append({"id": e.id, "was": e.text, "ursache": e.ursache, "schwere": e.schwere, "orte": e.orte, "wirkung": e.wirkung,
			"endet": e.ende_bedingung, "bis_spaetestens_in_min": int(float(e.ende) - sim.game_min)})
	return out.slice(-6)


## Oeffentlicher Wetterstand: fuer alle Unternehmen identisch (Modelldaten). Erklaerung steht im Systemprompt.
## Referenzzins, eigene Kredite/Einlagen und Angebote der drei Banken (10 000 EUR, 12 Monate bzw. Bankgrenze).
static func _bank(sim: Simulation, cid: int) -> Dictionary:
	var out: Dictionary = sim.banking.summary_of(cid)
	var offers: Array = []
	for i in Banking.BANKS.size():
		var B: Dictionary = Banking.BANKS[i]
		var months := clampi(12, int(B.min_m), int(B.max_m))
		var q: Dictionary = sim.banking.quote(i, cid, 10000.0, months, sim.banking.best_collateral(cid))
		offers.append({"bank": B.id, "name": B.name, "schwerpunkt": B.focus, "laufzeit_monate": "%d–%d" % [B.min_m, B.max_m],
			"beispiel": q.msg if q.ok else "Beispiel 10 000 EUR: " + q.msg})
	out["angebote"] = offers
	return out


## Bauhof: Preise/Bestand je Material und das eigene Material mit Ort.
static func _bauhof(sim: Simulation, cid: int) -> Dictionary:
	var prices := {}
	for it in Trader.MATERIALS:
		prices[it] = "%.2f EUR, Bestand %d" % [sim.trader.price(it), sim.trader.stock_of(it)]
	var own: Array = []
	for l in sim.stock.of_owner("C%d" % cid):
		own.append({"material": l.item, "menge": l.qty, "ort": sim.city.building(int(l.loc)).name})
	return {"standort": sim.city.building(sim.trader.bauhof).name, "preise": prices, "dein_material": own}


static func _weather(sim: Simulation) -> Dictionary:
	var w: Weather = sim.wx
	var c: Dictionary = w.cur
	var effects: Array = []
	if w.is_rain():
		effects.append("Regen: Fahrten langsamer, Verladen im Freien länger (Überdachung hilft)")
	if w.is_strong_wind():
		effects.append("Sturm: Außenarbeiten und Bau verzögert")
	if w.is_hot():
		effects.append("Hitze: mehr Getränke-/Kühlbedarf")
	if w.is_icy():
		effects.append("Glätte: langsamer, höheres Pannenrisiko")
	elif w.is_cold():
		effects.append("Kälte: höheres Pannenrisiko ohne Wartung")
	if w.is_fog():
		effects.append("Nebel: vorsichtiger fahren, Lieferzeiten unsicher")
	return {"lage": c.text, "temp_c": snappedf(float(c.temp), 0.1), "regen_mm_h": snappedf(float(c.precip_mm_h), 0.1),
		"wind_kmh": roundi(float(c.wind)), "boeen_kmh": roundi(float(c.gust)), "status": w.status(Time.get_unix_time_from_system()),
		"auswirkungen": effects, "vorhersage": c.forecast.slice(0, 3).map(func(f): return "%s %s %d°C Regen %d%%" % [str(f.time).right(5), f.text, roundi(float(f.temp)), int(f.pop)])}


static func _staff(sim: Simulation, cid: int) -> Array:
	var out: Array = []
	for w in sim.personnel.employed(cid):
		var e := {"id": w.id, "name": w.name, "rolle": "Vorarbeiter" if w.role == "foreman" else "Arbeiter",
			"faehigkeiten": w.skills, "lohn_h": w.wage, "erfahrung": int(w.experience), "zuverlaessigkeit": snappedf(w.reliability, 0.01),
			"loyalitaet": int(w.loyalty), "erschoepfung": int(w.fatigue), "status": w.status_text(sim), "aufgabe": w.task_id,
			"fahrzeug": w.vehicle_id, "pos": [w.tile().x, w.tile().y], "vorarbeiter": w.foreman}
		if w.role == "foreman":
			e["betreut"] = w.supervised
			e["kapazitaet"] = w.capacity()
			e["bereich_tiles"] = int(w.control_radius())
			e["befugnisse"] = w.orders
		out.append(e)
	return out


static func _tasks(sim: Simulation, cid: int) -> Array:
	var out: Array = []
	for t in sim.personnel.tasks.values():
		if t.company == cid and (not t.is_final() or sim.game_min - t.created < 120.0):
			out.append({"id": t.id, "art": t.kind, "arbeiter": t.worker_id, "vorarbeiter": t.foreman_id, "ziel": t.target,
				"prioritaet": t.priority, "status": t.status, "fortschritt": snappedf(t.progress, 0.01), "meldung": t.report})
	return out.slice(-15)


## Oeffentlich sichtbare, umkaempfte Ressourcen (fuer alle Spieler gleich).
static func _resources(sim: Simulation, cid: int) -> Dictionary:
	var workers: Array = []
	for w in sim.personnel.available():
		workers.append({"id": w.id, "name": w.name, "rolle": "Vorarbeiter" if w.role == "foreman" else "Arbeiter",
			"faehigkeiten": w.skills, "lohn_h": w.wage, "anwerbung": w.hire_fee, "pos": [w.tile().x, w.tile().y]})
	var offers: Array = []
	for o in sim.resources.available_offers():
		var b: Dictionary = sim.city.building(o.dealer)
		offers.append({"id": o.id, "modell": o.model, "preis": o.price, "zustand": o.condition, "haendler": b.name,
			"pos": [b.walk.x, b.walk.y]})
	var supplies: Array = []
	for sp in sim.resources.supplies.values():
		var b: Dictionary = sim.city.building(sp.building)
		supplies.append({"id": sp.id, "art": "Treibstoff (Liter)" if sp.kind == "fuel" else "Ersatzteile (Stück)",
			"ort": b.name, "bestand": int(sp.stock), "preis": sim.resources.fuel_price(sp) if sp.kind == "fuel" else sp.price,
			"pos": [b.road.x, b.road.y]})
	workers.sort_custom(func(a, b): return a.lohn_h < b.lohn_h)
	offers.sort_custom(func(a, b): return a.preis < b.preis)
	return {"arbeitskraefte": workers.slice(0, 8), "fahrzeugangebote": offers.slice(0, 8), "betriebsmittel": supplies,
		"nachtanken_ohne_vorrat_preis_l": sim.resources.emergency_fuel_price()}


static func _place(sim: Simulation, bid: int) -> String:
	var b: Dictionary = sim.city.building(bid)
	return "%s (%s)" % [b.name, Catalog.DISTRICTS[b.district]]


static func _loyal(sim: Simulation, cid: int) -> Array:
	var out: Array = []
	for b in sim.customers:
		if sim.customers[b].loyal == cid:
			out.append(sim.city.building(b).name)
	return out
