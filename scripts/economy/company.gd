class_name Company
extends RefCounted
## Ein Transportunternehmen (ein KI-Spieler).

var id: int
var player_name: String
var company_name: String
var color: Color
var avatar_style: int
var personality: String
var ledger := Ledger.new()
var reputation := 50.0
var depots: Array = []          # Depot-Standort-IDs (erstes = Hauptdepot)
var fuel := 300.0               # Treibstoffvorrat in Litern (Startausstattung, fuer alle gleich)
var parts := 2                  # Ersatzteile auf Lager
var vehicle_ids: Array = []
var security_level := 0
var insurance := false
var disrupted_until := -1.0     # Betriebsstoerung aktiv bis Spielminute
var sabotage_ready_at := 0.0    # Abklingzeit als Saboteur
var protected_until := 0.0      # Schutzfrist als Opfer
var stats := {"completed": 0, "on_time": 0, "late": 0, "failed": 0, "sabotage_ok": 0, "sabotage_caught": 0,
	"deals": 0}
var key_events: Array = []      # wichtige Ereignisse fuer die Endauswertung
var offices: Array = []         # Gebaeude-IDs der Bueros; erstes = Zentrale
var office_level := 0           # Ausbaustufe der Zentrale (0 = kein Buero)
var internet_level := 0
var known: Dictionary = {}      # Auftrags-IDs, die die Firma kennt (Jobboerse/Internet/Stammkunden)
var property_cost := 0.0        # Anschaffungskosten Bueros (Abschreibungsbasis)
var property_book := 0.0        # Buchwert Bueros und Betriebseinrichtungen
var land_book := 0.0            # Grund und Boden (gekaufte Erweiterungsflaechen, keine Abschreibung)
var parking_slots := 2          # Stellplaetze auf eigenen Grundstuecken (vom Estate berechnet)
var plot_office_level := 0      # Ausbaustufe des Unternehmerbueros auf dem Grundstueck
var dispositions := 0
var form := "einzel"           # einzel | ug | gmbh (siehe CompanyForms)
var founded_min := 0.0
var generation := 1             # wievielter Unternehmer auf diesem Platz
var status := "aktiv"           # aktiv | warnung | verzug | insolvenz | verwertung | geschlossen
var status_since := 0.0
var status_reason := ""
var grace_until := -1.0         # Ende der Nachfrist bei Zahlungsverzug
var administrator := ""         # Insolvenzverwalter
var pending_form := ""
var pending_form_due := 0.0
var fuel_cap := 1000.0          # Tankgroesse in Litern (offenes Fasslager; Betriebstankstelle +3000)


## Stellplaetze auf eigenen Grundstuecken + 4 je gemieteter Gewerbehalle.
func fleet_limit() -> int:
	return parking_slots + Catalog.VEHICLES_PER_DEPOT * maxi(0, depots.size() - plot_count)


var plot_count := 1


## Gleichzeitig laufende Auftraege (angenommen bis unterwegs).
func contract_capacity() -> int:
	return 3 + 3 * maxi(office_level, plot_office_level) + 2 * maxi(0, offices.size() - (1 if office_level > 0 else 0)) + 2 * dispositions


func is_active() -> bool:
	return status in ["aktiv", "warnung", "verzug"]


func is_disrupted(now: float) -> bool:
	return now < disrupted_until


func add_key_event(text: String, now: float) -> void:
	key_events.append("%s: %s" % [Catalog.game_minutes_to_text(now), text])
	if key_events.size() > 12:
		key_events.pop_front()


func to_dict() -> Dictionary:
	return {"id": id, "player_name": player_name, "company_name": company_name, "color": color.to_html(),
		"avatar_style": avatar_style, "personality": personality, "ledger": ledger.to_dict(),
		"reputation": reputation, "depots": depots, "fuel": fuel, "parts": parts, "vehicle_ids": vehicle_ids,
		"security_level": security_level, "insurance": insurance, "disrupted_until": disrupted_until,
		"sabotage_ready_at": sabotage_ready_at, "protected_until": protected_until, "stats": stats,
		"key_events": key_events, "offices": offices, "office_level": office_level, "internet_level": internet_level,
		"form": form, "founded_min": founded_min, "generation": generation, "status": status, "status_since": status_since,
		"status_reason": status_reason, "grace_until": grace_until, "administrator": administrator, "pending_form": pending_form,
		"pending_form_due": pending_form_due, "known": known.keys(), "property_cost": property_cost, "property_book": property_book, "land_book": land_book}


static func from_dict(d: Dictionary) -> Company:
	var c := Company.new()
	c.id = int(d.id)
	c.player_name = d.player_name
	c.company_name = d.company_name
	c.color = Color.html(d.color)
	c.avatar_style = int(d.avatar_style)
	c.personality = d.personality
	c.ledger.from_dict(d.ledger)
	c.reputation = d.reputation
	c.depots = d.depots.map(func(x): return int(x))
	c.fuel = float(d.get("fuel", 0.0))
	c.parts = int(d.get("parts", 0))
	c.vehicle_ids = d.vehicle_ids.map(func(x): return int(x))
	c.security_level = int(d.security_level)
	c.insurance = d.insurance
	c.disrupted_until = d.disrupted_until
	c.sabotage_ready_at = d.sabotage_ready_at
	c.protected_until = d.protected_until
	c.stats = d.stats
	c.key_events = d.key_events
	c.offices = d.get("offices", []).map(func(x): return int(x))
	c.office_level = int(d.get("office_level", 0))
	c.internet_level = int(d.get("internet_level", 0))
	for k in d.get("known", []):
		c.known[str(k)] = true
	c.form = str(d.get("form", "einzel"))
	c.founded_min = float(d.get("founded_min", 0.0))
	c.generation = int(d.get("generation", 1))
	c.status = str(d.get("status", "aktiv"))
	c.status_since = float(d.get("status_since", 0.0))
	c.status_reason = str(d.get("status_reason", ""))
	c.grace_until = float(d.get("grace_until", -1.0))
	c.administrator = str(d.get("administrator", ""))
	c.pending_form = str(d.get("pending_form", ""))
	c.pending_form_due = float(d.get("pending_form_due", 0.0))
	c.property_cost = float(d.get("property_cost", 0.0))
	c.property_book = float(d.get("property_book", 0.0))
	c.land_book = float(d.get("land_book", 0.0))
	return c
