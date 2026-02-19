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
var keyVaultName = 'kv-${workload}-${environment}-${uniqueString(resourceGroup().id, location)}'

// Soft Delete nur in prod aktiviert
var enableSoftDelete = environment == 'prod'
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
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: enableSoftDelete ? softDeleteRetentionInDays : null
    enablePurgeProtection: enablePurgeProtection
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

// Outputs
@description('Key Vault Resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Certificate Validity Days (für Parameter-Weitergabe)')
output certificateValidityDays int = certificateValidityDays

@description('Certificate Near-Expiry Days (für Parameter-Weitergabe)')
output certificateNearExpiryDays int = certificateNearExpiryDays
