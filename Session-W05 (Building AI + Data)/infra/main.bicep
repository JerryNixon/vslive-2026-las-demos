targetScope = 'resourceGroup'

@description('Azure region')
param location string

@description('SQL admin username')
param sqlAdminLogin string = 'sqladmin'

@description('SQL admin password')
@secure()
param sqlAdminPassword string

// ──────────── Naming ────────────
var suffix      = uniqueString(resourceGroup().id)
var sqlServer   = 'sql-w05-${suffix}'
var dbName      = 'AiDemoDb'
var storageName = 'stw05${suffix}'
var aspName     = 'asp-w05-${suffix}'
var funcName    = 'func-w05-${suffix}'
var acrName     = 'acrw05${suffix}'
var caeName     = 'cae-w05-${suffix}'
var lawName     = 'law-w05-${suffix}'
var dabAppName  = 'ca-dab-api'

// ════════════════════════════════
//  SQL Server
// ════════════════════════════════

resource sql 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServer
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
  }
}

resource fwAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sql
  name: 'AllowAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource db 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sql
  name: dbName
  location: location
  sku: { name: 'GP_S_Gen5_2', tier: 'GeneralPurpose' }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368
    autoPauseDelay: 60
    minCapacity: json('0.5')
  }
}

// ════════════════════════════════
//  Storage (required by Functions)
// ════════════════════════════════

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
}

// ════════════════════════════════
//  App Service Plan (Consumption)
// ════════════════════════════════

resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: aspName
  location: location
  sku: { name: 'B1', tier: 'Basic' }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// ════════════════════════════════
//  Function App
// ════════════════════════════════

resource func 'Microsoft.Web/sites@2023-01-01' = {
  name: funcName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'dotnet-isolated' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'SqlConnection', value: 'Server=${sql.properties.fullyQualifiedDomainName};Database=${dbName};User Id=${sqlAdminLogin};Password=${sqlAdminPassword};TrustServerCertificate=true;Encrypt=true;' }
        { name: 'OpenAI__Endpoint', value: 'https://jnixon-openai.cognitiveservices.azure.com/openai/v1' }
        { name: 'OpenAI__ApiKey', value: '' }
        { name: 'OpenAI__Deployment', value: 'text-embedding-3-large' }
      ]
      use32BitWorkerProcess: false
    }
    httpsOnly: true
  }
}

// ════════════════════════════════
//  Container Registry (Basic)
// ════════════════════════════════

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

// ════════════════════════════════
//  Log Analytics (required by ACA)
// ════════════════════════════════

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ════════════════════════════════
//  Container Apps Environment
// ════════════════════════════════

resource cae 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: caeName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ════════════════════════════════
//  DAB Container App (placeholder — updated by azure-up.ps1)
// ════════════════════════════════

resource dabApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: dabAppName
  location: location
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5000
        transport: 'auto'
      }
      secrets: [
        {
          name: 'db-conn-string'
          value: 'Server=${sql.properties.fullyQualifiedDomainName};Database=${dbName};User Id=${sqlAdminLogin};Password=${sqlAdminPassword};TrustServerCertificate=true;Encrypt=true;'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'dab-api'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'DATABASE_CONNECTION_STRING'
              secretRef: 'db-conn-string'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ════════════════════════════════
//  Outputs
// ════════════════════════════════

output SQL_SERVER_FQDN string = sql.properties.fullyQualifiedDomainName
output SQL_SERVER_NAME string = sql.name
output DB_NAME string = dbName
output FUNC_APP_NAME string = func.name
output STORAGE_NAME string = storage.name
output ACR_NAME string = acr.name
output ACR_LOGIN_SERVER string = acr.properties.loginServer
output DAB_ENDPOINT_URL string = 'https://${dabApp.properties.configuration.ingress.fqdn}'
