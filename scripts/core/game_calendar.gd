class_name GameCalendar
extends RefCounted
## Spielkalender. Alle Funktionen rechnen aus der Logistikuhr (game_min = Spielminuten, 1 Sim-Sekunde = 2 Spielminuten).
## 1 Spieltag = day_seconds Sim-Sekunden (Standard 60 = eine aktive Echtzeitminute bei 1x), 1 Monat = 30 Tage, 1 Jahr = 12 Monate.
## Die Uhrzeit der Stadt (Tageslicht, Oeffnungszeiten) folgt dem Spieltag: ein Spieltag = ein Tag-Nacht-Zyklus.
## Pausen halten die Simulation und damit den Kalender an. Die Wetterzeit ist reale Zeit und davon getrennt.

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const DEFAULT_DAY_SECONDS := 60.0

static var day_seconds := DEFAULT_DAY_SECONDS
static var day_game_min := DEFAULT_DAY_SECONDS * Catalog.GAME_MIN_PER_SIM_SEC


static func configure(seconds: float) -> void:
	day_seconds = clampf(seconds, 5.0, 3600.0)
	day_game_min = day_seconds * Catalog.GAME_MIN_PER_SIM_SEC


## Absoluter Spieltag (0 = erster Tag).
static func day_of(m: float) -> int:
	return int(floor(maxf(0.0, m) / day_game_min))


## Absoluter Spielmonat (0 = erster Monat).
static func month_of(m: float) -> int:
	return day_of(m) / DAYS_PER_MONTH


static func year_of(m: float) -> int:
	return month_of(m) / MONTHS_PER_YEAR


## {jahr, monat, tag} jeweils ab 1.
static func parts(m: float) -> Dictionary:
	var d := day_of(m)
	var mo := d / DAYS_PER_MONTH
	return {"jahr": mo / MONTHS_PER_YEAR + 1, "monat": mo % MONTHS_PER_YEAR + 1, "tag": d % DAYS_PER_MONTH + 1}


## Spielminute (Logistikuhr) des Beginns eines absoluten Tages bzw. Monats.
static func day_start(day: int) -> float:
	return float(day) * day_game_min


static func month_start(month: int) -> float:
	return float(month * DAYS_PER_MONTH) * day_game_min


static func days_to_min(days: float) -> float:
	return days * day_game_min


static func months_to_min(months: float) -> float:
	return months * float(DAYS_PER_MONTH) * day_game_min


## Spieltage bis zum Monatsende (heutiger Tag zaehlt nicht mehr mit).
static func days_left_in_month(m: float) -> int:
	return DAYS_PER_MONTH - 1 - (day_of(m) % DAYS_PER_MONTH)


## Uhrzeit der Stadt in Stunden (0..24): ein Spieltag = ein Tag-Nacht-Zyklus, Start um 6 Uhr morgens.
static func hour_of(m: float) -> float:
	return fmod(Catalog.START_HOUR + 24.0 * fmod(maxf(0.0, m), day_game_min) / day_game_min, 24.0)


static func clock_text(m: float) -> String:
	var h := hour_of(m)
	return "%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)]


## "Jahr 1 · Monat 3 · Tag 12 · 14:30"
static func long_text(m: float) -> String:
	var p := parts(m)
	return "Jahr %d · Monat %d · Tag %d · %s" % [p.jahr, p.monat, p.tag, clock_text(m)]


## "M3 T12 14:30" (ab Jahr 2: "J2 M3 T12 14:30") fuer Protokolle.
static func log_text(m: float) -> String:
	var p := parts(m)
	return "%sM%d T%d %s" % ["J%d " % p.jahr if p.jahr > 1 else "", p.monat, p.tag, clock_text(m)]


## "T12 14:30" fuer enge Listen.
static func short_text(m: float) -> String:
	return "T%d %s" % [parts(m).tag, clock_text(m)]


## Erklaerung der Zeituebersetzung fuer die Oberflaeche (speed = aktuelle Simulationsgeschwindigkeit).
static func explain(speed: float) -> String:
	var s := day_seconds / maxf(speed, 0.001)
	return "1 Spieltag = %.0f s aktive Echtzeit bei 1× (bei %.0f× nur %.1f s) · 1 Monat = 30 Tage = %.0f min bei 1× · 1 Jahr = 12 Monate = %.1f h bei 1×. Pausen halten den Kalender an. Das Wetter folgt der realen Uhr." % [
		day_seconds, speed, s, day_seconds * 30.0 / 60.0, day_seconds * 360.0 / 3600.0]
