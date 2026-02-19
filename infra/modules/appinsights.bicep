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

@description('Log Analytics SKU')
@allowed([
  'Free'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Log Analytics Retention in Tagen')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionInDays int = 30

// Variables für Naming (Microsoft CAF)
var logAnalyticsWorkspaceName = 'log-${workload}-${environment}-${uniqueString(location)}'
var appInsightsName = 'appi-${workload}-${environment}-${uniqueString(location)}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: logAnalyticsRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Outputs
@description('Application Insights Resource ID')
output appInsightsId string = appInsights.id

@description('Application Insights Instrumentation Key')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output connectionString string = appInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output workspaceName string = logAnalyticsWorkspace.name
