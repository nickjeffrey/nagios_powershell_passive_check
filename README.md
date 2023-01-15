# nagios_powershell_passive_check
nagios passive check for Windows hosts using PowerShell

# Copy files to monitored host
Copy the *.ps1 and *.cfg files to c:\Program Files\nagios\libexec\

# Create Scheduled Task on monitored host
The assumption here is that the nagios server does not have a method to initiation connections to the monitored Windows hosts to perform active checks via SSH, WMI, NRPE, etc.  For this reason, a PowerShell script will execute from a Scheduled Task on the monitored Windows host(s) that submits passive checks to the nagios server via HTTP.

The PowerShell script runs in the security context of the LOCALSYSTEM account, which exists by default on all Windows hosts.  This is a good account to use because it does not require creation of local or domain user accounts on each Windows host, and the LOCALSYSTEM account has zero rights to any network resources, so it cannot be used for lateral system compromise or exploitation.

Create the scheduled task with a command similiar to:
```
schtasks.exe /create /S %computername% /RU SYSTEM /SC minute /MO 5 /TN nagios_passive_check /TR "powershell.exe c:\progra~1\nagios\libexec\nagios_passive_check.ps1"
```

# Create config file  on monitored host
You must edit the c:\progra~1\nagios\libexec\nagios_passive_check.cfg config file on the monitored host.  This config file will contain your site-specific details for the hostname/IP of the nagios server, the host_name of the monitored host as defined in the hosts.cfg file on the nagios server, and the username/password htpasswd credential that will be used to authenticate against the nagios CGI interface.  For example:
```
nagios_server=nagios.example.com
passive_host=server01.example.com
http_user=server01
htpasswd=SecretPass1
```


# Create apache htpasswd entries on nagios server
Each host submitting passive checks will need to provide credentials to access the nagios web interface.
For example, if there are 3 different hosts submitting passive checks, you would create the following HTTP credentials:
```
htpasswd -b /etc/nagios/htpasswd.users server01 SecretPass1
htpasswd -b /etc/nagios/htpasswd.users server02 SecretPass2
htpasswd -b /etc/nagios/htpasswd.users server03 SecretPass3
```



# Define commands in commands.cfg
Add the following to the commands.cfg file 
```
;
; Commands needed for stale host and service checks.
;
define command {
  ;Command changes a stale host from OK to UNKNOWN 0=ok 1=warn 2=critical 3=unknown
  ; yum install nagios-plugins-dummy
   command_name    stale_check
   command_line    /usr/local/nagios/libexec/check_dummy 3 "Passive check results are stale.  Please confirm the passive checks are being submitted."
}

define command {
   ;Command always returns true. Useful for keeping host status OK.
   command_name    check_null
   command_line    /bin/true
}


```
# Define service templates in services.cfg
```
define service{
        register                        0
        name                            passive-24x7-service
        use                             generic-service ; Name of service template to use
        check_command                   stale_check     ; When service becomes stale this check will be run to change the state to stale.
        max_check_attempts              1               ; Fail service immediately after first active stale check instead of waiting for several minutes
        check_interval                  1               ; A service is considered stale when freshness_threshold (in seconds) is reached.
                                                        ; Set check_interval to 1 to run the stale check as soon as the freshness threshold is reached.
        initial_state                   o               ; Assume initial service state is OK
        active_checks_enabled           0               ; Disable active checks of this service
        passive_checks_enabled          1               ; Enable passive checks and ensure it is checked for freshness.
        check_freshness                 1               ; Change default from off to on for passive checks
        freshness_threshold             900             ; Mark service as stale if no passive check results have been received for 60x15=900 seconds
        }

define service{
        register                        0
        name                            passive-8x5-service
        use                             generic-service ; Name of service template to use
        check_command                   stale_check     ; When service becomes stale this check will be run to change the state to stale.
        max_check_attempts              1               ; Fail service immediately after first active stale check instead of waiting for several minutes
        check_interval                  1               ; A service is considered stale when freshness_threshold (in seconds) is reached.
                                                        ; Set check_interval to 1 to run the stale check as soon as the freshness threshold is reached.
        initial_state                   o               ; Assume initial service state is OK
        active_checks_enabled           0               ; Disable active checks of this service
        passive_checks_enabled          1               ; Enable passive checks and ensure it is checked for freshness.
        check_freshness                 1               ; Change default from off to on for passive checks
        freshness_threshold             900             ; Mark service as stale if no passive check results have been received for 60x15=900 seconds
        notification_period             8x5
        }

```
# Define nagios contacts in contacts.cfg
You will need to define a contact in nagios for each host.  Unlike a typical nagios contact that is used for sending email alerts, these contacts are used to determine which credentials are used when submitting the passive check to nagios web interface.
```
define contact {                                                ;create a contact corresponding to htpasswd username
   use                            no-notify-contact             ;use template that has notification periods set to none
   contact_name                   myhost01                      ;this is a dummy contact only used to give the htpasswd credentials rights to the host_name
 }
define contact {                                                ;create a contact corresponding to htpasswd username
   use                            no-notify-contact             ;use template that has notification periods set to none
   contact_name                   myhost02                      ;this is a dummy contact only used to give the htpasswd credentials rights to the host_name
 }
define contact {                                                ;create a contact corresponding to htpasswd username
   use                            no-notify-contact             ;use template that has notification periods set to none
   contact_name                   myhost03                      ;this is a dummy contact only used to give the htpasswd credentials rights to the host_name
 }
 define contact {                                               ;create a contact corresponding to htpasswd username
   use                            no-notify-contact             ;use template that has notification periods set to none
   contact_name                   webserv01                     ;this is a dummy contact only used to give the htpasswd credentials rights to the host_name
 }

```


# services.cfg file 
You will need to add entries similar to the following to the services.cfg file on the nagios server.  Please adjust as appropriate for your environment.
```
##############################################
#
# PASSIVE CHECKS SUBMITTED FROM WINDOWS HOSTS
#
##############################################

# Define service for passive check for Veeam Office 365 health
define service {
   use                    passive-8x5-service
   host_name              veeam365.example.com 
   service_description    Veeam 365 health      ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               veam365               ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}


# Define service for passive check for Veeam Backup & Recovery health
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Veeam health          ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for CPU utilization
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    CPU util      ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for pagefile utilization
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    pagefile              ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Drive C: utilization
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Drive C:              ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for uptime
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    uptime                ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Disk SMART health metrics
define service {
   use                    passive-24x7-service
   host_name              myhost01.example.com
   service_description    Disk SMART status     ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Disk SCSI RAID controller health metrics
define service {
   use                    passive-24x7-service
   host_name              myhost01.example.com
   service_description    Disk RAID status      ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Disk latency and IOPS
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Disk IO               ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for failed login events in Windows Event Log
define service {
   use                    passive-24x7-service
   host_name              myhost01.example.com
   service_description    failed logins         ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Windows Defender antivirus status
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Defender Antivirus    ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Windows Firewall status
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    firewall              ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for Windows Update status
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Windows Update        ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for user logged in at Windows console
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    ConsoleLogon          ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

## Define service for passive check for status of Scheduled Task
define service {
   use                    passive-8x5-service
   host_name              myhost01.example.com
   service_description    Task GoogleUpdateTaskMachineCore    ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               myhost01              ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for IIS Application Pools
define service {
   use                    passive-8x5-service
   host_name              webserv01.example.com 
   service_description    IIS Application Pool DefaultAppPool   ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               webserv01             ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for IIS Application Pools
define service {
   use                    passive-8x5-service
   host_name              webserv01.example.com 
   service_description    IIS Application Pool MyAppPoolName  ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               webserv01             ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check MPIO disk paths iSCSI or FC
define service {
   use                    passive-8x5-service
   host_name              webserv01.example.com 
   service_description    MPIO disk paths ; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               webserv01             ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

# Define service for passive check for local SSL certificate store
define service {
   use                    passive-8x5-service
   host_name              webserv01.example.com 
   service_description    Certificate Expiry Date; Name of service passive check will reference when sending passive check results to nagios server
   contact_groups         admins                ; Who receives notifications for this service
   contacts               webserv01             ; This associates which contacts (and htpasswd users) are allowed to update this host and service.
}

###############################################
# END OF PASSIVE CHECKS
###############################################
```


# Troubleshooting
Run the Powershell script manually with: ```powershell.exe c:\progra~1\nagios\libexec\nagios_passive_check.ps1```

If you see this error message:
```
C:\Program Files\nagios\libexec\nagios_passive_check.ps1 is not digitally signed. You cannot run this script on the current system. 
For more information about running scripts and setting execution policy, see about_Execution_Policies at https://go.microsoft.com/fwlink/?LinkID=135170
```
It means that the Windows operating system has detected that the PowerShell script was downloaded from the internet.
You can work around this error by changing the default PowerShell execution policy, or by copying the files to a temporary location (ie c:\temp\), then create the files in the target directory using notepad copy/paste, which will make the files "locally created" instead of sourced from the internet, which will make PowerShell trust the files.

# Sample Output
<img src=images/passive_check.png>
