class_name Ledger
extends RefCounted
## Finanzbuchhaltung einer Firma.
##
## Gewinn (Punktestand) = Summe aller Erfolgsbuchungen (Erloese positiv, Aufwand negativ).
## Bilanzidentitaet, die jederzeit gilt und getestet wird:
##   Bargeld + Buchwert (Fahrzeuge + Bueros) - Schulden == Startkapital + Gewinn
## Startkapital, Kredite, Tilgung, Fahrzeug- und Buerokaeufe sind keine Erfolgsbuchungen.

const INCOME := ["transport", "sales", "trade_income", "insurance_payout", "compensation", "asset_result", "rent_income", "interest_income", "subsidy"]
const LABELS := {
	"transport": "Transporterlöse", "sales": "Ladenverkauf an Haushalte", "subsidy": "Prämien der Stadt", "trade_income": "Erlöse aus Geschäften", "insurance_payout": "Versicherungsleistungen",
	"compensation": "Schadensersatz erhalten", "asset_result": "Ergebnis Fahrzeugverkauf", "fuel": "Treibstoff",
	"wages": "Löhne", "hire_fees": "Einstellungs-/Abwerbegebühren", "repairs": "Reparaturen & Abschleppen",
	"rent": "Miete", "depreciation": "Abschreibungen", "interest": "Zinsen", "penalties": "Vertragsstrafen",
	"sabotage": "Sabotagekosten", "fines": "Bußgelder & Schadensersatz", "security": "Sicherheitsdienst",
	"insurance": "Versicherungsprämien", "trade_expense": "Zahlungen an Konkurrenten", "marketing": "Marketing",
	"office": "Büros & Internet", "supplies": "Betriebsmittel (Treibstoff, Ersatzteile)",
	"rent_income": "Mieteinnahmen", "interest_income": "Zinserträge", "admin": "Verwaltung & Berichtspflicht", "property_costs": "Gelände- und Gebäudekosten", "training": "Weiterbildung", "tax": "Ertragsteuer", "energy": "Strom (Stadtwerke)",
}

var start_capital: float
var cash: float
var debt := 0.0
var deposits := 0.0       # Einlagen bei Banken (Vermoegen)
var payables := 0.0       # aufgelaufene, noch nicht gezahlte Loehne (Verbindlichkeit)
var receivables := 0.0    # Forderungen aus Krediten an andere Firmen (Vermoegen)
var totals := {}          # Kategorie -> Summe (vorzeichenbehaftet)
var cost_center := ""     # Standard-Kostenstelle (Betrieb "B<n>"), wenn eine Buchung keine nennt; "" = Unternehmen allgemein
var cc_totals := {}       # Kostenstelle -> {Kategorie -> Summe}; Summe ueber alle Kostenstellen = totals (keine zweite Buchung)
var entries: Array = []   # letzte Buchungen fuer die Anzeige
var history: Array = []   # [Spielminute, Gewinn, Bargeld]
var economy: Economy = null   # Gegenbuchungen (Geldkonservierung); null = unverbunden
var account := ""


const GENERAL := "allgemein"


## Erfolgsbuchung in Gesamt- und Kostenstellensumme (einzige Stelle, die totals veraendert).
func _add_total(category: String, amount: float, cc: String = "") -> void:
	totals[category] = totals.get(category, 0.0) + amount
	var center := cc if cc != "" else (cost_center if cost_center != "" else GENERAL)
	var row: Dictionary = cc_totals.get(center, {})
	row[category] = float(row.get(category, 0.0)) + amount
	cc_totals[center] = row


## Ergebnis einer Kostenstelle (Summe ihrer Buchungen).
func cc_profit(center: String) -> float:
	var p := 0.0
	for k in cc_totals.get(center, {}):
		p += float(cc_totals[center][k])
	return p


func cc_revenue(center: String) -> float:
	var r := 0.0
	var row: Dictionary = cc_totals.get(center, {})
	for k in row:
		if k in INCOME and float(row[k]) > 0.0:
			r += float(row[k])
	return r


func _init(capital: float = Catalog.START_CAPITAL) -> void:
	start_capital = capital
	cash = capital


## Erfolgswirksame Buchung. amount > 0 = Ertrag, < 0 = Aufwand.
## affects_cash = false fuer unbare Posten (Abschreibung, Buchgewinn/-verlust).
## cc: Kostenstelle (Betriebs-ID); leer = Standard-Kostenstelle der Company.
func book(category: String, amount: float, affects_cash: bool, note: String, time: float, counter: String = "", cc: String = "") -> void:
	if is_zero_approx(amount):
		return
	assert(LABELS.has(category), "Unbekannte Buchungskategorie: " + category)
	_add_total(category, amount, cc)
	if affects_cash:
		_move(amount, counter if counter != "" else Economy.COUNTER[category])
	# Laufende Kleinstbuchungen (Treibstoff, Loehne, ...) nicht einzeln protokollieren
	if absf(amount) >= 50.0 or category in ["transport", "penalties", "fines", "asset_result"]:
		entries.append({"t": time, "cat": category, "amount": amount, "note": note})
		if entries.size() > 150:
			entries.pop_front()


## Investition: Bargeld sinkt, Vermoegen (Buchwert) steigt -> kein Aufwand.
func invest(amount: float, counter: String = "S0") -> void:
	_move(-amount, counter)


## Erloes aus Anlagenabgang (Gegenbuchung des Buchgewinns/-verlusts erfolgt separat).
func divest(proceeds: float, counter: String = "S0") -> void:
	_move(proceeds, counter)


func borrow(amount: float, bank: String = "B1") -> void:
	_move(amount, bank)
	debt += amount


func repay(amount: float, bank: String = "B1") -> void:
	_move(-amount, bank)
	debt -= amount


func deposit_in(amount: float, bank: String) -> void:
	_move(-amount, bank)
	deposits += amount


func deposit_out(amount: float, bank: String) -> void:
	_move(amount, bank)
	deposits -= amount


## Schuld ohne Bargeld getilgt (Pfandverwertung: die Bank erhaelt den Erloes direkt).
func settle_debt(amount: float, _bank: String = "") -> void:
	debt -= amount


## Schuldenerlass: erzeugt keinen Gewinn, zaehlt wie eine Kapitalzufuehrung.
func forgive_debt(amount: float) -> void:
	debt -= amount
	start_capital += amount


## Kapitaleinlage von aussen (Startkapital-Aufstockung, Tests): erhoeht auch das Startkapital der Bilanzidentitaet.
func inject(amount: float) -> void:
	_move(amount, "I0")
	start_capital += amount


## Lohn laeuft auf (Aufwand sofort) und wird bezahlt, soweit Bargeld da ist. Der Rest bleibt als Lohnrueckstand stehen und wird bei
## naechster Gelegenheit zuerst beglichen. Gibt den tatsaechlich gezahlten Betrag zurueck (laufender Lohn plus beglichene Rueckstaende).
## by_cc: optionale Aufteilung des Lohnaufwands auf Kostenstellen {cc: Betrag}; Summe = amount, Rest geht an die Standard-Kostenstelle.
func accrue_wages(amount: float, time: float, by_cc: Dictionary = {}) -> float:
	if amount > 0.0:
		var rest := amount
		for cc in by_cc:
			var part := minf(float(by_cc[cc]), rest)
			if part > 0.0:
				_add_total("wages", -part, str(cc))
				rest -= part
		if rest > 1e-9:
			_add_total("wages", -rest)
		payables += amount
	var pay := minf(payables, maxf(cash, 0.0))
	if pay > 0.0:
		_move(-pay, "H0")
		payables -= pay
	return pay


## Rueckstaende gezielt zahlen (Insolvenzmasse) bzw. nach Verteilung erlassen (keine Gewinnwirkung).
func pay_payables(limit: float) -> float:
	var pay := minf(minf(payables, limit), maxf(cash, 0.0))
	if pay > 0.0:
		_move(-pay, "H0")
		payables -= pay
	return pay


func forgive_payables() -> float:
	var x := payables
	payables = 0.0
	start_capital += x
	return x


## Zahlung an ein anderes Firmenbuch (Auktion, Handel): beide Seiten bewegen sich gegenlaeufig, es entsteht kein Geld.
func pay_to(other: Ledger, amount: float) -> void:
	_move(-amount, "")
	other._move(amount, "")


## Kredit an eine andere Firma (Spielerkredit): Bargeld wandert zwischen den Firmenbuechern, Forderung beim Geber, Schuld beim Nehmer.
func lend_to(other: Ledger, amount: float) -> void:
	_move(-amount, "")
	other._move(amount, "")
	receivables += amount
	other.debt += amount


## Rate eines Spielerkredits: Tilgung mindert Forderung und Schuld, Zins ist Aufwand beim Nehmer und Ertrag beim Geber.
func receive_installment(from: Ledger, principal: float, interest: float, note: String, time: float) -> void:
	from._move(-(principal + interest), "")
	_move(principal + interest, "")
	from.debt -= principal
	receivables -= principal
	if interest > 0.0:
		from._add_total("interest", -interest)
		_add_total("interest_income", interest)
		if interest >= 50.0:
			from.entries.append({"t": time, "cat": "interest", "amount": -interest, "note": note})
			entries.append({"t": time, "cat": "interest_income", "amount": interest, "note": note})


## Privatvermoegen des Gruenders haftet (Einzelunternehmen): Kapitalzufuehrung aus dem Haushaltssektor.
func take_private(amount: float) -> void:
	_move(amount, "H0")
	start_capital += amount


## Ueberschuss nach Verwertung geht an die Eigentuemer (Haushalte bzw. Kapitalgeber).
func pay_out_owner(amount: float, counter: String) -> void:
	_move(-amount, counter)
	start_capital -= amount


## Einzige Stelle, die Bargeld aendert: Firma und Gegenkonto bewegen sich gegenlaeufig.
func _move(delta: float, counter: String) -> void:
	cash += delta
	if economy != null and counter != "":
		economy.post(counter, delta)


func profit() -> float:
	var p := 0.0
	for k in totals:
		p += totals[k]
	return p


func revenue() -> float:
	var r := 0.0
	for k in totals:
		if k in INCOME and totals[k] > 0.0:
			r += totals[k]
	return r


func costs() -> float:
	return revenue() - profit()


func sample(time: float) -> void:
	history.append([time, profit(), cash])
	if history.size() > 600:
		# Verlauf ausduennen statt abschneiden
		var thinned: Array = []
		for i in range(0, history.size(), 2):
			thinned.append(history[i])
		history = thinned


func to_dict() -> Dictionary:
	return {"start_capital": start_capital, "cash": cash, "debt": debt, "deposits": deposits, "payables": payables, "receivables": receivables, "totals": totals, "cost_center": cost_center, "cc_totals": cc_totals,
		"entries": entries, "history": history}


func from_dict(d: Dictionary) -> void:
	start_capital = d.start_capital
	cash = d.cash
	debt = d.debt
	deposits = float(d.get("deposits", 0.0))
	payables = float(d.get("payables", 0.0))
	receivables = float(d.get("receivables", 0.0))
	totals = d.totals
	cost_center = str(d.get("cost_center", ""))
	cc_totals = d.get("cc_totals", {})
	if cc_totals.is_empty() and not totals.is_empty():
		cc_totals[cost_center if cost_center != "" else GENERAL] = totals.duplicate()   # alter Spielstand: bisherige Summen der Standard-Kostenstelle
	entries = d.entries
	history = d.history
