'''
This script processes login information from EMC Powermax storage systems.

Symmetrix ID            : 000197901042

Director Identification : FA-1D
Director Port           : 004
WWN Port Name           : 50000973b0104804

   Originator Node wwn : 200000051efd0ba0
   Originator Port wwn : 100000051efd0ba0
   Host QN             : N/A
   Host ID             : N/A
   ip Address          : N/A
   Protocol            : SCSI_FC
   User-generated Name : /
   FCID                : 798d40
   Logged In           : No
   On Fabric           : Yes
   Last Active Log-In  : 11:34:07 PM on Wed May 25,2022

   
   Originator Node wwn : 200000051efd3cb3
   Originator Port wwn : 100000051efd3cb3
   etc..
'''
$DebugPreference = 'SilentlyContinue'
$array_count = 0
$allLogins = [System.Collections.ArrayList]::new()
Get-ChildItem .\logins-*.txt | ForEach-Object {
    $filename = $_.Name
    Write-Debug "Processing file: $filename"
    $file = Get-Content $_ -Raw
    $textbolocks = ($file | Out-String) -split "\n\n"
    [string]$array = ''
    [string]$dirport = ''
    [string]$portnum = 0
    [string]$dirwwpn = ''
    foreach ($textbolock in $textbolocks) {
        
        $lines = $textbolock -split "\n"
        foreach($line in $lines) {
            if ($line -ne '') {
                if ($line -match 'Symmetrix ID\s+:\s+(\S+)') {
                $array = $matches[1]
                $array_count++
                break

                }elseif ($line -match 'Director Identification\s+:\s+(\S+)') {
                    # Director Identification : FA-1D
                    $dirport = ($matches[1]).Substring(3,2)
                }elseif ($line -match 'Director Port\s+:\s+(\S+)') {
                    $portnum = [int]$matches[1]
                }elseif ($line -match 'WWN Port Name\s+:\s+(\S+)') {
                    $dirwwpn = $matches[1]
                    break

                }elseif ($line -match 'Originator Node wwn\s+:\s+(\S+)') {
                    $login = (''|Select-Object array,dirport,dirwwpn,wwnn,wwpn,fcid,init_name,logged_in,on_fabric,logtime)
                    $login.wwnn = $matches[1]
                    $login.array = $array
                    $login.dirport = "$dirport-$portnum"
                    $login.dirwwpn = $dirwwpn
                }elseif ($line -match 'Originator Port wwn\s+:\s+(\S+)') {
                    $login.wwpn = $matches[1]
                }elseif ($line -match 'User-generated Name\s+:\s+(\S+)') {
                    if ($matches[1] -ne '/') {
                        $login.init_name = $matches[1]
                    }
                }elseif ($line -match 'FCID\s+:\s+(\S+)') {
                    $login.fcid = $matches[1]
                }elseif ($line -match 'Logged In\s+:\s+(\S+)') {
                    $login.logged_in = $matches[1]
                }elseif ($line -match 'On Fabric\s+:\s+(\S+)') {
                    $login.on_fabric = $matches[1]
                }elseif ($line -match 'Last Active Log-In\s+:\s+(.*)') {
                    $login.logtime = $matches[1]
                    Write-Debug $login|ConvertTo-Json 
                    [Void]$allLogins.Add($login)
                }

            }
        }
    }
}
Write-Host "Processed $($allLogins.Count) logins from $array_count arrays."
$allLogins|Export-Csv -Path pmax-logins.csv -NoTypeInformation
$allLogins|where {$_.wwpn -match 'c050760aa89f005[0-7]'}|ft