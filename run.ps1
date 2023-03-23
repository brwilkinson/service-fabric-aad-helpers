$Base = $PSScriptRoot
$t = Get-AzContext | ForEach-Object Tenant | ForEach-Object Id
$prefix = 'acu1'
$org = 'pe'
$app = 'sfm'
$env = 'd1'

$clusterName = "$prefix-$org-$app-$env-sfm01"
$reply =  "https://$clusterName.centralus.cloudapp.azure.com:29080/Explorer"

$Params = @{
    TenantId               = $t
    ClusterName            = $clusterName
    WebApplicationReplyUrl = $reply
    WebApplicationUri      = "api://$t/$clusterName"
    AddResourceAccess      = $true
}

$Configobj = . $Base\SetupApplications.ps1 @Params