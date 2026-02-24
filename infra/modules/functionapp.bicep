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

@description('Application Insights Connection String')
@secure()
param appInsightsConnectionString string

@description('Application Insights Instrumentation Key')
@secure()
param appInsightsInstrumentationKey string

@description('Function App Runtime')
@allowed([
  'dotnet'
  'node'
  'python'
  'java'
  'powershell'
])
param functionRuntime string = 'powershell'

@description('Function App Runtime Version')
param functionRuntimeVersion string = '7.4'

@description('Functions Extension Version')
param functionsExtensionVersion string = '~4'

@description('Storage Account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Gültigkeitsdauer neuer Zertifikate in Tagen (CERT_VALIDITY_DAYS App Setting)')
@minValue(1)
param certificateValidityDays int = 365

// Variables für Naming (Microsoft CAF)
// Storage Account: max 24 Zeichen, nur lowercase + digits
// 'st' (2) + workload[:6] (6) + environment[:3] (3) + suffix[:13] (13) = 24
var storageAccountName = 'st${take(workload, 6)}${take(environment, 3)}${take(uniqueString(resourceGroup().id), 13)}'
var appServicePlanName = 'plan-${workload}-${environment}-${uniqueString(location)}'
var functionAppName = 'func-${workload}-${environment}-${uniqueString(location)}'

// Storage Account (erforderlich für Function App)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true  // Linux-basiert
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: '${toUpper(functionRuntime)}|${functionRuntimeVersion}'
      powerShellVersion: functionRuntime == 'powershell' ? functionRuntimeVersion : null
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionsExtensionVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'PSWorkerInProcConcurrencyUpperBound'
          value: '1'
        }
        {
          name: 'CERT_VALIDITY_DAYS'
          value: string(certificateValidityDays)
        }
      ]
    }
  }
}

// Ausgaben
@description('Function App Ressourcen-ID')
output functionAppId string = functionApp.id

@description('Function App-Name')
output functionAppName string = functionApp.name

@description('Managed Identity Principal-ID der Function App')
output principalId string = functionApp.identity.principalId

@description('Function App Standard-Hostname')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('Storage Account-Name')
output storageAccountName string = storageAccount.name
