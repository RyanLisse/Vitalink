# Vitalink

A macOS CLI & MCP server for Apple HealthKit - enabling AI agents to read and write health data.

## Features

- **Read Health Data**: Steps, heart rate, workouts, activity rings, weight, blood glucose, and more
- **Write Health Data**: Record measurements, workouts, and health samples  
- **Query & Statistics**: Get aggregated stats, trends, and historical data
- **MCP Server**: Expose HealthKit to AI agents via Model Context Protocol

## Requirements

- macOS 14.0+
- Xcode 15+ / Swift 6.0+
- HealthKit available on the device

## Installation

### Build from Source

```bash
cd ~/Developer/Vitalink
swift build -c release

# Copy to PATH (optional)
cp .build/release/vitalink /usr/local/bin/
```

### Code Signing (Required for HealthKit)

**IMPORTANT**: HealthKit requires the binary to be code-signed with a valid Apple Developer certificate. Without proper signing, macOS will terminate the process immediately (SIGKILL / exit code 137).

#### Prerequisites
- Apple Developer account (free or paid)
- Valid code signing certificate installed in Keychain
- Xcode installed (for certificate management)

#### Step 1: Find Your Signing Identity
```bash
security find-identity -v -p codesigning
```
Look for a certificate like `Apple Development: Your Name (TEAMID)`.

#### Step 2: Sign the Binary
```bash
# Build release
swift build -c release

# Sign with your certificate and entitlements
codesign --force --sign "Apple Development: Your Name (TEAMID)" \
  --entitlements Resources/Vitalink.entitlements \
  --options runtime \
  .build/release/vitalink

# Verify signing
codesign -dvvv .build/release/vitalink
```

#### Step 3: Grant HealthKit Access
On first run, macOS will prompt for HealthKit authorization. You can also grant access in **System Settings → Privacy & Security → Health**.

#### Troubleshooting
- **Exit code 137**: Binary is not properly signed. Re-sign with valid certificate.
- **"No identity found"**: No developer certificate installed. Open Xcode → Settings → Accounts → Manage Certificates.
- **HealthKit not available**: Running on unsupported Mac or VM. HealthKit requires real Mac hardware.

## Usage

### Check Status
```bash
vitalink status
```

### Authorize Access
```bash
vitalink authorize          # Full read/write access
vitalink authorize --read-only  # Read-only access
```

### Read Data
```bash
# Steps
vitalink read steps --from 7d --to now

# Heart Rate  
vitalink read heart-rate --from 1d --json

# Workouts
vitalink read workouts --from 30d --activity-type running

# Activity Summary (Apple Watch rings)
vitalink read activity --date today

# Any quantity type
vitalink read quantity weight --from 30d
```

### Write Data
```bash
# Record weight
vitalink write quantity weight 75.5

# Record blood glucose
vitalink write quantity blood_glucose 95 --unit mg/dl

# Log a workout
vitalink write workout running \
  --start "2025-01-05T07:00:00" \
  --end "2025-01-05T07:30:00" \
  --calories 300 \
  --distance 5000
```

### Query Statistics
```bash
# Get stats for steps over the last week
vitalink query stats steps --from 7d

# Get daily trends for heart rate
vitalink query trends heart_rate --from 30d --interval day
```

### MCP Server

Start the MCP server for AI agent integration:

```bash
vitalink mcp serve
```

List available tools:
```bash
vitalink mcp tools --json
```

#### Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "vitalink": {
      "command": "/path/to/vitalink",
      "args": ["mcp", "serve"]
    }
  }
}
```

#### Testing with mcpli

```bash
# Install mcpli
bun install -g mcpli

# Test MCP server
mcpli --help -- /path/to/vitalink mcp serve

# Call a specific tool
mcpli health_status -- /path/to/vitalink mcp serve
```

## Date Formats

- **ISO8601**: `2025-01-05T10:30:00Z`, `2025-01-05`
- **Relative**: `1d` (1 day ago), `7d`, `1w` (1 week), `1m` (1 month)
- **Keywords**: `now`, `today`

## Supported Data Types

| Type | CLI Name | Description |
|------|----------|-------------|
| Steps | `steps` | Daily step count |
| Heart Rate | `heart_rate` | Heart rate in BPM |
| Active Energy | `active_energy` | Active calories burned |
| Basal Energy | `basal_energy` | Resting calories |
| Distance | `distance` | Walking/running distance |
| Weight | `weight` | Body mass |
| Height | `height` | Body height |
| Body Temperature | `body_temperature` | Temperature readings |
| Blood Pressure | `blood_pressure_systolic/diastolic` | BP measurements |
| Blood Glucose | `blood_glucose` | Glucose levels |
| Oxygen Saturation | `oxygen_saturation` | SpO2 readings |
| Respiratory Rate | `respiratory_rate` | Breathing rate |

## MCP Tools for AI Agents

| Tool | Description |
|------|-------------|
| `health_status` | Check HealthKit availability |
| `health_authorize` | Request health data access |
| `health_read_steps` | Read step count data |
| `health_read_heart_rate` | Read heart rate samples |
| `health_read_workouts` | Read workout history |
| `health_read_activity` | Read activity summary (rings) |
| `health_read_quantity` | Read any quantity type |
| `health_query_stats` | Get statistics for data type |
| `health_write_quantity` | Write health measurement |
| `health_write_workout` | Record a workout |

## Project Structure

```
Vitalink/
├── Package.swift
├── Sources/
│   ├── VitalinkCLI/
│   │   ├── Commands/
│   │   │   ├── Vitalink.swift       # Main command
│   │   │   ├── AuthorizeCommand.swift
│   │   │   ├── ReadCommand.swift
│   │   │   ├── WriteCommand.swift
│   │   │   ├── QueryCommand.swift
│   │   │   ├── StatusCommand.swift
│   │   │   └── MCPCommand.swift
│   │   ├── Services/
│   │   │   ├── HealthKitService.swift
│   │   │   └── DataTypes.swift
│   │   └── MCP/
│   │       └── VitalinkMCPServer.swift
│   └── VitalinkExec/
│       └── main.swift
└── Resources/
    ├── Vitalink.entitlements
    └── Info.plist
```

## License

MIT
