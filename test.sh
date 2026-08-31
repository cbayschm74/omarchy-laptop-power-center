#!/bin/bash

set -euo pipefail

plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
omarchy plugin validate "$plugin_root"
grep -F 'Qt.resolvedUrl("bin/omarchy-battery-limit")' "$plugin_root/Panel.qml" >/dev/null
grep -F 'Qt.resolvedUrl("bin/omarchy-energy-controls")' "$plugin_root/Panel.qml" >/dev/null
grep -F 'energyActionProc.command = ["/usr/bin/bash", energyCommand' "$plugin_root/Panel.qml" >/dev/null

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
cleanup() {
  local status=$?
  rm -rf "$fixture"
  exit "$status"
}
trap cleanup EXIT
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

# Energy controls use only user-level, independently authorized system
# interfaces. The fixture stubs those interfaces without touching live state.
mkdir -p "$fixture/energy/state" "$fixture/energy/nvidia/power"
printf '90\n' >"$fixture/energy/brightness"
printf 'balanced\n' >"$fixture/energy/profile"
printf 'active\n' >"$fixture/energy/nvidia/power/runtime_status"

cat >"$fixture/bin/omarchy-hyprland-monitor-focused" <<'STUB'
#!/bin/bash
echo eDP-1
STUB

cat >"$fixture/bin/omarchy-brightness-display" <<'STUB'
#!/bin/bash
value=""
while (( $# > 0 )); do
  case $1 in
    --no-osd) shift ;;
    --monitor) shift 2 ;;
    *) value=$1; shift ;;
  esac
done
if [[ -z $value ]]; then
  cat "$ENERGY_BRIGHTNESS_STATE"
else
  printf '%s\n' "${value%%%}" >"$ENERGY_BRIGHTNESS_STATE"
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
cat >"$fixture/bin/hyprctl" <<'STUB'
#!/bin/bash
if [[ $1 == monitors && $2 == -j ]]; then
  cat "$ENERGY_HYPR_MONITORS_STATE"
elif [[ $1 == eval ]]; then
  printf '%s\n' "$2" >>"$ENERGY_HYPR_CALL_LOG"
fi
STUB
chmod +x "$fixture/bin/omarchy-hyprland-monitor-focused" \
  "$fixture/bin/omarchy-brightness-display" "$fixture/bin/powerprofilesctl" \
  "$fixture/bin/hyprctl"
export OMARCHY_ENERGY_TEST_MODE=1
export OMARCHY_ENERGY_TEST_PATH="$fixture/bin:/usr/bin:/bin"
export OMARCHY_ENERGY_STATE_ROOT="$fixture/energy/state"
export OMARCHY_ENERGY_NVIDIA_PATH="$fixture/energy/nvidia"
export ENERGY_BRIGHTNESS_STATE="$fixture/energy/brightness"
export ENERGY_PROFILE_STATE="$fixture/energy/profile"
export OMARCHY_ENERGY_TEST_DESKTOP=Hyprland
export ENERGY_HYPR_MONITORS_STATE="$fixture/energy/monitors.json"
export ENERGY_HYPR_CALL_LOG="$fixture/energy/hypr-calls"
printf '%s\n' '[{"name":"eDP-1","width":2560,"height":1440,"x":0,"y":0,"scale":1.5,"refreshRate":144.0,"transform":1,"vrr":true},{"name":"HDMI-A-1","width":1920,"height":1080,"x":2560,"y":0,"scale":1,"refreshRate":60.0,"transform":0,"vrr":false}]' >"$ENERGY_HYPR_MONITORS_STATE"
touch "$ENERGY_HYPR_CALL_LOG"

energy="$plugin_root/bin/omarchy-energy-controls"
status=$($energy status --shell)
grep -Fx $'travel\tdisabled' <<<"$status" >/dev/null
grep -Fx $'brightness\t90' <<<"$status" >/dev/null
grep -Fx $'nvidia_power\tactive' <<<"$status" >/dev/null
grep -Fx $'fps\tnormal' <<<"$status" >/dev/null

printf 'unavailable\n' >"$fixture/energy/brightness"
grep -Fx $'quick_dim\tunsupported' < <($energy status --shell) >/dev/null
printf '90\n' >"$fixture/energy/brightness"

$energy quick-dim enable
grep -Fx '40' "$fixture/energy/brightness" >/dev/null
grep -Fx $'quick_dim\tenabled' < <($energy status --shell) >/dev/null
$energy quick-dim disable
grep -Fx '90' "$fixture/energy/brightness" >/dev/null

$energy travel enable
grep -Fx 'power-saver' "$fixture/energy/profile" >/dev/null
grep -Fx '40' "$fixture/energy/brightness" >/dev/null
grep -F 'output = "eDP-1", mode = "2560x1440@60"' "$ENERGY_HYPR_CALL_LOG" >/dev/null
grep -F 'transform = 1, vrr = true' "$ENERGY_HYPR_CALL_LOG" >/dev/null
if grep -F 'HDMI-A-1' "$ENERGY_HYPR_CALL_LOG" >/dev/null; then
  echo "Travel Mode changed a display already running at 60Hz" >&2
  exit 1
fi
grep -Fx $'fps\tlimited' < <($energy status --shell) >/dev/null
$energy travel disable
grep -Fx 'balanced' "$fixture/energy/profile" >/dev/null
grep -Fx '90' "$fixture/energy/brightness" >/dev/null
grep -F 'output = "eDP-1", mode = "2560x1440@144' "$ENERGY_HYPR_CALL_LOG" >/dev/null
[[ $(wc -l <"$ENERGY_HYPR_CALL_LOG") == 2 ]]
grep -Fx $'fps\tnormal' < <($energy status --shell) >/dev/null

export OMARCHY_ENERGY_TEST_DESKTOP=""
grep -Fx $'fps\tunsupported' < <($energy status --shell) >/dev/null

echo "All checks passed"
