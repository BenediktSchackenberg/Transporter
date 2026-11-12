class_name PowerGrid
extends RefCounted
## Kommunale Grundversorgung mit Strom (Auftrag 14, Etappe 1; docs/ENTREPRENEURS.md Abschnitt 8). Stadtwerke = Stadtkasse P0.
## Begrenzte Leistung: Grundlast der Bevoelkerung (pauschal, in den Haushaltsausgaben enthalten, nicht einzeln abgerechnet) plus
## angeschlossene Betriebe. Reicht die Leistung nicht, werden Betriebe in Reihenfolge ihres Anschlusses versorgt; die uebrigen sind
## mit konkretem Grund blockiert. Abrechnung je Spieltag nach Verbrauch (kW x Stunden) an die Stadtwerke; die Stadt zahlt die
## Erzeugungskosten. Betriebe ohne Stromanschluss des Grundstuecks sind blockiert. Ausbau ueber den Buergermeister (expand_power).
## Etappe 4 ersetzt die pauschale Erzeugung durch das Kraftwerk mit Brennstoff, Wartung und Netz.

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
	_bill()
	_allocate()


func _allocate() -> void:
	var base := base_load()
	var plant_kw: float = sim.plant.available_kw(capacity)
	var iv_kw: float = sim.waste.iv_available_kw() if sim.waste != null else 0.0   # Mue llverbrennung (Auftrag 22 Phase 2 Schritt 4)
	var free := plant_kw + iv_kw + PowerPlant.EMERGENCY_KW - base   # Notstrom von aussen deckt begrenzt die Luecke
	var consumers: Array = sim.biz.items.values().filter(func(b): return b.status in Businesses.RUNNING and float(b.energy_kw) > 0.0 and not sim.biz.frozen(int(b.owner)))
	consumers.sort_custom(func(a, b): return float(a.founded) < float(b.founded) or (float(a.founded) == float(b.founded) and str(a.id) < str(b.id)))
	var demand := 0.0
	var given := 0.0
	var off := 0
	supplied.clear()
	for b in consumers:
		var kw := float(b.energy_kw)
		demand += kw
		if not connected(b):
			sim.biz.block(b.id, "strom", "Kein Stromanschluss: Grundstück nicht erschlossen")
			continue
		if sim.company(int(b.owner)).ledger.cash < kw * GameCalendar.day_game_min / 60.0 * tariff:
			sim.biz.block(b.id, "strom", "Kein Strom: Stromrechnung kann nicht bezahlt werden (Kasse leer)")
			continue
		if kw <= free + 1e-6:
			free -= kw
			given += kw
			supplied[b.id] = true
			sim.biz.unblock(b.id, "strom")
		else:
			off += 1
			sim.biz.block(b.id, "strom", "Kein Strom: Netz ausgelastet (Bedarf %.0f kW, frei %.0f kW)" % [kw, maxf(0.0, free)])
	if off > 0:
		stats.engpass_tage += 1
	var emergency := clampf(base + given - plant_kw, 0.0, PowerPlant.EMERGENCY_KW)
	last = {"grundlast": snappedf(base, 1.0), "betriebe": snappedf(demand, 0.1), "bedarf": snappedf(base + demand, 1.0), "versorgt": snappedf(given, 0.1), "abgeschaltet": off,
		"kraftwerk_kw": snappedf(plant_kw, 1.0), "notstrom_kw": snappedf(emergency, 1.0)}


## Verbrauch der versorgten Betriebe fuer einen Spieltag (Stunden des Logistiktakts) an die Stadtwerke; Erzeugungskosten zahlt die Stadt.
func _bill() -> void:
	var hours := GameCalendar.day_game_min / 60.0
	# Erzeugung des abgelaufenen Tages: Kraftwerk (Brennstoff) und Notstrom von aussen; ersetzt die fruehere Pauschale je kWh
	var total_kwh := (float(last.get("grundlast", 0.0)) + float(last.get("versorgt", 0.0))) * hours
	var emerg_kwh := float(last.get("notstrom_kw", 0.0)) * hours
	sim.plant.generate(maxf(0.0, total_kwh - emerg_kwh), emerg_kwh)
	for id in supplied:
		var b: Dictionary = sim.biz.get_b(id)
		if b.is_empty() or b.status not in Businesses.RUNNING or sim.biz.frozen(int(b.owner)):
			continue
		var kwh := float(b.energy_kw) * hours
		var cost := minf(kwh * tariff, maxf(0.0, sim.company(int(b.owner)).ledger.cash))   # nie ins Minus; Versorgung endet dann (siehe _allocate)
		sim.company(int(b.owner)).ledger.book("energy", -cost, true, "Strom %s (%.0f kWh)" % [b.name, kwh], sim.game_min, "", id)
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
		"ausbau": {"kw": EXPAND_KW, "kosten": EXPAND_COST, "tage": EXPAND_DAYS}}


func to_dict() -> Dictionary:
	return {"capacity": capacity, "tariff": tariff, "expansions": expansions, "supplied": supplied, "stats": stats, "last": last}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	capacity = float(d.get("capacity", capacity))
	tariff = float(d.get("tariff", tariff))
	expansions = d.get("expansions", [])
	supplied = d.get("supplied", {})
	stats = d.get("stats", stats)
	last = d.get("last", last)
