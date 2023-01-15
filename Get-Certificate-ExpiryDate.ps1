# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2023-01-14	njeffrey	Script created


# FUTURE ENHANCEMENTS
# -------------------
# consider adding some logic to send an email report of all the certificates
# Create a new array to hold PSComputerName values that respond to ping but do not respond to PowerShell Remoting requests


# TROUBLESHOOTING
# --------------- 
# If you get this error message, it means you need to install a feature.
# Server Manager, Add Roles, Features, Remote Server Administation Tools, Role Administration Tools, AD DS and AD LS Tools
# Or from the CLI for Win2016 and above: Get-WindowsFeature | where name -like RSAT-AD-Tools | Install-WindowsFeature
# PS C:\temp> Get-ADComputer -Filter "OperatingSystem -like 'windows server*'" | Select -expandproperty name
# Get-ADComputer : The term 'Get-ADComputer' is not recognized as the name of a cmdlet, function, script file, or
# operable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.



# If you get this message, it means there is a ComputerName defined in Active Directory, but no corresponeding DNS entry.  
# This might be an obsolete computer account in AD, so consider deleting it from AD Sites and Services.
# [HYPERV2] Connecting to remote server HYPERV2 failed with the following error message : 
# The WinRM client cannot process the request because the server name cannot be resolved.



# If you get this message, it seems related to WinRM  permissions
#[HYPERV1] Connecting to remote server HYPERV1 failed with the following error message : The WinRM client cannot
#process the request. The WinRM client tried to use Kerberos authentication mechanism, but the destination computer
#(HYPERV1:5985) returned an 'access denied' error. Change the configuration to allow Kerberos authentication mechanism
#to be used or specify one of the authentication mechanisms supported by the server. To use Kerberos, specify the local
#computer name as the remote destination. Also verify that the client computer and the destination computer are joined
#to a domain. To use Basic, specify the local computer name as the remote destination, specify Basic authentication and
#provide user name and password. Possible authentication mechanisms reported by server:     Negotiate For more
#information, see the about_Remote_Troubleshooting Help topic.
#    + CategoryInfo          : OpenError: (HYPERV1:String) [], PSRemotingTransportException
#    + FullyQualifiedErrorId : AccessDenied,PSSessionStateBroken




# How to create a self-signed certificate for testing
# https://adamtheautomator.com/new-selfsignedcertificate/
# Create a self-signed certificate in the local machine personal certificate store valid for 24 months and store the result in the $cert variable.
# $cert = New-SelfSignedCertificate -DnsName localsite.com -FriendlyName MySelfSignedCert3 -NotAfter (Get-Date).AddDays(1)      #expires 1 day from now
# $cert = New-SelfSignedCertificate -DnsName localsite.com -FriendlyName MySelfSignedCert3 -NotAfter (Get-Date).AddMinutes(1)   #expires 1 minute from now




function Get-Certificate-ExpiryDate {
   #
   $verbose = "yes"
   $verbose = "no"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Certificate-ExpiryDate" }
   #
   # declare variables
   $service = "Certificate Expiry Date"
   $verbose = "yes"
   $servers = @()   #create empty array
   $DaysUntilExpiryWarningThreshold = 60
   $Certificates_NotExpired         = ""   #start with blank list to be used in output
   $Certificates_SoonToExpire       = ""   #start with blank list to be used in output
   $Certificates_AlreadyExpired     = ""   #start with blank list to be used in output
   $hash = @{}                             #create an empty hash to hold all the certificate details
   #
   #
   #
   # This check only needs to be run on a daily basis, so check to see if a dummy file containing the output exists.
   $dummyFile = "$env:TEMP\nagios.certificate.expirydate.check.txt"
   #
   # Delete the file if it is more than 60*24 minutes old
   if (Test-Path $dummyFile -PathType leaf) { 
      if ($verbose -eq "yes") { Write-Host "   checking age of flag file $dummyFile" }
      $lastWrite = (get-item $dummyFile).LastWriteTime
      $age_in_minutes = (New-TimeSpan -Start (Get-Date $lastWrite) -End (Get-Date)).TotalMinutes  #do some math to figure file age in minutes
      if ($age_in_minutes -gt 1440) {
         if ($verbose -eq "yes") { Write-Host "   deleting obsolete dummy file $dummyFile" }
         Remove-Item $dummyFile
      }
   }
   # If the file exists, print the output and exit, which essentially skips this iteration of the check.
   if ((Test-Path $dummyFile -PathType leaf)) { 
      if ($verbose -eq "yes") { Write-Host "   using cached result from earlier check" }
      # figure out if the last check result was OK | WARN | CRITICAL
      $plugin_state  = 3 								#start with a value of UNKNOWN just in case the contents of $dummyFile are corrupt
      $plugin_output = Get-Content $dummyFile  						#read the contents of the text file into a variable
      if     ( $plugin_output -match "$service OK"       ) { $plugin_state = 0 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service WARN"     ) { $plugin_state = 1 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service CRITICAL" ) { $plugin_state = 2 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service UNKNOWN"  ) { $plugin_state = 3 }	#0=ok 1=warn 2=critical 3=unknown
      if ($verbose -eq "yes") { Write-Host $plugin_output }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return										#break out of function
   }				
   #
   # If we get this far, no dummy text file exists with the previous check output, so perform the check.
   #
   #
   # check to see if the ActiveDirectory Powershell module exists, which contains the Get-ADComputer command
   #
   if (Get-Module -Name ActiveDirectory) {
      if ($verbose -eq "yes") { Write-Host "Found required PowerShell module ActiveDirectory" }
   } 
   else {
      $plugin_state = 3
      $plugin_output = "$service UNKNOWN - cannot find ActiveDirectory PowerShell module.  Please install with: Get-WindowsFeature | where name -like RSAT-AD-Tools | Install-WindowsFeature "  
      if ($verbose -eq "yes") { Write-Host $plugin_output }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return
   }
   #
   # if we get this far, we know that the ActiveDirectory Powershell module is available, which contains the Get-ADComputer command
   #
   # query Active Directory to get a list of all the Windows servers
   $server_list = Get-ADComputer -Filter "OperatingSystem -like 'windows server*'" | Select -expandproperty name
   if ($verbose -eq "yes") { Write-Host "Active Directory query reports these matching hosts:" $server_list }
   #
   #
   # ping each server to confirm DNS name resolution exists and the remote server is up 
   if ($verbose -eq "yes") {
      Write-Host ""
      Write-Host "Attempting to ping each host"
   }
   foreach ($server in $server_list) {
      #
      # confirm the remote machine responds to ping and PowerShell Remoting
      #
      if ( Test-Connection -Count 1 -Quiet  -ErrorAction Stop $server ) {
         # above command returns $True if any of the pings were successful
         if ($verbose -eq "yes") { Write-Host "      ping reply from $server" }
         # confirm the local machine has sufficient permission to connect to remote host via PowerShell remoting
         try { 
            $command = { Get-Childitem -Path Cert:\LocalMachine\my | Select-Object PSComputerName,Subject,Notafter,Issuer,ThumbPrint,FriendlyName }
            Invoke-Command -ComputerName $Server -ScriptBlock $command -ErrorAction stop
            $servers += ,$server   #add the hostname to the $servers array
         }
         catch {
            Write-Host "Unable to connect to $server via Powershell remoting, will skip this host"
         }
      } else {
         Write-Host "   no ping reply from $server"
      }
   }
   Write-Host "These servers reponded to ping:" $servers
   #
   # Use PowerShell Remoting to connect to all the remote servers in $servers 
   #
   Foreach ($Server in $Servers){
      $hash.$server = @{}   #create nested hash using the computername as a hash key
      Write-Host ""
      Write-Host "Checking certificates on $server"
      $command = { Get-Childitem -Path Cert:\LocalMachine\my | Select-Object PSComputerName,Subject,Notafter,Issuer,ThumbPrint,FriendlyName }
      $certificates = Invoke-Command -ComputerName $Server -ScriptBlock $command
      foreach ($x in $certificates) {
         Write-Host $x.PSComputerName $x.Thumbprint $x.FriendlyName $x.NotAfter
         #
         # Save the interesting certificate attributes to a 3-levels-deep hash
         #
         $thumbprint = $x.Thumbprint | Out-String
         $hash.$server.$thumbprint = @{}  #create (yet another deeper level of) nested hash using the (supposedly unique) thumbprint of the certificate as a hash key
         $hash.$server.$thumbprint.Thumbprint     = $x.Thumbprint     | Out-String
         $hash.$server.$thumbprint.PSComputername = $x.PSComputerName | Out-String
         $hash.$server.$thumbprint.Notafter       = $x.Notafter       | Out-String
         $hash.$server.$thumbprint.Issuer         = $x.Issuer         | Out-String
         $hash.$server.$thumbprint.FriendlyName   = $x.FriendlyName   | Out-String
         #
         #
         # Figure out how many days until certificate expiration
         #
         $DaysUntilExpiry = (New-TimeSpan -Start (Get-Date) -End (Get-Date $x.NotAfter)).TotalDays  #do some math to figure out number of days between now and license expiration date
         $DaysUntilExpiry = [math]::round($DaysUntilExpiry,0)   			                 # truncate to 0 decimal places, nearest day is close enough
         $hash.$server.$thumbprint.DaysUntilExpiry = $DaysUntilExpiry  #add to hash
         Write-Host "Days until expiry:" $DaysUntilExpiry
         $FriendlyName = $hash.$server.$thumbprint.FriendlyName | Out-String
         if ( $FriendlyName -NotMatch "\S" ) { $FriendlyName = $hash.$server.$thumbprint.Thumbprint | Out-String }  # if FriendlyName is blank, use Thumbprint instead
         #
         # find certificates that will NOT expire soon
         #
         if ($DaysUntilExpiry -gt $DaysUntilExpiryWarningThreshold ) {
            $Certificates_NotExpired = "$Certificates_NotExpired OK: $server certificate $FriendlyName is ok, expiring in $DaysUntilExpiry days."
            $Certificates_NotExpired = $Certificates_NotExpired -replace "`t|`n|`r",""  #replace newlines with blanks
         }
         #
         # find certificates that will expire soon, but are not yet expired
         #
         if ( ($DaysUntilExpiry -lt $DaysUntilExpiryWarningThreshold) -And ($DaysUntilExpiry -ge 0) ) {
            $Certificates_SoonToExpire = "$Certificates_SoonToExpire WARN: $server certificate $FriendlyName expiring in $DaysUntilExpiry days."
            $Certificates_SoonToExpire = $Certificates_SoonToExpire -replace "`t|`n|`r",""  #replace newlines with blanks
         }
         #
         # find certificates that are already expired
         #
         if ($DaysUntilExpiry -lt 0 ) {
            $Certificates_AlreadyExpired = "$Certificates_AlreadyExpired CRITICAL: $server certificate $FriendlyName already expired $DaysUntilExpiry days ago."
            $Certificates_AlreadyExpired = $Certificates_AlreadyExpired -replace "`t|`n|`r",""  #replace newlines with blanks
         }
      }
   }
   #
   #
   # provide some verbose output for debugging
   #
   if ($verbose -eq "yes") {
      Write-Host ""
      Write-Host "Certificates not expired:"
      Write-Host $Certificates_NotExpired
      Write-Host ""
      Write-Host "Certificates soon to expire:"
      Write-Host $Certificates_SoonToExpire
      Write-Host ""
      Write-Host "Certificates already expired:"
      Write-Host $Certificates_AlreadyExpired
   }
   #
   #
   # Figure out what result will be sent to nagios
   #
   if ( $Certificates_SoonToExpire -match "\S" ) {   # \S means any non-whitespace character
      $plugin_state  = 0			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $Certificates_NotExpired"
   }
   if ( $Certificates_SoonToExpire -match "\S" ) {
      $plugin_state  = 1			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - $Certificates_SoonToExpire"
   }
   if ( $Certificates_AlreadyExpired -match "\S" ) {
      $plugin_state  = 3			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - $Certificates_AlreadyExpired $Certificates_SoonToExpire"  #note that we include CRITICAL messages first, followed by WARN messages
   }
   #
   # send the output to nagios
   #
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return   
} 		#end of function
#
# call the above function
#
Get-Certificate-ExpiryDate




