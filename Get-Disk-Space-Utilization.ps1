function Get-Disk-Space-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-Space-Utilization function" }
   #
   # declare variables
   $service = "Drive $DeviceID"                 #name of check defined on nagios server
   $threshold_warn = 80				#warn     if disk space utilization is more than 80%
   $threshold_crit = 90				#critical if disk space utilization is more than 90%
   $driveletters = "C:","D:","E:","F:","G:","H:","I:","J:","K:","L:","M:","N:","O:","P:","Q:","R:","S:","T:","U:","V:","W:","X:","Y:","Z:"
   #
   try {
      $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" -ErrorAction Stop    #Drivetype=3 means local hard disk (not a CDROM, not a network drive)
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   # we only get here if the previous try/catch confirmed that sufficient permissions exist to run Get-WmiObject 
   foreach ($driveletter in ($driveletters)) {
      try {
         $diskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = '3'" | Where {($_.DeviceID -eq $driveletter) -and ($_.size -gt 0)} | select-object DeviceID,Size,FreeSpace -ErrorAction Stop
      }
      catch {
         Write-Host "Access denied.  Please check your WMI permissions."
         $service = "Drive $DeviceID"                 #update service description with current drive letter
         $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Could not determine drive $driveletter space usage.  Please check WMI permissions of user executing this script."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
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
         $service         = "Drive $DeviceID"                 #update service description with current drive letter
         if ($verbose -eq "yes") { Write-Host "Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)" }
         #
         # submit nagios passive check results
         #
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -ge $threshold_crit) ) {
            $plugin_state = 2 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service CRITICAL - (usage > ${threshold_crit}%) -  Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
            if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
            return
         }
         if ( ($Used_pct -gt $threshold_warn) -and ($Used_pct -lt $threshold_crit) ) {
            $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service WARN - (usage > ${threshold_warn}%) - Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
            if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
            return
         }
         if ($Used_pct -le $threshold_warn) {
            $plugin_state = 0 				 	#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "$service OK - Drive ${DeviceID} Size:${Size_GB}GB Used:${Used_GB}GB(${Used_pct}%) Free:${FreeSpace_GB}GB(${Free_pct}%)"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
            if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
            return
         }
      }								#end of if blcok
   }								#end of foreach block
}								#end of function
