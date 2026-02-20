# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script


# CHANGE LOG
# ----------
# 2022-05-25   njeffrey   Script created
# 2026-02-19   njeffrey   add NCPA compatibility
# 2026-02-19   njeffrey	   add $count_warn $count_crit $count_ok counter variables



function Get-Disk-Space-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-Space-Utilization function" }
   #
   # declare variables
   $service = "Drive $DeviceID"                 #name of check defined on nagios server
   $plugin_output  = "" 			#initialize variable
   $disks_warn     = "" 			#initialize variable
   $disks_crit     = "" 			#initialize variable
   $threshold_warn = 80				#warn     if disk space utilization is more than 80%
   $threshold_crit = 90				#critical if disk space utilization is more than 90%
   $count_ok       = 0
   $count_warn     = 0
   $count_crit     = 0
   $driveletters = "C:","D:","E:","F:","G:","H:","I:","J:","K:","L:","M:","N:","O:","P:","Q:","R:","S:","T:","U:","V:","W:","X:","Y:","Z:"
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3      
   #
   #
   try {
      $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" -ErrorAction Stop    #Drivetype=3 means local hard disk (not a CDROM, not a network drive)
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $exit_code = $UNKNOWN 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
         $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
         Submit-Nagios-Passive-Check   #call function to send results to nagios
      } else {
         Write-Output "$plugin_output"
         exit $exit_code
      }
      return                                                            #break out of function
   } 									#end of catch block
   #
   # we only get this far if the previous try/catch confirmed that sufficient permissions exist to run Get-WmiObject 
   foreach ($driveletter in ($driveletters)) {
      try {
         $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" | Where {($_.DeviceID -eq $driveletter) -and ($_.size -gt 0)} | select-object DeviceID,Size,FreeSpace -ErrorAction Stop
      }
      catch {
         Write-Host "Access denied.  Please check your WMI permissions."
         $service = "Drive $DeviceID"                 	#update service description with current drive letter
         $exit_code = $UNKNOWN 			 	#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
            $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
            Submit-Nagios-Passive-Check   #call function to send results to nagios
         } else {
            Write-Output "$plugin_output"
            exit $exit_code
         }
         return                                                            		#break out of function
      }											#end of catch block
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
         $service         = "Drive $DeviceID"                 				#update service description with current drive letter
         #
         # keep appending disk usage for each drive letter to the $plugin_output variable
         #
         $plugin_output = "$plugin_output Drive ${DeviceID} Used:${Used_GB}/${Size_GB}GB(${Used_pct}%). "
         if ($verbose -eq "yes") { Write-Host "Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)" }
         #
         # look for any disks with low free space, increment counter variables if found
         #
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -ge $threshold_crit) ) { 
            $count_crit++ 
            $disks_crit = "$disks_crit ${DeviceID} is ${Used_pct}% full."  #list of all critical drive letters
         }
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -lt $threshold_crit) ) { 
            $count_warn++ 
            $disks_warn = "$disks_warn ${DeviceID} is ${Used_pct}% full."  #list of all warn drive letters
         }
         if ( ($Used_pct -lt $threshold_warn) -and ($Used_pct -lt $threshold_crit) ) { 
            $count_ok++ 
         }
      }								#end of if block
   }							#end of foreach block
   #
   # at this point, all the drive letters have been checked
   # if there are any warnings, prepend the details to $plugin_output
   #
   if ( ($count_crit -gt 0) -and ($count_warn -gt 0) ) { $plugin_output = "Disk space CRITICAL $disks_crit $disks_warn $plugin_output" }
   if ( ($count_crit -gt 0) -and ($count_warn -eq 0) ) { $plugin_output = "Disk space CRITICAL $disks_crit $plugin_output" }
   if ( ($count_crit -eq 0) -and ($count_warn -gt 0) ) { $plugin_output = "Disk space WARN $disks_warn $plugin_output" }
   if ( ($count_crit -eq 0) -and ($count_warn -eq 0) ) { $plugin_output = "Disk space OK $disks_warn $plugin_output" }
   #
   #
   # capture nagios performance data
   #
   $perf_data = "0"  #no performance data to report for this check, this could be improved
   #
   # print output
   #
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
      $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
      Submit-Nagios-Passive-Check   #call function to send results to nagios
   } else {
      Write-Output "$plugin_output | $perf_data"
      exit $exit_code
   }
   return                                                            	#break out of function
}									#end of function
#
# call the above function
#
Get-Disk-Space-Utilization

