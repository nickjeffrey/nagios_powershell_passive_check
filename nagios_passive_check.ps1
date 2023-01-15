# Powershell script to submit passive check results to nagios via HTTP
#
# This is the "master" script that sets up the HTTP authentication to the nagios server, 
# and calls additional *.ps1 scripts in the same folder that perform the individual nagios checks.


#OUTSTANDING TASKS
#-----------------


# CHANGE LOG
# ----------
# 2020-12-16	njeffrey	Script created
# 2021-01-11	njeffrey	Add Get-Veeam-365-Health function
# 2022-04-12	njeffrey	Add Get-Console-User function
# 2022-04-12	njeffrey	Ignore domain machine accounts in Get-Windows-Failed-Logins, only look at user accounts
# 2022-04-12	njeffrey	Add Get-Scheduled-Task function
# 2022-05-25	njeffrey	Break out functions into external script files to make maintenance easier
# 2022-05-25	njeffrey	Move authentication details into external *.cfg file
# 2022-07-28	njeffrey	Add Get-IIS-Application-Pool-Status 
# 2022-09-23	njeffrey	Add Get-MPIO-Path-State (for iSCSI / Fibre Channel path status)
# 2023-01-14   njeffrey Add Get-Certificate-ExpiryDate for local certificate stores


# NOTES
# -----
# Each host that submits passive checks to nagios via HTTP should have its own authentication credentials to authenticate to the nagios web interface
# For example, run the following commands on the nagios server:
#   htpasswd -b /etc/nagios/htpasswd.users host1 SecretPass1
#   htpasswd -b /etc/nagios/htpasswd.users host2 SecretPass2
#   htpasswd -b /etc/nagios/htpasswd.users host3 SecretPass3
# To revoke HTTP authentication for a monitored host, use this syntax on the nagios server:
#   htpasswd -D /etc/nagios/htpasswd.users host1
#
# This powershell script should be scheduled to execute every 5 minutes from the LOCALSYSTEM account.
# Running this script as LOCALSYSTEM means you do not have to create a service user account, but it does mean that only local machine resources can be checked.
#
# Schedule this script to run every 5 minutes:
#  schtasks.exe /create /S %computername% /RU SYSTEM /SC minute /MO 5 /TN nagios_passive_check /TR "powershell.exe c:\progra~1\nagios\libexec\nagios_passive_check.ps1"


# ASSUMPTIONS
# -----------
#  If the name of the machine using passive checks is "myhost01":
#   - there should be a nagios contact called "myhost01" 
#   - there should be an apache webserver account called "myhost1" with an htpasswd set to a unique value 
#   - there should be a nagios host defined called "myhost01"
#   - MiXeD cAsE or UPPERcase will be converted to lowercase
#

# TROUBLESHOOTING
# ---------------
#  If you see the following message in /var/log/httpd/error_log, it indicates an error with HTTP authentiction.
#  Confirm the username/password you are using has been added to the the /etc/nagios/htpasswd.users file 
#   [Wed Dec 16 21:33:01.058989 2020] [auth_basic:error] [pid 14741] [client 192.168.99.30:56759] AH01617: user testuser01: authentication failure for "/nagios/cgi-bin/cmd.cgi": Password
#
# When a passive check is successfully submitted, you should see entries similar to the following in /var/log/nagios/nagios.log
#   [1608181188] EXTERNAL COMMAND: PROCESS_SERVICE_CHECK_RESULT;myhost01;pagefile;0;pagefile OK - paging space utilization is 630MB/1280MB(49.2%)|
#   [1608181188] PASSIVE SERVICE CHECK: myhost01;pagefile;0;
#
# When a passive check is successfully submitted, you should see entries similar to the following in /var/log/httpd/access_log
#  192.168.14.30 - PassiveHostName [12/Apr/2022:18:21:12 -0600] "POST /nagios/cgi-bin/cmd.cgi HTTP/1.1" 200 1316 "-" "Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.17763.2268"
#  192.168.14.30 - PassiveHostName [12/Apr/2022:18:21:12 -0600] "POST /nagios/cgi-bin/cmd.cgi HTTP/1.1" 200 1316 "-" "Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.17763.2268"
#  192.168.14.30 - PassiveHostName [12/Apr/2022:18:21:12 -0600] "POST /nagios/cgi-bin/cmd.cgi HTTP/1.1" 200 1316 "-" "Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.17763.2268"
#
# If you see this error, it means you need to allow PowerShell scripts to be executed on the local machine.
# File C:\path\to\script.ps1 cannot be loaded because running scripts is disabled on this system.
# You can fix with: 
#   C:\> powershell Get-ExecutionPolicy
#        Restricted
#   C:\> powershell.exe Set-ExecutionPolicy RemoteSigned
#   C:\> powershell Get-ExecutionPolicy
#        RemoteSigned

# declare variables
$user          = ""								#will be defined in Sanity-Checks function
$htpasswd      = ""								#htpasswd used to authenticate against nagios web server, read from external file in Read-Config-File
$nagios_server = "" 								#hostname of nagios server, read from external file in Read-Config-File
$cmd_cgi       = "/nagios/cgi-bin/cmd.cgi"					#URI for cmd.cgi script on nagios server
#$url           = "http://${nagios_server}${cmd_cgi}"				#full URL to nagios web interface, will be defined after $nagios_server is read from external file in Read-Config-File
$cmd_typ       = 30								#30 = submit passive check results
$cmd_mod       = 2
$passive_host  = ""								#name of the host as defined in hosts.cfg on nagios server.  Will be defined in Sanity-Checks function
$service       = ""								#matches the "service" description line in nagios server services.cfg file
$plugin_state  = 0           							#nagios return codes 0=ok 1=warn 2=critical 3=unknown
$plugin_output = ""								#text output of nagios plugin response
$verbose       = "yes"								#yes|no flag to increase verbosity for debugging




function Read-Config-File {
   #
   if ($verbose -eq "yes") { Write-Host "Running Read-Config-File function" }
   #
   # Site-specific details are stored in a config file that looks similar to the following:
   #nagios_server=mynagios01.example.com
   #passive_host=serv01.example.com
   #http_user=serv01
   #htpasswd=SecretPasswordForHTTPauth
   #
   #
   # Confirm the config file exists
   #
   $configfile = "$PSScriptRoot\nagios_passive_check.cfg"
   if (-Not(Test-Path $configfile -PathType leaf)) { 					#exit script if file does not exist
      Write-Host "ERROR: Cannot find $configfile config file - exiting script"
      Write-Host "Please create file $configfile with the following contents:"
      Write-Host "nagios_server=mynagios01.example.com"
      Write-Host "passive_host=ThisMonitoredHost.example.com"
      Write-Host "http_user=ThisMonitoredHost"
      Write-Host "htpasswd=SomeSecretPasswordForHTTPauth"
      exit 
   }				
   #
   #
   # Figure out the hostname/IPaddr of the nagios server that passive checks will be sent to 
   #
   $nagios_server = Get-Content $configfile						#slurp in the entire file contents
   $nagios_server = $nagios_server -match   '^nagios_server='				#parse out the interesting line of the multiline file
   $nagios_server = $nagios_server -replace '^nagios_server='				#remove the nagios_server= portion, leaving just the hostname
   if (!$nagios_server) { Write-Host "ERROR: Cannot find nagios_server=nagios01.example.com line in config file $configfile - exiting script" ; exit }  #problem if $nagios_server is blank or undefined
   if ($verbose -eq "yes") { Write-Host "   Found nagios_server=$nagios_server" }				
   #
   # By default, powershell variables are only available inside the current fuction.
   # Since we want the $nagios_server variable to be available throughout this script, change its scope.
   # The available scopes are: global, local, private, script, using, workflow
   $script:nagios_server = $nagios_server
   #
   #
   #
   # Figure out the name of the local machine that will be submitting passive checks to the $nagios_server via HTTP
   # In theory, the local hostname *should* match the host definition in the hosts.cfg file on the nagios server, but we should not assume.
   # For example, some nagios sysadmins populate the hosts.cfg with the FQDN of each monitored host, and some just use the short hostname.
   # To avoid making assumptions, we we take the value from the passive_host=somehost.example.com line in the $configfile config file.
   # 
   $passive_host = Get-Content $configfile						#slurp in the entire file contents
   $passive_host = $passive_host -match   '^passive_host='				#parse out the interesting line of the multiline file
   $passive_host = $passive_host -replace '^passive_host='				#remove the passive_host= portion, leaving just the hostname
   $passive_host = "$passive_host"  							#convert array to string
   if (!$passive_host) { Write-Host "ERROR: Cannot find passive_host=mypassivehost.example.com line in config file $configfile - exiting script" ; exit }  #problem if $passive_host is blank or undefined
   if ($verbose -eq "yes") { Write-Host "   Found passive_host=$passive_host" }				
   #
   # By default, powershell variables are only available inside the current fuction.
   # Since we want the $nagios_server variable to be available throughout this script, change its scope.
   # The available scopes are: global, local, private, script, using, workflow
   $script:passive_host = $passive_host
   #
   #
   #
   #
   #
   # Figure out the web server username that will be used for HTTP authentication 
   # In theory, the $http_user should be the same as the $passive_host, but some nagios sysadmins with multiple DNS suffixes 
   # will define the host entries using the FQDN, but will use a short hostname in the htpasswd file.
   # To avoid making assumptions, we we take the value from the passive_user=somehost line in the $configfile config file.
   # 
   $http_user = Get-Content $configfile						#slurp in the entire file contents
   $http_user = $http_user -match   '^http_user='				#parse out the interesting line of the multiline file
   $http_user = $http_user -replace '^http_user='				#remove the http_user= portion, leaving just the username used in the htpasswd file
   $http_user = "$http_user"  							#convert array to string
   if (!$http_user) { Write-Host "ERROR: Cannot find http_user=myserver line in config file $configfile - exiting script" ; exit }  #problem if $http_user is blank or undefined
   if ($verbose -eq "yes") { Write-Host "   Found http_user=$http_user" }				
   #
   # By default, powershell variables are only available inside the current fuction.
   # Since we want the $nagios_server variable to be available throughout this script, change its scope.
   # The available scopes are: global, local, private, script, using, workflow
   $script:http_user = $http_user
   #
   #
   #
   # HTTP basic authentication credentials are needed to submit the passive check to nagios web server at $url
   # There must be an entry in the /etc/nagios/htpasswd file containing the hostname of this machine and a password used for HTTP auth to $url
   # This section reads the contents of the htpasswd.txt file in the same directory as this script
   $htpasswd = Get-Content $configfile						#slurp in the entire file contents
   $htpasswd = $htpasswd -match   '^htpasswd='					#parse out the interesting line of the multiline file
   $htpasswd = $htpasswd -replace '^htpasswd='					#remove the htpasswd= portion, leaving just the password
   $htpasswd = "$htpasswd"  							#convert array to string
   if (!$htpasswd) { Write-Host "ERROR: Cannot find htpasswd=xxxxx line in config file $configfile - exiting script" ; exit }  #problem if $htpasswd is blank or undefined
   if ($verbose -eq "yes") { Write-Host "   HTTP auth credentials are ${http_user}:${htpasswd}" }
   #
   # By default, powershell variables are only available inside the current fuction.
   # Since we want the $htpasswd variable to be available throughout this script, change its scope.
   # The available scopes are: global, local, private, script, using, workflow
   $script:htpasswd = $htpasswd
}										#end of function



function Ping-Nagios-Server {
   #
   if ($verbose -eq "yes") { Write-Host "Running Ping-Nagios-Server function" }
   #
   # Confirm the nagios server responds to ping
   #
   if ($verbose -eq "yes") { Write-Host "   attempting to ping nagios server $nagios_server" }
   try { 
      Test-Connection -Count 4 -Quiet -ErrorAction Stop $nagios_server
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Test-Connection powershell module.  Exiting script."
      exit 
   }
   if ( Test-Connection -Count 4 -Quiet  -ErrorAction Stop $nagios_server ) {
      # above command returns $True if any of the pings were successful
      if ($verbose -eq "yes") { Write-Host "   successful ping test to $nagios_server" }
   } else {
      Write-Host "ERROR: Cannot ping nagios server $nagios_server , exiting script."
      exit 									#exit script
   }
}										#end of function





function Submit-Nagios-Passive-Check {
   #
   if ($verbose -eq "yes") { Write-Host "   Running Submit-Nagios-Passive-Check function"  }
   #
   # Define the URL for the nagios server web interface that will accept the passive checks via HTTP
   $url = "http://${nagios_server}${cmd_cgi}" 
   #
   # Generate the HTTP basic authentication credentials
   $pair            = "$($http_user):$($htpasswd)"								#join as username:password
   $encodedCreds    = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))         	#Invoke-WebRequest wants BASE64 encoded username:password
   $basicAuthValue  = "Basic $encodedCreds"
   $Headers         = @{Authorization = $basicAuthValue}
   $postParams      = @{cmd_typ=$cmd_typ;cmd_mod=$cmd_mod;host=$passive_host;service=$service;plugin_state=$plugin_state;plugin_output=$plugin_output;btnSubmit="Commit"}
   #
   #
   # Submit the message via HTTP
   # Note: The -UseBasicParsing command is not required for PowerShell 6.x and later. 
   #       For older PowerShell versions, you may get this error if you omit the -UseBasicParsing parameter:
   #       Invoke-WebRequest : The response content cannot be parsed because the Internet Explorer engine is not available, or Internet Explorer's first-launch configuration is not complete. Specify the UseBasicParsing parameter and try again.
   try {
      if ($verbose -eq "yes") { Write-Host "   Invoke-WebRequest -UseBasicParsing -Uri $url -Headers <authentication credentials> -Method POST -Body cmd_typ=$cmd_typ;cmd_mod=$cmd_mod;host=$passive_host;service=$service;plugin_state=$plugin_state;plugin_output=$plugin_output;btnSubmit=Commit" }
      $Response = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $Headers -Method POST -Body $postParams
      $StatusCode = $Response.StatusCode    # This will only execute if the Invoke-WebRequest is successful.
   }
   catch {
      # note that value__ is not a typo
      $StatusCode = $_.Exception.Response.StatusCode.value__
   }
   # check for the HTTP return code
   if ( $StatusCode -eq "200" ) { 
      Write-Host $plugin_output								#this is what the output would look like for a nagios active check
      Write-Host "OK HTTP 200 Passive check submitted successfully for $service" 
   } elseif ( $StatusCode -eq "401" ) { 
      Write-Host "ERROR: HTTP 401 Unathorized.  Please confirm the htpasswd credentials ${http_user}:${htpasswd} are valid for HTTP basic authentication." 
   } else { Write-Host "UNKNOWN HTTP $StatusCode response.  Please check the username:password used to submit this passive check to the nagios server." }
}





# ----------------- main body of script ------------------------
Read-Config-File
Ping-Nagios-Server
#exit
#
# call external scripts in the current directory
#
#$external_function="Get-Processor-Utilization"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
#$external_function="Get-Paging-Utilization"                ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
#$external_function="Get-Disk-Space-Utilization"            ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
#$external_function="Get-Uptime"                            ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-LastWindowsUpdate"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Disk-SMART-Health"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Disk-RAID-Health"                  ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Disk-Latency-IOPS"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Windows-Failed-Logins"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Windows-Defender-Antivirus-Status" ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Windows-Firewall-Status"           ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-HyperV-Replica-Status"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-TSM-Client-Backup-Age"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Veeam-Health"                      ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Veeam-365-Health"                  ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Console-User"                      ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-RDP-User"                          ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Scheduled-Task-001"                ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-IIS-Application-Pool-Status"       ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename --ApplicationPool DefaultAppPool}
 $external_function="Get-IIS-Application-Pool-Status"       ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename --ApplicationPool MyCustomPoolName}
 $external_function="Get-MPIO-Path-State"                   ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 $external_function="Get-Certificate-ExpiryDate"            ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename }
 
 
