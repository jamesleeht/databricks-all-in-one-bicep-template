
targetScope = 'subscription'

@description('')
param userObjectId string
var storageSuffix = environment().suffixes.storage

@description('Auto generate prefix based on subscription')
param prefix string = 'ss${uniqueString(guid(subscription().subscriptionId))}'

var storageAccountName = '${substring(prefix, 0, 10)}stg01'
var keyVaultName = '${substring(prefix, 0, 6)}kv01'
var resourceGroupName = '${substring(prefix, 0, 6)}-rg'
var adbWorkspaceName = '${substring(prefix, 0, 6)}AdbWksp'
var nsgName = '${substring(prefix, 0, 6)}nsg'
var firewallName = '${substring(prefix, 0, 6)}HubFW'
var firewallPublicIpName = '${substring(prefix, 0, 6)}FWPIp'
var fwRoutingTable = '${substring(prefix, 0, 6)}AdbRoutingTbl'
var clientPcName = '${substring(prefix, 0, 6)}ClientPc'
var eHNameSpace = '${substring(prefix, 0, 6)}eh'
// creating the event hub same as namespace
var eventHubName = eHNameSpace 

@description('')
param hubVnetName string
@description('')
param spokeVnetName string
@description('')
param location string
@description('')
param adminUsername string
@description('')
@secure()
param adminPassword string

// @allowed([
//   'new'
//   'existing'
// ])
// @description('')
// param newOrExisting string = 'existing'

@description('')
param webappDestinationAddresses array
@description('')
param logBlobstorageDomains array
@description('')
param extendedInfraIp array
@description('')
param sccReplayDomain array
@description('')
param metastoreDomains array
@description('')
param eventHubEndpointDomain array
@description('')
param artifactBlobStoragePrimaryDomains array
@description('')
param SpokeVnetCidr string
@description('')
param HubVnetCidr string
@description('')
param PrivateSubnetCidr string
@description('')
param PublicSubnetCidr string
@description('')
param FirewallSubnetCidr string
@description('')
param PrivateLinkSubnetCidr string


module rg './resourcegroup/rg.template.bicep' = {
  scope: subscription()
  name: 'ResourceGroup'
  params: {
    location: location
    resourceGroupName:resourceGroupName 
  }
  
}

module routeTable './network/routetable.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'RouteTable'
  params: {
    routeTableName: fwRoutingTable
  }
  dependsOn:[
    rg
  ]
}
module nsg './network/securitygroup.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'NetworkSecurityGroup'
  params: {
    securityGroupName: nsgName
  }
  dependsOn:[
    rg
  ]
}
module vnets './network/vnet.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'HubandSpokeVNET'
  params: {
    hubVnetName: hubVnetName
    spokeVnetName: spokeVnetName
    routeTableName: routeTable.outputs.routeTblName
    securityGroupName: nsg.outputs.nsgName
    firewallSubnetCidr: FirewallSubnetCidr
    hubVnetCidr: HubVnetCidr
    spokeVnetCidr: SpokeVnetCidr
    publicSubnetCidr: PublicSubnetCidr
    privateSubnetCidr: PrivateSubnetCidr
    privatelinkSubnetCidr: PrivateLinkSubnetCidr
  }
  dependsOn:[
    rg
  ]
}

module adb './databricks/workspace.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'DatabricksWorkspace'
  params: {
    vnetName: spokeVnetName
    adbWorkspaceSkuTier: 'premium'
    adbWorkspaceName: adbWorkspaceName
  }
  dependsOn:[
    rg
    vnets
  ]
}

module hubFirewall './network/firewall.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'HubFirewall'
  params: {
    firewallName: firewallName
    publicIpAddressName: firewallPublicIpName
    vnetName: hubVnetName
    webappDestinationAddresses: webappDestinationAddresses
    logBlobstorageDomains: logBlobstorageDomains
    infrastructureDestinationAddresses: extendedInfraIp
    sccRelayDomains: sccReplayDomain
    metastoreDomains: metastoreDomains
    eventHubEndpointDomains: eventHubEndpointDomain
    artifactBlobStoragePrimaryDomains: artifactBlobStoragePrimaryDomains
    dbfsBlobStrageDomain: array('${adb.outputs.databricks_dbfs_storage_accountName}.blob.${storageSuffix}')
    clientPrivateIpAddr: clientpc.outputs.clientPrivateIpaddr
  }
  dependsOn:[
    rg
  ]
}

module adlsGen2 './storage/storageaccount.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'StorageAccount'
  params: {
    storageAccountName: storageAccountName
  }
  dependsOn:[
    rg
  ]
}

module keyVault './keyvault/keyvault.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'KeyVault'
  params: {
    keyVaultName: keyVaultName
    objectId: userObjectId
  }
  dependsOn:[
    rg
  ]
}

module clientpc './other/clientdevice.template.bicep' = {
  name: 'ClientPC'
  scope: resourceGroup(resourceGroupName)
  params: {
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: hubVnetName
    clientPcName: clientPcName
  }
  dependsOn: [
    rg
    vnets
  ]
}

module loganalytics './monitor/loganalytics.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'loganalytics'
  dependsOn:[
    rg
  ]
}

module eventHubLogging './monitor/eventhub.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'EventHub'
  params: {
    namespaceName: eHNameSpace
  }
  dependsOn:[
    rg
  ]
}

module privateEndPoints './network/privateendpoint.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'PrivateEndPoints'
  params: {
    keyvaultName: keyVault.name
    keyvaultPrivateLinkResource: keyVault.outputs.keyvault_id
    privateLinkSubnetId: vnets.outputs.privatelinksubnet_id
    storageAccountName: adlsGen2.name
    storageAccountPrivateLinkResource: adlsGen2.outputs.storageaccount_id
    eventHubName: eventHubName
    eventHubPrivateLinkResource: eventHubLogging.outputs.eHNamespaceId
    targetSubResourceDfs: 'dfs'
    targetSubResourceVault: 'vault'
    targetSubResourceEventHub: 'namespace'
    vnetName: spokeVnetName
  }
  dependsOn:[
    rg
  ]
}

module createDatabricksCluster './databricks/deployment.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'createDatabricksCluster'
  params: {
    location: location
    pat_lifetime: '3600'
  }
  
}

module createAKVsecrets './keyvault/keyvaultsecrets.template.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'AddSecrets'
  params: {
    EventHubPK: eventHubLogging.outputs.eHPConnString
    keyVaultName: keyVaultName
    LogAWkspId: loganalytics.outputs.logAnalyticsWkspId
    LogAWkspkey: loganalytics.outputs.primarySharedKey
    StorageAccountKey1: adlsGen2.outputs.key1
    StorageAccountKey2: adlsGen2.outputs.key2
  }
  dependsOn:[
    rg
  ]
}

output resourceGroupName string = rg.name
output keyVaultName string = keyVaultName
output adbWorkspaceName string = adbWorkspaceName
output storageAccountName string = storageAccountName
output storageKey1 string = adlsGen2.outputs.key1
output storageKey2 string = adlsGen2.outputs.key2
output databricksWksp string = adb.outputs.databricks_workspace_id
output databricks_workspaceUrl string = adb.outputs.databricks_workspaceUrl
output keyvault_id string = keyVault.outputs.keyvault_id
output keyvault_uri string = keyVault.outputs.keyvault_uri
output logAnalyticsWkspId string = loganalytics.outputs.logAnalyticsWkspId
output logAnalyticsprimarySharedKey string = loganalytics.outputs.primarySharedKey
output logAnalyticssecondarySharedKey string = loganalytics.outputs.secondarySharedKey
output eHNamespaceId string = eventHubLogging.outputs.eHNamespaceId
output eHubNameId string = eventHubLogging.outputs.eHubNameId
output eHAuthRulesId string = eventHubLogging.outputs.eHAuthRulesId
output eHPConnString string = eventHubLogging.outputs.eHPConnString
output dsOutputs object = createDatabricksCluster.outputs.dsOutputs
