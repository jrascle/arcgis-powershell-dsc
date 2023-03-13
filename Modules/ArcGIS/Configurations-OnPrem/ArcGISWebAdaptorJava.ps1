Configuration ArcGISWebAdaptorJava
{
    param(
        [System.Management.Automation.PSCredential]
        $ServerPrimarySiteAdminCredential,

        [System.Management.Automation.PSCredential]
        $PortalAdministratorCredential,

        [Parameter(Mandatory=$False)]
        [System.String]
        $PrimaryServerMachine,

        [Parameter(Mandatory=$False)]
        [System.String]
        $PrimaryPortalMachine,

        [Parameter(Mandatory=$False)]
        [System.String]
        $ServerRole,

        [System.Int32]
		$WebSiteId = 1,

        [ValidateSet("Java","IIS")]
        [System.String]
        $WebAdaptorType,

        [System.String]
        $TomcatDir,

        [System.String]
        $InstallDir
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ArcGIS -ModuleVersion 4.0.2
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_WebAdaptorJava

    Node $AllNodes.NodeName
    {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }
        
        $MachineFQDN = Get-FQDN $Node.NodeName

        $Depends = @()

        ArcGIS_xFirewall "WebAdaptorFirewallRules$($Node.NodeName)"
        {
            Name                  = "WebServer-RV" 
            DisplayName           = "WebServer-RV" 
            DisplayGroup          = "WebServer-RV" 
            Ensure                = 'Present'  
            Access                = "Allow" 
            State                 = "Enabled" 
            Profile               = "Public"
            LocalPort             = ("80", "443")                         
            Protocol              = "TCP" 
        }
        $Depends += "[ArcGIS_xFirewall]WebAdaptorFirewallRules$($Node.NodeName)"

        if($Node.IsServerWebAdaptorEnabled -and $PrimaryServerMachine){
            ArcGIS_WebAdaptorJava "ConfigureServerWebAdaptor$($Node.NodeName)"
            {
                Ensure              = "Present"
                Component           = if($ServerRole -ieq "NotebookServer"){ 'NotebookServer' }elseif($ServerRole -ieq "MissionServer"){ 'MissionServer' }else{ 'Server' }
                HostName            = if($Node.SSLCertificate){ $Node.SSLCertificate.CName }else{ $MachineFQDN } 
                ComponentHostName   = (Get-FQDN $PrimaryServerMachine)
                Context             = $Node.ServerContext
                OverwriteFlag       = $False
                SiteAdministrator   = $ServerPrimarySiteAdminCredential
                AdminAccessEnabled  = if($ServerRole -ieq "NotebookServer" -or $ServerRole -ieq "MissionServer"){ $true }else{ if($Node.AdminAccessEnabled) { $true } else { $false } }
                TomcatDir           = $TomcatDir
                DependsOn           = $Depends
            }
            $Depends += "[ArcGIS_WebAdaptorJava]ConfigureServerWebAdaptor$($Node.NodeName)"
        }

        if($Node.IsPortalWebAdaptorEnabled -and $PrimaryPortalMachine){
            ArcGIS_WebAdaptorJava "ConfigurePortalWebAdaptor$($Node.NodeName)"
            {
                Ensure              = "Present"
                Component           = 'Portal'
                HostName            = if($Node.SSLCertificate){ $Node.SSLCertificate.CName }else{ $MachineFQDN }  
                ComponentHostName   = (Get-FQDN $PrimaryPortalMachine)
                Context             = $Node.PortalContext
                OverwriteFlag       = $False
                SiteAdministrator   = $PortalAdministratorCredential
                TomcatDir           = $TomcatDir
                DependsOn           = $Depends
            }
        }
    }
}