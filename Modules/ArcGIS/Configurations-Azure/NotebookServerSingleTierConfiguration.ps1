﻿Configuration NotebookServerSingleTierConfiguration
{
	param(
        [Parameter(Mandatory=$false)]
        [System.String]
        $Version = '11.1'

        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $ServiceCredential

        ,[Parameter(Mandatory=$false)]
        [System.Boolean]
        $ServiceCredentialIsDomainAccount
        
        ,[Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential

		,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $MachineAdministratorCredential

        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $PortalSiteAdministratorCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $Context

        ,[Parameter(Mandatory=$false)]
        [System.String]
		$PortalContext = 'portal'
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $FederateSite 

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $UseCloudStorage 

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $UseAzureFiles 

        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $StorageAccountCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PublicKeySSLCertificateFileUrl

        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $ServerInternalCertificatePassword
                
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerLicenseFileUrl

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerMachineNames

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerFunctions

		,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerRole

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ExternalDNSHostName

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PrivateDNSHostName
        
		,[Parameter(Mandatory=$false)]
        [System.Int32]
		$OSDiskSize = 0
		
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $EnableDataDisk 

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $FileShareName = 'fileshare' 

		,[Parameter(Mandatory=$false)]
        $GisServerMachineNamesOnHostingServer

		,[Parameter(Mandatory=$false)]
		$PortalMachineNamesOnHostingServer

        ,[Parameter(Mandatory=$false)]
        [System.Boolean]
        $IsUpdatingCertificates = $False
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $DebugMode
    )

    
    function Get-FileNameFromUrl
    {
        param(
            [string]$Url
        )
        $FileName = $Url
        if($FileName) {
            $pos = $FileName.IndexOf('?')
            if($pos -gt 0) { 
                $FileName = $FileName.Substring(0, $pos) 
            } 
            $FileName = $FileName.Substring($FileName.LastIndexOf('/')+1)   
        }     
        $FileName
    }
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DSCResource -ModuleName ArcGIS
	Import-DscResource -Name ArcGIS_License
    Import-DscResource -Name ArcGIS_NotebookServer
    Import-DscResource -Name ArcGIS_NotebookServerSettings
    Import-DscResource -Name ArcGIS_NotebookPostInstall
    Import-DscResource -Name ArcGIS_Server_TLS
    Import-DscResource -Name ArcGIS_Service_Account
    Import-DscResource -Name ArcGIS_WindowsService
    Import-DscResource -Name ArcGIS_Federation
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_xSmbShare
	Import-DscResource -Name ArcGIS_xDisk  
	Import-DscResource -Name ArcGIS_Disk  
    Import-DscResource -Name ArcGIS_TLSCertificateImport
    Import-DscResource -Name ArcGIS_PendingReboot
	
    $ServerHostName = ($ServerMachineNames -split ',') | Select-Object -First 1
    $FileShareHostName = $ServerHostName
	
    ##
    ## Download license files
    ##
    $ServerCertificateFileName  = 'SSLCertificateForServer.pfx'
    $ServerCertificateLocalFilePath =  (Join-Path $env:TEMP $ServerCertificateFileName)
    $ServerCertificateFileLocation = "\\$($FileShareHostName)\$FileShareName\Certs\$ServerCertificateFileName"

    if($ServerLicenseFileUrl) {
        $ServerLicenseFileName = Get-FileNameFromUrl $ServerLicenseFileUrl
        Invoke-WebRequest -OutFile $ServerLicenseFileName -Uri $ServerLicenseFileUrl -UseBasicParsing -ErrorAction Ignore
    }    

    if($PublicKeySSLCertificateFileUrl){
		$PublicKeySSLCertificateFileName = Get-FileNameFromUrl $PublicKeySSLCertificateFileUrl
		Invoke-WebRequest -OutFile $PublicKeySSLCertificateFileName -Uri $PublicKeySSLCertificateFileUrl -UseBasicParsing -ErrorAction Ignore
	}
    $ipaddress = (Resolve-DnsName -Name $FileShareHostName -Type A -ErrorAction Ignore | Select-Object -First 1).IPAddress    
    if(-not($ipaddress)) { $ipaddress = $FileShareHostName }
    $FileShareRootPath = "\\$ipaddress\$FileShareName"
    
    $FolderName = $ExternalDNSHostName.Substring(0, $ExternalDNSHostName.IndexOf('.')).ToLower()
    $ConfigStoreLocation  = "\\$($FileShareHostName)\$FileShareName\$FolderName\$($Context)\config-store"
    $ServerDirsLocation   = "\\$($FileShareHostName)\$FileShareName\$FolderName\$($Context)\server-dirs" 
    $Join = ($env:ComputerName -ine $ServerHostName)
	$IsDebugMode = $DebugMode -ieq 'true'
    $IsMultiMachineServer = (($ServerMachineNames -split ',').Length -gt 1)
	$LastServerHostName = ($ServerMachineNames -split ',') | Select-Object -Last 1
    $FileShareLocalPath = (Join-Path $env:SystemDrive $FileShareName)  

    if(($UseCloudStorage -ieq 'True') -and $StorageAccountCredential) 
    {
        $Namespace = $ExternalDNSHostName
        $Pos = $Namespace.IndexOf('.')
        if($Pos -gt 0) { $Namespace = $Namespace.Substring(0, $Pos) }        
        $Namespace = [System.Text.RegularExpressions.Regex]::Replace($Namespace, '[\W]', '') # Sanitize
        $AccountName = $StorageAccountCredential.UserName
		$EndpointSuffix = ''
        $Pos = $StorageAccountCredential.UserName.IndexOf('.blob.')
        if($Pos -gt -1) {
            $AccountName = $StorageAccountCredential.UserName.Substring(0, $Pos)
			$EndpointSuffix = $StorageAccountCredential.UserName.Substring($Pos + 6) # Remove the hostname and .blob. suffix to get the storage endpoint suffix
			$EndpointSuffix = ";EndpointSuffix=$($EndpointSuffix)"
        }
        if($UseAzureFiles -ieq 'True') {
            $AzureFilesEndpoint = $StorageAccountCredential.UserName.Replace('.blob.','.file.')   
            $FileShareName = $FileShareName.ToLower() # Azure file shares need to be lower case       
            $ConfigStoreLocation  = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\$($Context)\config-store"
            $ServerDirsLocation   = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\$($Context)\server-dirs" 
        }
        else {
            $ConfigStoreCloudStorageConnectionString = "NAMESPACE=$($Namespace)$($Context)$($EndpointSuffix);DefaultEndpointsProtocol=https;"
            $ConfigStoreCloudStorageAccountName = "AccountName=$AccountName"
            $ConfigStoreCloudStorageConnectionSecret = "AccountKey=$($StorageAccountCredential.GetNetworkCredential().Password)"
        }
    }

    #Since fileshare location sharing or mapped network locations not supported for Docker Desktop, we use local directories for server-dirs.
    $ServerDirsLocation = Join-Path $env:SystemDrive "arcgisnotebookserver\server-dirs"

	Node localhost
	{       
        LocalConfigurationManager
        {
			ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'    
            RebootNodeIfNeeded = $true
        }
         
		$DependsOn = @()
		
		if($OSDiskSize -gt 0) 
        {
            ArcGIS_Disk OSDiskSize
            {
				DriveLetter = ($env:SystemDrive -replace ":" )
				SizeInGB    = $OSDiskSize
				DependsOn 	= $DependsOn
			}
			$DependsOn += '[ArcGIS_Disk]OSDiskSize' 
		}
		
		if($EnableDataDisk -ieq 'true')
        {
            ArcGIS_xDisk DataDisk
            {
                DiskNumber  =  2
				DriveLetter = 'F'
				DependsOn 	= $DependsOn
			}
			$DependsOn += '[ArcGIS_xDisk]DataDisk' 
        }

        $HasValidServiceCredential = ($ServiceCredential -and ($ServiceCredential.GetNetworkCredential().Password -ine 'Placeholder'))
        if(-not($IsUpdatingCertificates)){ #Prepare machine to install mirantis
            WindowsFeature websockets
            {
                Name  = 'Web-WebSockets'
                Ensure = 'Present'
            }
            $DependsOn += '[WindowsFeature]websockets'

            WindowsFeature InstallContainers
            {
                Name  = 'Containers'
                Ensure = 'Present'
                DependsOn 	= $DependsOn
            }
            $DependsOn += '[WindowsFeature]InstallContainers' 

            ArcGIS_PendingReboot ContainerFeatureRebootNeeded {
                Name      = 'ContainerFeatureRebootNeeded'
                DependsOn 	= $DependsOn
            }
            $DependsOn += '[ArcGIS_PendingReboot]ContainerFeatureRebootNeeded' 
        }
        		
        if($HasValidServiceCredential -and -not($IsUpdatingCertificates)) 
        {
            if(-Not($ServiceCredentialIsDomainAccount)){
				User ArcGIS_RunAsAccount
				{
					UserName				= $ServiceCredential.UserName
					Password				= $ServiceCredential
					FullName				= 'ArcGIS Service Account'
					Ensure					= 'Present'
					PasswordChangeRequired  = $false
					PasswordNeverExpires	= $true
					DependsOn 				= $DependsOn
				}
				$DependsOn += '[User]ArcGIS_RunAsAccount'
			}

            File FileShareLocationPath
		    {
			    Type						= 'Directory'
			    DestinationPath				= $FileShareLocalPath
			    Ensure						= 'Present'
			    Force						= $true
			}
			$DependsOn += '[File]FileShareLocationPath'

			$Accounts = @('NT AUTHORITY\SYSTEM')
			if($ServiceCredential) { $Accounts += $ServiceCredential.GetNetworkCredential().UserName }
			if($MachineAdministratorCredential -and ($MachineAdministratorCredential.GetNetworkCredential().UserName -ine 'Placeholder') -and ($MachineAdministratorCredential.GetNetworkCredential().UserName -ine $ServiceCredential.GetNetworkCredential().UserName)) { $Accounts += $MachineAdministratorCredential.GetNetworkCredential().UserName }
            ArcGIS_xSmbShare FileShare 
		    { 
			    Ensure						= 'Present' 
			    Name						= $FileShareName
			    Path						= $FileShareLocalPath
			    FullAccess					= $Accounts
				DependsOn					= $DependsOn
			}
			$DependsOn += '[ArcGIS_xSmbShare]FileShare'
    
            ArcGIS_WindowsService ArcGIS_for_NotebookServer_Service
            {
                Name            = 'ArcGIS Notebook Server'
                Credential      = $ServiceCredential
                StartupType     = 'Automatic'
                State           = 'Running' 
                DependsOn       = $DependsOn
			}
			$DependsOn += '[ArcGIS_WindowsService]ArcGIS_for_NotebookServer_Service'

            ArcGIS_Service_Account NotebookServer_Service_Account
		    {
			    Name            = 'ArcGIS Notebook Server'
				RunAsAccount    = $ServiceCredential
				IsDomainAccount = $ServiceCredentialIsDomainAccount
			    Ensure          = 'Present'
				DependsOn       = $DependsOn
			}
			$DependsOn += '[ArcGIS_Service_Account]NotebookServer_Service_Account'
                
		    if($ServerLicenseFileName) 
            {
                ArcGIS_License ServerLicense
                {
                    LicenseFilePath = (Join-Path $(Get-Location).Path $ServerLicenseFileName)
                    Ensure          = 'Present'
                    Component       = 'Server'
                    ServerRole      = 'NotebookServer'
					DependsOn       = $DependsOn
				} 
				$DependsOn += '[ArcGIS_License]ServerLicense'
            }
		    
            if($AzureFilesEndpoint -and $StorageAccountCredential -and ($UseAzureFiles -ieq 'True')) 
            {
                  $filesStorageAccountName = $AzureFilesEndpoint.Substring(0, $AzureFilesEndpoint.IndexOf('.'))
                  $storageAccountKey       = $StorageAccountCredential.GetNetworkCredential().Password
              
                  Script PersistStorageCredentials
                  {
                      TestScript = { 
                                        $result = cmdkey "/list:$using:AzureFilesEndpoint"
                                        $result | ForEach-Object{Write-verbose -Message "cmdkey: $_" -Verbose}
                                        if($result -like '*none*')
                                        {
                                            return $false
                                        }
                                        return $true
                                    }
                      SetScript = { $result = cmdkey "/add:$using:AzureFilesEndpoint" "/user:$using:filesStorageAccountName" "/pass:$using:storageAccountKey" 
						            $result | ForEach-Object{Write-verbose -Message "cmdkey: $_" -Verbose}
					              }
                      GetScript            = { return @{} }                  
                      DependsOn       	   = $DependsOn
                      PsDscRunAsCredential = $ServiceCredential # This is critical, cmdkey must run as the service account to persist property
				  }
				  $DependsOn += '[Script]PersistStorageCredentials'
            }        

            ArcGIS_xFirewall NotebookServer_FirewallRules
		    {
			    Name                  = "ArcGISNotebookServer"
			    DisplayName           = "ArcGIS for Notebook Server"
			    DisplayGroup          = "ArcGIS for Notebook Server"
			    Ensure                = 'Present'
			    Access                = "Allow"
			    State                 = "Enabled"
			    Profile               = ("Domain","Private","Public")
			    LocalPort             = ("11443")
				Protocol              = "TCP"
				DependsOn       	   = $DependsOn
		    }
			$DependsOn += '[ArcGIS_xFirewall]NotebookServer_FirewallRules'
            
			foreach($ServiceToStop in @('ArcGIS Server', 'Portal for ArcGIS', 'ArcGIS Data Store', 'ArcGISGeoEvent', 'ArcGISGeoEventGateway', 'ArcGIS Mission Server', 'WorkflowManager'))
			{
                if(Get-Service $ServiceToStop -ErrorAction Ignore) 
			    {
                    Service "$($ServiceToStop.Replace(' ','_'))_Service"
                    {
                        Name			= $ServiceToStop
                        Credential		= $ServiceCredential
                        StartupType		= 'Manual'
                        State			= 'Stopped'
                        DependsOn		= if(-Not($ServiceCredentialIsDomainAccount)){ @('[User]ArcGIS_RunAsAccount')}else{ @()}
                    }
                }
			}
			
			ArcGIS_NotebookServer NotebookServer
		    {
                Version                                 = $Version
			    Ensure                                  = 'Present'
			    SiteAdministrator                       = $SiteAdministratorCredential
			    ConfigurationStoreLocation              = $ConfigStoreLocation
			    DependsOn                               = $DependsOn
			    ServerDirectoriesRootLocation           = $ServerDirsLocation
			    LogLevel                                = if($IsDebugMode) { 'DEBUG' } else { 'WARNING' }
                ConfigStoreCloudStorageConnectionString = $ConfigStoreCloudStorageConnectionString
                ConfigStoreCloudStorageAccountName      = $ConfigStoreCloudStorageAccountName
                ConfigStoreCloudStorageConnectionSecret = $ConfigStoreCloudStorageConnectionSecret
                Join                                    = $False
		    }
            $DependsOn += '[ArcGIS_NotebookServer]NotebookServer'
            
            ArcGIS_NotebookServerSettings NotebookServerSettings
            {
                WebContextURL                           = "https://$ExternalDNSHostName/$($Context)"
                SiteAdministrator                       = $SiteAdministratorCredential
                DependsOn                               = $DependsOn
            }
            $DependsOn += '[ArcGIS_NotebookServerSettings]NotebookServerSettings'

            ArcGIS_NotebookPostInstall NotebookPostInstallSamples {
                SiteName            = $Context
                ContainerImagePaths = @()
                ExtractSamples      = $true
                DependsOn           = $DependsOn
                PsDscRunAsCredential  = $ServiceCredential # Copy as arcgis account which has access to this share
            }
            $DependsOn += '[ArcGIS_NotebookPostInstall]NotebookPostInstallSamples'
        }
        
        Script CopyCertificateFileToLocalMachine
        {
            GetScript = {
                $null
            }
            SetScript = {    
                Write-Verbose "Copying from $using:ServerCertificateFileLocation to $using:ServerCertificateLocalFilePath"      
                $PsDrive = New-PsDrive -Name X -Root $using:FileShareRootPath -PSProvider FileSystem                 
                Write-Verbose "Mapped Drive $($PsDrive.Name) to $using:FileShareRootPath"              
                Copy-Item -Path $using:ServerCertificateFileLocation -Destination $using:ServerCertificateLocalFilePath -Force  
                if($PsDrive) {
                    Write-Verbose "Removing Temporary Mapped Drive $($PsDrive.Name)"
                    Remove-PsDrive -Name $PsDrive.Name -Force       
                }       
            }
            TestScript = {   
                $false
            }
            DependsOn             = if(-Not($ServiceCredentialIsDomainAccount) -and -not($IsUpdatingCertificates)){@('[User]ArcGIS_RunAsAccount')}else{@()}
            PsDscRunAsCredential  = $ServiceCredential # Copy as arcgis account which has access to this share
        }

        ArcGIS_Server_TLS Server_TLS
        {
            ServerHostName             = $env:ComputerName
            SiteAdministrator          = $SiteAdministratorCredential                         
            WebServerCertificateAlias  = "ApplicationGateway"
            CertificateFileLocation    = $ServerCertificateLocalFilePath
            CertificatePassword        = if($ServerInternalCertificatePassword -and ($ServerInternalCertificatePassword.GetNetworkCredential().Password -ine 'Placeholder')) { $ServerInternalCertificatePassword } else { $null }
            ServerType                 = $ServerFunctions
            DependsOn                  =  if(-not($IsUpdatingCertificates)){ @('[ArcGIS_NotebookServer]NotebookServer','[ArcGIS_NotebookServerSettings]NotebookServerSettings','[Script]CopyCertificateFileToLocalMachine') }else{ @('[Script]CopyCertificateFileToLocalMachine')  }
            SslRootOrIntermediate	   = if($PublicKeySSLCertificateFileName){ [string]::Concat('[{"Alias":"AppGW-ExternalDNSCerCert","Path":"', (Join-Path $(Get-Location).Path $PublicKeySSLCertificateFileName).Replace('\', '\\'),'"}]') }else{$null}
        }
        $DependsOn += @('[ArcGIS_Server_TLS]Server_TLS') 

		if(($FederateSite -ieq 'true') -and $PortalSiteAdministratorCredential -and -not($IsUpdatingCertificates)) 
        {
			ArcGIS_Federation Federate
			{
				PortalHostName = $ExternalDNSHostName
				PortalPort = 443
				PortalContext = $PortalContext
				ServiceUrlHostName = $ExternalDNSHostName
				ServiceUrlContext = $Context
				ServiceUrlPort = 443
				ServerSiteAdminUrlHostName = if($PrivateDNSHostName){ $PrivateDNSHostName }else{ $ExternalDNSHostName }
				ServerSiteAdminUrlPort = 443
				ServerSiteAdminUrlContext = $Context
				Ensure = "Present"
				RemoteSiteAdministrator = $PortalSiteAdministratorCredential
				SiteAdministrator = $SiteAdministratorCredential
				ServerRole = 'FEDERATED_SERVER'
				ServerFunctions = $ServerFunctions
				DependsOn = $DependsOn
			}
        }

		# Import TLS certificates from portal machines on the hosting server
		if($PortalMachineNamesOnHostingServer -and $PortalMachineNamesOnHostingServer.Length -gt 0 -and $PortalSiteAdministratorCredential)
		{
			$MachineNames = $PortalMachineNamesOnHostingServer -split ','
			foreach($MachineName in $MachineNames) 
			{
				ArcGIS_TLSCertificateImport "$($MachineName)-PortalTLSImport"
                {
                    HostName			= $MachineName
                    Ensure				= 'Present'
                    ApplicationPath		= '/arcgis/portaladmin/' 
                    HttpsPort			= 7443
                    StoreLocation		= 'LocalMachine'
                    StoreName			= 'Root'
                    SiteAdministrator	= $PortalSiteAdministratorCredential
                    ServerType          = $ServerFunctions
                    DependsOn = $DependsOn
                }
			}
		}

		# Import TLS certificates from GIS on the hosting server
		if($GisServerMachineNamesOnHostingServer -and $GisServerMachineNamesOnHostingServer.Length -gt 0 -and $PortalSiteAdministratorCredential)
		{
			$MachineNames = $GisServerMachineNamesOnHostingServer -split ','
			foreach($MachineName in $MachineNames) 
			{
				ArcGIS_TLSCertificateImport "$($MachineName)-ServerTLSImport"
                {
                    HostName			= $MachineName
                    Ensure				= 'Present'
                    ApplicationPath		= '/arcgis/admin/' 
                    HttpsPort			= 6443
                    StoreLocation		= 'LocalMachine'
                    StoreName			= 'Root'
                    SiteAdministrator	= $PortalSiteAdministratorCredential
                    ServerType          = $ServerFunctions
                    DependsOn = $DependsOn
                }
			}
		}
	}
}
