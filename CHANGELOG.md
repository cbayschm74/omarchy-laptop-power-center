# Changelog

## 1.2.1

- Treat a live charge stop threshold of 100% as battery protection disabled,
  even when firmware retains a nonzero charge-resume threshold. This fixes the
  protection toggle on Dell systems whose disabled state is reported as
  `50/100`.
- Preserve start-threshold-only detection on hardware that exposes no stop
  threshold.

Validation includes the Dell `50/100` regression fixture, the existing
`75/80` and `0/100` cases, the start-threshold-only fallback, plugin validation,
and shell syntax checks.

## 1.2.0

- Add optional NVIDIA utilization and power draw, queried for the selected GPU
  only while the panel is open. Check runtime state immediately before querying,
  skip sleeping devices, and bound query duration.
- Hide missing or invalid GPU readings and restore GPU pending-action messages.
- Show battery health relative to design capacity when available through UPower.
- Report incomplete Travel Mode changes and retain settings for restoration.
- Validate saved display settings before constructing Hyprland commands.
- Remove unused system-statistics polling.
- Preserve user-level operation through existing system interfaces; no plugin
  script runs as root.

Validation includes plugin structure, shell syntax, telemetry parsing, sleeping
GPU query suppression, selected-device querying, partial Travel Mode failure,
display-state validation, battery health, and existing restore behavior.
