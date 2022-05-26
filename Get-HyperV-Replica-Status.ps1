# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created

function Get-HyperV-Replica-Status {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-HyperV-Replica-Status function" }
   #
   # declare variables
   $service       = "Hyper-V Replica"
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
         $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "UNKNOWN - Hyper-V role is not installed on this machine"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
   }
   catch {
      Write-Host "ERROR: Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not run Get-WindowsFeature Powershell cmdlet.  Please check permissions."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # If we get this far, the Hyper-V role is installed.
   #
   # Get a list of VM's who are primary replicas whose is not Normal. 
   try { 
      $UnhealthyVMs = Measure-VMReplication -ErrorAction Stop | Where-Object {$_.ReplicationMode -eq "Primary" -and $_.ReplicationHealth -ne "Normal"} 
   } 
   catch { 
      Write-Host -NoNewline "Hyper-V Replica Status is Unknown.|" ; Write-Host "" ; exit $returnStateUnknown 
   } 
   if ($UnhealthyVMs) { 
      # If we have VMs then we need to determine if we need to return critical or warning. 
      $CriticalVMs = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Critical" 
      $WarningVMs  = $UnhealthyVMs | Where-Object -Property ReplicationHealth -eq "Warning" 
      if ($CriticalVMs) { 
         $plugin_state = 2 			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service CRITICAL - Hyper-V Replica Health is critical for $($CriticalVMs.Name)."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      } 
      elseif ($WarningVMs) { 
         $plugin_state = 1			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - Hyper-V Replica Health is WARN for $($WarningVMs.Name)."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      } 
      else { 
         $plugin_state = 3			 					#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service UNKNOWN - Hyper-V Replica Health is UNKNOWN"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      } 
   } 
   else { 
      # No Replication Problems Found 
      $plugin_state = 3			 						#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - Hyper-V Replica Health is normal"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   } 
}												#end of function
#
# call the above function
#
Get-HyperV-Replica-Status