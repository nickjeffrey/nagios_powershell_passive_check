# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created

function Get-RDP-User {
   #
   $verbose = "yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-RDP-User function" }
   #
   # This function parses the output of the "qwinsta" command to show the currently logged in users.
   # We are interested in the SESSIONNAME called "rdp-tcp#[0-9]", which shows the user currently logged in at the machine console.
   # This is important for certain ill-behaved applications that require a local user to be logged in via RDP.
   # Sample output for domain user with active RDP session:
   #    PS C:\> qwinsta.exe
   #    SESSIONNAME       USERNAME                 ID  STATE   TYPE        DEVICE
   #     services                                    0  Disc
   #     console                                     1  Conn
   #    >rdp-tcp#40        MYDOMAIN\Administrator    7  Active  rdpwd
   #     31c5ce94259d4...                        65536  Listen
   #     rdp-tcp                                 65537  Listen   #
   #
   # Sample output for domain user with disconnected RDP session:
   #    PS C:\> qwinsta.exe
   #    SESSIONNAME       USERNAME                 ID  STATE   TYPE        DEVICE
   #     services                                    0  Disc
   #     console                                     1  Conn
   #                       MYDOMAIN\Administrator    7  Disc           <---- notice that STATE is "Disc" and SESSIONNAME is empty
   #    >rdp-tcp#56        janedoe                   8  Active         <---- this example shows a local user with an active RDP session
   #                       johnsmith                 9  Disc           <---- this example shows another local user with a disconnected RDP session
   #     31c5ce94259d4...                        65536  Listen 
   #     rdp-tcp                                 65537  Listen


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
   # Let's parse out the interesting bits.
   #
   $RDPUser = $RDPUser -Match 'Active|Disc'                # parse out the connection states of Active and Disc
   $RDPUser = $RDPUser -replace 'services\s+0\s+Disc'      # there is always a sessionid 0, get rid of it
   $RDPUser = $RDPUser -Match 'Active|Disc'                # get rid of blank line by matching on Active|Disc again
   $RDPUser = $RDPUser -replace '>'                        # get rid of the leading > character
   $RDPUser = $RDPUser -replace 'rdp-tcp#\d+'              # get rid of the SESSIONNAME column, which only exists for the active RDP session
   $RDPUser = $RDPUser -replace ' rdpwd '                  # remove rdpwd from TYPE column
   $RDPUser = $RDPUser -replace '\s+',' '                  # change multiple spaces to single space
   $RDPUser = $RDPUser -replace '^ '                       # remove leading space
   #
   # At this point, we have (potentially multiple) RDP sessions, with the username, sessionid, state. 
   # Something similar to:
   #  $RDPUser
   #  Administrator 7 Active
   #  janedoe 8 Disc
   #  johnsmith 9 Disc
   #
   # drop the sessionid and state columns
   $RDPUser = $RDPUser -replace ' \d+ Active'
   $RDPUser = $RDPUser -replace ' \d+ Disc'
   #
   # At this point, we just have a list of the username(s) with Active or Disc RDP sessions, similar to:
   #Administrator
   #janedoe
   #johnsmith
   #
   # If the $RDPUser variable is empty or undefined at this point, put in a value of "none" to indicate no one is logged in
   if (!$RDPUser) {$RDPUser = "none"}                   
   #
   # At this point, we have the username(s) logged in via RDP stored in the $RDPUser variable.
   # Now let's decide if this is the user that *should* be logged in, which is somewhat site-dependent.
   # The acceptable values for the $RequiredUser variable are any|none|SomeUserName
   # $RequiredUser=any     means return OK if any user is logged in at the console
   # $RequiredUser=none    means return OK if no  user is logged in at the console
   # $RequiredUser=janedoe means return OK if only the janedoe user is logged in at the console
   # Please uncomment the appropriate $RequiredUser line for your specific environment
   #
   $RequiredUser = "janedoe"                             #return ok only if janedoe is logged in
   #$RequiredUser = "any"                                #return ok if any user is logged in (comment out this line if previous line is being used)
   #$RequiredUser = "none"                               #return ok if no  user is logged in (comment out this line if previous line is being used)
   if ($verbose -eq "yes") { Write-Host "   RDPUser=$RDPUser RequiredUser=$RequiredUser" }
   #
   # submit nagios passive check results
   #
   if ($RequiredUser -eq "any" -and $RDPUser -eq "none") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - no user logged on via RDP.  There should be at least one user logon via RDP."
   }
   if ($RequiredUser -eq "any" -and $RDPUser -notmatch "none" -and $RDPUser -match "\w") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The following RDP sessions exist: $RDPUser "
   }
   if ($RequiredUser -eq "none" -and $RDPUser -eq "none") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - no user logged on via RDP.  There should not be a user logged via RDP."
   }
   if ($RequiredUser -eq "none" -and $RDPUser -notmatch "none" -and $RDPUser -match "\w") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - There should not be anyone logged in via RDP.  Please logout the following RDP sessions: $RDPUser."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RDPUser -ne "none" -and $RDPUser -notmatch $RequiredUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in via RDP.  Please login via RDP as $RequiredUser."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RDPUser -eq "none" -and $RequiredUser -ne $RDPUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in via RDP, but there is no user logged in via RDP.  Please logon via RDP as $RequiredUser"
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RDPUser -match $RequiredUser) {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $RequiredUser user is logged in via RDP."
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}
#
# call the above function
#
Get-RDP-User
