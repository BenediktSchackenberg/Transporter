class_name PowerGrid
extends RefCounted
## Kommunale Grundversorgung mit Strom (Auftrag 14, Etappe 1; docs/ENTREPRENEURS.md Abschnitt 8). Stadtwerke = Stadtkasse P0.
## Begrenzte Leistung: Grundlast der Bevoelkerung (pauschal, in den Haushaltsausgaben enthalten, nicht einzeln abgerechnet) plus
## angeschlossene Betriebe. Reicht die Leistung nicht, werden Betriebe in Reihenfolge ihres Anschlusses versorgt; die uebrigen sind
## mit konkretem Grund blockiert. Abrechnung je Spieltag nach Verbrauch (kW x Stunden) an die Stadtwerke; die Stadt zahlt die
## Erzeugungskosten. Betriebe ohne Stromanschluss des Grundstuecks sind blockiert. Ausbau ueber den Buergermeister (expand_power).
## Etappe 4 ersetzt die pauschale Erzeugung durch das Kraftwerk mit Brennstoff, Wartung und Netz.
## Auftrag 22 Phase 3 Schritt 1 (docs/INFRASTRUCTURE.md): Das Kernkraftwerk gehoert allen Staedten zu gleichen, festen Anteilen
## (Kraftwerksgesellschaft E0, traegt Personal, Brennstoff, Wartung, Notstrom, Entsorgung). Verbrauch wird je Stadt getrennt
## erfasst (Grundlast nach Einwohnern, Betriebe nach Standort); jede Stadt kauft ihren Verbrauch zum Erzeugungspreis bei E0, die
## Betriebe zahlen ihren Tarif an die Stadtwerke ihrer Stadt. Am Monatsende wird das Ergebnis von E0 nach den Anteilen
## ausgeschuettet bzw. von den Staedten ausgeglichen (E0 steht danach auf 0).

const CONFIG_PATH := "res://config/energy.json"
const DEFAULTS := {"leistung_kw": 1600.0, "grundlast_kw_je_einwohner": 1.2, "tarif_eur_kwh": 0.32, "erzeugung_eur_kwh": 0.17}
const EXPAND_KW := 500.0
const EXPAND_COST := 60000.0
const EXPAND_DAYS := 10

var sim
var capacity := 0.0
var tariff := 0.32
var expansions: Array = []       # {kw, fertig_tag, kosten}
var supplied := {}               # Betriebs-ID -> true (diesen Tag versorgt)
var stats := {"kwh": 0.0, "erloes": 0.0, "erzeugung": 0.0, "engpass_tage": 0}
var last := {"grundlast": 0.0, "betriebe": 0.0, "bedarf": 0.0, "versorgt": 0.0, "abgeschaltet": 0}
var net := PowerNet.new()        # Hochspannungsnetz Kraftwerk -> Umspannwerke (Auftrag 22 Phase 3 Schritt 2)
var by_town := {}                # Stadt (str) -> {kwh, bezug, tarif, ausschuettung} seit Spielbeginn (Auftrag 22 Phase 3)
var last_settle := {}            # letzter Monatsausgleich {ergebnis, anteile: {Stadt: Betrag}}


static func cfg() -> Dictionary:
	var d := DEFAULTS.duplicate()
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			for k in parsed:
				if not str(k).begins_with("_"):
					d[k] = parsed[k]
	return d


func setup(simulation) -> void:
	sim = simulation
	var c := cfg()
	capacity = float(c.leistung_kw)
	tariff = float(c.tarif_eur_kwh)
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(func(_m): settle())
	net.setup(sim)


## Feste, gleiche Anteile aller Staedte am Kraftwerk (Regionalrat: unveraenderlich).
func shares() -> Dictionary:
	var out := {}
	var n: int = maxi(1, sim.towns.count())
	for k in n:
		out[str(k)] = 1.0 / float(n)
	return out


func base_load_of(k: int) -> float:
	return float(sim.citizens.population_of(k)) * float(cfg().grundlast_kw_je_einwohner)


func town_of_biz(b: Dictionary) -> int:
	return sim.city.town_of_building(int(b.site))


func _town(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"kwh": 0.0, "bezug": 0.0, "tarif": 0.0, "ausschuettung": 0.0}
	return by_town[key]


func base_load() -> float:
	return float(sim.citizens.population()) * float(cfg().grundlast_kw_je_einwohner)


## Stromanschluss des Betriebsgrundstuecks (Erschliessung der Parzelle des Standortgebaeudes; ohne Parzelle: Bestand gilt als angeschlossen).
func connected(b: Dictionary) -> bool:
	var p: Dictionary = sim.parcels.of_building(int(b.site))
	if p.is_empty():
		return true
	return bool(p.get("erschliessung", {}).get("strom", true))


## Tageslauf: Ausbau fertigstellen, Versorgung zuteilen, Verbrauch des abgelaufenen Tages abrechnen.
func on_day(day: int) -> void:
	for e in expansions.duplicate():
		if day >= int(e.fertig_tag):
			capacity += float(e.kw)
			expansions.erase(e)
			sim.log_event("Stadtwerke: Netzausbau fertig, Leistung jetzt %d kW." % int(capacity), "good")
	net.ensure()
	net.on_day(day)   # Leitungsschaeden und Netztrupps (Auftrag 22 Phase 3 Schritt 3)
	_bill()
	_allocate()


func _allocate() -> void:
	var base := base_load()
	var plant_kw: float = sim.plant.available_kw(capacity)
	var iv_kw: float = sim.waste.iv_available_kw() if sim.waste != null else 0.0   # Mue llverbrennung (Auftrag 22 Phase 2 Schritt 4)
	net.ensure()
	var consumers: Array = sim.biz.items.values().filter(func(b): return b.status in Businesses.RUNNING and float(b.energy_kw) > 0.0 and not sim.biz.frozen(int(b.owner)))
	consumers.sort_custom(func(a, b): return float(a.founded) < float(b.founded) or (float(a.founded) == float(b.founded) and str(a.id) < str(b.id)))
	var demand := 0.0
	var given := 0.0
	var off := 0
	# Zwei Toepfe: Kraftwerk (+ Muellverbrennung) nur fuer Staedte, deren Umspannwerk ueber intakte Trassen angeschlossen ist;
	# der Notstrom von aussen deckt begrenzt die Luecke aller Staedte (abgehaengte Staedte haben nur ihn).
	var towns := {}
	var base_on := 0.0
	var base_off := 0.0
	for k in maxi(1, sim.towns.count()):
		var on := net.connected(k)
		towns[str(k)] = {"grundlast": snappedf(base_load_of(k), 0.1), "betriebe": 0.0, "versorgt": 0.0, "abgeschaltet": 0, "netz": on}
		if on:
			base_on += base_load_of(k)
		else:
			base_off += base_load_of(k)
	var free_plant := plant_kw + iv_kw - base_on
	var free_em := PowerPlant.EMERGENCY_KW - base_off
	if free_plant < 0.0:   # Grundlast der angeschlossenen Staedte uebersteigt das Kraftwerk: Notstrom springt ein
		free_em += free_plant
		free_plant = 0.0
	supplied.clear()
	for b in consumers:
		var kw := float(b.energy_kw)
		demand += kw
		var tk: Dictionary = towns.get(str(town_of_biz(b)), towns["0"])
		tk.betriebe = float(tk.betriebe) + kw
		if not connected(b):
			sim.biz.block(b.id, "strom", "Kein Stromanschluss: Grundstück nicht erschlossen")
			continue
		if sim.company(int(b.owner)).ledger.cash < kw * GameCalendar.day_game_min / 60.0 * tariff:
			sim.biz.block(b.id, "strom", "Kein Strom: Stromrechnung kann nicht bezahlt werden (Kasse leer)")
			continue
		var on := bool(tk.netz)
		var avail := (free_plant if on else 0.0) + free_em   # abgehaengte Stadt: nur Notstrom
		if kw > avail + 1e-6:
			off += 1
			tk.abgeschaltet = int(tk.abgeschaltet) + 1
			var why := "Netz ausgelastet (Bedarf %.0f kW, frei %.0f kW)" % [kw, maxf(0.0, avail)]
			if not on:
				why = "Hochspannungstrasse unterbrochen, Notstrom erschöpft (Bedarf %.0f kW, frei %.0f kW)" % [kw, maxf(0.0, avail)]
			sim.biz.block(b.id, "strom", "Kein Strom: " + why)
			continue
		var from_plant := minf(kw, free_plant) if on else 0.0   # erst Kraftwerk, Rest Notstrom
		free_plant -= from_plant
		free_em -= kw - from_plant
		given += kw
		tk.versorgt = float(tk.versorgt) + kw
		supplied[b.id] = true
		sim.biz.unblock(b.id, "strom")
	if off > 0:
		stats.engpass_tage += 1
	var emergency := clampf(PowerPlant.EMERGENCY_KW - free_em, 0.0, PowerPlant.EMERGENCY_KW)
	var unserved := maxf(0.0, -free_em)   # Grundlast ohne Strom (abgehaengte Staedte ueber dem Notstrom)
	last = {"grundlast": snappedf(base, 1.0), "betriebe": snappedf(demand, 0.1), "bedarf": snappedf(base + demand, 1.0), "versorgt": snappedf(given, 0.1), "abgeschaltet": off,
		"kraftwerk_kw": snappedf(plant_kw, 1.0), "notstrom_kw": snappedf(emergency, 1.0), "staedte": towns,
		"unversorgt_kw": snappedf(unserved, 1.0)}


## Verbrauch der versorgten Betriebe fuer einen Spieltag (Stunden des Logistiktakts) an die Stadtwerke; Erzeugungskosten zahlt die Stadt.
func _bill() -> void:
	var hours := GameCalendar.day_game_min / 60.0
	# Erzeugung des abgelaufenen Tages: Kraftwerk (Brennstoff) und Notstrom von aussen; ersetzt die fruehere Pauschale je kWh
	var total_kwh := (float(last.get("grundlast", 0.0)) + float(last.get("versorgt", 0.0))) * hours
	var emerg_kwh := float(last.get("notstrom_kw", 0.0)) * hours
	sim.plant.generate(maxf(0.0, total_kwh - emerg_kwh), emerg_kwh)
	# Bezug je Stadt (Grundlast + versorgte Betriebe) zum Erzeugungspreis an die gemeinsame Kraftwerksgesellschaft
	var price := float(cfg().erzeugung_eur_kwh)
	var tl: Dictionary = last.get("staedte", {})
	for key in tl:
		var kwh_k := (float(tl[key].grundlast) + float(tl[key].versorgt)) * hours
		if kwh_k <= 0.0:
			continue
		sim.economy.transfer(Towns.account_of(int(key)), PowerPlant.ACCT, kwh_k * price)
		var st := _town(int(key))
		st.kwh = float(st.kwh) + kwh_k
		st.bezug = float(st.bezug) + kwh_k * price
	for id in supplied:
		var b: Dictionary = sim.biz.get_b(id)
		if b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		var kwh := float(b.energy_kw) * hours
		var cost := minf(kwh * tariff, maxf(0.0, sim.company(int(b.owner)).ledger.cash))   # nie ins Minus; Versorgung endet dann (siehe _allocate)
		var k := town_of_biz(b)
		sim.company(int(b.owner)).ledger.book("energy", -cost, true, "Strom %s (%.0f kWh)" % [b.name, kwh], sim.game_min, Towns.account_of(k), id)
		_town(k).tarif = float(_town(k).tarif) + cost
		stats.kwh += kwh
		stats.erloes += cost


## Ausbau durch den Buergermeister: staedtisches Bauprojekt (Ausschreibung an Baufirmen, auch Unternehmer-Baufirmen); die Leistung
## steigt erst mit der Fertigstellung, bezahlt wird die ausfuehrende Baufirma.
func expand(by: String, M: Mayor = null) -> Dictionary:
	if M == null:
		M = sim.mayor
	if M.available_budget() < EXPAND_COST:
		return {"ok": false, "msg": "Verfügbare Stadtkasse reicht nicht (%s nötig)." % Catalog.money(EXPAND_COST)}
	if expansion_running():
		return {"ok": false, "msg": "Ein Netzausbau läuft bereits."}
	var prj: Dictionary = M.add_power_project(EXPAND_COST, EXPAND_KW, by)
	sim.log_event("%s lässt Kraftwerk und Netz ausbauen: +%d kW, ausgeschrieben als %s (%s)." % [by, int(EXPAND_KW), prj.id, Catalog.money(EXPAND_COST)], "info")
	return {"ok": true, "msg": "Netzausbau +%d kW als Projekt %s ausgeschrieben (Bauzeit etwa %d Tage)." % [int(EXPAND_KW), prj.id, EXPAND_DAYS], "ref": prj.id}


## Monatsausgleich der Kraftwerksgesellschaft: Ueberschuss nach festen Anteilen an die Stadtkassen, Fehlbetrag von ihnen.
func settle() -> void:
	var bal := float(sim.economy.accounts.get(PowerPlant.ACCT, 0.0))
	if is_zero_approx(bal):
		return
	var parts := {}
	var txt: Array = []
	for key in shares():
		var amt := bal * float(shares()[key])
		var acct := Towns.account_of(int(key))
		if amt >= 0.0:
			sim.economy.transfer(PowerPlant.ACCT, acct, amt)
		else:
			sim.economy.transfer(acct, PowerPlant.ACCT, -amt)
		_town(int(key)).ausschuettung = float(_town(int(key)).ausschuettung) + amt
		parts[key] = snappedf(amt, 0.01)
		txt.append("%s %s" % [sim.towns.name_of(int(key)), Catalog.money(amt)])
	last_settle = {"ergebnis": snappedf(bal, 0.01), "anteile": parts, "tag": GameCalendar.day_of(sim.game_min)}
	if sim.towns.count() > 1:
		sim.log_event("Kraftwerksgesellschaft: Monatsergebnis %s, %s nach festen Anteilen (%s)." % [Catalog.money(bal),
			"ausgeschüttet" if bal >= 0.0 else "von den Städten ausgeglichen", ", ".join(txt)], "info")


func expansion_running() -> bool:
	return sim.towns.mayors.any(func(M): return M.projects.values().any(func(p): return p.kind == "netzausbau" and p.status != "fertig"))


## Vom Bausystem bei Fertigstellung des Projekts aufgerufen.
func finish_expansion(kw: float) -> void:
	capacity += kw
	sim.log_event("Stadtwerke: Netzausbau fertig, Leistung jetzt %d kW." % int(capacity), "good")


func summary() -> Dictionary:
	return {"leistung_kw": snappedf(capacity, 1.0), "grundlast_kw": last.grundlast, "betriebe_kw": last.betriebe, "bedarf_kw": last.bedarf,
		"auslastung": snappedf(float(last.bedarf) / maxf(1.0, capacity), 0.01), "abgeschaltete_betriebe": int(last.abgeschaltet),
		"tarif_eur_kwh": tariff, "ausbau_laeuft": expansion_running(), "engpass_tage": int(stats.engpass_tage), "kraftwerk": sim.plant.summary(), "notstrom_kw": float(last.get("notstrom_kw", 0.0)),
		"ausbau": {"kw": EXPAND_KW, "kosten": EXPAND_COST, "tage": EXPAND_DAYS}, "staedte": last.get("staedte", {}),
		"anteile": shares(), "letzter_ausgleich": last_settle, "netz": net.summary(), "gesellschaft_saldo": snappedf(float(sim.economy.accounts.get(PowerPlant.ACCT, 0.0)), 1.0)}


func to_dict() -> Dictionary:
	return {"capacity": capacity, "tariff": tariff, "expansions": expansions, "supplied": supplied, "stats": stats, "last": last, "by_town": by_town, "last_settle": last_settle, "net": net.to_dict()}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	capacity = float(d.get("capacity", capacity))
	tariff = float(d.get("tariff", tariff))
	expansions = d.get("expansions", [])
	supplied = d.get("supplied", {})
	stats = d.get("stats", stats)
	last = d.get("last", last)
	by_town = d.get("by_town", {})
	last_settle = d.get("last_settle", {})
	net.from_dict(d.get("net", {}))
