#!/bin/bash

set -euo pipefail

plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
omarchy plugin validate "$plugin_root"
grep -F 'Qt.resolvedUrl("bin/omarchy-battery-limit")' "$plugin_root/Panel.qml" >/dev/null
grep -F 'Qt.resolvedUrl("bin/omarchy-energy-controls")' "$plugin_root/Panel.qml" >/dev/null

node - "$plugin_root" <<'JS'
const root = process.argv[2]
const model = require(root + '/Model.js')

if (model.limitDescription('enabled', '75-80') !== 'Starts charging at 75% and stops at 80%') throw new Error('threshold range')
if (model.limitDescription('disabled', 'firmware') !== 'Use firmware optimized charging') throw new Error('firmware policy')
if (model.selectProfileIndex(0, 1, ['power-saver', 'balanced']) !== 1) throw new Error('existing profile selection')
if (model.gpuPowerLabel('active') !== 'Active') throw new Error('active GPU state')
if (model.gpuPowerLabel('suspended') !== 'Sleeping') throw new Error('sleeping GPU state')
JS

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
mkdir -p "$fixture/power_supply/BAT0"

cat >"$fixture/bin/upower" <<'STUB'
#!/bin/bash
[[ $1 == -e ]] && echo /org/freedesktop/UPower/devices/battery_BAT0
STUB

cat >"$fixture/bin/busctl" <<'STUB'
#!/bin/bash
if [[ $1 == get-property ]]; then
  case "$5" in
    ChargeThresholdSupported) echo "b true" ;;
    ChargeThresholdEnabled) echo "b false" ;;
    ChargeThresholdSettingsSupported) echo "u 3" ;;
    ChargeStartThreshold) echo "u ${BATTERY_TEST_START:-75}" ;;
    ChargeEndThreshold) echo "u ${BATTERY_TEST_END:-80}" ;;
    NativePath) echo 's "BAT0"' ;;
  esac
elif [[ $1 == call ]]; then
  printf '%s\t%s\n' "$3" "$7" >>"$BATTERY_CALL_LOG"
fi
STUB

chmod +x "$fixture/bin/upower" "$fixture/bin/busctl"
export PATH="$fixture/bin:$PATH"
export BATTERY_CALL_LOG="$fixture/calls"
export OMARCHY_BATTERY_TEST_MODE=1
export OMARCHY_BATTERY_POWER_SUPPLY_ROOT="$fixture/power_supply"

printf '75\n' >"$fixture/power_supply/BAT0/charge_control_start_threshold"
printf '80\n' >"$fixture/power_supply/BAT0/charge_control_end_threshold"

# Windows and firmware can leave effective thresholds behind while UPower's
# own enabled flag is false. The helper must still expose that as enabled.
status=$("$plugin_root/bin/omarchy-battery-limit" status --shell)
grep -Fx $'state\tenabled' <<<"$status" >/dev/null
grep -Fx $'policy\t75-80' <<<"$status" >/dev/null

# UPower keeps its remembered 75/80 policy after disabling it. Live sysfs
# values must win so the widget follows the actual firmware state.
printf '0\n' >"$fixture/power_supply/BAT0/charge_control_start_threshold"
printf '100\n' >"$fixture/power_supply/BAT0/charge_control_end_threshold"
status=$("$plugin_root/bin/omarchy-battery-limit" status --shell)
grep -Fx $'state\tdisabled' <<<"$status" >/dev/null

"$plugin_root/bin/omarchy-battery-limit" disable >/dev/null
grep -Fx $'/org/freedesktop/UPower/devices/battery_BAT0\tfalse' "$BATTERY_CALL_LOG" >/dev/null

# Energy controls run against isolated writable fixtures. Test-mode never
# bypasses real filesystem permissions; it only redirects this unprivileged
# test process to the temporary paths below.
mkdir -p "$fixture/energy/state" "$fixture/energy/nvidia/power"
printf '0\n' >"$fixture/energy/no_turbo"
printf '900\n' >"$fixture/energy/brightness"
printf '1000\n' >"$fixture/energy/max_brightness"
printf 'off\n' >"$fixture/energy/wifi_state"
printf 'balanced\n' >"$fixture/energy/profile"
printf 'active\n' >"$fixture/energy/nvidia/power/runtime_status"

cat >"$fixture/bin/iw" <<'STUB'
#!/bin/bash
if [[ $3 == get && $4 == power_save ]]; then
  printf 'Power save: %s\n' "$(<"$ENERGY_WIFI_STATE")"
elif [[ $3 == set && $4 == power_save ]]; then
  printf '%s\n' "$5" >"$ENERGY_WIFI_STATE"
else
  exit 2
fi
STUB

cat >"$fixture/bin/powerprofilesctl" <<'STUB'
#!/bin/bash
case "$1" in
  get) cat "$ENERGY_PROFILE_STATE" ;;
  set) printf '%s\n' "$2" >"$ENERGY_PROFILE_STATE" ;;
  *) exit 2 ;;
esac
STUB

chmod +x "$fixture/bin/iw" "$fixture/bin/powerprofilesctl"
export OMARCHY_ENERGY_TEST_MODE=1
export OMARCHY_ENERGY_TEST_PATH="$fixture/bin:/usr/bin:/bin"
export OMARCHY_ENERGY_STATE_ROOT="$fixture/energy/state"
export OMARCHY_ENERGY_NO_TURBO_PATH="$fixture/energy/no_turbo"
export OMARCHY_ENERGY_BRIGHTNESS_PATH="$fixture/energy/brightness"
export OMARCHY_ENERGY_BRIGHTNESS_MAX_PATH="$fixture/energy/max_brightness"
export OMARCHY_ENERGY_WIFI_IFACE=wlan-test
export OMARCHY_ENERGY_NVIDIA_PATH="$fixture/energy/nvidia"
export ENERGY_WIFI_STATE="$fixture/energy/wifi_state"
export ENERGY_PROFILE_STATE="$fixture/energy/profile"

energy="$plugin_root/bin/omarchy-energy-controls"
status=$($energy status --shell)
grep -Fx $'travel\tdisabled' <<<"$status" >/dev/null
grep -Fx $'turbo\tenabled' <<<"$status" >/dev/null
grep -Fx $'wifi_power\tdisabled' <<<"$status" >/dev/null
grep -Fx $'brightness\t90' <<<"$status" >/dev/null
grep -Fx $'nvidia_power\tactive' <<<"$status" >/dev/null

$energy turbo disable
grep -Fx '1' "$fixture/energy/no_turbo" >/dev/null
$energy turbo enable
grep -Fx '0' "$fixture/energy/no_turbo" >/dev/null

$energy quick-dim enable
grep -Fx '400' "$fixture/energy/brightness" >/dev/null
grep -Fx $'quick_dim\tenabled' < <($energy status --shell) >/dev/null
$energy quick-dim disable
grep -Fx '900' "$fixture/energy/brightness" >/dev/null

$energy travel enable
grep -Fx 'power-saver' "$fixture/energy/profile" >/dev/null
grep -Fx '1' "$fixture/energy/no_turbo" >/dev/null
grep -Fx 'on' "$fixture/energy/wifi_state" >/dev/null
grep -Fx '400' "$fixture/energy/brightness" >/dev/null
$energy travel disable
grep -Fx 'balanced' "$fixture/energy/profile" >/dev/null
grep -Fx '0' "$fixture/energy/no_turbo" >/dev/null
grep -Fx 'off' "$fixture/energy/wifi_state" >/dev/null
grep -Fx '900' "$fixture/energy/brightness" >/dev/null

echo "All checks passed"
