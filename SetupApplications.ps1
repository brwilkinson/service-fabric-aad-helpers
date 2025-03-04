﻿<#
.SYNOPSIS
Setup applications in a Service Fabric cluster Azure Active Directory tenant.

.DESCRIPTION
version: 2.0.1

Prerequisites:
1. An Azure Active Directory tenant.
2. A Global Admin user within tenant.

.PARAMETER TenantId
ID of tenant hosting Service Fabric cluster.

.PARAMETER WebApplicationName
Name of web application representing Service Fabric cluster.

.PARAMETER WebApplicationUri
App ID URI of web application. If using https:// format, the domain has to be a verified domain. Format: https://<Domain name of cluster>
Example: 'https://mycluster.contoso.com'
Alternatively api:// format can be used which does not require a verified domain. Format: api://<tenant id>/<cluster name>
Example: 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster'

.PARAMETER WebApplicationReplyUrl
Reply URL of web application. Format: https://<Domain name of cluster>:<Service Fabric Http gateway port>
Example: 'https://mycluster.westus.cloudapp.azure.com:19080'

.PARAMETER NativeClientApplicationName
Name of native client application representing client.

.PARAMETER ClusterName
A friendly Service Fabric cluster name. Application settings generated from cluster name: WebApplicationName = ClusterName + "_Cluster", NativeClientApplicationName = ClusterName + "_Client"

.PARAMETER Location
Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.

.PARAMETER AddResourceAccess
Used to add the cluster application's resource access to "Windows Azure Active Directory" application explicitly when AAD is not able to add automatically. This may happen when the user account does not have adequate permission under this subscription.

.PARAMETER signInAudience
Sign in audience option for selection of Applicaiton AAD tenant configuration type. Default selection is 'AzureADMyOrg'
'AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount'

.PARAMETER timeoutMin
Script execution retry wait timeout in minutes. Default is 5 minutes. If script times out, it can be re-executed and will continue configuration as script is idempotent.

.PARAMETER force
Use Force switch to force new authorization to acquire new token.

.PARAMETER remove
Use Remove to remove AAD configuration for provided cluster.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup tenant with default settings generated from a friendly cluster name.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -WebApplicationName 'SFWeb' -WebApplicationUri 'https://mycluster.contoso.com' -WebApplicationReplyUrl 'https://mycluster.contoso:19080' -NativeClientApplicationName 'SFnative'

Setup tenant with explicit application settings.

.EXAMPLE
. $configObj = Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup and save the setup result into a temporary variable to pass into SetupUser.ps1
#>
[cmdletbinding()]
Param
(
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $TenantId,

    [Parameter(ParameterSetName = 'Customize')]	
    [String]
    $webApplicationName,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    $WebApplicationUri,

    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $WebApplicationReplyUrl,
	
    [Parameter(ParameterSetName = 'Customize')]
    [String]
    $NativeClientApplicationName,

    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $ClusterName,

    [Parameter(ParameterSetName = 'Prefix')]
    [Parameter(ParameterSetName = 'Customize')]
    [ValidateSet('us', 'china')]
    [String]
    $Location,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $AddResourceAccess,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount')]
    $signInAudience = 'AzureADMyOrg',

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [int]
    $timeoutMin = 5,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [string]
    $logFile,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]$force,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $remove
)

$headers = $null
. "$PSScriptRoot\Common.ps1"
$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}"
$global:ConfigObj = @{}
$sleepSeconds = 5
$msGraphUserReadAppId = '00000003-0000-0000-c000-000000000000'
$msGraphUserReadId = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'

function main () {
    try {
        if ($logFile) {
            Start-Transcript -path $logFile -Force
        }

        enable-AAD
    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
        write-error $errorString
    }
    finally {
        if ($logFile) {
            Stop-Transcript
        }
    }
}

function add-appRegistration($WebApplicationUri, $WebApplicationReplyUrl, $requiredResourceAccess) {
    #Create Web Application
    write-host "creating app registration with $WebApplicationUri." -foregroundcolor yellow
    $webApp = @{}
    $appRole = @(@{
            allowedMemberTypes = @('User')
            description        = 'ReadOnly roles have limited query access'
            displayName        = 'ReadOnly'
            id                 = [guid]::NewGuid()
            isEnabled          = $true
            value              = 'User'
        }, @{
            allowedMemberTypes = @('User')
            description        = 'Admins can manage roles and perform all task actions'
            displayName        = 'Admin'
            id                 = [guid]::NewGuid()
            isEnabled          = $true
            value              = 'Admin'
        })

    $uri = [string]::Format($graphAPIFormat, 'applications')
    $webAppResource = @{
        homePageUrl           = $WebApplicationReplyUrl
        redirectUris          = @($WebApplicationReplyUrl)
        implicitGrantSettings = @{
            enableAccessTokenIssuance = $false
            enableIdTokenIssuance     = $true
        }
    }
    
    if ($AddResourceAccess) {
        $webApp = @{
            displayName            = $webApplicationName
            signInAudience         = $signInAudience
            identifierUris         = @($WebApplicationUri)
            defaultRedirectUri     = $WebApplicationReplyUrl
            appRoles               = $appRole
            requiredResourceAccess = $requiredResourceAccess
            web                    = $webAppResource
        }
    }
    else {
        $webApp = @{
            displayName        = $webApplicationName
            signInAudience     = $signInAudience
            identifierUris     = @($WebApplicationUri)
            defaultRedirectUri = $WebApplicationReplyUrl
            appRoles           = $appRole
            web                = $webAppResource
        }
    }

    # add
    $webApp = invoke-graphApi -retry -uri $uri -body $webApp -method 'post'

    if ($webApp) {
        $stopTime = set-stopTime $timeoutMin
        
        while (!($webApp.api.oauth2PermissionScopes.gethashcode())) {
            $webApp = wait-forResult -functionPointer (get-item function:\get-appRegistration) `
                -message "waiting for app registration completion" `
                -stopTime $stopTime `
                -WebApplicationUri $WebApplicationUri
            start-sleep -Seconds $sleepSeconds
        }
    }

    return $webApp
}

function add-nativeClient($webApp, $requiredResourceAccess, $oauthPermissionsId) {
    #Create Native Client Application
    $uri = [string]::Format($graphAPIFormat, "applications")
    $nativeAppResourceAccess = @($requiredResourceAccess.Clone())
    
    # todo not working in ms sub tenant
    # could be because of resource not existing?
    $nativeAppResourceAccess += @{
        resourceAppId  = $webApp.appId
        resourceAccess = @(@{
                id   = $oauthPermissionsId
                type = 'Scope'
            })
    }

    $nativeAppResource = @{
        publicClient           = @{
            redirectUris = @("urn:ietf:wg:oauth:2.0:oob") 
        }
        displayName            = $NativeClientApplicationName
        signInAudience         = $signInAudience
        isFallbackPublicClient = $true
        requiredResourceAccess = $nativeAppResourceAccess
    }

    $nativeApp = invoke-graphApi -retry -uri $uri -body $nativeAppResource -method 'post'

    if ($nativeApp) {
        $null = wait-forResult -functionPointer (get-item function:\get-nativeClient) `
            -message "waiting for native app registration completion" `
            -WebApplicationUri $WebApplicationUri `
            -NativeClientApplicationName $NativeClientApplicationName
    }

    return $nativeApp
}

function add-oauthPermissions($webApp, $webApplicationName) {
    write-host "adding user_impersonation scope"
    $patchApplicationUri = $graphAPIFormat -f ("applications/{0}" -f $webApp.Id)
    $webApp.api.oauth2PermissionScopes = @($webApp.api.oauth2PermissionScopes)
    $userImpersonationScopeId = [guid]::NewGuid()
    $webApp.api.oauth2PermissionScopes += @{
        id                      = $userImpersonationScopeId
        isEnabled               = $true
        type                    = "User"
        adminConsentDescription = "Allow the application to access $webApplicationName on behalf of the signed-in user."
        adminConsentDisplayName = "Access $webApplicationName"
        userConsentDescription  = "Allow the application to access $webApplicationName on your behalf."
        userConsentDisplayName  = "Access $webApplicationName"
        value                   = "user_impersonation"
    }

    $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
        -message "waiting for patch application uri to be available" `
        -uri $patchApplicationUri `
        -method get

    # timing issue even when call above successful
    $result = invoke-graphApi -retry -uri $patchApplicationUri -method 'patch' -body @{
        'api' = @{
            "oauth2PermissionScopes" = $webApp.api.oauth2PermissionScopes
        }
    }

    if ($result) {
        $null = wait-forResult -functionPointer (get-item function:\get-OauthPermissions) `
            -message "waiting for oauth permission completion" `
            -webApp $webApp
    }

    return $userImpersonationScopeId
}

function add-servicePrincipal($webApp, $assignmentRequired) {
    #Service Principal
    write-host "adding service principal: $($webapp.appid)"
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals")
    $servicePrincipal = @{
        accountEnabled            = $true
        appId                     = $webApp.appId
        displayName               = $webApp.displayName
        appRoleAssignmentRequired = $assignmentRequired
    }

    $servicePrincipal = invoke-graphApi -retry -uri $uri -body $servicePrincipal -method 'post'

    if ($servicePrincipal) {
        $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
            -message "waiting for service principal creation completion" `
            -webApp $webApp
    }

    return $servicePrincipal
}

function add-servicePrincipalGrants($servicePrincipalNa, $servicePrincipal) {
    #OAuth2PermissionGrant
    #AAD service principal
    $AADServicePrincipalId = (get-servicePrincipalAAD).value.Id
    assert-notNull $AADServicePrincipalId 'aad app service principal enumeration failed'
    $global:currentGrants = get-oauthPermissionGrants($servicePrincipalNa.Id)
    $result = $currentGrants
    
    $scope = "User.Read"
    if (!$currentGrants -or !($currentGrants.scope.Contains($scope))) {
        $result = add-servicePrincipalGrantScope -clientId $servicePrincipalNa.Id -resourceId $AADServicePrincipalId -scope $scope
    }

    $scope = "user_impersonation"
    if (!$currentGrants -or !($currentGrants.scope.Contains($scope))) {
        $result = $result -and (add-servicePrincipalGrantScope -clientId $servicePrincipalNa.Id -resourceId $servicePrincipal.Id -scope $scope)
    }

    return $result
}

function add-servicePrincipalGrantScope($clientId, $resourceId, $scope) {
    $uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants")
    $oauth2PermissionGrants = @{
        clientId    = $clientId
        consentType = "AllPrincipals"
        resourceId  = $resourceId
        scope       = $scope
        startTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
        expiryTime  = (Get-Date).AddYears(1800).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    }

    $result = invoke-graphApi -uri $uri -body $oauth2PermissionGrants -method 'post'
    assert-notNull $result "aad app service principal oauth permissions $scope configuration failed"

    if ($result) {
        $stopTime = set-stopTime $timeoutMin
        $checkGrants = $null
        
        while (!$checkGrants -or !($checkGrants.scope.Contains($scope))) {
            $checkGrants = wait-forResult -functionPointer (get-item function:\get-oauthPermissionGrants) `
                -message "waiting for service principal grants creation completion" `
                -stopTime $stopTime `
                -clientId $clientId
            start-sleep -Seconds $sleepSeconds
        }
    }

    return $result
}

function enable-AAD() {
    Write-Host 'TenantId = ' $TenantId
    $configObj.ClusterName = $clusterName
    $configObj.TenantId = $TenantId
    $webApp = $null

    if (!$webApplicationName) {
        $webApplicationName = "ServiceFabricCluster"
    }
    
    if (!$WebApplicationUri) {
        $WebApplicationUri = "https://ServiceFabricCluster"
    }
    
    if (!$NativeClientApplicationName) {
        $NativeClientApplicationName = "ServiceFabricClusterNativeClient"
    }

    # MS Graph access User.Read
    $requiredResourceAccess = @(@{
            resourceAppId  = $msGraphUserReadAppId
            resourceAccess = @(@{
                    id   = $msGraphUserReadId
                    type = "Scope"
                })
        })

    # cleanup
    if ($remove) {
        write-host "removing web service principals"
        $result = remove-servicePrincipal
    
        write-host "removing web service principals"
        $result = $result -and (remove-servicePrincipalNa)

        write-warning "removing app registration"
        $result = $result -and (remove-appRegistration -WebApplicationUri $WebApplicationUri)

        write-warning "removing native app registration"
        $result = $result -and (remove-nativeClient -nativeClientApplicationName $NativeClientApplicationName)
        write-host "removal complete result:$result" -ForegroundColor Green
        return $configObj
    }
    
    # check / add app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri
    if (!$webApp) {
        $webApp = add-appRegistration -WebApplicationUri $WebApplicationUri `
            -WebApplicationReplyUrl $WebApplicationReplyUrl `
            -requiredResourceAccess $requiredResourceAccess
    }

    assert-notNull $webApp 'Web Application Creation Failed'
    $configObj.WebAppId = $webApp.appId
    Write-Host "Web Application Created: $($webApp.appId)"

    # check / add oauth user_impersonation permissions
    $oauthPermissionsId = get-OauthPermissions -webApp $webApp
    if (!$oauthPermissionsId) {
        $oauthPermissionsId = add-oauthPermissions -webApp $webApp -WebApplicationName $webApplicationName
    }
    assert-notNull $oauthPermissionsId 'Web Application Oauth permissions Failed'
    Write-Host "Web Application Oauth permissions created: $($oauthPermissionsId|convertto-json)"  -ForegroundColor Green

    # check / add servicePrincipal
    $servicePrincipal = get-servicePrincipal -webApp $webApp
    if (!$servicePrincipal) {
        $servicePrincipal = add-servicePrincipal -webApp $webApp -assignmentRequired $true
    }
    assert-notNull $servicePrincipal 'service principal configuration failed'
    Write-Host "Service Principal Created: $($servicePrincipal.appId)" -ForegroundColor Green
    $configObj.ServicePrincipalId = $servicePrincipal.Id

    # check / add native app
    $nativeApp = get-nativeClient -NativeClientApplicationName $NativeClientApplicationName -WebApplicationUri $WebApplicationUri
    if (!$nativeApp) {
        $nativeApp = add-nativeClient -webApp $webApp -requiredResourceAccess $requiredResourceAccess -oauthPermissionsId $oauthPermissionsId
    }
    assert-notNull $nativeApp 'Native Client Application Creation Failed'
    Write-Host "Native Client Application Created: $($nativeApp.appId)"  -ForegroundColor Green
    $configObj.NativeClientAppId = $nativeApp.appId

    # check / add native app service principal
    $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp
    if (!$servicePrincipalNa) {
        $servicePrincipalNa = add-servicePrincipal -webApp $nativeApp -assignmentRequired $false
    }
    assert-notNull $servicePrincipalNa 'native app service principal configuration failed'
    Write-Host "Native app service principal created: $($servicePrincipalNa.appId)" -ForegroundColor Green

    # check / add native app service principal AAD
    $servicePrincipalAAD = add-servicePrincipalGrants -servicePrincipalNa $servicePrincipalNa `
        -servicePrincipal $servicePrincipal

    assert-notNull $servicePrincipalAAD 'aad app service principal configuration failed'
    Write-Host "AAD Application Configured: $($servicePrincipalAAD)"  -ForegroundColor Green
    write-host "configobj: $($configObj|convertto-json)"

    #ARM template AAD resource
    write-host "-----ARM template-----"
    write-host "`"azureActiveDirectory`": $(@{
        tenantId           = $configObj.tenantId
        clusterApplication = $configObj.WebAppId
        clientApplication  = $configObj.NativeClientAppId
    } | ConvertTo-Json)," -ForegroundColor Cyan

    return $configObj
}

function get-appRegistration($WebApplicationUri) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"identifierUris:$WebApplicationUri`"")
   
    $webApp = (invoke-graphApi -uri $uri -method 'get').value
    write-host "currentAppRegistration:$webApp"

    if ($webApp) {
        write-host "app registration $($webApp.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "currentAppRegistration:$($webApp|convertto-json -depth 99)"
        return $webApp
    }

    return $null
}

function get-nativeClient($NativeClientApplicationName) {
    # check for existing native clinet
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"displayName:$NativeClientApplicationName`"")
   
    $nativeClient = (invoke-graphApi -uri $uri -method 'get').value
    write-host "nativeClient:$nativeClient"

    if ($nativeClient) {
        write-host "native client $($nativeClient.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "current service principal:$($nativeClient|convertto-json -depth 99)"
        return $nativeClient
    }

    return $null
}

function get-OauthPermissions($webApp) {
    # Check for an existing delegated permission with value "user_impersonation". Normally this is created by default,
    # but if it isn't, we need to update the Application object with a new one.
    $user_impersonation_scope = $webApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "user_impersonation" }

    if ($user_impersonation_scope) {
        write-host "user_impersonation scope already exists. $($user_impersonation_scope.id)" -ForegroundColor yellow
        return $user_impersonation_scope.id
    }

    return $null
}

function get-oauthPermissionGrants($clientId) {
    # get 'Windows Azure Active Directory' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants") + "?`$filter=clientId eq '$clientId'"
    $grants = invoke-graphApi -uri $uri -method 'get'
    write-verbose "grants:$($grants | convertto-json -depth 2)"
    return $grants.value
}

function get-servicePrincipal($webApp) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals?`$search=`"appId:$($webApp.appId)`"")
    $servicePrincipal = (invoke-graphApi -uri $uri -method 'get').value
    write-host "servicePrincipal:$servicePrincipal"

    if ($servicePrincipal) {
        write-host "service principal $($servicePrincipal.appId) already exists." -foregroundcolor yellow
        write-host "current service principal:$($servicePrincipal|convertto-json -depth 99)"
        return $servicePrincipal
    }

    return $null
}

function get-servicePrincipalAAD() {
    # get 'Windows Azure Active Directory' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals") + "?`$filter=appId eq '$msGraphUserReadAppId'"
    $global:AADServicePrincipal = invoke-graphApi -uri $uri -method 'get'
    write-verbose "aad service princiapal:$($AADServicePrincipal | convertto-json -depth 2)"
    return $AADServicePrincipal
}

function remove-appRegistration($WebApplicationUri) {
    # remove web app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri
    if (!$webApp) {
        return $true
    } 

    $configObj.WebAppId = $webApp.appId
    $uri = [string]::Format($graphAPIFormat, "applications/$($webApp.id)")
    $webApp = (invoke-graphApi -uri $uri -method 'delete')

    if ($webApp) {
        $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
            -message "waiting for web client delete to complete..." `
            -waitForNullResult `
            -uri $uri `
            -method 'get'
    }

    return $true
}

function remove-nativeClient($NativeClientApplicationName) {
    # remove native app registration
    $nativeApp = get-nativeClient -nativeClientApplicationName $NativeClientApplicationName
    if (!$nativeApp) {
        return $true
    }

    $uri = [string]::Format($graphAPIFormat, "applications/$($nativeApp.id)")
    $nativeApp = (invoke-graphApi -uri $uri -method 'delete')

    if ($nativeApp) {
        $configObj.NativeClientAppId = $nativeApp.appId

        $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
            -message "waiting for native client delete to complete..." `
            -waitForNullResult `
            -uri $uri `
            -method 'get'
    }

    return $true
}

function remove-servicePrincipal() {
    $result = $true
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri

    if ($webApp) {
        $servicePrincipal = get-servicePrincipal -webApp $webApp
        if ($servicePrincipal) {
            $configObj.ServicePrincipalId = $servicePrincipal.Id
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipal.id)")
            $result = $result -and (invoke-graphApi -uri $uri -method 'delete')

            if ($result) {
                $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
                    -message "waiting for web spn delete to complete..." `
                    -waitForNullResult `
                    -webApp $webApp
            }
        }
    }

    return $result
}

function remove-servicePrincipalNa() {
    $result = $true
    $nativeApp = get-nativeClient -NativeClientApplicationName $NativeClientApplicationName -WebApplicationUri $WebApplicationUri

    if ($nativeApp) {
        $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp
        if ($servicePrincipalNa) {
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipalNa.id)")
            $result = invoke-graphApi -uri $uri -method 'delete'
            if ($result) {
                $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
                    -message "waiting for native spn delete to complete..." `
                    -waitForNullResult `
                    -webApp $nativeApp
            }
        }    
    }

    return $result
}

main