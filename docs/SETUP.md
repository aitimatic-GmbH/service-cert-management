# Setup-Anleitung

Diese Anleitung beschreibt alle Schritte um den Service in deiner Azure-Umgebung einzurichten.

---

## Voraussetzungen

### Lokale Tools

| Tool | Version | Installation |
|---|---|---|
| Azure CLI | >= 2.83.0 | [docs.microsoft.com](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| Bicep CLI | >= 0.40.2 | `az bicep install` |
| PowerShell | >= 7.x | [github.com/PowerShell](https://github.com/PowerShell/PowerShell) |
| jq | >= 1.7 | `brew install jq` / `apt install jq` |

### Azure Berechtigungen

Der Service Principal / die Managed Identity benötigt folgende Rollen:

| Rolle | Scope | Zweck |
|---|---|---|
| `Contributor` | Resource Group | Ressourcen deployen |
| `Key Vault Administrator` | Key Vault | Zertifikate verwalten |
| `User Access Administrator` | Resource Group | RBAC Assignments setzen |

---

## Schritt 1: OIDC / Federated Identity einrichten

### 1.1 App Registration erstellen

```bash
# App Registration anlegen
az ad app create --display-name "sp-certmgmt-github"

# Client ID merken
CLIENT_ID=$(az ad app list --display-name "sp-certmgmt-github" --query "[0].appId" -o tsv)
echo "Client ID: $CLIENT_ID"
```

### 1.2 Service Principal erstellen

```bash
az ad sp create --id $CLIENT_ID
```

### 1.3 Federated Credentials anlegen

Für jeden GitHub Environment (dev, staging, prod) eine eigene Federated Credential:

```bash
# Für Environment: dev
az ad app federated-credential create \
  --id $CLIENT_ID \
  --parameters '{
    "name": "github-env-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_ORG>/service-cert-management:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Für Environment: staging
az ad app federated-credential create \
  --id $CLIENT_ID \
  --parameters '{
    "name": "github-env-staging",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_ORG>/service-cert-management:environment:staging",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Für Environment: prod
az ad app federated-credential create \
  --id $CLIENT_ID \
  --parameters '{
    "name": "github-env-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_ORG>/service-cert-management:environment:prod",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 1.4 RBAC Rolle zuweisen

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SP_OBJECT_ID=$(az ad sp show --id $CLIENT_ID --query id -o tsv)

# Contributor auf Subscription (oder pro Resource Group)
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

---

## Schritt 2: GitHub Secrets anlegen

### 2.1 Globale Secrets (Repository Level)

Unter **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Wert |
|---|---|
| `AZURE_CLIENT_ID` | App Registration Client ID |
| `AZURE_TENANT_ID` | Azure Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |

### 2.2 Umgebungsspezifische Secrets (Environment Level)

Unter **Settings → Environments → \<env\> → Add secret**:

Für jede Umgebung (`dev`, `staging`, `prod`) ein Secret `AZURE_CONFIG` anlegen:

```json
{
  "azure": {
    "tenantId": "<DEIN_TENANT_ID>",
    "subscriptionId": "<DEINE_SUBSCRIPTION_ID>",
    "clientId": "<DEIN_CLIENT_ID>"
  },
  "resource": {
    "location": "westeurope",
    "workload": "certmgmt",
    "environment": "dev"
  },
  "keyVault": {
    "name": "kv-certmgmt-dev-weu"
  },
  "certificate": {
    "name": "demo-cert",
    "validityDays": "1",
    "nearExpiryDays": "1"
  }
}
```

> **Hinweis:** Den `environment`-Wert und die umgebungsspezifischen Werte  
> (`validityDays`, `nearExpiryDays`) pro Umgebung anpassen.

---

## Schritt 3: GitHub Environments konfigurieren

Unter **Settings → Environments**:

| Environment | Approval | Secret |
|---|---|---|
| `dev` | Kein Approval | `AZURE_CONFIG_DEV` |
| `staging` | Kein Approval | `AZURE_CONFIG_STAGING` |
| `prod` | **Manueller Approval erforderlich** | `AZURE_CONFIG_PROD` |

---

## Schritt 4: Branch Protection für `main`

Unter **Settings → Branches → Add rule**:

- Branch name pattern: `main`
- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
  - Status Check: `ci / bicep-lint`
  - Status Check: `ci / bicep-validate`
  - Status Check: `ci / powershell-lint`
- ✅ Require branches to be up to date before merging

---

## Schritt 5: Lokale Konfiguration

```bash
# Vorlage kopieren
cp example.config.json config.json

# config.json mit eigenen Werten befüllen
# (config.json wird nicht ins Repository eingecheckt)
```

---

## Troubleshooting

### OIDC Fehler: "Subject does not match"

Prüfe ob der `subject`-Wert in der Federated Credential exakt mit dem GitHub Environment übereinstimmt:

```
repo:<ORG>/<REPO>:environment:<ENV_NAME>
```

### Bicep Deploy schlägt fehl: "Insufficient permissions"

Stelle sicher dass der Service Principal die Rolle `User Access Administrator` hat –  
diese wird für RBAC Assignments innerhalb der Bicep-Vorlage benötigt.