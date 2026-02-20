# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   add NCPA compatibility


function Get-Processor-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Processor-Utilization function" }
   #
   # declare variables
   $service = "CPU util"         #name of check defined on nagios server
   $threshold_warn = 50				#warn     if processor utilization is more than 50%
   $threshold_crit = 75				#critical if processor utilization is more than 75%
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3         
   #
   #
   try {
      $ProcessorResults = Get-CimInstance -Class Win32_Processor -ComputerName $Computer  -ErrorAction Stop
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $exit_code = $UNKNOWN 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine paging space usage.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   #
   # We only get this far if $ProcessorResults contains data
   #
   $processor_load_pct = $ProcessorResults.LoadPercentage
   if ($verbose -eq "yes") { Write-Host "   Processor utilization:${processor_load_pct}%" }
   #
   if ($processor_load_pct -le $threshold_warn) {
      $exit_code = $OK 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_warn) {
      $exit_code = $WARN 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - processor utilization is ${processor_load_pct}%"
   }
   if ($processor_load_pct -gt $threshold_crit) {
      $exit_code = $CRITICAL 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - processor utilization is ${processor_load_pct}%"
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
   return                                                            #break out of function
}
#
# call the above function
#
Get-Processor-Utilization


