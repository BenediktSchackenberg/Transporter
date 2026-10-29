class_name Construction
extends RefCounted
## Bauunternehmen, Angebote, Bauvertraege, Bauphasen, Materiallieferung, Zahlungen, Uebergabe und Einzug (Auftrag 7, Etappen 4-6).
##
## Ablauf eines Bauvorhabens (`projects`): genehmigter Antrag -> Angebote mehrerer Baufirmen -> Vertrag (verbindlich, Mittel werden
## zurueckgelegt) -> Erschliessung des Grundstuecks (falls Anschluesse fehlen) -> zehn Bauphasen mit Material und Zahlungsplan ->
## Pruefung (Maengel werden behoben) -> Uebergabe (Gebaeude entsteht, Wohneinheiten, Einzug/Vermietung).
## Oeffentliche Erschliessungsprojekte des Buergermeisters (`Mayor.projects`) werden hier ausgeschrieben und von Baufirmen ausgefuehrt.
## Geld: Kunden zahlen ueber das Konto K0 (Baufirmen); Material kauft die Baufirma vom Bauhof (T0, StockBook). Bauträger-Konto D0.

const BUILDERS := {
	"BF1": {"name": "Rhein-Bau GmbH", "price": 1.00, "days": 1.00, "quality": 0.80, "reliability": 0.90, "capacity": 3},
	"BF2": {"name": "Schnell & Günstig Bau", "price": 0.88, "days": 0.90, "quality": 0.60, "reliability": 0.75, "capacity": 4},
	"BF3": {"name": "Meisterbau Mainz", "price": 1.18, "days": 1.05, "quality": 0.95, "reliability": 0.97, "capacity": 2},
}
## id, Name, Anteil an der Bauzeit, Anteil am Zahlungsplan, Anteil am Material (mit Gewichten je Artikel), wetterempfindlich
const PHASES := [
	{"id": "vorbereitung", "label": "Vorbereitung (Vermessung, Absperrung)", "days": 0.05, "pay": 0.05, "mat": 0.0, "items": {}, "wx": false},
	{"id": "erdarbeiten", "label": "Erdarbeiten", "days": 0.10, "pay": 0.08, "mat": 0.0, "items": {}, "wx": true},
	{"id": "fundament", "label": "Unterbau und Fundament", "days": 0.12, "pay": 0.12, "mat": 0.15, "items": {"beton": 3, "verbindung": 1}, "wx": true},
	{"id": "rohbau", "label": "Tragwerk und Rohbau", "days": 0.22, "pay": 0.20, "mat": 0.25, "items": {"ziegel": 3, "beton": 2, "holz": 1}, "wx": true},
	{"id": "dach", "label": "Dach", "days": 0.08, "pay": 0.08, "mat": 0.10, "items": {"holz": 2, "verbindung": 1}, "wx": true},
	{"id": "huelle", "label": "Gebäudehülle (Fenster, Türen, Fassade)", "days": 0.08, "pay": 0.10, "mat": 0.10, "items": {"glas": 2, "holz": 1}, "wx": false},
	{"id": "installation", "label": "Installation (Leitungen, Technik)", "days": 0.10, "pay": 0.10, "mat": 0.15, "items": {"installation": 3, "stahl": 1}, "wx": false},
	{"id": "innenausbau", "label": "Innenausbau", "days": 0.15, "pay": 0.13, "mat": 0.15, "items": {"holz": 2, "rohmaterial": 2}, "wx": false},
	{"id": "aussenanlagen", "label": "Außenanlagen (Wege, Zufahrt, Grün)", "days": 0.06, "pay": 0.06, "mat": 0.10, "items": {"beton": 1, "rohmaterial": 2}, "wx": true},
	{"id": "uebergabe", "label": "Prüfung und Übergabe", "days": 0.04, "pay": 0.08, "mat": 0.0, "items": {}, "wx": false},
]
## Besetzung je Phase fuer ein Haus mit einer Einheit und einem Geschoss: Bauarbeiter (inkl. Fachkraefte), Maschinenfuehrer, Geraete
const CREW := {
	"vorbereitung": {"work": 2, "ops": 0, "gear": [], "role": "Vermessung und Absperrung"},
	"erdarbeiten": {"work": 2, "ops": 1, "gear": ["bagger", "lkw"], "role": "Erdarbeiten"},
	"fundament": {"work": 3, "ops": 1, "gear": ["betonmischer"], "role": "Fundament"},
	"rohbau": {"work": 4, "ops": 1, "gear": ["kran"], "role": "Rohbau"},
	"dach": {"work": 3, "ops": 1, "gear": ["kran"], "role": "Dachdecker"},
	"huelle": {"work": 3, "ops": 0, "gear": [], "role": "Fenster- und Fassadenbau"},
	"installation": {"work": 2, "ops": 0, "gear": [], "role": "Installation"},
	"innenausbau": {"work": 3, "ops": 0, "gear": [], "role": "Innenausbau"},
	"aussenanlagen": {"work": 2, "ops": 1, "gear": ["bagger"], "role": "Außenanlagen"},
	"uebergabe": {"work": 1, "ops": 0, "gear": [], "role": "Prüfung"},
}
const GEAR_NAMES := {"bagger": "Bagger", "lkw": "Kipper", "betonmischer": "Betonmischer", "kran": "Kran"}
## Auftraege beim Einzug (Abschnitt 14): ein Transportunternehmen kann sie annehmen, sonst erledigt nach 3 Tagen eine Spedition (K0).
const MOVE_JOBS := {"umzug": {"label": "Umzug (Möbeltransport)", "fee": 320.0}, "moebel": {"label": "Möbellieferung (Küche, Betten)", "fee": 260.0}}
const CONNECTION_FEE := 90.0         # Anmeldung von Strom, Wasser und Internet bei den Stadtwerken (an P0)
const JOB_FALLBACK_DAYS := 3
const ACTIVE_STATES := ["erschliessung", "im_bau", "pruefung", "wartet_anschluss"]
const MATERIAL_SHARE := 0.30          # Anteil der Baukosten, der auf Material entfaellt
const ADVANCE := 0.0                  # keine Anzahlung: Abschlaege nur nach abgeschlossenen Phasen
const OFFER_VALID_DAYS := 10
const DELIVERY_FALLBACK_DAYS := 2     # nimmt kein Transporteur den Lieferauftrag an, liefert der Bauhof selbst
const FREIGHT_RATE := 0.04            # Frachtlohn: Anteil am Materialwert der Lieferung
const STORAGE_PHASES := 1             # Material hoechstens fuer die naechste Phase vorab liefern
const RENT_PER_UNIT_MONTH := 700.0
const DEVELOPER := "D0"
const HOME_DEF := "einfamilienhaus"
const HOME_RESERVE := 300.0           # so viel Bargeld behaelt ein bauender Haushalt
const MAX_HOME_PLANS := 3             # gleichzeitig bauende Haushalte
const HOME_DESIRE := 4                # jeder vierte Monat ein Haushalt mit Bauwunsch (je nach Haushalt)

var sim
var builders := {}                    # id -> {name, price, days, quality, reliability, capacity, status, history}
var projects := {}                    # "BP<n>" -> Bauvorhaben
var deliveries := {}                  # "L<n>" -> Lieferauftrag
var units := {}                       # "W<n>" -> Wohneinheit
var jobs := {}                        # "S<n>" -> Einzugsauftrag {kind, unit, payer, fee, status, carrier, day}
var public := {}                      # Mayor-Projekt-ID -> Ausfuehrung {builder, price, days_left, ...}
var reserved_co := {}                 # Unternehmen-ID -> fuer Bauvertraege zurueckgelegt
var reserved_dev := 0.0               # beim Bautraeger fuer Vertraege zurueckgelegt
var home_plans := {}                  # Haushalt -> {stage, parcel, app, project, credit, day}: Grundstueck -> Bank -> Antrag -> Bau
var home_notes: Array = []            # letzte Entscheidungen (Ablehnung der Bank usw.) fuer die Oberflaeche
var _next := 1
var _next_delivery := 1
var _next_unit := 1
var _next_job := 1


func setup(simulation) -> void:
	sim = simulation
	for id in BUILDERS:
		builders[id] = BUILDERS[id].duplicate()
		builders[id]["status"] = "aktiv"
		builders[id]["history"] = {"fertig": 0, "verzoegert": 0, "maengel": 0}
	sim.day_changed.connect(on_day)
	sim.month_changed.connect(on_month)


# ------------------------------------------------------------------ Angebote
## Baufirma ausgelastet? Anzahl laufender Vertraege.
func load_of(bid: String) -> int:
	var n := 0
	for p in projects.values():
		if p.get("builder", "") == bid and p.status in ["erschliessung", "im_bau", "pruefung", "wartet_anschluss"]:
			n += 1
	for e in public.values():
		if e.builder == bid and e.status == "laufend":
			n += 1
	return n


## Angebote aller handlungsfaehigen Baufirmen fuer ein Vorhaben mit Basispreis `base` und Basis-Bauzeit `days`.
func make_offers(base: float, days: int, seed_key: String, remaining: float = 1.0) -> Array:
	var offers: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key) + _today()
	for bid in builders:
		var b: Dictionary = builders[bid]
		if b.status != "aktiv":
			continue
		var load := load_of(bid)
		var wait := maxi(0, load - int(b.capacity) + 1) * 12          # ueber der Kapazitaet beginnt die Firma spaeter
		var price := snappedf(base * float(b.price) * rng.randf_range(0.95, 1.05), 10.0)
		var dur := maxi(2, int(ceil(float(days) * float(b.days) * remaining)))
		offers.append({"builder": bid, "name": b.name, "price": price, "days": dur, "start": _today() + 1 + wait, "quality": b.quality, "reliability": b.reliability,
			"material": "Baufirma beschafft Material (im Preis enthalten)", "payment": "Abschläge nach Bauabschnitten, 8 % bei Übergabe",
			"terms": "Verzögerungen durch Wetter und Lieferung ohne Aufpreis; Nachbesserung kostenlos", "valid_until": _today() + OFFER_VALID_DAYS})
	return offers


## Bewertung eines Angebots (niedriger = besser): guenstig allein reicht nicht, Qualitaet, Zuverlaessigkeit und Termin zaehlen.
static func score(o: Dictionary, base: float, today: int) -> float:
	return float(o.price) / maxf(1.0, base) - 0.45 * float(o.quality) - 0.6 * float(o.reliability) + 0.004 * float(int(o.start) - today) + 0.002 * float(o.days)


func best_offer(offers: Array, base: float) -> Dictionary:
	var best := {}
	var best_s := 1e9
	for o in offers:
		var s := score(o, base, _today())
		if s < best_s:
			best_s = s
			best = o
	return best


# ------------------------------------------------------------------ Vorhaben (private Bauherren, Bautraeger, Stadt)
func available_funds(client: String) -> float:
	if client.begins_with("H"):
		return float(sim.households.homes.get(client, {}).get("balance", 0.0)) + float(sim.banking.open_commitment(client).get("committed", 0.0))
	if client == DEVELOPER:
		return float(sim.economy.accounts[DEVELOPER]) - reserved_dev
	if client.begins_with("C"):
		var c: Company = sim.company(int(client.substr(1)))
		return 0.0 if c == null else c.ledger.cash - float(reserved_co.get(client, 0.0))
	return 0.0


## Bauvorhaben aus einer genehmigten Genehmigung anlegen und Angebote einholen.
func start_project(app_id: String) -> Dictionary:
	var a: Dictionary = sim.permits.apps.get(app_id, {})
	if a.is_empty() or a.status != "entschieden" or a.result not in ["genehmigt", "genehmigt_mit_bedingungen"] or a.get("expired", false):
		return {"ok": false, "msg": "Antrag %s ist nicht genehmigt oder abgelaufen." % app_id}
	for p in projects.values():
		if p.app == app_id and p.status != "abgebrochen":
			return {"ok": false, "msg": "Für %s gibt es bereits das Bauvorhaben %s." % [app_id, p.id]}
	var parcel: Dictionary = sim.parcels.parcel(a.parcel)
	var res := Planning.assess(parcel, a)
	var costs: Dictionary = res.costs
	var base := float(costs.bau)
	var pr := {"id": "BP%d" % _next, "client": a.applicant, "parcel": a.parcel, "app": a.id, "def": a.def, "floors": int(a.floors), "status": "angebote",
		"base": base, "build_days": int(res.days.bau), "dev_days": int(res.days.erschliessung), "missing": res.missing.duplicate(), "dev_cost": float(costs.erschliessung),
		"levy": float(costs.erschliessungsbeitrag), "offers": [], "builder": "", "price": 0.0, "reserved": 0.0, "paid": 0.0, "temp_access": false,
		"phase": 0, "progress": 0.0, "mats": {}, "blockers": [], "defects": 0, "units": [], "history": [], "lost_days": {}, "start": -1, "end_planned": -1, "end": -1,
		"dev_progress": 0.0, "paid_phases": 0}
	_next += 1
	pr.offers = make_offers(base, pr.build_days, pr.id)
	projects[pr.id] = pr
	_log(pr, "Bauvorhaben angelegt, %d Angebote eingeholt" % pr.offers.size())
	return {"ok": true, "msg": "Bauvorhaben %s für %s: %d Angebote." % [pr.id, a.parcel, pr.offers.size()], "id": pr.id}


## Angebot annehmen = verbindlicher Vertrag. Der Auftraggeber legt den Preis (plus Erschliessung, Beitrag, Zufahrt) zurueck.
func accept(project_id: String, builder_id: String) -> Dictionary:
	var pr: Dictionary = projects.get(project_id, {})
	if pr.is_empty() or pr.status != "angebote":
		return {"ok": false, "msg": "Bauvorhaben %s nimmt keine Angebote an." % project_id}
	var offer := {}
	for o in pr.offers:
		if o.builder == builder_id:
			offer = o
	if offer.is_empty() or int(offer.valid_until) < _today():
		return {"ok": false, "msg": "Kein gültiges Angebot von %s." % builder_id}
	if builders[builder_id].status != "aktiv":
		return {"ok": false, "msg": "%s kann keine Aufträge übernehmen." % builders[builder_id].name}
	var need := float(offer.price) + float(pr.dev_cost) + Planning.TEMP_ACCESS_COST * (1.0 if not pr.missing.is_empty() else 0.0)
	if available_funds(pr.client) + 0.5 < need:
		return {"ok": false, "msg": "Mittel von %s reichen nicht: %s verfügbar, %s nötig (Finanzierung gesichert?)." % [pr.client, Catalog.money(available_funds(pr.client)), Catalog.money(need)]}
	var credit := 0.0
	if str(pr.client).begins_with("H"):
		var m: Dictionary = sim.banking.open_commitment(pr.client)
		if not m.is_empty():
			credit = minf(float(m.committed), need)
			m.project = pr.id
			m.committed = credit
	pr.credit_total = credit
	pr.need_total = need
	_reserve(pr.client, need - credit)
	pr.reserved = need - credit
	pr.builder = builder_id
	pr.price = float(offer.price)
	pr.plan_days = int(offer.days)
	pr.start = int(offer.start)
	pr.end_planned = int(offer.start) + int(offer.days) + int(pr.dev_days)
	pr.status = "erschliessung" if not pr.missing.is_empty() else "im_bau"
	pr.contract = {"builder": builder_id, "price": pr.price, "start": pr.start, "days": pr.plan_days, "day": _today(), "offer": offer}
	pr.mats = _material_plan(pr)
	sim.parcels.mark(pr.parcel, "in_erschliessung" if not pr.missing.is_empty() else "im_bau", pr.app)
	_log(pr, "Vertrag mit %s: %s, Beginn Tag %d, Bauzeit %d Tage" % [builders[builder_id].name, Catalog.money(pr.price), pr.start, pr.plan_days])
	return {"ok": true, "msg": "Vertrag %s mit %s über %s." % [pr.id, builders[builder_id].name, Catalog.money(pr.price)]}


## Automatisch das beste Angebot waehlen (Bauherr ohne eigene Entscheidung).
func accept_best(project_id: String) -> Dictionary:
	var pr: Dictionary = projects.get(project_id, {})
	if pr.is_empty():
		return {"ok": false, "msg": "Bauvorhaben %s gibt es nicht." % project_id}
	var affordable: Array = pr.offers.filter(func(o): return float(o.price) + float(pr.dev_cost) + (Planning.TEMP_ACCESS_COST if not pr.missing.is_empty() else 0.0) <= available_funds(pr.client) + 0.5)
	var o := best_offer(affordable, float(pr.base))
	if o.is_empty():
		return {"ok": false, "msg": "Kein bezahlbares Angebot für %s." % project_id}
	return accept(project_id, o.builder)


func cancel(project_id: String, reason: String) -> Dictionary:
	var pr: Dictionary = projects.get(project_id, {})
	if pr.is_empty() or pr.status in ["uebergeben", "abgebrochen"]:
		return {"ok": false, "msg": "Bauvorhaben %s lässt sich nicht abbrechen." % project_id}
	_release(pr.client, float(pr.reserved))
	pr.reserved = 0.0
	var mc: Dictionary = sim.banking.mortgage_of_project(pr.id)
	if not mc.is_empty():
		sim.banking.mortgage_close_commitment(mc.id)
	pr.status = "abgebrochen"
	_log(pr, "Abgebrochen: " + reason)
	sim.parcels.mark(pr.parcel, "genehmigt" if int(pr.phase) == 0 else sim.parcels.parcel(pr.parcel).state, pr.app)
	return {"ok": true, "msg": "Bauvorhaben %s abgebrochen; offene Mittel freigegeben." % project_id}


# ------------------------------------------------------------------ Material
func _material_plan(pr: Dictionary) -> Dictionary:
	var out := {}
	var value := float(pr.base) * MATERIAL_SHARE
	for i in PHASES.size():
		var ph: Dictionary = PHASES[i]
		if float(ph.mat) <= 0.0:
			continue
		var wsum := 0.0
		for it in ph.items:
			wsum += float(ph.items[it])
		var need := {}
		for it in ph.items:
			var share := value * float(ph.mat) * float(ph.items[it]) / wsum
			need[it] = maxi(1, int(round(share / float(Trader.MATERIALS[it].base))))
		out[ph.id] = {"need": need, "delivered": {}, "ordered": false, "ready": false}
	return out


## Lieferauftrag fuer das Material einer Phase an die Baustelle. Ein Transportunternehmen kann ihn annehmen (Frachtlohn), sonst liefert der Bauhof.
func _order_material(pr: Dictionary, phase_id: String) -> void:
	var m: Dictionary = pr.mats[phase_id]
	if m.ordered:
		return
	m.ordered = true
	var value := 0.0
	for it in m.need:
		value += float(m.need[it]) * float(Trader.MATERIALS[it].base)
	var d := {"id": "L%d" % _next_delivery, "project": pr.id, "phase": phase_id, "need": m.need.duplicate(), "value": snappedf(value, 1.0), "freight": snappedf(value * FREIGHT_RATE, 1.0),
		"status": "offen", "carrier": "", "day": _today(), "from": sim.trader.bauhof, "to": int(sim.parcels.parcel(pr.parcel).get("building", -1))}
	_next_delivery += 1
	deliveries[d.id] = d
	_log(pr, "Materiallieferung %s bestellt (%s)" % [d.id, phase_id])


func open_deliveries() -> Array:
	return deliveries.values().filter(func(d): return d.status == "offen")


## Ein Spieler uebernimmt einen Lieferauftrag, liefert (Ware wird beim Bauhof entnommen) und erhaelt den Frachtlohn.
func take_delivery(delivery_id: String, company_id: int) -> Dictionary:
	if jobs.has(delivery_id):
		return take_job(delivery_id, company_id)
	var d: Dictionary = deliveries.get(delivery_id, {})
	if d.is_empty() or d.status != "offen":
		return {"ok": false, "msg": "Lieferauftrag %s ist nicht offen." % delivery_id}
	var c: Company = sim.company(company_id)
	if c == null or c.status in ["insolvenz", "verwertung", "geschlossen"]:
		return {"ok": false, "msg": "Unternehmen %d kann nicht liefern." % company_id}
	var res := _deliver(d, true)
	if not res.ok:
		return res
	d.carrier = "C%d" % company_id
	sim.economy.transfer("K0", "H0", float(d.freight))
	c.ledger.book("transport", float(d.freight), true, "Frachtlohn Baustoffe %s" % d.id, sim.game_min)
	return {"ok": true, "msg": "Lieferung %s ausgeführt, Frachtlohn %s." % [d.id, Catalog.money(float(d.freight))]}


## Ware beim Bauhof entnehmen und bezahlen. Fehlt Ware oder Geld, bleibt der Auftrag offen und blockiert die Phase.
func _deliver(d: Dictionary, with_carrier: bool) -> Dictionary:
	var pr: Dictionary = projects.get(d.project, {})
	if pr.is_empty():
		return {"ok": false, "msg": "Bauvorhaben fehlt."}
	for it in d.need:
		if sim.stock.available(it, "T0", sim.trader.bauhof) < int(d.need[it]):
			return {"ok": false, "msg": "Der Bauhof hat nicht genug %s (%d benötigt)." % [Trader.MATERIALS[it].name, int(d.need[it])]}
	var cost := float(d.value) + (float(d.freight) if with_carrier else 0.0)
	if float(sim.economy.accounts.K0) < cost:
		return {"ok": false, "msg": "Baufirma ist nicht liquide genug für die Materialbestellung."}
	for it in d.need:
		sim.stock.consume(it, int(d.need[it]), "T0", sim.trader.bauhof, "Baustelle %s" % pr.id, sim.game_min)
	sim.economy.transfer("K0", "T0", float(d.value))
	d.status = "geliefert"
	d.delivered_day = _today()
	var m: Dictionary = pr.mats[d.phase]
	for it in d.need:
		m.delivered[it] = int(m.delivered.get(it, 0)) + int(d.need[it])
	m.ready = true
	_log(pr, "Material für %s geliefert" % d.phase)
	return {"ok": true, "msg": "geliefert"}


# ------------------------------------------------------------------ Tageslauf
func on_day(day: int) -> void:
	for pr in projects.values():
		match pr.status:
			"angebote":
				if not pr.offers.is_empty() and int(pr.offers[0].valid_until) < day:
					pr.offers = make_offers(float(pr.base), int(pr.build_days), pr.id)   # abgelaufene Angebote erneuern
			"erschliessung", "wartet_anschluss":
				_day_site(pr, day)
			"im_bau":
				_day_build(pr, day)
			"pruefung":
				_day_inspection(pr, day)
	for d in deliveries.values():
		if d.status == "offen" and day - int(d.day) >= DELIVERY_FALLBACK_DAYS:
			_deliver(d, false)     # Bauhof liefert selbst
	_public_day(day)
	_jobs_day(day)
	_household_day()


func _day_site(pr: Dictionary, day: int) -> void:
	if day < int(pr.start) or builders[pr.builder].status != "aktiv":
		return
	pr.blockers = []
	if not pr.temp_access:
		if float(sim.economy.accounts.K0) >= 0.0 and _pay(pr, Planning.TEMP_ACCESS_COST, "Baustellenzufahrt"):
			pr.temp_access = true
	if pr.status == "erschliessung":
		pr.dev_progress += 1.0
		if pr.dev_progress >= float(pr.dev_days):
			var parcel: Dictionary = sim.parcels.parcel(pr.parcel)
			for part in pr.missing:
				parcel.erschliessung[part] = true
			_pay(pr, float(pr.dev_cost), "Erschließung")
			sim.parcels.touch(pr.parcel)
			pr.status = "im_bau"
			pr.missing = []
			sim.parcels.mark(pr.parcel, "im_bau", pr.app)
			_log(pr, "Erschließung hergestellt")


func _day_build(pr: Dictionary, day: int) -> void:
	if day < int(pr.start):
		return
	var b: Dictionary = builders[pr.builder]
	pr.blockers = []
	if b.status != "aktiv":
		pr.blockers.append("Baufirma %s ist ausgefallen." % b.name)
		return
	var ph: Dictionary = PHASES[int(pr.phase)]
	# Material der kommenden Phase vorbestellen (begrenzte Lagerflaeche: hoechstens eine Phase im Voraus)
	for k in range(int(pr.phase), mini(PHASES.size(), int(pr.phase) + 1 + STORAGE_PHASES)):
		if pr.mats.has(PHASES[k].id):
			_order_material(pr, PHASES[k].id)
	if pr.mats.has(ph.id) and not pr.mats[ph.id].ready:
		pr.blockers.append("Material für '%s' fehlt (Lieferung ausstehend)." % ph.label)
		_lose(pr, "material")
		return
	if ph.id in ["installation", "innenausbau"] and not pr.missing.is_empty():
		pr.blockers.append("Anschlüsse fehlen: " + ", ".join(pr.missing))
		_lose(pr, "anschluss")
		return
	var f := 1.0
	if bool(ph.wx):
		f = sim.wx.build_factor()
		if f < 1.0:
			_lose(pr, "wetter", 1.0 - f)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pr.id) + day * 31 + int(pr.phase)
	if rng.randf() > float(b.reliability) + 0.05:
		pr.blockers.append("Personalausfall bei %s." % b.name)
		_lose(pr, "personal")
		b.history.verzoegert = int(b.history.verzoegert) + 1
		return
	var over := maxi(0, load_of(pr.builder) - int(b.capacity))
	f *= float(b.capacity) / float(b.capacity + over)
	if f < 0.999 and over > 0:
		_lose(pr, "auslastung", 1.0 - float(b.capacity) / float(b.capacity + over))
	var phase_days := maxf(1.0, float(pr.plan_days) * float(ph.days))
	pr.progress += f / phase_days
	if pr.progress >= 1.0:
		_finish_phase(pr)


func _lose(pr: Dictionary, cause: String, amount: float = 1.0) -> void:
	pr.lost_days[cause] = snappedf(float(pr.lost_days.get(cause, 0.0)) + amount, 0.01)


func _finish_phase(pr: Dictionary) -> void:
	var ph: Dictionary = PHASES[int(pr.phase)]
	var pay := snappedf(float(pr.price) * float(ph.pay), 1.0)
	if ph.id != "uebergabe":                # die letzten 8 % werden erst bei der Uebergabe faellig
		if not _pay(pr, pay, "Abschlag " + ph.label):
			pr.blockers.append("Zahlung für '%s' nicht möglich (Finanzierung)." % ph.label)
			_lose(pr, "finanzierung")
			pr.progress = 0.99
			return
		pr.paid_phases = int(pr.paid_phases) + 1
		pr.paid_price = float(pr.get("paid_price", 0.0)) + pay
	_log(pr, "Phase abgeschlossen: " + ph.label)
	pr.progress = 0.0
	pr.phase = int(pr.phase) + 1
	if int(pr.phase) >= PHASES.size() - 1:
		_start_inspection(pr)


func _start_inspection(pr: Dictionary) -> void:
	var q := float(builders[pr.builder].quality)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pr.id) + 77
	pr.defects = int(round((1.0 - q) * 5.0 * rng.randf_range(0.5, 1.5)))
	builders[pr.builder].history.maengel = int(builders[pr.builder].history.maengel) + int(pr.defects)
	pr.status = "pruefung"
	_log(pr, "Prüfung: %d Mängel festgestellt" % pr.defects)


func _day_inspection(pr: Dictionary, day: int) -> void:
	if builders[pr.builder].status != "aktiv":
		return
	if int(pr.defects) > 0:
		pr.defects = int(pr.defects) - 1       # ein Mangel je Tag wird auf Kosten der Baufirma behoben
		_lose(pr, "maengel")
		return
	var parcel: Dictionary = sim.parcels.parcel(pr.parcel)
	var open: Array = []
	for need in Planning.rules(parcel.zone).anschluesse:
		if not parcel.erschliessung.get(need, false):
			open.append(need)
	if not open.is_empty():
		pr.status = "wartet_anschluss"
		pr.missing = open
		pr.blockers = ["Übergabe erst nach Anschluss: " + ", ".join(open)]
		return
	_hand_over(pr, day)


func _hand_over(pr: Dictionary, day: int) -> void:
	var rest := maxf(0.0, float(pr.price) - float(pr.get("paid_price", 0.0)))   # Schlusszahlung = Restforderung (kein Rundungsrest)
	if not _pay(pr, rest, "Schlusszahlung"):
		pr.blockers = ["Schlusszahlung nicht möglich."]
		return
	var parcel: Dictionary = sim.parcels.parcel(pr.parcel)
	var d: Dictionary = Planning.DEFS[pr.def]
	var w := int(d.w)
	var h := int(d.h)
	if w > int(parcel.rect[2]) or h > int(parcel.rect[3]):
		var t := w
		w = h
		h = t
	var r := Rect2i(int(parcel.rect[0]) + (int(parcel.rect[2]) - w) / 2, int(parcel.rect[1]) + (int(parcel.rect[3]) - h) / 2, w, h)
	var b: Dictionary = sim.events._add_building(str(d.sprite), r, "%s (%s)" % [d.label, pr.id])
	if b.is_empty():
		var shifted := Rect2i(int(parcel.rect[0]), int(parcel.rect[1]), w, h)
		b = sim.events._add_building(str(d.sprite), shifted, "%s (%s)" % [d.label, pr.id])
	if b.is_empty():
		pr.blockers = ["Gebäude kann nicht übergeben werden (kein Straßenzugang an der Parzelle)."]
		return
	sim.market.refresh()
	sim.residents.add_for_buildings([b.id])
	sim.events.buildings_added.emit([b.id])
	pr.building = int(b.id)
	pr.status = "uebergeben"
	pr.end = day
	pr.blockers = []
	builders[pr.builder].history.fertig = int(builders[pr.builder].history.fertig) + 1
	_release_reserve_rest(pr)
	_create_units(pr, parcel)
	_log(pr, "Übergeben am Tag %d: %s (Gebäude %d)" % [day, d.label, b.id])
	sim.log_event("Bauvorhaben %s übergeben: %s auf %s (%s)." % [pr.id, d.label, pr.parcel, builders[pr.builder].name], "info")


func _create_units(pr: Dictionary, parcel: Dictionary) -> void:
	var d: Dictionary = Planning.DEFS[pr.def]
	var n := Planning.units_of(pr.def, int(pr.floors))
	if d.use not in ["wohnen", "misch"]:
		return
	sim.mayor.stock_units += n
	for i in n:
		var u := {"id": "W%d" % _next_unit, "building": int(pr.building), "project": pr.id, "owner": pr.client, "tenant": "", "rent": RENT_PER_UNIT_MONTH, "area": 60 + 10 * i % 3 * 5, "move_in_day": -1}
		_next_unit += 1
		units[u.id] = u
		pr.units.append(u.id)
	# Der Bauherr-Haushalt zieht in die erste Wohneinheit ein; alle anderen werden vermietet.
	if str(pr.client).begins_with("H") and sim.households.homes.has(pr.client):
		var first: Dictionary = units[pr.units[0]]
		first.tenant = pr.client
		first.rent = 0.0
		first.move_in_day = _today()
		_move_in(first, pr.client)
		sim.households.homes[pr.client].address = int(pr.building)
		_log(pr, "Haushalt %s zieht in %s ein" % [pr.client, first.id])


# ------------------------------------------------------------------ Einzug: Umzugs-, Moebel- und Versorgungsauftraege
func _move_in(u: Dictionary, payer: String) -> void:
	for kind in MOVE_JOBS:
		var j := {"id": "S%d" % _next_job, "kind": kind, "unit": u.id, "payer": payer, "fee": float(MOVE_JOBS[kind].fee), "status": "offen", "carrier": "", "day": _today()}
		_next_job += 1
		jobs[j.id] = j
	# Versorgungsauftrag: Anschluss auf den Namen des Einziehenden, Gebuehr an die Stadt
	u["utilities_day"] = _today()
	if payer.begins_with("H") and sim.households.homes.has(payer) and float(sim.households.homes[payer].balance) >= CONNECTION_FEE:
		sim.households.homes[payer].balance = float(sim.households.homes[payer].balance) - CONNECTION_FEE
		sim.economy.transfer("H0", "P0", CONNECTION_FEE)


func open_jobs() -> Array:
	return jobs.values().filter(func(j): return j.status == "offen")


## Zahler -> Empfaenger (Unternehmen: Kasse; Spedition: K0). Zahlt der Haushalt nicht, entfaellt der Auftrag.
func _settle_job(j: Dictionary, company_id: int) -> bool:
	var payer := str(j.payer)
	if payer.begins_with("H"):
		var h: Dictionary = sim.households.homes.get(payer, {})
		if h.is_empty() or float(h.balance) < float(j.fee):
			return false
		h.balance = float(h.balance) - float(j.fee)
		if company_id >= 0:
			sim.company(company_id).ledger.book("transport", float(j.fee), true, "%s %s" % [MOVE_JOBS[j.kind].label, j.unit], sim.game_min)
		else:
			sim.economy.transfer("H0", "K0", float(j.fee))
		return true
	if company_id >= 0:
		sim.economy.transfer("X0", "H0", float(j.fee))
		sim.company(company_id).ledger.book("transport", float(j.fee), true, "%s %s" % [MOVE_JOBS[j.kind].label, j.unit], sim.game_min)
	else:
		sim.economy.transfer("X0", "K0", float(j.fee))
	return true


func take_job(job_id: String, company_id: int) -> Dictionary:
	var j: Dictionary = jobs.get(job_id, {})
	if j.is_empty() or j.status != "offen":
		return {"ok": false, "msg": "Auftrag %s ist nicht offen." % job_id}
	var c: Company = sim.company(company_id)
	if c == null or c.status in ["insolvenz", "verwertung", "geschlossen"]:
		return {"ok": false, "msg": "Unternehmen %d kann nicht fahren." % company_id}
	if not _settle_job(j, company_id):
		j.status = "entfallen"
		return {"ok": false, "msg": "Der Auftraggeber kann %s nicht bezahlen; Auftrag entfällt." % Catalog.money(float(j.fee))}
	j.status = "erledigt"
	j.carrier = "C%d" % company_id
	return {"ok": true, "msg": "%s ausgeführt, Entgelt %s." % [MOVE_JOBS[j.kind].label, Catalog.money(float(j.fee))]}


func _jobs_day(day: int) -> void:
	for j in jobs.values():
		if j.status == "offen" and day - int(j.day) >= JOB_FALLBACK_DAYS:
			j.status = "erledigt" if _settle_job(j, -1) else "entfallen"
			j.carrier = "K0"


# ------------------------------------------------------------------ Monat: Vermietung
func on_month(_month: int) -> void:
	var M: Mayor = sim.mayor
	for u in units.values():
		if u.tenant == "" and M.waiting > 0:
			M.waiting -= 1
			sim.citizens.immigrate(int(Mayor.PERSONS_PER_UNIT), _today() / 30)
			u.tenant = "W%d" % (hash(u.id) % 1000)
			u.move_in_day = _today()
			_move_in(u, "X0")
		if u.tenant != "" and float(u.rent) > 0.0:
			_collect_rent(u)
	_developer_month()
	_household_month(_month)


func _collect_rent(u: Dictionary) -> void:
	var rent := float(u.rent)
	if str(u.owner).begins_with("H") and sim.households.homes.has(u.owner):
		sim.households.homes[u.owner].balance = float(sim.households.homes[u.owner].balance) + rent
		sim.economy.transfer("X0", "H0", rent)
	elif u.owner == DEVELOPER:
		sim.economy.transfer("X0", DEVELOPER, rent)
	elif str(u.owner).begins_with("C") and sim.company(int(str(u.owner).substr(1))) != null:
		sim.economy.transfer("X0", "H0", rent)
		sim.company(int(str(u.owner).substr(1))).ledger.book("rent_income", rent, true, "Mieteinnahmen %s" % u.id, sim.game_min)


# ------------------------------------------------------------------ Bautraeger (Immobilienunternehmen, baut selbststaendig)
func _developer_month() -> void:
	var M: Mayor = sim.mayor
	if M.waiting <= 0 and M.vacancy() > 0.02:
		return
	for pr in projects.values():
		if pr.client == DEVELOPER and pr.status in ["angebote", "erschliessung", "im_bau", "pruefung", "wartet_anschluss"]:
			return        # ein Vorhaben nach dem anderen
	for a in sim.permits.apps.values():
		if a.applicant == DEVELOPER and a.status != "entschieden":
			return
		if a.applicant == DEVELOPER and a.status == "entschieden" and a.result.begins_with("genehmigt") and not a.expired:
			var known := false
			for pr in projects.values():
				known = known or pr.app == a.id
			if not known:
				var r := start_project(a.id)
				if r.ok:
					accept_best(r.id)
				return
	var cands: Array = sim.parcels.search({"zone": "wohnen", "min_area": 40, "limit": 80}).filter(func(p): return sim.parcels.utility_level(p) == "voll" and p.state == "frei" and p.owner == Parcels.CITY)
	var probe := {"def": "mehrfamilienhaus", "floors": 3, "parking": int(Planning.DEFS.mehrfamilienhaus.parking), "financing": {"eigenmittel": 1.0e9}}
	for p in cands:
		var chk := Planning.assess(p, probe)
		if not chk.ok or not chk.questions.is_empty() or float(chk.costs.gesamt) > available_funds(DEVELOPER):
			continue
		var res: Dictionary = sim.parcels.reserve(p.id, DEVELOPER)
		if not res.ok:
			continue
		var dr: Dictionary = sim.permits.draft(DEVELOPER, p.id, probe)
		if not dr.ok:
			sim.parcels.release(p.id, DEVELOPER)
			continue
		sim.permits.apps[dr.id].financing = {"eigenmittel": float(chk.costs.gesamt)}
		sim.permits.submit(dr.id)
		return


# ------------------------------------------------------------------ Haushalte als Bauherren (Abnahme Schritte 1-4, 7, 12)
func _home_note(hid: String, text: String) -> void:
	home_notes.append({"day": _today(), "home": hid, "text": text})
	if home_notes.size() > 30:
		home_notes.pop_front()
	sim.log_event("Haushalt %s: %s" % [hid, text], "info")


## Ein Haushalt mit Einkommen und Ersparnissen sucht ein Baugrundstueck, kauft es, laesst die Bank die Finanzierung pruefen und stellt den Antrag.
func _household_month(month: int) -> void:
	if home_plans.size() >= MAX_HOME_PLANS:
		return
	var ids: Array = sim.households.homes.keys()
	ids.sort()
	if ids.is_empty():
		return
	var told := false
	for k in ids.size():
		var hid: String = ids[(k + month) % ids.size()]
		var h: Dictionary = sim.households.homes[hid]
		if home_plans.has(hid) or float(h.get("last_income", 0.0)) <= 0.0 or float(h.balance) < 1500.0 or (hash(hid) + month) % HOME_DESIRE != 0:
			continue
		if _has_house_project(hid):
			continue
		var r := _plan_home(hid, h)
		if not r.ok and not told:
			_home_note(hid, str(r.msg))
			told = true
		if r.ok:
			return


func _has_house_project(hid: String) -> bool:
	for pr in projects.values():
		if pr.client == hid and pr.status not in ["abgebrochen"] and pr.def in ["einfamilienhaus", "doppelhaus"]:
			return true
	return false


func _plan_home(hid: String, h: Dictionary) -> Dictionary:
	var P: Parcels = sim.parcels
	var cands: Array = P.search({"zone": "wohnen", "min_area": 35, "limit": 200}).filter(func(p): return p.state == "frei" and p.owner == Parcels.CITY and P.utility_level(p) != "keine")
	cands.sort_custom(func(x, y): return (P.utility_level(x) == "voll") and (P.utility_level(y) != "voll"))   # voll erschlossene zuerst
	cands = cands.slice(0, 40)
	if cands.is_empty():
		return {"ok": false, "msg": "sucht ein Baugrundstück, findet aber kein freies Wohngrundstück mit Straßenanschluss."}
	var probe := {"def": HOME_DEF, "floors": 1, "parking": int(Planning.DEFS[HOME_DEF].parking), "financing": {"eigenmittel": 1.0e9}}
	var why := ""
	for p in cands:
		var chk := Planning.assess(p, probe)
		if not chk.ok or not chk.questions.is_empty():
			continue
		var total := float(p.price) + float(chk.costs.gesamt)
		var credit := maxf(0.0, total - float(h.balance) + HOME_RESERVE)
		var q := {"ok": true, "amount": 0.0}
		if credit > 0.0:
			q = sim.banking.mortgage_quote(hid, credit, total)
		if not q.ok:
			why = str(q.msg)
			continue
		var res: Dictionary = P.reserve(p.id, hid)
		if not res.ok:
			continue
		var bought: Dictionary = P.buy_for_household(p.id, hid)
		if not bought.ok:
			P.release(p.id, hid)
			continue
		var m := {}
		if credit > 0.0:
			m = sim.banking.mortgage_commit(hid, q)
		var fin := {"eigenmittel": float(chk.costs.gesamt) - credit}
		if credit > 0.0:
			fin["kredit"] = credit
			fin["kredit_gesichert"] = true
		var dr: Dictionary = sim.permits.draft(hid, p.id, {"def": HOME_DEF, "floors": 1, "parking": int(probe.parking), "financing": fin})
		if not dr.ok:
			if not m.is_empty():
				sim.banking.mortgage_close_commitment(m.id)
			return {"ok": false, "msg": str(dr.msg)}
		sim.permits.submit(dr.id)
		home_plans[hid] = {"stage": "antrag", "parcel": p.id, "app": dr.id, "project": "", "credit": credit, "day": _today()}
		_home_note(hid, "kauft %s (%s), %s, stellt Bauantrag %s." % [p.id, Catalog.money(float(p.price)),
			("Bank: " + str(q.msg)) if credit > 0.0 else "Finanzierung aus Eigenmitteln", dr.id])
		return {"ok": true, "msg": ""}
	return {"ok": false, "msg": why if why != "" else "findet kein geeignetes Grundstück."}


func _household_day() -> void:
	for hid in home_plans.keys():
		var pl: Dictionary = home_plans[hid]
		if pl.stage == "antrag":
			var a: Dictionary = sim.permits.apps.get(pl.app, {})
			if a.is_empty() or a.status != "entschieden":
				continue
			if not str(a.result).begins_with("genehmigt"):
				_home_note(hid, "Bauantrag %s nicht genehmigt (%s)." % [a.id, a.result])
				var mc: Dictionary = sim.banking.open_commitment(hid)
				if not mc.is_empty():
					sim.banking.mortgage_close_commitment(mc.id)
				home_plans.erase(hid)
				continue
			var r := start_project(a.id)
			if not r.ok:
				continue
			var acc := accept_best(r.id)
			if not acc.ok:
				cancel(r.id, "Haushalt kann den Bau nicht bezahlen")
				_home_note(hid, "kann den Bau nicht bezahlen: " + str(acc.msg))
				home_plans.erase(hid)
				continue
			pl.stage = "bau"
			pl.project = r.id
			_home_note(hid, "beauftragt %s (Vertrag %s)." % [builders[projects[r.id].builder].name, r.id])
		elif pl.stage == "bau":
			var pr: Dictionary = projects.get(pl.project, {})
			if pr.is_empty() or pr.status in ["uebergeben", "abgebrochen"]:
				if pr.get("status", "") == "uebergeben":
					_home_note(hid, "zieht in das neue Haus ein (Gebäude %d)." % int(pr.building))
				home_plans.erase(hid)


# ------------------------------------------------------------------ Oeffentliche Erschliessung (Buergermeister-Projekte)
func _public_day(day: int) -> void:
	var M: Mayor = sim.mayor
	for prj in M.projects.values():
		if prj.status == "ausgeschrieben" and not public.has(prj.id) and day > int(prj.tender.get("opened_day", day)):
			var days := 0
			for part in prj.parts:
				days = maxi(days, int(Planning.UTILITY_DAYS.get(part, 6)))
			days *= maxi(1, int(ceil(float(prj.parcels.size()) / 3.0)))
			var offers := make_offers(float(prj.cost), days, str(prj.id))
			prj.tender["bids"] = offers
			var o := best_offer(offers, float(prj.cost))
			if o.is_empty() or float(o.price) > float(prj.cost) * 1.2:
				prj.status = "beschlossen"      # kein tragfaehiges Angebot: neu planen oder ausschreiben
				prj.tender["note"] = "kein Angebot innerhalb des Budgets"
				continue
			# Material kommt aus dem Stadtlager (Auftragsmaterial): wird reserviert und vom Angebotspreis abgezogen, nicht nochmals abgerechnet
			var mats := CityDepot.material_need(prj.parts, prj.parcels.size())
			sim.city_depot.reserve_for_project(str(prj.id), mats, "ueberlassen")
			var mval := minf(sim.city_depot.value_of(mats), float(o.price) * 0.6)
			public[prj.id] = {"project": prj.id, "builder": o.builder, "price": float(o.price) - mval, "days_left": int(o.days), "days": int(o.days), "status": "laufend", "start": int(o.start), "paid": 0.0,
				"material_value": mval, "material_mode": "ueberlassen"}
			prj.status = "beauftragt"
			prj["builder"] = o.builder
	for e in public.values():
		if e.status != "laufend" or day < int(e.start):
			continue
		if builders[e.builder].status != "aktiv":
			continue
		if not sim.city_depot.project_complete(str(e.project)):
			e["waiting"] = "Material aus dem Stadtlager fehlt"
			continue
		e["waiting"] = ""
		e.days_left = int(e.days_left) - (1 if sim.wx.build_factor() > 0.3 else 0)
		if int(e.days_left) <= 0:
			_finish_public(e)


func _finish_public(e: Dictionary) -> void:
	var M: Mayor = sim.mayor
	var prj: Dictionary = M.projects[e.project]
	var pay := minf(float(e.price), maxf(0.0, float(sim.economy.accounts.P0)))
	sim.economy.transfer("P0", "K0", pay)
	e.paid = pay
	e["material_used"] = sim.city_depot.consume_project(str(e.project), builders[e.builder].name)
	M.commitments = maxf(0.0, M.commitments - float(prj.cost))
	for pid in prj.parcels:
		var p: Dictionary = sim.parcels.parcel(pid)
		for part in prj.parts:
			p.erschliessung[part] = true
		sim.parcels.touch(pid)
	e.status = "fertig"
	prj.status = "fertig"
	sim.log_event("Erschließungsprojekt %s fertiggestellt (%s, %s)." % [prj.id, ", ".join(prj.parts), builders[e.builder].name], "info")


# ------------------------------------------------------------------ Ausfall einer Baufirma
func fail_builder(bid: String) -> void:
	builders[bid].status = "insolvent"
	for pr in projects.values():
		if pr.builder == bid and pr.status in ["erschliessung", "im_bau", "pruefung", "wartet_anschluss"]:
			pr["failed_builder"] = bid
			_log(pr, "Baufirma %s ausgefallen; Baustelle bleibt bestehen (%d Phasen bezahlt)" % [builders[bid].name, int(pr.paid_phases)])
			pr.blockers = ["Baufirma %s ausgefallen." % builders[bid].name]


## Neuer Vertrag fuer die Restleistung. Bereits bezahlte Phasen werden nicht erneut bezahlt, das zurueckgelegte Restgeld bleibt zurueckgelegt.
func retender(project_id: String, builder_id: String) -> Dictionary:
	var pr: Dictionary = projects.get(project_id, {})
	if pr.is_empty() or not pr.has("failed_builder") or builders[builder_id].status != "aktiv":
		return {"ok": false, "msg": "Bauvorhaben %s braucht keinen Ersatz oder %s ist nicht verfügbar." % [project_id, builder_id]}
	var remaining := 0.0
	for i in range(int(pr.phase), PHASES.size()):
		remaining += float(PHASES[i].pay)
	var o := make_offers(float(pr.base), int(pr.build_days), pr.id + "r", remaining)
	var offer := {}
	for x in o:
		if x.builder == builder_id:
			offer = x
	var pending := float(pr.price) * remaining           # offene Restforderung des alten Vertrags
	var new_price := minf(float(offer.price), float(pr.reserved))
	pr.builder = builder_id
	pr.price = float(pr.price) - pending + new_price          # bezahlt bleibt bezahlt, Rest neu vergeben
	pr.plan_days = maxi(2, int(ceil(float(offer.days) / maxf(0.1, remaining) * 1.0)))
	pr.erase("failed_builder")
	pr.blockers = []
	pr.start = _today() + 1
	pr.price_rest = new_price
	_log(pr, "Ersatzvertrag mit %s über Restleistung %s" % [builders[builder_id].name, Catalog.money(new_price)])
	return {"ok": true, "msg": "Restleistung von %s übernommen." % builders[builder_id].name}


# ------------------------------------------------------------------ Geld
func _reserve(client: String, amount: float) -> void:
	if client.begins_with("H"):
		sim.households.homes[client].balance = float(sim.households.homes[client].balance) - amount
	elif client == DEVELOPER:
		reserved_dev += amount
	elif client.begins_with("C"):
		reserved_co[client] = float(reserved_co.get(client, 0.0)) + amount


func _release(client: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if client.begins_with("H") and sim.households.homes.has(client):
		sim.households.homes[client].balance = float(sim.households.homes[client].balance) + amount
	elif client == DEVELOPER:
		reserved_dev = maxf(0.0, reserved_dev - amount)
	elif client.begins_with("C"):
		reserved_co[client] = maxf(0.0, float(reserved_co.get(client, 0.0)) - amount)


func _pay(pr: Dictionary, amount: float, _note: String) -> bool:
	if amount <= 0.0:
		return true
	# Baukredit: die Bank zahlt ihren Anteil je Bauabschnitt direkt an die Baufirma
	var draw := 0.0
	var mort: Dictionary = sim.banking.mortgage_of_project(pr.id) if float(pr.get("credit_total", 0.0)) > 0.0 else {}
	if not mort.is_empty():
		draw = minf(amount * float(pr.credit_total) / maxf(float(pr.need_total), 1.0), float(mort.committed) - float(mort.drawn))
	if float(pr.reserved) + 0.5 < amount - draw:
		return false
	if draw > 0.0:
		draw = sim.banking.mortgage_draw(mort.id, draw)
		amount -= draw
	pr.reserved = float(pr.reserved) - amount
	pr.paid = float(pr.paid) + amount + draw
	if str(pr.client).begins_with("C"):
		# Unternehmen: Bauaufwand zulasten der Firmenkasse (Gegenkonto S0), von dort an die Baufirmen
		var c: Company = sim.company(int(str(pr.client).substr(1)))
		reserved_co[pr.client] = maxf(0.0, float(reserved_co.get(pr.client, 0.0)) - amount)
		c.ledger.book("supplies", -amount, true, "Bauvorhaben %s: %s" % [pr.id, _note], sim.game_min)
		sim.economy.transfer("S0", "K0", amount)
		return true
	var from_acct := "H0" if str(pr.client).begins_with("H") else DEVELOPER
	if from_acct == DEVELOPER:
		reserved_dev = maxf(0.0, reserved_dev - amount)
	sim.economy.transfer(from_acct, "K0", amount)
	return true


## Nicht verbrauchte Rueckstellung (Rundungen, entfallene Zufahrt) geht an den Auftraggeber zurueck.
func _release_reserve_rest(pr: Dictionary) -> void:
	_release(pr.client, float(pr.reserved))
	pr.reserved = 0.0
	var mc: Dictionary = sim.banking.mortgage_of_project(pr.id)
	if not mc.is_empty():
		sim.banking.mortgage_close_commitment(mc.id)


# ------------------------------------------------------------------ Abfragen
## Besetzung der Baustelle heute: Vorarbeiter, Bauarbeiter, Maschinenfuehrer und Geraete der laufenden Phase. `arbeitet` = false bei Blockade
## (die Leute stehen dann auf der Baustelle, koennen aber nicht arbeiten). Ohne laufende Bauleistung leer.
func crew_of(pr: Dictionary) -> Dictionary:
	if pr.status not in ["erschliessung", "im_bau", "pruefung", "wartet_anschluss"]:
		return {}
	var phase_id: String = "erdarbeiten" if pr.status == "erschliessung" else "uebergabe" if pr.status in ["pruefung", "wartet_anschluss"] else PHASES[clampi(int(pr.phase), 0, PHASES.size() - 1)].id
	var spec: Dictionary = CREW[phase_id]
	var d: Dictionary = Planning.DEFS.get(pr.def, {})
	var scale := 1.0 + 0.25 * float(maxi(int(d.get("units", 1)) - 1, 0)) + 0.2 * float(maxi(int(pr.floors) - 1, 0))
	var work := int(ceil(float(spec.work) * scale))
	var ops := int(spec.ops)
	var working: bool = pr.blockers.is_empty() and int(pr.get("start", 0)) <= _today()
	return {"phase": phase_id, "role": spec.role, "foreman": 1, "workers": work, "operators": ops, "gear": spec.gear.duplicate(), "working": working,
		"people": 1 + work + ops, "builder": pr.builder}


func progress_of(pr: Dictionary) -> float:
	if pr.status == "uebergeben":
		return 1.0
	var done := 0.0
	for i in mini(int(pr.phase), PHASES.size()):
		done += float(PHASES[i].days)
	if int(pr.phase) < PHASES.size():
		done += float(PHASES[int(pr.phase)].days) * float(pr.progress)
	return clampf(done, 0.0, 1.0)


func forecast_day(pr: Dictionary) -> int:
	if pr.status == "uebergeben":
		return int(pr.end)
	var lost := 0.0
	for k in pr.lost_days:
		lost += float(pr.lost_days[k])
	return int(pr.end_planned) + int(ceil(lost)) + int(pr.defects)


func phase_label(pr: Dictionary) -> String:
	if pr.status == "uebergeben":
		return "übergeben"
	if pr.status == "erschliessung":
		return "Erschließung"
	if pr.status == "angebote":
		return "Angebote"
	return PHASES[mini(int(pr.phase), PHASES.size() - 1)].label


func summary() -> Dictionary:
	var by := {}
	for pr in projects.values():
		by[pr.status] = int(by.get(pr.status, 0)) + 1
	return {"vorhaben": projects.size(), "nach_status": by, "einheiten": units.size(), "vermietet": units.values().filter(func(u): return u.tenant != "").size(),
		"offene_lieferungen": open_deliveries().size(), "oeffentlich": public.size()}


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _log(pr: Dictionary, text: String) -> void:
	pr.history.append({"day": _today(), "text": text})


func to_dict() -> Dictionary:
	return {"builders": builders, "projects": projects, "deliveries": deliveries, "units": units, "jobs": jobs, "public": public, "reserved_dev": reserved_dev, "reserved_co": reserved_co,
		"next": [_next, _next_delivery, _next_unit, _next_job], "home_plans": home_plans, "home_notes": home_notes}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	builders = d.get("builders", builders)
	projects = d.get("projects", {})
	deliveries = d.get("deliveries", {})
	units = d.get("units", {})
	jobs = d.get("jobs", {})
	for j in jobs.values():
		j.day = int(j.day)
	public = d.get("public", {})
	reserved_dev = float(d.get("reserved_dev", 0.0))
	reserved_co = d.get("reserved_co", {})
	for k in reserved_co:
		reserved_co[k] = float(reserved_co[k])
	home_plans = d.get("home_plans", {})
	home_notes = d.get("home_notes", [])
	for hid in home_plans:
		home_plans[hid].day = int(home_plans[hid].day)
	for n in home_notes:
		n.day = int(n.day)
	var nx: Array = d.get("next", [1, 1, 1])
	_next = int(nx[0])
	_next_delivery = int(nx[1])
	_next_unit = int(nx[2])
	_next_job = int(nx[3]) if nx.size() > 3 else 1
	for pr in projects.values():
		for k in ["floors", "phase", "defects", "paid_phases", "build_days", "dev_days", "start", "end_planned", "end", "plan_days"]:
			if pr.has(k):
				pr[k] = int(pr[k])
		if pr.has("building"):
			pr.building = int(pr.building)
		for pid in pr.mats:
			for it in pr.mats[pid].need:
				pr.mats[pid].need[it] = int(pr.mats[pid].need[it])
			for it in pr.mats[pid].delivered:
				pr.mats[pid].delivered[it] = int(pr.mats[pid].delivered[it])
	for dl in deliveries.values():
		for it in dl.need:
			dl.need[it] = int(dl.need[it])
		dl.from = int(dl.from)
		dl.to = int(dl.to)
	for u in units.values():
		u.building = int(u.building)
	for e in public.values():
		e.days_left = int(e.days_left)
		e.days = int(e.days)
		e.start = int(e.start)
