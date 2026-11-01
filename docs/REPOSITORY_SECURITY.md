# Repository-Schutz auf GitHub

Die Dateien in diesem Repository sichern Quellcode und Prüfungen. GitHub-Regeln
für Branches und Geheimnisse werden zusätzlich in den **Repository-Einstellungen**
gesetzt; eine Datei allein aktiviert sie nicht.

## `main` schützen

Unter **Settings → Rules → Rulesets** ein aktives Branch-Ruleset für
`refs/heads/main` anlegen. Die Vorlage orientiert sich am
[`main-protection`-Ruleset von octofleet](https://github.com/BenediktSchackenberg/octofleet/rules):

- Löschen und Force-Pushs untersagen.
- Änderungen nur über Pull Requests zulassen.
- Eine Zustimmung verlangen und veraltete Zustimmungen nach neuen Commits
  verwerfen. Wer allein entwickelt, benötigt dafür einen zweiten Reviewer oder
  einen bewusst gesetzten Admin-Bypass; octofleet nutzt einen Admin-Bypass.
- Den erfolgreichen Statuscheck **`Secret-Scan und Godot-Tests`** verlangen und
  eine aktuelle Branch-Basis erzwingen. Den Check erst nach dem ersten
  erfolgreichen Lauf dieses Workflows auswählen.

`CODEOWNERS` benennt den zuständigen Maintainer. Allein dadurch wird noch keine
Freigabe durch einen Code-Owner erzwungen; das ist eine weitere Ruleset-Option.

## Geheimnisse und Abhängigkeiten

Unter **Settings → Security & analysis** Secret Scanning, Push Protection und
Dependabot Alerts aktivieren, soweit sie für das Repository verfügbar sind.
Die Datei `.github/dependabot.yml` öffnet Update-PRs für GitHub Actions und die
Docker-Datei in `local-ai/`.

`tools/check_secrets.py` prüft beim PR und bei Pushes auf `main` bekannte
Schlüssel-Formate sowie versehentlich eingecheckte `.env`- und Schlüsseldateien.
Die Prüfung gibt nur Dateipfad und Fundart aus, nie den gefundenen Wert. Sie ist
eine zusätzliche Kontrolle und ersetzt die serverseitige Push Protection nicht.

Ein offengelegter Token muss beim Anbieter widerrufen werden. Das Entfernen aus
einem Commit oder ein späteres Force-Pushen macht ihn nicht wieder geheim.
Sicherheitslücken bitte gemäß [`SECURITY.md`](../SECURITY.md) privat melden.
