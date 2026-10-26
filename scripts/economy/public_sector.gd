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
const SPEND_SHARE := 0.5          # Anteil der Mittel ueber dem Ausgangsstand, die als Auftraege an S0 gehen

var sim: Simulation
var tax_total := 0.0
var social_total := 0.0
var benefits_total := 0.0
var spending_total := 0.0
var corporate_total := 0.0
var departments := {"Soziales": 0.0, "Verkehr": 0.0, "Bildung": 0.0, "Verwaltung": 0.0, "Gesundheit": 0.0}   # Ausgaben je Ressort


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


## Zieht Steuer und Sozialabgaben vom Bruttolohn (liegt auf H0) ab und gibt den Nettobetrag zurueck.
func withhold(gross: float) -> float:
	var tax := gross * INCOME_TAX
	var social := gross * SOCIAL_RATE
	sim.economy.transfer("H0", "P0", tax + social)
	tax_total += tax
	social_total += social
	return gross - tax - social


func on_month(_month: int) -> void:
	for h in sim.households.homes.values():
		var aid := minf(float(h.get("shortfall", 0.0)) * BENEFIT_SHARE, maxf(0.0, float(sim.economy.accounts.P0)))
		if aid > 0.0:
			sim.economy.transfer("P0", "H0", aid)
			h.balance = float(h.balance) + aid
			benefits_total += aid
			departments.Soziales += aid
	for c in sim.companies:
		collect_corporate_tax(c)
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


func to_dict() -> Dictionary:
	return {"tax": tax_total, "social": social_total, "benefits": benefits_total, "spending": spending_total, "corporate": corporate_total, "departments": departments}


func from_dict(d: Dictionary) -> void:
	tax_total = float(d.get("tax", 0.0))
	social_total = float(d.get("social", 0.0))
	benefits_total = float(d.get("benefits", 0.0))
	spending_total = float(d.get("spending", 0.0))
	corporate_total = float(d.get("corporate", 0.0))
	for k in d.get("departments", {}):
		departments[k] = float(d.departments[k])
