# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   add NCPA compatibility

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
   $predictfail_count = 0			   #counter variable used to track number of disks with predictive failure warnings
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3                         
   #
   #
   try {
      # NOTE: this WMI namespace is used for IDE/SATA/SCSI drives, but not NVMe drives!
      # So for modern hardware, you may get no output, which this script will interpret as "no drives supporting SMART"
      # This section should be updated to also search other WMI namespaces like MSFT_StorageReliabilityCounter
      Get-WmiObject -namespace root\wmi -class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue | Foreach $_ {
         $drive_count++						#increment counter 
         if ($verbose -eq "yes") { Write-Host "InstanceName:" $_.InstanceName "PredictFailure:" $_.PredictFailure }
         if ($_.PredictFailure -ne $True) {
            $predictfail_count++             #increment counter
            $exit_code = $WARN 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service WARN - predictive drive failure for disk $_.InstanceName , disk failure is imminent.)"
            # BUG ALERT: if there are multiple disks with errors, only the last disk will be shown in the output
         }
      } 							#end of foreach loop
      #
      # this section is for zero drives with SMART metrics detected.  
      # Probably a virtual machine, or a physical machine using hardware RAID.
      #
      if ($drive_count -eq 0) {					
         $exit_code = $OK 			 		      #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no drives supporting SMART health metrics were found.  This may be a virtual machine, or a physical machine using hardware RAID."
      }
      #
      # at least one drive that supports SMART, no predictive failure errors
      # if we get to this point far, none of the disks have SMART predictive errors
      #
      if ($drive_count -gt 0 -And $predictfail_count -eq 0) {
         $exit_code = $OK 			 		      #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - no SMART errors detected)"
      }
   }								                  #end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $exit_code = $UNKNOWN 			        #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
   }                                        #end of catch block
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
   return                                                            #break out of function
}								#end of function
#
# call the above function
#
Get-Disk-SMART-Health



