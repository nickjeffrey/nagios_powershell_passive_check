# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   Add NCPA compatibility

function Get-Uptime {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Uptime function" }
   #
   # declare variables
   $service = "uptime" 	  								#name of check defined on nagios server
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        
   #
   #
   $uptime = (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime
   $uptime_minutes = $uptime.TotalMinutes
   if ($verbose -eq "yes") { Write-Host "   uptime is $uptime minutes" }
   #
   # figure out if the uptime should be reported in minutes/hours/days
   #
   if ($uptime_minutes -ge 1440 ) {								#system has been up for more than 1 day (1440 minutes)
      $uptime_days = $uptime_minutes / 1440					#convert uptime to days
      $uptime_days = [math]::round($uptime_days,0) 		#truncate to 0 decimal places, nearest day is close enough 
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime_days days"
   }
   if ( ($uptime_minutes -ge 60) -and ($uptime_minutes -lt 1440) ) {		#system has been up for more than 1 hour, but less than 1 day, so report in hours
      $uptime_hours = $uptime_minutes / 60
      $uptime_hours = [math]::round($uptime_hours,0) 		  	            #truncate to 0 decimal places, nearest hour is close enough 
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime_hours hours"
   }
   if ( ($uptime_minutes -ge 30) -and ($uptime_minutes -lt 60) ) {		#system has been up for more than 30 minutes but less than 60 minutes, so report in minutes
      $uptime_minutes = $uptime_minutes 
      $uptime_minutes = [math]::round($uptime_minutes,0) 		  	      #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "OK - System uptime is $uptime_minutes minutes" }
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - System uptime is $uptime_minutes minutes"
   }
   if ($uptime_minutes -lt 30 ) {
      $uptime_minutes = $uptime_minutes 
      $uptime_minutes = [math]::round($uptime_minutes,0) 		  	                        #truncate to 0 decimal places, nearest minute is close enough 
      if ($verbose -eq "yes") {Write-Host "WARN - recent reboot detected.  System uptime is $uptime_minutes minutes" }
      $exit_code = $WARN 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - recent reboot detected.  System uptime is $uptime_minutes minutes"
   }
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
   return     #break out of function
} 											#end of function
#
# call the above function
#
Get-Uptime

