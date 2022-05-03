function Get-Disk-RAID-Health {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-RAID-Health function" }
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
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
      if ($error_count -gt 0) {					#at least one SCSI controllers report status other than OK
         $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - SCSI controller error.  $plugin_output"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
}								#end of function
