@description('Azure Region für die Ressourcen')
param location string

@description('Umgebung (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Workload-Name für Naming Convention')
param workload string

@description('Tags für alle Ressourcen')
param tags object

@description('Application Insights Resource ID für Diagnostic Settings')
param appInsightsId string

@description('Zertifikat Gültigkeitsdauer in Tagen')
param certificateValidityDays int

@description('Tage vor Ablauf für Near-Expiry Event')
param certificateNearExpiryDays int

@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

@description('Soft Delete Retention in Tagen (nur wenn Soft Delete aktiviert)')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

// Variables für Naming (Microsoft CAF)
// Key Vault: max 24 Zeichen. 'kv-' (3) + workload (max 8) + '-' (1) + envAbbr (max 4) + '-' (1) + suffix (5) = max 22
var envAbbr = environment == 'staging' ? 'stg' : environment
var keyVaultName = 'kv-${workload}-${envAbbr}-${take(uniqueString(resourceGroup().id, location), 5)}'

// Purge Protection nur in prod aktiviert (einmal aktiviert nicht mehr deaktivierbar → nur true oder weglassen)
var enablePurgeProtection = environment == 'prod'

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    // Soft Delete ist ab API 2021+ immer aktiviert, Retention kurz in dev/staging für schnelle Iteration
    softDeleteRetentionInDays: environment == 'prod' ? softDeleteRetentionInDays : 7
    // Purge Protection nur in prod: Eigenschaft weglassen wenn false (Azure erlaubt kein explizites false)
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Diagnostic Settings für Key Vault
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${keyVaultName}'
  scope: keyVault
  properties: {
    workspaceId: appInsightsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Ausgaben
@description('Key Vault Ressourcen-ID')
output keyVaultId string = keyVault.id

@description('Key Vault-URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault-Name')
output keyVaultName string = keyVault.name

@description('Zertifikat-Gültigkeitsdauer in Tagen (für Parameter-Weitergabe)')
output certificateValidityDays int = certificateValidityDays

@description('Tage vor Ablauf für Near-Expiry Event (für Parameter-Weitergabe)')
output certificateNearExpiryDays int = certificateNearExpiryDays
