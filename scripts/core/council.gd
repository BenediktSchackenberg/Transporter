class_name Council
extends RefCounted
## Gemeinderat (Auftrag 7, Etappe 3): drei Fraktionen stimmen ueber grosse Vorhaben ab. Die Abstimmung ist deterministisch und
## begruendet: jede Fraktion bewertet das Vorhaben nach ihren Zielen anhand der Stadtkennzahlen. Beschluesse binden die Buergermeisterin
## bzw. den Buergermeister; ohne Beschluss gibt es kein Geld und keine Ausweisung.

const SEATS := {"wachstum": 3, "soziales": 3, "haushalt": 3}
const LABELS := {"wachstum": "Fraktion Wachstum", "soziales": "Fraktion Soziales", "haushalt": "Fraktion Haushalt"}
const COST_LIMIT := 30000.0           # ab diesen Kosten muss der Rat zustimmen
const MAJORITY := 5


## Braucht das Vorhaben einen Ratsbeschluss? kind: quartier | erschliessung | strasse | oeffentlich_bau | ausschreibung
static func needs_vote(kind: String, cost: float) -> bool:
	return kind == "quartier" or cost > COST_LIMIT


## proposal: {kind, cost, units, area}; ind: Kennzahlen aus Mayor.indicators(). Ergebnis: {passed, yes, no, votes: {fraktion: {yes, text}}}
static func vote(proposal: Dictionary, ind: Dictionary) -> Dictionary:
	var cost := float(proposal.get("cost", 0.0))
	var units := int(proposal.get("units", 0))
	var housing: Dictionary = ind.get("wohnen", {})
	var money: Dictionary = ind.get("haushalt", {})
	var jobs: Dictionary = ind.get("arbeit", {})
	var waiting := int(housing.get("wohnungssuchende_haushalte", 0))
	var avail := float(money.get("verfuegbar", 0.0))
	var votes := {}
	# Wachstum: will Flaechen und Wohnraum, solange die Nachfrage besteht
	var pressure := waiting > 0 or float(housing.get("leerstand", 0.0)) < 0.03 or float(jobs.get("quote", 1.0)) < 0.75
	votes["wachstum"] = {"yes": pressure or str(proposal.get("kind", "")) in ["erschliessung", "strasse"],
		"text": "Nachfrage und Standortentwicklung rechtfertigen das Vorhaben." if pressure else "Es besteht derzeit kein erkennbarer Entwicklungsdruck."}
	# Soziales: will bezahlbaren Wohnraum und Arbeitsplaetze; skeptisch bei teuren Vorhaben ohne Wohnnutzen
	var social := units > 0 or waiting > 0 or float(housing.get("mietindex", 100.0)) > 110.0 or str(proposal.get("kind", "")) == "oeffentlich_bau"
	votes["soziales"] = {"yes": social, "text": "Das Vorhaben dient Wohnraum, Arbeit oder öffentlichen Einrichtungen." if social else "Kein erkennbarer Nutzen für Wohnen oder Arbeit."}
	# Haushalt: nur, wenn die Mittel ohne Schieflage reichen
	var affordable := cost <= avail * 0.6
	votes["haushalt"] = {"yes": affordable, "text": "Die Kosten von %s sind aus den verfügbaren Mitteln (%s) tragbar." % [Catalog.money(cost), Catalog.money(avail)] if affordable
		else "Die Kosten von %s übersteigen den tragbaren Rahmen (verfügbar %s)." % [Catalog.money(cost), Catalog.money(avail)]}
	var yes := 0
	for f in votes:
		if votes[f].yes:
			yes += int(SEATS[f])
	return {"passed": yes >= MAJORITY, "yes": yes, "no": 9 - yes, "votes": votes}


static func explain(r: Dictionary) -> String:
	var parts: Array = []
	for f in r.votes:
		parts.append("%s: %s – %s" % [LABELS[f], "dafür" if r.votes[f].yes else "dagegen", r.votes[f].text])
	return "Abstimmung %d:%d (%s). %s" % [int(r.yes), int(r.no), "beschlossen" if r.passed else "abgelehnt", " ".join(parts)]
