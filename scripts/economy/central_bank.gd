class_name CentralBank
extends RefCounted
## Zentralbank, Leitzins und Geldmengenkennzahlen (Auftrag 4, Rest: B1-B3, siehe docs/HOUSING_AND_MONEY.md).
##
## Konto Z0 darf negativ werden: Ein negatives Z0 ist ausgegebenes Zentralbankgeld (Refinanzierung der Banken), die Summe aller Konten
## und damit die Geldkonservierung bleiben unberuehrt. Banken, deren Bargeld unter die Mindestreserve (Reservequote x Einlagen) faellt,
## leihen bei Z0 bis zu REFI_LIMIT ihres Eigenkapitals, zahlen dafuer den Leitzins und tilgen, sobald sie wieder reichlich Reserve haben.
## Der Leitzins folgt dem Preisindex (Kraftstoff, Waren, Wohnen) und der Beschaeftigung; der Referenzzins der Banken (Banking.ref_rate)
## richtet sich nach ihm.

const ACCOUNT := "Z0"
const REAL_RATE := 0.01            # Realzins bei Preisstabilitaet und Zielbeschaeftigung
const TARGET := 0.02               # Inflationsziel pro Jahr
const EMPLOYMENT_TARGET := 0.8
const STEP := 0.0025               # hoechste Zinsaenderung je Monat
const MIN_RATE := 0.0025
const MAX_RATE := 0.12
const REFI_LIMIT := 0.5            # Anteil des Eigenkapitals einer Bank, der als Zentralbankkredit moeglich ist
const WEIGHTS := {"kraftstoff": 0.2, "waren": 0.45, "wohnen": 0.35}

var sim: Simulation
var policy_rate := 0.02
var refi := {}                     # Bank-ID -> offener Zentralbankkredit
var created_total := 0.0           # insgesamt ausgegebenes Zentralbankgeld (kumuliert)
var cpi := 100.0                   # Preisindex
var cpi_history: Array = []        # Monatsendwerte
var inflation := 0.0               # geglaettet, pro Jahr
var interest_total := 0.0


func setup(s: Simulation) -> void:
	sim = s
	for b in Banking.BANKS:
		refi[b.id] = 0.0
	s.month_changed.connect(on_month)


# ------------------------------------------------------------------ Liquiditaet der Banken
func required(i: int) -> float:
	return sim.banking.reserve_ratio * sim.banking.deposits_of_bank(i)


## Wie viel die Bank noch bei der Zentralbank leihen koennte.
func headroom(i: int) -> float:
	return maxf(0.0, REFI_LIMIT * maxf(sim.banking.equity(i), 0.0) - float(refi[Banking.BANKS[i].id]))


## Vor einer Auszahlung `amount`: Fehlt der Bank danach Reserve, leiht sie bis zur Grenze bei Z0. Gibt das Geliehene zurueck.
func ensure(i: int, amount: float) -> float:
	var short := amount + required(i) - sim.banking.bank_cash(i)
	return _draw(i, minf(short, headroom(i))) if short > 0.0 else 0.0


func _draw(i: int, x: float) -> float:
	if x <= 0.0:
		return 0.0
	var id: String = Banking.BANKS[i].id
	sim.economy.transfer(ACCOUNT, id, x)
	refi[id] = float(refi[id]) + x
	created_total += x
	return x


func _repay(i: int, x: float) -> void:
	var id: String = Banking.BANKS[i].id
	x = minf(x, float(refi[id]))
	if x <= 0.0:
		return
	sim.economy.transfer(id, ACCOUNT, x)
	refi[id] = float(refi[id]) - x
	created_total -= x


# ------------------------------------------------------------------ Preisindex und Zins
func price_index() -> float:
	var fuel := 0.0
	for k in sim.fuel.ref:
		fuel += float(sim.fuel.ref[k]) / maxf(0.01, float(FuelPrices.DEFAULT_REF[k]))
	fuel /= maxf(1.0, float(sim.fuel.ref.size()))
	var goods := 0.0
	var n := 0
	for shop in sim.retail.shops.values():
		goods += float(shop.price_factor)
		n += 1
	goods = goods / n if n > 0 else 1.0
	return 100.0 * (WEIGHTS.kraftstoff * fuel + WEIGHTS.waren * goods + WEIGHTS.wohnen * sim.housing.index)


func on_month(_month: int) -> void:
	cpi = price_index()
	if not cpi_history.is_empty():
		var m: float = cpi / float(cpi_history[-1]) - 1.0
		inflation = 0.7 * inflation + 0.3 * (pow(1.0 + m, 12.0) - 1.0)
	cpi_history.append(cpi)
	var target := REAL_RATE + inflation + 0.5 * (inflation - TARGET) + 0.5 * (sim.citizens.employment_rate() - EMPLOYMENT_TARGET)
	policy_rate = clampf(clampf(target, MIN_RATE, MAX_RATE), policy_rate - STEP, policy_rate + STEP)
	for i in Banking.BANKS.size():
		var id: String = Banking.BANKS[i].id
		var interest := minf(float(refi[id]) * policy_rate / 12.0, maxf(0.0, sim.banking.bank_cash(i)))
		if interest > 0.0:
			sim.economy.transfer(id, ACCOUNT, interest)
			interest_total += interest
		var req := required(i)
		var cash := sim.banking.bank_cash(i)
		if cash < req:
			_draw(i, minf(req * 1.1 - cash, headroom(i)))
		elif float(refi[id]) > 0.0 and cash > req * 1.5 + 1.0:
			_repay(i, cash - req * 1.25)


# ------------------------------------------------------------------ Kennzahlen
## Zahlungsmittel der Nichtbanken: Firmenbargeld und alle Sektorkonten ausser Banken, Zentralbank, Ausland und Kapitalgeber.
func money_supply() -> float:
	var t := 0.0
	for c in sim.companies:
		t += c.ledger.cash
	for k in sim.economy.accounts:
		if k not in ["B1", "B2", "B3", ACCOUNT, "X0", "I0"]:
			t += float(sim.economy.accounts[k])
	return t


func credit_volume() -> float:
	var t := 0.0
	for i in Banking.BANKS.size():
		t += sim.banking.loans_of_bank(i)
	return t


func household_debt() -> float:
	var t := 0.0
	for m in sim.banking.mortgages.values():
		if m.status in ["laufend", "rueckstand"]:
			t += float(m.outstanding)
	return t


func company_debt() -> float:
	var t := 0.0
	for c in sim.companies:
		t += c.ledger.debt
	return t


## Bilanz einer Bank: Aktiva (Bargeld/Reserve, Kredite) und Passiva (Einlagen, Zentralbankkredit, Eigenkapital).
func balance_sheet(i: int) -> Dictionary:
	var B: Banking = sim.banking
	var id: String = Banking.BANKS[i].id
	var assets := B.bank_cash(i) + B.loans_of_bank(i)
	var deposits := B.deposits_of_bank(i)
	return {"bank": Banking.BANKS[i].name, "reserve": B.bank_cash(i), "kredite": B.loans_of_bank(i), "aktiva": assets, "einlagen": deposits,
		"zentralbankkredit": float(refi[id]), "eigenkapital": assets - deposits - float(refi[id])}


func summary() -> Dictionary:
	return {"leitzins": policy_rate, "inflation": inflation, "preisindex": cpi, "geldmenge": money_supply(), "kreditvolumen": credit_volume(),
		"haushaltsschulden": household_debt(), "firmenschulden": company_debt(), "zentralbankgeld": created_total, "zinsertrag": interest_total}


func to_dict() -> Dictionary:
	return {"policy_rate": policy_rate, "refi": refi, "created_total": created_total, "cpi": cpi, "cpi_history": cpi_history, "inflation": inflation, "interest_total": interest_total}


func from_dict(d: Dictionary) -> void:
	policy_rate = float(d.get("policy_rate", policy_rate))
	refi = d.get("refi", refi)
	for b in Banking.BANKS:
		refi[b.id] = float(refi.get(b.id, 0.0))
	created_total = float(d.get("created_total", 0.0))
	cpi = float(d.get("cpi", 100.0))
	cpi_history = d.get("cpi_history", [])
	inflation = float(d.get("inflation", 0.0))
	interest_total = float(d.get("interest_total", 0.0))
