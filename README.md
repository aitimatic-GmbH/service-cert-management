# automated-certificate-management# Service: Automated Certificate Management in Azure

> Vollautomatisierter Lebenszyklus für SSL/TLS-Zertifikate in Azure –  
> von der Bereitstellung über die Überwachung bis zur automatischen Erneuerung.

---

## Übersicht

Dieser Service automatisiert den gesamten Lebenszyklus von SSL/TLS-Zertifikaten in Azure Key Vault.  
Bei drohender Ablauf eines Zertifikats reagiert eine Event-gesteuerte Azure Function automatisch und erneuert das Zertifikat – ohne manuellen Eingriff.

### Architektur

```
Azure Key Vault
      │
      │  CertificateNearExpiry Event
      ▼
Azure Event Grid
      │
      │  Trigger
      ▼
Azure Function (PowerShell)
      │
      │  Zertifikat erneuern & importieren
      ▼
Azure Key Vault (aktualisiert)
      │
      │  Logging & Metriken
      ▼
Application Insights
```

---

## Umgebungen

| Umgebung | Zertifikat Laufzeit | Near-Expiry Trigger | Deploy |
|---|---|---|---|
| `dev` | 1 Tag | 1 Tag | Automatisch (Feature Branch) |
| `staging` | 7 Tage | 6 Tage | Automatisch (Feature Branch) |
| `prod` | 365 Tage | 30 Tage | Manuell (nach PR Merge) |

---

## Voraussetzungen

- Azure Subscription mit Berechtigungen zur Ressourcenerstellung
- Azure CLI (`az`) installiert
- Bicep CLI (`bicep`) installiert
- PowerShell 7.x installiert
- `jq` installiert (für lokale Skripte)
- GitHub Account mit Zugriff auf dieses Repository

---

## Quick Start

### 1. Repository klonen

```bash
git clone https://github.com/<YOUR_ORG>/service-cert-management.git
cd service-cert-management
```

### 2. Konfiguration vorbereiten

```bash
cp example.config.json config.json
# config.json mit eigenen Werten befüllen
```

### 3. Azure Ressourcen deployen (lokal)

```bash
chmod +x scripts/local-deploy.sh
./scripts/local-deploy.sh
```

### 4. Pipeline einrichten

Siehe [SETUP.md](docs/SETUP.md) für die vollständige Anleitung zur OIDC-Konfiguration und GitHub Secrets.

### 5. Renewal testen

```bash
chmod +x scripts/demo-trigger.sh
./scripts/demo-trigger.sh
```

---

## Projektstruktur

```
service-cert-management/
├── .github/workflows/      # GitHub Actions CI/CD
├── infra/                  # Bicep Infrastruktur
│   ├── modules/            # Wiederverwendbare Module
│   └── parameters/         # Umgebungsspezifische Parameter
├── src/                    # Azure Function Code
│   └── CertRenewalFunction/
├── scripts/                # Lokale Hilfsskripte
├── docs/                   # Dokumentation
├── example.config.json     # Konfigurationsvorlage
└── README.md
```

---

## Dokumentation

- [SETUP.md](docs/SETUP.md) – OIDC Einrichtung, GitHub Secrets, Onboarding
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – Architektur & Komponenten
- [DECISIONS.md](docs/DECISIONS.md) – Architekturentscheidungen

---

## Stack

| Technologie | Verwendung |
|---|---|
| Bicep | Infrastructure as Code |
| GitHub Actions | CI/CD Pipeline |
| OIDC / Federated Identity | Sichere Authentifizierung |
| Azure Key Vault | Zertifikatsspeicher |
| Azure Event Grid | Event-Steuerung |
| Azure Functions (PowerShell) | Renewal-Logik |
| Application Insights | Monitoring & Logging |

---

## Lizenz

MIT License – siehe [LICENSE](LICENSE)