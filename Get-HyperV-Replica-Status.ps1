# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created
# 2026-02-29   add NCPA compatibility

function Get-HyperV-Replica-Status {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-HyperV-Replica-Status function" }
   #
   # declare variables
   $service       = "Hyper-V Replica"
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        
   #
   # Confirm the Hyper-V windows feature is installed
   #
   try {
      $hyperv = Get-WindowsFeature -Name Hyper-V
      if ($hyperv.InstallState -eq "Installed") {
         if ($verbose -eq "yes") { Write-Host "Hyper-V role is installed" }
      } 
      else {
         if ($verbose -eq "yes") { Write-Host "Hyper-V role is not installed on this machine, skipping check" }
         $exit_code = $UNKNOWN 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "UNKNOWN - Hyper-V role is not installed on this machine"
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
      }    #end of else block
   }       #end of try block
   catch {
      Write-Host "ERROR: Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      $exit_code = $UNKNOWN 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
         $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
         Submit-Nagios-Passive-Check   #call function to send results to nagios
      } else {
         Write-Output "$plugin_output"
         exit $exit_code
      }
      return   #break out of function   
   }           #end of catch block
   #
   #
   # If we get this far, the Hyper-V role is installed.
   #
   # Get a list of VM's who are primary replicas whose is not Normal. 
   try { 
      $UnhealthyVMs = Measure-VMReplication -ErrorAction Stop | Where-Object {$_.ReplicationMode -eq "Primary" -and $_.ReplicationHealth -ne "Normal"} 
   } 
   catch { 
      Write-Host -NoNewline "Hyper-V Replica Status is Unknown.|" 
      Write-Host "" 
      $exit_code = $UNKNOWN
   } 
   if ($UnhealthyVMs) { 
      # If we have VMs then we need to determine if we need to return critical or warning. 
      $CriticalVMs = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Critical" 
      $WarningVMs  = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Warning" 
      if ($CriticalVMs) { 
         $exit_code = $CRITICAL 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service CRITICAL - Hyper-V Replica Health is critical for $($CriticalVMs.Name)."
      } 
      elseif ($WarningVMs) { 
         $exit_code = $WARN			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - Hyper-V Replica Health is WARN for $($WarningVMs.Name)."
      } 
      else { 
         $exit_code = $UNKNOWN			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Hyper-V Replica Health is UNKNOWN"
      } 
   } 
   else { 
      # No Replication Problems Found 
      $exit_code = $OK			 						#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - Hyper-V Replica Health is normal"
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
   return   
}												#end of function
#
# call the above function
#
Get-HyperV-Replica-Status
