# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   Add NCPA compatibility


function Get-Windows-Defender-Antivirus-Status {
   #
   $verbose = "no"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Windows-Defender-Antivirus-Status function" }
   #
   # declare variables
   $service        = "Defender Antivirus" 	#name of check defined on nagios server
   $threshold_warn = 7
   $threshold_crit = 30
   $warn_count     = 0
   $crit_count     = 0
   $warn_output    = ""
   $crit_output    = ""
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        
   #
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
      $exit_code = $UNKNOWN
      $plugin_output = "$service UNKNOWN insufficient permissions to run Get-MpComputerStatus powershell module."
      #
      # print output
      #
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
         $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
         Submit-Nagios-Passive-Check   #call function to send results to nagios
      } else {
         Write-Output "$plugin_output"
         exit $exit_code
      }
      return   
   }
   #
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
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$plugin_output"
   }
   if ($defender.AntivirusEnabled -ne "True") {
      $crit_count++
      $crit_output = "$crit_output Defender antivirus not Enabled."
   }
   if ($defender.ComputerState -ne 0) {							#0=CLEAN 1=PENDING_FULL_SCAN 2=PENDING_REBOOT
      $warn_count++
      $warn_output = "$warn_output Defender ComputerState needs attention."
   }
   if ($defender.LastSignatureUpdate -ge $threshold_crit) {
      $crit_count++
      $crit_output = "$crit_output Defender LastSignatureUpdate is more than $threshold_warn days old."
   }
   if ( ($defender.LastSignatureUpdate -ge $threshold_warn) -and ($defender.LastSignatureUpdate -lt $threshold_crit) ) {
      $warn_count++
      $warn_output = "$warn_output Defender LastSignatureUpdate is more than $threshold_warn days old."
   }
   #
   # prepend all the $crit_output and $warn_output messages to the $plugin_output
   #
   if ( ($crit_count -gt 0) -and ($warn_count -gt 0) ) { 
      $exit_code = $CRITICAL
      $plugin_output = "$service CRITICAL $crit_output $warn_output $plugin_output" 
   }
   if ( ($crit_count -gt 0) -and ($warn_count -eq 0) ) { 
      $exit_code = $CRITICAL
      $plugin_output = "$service CRITICAL $crit_output $plugin_output" 
   }
   if ( ($crit_count -eq 0) -and ($warn_count -gt 0) ) { 
      $exit_code = $WARN
      $plugin_output = "$service WARN $warn_output $plugin_output" 
   }
   if ( ($crit_count -eq 0) -and ($warn_count -eq 0) ) { 
      $exit_code = $OK
      $plugin_output = "$service OK $plugin_output" 
   }
   #
   # print output
   #
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
      $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
      Submit-Nagios-Passive-Check   #call function to send results to nagios
   } else {
      Write-Output "$plugin_output"
      exit $exit_code
   }
   return   #break out of function
} 											#end of function
#
# call the above function
#
Get-Windows-Defender-Antivirus-Status


