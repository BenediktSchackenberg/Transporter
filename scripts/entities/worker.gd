class_name Worker
extends Mover
## Arbeiter oder Vorarbeiter: sichtbare Figur mit eigenem Zustand, Standort und hoechstens einer Aufgabe.
## Ein Fahrer sitzt im Fahrzeug (vehicle_id) und bewegt sich mit ihm; er kann nichts anderes gleichzeitig tun.

const SKILLS := ["fahren", "verladen", "reparieren", "bewachen"]

var id: String
var name: String
var role := "worker"              # worker | foreman
var employer := -1                # -1 = verfuegbar
var skills := {"fahren": 0, "verladen": 0, "reparieren": 0, "bewachen": 0}
var wage := 14.0                  # EUR pro Spielstunde
var hire_fee := 400.0
var experience := 0.0             # 0..100, steigt mit erledigten Aufgaben
var reliability := 0.8            # 0..1: Chance, eine Aufgabe ohne Stoerung zu erledigen
var loyalty := 50.0               # 0..100: Schutz gegen Abwerbung
var fatigue := 0.0                # 0..100: ab 90 erschoepft (keine neuen Aufgaben)
var task_id := ""
var vehicle_id := -1              # Fahrzeug, das er faehrt
var foreman := ""                 # betreuender Vorarbeiter
var home := Vector2i.ZERO         # Aufenthaltsort, solange verfuegbar
var lost := false                 # bei Sabotage erwischt: fuer die Partie verloren
var leaving := false              # abgeworben, wechselt nach der aktuellen Fahrt
var transfer_to := -1             # neuer Arbeitgeber nach dem Wechsel
var idle_timer := 0.0
var rest_until := 0.0             # Pause (Fahrerengpass): bis dahin keine neuen Aufgaben
var household := ""               # Haushalt (siehe Households)
var motivation := 60.0            # 0..100, haengt an Lohn, Haushaltslage, Erschoepfung und verlaesslicher Bezahlung
var health := 100.0
# Vorarbeiter
var supervised: Array = []        # Arbeiter-IDs
var station := Vector2i(-1, -1)   # Standort (Mittelpunkt des Zustaendigkeitsbereichs)
## Befugnisse (vom Unternehmer gesetzt). budget: frei verfuegbares Geld fuer Routine (Teile, Abschleppen).
## Investitionen, neue Strategie und Sabotage brauchen immer die Freigabe des Unternehmers.
var orders := {"ziel": "", "prioritaet": "fristgerecht", "auto_driver": true, "auto_repair": true, "reassign_blocked": true,
	"darf_teile_kaufen": false, "repair_budget": 2000.0}
var spent := 0.0                  # vom Vorarbeiter ausgegebenes Geld
var report_due := 0.0
var report_notes: Array = []      # gesammelte Beobachtungen fuer den naechsten Bericht


func _init() -> void:
	lane = 0.0
	speed = 1.8


func org_level() -> int:
	return int(skills.get("organisation", 0))


## Wie viele Arbeiter ein Vorarbeiter betreuen kann und wie weit sein Bereich reicht (Tiles).
func capacity() -> int:
	return 3 + 2 * org_level()


func control_radius() -> float:
	return 14.0 + 4.0 * org_level()


func status_text(sim) -> String:
	if lost:
		return "verloren"
	if employer < 0:
		return "verfügbar"
	if vehicle_id >= 0:
		return "fährt" if sim.vehicles.has(vehicle_id) and sim.vehicles[vehicle_id].state not in ["idle", "broken", "repairing"] else "im Fahrzeug"
	if task_id != "":
		var t = sim.personnel.tasks.get(task_id)
		if t and not t.is_final():
			if t.kind == "gehen":
				return "bereit (unterwegs)"   # reiner Weg ist unterbrechbar
			return "unterwegs" if t.status == "unterwegs" else "arbeitet"
	if fatigue >= 90.0:
		return "erschöpft"
	return "bereit"


func skill_text() -> String:
	var parts: Array = []
	for k in skills:
		if int(skills[k]) > 0:
			parts.append("%s %d" % [k, skills[k]])
	return ", ".join(parts)


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "role": role, "employer": employer, "skills": skills, "wage": wage,
		"hire_fee": hire_fee, "experience": experience, "reliability": reliability, "loyalty": loyalty,
		"fatigue": fatigue, "task_id": task_id, "vehicle_id": vehicle_id, "foreman": foreman,
		"home": [home.x, home.y], "lost": lost, "leaving": leaving, "transfer_to": transfer_to, "supervised": supervised,
		"station": [station.x, station.y], "orders": orders, "report_due": report_due, "spent": spent, "x": pos.x, "y": pos.y,
		"household": household, "motivation": motivation, "health": health}


static func from_dict(d: Dictionary) -> Worker:
	var w := Worker.new()
	for k in ["id", "name", "role", "wage", "hire_fee", "experience", "reliability", "loyalty", "fatigue",
			"task_id", "foreman", "lost", "leaving", "supervised", "orders", "report_due"]:
		w.set(k, d[k])
	w.employer = int(d.employer)
	w.vehicle_id = int(d.vehicle_id)
	w.transfer_to = int(d.get("transfer_to", -1))
	w.spent = float(d.get("spent", 0.0))
	w.household = str(d.get("household", ""))
	w.motivation = float(d.get("motivation", 60.0))
	w.health = float(d.get("health", 100.0))
	for k in d.skills:
		w.skills[k] = int(d.skills[k])
	w.home = Vector2i(int(d.home[0]), int(d.home[1]))
	w.station = Vector2i(int(d.station[0]), int(d.station[1]))
	w.pos = Vector2(d.x, d.y)
	return w
