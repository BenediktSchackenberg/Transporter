class_name ActivityFeed
extends RefCounted
## Was die KI gerade tut, mit Ort auf der Karte: Unternehmer (Modell, Disposition, Regeln), Disponent, Buergermeister, Stadt.
## Jede ausgefuehrte oder vorgemerkte Entscheidung wird mit Begruendung und Zielort erfasst (Auftrag -> Abholort, Bau -> Grundstueck,
## Sabotage -> Zielfahrzeug, Kauf -> Haendler, Buergermeister -> Grundstuecke/Rathaus). Die Kartenebene (ActivityLayer) zeigt die
## Eintraege eine Weile als Markierung mit Linie vom Unternehmer zum Ziel; der HUD-Ticker springt per Klick hin.
## Reine Anzeige: veraendert keinen Spielzustand.

const KEEP_MIN := 240.0          # so lange (Spielminuten) bleibt eine Markierung sichtbar
const MAX := 120
const KINDS := {
	"auftrag": {"label": "Auftrag", "icon": "i_crate"},
	"bau": {"label": "Bau", "icon": "i_wrench"},
	"sabotage": {"label": "Sabotage", "icon": "i_bolt"},
	"angriff": {"label": "Angriff", "icon": "i_bolt"},
	"kauf": {"label": "Kauf", "icon": "i_star"},
	"personal": {"label": "Personal", "icon": "i_handshake"},
	"reparatur": {"label": "Reparatur", "icon": "i_wrench"},
	"kundschaft": {"label": "Kundschaft", "icon": "i_eye"},
	"stadt": {"label": "Stadt", "icon": "i_shield"},
	"verbrechen": {"label": "Verbrechen", "icon": "i_bolt"},
	"polizei": {"label": "Polizei", "icon": "i_shield"},
	"gesundheit": {"label": "Gesundheit", "icon": "i_star"},
	"infra": {"label": "Versorgung", "icon": "i_bolt"},   # Auftrag 22 Phase 8: Rohrbruch, Bahnstoerung
	"sonstiges": {"label": "Aktion", "icon": "i_chat"},
}
const ACTION_KIND := {
	"accept_contract": "auftrag", "assign_transport": "auftrag", "assign_vehicle": "auftrag", "plan_tour": "auftrag", "request_transport_help": "auftrag",
	"place_building": "bau", "upgrade_building": "bau", "build_office": "bau", "upgrade_office": "bau", "expand_plot": "bau", "rent_depot": "bau",
	"attempt_vehicle_sabotage": "sabotage", "attempt_sabotage": "angriff", "report_rival": "angriff", "block_road": "angriff", "poach_worker": "angriff", "poach_customer": "angriff",
	"buy_vehicle": "kauf", "buy_supplies": "kauf", "recruit_worker": "personal", "recruit_foreman": "personal", "dismiss_worker": "personal",
	"repair_vehicle": "reparatur", "schedule_maintenance": "reparatur",
}
## Routineaktionen, die die Karte nur ueberladen wuerden
const SKIP := ["wait", "remember", "forget", "send_message", "set_plan", "update_plan_step", "collect_contracts", "inspect_resource", "set_strategy",
	"schedule_refueling", "assign_foreman", "request_progress_report"]

var sim
var items: Array = []
var next_id := 1


func setup(simulation) -> void:
	sim = simulation


## Neuer Eintrag. actor: "C<Firma>", "buergermeister", "disponent" oder "stadt"; cell: Kartenzelle des Ziels.
func add(actor: String, cid: int, kind: String, text: String, why: String, cell: Vector2i, origin: String = "") -> Dictionary:
	var e := {"id": next_id, "t": sim.game_min, "actor": actor, "company": cid, "kind": kind if KINDS.has(kind) else "sonstiges",
		"text": text.left(140), "why": why.left(220), "x": cell.x, "y": cell.y, "origin": origin}
	next_id += 1
	items.append(e)
	if items.size() > MAX:
		items.pop_front()
	return e


## Aus einer Entscheidung des Entscheidungsprotokolls (alle Herkuenfte). Abgelehnte Aktionen erscheinen nicht auf der Karte.
func from_decision(cid: int, origin: String, action: Dictionary, result: Dictionary, why: String) -> void:
	var name := str(action.get("action", action.get("type", "")))
	if name in SKIP or not result.get("ok", false):
		return
	var kind: String = ACTION_KIND.get(name, "sonstiges")
	var cell := locate(cid, action)
	var who: String = sim.company(cid).player_name if sim.company(cid) != null else "?"
	if origin == "Disponent":
		who = "Disponent für " + who
	var txt := "%s: %s" % [who, describe(name, action, result)]
	add("C%d" % cid, cid, kind, txt, why if why != "" else str(result.get("msg", "")).left(160), cell, origin)


## Zielort einer Aktion; Rueckfall ist die Figur des Unternehmers.
func locate(cid: int, a: Dictionary) -> Vector2i:
	var k = sim.contracts.get(str(a.get("contract_id", "")))
	if k != null:
		return sim.city.building(int(k.pickup)).walk
	var name := str(a.get("action", ""))
	if name in ["attempt_vehicle_sabotage", "repair_vehicle", "schedule_maintenance"] and a.get("vehicle_id") != null:
		var v = sim.vehicles.get(ActionExecutor._i(a.vehicle_id))
		if v != null:
			return v.tile()
	if name in ["attempt_sabotage", "report_rival", "poach_worker", "block_road"] and a.get("target") != null:
		var t = sim.company(ActionExecutor._i(a.target))
		if t != null and not t.depots.is_empty():
			return sim.city.building(int(t.depots[0])).walk
	if name == "buy_vehicle" and a.get("offer_id") != null:
		for o in sim.resources.available_offers():
			if str(o.id) == str(a.offer_id) and o.has("dealer"):
				return sim.city.building(int(o.dealer)).walk
	if name in ["place_building", "upgrade_building", "expand_plot", "build_office", "upgrade_office", "rent_depot"]:
		var c = sim.company(cid)
		if c != null and not c.depots.is_empty():
			return sim.city.building(int(c.depots[0])).walk
	if sim.avatars.size() > cid and cid >= 0:
		return sim.avatars[cid].tile()
	return Vector2i(sim.city.size / 2, sim.city.size / 2)


static func describe(name: String, a: Dictionary, result: Dictionary) -> String:
	match name:
		"accept_contract":
			return "nimmt Auftrag %s an" % str(a.get("contract_id", "?"))
		"assign_transport", "assign_vehicle":
			return "schickt #%s zu %s" % [str(a.get("vehicle_id", "?")), str(a.get("contract_id", "?"))]
		"attempt_vehicle_sabotage":
			return "SABOTAGE an Fahrzeug #%s" % str(a.get("vehicle_id", "?"))
		"attempt_sabotage":
			return "Rufschädigung gegen Firma %s" % str(a.get("target", "?"))
		"report_rival":
			return "zeigt Firma %s beim Bürgermeister an" % str(a.get("target", "?"))
		"block_road":
			return "BLOCKIERT die Straße vor Firma %s mit Paletten" % str(a.get("target", "?"))
		"poach_worker":
			return "wirbt Personal von Firma %s ab" % str(a.get("target", "?"))
		"place_building":
			return "baut %s auf dem Hof" % str(a.get("typ", "?"))
		"buy_vehicle":
			return "kauft Fahrzeug (%s)" % str(a.get("offer_id", a.get("model", "?")))
		"recruit_worker", "recruit_foreman":
			return "wirbt %s an" % str(a.get("worker_id", "?"))
		"repair_vehicle":
			return "lässt #%s reparieren" % str(a.get("vehicle_id", "?"))
		"request_transport_help":
			return "sucht einen Partner für Fracht %s" % str(a.get("contract_id", "?"))
		"quote_transport_help":
			return "bietet Transporthilfe an (%s EUR)" % str(int(float(a.get("fee", 0))))
		"execute_plan_step":
			return "führt Planschritt %s aus" % str(a.get("step_id", "?"))
		"buy_supplies":
			return "kauft Vorräte (%s)" % str(a.get("resource_id", "?"))
		"assign_worker_task":
			return "gibt Aufgabe „%s“ an %s" % [str(a.get("kind", "?")), str(a.get("worker_id", "?"))]
		"propose_cooperation":
			return "schlägt Firma %s eine Kooperation vor" % str(a.get("to", "?"))
		"offer_trade", "accept_trade", "reject_trade":
			return {"offer_trade": "bietet ein Geschäft an", "accept_trade": "nimmt ein Geschäft an", "reject_trade": "lehnt ein Geschäft ab"}[name]
		"install_internet":
			return "richtet Internet im Büro ein"
		"dismiss_worker":
			return "entlässt %s" % str(a.get("worker_id", "?"))
	var msg := str(result.get("msg", ""))
	return "%s – %s" % [name, msg.left(60)] if msg != "" else name


## Mitte eines Grundstuecks (Parcels) als Kartenzelle; Rueckfall Kartenmitte.
func parcel_cell(pid: String) -> Vector2i:
	var p: Dictionary = sim.parcels.parcel(pid)
	if p.has("rect"):
		return Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
	return Vector2i(sim.city.size / 2, sim.city.size / 2)


## Sichtbare Eintraege (juenger als KEEP_MIN), neueste zuletzt.
func active(now: float) -> Array:
	return items.filter(func(e): return now - float(e.t) <= KEEP_MIN)


func to_dict() -> Dictionary:
	return {"items": items.slice(-40), "next": next_id}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	items = d.get("items", [])
	next_id = int(d.get("next", 1))
