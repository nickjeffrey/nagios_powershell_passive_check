# CHANGE LOG
# ----------
# 2025-08-27	njeffrey	Script created


# NOTES
# -----

# The "xsServer" service should be running.  For example:
# "Get-Service -Name xsServer"
# Status   Name               DisplayName
# ------   ----               -----------
# Running  xsServer           xsServer
#
# 
# There should be at least 22 instances of the XSCommServer process running.  for example:
# Get-Process -Name XSCommServer
#
#Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName
#-------  ------    -----      -----     ------     --  -- -----------
#    324      23     9404      24956       0.47    700   0 XSCommServer
#    531      43    29992      53212       1.80   1088   0 XSCommServer
#    324      23     9396      25024       0.41   1700   0 XSCommServer
# <output snipped, should be at least 22 of these processes>


<#
.SYNOPSIS
    Nagios check for Windows service 'xsServer' and process 'XSCommServer'
    Requires at least 22 XSCommServer process instances to be running.

.EXAMPLE
    .\check_xspoc.ps1
#>


# Nagios exit codes
$OK       = 0
$WARN     = 1
$CRITICAL = 2
$UNKNOWN  = 3

# Hardcoded service name and process name
$ServiceName = "xsServer"
$ProcessName = "XSCommServer"
$MinProcessCount = 22
$CHECK_NAME = "XSPOC"

# Confirm the xsServer service exists and is running
try {
    # Check service status
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    $serviceStatus = $service.Status
}
catch {
    Write-Output "$CHECK_NAME CRITICAL: service '$ServiceName' not found, please confirm XSPOC is installed"
    exit $CRITICAL
}


# Check process existence
# There should be at least $MinProcessCount instances of the XSCommServer running,
# fewer processes may mean the XSPOC application has hung
#
$process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
$processCount = if ($process) { $process.Count } else { 0 }
$perf_data = "process_count:$processCount;;;;"


# Evaluate combined status with minimum process threshold
if ($serviceStatus -eq "Running" -and $processCount -ge $MinProcessCount) {
    Write-Output "$CHECK_NAME OK: service '$ServiceName' is running and '$ProcessName' process count is $processCount (>= $MinProcessCount). | $perf_data"
    exit $OK
}
elseif ($serviceStatus -ne "Running") {
    Write-Output "$CHECK_NAME CRITICAL: service '$ServiceName' is $serviceStatus , please investigate and make sure the service is running."
    exit $CRITICAL
}
elseif ($serviceStatus -eq "Running" -and $processCount -lt $MinProcessCount) {
    Write-Output "$CHECK_NAME WARN: service '$ServiceName' is $serviceStatus, but '$ProcessName' process count is $processCount , less than $MinProcessCount running '$ProcessName' processes indicates a possibly hung application. | $perf_data"
    exit $WARN
}
else {
    Write-Output "$CHECK_NAME UNKNOWN: Unable to determine status of XSPOC, please confirm '$ServiceName' service is running, and at least $MinProcessCount instances of '$ProcessName' process are running. | $perf_data"
    exit $UNKNOWN
}
