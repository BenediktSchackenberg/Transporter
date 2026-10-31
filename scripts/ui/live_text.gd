class_name LiveText
extends RefCounted
## BBCode-Texte fuer die Zuschaueroberflaeche: was jedes KI-Unternehmen gerade tut und warum (Aktivitaeten) sowie
## Wetter, Ereignisse mit Ursachenketten und Kunden (Lage). Reine Funktionen ueber den Simulationszustand.

const SEVERITY := ["", "leicht", "mittel", "schwer"]


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
	return "überlegt am Betriebshof oder ist unterwegs"


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
	txt += "  Betreiberkonto %s · Tankwagen unterwegs: %d\n" % [Catalog.money(sim.economy.accounts.G0), sim.resources.tanker_orders.size()]
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
	for d in ct.by_district:
		txt += "  %s: %.0f
" % [d, float(ct.by_district[d])]
	var cs: Dictionary = sim.banking.consumer_summary()
	txt += "Konsumkredite: %d laufend (%s) · %d im Rückstand · %d in Pfändung (Restschuld %s) · %d vergeben
" % [int(cs.laufend), Catalog.money(float(cs.volumen)), int(cs.rueckstand), int(cs.pfaendung), Catalog.money(float(cs.restschuld_pfaendung)), int(cs.vergeben)]
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
		if r.owner == CityDepot.OWNER:
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
