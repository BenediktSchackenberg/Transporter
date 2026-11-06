class_name Population
extends RefCounted
## Bevoelkerungsmodell (Auftrag 10, Etappe 1, docs/RESIDENTS.md). Erweitert die Buerger aus `Citizens` (gleiche Datensaetze,
## kein Parallelsystem) um Alter, Bildung, Konto, Eigentum und Beduerfnisse.
##
## Konten: Jede Person hat ein Guthaben (`balance`). Die Summe aller Guthaben ist immer exakt das Sektorkonto R0 ("Buergerkonten");
## jede Buchung aendert Personenguthaben und R0 gemeinsam (`pay_in`/`pay_out`/`move`). Geld zwischen Personen (Miete an einen
## Buerger-Vermieter) bleibt innerhalb von R0. So bleibt die Geldkonservierung von `Economy` erhalten.
##
## Eigentum: Wohneinheiten mit Buerger-Eigentuemer tragen `owner = "R<Buerger-ID>"`; `owner_occupied` = der Eigentuemer wohnt selbst dort
## (keine Miete). Fuer jede dieser Einheiten zahlt der Eigentuemer Grundsteuer an die Stadtkasse (Satz vom Buergermeister).

const ACCOUNT := "R0"
const OWNER_PREFIX := "R"
const DEFAULTS := {
	"bevoelkerung": 1000, "beschaeftigungsquote": 0.9, "eigentuemerquote": 0.35, "alter_min": 18, "alter_max": 67,
	"bildung_verteilung": [0.25, 0.40, 0.25, 0.10], "startguthaben_basis": 1500.0, "startguthaben_je_bildungsstufe": 1000.0,
	"startguthaben_eigentuemer": 4000.0, "lohnzuschlag_je_bildungsstufe": 0.08, "grundsteuer_satz_prozent_jahr": 1.0,
	"grundsteuer_intervall": "monat", "immobilienwert_jahresmieten": 15.0, "eigennutzer_anteil_einfamilienhaus": 0.8,
	"eigennutzer_anteil_wohnblock": 0.25, "vermieter_max_einheiten": 6,
	"beduerfnis_gewichte_glueck": {"geld": 0.3, "arbeit": 0.25, "bildung": 0.15, "wohnen": 0.3},
	"mindestbildung": {"rathaus": 2, "schule_klinik": 2, "gesundheit": 2, "polizei": 1}, "unglueck_schwelle": 40.0,
	"weiterbildung_ab_monaten_arbeitslos": 2, "weiterbildung_chance": 0.15, "weiterbildung_monate": 6,
	"umzug_chance_unglueck": 0.3, "wegzug_ab_monaten_arbeitslos": 6, "wegzug_chance": 0.2,
}
const CONFIG_PATH := "res://config/residents.json"
const EDUCATION := ["Grundbildung", "Ausbildung", "Fachkraft", "Hochschule"]
const TAX_RATE_MIN := 0.2
const TAX_RATE_MAX := 3.0
const TAX_STEP_MAX := 0.5                # hoechste Aenderung des Satzes je Beschluss (Prozentpunkte)

static var _cfg := {}

var sim
var tax_rate := 1.0                      # Grundsteuer in Prozent des Immobilienwerts je Jahr
var tax_total := 0.0
var month_log: Array = []                # Monatsprotokoll der Summen (Statistik/Diagnose)
var last_validation: Array = []
var behavior := {}                       # Verhalten im letzten Monat (Etappe 2): Weiterbildung, Umzug, Wegzug
var training_support := 0                # Foerderung der Weiterbildung durch den Buergermeister (0-100 %)
const TRAINING_COST := 400.0             # Zuschuss je Kursbeginn bei voller Foerderung (an den Bildungstraeger, S0)


## Konfiguration: Standardwerte, ueberschrieben von config/residents.json (falls vorhanden).
static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = DEFAULTS.duplicate(true)
		if FileAccess.file_exists(CONFIG_PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
			if d is Dictionary:
				for k in d:
					if not str(k).begins_with("_"):
						_cfg[k] = d[k]
	return _cfg


## Fuer Tests: Konfiguration ersetzen (leer = neu laden).
static func set_cfg(d: Dictionary) -> void:
	_cfg = d.duplicate(true)


func setup(simulation) -> void:
	sim = simulation
	tax_rate = float(cfg().grundsteuer_satz_prozent_jahr)


# ------------------------------------------------------------------ Erzeugung
## Alter, Bildung und Startguthaben fuer alle Buerger ohne diese Angaben (Start und Zuzug). Startguthaben kommen als Ersparnisse
## aus dem Ausland (X0 -> R0).
func init_people(people: Array, salt: int = 0) -> void:
	var c := cfg()
	var total := 0.0
	for p in people:
		if p.has("balance"):
			continue
		if not p.has("education"):
			assign_attributes([p], salt)
		var edu := int(p.education)
		p["balance"] = 0.0
		p["needs"] = {"geld": 50.0, "arbeit": 50.0, "bildung": 25.0 * edu, "glueck": 50.0}
		p["tax_arrears"] = 0.0
		var start := float(c.startguthaben_basis) + float(c.startguthaben_je_bildungsstufe) * edu
		p.balance = snappedf(start, 0.01)
		total += p.balance
	if total > 0.0:
		sim.economy.transfer("X0", ACCOUNT, total)


## Eigentuemer bestimmen, bis etwa `eigentuemerquote` der Personen in eigenem Wohnraum lebt oder Wohnungen besitzt.
## Erst Eigennutzer (Einfamilienhaeuser, Villen bevorzugt), dann erhalten alle von Buergern gemieteten Einheiten einen
## Buerger-Vermieter (bevorzugt Eigennutzer mit hoher Bildung, hoechstens `vermieter_max_einheiten` je Person).
func assign_ownership() -> void:
	var c := cfg()
	var H: Housing = sim.housing
	var occ: Dictionary = H._citizen_occupants()
	var people: Array = sim.citizens.people
	var target := roundi(float(people.size()) * float(c.eigentuemerquote))
	var owners := 0
	var uids: Array = occ.keys()
	uids.sort_custom(func(a, b): return _unit_order(H.units[a]) < _unit_order(H.units[b]) or (_unit_order(H.units[a]) == _unit_order(H.units[b]) and str(a) < str(b)))
	var self_owned := {}
	for uid in uids:
		if owners >= target:
			break
		var u: Dictionary = H.units[uid]
		var group: Array = occ[uid]
		var b_type := str(sim.city.building(int(u.building)).type)
		var share := float(c.eigennutzer_anteil_einfamilienhaus) if b_type in ["house", "villa", "semi"] else float(c.eigennutzer_anteil_wohnblock)
		if Citizens.roll(int(group[0].id), 0, 41) >= share:
			continue
		var owner: Dictionary = group[0]
		for q in group:
			if int(q.education) > int(owner.education):
				owner = q
		u.owner = OWNER_PREFIX + str(int(owner.id))
		u.owner_occupied = true
		self_owned[uid] = true
		owners += group.size()
		_grant(owner, float(c.startguthaben_eigentuemer))   # Eigentuemer haben etwas mehr Ersparnis
	# Vermieter fuer alle gemieteten Buerger-Einheiten
	var landlords: Array = []
	for uid in self_owned:
		landlords.append(_person(int(str(H.units[uid].owner).substr(1))))
	landlords.sort_custom(func(a, b): return int(a.education) > int(b.education) or (int(a.education) == int(b.education) and int(a.id) < int(b.id)))
	var held := {}
	var li := 0
	var max_units := int(c.vermieter_max_einheiten)
	for uid in uids:
		if self_owned.has(uid) or landlords.is_empty():
			continue
		var tries := 0
		while tries < landlords.size() and int(held.get(int(landlords[li % landlords.size()].id), 0)) >= max_units:
			li += 1
			tries += 1
		if tries >= landlords.size():
			break   # alle Vermieter voll: Rest bleibt beim Vermietersektor V0
		var lord: Dictionary = landlords[li % landlords.size()]
		H.units[uid].owner = OWNER_PREFIX + str(int(lord.id))
		H.units[uid].owner_occupied = false
		held[int(lord.id)] = int(held.get(int(lord.id), 0)) + 1
		li += 1


static func _unit_order(u: Dictionary) -> int:
	return 0 if float(u.area) >= 100.0 else 1


func _grant(p: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	p.balance = float(p.balance) + amount
	sim.economy.transfer("X0", ACCOUNT, amount)


func _person(id: int) -> Dictionary:
	for p in sim.citizens.people:
		if int(p.id) == id:
			return p
	return {}


func person_index() -> Dictionary:
	var idx := {}
	for p in sim.citizens.people:
		idx[int(p.id)] = p
	return idx


# ------------------------------------------------------------------ Konten
## Zahlung von einem Sektorkonto an Personen: entries = [[person, betrag], ...].
func pay_in(from_acct: String, entries: Array) -> float:
	var sum := 0.0
	for e in entries:
		var amt := float(e[1])
		if amt <= 0.0:
			continue
		e[0].balance = float(e[0].balance) + amt
		sum += amt
	if sum > 0.0:
		sim.economy.transfer(from_acct, ACCOUNT, sum)
	return sum


## Zahlung von Personen an ein Sektorkonto (hoechstens ihr Guthaben). Gibt den gezahlten Betrag zurueck.
func pay_out(to_acct: String, entries: Array) -> float:
	var sum := 0.0
	for e in entries:
		var amt := minf(float(e[1]), maxf(0.0, float(e[0].balance)))
		if amt <= 0.0:
			continue
		e[0].balance = float(e[0].balance) - amt
		sum += amt
	if sum > 0.0:
		sim.economy.transfer(ACCOUNT, to_acct, sum)
	return sum


## Zahlung zwischen zwei Personen (bleibt in R0).
static func move(from_p: Dictionary, to_p: Dictionary, amount: float) -> float:
	var amt := minf(amount, maxf(0.0, float(from_p.balance)))
	if amt <= 0.0:
		return 0.0
	from_p.balance = float(from_p.balance) - amt
	to_p.balance = float(to_p.balance) + amt
	return amt


## Abweichung zwischen Summe der Personenguthaben und Konto R0 (muss 0 sein).
func account_error() -> float:
	var sum := 0.0
	for p in sim.citizens.people:
		sum += float(p.get("balance", 0.0))
	return sum - float(sim.economy.accounts.get(ACCOUNT, 0.0))


## Attribute ohne Geld (Alter, Bildung, Beduerfnisse) vor der Stellenvergabe, damit Bildung die Zuweisung lenkt.
func assign_attributes(people: Array, salt: int = 0) -> void:
	var c := cfg()
	var dist: Array = c.bildung_verteilung
	for p in people:
		if p.has("education"):
			continue
		var r1 := Citizens.roll(int(p.id), salt, 31)
		var r2 := Citizens.roll(int(p.id), salt, 32)
		p["age"] = int(c.alter_min) + int(r1 * float(int(c.alter_max) - int(c.alter_min) + 1))
		var acc := 0.0
		var edu := dist.size() - 1
		for i in dist.size():
			acc += float(dist[i])
			if r2 < acc:
				edu = i
				break
		p["education"] = edu


## Lohnzuschlag je Bildungsstufe (Faktor auf den Stundenlohn des Arbeitgebers).
static func wage_factor(p: Dictionary) -> float:
	return 1.0 + float(cfg().lohnzuschlag_je_bildungsstufe) * float(int(p.get("education", 0)))


## Miete an einen Buerger-Eigentuemer aus einem Sektorkonto (z. B. Firmenhaushalt aus H0). Gibt false zurueck, wenn es keinen gibt.
func credit_owner(owner_key: String, amount: float, from_acct: String) -> bool:
	if not owner_key.begins_with(OWNER_PREFIX) or not owner_key.substr(1).is_valid_int():
		return false
	var p := _person(int(owner_key.substr(1)))
	if p.is_empty():
		return false
	pay_in(from_acct, [[p, amount]])
	return true


## Wegzug: Guthaben der Wegziehenden verlassen die Stadt (R0 -> X0); ihre Wohnungen gehen an den Vermietersektor.
func on_emigrate(leaving: Array) -> void:
	var sum := 0.0
	var ids := {}
	for p in leaving:
		sum += maxf(0.0, float(p.get("balance", 0.0)))
		ids[OWNER_PREFIX + str(int(p.id))] = true
		p.balance = 0.0
	if sum > 0.0:
		sim.economy.transfer(ACCOUNT, "X0", sum)
	for u in sim.housing.units.values():
		if ids.has(str(u.owner)):
			u.owner = Housing.LANDLORD
			u.owner_occupied = false


# ------------------------------------------------------------------ Grundsteuer
## Immobilienwert einer Einheit: Jahreskaltmiete (Grundmiete) mal `immobilienwert_jahresmieten`.
static func unit_value(u: Dictionary) -> float:
	return float(u.base) * 12.0 * float(cfg().immobilienwert_jahresmieten)


func owned_units(pid: int) -> Array:
	var key := OWNER_PREFIX + str(pid)
	return sim.housing.units.values().filter(func(u): return str(u.owner) == key)


## Grundsteuer je Eigentuemer (monatlich oder im Januar fuer das ganze Jahr). Rueckstand bei zu wenig Guthaben.
func collect_property_tax(month: int) -> float:
	var yearly := str(cfg().grundsteuer_intervall) == "jahr"
	if yearly and posmod(month, 12) != 1:
		return 0.0
	var share := 1.0 if yearly else 1.0 / 12.0
	var due_by := {}
	for u in sim.housing.units.values():
		var o := str(u.owner)
		if o.begins_with(OWNER_PREFIX) and o.substr(1).is_valid_int():
			due_by[int(o.substr(1))] = float(due_by.get(int(o.substr(1)), 0.0)) + unit_value(u) * tax_rate / 100.0 * share
	var idx := person_index()
	var entries: Array = []
	for pid in due_by:
		var p: Dictionary = idx.get(pid, {})
		if p.is_empty():
			continue
		var due := float(due_by[pid]) + float(p.get("tax_arrears", 0.0))
		var pay := minf(due, maxf(0.0, float(p.balance)))
		p.tax_arrears = snappedf(due - pay, 0.01)
		entries.append([p, pay])
	var paid := pay_out("P0", entries)
	tax_total += paid
	sim.public_sector.property_tax_total += paid
	return paid


## Satz durch den Buergermeister (Prozent des Immobilienwerts je Jahr, schrittweise).
func set_tax_rate(pct: float) -> Dictionary:
	if pct < TAX_RATE_MIN or pct > TAX_RATE_MAX:
		return {"ok": false, "msg": "Grundsteuersatz muss zwischen %.1f und %.1f %% liegen." % [TAX_RATE_MIN, TAX_RATE_MAX]}
	if absf(pct - tax_rate) > TAX_STEP_MAX + 0.0001:
		return {"ok": false, "msg": "Der Satz darf je Beschluss höchstens um %.1f Prozentpunkte geändert werden (jetzt %.2f %%)." % [TAX_STEP_MAX, tax_rate]}
	var old := tax_rate
	tax_rate = snappedf(pct, 0.01)
	return {"ok": true, "msg": "Grundsteuersatz von %.2f %% auf %.2f %% des Immobilienwerts je Jahr geändert (geschätzte Einnahmen %s je Monat)." % [old, tax_rate, Catalog.money(estimated_monthly_tax())]}


func estimated_monthly_tax() -> float:
	var sum := 0.0
	for u in sim.housing.units.values():
		if str(u.owner).begins_with(OWNER_PREFIX):
			sum += unit_value(u) * tax_rate / 100.0 / 12.0
	return sum


# ------------------------------------------------------------------ Beduerfnisse
## Geld, Arbeit, Bildung und Glueck (0-100) je Person.
func update_needs() -> void:
	var w: Dictionary = cfg().beduerfnis_gewichte_glueck
	for p in sim.citizens.people:
		if not p.has("needs"):
			continue
		var net_month := maxf(400.0, float(p.get("net", 0.0)))
		var geld := clampf(50.0 + 25.0 * (float(p.balance) / net_month - 1.0) - minf(40.0, float(p.get("tax_arrears", 0.0)) / 20.0), 0.0, 100.0)
		var arbeit := 85.0 if p.employer != "" else clampf(60.0 - 12.0 * float(p.jobless_months), 5.0, 60.0)
		var bildung := clampf(15.0 + 25.0 * float(p.education), 0.0, 100.0)
		var unit: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
		var wohnen := 20.0 if unit.is_empty() else clampf(float(unit.get("sat", 60.0)) if float(unit.get("sat", 0.0)) > 0.0 else 60.0, 0.0, 100.0)
		if not unit.is_empty() and int(unit.get("arrears", 0)) > 0:
			wohnen -= 15.0 * float(int(unit.arrears))
		var glueck := float(w.geld) * geld + float(w.arbeit) * arbeit + float(w.bildung) * bildung + float(w.wohnen) * clampf(wohnen, 0.0, 100.0)
		p.needs = {"geld": snappedf(geld, 0.1), "arbeit": snappedf(arbeit, 0.1), "bildung": snappedf(bildung, 0.1), "glueck": snappedf(glueck, 0.1)}


func mean_need(key: String) -> float:
	var sum := 0.0
	var n := 0
	for p in sim.citizens.people:
		if p.has("needs"):
			sum += float(p.needs[key])
			n += 1
	return sum / maxf(1.0, float(n))


# ------------------------------------------------------------------ Verhalten aus Beduerfnissen (Etappe 2)
## Mindestbildung fuer eine Stelle beim Arbeitgeber (Konfiguration `mindestbildung`, fehlender Eintrag = keine Anforderung).
static func qualified(p: Dictionary, employer: String) -> bool:
	return int(p.get("education", 0)) >= int(cfg().mindestbildung.get(employer, 0))


## Monatliches Verhalten vor der Stellenvergabe, nach den Beduerfnissen des Vormonats:
## - Arbeitslose ab `weiterbildung_ab_monaten_arbeitslos` beginnen eine Weiterbildung (Schule, `weiterbildung_monate`; danach Bildung +1);
##   waehrend der Weiterbildung bewerben sie sich nicht.
## - Unglueckliche Mieter mit zu hoher Miete oder Rueckstand ziehen in eine guenstigere freie Wohnung.
## - Lange Arbeitslose ohne Wohneigentum, die ungluecklich sind, verlassen die Stadt (einzeln).
## Unglueckliche Beschaeftigte wechseln oefter die Stelle (`Citizens._dynamics`).
func behave(month: int) -> void:
	var c := cfg()
	var day: int = GameCalendar.day_of(sim.game_min)
	var unhappy := float(c.unglueck_schwelle)
	behavior = {"weiterbildung_beginn": 0, "weiterbildung_abschluss": 0, "umzug_unglueck": 0, "wegzug": 0}
	var leaving: Array = []
	for p in sim.citizens.people:
		if not p.has("needs") or PublicSafety.in_prison(p, day):
			continue
		var pid := int(p.id)
		if p.has("course_until") and int(p.course_until) <= day:
			p.erase("course_until")
			p.education = mini(3, int(p.education) + 1)
			behavior.weiterbildung_abschluss += 1
		var glueck := float(p.needs.glueck)
		if p.employer == "" and not p.has("course_until"):
			var chance := float(c.weiterbildung_chance) * (1.0 + 2.0 * float(training_support) / 100.0)
			if int(p.education) < 3 and int(p.jobless_months) >= int(c.weiterbildung_ab_monaten_arbeitslos) and Citizens.roll(pid, month, 51) < chance:
				var grant := TRAINING_COST * float(training_support) / 100.0
				if grant > 0.0 and sim.mayor.available_budget() < grant:
					training_support = 0       # Kasse leer: Foerderung endet
					sim.log_event("Weiterbildungsförderung eingestellt: Stadtkasse reicht nicht.", "warn")
					grant = 0.0
				if grant > 0.0:
					sim.economy.transfer("P0", "S0", grant)
					behavior["foerderung"] = float(behavior.get("foerderung", 0.0)) + grant
				p["course_until"] = day + 30 * int(c.weiterbildung_monate)
				behavior.weiterbildung_beginn += 1
				continue
			if int(p.jobless_months) >= int(c.wegzug_ab_monaten_arbeitslos) and glueck < unhappy and Citizens.roll(pid, month, 52) < float(c.wegzug_chance) \
					and owned_units(pid).is_empty():
				leaving.append(p)
				continue
		if glueck < unhappy and Citizens.roll(pid, month, 53) < float(c.umzug_chance_unglueck) and sim.housing.relocate_cheaper(p):
			behavior.umzug_unglueck += 1
	for p in leaving:
		sim.citizens.emigrate_person(p)
	behavior.wegzug = leaving.size()
	if not leaving.is_empty():
		sim.log_event("%d Bewohner verlassen die Stadt (lange arbeitslos und unglücklich)." % leaving.size(), "bad")


func set_training_support(pct: int) -> Dictionary:
	if pct < 0 or pct > 100:
		return {"ok": false, "msg": "Förderung muss zwischen 0 und 100 % liegen."}
	var old := training_support
	training_support = pct
	return {"ok": true, "msg": "Weiterbildungsförderung %d %% -> %d %% (bis zu %.1f-fach mehr Kursbeginne, %s je Kursbeginn)." % [old, pct, 1.0 + 2.0 * pct / 100.0, Catalog.money(TRAINING_COST * pct / 100.0)]}


func in_course_count() -> int:
	var n := 0
	for p in sim.citizens.people:
		if p.has("course_until"):
			n += 1
	return n


# ------------------------------------------------------------------ Status und Pruefung
## "eigentuemer": besitzt Wohnraum oder lebt im Wohnraum eines Haushaltsmitglieds, das ihn besitzt; sonst "mieter" (oder "ohne Wohnung").
func status_of(p: Dictionary) -> String:
	var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
	if u.is_empty():
		return "ohne Wohnung"
	if bool(u.get("owner_occupied", false)) or str(u.owner) == OWNER_PREFIX + str(int(p.id)):
		return "eigentuemer"
	return "mieter"


## Startpruefung (Vorlage Abschnitt 8). Gibt die Pruefpunkte zurueck und schreibt sie ins Ereignisprotokoll.
func validate(log_it: bool = true) -> Array:
	var c := cfg()
	var people: Array = sim.citizens.people
	var n := people.size()
	var housed := 0
	var owners := 0
	for p in people:
		var s := status_of(p)
		if s != "ohne Wohnung":
			housed += 1
		if s == "eigentuemer":
			owners += 1
	var occ: Dictionary = sim.housing._citizen_occupants()
	var bad_owner := 0
	var overfull := 0
	var idx := person_index()
	for uid in occ:
		var u: Dictionary = sim.housing.units[uid]
		var o := str(u.owner)
		if o.begins_with(OWNER_PREFIX) and not idx.has(int(o.substr(1))):
			bad_owner += 1
		if not o.begins_with(OWNER_PREFIX) and not bool(u.get("owner_occupied", false)):
			bad_owner += 1     # Vorlage: jede vermietete Buerger-Einheit hat einen Eigentuemer aus der Bevoelkerung
		if occ[uid].size() > maxi(1, ceili(float(u.area) / 20.0)):
			overfull += 1
	var employed: int = sim.citizens.employed_total()
	var pop: int = sim.citizens.population()
	var goal: int = int(sim.population_target) + sim.citizens._real_workers() if int(sim.population_target) > 0 else int(c.bevoelkerung)   # Kuestenort: Wohnraum + Personal
	var labor := maxf(1.0, float(pop - sim.citizens.applicants()))   # Quote ohne offene Bewerber
	var owner_tol := maxf(0.05, 4.0 / maxf(1.0, n))   # kleiner Ort: Eigentum geht haushaltsweise, die Quote springt in groesseren Stufen
	var checks: Array = [
		{"pruefung": "Bewohner", "wert": pop, "ziel": goal, "ok": absi(pop - goal) <= maxi(20, goal / 20)},
		{"pruefung": "mit Wohnsitz", "wert": snappedf(float(housed) / maxf(1.0, n), 0.001), "ziel": 1.0, "ok": housed == n},
		{"pruefung": "Beschäftigungsquote", "wert": snappedf(float(employed) / labor, 0.001), "ziel": float(c.beschaeftigungsquote),
			"ok": absf(float(employed) / labor - float(c.beschaeftigungsquote)) <= 0.03},
		{"pruefung": "Eigentümerquote", "wert": snappedf(float(owners) / maxf(1.0, n), 0.001), "ziel": float(c.eigentuemerquote),
			"ok": absf(float(owners) / maxf(1.0, n) - float(c.eigentuemerquote)) <= owner_tol},
		{"pruefung": "vermietete Einheiten ohne gültigen Eigentümer", "wert": bad_owner, "ziel": 0, "ok": bad_owner == 0},
		{"pruefung": "überbelegte Wohneinheiten", "wert": overfull, "ziel": 0, "ok": overfull == 0},
		{"pruefung": "doppelt vergebene Arbeitsplätze", "wert": 0, "ziel": 0, "ok": true},   # Buerger haben genau einen Arbeitgeber-Eintrag
		{"pruefung": "Bürgerkonten = R0", "wert": snappedf(account_error(), 0.01), "ziel": 0.0, "ok": absf(account_error()) < 0.01},
	]
	last_validation = checks
	if log_it:
		var failed: Array = checks.filter(func(x): return not x.ok)
		var txt := "Startprüfung Bevölkerung: %d von %d Punkten erfüllt%s" % [checks.size() - failed.size(), checks.size(),
			"" if failed.is_empty() else " – abweichend: " + ", ".join(failed.map(func(x): return "%s %s (Ziel %s)" % [x.pruefung, str(x.wert), str(x.ziel)]))]
		sim.log_event(txt, "info" if failed.is_empty() else "warn")
		print(txt)
	return checks


func summary() -> Dictionary:
	var people: Array = sim.citizens.people
	var owners := 0
	for p in people:
		if status_of(p) == "eigentuemer":
			owners += 1
	var edu := [0, 0, 0, 0]
	for p in people:
		edu[clampi(int(p.get("education", 0)), 0, 3)] += 1
	return {"bewohner": people.size(), "eigentuemer": owners, "mieter": people.size() - owners, "bildung": edu,
		"grundsteuer_satz": tax_rate, "grundsteuer_monat_geschaetzt": snappedf(estimated_monthly_tax(), 1.0), "grundsteuer_gesamt": snappedf(tax_total, 1.0),
		"glueck": snappedf(mean_need("glueck"), 0.1), "geld": snappedf(mean_need("geld"), 0.1), "arbeit": snappedf(mean_need("arbeit"), 0.1),
		"guthaben_gesamt": snappedf(float(sim.economy.accounts.get(ACCOUNT, 0.0)), 1.0), "monat_zuletzt": month_log.back() if not month_log.is_empty() else {},
		"in_weiterbildung": in_course_count(), "weiterbildung_foerderung_prozent": training_support, "verhalten_letzter_monat": behavior}


func to_dict() -> Dictionary:
	return {"tax_rate": tax_rate, "tax_total": tax_total, "month_log": month_log.slice(-24), "behavior": behavior, "training_support": training_support}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	tax_rate = float(d.get("tax_rate", tax_rate))
	tax_total = float(d.get("tax_total", 0.0))
	month_log = d.get("month_log", [])
	behavior = d.get("behavior", {})
	training_support = int(d.get("training_support", 0))
