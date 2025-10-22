<#
.SYNOPSIS
  Idempotent post-deployment SQL Server configuration for Azure SQL VMs.

.DESCRIPTION
  - Detects proper instance registry path (MSSQL###.MSSQLSERVER)
  - Rebuilds system DBs to desired collation (first time only; guarded by marker)
  - Waits for data/log drives to appear
  - Writes DefaultData / DefaultLog / DefaultBackupDirectory in registry
  - Applies sp_configure + relocates all TempDB files to F:\TempDB
  - Logs all actions to C:\Temp\sql_post_config.log
#>

$ErrorActionPreference = 'Stop'
$LogDir  = 'C:\Temp'
$LogFile = Join-Path $LogDir 'sql_post_config.log'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Log {
  param([string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "$ts :: $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== SQL Post-Config Script Started ==="

# ------------------ Tunables ------------------
$InstanceName   = 'MSSQLSERVER'
$DesiredCollation = 'SQL_Latin1_General_CP1_CS_AS'
$DataDrive      = 'E'
$LogDrive       = 'E'
$TempDBDrive    = 'E'
$MaxMemoryMB    = 2147483647
$MinMemoryMB    = 0
$MaxDOP         = 0
$OptimizeAdHoc  = 1
$RebuildMarker  = 'C:\Temp\_sql_rebuild_done.flag'
# ------------------------------------------------

function Get-SetupExe {
  $setup = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server\" -Recurse -Filter Setup.exe -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match 'Setup Bootstrap' } |
           Select-Object -First 1
  if (-not $setup) { throw "Could not locate SQL setup executable." }
  $setup.FullName
}

function Get-InstanceKey {
  $root = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'
  $key  = Get-ChildItem $root -ErrorAction SilentlyContinue |
          Where-Object { $_.PSChildName -match '^MSSQL\d{3}\.MSSQLSERVER$' } |
          Select-Object -ExpandProperty PSChildName -First 1
  if (-not $key) {
    $map = Get-ItemProperty "${root}Instance Names\SQL" -ErrorAction SilentlyContinue
    if ($map -and $map.MSSQLSERVER) { $key = $map.MSSQLSERVER }
  }
  if (-not $key) { throw "Could not determine instance key under Microsoft SQL Server registry hive." }
  $key
}

function Get-RegBase {
  param([string]$InstanceKey)
  "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\${InstanceKey}\MSSQLServer"
}

function Drive-Ready {
  param([string]${DriveLetter})
  Test-Path ("{0}:" -f ${DriveLetter})
}

function Wait-ForDrive {
  param([string]${DriveLetter}, [int]$TimeoutSec = 900)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while (-not (Drive-Ready ${DriveLetter})) {
    if ((Get-Date) -gt $deadline) { return $false }    # fixed: added parentheses
    Write-Log "Drive ${DriveLetter}: not ready, waiting 30s..."
    Start-Sleep -Seconds 30
  }
  return $true
}

function Sql-Try {
  param([string]$Query, [int]$Timeout = 15)
  try {
    sqlcmd -S localhost -E -C -l $Timeout -W -Q $Query | Out-Null
    return $true
  } catch {
    return $false
  }
}

try {
  # 1) Detect setup + instance key + reg base
  $setupExe    = Get-SetupExe
  Write-Log "Found SQL setup at: $setupExe"

  $instanceKey = Get-InstanceKey
  $regBase     = Get-RegBase -InstanceKey $instanceKey
  Write-Log "Instance registry base: $regBase"

  # 2) Read current collation
  $currentCollation = ''
  try { $props = Get-ItemProperty -Path $regBase -ErrorAction Stop; $currentCollation = $props.Collation } catch { }
  if ([string]::IsNullOrWhiteSpace($currentCollation)) { $currentCollation = 'Unknown' }
  Write-Log "Current (registry) collation: $currentCollation"

  # 3) Rebuild system DBs if needed
  $needRebuild = (-not (Test-Path $RebuildMarker)) -and ($currentCollation -ne $DesiredCollation)
  if ($needRebuild) {
    Write-Log "Rebuilding system databases to collation $DesiredCollation..."
    & $setupExe /QUIET /ACTION=REBUILDDATABASE /INSTANCENAME=$InstanceName /SQLSYSADMINACCOUNTS="Administrators" /SQLCOLLATION=$DesiredCollation
    Write-Log "System databases rebuild requested."
    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL Server restarted after rebuild."
    New-Item -ItemType File -Path $RebuildMarker -Force | Out-Null
  } else {
    Write-Log "Rebuild not required (marker present or collation already matches)."
  }

  # 4) Wait for SQL to be reachable
  Write-Log "Waiting for SQL to accept connections..."
  $online = $false
  for ($i=1; $i -le 10; $i++) {
    if (Sql-Try "SELECT 1") { $online = $true; break }
    Write-Log "SQL not ready yet (attempt $i/10)..."
    Start-Sleep -Seconds 30
  }
  if ($online) { Write-Log "SQL is online and accepting connections." }
  else { Write-Log "SQL did not become reachable in time; continuing with registry updates." }

  # 5) Wait for drives and create folders
  foreach ($drv in @($DataDrive, $LogDrive, $TempDBDrive)) {
    if (-not (Wait-ForDrive $drv 900)) { throw "Drive $drv never became ready." }
  }

  $DataPath   = "${DataDrive}:\Data"
  $LogPath    = "${LogDrive}:\Log"
  $TempDBPath = "${TempDBDrive}:\TempDB"

  foreach ($p in @($DataPath,$LogPath,$TempDBPath)) {
    if (-not (Test-Path $p)) {
      Write-Log "Creating directory: $p"
      New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
  }

  # 6) Update registry defaults
  Write-Log "Writing DefaultData/DefaultLog/BackupDirectory to registry at $regBase"
  Set-ItemProperty -Path $regBase -Name 'DefaultData' -Value $DataPath -Force
  Set-ItemProperty -Path $regBase -Name 'DefaultLog'  -Value $LogPath  -Force
  Set-ItemProperty -Path $regBase -Name 'BackupDirectory' -Value $DataPath -Force

  # 7) Apply perf settings + move TempDB
  if ($online) {
    Write-Log "Applying sp_configure settings..."
    [void](Sql-Try "EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;")
    [void](Sql-Try "EXEC sys.sp_configure N'max degree of parallelism', $MaxDOP; RECONFIGURE;")
    [void](Sql-Try "EXEC sys.sp_configure N'optimize for ad hoc workloads', $OptimizeAdHoc; RECONFIGURE;")
    [void](Sql-Try "EXEC sys.sp_configure N'min server memory (MB)', $MinMemoryMB; RECONFIGURE;")
    [void](Sql-Try "EXEC sys.sp_configure N'max server memory (MB)', $MaxMemoryMB; RECONFIGURE;")
    Write-Log "sp_configure applied."

    Write-Log "Relocating TempDB files to $TempDBPath..."
    $tempMove = @"
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = '$TempDBPath\tempdb.mdf');
ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = '$TempDBPath\templog.ldf');
"@
    [void](Sql-Try $tempMove)

    # Add relocation for secondary files temp2–temp8
    for ($n=2; $n -le 8; $n++) {
      $f = "temp$n"
      $move = "ALTER DATABASE tempdb MODIFY FILE (NAME = $f, FILENAME = '$TempDBPath\$f.ndf');"
      [void](Sql-Try $move)
    }
    Write-Log "TempDB move statements submitted."

    Restart-Service MSSQLSERVER -Force
    Write-Log "SQL restarted to apply TempDB/perf changes."
  } else {
    Write-Log "Skipping SQL config (instance not reachable)."
  }

  # 8) Verification
  try {
    $props2 = Get-ItemProperty -Path $regBase -ErrorAction Stop
    Write-Log "Registry verification: Collation='$($props2.Collation)', DefaultData='$($props2.DefaultData)', DefaultLog='$($props2.DefaultLog)'"
  } catch {
    Write-Log "Registry verification failed: $($_.Exception.Message)"
  }

  if ($online) {
    try {
      $finalColl = sqlcmd -S localhost -E -C -h-1 -W -Q "SELECT SERVERPROPERTY('Collation')" 2>$null
      Write-Log "SQL verification: Collation (SERVERPROPERTY)='$finalColl'"
      $tempdbFiles = sqlcmd -S localhost -E -C -W -Q "SET NOCOUNT ON; SELECT name, physical_name FROM sys.master_files WHERE database_id = DB_ID('tempdb');"
      Write-Log "SQL verification: TempDB files:`n$tempdbFiles"
    } catch {
      Write-Log "SQL verification failed: $($_.Exception.Message)"
    }
  }

  Write-Log "=== SQL Post-Config Script Completed Successfully ==="
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  throw
}
finally {
  Write-Log "=== SQL Post-Config Script Finished ==="
}
