# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-05-25	njeffrey	Script created



# xxxx - to be added - confirm email notification is enabled
# Future enhancement: Veeam BR 9.5 does not have a method to globally enable email notifications from powershell.  One workaround is New-VBRNotificationOptions on a job-by-job basis.
# https://forums.veeam.com/powershell-f26/enable-disable-global-e-mail-notifications-setting-t42726.html
function Get-Veeam-Health {
   #
   $verbose = "yes"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Veeam-Health function" }
   #
   # declare variables
   $service       = "Veeam health"
   #
   # Confirm the Veeam.Backup.Manager process is running
   #
   $fileToCheck = "C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Manager.exe"
   if (-Not(Test-Path $fileToCheck -PathType leaf)) { return }				#break out of function if file does not exist
   if (Test-Path $fileToCheck -PathType leaf) {						#check to see if the file exists
      $processToCheck = "Veeam.Backup.Manager"						#notice the process name does not have an .exe extension
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
   # At this point, we have confirmed the Veeam.Backup.Manager process is running
   # This check only needs to be run on an hourly basis, so check to see if a dummy file containing the output exists.
   $dummyFile = "$env:TEMP\nagios.veeam.backup.check.txt"
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
   ## Now confirm the VeeamPSSnapin PowerShell module is available
   ## We only do this section once per hour because adding a plugin is time consuming.
   ##
   #try {
   #   if ( (Get-PSSnapin -Name VeeamPSSnapin -ErrorAction SilentlyContinue) -eq $null ) { #confirm the Veeam powershell plugin is loaded
   #      Write-Host "Adding VeeamPSSnapin PowerShell snap in"
   #      try {
   #         Add-PSSnapin VeeamPSSnapin
   #      }
   #      catch {
   #         Write-Host "ERROR: Could not add VeeamPSSnapin PowerShell snap in"
   #         $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
   #         $plugin_output = "UNKNOWN - could not add VeeamPSSnapin PowerShell snap-in to check status of Veeam backup jobs"
   #         Submit-Nagios-Passive-Check
   #         return									#break out of function
   #      }
   #   }		
   #}
   #catch {
   #   $StatusCode = $_.Exception.Response.StatusCode.value__
   #}
   #
   # At this point, we have confirmed the Veeam process is running and the VeeamPSSnapin PowerShell module is loaded
   # Now we will connect to the Veeam server
   #
   try {
      Connect-VBRServer 								#connect to the Veeam server running on local machine
   }
   catch {
      Write-Host "ERROR: Could not connect to Veeam server with Connect-VBRServer PowerShell module"
      $plugin_state = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "UNKNOWN - Could not connect to Veeam server with Connect-VBRServer PowerShell module"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # At this point, we have a connection to the Veeam server.
   # Now we will check the license status.  
   # The output from a perpetual license will look like the following.  Please note the lack of an ExpirationDate.
   #   Get-VBRInstalledLicense
   #   Status                              : Valid
   #   ExpirationDate                      :
   #   Type                                : Perpetual
   #   Edition                             : Enterprise
   #   LicensedTo                          : BigCorp Inc
   #   SocketLicenseSummary                : {Veeam.Backup.PowerShell.Infos.VBRSocketLicenseSummary}
   #   InstanceLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRInstanceLicenseSummary
   #   CapacityLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRCapacityLicenseSummary
   #   SupportId                           :
   #   SupportExpirationDate               : 2025-09-23 12:00:00 AM
   #   AutoUpdateEnabled                   : False
   #   FreeAgentInstanceConsumptionEnabled : False
   #   CloudConnect                        : Disabled
   #
   # The output from an NFR license will look like the following.  Please note the lack of a SupportExpirationDate.
   #   Status                              : Valid
   #   ExpirationDate                      : 4/7/2021 12:00:00 AM
   #   Type                                : NFR
   #   Edition                             : EnterprisePlus
   #   LicensedTo                          : BigCorp Inc
   #   SocketLicenseSummary                : {Veeam.Backup.PowerShell.Infos.VBRSocketLicenseSummary}
   #   InstanceLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRInstanceLicenseSummary
   #   CapacityLicenseSummary              : Veeam.Backup.PowerShell.Infos.VBRCapacityLicenseSummary
   #   SupportId                           :
   #   SupportExpirationDate               :
   #   AutoUpdateEnabled                   : False
   #   FreeAgentInstanceConsumptionEnabled : True
   #   CloudConnect                        : Disabled
   #
   $veeam = @{}										#create an empty hash
   $x = Get-VBRInstalledLicense
   $veeam.Add("LicenseStatus",$x.Status)						#add license status to hash (HINT: do not surround $x.Status with quotes)
   $veeam.Add("LicenseType",$x.Type)							#add license type (Rental, Perpetual, Subscription, Evaluation, Free, Empty, NFR)
   #
   # NFR licenses do not have vendor support, so they do not have a SupportExpirationDate, so put in a dummy value of 0
   if ($x.SupportExpirationDate -eq $Null) { 
      $veeam.Add("SupportExpirationDate",0) 
      $veeam.Add("DaysToSupportExpirationDate",0) 
   }
   else { 
      $veeam.Add("SupportExpirationDate",$x.SupportExpirationDate) 					#add license expiration date to hash
      $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.SupportExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
      $x = [math]::round($x,0)   								#truncate to 0 decimal places, nearest day is close enough
      $veeam.Add("DaysToSupportExpirationDate",$x)                                                #add days until license expiry to hash
   }
   #
   # Perpetual licenses do not have an expiration date, so put in a dummy value of 99999
   if ($x.LicenseExpirationDate -eq $Null) { 
      $veeam.Add("LicenseExpirationDate",99999) 
      $veeam.Add("DaysToLicenseExpirationDate",99999) 
   }
   else { 
      $veeam.Add("LicenseExpirationDate",$x.ExpirationDate) 					#add license expiration date to hash
      $x = (New-TimeSpan -Start (Get-Date) -End (Get-Date $veeam.ExpirationDate)).TotalDays  #do some math to figure out number of days between now and license expiration date
      $x = [math]::round($x,0)   								#truncate to 0 decimal places, nearest day is close enough
      $veeam.Add("DaysToExpirationDate",$x)                                                #add days until license expiry to hash
   }
   #
   #
   # Get the version of Veeam
   $filename = "C:\Program Files\Veeam\Backup and Replication\Console\veeam.backup.shell.exe"
   if (Test-Path $filename -PathType leaf) { 
      $x = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$filename").FileVersion
      $veeam.Add("Version",$x)                                                #add veeam version and patch level to hash
   }
   #
   #
   # Check the size of the Veeam backup repositories to ensure they have at least 20% free space
   #
   if ($verbose -eq "yes") { Write-Host "Checking size of local veeam repositories" }
   $threshold_warn = 80									#warn     if repository space utilization is more than 80%
   $threshold_crit = 90									#critical if repository space utilization is more than 90%
   $repo_usage = ""									#temporary variable to concatenate all the repositories together
   $veeam.Add("RepoUsageWarn","")							#initialize hash value that will be used to send alert  
   $veeam.Add("RepoUsageCrit","")							#initialize hash value that will be used to send alert
   $repolist = Get-VBRBackupRepository | Where-Object {$_.Type -ne "SanSnapShotOnly"}	#skip SanSnapshotOnly repositories because they always return -1 for Info.CachedTotalSpace
   foreach ($repo in $repolist) {
      $repo_name     = $repo.Name
      $repo_type     = $repo.Type 							#WinLocal, SanSnapshotOnly
      $repo_total_tb = $repo.GetContainer().CachedTotalSpace.InBytes / 1TB		#this value is cached by Veeam and only updated occasionally, so may be out of date
      $repo_free_tb  = $repo.GetContainer().CachedFreeSpace.InBytes  / 1TB		#this value is cached by Veeam and only updated occasionally, so may be out of date
      $repo_used_tb  = $repo_total_tb - $repo_free_tb 					#do some math to figure out TB of used space in repository
      $repo_free_pct = $repo_free_tb / $repo_total_tb * 100				#do some math to figure out percentage of free space in repository	
      $repo_free_pct = [math]::round($repo_free_pct,0)   				#truncate to 0 decimal places, nearest percentage point is close enough
      $repo_total_tb = [math]::round($repo_total_tb,1)   				#truncate to 1 decimal places
      $repo_free_tb  = [math]::round($repo_free_tb,1)   				#truncate to 1 decimal places
      $repo_used_tb  = [math]::round($repo_used_tb,1)   				#truncate to 1 decimal places
      $repo_used_pct = 100 - $repo_free_pct 						#do some math to figure out percentage of used space in repository
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -ge $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "yes" } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -ge $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "yes" ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      if ( ($repo_used_pct -lt $threshold_warn) -and ($repo_used_pct -lt $threshold_crit) ) { $veeam['RepoUsageWarn'] = "no"  ; $veeam['RepoUsageCrit'] = "no"  } #set yes|no flag that applies globally to all repos for alerting purposes
      $x = "RepoName:" + $repo_name + " RepoUsage:" + $repo_used_tb + "/" +  $repo_total_tb + "TB(" + $repo_used_pct + "%)"
      $repo_usage = "$repo_usage, $x"						#concatenate all the repository details into a single string variable
   }
   $veeam.Add("RepoUsage",$repo_usage)							#add all repository usage details to a single hash element
   if ($verbose -eq "yes") { Write-Host $repo_usage }
   #
   #
   # Check the success/warning/failure status of the backup jobs
   # Get a list of the backup jobs
   #
   $success_count = 0									#initialize variable
   $failed_count = 0									#initialize variable
   $unknown_count = 0									#initialize variable
   $j = Get-VBRJob
   ForEach ($job in $j) {
      $s = $job.FindLastSession()
      $JobName = $s.JobName
      $Result  = $s.Result  								#Success, Failed
      $State   = $s.State 								#Stopped, Starting, Stopping, Working, Pausing, Resuming, Postprocessing
      if ($verbose -eq "yes") {Write-Host "   JobName:$JobName Result:$Result State:$State" }
      if ( ($Result -eq "Success") -or ($Result -eq "Warning") ) {			#Job result of Warning means it succeeded, but with warnings like slowdown or low disk space
         $success_count++								#increment counter
         $veeam_backups_success = "$veeam_backups_success $JobName"               	#build a string containing all the backup jobs that have Success/Warning status
         #if ($verbose -eq "yes") { Write-Host "   Found successful job $JobName" }
      } elseif ($Result -eq "Failed") {
         $failed_count++								#increment counter
         $veeam_backups_failed = "$veeam_backups_failed $JobName"               	#build a string containing all the backup jobs that have Failed status
         #if ($verbose -eq "yes") { Write-Host "   Found failed job $JobName" }
      } elseif ($Result -eq "None") {
         if ($verbose -eq "yes") { Write-Host "   Skipping job $JobName because it is in progress" }
         #Assume this in-progress job will succeed.  This avoids having a total job count of zero if the only job on the entire system is currently running.
         $success_count++								#increment counter
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
   Disconnect-VBRServer 								#disconnect from the Veeam server running on local machine
   #
   # Figure out if there are any problems to be reported
   # Put all the output into a single variable
   $plugin_output = "Version:" + $veeam.Version + " LicenseType:" + $veeam.LicenseType + " LicenseStatus:" + $veeam.LicenseStatus + " LicenseExpiration:" + $veeam.DaysToLicenseExpirationDate + "days SupportExpiration:" + $veeam.DaysToSupportExpirationDate + "days Successful_backups:" + $veeam.BackupSuccessCount + " Failed_backups:" + $veeam.BackupFailedCount + $veeam.RepoUsage
   #
   # This is the "everything is all good" message format
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -gt 30) -and ($veeam.BackupSuccessCount -gt 0) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 0			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # There are multiple versions of the "something is wrong" message format, depending on exactly what the problem is
   #
   #
   # send alert if there are zero scheduled backups
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -gt 30) -and ($veeam.BackupSuccessCount -eq 0) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) -and ($veeam.RepoUsageWarn -eq "no") -and ($veeam.RepoUsageCrit -eq "no")) {
      $plugin_state  = 3 			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service UNKNOWN - There are no scheduled backup jobs.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # send alert if license status is anything other than Valid
   #
   if ( ($veeam.LicenseStatus -ne "Valid") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam license is not valid.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # send alert if license is about to expire
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoLicenseExpirationDate -le 30) -and ($veeam.BackupFailedCount -eq 0) -and ($veeam.BackupUnknownCount -eq 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: License will expire in " + $veeam.DaysToLicenseExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # send alert if vendor support is about to expire (for license types that include support)
   #
   if ( ($veeam.LicenseStatus -eq "Valid") -and ($veeam.DaystoSupportExpirationDate -le 30) -and ( ($veeam.LicenseType -eq "Perpetual") -or ($veeam.LicenseType -eq "Rental") -or ($veeam.LicenseType -eq "Subscription")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: Support will expire in " + $veeam.DaysToSupportExpirationDate + " days.  $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }
   #
   # send alert if there are failed / unknown backup jobs and nearly full backup repository
   #
   if ( (($veeam.BackupFailedCount -gt 0) -or ($veeam.BackupUnknownCount -gt 0)) -and (($veeam.RepoUsageWarn -eq "yes") -or ($veeam.RepoUsageCrit -eq "yes")) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are failed/unknown Veeam backup jobs and nearly full backup repositories.  Failed job names are:" + $veeam.BackupFailedJobNames + " Unknown result job names are:" + $veeam.BackupUnknownJobNames + " , $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   #
   # send alert if there are failed backup jobs
   #
   if ( ($veeam.BackupFailedCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $x = $veeam.BackupFailedJobNames
      $plugin_output = "$service WARNING: there are failed Veeam backup jobs.  Failed job names are:" + $veeam.BackupFailedJobNames + " $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   #
   # send alert if there are backup jobs with a completion status of unknown
   #
   if ( ($veeam.BackupUnknownCount -gt 0) ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARNING: there are Veeam backup jobs with unknown results.  Job names are:" + $veeam.BackupUnknownJobNames + " , $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }  
   #
   # send alert if there backup repositories that are nearly full
   # 
   if ( ($veeam.RepoUsageCrit -eq "yes") ) {
      $plugin_state  = 2			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL: Veeam backup repository nearly full. " + $veeam.RepoUsage + ", $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
   if ( ($veeam.RepoUsageWarn -eq "yes") ) {
      $plugin_state  = 1			 					#0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN: Veeam backup repository nearly full. " + $veeam.RepoUsage + ", $plugin_output"
      if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
      $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return                                                            #break out of function
   }   
} 											#end of function
#
# call the above function
#
Get-Veeam-Health
