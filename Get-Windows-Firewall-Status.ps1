# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   Add NCPA compatibility


function Get-Windows-Firewall-Status {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Windows-Firewall-Status function" }
   #
   # declare variables
   $service             = "firewall" 				#name of check defined on nagios server
   $zone_disabled_count = 0 					#initialize counter variable
   $plugin_output       = ""					#initialize variable
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
      $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name,Enabled
      #
      # returned info looks like:
      # Name    Enabled
      # ----    -------
      # Domain     True
      # Private    True
      # Public     True
   }
   catch { 
      $exit_code = $UNKNOWN
      $plugin_output = "$service UNKNOWN - insufficient permissions to run Get-NetFirewallProfile powershell module."
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
   # if we get this far, the $firewall variable contains all the details about the different firewall zones and their enabled/disabled statusMicrosoft Defender antivirus
   #
   foreach ($zone in $firewall) {
      if ($zone.Enabled -ne $True) { $zone_disabled_count++ }			#increment counter 
      $plugin_output = "$plugin_output, Zone:" + $zone.Name + " Enabled:" + $zone.Enabled  #append each firewall zone status to a string
   }
   # 
   if ( $zone_disabled_count -eq 0 ) {
      $exit_code = $OK 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK $plugin_output"
   }
   if ( $zone_disabled_count -gt 0 ) {
      $exit_code = $WARN 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - $zone_disabled_count firewall zones are disabled.  $plugin_output"
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
Get-Windows-Firewall-Status

