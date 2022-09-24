# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-09-23	njeffrey	Script created


function Get-MPIO-Path-State {
   #
   $verbose="yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-MPIO-Path-State function" }
   #
   # nagios return codes
   $OK=0
   $WARN=1
   $CRITICAL=2
   $UNKNOWN=3
   #
   # This function parses the output of the "mpclaim.exe" command to show the path state of multipath iSCSI and/or Fibre Channel disks
   # Sample output:
   # PS C:\> c:\windows\system32\mpclaim.exe -s -d
   # For more information about a particular disk, use 'mpclaim -s -d #' where # is the MPIO disk number.
   # MPIO Disk    System Disk  LB Policy    DSM Name
   # -------------------------------------------------------------------------------
   # MPIO Disk0   Disk 2       RR           Microsoft DSM
   # MPIO Disk1   Disk 3       RR           Microsoft DSM
   # MPIO Disk2   Disk 4       RR           Microsoft DSM
   #
   #  This command shows the path status for Disk0.  In this example, there are 4 paths.
   # PS C:\temp> c:\windows\system32\mpclaim.exe -s -d 0
   # MPIO Disk0: 04 Paths, Round Robin, Symmetric Access
   #  Controlling DSM: Microsoft DSM
   #  SN: 6000D31004704E000000000000000008
   #  Supported Load Balance Policies: FOO RR RRWS LQD WP LB
   #
   # Path ID          State              SCSI Address      Weight
   # ---------------------------------------------------------------------------
   # 0000000077050007 Active/Optimized   005|000|007|001   0     
   #   TPG_State : Active/Optimized  , TPG_Id: 61498, : 58       <---- This is what we want to see
   #
   # 0000000077050006 Active/Unoptimized   005|000|006|001   0   
   #   TPG_State : Active/Unoptimized  , TPG_Id: 61498, : 58     <---- Acceptable for active/passive storage systems
   #
   # 0000000077050003 Standby              005|000|003|001   0
   #   TPG_State : Standby             , TPG_Id: 61495, : 55     <---- This is bad
   #
   # 0000000077050002 Unavailable          005|000|002|001   0
   #   TPG_State : Unavailable         , TPG_Id: 61495, : 55     <---- This is bad
   #
   #
   #
   # declare variables
   $service = "MPIO Path State"                    #name of check defined on nagios server
   #
   #
   # confirm the mpclaim.exe file exists
   $mpclaim = "c:\windows\system32\mpclaim.exe"
   if (-Not(Test-Path $mpclaim -PathType Leaf)) {
      $plugin_state  = $UNKNOWN  
      $plugin_output = "$service UNKNOWN - cannot find $mpclaim executable.  Please confirm the MPIO feature is installed."
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   try {
      # xxxxThe expected output of this command is empty if there is no user logged in at the console.
      # xxxxIf there is a user logged in at the console (but not via RDP), the output will look similar to:
      # xxxxSOMEDOMAIN\someusername
      #
      $mpclaim_result = . $mpclaim -s -d 
      $mpio_disks = $mpclaim_result | Select-String -Pattern "MPIO Disk[0-9]"
      $mpio_disks = $mpio_disks -Replace '^MPIO Disk'   #get rid of leading text
      $mpio_disks = $mpio_disks -Replace ' .*'          #get rid of trailing text
      $mpio_disks = @($mpio_disks)                      #convert string to array
   }
   catch {
      Write-Host "Access denied.  Please check your permissions."
      $plugin_state = $UNKNOWN
      $plugin_output = "$service UNKNOWN - Could not run $mpclaim command.  Please check permissions of user executing this script."
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # We only get this far if $mpio_disks contains data
   #
   $active_optimized   = 0   #initialize counter variable
   $active_unoptimized = 0   #initialize counter variable
   $standby            = 0   #initialize counter variable
   $unavailable        = 0   #initialize counter variable
   #
   $mpio_disks | ForEach {
      $path_status = . $mpclaim -s -d $_
      $path_status = $path_status | Select-String -Pattern 'TPG_State'   #parse out the TPG_State lines
      $path_status | ForEach {
         if ($_ -Match 'Active/Optimized')   { $active_optimized++ }    #increment counter variable
         if ($_ -Match 'Active/Unoptimized') { $active_unoptimized++ }  #increment counter variable
         if ($_ -Match 'Standby')            { $standby++ }             #increment counter variable
         if ($_ -Match 'Unavailable')        { $unavailable++ }         #increment counter variable
      }
   }
   #
   # submit nagios passive check results
   #
   if ($active_optimized %2 -eq 0) {   #modulus of 2 should return zero
      $plugin_state  = $WARN 
      $plugin_output = "$service WARN - Active/Optimized paths should be an even number.  Odd numbers indicate a non-redundant configuration.  Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($active_optimized -lt $active_unoptimized) {
      $plugin_state  = $WARN  
      $plugin_output = "$service WARN - There are fewer Active/Optimized paths than Active/Unoptimized paths.  Active/Optimized should be at least equal.  Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($standby -gt 0) {
      $plugin_state  = $WARN  
      $plugin_output = "$service WARN - Detected $standby paths in standby mode.  Please investigate.  Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($unavailable -gt 0) {
      $plugin_state  = $WARN  
      $plugin_output = "$service WARN - Detected $unavailable paths in unavailable state.  Please investigate.  Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($active_optimized -eq $active_unoptimized -eq 0 -and $standby -eq 0 -and $unavailable -eq 0) {
      $plugin_state  = $OK  
      $plugin_output = "$service OK - Equal numbers of Active/Optimized and Active/Unoptimized paths indicate an active/passive storage system.  Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($active_optimized -gt 0 -and $active_unoptimized -eq 0 -and $standby -eq 0 -and $unavailable -eq 0) {
      $plugin_state  = $OK  
      $plugin_output = "$service OK - Active/Optimized:$active_optimized Active/Unoptimized:$active_unoptimized Standby:$standby Unavailable:$unavailable"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return                                                            #break out of function
}
#
# call the above function
#
Get-MPIO-Path-State