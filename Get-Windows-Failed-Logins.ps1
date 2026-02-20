# powershell function to perform check on local machine
# this script can be called by NCPA or executed as a passive check
# intent: find failed user logins in the past 60 minutes

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created
# 2025-09-18	njeffrey	Add NCPA compatibility

function Get-Windows-Failed-Logins {
   #
   $verbose = "no"             #yes|no flag to increase verbosity for debugging
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Windows-Failed-Logins function" }
   #
   # declare variables
   $service = "failed logins" 						#name of check defined on nagios server
   $failed_login_count = 0						#initialize counter variable
   $threshold_warn     = 10
   $threshold_crit     = 100
   $bad_users          = @()					#define empty array
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        

   try { 
      # Query the server for the login events. 
      $colEvents = Get-WinEvent -FilterHashtable @{logname='Security'; ID=4625 ; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue
   }
   catch { 
      $exit_code = $UNKNOWN
      $plugin_output = "$service UNKNOWN - insufficient permissions to run Get-WinEvent powershell module."
      #
      # print output
      #
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
         $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
         Submit-Nagios-Passive-Check   #call function to send results to nagios
      } else {
         Write-Output "$plugin_output"
         exit $exit_code
      }
      return
   }
   #
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
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service OK - $failed_login_count failed logins in last hour"
   }
   if ( ($failed_login_count -gt 0) -and ($failed_login_count -lt $threshold_warn) ) {
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service OK - $failed_login_count failed logins in last hour.  This is more than zero, but low enough to be acceptable.  Usernames:$bad_users"
   }
   if ($failed_login_count -ge $threshold_warn) {
      $exit_code = $WARN 								 #0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service WARN - $failed_login_count failed logins in last hour.  Possible brute force attack. Usernames:$bad_users"
   }
   if ($failed_login_count -ge $threshold_crit) {
      $exit_code = $CRITICAL 								 #0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service CRITICAL - $failed_login_count failed logins in last hour.  Possible brute force attack. Usernames:$bad_users"
   }
   #
   # capture nagios performance data
   #
   $perf_data = "0"  #no performance data to report for this check
   #
   # combine the common output and the $perf_data
   $plugin_output = "$common_output_data | $perf_data"
   #
   # print output
   #
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
      $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
      Submit-Nagios-Passive-Check   #call function to send results to nagios
   } else {
      Write-Output "$plugin_output"
      exit $exit_code
   }
   return                                               #break out of function
} 							#end of function
#
# call the above function
#
Get-Windows-Failed-Logins




