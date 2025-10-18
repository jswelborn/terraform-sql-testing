<#
.SYNOPSIS
    Fully automated post-deployment SQL Server configuration for Azure SQL VMs.

.DESCRIPTION
    - Rebuilds system DBs with custom collation
    - Enables SA account (temporary password)
    - Sets default data/log directories
    - Moves TempDB
    - Configures MAXDOP, memory, and ad hoc workloads
    - Waits for SQL to become available before applying changes
    - Logs all actions to C:\Temp\sql_post_config.log
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
    # --- Configuration Values ---
    $Instance = "MSSQLSERVER"
    $Collation = "SQL_Latin1_General_CP1_CS_AS"
    $TempSAPassword = "ChangeMe123!"
    $MaxMemoryMB = 2147483647
    $MinMemoryMB = 0
    $MaxDOP = 0
    $OptimizeAdHoc = 1
    $DataDrive = "F"
    $LogDrive = "G"
    $TempDBDrive = "F"

    # --- Detect SQL Setup Path ---
    $setup = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server\" -Recurse -Filter Setup.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "Setup Bootstrap" } | Select-Object -First 1
    if (-not $setup) { throw "Could not locate SQL setup executable." }

    Write-Log "Found SQL setup at: $($setup.FullName)"

    # --- Detect current collation ---
    try {
        $currentCollation = sqlcmd -S localhost -E -C -h-1 -W -Q "SELECT SERVERPROPERTY('Collation')" 2>$null
        Write-Log "Current SQL collation: $currentCollation"
    } catch {
        Write-Log "Could not detect current collation (may be first run)."
    }

    # --- Rebuild system DBs with correct collation ---
    Write-Log "Rebuilding system databases with collation $Collation..."
    & $setup.FullName /QUIET /ACTION=REBUILDDATABASE /INSTANCENAME=$Instance /SQLSYSADMINACCOUNTS="Administrators" /SQLCOLLATION=$Collation
    Write-Log "System databases rebuilt successfully."
    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL Server restarted after rebuild."

    # --- Wait for SQL to become available ---
    Write-Log "Waiting for SQL to accept connections..."
    for ($i = 1; $i -le 10; $i++) {
        try {
            sqlcmd -S localhost -E -C -Q "SELECT 1" -W | Out-Null
            Write-Log "SQL is online and accepting connections."
            break
        } catch {
            Write-Log "SQL not ready yet (attempt $i/10)..."
            Start-Sleep -Seconds 30
        }
        if ($i -eq 10) { throw "SQL Server did not start within timeout window." }
    }

    # --- Enable SA login ---
    Write-Log "Ensuring 'sa' login is enabled..."
    sqlcmd -S localhost -E -C -Q "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$TempSAPassword'; ALTER LOGIN sa WITH CHECK_POLICY = OFF;"
    Write-Log "'sa' login enabled with temporary password '$TempSAPassword'."

    # --- Create drive paths ---
    foreach ($drive in @($DataDrive, $LogDrive, $TempDBDrive)) {
        foreach ($folder in @("Data", "Log", "TempDB")) {
            $path = "$drive`:\$folder"
            if (!(Test-Path $path)) {
                Write-Log "Creating directory: $path"
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }

    # --- Update default data/log directories in registry ---
    Write-Log "Setting default data/log paths in SQL registry..."
    sqlcmd -S localhost -E -C -Q "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQLServer', N'DefaultData', REG_SZ, '$DataDrive`:\Data';"
    sqlcmd -S localhost -E -C -Q "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQLServer', N'DefaultLog', REG_SZ, '$LogDrive`:\Log';"
    Write-Log "Registry paths updated."

    # --- Apply performance configuration ---
    Write-Log "Applying SQL configuration (MAXDOP, memory, ad hoc)..."
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'max degree of parallelism', $MaxDOP; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'optimize for ad hoc workloads', $OptimizeAdHoc; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'min server memory (MB)', $MinMemoryMB; RECONFIGURE;"
    sqlcmd -S localhost -E -C -Q "EXEC sys.sp_configure N'max server memory (MB)', $MaxMemoryMB; RECONFIGURE;"
    Write-Log "SQL configuration applied successfully."

    # --- Move TempDB ---
    Write-Log "Moving TempDB to $TempDBDrive:\TempDB..."
    sqlcmd -S localhost -E -C -Q "
    ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = '$TempDBDrive`:\TempDB\tempdb.mdf');
    ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = '$TempDBDrive`:\TempDB\templog.ldf');"
    Write-Log "TempDB location updated. Restart SQL to apply."

    # --- Restart SQL to finalize changes ---
    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL Server restarted to apply all configuration changes."

    # --- Verify and log summary ---
    $collation = sqlcmd -S localhost -E -C -h-1 -W -Q "SELECT SERVERPROPERTY('Collation')"
    Write-Log "Final collation: $collation"

    $paths = sqlcmd -S localhost -E -C -W -Q "
    EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQLServer', N'DefaultData';
    EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQLServer', N'DefaultLog';"
    Write-Log "Default path check:`n$paths"

    Write-Log "=== SQL Post-Config Script Completed Successfully ==="
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Write-Log "=== SQL Post-Config Script Finished ==="
}
