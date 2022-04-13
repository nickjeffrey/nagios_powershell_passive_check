# Powershell script to submit passive check results to nagios via HTTP

#OUTSTANDING TASKS
#-----------------
# get into a git repo
# figure where to put the ps1 file and how to schedule
# The user account running this script likely needs admin rights.  Fix up the documentation referring to low privileged user.


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
# This powershell script should be scheduled to execute every 5 minutes from a low-privileged userid.
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



function Get-Processor-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Processor-Utilization function" }
   #
   # declare variables
   $service = "CPUutil"                         #name of check defined on nagios server
   $threshold_warn = 50				#warn     if processor utilization is more than 50%
   $threshold_crit = 75				#critical if processor utilization is more than 75%
   #
   try {
      $ProcessorResults = Get-CimInstance -Class Win32_Processor -ComputerName $Computer  -ErrorAction Stop
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine paging space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
   #
   # We only get this far if $ProcessorResults contains data
   #
   $processor_load_pct = $ProcessorResults.LoadPercentage
   if ($verbose -eq "yes") { Write-Host "   Processor utilization:${processor_load_pct}%" }
   #
   # submit nagios passive check results
   #
   if ($processor_load_pct -le $threshold_warn) {
      $plugin_state = 0 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_warn) {
      $plugin_state = 1 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_crit) {
      $plugin_state = 2 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - processor utilization is ${processor_load_pct}%"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
   Submit-Nagios-Passive-Check
}



function Get-Paging-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Paging-Utilization function" }
   #
   # declare variables
   $service = "pagefile"                        #name of check defined on nagios server
   $threshold_warn = 50				#warn     if paging space utilization is more than 50%
   $threshold_crit = 75				#critical if paging space utilization is more than 50%
   #
   try {
      $PageFileResults = Get-CimInstance -Class Win32_PageFileUsage -ComputerName $Computer -ErrorAction Stop
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine paging space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
   #
   # We only get this far if $PageFileResults contains data
   #
   $paging_total_mb = $PageFileResults.AllocatedBaseSize
   $paging_used_mb  = $PageFileResults.CurrentUsage
   if ( $paging_total_mb -gt 0 ) { $paging_used_pct = $paging_used_mb / $paging_total_mb * 100 } else { $paging_used_pct = 0 }    # avoid divide by zero error if $paging_total_mb is zero size
   $paging_used_pct = [math]::round($paging_used_pct,1)   	                        #truncate to 1 decimal place
   if ($verbose -eq "yes") { Write-Host "   Paging space used ${paging_used_mb}MB/${paging_total_mb}MB(${paging_used_pct}%)" }
   #
   # submit nagios passive check results
   #
   if ($paging_used_pct -le $threshold_warn) {
      $plugin_state = 0 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%"
   }
   if ($paging_used_pct -gt $threshold_warn) {
      $plugin_state = 1 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%.  Consider adding more RAM."
   }
   if ($paging_used_pct -gt $threshold_crit) {
      $plugin_state = 2 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%.  System will crash if paging space usage reaches 100%"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
   Submit-Nagios-Passive-Check
}




function Get-Disk-Space-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Disk-Space-Utilization function" }
   #
   # declare variables
   $service = "Drive $DeviceID"                 #name of check defined on nagios server
   $threshold_warn = 80				#warn     if disk space utilization is more than 80%
   $threshold_crit = 90				#critical if disk space utilization is more than 90%
   $driveletters = "C:","D:","E:","F:","G:","H:","I:","J:","K:","L:","M:","N:","O:","P:","Q:","R:","S:","T:","U:","V:","W:","X:","Y:","Z:"
   #
   try {
      $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" -ErrorAction Stop    #Drivetype=3 means local hard disk (not a CDROM, not a network drive)
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
   # we only get here if the previous try/catch confirmed that sufficient permissions exist to run Get-WmiObject 
   foreach ($driveletter in ($driveletters)) {
      try {
         $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" | Where {($_.DeviceID -eq $driveletter) -and ($_.size -gt 0)} | select-object DeviceID,Size,FreeSpace -ErrorAction Stop
      }
      catch {
         Write-Host "Access denied.  Please check your WMI permissions."
         $service = "Drive $DeviceID"                 #update service description with current drive letter
         $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return 					#break out of function
      }
      #
      # We only get this far if $diskInfo contains data
      #
      if ($diskInfo.Size -gt 0) {
         $DeviceID        = $diskInfo.DeviceID
         $Size_bytes      = $diskInfo.Size
         $Size_GB         = $Size_bytes / 1024 / 1024 / 1024
         $Size_GB         = [math]::round($Size_GB,0)   	                        #truncate to 0 decimal places
         $FreeSpace_bytes = $diskInfo.FreeSpace
         $FreeSpace_GB    = $FreeSpace_bytes / 1024 / 1024 / 1024
         $FreeSpace_GB    = [math]::round($FreeSpace_GB,0)   	                        #truncate to 0 decimal places
         $Used_GB         = $Size_GB - $FreeSpace_GB
         $Used_pct        = $Used_GB / $Size_Gb * 100
         $Used_pct        = [math]::round($Used_pct,1)   	                        #truncate to 1 decimal places
         $Free_pct        = 100-$Used_pct
         $Free_pct        = [math]::round($Free_pct,1)   	                        #truncate to 1 decimal places
         $service         = "Drive $DeviceID"                 #update service description with current drive letter
         if ($verbose -eq "yes") { Write-Host "Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)" }
         #
         # submit nagios passive check results
         #
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -ge $threshold_crit) ) {
            $plugin_state = 2 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service CRITICAL - (usage > ${threshold_crit}%) -  Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
            Submit-Nagios-Passive-Check
         }
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -lt $threshold_crit) ) {
            $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service WARN - (usage > ${threshold_warn}%) - Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
            Submit-Nagios-Passive-Check
         }
         if ($Used_pct -le $threshold_warn) {
            $plugin_state = 0 				 	#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service OK - Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
            Submit-Nagios-Passive-Check
         }
      }								#end of if blcok
   }								#end of foreach block
}								#end of function


function Get-Uptime {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Uptime function" }
   #
   # declare variables
   $service = "uptime" 	  								#name of check defined on nagios server
   #
   $uptime = (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime
   $uptime = $uptime.TotalMinutes
   if ($verbose -eq "yes") { Write-Host "   uptime is $uptime minutes" }
   #
   if ($uptime -ge 1440 ) {								#system has been up for more than 1 day (1440 minutes)
      $uptime = $uptime / 1440								#convert uptime to days
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest day is close enough 
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime days"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ( ($uptime -gt 60) -and ($uptime -lt 1440) ) {					#system has been up for more than 1 hour, but less than 1 day, so report in hours
      $uptime = $uptime / 60
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest hour is close enough 
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime hours"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($uptime -ge 30 ) { 								#system has been up for more than 30 minutes but less than 60 minutes, so report in minutes
      $uptime = $uptime 
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "OK - System uptime is $uptime minutes" }
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime minutes"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($uptime -lt 30 ) {
      $uptime = $uptime 
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "WARN - recent reboot detected.  System uptime is $uptime minutes" }
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - recent reboot detected.  System uptime is $uptime minutes"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
} 											#end of function




function Get-LastWindowsUpdate {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-LastWindowsUpdate function" }
   #
   # The intent of this function is to find Windows boxes that have not been updated in >90 days
   # Which would typically indicate the machine is not on a regular patching schedule
   #
   #
   # declare variables
   $service = "Windows Update"                 							#name of check defined on nagios server
   $most_recent_hotfix = 99999									#initialize variable with a high number of days since last hotfix
   #
   try {
      Get-HotFix -ErrorAction SilentlyContinue | sort InstalledOn -Descending | Foreach $_ {
         #if ($verbose -eq "yes") { Write-Host "   most recent hotfix was $most_recent_hotfix days ago" }
         $age_in_days = (New-TimeSpan -Start (Get-Date $_.InstalledOn) -End (Get-Date)).TotalDays
         if ($age_in_days -lt $most_recent_hotfix) { 
            $most_recent_hotfix = $age_in_days 	
            $most_recent_hotfix = [math]::round($most_recent_hotfix,0)   	                        #truncate to 0 decimal places, nearest day is close enough						#find the most recent hotfix based on days since last install
            if ($verbose -eq "yes") { Write-Host "   HotFixID:" $_.HotFixID " InstalledOn:" $_.InstalledOn " ($age_in_days days ago)" }
         } 
      } 											#end of foreach loop
      if ($most_recent_hotfix -eq 99999) {							#could not find any hotfixes / Windows Updates
         $plugin_state = 1 			 	#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - could not find any Windows Updates or patches applied to this system.  Please confirm this host is getting updated."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return						#break out of subroutine
      }
      if ($most_recent_hotfix -gt 90) {								#found at least 1 hotfix, but more than 90 days ago
         $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - most recent Windows patches were applied $most_recent_hotfix days ago.  Please confirm this host is getting updated on a regular basis."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return						#break out of subroutine
      }
      if ($most_recent_hotfix -le 90) {								#found at least 1 hotfix installed within the last 90 days
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - most recent Windows patches were applied $most_recent_hotfix days ago."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return						#break out of subroutine
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine state of Windows patching.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
}								#end of function



function Get-Disk-SMART-Health {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Disk-SMART-Health function" }
   #
   # HINT: virtual machines will have virtual disks that do not provide SMART metrics
   # HINT: physical machines using hardware RAID controllers will not expose SMART metrics to MSStorageDriver class.  It is assumed you will check for hardware RAID problems by querying the xClarity / iDRAC / ILO / IPMI controller.
   #
   # declare variables
   $service = "Disk SMART status"                 		#name of check defined on nagios server
   $drive_count = 0						#counter variable used to detect disks that have SMART metrics.  Virtual machines will not have physical disk.
   #
   try {
      Get-WmiObject -namespace root\wmi -class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue | Foreach $_ {
         $drive_count++						#increment counter 
         if ($verbose -eq "yes") { Write-Host "InstanceName:" $_.InstanceName "PredictFailure:" $_.PredictFailure }
         if ($_.PredictFailure -ne $True) {
            Write-Host "WARNING: disk smart error"
            $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service WARN - predictive drive failure for disk.  Disk failure is imminent.)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
            Submit-Nagios-Passive-Check
         }
      } 							#end of foreach loop
      if ($drive_count -eq 0) {					#no drives with SMART metrics detected.  Probably a virtual machine, or a physical machine using hardware RAID.
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no drives supporting SMART health metrics were found.  This may be a virtual machine, or a physical machine using hardware RAID."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
      }
      if ($drive_count -gt 0) {					#found at least 1 drive that supports SMART health metrics
         # if we get this far, none of the disks have SMART predictive errors
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no SMART errors detected)"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
}								#end of function



function Get-Disk-RAID-Health {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Disk-RAID-Health function" }
   #
   # if the local machine has a RAID controller, this will report on the status
   #
   # declare variables
   $service = "Disk RAID status"                 		#name of check defined on nagios server
   $error_count = 0 						#initialize counter
   $plugin_output = ""						#initialize variable
   #
   try {
      Get-WmiObject -class Win32_SCSIController -ErrorAction SilentlyContinue | Foreach $_ {
         $DriverName = $_.DriverName
         $Name       = $_.Name
         $Status     = $_.Status
         $plugin_output = "$plugin_output, SCSIcontroller:$Name DriverName:$DriverName Status:$Status"
         if ($verbose -eq "yes") { Write-Host "DriverName:$DriverName Name:$Name Status:$Status" }
         if ($_.Status -ne "OK") { $error_count++ }		#increment counter
      } 							#end of foreach loop
      if ($error_count -eq 0) {					#all SCSI controllers report status of OK
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - $plugin_output"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return							#break out of function
      }
      if ($error_count -gt 0) {					#at least one SCSI controllers report status other than OK
         $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - SCSI controller error.  $plugin_output"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return							#break out of function
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 					#break out of function
   }
}								#end of function



function Get-Disk-Latency-IOPS {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Disk-Latency-IOPS function" }
   #
   # declare variables
   $service        = "Disk IO" 	                		#name of check defined on nagios server
   $drive_count    = 0						#counter variable used to detect the number of disks
   $plugin_state   = 0						#0=ok 1=warn 2=critical 3=unknown
   $plugin_output  = ""						#initialize variable
   $queueLengthWarn = "no"					#initialize yes|no flag
   $latencyWarn     = "no"					#initialize yes|no flag
   #
   try {
      Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue | Foreach $_ {
         $DriveName    = $_.Name
      
         $writeMBps    = $_.DiskWriteBytesPersec /1MB ; $writeMBps = [math]::round($writeMBps,1)        #truncate to 1 decimal
         $readMBps     = $_.DiskReadBytesPersec  /1MB ; $readMBps  = [math]::round($readMBps,1)         #truncate to 1 decimal
         $writeIOPS    = $_.DiskWritesPersec
         $readIOPS     = $_.DiskReadsPersec
         $writeLatency = $_.AvgDisksecPerWrite
         $readLatency  = $_.AvgDisksecPerWrite
         $queueLength  = $_.CurrentDiskQueueLength
         #$x = "DriveName:" + $_.Name + " writeIOPS:" +  $_.DiskWritesPersec + " readIOPS:" + $_.DiskReadsPersec + " writeLatency:" + $_.AvgDisksecPerWrite + "ms readLatency:" + $_.AvgDisksecPerRead + "ms"
         $x = "DriveName:$DriveName writeIOPS:$writeIOPS readIOPS:$readIOPS writeLatency:${writeLatency}ms readLatency:${readLatency}ms queueLength:$queueLength"
         if ($verbose -eq "yes") { Write-Host $x }
         $plugin_output = "$plugin_output, $x"			#concatenate the output for each disk
         if ( ($readLatency -ge 30) -or ($writeLatency -ge 30) ) { $latencyWarn     = "yes" }		#set flag for alerting
         if ( $queueLength -gt 4 )                               { $queueLengthWarn = "yes" }		#set flag for alerting
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine disk latency.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 							#break out of function
   }
   #
   # If we get this far, all the disk latency/IOPS detail has been collected.
   #
   # Alert for high latency
   #

   if ( $latencyWarn -eq "yes") {
      $plugin_state -eq 1
      $plugin_output = "$service WARN - high disk latency.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 							#break out of function
   }
   #
   # Alert for high disk queue length
   #
   if ( $queueLengthWarn -eq "yes") {
      $plugin_state -eq 1
      $plugin_output = "$service WARN - high disk queue length.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 							#break out of function
   }
   #
   # We only get this far if everything is ok
   #
   $plugin_state -eq 0
   $plugin_output = "$service OK $plugin_output"
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
   Submit-Nagios-Passive-Check
   return 							#break out of function
}								#end of function







function Get-Windows-Failed-Logins {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Windows-Failed-Logins function" }
   #
   # declare variables
   $service = "failed logins" 						#name of check defined on nagios server
   $failed_login_count = 0						#initialize counter variable
   $threshold_warn     = 10
   $threshold_crit     = 100
   $bad_users          = @()					#define empty array

   try { 
      # Query the server for the login events. 
      $colEvents = Get-WinEvent -FilterHashtable @{logname='Security'; ID=4625 ; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Get-WinEvent powershell module.  Exiting script."
      exit 
   }
   #
   # If we get this far, the $colEvents variable contains all the Windows Event Log failed logins with ID=4625
   # Iterate through the collection of login events. 
   Foreach ($Entry in $colEvents) { 
      If ($Entry.Id -eq "4625") {
         $Username = $Entry.Properties[5].Value 
         if ($Username -notmatch '.*\$') {   #skip any machine account entries, which will end with $ character
            $failed_login_count++
            $TimeCreated = $Entry.TimeCreated 
            $Domain = $Entry.Properties[6].Value 
            $Result = "$TimeCreated,$Domain\$Username,Login Failure" 
            if ($verbose -eq "yes") { Write-Host $Result }
            $bad_users += "$Username"   #append username to array
         } 
      } 
   }
   $bad_users = $bad_users | Sort-Object | Get-Unique               #sort the array and eliminate duplicates
   if ($failed_login_count -eq 0) {
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $failed_login_count failed logins in last hour"
   }
   if ( ($failed_login_count -gt 0) -and ($failed_login_count -lt $threshold_warn) ) {
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $failed_login_count failed logins in last hour.  This is more than zero, but low enough to be acceptable.  Usernames:$bad_users"
   }
   if ($failed_login_count -ge $threshold_warn) {
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - $failed_login_count failed logins in last hour.  Possible brute force attack. Usernames:$bad_users"
   }
   if ($failed_login_count -ge $threshold_crit) {
      $plugin_state = 2 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - $failed_login_count failed logins in last hour.  Possible brute force attack. Usernames:$bad_users"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
   Submit-Nagios-Passive-Check
} 											#end of function




function Get-Windows-Defender-Antivirus-Status {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Windows-Defender-Antivirus-Status function" }
   #
   # declare variables
   $service = "Defender Antivirus" 					#name of check defined on nagios server
   $threshold_warn     = 7
   $threshold_crit     = 30
   #
   try { 
      # Query the server for the login events. 
      $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
      #
      # returned info looks like:
      # AMEngineVersion                 : 1.1.17700.4
      # AMProductVersion                : 4.18.2011.6
      # AMRunningMode                   : Normal
      # AMServiceEnabled                : True
      # AMServiceVersion                : 4.18.2011.6
      # AntispywareEnabled              : True
      # AntispywareSignatureAge         : 0
      # AntispywareSignatureLastUpdated : 12/20/2020 6:33:13 PM
      # AntispywareSignatureVersion     : 1.329.773.0
      # AntivirusEnabled                : True
      # AntivirusSignatureAge           : 0
      # AntivirusSignatureLastUpdated   : 12/20/2020 6:33:13 PM
      # AntivirusSignatureVersion       : 1.329.773.0
      # BehaviorMonitorEnabled          : True
      # ComputerID                      : C6DBDD29-ED27-4C91-8FEE-ECA4C9FDCCA1
      # ComputerState                   : 0
      # FullScanAge                     : 4294967295
      # FullScanEndTime                 :
      # FullScanStartTime               :
      # IoavProtectionEnabled           : True
      # IsTamperProtected               : False
      # IsVirtualMachine                : True
      # LastFullScanSource              : 0
      # LastQuickScanSource             : 2
      # NISEnabled                      : True
      # NISEngineVersion                : 1.1.17700.4
      # NISSignatureAge                 : 0
      # NISSignatureLastUpdated         : 12/20/2020 6:33:13 PM
      # NISSignatureVersion             : 1.329.773.0
      # OnAccessProtectionEnabled       : True
      # QuickScanAge                    : 0
      # QuickScanEndTime                : 12/21/2020 2:38:27 AM
      # QuickScanStartTime              : 12/21/2020 2:37:17 AM
      # RealTimeProtectionEnabled       : True
      # RealTimeScanDirection           : 0
      # PSComputerName                  :
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Get-MpComputerStatus powershell module.  Exiting script."
      exit 
   }
   #
   # if we get this far, the $defender variable contains all the details about the Microsoft Defender antivirus
   #
   # parse out the ComputerState property and translate from a numeric value to human readable text
   #
   if ($defender.ComputerState -eq 0)  { $ComputerState = "CLEAN"                    }
   if ($defender.ComputerState -eq 1)  { $ComputerState = "PENDING_FULL_SCAN"        }
   if ($defender.ComputerState -eq 2)  { $ComputerState = "PENDING_REBOOT"           }
   if ($defender.ComputerState -eq 4)  { $ComputerState = "PENDING_MANUAL_STEPS"     }
   if ($defender.ComputerState -eq 8)  { $ComputerState = "PENDING_OFFLINE_SCAN"     }
   if ($defender.ComputerState -eq 16) { $ComputerState = "PENDING_CRITICAL_FAILURE" }
   #
   # collect all the common data in a single variable for ease of output
   $plugin_output = "ComputerState:" + $ComputerState + " DefenderEnabled:" + $defender.AntivirusEnabled + " LastSignatureUpdate:" + $defender.AntivirusSignatureAge  + "days LastQuickScan:" + $defender.QuickScanAge + "days LastFullScan:" + $defender.FullScanAge + "days"
   #
   # 
   if ( ($defender.AntivirusEnabled -eq "True") -and ($defender.ComputerState -eq 0) -and ($defender.LastSignatureUpdate -lt $threshold_warn) -and ($defender.LastQuickScan -lt $threshold_warn) ) {
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($defender.AntivirusEnabled -ne "True") {
      $plugin_state = 2 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Defender antivirus not Enabled.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($defender.ComputerState -ne 0) {							#0=CLEAN 1=PENDING_FULL_SCAN 2=PENDING_REBOOT
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Defender ComputerState needs attention.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($defender.LastSignatureUpdate -ge $threshold_crit) {
      $plugin_state = 2 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Defender LastSignatureUpdate is more than $threshold_warn days old.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ($defender.LastSignatureUpdate -ge $threshold_warn) {
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Defender LastSignatureUpdate is more than $threshold_warn days old.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
} 											#end of function





function Get-Windows-Firewall-Status {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Windows-Firewall-Status function" }
   #
   # declare variables
   $service             = "firewall" 				#name of check defined on nagios server
   $zone_disabled_count = 0 					#initialize counter variable
   $plugin_output       = ""					#initialize variable
   #
   try { 
      # Query the server for the login events. 
      $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name,Enabled
      #
      # returned info looks like:
      # Name    Enabled
      # ----    -------
      # Domain     True
      # Private    True
      # Public     True
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Get-NetFirewallProfile powershell module.  Exiting script."
      exit 
   }
   #
   # if we get this far, the $firewall variable contains all the details about the different firewall zones and their enabled/disabled statusMicrosoft Defender antivirus
   #
   foreach ($zone in $firewall) {
      if ($zone.Enabled -ne $True) { $zone_disabled_count++ }			#increment counter 
      $plugin_output = "$plugin_output, Zone:" + $zone.Name + " Enabled:" + $zone.Enabled  #append each firewall zone status to a string
   }
   # 
   if ( $zone_disabled_count -eq 0 ) {
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   if ( $zone_disabled_count -gt 0 ) {
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - $zone_disabled_count firewall zones are disabled.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
} 											#end of function









function Get-TSM-Client-Backup-Age {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-TSM-Client-Backup-Age function" }
   #
   # declare variables
   $service = "$processToCheck"   						#name of check defined on nagios server
   #
   $fileToCheck = "C:\Program Files\Tivoli\TSM\baclient\dsmcad.exe"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { return }				#break out of function if file does not exist
   if (Test-Path $fileToCheck -PathType leaf) {						#check to see if the file exists
      $processToCheck = "dsmcad.exe"							#
      if (Get-Process $processToCheck) {						#if the file exists, confirm process is running
         if ($verbose -eq "yes") {Write-Host "$processToCheck is running" }
         $plugin_state = 0 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - process $processToCheck is running"
      } else {
         if ($verbose -eq "yes") {Write-Host "WARN: $processToCheck is NOT running" }
         $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - process $processtoCheck is NOT running.  IBM TSM / Spectrum Protect client is installed but not running."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return 									#break out of function
      }
   }
   #
   # At this point, we know the TSM client is installed and the dsmcad.exe process is running.
   # Now let's confirm the backup is less than 24 hours old.
   #
   $fileToCheck = "C:\Program Files\Tivoli\TSM\log\dsmsched.log" 			#this is the default location of the backup logfile
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { 
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - process $processtoCheck is running, but the $fileToCheck backup logfile cannot be found."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 										#break out of function
   }
   $x = Get-ChildItem $fileToCheck
   $age_in_hours = (New-TimeSpan -Start (Get-Date $x.LastWriteTime) -End (Get-Date)).TotalHours  #do some math to figure out number of hours between now and license expiration date
   $age_in_hours = [math]::round($age_in_hours,0)   	                        #truncate to 0 decimal places, nearest hour is close enough
   if ( $age_in_hours > 28 ) { 								#last backup time was more than 28 hours ago
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - last backup was $age_in_hours hours ago."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return 										#break out of function
   }	
} 											#end of function



# xxxx - to be added - confirm email notification is enabled
# Future enhancement: Veeam BR 9.5 does not have a method to globally enable email notifications from powershell.  One workaround is New-VBRNotificationOptions on a job-by-job basis.
# https://forums.veeam.com/powershell-f26/enable-disable-global-e-mail-notifications-setting-t42726.html
function Get-Veeam-Health {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Veeam-Health function" }
   #
   # declare variables
   $service       = "Veeam health"
   #
   # Confirm the Veeam.Backup.Manager process is running
   #
   $fileToCheck = "C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Manager.exe"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { return }				#break out of function if file does not exist
   if (Test-Path $fileToCheck -PathType leaf) {						#check to see if the file exists
      $processToCheck = "Veeam.Backup.Manager"						#notice the process name does not have an .exe extension
      if (Get-Process $processToCheck) {						#if the file exists, confirm process is running
         if ($verbose -eq "yes") {Write-Host "$processToCheck is running" }
      } else {
         if ($verbose -eq "yes") {Write-Host "WARN: $processToCheck is NOT running" }
         $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - process $processtoCheck is NOT running"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      }
   }
   #
   # At this point, we have confirmed the Veeam.Backup.Manager process is running
   # This check only needs to be run on an hourly basis, so check to see if a dummy file containing the output exists.
   $dummyFile = "$env:TEMP\nagios.veeam.backup.check.txt"
   #
   # Delete the file if it is more than 60 minutes old
   if (Test-Path $dummyFile -PathType leaf) { 
      if ($verbose -eq "yes") { Write-Host "   checking age of flag file $dummyFile" }
      $lastWrite = (get-item $dummyFile).LastWriteTime
      $age_in_minutes = (New-TimeSpan -Start (Get-Date $lastWrite) -End (Get-Date)).TotalMinutes  #do some math to figure file age in minutes
      if ($age_in_minutes -gt 60) {
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
      Submit-Nagios-Passive-Check
      return										#break out of function
   }				
   #
   # If we get this far, no dummy text file exists with the previous check output, so perform the check.
   #
   # Now confirm the VeeamPSSnapin PowerShell module is available
   # We only do this section once per hour because adding a plugin is time consuming.
   #
   try {
      if ( (Get-PSSnapin -Name VeeamPSSnapin -ErrorAction SilentlyContinue) -eq $null ) { #confirm the Veeam powershell plugin is loaded
         Write-Host "Adding VeeamPSSnapin PowerShell snap in"
         try {
            Add-PSSnapin VeeamPSSnapin
         }
         catch {
            Write-Host "ERROR: Could not add VeeamPSSnapin PowerShell snap in"
            $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "UNKNOWN - could not add VeeamPSSnapin PowerShell snap-in to check status of Veeam backup jobs"
            Submit-Nagios-Passive-Check
            return									#break out of function
         }
      }		
   }
   catch {
      $StatusCode = $_.Exception.Response.StatusCode.value__
   }
   #
   # At this point, we have confirmed the Veeam process is running and the VeeamPSSnapin PowerShell module is loaded
   # Now we will connect to the Veeam server
   #
   try {
      Connect-VBRServer 								#connect to the Veeam server running on local machine
   }
   catch {
      Write-Host "ERROR: Could not connect to Veeam server with Connect-VBRServer PowerShell snap in"
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not connect to Veeam server with Connect-VBRServer PowerShell snap in"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   #
   # At this point, we have a connection to the Veeam server.
   # Now we will check the license status.  
   # The output from a perpetual license will look like the following.  Please note the lack of an ExpirationDate.
   #   Get-VBRInstalledLicense
   #   Status                              : Valid
   #   ExpirationDate                      :
   #   Type                                : Perpetual
   #   Edition                             : Enterprise
   #   LicensedTo                          : BigCorp Inc
   #   SocketLicenseSummary                : {Veeam.Backup.PowerShell.Infos.VBRSocketLicenseSummary}
   #   InstanceLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRInstanceLicenseSummary
   #   CapacityLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRCapacityLicenseSummary
   #   SupportId                           :
   #   SupportExpirationDate               : 2025-09-23 12:00:00 AM
   #   AutoUpdateEnabled                   : False
   #   FreeAgentInstanceConsumptionEnabled : False
   #   CloudConnect                        : Disabled
   #
   # The output from an NFR license will look like the following.  Please note the lack of a SupportExpirationDate.
   #   Status                              : Valid
   #   ExpirationDate                      : 4/7/2021 12:00:00 AM
   #   Type                                : NFR
   #   Edition                             : EnterprisePlus
   #   LicensedTo                          : BigCorp Inc
   #   SocketLicenseSummary                : {Veeam.Backup.PowerShell.Infos.VBRSocketLicenseSummary}
   #   InstanceLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRInstanceLicenseSummary
   #   CapacityLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRCapacityLicenseSummary
   #   SupportId                           :
   #   SupportExpirationDate               :
   #   AutoUpdateEnabled                   : False
   #   FreeAgentInstanceConsumptionEnabled : True
   #   CloudConnect                        : Disabled
   #
   $veeam = @{}										#create an empty hash
   $x = Get-VBRInstalledLicense
   $veeam.Add("LicenseStatus",$x.Status)						#add license status to hash (HINT: do not surround $x.Status with quotes)
   $veeam.Add("LicenseType",$x.Type)							#add license type (Rental, Perpetual, Subscription, Evaluation, Free, Empty, NFR)
   #
   # NFR licenses do not have vendor support, so they do not have a SupportExpirationDate, so put in a dummy value of 0
   if ($x.SupportExpirationDate -eq $Null) { 
      $veeam.Add("SupportExpirationDate",0) 
      $veeam.Add("DaysToSupportExpirationDate",0) 
   }
   else { 
      $veeam.Add("SupportExpirationDate",$x.SupportExpirationDate) 					#add license expiration date to hash
      $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.SupportExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
      $x = [math]::round($x,0)   								#truncate to 0 decimal places, nearest day is close enough
      $veeam.Add("DaysToSupportExpirationDate",$x)                                                #add days until license expiry to hash
   }
   #
   # Perpetual licenses do not have an expiration date, so put in a dummy value of 99999
   if ($x.LicenseExpirationDate -eq $Null) { 
      $veeam.Add("LicenseExpirationDate",99999) 
      $veeam.Add("DaysToLicenseExpirationDate",99999) 
   }
   else { 
      $veeam.Add("LicenseExpirationDate",$x.ExpirationDate) 					#add license expiration date to hash
      $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.ExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
      $x = [math]::round($x,0)   								#truncate to 0 decimal places, nearest day is close enough
      $veeam.Add("DaysToExpirationDate",$x)                                                #add days until license expiry to hash
   }
   #
   #
   # Get the version of Veeam
   $filename = "C:\Program Files\Veeam\Backup and Replication\Console\veeam.backup.shell.exe"
   if (Test-Path $filename -PathType leaf) { 
      $x = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$filename").FileVersion
      $veeam.Add("Version",$x)                                                #add veeam version and patch level to hash
   }
   #
   #
   # Check the size of the Veeam backup repositories to ensure they have at least 20% free space
   #
   $threshold_warn = 80									#warn     if repository space utilization is more than 80%
   $threshold_crit = 90									#critical if repository space utilization is more than 90%
   $repo_usage = ""									#temporary variable to concatenate all the repositories together
   $veeam.Add("RepoUsageWarn","")							#initialize hash value that will be used to send alert
   $veeam.Add("RepoUsageCrit","")							#initialize hash value that will be used to send alert
   $repolist = Get-VBRBackupRepository | Where-Object {$_.Type -ne "SanSnapShotOnly"}	#skip SanSnapshotOnly repositories because they always return -1 for Info.CachedTotalSpace
   foreach ($repo in $repolist) {
      $repo_name     = $repo.Name
      $repo_type     = $repo.Type 							#WinLocal, SanSnapshotOnly
      $repo_total_gb = $repo.Info.CachedTotalSpace / 1GB				#this value is cached by Veeam and only updated occasionally, so may be out of date
      $repo_total_gb = [math]::round($repo_total_gb,0)   				#truncate to 0 decimal places, nearest day is close enough
      $repo_free_gb  = $repo.Info.CachedFreeSpace  / 1GB				#this value is cached by Veeam and only updated occasionally, so may be out of date
      $repo_free_gb  = [math]::round($repo_free_gb,0)   				#truncate to 0 decimal places, nearest day is close enough
      $repo_used_gb  = $repo_total_gb - $repo_free_gb 					#do some math to figure out GB of used space in repository
      $repo_free_pct = $repo_free_gb / $repo_total_gb * 100				#do some math to figure out percentage of free space in repository	
      $repo_free_pct = [math]::round($repo_free_pct,0)   				#truncate to 0 decimal places, nearest day is close enough
      $repo_used_pct = 100 - $repo_free_pct 						#do some math to figure out percentage of used space in repository
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -ge $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "yes" } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -lt $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "no"  ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      $x = "RepoName:" + $repo_name + " RepoUsage:" + $repo_used_gb + "/" +  $repo_total_gb + "GB(" + $repo_used_pct + "%)"
      $repo_usage = "$repo_usage, $x"						#concatenate all the repository details into a single string variable
   }
   $veeam.Add("RepoUsage",$repo_usage)							#add all repository usage details to a single hash element
   if ($verbose -eq "yes") { Write-Host $repo_usage }
   #
   #
   # Check the success/warning/failure status of the backup jobs
   # Get a list of the backup jobs
   #
   $success_count = 0									#initialize variable
   $failed_count = 0									#initialize variable
   $unknown_count = 0									#initialize variable
   $j = Get-VBRJob
   ForEach ($job in $j) {
      $s = $job.FindLastSession()
      $JobName = $s.JobName
      $Result  = $s.Result  								#Success, Failed
      $State   = $s.State 								#Stopped, Starting, Stopping, Working, Pausing, Resuming, Postprocessing
      if ($verbose -eq "yes") {Write-Host "   JobName:$JobName Result:$Result State:$State" }
      if ( ($Result -eq "Success") -or ($Result -eq "Warning") ) {			#Job result of Warning means it succeeded, but with warnings like slowdown or low disk space
         $success_count++								#increment counter
         $veeam_backups_success = "$veeam_backups_success $JobName"               	#build a string containing all the backup jobs that have Success/Warning status
         #if ($verbose -eq "yes") { Write-Host "   Found successful job $JobName" }
      } elseif ($Result -eq "Failed") {
         $failed_count++								#increment counter
         $veeam_backups_failed = "$veeam_backups_failed $JobName"               	#build a string containing all the backup jobs that have Failed status
         #if ($verbose -eq "yes") { Write-Host "   Found failed job $JobName" }
      } elseif ($Result -eq "None") {
         if ($verbose -eq "yes") { Write-Host "   Skipping job $JobName because it is in progress" }
         #Assume this in-progress job will succeed.  This avoids having a total job count of zero if the only job on the entire system is currently running.
         $success_count++								#increment counter
      }
   }
   # put all the job details in the $veeam hash so we have a single place with all the data
   $veeam.Add("BackupSuccessCount"    , $success_count)  
   $veeam.Add("BackupFailedCount"     , $failed_count)  
   $veeam.Add("BackupUnknownCount"    , $unknown_count)  
   $veeam.Add("BackupSuccessJobNames" , $veeam_backups_success)  
   $veeam.Add("BackupFailedJobNames"  , $veeam_backups_failed)  
   $veeam.Add("BackupUnknownJobNames" , $veeam_backups_unknown)  
   #
   Disconnect-VBRServer 								#disconnect from the Veeam server running on local machine
   #
   # Figure out if there are any problems to be reported
   # Put all the output into a single variable
   $plugin_output = "Version:" + $veeam.Version + " LicenseType:" + $veeam.LicenseType + " LicenseStatus:" + $veeam.LicenseStatus + " LicenseExpiration:" + $veeam.DaysToLicenseExpirationDate + "days SupportExpiration:" + $veeam.DaysToSupportExpirationDate + "days Successful_backups:" + $veeam.BackupSuccessCount + " Failed_backups:" + $veeam.BackupFailedCount + $veeam.RepoUsage
   #
   # This is the "everything is all good" message format
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -gt 30) -and ($veeam.BackupSuccessCount -gt 0) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 0			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license is not Valid
   }
   #
   # There are multiple versions of the "something is wrong" message format, depending on exactly what the problem is
   #
   #
   # send alert if there are zero scheduled backups
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -gt 30) -and ($veeam.BackupSuccessCount -eq 0) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - There are no scheduled backup jobs.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license is not Valid
   }
   #
   # send alert if license status is anything other than Valid
   #
   if ( ($veeam.LicenseStatus -ne "Valid") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam license is not valid.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license is not Valid
   }
   #
   # send alert if license is about to expire
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -le 30) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license will expire soon, but all backup jobs are good
   }
   #
   # send alert if vendor support is about to expire (for license types that include support)
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoSupportExpirationDate -le 30) -and ( ($veeam.LicenseType -eq "Perpetual") -or ($veeam.LicenseType -eq "Rental") -or ($veeam.LicenseType -eq "Subscription")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: Support will expire in " + $veeam.DaysToSupportExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license will expire soon, but all backup jobs are good
   }
   #
   # send alert if there are failed / unknown backup jobs and nearly full backup repository
   #
   if ( (($veeam.BackupFailedCount -gt 0) -or ($veeam.BackupUnknownCount -gt 0)) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are failed/unknown Veeam backup jobs and nearly full backup repositories.  Failed job names are:" + $veeam.BackupFailedJobNames + " Unknown result job names are:" + $veeam.BackupUnknownJobNames + " , $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   #
   # send alert if there are failed backup jobs
   #
   if ( ($veeam.BackupFailedCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $x = $veeam.BackupFailedJobNames
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs.  Failed job names are:" + $veeam.BackupFailedJobNames + " $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   #
   # send alert if there are backup jobs with a completion status of unknown
   #
   if ( ($veeam.BackupUnknownCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are Veeam backup jobs with unknown results.  Job names are:" + $veeam.BackupUnknownJobNames + " , $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }  
   #
   # send alert if there backup repositories that are nearly full
   # 
   if ( ($veeam.RepoUsageCrit -eq "yes") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam backup repository nearly full. " + $veeam.RepoUsage + ", $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if ( ($veeam.RepoUsageWarn -eq "yes") ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN: Veeam backup repository nearly full. " + $veeam.RepoUsage + ", $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
} 											#end of function




function Get-Veeam-365-Health {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Veeam-365-Health function" }
   #
   # declare variables
   $service       = "Veeam 365 health"
   #
   # Confirm the Veeam.Archiver.Servicer process is running
   #
   $fileToCheck = "C:\Program Files\Veeam\Backup365\Veeam.Archiver.Service.exe"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { return }				#break out of function if file does not exist
   if (Test-Path $fileToCheck -PathType leaf) {						#check to see if the file exists
      $processToCheck = "Veeam.Archiver.Service"					#notice the process name does not have an .exe extension
      if (Get-Process $processToCheck) {						#if the file exists, confirm process is running
         if ($verbose -eq "yes") {Write-Host "$processToCheck is running" }
      } else {
         if ($verbose -eq "yes") {Write-Host "WARN: $processToCheck is NOT running" }
         $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - process $processtoCheck is NOT running"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      }
   }
   #
   # At this point, we have confirmed the Veeam.Archiver.Service process is running
   # This check only needs to be run on an hourly basis, so check to see if a dummy file containing the output exists.
   $dummyFile = "$env:TEMP\nagios.veeam365.backup.check.txt"
   #
   # Delete the file if it is more than 60 minutes old
   if (Test-Path $dummyFile -PathType leaf) { 
      if ($verbose -eq "yes") { Write-Host "   checking age of flag file $dummyFile" }
      $lastWrite = (get-item $dummyFile).LastWriteTime
      $age_in_minutes = (New-TimeSpan -Start (Get-Date $lastWrite) -End (Get-Date)).TotalMinutes  #do some math to figure file age in minutes
      if ($age_in_minutes -gt 60) {
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
      Submit-Nagios-Passive-Check
      return										#break out of function
   }				
   #
   # If we get this far, no dummy text file exists with the previous check output, so perform the check.
   #
   # Now confirm the VeeamPSSnapin PowerShell module is available
   #
   try {
      if ( (Get-Module -Name Veeam.Archiver.PowerShell -ErrorAction SilentlyContinue) -eq $null ) { #confirm the Veeam powershell plugin is loaded
         Write-Host "Importing Veeam.Archiver.PowerShell PowerShell module"
         try {
            Import-Module Veeam.Archiver.PowerShell
         }
         catch {
            Write-Host "ERROR: Could not import Veeam.Archiver.PowerShell PowerShell module"
            $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "UNKNOWN - could not import Veeam.Archiver.PowerShell PowerShell module check status of Veeam Office 365 backup jobs"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
            Submit-Nagios-Passive-Check
            return									#break out of function
         }
      }		
   }
   catch {
      $StatusCode = $_.Exception.Response.StatusCode.value__
   }
   #
   # At this point, we have confirmed the Veeam for Office365 process is running and the Veeam.Archiver.PowerShell PowerShell module is loaded
   # Now we will connect to the Veeam server
   #
   try {
      Connect-VBOServer 								#connect to the Veeam server running on local machine
   }
   catch {
      Write-Host "ERROR: Could not connect to Veeam 365 server with Connect-VBOServer PowerShell snap in"
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not connect to Veeam server with Connect-VBRServer PowerShell snap in"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   #
   # At this point, we have a connection to the Veeam server.
   # Now we will check the license status.
   #
   $veeam = @{}										#create an empty hash
   $x = Get-VBOLicense
   $veeam.Add("LicenseStatus",$x.Status)						#add license status to hash (HINT: do not surround $x.Status with quotes)
   $veeam.Add("LicenseExpirationDate",$x.ExpirationDate)				#add license expiration date to hash
   $veeam.Add("SupportExpirationDate",$x.SupportExpirationDate)				#add support expiration date to hash
   #
   # do some math to figure out days until license expiration
   #
   $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.LicenseExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
   $x = [math]::round($x,0)   				                                #truncate to 0 decimal places, nearest day is close enough
   $veeam.Add("DaysToLicenseExpirationDate",$x)                                         #add days until license expiry to hash
   #
   # do some math to figure out days until support expiration (typically the same day as license expiration)
   #
   $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.SupportExpirationDate)).TotalDays  #do some math to figure out number of days between now and support expiration date
   $x = [math]::round($x,0)   				                                #truncate to 0 decimal places, nearest day is close enough
   $veeam.Add("DaysToSupportExpirationDate",$x)                                         #add days until license expiry to hash
   #
   #
   # Confirm Veeam email reporting is enabled
   #
   $x = Get-VBOEmailSettings
   $veeam.Add("EnableNotification",$x.EnableNotification)				#add license status to hash (HINT: do not surround $x.Status with quotes)
   #
   #
   #
   #
   # Check the size of the Veeam backup repositories to ensure they have at least 20% free space
   #
   $threshold_warn = 80									#warn     if repository space utilization is more than 80%
   $threshold_crit = 90									#critical if repository space utilization is more than 90%
   $repo_usage = ""									#temporary variable to concatenate all the repositories together
   $veeam.Add("RepoUsageWarn","")							#initialize hash value that will be used to send alert
   $veeam.Add("RepoUsageCrit","")							#initialize hash value that will be used to send alert
   $repolist = Get-VBORepository
   foreach ($repo in $repolist) {
      $repo_name     = $repo.Name
      $repo_total_gb = $repo.Capacity /1GB						#
      $repo_total_gb = [math]::round($repo_total_gb,0)   	                        #truncate to 0 decimal places, nearest GB is close enough
      $repo_free_gb  = $repo.FreeSpace /1GB							#
      $repo_free_gb  = [math]::round($repo_free_gb,0)   	                        #truncate to 0 decimal places, nearest GB is close enough
      $repo_used_gb  = $repo_total_gb - $repo_free_gb 					#do some math to figure out GB of used space in repository
      $repo_free_pct = $repo_free_gb / $repo_total_gb * 100				#do some math to figure out percentage of free space in repository	
      $repo_free_pct = [math]::round($repo_free_pct,0)   	                        #truncate to 0 decimal places, nearest integer is close enough
      $repo_used_pct = 100 - $repo_free_pct 						#do some math to figure out percentage of used space in repository
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -ge $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "yes" } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -lt $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "no"  ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      $x = "RepoName:" + $repo_name + " RepoUsage:" + $repo_used_gb + "/" +  $repo_total_gb + "GB(" + $repo_used_pct + "%)"
      $repo_usage = "$repo_usage, $x"						#concatenate all the repository details into a single string variable
   }
   $veeam.Add("RepoUsage",$repo_usage)							#add all repository usage details to a single hash element
   if ($verbose -eq "yes") { Write-Host $repo_usage }
   #
   # Check the success/warning/failure status of the backup jobs
   #
   # Get a list of the backup jobs
   #
   $success_count = 0
   $failed_count = 0
   $unknown_count = 0
   $job = Get-VBOJob
   ForEach ($j in $job.Name) {
      $jobsession = Get-VBOJobSession -Job $job -last                                  #get the details of the most recent run of each backup job
      $JobName = $jobsession.JobName
      $Result  = $jobsession.Status
      if ($verbose -eq "yes") {Write-Host "   JobName:$JobName Status:$Result " }
      if ( ($Result -eq "Success") -or ($Result -eq "Warning") ) {                      #Job result of Warning means it succeeded, but with warnings like slowdown or low disk space
         $success_count++                                                               #increment counter
         $veeam_backups_success = "$veeam_backups_success $JobName"                     #build a string containing all the backup jobs that have Success/Warning status
         if ($verbose -eq "yes") { Write-Host "Found successful job $JobName" }
      } elseif ($Result -eq "Failed") {
         $failed_count++                                                                #increment counter
         $veeam_backups_failed = "$veeam_backups_failed $JobName"                       #build a string containing all the backup jobs that have Failed status
         if ($verbose -eq "yes") { Write-Host "Failed:$veeam_backups_failed" } 
      } else {
         $unknown_count++                                                               #increment counter
         $veeam_backups_unknown = "$veeam_backups_unknown $JobName"                    #build a string containing all the backup jobs that we could not determine the status of
         if ($verbose -eq "yes") { Write-Host "Unknown:$veeam_backups_unknown" }
      }
   }
   # put all the job details in the $veeam hash so we have a single place with all the data
   $veeam.Add("BackupSuccessCount"    , $success_count)  
   $veeam.Add("BackupFailedCount"     , $failed_count)  
   $veeam.Add("BackupUnknownCount"    , $unknown_count)  
   $veeam.Add("BackupSuccessJobNames" , $veeam_backups_success)  
   $veeam.Add("BackupFailedJobNames"  , $veeam_backups_failed)  
   $veeam.Add("BackupUnknownJobNames" , $veeam_backups_unknown)  
   #
   Disconnect-VBOServer 
   #
   # Figure out if there are any problems to be reported
   # get all the common info into a single variable
   $plugin_output = "LicenseStatus:" + $veeam.LicenseStatus + " LicenseExpiration:" + $veeam.DaysToLicenseExpirationDate + "days SupportExpiration:" + $veeam.DaysToSupportExpirationDate + "days Successful_backups:" + $veeam.BackupSuccessCount + " Failed_backups:" + $veeam.BackupFailedCount + " Unknown_backups:" + $veeam.BackupUnknownCount + $veeam.RepoUsage
   #
   # This is the "everything is all good" message format
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaysToLicenseExpirationDate -gt 30) -and ($veeam.EnableNotification -eq $True) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 0			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - All backups are successful.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return										#break out of function if everything is good
   }
   #
   # There are multiple versions of the "something is wrong" message format, depending on exactly what the problem is
   #
   if ( ($veeam.LicenseStatus -ne "Valid") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam license is not valid.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license is not Valid
   }
   if ( ($veeam.EnableNotification -ne "True") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam 365 email notifications are not enabled.  Please enable email notifications by clicking General Options, Notifications, Enable email notifications. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return 										#break out of function if the email notifications are disabled
   }
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -le 30) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license will expire soon, but all backup jobs are good
   }
   if ( ($veeam.BackupFailedCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs and nearly full backup repositories.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if (  ($veeam.BackupUnknownCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are unknown Veeam backup jobs and nearly full backup repositories.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   

   if ( ($veeam.BackupFailedCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $x = $veeam.BackupFailedJobNames
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs.  Failed job names are: $x, $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if ( ($veeam.BackupUnknownCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are Veeam backup jobs with unknown results.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if ( $veeam.RepoUsageCrit -eq "yes" ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam backup repository nearly full. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if ( $veeam.RepoUsageWarn -eq "yes" ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN: Veeam backup repository nearly full. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if there were and Failed or Unknown backup jobs
   }   
   if ( $veeam.DaystoLicenseExpirationDate -le 30 )  {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license will expire soon, but all backup jobs are good
   }
   if ( $veeam.DaystoSupportExpirationDate -le 30 )  {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: Support will expire in " + $veeam.DaysToSupportExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      return                   								#break out of function if the Veeam license will expire soon, but all backup jobs are good
   }
}



function Get-HyperV-Replica-Status {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-HyperV-Replica-Status function" }
   #
   # declare variables
   $service       = "Hyper-V Replica"
   #
   # Confirm the Hyper-V windows feature is installed
   #
   try {
      $hyperv = Get-WindowsFeature -Name Hyper-V
      if ($hyperv.InstallState -eq "Installed") {
         if ($verbose -eq "yes") { Write-Host "Hyper-V role is installed" }
      } 
      else {
         if ($verbose -eq "yes") { Write-Host "Hyper-V role is not installed on this machine, skipping check" }
         $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "UNKNOWN - Hyper-V role is not installed on this machine"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      }
   }
   catch {
      Write-Host "ERROR: Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   }
   #
   # If we get this far, the Hyper-V role is installed.
   #
   # Get a list of VM's who are primary replicas whose is not Normal. 
   try { 
      $UnhealthyVMs = Measure-VMReplication -ErrorAction Stop | Where-Object {$_.ReplicationMode -eq "Primary" -and $_.ReplicationHealth -ne "Normal"} 
   } 
   catch { 
      Write-Host -NoNewline "Hyper-V Replica Status is Unknown.|" ; Write-Host "" ; exit $returnStateUnknown 
   } 
   if ($UnhealthyVMs) { 
      # If we have VMs then we need to determine if we need to return critical or warning. 
      $CriticalVMs = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Critical" 
      $WarningVMs  = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Warning" 
      if ($CriticalVMs) { 
         $plugin_state = 2 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service CRITICAL - Hyper-V Replica Health is critical for $($CriticalVMs.Name)."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      } 
      elseif ($WarningVMs) { 
         $plugin_state = 1			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - Hyper-V Replica Health is WARN for $($WarningVMs.Name)."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      } 
      else { 
         $plugin_state = 3			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Hyper-V Replica Health is UNKNOWN"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         Submit-Nagios-Passive-Check
         return										#break out of function
      } 
   } 
   else { 
      # No Replication Problems Found 
      $plugin_state = 3			 						#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - Hyper-V Replica Health is normal"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return										#break out of function
   } 
}												#end of function



function Get-Console-User {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Console-User function" }
   #
   # This function parses the output of the "query user" command to show the currently logged in users.
   # We are interested in the SESSIONNAME called "console", which shows the user currently logged in at the machine console.
   # This is important for certain ill-behaved applications that require a local user to be logged in at the console.
   #Sample output:
   # PS C:\> query user
   #  USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME
   # >janedoe               console             1  Active      none   4/2/2022 5:19 PM
   #  administrator         rdp-tcp#1           2  Active          .  4/12/2022 11:26 AM
   #  john.smith                                3  Disc     11+04:12  2022-03-31 5:09 PM
   #
   # declare variables
   $service = "ConsoleLogon"                    #name of check defined on nagios server
   #
   try {
      $ConsoleUser = query user
   }
   catch {
      Write-Host "Access denied.  Please check your permissions."
      $plugin_state = 3                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not run query user command.  Please check permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return                                    #break out of function
   }
   #
   # We only get this far if $ConsoleUser contains data
   #
   $ConsoleUser = $ConsoleUser -match 'console'     #parse out the line containing the console session
   $ConsoleUser = $ConsoleUser -replace '^>'        #remove the > character at the beginning of the line
   $ConsoleUser = $ConsoleUser -replace ' +.*'      #remove everything after the username
   if (!$ConsoleUser) {$ConsoleUser = "none"}       #if $ConsoleUser is empty or undefined at this point, put in a value of "none" to indicate no one is logged in
   #
   # At this point, we have the username logged in at the console.
   # Now let's decide if this is the user that *should* be logged in, which is somewhat site-dependent.
   # The acceptable values for the $RequiredUser variable are any|none|SomeUserName
   # $RequiredUser=any     means return OK if any user is logged in at the console
   # $RequiredUser=none    means return OK if no  user is logged in at the console
   # $RequiredUser=janedoe means return OK if only the janedoe user is logged in at the console
   # Please uncomment the appropriate $RequiredUser line for your specific environment
   #
   #$RequiredUser = "janedoe"                          #return ok only if janedoe is logged in
   #$RequiredUser = "any"                              #return ok if any user is logged in (comment out this line if previous line is being used)
   $RequiredUser = "none"                              #return ok if no   user is logged in (comment out this line if previous line is being used)
   if ($verbose -eq "yes") { Write-Host "   ConsoleUser=$ConsoleUser RequiredUser=$RequiredUser" }
   #
   # submit nagios passive check results
   #
   if ($RequiredUser -eq "any" -and $ConsoleUser -eq "none") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - no user logged on at local console.  There should be a user logon at the console."
   }
   if ($RequiredUser -eq "any" -and $ConsoleUser -notmatch "none" -and $ConsoleUser -match "\w") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $ConsoleUser user is logged in at the console."
   }
   if ($RequiredUser -eq "none" -and $ConsoleUser -eq "none") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - no user logged on at local console.  There should not be a user logged on at the console."
   }
   if ($RequiredUser -eq "none" -and $ConsoleUser -notmatch "none" -and $ConsoleUser -match "\w") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $ConsoleUser user is logged in at the console.  There should not be anyone logged in at the console.  Please logout the user $ConsoleUser."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $ConsoleUser -ne "none" -and $RequiredUser -ne $ConsoleUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in at the console, but the $ConsoleUser user is logged in instead."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $ConsoleUser -eq "none" -and $RequiredUser -ne $ConsoleUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in at the console, but there is no user logged into the console.  Please logon to the console as $RequiredUser"
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RequiredUser -eq $ConsoleUser) {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $RequiredUser is logged in at the console."
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   Submit-Nagios-Passive-Check
}




function Get-Scheduled-Task-001 {
   #
   if ($verbose -eq "yes") { Write-Host "Running Get-Scheduled-Task-001" }
   #
   # The Get-ScheduledTaskInfo powershell cmdlet should exist on Windows 2012 and later.
   # This function looks at the Scheduled Task and alerts if the most recent execution was unsuccessful, or the task has not run for XXX hours
   # This function name is Get-Scheduled-Task-###, with the intent that there may be a -001, -002, -003, etc if you have multiple tasks to check
   #Sample output:
   # PS C:\> query user
   #  USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME
   # >janedoe               console             1  Active      none   4/2/2022 5:19 PM
   #  administrator         rdp-tcp#1           2  Active          .  4/12/2022 11:26 AM
   #  john.smith                                3  Disc     11+04:12  2022-03-31 5:09 PM
   #
   # declare variables
   $TaskName = "GoogleUpdateTaskMachineCore"      #name of the scheduled task, get with schtasks.exe on monitored host
   #$TaskName = "nagios_passive_check"            #name of the scheduled task, get with schtasks.exe on monitored host
   $service = "Task $TaskName"                    #name of check defined on nagios server
   #
   try {
      $TaskInfo = get-scheduledtaskinfo -TaskName $TaskName
   }
   catch {
      Write-Host "Access denied.  Please check your permissions."
      $plugin_state = 3                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not find scheduled task $TaskName.  Please confirm the scheduled task name is correct, and check permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      Submit-Nagios-Passive-Check
      return                                    #break out of function
   }
   #
   # We only get this far if $TaskInfo contains data
   # The $TaskInfo variable should contain data similar to the following:
   # LastRunTime        : 4/12/2022 4:47:47 PM    <--- should be within the last ??? minutes
   # LastTaskResult     : 0                       <--- 0=success, >0 can mean many things, currently running, failed, etc
   # NextRunTime        : 4/12/2022 4:52:52 PM
   # NumberOfMissedRuns : 0
   # TaskName           : nagios_passive_check
   # TaskPath           :
   # PSComputerName     :
   #
   #
   # figure out how long ago the task was run
   $age_in_hours = (New-TimeSpan -Start (Get-Date $TaskInfo.LastRunTime) -End (Get-Date)).TotalHours  #do some math to figure out number of hours between now and license expiration date
   $age_in_hours = [math]::round($age_in_hours,0)   	                        #truncate to 0 decimal places, nearest hour is close enough
   $LastTaskResult = $TaskInfo.LastTaskResult
   $LastRunTime    = $TaskInfo.LastRunTime
   #
   if ($verbose -eq "yes") { Write-Host "   TaskName=$TaskName, LastRunTime=$age_in_hours hours ago, LastTaskResult=$LastTaskResult" }
   #
   # submit nagios passive check results
   #
   #
   if ( $age_in_hours -le '24' -and $LastTaskResult -eq '0') { 	#task is ok
      $plugin_state = 0						 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - Scheduled task $TaskName ran successfully at $LastRunTime"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      Submit-Nagios-Passive-Check
      return 										#break out of function
   }	
   if ( $age_in_hours -gt '24' ) { 						#last task execution time was more than 24 hours ago
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Scheduled task $TaskName last execution time was was $age_in_hours hours ago at $LastRunTime."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      Submit-Nagios-Passive-Check
      return 										#break out of function
   }	
   # Potential bug: what if the task is currently running?  The return code will be >0 for the brief period the task is running.
   if ( $LastTaskResult -gt '0' ) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Scheduled task $TaskName failed, please check status of this scheduled task"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      Submit-Nagios-Passive-Check
      return 										#break out of function
   }
}



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
#Get-Processor-Utilization 	#get this via SNMP active check instead of passively
#Get-Paging-Utilization 	#get this via SNMP active check instead of passively
#Get-Disk-Space-Utilization 	#get this via SNMP active check instead of passively
#Get-Uptime  			#get this via SNMP active check instead of passively
Get-LastWindowsUpdate
Get-Disk-SMART-Health
Get-Disk-RAID-Health
Get-Disk-Latency-IOPS
Get-Windows-Failed-Logins
Get-Windows-Defender-Antivirus-Status
Get-Windows-Firewall-Status
#Get-TSM-Client-Backup-Age
Get-Veeam-Health
#Get-Veeam-365-Health
#Get-HyperV-Replica-Status
Get-Console-User
Get-Scheduled-Task-001 