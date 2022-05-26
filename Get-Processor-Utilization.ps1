# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created

function Get-Processor-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Processor-Utilization function" }
   #
   # declare variables
   $service = "CPUutil"                         #name of check defined on nagios server
   $threshold_warn = 50				#warn     if processor utilization is more than 50%
   $threshold_crit = 75				#critical if processor utilization is more than 75%
   #
   try {
      $ProcessorResults = Get-CimInstance -Class Win32_Processor -ComputerName $Computer  -ErrorAction Stop
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine paging space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # We only get this far if $ProcessorResults contains data
   #
   $processor_load_pct = $ProcessorResults.LoadPercentage
   if ($verbose -eq "yes") { Write-Host "   Processor utilization:${processor_load_pct}%" }
   #
   # submit nagios passive check results
   #
   if ($processor_load_pct -le $threshold_warn) {
      $plugin_state = 0 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_warn) {
      $plugin_state = 1 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_crit) {
      $plugin_state = 2 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - processor utilization is ${processor_load_pct}%"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}
#
# call the above function
#
Get-Processor-Utilization