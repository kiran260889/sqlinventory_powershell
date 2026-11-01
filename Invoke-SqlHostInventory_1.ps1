<#
.SYNOPSIS
    SQL Server host inventory collector - physical vs VM, default vs named instance,
    version/CU, CPU, memory, AG membership - across every instance in your inventory.

.DESCRIPTION
    Reads SERVER NAMES from the server file (-InstanceListPath, default instances.txt next to
    this script) and finds every SQL Server instance on each server - default and named -
    then inventories each one. You don't list instance names; the script works them out.

    Server file format - one server per line:
        SERVER01
        SERVER02.healthcare.HUARAHI.HEALTH.GOVT.NZ
        # comment                     blank lines and lines starting with # are ignored
        (an optional '| version' suffix is accepted and ignored. A line that already contains
         '\INSTANCE' or ',PORT' is used as-is, without discovery.)

    How instances are found on each server, first method that works wins:
        1. Windows services (CIM over WinRM, then DCOM): MSSQLSERVER = default instance,
           MSSQL$<name> = named instance. Stopped instances are reported as STOPPED.
        2. SQL Server Browser (UDP 1434): lists the instances the Browser advertises.
        3. Neither reachable: the server name is tried as a default instance.
    The method used is recorded per row in the DiscoveryMethod column.

    Runs SqlHostInventory_Row.sql against each instance via sqlcmd and combines the results.
    Output lands in:
        <OutputFolder>/inventory_output/SqlHostInventory_<timestamp>.csv
        <OutputFolder>/inventory_output/SqlHostInventory_Failed_<timestamp>.csv
        <OutputFolder>/inventory_output/run_<timestamp>.log   (full transcript)
    and, with -WriteToTable, is bulk-loaded into a staging table (default
    dbo.SQLServer_Host_stagging, created if missing).

    Connection handling mirrors Invoke-SQLCollection.ps1:
        - sqlcmd.exe next to this script is preferred, else sqlcmd on PATH (or -SqlCmdPath)
        - TLS handshake failure        -> retried once with -Ndisable (Go sqlcmd syntax)
        - any other connection failure -> retried with the ODBC sqlcmd (...\Tools\Binn\) if present
        - hard wall-clock timeout per instance, so one hung instance never blocks the run

    Physical/VM detection:
        HostType comes from sys.dm_os_sys_info.virtual_machine_type_desc (2008 R2 SP1+).
        -CollectHardware additionally reads Win32_ComputerSystem Manufacturer/Model from the
        physical node (WinRM, falling back to DCOM) and flags any disagreement in the summary.

.PARAMETER InstanceListPath
    Server file - one server name per line. Default: instances.txt next to this script.

.PARAMETER SqlScriptPath
    Path to SqlHostInventory_Row.sql. Default: next to this script.

.PARAMETER OutputFolder
    Root output folder. Default: current directory.

.PARAMETER CollectHardware
    Also collect hardware Manufacturer/Model from Windows as a cross-check on HostType.

.PARAMETER WriteToTable
    Switch. Bulk-loads the results into the staging table named by -StagingTable.
    Created if missing; missing columns are added. Rows are appended, tagged with RunId.

.PARAMETER StagingTable
    Name of the staging table. Default: dbo.SQLServer_Host_stagging.
    The name always ends in '_stagging' - if you pass a name without it, the suffix is
    added (e.g. dbo.HostInventory -> dbo.HostInventory_stagging).

.PARAMETER TargetServer
    Instance the staging table is written to. Required with -WriteToTable.

.PARAMETER TargetDatabase
    Database the staging table is written to. Required with -WriteToTable. Must already exist.

.PARAMETER TrustServerCertificate
    Pass -C to sqlcmd (and TrustServerCertificate=True to the bulk load connection).

.PARAMETER TimeoutSeconds
    Per-instance query timeout. Default: 120.

.PARAMETER SqlCmdPath
    Explicit sqlcmd executable. Disables the fallback-sqlcmd retry.

.EXAMPLE
    # Instances from instances.txt next to the script, CSV output only
    .\Invoke-SqlHostInventory.ps1

.EXAMPLE
    # Different instance file and output folder
    .\Invoke-SqlHostInventory.ps1 -InstanceListPath .\servers.txt -OutputFolder C:\SQLAudit

.EXAMPLE
    # Hardware check + load into nestview.dbo.SQLServer_Host_stagging
    .\Invoke-SqlHostInventory.ps1 -CollectHardware -WriteToTable -TargetServer sqlaoag2019p1.cdhb.local -TargetDatabase nestview
#>

[CmdletBinding()]
param(
    [string] $InstanceListPath  = (Join-Path $PSScriptRoot 'instances.txt'),
    [string] $SqlScriptPath     = (Join-Path $PSScriptRoot 'SqlHostInventory_Row.sql'),
    [string] $OutputFolder      = '.',
    [switch] $CollectHardware,
    [switch] $WriteToTable,
    [string] $StagingTable      = 'dbo.SQLServer_Host_stagging',
    [string] $TargetServer,
    [string] $TargetDatabase,
    [switch] $TrustServerCertificate,
    [int]    $TimeoutSeconds    = 120,
    [string] $SqlCmdPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Column order returned by SqlHostInventory_Row.sql - keep in sync with the .sql file.
$InventoryColumns = @(
    'Server Name FQDN', 'ServerName', 'PhysicalNodeName', 'InstanceName', 'InstanceType',
    'SqlInstanceName', 'InstanceDisplay', 'WindowsOSVersion', 'SQLVersionNumber', 'SQLVersionName',
    'SQLEdition', 'ServicePackLevel', 'CUBundleLevel', 'PhysicalCoreCount', 'LogicalCPUCount',
    'TotalOSMemory_MB', 'MinServerMemory_MB', 'MaxServerMemory_MB', 'AGName', 'AGRole',
    'TotalDatabaseCount', 'VirtualMachineType', 'HostType', 'IsClustered', 'IsHadrEnabled',
    'CollectedAt'
)
# Added by this script
$ExtraColumns = @('SourceServer', 'CollectedFrom', 'DiscoveryMethod', 'HWManufacturer', 'HWModel', 'HWHostType', 'RunId')
$AllColumns   = $InventoryColumns + $ExtraColumns

# ---------------------------------------------------------------------------
# Resolve sqlcmd (same order as Invoke-SQLCollection.ps1)
# ---------------------------------------------------------------------------
$SqlCmdExe = $null
if ($SqlCmdPath) {
    if (-not (Test-Path -LiteralPath $SqlCmdPath -PathType Leaf)) {
        Write-Host "`nsqlcmd not found at -SqlCmdPath '$SqlCmdPath'.`n" -ForegroundColor Red
        exit 1
    }
    $SqlCmdExe = (Resolve-Path -LiteralPath $SqlCmdPath).ProviderPath
}
elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'sqlcmd.exe') -PathType Leaf) {
    $SqlCmdExe = Join-Path $PSScriptRoot 'sqlcmd.exe'
}
else {
    $onPath = Get-Command sqlcmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { $SqlCmdExe = $onPath.Source }
}
if (-not $SqlCmdExe) {
    Write-Host "`nsqlcmd not found. Place sqlcmd.exe in '$PSScriptRoot', install sqlcmd, or pass -SqlCmdPath.`n" -ForegroundColor Red
    exit 1
}

$FallbackSqlCmdExe = $null
if (-not $SqlCmdPath) {
    $candidates = @(Get-Command sqlcmd -All -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -ne $SqlCmdExe -and $_.Source -match '\\Tools\\Binn\\' })
    if ($candidates.Count -gt 0) { $FallbackSqlCmdExe = $candidates[0].Source }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Text)
    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor Cyan
}

# Win32 command-line quoting (see Invoke-SQLCollection.ps1 for the why).
function ConvertTo-SqlCmdArgString {
    param([string[]]$ArgumentList)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($argument in $ArgumentList) {
        $argument = [string]$argument
        if ($sb.Length -ne 0) { [void]$sb.Append(' ') }
        if ($argument.Length -ne 0 -and $argument -notmatch '[\s"]') { [void]$sb.Append($argument); continue }
        [void]$sb.Append('"')
        $idx = 0
        while ($idx -lt $argument.Length) {
            $c = $argument[$idx]; $idx++
            if ($c -eq '\') {
                $n = 1
                while ($idx -lt $argument.Length -and $argument[$idx] -eq '\') { $idx++; $n++ }
                if ($idx -eq $argument.Length)       { [void]$sb.Append([char]'\', ($n * 2)) }
                elseif ($argument[$idx] -eq '"')     { [void]$sb.Append([char]'\', ($n * 2 + 1)); [void]$sb.Append('"'); $idx++ }
                else                                 { [void]$sb.Append([char]'\', $n) }
            }
            elseif ($c -eq '"') { [void]$sb.Append('\"') }
            else                { [void]$sb.Append($c) }
        }
        [void]$sb.Append('"')
    }
    $sb.ToString()
}

function Invoke-SqlCmdWithTimeout {
    param([string[]]$SqlCmdArgs, [int]$TimeoutSeconds, [string]$Exe)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $Exe
    $psi.Arguments              = ConvertTo-SqlCmdArgString -ArgumentList $SqlCmdArgs
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.WorkingDirectory       = $PWD.Path

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch {}
        $proc.WaitForExit()
        return [pscustomobject]@{ TimedOut = $true; ExitCode = -1; StdOut = $stdoutTask.Result; StdErr = $stderrTask.Result }
    }
    [pscustomobject]@{ TimedOut = $false; ExitCode = $proc.ExitCode; StdOut = $stdoutTask.Result; StdErr = $stderrTask.Result }
}

# Runs a query/script against one instance with the TLS (-Ndisable) and fallback-sqlcmd
# retries. $QueryArgs is e.g. @('-i', $file) or @('-d', 'db', '-Q', $query).
function Invoke-SqlCmdSmart {
    param([string]$Instance, [string[]]$QueryArgs, [int]$TimeoutSeconds)

    $tmpOut = [System.IO.Path]::GetTempFileName()
    try {
        $useFallback = $false
        $noEnc       = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $exe = if ($useFallback) { $FallbackSqlCmdExe } else { $SqlCmdExe }
            $sqlArgs = @('-E', '-S', $Instance) + $QueryArgs +
                       @('-h', '-1', '-w', '8000', '-W', '-o', $tmpOut, '-l', '30', '-t', $TimeoutSeconds)
            if ($TrustServerCertificate) { $sqlArgs += '-C' }
            if ($noEnc)                  { $sqlArgs += '-Ndisable' }

            $run   = Invoke-SqlCmdWithTimeout -SqlCmdArgs $sqlArgs -TimeoutSeconds ($TimeoutSeconds + 30) -Exe $exe
            $lines = @(Get-Content $tmpOut -ErrorAction SilentlyContinue)

            if (-not $run.TimedOut -and $run.ExitCode -eq 0) {
                return [pscustomobject]@{ Success = $true; Lines = $lines; Detail = $null
                                          NoEncrypt = $noEnc; UsedFallback = $useFallback }
            }
            if ($run.TimedOut) {
                return [pscustomobject]@{ Success = $false; Lines = $lines
                                          Detail = "Timed out after $TimeoutSeconds second(s)."
                                          NoEncrypt = $noEnc; UsedFallback = $useFallback }
            }

            $errLines = @($lines + ($run.StdErr -split "`r?`n") + ($run.StdOut -split "`r?`n") |
                          Where-Object { $_ -and $_.Trim() })
            $errText  = $errLines -join ' '

            if (-not $useFallback -and -not $noEnc -and $errText -match 'TLS Handshake') {
                Write-Host "  TLS handshake failed - retrying without encryption (-Ndisable)..." -ForegroundColor Yellow
                $noEnc = $true
                continue
            }
            if (-not $useFallback -and $FallbackSqlCmdExe) {
                Write-Host "  Connection failed - retrying with $FallbackSqlCmdExe ..." -ForegroundColor Yellow
                $useFallback = $true
                $noEnc       = $false
                continue
            }
            return [pscustomobject]@{ Success = $false; Lines = $lines
                                      Detail = (($errLines | Select-Object -Last 3) -join ' | ') + " (exit code $($run.ExitCode))"
                                      NoEncrypt = $noEnc; UsedFallback = $useFallback }
        }
    }
    finally {
        if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue }
    }
}

# Extracts the text between <<<ROW>>> and <<<END>>> markers.
function Get-MarkedValues {
    param([string[]]$Lines)
    foreach ($l in $Lines) {
        $m = [regex]::Match([string]$l, '<<<ROW>>>(.*?)<<<END>>>')
        if ($m.Success) { $m.Groups[1].Value }
    }
}

# CIM query over WinRM, falling back to DCOM.
# Asks the SQL Server Browser service (UDP 1434) which instances it advertises.
# Returns instance names ('MSSQLSERVER' for the default instance) and TCP ports where given.
function Get-SqlBrowserInstances {
    param([string]$ComputerName, [int]$TimeoutMs = 3000)
    $udp = $null
    try {
        $udp = [System.Net.Sockets.UdpClient]::new()
        $udp.Client.ReceiveTimeout = $TimeoutMs
        $udp.Connect($ComputerName, 1434)
        [void]$udp.Send([byte[]](0x02), 1)                      # CLNT_UCAST_EX: list all instances
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $bytes  = $udp.Receive([ref]$remote)
        if ($bytes.Length -le 3) { return [pscustomobject]@{ Success = $false; Instances = @(); Detail = 'Empty Browser reply' } }

        $text  = [System.Text.Encoding]::ASCII.GetString($bytes, 3, $bytes.Length - 3)   # skip 3-byte header
        $found = foreach ($block in ($text -split ';;')) {
            if (-not $block.Trim()) { continue }
            $kv = @{}
            $parts = $block.Trim(';') -split ';'
            for ($i = 0; $i + 1 -lt $parts.Count; $i += 2) { $kv[$parts[$i]] = $parts[$i + 1] }
            if ($kv.ContainsKey('InstanceName')) {
                [pscustomobject]@{
                    InstanceName = $kv['InstanceName']
                    TcpPort      = if ($kv.ContainsKey('tcp')) { $kv['tcp'] } else { $null }
                }
            }
        }
        [pscustomobject]@{ Success = $true; Instances = @($found); Detail = $null }
    }
    catch { [pscustomobject]@{ Success = $false; Instances = @(); Detail = $_.Exception.Message } }
    finally { if ($udp) { $udp.Close() } }
}

function Get-CimSafe {
    param([string]$ComputerName, [string]$ClassName, [string]$Filter)
    $lastErr = $null
    foreach ($proto in 'Wsman', 'Dcom') {
        $session = $null
        try {
            $opt     = New-CimSessionOption -Protocol $proto
            $session = New-CimSession -ComputerName $ComputerName -SessionOption $opt -OperationTimeoutSec 30 -ErrorAction Stop
            $p = @{ CimSession = $session; ClassName = $ClassName; ErrorAction = 'Stop' }
            if ($Filter) { $p['Filter'] = $Filter }
            $data = @(Get-CimInstance @p)
            return [pscustomobject]@{ Success = $true; Data = $data; Detail = $null }
        }
        catch { $lastErr = $_.Exception.Message }
        finally { if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue } }
    }
    [pscustomobject]@{ Success = $false; Data = @(); Detail = $lastErr }
}

# Bulk-loads rows into a table via SqlBulkCopy, creating the table / adding columns as needed.
function Write-InventoryTable {
    param($Rows, [string[]]$Columns, [string]$Server, [string]$Database, [string]$Table)

    if ($Table -notmatch '^[\w\[\]]+(\.[\w\[\]]+)?$') { throw "Invalid table name '$Table'." }

    $cs = "Server=$Server;Database=$Database;Integrated Security=SSPI;Application Name=SqlHostInventory"
    if ($TrustServerCertificate) { $cs += ';TrustServerCertificate=True' }

    $conn = [System.Data.SqlClient.SqlConnection]::new($cs)
    $conn.Open()
    try {
        $colDefs = ($Columns | ForEach-Object { "[$_] nvarchar(512) NULL" }) -join ",`n    "
        $addCols = ($Columns | ForEach-Object {
            "IF COL_LENGTH(N'$Table', N'$_') IS NULL ALTER TABLE $Table ADD [$_] nvarchar(512) NULL;"
        }) -join "`n"
        $ddl = "IF OBJECT_ID(N'$Table', N'U') IS NULL CREATE TABLE $Table (`n    $colDefs`n);`n$addCols"

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $ddl
        [void]$cmd.ExecuteNonQuery()

        $dt = [System.Data.DataTable]::new()
        foreach ($c in $Columns) { [void]$dt.Columns.Add($c, [string]) }
        foreach ($r in $Rows) {
            $dr = $dt.NewRow()
            foreach ($c in $Columns) {
                $v = $r.$c
                if ($null -eq $v -or [string]$v -eq '') { $dr[$c] = [DBNull]::Value } else { $dr[$c] = [string]$v }
            }
            $dt.Rows.Add($dr)
        }

        $bc = [System.Data.SqlClient.SqlBulkCopy]::new($conn)
        $bc.DestinationTableName = $Table
        $bc.BulkCopyTimeout      = 300
        foreach ($c in $Columns) { [void]$bc.ColumnMappings.Add($c, $c) }
        $bc.WriteToServer($dt)
        $dt.Rows.Count
    }
    finally { $conn.Close() }
}

# ---------------------------------------------------------------------------
# Validate inputs / output folders / logging
# ---------------------------------------------------------------------------
if (-not (Test-Path $SqlScriptPath)) {
    Write-Host "`nInventory SQL script not found: '$SqlScriptPath'. Put SqlHostInventory_Row.sql next to this script or pass -SqlScriptPath.`n" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $InstanceListPath)) {
    Write-Host "`nInstance file not found: '$InstanceListPath'" -ForegroundColor Red
    Write-Host "Create it (one instance per line, e.g. 'SERVER01' or 'SERVER01\SQL01B'), or pass -InstanceListPath.`n" -ForegroundColor Yellow
    exit 1
}
if ($WriteToTable -and (-not $TargetServer -or -not $TargetDatabase)) {
    Write-Host "`n-WriteToTable needs both -TargetServer and -TargetDatabase (where to create the staging table).`n" -ForegroundColor Red
    exit 1
}
# Staging table name always ends in _stagging (bracket-aware: dbo.[X] -> dbo.[X_stagging])
$StagingTable = $StagingTable.Trim()
if ($StagingTable -notmatch '(?i)_stagging\]?$') {
    if ($StagingTable.EndsWith(']')) { $StagingTable = $StagingTable.Substring(0, $StagingTable.Length - 1) + '_stagging]' }
    else                             { $StagingTable = $StagingTable + '_stagging' }
}

$OutputFolder = if ([System.IO.Path]::IsPathRooted($OutputFolder)) { $OutputFolder } else { Join-Path $PWD.Path $OutputFolder }
$OutputFolder = [System.IO.Path]::GetFullPath($OutputFolder)
$OutDir       = Join-Path $OutputFolder 'inventory_output'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$RunStamp          = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile           = Join-Path $OutDir ("run_{0}.log" -f $RunStamp)
$TranscriptStarted = $false
try {
    Start-Transcript -Path $LogFile -Append -ErrorAction Stop | Out-Null
    $TranscriptStarted = $true
    Write-Host "Logging full run output to: $LogFile" -ForegroundColor Cyan
}
catch { Write-Warning "Could not start transcript logging ($($_.Exception.Message)) - console output only." }

function Exit-Script {
    param([int]$Code = 0)
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    exit $Code
}

# ---------------------------------------------------------------------------
# Build instance list
# ---------------------------------------------------------------------------
Write-Header "Finding instances on each server"

Write-Host "Reading servers from: $InstanceListPath" -ForegroundColor Yellow
$serverNames = @(Get-Content $InstanceListPath |
    Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { ($_ -split '\|', 2)[0].Trim() } | Where-Object { $_ } |
    Sort-Object -Unique)

if ($serverNames.Count -eq 0) {
    Write-Warning "No servers found in '$InstanceListPath'. Nothing to do."
    Exit-Script -Code 0
}
Write-Host "Servers in file: $($serverNames.Count)" -ForegroundColor Cyan

$rows    = [System.Collections.Generic.List[object]]::new()
$status  = [System.Collections.Generic.List[object]]::new()
$targets = [System.Collections.Generic.List[object]]::new()   # instances to query

foreach ($server in $serverNames) {
    # A line with \INSTANCE or ,PORT is already an instance - use it as-is.
    if ($server -match '[\\,]') {
        $targets.Add([pscustomobject]@{ Server = ($server -split '[\\,]')[0]; Instance = $server; Method = 'AsListed' })
        Write-Host "  $server : used as listed" -ForegroundColor DarkGray
        continue
    }

    # 1. Windows services
    $svcFilter = "Name='MSSQLSERVER' OR Name LIKE 'MSSQL`$%'"
    $cim = Get-CimSafe -ComputerName $server -ClassName Win32_Service -Filter $svcFilter
    if ($cim.Success -and $cim.Data.Count -gt 0) {
        $names = @()
        foreach ($svc in $cim.Data) {
            $instName = if ($svc.Name -eq 'MSSQLSERVER') { 'DEFAULT' } else { $svc.Name.Substring(6) }
            $connect  = if ($svc.Name -eq 'MSSQLSERVER') { $server } else { "$server\$instName" }
            if ($svc.State -eq 'Running') {
                $targets.Add([pscustomobject]@{ Server = $server; Instance = $connect; Method = 'WindowsServices' })
                $names += $instName
            }
            else {
                $names += "$instName (stopped)"
                $status.Add([pscustomobject]@{
                    Server = $server; Instance = $connect; Status = 'STOPPED'; Rows = 0
                    InstanceType = if ($instName -eq 'DEFAULT') { 'Default' } else { 'Named' }
                    HostType = $null; DiscoveryMethod = 'WindowsServices'
                    NoEncrypt = $false; UsedFallback = $false
                    Detail = "Service $($svc.Name) is $($svc.State)"
                })
            }
        }
        Write-Host "  $server : $($names -join ', ')  [services]" -ForegroundColor DarkGray
        continue
    }
    if ($cim.Success) {
        Write-Host "  $server : no SQL Server engine services found  [services]" -ForegroundColor DarkYellow
        $status.Add([pscustomobject]@{
            Server = $server; Instance = $server; Status = 'NO SQL'; Rows = 0
            InstanceType = $null; HostType = $null; DiscoveryMethod = 'WindowsServices'
            NoEncrypt = $false; UsedFallback = $false
            Detail = 'No MSSQLSERVER or MSSQL$ services on this server'
        })
        continue
    }

    # 2. SQL Server Browser
    $br = Get-SqlBrowserInstances -ComputerName $server
    if ($br.Success -and $br.Instances.Count -gt 0) {
        $names = @()
        foreach ($bi in $br.Instances) {
            if ($bi.InstanceName -eq 'MSSQLSERVER') {
                $targets.Add([pscustomobject]@{ Server = $server; Instance = $server; Method = 'SqlBrowser' })
                $names += 'DEFAULT'
            }
            else {
                $targets.Add([pscustomobject]@{ Server = $server; Instance = "$server\$($bi.InstanceName)"; Method = 'SqlBrowser' })
                $names += $bi.InstanceName
            }
        }
        Write-Host "  $server : $($names -join ', ')  [SQL Browser]" -ForegroundColor DarkGray
        continue
    }

    # 3. Nothing reachable - try it as a default instance
    Write-Host "  $server : services and SQL Browser not reachable - trying as default instance only" -ForegroundColor DarkYellow
    $targets.Add([pscustomobject]@{ Server = $server; Instance = $server; Method = 'AssumedDefault' })
}

if ($targets.Count -eq 0) {
    Write-Warning "No running instances found on any server."
}
Write-Host "Instances to query: $($targets.Count)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------
Write-Header "Collecting inventory"

$n = 0
foreach ($t in $targets) {
    $srv = $t.Instance
    $n++
    Write-Host "[$n/$($targets.Count)] $srv" -ForegroundColor Yellow

    $res = Invoke-SqlCmdSmart -Instance $srv -QueryArgs @('-I', '-i', $SqlScriptPath) -TimeoutSeconds $TimeoutSeconds
    $rowCount = 0
    $detail   = $null

    if ($res.Success) {
        foreach ($v in @(Get-MarkedValues -Lines $res.Lines)) {
            $vals = $v -split '\|'
            if ($vals.Count -ne $InventoryColumns.Count) {
                $detail = "Unexpected column count $($vals.Count) (expected $($InventoryColumns.Count))."
                continue
            }
            $o = [ordered]@{}
            for ($k = 0; $k -lt $InventoryColumns.Count; $k++) { $o[$InventoryColumns[$k]] = $vals[$k] }
            $o['SourceServer']    = $t.Server
            $o['CollectedFrom']   = $srv
            $o['DiscoveryMethod'] = $t.Method
            $o['HWManufacturer'] = ''
            $o['HWModel']        = ''
            $o['HWHostType']     = ''
            $o['RunId']          = $RunStamp
            $rows.Add([pscustomobject]$o)
            $rowCount++
        }
        if ($rowCount -eq 0 -and -not $detail) {
            # sqlcmd connected but the script errored (e.g. SQL 2000, permissions) - show why
            $detail = (@($res.Lines | Where-Object { $_ -and $_.Trim() }) | Select-Object -Last 3) -join ' | '
            if (-not $detail) { $detail = 'No rows returned.' }
        }
    }
    else { $detail = $res.Detail }

    $state = if ($rowCount -gt 0) { 'OK' } else { 'FAILED' }
    $last  = if ($rowCount -gt 0) { $rows[$rows.Count - 1] } else { $null }
    if ($state -eq 'OK') {
        Write-Host ("  OK - {0} | {1} | {2} {3}" -f $last.HostType, $last.InstanceDisplay, $last.SQLVersionName, $last.SQLVersionNumber) -ForegroundColor Green
    }
    else {
        Write-Host "  FAILED: $detail" -ForegroundColor Red
    }

    $status.Add([pscustomobject]@{
        Server          = $t.Server
        Instance        = $srv
        Status          = $state
        Rows            = $rowCount
        InstanceType    = if ($last) { $last.InstanceType } else { $null }
        HostType        = if ($last) { $last.HostType } else { $null }
        DiscoveryMethod = $t.Method
        NoEncrypt    = $res.NoEncrypt
        UsedFallback = $res.UsedFallback
        Detail       = $detail
    })
}

# ---------------------------------------------------------------------------
# De-duplicate (same instance listed under different names, e.g. short name + FQDN)
# ---------------------------------------------------------------------------
$beforeDedup = $rows.Count
$rows = @($rows | Group-Object { "$($_.SqlInstanceName)|$($_.AGName)".ToLowerInvariant() } | ForEach-Object { $_.Group[0] })
if ($beforeDedup -ne $rows.Count) {
    Write-Host "`nRemoved $($beforeDedup - $rows.Count) duplicate row(s) (same instance reached under different names)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Hardware cross-check (optional)
# ---------------------------------------------------------------------------
$mismatches = @()
if ($CollectHardware -and $rows.Count -gt 0) {
    Write-Header "Collecting hardware details"
    $hwCache   = @{}
    $vmPattern = '(?i)virtual|vmware|kvm|qemu|xen|hvm domu|amazon ec2|google compute|openstack|bochs|parallels|nutanix'
    foreach ($r in $rows) {
        $node   = if ($r.PhysicalNodeName) { $r.PhysicalNodeName } else { $r.ServerName }
        $suffix = if ($r.'Server Name FQDN' -match '^[^.]+\.(.+)$') { $Matches[1] } else { '' }
        $target = if ($suffix) { "$node.$suffix" } else { $node }

        if (-not $hwCache.ContainsKey($target)) {
            $cim = Get-CimSafe -ComputerName $target -ClassName Win32_ComputerSystem
            if ($cim.Success -and $cim.Data.Count -gt 0) {
                $hwCache[$target] = $cim.Data[0]
                Write-Host "  $target : $($cim.Data[0].Manufacturer) / $($cim.Data[0].Model)" -ForegroundColor DarkGray
            }
            else {
                $hwCache[$target] = $null
                Write-Host "  $target : hardware query failed ($($cim.Detail))" -ForegroundColor DarkYellow
            }
        }
        $hw = $hwCache[$target]
        if ($hw) {
            $r.HWManufacturer = [string]$hw.Manufacturer
            $r.HWModel        = [string]$hw.Model
            $r.HWHostType     = if ("$($hw.Manufacturer) $($hw.Model)" -match $vmPattern) { 'Virtual' } else { 'Physical' }
        }
    }
    $mismatches = @($rows | Where-Object { $_.HWHostType -and $_.HostType -ne 'Unknown' -and $_.HWHostType -ne $_.HostType })
}

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
Write-Header "Run Summary"

$csvPath    = Join-Path $OutDir ("SqlHostInventory_{0}.csv" -f $RunStamp)
$failedPath = Join-Path $OutDir ("SqlHostInventory_Failed_{0}.csv" -f $RunStamp)

$rows | Select-Object $AllColumns | Export-Csv -Path $csvPath -NoTypeInformation
$failedList = @($status | Where-Object { $_.Status -ne 'OK' })
if ($failedList.Count -gt 0) { $failedList | Export-Csv -Path $failedPath -NoTypeInformation }

$status | Sort-Object Server, Instance |
    Select-Object Server, Instance, Status, InstanceType, HostType, DiscoveryMethod, Rows | Format-Table -AutoSize

$okCount      = @($status | Where-Object { $_.Status -eq 'OK' }).Count
$stoppedCount = @($status | Where-Object { $_.Status -eq 'STOPPED' }).Count
$failCount    = @($status | Where-Object { $_.Status -eq 'FAILED' }).Count
Write-Host ("Servers: {0}. Instances: {1} OK, {2} FAILED, {3} STOPPED. Rows: {4}." -f `
    $serverNames.Count, $okCount, $failCount, $stoppedCount, $rows.Count) -ForegroundColor $(if ($failCount) { 'Yellow' } else { 'Green' })

# Breakdown
$rows | Group-Object HostType     | Select-Object @{n='HostType';e={$_.Name}}, Count     | Format-Table -AutoSize
$rows | Group-Object InstanceType | Select-Object @{n='InstanceType';e={$_.Name}}, Count | Format-Table -AutoSize

if ($mismatches.Count -gt 0) {
    Write-Host "HostType disagrees with hardware model on $($mismatches.Count) row(s) - check these:" -ForegroundColor Yellow
    $mismatches | Select-Object SqlInstanceName, HostType, VirtualMachineType, HWManufacturer, HWModel | Format-Table -AutoSize
}

if ($failedList.Count -gt 0) {
    Write-Host "Not collected (failed / stopped / no SQL):" -ForegroundColor Red
    foreach ($f in $failedList) { Write-Host "  [$($f.Status)] $($f.Instance): $($f.Detail)" -ForegroundColor DarkRed }
}

if ($WriteToTable -and $rows.Count -gt 0) {
    try {
        $written = Write-InventoryTable -Rows $rows -Columns $AllColumns -Server $TargetServer -Database $TargetDatabase -Table $StagingTable
        Write-Host "`nWrote $written row(s) to [$TargetServer].[$TargetDatabase].$StagingTable (RunId $RunStamp)." -ForegroundColor Green
    }
    catch {
        Write-Host "`nWrite to $StagingTable failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nInventory CSV : $csvPath" -ForegroundColor Cyan
if ($failedList.Count -gt 0) { Write-Host "Failures CSV  : $failedPath" -ForegroundColor Cyan }
if ($TranscriptStarted)      { Write-Host "Run log       : $LogFile" -ForegroundColor Cyan }
Write-Host "Done.`n" -ForegroundColor Green

Exit-Script -Code $(if ($failCount) { 1 } else { 0 })
