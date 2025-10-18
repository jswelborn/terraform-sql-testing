<#
.SYNOPSIS
    Fully automated post-deployment SQL Server configuration for Azure SQL VMs.
.DESCRIPTION
    - Rebuilds system DBs with custom collation
    - Enables SA account (temporary password)
    - Sets default data/log directories
    - Moves TempDB
    - Configures MAXDOP, memory, and ad hoc workloads
    - Updates registry directly (no SMO dependency)
    - Logs all actions to C:\Temp\sql_post_config.log
#>

$ErrorActionPreference = 'Stop'
$LogFile = "C:\Temp\sql_post_config.log"
New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

function Write-Log($msg) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp :: $msg" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== SQL Post-Config Script Started ==="

try {
    # --- Configurable values ---
    $Instance       = "MSSQLSERVER"
    $Collation      = "SQL_Latin1_General_CP1_CS_AS"
    $TempSAPassword = "ChangeMe123!"
    $MaxMemoryMB    = 2147483647
    $MinMemoryMB    = 0
    $MaxDOP         = 0
    $OptimizeAdHoc  = 1
    $DataDrive      = "F"
    $LogDrive       = "G"
    $TempDBDrive    = "F"

    # --- Detect SQL Setup executable ---
    $setup = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server\" -Recurse -Filter Setup.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "Setup Bootstrap" } | Select-Object -First 1
    if (-not $setup) { throw "Could not locate SQL setup executable." }
    Write-Log "Found SQL setup at: $($setup.FullName)"

    # --- Detect current collation ---
    try {
        $currentCollation = sqlcmd -S localhost -E -C -h-1 -W -Q "SELECT SERVERPROPERTY('Collation')" 2>$null
        Write-Log "Current SQL collation: $currentCollation"
    } catch {
        Write-Log "Could not detect current collation (SQL may not be fully configured yet)."
    }

    # --- Rebuild system databases ---
    Write-Log "Rebuilding system databases with collation $Collation..."
    & $setup.FullName /QUIET /ACTION=REBUILDDATABASE /INSTANCENAME=$Instance /SQLSYSADMINACCOUNTS="Administrators" /SQLCOLLATION=$Collation
    Write-Log "System databases rebuilt successfully."
    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL Server restarted after rebuild."

    # --- Enable 'sa' login with a known password ---
    Write-Log "Ensuring 'sa' login is enabled for DBA setup..."
    sqlcmd -S localhost -E -C -Q "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$TempSAPassword'; ALTER LOGIN sa WITH CHECK_POLICY = OFF;"
    Write-Log "'sa' login enabled with temporary password '$TempSAPassword'."

    # --- Ensure required directories exist ---
    foreach ($drive in @($DataDrive, $LogDrive, $TempDBDrive)) {
        foreach ($folder in @("Data", "Log", "TempDB")) {
            $path = "$drive`:\$folder"
            if (!(Test-Path $path)) {
                Write-Log "Creating directory: $path"
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }

    # --- Detect SQL instance registry path dynamically ---
    Write-Log "Detecting SQL instance registry path..."
    $baseKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
    $instanceKey = Get-ChildItem $baseKey -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'MSSQL\d+\.MSSQLSERVER' } |
        Select-Object -ExpandProperty PSPath -First 1

    if ($instanceKey) {
        $mssqlKey = "$instanceKey\MSSQLServer"
        Write-Log "Detected SQL instance registry key: $mssqlKey"

        $DefaultData = "$DataDrive`:\Data"
        $DefaultLog  = "$LogDrive`:\Log"

        New-Item -Path $mssqlKey -Force | Out-Null
        Set-ItemProperty -Path $mssqlKey -Name Collation -Value $Collation -Force
        Set-ItemProperty -Path $mssqlKey -Name DefaultData -Value $DefaultData -Force
        Set-ItemProperty -Path $mssqlKey -Name DefaultLog -Value $DefaultLog -Force

        $props = Get-ItemProperty -Path $mssqlKey
        Write-Log "Registry updated:"
        Write-Log "  Collation   = $($props.Collation)"
        Write-Log "  DefaultData = $($props.DefaultData)"
        Write-Log "  DefaultLog  = $($props.DefaultLog)"
    } else {
        Write-Log "ERROR: Could not locate SQL instance registry path; skipping registry update."
    }

    # --- Apply performance settings ---
    Write-Log "Applying SQL configuration (MAXDOP, memory, ad hoc)..."
    $sqlConfigCmds = @(
        "EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;",
        "EXEC sys.sp_configure N'max degree of parallelism', $MaxDOP; RECONFIGURE;",
        "EXEC sys.sp_configure N'optimize for ad hoc workloads', $OptimizeAdHoc; RECONFIGURE;",
        "EXEC sys.sp_configure N'min server memory (MB)', $MinMemoryMB; RECONFIGURE;",
        "EXEC sys.sp_configure N'max server memory (MB)', $MaxMemoryMB; RECONFIGURE;"
    )
    foreach ($cmd in $sqlConfigCmds) {
        sqlcmd -S localhost -E -C -Q $cmd 2>$null
    }
    Write-Log "SQL configuration applied successfully."

    # --- Move TempDB ---
    Write-Log "Moving TempDB to $TempDBDrive:\TempDB..."
    sqlcmd -S localhost -E -C -Q "
        ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = '$TempDBDrive`:\TempDB\tempdb.mdf');
        ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = '$TempDBDrive`:\TempDB\templog.ldf');
    " 2>$null
    Write-Log "TempDB relocation completed. Will take effect after restart."

    # --- Restart SQL ---
    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL Server restarted to apply all configuration changes."

    # --- Verify and summarize ---
    $finalCollation = sqlcmd -S localhost -E -C -h-1 -W -Q "SELECT SERVERPROPERTY('Collation')" 2>$null
    Write-Log "Final collation: $finalCollation"

    $pathSummary = Get-ItemProperty -Path $mssqlKey | Select-Object DefaultData, DefaultLog
    Write-Log "Final registry paths:`n$($pathSummary | Out-String)"

    Write-Log "=== SQL Post-Config Script Completed Successfully ==="
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Write-Log "=== SQL Post-Config Script Finished ==="
}
