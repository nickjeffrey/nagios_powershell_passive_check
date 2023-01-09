# powershell function to perform check on local machine
# this script is called from the master nagios_passive_check.ps1 script
# the results of this check are submitted to the nagios server as a passive check via HTTP

# CHANGE LOG
# ----------
# 2022-07-28		njeffrey	Formatting changes
# 2022-07-28		njeffrey	Rewrite of https://github.com/willemdh/check_ms_iis_application_pool to implement as nagios passive check
# 2020-12-01            willemdh        Deleted MEM and CPU alert limits, added min sites limit and changed ApplicationPool search to case-sensitive
# 2018-04-11		willemdh	Fixed bug with multiple w3wp processes, cpu and memory parts and added warn/crit to perfdata (Yannick Charton)
# 2017-09-22		willemdh	Fixed bug with multiple w3wp processes
# 2017-09-15		willemdh	Fixed perfdata not working in some cases (Yannick Charton)
# 2017-02-18		willemdh	Cleanup and PSSharpening
# 2017-01-27		willemdh 	AppCmd method as workaround for hanging gci
# 2016-01-28		willemdh	appcount to the back

# TROUBLESHOOTING
# ---------------
# This check assumes that the IIS component "IIS Scripts and Tools" is installed, 
# and will crash with an error saying "root\WebAdministration namespace is missing" if that component is missing.

# Copyright:
#   This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published
#   by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program is distributed 
#   in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
#   PARTICULAR PURPOSE. See the GNU General Public License for more details. You should have received a copy of the GNU General Public 
#   License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires -Version 2.0


if ($verbose -eq "yes") { Write-Host "" ; Write-Host "Running Get-IIS-Application-Pool-Status" }

# Declare variables
$DebugPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
#$DebugPreference = 'Continue'
#$VerbosePreference = 'Continue'
$service             = "" 			#initialize name of check defined on nagios server
$plugin_output       = ""			#initialize variable



$IISStruct = New-Object -TypeName PSObject -Property @{
   StopWatch = [Diagnostics.Stopwatch]::StartNew()
   ApplicationPool = ''
   ProcessId = ''
   Process = ''
   PoolCount = ''
   PoolState = ''
   SitesCount = ''
   CurrentMemory = ''
   CurrentCpu = ''
   Duration = ''
   Exitcode = 3
   MinSites = 0
   AppPoolOnDemand = 0
   AppCmd = 0
   AppCmdList = ''
   ReturnString = 'UNKNOWN: Please debug the script...'
}

#region Functions

Function Write-Log {
   Param (
      [parameter(Mandatory=$true)][string]$Log,
      [parameter(Mandatory=$true)][ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Unknown')][string]$Severity,
      [parameter(Mandatory=$true)][string]$Message
   )
   $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
   $LocalScriptName = Split-Path -Path $myInvocation.ScriptName -Leaf
   If ( $Log -eq 'Undefined' ) {
      Write-Debug -Message "${Now}: ${LocalScriptName}: Info: LogServer is undefined."
   }
   ElseIf ( $Log -eq 'Verbose' ) {
      Write-Verbose -Message "${Now}: ${LocalScriptName}: ${Severity}: $Message"
   }
   ElseIf ( $Log -eq 'Debug' ) {
      Write-Debug -Message "${Now}: ${LocalScriptName}: ${Severity}: $Message"
   }
   ElseIf ( $Log -eq 'Output' ) {
      Write-Host "${Now}: ${LocalScriptName}: ${Severity}: $Message"
   }
   ElseIf ( $Log -match '^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])(?::(?<port>\d+))$' -or $Log -match '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$' ) {
      $IpOrHost = $log.Split(':')[0]
      $Port = $log.Split(':')[1]
      If ( $IpOrHost -match '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$' ) {
         $Ip = $IpOrHost
      }
      Else {
         $Ip = [Net.Dns]::GetHostAddresses($IpOrHost)[0].IPAddressToString
      }
      Try {
         $LocalHostname = ([Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower()
         $JsonObject = (New-Object -TypeName PSObject | 
            Add-Member -PassThru NoteProperty logsource $LocalHostname | 
            Add-Member -PassThru NoteProperty hostname $LocalHostname | 
            Add-Member -PassThru NoteProperty scriptname $LocalScriptName | 
            Add-Member -PassThru NoteProperty logtime $Now | 
            Add-Member -PassThru NoteProperty severity_label $Severity | 
            Add-Member -PassThru NoteProperty message $Message ) 
            If ( $psversiontable.psversion.major -ge 3 ) {
               $JsonString = $JsonObject | ConvertTo-Json
               $JsonString = $JsonString -replace "`n",' ' -replace "`r",' '
            }
            Else {
               $JsonString = $JsonObject | ConvertTo-Json2
            }               
            $Socket = New-Object -TypeName System.Net.Sockets.TCPClient -ArgumentList ($Ip,$Port) 
            $Stream = $Socket.GetStream() 
            $Writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList ($Stream)
            $Writer.WriteLine($JsonString)
            $Writer.Flush()
            $Stream.Close()
            $Socket.Close()
      }
      Catch {
         Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while trying to send message to logserver `"$Log`"."
      }
      Write-Verbose -Message "${Now}: ${LocalScriptName}: ${Severity}: Ip: $Ip Port: $Port JsonString: $JsonString"
   }
   ElseIf ($Log -match '^((([a-zA-Z]:)|(\\{2}\w+)|(\\{2}(?:(?:25[0-5]|2[0-4]\d|[01]\d\d|\d?\d)(?(?=\.?\d)\.)){4}))(\\(\w[\w ]*))*)') {
      If (Test-Path -Path $Log -pathType container){
          Write-Host "${Now}: ${LocalScriptName}: Error: Passed Path is a directory. Please provide a file."
          Exit 1
      }
      ElseIf (!(Test-Path -Path $Log)) {
         Try {
             $null = New-Item -Path $Log -Type file -Force
         } 
         Catch { 
            $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
            Write-Host "${Now}: ${LocalScriptName}: Error: Write-Log was unable to find or create the path `"$Log`". Please debug.."
            exit 1
         }
      }
      Try {
         "${Now}: ${LocalScriptName}: ${Severity}: $Message" | Out-File -filepath $Log -Append   
      }
      Catch {
         Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while writing to file `"$Log`". It might be locked."
      }
   }
}





Function ConvertTo-JSON2 {
   param   ( $MaxDepth = 4, $ForceArray = $false )
   Begin   { $Data = @() }
   Process { $Data += $_ }
   End{
      If ($Data.length -eq 1 -and $ForceArray -eq $false) {
         $Value = $Data[0]
      } 
      Else {
         $Value = $Data
      }
      If ($Value -eq $null) {
         Return 'null'
      }
      $DataType = $Value.GetType().Name
      Switch -Regex ($DataType) {
         'String'                { Return  "`"{0}`"" -f (Format-JSONString $Value ) }
         '(System\.)?DateTime'   { Return  "`"{0:yyyy-MM-dd}T{0:HH:mm:ss}`"" -f $Value }
         'Int32|Double'          { Return  "$Value" }
         'Boolean'               { Return  "$Value".ToLower() }
         '(System\.)?Object\[\]' {
            If ($MaxDepth -le 0) {
               Return "`"$value`""
            }
            $JsonResult = ''
            ForEach ($Elem in $Value) {
               If ($JsonResult.Length -gt 0) {
                  $JsonResult +=', '
               }
               $JsonResult += ($Elem | ConvertTo-JSON -MaxDepth ($MaxDepth -1))
               }
               Return '[' + $jsonResult + ']'
            }
            '(System\.)?Hashtable' {
               $JsonResult = ''
               ForEach ($Key in $Value.Keys) {
                  If ($JsonResult.Length -gt 0) {
                     $JsonResult +=', '
                  }
               $jsonResult += 
@'
    "{0}": {1}
'@ -f $Key , ($Value[$Key] | ConvertTo-JSON2 -MaxDepth ($MaxDepth -1) )
                }
                Return '{' + $jsonResult + '}'
            }
            default {
                If ($MaxDepth -le 0) {
                    Return  "`"{0}`"" -f (Format-JSONString $Value)
                }
                Return '{' +(($value | Get-Member -MemberType *property | ForEach-Object { 
@'
	"{0}": {1}
'@ -f $_.Name , ($value.($_.Name) | ConvertTo-JSON2 -maxDepth ($maxDepth -1))
                }) -join ', ') + '}'
            }
        }
    }
}




Function Initialize-Args {
   Param ( 
      [Parameter(Mandatory=$true)]$Args
   )
   try {
      For ( $i = 0; $i -lt $Args.count; $i++ ) { 
         $CurrentArg = $Args[$i].ToString()
         if ($i -lt $Args.Count-1) {
            $Value = $Args[$i+1];
            If ($Value.Count -ge 2) {
               foreach ($Item in $Value) {
                   $null = Test-Strings -String $Item
                }
             }
             else {
                $Value = $Args[$i+1];
                $null = Test-Strings -String $Value
             }
          } 
          else {
             $Value = ''
          }
          switch -regex -casesensitive ($CurrentArg) {
             '^(-A|--ApplicationPool)$' {
                 if ($value -match '^[a-zA-Z0-9. _-]+$') {
                    $IISStruct.ApplicationPool = $Value
                 }
                 else {
                    throw "Application Pool `"$value`" does not meet regex requirements."
                 }
                 $i++
              }
              '^(-APOD|--AppPoolOnDemand)$' {
                 if ($value -match '^[0-1]{1,2}$') {
                    $IISStruct.AppPoolOnDemand = $Value
                 }
                 else {
                    throw "Method `"$value`" does not meet regex requirements."
                 }
                 $i++
              }
              '^(-Appcmd|-AppCmd|-appcmd|-APPCMD)$' {
                 if ($value -match '^[0-1]{1,2}$') {
                    $IISStruct.Appcmd = $Value
                 }
                 else {
                    throw "Method `"$value`" does not meet regex requirements."
                 }
                 $i++
              }
              '^(-ms|-minsites)$' {
                 if ($value -match '^[0-9]{1,2}$') {
                    $IISStruct.MinSites = $Value
                 }
                 else {
                    throw "Method `"$value`" does not meet regex requirements."
                 }
                 $i++
             }
             '^(-h|--Help|--help)$' {
                #Write-Help
                Write-Host "Script parameters:"
                Write-Host "   -A --ApplicationPool MyApplicationPoolName"
                Write-Host "   -ms -minsites  Min site limit (default 0)"
                Write-Host "   -APOD --AppPoolOnDemand"
                Write-Host "   -Appcmd -AppCmd -appcmd -APPCMD"
                Write-Host "   -h  --help "
             }
             default {
                throw "Illegal arguments detected: $_"
            }
         }
      }
   } 
   catch {
      Write-Host "CRITICAL: Argument: $CurrentArg Value: $Value Error: $_"
      Exit 2
   }
}



Function Test-Strings {
   Param ( [Parameter(Mandatory=$true)][string]$String )
   $BadChars=@("``", '|', ';', "`n")
   $BadChars | ForEach-Object {
      If ( $String.Contains("$_") ) {
         Write-Host "Error: String `"$String`" contains illegal characters."
         Exit $IISStruct.ExitCode
      }
   }
   Return $true
} 



Function Invoke-CheckIISApplicationPool {
   Try {
      Import-Module -Name WebAdministration
      If (Get-ChildItem -Path IIS:\AppPools | Where-Object {$_.Name -ceq "$($IISStruct.ApplicationPool)"}) {
         $Sites = Get-WebConfigurationProperty "/system.applicationHost/sites/site/application[@applicationPool='$($IISStruct.ApplicationPool)' and @path='/']/parent::*" machine/webroot/apphost -name name
         $Apps = Get-WebConfigurationProperty "/system.applicationHost/sites/site/application[@applicationPool='$($IISStruct.ApplicationPool)' and @path!='/']" machine/webroot/apphost -name path
         $IISStruct.SitesCount = ($Sites,$Apps | ForEach-Object {$_.value}).count
         If ( $IISStruct.SitesCount -lt $IISStruct.MinSites ) { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" have `"$($IISStruct.SitesCount)`" Sites. Must be equal or more than `"$($IISStruct.MinSites)`"" }
            $IISStruct.PoolState = Get-ChildItem -Path IIS:\AppPools | Where-Object {$_.Name -eq "$($IISStruct.ApplicationPool)"} | Select-Object -Property State -ExpandProperty State
            If ( $IISStruct.PoolState -eq 'Started') {
               $IISStruct.ProcessId = Get-WmiObject -NameSpace 'root\WebAdministration' -class 'WorkerProcess' | Where-Object {$_.AppPoolName -match $IISStruct.ApplicationPool}  | Select-Object -Expand ProcessId
               If ( $IISStruct.ProcessId ) {
                  If ( @($($IISStruct.ProcessId)) -gt 1 ) {
                     $IISStruct.CurrentCpu  = 0
                     $IISStruct.CurrentMemory = 0
                     Get-WmiObject -NameSpace 'root\WebAdministration' -class 'WorkerProcess' | Where-Object {$_.AppPoolName -match $IISStruct.ApplicationPool} | Select-Object -Expand ProcessId | ForEach-Object {
                        $MyProcessId=$_
                        $IISStruct.Process = Get-Wmiobject -Class Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IdProcess -eq $MyProcessId } 
                        $MyCurrentCpu = $IISStruct.Process.PercentProcessorTime
                        $MyCurrentMemory = [Math]::Round(($IISStruct.Process.workingSetPrivate / 1MB),2)
                        $IISStruct.CurrentCpu += $MyCurrentCpu
                        $IISStruct.CurrentMemory += $MyCurrentMemory
                        Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id: $_ Percent CPU: $MyCurrentCpu Private Memory: $MyCurrentMemory"
                     }
                  } 
                  Else {
                     $IISStruct.Process = Get-Wmiobject -Class Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IdProcess -eq $IISStruct.ProcessId } 
                     $IISStruct.CurrentCpu = $IISStruct.Process.PercentProcessorTime
                     $IISStruct.CurrentMemory = [Math]::Round(($IISStruct.Process.workingSetPrivate / 1MB),2)
                  }
                  Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id(s): $($IISStruct.ProcessId) Percent CPU: $($IISStruct.CurrentCpu) Private Memory: $($IISStruct.CurrentMemory)"
                  $IISStruct.ExitCode = 0
                  $IISStruct.ReturnString = "OK: Application Pool `"$($IISStruct.ApplicationPool)`" with $($IISStruct.SitesCount) Applications. {CPU: $($IISStruct.CurrentCpu) %}{Memory: $($IISStruct.CurrentMemory) MB}"
                  $IISStruct.ReturnString += " | 'pool_cpu'=$($IISStruct.CurrentCpu)%; 'pool_memory'=$($IISStruct.CurrentMemory)MB; 'app_count'=$($IISStruct.SitesCount)"
               }
               Else {
                  If ( $IISStruct.AppPoolOnDemand = 1 ) {
                     $IISStruct.Process = 0
                     $IISStruct.CurrentCpu  = 0
                     $IISStruct.CurrentMemory = 0
                     $Sites = 0
                     $Apps = 0
                     $IISStruct.SitesCount = 0
                     $IISStruct.ExitCode = 0
                     $IISStruct.ReturnString = "OK:  Application Pool Started but no process is assigned yet `"$($IISStruct.ApplicationPool)`" with 0 Applications. {CPU: 0%}{Memory: 0MB}"
                     $IISStruct.ReturnString += " | 'pool_cpu'=0%; 'pool_memory'=0MB; 'app_count'=0"
                  }
                  Else { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" not found in WMI." }
               }
            }
         Else { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" is $($IISStruct.PoolState)." }
      }
      Else { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" does not exist." }
   }
   Catch {
      $IISStruct.ExitCode = 2
      $IISStruct.ReturnString = "CRITICAL: $_"
   }
}




Function Invoke-CheckIISWithAppCmd {
   Try {
      [xml]$AppCmdXml = & "$env:windir\system32\inetsrv\appcmd.exe" list apppools /xml
      $IISStruct.PoolCount = $AppCmdXml.appcmd.APPPOOL.Count
      If ( ! $IISStruct.PoolCount ) {
         $IISStruct.PoolState = $AppCmdXml.appcmd.APPPOOL.'state'
         if ( $AppCmdXml.appcmd.APPPOOL.'APPPOOL.NAME' -eq $IISStruct.ApplicationPool ) {
            $Found = $True
         }
         Else {
            $IISStruct.ReturnString = "CRITICAL: NO IIS application pool with name $($IISStruct.ApplicationPool) found. "
            $IISStruct.ExitCode = 2
         }
      }
      Else {
         $Found = $False
         $i = 0
         while ( ! $found -and $i -lt $IISStruct.PoolCount ) {
            If ( $AppCmdXml.appcmd.APPPOOL[$i].'APPPOOL.NAME' -eq $IISStruct.ApplicationPool ) {
               Write-Log Verbose Info "Application pool found: $($IISStruct.ApplicationPool)"
               $IISStruct.PoolState = $AppCmdXml.appcmd.APPPOOL[$i].'state'
               $Found = $True
            }
            Write-Log Verbose Info "Pool: $($AppCmdXml.appcmd.APPPOOL[$i].'APPPOOL.NAME')"
            $i++
         }
      }
      If ( $Found ) {
         If ( $IISStruct.PoolState -eq 'Started') {
            $IISStruct.ProcessId = Get-WmiObject -NameSpace 'root\WebAdministration' -class 'WorkerProcess' | Where-Object {$_.AppPoolName -match "^$($IISStruct.ApplicationPool)$"}  | Select-Object -Expand ProcessId
            If ( $IISStruct.ProcessId ) {
               $IISStruct.Process = get-wmiobject Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IdProcess -eq $IISStruct.ProcessId } 
               $IISStruct.CurrentCpu = $IISStruct.Process.PercentProcessorTime
               Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id: $($IISStruct.ProcessId) Percent CPU: $($IISStruct.CurrentCpu)"
               $IISStruct.CurrentMemory = [Math]::Round(($IISStruct.Process.workingSetPrivate / 1MB),2)
               Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id: $($IISStruct.ProcessId) Private Memory: $($IISStruct.CurrentMemory)"
               $IISStruct.ExitCode = 0
               $IISStruct.ReturnString = "OK: Application Pool `"$($IISStruct.ApplicationPool)`" with $($IISStruct.SitesCount) Applications. {CPU: $($IISStruct.CurrentCpu) %}{Memory: $($IISStruct.CurrentMemory) MB}"
               $IISStruct.ReturnString += " | 'pool_cpu'=$($IISStruct.CurrentCpu)%; 'pool_memory'=$($IISStruct.CurrentMemory)MB; 'app_count'=$($IISStruct.SitesCount)"
            }
            Else {
               If ( $IISStruct.AppPoolOnDemand = 1 ) {
                  $IISStruct.Process = 0
                  $IISStruct.CurrentCpu  = 0
                  $IISStruct.CurrentMemory = 0
                  $Sites = 0
                  $Apps = 0
                  $IISStruct.SitesCount = 0
                  $IISStruct.ExitCode = 0
                  $IISStruct.ReturnString = "OK:  Application Pool Started but no process is assigned yet `"$($IISStruct.ApplicationPool)`" with 0 Applications. {CPU: 0%}{Memory: 0MB}"
                  $IISStruct.ReturnString += " | 'pool_cpu'=0%; 'pool_memory'=0MB; 'app_count'=0"
               }
               Else { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" not found in WMI." }
            }
         }
         Else { Throw "Application Pool `"$($IISStruct.ApplicationPool)`" is $($IISStruct.PoolState)." }
      }
      Else { Throw "NO IIS application pool with name $($IISStruct.ApplicationPool) found. " }
   }   
   Catch {
      $IISStruct.ExitCode = 2
      $IISStruct.ReturnString = "CRITICAL: $_"
   }            
}

#endregion Functions




# ---------------- main body of script ------------------------------

# confirm script parameters were provided 
If ( $Args ) {
   If ( ! ( $Args[0].ToString()).StartsWith('$') ) {
      If ( $Args.count -ge 1 ) {
         Initialize-Args $Args
      }
   }
   Else {
      $IISStruct.ReturnString = 'CRITICAL: Script needs mandatory parameters to work.'
      $IISStruct.ExitCode = 2
   }
}
If ( $IISStruct.AppCmd -eq 0 ) { Invoke-CheckIISApplicationPool }   #call function to check IIS Application Pool     --ApplicationPool xxx
else                           { Invoke-CheckIISWithAppCmd      }   #call function to check IIS Application Command  --


$service = "IIS Application Pool $($IISStruct.ApplicationPool)"
$plugin_state = $IISStruct.ExitCode
$plugin_output = $IISStruct.ReturnString
if ($verbose -eq "yes") { Write-Host "   Submitting nagios passive check results: $plugin_output" }
if (Get-Command Submit-Nagios-Passive-Check -errorAction SilentlyContinue) { Submit-Nagios-Passive-Check}   	#call function to send results to nagios
return														#return to the nagios_passive_check.ps1 script


