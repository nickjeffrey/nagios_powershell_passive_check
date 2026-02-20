# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   add NCPA compatibility


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
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3       
   #
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
         $exit_code = $OK 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - $plugin_output"
      }
      if ($error_count -gt 0) {					#at least one SCSI controllers report status other than OK
         $exit_code = $WARN 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - SCSI controller error.  $plugin_output"
      }
   }								#end of try block
   #
   # we only get into the "catch" block if there were insufficient WMI permissions
   #
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $exit_code = $UNKNOWN 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
   }                  #end of catch block
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
Get-Disk-RAID-Health

