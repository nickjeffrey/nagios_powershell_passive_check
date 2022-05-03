function Get-Uptime {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Uptime function" }
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
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Submit-Nagios-Passive-Check) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ( ($uptime -gt 60) -and ($uptime -lt 1440) ) {					#system has been up for more than 1 hour, but less than 1 day, so report in hours
      $uptime = $uptime / 60
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest hour is close enough 
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime hours"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Submit-Nagios-Passive-Check) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($uptime -ge 30 ) { 								#system has been up for more than 30 minutes but less than 60 minutes, so report in minutes
      $uptime = $uptime 
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "OK - System uptime is $uptime minutes" }
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime minutes"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Submit-Nagios-Passive-Check) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($uptime -lt 30 ) {
      $uptime = $uptime 
      $uptime = [math]::round($uptime,0) 		  	                        #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "WARN - recent reboot detected.  System uptime is $uptime minutes" }
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - recent reboot detected.  System uptime is $uptime minutes"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Submit-Nagios-Passive-Check) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
} 											#end of function
