# SQL Server Host Inventory

Collects a host inventory from every SQL Server instance on a list of servers:
physical vs virtual, default vs named instance, version and CU, edition, CPU, memory,
memory settings, AG membership and database count. Results go to a CSV and, optionally,
a staging table.

You list **server names only**. The script finds every instance (default and named) on
each server itself.

---

## Files

Keep all three in the same folder.

| File | Purpose |
|---|---|
| `Invoke-SqlHostInventory.ps1` | The collector. Finds instances, runs the SQL on each, writes CSV / table. |
| `SqlHostInventory_Row.sql` | Query run on each instance. Returns one row per instance (one per AG if it's in several). |
| `instances.txt` | Your list of server names. |

---

## Prerequisites

- **Windows PowerShell 5.1** (or PowerShell 7). No modules needed (no dbatools, no SqlServer module).
- **sqlcmd**: either on PATH, or `sqlcmd.exe` placed next to the script. Both the ODBC sqlcmd and the Go sqlcmd work.
- **SQL permissions** on each instance: `VIEW SERVER STATE`. The FQDN domain lookup (`xp_regread`) normally needs `sysadmin`; without it, `Server Name FQDN` is just the machine name.
- **Windows access** to each server (WinRM or DCOM) to read its services. If that isn't available the script falls back to SQL Browser (UDP 1434), then to the default instance only.
- **For `-WriteToTable`**: CREATE TABLE and INSERT permissions in the target database, which must already exist.

---

## The server file (`instances.txt`)

One server per line. Blank lines and lines starting with `#` are ignored.

```
# Health NZ SQL servers
vprt1cls014.healthcare.HUARAHI.HEALTH.GOVT.NZ
VHAL1CSS18102.healthcare.HUARAHI.HEALTH.GOVT.NZ
vhal3ray001.healthcare.HUARAHI.HEALTH.GOVT.NZ
```

- Use FQDNs if short names don't resolve from the machine you run it on.
- A line written as `SERVER\INSTANCE` or `SERVER,PORT` is used exactly as written, with no discovery.
- For **failover cluster instances**, list the FCI's virtual network name, not the node names.
- An optional `| version` suffix is accepted and ignored, so the same file works with `Invoke-SQLCollection.ps1`.

---

## Running it

If scripts are blocked on the machine ("running scripts is disabled on this system"), start
it through `powershell -ExecutionPolicy Bypass -File`, as below.

**CSV only**

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-SqlHostInventory.ps1
```

**CSV + hardware cross-check + load into a staging table**

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-SqlHostInventory.ps1 `
    -CollectHardware -WriteToTable -TargetServer sqlaoag2019p1.cdhb.local -TargetDatabase nestview
```

**Different server file and output folder**

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-SqlHostInventory.ps1 `
    -InstanceListPath D:\Lists\prod_servers.txt -OutputFolder D:\SQLAudit
```

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-InstanceListPath` | `instances.txt` next to the script | Server file. |
| `-SqlScriptPath` | `SqlHostInventory_Row.sql` next to the script | Query run on each instance. |
| `-OutputFolder` | Current folder | Output goes to `<OutputFolder>\inventory_output\`. |
| `-CollectHardware` | Off | Also reads the hardware manufacturer and model from Windows (see *Physical vs virtual*). |
| `-WriteToTable` | Off | Loads results into the staging table. Needs `-TargetServer` and `-TargetDatabase`. |
| `-TargetServer` | None | Instance to create the staging table on. Use `HOST\INSTANCE` for a named instance. |
| `-TargetDatabase` | None | Database to create the staging table in. Must exist. |
| `-StagingTable` | `dbo.SQLServer_Host_stagging` | Table name. `_stagging` is appended if missing. |
| `-TrustServerCertificate` | Off | Trusts the server TLS certificate (sqlcmd `-C`). |
| `-TimeoutSeconds` | `120` | Per-instance query timeout. A hung instance is killed and the run moves on. |
| `-SqlCmdPath` | Auto | A specific sqlcmd executable. Turns off the fallback-sqlcmd retry. |

---

## How instances are found

For each server, the first method that works is used. The method is recorded in the
`DiscoveryMethod` column.

| Order | Method | Notes |
|---|---|---|
| 1 | `WindowsServices` | Reads services over WinRM, then DCOM. `MSSQLSERVER` = default instance, `MSSQL$<name>` = named. Stopped instances are reported as **STOPPED**. |
| 2 | `SqlBrowser` | Asks the SQL Server Browser service (UDP 1434) which instances it advertises. |
| 3 | `AssumedDefault` | Nothing reachable, so only the default instance is tried. **Named instances on this server are missed** - open WinRM to it, or list them as `SERVER\INSTANCE`. |
| - | `AsListed` | The line already contained `\INSTANCE` or `,PORT`. |

Connection handling (same as `Invoke-SQLCollection.ps1`):
- TLS handshake failure: retried once with encryption disabled (`-Ndisable`, Go sqlcmd).
- Other connection failure: retried with the ODBC sqlcmd from `...\Tools\Binn\`, if one is installed.

---

## Output

Everything is written to `<OutputFolder>\inventory_output\`, with a timestamp in each name:

| File | Contents |
|---|---|
| `SqlHostInventory_<timestamp>.csv` | One combined file with every instance. |
| `SqlHostInventory_Failed_<timestamp>.csv` | Instances that FAILED, were STOPPED, or servers with NO SQL. Only written if there are any. |
| `run_<timestamp>.log` | Full transcript of the console output. |

### Columns

**From SQL Server**

| Column | Notes |
|---|---|
| `Server Name FQDN`, `ServerName` | Machine name, with domain if `xp_regread` is allowed. |
| `PhysicalNodeName` | Node the instance is running on (differs from `ServerName` for an FCI). |
| `InstanceName` | `DEFAULT` or the instance name. |
| `InstanceType` | `Default` or `Named`. |
| `SqlInstanceName` | `HOST` or `HOST\INSTANCE`. |
| `InstanceDisplay` | `Default (MSSQLSERVER)` or `Named (<name>)`. |
| `WindowsOSVersion` | From `@@VERSION`. |
| `SQLVersionNumber`, `SQLVersionName`, `SQLEdition`, `ServicePackLevel`, `CUBundleLevel` | |
| `PhysicalCoreCount`, `LogicalCPUCount` | Physical cores need 2016 SP2+ / 2017+. |
| `TotalOSMemory_MB`, `MinServerMemory_MB`, `MaxServerMemory_MB` | |
| `AGName`, `AGRole` | One row per AG the instance is in. |
| `TotalDatabaseCount` | User databases. |
| `VirtualMachineType` | `NONE`, `HYPERVISOR` or `OTHER` (2008 R2 SP1+). |
| `HostType` | `Physical`, `Virtual` or `Unknown`, from `VirtualMachineType`. |
| `IsClustered`, `IsHadrEnabled`, `CollectedAt` | |

**Added by the script**

| Column | Notes |
|---|---|
| `SourceServer` | The server name from your file. |
| `CollectedFrom` | The connection string used. |
| `DiscoveryMethod` | How the instance was found (see above). |
| `HWManufacturer`, `HWModel`, `HWHostType` | Only with `-CollectHardware`. |
| `RunId` | Run timestamp, e.g. `20261101_123316`. |

---

## Staging table

Only created when `-WriteToTable` is used.

- Created on `-TargetServer` in `-TargetDatabase`, named by `-StagingTable` (default `dbo.SQLServer_Host_stagging`).
- Created on the first run if it doesn't exist; any missing columns are added on later runs.
- All columns are `nvarchar(512)`; empty values are stored as NULL.
- Each run **appends** rows tagged with `RunId`. Nothing is deleted or updated.
- Loaded in one batch with `SqlBulkCopy`, using Windows authentication.

The only other object created is a `#ag` temp table in tempdb on each inventoried
instance, dropped at the end of the query. Nothing permanent is created on those instances.

Rows per run:

```sql
SELECT RunId, COUNT(*) AS Rows
FROM dbo.SQLServer_Host_stagging
GROUP BY RunId
ORDER BY RunId DESC;
```

Latest run only:

```sql
SELECT *
FROM dbo.SQLServer_Host_stagging
WHERE RunId = (SELECT MAX(RunId) FROM dbo.SQLServer_Host_stagging);
```

---

## Physical vs virtual

`HostType` comes from `sys.dm_os_sys_info.virtual_machine_type_desc`. SQL Server reports
`HYPERVISOR` whenever Windows is running on a hypervisor, and that includes **physical**
machines where Windows itself runs on Hyper-V: the Hyper-V role, Credential Guard,
virtualization-based security, or WSL2. Those physical servers show as `Virtual`.

Use `-CollectHardware` for the final answer. It reads the hardware manufacturer and model
(e.g. `Dell Inc. / PowerEdge R740` vs `VMware, Inc. / VMware Virtual Platform`) and sets
`HWHostType`. Rows where `HostType` and `HWHostType` disagree are listed in the run summary.
**Where both are filled in, trust `HWHostType`.**

---

## Troubleshooting

| Message | Cause / fix |
|---|---|
| `running scripts is disabled on this system` | Execution policy. Run with `powershell -ExecutionPolicy Bypass -File .\Invoke-SqlHostInventory.ps1 ...` |
| `Inventory SQL script not found` | `SqlHostInventory_Row.sql` isn't next to the script, or was saved under another name (e.g. with `(1)` or `.txt`). Rename it or pass `-SqlScriptPath`. |
| `Instance file not found` | No `instances.txt` next to the script. Create it or pass `-InstanceListPath`. |
| `sqlcmd not found` | Install sqlcmd, put `sqlcmd.exe` next to the script, or pass `-SqlCmdPath`. |
| `TerminatingError(New-CimSession) ... WinRM` in the log | Harmless if the next line lists instances with `[services]`: WinRM failed and DCOM worked. |
| `services and SQL Browser not reachable` | Neither WinRM/DCOM nor UDP 1434 is open to that server. Only the default instance is tried. |
| `Write to ... failed: ... error: 40 - Could not open a connection` | `-TargetServer` points at a default instance that doesn't exist. Use `HOST\INSTANCE` for a named instance (e.g. `localhost\SQLDEV`). |
| `-WriteToTable needs both -TargetServer and -TargetDatabase` | Pass both. |
| `FAILED` with SQL errors in the detail | Usually permissions (no `VIEW SERVER STATE`) or SQL Server 2000, which isn't supported. |

Full details for every run are in `inventory_output\run_<timestamp>.log`.
