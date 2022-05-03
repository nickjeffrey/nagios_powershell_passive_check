function Get-Windows-Failed-Logins {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Windows-Failed-Logins function" }
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
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
} 											#end of function



