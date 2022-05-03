function Get-Paging-Utilization {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Paging-Utilization function" }
   #
   # declare variables
   $service = "pagefile"                        #name of check defined on nagios server
   $threshold_warn = 50				#warn     if paging space utilization is more than 50%
   $threshold_crit = 75				#critical if paging space utilization is more than 50%
   #
   try {
      $PageFileResults = Get-CimInstance -Class Win32_PageFileUsage -ComputerName $Computer -ErrorAction Stop
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
   # We only get this far if $PageFileResults contains data
   #
   $paging_total_mb = $PageFileResults.AllocatedBaseSize
   $paging_used_mb  = $PageFileResults.CurrentUsage
   if ( $paging_total_mb -gt 0 ) { $paging_used_pct = $paging_used_mb / $paging_total_mb * 100 } else { $paging_used_pct = 0 }    # avoid divide by zero error if $paging_total_mb is zero size
   $paging_used_pct = [math]::round($paging_used_pct,1)   	                        #truncate to 1 decimal place
   if ($verbose -eq "yes") { Write-Host "   Paging space used ${paging_used_mb}MB/${paging_total_mb}MB(${paging_used_pct}%)" }
   #
   # submit nagios passive check results
   #
   if ($paging_used_pct -le $threshold_warn) {
      $plugin_state = 0 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%"
   }
   if ($paging_used_pct -gt $threshold_warn) {
      $plugin_state = 1 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%.  Consider adding more RAM."
   }
   if ($paging_used_pct -gt $threshold_crit) {
      $plugin_state = 2 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - paging space utilization is ${paging_used_mb}MB/${paging_total_mb}MB ${paging_used_pct}%.  System will crash if paging space usage reaches 100%"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}
