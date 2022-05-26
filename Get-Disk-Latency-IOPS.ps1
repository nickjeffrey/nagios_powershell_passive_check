# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created

function Get-Disk-Latency-IOPS {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Disk-Latency-IOPS function" }
   #
   # declare variables
   $service        = "Disk IO" 	                		#name of check defined on nagios server
   $drive_count    = 0						#counter variable used to detect the number of disks
   $plugin_state   = 0						#0=ok 1=warn 2=critical 3=unknown
   $plugin_output  = ""						#initialize variable
   $queueLengthWarn = "no"					#initialize yes|no flag
   $latencyWarn     = "no"					#initialize yes|no flag
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
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine disk latency.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # If we get this far, all the disk latency/IOPS detail has been collected.
   #
   # Alert for high latency
   #

   if ( $latencyWarn -eq "yes") {
      $plugin_state -eq 1
      $plugin_output = "$service WARN - high disk latency.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # Alert for high disk queue length
   #
   if ( $queueLengthWarn -eq "yes") {
      $plugin_state -eq 1
      $plugin_output = "$service WARN - high disk queue length.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # We only get this far if everything is ok
   #
   $plugin_state -eq 0
   $plugin_output = "$service OK $plugin_output"
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}								#end of function
#
# call the above function
#
Get-Disk-Latency-IOPS