# Netcool Audit Script v2.0 - New Features Documentation

## Overview

Version 2.0 introduces three major enhancements to the Netcool audit script:

1. **JSON/XML Output Formats** - Machine-readable export for integration with monitoring systems
2. **Historical Trending** - Track audit results over time and compare with previous runs
3. **Active Stress Testing** - Inject synthetic events to measure ObjectServer performance under load

---

## Feature 1: JSON/XML Output Formats

### Description

The audit script can now export results in JSON or XML format, making it easy to integrate with:
- Monitoring systems (Splunk, ELK, Prometheus)
- Dashboards and visualization tools (Grafana, Kibana)
- ITSM platforms (ServiceNow, Remedy)
- Custom automation pipelines

### Usage

```bash
# Export as JSON
./netcool_audit.sh --format json --output audit_report.json

# Export as XML
./netcool_audit.sh --format xml --output audit_report.xml

# JSON to stdout (for piping)
./netcool_audit.sh --format json | jq '.netcool_audit.summary'
```

### JSON Output Structure

```json
{
  "netcool_audit": {
    "metadata": {
      "script_version": "2.0",
      "audit_timestamp": "2025-11-06 14:30:00",
      "hostname": "netcool-prod-01",
      "execution_time_seconds": 135
    },
    "system_info": {
      "os_type": "RHEL",
      "os_version": "Red Hat Enterprise Linux 7.9",
      "cpu_cores": "16",
      "total_ram_mb": "65536",
      "nchome": "/opt/IBM/tivoli/netcool",
      "omnihome": "/opt/IBM/tivoli/netcool/omnibus",
      "impact_home": "/opt/IBM/tivoli/netcool/impact",
      "webgui_home": "/opt/IBM/JazzSM"
    },
    "summary": {
      "passed_checks": 15,
      "warnings": 3,
      "failures": 0,
      "recommendations": 2
    },
    "test_results": [
      {
        "test": "ulimit_nofile",
        "status": "pass",
        "value": "65536",
        "threshold": "65536",
        "message": "Open files limit meets baseline"
      }
    ],
    "warnings": [
      "Profiler may not be configured"
    ],
    "failures": [],
    "recommendations": [
      "[MEDIUM] Enable profiler_report trigger group for performance diagnostics"
    ]
  }
}
```

### XML Output Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<netcool_audit>
  <metadata>
    <script_version>2.0</script_version>
    <audit_timestamp>2025-11-06 14:30:00</audit_timestamp>
    <hostname>netcool-prod-01</hostname>
    <execution_time_seconds>135</execution_time_seconds>
  </metadata>
  <system_info>
    <os_type>RHEL</os_type>
    <os_version>Red Hat Enterprise Linux 7.9</os_version>
    <cpu_cores>16</cpu_cores>
    <total_ram_mb>65536</total_ram_mb>
    <nchome>/opt/IBM/tivoli/netcool</nchome>
    <omnihome>/opt/IBM/tivoli/netcool/omnibus</omnihome>
  </system_info>
  <summary>
    <passed_checks>15</passed_checks>
    <warnings>3</warnings>
    <failures>0</failures>
    <recommendations>2</recommendations>
  </summary>
  <warnings>
    <warning>Profiler may not be configured</warning>
  </warnings>
  <failures />
  <recommendations>
    <recommendation>[MEDIUM] Enable profiler_report trigger group</recommendation>
  </recommendations>
</netcool_audit>
```

### Integration Examples

#### Splunk Integration

```bash
# Run audit and send to Splunk HEC
./netcool_audit.sh --format json | \
curl -k https://splunk.company.com:8088/services/collector \
  -H "Authorization: Splunk YOUR-HEC-TOKEN" \
  -d @-
```

#### Elasticsearch Integration

```bash
# Index audit results in Elasticsearch
./netcool_audit.sh --format json --output /tmp/audit.json

curl -X POST "http://elasticsearch:9200/netcool-audits/_doc" \
  -H "Content-Type: application/json" \
  -d @/tmp/audit.json
```

#### Grafana Dashboard

Use the JSON output with Infinity or JSON API data source to create real-time dashboards showing:
- Historical trend of passed/failed checks
- Warning and failure counts over time
- Recommendation priorities

---

## Feature 2: Historical Trending

### Description

Track audit results over time to identify trends, regressions, and improvements. The script maintains a history of the last 30 audits in JSONL (JSON Lines) format and can compare the current run with previous results.

### Usage

```bash
# Enable trending (saves results to ~/.netcool_audit_history/)
./netcool_audit.sh --enable-trending

# Compare with previous audit
./netcool_audit.sh --compare-previous

# Use custom history directory
./netcool_audit.sh --enable-trending --history-dir /var/log/netcool/audits

# Combine with JSON output
./netcool_audit.sh --enable-trending --format json --output latest_audit.json
```

### How It Works

1. **History Storage**: Audit results are saved to `~/.netcool_audit_history/audit_history.jsonl`
2. **Format**: JSONL (one JSON object per line) for easy parsing
3. **Retention**: Automatically keeps last 30 audits, older entries are pruned
4. **Comparison**: Compares current audit with the most recent previous audit

### History File Location

By default: `$HOME/.netcool_audit_history/audit_history.jsonl`

Custom location: Use `--history-dir /path/to/dir`

### Sample Trend Comparison Output

```
============================================
Historical Trend Analysis
============================================
[INFO] Comparing with previous audit from: 2025-11-05 14:30:00

  Warnings: 3 (▼ -2 from previous) - Improved!
  Failures: 0 (= no change)
  Passed Checks: 15 (▲ +2 from previous) - Improved!

  Overall Trend: ✓ IMPROVING
```

### Trend Indicators

- **▲** - Metric increased
- **▼** - Metric decreased
- **=** - No change

### Overall Trend Assessment

- **✓ IMPROVING** - Failures decreased and/or warnings decreased
- **✗ DEGRADING** - Failures increased
- **⚠ MIXED** - Warnings increased but failures unchanged
- **= STABLE** - No significant changes

### Use Cases

**Daily Automated Audits**:
```bash
# Add to cron
0 2 * * * /opt/netcool/scripts/netcool_audit.sh --enable-trending --skip-sql --no-color >> /var/log/netcool/daily_audit.log 2>&1
```

**Weekly Comparison Reports**:
```bash
# Run weekly with comparison
0 6 * * 1 /opt/netcool/scripts/netcool_audit.sh --compare-previous --output /var/log/netcool/weekly_audit_$(date +\%Y\%m\%d).txt
```

**Long-term Analysis**:
```bash
# Parse history file to generate trends
cat ~/.netcool_audit_history/audit_history.jsonl | \
  jq -r '[.netcool_audit.metadata.audit_timestamp, .netcool_audit.summary.failures] | @csv'
```

### Historical Data Analysis

The JSONL format allows for easy analysis with standard tools:

```bash
# Count audits
wc -l < ~/.netcool_audit_history/audit_history.jsonl

# Extract all failure counts
jq '.netcool_audit.summary.failures' ~/.netcool_audit_history/audit_history.jsonl

# Show audit timestamps
jq -r '.netcool_audit.metadata.audit_timestamp' ~/.netcool_audit_history/audit_history.jsonl

# Find audits with failures
jq 'select(.netcool_audit.summary.failures > 0)' ~/.netcool_audit_history/audit_history.jsonl

# Generate CSV for Excel/spreadsheet
jq -r '[.netcool_audit.metadata.audit_timestamp, .netcool_audit.summary.passed_checks, .netcool_audit.summary.warnings, .netcool_audit.summary.failures] | @csv' \
  ~/.netcool_audit_history/audit_history.jsonl > audit_trends.csv
```

---

## Feature 3: Active Stress Testing

### Description

⚠️ **WARNING**: This feature is **NOT read-only** and should be used with caution in production environments.

Stress testing injects synthetic events into the ObjectServer to measure:
- Event insertion rate (events per second)
- Trigger processing performance
- Deduplication effectiveness
- System behavior under load

### Usage

```bash
# Basic stress test (100 events, 60 second observation)
./netcool_audit.sh --stress-test

# Custom event count
./netcool_audit.sh --stress-test --stress-events 500

# Custom observation duration
./netcool_audit.sh --stress-test --stress-duration 120

# Full stress test configuration
./netcool_audit.sh --stress-test --stress-events 1000 --stress-duration 300
```

### Safety Features

1. **Explicit Confirmation Required**:
   ```
   ⚠️  WARNING: STRESS TEST MODE ⚠️

   Stress testing will:
     • Inject 100 synthetic events into ObjectServer
     • Generate load for approximately 60 seconds
     • Measure trigger performance and event processing rates
     • May impact production operations during the test

   This is NOT a read-only operation!

   Are you sure you want to proceed with stress testing? (yes/no):
   ```

2. **Unique Event Identifiers**: All test events use `NETCOOL_AUDIT_TEST_[PID]_[N]` pattern
3. **Automatic Cleanup**: Test events are automatically deleted after observation period
4. **Credential Prompting**: ObjectServer credentials required (not passed on command line)

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--stress-events` | 100 | Number of synthetic events to inject |
| `--stress-duration` | 60 | Observation period in seconds before cleanup |

### How It Works

1. **Connection Test**: Verifies ObjectServer connectivity
2. **Baseline Count**: Records current `alerts.status` row count
3. **Event Injection**: Inserts synthetic events with unique identifiers
4. **Observation Period**: Waits for trigger processing and deduplication
5. **Metrics Collection**: Measures insertion rate, errors, net retention
6. **Cleanup**: Deletes all test events
7. **Final Count**: Verifies cleanup completed

### Sample Output

```
============================================
Active Stress Testing
============================================

[INFO] Testing connection to ObjectServer: NCOMS
[PASS] Connected to ObjectServer: NCOMS
[INFO] Current alert count: 12543
[INFO] Injecting 100 test events...
[INFO] Event injection completed in 15 seconds
[INFO]   Successful: 100
[INFO]   Errors: 0
[INFO] Waiting for event processing (may take up to 60 seconds)...
[INFO] Final alert count: 12598
[INFO] Net increase: 55 events
[INFO] Cleaning up test events...
[INFO] Alert count after cleanup: 12543

--- Stress Test Results ---
[PASS] Events injected: 100 in 15 seconds
[INFO] Event injection rate: 6.67 events/sec
[INFO] Injection errors: 0
[INFO] Net alerts retained: 55 (after deduplication/clearing)
```

### Performance Thresholds

The script evaluates event insertion rate:

- **< 10 events/sec**: ❌ Low - may indicate performance issues
- **10-50 events/sec**: ⚠️ Moderate - acceptable for most environments
- **> 50 events/sec**: ✅ Good - healthy performance

### Stress Test Results in JSON

When combined with `--format json`, stress test results are included:

```json
{
  "netcool_audit": {
    ...
    "stress_test_results": {
      "events_injected": "100",
      "injection_errors": "0",
      "injection_duration_sec": "15",
      "events_per_second": "6.67",
      "start_alert_count": "12543",
      "end_alert_count": "12598",
      "net_increase": "55"
    }
  }
}
```

### Use Cases

**Pre-Deployment Validation**:
```bash
# Test new ObjectServer before go-live
./netcool_audit.sh --stress-test --stress-events 500 --stress-duration 120
```

**Post-Tuning Verification**:
```bash
# Verify trigger optimization improved performance
./netcool_audit.sh --stress-test --format json --output before_tuning.json
# Make trigger changes...
./netcool_audit.sh --stress-test --format json --output after_tuning.json
# Compare results
```

**Capacity Planning**:
```bash
# Gradually increase load to find breaking point
for events in 100 500 1000 2000 5000; do
  echo "Testing with $events events..."
  ./netcool_audit.sh --stress-test --stress-events $events --format json \
    --output "stress_test_${events}.json"
  sleep 300  # Cool-down period
done
```

### Important Considerations

⚠️ **Production Safety**:
- Run during maintenance windows or low-traffic periods
- Start with small event counts (100-500)
- Monitor ObjectServer CPU/memory during test
- Ensure adequate space in `alerts.status` table
- Test cleanup in non-production first

⚠️ **Trigger Impacts**:
- Test events will trigger all enabled triggers
- May generate notifications if triggers send emails/pages
- May impact performance if expensive triggers are configured
- Review trigger configuration before running

⚠️ **Network Considerations**:
- Script runs synchronously (waits for each event)
- Network latency affects insertion rate
- Run from server close to ObjectServer for best results

---

## Combining Features

All three features can be combined for comprehensive testing and analysis:

### Example 1: Full Audit with Trending

```bash
./netcool_audit.sh \
  --enable-trending \
  --compare-previous \
  --format json \
  --output /var/log/netcool/audit_$(date +%Y%m%d).json
```

This will:
1. Run standard audit
2. Compare with previous audit
3. Export as JSON
4. Save to history for future comparisons

### Example 2: Stress Test with Historical Tracking

```bash
./netcool_audit.sh \
  --stress-test \
  --stress-events 500 \
  --enable-trending \
  --format json \
  --output stress_test_results.json
```

This will:
1. Run stress test with 500 events
2. Save results to history
3. Export detailed JSON with stress test metrics

### Example 3: Automated Weekly Comparison

```bash
# Weekly audit with trends (add to cron)
0 6 * * 1 /opt/netcool/scripts/netcool_audit.sh \
  --compare-previous \
  --enable-trending \
  --output /var/log/netcool/weekly_audit_$(date +\%Y\%m\%d).txt \
  | mail -s "Weekly Netcool Audit" netcool-admins@company.com
```

---

## Configuration

### Environment Variables

The script respects these environment variables:

```bash
# Override default history directory
export NETCOOL_AUDIT_HISTORY_DIR="/shared/netcool/audits"

# Use in script
./netcool_audit.sh --history-dir "$NETCOOL_AUDIT_HISTORY_DIR" --enable-trending
```

### History Management

**Manual History Cleanup**:
```bash
# Remove old history
rm ~/.netcool_audit_history/audit_history.jsonl

# Archive history
mv ~/.netcool_audit_history/audit_history.jsonl \
   /archive/audit_history_$(date +%Y%m%d).jsonl
```

**Backup History**:
```bash
# Periodic backup
tar -czf netcool_audit_history_$(date +%Y%m%d).tar.gz \
  ~/.netcool_audit_history/

# Restore from backup
tar -xzf netcool_audit_history_20251106.tar.gz -C ~/
```

---

## API Integration Examples

### REST API Webhook

Post audit results to a REST endpoint:

```bash
./netcool_audit.sh --format json | \
curl -X POST https://api.company.com/netcool/audits \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d @-
```

### ServiceNow Integration

Create incident if failures detected:

```bash
#!/bin/bash
./netcool_audit.sh --format json --output /tmp/audit.json

FAILURES=$(jq '.netcool_audit.summary.failures' /tmp/audit.json)

if [ "$FAILURES" -gt 0 ]; then
  # Create ServiceNow incident
  curl -X POST "https://instance.service-now.com/api/now/table/incident" \
    -H "Authorization: Basic $(echo -n user:pass | base64)" \
    -H "Content-Type: application/json" \
    -d "{
      \"short_description\": \"Netcool Audit Failures Detected\",
      \"description\": \"$(jq -r '.netcool_audit.failures | join(", ")' /tmp/audit.json)\",
      \"urgency\": \"2\",
      \"impact\": \"2\"
    }"
fi
```

### Prometheus Metrics

Export metrics in Prometheus format:

```bash
#!/bin/bash
./netcool_audit.sh --format json --output /tmp/audit.json

# Generate Prometheus metrics
cat << EOF > /var/lib/node_exporter/textfile_collector/netcool_audit.prom
# HELP netcool_audit_passed_checks Number of passed checks
# TYPE netcool_audit_passed_checks gauge
netcool_audit_passed_checks $(jq '.netcool_audit.summary.passed_checks' /tmp/audit.json)

# HELP netcool_audit_warnings Number of warnings
# TYPE netcool_audit_warnings gauge
netcool_audit_warnings $(jq '.netcool_audit.summary.warnings' /tmp/audit.json)

# HELP netcool_audit_failures Number of failures
# TYPE netcool_audit_failures gauge
netcool_audit_failures $(jq '.netcool_audit.summary.failures' /tmp/audit.json)
EOF
```

---

## Troubleshooting

### JSON Output Issues

**Problem**: Invalid JSON generated

**Solution**:
```bash
# Validate JSON
./netcool_audit.sh --format json --output audit.json
jq . audit.json  # Will show syntax errors

# Common causes:
# - Special characters in strings (should be auto-escaped)
# - Run with --verbose to see processing details
```

### Historical Trending Issues

**Problem**: Permission denied creating history directory

**Solution**:
```bash
# Pre-create directory with correct permissions
mkdir -p ~/.netcool_audit_history
chmod 700 ~/.netcool_audit_history

# Or use alternate location
./netcool_audit.sh --history-dir /tmp/netcool_audit --enable-trending
```

**Problem**: History comparisons show "not enough history"

**Solution**:
```bash
# Need at least 2 audits in history
./netcool_audit.sh --enable-trending  # Run 1
./netcool_audit.sh --compare-previous  # Run 2 - now has data
```

### Stress Test Issues

**Problem**: Stress test fails to connect

**Solution**:
- Verify ObjectServer is running: `nco_pad -list`
- Check network connectivity to ObjectServer port
- Verify credentials are correct
- Ensure nco_sql is in PATH

**Problem**: Events not cleaned up

**Solution**:
```bash
# Manual cleanup
echo "DELETE FROM alerts.status WHERE Identifier LIKE 'NETCOOL_AUDIT_TEST_%';" | \
  nco_sql -server NCOMS -user root -passwd XXXXX
```

**Problem**: Low event injection rate

**Possible Causes**:
- Network latency between script and ObjectServer
- ObjectServer overloaded
- Expensive triggers executing on each insert
- Disk I/O bottleneck

**Diagnosis**:
```bash
# Run with verbose logging
./netcool_audit.sh --stress-test --verbose

# Monitor ObjectServer during test
top -p $(pgrep nco_objserv)
iostat -x 1
```

---

## Performance Considerations

### JSON/XML Export

- **Overhead**: Minimal (~1-2 seconds for generation)
- **File Size**: Typical audit ~50-200 KB
- **Memory**: Low impact, streaming output

### Historical Trending

- **Storage**: ~50-200 KB per audit × 30 audits = ~1.5-6 MB
- **Processing**: Lightweight, regex-based comparison
- **I/O Impact**: Minimal, single file append

### Stress Testing

- **Duration**: Depends on `--stress-events` count and insertion rate
- **ObjectServer Impact**:
  - CPU: Moderate during injection
  - Memory: Minimal (events are small)
  - Disk: Depends on table size and triggers
- **Network**: ~1-2 KB per event
- **Cleanup**: Fast (single DELETE query with indexed Identifier)

**Recommended Limits**:
- Development: Up to 5,000 events
- Production (maintenance window): Up to 1,000 events
- Production (during business hours): Up to 100 events

---

## Best Practices

### JSON/XML Output

1. ✅ Use for automation and integration
2. ✅ Validate JSON with `jq` before processing
3. ✅ Compress large audit histories: `gzip audit.json`
4. ✅ Version control your integration scripts

### Historical Trending

1. ✅ Run audits on consistent schedule (daily/weekly)
2. ✅ Archive history files monthly for long-term analysis
3. ✅ Use trending to identify slow degradation
4. ✅ Alert on negative trends (increasing failures)
5. ❌ Don't rely on history for critical alerting (use real-time monitoring)

### Stress Testing

1. ✅ Always get approval before running in production
2. ✅ Start with small event counts (100-500)
3. ✅ Run during maintenance windows
4. ✅ Monitor ObjectServer resources during test
5. ✅ Document baseline performance for comparison
6. ❌ Don't run stress tests during peak business hours
7. ❌ Don't assume results transfer across different hardware
8. ❌ Don't use stress tests as the only performance validation

---

## Version History

### Version 2.0 (2025-11-06)

**New Features**:
- JSON/XML output formats (`--format json|xml`)
- Historical trending (`--enable-trending`, `--compare-previous`)
- Active stress testing (`--stress-test`, `--stress-events`, `--stress-duration`)

**Enhancements**:
- Structured data collection throughout audit
- JSONL format for efficient history storage
- Automatic history retention (last 30 audits)
- Comprehensive stress test metrics
- Safety confirmations for destructive operations

**Breaking Changes**:
- Script version bumped from 1.0 to 2.0
- New command-line options (backward compatible)
- Output format affects display (text vs JSON/XML)

### Version 1.0 (2025-11-06)

**Initial Release**:
- OS-level configuration auditing
- ObjectServer health checks
- Impact and WebGUI profiling
- Probe and gateway monitoring
- IBM baseline comparisons
- Text-based reporting

---

## Support & Feedback

For issues, questions, or feature requests related to the new features:

1. **Documentation**: Review this guide and the main README.md
2. **Troubleshooting**: Check the Troubleshooting section above
3. **Testing**: Always test in non-production first
4. **Examples**: See integration examples for common use cases

---

## Summary

Version 2.0 transforms the Netcool audit script from a standalone diagnostic tool into a comprehensive platform for:

- ✅ **Automation**: Machine-readable output integrates with existing tools
- ✅ **Trending**: Historical analysis identifies patterns and regressions
- ✅ **Validation**: Active testing validates performance under realistic load

Use these features individually or in combination to build a robust Netcool monitoring and validation framework.
