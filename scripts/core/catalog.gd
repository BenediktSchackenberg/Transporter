class_name Catalog
## Alle Spielkonstanten an einer Stelle (Wirtschaft, Fahrzeuge, Waren, Zeit).

## Zeitmodell: 1 Sim-Sekunde = 2 Spielminuten. Bei 1x laeuft 1 Sim-Sekunde pro Echtzeitsekunde.
const GAME_MIN_PER_SIM_SEC := 2.0
const START_HOUR := 6
## Partiedauer in aktiven Echtzeitminuten (0 = Endlosmodus). Eine Partie zaehlt nur aktive (nicht pausierte) Echtzeit.
const DURATION_OPTIONS := [240, 720, 1440, 0]
const MAP_SIZE := 256

const START_CAPITAL := 150000.0   # traegt die Startbelegschaft von 10 Mitarbeitern
const VEHICLES_PER_DEPOT := 4
const DEPOT_STORAGE := 60           # Lagerplaetze (Einheiten) je Depot fuer Zwischenlagerung
const MAX_EXTRA_DEPOTS := 3

## Abschreibung: linear 2 % des Kaufpreises pro Spieltag, bis auf 20 % Restwert.
const DEPRECIATION_PER_DAY := 0.02
const RESIDUAL_SHARE := 0.2
## Haendler kauft zu 85 % des Buchwerts zurueck.
const DEALER_BUYBACK := 0.85

const DRIVER_BASE_WAGE := 14.0          # EUR pro Spielstunde
const HIRE_FEE := 400.0                 # Vermittlungsgebuehr
const POACH_FEE := 600.0

const EXTRA_DEPOT_RENT := 350.0

const LOAN_BASE_LIMIT := 40000.0
const LOAN_INTEREST_PER_DAY := 0.012
const OVERDRAFT_INTEREST_PER_DAY := 0.03

const LOADING_MIN := 12.0               # Spielminuten fuer Be- oder Entladen
const REPAIR_MIN := 25.0
const REPAIR_COST_PER_POINT := 0.0008   # Anteil Kaufpreis pro Zustandspunkt
const BREAKDOWN_THRESHOLD := 30.0
const TOW_FEE := 400.0

const LATE_PENALTY_PER_HOUR := 0.25     # Verguetung sinkt pro angefangener Stunde Verspaetung
const FAIL_AFTER_HOURS := 4.0           # danach gilt der Auftrag als gescheitert
const FAIL_PENALTY_SHARE := 0.3         # Vertragsstrafe in Anteil der Verguetung

const SECURITY_INSTALL := [0.0, 1500.0, 3000.0]
const SECURITY_PER_DAY := [0.0, 300.0, 700.0]
const INSURANCE_PER_DAY := 600.0

const SABOTAGE := {
	"depot_disruption": {"name": "Betriebsstörung", "cost": 2500.0, "duration_min": 90.0,
		"success": 0.85, "detect": 0.35, "fine": 3000.0, "compensation": 2000.0, "rep_loss": 15.0,
		"insurance_payout": 1500.0, "visit": true},
	"smear_campaign": {"name": "Rufschädigung", "cost": 1500.0, "rep_damage": 8.0,
		"success": 0.65, "detect": 0.3, "fine": 1500.0, "compensation": 1000.0, "rep_loss": 12.0,
		"insurance_payout": 800.0, "visit": false},
}
const SABOTAGE_COOLDOWN_MIN := 360.0    # pro Saboteur
const SABOTAGE_PROTECTION_MIN := 240.0  # Schutzfrist pro Opfer
const PACT_BREACH_REP := 10.0

const MESSAGES_PER_HOUR := 6
const CONVERSATION_ROUNDS := 8          # Nachrichten zwischen zwei Firmen pro 2 Spielstunden
const MAX_OPEN_OFFERS := 3
const OFFER_EXPIRY_MIN := 360.0          # lang genug, damit der Empfaenger auch bei hoher Geschwindigkeit reagieren kann

const VEHICLE_MODELS := {
	"cargobike": {"name": "Lastenrad", "price": 2500.0, "capacity": 3, "speed": 2.2,
		"cost_per_tile": 0.1, "wear": 0.015, "refrigerated": false, "heavy": false},
	"van": {"name": "Kleintransporter", "price": 12000.0, "capacity": 8, "speed": 2.8,
		"cost_per_tile": 0.6, "wear": 0.025, "refrigerated": false, "heavy": false},
	"transporter": {"name": "Lieferwagen", "price": 22000.0, "capacity": 18, "speed": 2.5,
		"cost_per_tile": 0.85, "wear": 0.022, "refrigerated": false, "heavy": false},
	"reefer": {"name": "Kühltransporter", "price": 32000.0, "capacity": 14, "speed": 2.4,
		"cost_per_tile": 1.1, "wear": 0.025, "refrigerated": true, "heavy": false},
	"truck": {"name": "LKW 12t", "price": 46000.0, "capacity": 40, "speed": 2.1,
		"cost_per_tile": 1.5, "wear": 0.02, "refrigerated": false, "heavy": true},
	"semi": {"name": "Sattelzug", "price": 80000.0, "capacity": 80, "speed": 1.8,
		"cost_per_tile": 2.3, "wear": 0.018, "refrigerated": false, "heavy": true},
}

## value: Verguetungsfaktor; refrigerated/heavy: Fahrzeugvoraussetzung (heavy ab heavy_from Einheiten)
const CARGO := {
	"pakete": {"name": "Pakete", "value": 1.0, "refrigerated": false, "heavy_from": 999},
	"lebensmittel": {"name": "Lebensmittel (gekühlt)", "value": 1.25, "refrigerated": true, "heavy_from": 999},
	"medikamente": {"name": "Medikamente (gekühlt)", "value": 1.6, "refrigerated": true, "heavy_from": 999},
	"getraenke": {"name": "Getränke", "value": 0.9, "refrigerated": false, "heavy_from": 30},
	"elektronik": {"name": "Elektronik", "value": 1.4, "refrigerated": false, "heavy_from": 999},
	"moebel": {"name": "Möbel", "value": 1.1, "refrigerated": false, "heavy_from": 25},
	"baustoffe": {"name": "Baustoffe", "value": 0.85, "refrigerated": false, "heavy_from": 15},
	"maschinenteile": {"name": "Maschinenteile", "value": 1.3, "refrigerated": false, "heavy_from": 15},
	"container": {"name": "Container", "value": 1.0, "refrigerated": false, "heavy_from": 1},
}

## Bueros: erstes Buero = Zentrale (Stufe 1). Gleichzeitig laufende Auftraege (angenommen bis unterwegs)
## sind begrenzt auf 3 + 3 je Zentralenstufe + 2 je Filiale. Bueros sind Investitionen (1 %/Tag Abschreibung).
const OFFICE_HQ_COST := 4500.0
const OFFICE_BRANCH_COST := 6000.0          # +3000 je weitere Filiale
const OFFICE_UPGRADE_COST := [0.0, 6000.0, 10500.0]   # Stufe 1->2, 2->3
const OFFICE_PER_DAY := 120.0
const PROPERTY_DEPRECIATION_PER_DAY := 0.01
## Internet: Stufe 1 = Auftraege im eigenen Buero sammeln, Stufe 2 = von ueberall
const INTERNET_COST := [2500.0, 4500.0]
const INTERNET_PER_DAY := [0.0, 150.0, 300.0]
const TALK_DISTANCE := 96.0                 # Pixel: oeffentliche Ansprache nur bei Begegnung

## Konkrete Lieferketten: [Quelle (Typ|Namensanfang), Ziel (Typ|Namensanfang), Bezeichnung, Warenkategorie, Menge min, max]
const CHAINS := [
	["factory|Brauerei", "restaurant|", "Bierfässer", "getraenke", 4, 14],
	["factory|Brauerei", "shop|Getränkemarkt", "Bierkisten", "getraenke", 6, 18],
	["farm|", "restaurant|", "Frisches Gemüse", "lebensmittel", 3, 10],
	["farm|", "shop|Supermarkt", "Obstkisten", "lebensmittel", 5, 14],
	["factory|Maschinenbau", "construction|", "Maschinenteile", "maschinenteile", 9, 20],
	["port_office|", "shop|Möbelhaus", "Importmöbel", "moebel", 7, 18],
	["warehouse|Druckerei", "shop|Buchhandlung", "Bücherkartons", "pakete", 3, 12],
	["warehouse|Recyclinghof", "construction|", "Baustoffe", "baustoffe", 8, 18],
	["warehouse|Lager", "clinic|", "Medizinische Geräte", "elektronik", 2, 8],
	["pharmacy|", "clinic|", "Medikamente", "medikamente", 2, 7],
	["shop|Bäckerei", "restaurant|", "Backwaren", "pakete", 2, 8],
	["shipyard|", "factory|Maschinenbau", "Stahlteile", "maschinenteile", 10, 20],
	["shop|Möbelhaus", "school|", "Schulmöbel", "moebel", 8, 20],
	["farm|", "kindergarten|", "Frischkost für die Kita", "lebensmittel", 4, 10],
	["airport_cargo|", "warehouse|Lager", "Luftfracht-Container", "container", 2, 6],
	["airport_cargo|", "office|", "Luftfracht-Elektronik", "elektronik", 3, 8],
	["warehouse|Lager", "airport_cargo|", "Weitertransport Luftfracht", "pakete", 4, 14],
]

const DISTRICTS := ["Innenstadt", "Wohnviertel", "Industriegebiet", "Hafen", "Gewerbegebiet", "Randbezirk"]

const PERSONALITIES := {
	"kostenoptimierer": {"name": "Vorsichtiger Kostenoptimierer",
		"prompt": "Du bist vorsichtig und rechnest genau. Du vermeidest Schulden, achtest auf Auslastung und Wartung und gehst selten Risiken ein. Sprache: sachlich, knapp, hanseatisch."},
	"wachstum": {"name": "Aggressiver Wachstumsstratege",
		"prompt": "Du willst schnell wachsen: mehr Fahrzeuge, mehr Depots, große Aufträge. Du nimmst kalkulierte Kredite auf und machst Konkurrenten Druck. Sprache: selbstbewusst, zupackend."},
	"netzwerker": {"name": "Diplomatischer Netzwerker",
		"prompt": "Du setzt auf Kooperation, faire Geschäfte und Vertrauen. Du teilst Aufträge, schließt Pakte und reagierst auf Sabotage mit Diplomatie, aber nicht naiv. Sprache: freundlich, verbindlich."},
	"risikospieler": {"name": "Opportunistischer Risikospieler",
		"prompt": "Du nutzt jede Gelegenheit, auch riskante: Bluffs, Abwerbung, gelegentliche Sabotage, wenn sie sich lohnt. Sprache: frech, provokant, mit Humor."},
}

const COMPANY_COLORS := [Color("#e04a3a"), Color("#3a8fe0"), Color("#3ac06a"), Color("#e0b020"),
	Color("#b05ae0"), Color("#20c0c0")]
const COLOR_NAMES := ["Rot", "Blau", "Grün", "Gelb", "Violett", "Türkis"]
const AVATAR_COUNT := 6


static func model(id: String) -> Dictionary:
	return VEHICLE_MODELS.get(id, {})


## Zeitstempel fuer Protokolle und Anzeigen: "M3 T12 14:30" (Spielkalender + Uhrzeit der Stadt).
static func game_minutes_to_text(m: float) -> String:
	return GameCalendar.log_text(m)


## Kurzform "T12 14:30" fuer enge Listen.
static func game_time_short(m: float) -> String:
	return GameCalendar.short_text(m)


static func hour_of_day(m: float) -> float:
	return GameCalendar.hour_of(m)


static func money(v: float) -> String:
	var neg := v < 0.0
	var s := str(int(round(absf(v))))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out + " EUR"
