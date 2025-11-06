# Netcool Audit Script - Quick Start Guide

## 5-Minute Quick Start

### Step 1: Basic Setup (30 seconds)

```bash
# Switch to netcool user
su - netcool

# Navigate to script location
cd /path/to/netcool_audit

# Verify script is executable
ls -l netcool_audit.sh
# Should show: -rwxr-xr-x ... netcool_audit.sh
```

### Step 2: First Run - No SQL (2 minutes)

Run a quick audit without ObjectServer queries:

```bash
./netcool_audit.sh --skip-sql
```

This will check:
- ✅ OS configuration (ulimits, kernel params)
- ✅ Netcool installation detection
- ✅ Process discovery
- ✅ Impact/WebGUI JVM settings
- ✅ Probe/Gateway log analysis
- ❌ ObjectServer SQL profiling (skipped)

### Step 3: Full Audit with SQL (5 minutes)

Run complete audit with ObjectServer profiling:

```bash
./netcool_audit.sh
```

When prompted:
```
Enter ObjectServer name: NCOMS
Enter username (default: root): root
Enter password: ******
```

This adds:
- ✅ Active connection analysis
- ✅ Trigger performance profiling
- ✅ Table statistics
- ✅ Alert distribution

## Common Use Cases

### Use Case 1: Daily Health Check

**Scenario**: You want a quick daily health check without SQL overhead.

```bash
./netcool_audit.sh --skip-sql --no-color > /var/log/netcool_daily_health.log
```

**When**: Add to cron for 2 AM daily execution
```bash
0 2 * * * /opt/netcool/scripts/netcool_audit.sh --skip-sql --no-color > /var/log/netcool_daily_health.log 2>&1
```

### Use Case 2: Pre-Change Baseline

**Scenario**: You're planning changes and want a before/after comparison.

```bash
# Before change
./netcool_audit.sh --output /tmp/audit_before_change_$(date +%Y%m%d_%H%M).txt

# Make your changes...

# After change
./netcool_audit.sh --output /tmp/audit_after_change_$(date +%Y%m%d_%H%M).txt

# Compare
diff /tmp/audit_before_change_*.txt /tmp/audit_after_change_*.txt
```

### Use Case 3: Performance Investigation

**Scenario**: Users report slowness, you need to identify bottlenecks.

```bash
# Run with verbose logging for maximum detail
./netcool_audit.sh --verbose --output /tmp/perf_investigation.log
```

**Focus on**:
- Trigger execution times in profiler section
- Connection counts
- Table sizes
- JVM heap usage

### Use Case 4: New Installation Validation

**Scenario**: Fresh Netcool installation, verify against best practices.

```bash
./netcool_audit.sh --output /tmp/new_install_audit.txt
```

**Expected**: Few or no failures for a properly installed system.

### Use Case 5: Remote Server Audit

**Scenario**: Audit multiple Netcool servers from central location.

```bash
# Single remote server
ssh netcool@server1 'bash -s' < netcool_audit.sh --skip-sql

# Multiple servers
for server in server1 server2 server3; do
    echo "Auditing $server..."
    ssh netcool@$server 'bash -s' < netcool_audit.sh --skip-sql --no-color > audit_${server}.log
done
```

## Reading the Output

### Understanding Check Results

```
[PASS] ✅ Everything is good - meets IBM best practices
[WARN] ⚠️  Suboptimal but functional - review recommended
[FAIL] ❌ Below minimum requirements - action needed
```

### Priority Levels in Recommendations

| Priority | When to Address | Impact |
|----------|----------------|--------|
| **[HIGH]** | Immediately / This week | Performance, stability, or security risk |
| **[MEDIUM]** | Within 1-2 months | Suboptimal configuration, future issues |
| **[LOW]** | Next maintenance window | Minor optimizations |

### Exit Codes for Automation

```bash
./netcool_audit.sh
EXIT_CODE=$?

case $EXIT_CODE in
    0) echo "✅ Perfect - all checks passed" ;;
    1) echo "❌ Critical - failures detected" ;;
    2) echo "⚠️  Warnings present - review needed" ;;
esac
```

## Top 10 Most Common Issues

Based on typical enterprise deployments, here are the most frequently flagged issues:

### 1. Low ulimit for Open Files

**Symptom**:
```
[FAIL] Open files limit (1024) below baseline (65536)
```

**Fix**:
```bash
# Edit /etc/security/limits.conf
netcool soft nofile 65536
netcool hard nofile 65536

# Logout and login for changes to take effect
```

### 2. Profiler Disabled

**Symptom**:
```
[WARN] Profiler may not be configured
```

**Fix**:
```bash
nco_sql -server NCOMS -user root -passwd XXXXX
> ALTER TRIGGER GROUP profiler_report SET ENABLED TRUE;
> GO
```

### 3. Debug Logging in Production

**Symptom**:
```
[WARN] MessageLog set to DEBUG level - high performance impact!
```

**Fix**:
Edit `$OMNIHOME/etc/SERVERNAME.props`:
```
# Change from:
MessageLog: 'debug' $OMNIHOME/log/SERVERNAME.log
# To:
MessageLog: 'warn' $OMNIHOME/log/SERVERNAME.log
```

Restart ObjectServer to apply.

### 4. Low Impact Heap

**Symptom**:
```
[WARN] Impact heap size (2G) below baseline (4GB)
```

**Fix**:
Edit Impact startup script or properties:
```bash
# Increase -Xmx value
-Xms4096m -Xmx4096m
```

### 5. High Trigger Execution Time

**Symptom**:
```
[WARN] Trigger exceeds performance threshold: update_status_trigger (avg: 250ms)
```

**Fix**:
- Review trigger SQL for inefficient queries
- Add indexes to frequently queried columns
- Consider breaking complex triggers into smaller ones
- Check for missing statistics updates

### 6. Large alerts.status Table

**Symptom**:
```
[WARN] alerts.status table is large (75000 rows) - may impact performance
```

**Fix**:
- Review deduplication rules
- Implement automated clearing for resolved events
- Tune alert lifecycle policies
- Consider archiving historical data

### 7. Kernel Semaphore Settings

**Symptom**:
```
[FAIL] Kernel semaphore settings below IBM recommendations
```

**Fix**:
```bash
# Edit /etc/sysctl.conf
kernel.sem = 250 32000 32 128

# Apply immediately
sysctl -p
```

### 8. Probe Disconnects

**Symptom**:
```
[WARN] Probe MTTrapd: 15 disconnect/error events in recent logs
```

**Fix**:
- Check network stability between probe and ObjectServer
- Verify ObjectServer is not overloaded
- Review probe configuration (reconnect interval, timeout)
- Check firewall rules

### 9. Gateway Writer Buffer Full

**Symptom**:
```
[WARN] Gateway G_NCOMS_AGG: Writer buffer issues detected
```

**Fix**:
- Increase gateway writer buffer size
- Check target ObjectServer performance
- Review event flow rate
- Consider gateway hardware resources

### 10. TCP Keepalive Too High

**Symptom**:
```
[WARN] TCP keepalive time is high; may delay detection of connection failures
```

**Fix**:
```bash
# Edit /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 300

# Apply immediately
sysctl -p
```

## Integration Examples

### Integrating with Nagios/ICINGA

```bash
#!/bin/bash
# /usr/local/nagios/libexec/check_netcool_health.sh

/opt/netcool/scripts/netcool_audit.sh --skip-sql --no-color > /dev/null 2>&1
EXIT_CODE=$?

case $EXIT_CODE in
    0)
        echo "OK - Netcool environment healthy"
        exit 0
        ;;
    2)
        echo "WARNING - Netcool has warnings"
        exit 1
        ;;
    1)
        echo "CRITICAL - Netcool has failures"
        exit 2
        ;;
esac
```

### Integrating with Splunk

```bash
# Run audit and send to Splunk HEC
./netcool_audit.sh --no-color | \
curl -k https://splunk.example.com:8088/services/collector \
    -H "Authorization: Splunk YOUR-HEC-TOKEN" \
    -d '{"event": "'"$(cat)"'", "sourcetype": "netcool:audit"}'
```

### Integrating with ServiceNow

```bash
# Run audit and create incident if failures detected
./netcool_audit.sh --output /tmp/audit.log
EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    # Create ServiceNow incident via API
    curl -X POST https://instance.service-now.com/api/now/table/incident \
        -H "Authorization: Basic $(echo -n user:pass | base64)" \
        -H "Content-Type: application/json" \
        -d '{
            "short_description": "Netcool Audit Failures Detected",
            "description": "'"$(cat /tmp/audit.log)"'",
            "urgency": "2",
            "impact": "2"
        }'
fi
```

## Tips & Tricks

### Tip 1: Save Credentials for Automated Runs

Create `~/.pgpass` file (PostgreSQL style, works with Netcool SQL):

```bash
# Format: hostname:port:database:username:password
localhost:4100:NCOMS:root:your_password

# Secure the file
chmod 600 ~/.pgpass
```

### Tip 2: Focus on Specific Checks

Use `grep` to filter output:

```bash
# Show only failures
./netcool_audit.sh | grep FAIL

# Show only warnings and failures
./netcool_audit.sh | grep -E "WARN|FAIL"

# Show only recommendations
./netcool_audit.sh | grep -A 100 "RECOMMENDATIONS"
```

### Tip 3: Compare Across Environments

```bash
# Run on DEV
ssh netcool@dev-server 'bash -s' < netcool_audit.sh --skip-sql > audit_dev.log

# Run on PROD
ssh netcool@prod-server 'bash -s' < netcool_audit.sh --skip-sql > audit_prod.log

# Compare
vimdiff audit_dev.log audit_prod.log
```

### Tip 4: Create Custom Baseline

Make a copy and adjust for your environment:

```bash
cp netcool_audit.sh netcool_audit_custom.sh

# Edit baselines
vi netcool_audit_custom.sh
# Adjust BASELINE_* variables around line 60
```

### Tip 5: Schedule Weekly Reports

```bash
# Add to netcool user's crontab
crontab -e

# Run every Monday at 6 AM, email results
0 6 * * 1 /opt/netcool/scripts/netcool_audit.sh --no-color | mail -s "Weekly Netcool Audit" sre-team@example.com
```

## Troubleshooting Quick Reference

| Problem | Quick Fix |
|---------|-----------|
| Script won't run | `chmod +x netcool_audit.sh` |
| NCHOME not found | `export NCHOME=/opt/IBM/tivoli/netcool` |
| SQL connection fails | Use `--skip-sql` flag |
| Colors not showing | Use `--no-color` or check terminal |
| Too much output | Use `--skip-sql` and pipe to `grep FAIL` |
| Need more details | Add `--verbose` flag |
| Script hangs | Ctrl+C, then use `--skip-sql` |

## Next Steps

After running the audit:

1. **Review Failures First**: Address [FAIL] items immediately
2. **Plan for Warnings**: Create tickets for [WARN] items
3. **Document Baseline**: Save initial audit report
4. **Schedule Regular Runs**: Add to cron for weekly execution
5. **Trend Analysis**: Compare reports over time
6. **Share Results**: Distribute to team for awareness

## Getting Help

If you need assistance:

1. Run with `--verbose` for detailed logs
2. Check the main README.md for comprehensive documentation
3. Review IBM Netcool documentation
4. Contact your IBM support representative

---

**Quick Reference Card**

```
BASIC:    ./netcool_audit.sh --skip-sql
FULL:     ./netcool_audit.sh
SAVE:     ./netcool_audit.sh --output report.txt
VERBOSE:  ./netcool_audit.sh --verbose
CRON:     ./netcool_audit.sh --skip-sql --no-color

EXIT:     0=Pass, 1=Fail, 2=Warn
```
