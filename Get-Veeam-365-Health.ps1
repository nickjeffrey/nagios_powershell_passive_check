# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created

function Get-Veeam-365-Health {
   #
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Veeam-365-Health function" }
   #
   # declare variables
   $service       = "Veeam 365 health"
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
         $plugin_state = 1 								 #0=ok 1=warn 2=critical 3=unknown
         $plugin_output = "$service WARN - process $processtoCheck is NOT running"
         if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
         if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
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
      $plugin_state  = 3 								#start with a value of UNKNOWN just in case the contents of $dummyFile are corrupt
      $plugin_output = Get-Content $dummyFile  						#read the contents of the text file into a variable
      if     ( $plugin_output -match "$service OK"       ) { $plugin_state = 0 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service WARN"     ) { $plugin_state = 1 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service CRITICAL" ) { $plugin_state = 2 }	#0=ok 1=warn 2=critical 3=unknown
      elseif ( $plugin_output -match "$service UNKNOWN"  ) { $plugin_state = 3 }	#0=ok 1=warn 2=critical 3=unknown
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
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
            $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
            $plugin_output = "UNKNOWN - could not import Veeam.Archiver.PowerShell PowerShell module check status of Veeam Office 365 backup jobs"
            if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
            if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
            return                                                            #break out of function
         }
      }		
   }
   catch {
      $StatusCode = $_.Exception.Response.StatusCode.value__
   }
   #
   # At this point, we have confirmed the Veeam for Office365 process is running and the Veeam.Archiver.PowerShell PowerShell module is loaded
   # Now we will connect to the Veeam server
   #
   try {
      Connect-VBOServer 								#connect to the Veeam server running on local machine
   }
   catch {
      Write-Host "ERROR: Could not connect to Veeam 365 server with Connect-VBOServer PowerShell snap in"
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not connect to Veeam server with Connect-VBRServer PowerShell snap in"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # At this point, we have a connection to the Veeam server.
   # Now we will check the license status.
   #
   $veeam = @{}										#create an empty hash
   $x = Get-VBOLicense
   $veeam.Add("LicenseStatus",$x.Status)						#add license status to hash (HINT: do not surround $x.Status with quotes)
   $veeam.Add("LicenseExpirationDate",$x.ExpirationDate)				#add license expiration date to hash
   $veeam.Add("SupportExpirationDate",$x.SupportExpirationDate)				#add support expiration date to hash
   #
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
      $repo_total_gb = $repo.Capacity /1GB						#
      $repo_total_gb = [math]::round($repo_total_gb,0)   	                        #truncate to 0 decimal places, nearest GB is close enough
      $repo_free_gb  = $repo.FreeSpace /1GB							#
      $repo_free_gb  = [math]::round($repo_free_gb,0)   	                        #truncate to 0 decimal places, nearest GB is close enough
      $repo_used_gb  = $repo_total_gb - $repo_free_gb 					#do some math to figure out GB of used space in repository
      $repo_free_pct = $repo_free_gb / $repo_total_gb * 100				#do some math to figure out percentage of free space in repository	
      $repo_free_pct = [math]::round($repo_free_pct,0)   	                        #truncate to 0 decimal places, nearest integer is close enough
      $repo_used_pct = 100 - $repo_free_pct 						#do some math to figure out percentage of used space in repository
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -ge $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "yes" } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -lt $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "no"  ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      $x = "RepoName:" + $repo_name + " RepoUsage:" + $repo_used_gb + "/" +  $repo_total_gb + "GB(" + $repo_used_pct + "%)"
      $repo_usage = "$repo_usage, $x"						#concatenate all the repository details into a single string variable
   }
   $veeam.Add("RepoUsage",$repo_usage)							#add all repository usage details to a single hash element
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
   $plugin_output = "LicenseStatus:" + $veeam.LicenseStatus + " LicenseExpiration:" + $veeam.DaysToLicenseExpirationDate + "days SupportExpiration:" + $veeam.DaysToSupportExpirationDate + "days Successful_backups:" + $veeam.BackupSuccessCount + " Failed_backups:" + $veeam.BackupFailedCount + " Unknown_backups:" + $veeam.BackupUnknownCount + $veeam.RepoUsage
   #
   # This is the "everything is all good" message format
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaysToLicenseExpirationDate -gt 30) -and ($veeam.EnableNotification -eq $True) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 0			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - All backups are successful.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # There are multiple versions of the "something is wrong" message format, depending on exactly what the problem is
   #
   if ( ($veeam.LicenseStatus -ne "Valid") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam license is not valid.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ( ($veeam.EnableNotification -ne "True") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam 365 email notifications are not enabled.  Please enable email notifications by clicking General Options, Notifications, Enable email notifications. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -le 30) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ( ($veeam.BackupFailedCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs and nearly full backup repositories.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if (  ($veeam.BackupUnknownCount -gt 0) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are unknown Veeam backup jobs and nearly full backup repositories.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   

   if ( ($veeam.BackupFailedCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $x = $veeam.BackupFailedJobNames
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs.  Failed job names are: $x, $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if ( ($veeam.BackupUnknownCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are Veeam backup jobs with unknown results.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if ( $veeam.RepoUsageCrit -eq "yes" ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam backup repository nearly full. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if ( $veeam.RepoUsageWarn -eq "yes" ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN: Veeam backup repository nearly full. $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if ( $veeam.DaystoLicenseExpirationDate -le 30 )  {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   if ( $veeam.DaystoSupportExpirationDate -le 30 )  {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: Support will expire in " + $veeam.DaysToSupportExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
}
#
# call the above function
#
Get-Veeam-365-Health