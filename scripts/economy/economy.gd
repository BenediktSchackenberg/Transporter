class_name Economy
extends RefCounted
## Konten ausserhalb der Firmen und Geldkonservierung.
##
## Jede Barbewegung einer Firma (Ledger) hat eine Gegenbuchung auf einem dieser Konten.
## Es entsteht und verschwindet kein Geld: Summe(Firmenbargeld) + Summe(Konten) == Anfangsbestand.
## Konten duerfen negativ werden (= Sektor hat netto mehr gezahlt als erhalten); das ist eine Kennzahl, kein Fehler.
##
## Konten: H0 Haushalte, P0 Oeffentliche Hand, X0 Ausland, S0 Dienstleister/Versicherer/Werkstaetten,
## B1 Geschaeftsbank, B2 Investitionsbank, B3 Handelsbank (Bargeld der Banken, siehe Banking), C0 Verrechnung zwischen Firmen (muss sich auf 0 ausgleichen),
## I0 Kapitalgeber (negativ = hat Kapital eingezahlt).

const SEED := {"H0": 300000.0, "P0": 200000.0, "X0": 200000.0, "S0": 100000.0, "B1": 400000.0, "B2": 600000.0, "B3": 300000.0, "T0": 120000.0, "G0": 80000.0, "C0": 0.0, "I0": 150000.0, "K0": 0.0, "D0": 140000.0}
const NAMES := {
	"H0": "Haushalte", "P0": "Öffentliche Hand", "X0": "Ausland", "S0": "Dienstleister",
	"B1": "Geschäftsbank", "B2": "Investitionsbank", "B3": "Handelsbank", "T0": "Bauhof (Großhandel)", "G0": "Tankstellenbetreiber", "C0": "Verrechnung zwischen Firmen", "I0": "Kapitalgeber", "K0": "Baufirmen", "D0": "Bauträger",
}
## Standardgegenkonto je Buchungskategorie (siehe Ledger.LABELS)
const COUNTER := {
	"transport": "H0", "trade_income": "C0", "trade_expense": "C0", "insurance_payout": "S0", "insurance": "S0",
	"compensation": "H0", "penalties": "H0", "fines": "P0", "wages": "H0", "hire_fees": "H0", "repairs": "S0",
	"rent": "H0", "rent_income": "H0", "interest": "B1", "interest_income": "B1", "fuel": "X0", "supplies": "S0", "security": "S0",
	"sabotage": "S0", "marketing": "S0", "office": "S0", "property_costs": "P0", "training": "S0",
	"admin": "P0", "tax": "P0", "depreciation": "", "asset_result": "",
}

var accounts := {}
var outflow := {}       # Konto -> Abfluesse im laufenden Spielmonat (fuer den Kreislauf der Haushalte)
var initial_total := 0.0
var _ledgers: Array = []


func _init() -> void:
	for k in SEED:
		accounts[k] = SEED[k]
		initial_total += SEED[k]


## Meldet ein Firmenbuch an; sein aktueller Bargeldbestand zaehlt zum Anfangsbestand.
func attach(ledger: Ledger, name: String) -> void:
	ledger.economy = self
	ledger.account = name
	_ledgers.append(ledger)
	initial_total += ledger.cash


func detach_all() -> void:
	_ledgers.clear()
	initial_total = 0.0
	for k in SEED:
		initial_total += SEED[k]


## Gegenbuchung: die Firma hat 'delta' Bargeld erhalten (>0) bzw. gezahlt (<0).
func post(counter: String, delta: float) -> void:
	assert(accounts.has(counter), "Unbekanntes Konto: " + counter)
	accounts[counter] -= delta
	if delta > 0.0:
		outflow[counter] = float(outflow.get(counter, 0.0)) + delta


## Zahlung zwischen zwei Konten ausserhalb der Firmen.
func transfer(from_acct: String, to_acct: String, amount: float) -> void:
	accounts[from_acct] -= amount
	accounts[to_acct] += amount
	outflow[from_acct] = float(outflow.get(from_acct, 0.0)) + amount


## Abfluesse des Kontos im abgelaufenen Monat holen und zuruecksetzen.
func take_outflow(acct: String) -> float:
	var v := float(outflow.get(acct, 0.0))
	outflow[acct] = 0.0
	return v


func total() -> float:
	var t := 0.0
	for l in _ledgers:
		t += l.cash
	for k in accounts:
		t += accounts[k]
	return t


## Abweichung von der Geldkonservierung (soll 0 sein).
func conservation_error() -> float:
	return total() - initial_total


func to_dict() -> Dictionary:
	return {"accounts": accounts, "initial_total": initial_total, "outflow": outflow}


func from_dict(d: Dictionary) -> void:
	for k in d.get("accounts", {}):
		accounts[k] = float(d.accounts[k])
	initial_total = float(d.get("initial_total", initial_total))
	outflow = d.get("outflow", {})
