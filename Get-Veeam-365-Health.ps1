# powershell function to perform check on local machine

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey   Script created for Veeam for MS365 version 4 (uses VeeamPSSnapin snap-in PowerShell module)
# 2022-10-14	njeffrey   Add error checks for Veeam O365 Community Edition, LicenseExpirationDate and SupportExpirationDate will be blank because these are unsupported products
# 2026-02-19   njeffrey   Add NCPA compatibility


function Get-Veeam-365-Health {
   #
   $verbose = "yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Veeam-365-Health function" }
   #
   # declare variables
   $service       = "Veeam 365 health"
   $warn_count    = 0
   $crit_count    = 0
   $warn_output   = ""
   $crit_output   = ""
   #
   # nagios exit codes
   $OK       = 0                            	
   $WARN     = 1                          	
   $CRITICAL = 2                        
   $UNKNOWN  = 3        
   #
   # Confirm the Veeam.Archiver.Servicer process is running
   #
   $fileToCheck = "C:\Program Files\Veeam\Backup365\Veeam.Archiver.Service.exe"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { return }				#break out of function if file does not exist
   if (Test-Path $fileToCheck -PathType leaf) {						#check to see if the file exists
      $processToCheck = "Veeam.Archiver.Service"					#notice the process name does not have an .exe extension
      if (Get-Process $processToCheck) {						#if the file exists, confirm process is running
         if ($verbose -eq "yes") {Write-Host "$processToCheck is running" }
      } else {
         if ($verbose -eq "yes") {Write-Host "WARN: $processToCheck is NOT running" }
         $exit_code = $WARN 								 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - process $processtoCheck is NOT running"
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
      }
   }
   #
   # At this point, we have confirmed the Veeam.Archiver.Service process is running
   # This check only needs to be run on an hourly basis, so check to see if a dummy file containing the output exists.
   $dummyFile = "$env:TEMP\nagios.veeam365.backup.check.txt"
   #
   # Delete the file if it is more than 60 minutes old
   if (Test-Path $dummyFile -PathType leaf) { 
      if ($verbose -eq "yes") { Write-Host "   checking age of flag file $dummyFile" }
      $lastWrite = (get-item $dummyFile).LastWriteTime
      $age_in_minutes = (New-TimeSpan -Start (Get-Date $lastWrite) -End (Get-Date)).TotalMinutes  #do some math to figure file age in minutes
      if ($age_in_minutes -gt 60) {
         if ($verbose -eq "yes") { Write-Host "   deleting obsolete dummy file $dummyFile" }
         Remove-Item $dummyFile
      }
   }
   # If the file exists, print the output and exit, which essentially skips this iteration of the check.
   if ((Test-Path $dummyFile -PathType leaf)) { 
      if ($verbose -eq "yes") { Write-Host "   using cached result from earlier check" }
      # figure out if the last check result was OK | WARN | CRITICAL
      $exit_code  = $UNKNOWN 								#start with a value of UNKNOWN just in case the contents of $dummyFile are corrupt
      $plugin_output = Get-Content $dummyFile  						#read the contents of the text file into a variable
      if     ( $plugin_output -match "$service OK"       ) { $exit_code = $OK       }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service WARN"     ) { $exit_code = $WARN     }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service CRITICAL" ) { $exit_code = $CRITICAL }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service UNKNOWN"  ) { $exit_code = $UNKNOWN  }	#0=ok 1=warn 2=critical 3=unknown
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
      return										#break out of function
   }				
   #
   # If we get this far, no dummy text file exists with the previous check output, so perform the check.
   #
   # Now confirm the VeeamPSSnapin PowerShell module is available
   #
   try {
      if ( (Get-Module -Name Veeam.Archiver.PowerShell -ErrorAction SilentlyContinue) -eq $null ) { #confirm the Veeam powershell plugin is loaded
         Write-Host "Importing Veeam.Archiver.PowerShell PowerShell module"
         try {
            Import-Module Veeam.Archiver.PowerShell
         }
         catch {
            Write-Host "ERROR: Could not import Veeam.Archiver.PowerShell PowerShell module"
            $exit_code = $UNKNOWN 			 					#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "UNKNOWN - could not import Veeam.Archiver.PowerShell PowerShell module check status of Veeam Office 365 backup jobs"
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
            return                                                            #break out of function
         }
      }		
   }
   catch {
      $StatusCode = $_.Exception.Response.StatusCode.value__
   }
   #
   # At this point, we have confirmed the Veeam for MS365 process is running and the Veeam.Archiver.PowerShell PowerShell module is loaded
   # Now we will connect to the Veeam server
   #
   try {
      Connect-VBOServer                                    #connect to the Veeam server running on local machine
   }
   catch {
      Write-Host "ERROR: Could not connect to Veeam 365 server with Connect-VBOServer PowerShell snap in"
      $exit_code = $UNKNOWN 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not connect to Veeam server with Connect-VBRServer PowerShell snap in"
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
      return                                                            #break out of function
   }
   #
   # At this point, we have a connection to the Veeam server.
   # Now we will check the license status.
   #
   $veeam = @{}										#create an empty hash
   $x = Get-VBOLicense
   $veeam.Add("LicenseStatus",$x.Status)						#add license status to hash (HINT: do not surround $x.Status with quotes)
   $veeam.Add("LicenseType",$x.Type)							#add license type to hash
   $veeam.Add("LicenseExpirationDate",$x.ExpirationDate)				#add license expiration date to hash
   $veeam.Add("SupportExpirationDate",$x.SupportExpirationDate)				#add support expiration date to hash
   #
   # If the license type is "Community" and the license status is "Valid", the ExpirationDate and SupportExpirationDate will be blank, because those products have no vendor support.
   # Put in dummy values of 9999 days from now to avoid undef errors
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.LicenseType -eq "Community") -and ($veeam.LicenseExpirationDate -eq $Null) -and ($veeam.SupportExpirationDate -eq $Null) ) { 
      Write-Host "Adding dummy values to LicenseExpirationDate and SupportExpirationDate for Community edition"
      $veeam.LicenseExpirationDate = (Get-Date).AddDays(9999)
      $veeam.SupportExpirationDate = (Get-Date).AddDays(9999)
   }
   # do some math to figure out days until license expiration
   #
   $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.LicenseExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
   $x = [math]::round($x,0)   				                                #truncate to 0 decimal places, nearest day is close enough
   $veeam.Add("DaysToLicenseExpirationDate",$x)                                         #add days until license expiry to hash
   #
   # do some math to figure out days until support expiration (typically the same day as license expiration)
   #
   $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.SupportExpirationDate)).TotalDays  #do some math to figure out number of days between now and support expiration date
   $x = [math]::round($x,0)   				                                #truncate to 0 decimal places, nearest day is close enough
   $veeam.Add("DaysToSupportExpirationDate",$x)                                         #add days until license expiry to hash
   #
   #
   # Confirm Veeam email reporting is enabled
   #
   $x = Get-VBOEmailSettings
   $veeam.Add("EnableNotification",$x.EnableNotification)				#add license status to hash (HINT: do not surround $x.Status with quotes)
   #
   #
   #
   #
   # Check the size of the Veeam backup repositories to ensure they have at least 20% free space
   #
   $threshold_warn = 80									#warn     if repository space utilization is more than 80%
   $threshold_crit = 90									#critical if repository space utilization is more than 90%
   $repo_usage = ""									#temporary variable to concatenate all the repositories together
   $veeam.Add("RepoUsageWarn","")							#initialize hash value that will be used to send alert
   $veeam.Add("RepoUsageCrit","")							#initialize hash value that will be used to send alert
   $repolist = Get-VBORepository
   foreach ($repo in $repolist) {
      $repo_name     = $repo.Name
      $repo_total_gb = $repo.Capacity /1GB						  #
      $repo_total_gb = [math]::round($repo_total_gb,0)   	  #truncate to 0 decimal places, nearest GB is close enough
      $repo_free_gb  = $repo.FreeSpace /1GB						  #
      $repo_free_gb  = [math]::round($repo_free_gb,0)   	     #truncate to 0 decimal places, nearest GB is close enough
      $repo_used_gb  = $repo_total_gb - $repo_free_gb 		  #do some math to figure out GB of used space in repository
      $repo_free_pct = $repo_free_gb / $repo_total_gb * 100	  #do some math to figure out percentage of free space in repository	
      $repo_free_pct = [math]::round($repo_free_pct,0)   	  #truncate to 0 decimal places, nearest integer is close enough
      $repo_used_pct = 100 - $repo_free_pct 						  #do some math to figure out percentage of used space in repository
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -ge $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "yes" } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -lt $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "no"  ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      $x = "RepoName:" + $repo_name + " RepoUsage:" + $repo_used_gb + "/" +  $repo_total_gb + "GB(" + $repo_used_pct + "%)"
      $repo_usage = "$repo_usage, $x"                                                   #concatenate all the repository details into a single string variable
   }
   $veeam.Add("RepoUsage",$repo_usage)                                                  #add all repository usage details to a single hash element
   if ($verbose -eq "yes") { Write-Host $repo_usage }
   #
   # Check the success/warning/failure status of the backup jobs
   #
   # Get a list of the backup jobs
   #
   $success_count = 0
   $failed_count = 0
   $unknown_count = 0
   $job = Get-VBOJob
   ForEach ($j in $job.Name) {
      $jobsession = Get-VBOJobSession -Job $job -last                                  #get the details of the most recent run of each backup job
      $JobName = $jobsession.JobName
      $Result  = $jobsession.Status
      if ($verbose -eq "yes") {Write-Host "   JobName:$JobName Status:$Result " }
      if ( ($Result -eq "Success") -or ($Result -eq "Warning") ) {                      #Job result of Warning means it succeeded, but with warnings like slowdown or low disk space
         $success_count++                                                               #increment counter
         $veeam_backups_success = "$veeam_backups_success $JobName"                     #build a string containing all the backup jobs that have Success/Warning status
         if ($verbose -eq "yes") { Write-Host "Found successful job $JobName" }
      } elseif ($Result -eq "Failed") {
         $failed_count++                                                                #increment counter
         $veeam_backups_failed = "$veeam_backups_failed $JobName"                       #build a string containing all the backup jobs that have Failed status
         if ($verbose -eq "yes") { Write-Host "Failed:$veeam_backups_failed" } 
      } else {
         $unknown_count++                                                               #increment counter
         $veeam_backups_unknown = "$veeam_backups_unknown $JobName"                    #build a string containing all the backup jobs that we could not determine the status of
         if ($verbose -eq "yes") { Write-Host "Unknown:$veeam_backups_unknown" }
      }
   }
   # put all the job details in the $veeam hash so we have a single place with all the data
   $veeam.Add("BackupSuccessCount"    , $success_count)  
   $veeam.Add("BackupFailedCount"     , $failed_count)  
   $veeam.Add("BackupUnknownCount"    , $unknown_count)  
   $veeam.Add("BackupSuccessJobNames" , $veeam_backups_success)  
   $veeam.Add("BackupFailedJobNames"  , $veeam_backups_failed)  
   $veeam.Add("BackupUnknownJobNames" , $veeam_backups_unknown)  
   #
   Disconnect-VBOServer 
   #
   # Figure out if there are any problems to be reported
   # get all the common info into a single variable
   $plugin_output = "LicenseStatus:" + $veeam.LicenseStatus + " LicenseType:" + $veeam.LicenseType + " LicenseExpiration:" + $veeam.DaysToLicenseExpirationDate + "days SupportExpiration:" + $veeam.DaysToSupportExpirationDate + "days Successful_backups:" + $veeam.BackupSuccessCount + " Failed_backups:" + $veeam.BackupFailedCount + " Unknown_backups:" + $veeam.BackupUnknownCount + $veeam.RepoUsage
   #
   # This is the "everything is all good" message format
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaysToLicenseExpirationDate -gt 30) -and ($veeam.EnableNotification -eq $True) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $exit_code  = $OK			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - All backups are successful.  $plugin_output"
   }
   #
   # There are multiple versions of the "something is wrong" message format, depending on exactly what the problem is
   #
   if ( ($veeam.LicenseStatus -ne "Valid") ) {
      $crit_count++
      $crit_output = "$crit_output Veeam license is not valid."
   }
   if ( ($veeam.EnableNotification -ne "True") ) {
      $crit_count++
      $crit_output = "$crit_output Veeam 365 email notifications are not enabled.  Please enable email notifications by clicking General Options, Notifications, Enable email notifications."
   }
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -le 30) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) ) {
      $warn_count++
      $warn_output = "$warn_output License will expire in " + $veeam.DaysToLicenseExpirationDate + " days."
   }
   if ( ($veeam.BackupFailedCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $warn_count++
      $warn_output = "$warn_output There are failed Veeam backup jobs and nearly full backup repositories."
   }   
   if (  ($veeam.BackupUnknownCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $warn_count++
      $warn_output = "$warn_output There are unknown Veeam backup jobs and nearly full backup repositories."
   }   
   if ( ($veeam.BackupFailedCount -gt 0) ) {
      $warn_count++
      $x = $veeam.BackupFailedJobNames
      $warn_output = "$warn_output There are failed Veeam backup jobs.  Failed job names are: $x ."
   }   
   if ( ($veeam.BackupUnknownCount -gt 0) ) {
      $warn_count++
      $warn_output = "$warn_output There are Veeam backup jobs with unknown results."
   }   
   if ( $veeam.RepoUsageCrit -eq "yes" ) {
      $crit_count++
      $crit_output = "$crit_output Veeam backup repository nearly full."
   }   
   if ( ($veeam.RepoUsageWarn -eq "yes") -and ($veeam.RepoUsageCrit -eq "no") ) {
      $warn_count++
      $warn_output = "$warn_output Veeam backup repository nearly full."
   }   
   if ( $veeam.DaystoLicenseExpirationDate -le 30 )  {
      $warn_count++
      $warn_output = "$warn_output License will expire in " + $veeam.DaysToLicenseExpirationDate + " days."
   }
   if ( $veeam.DaystoSupportExpirationDate -le 30 )  {
      $warn_count++
      $warn_output = "$warn_output Support will expire in " + $veeam.DaysToSupportExpirationDate + " days."
   }
   #
   # prepend all the $crit_output and $warn_output messages to the $plugin_output
   #
   if ( ($crit_count -gt 0) -and ($warn_count -gt 0) ) { 
      $exit_code = $CRITICAL
      $plugin_output = "$service CRITICAL $crit_output $warn_output $plugin_output" 
   }
   if ( ($crit_count -gt 0) -and ($warn_count -eq 0) ) { 
      $exit_code = $CRITICAL
      $plugin_output = "$service CRITICAL $crit_output $plugin_output" 
   }
   if ( ($crit_count -eq 0) -and ($warn_count -gt 0) ) { 
      $exit_code = $WARN
      $plugin_output = "$service WARN $warn_output $plugin_output" 
   }
   if ( ($crit_count -eq 0) -and ($warn_count -eq 0) ) { 
      $exit_code = $OK
      $plugin_output = "$service OK $plugin_output" 
   }
   #
   # print output
   #
   $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
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
# call the above function
#
Get-Veeam-365-Health

