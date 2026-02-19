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

@description('Key Vault Resource ID (Source)')
param keyVaultId string

@description('Key Vault Name')
param keyVaultName string

@description('Function App Resource ID (Target)')
param functionAppId string

@description('Function App Name')
param functionAppName string

@description('Storage Account Name für Dead Letter')
param storageAccountName string

@description('Maximale Anzahl Delivery-Versuche')
@minValue(1)
@maxValue(30)
param maxDeliveryAttempts int = 30

@description('Event Time-to-Live in Minuten')
@minValue(1)
@maxValue(1440)
param eventTimeToLiveInMinutes int = 1440

// Variables für Naming (Microsoft CAF)
var systemTopicName = 'evgt-${workload}-${environment}-${uniqueString(location)}'
var eventSubscriptionName = 'evgs-${workload}-${environment}-certnearexpiry'
var deadLetterContainerName = 'deadletter'

// Storage Account Reference (existing)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Dead Letter Container
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccountName}/default/${deadLetterContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

// Event Grid System Topic (Key Vault als Source)
resource systemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: systemTopicName
  location: location
  tags: tags
  properties: {
    source: keyVaultId
    topicType: 'Microsoft.KeyVault.vaults'
  }
}

// Event Subscription (Certificate Near Expiry → Function)
resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  name: eventSubscriptionName
  parent: systemTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionAppId}/functions/CertRenewalFunction'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.KeyVault.CertificateNearExpiry'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: maxDeliveryAttempts
      eventTimeToLiveInMinutes: eventTimeToLiveInMinutes
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: deadLetterContainerName
      }
    }
  }
}

// Outputs
@description('Event Grid System Topic ID')
output systemTopicId string = systemTopic.id

@description('Event Grid System Topic Name')
output systemTopicName string = systemTopic.name

@description('Event Subscription ID')
output eventSubscriptionId string = eventSubscription.id

@description('Event Subscription Name')
output eventSubscriptionName string = eventSubscription.name
