# Backlog: Automated Certificate Management in Azure

> **Vision:** Vollautomatisierter, revisionssicherer Lebenszyklus für SSL/TLS-Zertifikate in Azure –
> von der Bereitstellung über die Überwachung bis zur automatischen Erneuerung.
>
> **Stack:** Bicep · GitHub Actions · OIDC · Azure Key Vault · Azure Functions · Event Grid  
>
> **Umgebungen:** `dev` · `staging` · `prod`

---

## Entscheidungsprotokoll

| Thema | Entscheidung | Begründung |
|---|---|---|
| IaC Technologie | Bicep | Azure-nativ, keine State-Datei erforderlich |
| Pipeline | GitHub Actions | Einheitlich mit anderen Services im Katalog |
| Authentifizierung | OIDC / Federated Identity | Kein langlebiges Secret, moderner Standard |
| Naming Convention | Microsoft CAF | Konsistenz & Enterprise-Readiness |
| Resource Groups | Eine RG pro Umgebung | Klare Trennung, einfaches Lifecycle-Management |
| Branch-Strategie | Feature Branches → PR → main | Nachvollziehbarer Änderungsprozess |
| Config Pattern | `config.json` (lokal) + Secrets (Pipeline) | Keine hardcodierten Werte, umgebungsspezifisch |
| Deploy dev/staging | Automatisch (Feature Branch Push) | Schnelles Feedback für Entwickler |
| Deploy prod | Manuell (nach Merge, GitHub Environment Approval) | Vier-Augen-Prinzip, Audit-Trail |
| Zertifikat Laufzeit dev | 1 Tag | Schnelles Testen der Renewal-Logik |
| Zertifikat Laufzeit staging | 7 Tage | Vollständige Validierung des Ablaufs |
| Zertifikat Laufzeit prod | 365 Tage | Realistischer Produktionsbetrieb |
| Soft Delete | Nur in prod | dev/staging ohne Soft Delete für schnelles Testen |

---

## Repo-Struktur

```
service-cert-management/
├── .github/
│   └── workflows/
│       ├── ci.yml                  # PR-Check: Lint, Validate, What-if
│       └── cd.yml                  # Deploy: dev/staging auto, prod manuell
├── infra/
│   ├── modules/
│   │   ├── keyvault.bicep
│   │   ├── functionapp.bicep
│   │   ├── eventgrid.bicep
│   │   └── appinsights.bicep
│   └── main.bicep
├── src/
│   └── CertRenewalFunction/
│       ├── run.ps1
│       └── function.json
├── scripts/
│   ├── local-deploy.sh
│   └── demo-trigger.sh
├── docs/
│   ├── DECISIONS.md
│   ├── SETUP.md
│   └── ARCHITECTURE.md
├── example.config.json             # Vorlage für alle Umgebungen
├── .bicepconfig.json
└── README.md
```

---

## Epic 1: Repo & Grundstruktur

Status: ✅ Abgeschlossen

### Story 1.1 – GitHub Repo erstellen

- [x] Repo anlegen (privat)
- [x] `.gitignore` anlegen
- [x] Ordnerstruktur anlegen
- [x] Initiales `README.md`
- [x] MIT Lizenz hinzufügen

### Story 1.2 – Ordnerstruktur & Konfiguration

- [x] Alle Verzeichnisse und `.gitkeep` Platzhalter erstellen
- [x] `.bicepconfig.json` Grundkonfiguration (Linter aktivieren)
- [x] `CODEOWNERS` Datei anlegen

### Story 1.3 – GitHub Environments konfigurieren

- [x] Environment `dev` anlegen (kein Approval, Secret: `AZURE_CONFIG`)
- [x] Environment `staging` anlegen (kein Approval, Secret: `AZURE_CONFIG`)
- [x] Environment `prod` anlegen (manueller Approval, Secret: `AZURE_CONFIG`)
- [ ] Branch Protection Rules für `main` aktivieren
- [ ] Required Status Checks definieren

---

## Epic 2: Konfiguration & Secrets Pattern

Status: ✅ Abgeschlossen

### Story 2.1 – `example.config.json` erstellen

- [x] Eine einzige Vorlage für alle Umgebungen
- [x] Alle Felder mit Platzhaltern und Kommentaren
- [x] Umgebungsspezifische Werte als Parameter definiert

### Story 2.2 – `.gitignore` & Dokumentation

- [x] `config.json` in `.gitignore`
- [x] `!example.config.json` explizit ausschließen
- [x] `SETUP.md`: Anleitung zum Kopieren der Vorlage
- [x] `SETUP.md`: Anleitung zum Anlegen der GitHub Secrets

---

## Epic 3: Infrastruktur als Bicep

Status: ✅ Abgeschlossen

### Story 3.1 – `keyvault.bicep` Modul

- [x] Key Vault deployen (CAF Naming: `kv-certmgmt-<env>-<region>`)
- [x] Soft Delete nur in prod aktiviert (dev/staging: deaktiviert)
- [x] RBAC Konfiguration (kein Legacy Access Policy Mode)
- [x] Diagnostic Settings → Log Analytics Workspace
- [x] Parameter: `name`, `location`, `environment`, `tags`, `keyVaultSku`, `softDeleteRetentionInDays`
- [x] Outputs: `keyVaultId`, `keyVaultUri`, `keyVaultName`

### Story 3.2 – `functionapp.bicep` Modul

- [x] Consumption Plan (serverless)
- [x] Function App (PowerShell 7.4 Runtime)
- [x] System-assigned Managed Identity aktivieren
- [x] Storage Account für Function App
- [x] Application Insights Anbindung
- [x] Konfigurierbare Runtime und Storage SKU
- [x] Outputs: `functionAppId`, `principalId`, `functionAppName`, `storageAccountName`

### Story 3.3 – `eventgrid.bicep` Modul

- [x] Event Grid System Topic (Quelle: Key Vault)
- [x] Event Subscription
  - Filter: `Microsoft.KeyVault.CertificateNearExpiry`
  - Endpoint: Azure Function
- [x] Dead Letter Konfiguration (Storage Account)
- [x] Konfigurierbare Retry Policy und TTL
- [x] Outputs: `systemTopicId`, `eventSubscriptionId`

### Story 3.4 – `appinsights.bicep` Modul

- [x] Application Insights Ressource
- [x] Log Analytics Workspace Anbindung
- [x] Konfigurierbare Retention und SKU
- [x] Outputs: `appInsightsId`, `instrumentationKey`, `connectionString`, `workspaceId`

### Story 3.5 – `main.bicep` & Konfiguration

- [x] Alle Module in `main.bicep` zusammengeführt
- [x] RBAC Assignment: Function Managed Identity → Key Vault Certificates Officer
- [x] `example.config.json` erweitert mit allen Parametern
- [x] Parameter-Mapping: config.json → main.bicep (lokal) bzw. Secrets → main.bicep (Pipeline)
- [x] Keine .bicepparam Dateien (alle Parameter via config.json oder GitHub Secrets)
- [x] Tagging-Strategie: `environment`, `workload`, `managedBy`

---

## Epic 4: Automatisierungslogik (Azure Function)

Status: ⬜ Offen

### Story 4.1 – PowerShell Function: Grundlogik

- [ ] Event Grid Trigger konfigurieren (`function.json`)
- [ ] Zertifikat-Name und Metadaten aus Event-Payload extrahieren
- [ ] Strukturiertes Logging (JSON Format für Application Insights)
- [ ] Managed Identity Authentifizierung gegen Key Vault
- [ ] Eingabe-Validierung (Pflichtfelder prüfen)

### Story 4.2 – PowerShell Function: Renewal Logic

- [ ] Self-signed Zertifikat erstellen und erneuern
- [ ] Neues Zertifikat in Key Vault importieren
- [ ] Versionierung: altes Zertifikat bleibt als Vorversion erhalten
- [ ] Erfolg/Fehler strukturiert protokollieren (Audit Trail)
- [ ] Erweiterungspunkt für echte CA dokumentieren (Let's Encrypt / DigiCert)

### Story 4.3 – Fehlerbehandlung & Alerting

- [ ] Try/Catch mit strukturiertem Logging
- [ ] Bei Fehler → Application Insights Custom Event (`CertRenewalFailed`)
- [ ] Alert Rule: bei Fehler → E-Mail / Teams Benachrichtigung
- [ ] Idempotenz: doppelte Events werden sicher behandelt

---

## Epic 5: GitHub Actions Workflows

Status: ⬜ Offen

### Story 5.1 – CI Workflow `ci.yml`

- [ ] Trigger: Pull Request auf `main`
- [ ] Job 1: `az bicep build` (Lint & Syntax Check)
- [ ] Job 2: `az deployment what-if` (Preview aller Änderungen)
- [ ] Job 3: `PSScriptAnalyzer` (PowerShell Code Quality)
- [ ] PR Kommentar: What-if Ergebnis automatisch posten
- [ ] Status-Check als Required für PR Merge

### Story 5.2 – CD Workflow `cd.yml`

- [ ] Trigger: Push auf Feature Branch → deploy `dev` + `staging` (automatisch)
- [ ] Trigger: Merge main → deploy `prod` (manuell, GitHub Environment Approval)
- [ ] Config aus GitHub Secret laden → Parameter übergeben
- [ ] GitHub Environment Protection für `prod` (Approval erforderlich)
- [ ] Deploy-Zusammenfassung als Job-Summary ausgeben

### Story 5.3 – OIDC Setup & Dokumentation

- [ ] Federated Identity für GitHub Actions einrichten
- [ ] `SETUP.md`: Schritt-für-Schritt OIDC Anleitung
- [ ] Benötigte GitHub Secrets dokumentieren

---

## Epic 6: Lokaler Workflow

Status: ⬜ Offen

### Story 6.1 – `local-deploy.sh`

- [ ] Voraussetzungen prüfen: `az cli`, `bicep`, `jq`
- [ ] `config.json` Existenz prüfen → hilfreiche Fehlermeldung
- [ ] Werte aus `config.json` laden
- [ ] `az bicep build` (Lint)
- [ ] `az deployment validate` (Template Validation)
- [ ] `az deployment what-if` → Preview anzeigen
- [ ] Interaktiv: "Wirklich deployen? (y/n)"
- [ ] Farbige Ausgabe (grün/rot/gelb)

### Story 6.2 – `demo-trigger.sh`

- [ ] Event Grid `CertificateNearExpiry` Event manuell auslösen
- [ ] Funktioniert für `dev` und `staging`
- [ ] Ausgabe: welche Function wurde getriggert, was ist passiert
- [ ] Dokumentiert in `README.md`

---

## Epic 7: Dokumentation

Status: ✅ Abgeschlossen

### Story 7.1 – `README.md`

- [x] Architektur-Diagramm
- [x] Kurzbeschreibung des Services
- [x] Quick Start
- [x] Umgebungsübersicht
- [x] Voraussetzungen

### Story 7.2 – `ARCHITECTURE.md`

- [x] Komponentenübersicht mit Mermaid Diagrammen
- [x] Sequenzdiagramm (Runtime-Flow)
- [x] Sicherheitskonzept: Managed Identity, RBAC, OIDC
- [x] RBAC Modell Tabelle

### Story 7.3 – `DECISIONS.md`

- [x] Warum Managed Identity statt Secret
- [x] Warum Event Grid statt Scheduled Job
- [x] Warum Consumption Plan statt Dedicated Plan
- [x] Warum RBAC statt Access Policies
- [x] Nicht gewählte Alternativen dokumentiert

---

## Epic 8: Observability & Monitoring

Status: ⬜ Offen

### Story 8.1 – Application Insights Dashboard

- [ ] Custom Metrics: Anzahl erfolgreicher Erneuerungen
- [ ] Custom Metrics: Anzahl fehlgeschlagener Erneuerungen
- [ ] Workbook: Übersicht aller verwalteten Zertifikate
- [ ] Workbook: Ablaufdatum-Timeline

### Story 8.2 – Alert Rules

- [ ] Alert: Erneuerung fehlgeschlagen (Severity 1)
- [ ] Alert: Zertifikat läuft in < 7 Tagen ab und keine Erneuerung erfolgt
- [ ] Alert: Function App nicht erreichbar
- [ ] Notification: E-Mail und/oder Teams Webhook

---

## Epic 9: Sicherheit & Härtung

Status: ⬜ Offen

### Story 9.1 – Key Vault Härtung

- [ ] Private Endpoint für Key Vault (optional aktivierbar)
- [ ] Firewall Rules: nur bekannte IPs / VNet
- [ ] Diagnostic Logs: alle Zugriffe protokollieren
- [ ] RBAC: Least Privilege Prinzip konsequent umsetzen

### Story 9.2 – Function App Härtung

- [ ] HTTPS only erzwingen
- [ ] Minimum TLS Version 1.2
- [ ] Outbound IPs dokumentieren
- [ ] App Settings: keine Secrets als Umgebungsvariablen (Key Vault Referenzen)

---

## Epic 10: Erweiterung – Echte Certificate Authority

Status: ⬜ Offen

### Story 10.1 – Let's Encrypt Integration

- [ ] ACME Challenge Logik in PowerShell Function
- [ ] DNS Challenge via Azure DNS (Managed Identity)
- [ ] Zertifikat automatisch in Key Vault importieren
- [ ] Renewal 30 Tage vor Ablauf (Let's Encrypt Standard)

### Story 10.2 – DigiCert / Sectigo Integration

- [ ] CA Connector in Key Vault konfigurieren
- [ ] Automatische Ausstellung über Key Vault CA Integration
- [ ] OV/EV Zertifikate unterstützen
- [ ] Wildcard Zertifikat Support

---

## Epic 11: Erweiterung – Multi-Anwendung Support

Status: ⬜ Offen

### Story 11.1 – App Service Anbindung

- [ ] Zertifikat nach Erneuerung automatisch an App Service binden
- [ ] Custom Domain Binding aktualisieren
- [ ] Zero-Downtime Rotation sicherstellen

### Story 11.2 – Application Gateway / Front Door

- [ ] Zertifikat-Rotation für Application Gateway Listener
- [ ] Azure Front Door Custom Domain Zertifikat
- [ ] Managed Certificate vs. eigenes Zertifikat dokumentieren

### Story 11.3 – Multi-Subscription Support

- [ ] Cross-Subscription Deployment via Managed Identity
- [ ] Zentrale Key Vault Instanz für mehrere Subscriptions
- [ ] RBAC über Subscription-Grenzen hinweg

---

## Epic 12: Erweiterung – Governance & Compliance

Status: ⬜ Offen

### Story 12.1 – Azure Policy Integration

- [ ] Policy: alle App Services müssen Zertifikat aus Key Vault nutzen
- [ ] Policy: Zertifikate dürfen nicht manuell hochgeladen werden
- [ ] Compliance Report via Azure Policy Dashboard

### Story 12.2 – Audit & Reporting

- [ ] Monatlicher Report: alle verwalteten Zertifikate mit Status
- [ ] Ablaufdatum-Übersicht als exportierbare CSV
- [ ] Integration in bestehende ITSM/Ticketing Systeme (Webhook)

---

## Priorisierung

```
Phase 1 – Initial Release (Epics 1–7)
→ Vollständig funktionsfähige Lösung
→ Self-signed Zertifikate
→ Drei Umgebungen (dev/staging/prod)
→ GitHub Actions CI/CD

Phase 2 – Produktionsreife (Epics 8–9)
→ Vollständiges Monitoring & Alerting
→ Sicherheitshärtung
→ Bereit für Enterprise-Einsatz

Phase 3 – Feature-Erweiterungen (Epics 10–12)
→ Echte Certificate Authority
→ Multi-Anwendung & Multi-Subscription
→ Governance & Compliance
```

---

## Definition of Done

Phase 1 gilt als abgeschlossen wenn folgende Kriterien erfüllt sind:

- [ ] GitHub Actions CI läuft grün (PR Check)
- [ ] GitHub Actions CD deployt dev + staging automatisch
- [ ] prod Deploy funktioniert nach manuellem Approval
- [ ] Zertifikat erscheint in Key Vault (dev: innerhalb Minuten)
- [ ] Event Grid löst Function aus (nachweisbar in App Insights)
- [ ] Function erneuert Zertifikat (Log zeigt Erfolg)
- [ ] Keine hardcodierten Werte im Repo
- [ ] README ermöglicht eigenständiges Onboarding
- [ ] SETUP.md erklärt OIDC Einrichtung Schritt für Schritt
- [ ] Alle drei Umgebungen deployen erfolgreich