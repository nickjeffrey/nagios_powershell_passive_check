function Get-RDP-User {
   #
   $verbose = "yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-RDP-User function" }
   #
   # This function parses the output of the "qwinsta" command to show the currently logged in users.
   # We are interested in the SESSIONNAME called "rdp-tcp#[0-9]", which shows the user currently logged in at the machine console.
   # This is important for certain ill-behaved applications that require a local user to be logged in via RDP.
   #Sample output:
   # PS C:\> qwinsta.exe
   # SESSIONNAME       USERNAME                 ID  STATE   TYPE        DEVICE
   #  services                                    0  Disc
   #  console                                     1  Conn
   # >rdp-tcp#40        MYDOMAIN\Administrator    7  Active  rdpwd
   #  31c5ce94259d4...                        65536  Listen
   #  rdp-tcp                                 65537  Listen   #
   #
   # declare variables
   $service = "RDPLogon"                    #name of check defined on nagios server
   #
   try {
      $RDPUser = qwinsta.exe
   }
   catch {
      Write-Host "Access denied.  Please check your permissions."
      $plugin_state = 3                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not run query user command.  Please check permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # We only get this far if $RDPUser contains data
   #
   $RDPUser = $RDPUser -Match "rdp-tcp#"                 #parse out the interesting line(s)
   $RDPUser = $RDPUser -Match "Active"                   #parse out the interesting line(s)
   $RDPUser = $RDPUser -replace '>'                      #replace leading > character
   $RDPUser = $RDPUser -replace '^\s+'                   #replace leading spaces
   $RDPUser = $RDPUser -replace 'rdp-tcp#\d+\s+'         #replace leading rdp-tcp#[0-9]+ characters
   $RDPUser = $RDPUser -replace '\s+\d+\s+Active\s+rdpwd\s+'     #replace trailing characters
   $RDPUser = $RDPUser -replace '\s+\d+\s+Active\s+'     #replace trailing characters
   $RDPUser = $RDPUser -replace '^.*\\'                  #change DOMAIN\username to username
   if (!$RDPUser) {$RDPUser = "none"}                    #if $ConsoleUser is empty or undefined at this point, put in a value of "none" to indicate no one is logged in
   #
   # At this point, we have the username logged in via RDP
   # Now let's decide if this is the user that *should* be logged in, which is somewhat site-dependent.
   # The acceptable values for the $RequiredUser variable are any|none|SomeUserName
   # $RequiredUser=any     means return OK if any user is logged in at the console
   # $RequiredUser=none    means return OK if no  user is logged in at the console
   # $RequiredUser=janedoe means return OK if only the janedoe user is logged in at the console
   # Please uncomment the appropriate $RequiredUser line for your specific environment
   #
   $RequiredUser = "administrator"                          #return ok only if janedoe is logged in
   #$RequiredUser = "any"                              #return ok if any user is logged in (comment out this line if previous line is being used)
   #$RequiredUser = "none"                              #return ok if no   user is logged in (comment out this line if previous line is being used)
   if ($verbose -eq "yes") { Write-Host "   RDPUser=$RDPUser RequiredUser=$RequiredUser" }
   #
   # submit nagios passive check results
   #
   if ($RequiredUser -eq "any" -and $RDPUser -eq "none") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - no user logged on via RDP.  There should be a user logon via RDP."
   }
   if ($RequiredUser -eq "any" -and $RDPUser -notmatch "none" -and $RDPUser -match "\w") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $RDPUser user is logged in via RDP."
   }
   if ($RequiredUser -eq "none" -and $RDPUser -eq "none") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - no user logged on via RDP.  There should not be a user logged via RDP."
   }
   if ($RequiredUser -eq "none" -and $RDPUser -notmatch "none" -and $RDPUser -match "\w") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RDPUser user is logged in via RDP.  There should not be anyone logged in via RDP.  Please logout the user $RDPUser."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RDPUser -ne "none" -and $RequiredUser -ne $RDPUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in via RDP, but the $RDPUser user is logged in instead."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RDPUser -eq "none" -and $RequiredUser -ne $RDPUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in via RDP, but there is no user logged in via RDP.  Please logon via RDP as $RequiredUser"
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RequiredUser -eq $RDPUser) {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $RequiredUser user is logged in via RDP."
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}

