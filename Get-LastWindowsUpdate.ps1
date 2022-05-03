function Get-LastWindowsUpdate {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-LastWindowsUpdate function" }
   #
   # The intent of this function is to find Windows boxes that have not been updated in >90 days
   # Which would typically indicate the machine is not on a regular patching schedule
   #
   #
   # declare variables
   $service = "Windows Update"                 							#name of check defined on nagios server
   $most_recent_hotfix = 99999									#initialize variable with a high number of days since last hotfix
   #
   try {
      Get-HotFix -ErrorAction SilentlyContinue | sort InstalledOn -Descending | Foreach $_ {
         #if ($verbose -eq "yes") { Write-Host "   most recent hotfix was $most_recent_hotfix days ago" }
         $age_in_days = (New-TimeSpan -Start (Get-Date $_.InstalledOn) -End (Get-Date)).TotalDays
         if ($age_in_days -lt $most_recent_hotfix) { 
            $most_recent_hotfix = $age_in_days 	
            $most_recent_hotfix = [math]::round($most_recent_hotfix,0)   	                        #truncate to 0 decimal places, nearest day is close enough						#find the most recent hotfix based on days since last install
            if ($verbose -eq "yes") { Write-Host "   HotFixID:" $_.HotFixID " InstalledOn:" $_.InstalledOn " ($age_in_days days ago)" }
         } 
      } 											#end of foreach loop
      if ($most_recent_hotfix -eq 99999) {							#could not find any hotfixes / Windows Updates
         $plugin_state = 1 			 	#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - could not find any Windows Updates or patches applied to this system.  Please confirm this host is getting updated."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
      if ($most_recent_hotfix -gt 90) {								#found at least 1 hotfix, but more than 90 days ago
         $plugin_state = 1 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - most recent Windows patches were applied $most_recent_hotfix days ago.  Please confirm this host is getting updated on a regular basis."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
      if ($most_recent_hotfix -le 90) {								#found at least 1 hotfix installed within the last 90 days
         $plugin_state = 0 			 		#0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service OK - most recent Windows patches were applied $most_recent_hotfix days ago."
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
         return                                                            #break out of function
      }
   }								#end of try block
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3 			 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not determine state of Windows patching.  Please check WMI permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
}								#end of function
