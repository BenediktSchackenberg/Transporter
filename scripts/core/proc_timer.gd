class_name ProcTimer
extends RefCounted
## Ruckler-Suche: summiert die Rechenzeit je Knotenart (_process), ausgegeben in den perf-Eintraegen der Partie.

static var acc := {}

## Haenger-Melder: Der Hauptthread setzt vor jedem grossen Schritt eine Markierung; ein Waechter-Thread (main.gd) schreibt sie nach
## user://logs/haenger.txt, wenn mehr als 3 s kein Bild fertig wird. Nur Ganzzahlen, damit der Lesezugriff aus dem Thread sicher ist.
const PHASES := ["-", "main", "spielsitzung", "firmen_ki", "buergermeister_ki", "disponent_ki", "gespraeche_ki", "dienste", "ereignisfenster",
	"platzierung", "Simulation", "Simulation: Tageswechsel", "Stadtansicht", "Fahrzeuge/Figuren", "Aktivitaeten", "Betriebshof", "Oberflaeche",
	"Leistungslog", "KI: Beobachtung", "KI: Anfrage senden", "KI: Antwort verarbeiten", "KI: Aktionen ausfuehren", "KI: Hofrunde",
	"KI: Ersatzmodus", "KI: Nachkauf", "Partie wird aufgebaut (Karte, Ansicht)",
	"nach _process (Layout, _draw)", "Rendern", "nach Rendern"]
static var phase := 0
static var detail := 0
static var who := -1


static func mark(name: String, firm: int = -2) -> void:
	phase = maxi(0, PHASES.find(name))
	if firm != -2:
		who = firm


static func sub(name: String, firm: int = -2) -> void:
	detail = maxi(0, PHASES.find(name))
	if firm != -2:
		who = firm


static func text() -> String:
	return "%s / %s%s" % [PHASES[phase], PHASES[detail], (" (Firma %d)" % who) if who >= 0 else ""]


static func add(what: String, t0: int) -> void:
	acc[what] = float(acc.get(what, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0


## Summen seit dem letzten Aufruf je Bild (ms) und zuruecksetzen.
static func report(frames: int) -> Dictionary:
	var out := {}
	for k in acc:
		out[k] = snappedf(float(acc[k]) / maxf(1.0, float(frames)), 0.01)
	acc.clear()
	return out
