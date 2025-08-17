function Get-AllPmaxLogins {
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("Sid")]
        [string[]]$arrayIds = @()
    )
    begin {
        $timeStamp = Get-Date -Format "yyyyMMdd@HHmm"
        $SYMCLIPATH = "/opt/emc/SYMCLI/bin/symcli"
        while (-not (Test-Path $SYMCLIPATH)) {
            $SYMCLIPATH = Read-Host -Prompt "symcli not found. Enter path to symcli or Ctrl-C to exit"
        }
        # remove symcli part from path
        $SYMCLIPATH = $SYMCLIPATH -replace '/symcli', ''
        try {
            # If we do not have any arrayIds, get a list from symcfg
            if (!$arrayIds) {
                $arrayIds = & "$SYMCLIPATH/symcfg" list
                $arrayIds = ($arrayIds -Split '\r?\n' | 
                    Select-String -Pattern '([0-9]{12}) \w+\s+PowerMax_2000' -AllMatches).Matches |
                    ForEach-Object { $_.Groups[1].Value }
            }
        }
        catch {
            Write-Error "Unable to get list of arrays: $_"
        }
    }
    process {
        try {
                foreach ($arrayId in $arrayIds) {
                    Write-Verbose "Collecting logins from array $arrayId"
                    & "$SYMCLIPATH/symaccess" list logins -v -sid $arrayId | Out-File -FilePath "logins-$arrayId-$timeStamp.txt"
                }
        }
        catch {
                Write-Error "Unable to get logins: $_"
        }
    }
    end {
        Write-Verbose "Processed $($arrayIds.Count) arrays."
    }
    
}

function Import-PmaxLogins {
    <#
    .SYNOPSIS
        Processes login information from EMC Powermax storage systems.
    
    .DESCRIPTION
        This script parses login information from text files and exports them to a CSV file.
        It processes multiple log files and combines the results. The files must contain the output of 'symaccess list logins -v'.
        Below is and example:

                
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

    .PARAMETER Path
        Specifies one or more login files or patterns to process. Defaults to "./logins*.txt".
        
    .EXAMPLE
        # Process all logins*.txt files in current directory and save the output and array
        $allLogins = Get-PowerMaxLogins
        $allLogins|where {$_.wwpn -match 'c050760aa89f005[0-7]'}|ft

        # Process all logins*.txt files in current directory and output to console
        Get-PowerMaxLogins | format-table
    
        # Process specific files and export to CSV
        Get-PowerMaxLogins -Path "C:\Logs\logins-001.txt", "C:\Logs\logins-002.txt" -OutputFile "output.csv"
    
        # Process files using wildcard and pipe to other commands
        Get-PowerMaxLogins -Path "C:\Logs\logins-*.txt" | Where-Object { $_.LoggedIn -eq "Yes" }
    
        # Pipe files from Get-ChildItem
        Get-ChildItem -Path "C:\Logs" -Filter "logins-*.txt" | Get-PowerMaxLogins
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [Alias("FullName", "PSPath")]
        [string[]]$Path = @("./logins*.txt")
    )
    
    begin {
        # to enable debug output set $DebugPreference = 'Continue'
        # $DebugPreference = 'continue'
        #
        # Initialize variables
        #
        # Pre-compile regex patterns for better performance
        $regexPatterns = @{
            ArrayId           = 'Symmetrix ID\s+:\s+(\S+)'
            DirectorId        = 'Director Identification\s+:\s+(\S+)'
            DirectorPort      = 'Director Port\s+:\s+(\S+)'
            WwnPortName       = 'WWN Port Name\s+:\s+(\S+)'
            OriginatorNodeWwn = 'Originator Node wwn\s+:\s+(\S+)'
            OriginatorPortWwn = 'Originator Port wwn\s+:\s+(\S+)'
            UserGeneratedName = 'User-generated Name\s+:\s+(\S+)'
            Fcid              = 'FCID\s+:\s+(\S+)'
            LoggedIn          = 'Logged In\s+:\s+(\S+)'
            OnFabric          = 'On Fabric\s+:\s+(\S+)'
            LastActiveLogin   = 'Last Active Log-In\s+:\s+(.*)'
        }
        $arrayCount = 0
        $allLogins = [System.Collections.ArrayList]::new()
        $processedFiles = 0
        $exportToFile = $PSBoundParameters.ContainsKey('OutputFile')
            
        if ($exportToFile -and (Test-Path -Path $OutputFile)) {
            Write-Warning "Output file already exists and will be overwritten: $OutputFile"
        }
    }
    
    process {
        try {
            # Resolve file paths, expanding wildcards if any
            $filesToProcess = $Path | ForEach-Object {
                if (Test-Path -Path $_) {
                    Get-Item -Path $_
                }
                else {
                    Write-Warning "Path not found: $_"
                }
            } | Where-Object { $_ -is [System.IO.FileInfo] }
    
            if ($filesToProcess.Count -eq 0) {
                Write-Warning "No matching files found."
                return
            }
    
            foreach ($file in $filesToProcess) {
                $processedFiles++
                Write-Progress -Activity "Processing files" -Status $file.Name -PercentComplete (($processedFiles / $filesToProcess.Count) * 100)
                    
                try {
                    $fileContent = [System.IO.File]::ReadAllText($file.FullName)
                    $textBlocks = $fileContent -split '(?:\r?\n){2,}'
                        
                    $currentArray = $null
                    $currentDirPort = $null
                    $currentPortNum = $null
                    $currentDirWwpn = $null
                    $currentLogin = $null
    
                    foreach ($block in $textBlocks) {
                        $lines = $block -split '\r?\n'
                            
                        foreach ($line in $lines) {
                            $line = $line.Trim()
                            if ([string]::IsNullOrWhiteSpace($line)) { continue }
    
                            switch -Regex ($line) {
                                $regexPatterns.ArrayId {
                                    $currentArray = $matches[1]
                                    $arrayCount++
                                    break
                                }
                                $regexPatterns.DirectorId {
                                    $currentDirPort = $matches[1].Substring(3, 2)
                                    break
                                }
                                $regexPatterns.DirectorPort {
                                    $currentPortNum = [int]$matches[1]
                                    break
                                }
                                $regexPatterns.WwnPortName {
                                    $currentDirWwpn = $matches[1]
                                    break
                                }
                                $regexPatterns.OriginatorNodeWwn {
                                    $currentLogin = [PSCustomObject]@{
                                        Array      = $currentArray
                                        DirPort    = if ($currentDirPort -and $currentPortNum) { "$currentDirPort-$currentPortNum" } else { $null }
                                        DirWwpn    = $currentDirWwpn
                                        Wwnn       = $matches[1]
                                        Wwpn       = $null
                                        Fcid       = $null
                                        InitName   = $null
                                        LoggedIn   = $null
                                        OnFabric   = $null
                                        LogTime    = $null
                                        SourceFile = $file.Name
                                    }
                                    break
                                }
                                $regexPatterns.OriginatorPortWwn {
                                    if ($currentLogin) { $currentLogin.Wwpn = $matches[1] }
                                    break
                                }
                                $regexPatterns.UserGeneratedName {
                                    if ($currentLogin -and $matches[1] -ne '/') { 
                                        $currentLogin.InitName = $matches[1] 
                                    }
                                    break
                                }
                                $regexPatterns.Fcid {
                                    if ($currentLogin) { $currentLogin.Fcid = $matches[1] }
                                    break
                                }
                                $regexPatterns.LoggedIn {
                                    if ($currentLogin) { $currentLogin.LoggedIn = $matches[1] }
                                    break
                                }
                                $regexPatterns.OnFabric {
                                    if ($currentLogin) { $currentLogin.OnFabric = $matches[1] }
                                    break
                                }
                                $regexPatterns.LastActiveLogin {
                                    if ($currentLogin) {
                                        $currentLogin.LogTime = $matches[1]
                                        [void]$allLogins.Add($currentLogin)
                                        # For debugging, output the current login to the pipeline
                                        Write-Debug $currentLogin | ConvertTo-Json
                                        $currentLogin = $null
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Error "Error processing file $($file.Name): $_"
                }
            }
        }
        catch {
            Write-Error "Error: $_"
        }
    }
    
    end {
        Write-Progress -Activity "Processing files" 
        Write-Verbose "Processed $($allLogins.Count) logins from $array_count arrays."
        # Return the results in an array
        $allLogins
    }
}

# file is being run as a script
if ($MyInvocation.InvocationName -ne '.') {
    Get-AllPmaxLogins
    $VerbosePreference = "Continue"
    $OutputFile = "pmax-logins.csv"
    $allLogins = Import-PmaxLogins -Path "logins-*.txt"
    # $allLogins = Import-PmaxLogins -Path "logins-000197901097.txt"
    $allLogins | where-object { $_.wwpn -match 'c050760aa89f005[0-7]' } | format-table -Wrap
    $allLogins | Export-Csv -Path $OutputFile -NoTypeInformation
     
}
