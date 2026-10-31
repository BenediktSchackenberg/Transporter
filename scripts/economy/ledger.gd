class_name Ledger
extends RefCounted
## Finanzbuchhaltung einer Firma.
##
## Gewinn (Punktestand) = Summe aller Erfolgsbuchungen (Erloese positiv, Aufwand negativ).
## Bilanzidentitaet, die jederzeit gilt und getestet wird:
##   Bargeld + Buchwert (Fahrzeuge + Bueros) - Schulden == Startkapital + Gewinn
## Startkapital, Kredite, Tilgung, Fahrzeug- und Buerokaeufe sind keine Erfolgsbuchungen.

const INCOME := ["transport", "trade_income", "insurance_payout", "compensation", "asset_result", "rent_income", "interest_income"]
const LABELS := {
	"transport": "Transporterlöse", "trade_income": "Erlöse aus Geschäften", "insurance_payout": "Versicherungsleistungen",
	"compensation": "Schadensersatz erhalten", "asset_result": "Ergebnis Fahrzeugverkauf", "fuel": "Treibstoff",
	"wages": "Löhne", "hire_fees": "Einstellungs-/Abwerbegebühren", "repairs": "Reparaturen & Abschleppen",
	"rent": "Miete", "depreciation": "Abschreibungen", "interest": "Zinsen", "penalties": "Vertragsstrafen",
	"sabotage": "Sabotagekosten", "fines": "Bußgelder & Schadensersatz", "security": "Sicherheitsdienst",
	"insurance": "Versicherungsprämien", "trade_expense": "Zahlungen an Konkurrenten", "marketing": "Marketing",
	"office": "Büros & Internet", "supplies": "Betriebsmittel (Treibstoff, Ersatzteile)",
	"rent_income": "Mieteinnahmen", "interest_income": "Zinserträge", "admin": "Verwaltung & Berichtspflicht", "property_costs": "Gelände- und Gebäudekosten", "training": "Weiterbildung", "tax": "Ertragsteuer",
}

var start_capital: float
var cash: float
var debt := 0.0
var deposits := 0.0       # Einlagen bei Banken (Vermoegen)
var payables := 0.0       # aufgelaufene, noch nicht gezahlte Loehne (Verbindlichkeit)
var receivables := 0.0    # Forderungen aus Krediten an andere Firmen (Vermoegen)
var totals := {}          # Kategorie -> Summe (vorzeichenbehaftet)
var entries: Array = []   # letzte Buchungen fuer die Anzeige
var history: Array = []   # [Spielminute, Gewinn, Bargeld]
var economy: Economy = null   # Gegenbuchungen (Geldkonservierung); null = unverbunden
var account := ""


func _init(capital: float = Catalog.START_CAPITAL) -> void:
	start_capital = capital
	cash = capital


## Erfolgswirksame Buchung. amount > 0 = Ertrag, < 0 = Aufwand.
## affects_cash = false fuer unbare Posten (Abschreibung, Buchgewinn/-verlust).
func book(category: String, amount: float, affects_cash: bool, note: String, time: float, counter: String = "") -> void:
	if is_zero_approx(amount):
		return
	assert(LABELS.has(category), "Unbekannte Buchungskategorie: " + category)
	totals[category] = totals.get(category, 0.0) + amount
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
func accrue_wages(amount: float, time: float) -> float:
	if amount > 0.0:
		totals["wages"] = totals.get("wages", 0.0) - amount
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
		from.totals["interest"] = from.totals.get("interest", 0.0) - interest
		totals["interest_income"] = totals.get("interest_income", 0.0) + interest
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
	return {"start_capital": start_capital, "cash": cash, "debt": debt, "deposits": deposits, "payables": payables, "receivables": receivables, "totals": totals,
		"entries": entries, "history": history}


func from_dict(d: Dictionary) -> void:
	start_capital = d.start_capital
	cash = d.cash
	debt = d.debt
	deposits = float(d.get("deposits", 0.0))
	payables = float(d.get("payables", 0.0))
	receivables = float(d.get("receivables", 0.0))
	totals = d.totals
	entries = d.entries
	history = d.history
