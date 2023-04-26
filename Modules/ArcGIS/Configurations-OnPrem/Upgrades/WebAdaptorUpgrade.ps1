﻿Configuration WebAdaptorUpgrade{
    param(
        [ValidateSet("ServerWebAdaptor","PortalWebAdaptor")]
        [System.String]
        $WebAdaptorRole,

        [System.String]
        $Component,

        [System.String]
        $Version,

        [System.String]
        $OldVersion,
        
        [System.String]
        $InstallerPath,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $InstallerIsSelfExtracting = $True,

        [System.String]
        $DotnetHostingBundlePath,

        [System.String]
        $WebDeployPath,

        [parameter(Mandatory = $false)]
        [System.String]
        $PatchesDir,

        [parameter(Mandatory = $false)]
        [System.Array]
        $PatchInstallOrder,
        
        [System.String]
        $ComponentHostName,

        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential,
        
        [System.Int32]
		$WebSiteId = 1,

        [ValidateSet("Java","IIS")]
        [System.String]
        $WebAdaptorType,

        [System.String]
        $TomcatDir,

        [System.Boolean]
        $DownloadPatches = $False,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $EnableMSILogging = $false
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DscResource -ModuleName ArcGIS -ModuleVersion 4.1.0 
    Import-DscResource -Name ArcGIS_Install
    Import-DscResource -Name ArcGIS_WebAdaptor

    Node $AllNodes.NodeName {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }

        $VersionArray = $Version.Split('.')

        if($WebAdaptorRole -ieq "PortalWebAdaptor"){
            $AdminAccessEnabled = $False
            $Context = $Node.PortalContext
        }
        if($WebAdaptorRole -ieq "ServerWebAdaptor"){
            $AdminAccessEnabled = if($Node.AdminAccessEnabled) { $true } else { $false }
            $Context = $Node.ServerContext
        }

        if ($WebAdaptorType -eq "Java"){
            $Name=$WebAdaptorRole+"Java"
        }else{
            $Name=$WebAdaptorRole
        }

        $Depends = @()

        ArcGIS_Install WebAdaptorUninstall
        { 
            Name = $Name
            Version = $OldVersion
            WebAdaptorContext = $Context
            Arguments = "WEBSITE_ID=$($WebSiteId)"
            TomcatDir = $TomcatDir
            Ensure = "Absent"
        }
        $Depends += '[ArcGIS_Install]WebAdaptorUninstall'

        if ($WebAdaptorType -eq "Java"){
            $WAArguments = "/qn InstallDir=`"$($InstallDir)`""
        }else{
            $WAArguments = "/qn VDIRNAME=$($Context) WEBSITE_ID=$($WebSiteId)"
            if($VersionArray[0] -eq 11 -or ($VersionArray[0] -eq 10 -and $VersionArray[1] -gt 5)){
                $WAArguments += " CONFIGUREIIS=TRUE"
            }
        }

        if($VersionArray[0] -eq 11 -or ($VersionArray[0] -eq 10 -and $VersionArray[1] -gt 8)){
            $WAArguments += " ACCEPTEULA=YES"
        }

        ArcGIS_Install WebAdaptorInstall
        { 
            Name = $WebAdaptorRole
            Version = $Version
            Path = $InstallerPath
            Extract = $InstallerIsSelfExtracting
            WebAdaptorContext = $Context
            WebAdaptorDotnetHostingBundlePath = $DotnetHostingBundlePath
	        WebAdaptorWebDeployPath = $WebDeployPath
            Arguments = $WAArguments
            TomcatDir = $TomcatDir
            EnableMSILogging = $EnableMSILogging
            Ensure = "Present"
            DependsOn = $Depends
        }
        $Depends += '[ArcGIS_Install]WebAdaptorInstall'
        
        if($PatchesDir){
            ArcGIS_InstallPatch WebAdaptorInstallPatch
            {
                Name = "WebAdaptor"
                Version = $Version
                DownloadPatches = $DownloadPatches
                PatchesDir = $PatchesDir
                PatchInstallOrder = $PatchInstallOrder
                Ensure = "Present"
                DependsOn = $Depends
            }
            $Depends += '[ArcGIS_InstallPatch]WebAdaptorInstallPatch'
        }

        if ($WebAdaptorType -eq "Java"){
            ArcGIS_WebAdaptorJava "Configure$($Component)-$($Node.NodeName)"
            {
                Ensure = "Present"
                Component = $Component
                HostName =  if($Node.SSLCertificate){ $Node.SSLCertificate.CName }else{ (Get-FQDN $Node.NodeName) }
                ComponentHostName = (Get-FQDN $ComponentHostName)
                Context = $Context
                OverwriteFlag = $False
                SiteAdministrator = $SiteAdministratorCredential
                AdminAccessEnabled  = $AdminAccessEnabled
                TomcatDir = $TomcatDir
                DependsOn = $Depends
            }
        }else{
            ArcGIS_WebAdaptor "Configure$($Component)-$($Node.NodeName)"
            {
                Ensure = "Present"
                Component = $Component
                HostName =  if($Node.SSLCertificate){ $Node.SSLCertificate.CName }else{ (Get-FQDN $Node.NodeName) }
                ComponentHostName = (Get-FQDN $ComponentHostName)
                Context = $Context
                OverwriteFlag = $False
                SiteAdministrator = $SiteAdministratorCredential
                AdminAccessEnabled  = $AdminAccessEnabled
                DependsOn = $Depends
            }
        }
    }
}
