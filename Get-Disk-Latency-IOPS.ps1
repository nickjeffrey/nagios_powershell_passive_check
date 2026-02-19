# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created
# 2023-11-29	Bug fix, use = instead of -eq for assignment
# 2026-02-19   add NCPA compatibility


function Get-Disk-Latency-IOPS {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-Latency-IOPS function" }
   #
   # declare variables
   $service        = "Disk IO" 	                		#name of check defined on nagios server
   $drive_count    = 0						#counter variable used to detect the number of disks
   $plugin_output  = ""						#initialize variable
   $queueLengthWarn = "no"					#initialize yes|no flag
   $latencyWarn     = "no"					#initialize yes|no flag
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3      
   #
   #
   try {
      Get-WmiObject -class Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue | Foreach $_ {
         $DriveName    = $_.Name
      
         $writeMBps    = $_.DiskWriteBytesPersec /1MB ; $writeMBps = [math]::round($writeMBps,1)        #truncate to 1 decimal
         $readMBps     = $_.DiskReadBytesPersec  /1MB ; $readMBps  = [math]::round($readMBps,1)         #truncate to 1 decimal
         $writeIOPS    = $_.DiskWritesPersec
         $readIOPS     = $_.DiskReadsPersec
         $writeLatency = $_.AvgDisksecPerWrite
         $readLatency  = $_.AvgDisksecPerWrite
         $queueLength  = $_.CurrentDiskQueueLength
         #$x = "DriveName:" + $_.Name + " writeIOPS:" +  $_.DiskWritesPersec + " readIOPS:" + $_.DiskReadsPersec + " writeLatency:" + $_.AvgDisksecPerWrite + "ms readLatency:" + $_.AvgDisksecPerRead + "ms"
         $x = "DriveName:$DriveName writeIOPS:$writeIOPS readIOPS:$readIOPS writeLatency:${writeLatency}ms readLatency:${readLatency}ms queueLength:$queueLength"
         if ($verbose -eq "yes") { Write-Host $x }
         $plugin_output = "$plugin_output, $x"			#concatenate the output for each disk
         if ( ($readLatency -ge 30) -or ($writeLatency -ge 30) ) { $latencyWarn     = "yes" }		#set flag for alerting
         if ( $queueLength -gt 4 )                               { $queueLengthWarn = "yes" }		#set flag for alerting
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $exit_code = $UNKNOWN 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine disk latency.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # If we get this far, all the disk latency/IOPS detail has been collected.
   #
   # Alert for both high latency and high disk queue length
   #
   if ($latencyWarn -eq "yes" -And $queueLengthWarn -eq "yes") {
      $exit_code = $WARN
      $plugin_output = "$service WARN - high disk latency and high disk queue length.  $plugin_output"
   }
   #
   # Alert for high latency but low disk queue length
   #
   if ($latencyWarn -eq "yes" -And $queueLengthWarn -eq "no") {
      $exit_code = $WARN
      $plugin_output = "$service WARN - high disk latency.  $plugin_output"
   }
   #
   # Alert for high disk queue length but low disk latency
   #
   if ($latencyWarn -eq "no" -And $queueLengthWarn -eq "yes") {
      $exit_code = $WARN
      $plugin_output = "$service WARN - high disk queue length.  $plugin_output"
   }
   #
   # This is what normal should be, low disk latency and low disk queue length
   #
   if ($latencyWarn -eq "no" -And $queueLengthWarn -eq "no") {
      $exit_code = $OK
      $plugin_output = "$service OK $plugin_output"
   }
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
Get-Disk-Latency-IOPS

