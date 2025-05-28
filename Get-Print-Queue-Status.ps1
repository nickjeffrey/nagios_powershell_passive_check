# powershell function to perform check on local machine


# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created
# 2025-05-15	njeffrey	Add performance counters

function Get-Print-Queue-Status {
   #
   $verbose = "no"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Print-Queue-Status function" }
   #
   # declare variables
   $service         = "PrintQueues"				#name of check defined on nagios server
   $threshold_warn  = 5                                         #warning threshold for outstanding print jobs
   $bad_queue_count = 0 					#initialize counter variable
   $all_queue_count = 0 					#initialize counter variable
   $plugin_output   = ""					#initialize variable
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3                         
   #
   try { 
      # Get the names of all the print queues
      $queues = Get-CimInstance -ClassName Win32_PerfFormattedData_Spooler_PrintQueue | Where-Object { $_.Name -ne "_Total" }
      #
      # returned info looks like:
      # Name  
      # ----  
      # Fax
      # HPF1D76C (HP OfficeJet Pro 8720)
      # OneNote (Desktop)
      # Webex Document Loader
   }
   catch { 
      Write-Host "ERROR: insufficient permissions to run Get-CimInstance powershell module.  Exiting script."
      exit 
   }
   #
   # if we get this far, the $queues variable contains all the details about the different print queues, including how many jobs are in each queue
   #
   foreach ($queue in $queues) {
      $all_queue_count++  			#count up the total number of all print queues
      if ($queue.Jobs -ge $threshold_warn) { 
         $bad_queue_count++ 			#increment counter 
         $plugin_output = "$plugin_output, PrintQueue:" + $queue.Name + " has " + $queue.Jobs + " outstanding."  #append each queue with pending jobs to a string
      }
   }
   # 
   # At this point, we have details on all the print queues.
   # Now we check to see if there are any outstanding jobs in any of the print queues
   #
   if ( $bad_queue_count -gt 0 ) {
      $common_output_data = "$service WARN - found $bad_queue_count print queues with outstanding jobs.  $plugin_output"
      $exit_code = $WARN	 								 #0=ok 1=warn 2=critical 3=unknown
   }
   if ( $bad_queue_count -eq 0 ) {  
      $plugin_output = "all $all_queue_count print queues are ok"
      $common_output_data = "$service OK $plugin_output"
      $exit_code = $OK	 								 #0=ok 1=warn 2=critical 3=unknown
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
   return                                                            #break out of function

} 											#end of function
#
# call the above function
#
Get-Print-Queue-Status

