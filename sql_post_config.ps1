<#
.SYNOPSIS
    Post-deployment SQL Server configuration script for Azure SQL VMs.
.DESCRIPTION
    Configures collation, memory, MAXDOP, ad-hoc workloads, default DB paths,
    and TempDB locations. Safe to re-run multiple times.
    Writes detailed logs to C:\Temp\sql_post_config.log
#>

$ErrorActionPreference = 'Stop'
$LogFile = "C:\Temp\sql_post_config.log"
New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

Function Write-Log($msg) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp :: $msg" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== SQL Post-Config Script Started ==="

try {
    # SQL Instance
    $Instance = "MSSQLSERVER"

    # Ensure SQL PowerShell module is loaded
    Import-Module SQLPS -DisableNameChecking -ErrorAction SilentlyContinue

    # --- SQL Settings ---
    $Collation = "SQL_Latin1_General_CP1_CS_AS"
    $MaxMemoryMB = 2147483647
    $MinMemoryMB = 0
    $MaxDOP = 0
    $OptimizeAdHoc = 1

    # Default paths (update if your F:/G: drives differ)
    $DefaultDataPath = "F:\Data"
    $DefaultLogPath  = "G:\Log"
    $TempDBPath      = "D:\tempdb"

    # --- Ensure directories exist ---
    foreach ($dir in @($DefaultDataPath, $DefaultLogPath, $TempDBPath)) {
        if (!(Test-Path $dir)) {
            Write-Log "Creating directory: $dir"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # --- Configure instance ---
    Write-Log "Connecting to SQL instance $Instance..."
    $srv = New-Object ("Microsoft.SqlServer.Management.Smo.Server") $Instance

    # Collation check
    if ($srv.Collation -ne $Collation) {
        Write-Log "Changing instance collation from $($srv.Collation) to $Collation..."
        $srv.Collation = $Collation
        $srv.Alter()
        Write-Log "Collation updated."
    } else {
        Write-Log "Collation already set to $Collation."
    }

    # --- SQLCMD Settings ---
    Write-Log "Applying SQL configuration options..."
    sqlcmd -Q "EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;"
    sqlcmd -Q "EXEC sys.sp_configure N'max degree of parallelism', $MaxDOP; RECONFIGURE;"
    sqlcmd -Q "EXEC sys.sp_configure N'optimize for ad hoc workloads', $OptimizeAdHoc; RECONFIGURE;"
    sqlcmd -Q "EXEC sys.sp_configure N'min server memory (MB)', $MinMemoryMB; RECONFIGURE;"
    sqlcmd -Q "EXEC sys.sp_configure N'max server memory (MB)', $MaxMemoryMB; RECONFIGURE;"

    # --- Set default data/log directories ---
    Write-Log "Updating default data/log directories..."
    $srv.DefaultFile = $DefaultDataPath
    $srv.DefaultLog  = $DefaultLogPath
    $srv.Alter()
    Write-Log "Default paths updated."

    # --- Move TempDB ---
    if (Test-Path $TempDBPath) {
        Write-Log "Updating TempDB file locations..."
        $TempDev = Join-Path $TempDBPath "tempdb.mdf"
        $TempLog = Join-Path $TempDBPath "templog.ldf"

        $tdev = $srv.Databases["tempdb"].FileGroups["PRIMARY"].Files["tempdev"]
        $tdev.FileName = $TempDev
        $tlog = $srv.Databases["tempdb"].LogFiles["templog"]
        $tlog.FileName = $TempLog

        $srv.Alter()
        Write-Log "TempDB paths updated. These take effect after SQL restart."
    }

    # --- Done ---
    Write-Log "SQL configuration completed successfully."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Write-Log "=== SQL Post-Config Script Finished ==="
}
