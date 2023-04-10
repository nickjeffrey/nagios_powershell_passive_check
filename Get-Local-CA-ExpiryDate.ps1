
# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2023-02-05	njeffrey	Script created
# 2023-04-10	njeffrey	Change $plugin_output_maxsize from 8192 to 4096 to avoid cluttering web interface





# FUTURE ENHANCEMENTS
# -------------------


# TROUBLESHOOTING
# --------------- 






# NOTES
# -----
# Needs PKITools module installed https://www.powershellgallery.com/packages/PKITools/1.6
# Needs Certification Authority role installed in Windows
# Needs name of local CA, which can be found in Control Panel, Administrative Tools, Certification Authority, or powershell command: Get-CertificatAuthority

# For example:
# powershell.exe Get-CertificatAuthority
#distinguishedName : {CN=mydomain-MYCA1-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com}
#Path              : LDAP://CN=mydomain-MYCA1-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com
#
#distinguishedName : {CN=mydomain-MYCA2-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com}
#Path              : LDAP://CN=mydomain-MYCA2-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com


function Get-Local-CA-ExpiryDate {
   #
   $verbose = "yes"
   #$verbose = "no"
   if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-Local-CA-ExpiryDate" }
   #
   # declare variables
   $CAlocation = "NYXDC3\nyx-NYXDC3-CA"
   $service = "Local CA Expiry Date"
   $verbose = "yes"
   $servers = @()   #create empty array
   $DaysUntilExpiryWarningThreshold = 60
   $Certificates_NotExpired         = ""   #start with blank list to be used in output
   $Certificates_SoonToExpire       = ""   #start with blank list to be used in output
   $Certificates_AlreadyExpired     = ""   #start with blank list to be used in output
   $hash = @{}                             #create an empty hash to hold all the certificate details
   #
   #
   #
   # This check only needs to be run on a daily basis, so check to see if a dummy file containing the output exists.
   $DestDir = "C:\temp"
   If(!(test-path -PathType container $DestDir)) {
      New-Item -ItemType Directory -Path $DestDir
   }
   #$dummyFile = "$env:TEMP\nagios.local.ca.expirydate.check.txt"  #cannot use ENV variable because this script runs as 2 different users with different ENV
   $dummyFile = "c:\temp\nagios.local.ca.expirydate.check.txt"
   #
   # Delete the file if it is more than 60*24 minutes old
   if (Test-Path $dummyFile -PathType leaf) { 
      if ($verbose -eq "yes") { Write-Host "   checking age of flag file $dummyFile" }
      $lastWrite = (get-item $dummyFile).LastWriteTime
      $age_in_minutes = (New-TimeSpan -Start (Get-Date $lastWrite) -End (Get-Date)).TotalMinutes  #do some math to figure file age in minutes
      if ($age_in_minutes -gt 1440) {
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
      if ($verbose -eq "yes") { Write-Host $plugin_output }
      if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
      return										#break out of function
   }				
   #
   # If we get this far, no dummy text file exists with the previous check output, so perform the check.
   #
   #
   # check to see if the Get-IssuedCertificate Powershell module exists
   #
   # to be written...
   #
   # $CACert = Get-IssuedCertificate -ExpireInDays 60 -Properties "Issued Request ID","Issued Common Name","Certificate Expiration Date","Certificate Hash","Certificate Template"  | Select * | Where-Object { ($_."Issued Common Name" -like 'SWCB*' -or $_."Issued Common Name" -like 'aix*' -or $_."PSComputerName" -ne 'SWCBENTCA.wcbsask.com' ) }   
   #$CACert = Get-IssuedCertificate -ExpireInDays 60 -Properties "Issued Request ID","Issued Common Name","Certificate Expiration Date"  | Select *
   $CACert = Get-IssuedCertificate -CAlocation $CAlocation
   foreach ($x in $CACert) {
      Write-Host $x."Issued Request ID" $x."Issued Common Name" $x."Certificate Template" $x."Certificate Hash" $x."Certificate Expiration Date"
      #
      # Save the interesting certificate attributes to a 2-levels-deep hash
      #
      $IssuedRequestID = $x."Issued Request ID" | Out-String
      $IssuedCommonName = $x."Issued Common Name" | Out-String
      $hash.$IssuedRequestID = @{}  #create a nested hash using the (supposedly unique) thumbprint of the Issued Request ID as a hash key
      $hash.$IssuedRequestID.IssuedRequestID           = $x."Issued Request ID"           | Out-String
      $hash.$IssuedRequestID.IssuedCommonName          = $x."Issued Common Name"          | Out-String
      $hash.$IssuedRequestID.CertificateTemplate       = $x."Certificate Template"        | Out-String
      $hash.$IssuedRequestID.CertificateHash           = $x."Certificate Hash"            | Out-String
      $hash.$IssuedRequestID.CertificateExpirationDate = $x."Certificate Expiration Date" | Out-String
      #
      #
      # Figure out how many days until certificate expiration
      #
      $DaysUntilExpiry = (New-TimeSpan -Start (Get-Date) -End (Get-Date $x."Certificate Expiration Date")).TotalDays  #do some math to figure out number of days between now and license expiration date
      $DaysUntilExpiry = [math]::round($DaysUntilExpiry,0)   			                 # truncate to 0 decimal places, nearest day is close enough
      $hash.$IssuedRequestID.DaysUntilExpiry = $DaysUntilExpiry  #add to hash
      Write-Host "Days until expiry:" $DaysUntilExpiry
      #
      # find certificates that will NOT expire soon
      #
      if ($DaysUntilExpiry -gt $DaysUntilExpiryWarningThreshold ) {
         $Certificates_NotExpired = "$Certificates_NotExpired OK: certificate $IssuedRequestID $IssuedCommonName is ok, expiring in $DaysUntilExpiry days."
         $Certificates_NotExpired = $Certificates_NotExpired -replace "`t|`n|`r",""  #replace newlines with blanks
      }
      #
      # find certificates that will expire soon, but are not yet expired
      #
      if ( ($DaysUntilExpiry -lt $DaysUntilExpiryWarningThreshold) -And ($DaysUntilExpiry -ge 0) ) {
         $Certificates_SoonToExpire = "$Certificates_SoonToExpire WARN: certificate $IssuedRequestID $IssuedCommonName will expire in $DaysUntilExpiry days."
         $Certificates_SoonToExpire = $Certificates_SoonToExpire -replace "`t|`n|`r",""  #replace newlines with blanks
      }
      #
      # find certificates that are already expired
      #
      if ($DaysUntilExpiry -lt 0 ) {
         $DaysSinceExpiry = $DaysUntilExpiry * -1 #convert negative number to positive number
         $Certificates_AlreadyExpired = "$Certificates_AlreadyExpired CRITICAL: certificate $IssuedRequestID $IssuedCommonName already expired $DaysSinceExpiry days ago."
         $Certificates_AlreadyExpired = $Certificates_AlreadyExpired -replace "`t|`n|`r",""  #replace newlines with blanks
      }
   }
   #
   #
   # provide some verbose output for debugging
   #
   if ($verbose -eq "yes") {
      Write-Host ""
      Write-Host "Certificates not expired:"
      Write-Host $Certificates_NotExpired
      Write-Host ""
      Write-Host "Certificates soon to expire:"
      Write-Host $Certificates_SoonToExpire
      Write-Host ""
      Write-Host "Certificates already expired:"
      Write-Host $Certificates_AlreadyExpired
   }
   #
   #
   # Figure out what result will be sent to nagios
   #
   if ( $Certificates_NotExpired -match "\S" ) {   # \S means any non-whitespace character
      $plugin_state  = 0			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service OK - $Certificates_NotExpired"
   }
   if ( $Certificates_SoonToExpire -match "\S" ) {
      $plugin_state  = 1			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service WARN - $Certificates_SoonToExpire $Certificates_NotExpired"
   }
   if ( $Certificates_AlreadyExpired -match "\S" ) {
      $plugin_state  = 3			     #0=ok 1=warn 2=critical 3=unknown
      $plugin_output = "$service CRITICAL - $Certificates_AlreadyExpired $Certificates_SoonToExpire $Certificates_NotExpired"  #note that we include CRITICAL messages first, followed by WARN messages, followed by OK
   }
   #
   # send the output to nagios
   #
   $plugin_output_maxsize = 4096
   if ($plugin_output.Length -gt $plugin_output_maxsize) { 
      if ($verbose -eq "yes") { Write-Host "---truncating output for OK messages due to excessive message size--- " }
      $plugin_output = $plugin_output -replace "is ok, expiring in \d+ days",""  #shorten the OK messages
   }
   if ($plugin_output.Length -gt $plugin_output_maxsize) { 
      if ($verbose -eq "yes") { Write-Host "---truncating output for WARN messages due to excessive message size --- " }
      $plugin_output = $plugin_output -replace "will expire in \d+ days",""  #shorten the WARN messages
   }
   if ($plugin_output.Length -gt $plugin_output_maxsize) { 
      if ($verbose -eq "yes") { Write-Host "---truncating output for CRITICAL messages due to excessive message size --- " }
      $plugin_output = $plugin_output -replace "already expired \d+ days ago",""  #shorten the CRITICAL messages
   }
   if ($plugin_output.Length -gt $plugin_output_maxsize) { 
      if ($verbose -eq "yes") { Write-Host "---truncating output for all messages due to excessive message size --- " }
      $plugin_output = $plugin_output -replace "already expired \d+ days ago",""  #shorten the WARN messages
      $plugin_output = $plugin_output.Substring(0,$plugin_output_maxsize-50)  #truncate message so it does not exceed nagios maximum message size  
      $plugin_output = "$plugin_output MESSAGE TRUNCATED DUE TO EXCESSIVE LENGTH"
   }
   if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
   $plugin_output | Out-File $dummyFile						#write the output to a dummy file that can be re-used to speed up subsequent checks
   if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   #call function to send results to nagios
   return   
} 		#end of function
#
# call the above function
#
Get-Local-CA-ExpiryDate
