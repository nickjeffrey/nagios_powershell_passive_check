# powershell function to perform check on local machine
# this script can be called by NCPA or executed as a passive check
# intent: find Windows hosts not updated in > 90 days

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created
# 2025-09-18	njeffrey	Add error check to catch updates will missing InstalledOn date



function Get-LastWindowsUpdate {
   $verbose = "no"             #yes|no flag to increase verbosity for debugging
   if ($verbose -eq "yes") { Write-Host "`nRunning Get-LastWindowsUpdate function" }

   $service = "Windows Update"
   $most_recent_hotfix = 99999  # sentinel for "none found"

   # --- helper: safe date parser (never throws), used if Windows update did not include InstalledOn date----
   function Convert-ToDateSafe {
     param([Parameter(Mandatory=$false)]$Value)
     if ($Value -is [datetime]) { return $Value }
     if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
     $dt = $null
     # try invariant, then current culture
     if ([datetime]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
                              [Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt }
     if ([datetime]::TryParse([string]$Value, $null,
                              [Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) { return $dt }
     return $null
   }
   # --------------------------------------------------------------------------

   try {
      # You can switch to CIM (often more stable) by uncommenting the next line
      # $hotfixes = Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue
      $hotfixes = Get-HotFix -ErrorAction SilentlyContinue

      # sort by a safe computed key; missing/invalid dates sort last and do NOT stop the pipeline
      $hotfixes |
        Sort-Object {
          try { Convert-ToDateSafe $_.InstalledOn } catch { $null }
        } -Descending |
        ForEach-Object {
          # read + parse InstalledOn safely
          $installed = $null
          try { $installed = Convert-ToDateSafe $_.InstalledOn } catch { $installed = $null }

          if (-not $installed) {
            if ($verbose -eq "yes") { Write-Host "   Skipping HotFixID $($_.HotFixID): no InstalledOn date" }
            return  # continue to next item
          }

          $age_in_days = (New-TimeSpan -Start $installed -End (Get-Date)).TotalDays
          if ($age_in_days -lt $most_recent_hotfix) {
            $most_recent_hotfix = [math]::Round($age_in_days, 0)   # nearest day
            if ($verbose -eq "yes") {
              Write-Host ("   HotFixID: {0}  InstalledOn: {1}  ({2} days ago)" -f $_.HotFixID, $installed, $most_recent_hotfix)
            }
          }
        }
   }
   catch {
      Write-Host "Access denied.  Please check your WMI permissions."
      $plugin_state = 3
      $common_output_data = "$service UNKNOWN - Could not determine state of Windows patching. Please check WMI permissions of user executing this script."
      #
      # print output and exit script
      #
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { 
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         $plugin_state = $exit_code    #used by Submit-Nagios-Passive-Check
         Submit-Nagios-Passive-Check   #call function to send results to nagios
      } else {
         Write-Output "$plugin_output"
         exit $exit_code
      }
      return
   }
   #
   # If we get this far, the $most_recent_hotfix variable contains the number of days since the last updates.
   # Based on that number of deays, figure out the appropriate output 
   #
   if ($most_recent_hotfix -le 90) {
      $plugin_state = 0  # 0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service OK - most recent Windows patches were applied $most_recent_hotfix days ago."
   }
   if ($most_recent_hotfix -gt 90) {
      $plugin_state = 1  # 0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service WARN - most recent Windows patches were applied $most_recent_hotfix days ago. Please confirm this host is getting updated on a regular basis."
   }
   if ($most_recent_hotfix -eq 99999) {
      $plugin_state = 1   # 0=ok 1=warn 2=critical 3=unknown
      $common_output_data = "$service WARN - could not find any Windows Updates or patches applied to this system. Please confirm this host is getting updated."
   }
   #
   # capture nagios performance data
   #
   $perf_data = "0"  #no performance data to report for this check
   #
   # combine the common output and the $perf_data
   $plugin_output = "$common_output_data | $perf_data"
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
   return                                               #break out of function
} 							#end of function

# call the function
Get-LastWindowsUpdate
