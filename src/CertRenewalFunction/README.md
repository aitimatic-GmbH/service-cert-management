# Certificate Renewal Function

PowerShell-basierte Azure Function zum automatischen Erneuern von Zertifikaten in Azure Key Vault.

## Funktionsweise

1. Event Grid sendet `CertificateNearExpiry` Event
2. Function wird getriggert
3. Zertifikat-Details werden aus Event extrahiert
4. Managed Identity authentifiziert gegen Key Vault
5. Neues Self-signed Zertifikat wird generiert
6. Zertifikat wird in Key Vault importiert
7. Alte Version bleibt als Vorversion erhalten

## Dateien

```
src/                               # Function App Root (Deploy-Root)
├── host.json                      # Function App Konfiguration
├── profile.ps1                    # Initialisierung (Cold Start)
├── requirements.psd1              # PowerShell Module Dependencies
├── example.settings.json          # Vorlage für lokale Entwicklungseinstellungen
└── CertRenewalFunction/           # Function-Ordner
    ├── function.json              # Event Grid Trigger Definition
    └── run.ps1                    # Hauptlogik
```

## Umgebungsvariablen

| Variable | Beschreibung | Default | Quelle |
|---|---|---|---|
| `CERT_VALIDITY_DAYS` | Gültigkeitsdauer neuer Zertifikate (Tage) | 365 | Bicep Parameter |
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Application Insights Key | - | Bicep Output |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Application Insights Connection String | - | Bicep Output |

## Logging

Die Function verwendet strukturiertes JSON-Logging für Application Insights:

```json
{
  "Timestamp": "2026-02-19T14:30:00Z",
  "Level": "Information",
  "Message": "Certificate renewal completed successfully",
  "EventId": "uuid",
  "EventType": "Microsoft.KeyVault.CertificateNearExpiry",
  "CertificateName": "demo-cert",
  "KeyVaultName": "kv-certmgmt-dev-xyz",
  "NewVersion": "abc123",
  "OldVersion": "xyz789"
}
```

## Custom Events für Alerting

### CertRenewalSuccess

Wird bei erfolgreicher Erneuerung gesendet:

```json
{
  "name": "CertRenewalSuccess",
  "properties": {
    "CertificateName": "demo-cert",
    "KeyVaultName": "kv-certmgmt-dev-xyz",
    "ValidityDays": 365
  }
}
```

### CertRenewalFailed

Wird bei Fehler gesendet (für Alert Rules):

```json
{
  "name": "CertRenewalFailed",
  "properties": {
    "CertificateName": "demo-cert",
    "KeyVaultName": "kv-certmgmt-dev-xyz",
    "ErrorMessage": "Certificate demo-cert not found"
  }
}
```

## Fehlerbehandlung

- **Validation Errors**: Event Type prüfung, Pflichtfelder-Validierung
- **Authentication Errors**: Managed Identity Probleme
- **Key Vault Errors**: Zertifikat nicht gefunden, Permission Denied
- **Certificate Generation Errors**: Self-signed Cert Generierung fehlgeschlagen

Alle Fehler werden strukturiert geloggt und als Custom Event an Application Insights gesendet.

## Idempotenz

Die Function ist idempotent:
- Bei doppeltem Event wird das Zertifikat erneut generiert
- Die neue Version überschreibt die alte in Key Vault
- Keine Duplikate oder Inkonsistenzen

## Testing

### Lokales Testen

```bash
# 1. Local Settings kopieren (aus src/ Root)
#    (Azure Function Core Tools sind im Devcontainer bereits vorinstalliert)
cp ../example.settings.json settings.local.json

# 2. Azure Login (für Managed Identity Simulation)
az login

# 3. Function starten
func start
```

### Event Grid Event simulieren

Event erstellen und an lokale Function senden:

```bash
curl -X POST http://localhost:7071/runtime/webhooks/EventGrid?functionName=CertRenewalFunction \
  -H "Content-Type: application/json" \
  -H "aeg-event-type: Notification" \
  -d '[{
    "id": "test-event-id",
    "subject": "/certificates/demo-cert",
    "data": {
      "Id": "https://kv-certmgmt-dev-xyz.vault.azure.net/certificates/demo-cert",
      "VaultName": "kv-certmgmt-dev-xyz",
      "ObjectType": "Certificate",
      "ObjectName": "demo-cert"
    },
    "eventType": "Microsoft.KeyVault.CertificateNearExpiry",
    "eventTime": "2026-02-19T14:30:00Z"
  }]'
```

## Erweiterungspunkte

### Let's Encrypt Integration (Epic 10)

Aktuell: Self-signed Zertifikate
Geplant: ACME Challenge via Let's Encrypt

Änderungen erforderlich:
- ACME Client Integration
- DNS Challenge via Azure DNS
- Domain Validation

### Multi-CA Support

Konfigurierbare Certificate Authority pro Zertifikat via Key Vault Tags.

## Abhängigkeiten

- **Az.Accounts** 3.* - Managed Identity Authentifizierung
- **Az.KeyVault** 6.* - Key Vault Operations
- PowerShell 7.4 Runtime

## RBAC Berechtigungen

Function Managed Identity benötigt:
- **Key Vault Certificates Officer** auf Key Vault Scope