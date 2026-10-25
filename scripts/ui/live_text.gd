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
	return txt + district_block(sim) + fuel_block(sim)


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
