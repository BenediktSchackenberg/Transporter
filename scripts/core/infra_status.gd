class_name InfraStatus
extends RefCounted
## Lagebild "Infrastruktur & Versorgung" (Auftrag 22 Phase 8): Ampel je Stadt und Bereich aus den echten Zustaenden der Systeme
## (Strom, Wasser, Abwasser, Muell, Polizei, Bahn). ok = gruen, warn = gelb, krit = rot; text nennt den Grund.

const AREAS := ["strom", "wasser", "abwasser", "muell", "polizei", "bahn"]
const LABEL := {"strom": "Strom", "wasser": "Wasser", "abwasser": "Abwasser", "muell": "Müll", "polizei": "Polizei", "bahn": "Bahn"}
const COLOR := {"ok": "#6fd08c", "warn": "#e0c040", "krit": "#ff6b5e"}


static func of_town(sim, k: int) -> Dictionary:
	var out := {}
	# Strom: Stadt vom Netz getrennt und Notstrom erschoepft -> rot
	if sim.water != null and sim.water.enabled() and not sim.water.power_ok(k):
		out["strom"] = {"ampel": "krit", "text": "Stromausfall: Pumpen, Ampeln und Signale ohne Strom"}
	elif float(sim.grid.last.get("unversorgt_kw", 0.0)) > 0.0:
		out["strom"] = {"ampel": "warn", "text": "%.0f kW in der Region unversorgt" % float(sim.grid.last.get("unversorgt_kw", 0.0))}
	else:
		out["strom"] = {"ampel": "ok", "text": "versorgt"}
	# Wasser
	var h: Dictionary = sim.water.last.get(str(k), {}) if sim.water != null else {}
	if h.is_empty():
		out["wasser"] = {"ampel": "ok", "text": "noch keine Abrechnung"}
	elif float(h.get("fehl", 0.0)) > 0.01:
		out["wasser"] = {"ampel": "krit", "text": "Wasserknappheit: %.1f m³ fehlen (%s)" % [float(h.fehl), str(h.get("grund", ""))]}
	elif bool(h.get("rohrbruch", false)):
		out["wasser"] = {"ampel": "warn", "text": "Rohrbruch, Wassertrupp unterwegs"}
	elif int(h.get("ohne_anschluss", 0)) > 0:
		out["wasser"] = {"ampel": "warn", "text": "%d Einwohner ohne Anschluss" % int(h.ohne_anschluss)}
	else:
		out["wasser"] = {"ampel": "ok", "text": "Vorrat %.0f/%.0f m³" % [float(h.get("speicher", 0.0)), float(h.get("speicher_max", 0.0))]}
	# Abwasser (gemeinsame Klaeranlage)
	var pl: Dictionary = sim.water.plant_last if sim.water != null else {}
	if sim.water == null or sim.water.plant().is_empty():
		out["abwasser"] = {"ampel": "warn", "text": "keine Kläranlage"}
	elif float(pl.get("ueberlauf", 0.0)) > 0.0:
		out["abwasser"] = {"ampel": "krit", "text": "Überlauf %.1f m³ (%s)" % [float(pl.ueberlauf), str(pl.get("grund", ""))]}
	else:
		out["abwasser"] = {"ampel": "ok", "text": "geklärt"}
	# Muell: ueberquellende Tonnen
	var over: int = sim.waste.overflowing(k).size() if sim.waste != null else 0
	out["muell"] = {"ampel": "krit" if over >= 10 else ("warn" if over > 0 else "ok"), "text": "%d Tonnen quellen über" % over if over > 0 else "Abfuhr läuft"}
	# Polizei
	if sim.police == null or not sim.police.enabled() or sim.police.station_of(k).is_empty():
		out["polizei"] = {"ampel": "warn", "text": "keine Wache"}
	else:
		var waiting: int = sim.police.missions.values().filter(func(m): return m.status == "laufend" and int(m.town) == k and str(m.phase) == "wartet").size()
		var running: int = sim.police.missions.values().filter(func(m): return m.status == "laufend" and int(m.town) == k).size()
		out["polizei"] = {"ampel": "warn" if waiting > 0 else "ok", "text": "%d Einsätze, %d warten auf einen Wagen" % [running, waiting] if running > 0 else "ruhig"}
	# Bahn: Stoerung oder Langsamfahrstelle in einem Abschnitt der Stadt
	out["bahn"] = {"ampel": "ok", "text": "kein Bahnhof"}
	if sim.trains != null and not sim.trains.stops.is_empty():
		var s: int = sim.trains.stop_of_town(k)
		if s >= 0:
			out["bahn"] = {"ampel": "ok", "text": "planmäßig"}
			for b in [s - 1, s]:
				if b < 0 or b >= sim.trains.stops.size() - 1:
					continue
				if sim.trains.disruptions.has(b):
					out["bahn"] = {"ampel": "krit", "text": "%s im Abschnitt" % str(sim.trains.disruptions[b].art)}
					break
				if sim.trains.speed_factor(b) < 1.0:
					out["bahn"] = {"ampel": "warn", "text": "Langsamfahrstelle (Gleis %d %%)" % roundi(sim.trains.condition_of(b))}
	return out


## Kompakt fuer die Buergermeister-Beobachtung: {bereich: "ok|warn|krit: Grund"}, nur Abweichungen.
static func compact(sim, k: int) -> Dictionary:
	var out := {}
	var st := of_town(sim, k)
	for a in st:
		if str(st[a].ampel) != "ok":
			out[a] = "%s: %s" % [st[a].ampel, st[a].text]
	return out
