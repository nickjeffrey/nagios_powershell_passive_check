# Powershell script to submit passive check results to nagios via HTTP

#OUTSTANDING TASKS
#-----------------
# figure where to put the ps1 file and how to schedule
# The user account running this script likely needs admin rights.  Fix up the documentation referring to low privileged user.
# Get rid of the hardcoded $nagios_server variable, and put in the htpasswd.txt file 

# CHANGE LOG
# ----------
# 2020-12-16	njeffrey	Script created
# 2021-01-11	njeffrey	Add Get-Veeam-365-Health function
# 2022-04-12	njeffrey	Add Get-Console-User function
# 2022-04-12	njeffrey	Ignore domain machine accounts in Get-Windows-Failed-Logins, only look at user accounts
# 2022-04-12	njeffrey	Add Get-Scheduled-Task function


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
# If the monitored host is part of an Active Directory domain, create a low-privileged userid called "nagios" with a strong password.
# You can also deny the Interactive login privilege to that userid for added security.
#
# If the monitored host is not joined to an Active Directory, create a local user account named "nagios".  For example:
#   net user nagios SomeSuperSecretComplexPassword1! /comment:"service account to submit passive checks to nagios server" /add
#   cusrmgr -u nagios +s PasswordNeverExpires
#   **** grant user the "Logon as a batch job" privilege.  Secpol.msc, Security Settings, Local Policies, User Rights Assignment, Logon as a batch job
# Schedule this script to run every 5 minutes:
#  schtasks.exe /create /S %computername% /RU SYSTEM /SC minute /MO 5 /TN nagios_passive_check /TR "powershell.exe c:\temp\nagios_passive_check.ps1"


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
$htpasswd      = ""								#htpasswd used to authenticate against nagios web server, read from external file in Sanity-Checks function
$nagios_server = "nagios.example.com"						#adjust as appropriate to point at nagios server FQDN
$nagios_server = "nyxmon1.nyx.local"						#adjust as appropriate to point at nagios server FQDN
if ($nagios_server -match '(^[\w-_\d]+)\.(.*)') { $dns_suffix = $matches[2]}    #if $nagios_server is a FQDN, parse out the DNS suffix  ($matches is a built-in Powershell array)
$cmd_cgi       = "/nagios/cgi-bin/cmd.cgi"					#URI for cmd.cgi script on nagios server
$url           = "http://${nagios_server}${cmd_cgi}"				#concatenate above two variables together to form the URL to cmd.cgi on the nagios server
$cmd_typ       = 30								#30 = submit passive check results
$cmd_mod       = 2
$passive_host  = ""								#name of the host as defined in hosts.cfg on nagios server.  Will be defined in Sanity-Checks function
$service       = ""								#matches the "service" description line in nagios server services.cfg file
$plugin_state  = 0           							#nagios return codes 0=ok 1=warn 2=critical 3=unknown
$plugin_output = ""								#text output of nagios plugin response
$verbose       = "yes"								#yes|no flag to increase verbosity for debugging



function Sanity-Checks {
   #
   if ($verbose -eq "yes") { Write-Host "Running Sanity-Checks function" }
   #
   # Confirm the nagios server responds to ping
   #
   if ($verbose -eq "yes") { Write-Host "   attempting to ping nagios server $nagios_server" }
   try { 
      Test-Connection -Count 4 -Quiet  -ErrorAction Stop $nagios_server
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
   #
   #
   #
   # Figure out the hostname of the local machine, which will be used in two places:
   #    - HTTP username passed to nagios webserver to be authenticated by htpasswd
   #    - value of "define host" on nagios server in hosts.cfg file
   # This will match a defined contact in contacts.cfg on the nagios server, and a defined host in hosts.cfg on the nagios server
   # To keep things consistent, we use the DNS hostname of the local machine.
   if ($verbose -eq "yes") { Write-Host "   attempting to determine local hostname" }
   try { 
      $user = $(Get-WmiObject Win32_Computersystem -ErrorAction Stop).name
      $user = $user.ToLower()						#convert to lowercase
      #
      # By default, powershell variables are only available inside the current fuction.
      # Since we want the $passive_host variable to be available throughout this script, change its scope.
      # The available scopes are: global, local, private, script, using, workflow
      $script:user = $user
   }
   catch {
      Write-Host "ERROR: insufficient permissions to run Get-WmiObject powershell module.  Exiting script."
      exit 
   }
   # we only get this far if Get-WmiObject was successful in the previous section
   #   
   if ( $user = $(Get-WmiObject Win32_Computersystem -ErrorAction Stop).name) {
      $user         = $user.ToLower()						#convert to lowercase
      $passive_host = "$user.$dns_suffix"					#if host definition on nagios server includes domain suffix
      if ($verbose -eq "yes") { Write-Host "   local hostname is $user , FQDN is $passive_host" }
      #
      # By default, powershell variables are only available inside the current fuction.
      # Since we want the $passive_host variable to be available throughout this script, change its scope.
      # The available scopes are: global, local, private, script, using, workflow
      $script:passive_host = $passive_host
   } else {
      Write-Host "ERROR: Cannot determine local hostname.  Please check WMI permissions. Exiting script."
      exit 
   }
   #
   #
   #
   # HTTP basic authentication credentials are needed to submit the passive check to nagios web server at $url
   # There must be an entry in the /etc/nagios/htpasswd file containing the hostname of this machine and a password
   # This section reads the contents of the htpasswd.txt file in the same directory as this script
   $fileToCheck = "$PSScriptRoot\htpasswd.txt"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { 					#exit script if file does not exist
      Write-Host "ERROR: Cannot find $fileToCheck file containing HTTP authentication password - exiting script"
      exit 
   }				
   if (Test-Path $fileToCheck -PathType leaf) {	      					#check to see if the file exists
      # $fileToCheck must be nonzero in length, lines beginning with # will be ignored
      Get-Content $PSScriptRoot\htpasswd.txt -ErrorAction Stop | Where-Object {$_.length -gt 0} | Where-Object {!$_.StartsWith("#")} | ForEach-Object { $htpasswd = $_ }
      if ($verbose -eq "yes") { Write-Host "   HTTP auth credentials are ${user}:${htpasswd}" }
      #
      # By default, powershell variables are only available inside the current fuction.
      # Since we want the $passive_host variable to be available throughout this script, change its scope.
      # The available scopes are: global, local, private, script, using, workflow
      $script:htpasswd = $htpasswd
   }
}											#end of function









function Submit-Nagios-Passive-Check {
   #
   if ($verbose -eq "yes") { Write-Host "   Running Submit-Nagios-Passive-Check function"  }
   #
   # Generate the HTTP basic authentication credentials
   $pair            = "$($user):$($htpasswd)"									#join as username:password
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
      Write-Host "ERROR: HTTP 401 Unathorized.  Please confirm the htpasswd credentials ${user}:${htpasswd} are valid for HTTP basic authentication." 
   } else { Write-Host "UNKNOWN HTTP $StatusCode response.  Please check the username:password used to submit this passive check to the nagios server." }
}




# ----------------- main body of script ------------------------
Sanity-Checks

#$external_function="Get-Processor-Utilization"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Processor-Utilization             }
#$external_function="Get-Paging-Utilization"                ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Paging-Utilization                }
#$external_function="Get-Disk-Space-Utilization"            ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Disk-Space-Utilization            }
#$external_function="Get-Uptime"                            ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Uptime                            }
 $external_function="Get-LastWindowsUpdate"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-LastWindowsUpdate                 }
 $external_function="Get-Disk-SMART-Health"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Disk-SMART-Health                 }
 $external_function="Get-Disk-RAID-Health"                  ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Disk-RAID-Health                  }
 $external_function="Get-Disk-Latency-IOPS"                 ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Disk-Latency-IOPS                 }
 $external_function="Get-Windows-Failed-Logins"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Windows-Failed-Logins             }
 $external_function="Get-Windows-Defender-Antivirus-Status" ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Windows-Defender-Antivirus-Status }
 $external_function="Get-Windows-Firewall-Status"           ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Windows-Firewall-Status           }
 $external_function="Get-HyperV-Replica-Status"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-HyperV-Replica-Status             }
 $external_function="Get-TSM-Client-Backup-Age"             ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-TSM-Client-Backup-Age             }
 $external_function="Get-Veeam-Health"                      ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Veeam-Health                      }
 $external_function="Get-Veeam-365-Health"                  ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Veeam-365-Health                  }
 $external_function="Get-Console-User"                      ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Console-User                      }
 $external_function="Get-RDP-User"                          ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-RDP-User                          }
 $external_function="Get-Scheduled-Task-001"                ; $filename = (Join-Path -Path "$PSScriptRoot" -ChildPath "$external_function.ps1") ; if (Test-Path -PathType Leaf -Path "$filename") { Write-Host "   sourcing file $filename" ; . $filename ;  Get-Scheduled-Task-001               }