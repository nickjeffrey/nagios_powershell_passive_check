function Get-Disk-SMART-Health {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-SMART-Health function" }
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
            if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
            return                                                            #break out of function
         }
      } 							#end of foreach loop
      if ($drive_count -eq 0) {					#no drives with SMART metrics detected.  Probably a virtual machine, or a physical machine using hardware RAID.
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no drives supporting SMART health metrics were found.  This may be a virtual machine, or a physical machine using hardware RAID."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
      if ($drive_count -gt 0) {					#found at least 1 drive that supports SMART health metrics
         # if we get this far, none of the disks have SMART predictive errors
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no SMART errors detected)"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
}								#end of function

