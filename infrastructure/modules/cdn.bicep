@description('Azure Front Door profile name')
param profileName string

@description('Azure Front Door endpoint name')
param endpointName string

@description('Origin storage blob host name (e.g. lughataistorage.blob.core.windows.net)')
param storageHostName string

// ── Front Door Profile (Standard) ─────────────────────────────────────────
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: 'Global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: endpointName
  location: 'Global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource audioOriginGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: '${endpointName}-audio'
  properties: {
    healthProbeSettings: {
      probeIntervalInSeconds: 120
      probePath: '/frontdoor-health'
      probeProtocol: 'Https'
      probeRequestType: 'HEAD'
    }
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: 0
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    sessionAffinityState: 'Disabled'
  }
}

resource blobOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: audioOriginGroup
  name: 'blob-origin'
  properties: {
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    hostName: storageHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: storageHostName
    priority: 1
    weight: 1000
  }
}

// ── Front Door route for public audio files ───────────────────────────────
resource audioRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: frontDoorEndpoint
  name: endpointName
  properties: {
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
    }
    enabledState: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
    originGroup: {
      id: audioOriginGroup.id
    }
    patternsToMatch: [
      '/audio/*'
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
output endpointUrl string = 'https://${frontDoorEndpoint.properties.hostName}'
output endpointHostName string = frontDoorEndpoint.properties.hostName
