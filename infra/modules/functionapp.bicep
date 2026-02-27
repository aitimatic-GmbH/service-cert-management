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

// Variables für Naming (Microsoft CAF)
// Storage Account: max 24 Zeichen, nur lowercase + digits
var storageAccountName = 'st${workload}${environment}${uniqueString(resourceGroup().id)}'
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
      ]
    }
  }
}

// Outputs
@description('Function App Resource ID')
output functionAppId string = functionApp.id

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App Principal ID (Managed Identity)')
output principalId string = functionApp.identity.principalId

@description('Function App Default Hostname')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('Storage Account Name')
output storageAccountName string = storageAccount.name
