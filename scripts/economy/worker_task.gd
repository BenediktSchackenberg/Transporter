class_name WorkerTask
extends RefCounted
## Konkrete Anweisung an einen Arbeiter. Zustaende:
## zugewiesen -> unterwegs -> in Bearbeitung -> abgeschlossen; zusaetzlich blockiert, fehlgeschlagen, abgebrochen.
## Ohne Arbeiter (worker_id == "") wartet die Aufgabe beim Vorarbeiter auf Verteilung.

const KINDS := {
	"fahren": "Fahrzeug übernehmen (optional Auftrag ausliefern)",
	"reparieren": "Fahrzeug vor Ort reparieren (braucht Ersatzteile)",
	"bewachen": "Depot oder Fahrzeug bewachen",
	"verladen": "beim Verladen an einem Gebäude helfen (halbiert Ladezeit)",
	"auskundschaften": "gegnerisches Depot beobachten und berichten",
	"sabotage": "gegnerisches Fahrzeug vorübergehend außer Betrieb setzen",
	"unterstuetzen": "anderen Arbeiter bei Reparatur oder Verladen unterstützen",
	"gehen": "zu einem Ort gehen",
	"bauen": "auf einer eigenen Baustelle mitarbeiten (Eigenbau)",
	"schulung": "Weiterbildung im Schulungsraum (über train_worker)",
}
const FINAL := ["abgeschlossen", "fehlgeschlagen", "abgebrochen"]
## benoetigte Faehigkeit je Aufgabe (Mindeststufe 1); leer = jeder Arbeiter
const SKILL := {"fahren": "fahren", "reparieren": "reparieren", "verladen": "verladen", "bewachen": ""}

var id: String
var company: int
var worker_id := ""
var foreman_id := ""              # ueber Vorarbeiter erteilt
var kind: String
var target := {}                  # vehicle_id, contract_id, site, company, building, worker_id
var priority := 2                 # 1 = hoch, 3 = niedrig
var status := "zugewiesen"
var progress := 0.0               # 0..1
var work_needed := 0.0            # Spielminuten Arbeit
var created := 0.0
var cost := 0.0                   # bereits entstandene Kosten
var report := ""                  # letzte Rueckmeldung
var cell := Vector2i(-1, -1)      # Einsatzort


func is_final() -> bool:
	return status in FINAL


func describe() -> String:
	var t := ""
	if target.has("vehicle_id"):
		t += " Fzg #%d" % int(target.vehicle_id)
	if target.has("contract_id") and str(target.contract_id) != "":
		t += " Auftrag %s" % target.contract_id
	if target.has("site"):
		t += " Depot %d" % int(target.site)
	if target.has("company"):
		t += " Firma %d" % int(target.company)
	if target.has("building"):
		t += " Gebäude %d" % int(target.building)
	return kind + t


func to_dict() -> Dictionary:
	return {"id": id, "company": company, "worker_id": worker_id, "foreman_id": foreman_id, "kind": kind,
		"target": target, "priority": priority, "status": status, "progress": progress, "work_needed": work_needed,
		"created": created, "cost": cost, "report": report, "cell": [cell.x, cell.y]}


static func from_dict(d: Dictionary) -> WorkerTask:
	var t := WorkerTask.new()
	for k in ["id", "worker_id", "foreman_id", "kind", "target", "status", "progress", "work_needed", "created",
			"cost", "report"]:
		t.set(k, d[k])
	t.company = int(d.company)
	t.priority = int(d.priority)
	t.cell = Vector2i(int(d.cell[0]), int(d.cell[1]))
	return t
