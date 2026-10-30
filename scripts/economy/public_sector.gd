class_name PublicSector
extends RefCounted
## Oeffentliche Hand (Auftrag 4, erster Schritt): Lohnsteuer und Sozialabgaben der Haushalte fliessen auf P0,
## Sozialleistungen gleichen Haushaltsdefizite teilweise aus, uebrige Mittel gehen als oeffentliche Auftraege an S0.
## Alle Bewegungen laufen ueber Economy.transfer; die Geldsumme bleibt erhalten.

const INCOME_TAX := 0.12          # Anteil des Bruttolohns
const SOCIAL_RATE := 0.10         # Arbeitnehmeranteil Sozialversicherung
const BENEFIT_SHARE := 0.6        # Anteil des Haushaltsdefizits, den die Sozialleistung deckt
const CORPORATE_TAX := 0.15       # Ertragsteuer auf den kumulierten Gewinn (Verluste werden vorgetragen)
const DEPARTMENTS := {"Verkehr": 0.4, "Bildung": 0.25, "Verwaltung": 0.2, "Gesundheit": 0.15}   # Verteilung der Auftraege
const VAT_SHARE := 0.25           # kommunaler Anteil an der Umsatzsteuer auf den Konsum von Buergern und Haushalten (Anteil der Ausgaben)
const CASH_TARGET := 250000.0     # Soll der Stadtkasse: darunter erhoeht der Rat den Hebesatz, weit darueber senkt er ihn
const VAT_STEP := 0.02
const VAT_MIN := 0.15
const VAT_MAX := 0.60
const AUDIT_CHANCE := 0.15          # Wahrscheinlichkeit je Firma und Monat
const AUDIT_SURCHARGE := 0.10      # Zuschlag auf offene Steuer, wird als Bussgeld gebucht
const SPEND_SHARE := 0.5          # Anteil der Mittel ueber dem Ausgangsstand, die als Auftraege an S0 gehen

var sim: Simulation
var tax_total := 0.0
var social_total := 0.0
var benefits_total := 0.0
var spending_total := 0.0
var corporate_total := 0.0
var vat_total := 0.0
var vat_rate := VAT_SHARE         # aktueller Hebesatz; der Rat passt ihn monatlich an die Stadtkasse an
var audits: Array = []            # letzte Pruefungen: {cid, month, arrears, fine}
var departments := {"Soziales": 0.0, "Verkehr": 0.0, "Bildung": 0.0, "Verwaltung": 0.0, "Gesundheit": 0.0}   # Ausgaben je Ressort


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


## Umsatzsteuer-Anteil: Der Handel (S0) fuehrt einen Teil der Konsumausgaben an die Stadt ab. Gibt den Steuerbetrag zurueck.
func consumption_tax(spent: float) -> float:
	var tax := spent * vat_rate
	if tax <= 0.0:
		return 0.0
	sim.economy.transfer("S0", "P0", tax)
	vat_total += tax
	return tax


## Zieht Steuer und Sozialabgaben vom Bruttolohn (liegt auf H0) ab und gibt den Nettobetrag zurueck.
func withhold(gross: float) -> float:
	var tax := gross * INCOME_TAX
	var social := gross * SOCIAL_RATE
	sim.economy.transfer("H0", "P0", tax + social)
	tax_total += tax
	social_total += social
	return gross - tax - social


## Haushaltsregel des Rates: Faellt die Kasse unter 80 % des Solls, steigt der Hebesatz um zwei Punkte, liegt sie ueber 150 %, sinkt er.
func _adjust_rate() -> void:
	var cash := float(sim.economy.accounts.P0)
	var old := vat_rate
	if cash < CASH_TARGET * 0.8:
		vat_rate = minf(VAT_MAX, vat_rate + VAT_STEP)
	elif cash > CASH_TARGET * 1.5:
		vat_rate = maxf(VAT_MIN, vat_rate - VAT_STEP)
	if vat_rate != old:
		sim.log_event("Haushaltsbeschluss des Rates: kommunaler Umsatzsteueranteil %d %% → %d %% (Stadtkasse %s)." % [roundi(old * 100.0), roundi(vat_rate * 100.0), Catalog.money(cash)], "info")


func on_month(_month: int) -> void:
	_adjust_rate()
	for h in sim.households.homes.values():
		var aid := minf(float(h.get("shortfall", 0.0)) * BENEFIT_SHARE, maxf(0.0, float(sim.economy.accounts.P0)))
		if aid > 0.0:
			sim.economy.transfer("P0", "H0", aid)
			h.balance = float(h.balance) + aid
			benefits_total += aid
			departments.Soziales += aid
	for c in sim.companies:
		collect_corporate_tax(c)
		if _audit_roll(c.id, _month) < AUDIT_CHANCE:
			audit(c, _month)
	var excess: float = float(sim.economy.accounts.P0) - float(Economy.SEED.P0)
	if excess > 0.0:
		sim.economy.transfer("P0", "S0", SPEND_SHARE * excess)
		spending_total += SPEND_SHARE * excess
		for d in DEPARTMENTS:
			departments[d] += SPEND_SHARE * excess * DEPARTMENTS[d]


## Ertragsteuer: Sollsteuer auf den kumulierten Vorsteuergewinn (nie negativ) abzueglich bereits gezahlter Steuer, soweit Bargeld da ist.
func collect_corporate_tax(c: Company) -> float:
	var paid := -float(c.ledger.totals.get("tax", 0.0))
	var pretax: float = c.ledger.profit() + paid
	var due := maxf(0.0, pretax) * CORPORATE_TAX - paid
	var pay := minf(due, maxf(0.0, c.ledger.cash))
	if pay <= 0.01:
		return 0.0
	c.ledger.book("tax", -pay, true, "Ertragsteuer", sim.game_min)
	corporate_total += pay
	return pay


## Zufall ohne Zustand: gleiche Firma und gleicher Monat ergeben immer dieselbe Zahl (Wiederholung und Laden bleiben exakt).
func _audit_roll(cid: int, month: int) -> float:
	return float(hash(Vector2i(cid, month)) % 10000) / 10000.0


## Steuerpruefung: offene Ertragsteuer wird nachgefordert, dazu ein Zuschlag; gezahlt wird soweit Bargeld da ist.
func audit(c: Company, month: int) -> Dictionary:
	var paid := -float(c.ledger.totals.get("tax", 0.0))
	var pretax: float = c.ledger.profit() + paid
	var arrears := maxf(0.0, maxf(0.0, pretax) * CORPORATE_TAX - paid)
	var fine := 0.0
	if arrears > 0.01:
		collect_corporate_tax(c)
		var open := maxf(0.0, maxf(0.0, pretax) * CORPORATE_TAX - (-float(c.ledger.totals.get("tax", 0.0))))
		fine = minf(open * AUDIT_SURCHARGE + arrears * AUDIT_SURCHARGE, maxf(0.0, c.ledger.cash))
		if fine > 0.01:
			c.ledger.book("fines", -fine, true, "Steuerprüfung: Zuschlag", sim.game_min)
	var rec := {"cid": c.id, "month": month, "arrears": arrears, "fine": fine}
	audits.append(rec)
	if audits.size() > 40:
		audits.pop_front()
	sim.log_event("Steuerprüfung bei %s: %s" % [c.company_name, "Nachforderung %.0f, Zuschlag %.0f" % [arrears, fine] if arrears > 0.01 else "ohne Beanstandung"], "info", c.id)
	return rec


func to_dict() -> Dictionary:
	return {"tax": tax_total, "social": social_total, "benefits": benefits_total, "spending": spending_total, "corporate": corporate_total, "vat": vat_total, "vat_rate": vat_rate, "audits": audits, "departments": departments}


func from_dict(d: Dictionary) -> void:
	tax_total = float(d.get("tax", 0.0))
	social_total = float(d.get("social", 0.0))
	benefits_total = float(d.get("benefits", 0.0))
	spending_total = float(d.get("spending", 0.0))
	corporate_total = float(d.get("corporate", 0.0))
	vat_total = float(d.get("vat", 0.0))
	vat_rate = float(d.get("vat_rate", VAT_SHARE))
	audits = d.get("audits", [])
	for k in d.get("departments", {}):
		departments[k] = float(d.departments[k])
