# Architekturentscheidungen

Dieses Dokument beschreibt die wichtigsten Architekturentscheidungen und deren Begründung.

---

## Warum Event Grid statt Scheduled Job?

Ein Scheduled Job (z.B. täglich um 08:00 Uhr) würde alle Zertifikate aktiv abfragen –
selbst wenn kein Handlungsbedarf besteht.

Azure Key Vault sendet bei drohender Ablauf automatisch ein `CertificateNearExpiry` Event.
Event Grid leitet dieses Event direkt an die Function weiter.

**Vorteile:**

* Keine unnötigen API-Aufrufe
* Reaktion in Echtzeit
* Keine Polling-Logik notwendig
* Geringere Kosten (Function läuft nur bei Bedarf)
* Bessere Skalierbarkeit bei vielen Zertifikaten

---

## Warum Managed Identity statt Secret?

Ein Service Principal Secret hat eine begrenzte Laufzeit und muss regelmäßig erneuert werden –
ein häufiger Grund für Produktionsausfälle.

Die Azure Function nutzt eine System-assigned Managed Identity.
Azure übernimmt das gesamte Credential-Management automatisch.

**Vorteile:**

* Kein langlebiges Secret
* Keine manuelle Rotation
* Audit Trail über Azure Activity Log
* Least Privilege via RBAC
* Kein Secret Storage notwendig

---

## Warum RBAC statt Key Vault Access Policies?

Access Policies sind das ältere Modell und werden von Microsoft nicht mehr empfohlen.
RBAC ist konsistenter mit dem Rest der Azure-Plattform und ermöglicht zentrales Management.

**Vorteile:**

* Einheitliches Berechtigungsmodell
* Management über Azure Policy möglich
* Granularere Rollen verfügbar
* Besserer Audit Trail
* Konsistenz mit anderen Azure Ressourcen

---

## Warum Consumption Plan statt Dedicated Plan?

Die Renewal-Funktion läuft nur dann wenn ein Zertifikat erneuert werden muss –
das ist selten (maximal einmal pro Zertifikat pro Jahr in Produktion).

Ein dedizierter App Service Plan würde dauerhaft Kosten verursachen.

**Vorteile:**

* Kosten entstehen nur bei tatsächlicher Ausführung
* Automatische Skalierung
* Kein Betriebsaufwand
* Optimiert für Event-driven Workloads

---

## Warum Event-driven Architektur statt zentralem Controller-Service?

Alternativ könnte ein zentraler Service alle Zertifikate überwachen und erneuern.

Dies würde jedoch bedeuten:

* dauerhafte Compute-Ressourcen
* komplexeres Lifecycle-Management
* höheres Fehlerrisiko

Event-driven Architektur nutzt native Plattform-Events.

**Vorteile:**

* keine dauerhaft laufenden Services
* geringere Komplexität
* höhere Zuverlässigkeit
* bessere Integration in Azure

---

## Warum Azure Function statt VM oder Container?

Alternative Implementierungen:

* Virtual Machine
* Container App
* Kubernetes Service

Diese Optionen benötigen aktives Lifecycle-Management.

Azure Function ist vollständig serverless.

**Vorteile:**

* keine Serververwaltung
* automatische Skalierung
* integrierte Event Grid Integration
* geringere Betriebskosten
* reduzierte Angriffsfläche

---

## Warum System-assigned Managed Identity statt User-assigned?

Beide Optionen sind möglich.

System-assigned Identity wurde gewählt, da sie direkt an die Function gebunden ist.

**Vorteile:**

* Automatische Lifecycle-Verwaltung
* Kein separates Identity-Deployment notwendig
* Kein Risiko verwaister Identitäten
* Geringere Komplexität

User-assigned Identity wäre sinnvoll bei:

* mehreren Functions mit gleicher Identity
* zentralem Identity-Management

---

## Warum Infrastructure as Code statt manueller Deployment?

Alle Ressourcen werden über Infrastructure-as-Code bereitgestellt.

Manuelles Deployment führt häufig zu:

* Konfigurationsabweichungen
* fehlender Nachvollziehbarkeit
* höherem Fehlerrisiko

**Vorteile:**

* reproduzierbare Deployments
* Versionierung im Git Repository
* automatisierte Deployments via CI/CD
* Auditierbarkeit aller Änderungen

---

## Warum Environment Isolation per Resource Group statt Shared Resources?

Jede Umgebung besitzt eine eigene Resource Group.

Alternative wäre:

* eine gemeinsame Resource Group mit Namenspräfixen

Dies erhöht jedoch das Risiko von Fehlkonfigurationen.

**Vorteile:**

* vollständige Isolation
* einfacheres RBAC Management
* geringeres Risiko versehentlicher Änderungen
* klarere Struktur

---

## Warum Application Insights statt Custom Logging?

Alternative wäre Logging in:

* Files
* Storage Account
* externe Systeme

Application Insights ist nativ integriert.

**Vorteile:**

* zentrale Log-Verwaltung
* integriertes Monitoring
* automatische Telemetrie
* Alerting möglich
* Query via KQL

---

## Erweiterungspunkte

### Echte Certificate Authority

Aktuell werden Self-signed Zertifikate verwendet.

Für produktiven Einsatz geplant:

* Let's Encrypt via ACME Challenge
* Integration via Azure DNS
* Key Vault Certificate Issuer Integration

---

### Netzwerkhärtung

Für Umgebungen mit erhöhten Sicherheitsanforderungen:

* Private Endpoint für Key Vault
* VNet Integration für Function App
* Firewall Einschränkungen
* Public Access deaktivieren

---

### Erweiterte Monitoring-Integration

Optional möglich:

* Alert Rules
* automatische Incident-Erstellung
* Integration mit ITSM-Systemen

---

## Nicht gewählte Alternativen

### Polling-basierte Lösung

Nicht gewählt aufgrund:

* höherer Kosten
* unnötiger API Calls
* schlechter Skalierbarkeit

---

### VM-basierte Lösung

Nicht gewählt aufgrund:

* höherem Betriebsaufwand
* Patch Management notwendig
* schlechtere Skalierbarkeit

---

### Kubernetes-basierte Lösung

Nicht gewählt aufgrund:

* unnötiger Komplexität
* Overhead für einfachen Use Case

---

## Zusammenfassung

Die Architektur basiert auf folgenden Kernprinzipien:

* Event-driven
* Serverless
* Secretless Authentication
* Least Privilege
* Fully automated Deployment
* Environment Isolation
* minimale Betriebskosten

