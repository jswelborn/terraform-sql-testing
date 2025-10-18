<#
.SYNOPSIS
    SQL Server 2025 Post-Deployment Configuration Script for Azure SQL VMs
.DESCRIPTION
    - Rebuilds system databases if collation is incorrect
    - Ensures 'Administrator' remains sysadmin
    - Enables 'sa' login with placeholder password
    - Configures memory, MAXDOP, ad-hoc workloads
    - Moves TempDB and sets default data/log directories
    - Logs to C:\Temp\sql_post_config.log
#>

$ErrorActionPreference = 'Stop'
$LogFile = "C:\Temp\sql_post_config.log"
New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

function Write-Log($Message) {
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$Timestamp :: $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== SQL Post-Config Script Started ==="

try {
    $Instance = "MSSQLSERVER"
    $DesiredCollation = "SQL_Latin1_General_CP1_CS_AS"

    $MaxMemoryMB = 2147483647
    $MinMemoryMB = 0
    $MaxDOP = 0
    $OptimizeAdHoc = 1
    $SaPassword = "ChangeMe123!"

    # Locate SQL setup.exe (latest)
    $SqlSetupExe = (Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server\" -Recurse -Filter setup.exe -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match "Setup Bootstrap" } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName)

    if (-not $SqlSetupExe) {
        Write-Log "SQL setup.exe not found; skipping rebuild."
    } else {
        Write-Log "Found SQL setup at: $SqlSetupExe"

        try {
            $CurrentCollation = sqlcmd -S localhost -E -C -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('Collation');" -h-1 -W 2>$null
        } catch {
            $CurrentCollation = "Unknown"
        }

        Write-Log "Current SQL collation: $CurrentCollation"
        if ($CurrentCollation -and $CurrentCollation -ne $DesiredCollation) {
            Write-Log "Rebuilding system databases to use $DesiredCollation..."
            Stop-Service MSSQLSERVER -Force
            & "$SqlSetupExe" /QUIET /ACTION=REBUILDDATABASE /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS="Administrator" /SQLCOLLATION=$DesiredCollation
            if ($LASTEXITCODE -eq 0) {
                Write-Log "System databases rebuilt successfully."
            } else {
                Write-Log "ERROR: setup.exe exited with code $LASTEXITCODE"
            }
            Start-Service MSSQLSERVER
            Write-Log "SQL Server restarted after rebuild."
        } else {
            Write-Log "Collation already matches $DesiredCollation; no rebuild required."
        }
    }

    # Enable sa login with placeholder password
    Write-Log "Ensuring 'sa' login is enabled for DBA configuration..."
    sqlcmd -S localhost -E -Q "ALTER LOGIN sa WITH PASSWORD='$SaPassword'; ALTER LOGIN sa ENABLE;"
    Write-Log "'sa' login enabled with temporary password '$SaPassword'"

    # Detect available data/log drives (skip C:, D:)
    $Drives = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -notin @('C','D') } | Sort-Object DriveLetter
    if ($Drives.Count -eq 0) {
        $DataDrive = "C"; $LogDrive = "C"
    } elseif ($Drives.Count -eq 1) {
        $DataDrive = $Drives[0].DriveLetter; $LogDrive = $Drives[0].DriveLetter
    } else {
        $DataDrive = $Drives[0].DriveLetter; $LogDrive = $Drives[1].DriveLetter
    }

    Write-Log "Detected data drive: $DataDrive, log drive: $LogDrive"

    $DefaultDataPath = "$DataDrive`:\Data"
    $DefaultLogPath  = "$LogDrive`:\Log"
    $TempDBPath      = "$DataDrive`:\TempDB"

    foreach ($dir in @($DefaultDataPath, $DefaultLogPath, $TempDBPath)) {
        if (!(Test-Path $dir)) {
            Write-Log "Creating directory: $dir"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Apply SQL configuration
    Write-Log "Applying SQL configuration (MAXDOP, memory, ad hoc)..."
    sqlcmd -S localhost -E -C -Q 'EXEC sys.sp_configure N''show advanced options'', 1; RECONFIGURE;'
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'max degree of parallelism', $MaxDOP; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'optimize for ad hoc workloads', $OptimizeAdHoc; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'min server memory (MB)', $MinMemoryMB; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'max server memory (MB)', $MaxMemoryMB; RECONFIGURE;"
    Write-Log "SQL configuration applied successfully."

    # Default paths
    Write-Log "Updating default data/log paths..."
    $srv = New-Object ("Microsoft.SqlServer.Management.Smo.Server") $Instance
    $srv.DefaultFile = $DefaultDataPath
    $srv.DefaultLog  = $DefaultLogPath
    $srv.Alter()
    Write-Log "Default paths set to: Data=$DefaultDataPath, Log=$DefaultLogPath"

    # Move TempDB
    $RestartRequired = $false
    if (Test-Path $TempDBPath) {
        Write-Log "Relocating TempDB files..."
        $TempDev = Join-Path $TempDBPath "tempdb.mdf"
        $TempLog = Join-Path $TempDBPath "templog.ldf"
        $Query = "ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = '$TempDev'); ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = '$TempLog');"
        sqlcmd -S localhost -E -C -Q $Query
        $RestartRequired = $true
        Write-Log "TempDB move complete; restart required."
    }

    if ($RestartRequired) {
        Write-Log "Restarting SQL Server..."
        Restart-Service MSSQLSERVER -Force
        Write-Log "SQL Server restarted."
    }

    # Verification summary
    $VersionInfo = sqlcmd -S localhost -E -C -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('Edition');" -h-1 -W 2>$null
    $Collation = sqlcmd -S localhost -E -C -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('Collation');" -h-1 -W 2>$null
    Write-Log "Final SQL Version: $VersionInfo"
    Write-Log "Final Collation: $Collation"
    Write-Log "SQL Post-Config Completed Successfully."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {
    Write-Log "=== SQL Post-Config Script Finished ==="
}
