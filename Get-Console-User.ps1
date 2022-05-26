# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created


function Get-Console-User {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Console-User function" }
   #
   # This function parses the output of the "query user" command to show the currently logged in users.
   # We are interested in the SESSIONNAME called "console", which shows the user currently logged in at the machine console.
   # This is important for certain ill-behaved applications that require a local user to be logged in at the console.
   #Sample output:
   # PS C:\> query user
   #  USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME
   # >janedoe               console             1  Active      none   4/2/2022 5:19 PM
   #  administrator         rdp-tcp#1           2  Active          .  4/12/2022 11:26 AM
   #  john.smith                                3  Disc     11+04:12  2022-03-31 5:09 PM
   #
   # declare variables
   $service = "ConsoleLogon"                    #name of check defined on nagios server
   #
   try {
      # The expected output of this command is empty if there is no user logged in at th console.
      # If there is a user logged in at the console (but not via RDP), the output will look similar to:
      # SOMEDOMAIN\someusername
      #
      $ConsoleUser = (Get-WMIObject -ClassName Win32_ComputerSystem).Username
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
   # We only get this far if $ConsoleUser contains data
   #
   $ConsoleUser = $ConsoleUser -replace '^.*\\'      #change DOMAIN\username to username
   if (!$ConsoleUser) {$ConsoleUser = "none"}        #if $ConsoleUser is empty or undefined at this point, put in a value of "none" to indicate no one is logged in
   #
   # At this point, we have the username logged in at the console.
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
   if ($verbose -eq "yes") { Write-Host "   ConsoleUser=$ConsoleUser RequiredUser=$RequiredUser" }
   #
   # submit nagios passive check results
   #
   if ($RequiredUser -eq "any" -and $ConsoleUser -eq "none") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - no user logged on at local console.  There should be a user logon at the console."
   }
   if ($RequiredUser -eq "any" -and $ConsoleUser -notmatch "none" -and $ConsoleUser -match "\w") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $ConsoleUser user is logged in at the console."
   }
   if ($RequiredUser -eq "none" -and $ConsoleUser -eq "none") {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - no user logged on at local console.  There should not be a user logged on at the console."
   }
   if ($RequiredUser -eq "none" -and $ConsoleUser -notmatch "none" -and $ConsoleUser -match "\w") {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $ConsoleUser user is logged in at the console.  There should not be anyone logged in at the console.  Please logout the user $ConsoleUser."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $ConsoleUser -ne "none" -and $RequiredUser -ne $ConsoleUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in at the console, but the $ConsoleUser user is logged in instead."
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $ConsoleUser -eq "none" -and $RequiredUser -ne $ConsoleUser) {
      $plugin_state = 2                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - The $RequiredUser user should be logged in at the console, but there is no user logged into the console.  Please logon to the console as $RequiredUser"
   }
   if ($RequiredUser -ne "none" -and $RequiredUser -ne "any" -and $RequiredUser -eq $ConsoleUser) {
      $plugin_state = 0                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - The $RequiredUser user is logged in at the console."
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}
#
# call the above function
#
Get-Console-User


