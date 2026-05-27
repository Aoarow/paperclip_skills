---
name: om-google-new-projects-workflow
description: Was zu tun ist bei neuen Google Ads-Projekten
---

# Übersicht

Dieser Skill beschreibt, welche Arbeitsschritte beim Beginn neuer Google Ads-Projekte zu erledigen sind.

## Dateien und Ordner

Prüfe, ob die Dateien und Ordner vorhanden sind. Wenn nicht, dann erstelle sie zunächst als leere Dateien und erstelle danach einen Issue an das Board, damit die Dateien befüllt werden.

**Genereller Arbeitsraum**

```
https://drive.google.com/drive/u/0/folders/0APpEXGtLsCwkUk9PVA
Folder-ID: 0APpEXGtLsCwkUk9PVA
```

**Ordner des Kunden**

```
01_Kunden & Projekte/01_Kunden/[Kundenname]/
```

* client.md

**Projektdurchführung und Assets**

```
01_Kunden & Projekte/01_Kunden/[Kunde]/02_Projektdurchführung & Assets/01_Google Ads/[property]/
```

* data-sources.md
* strategy.md
* budget.csv
* learnings.md (nur leere Datei erstellen, nicht Issue erstellen)

**Reporting**

```
01_Kunden & Projekte/01_Kunden/[Kunde]/04_Reporting & Analysen/Google/[property]/
```

* decision-log.md

## Agenten

Jedes Google-Projekt benötigt mindestens 2 Agenten:

* **\[property] - Optimizer:** Prüft jede Nacht die Performance der Kampagnen, passt Gebote und Keywords an und spricht Empfehlungen für umfassendere Änderungen aus. Dokumentiert seine Entscheidungen in der decision-log.md.
* **\[property] - Reviewer:** Liest einmal jede Woche die decision-log.md und prüft die vergangenen Entscheidungen des Optimizer-Agenten aus den letzten 14 Tagen auf ihre Auswirkungen. Die Ergebnisse schreibt der Reviewer in die learnings.md. Ziel: Erkenntnisgewinn und Verbesserung.

Erstelle die Agenten basierend auf schon vorhandenen Agenten aus anderen Projekten (properties) und passe die Pfade der neuen Agenten an das neue Projekt an.

## Webseitenanalyse

Scanne die Webseite, die in der client.md des Kunden genannt wird, bewerte sie im Hinblick auf Google Ads und erstelle ein Dokument mit Deinen Erkenntnissen in folgendem Pfad:

```
01_Kunden & Projekte/01_Kunden/[Kunde]/02_Projektdurchführung & Assets/01_Google Ads/[property]/webseiten-analyse-google.md
```

**Format des Dokuments:**

```
---
erstellt: [DATUM]
analysiert_von: Peggy
webseiten: [URL]
kanal: Google Ads
---

## Gesamtbewertung
[Ampel-Tabelle: Klarheit, CTA, Landingpages, Social Proof, Tracking]

## Was gut ist
[Stärken]

## Keyword-Potenzial
[Cluster A, B, C mit konkreten Keywords]

## Empfohlene Kampagnenstruktur
[Kampagne 1, 2, 3 mit Zielen und Budget-Anteilen]

## Handlungsbedarf vor Kampagnenstart
[Kritisch 🔴 / Empfehlenswert 🟡 / Gut 🟢]

## Empfehlung Kampagnenstart
[Womit beginnen, warum]
```

Erstelle einen Task für das Board: "Webseiten-Analyse liegt vor für \[URL] – bitte prüfen und ggf. Handlungsbedarf angehen, bevor Kampagne startet."

**Wichtig:** Ohne abgeschlossene Webseiten-Analyse startet kein Google-Projekt.