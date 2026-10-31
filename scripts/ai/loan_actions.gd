class_name LoanActions
extends RefCounted
## KI-Aktionen fuer Kredite zwischen Unternehmen (siehe PlayerLoans).

const SCHEMA := {
	"offer_loan": {"params": {"nehmer": "int", "betrag": "number", "zins": "number", "monate": "number", "fahrzeug_id": "int?"},
		"desc": "Einem anderen Unternehmen Geld leihen (zins als Jahresanteil, z. B. 0.06; Laufzeit 1–36 Monate; optional Fahrzeug des Nehmers als Pfand). Du musst das Geld besitzen; Auszahlung erst nach Annahme."},
	"counter_loan": {"params": {"kredit_id": "string", "betrag": "number?", "zins": "number?", "monate": "number?"},
		"desc": "Gegenangebot zu einem Kreditangebot (obs.spielerkredite.angebote mit du_antwortest=true); höchstens 3 Gegenangebote."},
	"accept_loan": {"params": {"kredit_id": "string"}, "desc": "Kreditangebot der Gegenseite annehmen; der Geber zahlt sofort aus."},
	"decline_loan": {"params": {"kredit_id": "string"}, "desc": "Kreditangebot ablehnen."},
}

var sim


func setup(simulation) -> void:
	sim = simulation


func run(cid: int, name: String, a: Dictionary) -> Dictionary:
	var P: PlayerLoans = sim.player_loans
	match name:
		"offer_loan":
			var coll := ActionExecutor._i(a.fahrzeug_id) if a.get("fahrzeug_id") != null else -1
			return P.offer(cid, ActionExecutor._i(a.nehmer), ActionExecutor._f(a.betrag), ActionExecutor._f(a.zins), ActionExecutor._i(a.monate), coll)
		"counter_loan":
			return P.counter(str(a.kredit_id), cid, ActionExecutor._f(a.betrag) if a.get("betrag") != null else -1.0,
				ActionExecutor._f(a.zins) if a.get("zins") != null else -1.0, ActionExecutor._i(a.monate) if a.get("monate") != null else -1)
		"accept_loan":
			return P.accept(str(a.kredit_id), cid)
		"decline_loan":
			return P.decline(str(a.kredit_id), cid)
	return {}
