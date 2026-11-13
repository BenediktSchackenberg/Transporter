class_name LiveText
extends RefCounted
## BBCode-Texte fuer die Zuschaueroberflaeche: was jedes KI-Unternehmen gerade tut und warum (Aktivitaeten) sowie
## Wetter, Ereignisse mit Ursachenketten und Kunden (Lage). Reine Funktionen ueber den Simulationszustand.

const SEVERITY := ["", "leicht", "mittel", "schwer"]


static func operations(sim: Simulation) -> String:
	var text := "[b]BETRIEBSABLAUF[/b]\nAuftrag → Fahrer → Hofkontrolle → Abholung → Lager / Umschlag → Zustellung → Rueckmeldung\n\n"
	for c in sim.companies:
		text += "[color=#%s][b]%s[/b][/color]\n" % [_col(c), esc(c.company_name)]
		var summary: Dictionary = sim.operations.summary(c.id)
		if summary.linien.is_empty():
			text += "  Einzelauftraege; die KI hat noch keinen Liniendienst beauftragt.\n"
		for line in summary.linien:
			text += "  [b]%s · %s[/b]%s\n    %s\n    %d zugestellt · Erloes %s\n" % [line.id, esc(line.name), " (pausiert, laufende Fracht wird fertiggestellt)" if not line.active else "", esc(line.status), int(line.delivered), Catalog.money(line.revenue)]
		for v in sim.company_vehicles(c.id):
			var driver: Worker = sim.driver_of(v)
			text += "  #%d %s · %s · Fahrer: %s\n" % [v.id, esc(v.spec().name), esc(FleetVehicle.STATE_TEXT.get(v.state, v.state)), esc(driver.name) if driver else "FEHLT"]
			if not v.stops.is_empty():
				var stop: Dictionary = v.stops[0]
				var k: Contract = sim.contracts.get(str(stop.contract_id))
				if k:
					var site: int = sim.logistics.place_building(k, str(stop.ort))
					text += "    %s · %d x %s · %s bei %s\n" % [k.id, int(stop.menge), esc(k.cargo_name()), "laden" if stop.art == "laden" else "entladen", esc(sim.city.building(site).name)]
		var duty_counts := {}
		for w in sim.personnel.employed(c.id):
			if w.duty_label != "" and w.vehicle_id < 0:
				duty_counts[w.duty_label] = int(duty_counts.get(w.duty_label, 0)) + 1
		for duty in duty_counts:
			text += "  Hof: %d Mitarbeiter · %s\n" % [int(duty_counts[duty]), esc(duty)]
		for site in c.depots:
			text += "  Lager %d: %d / %d Einheiten\n" % [int(site), sim.logistics.storage_used(int(site)), sim.logistics.storage_cap(int(site))]
		text += "\n"
	text += "[b]BETRIEBSFUNK[/b] · Meldungen aus ausgefuehrten Vorgaengen\n"
	for entry in sim.operations.dialogue.slice(-14):
		text += "%s · %s · %s: %s\n" % [Catalog.game_time_short(float(entry.t)), esc(sim.company(int(entry.company)).player_name), esc(entry.speaker), esc(entry.text)]
	return text


static func esc(t: Variant) -> String:
	return str(t).replace("[", "[lb]")


static func _col(c: Company) -> String:
	return c.color.lightened(0.3).to_html(false)


## Auftrag mit Kunde und Anlass in einer Zeile.
static func contract_line(sim: Simulation, k: Contract) -> String:
	var s := "%s %d× %s: %s → %s" % [k.id, k.qty, k.cargo_name(), sim.city.building(k.pickup).name, sim.city.building(k.dropoff).name]
	if k.requester != "":
		var p: Dictionary = sim.residents.people.get(k.requester, {})
		s += " · Kunde %s (%s): „%s“" % [p.get("name", "?"), p.get("role", ""), k.concern]
	if k.cause != "":
		s += " · Anlass %s" % k.cause
	return s


static func figure_text(sim: Simulation, cid: int) -> String:
	var a: Avatar = sim.avatars[cid]
	if a.pending.has("place"):
		return "geht zu %s (%s)%s" % [a.pending.place, str(a.pending.get("action", {}).get("action", "Besuch")),
			(", danach %d weitere Besuche" % a.queue.size()) if not a.queue.is_empty() else ""]
	if a.state == "talking":
		return "spricht mit %s" % (sim.company(a.talk_with).player_name if a.talk_with >= 0 else "einer Person")
	return "disponiert am Betriebshof; wartet auf Rueckmeldungen"


## Konkreter Zustand eines Unternehmens mit tatsaechlicher Ursache (Karte im Dashboard).
## Rueckgabe: {zustand, grund, farbe} mit Zustand = Unterwegs | Verhandelt | Plant | Wartet auf API-Antwort | Wartet auf Material |
## Arbeitet | Blockiert | Reagiert auf Stoerung | Bereit.
static func company_state(sim: Simulation, ctl: AgentController, c: Company) -> Dictionary:
	var a: Avatar = sim.avatars[c.id]
	var warn := Color("#ffb347")
	var bad := Color("#ff6b5e")
	var good := Color("#6fd08c")
	match c.status:
		"warnung":
			return {"zustand": "Liquiditätswarnung", "grund": c.status_reason, "farbe": warn}
		"verzug":
			return {"zustand": "Zahlungsverzug", "grund": "Nachfrist bis %s – %s" % [GameCalendar.short_text(c.grace_until), c.status_reason.left(70)], "farbe": bad}
		"insolvenz":
			return {"zustand": "Insolvenz", "grund": "Verwalter %s, Aktionen gesperrt" % c.administrator, "farbe": bad}
		"verwertung":
			return {"zustand": "Verwertung", "grund": "Auktionen laufen, Gläubiger werden bedient", "farbe": bad}
		"geschlossen":
			return {"zustand": "Geschlossen", "grund": c.status_reason.left(90), "farbe": bad}
	if c.is_disrupted(sim.game_min):
		return {"zustand": "Reagiert auf Störung", "grund": "Betriebsstörung bis %s" % Catalog.game_time_short(c.disrupted_until), "farbe": bad}
	for v in sim.company_vehicles(c.id):
		if v.state == "broken":
			return {"zustand": "Blockiert", "grund": "%s #%d liegt mit Panne (Mechaniker oder Abschleppen nötig)" % [Catalog.model(v.model).name, v.id], "farbe": bad}
		if v.state == "waiting_bay":
			return {"zustand": "Blockiert", "grund": "#%d wartet auf eine freie Laderampe" % v.id, "farbe": warn}
		if not v.stops.is_empty() and sim.driver_of(v) == null:
			return {"zustand": "Blockiert", "grund": "#%d hat Aufträge, aber keinen Fahrer" % v.id, "farbe": warn}
	for t in sim.personnel.tasks.values():
		if t.company == c.id and t.status == "blockiert":
			return {"zustand": "Blockiert", "grund": "%s %s: %s" % [t.id, t.kind, str(t.report).left(70)], "farbe": warn}
	for f in sim.estate.facilities.values():
		if f.owner == c.id and f.status == "im_bau" and int(f.mat) < int(f.mat_needed):
			return {"zustand": "Wartet auf Material", "grund": "Baustelle %s (%s) braucht %d Material" % [f.id, Estate.FACILITIES[f.typ].name, int(f.mat_needed) - int(f.mat)], "farbe": warn}
	if ctl.status.begins_with("wartet"):
		return {"zustand": "Wartet auf API-Antwort", "grund": "Antwort des Modells steht aus", "farbe": warn}
	if a.state == "talking":
		return {"zustand": "Verhandelt", "grund": "im Gespräch mit %s" % (sim.company(a.talk_with).player_name if a.talk_with >= 0 else "einer Person"), "farbe": good}
	if a.pending.has("place") or (a.state == "walking" and not a.arrived()):
		return {"zustand": "Unterwegs", "grund": "zu %s" % str(a.pending.get("place", "einem Ziel")), "farbe": good}
	var working := 0
	for t in sim.personnel.tasks.values():
		if t.company == c.id and t.status == "in Bearbeitung" and t.kind not in ["fahren", "gehen"]:
			working += 1
	if working > 0:
		return {"zustand": "Arbeitet", "grund": "%d Arbeiter im Einsatz" % working, "farbe": good}
	var plan: Dictionary = sim.plans.summary(c.id)
	if plan.has("ziel") and plan.status == "aktiv":
		return {"zustand": "Plant", "grund": "Plan %s: %s" % [plan.id, str(plan.ziel).left(60)], "farbe": good}
	return {"zustand": "Bereit", "grund": "", "farbe": Color("#9a98a8")}


## Unternehmensaktivitaet (getrennt von der persoenlichen Taetigkeit der Figur): "2 Lieferungen, 1 Reparatur, 1 Bau aktiv".
static func company_activity(sim: Simulation, c: Company) -> String:
	var deliveries := 0
	var repairs := 0
	for v in sim.company_vehicles(c.id):
		if v.state in ["to_pickup", "loading", "to_dropoff", "unloading"]:
			deliveries += 1
		elif v.state in ["repairing", "to_workshop", "broken"]:
			repairs += 1
	for t in sim.personnel.tasks.values():
		if t.company == c.id and t.kind == "reparieren" and not t.is_final():
			repairs += 1
	var builds: int = sim.estate.facilities.values().filter(func(f): return f.owner == c.id and f.status in ["im_bau", "ausbau"]).size()
	var parts: Array = []
	if deliveries > 0:
		parts.append("%d Lieferung%s" % [deliveries, "en" if deliveries != 1 else ""])
	if repairs > 0:
		parts.append("%d Reparatur%s" % [repairs, "en" if repairs != 1 else ""])
	if builds > 0:
		parts.append("%d Bau%s" % [builds, "ten" if builds != 1 else ""])
	return (", ".join(parts) + " aktiv") if not parts.is_empty() else "keine laufenden Vorgänge"


## Naechster geplanter Schritt: eingereihter Besuch, ausfuehrbarer Planschritt oder offener Planschritt.
static func next_step(sim: Simulation, c: Company) -> String:
	var a: Avatar = sim.avatars[c.id]
	if a.pending.has("place"):
		var rest := ", danach %d weitere" % a.queue.size() if not a.queue.is_empty() else ""
		return "Besuch %s (%s)%s" % [a.pending.place, str(a.pending.get("action", {}).get("action", "")), rest]
	var plan: Dictionary = sim.plans.summary(c.id)
	if plan.has("schritte"):
		for st in plan.schritte:
			if st.id in plan.jetzt_ausfuehrbar:
				return "Planschritt %s: %s" % [st.id, str(st.text).left(70)]
		for st in plan.schritte:
			if st.status == "offen":
				return "Planschritt %s (wartet auf Voraussetzung): %s" % [st.id, str(st.text).left(60)]
	return "kein Schritt geplant"


## Letzte wichtige Entscheidung des Unternehmens mit Begruendung (nur Modell-/Plan-/Ersatzentscheidungen).
static func last_decision(sim: Simulation, c: Company) -> Dictionary:
	for i in range(sim.decisions.entries.size() - 1, -1, -1):
		var e: Dictionary = sim.decisions.entries[i]
		if e.company == c.id and e.herkunft in ["api", "plan", "fallback"] and str(e.aktion) not in ["wait()", ""]:
			return {"id": e.id, "t": e.t, "aktion": str(e.aktion), "ergebnis": str(e.ergebnis), "begruendung": str(e.begruendung),
				"wahrgenommen": e.wahrgenommen, "ziel": str(e.ziel), "herkunft": str(e.herkunft), "ok": e.pruefung == "ok"}
	return {}


## Was tut jede Firma gerade? Ziel, Plan, Figur, Fahrzeuge (mit Kunde und Anlass), Personal, letzte Entscheidungen.
## Reiter "Strategie": je Unternehmen die laufende Strategie und die gemessenen Ergebnisse der bewerteten Zeitraeume (keine erfundenen Gedanken).
static func strategy(sim: Simulation) -> String:
	var txt := "[b]Strategie und Lernen[/b]
Messwerte kommen aus der Buchhaltung und den Auftragszählern. Weniger als %d Aufträge gelten als unsicher.

" % StrategyMemory.MIN_CONTRACTS
	for c in sim.companies:
		var s: Dictionary = sim.strategy.summary_of(c.id)
		if s.is_empty():
			continue
		txt += "[color=#%s][b]%s[/b][/color]  aktuell [b]%s[/b] seit %d Tagen · bewertete Strategien %d · Zeiträume %d
" % [_col(c), esc(c.company_name), esc(s.bezeichnung), int(s.tage_im_zeitraum), int(s.bewertet), int(s.zeitraeume_gesamt)]
		for id in s.bewertungen:
			var r: Dictionary = s.bewertungen[id]
			if int(r.zeitraeume) == 0:
				txt += "    %s: noch nicht erprobt
" % esc(sim.strategy.label_of(id))
			else:
				txt += "    %s: %s je Spieltag · %d Zeiträume · %d Aufträge · %s
" % [esc(sim.strategy.label_of(id)), Catalog.money(float(r.gewinn_je_tag)), int(r.zeitraeume), int(r.auftraege), r.vertrauen]
		if int(s.letzter_wechsel_tag) > 0:
			txt += "    Letzter Strategiewechsel: Spieltag %d
" % (int(s.letzter_wechsel_tag) + 1)
		if str(s.letzte_erkenntnis) != "":
			txt += "    [color=#f2c14e]Letzte Erkenntnis:[/color] %s
" % esc(str(s.letzte_erkenntnis))
		for n in s.vermutungen:
			txt += "    [color=#9fd8ff]Vermutung des Spielers (Tag %d, nicht bewiesen):[/color] %s
" % [int(n.tag) + 1, esc(str(n.text))]
		txt += "
"
	return txt


static func activities(sim: Simulation, controllers: Array) -> String:
	var txt := ""
	for c in sim.companies:
		var ctl: AgentController = controllers[c.id]
		txt += "[color=#%s][b]%s – %s[/b][/color]  Gewinn %s · Bargeld %s\n" % [_col(c), c.player_name, c.company_name,
			Catalog.money(c.ledger.profit()), Catalog.money(c.ledger.cash)]
		txt += "  [color=#f2c14e]Ziel:[/color] %s\n" % (esc(ctl.goal) if ctl.goal != "" else "noch keines formuliert")
		var plan: Dictionary = sim.plans.summary(c.id)
		if plan.has("ziel"):
			var done: int = plan.schritte.filter(func(st): return st.status in ["erledigt", "uebersprungen"]).size()
			txt += "  [color=#b48cff]Plan %s:[/color] %s (%d/%d Schritte, %s)\n" % [plan.id, esc(plan.ziel), done, plan.schritte.size(), plan.status]
		txt += "  [color=#9fd8ff]Status der KI:[/color] %s\n" % esc(ctl.status)
		txt += "  [color=#9fd8ff]Figur:[/color] %s\n" % esc(figure_text(sim, c.id))
		for v in sim.company_vehicles(c.id):
			var k: Contract = sim.contracts.get(v.contract_id)
			if k == null and not v.stops.is_empty():
				k = sim.contracts.get(str(v.stops[0].get("contract_id", "")))   # geplanter erster Stopp
			var d: Worker = sim.driver_of(v)
			txt += "  #%d %s – %s%s%s\n" % [v.id, Catalog.model(v.model).name, FleetVehicle.STATE_TEXT.get(v.state, v.state),
				(" (Fahrer %s)" % d.name) if d else " (kein Fahrer)", (" · " + esc(contract_line(sim, k))) if k and k.status in ["accepted", "assigned", "loading", "in_transit"] else ""]
		for w in sim.personnel.employed(c.id):
			var t: WorkerTask = sim.personnel.tasks.get(w.task_id)
			if t and not t.is_final() and t.kind != "fahren" and t.kind != "gehen":
				txt += "  %s %s: %s (%s, %d %%)\n" % [w.name, w.status_text(sim), t.describe(), t.status, int(t.progress * 100)]
		var shown := 0
		for i in range(sim.decisions.entries.size() - 1, -1, -1):
			var e: Dictionary = sim.decisions.entries[i]
			if e.company != c.id or e.herkunft not in ["api", "plan", "fallback", "foreman"]:
				continue
			txt += "  [color=#7fc8ff]%s[/color] %s → %s%s\n" % [e.id, esc(e.aktion), esc(e.ergebnis).left(110),
				("  [color=#c9c4b4]Begründung: „%s“[/color]" % esc(e.begruendung).left(160)) if e.begruendung != "" else ""]
			shown += 1
			if shown >= 3:
				break
		txt += "\n"
	return txt


## Wetter, Zeitachsen, aktive Ereignisse mit Ursachenkette, beendete Ereignisse und Kunden.
static func situation(sim: Simulation, remaining_real_min: float) -> String:
	var w: Weather = sim.wx
	var c: Dictionary = w.cur
	var now_unix := Time.get_unix_time_from_system()
	var st := w.status(now_unix)
	var txt := "[b][color=#f2c14e]WETTER MAINZ[/color][/b] – %s\n" % st.to_upper()
	txt += "%s, %.1f °C (gefühlt %.1f) · Niederschlag %.1f mm/h · Wind %.0f km/h, Böen %.0f · Bewölkung %d %% · %s\n" % [
		c.text, float(c.temp), float(c.feels), float(c.precip_mm_h), float(c.wind), float(c.gust), int(c.cloud), "Tag" if c.is_day else "Nacht"]
	var quelle := {"open-meteo": "Open-Meteo (Modelldaten, keine Messung einer lokalen Wetterstation)", "simuliert": "simuliertes Ersatzwetter (keine echten Wetterdaten verfügbar)",
		"wiederholung": "aufgezeichneter Wetterverlauf einer früheren Partie"}
	txt += "[color=#9a98a8]Quelle: %s · Daten von %s · letzter Abruf %s%s[/color]\n" % [quelle.get(c.source, c.source),
		str(c.obs_time).replace("T", " ") if str(c.obs_time) != "" else "–",
		Time.get_datetime_string_from_unix_time(int(w.fetched_unix + Time.get_time_zone_from_system().bias * 60.0)).replace("T", " ") if w.fetched_unix > 0.0 else "–",
		(" · Fehler: " + esc(w.last_error)) if w.last_error != "" else ""]
	if not c.forecast.is_empty():
		txt += "Vorhersage: " + " · ".join(c.forecast.slice(0, 5).map(func(f): return "%s %s %d °C (%d %%)" % [str(f.time).right(5), f.text, roundi(float(f.temp)), int(f.pop)])) + "\n"
	txt += "[color=#9a98a8]Zeitachsen: Restzeit der Partie %02d:%02d aktive Echtzeit · Spielzeit %s (beschleunigt) · Wetterzeit = reale Uhrzeit, ändert sich nicht durch Beschleunigung.[/color]\n" % [
		int(remaining_real_min), int(fmod(remaining_real_min, 1.0) * 60.0), Catalog.game_minutes_to_text(sim.game_min)]
	var eff: Array = []
	if w.is_rain():
		eff.append("Fahrten ×%.2f, Verladen im Freien ×%.2f (überdacht ×%.2f), Bau ×%.2f" % [w.drive_factor(), w.loading_factor(false), w.loading_factor(true), w.build_factor()])
	if w.is_strong_wind():
		eff.append("Sturm: Außenarbeiten verzögert")
	if w.is_hot():
		eff.append("Hitze: Getränke-/Kühlbedarf, Fahrzeuge belastet")
	if w.is_icy():
		eff.append("Glätte: Fahrten ×%.2f, höheres Pannenrisiko" % w.drive_factor())
	elif w.is_cold():
		eff.append("Kälte: höheres Pannenrisiko ohne Wartung")
	if w.is_fog():
		eff.append("Nebel: vorsichtigere Fahrweise")
	txt += "[color=#8fe0a0]Spielwirkung (simuliert):[/color] %s\n\n" % ("; ".join(eff) if not eff.is_empty() else "keine besonderen Effekte")

	var active: Array = sim.events.events.filter(func(e): return e.status == "aktiv" and e.get("auto", false))
	txt += "[b][color=#f2c14e]AKTIVE EREIGNISSE[/color][/b] (%d) – Ruhige Phasen sind normal.\n" % active.size()
	for i in range(active.size() - 1, -1, -1):
		txt += event_block(sim, active[i])
	var ended: Array = sim.events.events.filter(func(e): return e.status == "beendet" and e.get("auto", false))
	if not ended.is_empty():
		txt += "\n[b][color=#9a98a8]ZULETZT BEENDET[/color][/b]\n"
		for e in ended.slice(-5):
			txt += "[color=#777]%s %s – %s[/color]\n" % [e.id, e.text, "Ursache: " + e.ursache]
	var waiting: Array = sim.residents.people.values().filter(func(p): return p.state == "wartet")
	var fresh: Array = sim.residents.people.values().filter(func(p): return p.state in ["zufrieden", "verärgert"])
	txt += "\n[b][color=#f2c14e]KUNDEN MIT ANLIEGEN[/color][/b] (%d offen · %d Figuren insgesamt)\n" % [waiting.size(), sim.residents.people.size()]
	for p in waiting.slice(0, 14):
		var k: Contract = sim.contracts.get(p.contract)
		var b: Dictionary = sim.city.building(p.building)
		txt += "  [b]%s[/b], %s, %s (%s): „%s“ – %s\n" % [esc(p.name), esc(p.role), esc(b.name), Catalog.DISTRICTS[b.district], esc(p.last_concern),
			("%s, %s, %s" % [k.id, Catalog.money(k.reward), ("angenommen von " + sim.company(k.owner).company_name) if k.owner >= 0 else "wartet auf ein Unternehmen"]) if k else "–"]
	for p in fresh.slice(0, 6):
		txt += "  [color=%s]%s (%s) ist %s[/color]\n" % ["#8fe0a0" if p.state == "zufrieden" else "#ff6b5e", esc(p.name), esc(p.role), p.state]
	return txt + traffic_block(sim) + retail_block(sim) + district_block(sim) + fuel_block(sim) + news_block(sim)


## Handel und Abfall: Kennzahlen aller Restaurants und Geschaefte, Muellabfuhr mit Recyclingquote.
static func retail_block(sim: Simulation) -> String:
	var R: Retail = sim.retail
	var sm := R.summary()
	var txt := "
[b][color=#f2c14e]HANDEL UND GASTRONOMIE[/color][/b] – %d Betriebe, Umsatz %s, %d Verkäufe, %d entgangen, %d Nachbestellungen (%d geliefert, %d mit eigenem Lieferdienst)
" % [
		int(sm.betriebe), Catalog.money(float(sm.umsatz)), int(sm.verkauft), int(sm.entgangen), int(sm.bestellungen), int(sm.geliefert), int(sm.eigene_lieferfahrten)]
	for s in R.shops.values():
		var col := "#8fe0a0" if s.status == "offen" else "#ff6b5e"
		txt += "  [color=%s]%s[/color] (%s) Kasse %s · Gewinn %s%s
" % [col, esc(s.name), R.spec_of(s).label, Catalog.money(float(sim.economy.accounts[s.id])), Catalog.money(R.profit_of(s)),
			(" · [color=#ffb347]fehlt: " + ", ".join(s.missing.map(func(k): return Retail.GOODS[k].name)) + "[/color]") if not s.missing.is_empty() else ""]
	var W: Waste = sim.waste
	txt += "[b]Müllabfuhr[/b] %.1f t gesamt · Recyclingquote %d %% · Mehrwegquote %d %% · %d Flaschen wiederbefüllt · Gebühren %s, Kosten %s
" % [float(W.total.tons), roundi(W.rate * 100.0),
		roundi(W.mehrweg_share() * 100.0), int(R.stats.bottles_reused), Catalog.money(float(W.total.fees)), Catalog.money(float(W.total.cost))]
	var H: Harbor = sim.harbor
	if H.enabled:
		var hs := H.summary()
		txt += "[b]Hafen[/b] %d Schiffe · %d Ladeeinheiten gelöscht, %d geladen · %d Einfuhren warten (%d LE) · nächstes Schiff in %d Tag(en)%s
" % [
			int(H.stats.schiffe), int(H.stats.einheiten_ein), int(H.stats.einheiten_aus), H.manifest.size(), H.waiting_units(), int(hs.naechstes_in_tagen),
			(" · am Kai: „%s“" % H.ship.name) if not H.ship.is_empty() and H.ship.status == "am_kai" else ""]
	return txt


## Anzeige eines angeklickten Betriebs: Konto, Personal, Bestand, Bestellungen, Zahlen.
static func shop_panel(sim: Simulation, s: Dictionary) -> String:
	var R: Retail = sim.retail
	var spec: Dictionary = R.spec_of(s)
	var txt := "[b]%s[/b] (%s) · Konto %s · Status %s
" % [esc(s.name), spec.label, s.id, s.status]
	txt += "Kasse %s · Personal %d · Miete %s/Monat · Preisniveau %.2f
" % [Catalog.money(float(sim.economy.accounts[s.id])), int(s.staff), Catalog.money(float(spec.rent)), float(s.price_factor)]
	txt += "Umsatz %s · Wareneinsatz %s · Löhne %s · Miete %s · Fracht %s → [b]Gewinn %s[/b] · %d Verkäufe, %d entgangen
" % [Catalog.money(float(s.revenue)), Catalog.money(float(s.cogs)),
		Catalog.money(float(s.wages)), Catalog.money(float(s.rent)), Catalog.money(float(s.freight)), Catalog.money(R.profit_of(s)), int(s.units), int(s.lost)]
	txt += "[b]Lager[/b]
"
	for item in spec.goods:
		var have := R.stock_of(s, item)
		var inc := R.incoming(s, item)
		var empty := have <= 0
		txt += "  %s%s: %d %s%s%s[/color]
" % ["[color=#ff6b5e]" if empty else "[color=#ece8dc]", Retail.GOODS[item].name, have, Retail.GOODS[item].unit,
			(" · unterwegs %d" % inc) if inc > 0 else "", " – AUSVERKAUFT" if empty else ""]
	var leer := sim.stock.qty("leergut", s.id, int(s.building))
	if leer > 0 or int(s.out_bottles) > 0:
		txt += "  Leergut im Lager: %d · Pfandflaschen bei Kunden: %d
" % [leer, int(s.out_bottles)]
	if s.kind == "restaurant":
		var menu: Array = []
		for dn in spec.dishes:
			var d: Dictionary = Retail.DISHES[dn]
			var can := true
			for it in d.uses:
				if R.stock_of(s, it) < int(d.uses[it]):
					can = false
			menu.append("%s %s%s" % [d.name, Catalog.money(float(d.price) * float(s.price_factor)), "" if can else " (nicht verfügbar)"])
		txt += "[b]Speisekarte[/b] " + " · ".join(menu) + "
"
	var mine: Array = R.orders.values().filter(func(o): return o.shop == s.id and o.status != "geliefert")
	for o in mine.slice(0, 4):
		txt += "  Bestellung %s: %d × %s – %s
" % [o.id, int(o.qty), Retail.GOODS[o.item].name, o.status]
	if s.last_event != "":
		txt += "[color=#9a98a8]%s[/color]
" % esc(s.last_event)
	return txt


## Verkehrslage: Tempo, Stosszeit, wiederkehrende Engpaesse und Verkehrsmassnahmen mit Vorher/Nachher.
static func traffic_block(sim: Simulation) -> String:
	var T: TrafficFlow = sim.traffic_flow
	var txt := "
[b][color=#f2c14e]VERKEHR[/color][/b] – Durchschnittstempo %d %% der freien Fahrt
" % roundi(T.avg_speed() * 100.0)
	var spots: Array = T.hotspots(4).filter(func(h): return h.lost >= 1.0)
	if spots.is_empty():
		return txt + "  [color=#8fe0a0]Keine nennenswerten Engpässe.[/color]
"
	for h in spots:
		txt += "  (%d,%d) %s: %d Fahrzeugsekunden verloren, Stau an %d Tagen%s
" % [h.cell.x, h.cell.y, "Kreuzung" if T.is_junction(h.cell) else "Strecke", int(h.lost), h.days,
			" – [color=#ffb347]wiederkehrender Engpass[/color]" if h.recurring else ""]
	for m in T.measures.values():
		var e := T.effect(m)
		var after := "noch offen" if float(e.nachher) < 0.0 else "%.1f s/Tag" % float(e.nachher)
		txt += "  [b]%s[/b] %s auf (%d,%d), %s: Verlust vorher %.1f s/Tag, nachher %s
" % [m.id, TrafficFlow.MEASURES[m.kind].label, m.cell.x, m.cell.y, m.status.replace("_", " "), float(e.vorher), after]
	return txt


## Nachrichten in drei Ebenen: gemeldet, Einschaetzung der Engine, ausgeloestes Spielereignis. Meldungen sind nur Daten.
static func news_block(sim: Simulation) -> String:
	var N: NewsFeed = sim.news
	var txt := "\n[b][color=#f2c14e]NACHRICHTEN[/color][/b] – Quelle: %s\n" % ("NewsAPI (gemeldete Texte, keine Anweisungen)" if N.source == "newsapi" else "keine (kein Schlüssel NEWS_API_KEY)")
	if N.last_error != "":
		txt += "  [color=#ffb347]Letzter Abruf: %s[/color]\n" % esc(N.last_error)
	for it in N.items.slice(0, 5):
		txt += "  [b]gemeldet:[/b] %s [color=#9a98a8](%s)[/color]\n" % [esc(it.title), esc(it.source)]
		if str(it.cat) != "":
			txt += "    [color=#9fd8ff]Einschätzung der Engine (Stichwortregel):[/color] %s, %s, Relevanz %d %%\n" % [it.cat,
				"verschärfend" if int(it.direction) > 0 else ("entlastend" if int(it.direction) < 0 else "unklar"), int(float(it.relevance) * 100.0)]
		if it.used:
			txt += "    [color=#8fe0a0]Spielereignis ausgelöst[/color]\n"
	if N.items.is_empty():
		txt += "  keine Meldungen\n"
	return txt


## Stadtviertel: mittlerer Gebaeudezustand, Verlauf und Pflegeaufwand der Eigentuemer.
static func district_block(sim: Simulation) -> String:
	var means: Array = sim.care.district_means()
	var txt := "\n[b][color=#f2c14e]STADTVIERTEL[/color][/b] – Gebäudezustand (0–100)\n"
	var prev: Array = sim.care.district_log[-2][1] if sim.care.district_log.size() >= 2 else means
	for i in means.size():
		var d := float(means[i]) - float(prev[i])
		var col := "#8fe0a0" if d > 0.05 else ("#ff6b5e" if d < -0.05 else "#9a98a8")
		txt += "  %s: %.0f %s[color=%s](%+.1f)[/color]\n" % [Catalog.DISTRICTS[i], means[i], sim.care.state_of(float(means[i])), col, d]
	txt += "  Eigentümer haben bisher %s in Instandhaltung gesteckt.\n" % Catalog.money(sim.care.spent_city)
	return txt


## Kraftstoff: reale Referenz, Status, Ereignisfaktor und daraus der Spielpreis (jeweils getrennt ausgewiesen).
static func fuel_block(sim: Simulation) -> String:
	var F: FuelPrices = sim.fuel
	var st := F.status(Time.get_unix_time_from_system())
	var quelle := "Tankerkönig, Median von %d Tankstellen im Umkreis %.0f km um Mainz" % [F.stations_n, FuelPrices.LOCATION.radius_km] if F.source == "tankerkoenig" \
		else "simulierter Ersatzpreis (kein Schlüssel oder keine Daten)"
	var txt := "\n[b][color=#f2c14e]KRAFTSTOFF[/color][/b] – %s\n" % st.to_upper()
	txt += "  Referenz: Diesel %.3f · E5 %.3f · E10 %.3f EUR/l [color=#9a98a8](%s)[/color]\n" % [F.ref.diesel, F.ref.e5, F.ref.e10, quelle]
	txt += "  Ereignisfaktor ×%.2f → Spielpreis Diesel an der Durchschnittstankstelle %.2f EUR/l\n" % [sim.resources.fuel_price_factor,
		F.ref.diesel * sim.resources.fuel_price_factor]
	if F.last_error != "":
		txt += "  [color=#ffb347]Letzter Abruf: %s[/color]\n" % esc(F.last_error)
	txt += "  Betreiberkonto %s · Tankwagen unterwegs: %d\n" % [Catalog.money(sim.economy.accounts.G0), sim.resources.tanker_orders.size() + sim.resources.fuel_deliveries.size()]
	for sid in sim.resources.supplies:
		var sp: Dictionary = sim.resources.supplies[sid]
		if sp.kind != "fuel":
			continue
		txt += "  %s: %d / %d l · %.2f EUR/l (Aufschlag %+.1f %%) · Säulen %d/%d belegt · abgesetzt %d l · Wartezeit gesamt %d min%s\n" % [
			esc(sim.city.building(sp.building).name), int(sp.stock), int(sp.max), sim.resources.fuel_price(sp), float(sp.markup) * 100.0,
			sim.resources.pumps_busy(sp), int(sp.pumps), int(sp.sales_l), int(sp.wait_min),
			"  [color=#ff6b5e]LEER[/color]" if float(sp.stock) < 1.0 else ""]
	return txt


## Ein Ereignis mit allen Pflichtfeldern und der Kette: Ursache -> Wirkung -> Auftraege -> Entscheidungen -> Ergebnis.
static func event_block(sim: Simulation, e: Dictionary) -> String:
	var t := "[color=#ffb347]%s[/color] [b]%s[/b] (%s)\n" % [e.id, esc(e.text), SEVERITY[clampi(int(e.schwere), 0, 3)]]
	t += "   Ursache: %s%s\n" % [esc(e.ursache), (" · Bedingungen: " + esc(e.bedingungen)) if e.bedingungen != "" and e.bedingungen != e.ursache else ""]
	t += "   Orte: %s · Beginn %s · bis spätestens %s · endet: %s\n" % [esc(", ".join(e.orte)), Catalog.game_time_short(e.start),
		Catalog.game_time_short(e.ende), esc(e.ende_bedingung)]
	if not e.wirkung.is_empty():
		t += "   Wirkung: %s\n" % esc("; ".join(e.wirkung))
	t += "   Quellen für Spieler: %s\n" % esc(", ".join(e.quellen))
	var ks: Array = sim.contracts.values().filter(func(k): return k.cause == e.id)
	for k in ks.slice(0, 5):
		var who := (" von %s" % sim.company(k.owner).company_name) if k.owner >= 0 else ""
		t += "   [color=#7fc8ff]→ Auftrag[/color] %s – %s%s\n" % [esc(contract_line(sim, k)), k.status, who]
	var ds: Array = sim.decisions.entries.filter(func(d): return d.refs.get("event_id", "") == e.id)
	for d in ds.slice(-4):
		var who: String = sim.company(d.company).company_name if d.company >= 0 else "Stadt"
		t += "   [color=#b48cff]→ Entscheidung[/color] %s %s: %s – %s\n" % [d.id, esc(who), esc(d.aktion), esc(sim.decisions.consequences(d)).left(120)]
	return t


## Reiter "Banken": Referenzzins, Bankbilanzen, Kredite mit Tilgungsstand, Einlagen, Konten der Sektoren.
static func banks(sim: Simulation) -> String:
	var B: Banking = sim.banking
	var txt := "[b][color=#f2c14e]BANKEN UND GELD[/color][/b]
"
	txt += "Referenzzins %.2f %% p. a. (%.3f %% je Monat) · %s
" % [B.ref_rate * 100.0, B.ref_rate * 100.0 / 12.0, GameCalendar.long_text(sim.game_min)]
	for i in Banking.BANKS.size():
		var bk: Dictionary = Banking.BANKS[i]
		txt += "
[b]%s[/b] [color=#9a98a8](%s)[/color]
  Bargeld %s · Kredite %s · Einlagen %s · Eigenkapital %s · verfügbar %s · Verluste %s
" % [
			bk.name, bk.focus, Catalog.money(B.bank_cash(i)), Catalog.money(B.loans_of_bank(i)), Catalog.money(B.deposits_of_bank(i)),
			Catalog.money(B.equity(i)), Catalog.money(B.available(i)), Catalog.money(B.losses[bk.id])]
	txt += "
[b]Kredite[/b]
"
	var any := false
	for l in B.loans.values():
		if l.status == "getilgt":
			continue
		any = true
		var n: Dictionary = B.next_due(l)
		txt += "  %s %s bei %s: Rest %s, %.2f %% p. a., nächste Rate %s (Monat %d), %s%s
" % [l.id, sim.company(l.owner).company_name, Banking.BANKS[l.bank].name,
			Catalog.money(l.outstanding), l.rate * 100.0, Catalog.money(n.get("pay", 0.0)), int(n.get("month", 0)) + 1, l.status,
			(", Pfand Fahrzeug #%d" % l.collateral) if l.collateral >= 0 else ""]
	if not any:
		txt += "  keine offenen Kredite
"
	txt += "
[b]Einlagen[/b]
"
	if B.deposits.is_empty():
		txt += "  keine
"
	for d in B.deposits.values():
		txt += "  %s %s: %s %s bei %s, %.2f %% p. a.
" % [d.id, sim.company(d.owner).company_name, Catalog.money(d.amount),
			"Tagesgeld" if d.kind == "tages" else "Festgeld", Banking.BANKS[d.bank].name, d.rate * 100.0]
	txt += "
[b]Geldkreislauf (Konten außerhalb der Firmen)[/b]
"
	for k in ["H0", "P0", "X0", "S0", "C0", "I0"]:
		txt += "  %s: %s
" % [Economy.NAMES[k], Catalog.money(sim.economy.accounts[k])]
	txt += "[color=#9a98a8]Gesamtgeld (Firmen + Konten) weicht vom Anfangsbestand um %s ab.[/color]
" % Catalog.money(sim.economy.conservation_error())
	return txt


## Reiter "Unternehmen": Rechtsform und Status, laufende Auktionen, Historie geschlossener Unternehmen.
## Region: Heimatstadt und Betriebe nach Standort (Auftrag 17, Abschnitt 14).
static func company_places(sim: Simulation, c: Company) -> String:
	var per := {}
	for b in sim.biz.of(c.id):
		var k: int = sim.towns.of_building(int(b.site))
		if not per.has(k):
			per[k] = []
		per[k].append(str(b.branch))
	var parts: Array = []
	for k in per:
		parts.append("%s: %s" % [sim.towns.name_of(int(k)), ", ".join(per[k])])
	return "Heimat %s · Betriebe %s" % [sim.towns.name_of(int(c.home_town)), "; ".join(parts) if not parts.is_empty() else "keine"]


static func firms(sim: Simulation) -> String:
	var I: Insolvency = sim.insolvency
	var txt := "[b][color=#f2c14e]UNTERNEHMEN[/color][/b]
"
	for c in sim.companies:
		var spec: Dictionary = CompanyForms.FORMS[c.form]
		txt += "
[b]%s[/b] (%s, Gründer %d) – %s
" % [c.company_name, spec.name, c.generation, c.status.to_upper()]
		txt += "  Gründung %s · Verwaltung %s/Monat · Berichtspflicht %s · Kreditrahmen ×%.1f
" % [GameCalendar.log_text(c.founded_min), Catalog.money(spec.admin), spec.report, spec.loan_factor]
		if sim.towns.is_region():
			txt += "  " + company_places(sim, c) + "
"
		if c.status_reason != "":
			txt += "  [color=#ffb347]%s[/color]
" % c.status_reason
		if c.pending_form != "":
			txt += "  Formwechsel zu %s ab %s
" % [CompanyForms.name_of(c.pending_form), GameCalendar.short_text(c.pending_form_due)]
	txt += "
[b]Insolvenzauktionen[/b]
"
	var open: Array = I.open_auctions()
	if open.is_empty():
		txt += "  keine
"
	for a in open:
		var t: Dictionary = I.top_bid(a)
		txt += "  %s %s (Wert %s, aus der Masse von %s): Höchstgebot %s%s, endet %s
" % [a.id, a.title, Catalog.money(a.value), sim.company(a.cid).company_name,
			Catalog.money(t.amount), (" von " + sim.company(t.by).company_name) if int(t.by) >= 0 else (" (Händler)" if int(t.by) == -2 else ""), GameCalendar.short_text(a.end)]
	txt += "
[b]Historie geschlossener Unternehmen[/b]
"
	if I.archive.is_empty():
		txt += "  noch keine Insolvenz
"
	for e in I.archive:
		txt += "  %s (%s) geschlossen %s · Forderungen %s, erlöst %s, abgeschrieben %s, Ausfallquote %d %%
" % [e.name, CompanyForms.name_of(e.form),
			GameCalendar.log_text(e.closed), Catalog.money(e.claims), Catalog.money(e.recovered), Catalog.money(e.lost), int(float(e.quota) * 100.0)]
	return txt


## Reiter "Bauhof": Preise, Bestand, Bestellungen, Produktion, Warenbewegungen.
static func trader(sim: Simulation) -> String:
	var T: Trader = sim.trader
	var txt := "[b][color=#f2c14e]BAUHOF (GROSSHANDEL)[/color][/b] – Konto %s · Standort %s
" % [Catalog.money(T.cash()), sim.city.building(T.bauhof).name]
	txt += "Verkäufe %s · Importe %s · Exporte %s · Löhne %s · Energie %s
" % [Catalog.money(T.stats.sales), Catalog.money(T.stats.imports),
		Catalog.money(T.stats.exports), Catalog.money(T.stats.wages), Catalog.money(T.stats.energy)]
	txt += "
[b]Material[/b] (Preis je Einheit, Bestand / Ziel)
"
	for it in Trader.MATERIALS:
		var m: Dictionary = Trader.MATERIALS[it]
		txt += "  %s: %s · %d / %d
" % [m.name, Catalog.money(T.price(it)), T.stock_of(it), int(m.target)]
	txt += "
[b]Produktion[/b]
"
	for pid in Trader.PLANTS:
		var p: Dictionary = Trader.PLANTS[pid]
		txt += "  %s: %d Zyklen insgesamt
" % [p.name, int(T.produced.get(pid, 0))]
	txt += "
[b]Bestellungen im Ausland[/b]
"
	if T.orders.is_empty():
		txt += "  keine offen
"
	for o in T.orders:
		txt += "  %d × %s, Ankunft %s
" % [int(o.qty), Trader.MATERIALS[o.item].name, GameCalendar.short_text(o.due)]
	txt += "
[b]Letzte Warenbewegungen[/b]
"
	for e in sim.stock.log.slice(-12):
		txt += "  %s: %d × %s, %s → %s (%s)
" % [GameCalendar.short_text(e.t), int(e.qty), Trader.MATERIALS[e.item].name, e.von, e.nach, e.grund]
	return txt


## Reiter "Rangliste": aktueller Stand, Etappensieger, Verpflichtungen und Insolvenzverluste.
static func standings(sim: Simulation) -> String:
	var S: Standings = sim.standings
	var txt := "[b][color=#f2c14e]RANGLISTE[/color][/b] – Wertung: kumulierter Nettogewinn, Sieger muss zahlungsfähig sein
"
	var rank := sim.ranking()
	for i in rank.size():
		var c: Company = rank[i]
		txt += "
%d. [b]%s[/b] (%s%s) – %s
" % [i + 1, c.company_name, CompanyForms.name_of(c.form), ", Gründer %d" % c.generation if c.generation > 1 else "", c.status]
		txt += "  Gewinn %s · Vermögen %s · Bargeld %s · Schulden %s
" % [Catalog.money(c.ledger.profit()), Catalog.money(sim.net_worth(c.id)),
			Catalog.money(c.ledger.cash), Catalog.money(c.ledger.debt)]
		txt += "  Pflichten der nächsten 30 Tage %s · Ruf %d · Aufträge %d
" % [Catalog.money(S.obligations(c)) if c.is_active() else "–", int(c.reputation), c.stats.completed]
	var lead: Company = S.winner()
	txt += "
[b]Aktuell führt:[/b] %s
" % (lead.company_name if lead != null else "niemand zahlungsfähig")
	txt += "
[b]Etappensieger (je Spielmonat)[/b]
"
	for w in S.stage_winners.slice(-10):
		txt += "  Monat %d: %s (Gewinn %s)
" % [int(w.month) + 1, w.name, Catalog.money(w.profit)]
	if S.stage_winners.is_empty():
		txt += "  noch keiner
"
	txt += "
[b]Insolvenzverluste der Gläubiger insgesamt[/b]: %s
" % Catalog.money(S.insolvency_losses())
	return txt


## Haushalte, Loehne, Gesundheit und Kaufkraft je Unternehmen.
static func households(sim: Simulation) -> String:
	var H: Households = sim.households
	var txt := "[b][color=#f2c14e]HAUSHALTE UND PERSONAL[/color][/b]\n"
	txt += "%d Haushalte erfasst · Guthaben gesamt %s · bisher für Lebenshaltung ausgegeben %s (Kaufkraft)\n" % [H.homes.size(), Catalog.money(H.total_balance()), Catalog.money(H.spent_total)]
	for c in sim.companies:
		var l: Dictionary = H.summary_of(c.id)
		var g: Dictionary = sim.workforce.summary_of(c.id)
		txt += "\n[b]%s[/b] – %d Mitarbeiter · Motivation Ø %d · Gesundheit Ø %d\n" % [c.company_name, int(l.mitarbeiter), int(l.motivation_mittel), int(g.gesundheit_mittel)]
		txt += "  unzufrieden %d · Haushalte im Defizit %d · erschöpft %d · krank/in Pause %d · Lohnrückstand %s\n" % [int(l.unzufrieden), int(l.haushalte_im_defizit),
			int(g.erschoepft), int(g.krank_oder_in_pause), Catalog.money(float(l.lohnrueckstand))]
		for w in sim.personnel.employed(c.id).slice(0, 6):
			var h: Dictionary = H.household_of(w)
			txt += "    %s: %.1f EUR/h (Mindestlohn %.1f) · Motivation %d · Gesundheit %d · Haushalt %s (%d Angehörige, Guthaben %s)\n" % [esc(w.name), w.wage,
				H.reservation_wage(w), int(w.motivation), int(w.health), h.id, int(h.dependents), Catalog.money(float(h.balance))]
	return txt


static func public_sector(sim: Simulation) -> String:
	var P: PublicSector = sim.public_sector
	var txt := "[b][color=#f2c14e]ÖFFENTLICHE HAND[/color][/b]\n"
	txt += "Kasse %s · Lohnsteuer %s · Sozialabgaben %s · Ertragsteuer %s\n" % [Catalog.money(float(sim.economy.accounts.P0)), Catalog.money(P.tax_total), Catalog.money(P.social_total), Catalog.money(P.corporate_total)]
	txt += "Sätze: Lohnsteuer %d %% · Sozialabgaben %d %% · Ertragsteuer %d %%\n" % [roundi(PublicSector.INCOME_TAX * 100.0), roundi(PublicSector.SOCIAL_RATE * 100.0), roundi(PublicSector.CORPORATE_TAX * 100.0)]
	txt += "\n[b]Ausgaben je Ressort[/b]\n"
	for d in P.departments:
		txt += "  %s: %s\n" % [d, Catalog.money(float(P.departments[d]))]
	txt += "\n[b]Ertragsteuer je Firma[/b]\n"
	for c in sim.companies:
		txt += "  %s: %s gezahlt\n" % [esc(c.company_name), Catalog.money(-float(c.ledger.totals.get("tax", 0.0)))]
	txt += "\n[b]Letzte Steuerprüfungen[/b] (Chance %d %% je Firma und Monat)\n" % roundi(PublicSector.AUDIT_CHANCE * 100.0)
	for a in P.audits.slice(-5):
		txt += "  Monat %d · %s: Nachforderung %s, Zuschlag %s\n" % [int(a.month), esc(sim.company(int(a.cid)).company_name), Catalog.money(float(a.arrears)), Catalog.money(float(a.fine))]
	return txt


static func citizens(sim: Simulation) -> String:
	var Z: Citizens = sim.citizens
	var sm := Z.summary()
	var txt := "[b][color=#f2c14e]BÜRGER UND ARBEITSMARKT[/color][/b]\n"
	txt += "%d Einwohner · %d beschäftigt (%.1f %%) · %d arbeitslos\n" % [int(sm.einwohner), int(sm.beschaeftigt), float(sm.quote) * 100.0, int(sm.arbeitslos)]
	txt += "\n[b]Arbeitgeber[/b]\n"
	for k in sm.arbeitgeber:
		txt += "  %s: %d Beschäftigte\n" % [esc(str(k)), int(sm.arbeitgeber[k])]
	var l: Dictionary = Z.last if not Z.last.is_empty() else sm
	txt += "\n[b]Letzter Monat[/b]\n  Stellenwechsel %d · Entlassungen %d · Einstellungen %d · Kündigungen %d\n" % [int(l.wechsel), int(l.entlassungen), int(l.einstellungen), int(l.kuendigungen)]
	txt += "  Lohnsumme %s · Lohnsteuer und Sozialabgaben %s · Arbeitslosengeld %s\n" % [Catalog.money(float(l.lohnsumme)), Catalog.money(float(l.abgaben)), Catalog.money(float(l.arbeitslosengeld))]
	return txt


## Wohnstufen je Viertel: Verteilung, Stufenmittel und welche Bedürfnisse unversorgt sind (mit der Ware, die Spediteure liefern können).
static func tiers_block(sim: Simulation) -> String:
	var T: Tiers = sim.tiers
	var sm: Dictionary = T.summary()
	if sm.is_empty():
		return ""
	var txt := "
[b]Wohnstufen[/b] (Stadtmittel %.2f · Aufstiege %d · Abstiege %d)
" % [T.city_mean(), int(T.stats.up), int(T.stats.down)]
	for d in sm:
		var e: Dictionary = sm[d]
		var st: Dictionary = e.stufen
		txt += "  %s: %d Bewohner · Stufe 1/2/3/4 = %d/%d/%d/%d · Mittel %.2f
" % [d, int(e.personen), int(st[1]), int(st[2]), int(st[3]), int(st[4]), float(e.mittel)]
		if not e.fehlt.is_empty():
			txt += "    unversorgt: %s
" % ", ".join(e.fehlt.map(func(f): return "%s (%d %%%s)" % [f.bedarf, roundi(float(f.deckung) * 100.0), (", Ware: " + str(f.ware)) if str(f.ware) != "" else ""]))
	txt += "  Neue Geschäfte durch Marktzutritt %d · Versorgungsbauten beantragt %d · Prämien der Stadt %s
" % [int(T.stats.shops_opened), int(T.stats.supply_projects), Catalog.money(float(T.stats.get("bonus_paid", 0.0)))]
	var locks: Array = []
	for def_id in Tiers.UNLOCK:
		locks.append("%s %s (ab Stufenmittel %.1f)" % [Planning.DEFS[def_id].label, "frei" if T.unlocked(def_id) else "gesperrt", float(Tiers.UNLOCK[def_id])])
	txt += "  Freischaltungen: %s
" % ", ".join(locks)
	txt += "  Meilensteine:
"
	for id in Tiers.MILESTONES:
		txt += "    %s %s%s
" % ["✔" if T.milestones.has(id) else "○", Tiers.MILESTONES[id], (" (Tag %d)" % int(T.milestones[id])) if T.milestones.has(id) else ""]
	return txt


static func housing(sim: Simulation) -> String:
	var sm: Dictionary = sim.housing.summary()
	var txt := "[b][color=#f2c14e]WOHNEN[/color][/b]
"
	txt += "%d Wohneinheiten · %d belegt · Leerstand %.1f %%
" % [int(sm.einheiten), int(sm.belegt), float(sm.leerstand) * 100.0]
	txt += "Durchschnittsmiete %s je Monat · Mietspiegel %.1f %% des Ausgangswerts · Mieteinnahmen seit Beginn %s
" % [Catalog.money(float(sm.durchschnittsmiete)), float(sm.mietspiegel) * 100.0, Catalog.money(float(sm.mieteinnahmen))]
	txt += "Räumungen %d · Menschen ohne Wohnung %d
" % [int(sm.raeumungen), int(sm.wohnungslos)]
	var ct: Contentment = sim.contentment
	txt += "Zufriedenheit %.0f von 100 (Wohnung %.0f · Arbeit %.0f · Versorgung %.0f · Verkehr %.0f) · Wegzüge %d
" % [ct.mean, float(ct.parts.wohnung), float(ct.parts.arbeit), float(ct.parts.versorgung), float(ct.parts.verkehr), ct.emigrated]
	for d in ct.attractiveness:
		var tr: float = float(ct.trend.get(d, 0.0))
		txt += "  %s: Zufriedenheit %s · Attraktivität %.0f %s (Lagefaktor %.2f)
" % [d, "%.0f" % float(ct.by_district[d]) if ct.by_district.has(d) else "–", float(ct.attractiveness[d]), "▲" if tr > 0.5 else ("▼" if tr < -0.5 else "▬"), ct.district_factor(Catalog.DISTRICTS.find(d))]
	txt += tiers_block(sim)
	var cs: Dictionary = sim.banking.consumer_summary()
	txt += "Konsumkredite: %d laufend (%s) · %d im Rückstand · %d in Pfändung (Restschuld %s) · %d vergeben
" % [int(cs.laufend), Catalog.money(float(cs.volumen)), int(cs.rueckstand), int(cs.pfaendung), Catalog.money(float(cs.restschuld_pfaendung)), int(cs.vergeben)]
	var os: Dictionary = sim.oversight.summary()
	txt += "Gewerbeaufsicht: %d Auflagen offen · %d erfüllt · %d mit Bußgeld (%s) · Einsätze der Stadt %d (%s)
" % [int(os.auflagen.offen), int(os.auflagen.erfuellt), int(os.auflagen.bussgeld), Catalog.money(float(os.bussgelder)), int(os.einsaetze), Catalog.money(float(os.einsatzkosten))]
	var late: Array = sim.housing.units.values().filter(func(u): return int(u.arrears) > 0)
	txt += "
[b]Mietrückstand (%d)[/b]
" % late.size()
	for u in late.slice(0, 8):
		txt += "  %s · Gebäude %d · %d Monate · Miete %s
" % [u.id, int(u.building), int(u.arrears), Catalog.money(float(u.rent))]
	return txt


static func central_bank(sim: Simulation) -> String:
	var Z: CentralBank = sim.central_bank
	var sm: Dictionary = Z.summary()
	var txt := "[b][color=#f2c14e]ZENTRALBANK UND GELDMENGE[/color][/b]
"
	txt += "Leitzins %.2f %% · Referenzzins der Banken %.2f %% · Inflation %.1f %% p. a. · Preisindex %.1f
" % [Z.policy_rate * 100.0, sim.banking.ref_rate * 100.0, Z.inflation * 100.0, Z.cpi]
	txt += "Geldmenge der Nichtbanken %s · Kreditvolumen %s · Zentralbankgeld in Umlauf %s
" % [Catalog.money(float(sm.geldmenge)), Catalog.money(float(sm.kreditvolumen)), Catalog.money(float(sm.zentralbankgeld))]
	txt += "Schulden: Haushalte %s · Unternehmen %s · Mindestreserve %d %%
" % [Catalog.money(float(sm.haushaltsschulden)), Catalog.money(float(sm.firmenschulden)), roundi(sim.banking.reserve_ratio * 100.0)]
	txt += "
[b]Bankbilanzen[/b]
"
	for i in Banking.BANKS.size():
		var b: Dictionary = Z.balance_sheet(i)
		txt += "  %s: Reserve %s + Kredite %s = Aktiva %s | Einlagen %s + Zentralbankkredit %s + Eigenkapital %s
" % [b.bank, Catalog.money(float(b.reserve)), Catalog.money(float(b.kredite)), Catalog.money(float(b.aktiva)), Catalog.money(float(b.einlagen)), Catalog.money(float(b.zentralbankkredit)), Catalog.money(float(b.eigenkapital))]
	return txt


## Unternehmer mit ihren Betrieben (Auftrag 14). Ergebnisse sind Kostenstellen derselben Buchungen (keine zweite Rechnung).
static func businesses(sim: Simulation) -> String:
	var txt := "[b][color=#f2c14e]UNTERNEHMER UND BETRIEBE[/color][/b]
"
	txt += "
[b]Marktmacht[/b] (Anteil am Umsatz je Branche, Fläche in Feldern: Eigentum / Pacht / reserviert)
"
	for d in sim.biz.dominance():
		var parts: Array = []
		for br in d.marktanteile:
			parts.append("%s %d %%" % [br, int(float(d.marktanteile[br]) * 100.0)])
		txt += "  %s: %s · %d Beschäftigte · %d Betriebe · Kapazität %d Chargen/Tag · Fläche %d / %d / %d · Vermögen %s · Schulden %s · Gewinn %s
" % [d.name,
			", ".join(parts) if not parts.is_empty() else "noch kein Umsatz", int(d.beschaeftigte), int(d.betriebe), int(d.kapazitaet_chargen_tag), int(d.flaeche_eigentum), int(d.flaeche_pacht),
			int(d.flaeche_reserviert), Catalog.money(float(d.vermoegen)), Catalog.money(float(d.schulden)), Catalog.money(float(d.gewinn))]
	for c in sim.companies:
		var L: Ledger = c.ledger
		txt += "
[b][color=#%s]%s[/color][/b] (%s, %s) · Bargeld %s · Gewinn %s · Hauptsitz %s
" % [c.color.to_html(false), c.company_name, c.player_name,
			Catalog.PERSONALITIES.get(c.personality, {}).get("name", c.personality), Catalog.money(L.cash), Catalog.money(L.profit()),
			sim.city.building(int(c.depots[0])).name if not c.depots.is_empty() else "–"]
		if L.cc_totals.has(Ledger.GENERAL):
			txt += "  Hauptsitz/Verwaltung: Ergebnis %s
" % Catalog.money(L.cc_profit(Ledger.GENERAL))
		var rows: Array = sim.biz.summary_of(c.id)
		if rows.is_empty():
			txt += "  [color=#9aa3ad]noch kein Betrieb[/color]
"
		for r in rows:
			var col := "#8fd18f" if r.status == "aktiv" else ("#e0a040" if r.status == "blockiert" else "#9aa3ad")
			txt += "  %s %s – [color=%s]%s[/color] · %d Personal · Umsatz %s · Kosten %s · Ergebnis %s · Strom %.0f kW
" % [r.id, r.name, col, r.status,
				int(r.personal), Catalog.money(float(r.umsatz)), Catalog.money(float(r.kosten)), Catalog.money(float(r.ergebnis)), float(r.strom_kw)]
			for bl in r.blockaden:
				txt += "    [color=#e0a040]Blockade: %s[/color]
" % bl
			var pd: Dictionary = sim.prod.detail(sim.biz.get_b(r.id))   # Produktion (Etappe 2): Phase/Chargen, Bestand, Unterwegs, Preise
			if pd.has("phase"):
				txt += "    Feld %s: Phase %s (Tag %d) · %d Felder · Ernten %d, zuletzt %d dt
" % [str(pd.get("grundstueck", "")), pd.phase, int(pd.tag_in_phase), int(pd.flaeche), int(pd.ernten), int(pd.letzte_ernte_dt)]
			elif pd.has("chargen_heute"):
				txt += "    Produktion heute %d Chargen (gesamt %d) · Absatz ~%d/Tag
" % [int(pd.chargen_heute), int(pd.chargen_gesamt), int(pd.get("absatz_tag", 0))]
			if pd.has("bestand"):
				var parts: Array = []
				for it in pd.bestand:
					parts.append("%s %d" % [Production.item_name(it), int(pd.bestand[it])])
				for it in pd.get("unterwegs", {}):
					parts.append("%s %d unterwegs" % [Production.item_name(it), int(pd.unterwegs[it])])
				for it in pd.get("preise", {}):
					parts.append("Preis %s %s" % [Production.item_name(it), Catalog.money(float(pd.preise[it]))])
				txt += "    %s
" % " · ".join(parts)
			var rb: Dictionary = sim.biz.get_b(r.id)
			if rb.branch == "hotel":
				var td: Dictionary = sim.tourism.detail(rb)
				txt += "    Zimmer %d, belegt %d, morgen gebucht %d · Preis %s/Nacht\n" % [int(td.zimmer), int(td.belegt), int(td.gebucht_morgen), Catalog.money(float(td.zimmerpreis))]
			elif Tourism.VENUES.has(str(rb.branch)):
				var td: Dictionary = sim.tourism.detail(rb)
				txt += "    Besucher heute %d · Eintritt %s · Getränke auf Lager %d\n" % [int(td.besucher_tag), Catalog.money(float(td.eintritt)), int(td.getraenke)]
			if rb.get("branch", "") == "immobilien":
				for key in rb.get("props", {}):
					var dd: Dictionary = sim.realty.detail(rb).gebaeude[key]
					txt += "    Gebäude %s: %d Wohnungen, %d belegt · Sollmiete %s/Monat · Buchwert %s
" % [key, int(dd.einheiten), int(dd.belegt), Catalog.money(float(dd.miete_monat)), Catalog.money(float(dd.buchwert))]
			if not r.letzte_entscheidung.is_empty():
				txt += "    Zuletzt (%s): %s
" % [r.letzte_entscheidung.source, r.letzte_entscheidung.text]
	return txt


## Stadtwerke: Leistung, Last, Abschaltungen, Tarif und Ausbau (Auftrag 14, Grundversorgung).
## Stadtfenster (Auftrag 15, Abschnitt 12): Name, Einwohner, Gebaeude, Entwicklung, Finanzen, Projekte, Hafen, Betriebsstufen.
static func town(sim: Simulation, k: int = 0) -> String:
	var T: Towns = sim.towns
	var M: Mayor = T.mayor(k)
	var g: Dictionary = M.goals()
	var region := T.is_region()
	var name: String = T.name_of(k)
	var chr: String = str(T.get_t(k).get("charakter", ""))
	var txt := "[b][color=#f2c14e]%s[/color][/b]%s  (Bürgermeister %s, %s, Zustimmung %d %%%s)\n" % [esc(name).to_upper(), (" · " + chr) if chr != "" else "", esc(M.name), M.party, int(M.approval),
		", Stadt %d von %d · Taste O wechselt" % [k + 1, T.count()] if region else ""]
	var homes := sim.housing.units.values().filter(func(u): return T.of_building(int(u.building)) == k) if region else sim.housing.units.values()
	var nb: int = sim.city.buildings.filter(func(b): return not region or T.of_building(int(b.id)) == k).size()
	txt += "Einwohner %d · Wohnungen %d (Leerstand %d %%) · Wohnungssuchende %d · Wohnhäuser %d · Geschäfte %d · Gebäude %d · Zufriedenheit %.0f\n" % [sim.citizens.population_of(k),
		homes.size(), int(M.vacancy() * 100.0), int(M.waiting), int(g.wohnhaeuser), int(g.geschaefte), nb, float(g.zufriedenheit)]
	var jobless: int = sim.citizens.people.filter(func(p): return p.employer == "" and sim.citizens.home_town(p) == k).size()
	txt += "Beschäftigung: %d Arbeitslose unter den Bürgern · Grundsicherung aus der eigenen Kasse\n" % jobless
	if region:
		var cm: Dictionary = sim.commute.stats.last.get(k, {})
		txt += "Pendler: %d fahren hinaus, %d kommen herein\n" % [int(cm.get("aus", 0)), int(cm.get("ein", 0))]
	if not M.growth_history.is_empty():
		var parts: Array = []
		for h in M.growth_history.slice(-4):
			parts.append("M%d: %d Wohnh./%d Gesch." % [int(h.monat), int(h.wohnhaeuser), int(h.geschaefte)])
		txt += "[b]Entwicklung[/b] " + " · ".join(parts) + "\n"
	txt += "[b]Finanzen[/b] Kasse %s · verfügbar %s · für Projekte reserviert %s · Mindestreserve %s\n" % [Catalog.money(M.cash()),
		Catalog.money(M.available_budget()), Catalog.money(M.commitments), Catalog.money(M.reserve_cash())]
	var open: Array = M.projects.values().filter(func(p): return p.status != "fertig" and p.has("kind"))
	txt += "[b]Projekte[/b] %d laufend\n" % open.size()
	for p in open.slice(0, 6):
		txt += "  %s %s: %s (%s)%s\n" % [p.id, p.kind, p.status, Catalog.money(float(p.cost)), " · Gemeinschaftsprojekt" if p.has("shares") else ""]
	var H: Harbor = T.harbor(k)
	if H.enabled:
		var h: Dictionary = H.summary()
		txt += "[b]Hafen[/b] %s · %d Ladeeinheiten je Schiff · Rückstau %.1f Schiffsladungen%s\n" % [h.stufe_name, int(h.ladung_je_schiff), float(h.rueckstau_schiffsladungen),
			" · Ausbau läuft" if bool(h.ausbau_laeuft) else (" · nächste Stufe %s (%s)" % [h.ausbau.ziel, Catalog.money(float(h.ausbau.kosten))] if not h.ausbau.is_empty() else "")]
	var D: CityDepot = T.depot(k)
	txt += "[b]Zentrallager[/b] %s · Konto %s\n" % [esc(sim.city.building(D.building).get("name", "")), D.owner()]
	var guests: Dictionary = sim.tourism.summary(k)
	txt += "[b]Tourismus[/b] %d Ankünfte · %d aktive Gäste · %d Übernachtungen · %d Freizeitbesuche · Ausgaben %s\n" % [int(guests.ankuenfte), int(guests.aktive_gaeste), int(guests.uebernachtungen), int(guests.get("nachtleben", 0)), Catalog.money(float(guests.ausgaben))]
	if region:
		var firms: Array = sim.companies.filter(func(c): return int(c.home_town) == k)
		txt += "[b]Unternehmen mit Heimat hier[/b] %s\n" % ", ".join(firms.map(func(c): return "%s (%s)" % [esc(c.company_name), c.status]))
	var here: Array = sim.biz.items.values().filter(func(b): return b.status != "geschlossen" and (not region or T.of_building(int(b.site)) == k))
	if not here.is_empty():
		txt += "[b]Betriebe in der Stadt[/b]\n"
		for b in here.slice(0, 14):
			var ob: Dictionary = sim.stages.obs(b)
			var nxt := ""
			if ob.has("ausbau"):
				nxt = " → %s %s" % [ob.ausbau.ziel, "möglich" if bool(ob.ausbau.moeglich) else "(fehlt: %s)" % "; ".join(ob.ausbau.fehlt)]
			if str(b.get("upgrading", "")) != "":
				nxt = " · Ausbau im Bau (%s)" % b.upgrading
			var owner: Company = sim.company(int(b.owner))
			txt += "  %s (%s%s)%s%s\n" % [esc(b.name), esc(owner.company_name), ", auswärts registriert" if region and int(owner.home_town) != k else "",
				(": " + str(ob.stufe_name) + ", Nachfrage %d %%" % int(float(ob.nachfrage) * 100.0)) if not ob.is_empty() else "", nxt]
	return txt


## Bewertung einer Stadt (Auftrag 17, Abschnitt 14): Bestandteile und Gewichte offen. Groesse und Schulden zaehlen nicht als Erfolg.
const TOWN_SCORE := {"versorgung": 0.25, "beschaeftigung": 0.2, "wohnen": 0.2, "zufriedenheit": 0.15, "infrastruktur": 0.1, "finanzen": 0.1}
static func town_score(sim: Simulation, k: int) -> Dictionary:
	var T: Towns = sim.towns
	var M: Mayor = T.mayor(k)
	var running: Array = sim.biz.items.values().filter(func(b): return b.status in Businesses.RUNNING and T.of_building(int(b.site)) == k)
	var shops := 0
	for br in ["baeckerei", "restaurant"]:
		if running.any(func(b): return b.branch == br):
			shops += 1
	var vers := (float(shops) / 2.0) * 0.6 + (0.4 if sim.city.buildings.any(func(b): return b.type == "shop" and T.of_building(int(b.id)) == k) else 0.0)
	var mine: Array = sim.citizens.people.filter(func(p): return sim.citizens.home_town(p) == k)
	var emp := float(mine.filter(func(p): return p.employer != "").size()) / maxf(1.0, float(mine.size()))
	var wohn := clampf(1.0 - float(M.waiting) / 5.0, 0.0, 1.0) * clampf(1.0 - absf(M.vacancy() - Mayor.BASE_VACANCY) * 3.0, 0.0, 1.0)
	var zuf := clampf(float(M.approval) / 100.0, 0.0, 1.0)
	var parcels_town: Array = sim.parcels.items.values().filter(func(p): return Towns.town_of_owner(str(p.owner)) == k)
	var infra := float(parcels_town.filter(func(p): return sim.parcels.utility_level(p) == "voll").size()) / maxf(1.0, float(parcels_town.size())) * 5.0
	var start := float(Economy.SEED.P0) if k == 0 else Towns.START_BUDGET
	var fin := clampf(M.available_budget() / start, 0.0, 1.0)
	var parts := {"versorgung": snappedf(vers, 0.01), "beschaeftigung": snappedf(emp, 0.01), "wohnen": snappedf(wohn, 0.01), "zufriedenheit": snappedf(zuf, 0.01),
		"infrastruktur": snappedf(minf(1.0, infra), 0.01), "finanzen": snappedf(fin, 0.01)}
	var total := 0.0
	for key in TOWN_SCORE:
		total += float(TOWN_SCORE[key]) * float(parts[key])
	return {"punkte": int(round(total * 100.0)), "teile": parts}


## Regionsuebersicht (Auftrag 17, Abschnitt 14): Staedte, Verbindungen, Fluege, Gemeinschaftsprojekte, Gruender, Pendler, Handel.
## Auftrag 19: Buergermeisterfenster - je Stadt Persoenlichkeit, Vision, Projekte mit Begruendung und Fortschritt, Bestellungen, Fahrt.
static func civic(sim: Simulation) -> String:
	if sim.civic == null or not sim.civic.enabled():
		return "Autonome Stadtentwicklung gibt es nur in der Region mit Großlager (neue Partie)."
	var txt := "[b][color=#f2c14e]STADTENTWICKLUNG[/color][/b] – alle %d Tage fährt jeder Bürgermeister zum Großlager und entscheidet über neue Projekte.

" % CivicWorks.VISIT_EVERY
	for k in sim.civic.profiles:
		var w: Dictionary = sim.civic.window(int(k))
		txt += "[b][color=%s]■[/color] %s – Bürgermeister %s[/b] (%s)
" % ["#" + str(w.farbe), esc(w.stadt), esc(w.name), esc(w.persoenlichkeit)]
		txt += "  Ziel: [i]%s[/i]
" % esc(w.vision)
		txt += "  Zustimmung %.0f %% · Kasse %s (verfügbar %s) · %s · nächster Besuch Tag %d
" % [float(w.zustimmung), Catalog.money(float(w.kasse)), Catalog.money(float(w.verfuegbar)), esc(w.unterwegs), int(w.naechster_besuch)]
		for p in w.projekte.slice(-6):
			var st: String = {"geplant": "geplant", "material": "Material wird geliefert", "im_bau": "im Bau %d %%" % int(float(p.fortschritt) * 100.0), "eroeffnet": "eröffnet", "abgelehnt": "vom Rat abgelehnt"}.get(str(p.status), str(p.status))
			txt += "  • [b]%s[/b] – %s%s
    Begründung: %s%s
" % [esc(p.titel), st, " (eigene KI-Idee)" if p.herkunft == "ki" else "", esc(p.grund).left(180), ("
    Ergebnis: " + esc(p.ergebnis)) if str(p.ergebnis) != "" else ""]
		if not w.bestellungen.is_empty():
			txt += "  Bestellungen: %s
" % esc(", ".join(w.bestellungen.slice(0, 6)))
		for l in w.lernen:
			txt += "  [color=#9fd8ff]Gelernt:[/color] %s
" % esc(l)
		txt += "
"
	if not sim.civic.comments.is_empty():
		txt += "[b]Sticheleien unter Bürgermeistern[/b]
"
		for c in sim.civic.comments.slice(-6):
			txt += "  Tag %d, %s: „%s“
" % [int(c.day), esc(sim.towns.name_of(int(c.from))), esc(c.text)]
	return txt


## Auftrag 19: zentrales Grosslager - Bestand, Preise, Knappheit, Handel.
static func hub(sim: Simulation) -> String:
	if sim.hub == null or not sim.hub.enabled:
		return "Auf dieser Karte gibt es kein Großlager (neue Region-Partie)."
	var H: CentralHub = sim.hub
	var txt := "[b][color=#f2c14e]GROSSLAGER[/color][/b] (Kartenmitte) – Kasse %s, frei %d von %d Einheiten
" % [Catalog.money(float(sim.economy.accounts.get(CentralHub.ACCT, 0.0))), H.free_capacity(), CentralHub.CAPACITY]
	txt += "Verkäufe %d (%s) · Ankäufe %d (%s) · Importe über den Flughafen %d (%s)

" % [int(H.stats.verkaeufe), Catalog.money(float(H.stats.umsatz)), int(H.stats.ankaeufe), Catalog.money(float(H.stats.ankauf)), int(H.stats.importe), Catalog.money(float(H.stats.import))]
	for w in H.summary().waren:
		txt += "  %s%-22s %5d  Kauf %8s  Ankauf %8s%s
" % ["[color=#ff8a6a]" if w.knapp else "", esc(w.name), int(w.bestand), Catalog.money(float(w.kaufpreis)), Catalog.money(float(w.ankaufpreis)), "  knapp[/color]" if w.knapp else ""]
	var open: Array = H.deals.values().filter(func(d): return d.status not in ["geliefert", "storniert"])
	if not open.is_empty():
		txt += "
[b]Unterwegs[/b]
"
		for d in open.slice(-10):
			txt += "  %s %s: %d × %s (%s)
" % [d.id, d.kind, int(d.qty), esc(CentralHub.item_name(str(d.item))), d.status]
	return txt


static func region(sim: Simulation) -> String:
	var T: Towns = sim.towns
	if not T.is_region():
		return "[b]REGION[/b]\nDiese Partie hat eine einzige Stadt (Weltart %s)." % sim.city.world
	var txt := "[b][color=#f2c14e]REGION · %d STÄDTE[/color][/b]  (Taste O: Stadt wählen und hinspringen)\n" % T.count()
	txt += "[b]Städte[/b] (Punkte = %s)\n" % ", ".join(TOWN_SCORE.keys().map(func(key): return "%s %d %%" % [key, int(TOWN_SCORE[key] * 100.0)]))
	for t in T.summary():
		var k := int(t.id)
		var sc := town_score(sim, k)
		txt += "  %s – Bürgermeister %s (%s), Zustimmung %d %%, Einwohner %d, Kasse %s (verfügbar %s), Unternehmen %d, Punkte %d %s\n" % [esc(t.name), esc(t.buergermeister),
			t.partei, int(t.zustimmung), sim.citizens.population_of(k), Catalog.money(float(t.kasse)), Catalog.money(float(t.verfuegbar)),
			sim.companies.filter(func(c): return int(c.home_town) == k).size(), int(sc.punkte), str(sc.teile)]
		var guests: Dictionary = sim.tourism.summary(k)
		txt += "    Tourismus: %d Ankünfte · %d aktive Gäste · %d Übernachtungen · %d Freizeitbesuche · Ausgaben %s\n" % [int(guests.ankuenfte), int(guests.aktive_gaeste), int(guests.uebernachtungen), int(guests.get("nachtleben", 0)), Catalog.money(float(guests.ausgaben))]
	txt += "[b]Verbindungen[/b] Startstraßen: %s\n" % ", ".join(sim.city.region_roads.map(func(r): return "%s %s–%s (%d Felder)" % [r.id, T.name_of(int(r.von)), T.name_of(int(r.nach)), int(r.laenge)]))
	for r in sim.regional.summary():
		txt += "  Gemeinschaftsprojekt %s %s: %s (%s, Anteile %s)%s\n" % [r.id, r.verbindung, r.status, Catalog.money(float(r.kosten)), r.anteile, (" – " + str(r.hinweis)) if str(r.hinweis) != "" else ""]
	if sim.air.enabled:
		var a: Dictionary = sim.air.summary()
		txt += "[b]Flugnetz[/b] Betreiber %s (Kasse %s) · Strecken %s\n" % [a.betreiber, Catalog.money(float(a.kasse)), ", ".join(a.strecken)]
		txt += "  Flüge %d · Passagiere %d · Fracht %d LE · Erlöse %s · Kosten %s · ausgefallen %d\n" % [int(a.statistik.fluege), int(a.statistik.passagiere), int(a.statistik.fracht_einheiten),
			Catalog.money(float(a.statistik.erloese)), Catalog.money(float(a.statistik.kosten)), int(a.statistik.ausgefallen)]
		for f in a.fluege_unterwegs:
			txt += "  ✈ %s %s → %s: %s (%d Passagiere, %d LE Fracht)\n" % [f.id, f.von, f.nach, f.status, int(f.passagiere), int(f.fracht_le)]
	var fs: Dictionary = sim.founders.summary()
	txt += "[b]Gründer[/b] höchstens %d aktive Unternehmen je Heimatstadt · Gründungen %d\n" % [int(fs.max_je_stadt), sim.founders.history.size()]
	for h in fs.gruendungen:
		txt += "  Tag %d %s: Firma %d (%s) – %s\n" % [int(h.tag), T.name_of(int(h.stadt)), int(h.firma), h.branche, h.anlass]
	for r in fs.abgelehnt:
		txt += "  [color=#999]Tag %d %s %s: %s[/color]\n" % [int(r.tag), T.name_of(int(r.stadt)), r.branche, r.grund]
	var cm: Dictionary = sim.commute.summary()
	txt += "[b]Pendeln[/b] %d Pendler · Fahrtkosten bisher %s · Umzüge zwischen Städten %d\n" % [int(cm.pendler), Catalog.money(float(cm.pendelkosten)), int(cm.umzuege)]
	var inner := 0
	var inner_val := 0.0
	for d in sim.prod.deals.values():
		if d.seller != Production.IMPORT and d.buyer != Production.IMPORT and T.of_building(int(d.seller_loc)) != T.of_building(int(d.buyer_loc)):
			inner += 1
			inner_val += float(d.qty) * float(d.unit)
	var ex: Dictionary = sim.prod.stats.exported
	var im: Dictionary = sim.prod.stats.imported
	txt += "[b]Handel[/b] Binnenhandel zwischen Städten: %d Geschäfte (%s) · Außenhandel: Einfuhr %d, Ausfuhr %d Einheiten\n" % [inner, Catalog.money(inner_val),
		im.values().reduce(func(s, x): return s + int(x), 0), ex.values().reduce(func(s, x): return s + int(x), 0)]
	return txt


static func power(sim: Simulation) -> String:
	var g: Dictionary = sim.grid.summary()
	var txt := "[b][color=#f2c14e]STROM (STADTWERKE)[/color][/b]
"
	txt += "Leistung %d kW · Bedarf %d kW (Grundlast der Bevölkerung %d kW, Betriebe %.0f kW) · Auslastung %d %%
" % [int(g.leistung_kw), int(g.bedarf_kw),
		int(g.grundlast_kw), float(g.betriebe_kw), int(float(g.auslastung) * 100.0)]
	txt += "Tarif %.2f EUR/kWh · abgerechnet %s für %d kWh · Erzeugungskosten %s · Tage mit Abschaltung %d
" % [float(g.tarif_eur_kwh),
		Catalog.money(float(sim.grid.stats.erloes)), int(sim.grid.stats.kwh), Catalog.money(float(sim.grid.stats.erzeugung)), int(g.engpass_tage)]
	if bool(g.ausbau_laeuft):
		txt += "[color=#8fd18f]Netzausbau läuft: +%d kW[/color]
" % int(g.ausbau.kw)
	# Auftrag 22 Phase 3: gemeinsames Kraftwerk, Verbrauch und Abrechnung je Stadt
	var st: Dictionary = g.get("staedte", {})
	var nz: Dictionary = g.get("netz", {})
	if not nz.is_empty():
		txt += "[b]Hochspannungsnetz[/b] · %d Trassen, %d Felder · " % [int(nz.trassen), int(nz.laenge_felder)]
		var cut: Array = nz.defekt
		if cut.is_empty():
			txt += "alle Umspannwerke angeschlossen
"
		else:
			var off_t: Array = nz.angeschlossen.keys().filter(func(k): return not bool(nz.angeschlossen[k])).map(func(k): return sim.towns.name_of(int(k)))
			txt += "[color=#e05040]Trasse %s unterbrochen – ohne Kraftwerksstrom: %s (nur Notstrom)[/color]
" % [", ".join(cut), ", ".join(off_t) if not off_t.is_empty() else "keine Stadt"]
		for lb in nz.get("im_bau", []):
			txt += "  [color=#8fd18f]Ringschluss im Bau: %s – %s (Projekt %s)[/color]\n" % [str(lb.von), str(lb.nach), str(lb.projekt)]
		for rp in nz.get("reparaturen", []):
			txt += "  Netztrupp %s repariert Trasse %s (%s)\n" % [str(rp.trupp), str(rp.trasse), str(rp.ursache)]
		var ns: Dictionary = nz.get("statistik", {})
		if int(ns.get("schaeden", 0)) > 0:
			txt += "  Schäden bisher %d, repariert %d (%s), Ausfall gesamt %.1f Spieltage\n" % [int(ns.schaeden), int(ns.reparaturen), Catalog.money(float(ns.kosten)),
				float(ns.ausfall_min) / GameCalendar.days_to_min(1.0)]
	if st.size() > 1:
		txt += "[b]Gemeinsames Kraftwerk[/b] · Anteile je %d %% · Gesellschaft %s offen bis Monatsende
" % [roundi(100.0 / float(st.size())), Catalog.money(float(g.gesellschaft_saldo))]
		for key in st:
			var a: Dictionary = sim.grid.by_town.get(key, {})
			txt += "  %s: %d kW (Grundlast %d, Betriebe %.0f, %d ohne Strom) · Bezug %s · Tarif der Betriebe %s · Ausgleich %s
" % [sim.towns.name_of(int(key)),
				roundi(float(st[key].grundlast) + float(st[key].versorgt)), roundi(float(st[key].grundlast)), float(st[key].versorgt), int(st[key].abgeschaltet),
				Catalog.money(float(a.get("bezug", 0.0))), Catalog.money(float(a.get("tarif", 0.0))), Catalog.money(float(a.get("ausschuettung", 0.0)))]
	if int(g.abgeschaltete_betriebe) > 0:
		txt += "[color=#e0a040]%d Betrieb(e) ohne Strom:[/color]
" % int(g.abgeschaltete_betriebe)
		for b in sim.biz.items.values():
			for x in b.blockers:
				if x.key == "strom":
					txt += "  %s (%s): %s
" % [b.name, sim.company(int(b.owner)).company_name, x.text]
	return txt


static func parcels(sim: Simulation) -> String:
	var P: Parcels = sim.parcels
	var sm: Dictionary = P.summary()
	var txt := "[b][color=#f2c14e]GRUNDSTÜCKE[/color][/b]\n"
	txt += "%d Grundstücke · unbebaute Reserve %.1f %% der bebaubaren Fläche\n" % [int(sm.anzahl), float(sm.reserveanteil) * 100.0]
	txt += "\n[b]Nach Status[/b]\n"
	for st in Parcels.STATES:
		txt += "  %s: %d\n" % [st, int(sm.nach_status.get(st, 0))]
	txt += "\n[b]Nach Zone[/b]\n"
	for z in sm.nach_zone:
		txt += "  %s: %d\n" % [Parcels.ZONES[z].label, int(sm.nach_zone[z])]
	txt += "\n[b]Günstigste freie Baugrundstücke[/b]\n"
	for p in P.search({"limit": 8}):
		txt += "  %s · %s · %d Felder · %s · Erschließung %s · %s\n" % [p.id, Parcels.ZONES[p.zone].label, int(p.area), Catalog.money(float(p.price)), P.utility_level(p), "Kauf"]
	return txt


## Muellwagen: Tour, Halte, Ladung, naechstes Ziel.
static func garbage_truck(sim: Simulation, v: Dictionary) -> String:
	var wert := str(v.get("stream", "rest")) == "wert"
	var phase := {"tour": ("fährt zum nächsten Halt" if not wert else "fährt zum nächsten Halt"), "leeren": ("Müllwerker leeren die Tonnen" if not wert else "Wertstoffwerker leeren Bio- und Wertstofftonne"),
		"zur_deponie": ("fährt zur Deponie" if not wert else "fährt zum Recyclinghof"), "abladen": ("lädt auf der Deponie ab" if not wert else "lädt am Recyclinghof ab"), "rueckfahrt": "fährt zum Betriebshof"}
	var txt := "Status: %s\n" % phase.get(str(v.phase), str(v.phase))
	txt += "Halt %d von %d · Ladung %.2f t von %.2f t\n" % [mini(int(v.get("stop", 0)) + 1, v.get("stops", []).size()), v.get("stops", []).size(), float(v.get("load", 0.0)), float(v.get("tons", 0.0))]
	if str(v.phase) in ["tour", "leeren"] and int(v.stop) < v.stops.size():
		var bid := int(v.stops[int(v.stop)].building)
		if wert:
			txt += "Haus: %s · Bio %.0f, Wertstoffe %.0f kg\n" % [sim.city.building(bid).name, float(sim.waste.bio.get(bid, 0.0)), float(sim.waste.wert.get(bid, 0.0))]
		else:
			txt += "Haus: %s · Tonne %.0f von %.0f kg\n" % [sim.city.building(bid).name, float(sim.waste.bins.get(bid, 0.0)), sim.waste.bin_capacity(bid)]
	txt += "Besatzung: Fahrer und zwei Müllwerker · Auftraggeber: %s (Müllabfuhr)\n" % sim.towns.name_of(int(v.get("town", 0)))
	return txt


## Bruecke: Variante, Phase, Fortschritt, Baufirma, Material, Kosten, Tragfaehigkeit, Sperrung.
static func bridge(sim: Simulation, b: Dictionary) -> String:
	var B: Bridges = sim.bridges
	var v: Dictionary = Bridges.VARIANTS[b.variant]
	var names := {"ausgeschrieben": "ausgeschrieben, Baufirma wird gesucht", "widerlager": "Widerlager an den Ufern", "pfeiler": "Pfeiler im Wasser",
		"fahrbahn": "Fahrbahn wird verlegt", "gelaender": "Geländer und Ausstattung", "abnahme": "Abnahme durch das Bauamt", "wartet": "wartet auf Material", "freigegeben": "freigegeben"}
	var txt := "Phase: [b]%s[/b] · Fortschritt %d %%\n" % [names.get(B.phase(b), B.phase(b)), int(B.progress(b) * 100.0)]
	txt += "Spannweite %d Felder · trägt %d t · Kosten %s · bezahlt von %s\n" % [b.cells.size(), int(v.last_t), Catalog.money(float(b.cost)),
		"der Stadtkasse" if int(b.payer) < 0 else sim.company(int(b.payer)).company_name]
	var prj: Dictionary = sim.mayor.projects.get(str(b.project), {})
	var e: Dictionary = sim.construction.public.get(str(b.project), {})
	if not e.is_empty():
		txt += "Baufirma: %s · Bauzeit %d Tage, noch %d\n" % [sim.construction.builders[e.builder].name, int(e.days), maxi(0, int(e.days_left))]
		if str(e.get("waiting", "")) != "":
			txt += "[color=#e0a040]Blockiert: %s (kommt per Schiff ins Stadtlager).[/color]\n" % e.waiting
	elif not prj.is_empty():
		txt += "Projekt %s: %s%s\n" % [prj.id, prj.status, (" – " + str(prj.tender.get("note", ""))) if str(prj.get("tender", {}).get("note", "")) != "" else ""]
	var mats: Array = []
	for it in prj.get("material", {}):
		mats.append("%d %s" % [int(prj.material[it]), CityGoods.get_item(it).get("name", it)])
	if not mats.is_empty():
		txt += "Material aus dem Stadtlager: %s\n" % ", ".join(mats)
	if b.status != "freigegeben":
		txt += "[color=#e07060]Gesperrt bis zur Abnahme – Fahrzeuge fahren noch nicht darüber.[/color]\n"
	else:
		txt += "Freigegeben seit Tag %d, Teil des Straßennetzes.\n" % int(b.get("opened", 0))
	if str(b.get("access", "")) != "":
		var j: Dictionary = sim.access.jobs.get(str(b.access), {})
		if not j.is_empty():
			txt += "Gehört zur Zufahrt %s nach %s (%d %% gebaut%s).\n" % [j.id, j.parcel, int(100.0 * float(j.built) / maxf(1.0, float(j.cells.size()))),
				", Trupp wartet am Ufer" if str(j.get("waiting", "")) != "" else ""]
	return txt


## Eisenbahn (Auftrag 22 Phase 6): Linie, Zuege mit Ort, Status, Verspaetung und Grund, Strecken.
static func rail(sim: Simulation) -> String:
	if sim.rail == null or not sim.rail.is_built():
		return ""
	var txt := "
[b][color=#2fb5a8]EISENBAHN (REGIONALBAHN)[/color][/b]
"
	var sm: Dictionary = sim.rail.summary()
	txt += "%d Bahnhöfe · %d Gleisfelder · Strecken: %s
" % [sm.bahnhoefe.size(), int(sm.gleisfelder), ", ".join(sm.abschnitte.map(func(a): return "%s %s–%s (%d Felder, %d Übergänge%s)" % [a.id, a.von, a.nach,
		int(a.felder), int(a.bahnuebergaenge), ", Brücke" if int(a.brueckenfelder) > 0 else ""]))]
	if sim.trains == null or sim.trains.path.is_empty():
		return txt
	var ts: Dictionary = sim.trains.summary()
	txt += "Linie RB: %s · Fahrzeit einfach ca. %d Spielminuten
" % [" – ".join(ts.linie), int(ts.fahrzeit_min)]
	for z in ts.zuege:
		var st: String = {"halt": "hält", "fahrt": "fährt", "wartet": "wartet am Signal"}.get(str(z.status), str(z.status))
		txt += "  %s %s %s · %d Fahrgäste · Verspätung %d min%s · %d Fahrten
" % [z.zug, st, z.ort, int(z.fahrgaeste), int(z.verspaetung_min), (" (%s)" % z.grund) if str(z.grund) != "" else "", int(z.fahrten)]
	var stt: Dictionary = ts.statistik
	txt += "  Kreuzungen im Bahnhof %d · Wartezeit am Signal %d min · gefahren %d Felder
" % [int(stt.kreuzungen), int(stt.wartezeit), int(stt.felder)]
	var wl: Array = []
	for k in ts.wartende:
		wl.append("%s %d" % [k, int(ts.wartende[k])])
	txt += "  Fahrgäste befördert %d (schwarz %d) · am Bahnsteig wartend: %s
" % [int(stt.fahrgaeste), int(stt.schwarz), ", ".join(wl)]
	txt += "  Regionalbahngesellschaft: Fahrgeld %s, Landeszuschuss %s, Betriebskosten %s · Saldo %s · Personal %d Triebfahrzeugführer, %d Zugbegleiter
" % [Catalog.money(float(stt.erloes)), Catalog.money(float(stt.zuschuss)), Catalog.money(float(stt.kosten)), Catalog.money(float(ts.gesellschaft_saldo)),
		int(ts.personal.triebfahrzeugfuehrer), int(ts.personal.zugbegleiter)]
	if not ts.letzter_ausgleich.is_empty():
		txt += "  letzter Monatsausgleich: %s nach Einwohneranteilen
" % Catalog.money(float(ts.letzter_ausgleich.ergebnis))
	for dz in ts.stoerungen:
		txt += "  [color=#e05040]Störung: %s seit %d Spielminuten – Bahntrupp aus %s[/color]
" % [dz.art, int(dz.seit_min), dz.trupp_aus]
	txt += "  Güterbahn: %d Einheiten warten am Güterbahnhof · %d befördert · %d Touren
" % [int(ts.get("gueter_wartend", 0)), int(stt.get("gueter_einheiten", 0)), int(stt.get("gueter_touren", 0))]
	txt += "  Bahnübergänge: %d gerade geschlossen, %d Schließungen · Störungen %d (Sperrzeit %d min) · auf die Straße ausgewichen %d Fahrgäste
" % [int(ts.schranken_zu), int(stt.get("schranken", 0)), int(stt.get("stoerungen", 0)), int(stt.get("ausfall_min", 0.0)), int(stt.get("strasse", 0))]
	return txt


## Trinkwasser je Stadt (Auftrag 22 Phase 4): Werk, Foerderung, Bedarf, Gebuehr, Engpaesse.
static func water(sim: Simulation) -> String:
	if not sim.water.enabled():
		return ""
	var txt := "
[b][color=#5aa0ff]TRINKWASSER (WASSERWERKE)[/color][/b]
"
	for t in sim.towns.list:
		var k := int(t.id)
		var w: Dictionary = sim.water.summary(k)
		var h: Dictionary = w.heute
		var g: Dictionary = w.gesamt
		if h.is_empty():
			txt += "%s: noch keine Abrechnung
" % sim.towns.name_of(k)
			continue
		var werk := "Fernwasser" if str(h.werk) == "" else "%s, Leistung %.0f m³, heute %.0f m³" % [str(h.werk), float(h.leistung), float(h.foerderung)]
		txt += "%s: %s · Bedarf %.1f m³ (Haushalte %.1f, Einrichtungen %.1f, Betriebe %.1f) · Gebühr %.2f €/m³ · Abwasser %.1f m³
" % [
			sim.towns.name_of(k), werk, float(h.bedarf), float(h.haushalte), float(h.einrichtungen), float(h.betriebe), float(w.tarif_eur_m3), float(h.abwasser)]
		if float(h.fehl) > 0.0 or int(h.abgeschaltet) > 0:
			txt += "  [color=#e05040]Wasserknappheit: %.1f m³ fehlen, %d Betriebe ohne Wasser (%s)[/color]
" % [float(h.fehl), int(h.abgeschaltet),
				str(h.grund) if str(h.grund) != "" else "Wasserwerk ausgelastet"]
		if not g.is_empty():
			txt += "  seit Beginn %.0f m³ · Gebühren Haushalte %s, Betriebe %s · Engpasstage %d
" % [float(g.m3), Catalog.money(float(g.haushalte_eur)),
				Catalog.money(float(g.betriebe_eur)), int(g.engpass_tage)]
	return txt


## Deponie: Fuellstand, Erweiterung, Waage je Stadt, Tonnen, Kosten und Gebuehren.
static func landfill(sim: Simulation) -> String:
	var W: Waste = sim.waste
	var txt := "[b]Gemeinsame Deponie[/b] · Füllstand %.0f %% (%.0f von %.0f t Restmüll)\n" % [W.fill_share() * 100.0, W.deposited, W.capacity]
	if not W.expansion.is_empty():
		var ep: Dictionary = W._expansion_project()
		var ee: Dictionary = sim.construction.public.get(str(W.expansion.get("project", "")), {})
		var who := str(sim.construction.builders.get(str(ee.get("builder", "")), {}).get("name", "")) if not ee.is_empty() else ""
		var zust := ""
		if who != "":
			zust = "Baufirma %s baut (noch %d Tage, Budget %s)" % [who, int(ee.days_left), Catalog.money(float(W.expansion.kosten))]
		elif str(ep.get("status", "")) in ["beauftragt", "im_bau"]:
			zust = "Baufirma baut (Budget %s)" % Catalog.money(float(W.expansion.kosten))
		else:
			zust = "Ausschreibung läuft (Budget %s, Baufirmen bieten)" % Catalog.money(float(W.expansion.kosten))
		txt += "[color=#e0a040]Erweiterung um %.0f t: %s.[/color]\n" % [float(W.expansion.t), zust]
	elif W.fill_share() > 0.7:
		txt += "[color=#e0a040]Die Deponie wird voll – ab %d %% wird erweitert.[/color]\n" % roundi(Waste.EXPAND_AT * 100.0)
	if W.iv_building > 0 and W.iv_fertig == 0:
		var e2: Dictionary = sim.construction.public.get(W.iv_project, {}) if W.iv_project != "" else {}
		var who2 := str(sim.construction.builders.get(str(e2.get("builder", "")), {}).get("name", "")) if not e2.is_empty() else ""
		var state := "Baufirma %s baut (noch %d Tage)" % [who2, int(e2.days_left)] if who2 != "" else "Ausschreibung läuft (Baufirmen bieten)"
		txt += "[color=#e0a040]Müllverbrennungsanlage im Bau (%s) – der Restmüll wird bis dahin noch gelagert.[/color]\n" % state
	if W.iv_fertig > 0 and W._iv_on():
		var kw := W.iv_available_kw()
		txt += "Müllverbrennung: %.1f t verbrannt (gestern %.1f t, Strom %d kW ins Netz, %.0f MWh gesamt) · Asche %.1f t von %.1f t Restmüll\n" % [
			float(W.iv_stats.t), float(W.iv_last.t), roundi(kw), float(W.iv_stats.kwh) / 1000.0, float(W.iv_stats.ash), float(W.iv_stats.t)]
		txt += "Kosten je Tonne: Deponiegebühr nur für die Asche, plus Verarbeitung %s – der Stromerlös (%s gestern) deckt den Anlagenbetrieb.\n" % [
			Catalog.money(Waste.IV_PROC_PER_T), Catalog.money(float(W.iv_last.kwh) * sim.grid.tariff)]
	txt += "Diesen Monat gewogen %.1f t · Recyclingquote %.0f %% (Mehrweg %.0f %%) · Erweiterungen bisher %d\n" % [float(W.month.tons), W.rate * 100.0, W.mehrweg_share() * 100.0, W.expansions]
	txt += "Müllwagen unterwegs: %d · Touren bisher %d · Halte %d\n" % [sim.fleet.vehicles.filter(func(v): return v.kind == "muell").size(), W.tours, int(sim.fleet.stats.halte)]
	if W.real:
		txt += "Wertstoffwagen unterwegs: %d · Wertstofftouren bisher %d · Bio- und Wertstofftonnen je Stadt unten\n" % [sim.fleet.vehicles.filter(func(v): return v.kind == "wertstoff").size(), W.tours_wert]
	txt += "\n[b]Waage – Anlieferung je Stadt (gesamt)[/b]\n"
	for k in sim.towns.count():
		var t: Dictionary = W.by_town.get(str(k), {}).get("total", {})
		var bins_k: int = W.bins.keys().filter(func(b): return sim.towns.of_building(b) == k).size()
		txt += "  %s: %.1f t · Kosten %s · Gebühren %s · Tonnen %d, davon %d überquellend\n" % [sim.towns.name_of(k), float(t.get("tons", 0.0)),
			Catalog.money(float(t.get("cost", 0.0))), Catalog.money(float(t.get("fees", 0.0))), bins_k, W.overflowing(k).size()]
		if W.real:
			var bio_k: int = W.bio.keys().filter(func(b): return sim.towns.of_building(b) == k).size()
			var wert_k: int = W.wert.keys().filter(func(b): return sim.towns.of_building(b) == k).size()
			txt += "    Tonnen: %d Rest · %d Bio · %d Wertstoffe\n" % [bins_k, bio_k, wert_k]
		var dep: Dictionary = W.depot_of(k)
		txt += "    %s\n" % ("Abholung durch Entsorger (kein Betriebshof)" if dep.is_empty() else "%s: %d Müllwagen, %d mit Besatzung, %d Müllwerker" % [dep.name,
			dep.vehicles.filter(func(v): return str(sim.municipal.vehicles[v].type) == "Müllwagen").size(), W.crews_of(k), sim.municipal.staff_count(dep.id, "muellwerker")])
		var sc: Dictionary = sim.street_cleaning.summary(k)
		var worst := ""
		if not sc.viertel.is_empty():
			var d: int = sc.viertel.max(func(x, y): return float(sc.viertel[x]) > float(sc.viertel[y]))
			worst = " · verschmutztes Viertel: %s (%d %%)" % [Catalog.DISTRICTS[d], int(float(sc.viertel[d]) * 100.0)]
		txt += "    Stadtreinigung: %d verschmutzte Straßenstellen (%.0f kg Straßenmüll)%s · Kehrmaschine im Einsatz: %d, geräumt %d\n" % [int(sc.abschnitte), float(sc.dreck_kg), worst, int(sc.im_einsatz), int(sc.geraeumt)]
	if not W.scale_log.is_empty():
		txt += "Letzte Wägungen: %s\n" % ", ".join(W.scale_log.slice(-5).map(func(e): return "Tag %d %s %.2f t" % [int(e.tag), sim.towns.name_of(int(e.stadt)), float(e.t)]))
	txt += "Kosten bisher %s · Wertstofferlöse %s · Gebühren der Haushalte %s\n" % [Catalog.money(float(W.total.cost)), Catalog.money(float(W.total.income)), Catalog.money(float(W.total.fees))]
	return txt


## Berg mit Lagerstaette bzw. Bergwerk (Klick auf den Berg): Vorkommen, Abbau, Betreiber, Foerderung, Halde, Lage.
static func mountain(sim: Simulation, pid: String) -> String:
	var P: Production = sim.prod
	var dep := P.deposit_of(pid)
	var ex := P.excavated(pid)
	var p: Dictionary = sim.parcels.parcel(pid)
	var item := str(dep.get("art", ""))
	var start := int(P.terrain.get(pid, {}).get("start", 0))
	var txt := "[b]Lagerstätte[/b] %s · Grundstück %s (%d Felder)\n" % [Production.item_name(item), pid, int(p.get("area", 0))]
	txt += "Restvorrat %d von %d Einheiten · Qualität %.0f %% · abgebaut %.1f %%\n" % [int(dep.get("menge", 0)), start, float(dep.get("qualitaet", 0.0)) * 100.0, float(ex.get("anteil", 0.0)) * 100.0]
	var mb := P.mine_on(pid)
	if mb.is_empty():
		txt += "\n[color=#9aa3ad]Noch kein Bergwerk. Kaufpreis des Grundstücks %s. Abbau über die Unternehmer-Aktion found_business (branche bergwerk, rohstoff %s); Abbau nur auf eigenem Grund.[/color]\n" % [Catalog.money(float(p.get("price", 0.0))), item]
		return txt
	var c = sim.company(int(mb.owner))
	var d := P.detail(mb)
	txt += "\n[b]Betreiber[/b] [color=#%s]%s[/color] · Status %s · Personal %d · Förderung heute %d · gesamt %d\n" % [c.color.to_html(false), c.company_name, mb.status,
		sim.biz.staff_of(mb.id).size(), int(d.get("foerderung_heute", 0)), int(mb.get("total", 0))]
	txt += "Halde %d Einheiten · Preis %s je Einheit · Absatz ~%d/Tag\n" % [sim.stock.qty(item, "C%d" % int(mb.owner), int(mb.site)), Catalog.money(P.price_of(mb, item)), int(d.get("absatz_tag", 0))]
	for bl in mb.blockers:
		txt += "[color=#e0a040]Blockade: %s[/color]\n" % bl.text
	var bt: float = float(P.blasts.get(mb.id, -1.0))
	if bt >= 0.0:
		txt += "Letzte Sprengung: %s\n" % GameCalendar.short_text(bt)
	var buyers := {}
	for dl in P.deals.values():
		if dl.seller_biz == mb.id:
			buyers[P._who(dl.buyer)] = int(buyers.get(P._who(dl.buyer), 0)) + int(dl.qty)
	if not buyers.is_empty():
		var parts: Array = []
		for k in buyers:
			parts.append("%s %d" % [k, int(buyers[k])])
		txt += "Lieferungen an: %s\n" % ", ".join(parts)
	var L: Ledger = c.ledger
	txt += "Ergebnis des Betriebs: %s (Umsatz %s)\n" % [Catalog.money(L.cc_profit(mb.id)), Catalog.money(L.cc_revenue(mb.id))]
	if not mb.decisions.is_empty():
		txt += "Zuletzt: %s\n" % mb.decisions.back().text
	return txt


static func site(sim: Simulation, pr: Dictionary) -> String:
	var C: Construction = sim.construction
	var txt := "Bauherr: %s · Baufirma: %s · Genehmigung: %s · Status: %s
" % [pr.client, C.builders[pr.builder].name if pr.builder != "" else "noch keine", pr.app, pr.status]
	txt += "Preis %s · bezahlt %s · zurückgelegt %s · Phase: %s · Fortschritt %.0f %% · Fertigstellung ca. Tag %d
" % [Catalog.money(float(pr.price)), Catalog.money(float(pr.paid)),
		Catalog.money(float(pr.reserved)), C.phase_label(pr), C.progress_of(pr) * 100.0, C.forecast_day(pr)]
	var crew := C.crew_of(pr)
	if not crew.is_empty():
		var gear: Array = crew.gear.map(func(g): return Construction.GEAR_NAMES[g])
		txt += "Mannschaft (%s): 1 Vorarbeiter, %d Bauarbeiter, %d Maschinenführer%s · %s
" % [crew.role, int(crew.workers), int(crew.operators),
			(" · Geräte: " + ", ".join(gear)) if not gear.is_empty() else "", "arbeitet" if crew.working else "steht still (Blockade)"]
	var m: Dictionary = pr.mats.get(Construction.PHASES[mini(int(pr.phase), Construction.PHASES.size() - 1)].id, {})
	if not m.is_empty():
		txt += "Material dieser Phase: benötigt %s · geliefert %s
" % [JSON.stringify(m.need), JSON.stringify(m.delivered)]
	for d in C.deliveries.values():
		if d.project == pr.id and d.status == "offen":
			txt += "Erwartete Lieferung %s: %s
" % [d.id, JSON.stringify(d.need)]
	for bl in pr.blockers:
		txt += "Blockade: %s
" % bl
	return txt


static func construction(sim: Simulation) -> String:
	var C: Construction = sim.construction
	var sm: Dictionary = C.summary()
	var txt := "[b][color=#f2c14e]BAUVORHABEN UND BAUFIRMEN[/color][/b]
"
	txt += "%d Vorhaben · %d Wohneinheiten (%d vermietet) · %d offene Lieferaufträge · %d öffentliche Projekte
" % [int(sm.vorhaben), int(sm.einheiten), int(sm.vermietet), int(sm.offene_lieferungen), int(sm.oeffentlich)]
	txt += "
[b]Baufirmen[/b]
"
	for id in C.builders:
		var b: Dictionary = C.builders[id]
		txt += "  %s · %s · Preisfaktor %.2f · Qualität %.0f %% · Zuverlässigkeit %.0f %% · Auslastung %d/%d · fertig %d, Mängel %d
" % [id, esc(str(b.name)), float(b.price),
			float(b.quality) * 100.0, float(b.reliability) * 100.0, C.load_of(id), int(b.capacity), int(b.history.fertig), int(b.history.maengel)]
	txt += "
[b]Baustellen[/b]
"
	for pr in C.projects.values():
		var parcel: Dictionary = sim.parcels.parcel(pr.parcel)
		txt += "  %s · %s · %s auf %s (%s)
    Bauherr %s · Baufirma %s · Preis %s · bezahlt %s · Phase: %s · Fortschritt %.0f %% · Fertigstellung ca. Tag %d
" % [pr.id,
			pr.status, Planning.DEFS[pr.def].label, pr.parcel, Parcels.ZONES[parcel.zone].label, esc(str(pr.client)),
			esc(str(C.builders[pr.builder].name)) if pr.builder != "" else "-", Catalog.money(float(pr.price)), Catalog.money(float(pr.paid)), C.phase_label(pr),
			C.progress_of(pr) * 100.0, C.forecast_day(pr)]
		for bl in pr.blockers:
			txt += "    [color=#e07a5f]Blockade: %s[/color]
" % esc(str(bl))
		if not pr.lost_days.is_empty():
			txt += "    Verlorene Tage: %s
" % esc(JSON.stringify(pr.lost_days))
	txt += "
[b]Offene Lieferaufträge (Transportunternehmen)[/b]
"
	for d in C.open_deliveries().slice(0, 8):
		txt += "  %s · %s · %s · Frachtlohn %s
" % [d.id, d.project, esc(JSON.stringify(d.need)), Catalog.money(float(d.freight))]
	return txt


## Kurzuebersicht beim Anklicken des Zentrallagers (Abschnitt 8).
static func depot_panel(sim: Simulation) -> String:
	var D: CityDepot = sim.city_depot
	var ct: Dictionary = D.current_tasks()
	var txt := "Betreiber und Eigentümer: Stadtverwaltung (Konto P0) · Bauhof angeschlossen\n"
	var staff: Array = D.roster()
	txt += "[b]Mitarbeiter[/b] %d, davon %d verfügbar:\n" % [staff.size(), D.available_staff()]
	var by_name := {}
	for tk in ct.tasks:
		by_name[tk.worker] = tk
	for w in staff:
		var tk: Dictionary = by_name.get(w.id, {})
		txt += "  %s (%s) · %s · Erschöpfung %d %%%s\n" % [esc(str(w.name)), w.role_label, w.state, int(w.fatigue), (" · " + esc(str(tk.task)) + ((": " + esc(str(CityGoods.get_item(tk.item).get("name", "")))) if str(tk.item) != "" else "")) if not tk.is_empty() else ""]
	txt += "[b]Rampen[/b] %d (frei %d) · [b]Geräte[/b] Gabelstapler %d, Hubwagen %d · Wareneingang schafft %d Einheiten/Tag, Rückstau %d\n" % [D.ramps, D.ramps_free(), D.forklifts(), D.hand_trucks(), D.dock_capacity(), D.backlog_units()]
	var sm: Dictionary = D.summary()
	var zs := []
	for z in CityGoods.ZONES:
		zs.append("%s %d %%" % [CityGoods.ZONES[z].label, int(100.0 * float(sm.zonen[z].belegt) / float(sm.zonen[z].kapazitaet))])
	txt += "[b]Auslastung[/b] " + " · ".join(zs) + "\n"
	var res_total := 0
	for r in sim.stock.reservations.values():
		if Towns.town_of_account(str(r.owner)) >= 0:
			res_total += int(r.qty)
	txt += "[b]Reserviert[/b] %d Einheiten für %d Projekte\n" % [res_total, D.project_res.size()]
	var inc: Array = D.open_orders().filter(func(o): return o.status != "vorschlag")
	txt += "[b]Eingehende Lieferungen[/b] %d" % inc.size()
	for o in inc.slice(0, 3):
		txt += " · %d × %s (%s)" % [int(o.qty), esc(CityGoods.get_item(o.item).name), o.status]
	txt += "\n[b]Ausgehende Aufträge[/b] " + (", ".join(D.project_res.keys()) if not D.project_res.is_empty() else "keine") + "\n"
	var crit: Array = D.critical_items()
	txt += "[b]Fehlende Artikel[/b] " + (", ".join(crit.slice(0, 5).map(func(i): return str(i.name))) if not crit.is_empty() else "keine") + "\n"
	var rc: Dictionary = D.running_costs()
	txt += "[b]Laufende Kosten[/b] %s im Monat (Löhne %s, Betrieb %s)\n" % [Catalog.money(float(rc.summe)), Catalog.money(float(rc.loehne)), Catalog.money(float(rc.betrieb))]
	if not ct.blockers.is_empty() or not ct.waiting.is_empty():
		txt += "[b]Blockaden[/b] " + "; ".join(ct.waiting + ct.blockers) + "\n"
	txt += "Details: Reiter Wirtschaft → Stadtlager. Paletten in der Innenansicht anklicken für Herkunft und Auftrag."
	return txt


## Warenposten: Herkunft, Eigentuemer, Menge, Standort, zugehoeriger Auftrag.
static func lot(sim: Simulation, l: Dictionary) -> String:
	var it: Dictionary = CityGoods.get_item(l.item)
	var owner_name: String = {"P0": "Stadtverwaltung", "T0": "Großhändler (Bauhof)", "X0": "Ausland"}.get(str(l.owner), "Unternehmen %s" % l.owner)
	var txt := "Artikel: %s (%s, %s) · Menge %d %s · Zustand: %s\n" % [esc(str(it.get("name", l.item))), str(it.get("group_label", "")), str(it.get("class", "")), int(l.qty), str(it.get("unit", "")), str(l.get("state", "ok"))]
	txt += "Eigentümer: %s · Standort: %s (%s)\n" % [owner_name, esc(sim.city.building(int(l.loc)).name), CityGoods.ZONES.get(str(it.get("zone", "")), {}).get("label", "")]
	txt += "Herkunft: %s\n" % esc(str(l.source))
	var refs: Array = []
	for o in sim.city_depot.orders.values():
		if o.item == l.item and o.status in ["angeliefert", "eingelagert", "bezahlt"]:
			refs.append("%s (%s, %s)" % [o.id, o.supplier, o.status])
	for pid in sim.city_depot.project_res:
		if sim.city_depot.project_res[pid].reserved.has(l.item):
			refs.append("reserviert für Projekt %s (%d)" % [pid, int(sim.city_depot.project_res[pid].reserved[l.item])])
	txt += "Zugehörige Aufträge: " + (", ".join(refs.slice(-4)) if not refs.is_empty() else "keine") + "\n"
	txt += "Bestand frei %d · reserviert %d" % [sim.stock.available(l.item, l.owner, int(l.loc)), sim.stock.reserved(l.item, l.owner, int(l.loc))]
	return txt


static func city_depot(sim: Simulation) -> String:
	var D: CityDepot = sim.city_depot
	var sm: Dictionary = D.summary()
	var txt := "[b][color=#f2c14e]STADTLAGER (ZENTRALLAGER MIT BAUHOF)[/color][/b]
"
	txt += "Standort: %s · Eigentümer und Einkäufer: Stadtverwaltung (Konto P0)
" % esc(sim.city.building(D.building).name)
	txt += "Einkauf bisher %s · Fracht %s · Verkauf von Überbeständen %s · Stadtfuhrpark-Fahrten %d · Ausschuss %d
" % [Catalog.money(float(sm.einkauf)), Catalog.money(float(sm.fracht)),
		Catalog.money(float(sm.verkauft)), int(D.stats.fallback_trips), int(D.stats.scrapped)]
	txt += "
[b]Lagerbereiche[/b]
"
	for z in CityGoods.ZONES:
		var zz: Dictionary = sm.zonen[z]
		txt += "  %s: %d von %d belegt (%.0f %%)
" % [CityGoods.ZONES[z].label, int(zz.belegt), int(zz.kapazitaet), 100.0 * float(zz.belegt) / float(zz.kapazitaet)]
	txt += "
[b]Beschaffung[/b] (Bedarf → Budget → Bestellung → Transport → Anlieferung → Prüfung → Einlagerung → Zahlung)
"
	var rows: Array = D.open_orders()
	rows.sort_custom(func(a, b): return int(a.day) > int(b.day))
	for o in rows.slice(0, 10):
		txt += "  %s · %s · %d × %s · %s%s
" % [o.id, str(o.status).capitalize(), int(o.qty), esc(CityGoods.get_item(o.item).name), esc(str(o.get("supplier", ""))),
			(" · " + esc(str(o.history[-1].text))) if not o.history.is_empty() else ""]
	if rows.is_empty():
		txt += "  keine offenen Vorgänge
"
	txt += "
[b]Kritische Bestände[/b]
"
	for i in D.critical_items().slice(0, 8):
		txt += "  %s: %d %s (Mindestbestand %d, bestellt %d)
" % [esc(str(i.name)), int(i.bestand), esc(str(i.einheit)), int(i.mindestbestand), int(i.unterwegs)]
	if D.critical_items().is_empty():
		txt += "  keine
"
	txt += "
[b]Projektmaterial[/b]
"
	for pid in D.project_res:
		var r: Dictionary = D.project_res[pid]
		txt += "  %s · %s · Wert %s · %s
" % [pid, r.mode, Catalog.money(float(r.value)), "vollständig reserviert" if D.project_complete(pid) else "Fehlmenge wird beschafft"]
	txt += "
[b]Letzte Ausgaben[/b]
"
	for i in D.issues.slice(-6):
		txt += "  Tag %d · %d × %s → %s (%s)
" % [int(i.day), int(i.qty), esc(CityGoods.get_item(i.item).name), esc(str(i.to)), str(i.mode)]
	return txt


static func permits(sim: Simulation) -> String:
	var PM: Permits = sim.permits
	var sm: Dictionary = PM.summary()
	var txt := "[b][color=#f2c14e]BAUANTRÄGE UND PLANUNGSREGELN[/color][/b]\n"
	txt += "%d Anträge · %d in der Warteschlange · Verwaltungskapazität %.1f Punkte je Tag (Rathaus: %d Beschäftigte)\n" % [int(sm.anzahl), int(sm.warteschlange), float(sm.kapazitaet_je_tag), sim.citizens.employed_count("rathaus")]
	txt += "\n[b]Warteschlange[/b]\n"
	for a in PM.queue().slice(0, 8):
		txt += "  %s · %s · %s auf %s · Stand %d/%d · Entscheidung voraussichtlich Tag %d\n" % [a.id, esc(str(a.applicant)), Planning.DEFS[a.def].label, a.parcel, int(a.progress), int(a.effort), PM.eta_day(a.id)]
	txt += "\n[b]Offene Rückfragen[/b]\n"
	for a in PM.apps.values():
		if a.status == "rueckfrage":
			txt += "  %s (%s): %s\n" % [a.id, esc(str(a.applicant)), esc(" ".join(a.questions))]
	txt += "\n[b]Letzte Entscheidungen[/b]\n"
	var done: Array = PM.apps.values().filter(func(a): return a.status == "entschieden")
	for a in done.slice(-6):
		txt += "  %s · %s · %s\n    %s\n" % [a.id, a.result, esc(str(a.decided_by)), esc(str(a.decision).left(200))]
	txt += "\n[b]Planungsregeln je Zone[/b]\n"
	for z in Planning.ZONE_RULES:
		var r: Dictionary = Planning.rules(z)
		txt += "  %s: bis %d Geschosse, Bebauung höchstens %d %%, Freifläche mind. %d %%, Gebühr %s + %s je Geschossfeld, Beitrag %s je Feld\n    %s\n" % [r.label, int(r.max_geschosse),
			roundi(float(r.max_bebauung) * 100.0), roundi(float(r.min_freiflaeche) * 100.0), Catalog.money(float(r.gebuehr_basis)), Catalog.money(float(r.gebuehr_je_geschossfeld)),
			Catalog.money(float(r.erschliessungsbeitrag_je_feld)), esc(str(r.hinweis))]
	return txt


## Kurzbezeichnung der Steuerung des Buergermeisters fuer Karte und Kopfzeile.
static func mayor_mode(agent: MayorAgent) -> String:
	if agent == null or not agent.uses_model():
		return "Regeln"
	var provider := str(agent.config.get("provider", ""))
	var model := str(agent.config.get("model", ""))
	var label := "Claude" if provider == "anthropic" else ("Ollama" if provider == "ollama" else provider)
	var txt := "%s · %s" % [label, model]
	if agent.fallback_active:
		txt += " · Ersatzmodus"
	return txt


## Was der Buergermeister gerade tut: {text, color, detail} fuer die Karte.
static func mayor_now(sim: Simulation, agent: MayorAgent) -> Dictionary:
	var M: Mayor = sim.mayor
	var last: Dictionary = M.decisions.back() if not M.decisions.is_empty() else {}
	var detail := ""
	if agent != null and not agent.summaries.is_empty():
		detail = str(agent.summaries.back().text).left(240)
	var text := "wartet auf die nächste Runde"
	var color := UITheme.MUTED
	if agent != null and agent.status.begins_with("wartet"):
		text = "überlegt gerade …"
		color = UITheme.ACCENT
	elif agent != null and agent.status.begins_with("Fehler"):
		text = "Störung: %s" % agent.last_error.left(40)
		color = UITheme.BAD
	elif not last.is_empty():
		text = "Zuletzt: %s%s" % [str(last.action), "" if last.ok else " (abgelehnt)"]
		color = UITheme.GOOD if last.ok else UITheme.BAD
	return {"text": text, "color": color, "detail": detail}


## Lage der Stadt aus Sicht des Buergermeisters (linke Spalte der Detailansicht).
static func mayor_state(sim: Simulation) -> String:
	var M: Mayor = sim.mayor
	var txt := "[b][color=#f2c14e]LAGE DER STADT[/color][/b]\n"
	txt += _mayor_lage(M, M.indicators())
	txt += _rathaus_text(sim)
	txt += "\n[b]Wahlen[/b]\n"
	for e in M.elections:
		txt += "  Tag %d: %s (Zustimmung %.0f %%)%s\n" % [int(e.day), e.ergebnis, float(e.zustimmung), (", Nachfolger " + esc(str(e.nachfolger))) if e.has("nachfolger") else ""]
	if M.elections.is_empty():
		txt += "  Noch keine Wahl.\n"
	return txt


## Was die Steuerung gerade macht und entschieden hat (rechte Spalte der Detailansicht).
static func mayor_activity(sim: Simulation, agent: MayorAgent) -> String:
	var M: Mayor = sim.mayor
	var txt := "[b][color=#f2c14e]STEUERUNG[/color][/b]\n"
	if agent != null:
		txt += "%s · Status: [b]%s[/b]\nAnfragen %d · gültig %d · Fehler %d · ungültige Antworten %d · Token %d\nAktionen ausgeführt %d · abgelehnt %d\n" % [
			mayor_mode(agent), esc(agent.status), int(agent.stats.requests), int(agent.stats.ok), int(agent.stats.errors), int(agent.stats.invalid),
			int(agent.stats.tokens), int(agent.stats.actions_ok), int(agent.stats.actions_rejected)]
		if agent.last_error != "":
			txt += "[color=#ff6b5e]Letzter Fehler: %s[/color]\n" % esc(agent.last_error.left(200))
		txt += "\n[b][color=#f2c14e]BEGRÜNDUNGEN DER LETZTEN RUNDEN[/color][/b]\n"
		if agent.summaries.is_empty():
			txt += "Noch keine Runde abgeschlossen.\n"
		for s in agent.summaries.slice(-5):
			txt += "• [color=#9a98a8](%s, %s)[/color] %s\n" % [Catalog.game_time_short(float(s.t)), esc(str(s.source)), esc(str(s.text))]
	txt += "\n[b][color=#f2c14e]LETZTE ENTSCHEIDUNGEN[/color][/b]\n"
	if M.decisions.is_empty():
		txt += "Noch keine.\n"
	for d in M.decisions.slice(-10):
		txt += "[b]Tag %d · %s[/b] [color=#%s]%s[/color]\n    Grund: %s\n    Ergebnis: %s\n" % [int(d.day), esc(str(d.action)), "6fd08c" if d.ok else "ff6b5e",
			"ausgeführt" if d.ok else "abgelehnt", esc(str(d.reason)), esc(str(d.msg).left(160))]
	return txt


## Rathaus: Abteilungen mit Soll/Ist und Belegschaft (Auftrag 9).
static func _rathaus_text(sim: Simulation) -> String:
	var T: TownHall = sim.town_hall
	var sm: Dictionary = T.summary()
	var txt := "
[b][color=#f2c14e]RATHAUS[/color][/b] %s
" % ("(%s)" % esc(sm.gebaeude) if sm.gebaeude != "" else "(ohne Gebäude)")
	txt += "Personal %d von %d Stellen · offene Stellen %d · Kosten %s je Monat · Bauanträge %.1f Punkte je Tag
" % [int(sm.ist_gesamt), int(sm.soll_gesamt),
		int(sm.offene_stellen), Catalog.money(float(sm.kosten_monat)), float(sm.bauantrag_kapazitaet_je_tag)]
	var roster: Array = T.roster()
	for d in sm.abteilungen:
		var e: Dictionary = sm.abteilungen[d]
		txt += "  [b]%s[/b] %d/%d · %s
" % [esc(e.bezeichnung), int(e.ist), int(e.soll), esc(e.aufgabe)]
		var names: Array = roster.filter(func(r): return r.dept == d).slice(0, 6).map(func(r): return esc(r.name))
		if not names.is_empty():
			txt += "    [color=#9a98a8]%s%s[/color]
" % [", ".join(names), " …" if int(e.ist) > 6 else ""]
	return txt


static func _mayor_lage(M: Mayor, ind: Dictionary) -> String:
	var w: Dictionary = ind.wohnen
	var a: Dictionary = ind.arbeit
	var h: Dictionary = ind.haushalt
	var txt := "Einwohner %d (%+d) · Wohnungen %d, Leerstand %.1f %% · wohnungssuchende Haushalte %d · Mietindex %.0f\n" % [int(ind.bevoelkerung.einwohner),
		int(ind.bevoelkerung.veraenderung_letzter_monat), int(w.bestand_einheiten), float(w.leerstand) * 100.0, int(w.wohnungssuchende_haushalte), float(w.mietindex)]
	txt += "Beschäftigung %.1f %% · arbeitslos %d · offene Stellen %d\n" % [float(a.quote) * 100.0, int(a.arbeitslos), int(a.offene_stellen)]
	txt += "Stadtkasse %s · reserviert %s · verfügbar %s%s\n" % [Catalog.money(float(h.kasse)), Catalog.money(float(h.reserviert)), Catalog.money(float(h.verfuegbar)), " · DEFIZIT" if h.defizit else ""]
	txt += "\n[b]Entwicklungspläne[/b]\n"
	for p in M.plans.values():
		txt += "  %s %s · %s · %d Grundstücke · %s\n    %s\n" % [p.id, esc(str(p.name)), p.status, p.parcels.size(), Parcels.ZONES[p.zone].label, esc(str(p.vote).left(220))]
	txt += "\n[b]Öffentliche Projekte[/b]\n"
	for p in M.projects.values():
		txt += "  %s %s · %s · %s · Priorität %d\n" % [p.id, p.kind, p.status, Catalog.money(float(p.cost)), int(p.get("priority", 0))]
	txt += "\n[b]Bauanträge zur Entscheidung[/b]: %d\n" % ind.bauantraege.zur_entscheidung.size()
	return txt


static func mayor(sim: Simulation, agent: MayorAgent = null) -> String:
	var M: Mayor = sim.mayor
	var ind: Dictionary = M.indicators()
	var txt := "[b][color=#f2c14e]BÜRGERMEISTER[/color][/b]\n"
	txt += "%s (%s) · Zustimmung %.0f %% · im Amt seit Tag %d\n" % [esc(M.name), Council.LABELS.get(M.party, M.party), M.approval, M.term_start_day]
	if agent != null:
		txt += "Steuerung: %s · Status: %s · Anfragen %d (ok %d, Fehler %d) · Aktionen ok %d, abgelehnt %d\n" % [
			("Modell " + str(agent.config.get("model", "?"))) if agent.uses_model() else "regelbasiert", agent.status, int(agent.stats.requests), int(agent.stats.ok),
			int(agent.stats.errors), int(agent.stats.actions_ok), int(agent.stats.actions_rejected)]
	var w: Dictionary = ind.wohnen
	var a: Dictionary = ind.arbeit
	var h: Dictionary = ind.haushalt
	txt += "\n[b]Lage[/b]\n  Einwohner %d (%+d) · Wohnungen %d, Leerstand %.1f %% · wohnungssuchende Haushalte %d · Mietindex %.0f\n" % [int(ind.bevoelkerung.einwohner),
		int(ind.bevoelkerung.veraenderung_letzter_monat), int(w.bestand_einheiten), float(w.leerstand) * 100.0, int(w.wohnungssuchende_haushalte), float(w.mietindex)]
	txt += "  Beschäftigung %.1f %% · arbeitslos %d · offene Stellen %d\n" % [float(a.quote) * 100.0, int(a.arbeitslos), int(a.offene_stellen)]
	txt += "  Stadtkasse %s · reserviert %s · verfügbar %s%s\n" % [Catalog.money(float(h.kasse)), Catalog.money(float(h.reserviert)), Catalog.money(float(h.verfuegbar)), " · DEFIZIT" if h.defizit else ""]
	txt += "\n[b]Entwicklungspläne[/b]\n"
	for p in M.plans.values():
		txt += "  %s %s · %s · %d Grundstücke · %s\n    %s\n" % [p.id, esc(str(p.name)), p.status, p.parcels.size(), Parcels.ZONES[p.zone].label, esc(str(p.vote).left(220))]
	txt += "\n[b]Öffentliche Projekte[/b]\n"
	for p in M.projects.values():
		txt += "  %s %s · %s · %s · Priorität %d\n" % [p.id, p.kind, p.status, Catalog.money(float(p.cost)), int(p.get("priority", 0))]
	txt += "\n[b]Antragswarteschlange bei der Bürgermeisterebene[/b]: %d\n" % ind.bauantraege.zur_entscheidung.size()
	txt += "\n[b]Letzte Entscheidungen[/b]\n"
	for d in M.decisions.slice(-8):
		txt += "  Tag %d · %s · %s\n    Begründung: %s\n    Ergebnis: %s\n" % [int(d.day), d.action, "ausgeführt" if d.ok else "abgelehnt von der Engine", esc(str(d.reason)), esc(str(d.msg).left(200))]
	txt += "\n[b]Wahlen[/b]\n"
	for e in M.elections:
		txt += "  Tag %d: %s (Zustimmung %.0f %%)%s\n" % [int(e.day), e.ergebnis, float(e.zustimmung), (", Nachfolger " + esc(str(e.nachfolger))) if e.has("nachfolger") else ""]
	return txt
