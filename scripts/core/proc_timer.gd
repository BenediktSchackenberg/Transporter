class_name ProcTimer
extends RefCounted
## Ruckler-Suche: summiert die Rechenzeit je Knotenart (_process), ausgegeben in den perf-Eintraegen der Partie.

static var acc := {}


static func add(what: String, t0: int) -> void:
	acc[what] = float(acc.get(what, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0


## Summen seit dem letzten Aufruf je Bild (ms) und zuruecksetzen.
static func report(frames: int) -> Dictionary:
	var out := {}
	for k in acc:
		out[k] = snappedf(float(acc[k]) / maxf(1.0, float(frames)), 0.01)
	acc.clear()
	return out
