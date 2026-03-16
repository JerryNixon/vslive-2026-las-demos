targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string

@description('SQL Server admin username')
param sqlAdminLogin string = 'sqladmin'

@description('SQL Server admin password')
@secure()
param sqlAdminPassword string

// ──────────────────── Naming ────────────────────────
var suffix        = uniqueString(resourceGroup().id)
var sqlServerName = 'sql-h06-${suffix}'
var acrName       = 'acrh06${suffix}'
var caeName       = 'cae-h06-${suffix}'
var lawName       = 'law-h06-${suffix}'
var dabAppName    = 'ca-dab-api'

// ════════════════════════════════════════════════════
//  SQL Server
// ════════════════════════════════════════════════════

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
  }
}

// Allow Azure services (ACA → SQL)
resource fwAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// CRM Database – free tier (serverless Gen5)
resource crmDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'CrmDb'
  location: location
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368
    autoPauseDelay: 60
    minCapacity: json('0.5')
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
  }
}

// Company Database – Basic tier (cheapest paid ~$5/mo)
resource companyDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'CompanyDb'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

// ════════════════════════════════════════════════════
//  Container Registry (Basic – cheapest)
// ════════════════════════════════════════════════════

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ════════════════════════════════════════════════════
//  Log Analytics (required for ACA)
// ════════════════════════════════════════════════════

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ════════════════════════════════════════════════════
//  Container Apps Environment (Consumption – free tier)
// ════════════════════════════════════════════════════

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

// ════════════════════════════════════════════════════
//  DAB Container App (placeholder image – updated by post-provision script)
// ════════════════════════════════════════════════════

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
          name: 'crm-conn-string'
          value: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database=CrmDb;User Id=crmUser;Password=P@ssw0rd!;TrustServerCertificate=true;Encrypt=true;'
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
              name: 'CRM_CONNECTION_STRING'
              secretRef: 'crm-conn-string'
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

// ════════════════════════════════════════════════════
//  Outputs (consumed by post-provision script via azd env)
// ════════════════════════════════════════════════════

output SQL_SERVER_FQDN string = sqlServer.properties.fullyQualifiedDomainName
output SQL_SERVER_NAME string = sqlServer.name
output SQL_ADMIN_LOGIN string = sqlAdminLogin
output ACR_NAME string = acr.name
output ACR_LOGIN_SERVER string = acr.properties.loginServer
output DAB_ENDPOINT_URL string = 'https://${dabApp.properties.configuration.ingress.fqdn}'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer
