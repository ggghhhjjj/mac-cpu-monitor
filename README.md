# CPU Monitor - AppleScript Edition

A lightweight, dependency-free AppleScript implementation of CPU Monitor for macOS users without sudo privileges. Full feature parity with the C++ version.

## Features

- ✅ **No sudo required** — Uses macOS `ps` command instead of restricted libproc APIs
- ✅ **Pure AppleScript** — Single self-contained script, no external dependencies
- ✅ **Full feature parity** — Same CLI options, CSV logging, notifications, debug mode
- ✅ **State machine monitoring** — Detects sustained high CPU usage (not transient spikes)
- ✅ **Flexible CSV logging** — In-memory buffering with automatic periodic flush
- ✅ **Native macOS notifications** — Desktop alerts when thresholds exceeded
- ✅ **Lightweight** — Minimal resource overhead, efficient ps parsing

## Installation

```bash
cd /path/to/mac-cpu-monitor-applescript
chmod +x bin/cpu-monitor-as
```

## Usage

### Basic Usage

```bash
# Monitor with default settings (85% threshold, 30s interval)
./bin/cpu-monitor-as

# Monitor with custom threshold
./bin/cpu-monitor-as --threshold 50 --interval 10

# Enable debug output
./bin/cpu-monitor-as --debug --threshold 50 --check-count 2 --interval 5
```

### All Options

```
--threshold PERCENT       CPU percentage threshold (default: 85, range: 1-100)
--interval SECONDS        Sampling interval in seconds (default: 30, min: 3)
--check-count N           Consecutive samples above threshold to trigger alert (default: 4)
--csv-commands CMD,...    Comma-separated process names to log to CSV (default: disabled)
--csv-dir PATH            Directory to save CSV files (default: current directory)
--debug                   Enable detailed debug output
--help, -h                Show help
--version, -v             Show version
```

### Examples

```bash
# Monitor processes using 50% or more CPU
./bin/cpu-monitor-as --threshold 50

# Monitor with stricter settings (trigger after 2 consecutive samples)
./bin/cpu-monitor-as --threshold 75 --check-count 2

# Log Chrome and Node.js CPU to CSV
./bin/cpu-monitor-as --threshold 50 --csv-commands Chrome,node --csv-dir ./logs

# Debug mode with immediate notification trigger
./bin/cpu-monitor-as --debug --threshold 0 --check-count 1 --interval 5

# With sudo for system process monitoring
sudo ./bin/cpu-monitor-as --debug --threshold 50 --interval 5
```

## How It Works

### Process Detection

The script uses `ps -axo pid,%cpu,comm` to enumerate processes and their CPU usage without requiring elevated privileges for most user processes.

```
PID %CPU COMM
100 25.3 Chrome
200 15.5 node
300  5.2 Safari
```

**Advantages over C++ version:**
- No sudo needed for typical user processes (Chrome, VS Code, terminal, etc.)
- Works for corporate-locked machines without admin privileges
- Still works with sudo for system process monitoring

### State Machine

Monitors are based on consecutive threshold exceedances:

1. **New process detected:** Reset counter to 1 (if above threshold) or 0
2. **Same process, CPU ≥ threshold:** Increment counter
3. **Same process, CPU < threshold:** Reset counter to 0
4. **Trigger notification:** When counter ≥ `check_count`

This prevents false positives from transient spikes while quickly detecting sustained high CPU.

### CSV Logging

When `--csv-commands` is specified, matching processes are logged to CSV files:

**File naming:** First 10 characters of command + `.csv` (e.g., `chrome.csv`, `node.csv`)

**CSV format:**
```
timestamp,PID,command,CPU%
2026-02-15T14:30:45Z,1234,Chrome,85.2
2026-02-15T14:31:15Z,1234,Chrome,92.5
```

**Buffering:** Samples are buffered in memory and flushed every 60 seconds or on exit (Ctrl+C).

### Notifications

Desktop notifications appear in macOS Notification Center when threshold is exceeded:

```
CPU Monitor
High CPU: Chrome (PID 1234) - 85.2%
```

## Differences from C++ Version

| Aspect | C++ Version | AppleScript Version |
|--------|---|---|
| **Privileges required** | Sudo (for system processes) | None (for user processes) |
| **Process data source** | libproc (kernel APIs) | ps command |
| **Target users** | All macOS users | Corporate/restricted environments |
| **Performance** | Faster (compiled C++) | Slightly slower (interpreted) |
| **CPU% accuracy** | Exact (kernel data) | Accurate (ps reports CPU%) |
| **Dependencies** | None | None (AppleScript built-in) |
| **Deployment** | Binary executable | Single `.scpt` file |

## Limitations

1. **Notification permission:** macOS may require one-time user authorization in System Preferences → Notifications
2. **Process name truncation:** Very long command names may be truncated by `ps` output
3. **System processes:** CPU data for privileged processes (WindowServer, kernel_task) may be unavailable without sudo
4. **Single-threaded:** Blocks on 60-second sampling interval (acceptable for monitoring use case)

## Advantages Over C++

- **No compilation needed** — Deploy single `.scpt` file
- **No sudo required** — Works in restricted corporate environments
- **Lower friction** — No build system, no Makefile
- **Easy to modify** — AppleScript is readable and editable in any text editor
- **Cross-compatible** — Works on any macOS version with AppleScript support (10.9+)

## Debug Mode

Enable detailed output to troubleshoot state machine behavior:

```bash
./bin/cpu-monitor-as --debug --threshold 50 --check-count 2 --interval 5
```

**Debug output includes:**
- `[DEBUG] CPU Sample:` — Current process and CPU percentage
- `[DEBUG] Counter State:` — Internal state machine values
- `[DEBUG] Notification Request:` — Alert triggers
- `[DEBUG] Flushing X CSV records` — Data persistence events

## Examples: Debug Session

```bash
# Quick test with low threshold to trigger immediately
./bin/cpu-monitor-as --debug --threshold 0 --check-count 1 --interval 3

# Expected output:
# [DEBUG] CPU Monitor started
# [DEBUG] Threshold: 0% | Interval: 3s | Check count: 1
# [DEBUG] CPU Sample: PID=12345 Command=Chrome CPU%=45.2
# [DEBUG] Counter State: consecutive_count=1 threshold=0 check_count=1
# [DEBUG] Notification Request: command=Chrome pid=12345 cpu_percent=45.2
# (Notification appears in Notification Center)
# [DEBUG] CPU Sample: PID=12346 Command=Safari CPU%=32.1
# (counters reset for new process)
```

## Troubleshooting

### Notifications Not Appearing

1. Check System Preferences → Notifications for app authorization
2. Enable notifications for "Script Editor" or "osascript"
3. Ensure Do Not Disturb is not enabled
4. Run with `--debug` to verify notification was triggered

### Incorrect CPU Percentages

- Different measurement methods may show slightly different CPU% than C++ version
- This is normal — measurements can vary by 1-5% between tools
- For validation, compare with `ps -p <PID> -o %cpu` or Activity Monitor

### CSV Files Not Created

- Verify `--csv-dir` directory exists or is writable
- Check that `--csv-commands` contains valid process names (substring match)
- Run with `--debug` to see CSV buffer flushing events

## Comparison with C++ Version

Use the **AppleScript version** if:
- You don't have sudo access
- Working in a corporate/restricted environment
- Want zero deployment friction (single file)
- Need fast development iteration

Use the **C++ version** if:
- You need to monitor privileged system processes (WindowServer, kernel_task)
- Maximum performance is critical
- Prefer compiled binary
- Need lower-level process access

## Future Enhancements

Potential improvements for future releases:

1. **Configuration file support** — Load settings from `~/.cpumonitorrc`
2. **Process whitelist/blacklist** — Exclude specific processes from monitoring
3. **Alert sound option** — Play sound on threshold exceeded
4. **Database logging** — JSON or SQLite output option
5. **Multi-process grouping** — Monitor total CPU of related processes
6. **Terminal UI** — Real-time statistics display instead of console logging

## License

Same as parent C++ CPU Monitor project.

## Contributing

To extend this AppleScript version:

1. **Add new features** — Edit `src/cpu-monitor.scpt` directly
2. **Improve ps parsing** — Optimize `getTopCPUProcess()` function
3. **Enhance CSV** — Add new columns in `writeCSVFile()` function
4. **Better error handling** — Catch more edge cases in parsing logic

## Support

For issues or feature requests:
- Compare behavior with C++ version
- Use `--debug` flag to troubleshoot
- Check ps output manually: `ps -axo pid,%cpu,comm | head`
- Review AppleScript syntax near error location

---

**Version:** 1.0.0-AS (AppleScript Edition)  
**Requirements:** macOS 10.9+ with AppleScript support  
**Status:** Production-ready for user process monitoring
