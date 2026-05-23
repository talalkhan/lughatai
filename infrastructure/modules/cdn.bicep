@description('CDN profile name')
param profileName string

@description('CDN endpoint name')
param endpointName string

@description('Origin storage blob host name (e.g. lughataistorage.blob.core.windows.net)')
param storageHostName string

// ── CDN Profile (Standard Microsoft) ──────────────────────────────────────
resource cdnProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: 'Global'
  sku: {
    name: 'Standard_Microsoft'
  }
}

// ── CDN Endpoint pointing at Blob Storage ──────────────────────────────────
resource cdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2023-05-01' = {
  name: endpointName
  parent: cdnProfile
  location: 'Global'
  properties: {
    originHostHeader: storageHostName
    isHttpAllowed: false
    isHttpsAllowed: true
    queryStringCachingBehavior: 'IgnoreQueryString'
    optimizationType: 'GeneralMediaStreaming'
    origins: [
      {
        name: 'blob-origin'
        properties: {
          hostName: storageHostName
          httpsPort: 443
          originHostHeader: storageHostName
        }
      }
    ]
    deliveryPolicy: {
      rules: [
        {
          name: 'EnforceHTTPS'
          order: 1
          conditions: [
            {
              name: 'RequestScheme'
              parameters: {
                typeName: 'DeliveryRuleRequestSchemeConditionParameters'
                matchValues: ['HTTP']
                operator: 'Equal'
                negateCondition: false
              }
            }
          ]
          actions: [
            {
              name: 'UrlRedirect'
              parameters: {
                typeName: 'DeliveryRuleUrlRedirectActionParameters'
                redirectType: 'PermanentRedirect'
                destinationProtocol: 'Https'
              }
            }
          ]
        }
      ]
    }
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
output endpointUrl string = 'https://${cdnEndpoint.properties.hostName}'
output endpointHostName string = cdnEndpoint.properties.hostName
