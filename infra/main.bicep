targetScope = 'resourceGroup'

@description('Azure Region für die Ressourcen')
param location string = resourceGroup().location

@description('Umgebung (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Workload-Name für Naming Convention')
param workload string

@description('Log Analytics SKU')
param logAnalyticsSku string

@description('Log Analytics Retention in Tagen')
param logAnalyticsRetentionInDays int

@description('Key Vault SKU')
param keyVaultSku string

@description('Soft Delete Retention in Tagen')
param softDeleteRetentionInDays int

@description('Function App Runtime')
param functionRuntime string

@description('Function App Runtime Version')
param functionRuntimeVersion string

@description('Functions Extension Version')
param functionsExtensionVersion string

@description('Storage Account SKU')
param storageAccountSku string

@description('Maximale Anzahl Delivery-Versuche')
param maxDeliveryAttempts int

@description('Event Time-to-Live in Minuten')
param eventTimeToLiveInMinutes int

@description('Zertifikat Gültigkeitsdauer in Tagen')
param certificateValidityDays int

@description('Tage vor Ablauf für Near-Expiry Event')
param certificateNearExpiryDays int

var commonTags = {
  environment: environment
  workload: workload
  managedBy: 'bicep'
}

module appInsights 'modules/appinsights.bicep' = {
  name: 'appinsights-deployment'
  params: {
    location: location
    environment: environment
    workload: workload
    tags: commonTags
    logAnalyticsSku: logAnalyticsSku
    logAnalyticsRetentionInDays: logAnalyticsRetentionInDays
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    location: location
    environment: environment
    workload: workload
    tags: commonTags
    appInsightsId: appInsights.outputs.workspaceId
    certificateValidityDays: certificateValidityDays
    certificateNearExpiryDays: certificateNearExpiryDays
    keyVaultSku: keyVaultSku
    softDeleteRetentionInDays: softDeleteRetentionInDays
  }
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionapp-deployment'
  params: {
    location: location
    environment: environment
    workload: workload
    tags: commonTags
    appInsightsConnectionString: appInsights.outputs.connectionString
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    functionRuntime: functionRuntime
    functionRuntimeVersion: functionRuntimeVersion
    functionsExtensionVersion: functionsExtensionVersion
    storageAccountSku: storageAccountSku
  }
}

module eventGrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid-deployment'
  params: {
    location: location
    environment: environment
    workload: workload
    tags: commonTags
    keyVaultId: keyVault.outputs.keyVaultId
    keyVaultName: keyVault.outputs.keyVaultName
    functionAppId: functionApp.outputs.functionAppId
    functionAppName: functionApp.outputs.functionAppName
    storageAccountName: functionApp.outputs.storageAccountName
    maxDeliveryAttempts: maxDeliveryAttempts
    eventTimeToLiveInMinutes: eventTimeToLiveInMinutes
  }
}

resource rbacFunctionToKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, workload, environment, 'keyvault-certificates-officer')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Key Vault Name')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Function App Name')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App Hostname')
output functionAppHostName string = functionApp.outputs.functionAppHostName

@description('Application Insights Workspace Name')
output appInsightsName string = appInsights.outputs.workspaceName

@description('Event Grid System Topic Name')
output systemTopicName string = eventGrid.outputs.systemTopicName
