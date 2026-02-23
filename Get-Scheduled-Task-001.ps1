# powershell function to perform check on local machine
# this script can be called by NCPA, or submitted as a passive check from the master nagios_passive_check.ps1 script

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created
# 2026-02-19   njeffrey   Add NCPA compatibility

function Get-Scheduled-Task-001 {
   #
   $verbose = "yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Scheduled-Task-001 function" }
   #
   # The Get-ScheduledTaskInfo powershell cmdlet should exist on Windows 2012 and later.
   # This function looks at the Scheduled Task and alerts if the most recent execution was unsuccessful, or the task has not run for XXX hours
   # This function name is Get-Scheduled-Task-###, with the intent that there may be a -001, -002, -003, etc if you have multiple tasks to check
   #
   # declare variables
   $TaskName = "GoogleUpdateTaskMachineCore"      #name of the scheduled task, get with schtasks.exe on monitored host
   $TaskName = "testtask"                         #name of the scheduled task, get with schtasks.exe on monitored host
   $service = "Task $TaskName"                    #name of check defined on nagios server
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        
   #
   #
   try {
      $TaskInfo = get-scheduledtaskinfo -TaskName $TaskName
   }
   catch {
      Write-Host "Access denied.  Please check your permissions."
      $exit_code = $UNKNOWN                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - Could not find scheduled task $TaskName.  Please confirm the scheduled task name is correct, and check permissions of user executing this script."
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
      return      #break out of function
   }
   #
   # We only get this far if $TaskInfo contains data
   # The $TaskInfo variable should contain data similar to the following:
   # LastRunTime        : 4/12/2022 4:47:47 PM    <--- should be within the last ??? minutes
   # LastTaskResult     : 0                       <--- 0=success, >0 can mean many things, currently running, failed, etc
   # NextRunTime        : 4/12/2022 4:52:52 PM
   # NumberOfMissedRuns : 0
   # TaskName           : nagios_passive_check
   # TaskPath           :
   # PSComputerName     :
   #
   #
   # figure out how long ago the task was run
   $age_in_hours = (New-TimeSpan -Start (Get-Date $TaskInfo.LastRunTime) -End (Get-Date)).TotalHours  #do some math to figure out number of hours between now and license expiration date
   $age_in_hours = [math]::round($age_in_hours,0)   	                        #truncate to 0 decimal places, nearest hour is close enough
   $LastTaskResult = $TaskInfo.LastTaskResult
   $LastRunTime    = $TaskInfo.LastRunTime
   #
   if ($verbose -eq "yes") { Write-Host "   TaskName=$TaskName, LastRunTime=$age_in_hours hours ago, LastTaskResult=$LastTaskResult" }
   #
   #
   if ( $age_in_hours -le '24' -and $LastTaskResult -eq '0') { 	#task is ok
      $exit_code = $OK						 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - Scheduled task $TaskName ran successfully at $LastRunTime"
   }	
   if ( $age_in_hours -gt '24' ) { 						#last task execution time was more than 24 hours ago
      $exit_code = $WARN 								 #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - Scheduled task $TaskName last execution time was was $age_in_hours hours ago at $LastRunTime."
   }	
   # Potential bug: what if the task is currently running?  The return code will be >0 for the brief period the task is running.
   if ( $LastTaskResult -gt '0' ) {
      $exit_code = $CRITICAL                          #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - Scheduled task $TaskName failed, please check status of this scheduled task"
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
   return      #break out of function
}
#
# call the above function
#
Get-Scheduled-Task-001




