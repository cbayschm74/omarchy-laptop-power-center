# Credits and third-party notices

Laptop Power Center combines and extends the following MIT-licensed projects.
The source links and Git history are retained so users and reviewers can trace
the origin of the adapted code.

## Omarchy Power Panel

The panel structure, base power-profile controls, battery display, and Omarchy
visual components are derived from the built-in `omarchy.power` widget.

- Project: [Omarchy](https://github.com/basecamp/omarchy)
- Copyright: David Heinemeier Hansson
- License: MIT

## Omarchy Laptop GPU Modes

The optional NVIDIA and `supergfxctl` integration is derived from Omarchy
Laptop GPU Modes. This repository is maintained as a fork so its original Git
history and authorship remain visible.

- Project: [Omarchy Laptop GPU Modes](https://github.com/Minokai69/omarchy-laptop-gpu-modes)
- Copyright: 2026 Minokai-Dev
- License: MIT

## Battery Health for Omarchy

The UPower charge-threshold integration is adapted from Battery Health for
Omarchy, with additional live sysfs-state detection and refresh handling.

- Project: [Battery Health for Omarchy](https://github.com/patcastle/omarchy-battery-health)
- Copyright: 2026 Patrick Castiglia and Basecamp, LLC
- License: MIT

## Laptop Power Center additions

The combined layout, Travel Mode, CPU Turbo control, Wi-Fi power saving,
Quick Dim, NVIDIA runtime-power reporting, capability gating, state refresh,
tests, and related safety handling were added for Laptop Power Center.

- Copyright: 2026 Carlos Bay-Schmith
- License: MIT

The complete license text and retained copyright notices are in
[LICENSE](LICENSE).
