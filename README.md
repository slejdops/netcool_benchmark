# Netcool Environment Audit & Benchmark Tool

**Version 2.0** - Now with JSON/XML export, historical trending, and active stress testing!

## Overview

The `netcool_audit.sh` script is a comprehensive bash utility designed to audit, profile, and benchmark IBM Tivoli Netcool/OMNIbus environments. It performs assessments of your Netcool infrastructure against IBM best practices and generates detailed health and tuning reports.

**New in v2.0**: Machine-readable output formats (JSON/XML), historical trend analysis, and optional active stress testing capabilities.

## Features

### Comprehensive Component Coverage

- **Netcool/OMNIbus ObjectServer**: Configuration validation, performance profiling, trigger analysis
- **Probes**: Log analysis, connectivity health, event processing metrics
- **Gateways**: Replication health, buffer analysis, connection stability
- **Netcool Impact**: JVM configuration, cluster setup, service health
- **WebGUI/JazzSM**: JVM settings, service status, log analysis

### NEW in v2.0: Advanced Features

- **JSON/XML Export** (`--format json|xml`): Machine-readable output for integration with monitoring systems, dashboards, and automation pipelines
- **Historical Trending** (`--enable-trending`, `--compare-previous`): Track audit results over time, compare with previous runs, identify trends
- **Active Stress Testing** (`--stress-test`): Inject synthetic events to measure ObjectServer performance under load (optional, requires confirmation)

### Safety First

- **Standard Mode: 100% Read-Only**: No modifications to configurations or services
- **Non-Intrusive**: Does not restart services or inject events (unless `--stress-test` is explicitly used)
- **Production Safe**: Standard audit mode can be run on live production systems without risk
- **Stress Test Mode**: Optional active testing with safety confirmations and automatic cleanup

### Intelligent Analysis

- **Auto-Discovery**: Automatically detects `$NCHOME`, `$OMNIHOME`, and component installations
- **Embedded Baselines**: Built-in IBM recommended best practices for comparison
- **Color-Coded Output**: Green (Pass), Yellow (Warning), Red (Failure) for easy interpretation
- **Actionable Recommendations**: Specific remediation steps for identified issues
- **Structured Export**: Full audit results available in JSON or XML format

## Requirements

### System Requirements

- Operating System: RHEL/CentOS 6+, SLES, or AIX 6.1+
- Bash version: 4.0 or higher
- Run as: Netcool service account (typically `netcool` user)

### Access Requirements

- Read access to Netcool installation directories
- For ObjectServer profiling: Valid ObjectServer credentials (optional, can be skipped)
- Standard Unix utilities: `grep`, `awk`, `sed`, `ps`, `find`

### Optional Components

- `nco_sql`: Required for ObjectServer performance profiling
- `nco_pad`: Used for process discovery if available
- `sysctl`: For kernel parameter validation (Linux only)

## Installation

1. Download the script to your Netcool server:
   ```bash
   curl -O https://your-repo/netcool_audit.sh
   # or
   scp netcool_audit.sh netcool@netcool-server:/tmp/
   ```

2. Make it executable:
   ```bash
   chmod +x netcool_audit.sh
   ```

3. Ensure you're running as the Netcool user:
   ```bash
   su - netcool
   # or
   sudo -u netcool -i
   ```

## Usage

### Basic Usage

```bash
# Run standard audit (read-only)
./netcool_audit.sh

# Run with verbose output
./netcool_audit.sh --verbose

# Save report to file
./netcool_audit.sh --output /tmp/netcool_audit_report.txt

# Skip ObjectServer SQL profiling
./netcool_audit.sh --skip-sql

# Run without colors (for logging)
./netcool_audit.sh --no-color
```

### NEW v2.0 Usage Examples

```bash
# Export as JSON
./netcool_audit.sh --format json --output audit_report.json

# Export as XML
./netcool_audit.sh --format xml --output audit_report.xml

# Enable historical trending
./netcool_audit.sh --enable-trending --compare-previous

# Run stress test (requires confirmation)
./netcool_audit.sh --stress-test --stress-events 500

# Combined: trending + JSON export
./netcool_audit.sh --enable-trending --format json --output report.json
```

### Command-Line Options

#### Standard Options

| Option | Description |
|--------|-------------|
| `--help`, `-h` | Display usage information |
| `--output FILE` | Save report to specified file |
| `--no-color` | Disable colored output (for log files) |
| `--verbose`, `-v` | Enable detailed debug logging |
| `--skip-sql` | Skip ObjectServer SQL queries |

#### NEW v2.0 Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format: `text` (default), `json`, or `xml` |
| `--enable-trending` | Save results for historical comparison |
| `--compare-previous` | Compare with previous audit results |
| `--history-dir DIR` | Custom directory for historical data |
| `--stress-test` | Enable active stress testing (requires confirmation) |
| `--stress-events COUNT` | Number of test events (default: 100) |
| `--stress-duration SEC` | Observation period in seconds (default: 60) |

See [FEATURES_V2.md](FEATURES_V2.md) for detailed documentation on new features.

### Example Workflows

#### Quick Health Check

```bash
./netcool_audit.sh --skip-sql
```

#### JSON Export for Monitoring Integration

```bash
# Generate JSON and send to monitoring system
./netcool_audit.sh --format json | curl -X POST https://monitoring.company.com/api/netcool \
  -H "Content-Type: application/json" \
  -d @-
```

#### Weekly Trending Report

```bash
# Add to cron for weekly comparison
./netcool_audit.sh --compare-previous --enable-trending \
  --output /var/log/netcool/weekly_audit.txt
```

#### Pre-Deployment Stress Test

```bash
# Validate performance before go-live
./netcool_audit.sh --stress-test --stress-events 1000 --stress-duration 120 \
  --format json --output pre_deployment_test.json
```

This performs a rapid assessment without requiring ObjectServer credentials.

#### Full Production Audit

```bash
./netcool_audit.sh --output /var/log/netcool_audit_$(date +%Y%m%d).txt
```

Performs complete audit including SQL profiling and saves timestamped report.

#### Automated Daily Monitoring

```bash
# Add to cron (as netcool user)
0 2 * * * /opt/netcool/scripts/netcool_audit.sh --no-color --output /var/log/netcool_daily_audit.log
```

## Embedded IBM Best Practice Baselines

The script includes the following IBM-recommended baselines:

### OS Level
- **ulimit -n (open files)**: ≥ 65,536
- **Kernel Semaphores (SEMMSL)**: ≥ 250
- **Kernel Semaphores (SEMMNS)**: ≥ 32,000
- **Kernel Semaphores (SEMOPM)**: ≥ 32
- **Kernel Semaphores (SEMMNI)**: ≥ 128

### ObjectServer
- **Minimum Memory**: 2048 MB
- **Max Connections Warning**: 1,000
- **Max Disabled Triggers**: 5
- **Trigger Performance Threshold**: 100ms average execution time

### Netcool Impact
- **Minimum Heap (Production)**: 4 GB
- **Recommended Maximum Heap**: 16 GB
- **GC Algorithm**: G1GC (recommended for large heaps)

### WebGUI/JazzSM
- **Minimum Heap**: 2 GB
- **Recommended Maximum Heap**: 8 GB

### Probes & Gateways
- **Max Acceptable Disconnects**: 10 (in recent logs)
- **Gateway Lag Warning**: 30 seconds

## Understanding the Output

### Check Results

The script uses a three-tier classification system:

- **[PASS]** (Green): Configuration meets or exceeds IBM best practices
- **[WARN]** (Yellow): Configuration is functional but suboptimal; review recommended
- **[FAIL]** (Red): Configuration below minimum requirements; action required

### Recommendations

At the end of the audit, you'll receive prioritized recommendations:

- **[HIGH]**: Critical issues affecting performance or stability - address immediately
- **[MEDIUM]**: Suboptimal configurations - plan remediation
- **[LOW]**: Minor optimizations - consider for future maintenance

### Exit Codes

- `0`: All checks passed
- `1`: One or more failures detected
- `2`: Warnings present but no failures

## What the Script Checks

### System Level Checks

1. **Operating System Configuration**
   - OS type and version
   - CPU core count
   - Total system memory
   - User limits (ulimit)
   - Kernel parameters (semaphores, shared memory)
   - Network tuning (TCP keepalive)
   - Firewall status

### ObjectServer Checks

2. **Configuration Audit**
   - `omnibus.env` validation
   - Server properties files (`.props`)
   - Security audit level settings
   - Message log levels
   - Memory threshold settings
   - Profiler configuration

3. **Performance Profiling** (requires credentials)
   - Active client connections by type
   - Trigger performance analysis (via profiler)
   - Table size statistics
   - Alert severity distribution
   - Disabled trigger count

### Impact Checks

4. **JVM Configuration**
   - Heap size settings (-Xms, -Xmx)
   - Garbage collector algorithm
   - Running process detection

5. **Cluster Configuration**
   - Cluster mode (standalone vs. clustered)
   - Cluster member list
   - High availability setup

6. **Service Health**
   - Log file analysis
   - Recent error detection
   - Service uptime verification

### WebGUI Checks

7. **JVM Settings**
   - WebSphere/Liberty heap configuration
   - Process detection and validation

8. **Service Status**
   - Log directory scanning
   - Recent error analysis (24-hour window)

### Probe & Gateway Checks

9. **Probe Health**
   - Log file discovery
   - Disconnect event counting
   - Event processing time analysis
   - Connection stability assessment

10. **Gateway Health**
    - Writer buffer status
    - Replication lag detection
    - Connection error tracking
    - Failover pair synchronization

## Sample Output

```
╔════════════════════════════════════════════════════════════╗
║   Netcool Environment Audit & Benchmark Tool v1.0          ║
║   IBM Tivoli Netcool/OMNIbus Health Assessment            ║
╚════════════════════════════════════════════════════════════╝

Starting audit at: 2025-11-06 14:30:00
This script performs READ-ONLY operations and is safe for production

============================================
System Information Discovery
============================================
[INFO] Hostname: netcool-prod-01
[INFO] OS Type: RHEL
[INFO] OS Version: Red Hat Enterprise Linux Server release 7.9
[INFO] Kernel: 3.10.0-1160.el7.x86_64
[INFO] Architecture: x86_64
[INFO] CPU Cores: 16
[INFO] Total RAM: 65536 MB

--- Netcool Installation Discovery ---
[PASS] NCHOME already set: /opt/IBM/tivoli/netcool
[PASS] OMNIHOME already set: /opt/IBM/tivoli/netcool/omnibus
[INFO] Detected Impact installation: /opt/IBM/tivoli/netcool/impact
[INFO] Detected WebGUI installation: /opt/IBM/JazzSM

============================================
OS Level Configuration Audit
============================================

--- User Limits (ulimit) Check ---
[INFO] Open Files - Soft Limit: 65536
[INFO] Open Files - Hard Limit: 65536
[PASS] Open files limit (65536) meets baseline (>= 65536)
[PASS] Max user processes limit is adequate
[PASS] Stack size is adequate

--- Kernel Parameter Check ---
[INFO] Kernel Semaphores: 250 32000 32 128
[PASS] Kernel semaphore settings meet IBM baseline requirements

============================================
ObjectServer Configuration Audit
============================================

--- ObjectServer Properties Files ---
[INFO] Found 2 ObjectServer property file(s)
[INFO] Analyzing: NCOMS
  [PASS] Security auditing is enabled
  [INFO] MemThreshold: 2048
  [WARN] Profiler may not be configured

============================================
Audit Summary Report
============================================

==========================================
Netcool Environment Audit Results
==========================================

[INFO] Audit completed at: 2025-11-06 14:32:15
[INFO] Total execution time: 135 seconds

PASSED CHECKS: 15
WARNINGS: 3
FAILURES: 0

WARNING DETAILS:
  - Profiler may not be configured

==========================================
RECOMMENDATIONS & REMEDIATION STEPS
==========================================

MEDIUM PRIORITY:
  [MEDIUM] Enable profiler_report trigger group for performance diagnostics
  [MEDIUM] Review Impact logs for errors: /opt/IBM/tivoli/netcool/impact/logs/nci.log

==========================================
End of Audit Report
==========================================
```

## Troubleshooting

### Script Won't Run

**Problem**: Permission denied
```bash
bash: ./netcool_audit.sh: Permission denied
```

**Solution**: Make the script executable
```bash
chmod +x netcool_audit.sh
```

### NCHOME Not Detected

**Problem**: Script cannot find Netcool installation
```
[FAIL] NCHOME not set and could not be auto-detected
```

**Solution**: Manually set environment variable
```bash
export NCHOME=/path/to/netcool
export OMNIHOME=$NCHOME/omnibus
./netcool_audit.sh
```

### ObjectServer Connection Fails

**Problem**: Cannot connect for SQL profiling
```
[FAIL] Failed to connect to ObjectServer: NCOMS
```

**Solution**:
1. Verify credentials are correct
2. Check ObjectServer is running: `nco_pad -list`
3. Use `--skip-sql` to bypass SQL checks
4. Verify network connectivity to ObjectServer port (typically 4100)

### No Color Output

**Problem**: Color codes showing as text
```
^[[0;32m[PASS]^[[0m Test
```

**Solution**: Use `--no-color` flag or check terminal supports ANSI colors

## Advanced Usage

### Integrating with Monitoring Systems

Export results to monitoring platforms:

```bash
# Run audit and capture exit code
./netcool_audit.sh --no-color --output /tmp/audit.log
EXIT_CODE=$?

# Send to monitoring system
if [ $EXIT_CODE -eq 0 ]; then
    send_metric "netcool.audit.status" "OK"
elif [ $EXIT_CODE -eq 1 ]; then
    send_alert "netcool.audit.status" "CRITICAL - Failures detected"
else
    send_alert "netcool.audit.status" "WARNING - Issues detected"
fi
```

### Customizing Baselines

To adjust baselines for your environment, edit the script variables:

```bash
# Edit the script
vi netcool_audit.sh

# Locate and modify baseline variables (around line 60)
BASELINE_ULIMIT_NOFILE=65536           # Change to your requirement
BASELINE_IMPACT_HEAP_MIN_GB=8          # Increase for larger environments
```

### Running Remotely

Execute audit on remote Netcool servers:

```bash
ssh netcool@remote-server 'bash -s' < netcool_audit.sh
```

## Security Considerations

- Script requires **read-only access** - no write operations performed
- ObjectServer passwords are prompted interactively (not stored)
- Password input uses `-s` flag (silent mode - no echo to screen)
- All credentials are handled in memory only
- Consider using `.pgpass` file for automated ObjectServer authentication

## Future Enhancements

The following features are planned for future releases:

- **Active Stress Testing**: `--stress-test` flag to inject synthetic events
- **JSON/XML Output**: Machine-readable report formats
- **Historical Trending**: Compare audit results over time
- **Email Notifications**: Automatic report distribution
- **Webhook Integration**: Push results to external systems
- **Custom Check Plugins**: User-defined audit modules

## Support & Contributions

### Reporting Issues

If you encounter problems:
1. Run with `--verbose` flag to capture detailed logs
2. Check the troubleshooting section above
3. Review the script output for specific error messages

### Best Practices

- Run audit during maintenance windows for most accurate assessment
- Execute from Netcool service account for proper permissions
- Review recommendations with IBM documentation before implementing
- Test configuration changes in non-production environments first
- Keep audit reports for compliance and historical tracking

## References

### IBM Documentation

- [IBM Netcool/OMNIbus Administration Guide](https://www.ibm.com/docs/en/netcoolomnibus)
- [ObjectServer Performance Tuning](https://www.ibm.com/docs/en/netcoolomnibus/8.1.0?topic=objectserver-performance-tuning)
- [Impact Server Configuration](https://www.ibm.com/docs/en/netcool-impact)
- [Netcool WebGUI Administration](https://www.ibm.com/docs/en/netcool-impact)

### IBM Redbooks

- "IBM Tivoli Netcool/OMNIbus: Implementation and Performance Optimization"
- "High Availability and Disaster Recovery Options for Netcool/OMNIbus"

## Version History

- **v1.0** (2025-11-06): Initial release
  - Complete component coverage (ObjectServer, Impact, WebGUI, Probes, Gateways)
  - OS-level configuration validation
  - Performance profiling via SQL
  - Color-coded reporting with prioritized recommendations

## License

This script is provided as-is for use in IBM Tivoli Netcool/OMNIbus environments.

---

**Author**: SRE Team
**Version**: 1.0
**Last Updated**: 2025-11-06
