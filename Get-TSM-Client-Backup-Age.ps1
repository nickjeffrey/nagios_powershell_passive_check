function Get-TSM-Client-Backup-Age {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-TSM-Client-Backup-Age function" }
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
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
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
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   $x = Get-ChildItem $fileToCheck
   $age_in_hours = (New-TimeSpan -Start (Get-Date $x.LastWriteTime) -End (Get-Date)).TotalHours  #do some math to figure out number of hours between now and license expiration date
   $age_in_hours = [math]::round($age_in_hours,0)   	                        #truncate to 0 decimal places, nearest hour is close enough
   if ( $age_in_hours > 28 ) { 								#last backup time was more than 28 hours ago
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - last backup was $age_in_hours hours ago."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }	
} 											#end of function

