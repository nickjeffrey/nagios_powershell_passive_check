# nagios_powershell_passive_check
nagios passive check for Windows hosts using PowerShell

# Notes


# Create apache htpasswd entries
Each host submitting passive checks will need to provide credentials to access the nagios web interface.
For example, if there are 3 different hosts submitting passive checks, you would create the following HTTP credentials:
```
htpasswd -b /etc/nagios/htpasswd.users host1 SecretPass1
htpasswd -b /etc/nagios/htpasswd.users host2 SecretPass2
htpasswd -b /etc/nagios/htpasswd.users host3 SecretPass3
```


# Client side authentication
The powershell script will look for user credentials in the htpasswd.txt file located in the same directory as the powershell script.
For example, if the htpasswd entry created in the previous step was "SecretPass1", create a file called htpasswd.txt in the same directory as the powershell script with the following content:
```
SecretPass1
```

# Define commands in commands.cfg
Add the following to the commands.cfg file 
```
;
; Commands needed for stale host and service checks.
;
define command {
  ;Command changes a stale host from OK to UNKNOWN 0=ok 1=warn 2=critical 3=unknown
   command_name    stale_check
   command_line    /usr/local/nagios/libexec/check_dummy 3 "Passive check results are stale.  Please confirm the passive checks are being submitted."
}

define command {
   ;Command always returns true. Useful for keeping host status OK.
   command_name    check_null
   command_line    /bin/true
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
###############################################
# END OF PASSIVE CHECKS
###############################################
```
