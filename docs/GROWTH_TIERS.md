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

## Grenzen / nächste Schritte
- Viertel ohne passendes leeres Ladengebäude (z. B. keine Drogerie) bleiben bei fehlendem Bedürfnis stehen. Dort müsste der Bürgermeister bzw. ein Bauherr ein Geschäft bauen.
- Kliniken und Schulen entstehen nicht automatisch; ihre Deckung kommt nur aus vorhandenen Gebäuden.
- Keine Freischaltung neuer Gebäude oder Waren durch Stufen und keine Bedarfs-Boni auf Frachtlöhne (müssten aus einer Kasse bezahlt werden).
- Die Zahlen sind nicht langzeitbalanciert: Lauf mit 75 Spieltagen (Wirtschaftslabor, Seed 21): Stadtkasse 363 k, Geld erhalten, Zufriedenheit 84.
