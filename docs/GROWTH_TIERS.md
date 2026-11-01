# Auftrag 8: Wohnstufen und Bedürfnisse (Anno-Prinzip, Transport als Kern)

Stand: 01.11.2026. Code: `scripts/economy/tiers.gd` (`Tiers`, `sim.tiers`), Tests: `test_tiers`.

## Idee
Jede belegte Wohneinheit hat eine **Stufe 1-4** (Einfache Haushalte, Familien, Bürger, Wohlhabende). Mit der Stufe wachsen die Ansprüche.
Ob sie gedeckt sind, hängt von den **Geschäften im Viertel** ab, und deren Regale füllen **Transportaufträge** (Retail → Großhandel).
So wird Versorgung zum Transportbedarf der Spediteure, und der Aufstieg eines Viertels ist das Spielziel dahinter.

## Bedürfnisse
| Stufe | Bedürfnis | Gedeckt durch | Ware |
|---|---|---|---|
| 1 | Grundnahrung | Lebensmittelgeschäft, Bäckerei | lebensmittel |
| 1 | Getränke | Getränkemarkt, Lebensmittelgeschäft | getraenke |
| 2 | Haushaltswaren | Drogerie, Baumarkt | pakete |
| 2 | Gesundheit | Klinik, Apotheke (Gebäude im Viertel) | medikamente |
| 2 | Bildung und Betreuung | Schule, Kindergarten (Gebäude) | – |
| 3 | Gastronomie | Restaurant | lebensmittel |
| 3 | Möbel und Einrichtung | Möbelgeschäft | moebel |
| 4 | Technik | Technikgeschäft | elektronik |

**Deckung** (0-1) je Viertel und Bedürfnis: bestes passendes Geschäft im Viertel (voll) oder außerhalb (60 %). Der Versorgungsgrad eines Geschäfts
ist verkaufte Kunden / (verkaufte + entgangene) seit dem letzten Monatswechsel, ein Geschäft mit leerem Regal deckt also schlecht.

## Regeln
- **Aufstieg:** alle Bedürfnisse bis zur nächsten Stufe zu mindestens 75 % gedeckt, Zufriedenheit der Wohnung mindestens 50, zwei Monate in Folge, das Gebäude erlaubt die Stufe (Apartment/Haus/Doppelhaus bis 3, Hochhaus und Villa bis 4).
- **Abstieg:** ein Bedürfnis der eigenen Stufe drei Monate unter 40 %.
- **Start:** Stufe 2 (Villa 3), 30 % der Haushalte starten gehoben.
- **Miete:** ±15 % je Stufe um Stufe 2. **Konsum** und Wunschhäufigkeit der Kundenfiguren: ±10 % je Stufe.
- **Nachfrage nach gehobenen Geschäften** (Restaurant, Möbel: ab Stufe 3, Technik: ab Stufe 4) folgt dem Anteil dieser Stufen im Viertel (Faktor 0,75 bis 1,35).
- **Marktzutritt:** fehlt in einem Viertel mit mindestens 60 Bewohnern jedes Geschäft einer benötigten Art, eröffnet dort monatlich höchstens ein neues Geschäft in einem leeren Ladengebäude.

## Sichtbarkeit
- Ansicht „Wohnen“: Block „Wohnstufen“ mit Verteilung je Viertel und unversorgten Bedürfnissen samt Ware.
- Ereignisse: „Viertel: n Haushalte steigen auf / sinken ab (…)“ und „Neues Geschäft …“.
- KI-Beobachtung: `bevoelkerung` (Stufenmittel, Viertel mit Mangel und welche Bedürfnisse).

## Versorgungsbau (Etappe 2)
Fehlt ein Bedürfnis in einem Viertel (mindestens 60 Bewohner) zwei Monate lang ganz, und gibt es kein leeres Ladengebäude mehr, baut der **Bautraeger (D0)** auf einem freien
städtischen Grundstück des Viertels: Supermarkt/Bäckerei, Getränkemarkt, Drogerie, Restaurant, Möbelhaus, Technik-Fachmarkt, Klinik oder Schule
(Gebäudedefinitionen in `Planning.DEFS`, Zone Wohnen/Misch/Gewerbe). Ablauf wie jedes Bauvorhaben (Antrag, Genehmigung, Angebote, Bau, Übergabe). Nach der Übergabe
eröffnet bei Läden automatisch ein Geschäft (`Retail.on_building_added`); dessen Miete geht an den Bautraeger statt an die Stadt, so trägt sich das Programm.
Ein beantragter Bau wird acht Monate lang nicht doppelt geplant.

## Versorgungsprämie (Etappe 3)
Bestellt ein unterversorgtes Geschäft (Versorgungsgrad unter 75 %) Nachschub, trägt der Transportauftrag eine **Prämie der Stadt** (50 % der Fracht, höchstens 300 EUR),
sichtbar im Auftragstext und als `praemie_stadt` in der KI-Beobachtung. Bezahlt wird bei Lieferung aus der Stadtkasse (Kategorie `subsidy`), höchstens 3000 EUR im
Monat und nur oberhalb der Mindestreserve der Stadtkasse. Die Regel-KI rechnet die Prämie in ihren Gewinn ein.

## Freischaltungen und Meilensteine (Etappe 4)
- **Freischaltungen** nach Stadtmittel der Wohnstufen: Stadtvilla ab 2,5, Hochhaus ab 3,0. Anträge auf gesperrte Gebäude lehnt `Permits.draft` mit Begründung ab; der Bautraeger baut ab 2,5 jeden dritten Wohnbau als Stadtvilla.
- **Meilensteine** (Ansicht „Wohnen“, Ereignisliste): alle bewohnten Viertel bis Stufe 2 versorgt · Stadtmittel 2,5 · Stadtmittel 3,0 · 100 Bewohner auf Stufe 4 · 5 neue Geschäfte · erste Stadtvilla freigeschaltet.

## Grenzen / nächste Schritte
- Läden in Vierteln ohne freies Grundstück passender Größe oder ohne Mittel des Bautraegers entstehen nicht (im Probelauf blieb eine Lücke für einen Supermarkt im Randbezirk bestehen).
- Kliniken und Schulen baut ebenfalls der Bautraeger (privat); eine öffentliche Trägerschaft über die Stadtkasse ist nicht umgesetzt.
- Die Prämie wurde im 36-Monats-Probelauf nie ausgelöst, weil Regale selten leer waren; sie greift erst bei echtem Mangel.
- Balance: 36 Monate Probelauf (kleine Karte): Stadtmittel pendelt sich bei 3,2 ein, Zufriedenheit 82-84, Stadtkasse 280-430 k, Geld erhalten. Längere Läufe mit KI-Spielern fehlen.
