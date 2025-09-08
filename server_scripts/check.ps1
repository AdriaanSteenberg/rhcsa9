# Path to the text file containing one server name per line
$serverListFile = ".\servers.txt"

# Output folder for per-host CSV reports
$reportFolder = ".\Reports"

# Create output folder if it doesn't exist
if (-not (Test-Path $reportFolder)) {
    New-Item -ItemType Directory -Path $reportFolder | Out-Null
}

# Read all server names
$servers = Get-Content -Path $serverListFile

# Prompt once for credentials that have access on all target servers
$credential = Get-Credential -Message 'Enter credentials for remote server access'

foreach ($server in $servers) {
    Write-Host "Collecting metrics from $server..."

    try {
        $data = Invoke-Command -ComputerName $server -Credential $credential -ScriptBlock {
            # CPU usage (% Processor Time)
            $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -MaxSamples 1
            $cpuUsage = [math]::Round($cpu.CounterSamples.CookedValue, 2)

            # Memory stats
            $os = Get-CimInstance Win32_OperatingSystem
            $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)
            $freeMB  = [math]::Round($os.FreePhysicalMemory       / 1024, 2)
            $usedMB  = $totalMB - $freeMB
            $memPct  = [math]::Round(($usedMB / $totalMB) * 100, 2)

            # Logical drives (Type 3 = local disks)
            $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Select-Object DeviceID,
                              @{Name='SizeGB';       Expression = {[math]::Round($_.Size    /1GB,2)}},
                              @{Name='FreeGB';       Expression = {[math]::Round($_.FreeSpace/1GB,2)}},
                              @{Name='FreePercent';  Expression = {[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}

            # Emit one object per drive with server-wide metrics repeated
            $drives | ForEach-Object {
                [PSCustomObject]@{
                    HostName           = $env:COMPUTERNAME
                    CPU_UsagePercent   = $cpuUsage
                    TotalMemory_MB     = $totalMB
                    FreeMemory_MB      = $freeMB
                    Memory_UsagePercent= $memPct
                    DriveLetter        = $_.DeviceID
                    DriveSize_GB       = $_.SizeGB
                    DriveFree_GB       = $_.FreeGB
                    DriveFreePercent   = $_.FreePercent
                }
            }
        }

        # Export that server's data to hostname.csv
        $outFile = Join-Path $reportFolder "$server.csv"
        $data | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

        Write-Host "→ Report saved to $outFile" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to collect from $server : $_"
    }
}








# Path to folder containing individual host reports
$reportFolder = ".\Reports"

# Optionally timestamp the master file
$timestamp    = Get-Date -Format "yyyyMMdd_HHmm"
$masterReport = Join-Path $reportFolder "Master_Report_$timestamp.csv"

# Import all CSVs and combine into one collection
$allData = Get-ChildItem -Path $reportFolder -Filter "*.csv" |
    ForEach-Object {
        Import-Csv -Path $_.FullName
    }

# Export the merged data
$allData | Export-Csv -Path $masterReport -NoTypeInformation -Encoding UTF8

Write-Host "Master report created at $masterReport" -ForegroundColor Green








$allData | Select-Object *,@{Name='CollectionDate';Expression={Get-Date}} |
    Export-Csv ...





Param(
    [string]$ReportFolder   = ".\Reports",
    [datetime]$StartDate    = (Get-Date).AddDays(-7),
    [datetime]$EndDate      = Get-Date,
    [string[]]$HostFilter   = @("*"),   # wildcard patterns, e.g. "WEB*","DB*"
    [string[]]$DriveFilter  = @("C","D") # drive letters to include
)

# Build timestamped master filename
$timestamp    = Get-Date -Format "yyyyMMdd_HHmm"
$masterReport = Join-Path $ReportFolder "Master_Report_$timestamp.csv"

# Collect, tag, filter, and sort
$allData = Get-ChildItem -Path $ReportFolder -Filter "*.csv" |
    ForEach-Object {
        Import-Csv -Path $_.FullName |
        Select-Object *,
            @{Name='CollectionDate';Expression={Get-Date}}
    } |
    Where-Object {
        $_.CollectionDate -ge $StartDate -and
        $_.CollectionDate -le $EndDate -and
        $HostFilter -contains $_.HostName -and
        $DriveFilter -contains $_.DriveLetter
    } |
    Sort-Object CollectionDate, HostName, DriveLetter

# Export merged data
$allData | Export-Csv -Path $masterReport -NoTypeInformation -Encoding UTF8

Write-Host "Master report generated: $masterReport" -ForegroundColor Green


