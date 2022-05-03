function Get-Windows-Defender-Antivirus-Status {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Windows-Defender-Antivirus-Status function" }
   #
   # declare variables
   $service = "Defender Antivirus" 					#name of check defined on nagios server
   $threshold_warn     = 7
   $threshold_crit     = 30
   #
   try { 
      # Query the server for the login events. 
      $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
      #
      # returned info looks like:
      # AMEngineVersion                 : 1.1.17700.4
      # AMProductVersion                : 4.18.2011.6
      # AMRunningMode                   : Normal
      # AMServiceEnabled                : True
      # AMServiceVersion                : 4.18.2011.6
      # AntispywareEnabled              : True
      # AntispywareSignatureAge         : 0
      # AntispywareSignatureLastUpdated : 12/20/2020 6:33:13 PM
      # AntispywareSignatureVersion     : 1.329.773.0
      # AntivirusEnabled                : True
      # AntivirusSignatureAge           : 0
      # AntivirusSignatureLastUpdated   : 12/20/2020 6:33:13 PM
      # AntivirusSignatureVersion       : 1.329.773.0
      # BehaviorMonitorEnabled          : True
      # ComputerID                      : C6DBDD29-ED27-4C91-8FEE-ECA4C9FDCCA1
      # ComputerState                   : 0
      # FullScanAge                     : 4294967295
      # FullScanEndTime                 :
      # FullScanStartTime               :
      # IoavProtectionEnabled           : True
      # IsTamperProtected               : False
      # IsVirtualMachine                : True
      # LastFullScanSource              : 0
      # LastQuickScanSource             : 2
      # NISEnabled                      : True
      # NISEngineVersion                : 1.1.17700.4
      # NISSignatureAge                 : 0
      # NISSignatureLastUpdated         : 12/20/2020 6:33:13 PM
      # NISSignatureVersion             : 1.329.773.0
      # OnAccessProtectionEnabled       : True
      # QuickScanAge                    : 0
      # QuickScanEndTime                : 12/21/2020 2:38:27 AM
      # QuickScanStartTime              : 12/21/2020 2:37:17 AM
      # RealTimeProtectionEnabled       : True
      # RealTimeScanDirection           : 0
      # PSComputerName                  :
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Get-MpComputerStatus powershell module.  Exiting script."
      exit 
   }
   #
   # if we get this far, the $defender variable contains all the details about the Microsoft Defender antivirus
   #
   # parse out the ComputerState property and translate from a numeric value to human readable text
   #
   if ($defender.ComputerState -eq 0)  { $ComputerState = "CLEAN"                    }
   if ($defender.ComputerState -eq 1)  { $ComputerState = "PENDING_FULL_SCAN"        }
   if ($defender.ComputerState -eq 2)  { $ComputerState = "PENDING_REBOOT"           }
   if ($defender.ComputerState -eq 4)  { $ComputerState = "PENDING_MANUAL_STEPS"     }
   if ($defender.ComputerState -eq 8)  { $ComputerState = "PENDING_OFFLINE_SCAN"     }
   if ($defender.ComputerState -eq 16) { $ComputerState = "PENDING_CRITICAL_FAILURE" }
   #
   # collect all the common data in a single variable for ease of output
   $plugin_output = "ComputerState:" + $ComputerState + " DefenderEnabled:" + $defender.AntivirusEnabled + " LastSignatureUpdate:" + $defender.AntivirusSignatureAge  + "days LastQuickScan:" + $defender.QuickScanAge + "days LastFullScan:" + $defender.FullScanAge + "days"
   #
   # 
   if ( ($defender.AntivirusEnabled -eq "True") -and ($defender.ComputerState -eq 0) -and ($defender.LastSignatureUpdate -lt $threshold_warn) -and ($defender.LastQuickScan -lt $threshold_warn) ) {
      $plugin_state = 0 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($defender.AntivirusEnabled -ne "True") {
      $plugin_state = 2 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Defender antivirus not Enabled.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($defender.ComputerState -ne 0) {							#0=CLEAN 1=PENDING_FULL_SCAN 2=PENDING_REBOOT
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Defender ComputerState needs attention.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($defender.LastSignatureUpdate -ge $threshold_crit) {
      $plugin_state = 2 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Defender LastSignatureUpdate is more than $threshold_warn days old.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ($defender.LastSignatureUpdate -ge $threshold_warn) {
      $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Defender LastSignatureUpdate is more than $threshold_warn days old.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
} 											#end of function


