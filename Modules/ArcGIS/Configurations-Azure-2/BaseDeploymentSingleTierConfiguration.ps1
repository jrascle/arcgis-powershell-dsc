﻿Configuration BaseDeploymentSingleTierConfiguration
{
	param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $ServiceCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServiceCredentialIsDomainAccount = 'false'

        ,[Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerContext = 'server'

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PortalContext = 'portal'

		,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $MachineAdministratorCredential

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
        [System.Management.Automation.PSCredential]
        $SelfSignedSSLCertificatePassword        
                
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServerLicenseFileUrl

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PortalLicenseFileUrl
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PortalLicenseUserTypeId

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $MachineName

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PeerMachineName       

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $ExternalDNSHostName
                
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $DataStoreTypes = 'Relational'

        ,[Parameter(Mandatory=$false)]
        [System.Boolean]
        $IsTileCacheDataStoreClustered = $False

        ,[Parameter(Mandatory=$false)]
        [System.Int32]
        $OSDiskSize = 0

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $EnableDataDisk
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $EnableLogHarvesterPlugin
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $FileShareName = 'fileshare' 
        
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
	Import-DscResource -Name ArcGIS_Server
    Import-DscResource -Name ArcGIS_Server_TLS
    Import-DscResource -Name ArcGIS_Service_Account
    Import-DscResource -name ArcGIS_WindowsService
    Import-DscResource -Name ArcGIS_Portal
    Import-DscResource -Name ArcGIS_Portal_TLS
    Import-DscResource -Name ArcGIS_DataStore
    Import-DscResource -Name ArcGIS_Federation
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_xSmbShare
    Import-DscResource -Name ArcGIS_xDisk
    Import-DscResource -Name ArcGIS_Disk
    Import-DscResource -Name ArcGIS_ServerSettings
    Import-DscResource -Name ArcGIS_PortalSettings
    Import-DscResource -Name ArcGIS_LogHarvester
    
    ##
    ## Download license files
    ##
    if($ServerLicenseFileUrl) {
        $ServerLicenseFileName = Get-FileNameFromUrl $ServerLicenseFileUrl
        Invoke-WebRequest -OutFile $ServerLicenseFileName -Uri $ServerLicenseFileUrl -UseBasicParsing -ErrorAction Ignore
    }
    if($PortalLicenseFileUrl) {
        $PortalLicenseFileName = Get-FileNameFromUrl $PortalLicenseFileUrl
        Invoke-WebRequest -OutFile $PortalLicenseFileName -Uri $PortalLicenseFileUrl -UseBasicParsing -ErrorAction Ignore
    }
    
    $HostNames = @($MachineName)
    if($PeerMachineName) {
        $HostNames += $PeerMachineName
    }        
    $FileShareHostName = $MachineName
    $ipaddress = (Resolve-DnsName -Name $FileShareHostName -Type A -ErrorAction Ignore | Select-Object -First 1).IPAddress    
    if(-not($ipaddress)) { $ipaddress = $FileShareHostName }
    $FileShareRootPath = "\\$ipaddress\$FileShareName"
    
    $FolderName = $ExternalDNSHostName.Substring(0, $ExternalDNSHostName.IndexOf('.')).ToLower()
    $ConfigStoreLocation  = "\\$($FileShareHostName)\$FileShareName\$FolderName\$($ServerContext)\config-store"
    $ServerDirsLocation   = "\\$($FileShareHostName)\$FileShareName\$FolderName\$($ServerContext)\server-dirs"
    $ContentStoreLocation = "\\$($FileShareHostName)\$FileShareName\$FolderName\$($PortalContext)\content"    
    $DataStoreBackupLocation = "\\$($FileShareHostName)\$FileShareName\$FolderName\datastore\dbbackups"    
    $FileShareLocalPath = (Join-Path $env:SystemDrive $FileShareName)         
    
    $ServerCertificateFileName  = 'SSLCertificateForServer.pfx'
    $PortalCertificateFileName  = 'SSLCertificateForPortal.pfx'
    
    $ServerCertificateFileLocation = "\\$($FileShareHostName)\$FileShareName\Certs\$ServerCertificateFileName"
    $PortalCertificateFileLocation = "\\$($FileShareHostName)\$FileShareName\Certs\$PortalCertificateFileName"

    $ServerCertificateLocalFilePath =  (Join-Path $env:TEMP $ServerCertificateFileName)
    $PortalCertificateLocalFilePath =  (Join-Path $env:TEMP $PortalCertificateFileName)
    
    $Join = ($env:ComputerName -ieq $PeerMachineName) -and ($MachineName -ine $PeerMachineName)
    $IsDualMachineDeployment = ($MachineName -ine $PeerMachineName)
    $IsDebugMode = $DebugMode -ieq 'true'
    $LastHostName = $HostNames | Select-Object -Last 1
    $IsServiceCredentialDomainAccount = $ServiceCredentialIsDomainAccount -ieq 'true'

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
        $AccountKey = $StorageAccountCredential.GetNetworkCredential().Password

        if($UseAzureFiles -ieq 'True') {
            $AzureFilesEndpoint = $StorageAccountCredential.UserName.Replace('.blob.','.file.')                        
            $FileShareName = $FileShareName.ToLower() # Azure file shares need to be lower case            
            $ConfigStoreLocation  = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\$($ServerContext)\config-store"
            $ServerDirsLocation   = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\$($ServerContext)\server-dirs" 
            $ContentStoreLocation = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\$($PortalContext)\content"    
            $DataStoreBackupLocation = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\datastore\dbbackups"    
        }
        else {
            $ConfigStoreCloudStorageConnectionString = "NAMESPACE=$($Namespace)$($ServerContext)$($EndpointSuffix);DefaultEndpointsProtocol=https;AccountName=$AccountName"
            $ConfigStoreCloudStorageConnectionSecret = "AccountKey=$($AccountKey)"
            $ContentDirectoryCloudConnectionString = "DefaultEndpointsProtocol=https;AccountName=$($AccountName);AccountKey=$($AccountKey)$($EndpointSuffix)"
		    $ContentDirectoryCloudContainerName = "arcgis-portal-content-$($Namespace)$($PortalContext)"
        }
    }

	Node localhost
	{
        LocalConfigurationManager
        {
			ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'    
            RebootNodeIfNeeded = $true
        }
        
        if($OSDiskSize -gt 0) 
        {
            ArcGIS_Disk OSDiskSize
            {
                DriveLetter = ($env:SystemDrive -replace ":" )
                SizeInGB    = $OSDiskSize
            }
        }
        
        if($EnableDataDisk -ieq 'true')
        {
            ArcGIS_xDisk DataDisk
            {
                DiskNumber  =  2
                DriveLetter = 'F'
            }
        }

        $HasValidServiceCredential = ($ServiceCredential -and ($ServiceCredential.GetNetworkCredential().Password -ine 'Placeholder'))
        if($HasValidServiceCredential) 
        {
            if(-Not($IsServiceCredentialDomainAccount)){
                User ArcGIS_RunAsAccount
                {
                    UserName       = $ServiceCredential.UserName
                    Password       = $ServiceCredential
                    FullName       = 'ArcGIS Service Account'
                    Ensure         = 'Present'
                    PasswordChangeRequired = $false
                    PasswordNeverExpires = $true
                }
            }
        
            File FileShareLocationPath
		    {
			    Type						= 'Directory'
			    DestinationPath				= $FileShareLocalPath
			    Ensure						= 'Present'
			    Force						= $true
		    }
        
            File ContentDirectoryLocationPath
		    {
			    Type						= 'Directory'
			    DestinationPath				= (Join-Path $FileShareLocalPath "$FolderName/$($PortalContext)/content")
			    Ensure						= 'Present'
			    Force						= $true
		    }

            $DataStoreBackupsLocalPath = (Join-Path $FileShareLocalPath "$FolderName/datastore/dbbackups")
            File DataStoreBackupsLocationPath
		    {
			    Type						= 'Directory'
			    DestinationPath				= $DataStoreBackupsLocalPath
			    Ensure						= 'Present'
			    Force						= $true
		    }

		    $Accounts = @('NT AUTHORITY\SYSTEM')
		    if($ServiceCredential) { $Accounts += $ServiceCredential.GetNetworkCredential().UserName }
		    if($MachineAdministratorCredential -and ($MachineAdministratorCredential.GetNetworkCredential().UserName -ine 'Placeholder') -and ($MachineAdministratorCredential.GetNetworkCredential().UserName -ine $ServiceCredential.GetNetworkCredential().UserName)) { $Accounts += $MachineAdministratorCredential.GetNetworkCredential().UserName }
            ArcGIS_xSmbShare FileShare 
		    { 
			    Ensure						= 'Present' 
			    Name						= $FileShareName
			    Path						= $FileShareLocalPath
			    FullAccess					= $Accounts
			    DependsOn					= if(-Not($IsServiceCredentialDomainAccount)){ @('[File]FileShareLocationPath', '[User]ArcGIS_RunAsAccount')}else{ @('[File]FileShareLocationPath')}
            }
            
            $ServerDependsOn = @('[ArcGIS_Service_Account]Server_Service_Account', '[ArcGIS_xFirewall]Server_FirewallRules')  
            if($ServerLicenseFileName) 
            {
                ArcGIS_License ServerLicense
                {
                    LicenseFilePath = (Join-Path $(Get-Location).Path $ServerLicenseFileName)
                    Ensure          = 'Present'
                    Component       = 'Server'
                } 
                $ServerDependsOn += '[ArcGIS_License]ServerLicense'
            }

            ArcGIS_WindowsService ArcGIS_for_Server_Service
            {
                Name            = 'ArcGIS Server'
                Credential      = $ServiceCredential
                StartupType     = 'Automatic'
                State           = 'Running' 
                DependsOn	    = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount')}else{ @()}
            }

            ArcGIS_Service_Account Server_Service_Account
		    {
			    Name            = 'ArcGIS Server'
			    RunAsAccount    = $ServiceCredential
                Ensure          = 'Present'
                DependsOn	    = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount','[ArcGIS_WindowsService]ArcGIS_for_Server_Service')}else{ @('[ArcGIS_WindowsService]ArcGIS_for_Server_Service')}
                IsDomainAccount = $IsServiceCredentialDomainAccount
		    }
            
            $PortalDependsOn = @('[ArcGIS_Service_Account]Portal_Service_Account')   
            if($AzureFilesEndpoint -and $StorageAccountCredential -and ($UseAzureFiles -ieq 'True')) 
            {
                  $filesStorageAccountName = $AzureFilesEndpoint.Substring(0, $AzureFilesEndpoint.IndexOf('.'))
                  $storageAccountKey       = $StorageAccountCredential.GetNetworkCredential().Password
              
                  Script PersistStorageCredentials
                  {
                      TestScript = { 
                                        $result = cmdkey "/list:$using:AzureFilesEndpoint"
                                        $result | ForEach-Object {Write-verbose -Message "cmdkey: $_" -Verbose}
                                        if($result -like '*none*')
                                        {
                                            return $false
                                        }
                                        return $true
                                    }
                      SetScript = { $result = cmdkey "/add:$using:AzureFilesEndpoint" "/user:$using:filesStorageAccountName" "/pass:$using:storageAccountKey" 
						            $result | ForEach-Object {Write-verbose -Message "cmdkey: $_" -Verbose}
					              }
                      GetScript            = { return @{} }                  
                      DependsOn            = @('[ArcGIS_Service_Account]Server_Service_Account')
                      PsDscRunAsCredential = $ServiceCredential # This is critical, cmdkey must run as the service account to persist property
                  }
                  $ServerDependsOn += '[Script]PersistStorageCredentials'
                  $PortalDependsOn += '[Script]PersistStorageCredentials'

                  $RootPathOfFileShare = "\\$($AzureFilesEndpoint)\$FileShareName"
                  Script CreatePortalContentFolder
                  {
                      TestScript = { 
                                        Test-Path $using:ContentStoreLocation
                                    }
                      SetScript = {                   
                                      Write-Verbose "Mount to $using:RootPathOfFileShare"
                                      $DriveInfo = New-PSDrive -Name 'Z' -PSProvider FileSystem -Root $using:RootPathOfFileShare
                                      if(-not(Test-Path $using:ContentStoreLocation)) {
                                        Write-Verbose "Creating folder $using:ContentStoreLocation"
                                        New-Item $using:ContentStoreLocation -ItemType directory
                                      }else {
                                        Write-Verbose "Folder '$using:ContentStoreLocation' already exists"
                                      }
					              }
                      GetScript            = { return @{} }     
                      PsDscRunAsCredential = $ServiceCredential # This is important, only arcgis account has access to the file share on AFS
                  }             
                  $PortalDependsOn += '[Script]CreatePortalContentFolder'
            } 

		    ArcGIS_xFirewall Server_FirewallRules
		    {
			    Name                  = "ArcGISServer"
			    DisplayName           = "ArcGIS for Server"
			    DisplayGroup          = "ArcGIS for Server"
			    Ensure                = 'Present'
			    Access                = "Allow"
			    State                 = "Enabled"
			    Profile               = ("Domain","Private","Public")
			    LocalPort             = ("6080","6443")
			    Protocol              = "TCP"
		    }
		    $ServerDependsOn += '[ArcGIS_xFirewall]Server_FirewallRules'

            ArcGIS_xFirewall Server_FirewallRules_Internal
		    {
			    Name                  = "ArcGISServerInternal"
			    DisplayName           = "ArcGIS for Server Internal RMI"
			    DisplayGroup          = "ArcGIS for Server"
			    Ensure                = 'Present'
			    Access                = "Allow"
			    State                 = "Enabled"
			    Profile               = ("Domain","Private","Public")
			    LocalPort             = ("4000-4004")
			    Protocol              = "TCP"
		    }
		    $ServerDependsOn += '[ArcGIS_xFirewall]Server_FirewallRules_Internal'
            
            ArcGIS_LogHarvester ServerLogHarvester
            {
                ComponentType = "Server"
                EnableLogHarvesterPlugin = if($EnableLogHarvesterPlugin -ieq 'true'){$true}else{$false}
                DependsOn = $ServerDependsOn
            }

            $ServerDependsOn += '[ArcGIS_LogHarvester]ServerLogHarvester'

            ArcGIS_Server Server
		    {
			    Ensure                                  = 'Present'
			    SiteAdministrator                       = $SiteAdministratorCredential
			    ConfigurationStoreLocation              = $ConfigStoreLocation
			    DependsOn                               = $ServerDependsOn
			    ServerDirectoriesRootLocation           = $ServerDirsLocation
			    Join                                    = $Join
			    PeerServerHostName                      = $MachineName
			    LogLevel                                = if($IsDebugMode) { 'DEBUG' } else { 'WARNING' }
			    SingleClusterMode                       = $true
                ConfigStoreCloudStorageConnectionString = $ConfigStoreCloudStorageConnectionString
                ConfigStoreCloudStorageConnectionSecret = $ConfigStoreCloudStorageConnectionSecret
            }
            
            Script CopyServerCertificateFileToLocalMachine
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
                DependsOn             = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
                PsDscRunAsCredential  = $ServiceCredential # Copy as arcgis account which has access to this share
            }

            ArcGIS_Server_TLS Server_TLS
            {
                Ensure                     = 'Present'
                SiteName                   = 'arcgis'
                SiteAdministrator          = $SiteAdministratorCredential                         
                CName                      = "ApplicationGateway"
                CertificateFileLocation    = $ServerCertificateLocalFilePath
                CertificatePassword        = if($SelfSignedSSLCertificatePassword -and ($SelfSignedSSLCertificatePassword.GetNetworkCredential().Password -ine 'Placeholder')) { $SelfSignedSSLCertificatePassword } else { $null }
                EnableSSL                  = -not($Join)
                ServerType                 = "GeneralPurposeServer"
                DependsOn                  = @('[ArcGIS_Server]Server','[Script]CopyServerCertificateFileToLocalMachine') 
            }

            if($env:ComputerName -ieq $LastHostName) # Perform on Last machine
            {
                ArcGIS_ServerSettings ServerSettings
                {
                    ServerContext       = 'server'
                    ServerHostName      = $MachineName
                    ServerEndPoint      = $ExternalDNSHostName
                    ServerEndPointPort  = 443
                    ServerEndPointContext = 'server'
                    ExternalDNSName     = $ExternalDNSHostName
                    SiteAdministrator   = $SiteAdministratorCredential
                    DependsOn = @('[ArcGIS_Server_TLS]Server_TLS')
                }
            }
            
            if($PortalLicenseFileName -and ($PortalLicenseFileName -ine $ServerLicenseFileName) -and [string]::IsNullOrEmpty($PortalLicenseUserTypeId))
            {
                ArcGIS_License PortalLicense
			    {
				    LicenseFilePath = (Join-Path $(Get-Location).Path $PortalLicenseFileName)
				    Ensure          = 'Present'
				    Component       = 'Portal'
			    }
            }

            ArcGIS_WindowsService Portal_for_ArcGIS_Service
            {
                Name            = 'Portal for ArcGIS'
                Credential      = $ServiceCredential
                StartupType     = 'Automatic'
                State           = 'Running' 
                DependsOn	    = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount')}else{ @()}
            }
            
            $ServiceAccountsDepends = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount','[ArcGIS_WindowsService]Portal_for_ArcGIS_Service')}else{ @('[ArcGIS_WindowsService]Portal_for_ArcGIS_Service')}
            $DataDirsForPortal = @('HKLM:\SOFTWARE\ESRI\Portal for ArcGIS')
            if($ContentStoreLocation -and (-not($ContentStoreLocation.StartsWith('\')))) 
            {
                $ServiceAccountsDepends += '[File]ContentStoreLocation'
                $DataDirsForPortal += $ContentStoreLocation
                $DataDirsForPortal += (Split-Path $ContentStoreLocation -Parent)
                File ContentStoreLocation
                {
                    Ensure          = 'Present'
                    DestinationPath = $ContentStoreLocation
                    Type            = 'Directory'
                }   
            }

            ArcGIS_Service_Account Portal_Service_Account
		    {
			    Name         = 'Portal for ArcGIS'
			    RunAsAccount = $ServiceCredential
			    Ensure       = 'Present'
			    DependsOn    = $ServiceAccountsDepends 
                DataDir      = $DataDirsForPortal    
                IsDomainAccount = $IsServiceCredentialDomainAccount
		    } 
    
            if($IsDualMachineDeployment) 
            {
                ArcGIS_xFirewall Portal_FirewallRules
		        {
				        Name                  = "PortalforArcGIS" 
				        DisplayName           = "Portal for ArcGIS" 
				        DisplayGroup          = "Portal for ArcGIS" 
				        Ensure                = 'Present'
				        Access                = "Allow" 
				        State                 = "Enabled" 
				        Profile               = ("Domain","Private","Public")
				        LocalPort             = ("7080","7443","7654")                         
				        Protocol              = "TCP" 
		        }
        
                ArcGIS_xFirewall Portal_Database_OutBound
		        {
				        Name                  = "PortalforArcGIS-Outbound" 
				        DisplayName           = "Portal for ArcGIS Outbound" 
				        DisplayGroup          = "Portal for ArcGIS Outbound" 
				        Ensure                = 'Present'
				        Access                = "Allow" 
				        State                 = "Enabled" 
				        Profile               = ("Domain","Private","Public")
				        RemotePort            = ("7654","7120","7220", "7005", "7099", "7199", "5701", "5702")  # Elastic Search uses 7120,7220 and Postgres uses 7654 for replication, Hazelcast uses 5701 and 5702
				        Direction             = "Outbound"                       
				        Protocol              = "TCP" 
		        } 

                ArcGIS_xFirewall Portal_Database_InBound
			    {
					    Name                  = "PortalforArcGIS-Inbound" 
					    DisplayName           = "Portal for ArcGIS Inbound" 
					    DisplayGroup          = "Portal for ArcGIS Inbound" 
					    Ensure                = 'Present'
					    Access                = "Allow" 
					    State                 = "Enabled" 
					    Profile               = ("Domain","Private","Public")
					    LocalPort             = ("7120","7220", "5701", "5702")  # Elastic Search uses 7120,7220, Hazelcast uses 5701 and 5702
					    Protocol              = "TCP" 
			    }  

			    $PortalDependsOn += @('[ArcGIS_xFirewall]Portal_FirewallRules', '[ArcGIS_xFirewall]Portal_Database_OutBound', '[ArcGIS_xFirewall]Portal_Database_InBound')
            }
            else # If single machine, need to open 7443 to allow federation over private portal URL and 6443 for changeServerRole
            {
                ArcGIS_xFirewall Portal_FirewallRules
			    {
					    Name                  = "PortalforArcGIS" 
					    DisplayName           = "Portal for ArcGIS" 
					    DisplayGroup          = "Portal for ArcGIS" 
					    Ensure                = 'Present'
					    Access                = "Allow" 
					    State                 = "Enabled" 
					    Profile               = ("Domain","Private","Public")
					    LocalPort             = ("7443")                         
					    Protocol              = "TCP" 
			    }
    
                ArcGIS_xFirewall ServerFederation_FirewallRules
			    {
					    Name                  = "ArcGISforServer-Federation" 
					    DisplayName           = "ArcGIS for Server" 
					    DisplayGroup          = "ArcGIS for Server" 
					    Ensure                = 'Present'
					    Access                = "Allow" 
					    State                 = "Enabled" 
					    Profile               = ("Domain","Private","Public")
					    LocalPort             = ("6443")                         
					    Protocol              = "TCP" 
			    }

			    $PortalDependsOn += @('[ArcGIS_xFirewall]Portal_FirewallRules', '[ArcGIS_xFirewall]ServerFederation_FirewallRules')
            }
        
		    ArcGIS_Portal Portal
		    {
                PortalHostName                        = if($MachineName -ieq $env:ComputerName){ $MachineName }else{ $PeerMachineName }
                Ensure                                = 'Present'
                LicenseFilePath                       = if($PortalLicenseFileName){(Join-Path $(Get-Location).Path $PortalLicenseFileName)}else{$null}
                UserLicenseTypeId                       = if($PortalLicenseUserTypeId){$PortalLicenseUserTypeId}else{$null}
			    PortalAdministrator                   = $SiteAdministratorCredential 
			    DependsOn                             = $PortalDependsOn
			    AdminEmail                            = 'portaladmin@admin.com'
			    AdminSecurityQuestionIndex            = 1
			    AdminSecurityAnswer                   = 'timbukto'
			    Join                                  = $Join
                PeerMachineHostName                   = if($Join) { $MachineName } else { $PeerMachineName }
                IsHAPortal                            = $IsDualMachineDeployment
                ContentDirectoryLocation              = $ContentStoreLocation
                EnableDebugLogging                    = $IsDebugMode
                LogLevel                              = if($IsDebugMode) { 'DEBUG' } else { 'WARNING' }
                ContentDirectoryCloudConnectionString = $ContentDirectoryCloudConnectionString			
                ContentDirectoryCloudContainerName    = $ContentDirectoryCloudContainerName
                EnableEmailSettings                   = $False
                EmailSettingsSMTPServerAddress        = $null
                EmailSettingsFrom                     = $null
                EmailSettingsLabel                    = $null
                EmailSettingsAuthenticationRequired   = $false
                EmailSettingsCredential               = $null
                EmailSettingsSMTPPort                 = $null
                EmailSettingsEncryptionMethod         = "NONE"
            } 

            Script CopyPortalCertificateFileToLocalMachine
            {
                GetScript = {
                    $null
                }
                SetScript = {    
                    Write-Verbose "Copying from $using:PortalCertificateFileLocation to $using:PortalCertificateLocalFilePath"      
                    $PsDrive = New-PsDrive -Name X -Root $using:FileShareRootPath -PSProvider FileSystem                 
                    Write-Verbose "Mapped Drive $($PsDrive.Name) to $using:FileShareRootPath"              
                    Copy-Item -Path $using:PortalCertificateFileLocation -Destination $using:PortalCertificateLocalFilePath -Force  
                    if($PsDrive) {
                        Write-Verbose "Removing Temporary Mapped Drive $($PsDrive.Name)"
                        Remove-PsDrive -Name $PsDrive.Name -Force       
                    }       
                }
                TestScript = {   
                    $false
                }
                DependsOn             = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
                PsDscRunAsCredential  = $ServiceCredential # Copy as arcgis account which has access to this share
            }

            ArcGIS_Portal_TLS ArcGIS_Portal_TLS
            {
                Ensure                  = 'Present'
                SiteName                = 'arcgis'
                SiteAdministrator       = $SiteAdministratorCredential 
                CName                   = "ApplicationGateway"
                #PortalEndPoint         = $PortalEndPoint
                #ServerEndPoint         = $ServerEndPoint
                CertificateFileLocation = $PortalCertificateLocalFilePath 
                CertificatePassword     = if($SelfSignedSSLCertificatePassword -and ($SelfSignedSSLCertificatePassword.GetNetworkCredential().Password -ine 'Placeholder')) { $SelfSignedSSLCertificatePassword } else { $null }
                DependsOn               = @('[ArcGIS_Portal]Portal','[Script]CopyPortalCertificateFileToLocalMachine')
            }

            if($env:ComputerName -ieq $LastHostName) # Perform on Last machine
            {
                ArcGIS_PortalSettings PortalSettings
                {
                    ExternalDNSName     = $ExternalDNSHostName
                    PortalContext       = 'portal'
                    PortalHostName      = $MachineName
                    PortalEndPoint      = $ExternalDNSHostName
                    PortalEndPointPort    = 443
                    PortalEndPointContext = 'portal'
                    PortalAdministrator = $SiteAdministratorCredential
                    DependsOn = @('[ArcGIS_Portal]Portal','[ArcGIS_Portal_TLS]ArcGIS_Portal_TLS')
                }
            }
            
            ArcGIS_WindowsService ArcGIS_DataStore_Service
            {
                Name            = 'ArcGIS Data Store'
                Credential      = $ServiceCredential
                StartupType     = 'Automatic'
                State           = 'Running' 
                DependsOn       = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount')}else{ @()}
            }

            ArcGIS_Service_Account ArcGIS_DataStore_RunAs_Account
		    {
			    Name              = 'ArcGIS Data Store'
			    RunAsAccount      = $ServiceCredential
			    Ensure            = 'Present'
			    DataDir           = $DataStoreContentDirectory
                DependsOn         = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount','[ArcGIS_WindowsService]ArcGIS_DataStore_Service')}else{ @('[ArcGIS_WindowsService]ArcGIS_DataStore_Service')}
                IsDomainAccount = $IsServiceCredentialDomainAccount
            } 
            $DataStoreDependsOn = @('[ArcGIS_Service_Account]ArcGIS_DataStore_RunAs_Account')

		    ArcGIS_xFirewall DataStore_FirewallRules
		    {
                Name                  = "ArcGISDataStore" 
                DisplayName           = "ArcGIS Data Store" 
                DisplayGroup          = "ArcGIS Data Store" 
                Ensure                = 'Present' 
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public")
                LocalPort             = ("2443", "9876")                        
                Protocol              = "TCP" 
            }
            $DataStoreDependsOn += @('[ArcGIS_xFirewall]DataStore_FirewallRules')

            if($IsDualMachineDeployment) 
            {
                ArcGIS_xFirewall DataStore_FirewallRules_OutBound
			    {
                    Name                  = "ArcGISDataStore-Out" 
                    DisplayName           = "ArcGIS Data Store Out" 
                    DisplayGroup          = "ArcGIS Data Store" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("9876")       
                    Direction             = "Outbound"                        
                    Protocol              = "TCP" 
			    } 

			    $DataStoreDependsOn += @('[ArcGIS_xFirewall]DataStore_FirewallRules_OutBound')
            }
            
            if($DataStoreTypes.split(",") -iContains "TileCache"){
                ArcGIS_xFirewall TileCache_DataStore_FirewallRules
                {
                    Name                  = "ArcGISTileCacheDataStore" 
                    DisplayName           = "ArcGIS Tile Cache Data Store" 
                    DisplayGroup          = "ArcGIS Tile Cache Data Store" 
                    Ensure                = 'Present' 
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("29079-29082")
                    Protocol              = "TCP" 
                }
                $DataStoreDependsOn += @('[ArcGIS_xFirewall]TileCache_DataStore_FirewallRules')

                ArcGIS_xFirewall TileCache_FirewallRules_OutBound
                {
                    Name                  = "ArcGISTileCacheDataStore-Out" 
                    DisplayName           = "ArcGIS TileCache Data Store Out" 
                    DisplayGroup          = "ArcGIS TileCache Data Store" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("29079-29082")       
                    Direction             = "Outbound"                        
                    Protocol              = "TCP" 
                } 
                $DataStoreDependsOn += @('[ArcGIS_xFirewall]TileCache_FirewallRules_OutBound')

                if($IsDualMachineDeployment) {
                    ArcGIS_xFirewall MultiMachine_TileCache_DataStore_FirewallRules
                    {
                        Name                  = "ArcGISMultiMachineTileCacheDataStore" 
                        DisplayName           = "ArcGIS Multi Machine Tile Cache Data Store" 
                        DisplayGroup          = "ArcGIS TileCache Data Store" 
                        Ensure                = 'Present' 
                        Access                = "Allow" 
                        State                 = "Enabled" 
                        Profile               = ("Domain","Private","Public")
                        LocalPort             = ("4369","29083-29090")
                        Protocol              = "TCP" 
                    }
                    $DataStoreDependsOn += @('[ArcGIS_xFirewall]MultiMachine_TileCache_DataStore_FirewallRules')

                    ArcGIS_xFirewall MultiMachine_TileCache_FirewallRules_OutBound
                    {
                        Name                  = "ArcGISMultiMachineTileCacheDataStore-Out" 
                        DisplayName           = "ArcGIS Multi Machine TileCache Data Store Out" 
                        DisplayGroup          = "ArcGIS TileCache Data Store" 
                        Ensure                = 'Present'
                        Access                = "Allow" 
                        State                 = "Enabled" 
                        Profile               = ("Domain","Private","Public")
                        LocalPort             = ("4369","29083-29090")       
                        Direction             = "Outbound"                        
                        Protocol              = "TCP" 
                    } 
                    $DataStoreDependsOn += @('[ArcGIS_xFirewall]MultiMachine_TileCache_FirewallRules_OutBound')
                }
            }

            if($DataStoreTypes.split(",") -iContains "SpatioTemporal"){
                ArcGIS_xFirewall SpatioTemporalDataStore_FirewallRules
                {
                    Name                  = "ArcGISSpatioTemporalDataStore" 
                    DisplayName           = "ArcGIS SpatioTemporal Data Store" 
                    DisplayGroup          = "ArcGIS SpatioTemporal Data Store" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("2443", "9220")                        
                    Protocol              = "TCP" 
                } 
                $DataStoreDependsOn += @('[ArcGIS_xFirewall]SpatioTemporalDataStore_FirewallRules')

                if($IsDualMachineDeployment){
                    ArcGIS_xFirewall SpatioTemporalDataStore_MultiMachine_FirewallRules
                    {
                        Name                  = "ArcGISSpatioTemporalMultiMachineDataStore" 
                        DisplayName           = "ArcGIS SpatioTemporal Multi Machine Data Store" 
                        DisplayGroup          = "ArcGIS SpatioTemporal Multi Machine Data Store" 
                        Ensure                = 'Present'
                        Access                = "Allow" 
                        State                 = "Enabled" 
                        Profile               = ("Domain","Private","Public")
                        LocalPort             = ("9320")                        
                        Protocol              = "TCP" 
                    } 
                    $DataStoreDependsOn += @('[ArcGIS_xFirewall]SpatioTemporalDataStore_MultiMachine_FirewallRules')
                }
            }

            $DataStoreDependsOn += @('[ArcGIS_Server]Server')

            ArcGIS_DataStore DataStore
		    {
			    Ensure                     = 'Present'
			    SiteAdministrator          = $SiteAdministratorCredential
			    ServerHostName             = $MachineName
			    ContentDirectory           = "$($env:SystemDrive)\\arcgis\\datastore\\content"
			    IsStandby                  = $false
                #DatabaseBackupsDirectory   = $DataStoreBackupLocation
                #FileShareRoot              = "\\$($FileShareHostName)\$($FileShareName)"
                RunAsAccount               = $ServiceCredential 
                DataStoreTypes             = $DataStoreTypes.split(",")
                IsEnvAzure                 = $true
                IsTileCacheDataStoreClustered = $IsTileCacheDataStoreClustered
                DependsOn                  = $DataStoreDependsOn
		    } 
	
            if($env:ComputerName -ieq $LastHostName) # Perform on Last machine
            {
                ArcGIS_Federation Federate
                {
                    PortalHostName = $ExternalDNSHostName
                    PortalPort = 443
                    PortalContext = 'portal'
                    ServiceUrlHostName = $ExternalDNSHostName
                    ServiceUrlContext = 'server'
                    ServiceUrlPort = 443
                    ServerSiteAdminUrlHostName = $ExternalDNSHostName
                    ServerSiteAdminUrlPort = 443
                    ServerSiteAdminUrlContext ='server'
                    Ensure = 'Present'
                    RemoteSiteAdministrator = $SiteAdministratorCredential
                    SiteAdministrator = $SiteAdministratorCredential
                    ServerRole = 'HOSTING_SERVER'
                    ServerFunctions = 'GeneralPurposeServer'
                    DependsOn =  @('[ArcGIS_ServerSettings]ServerSettings','[ArcGIS_PortalSettings]PortalSettings','[ArcGIS_DataStore]DataStore')
                }
            }

		    ArcGIS_WindowsService ArcGIS_GeoEvent_Service
		    {
			    Name		= 'ArcGISGeoEvent'
			    Credential  = $ServiceCredential
			    StartupType = 'Manual'
			    State		= 'Stopped' 
			    DependsOn   = if(-Not($IsServiceCredentialDomainAccount)){ @('[User]ArcGIS_RunAsAccount')}else{ @()}
		    }
        }
	}
}