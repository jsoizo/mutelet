# Security Policy

## Supported versions

Mutelet has not published its first stable release. Security fixes currently target the latest `main` revision and will target the latest release after v1.0.

## Reporting a vulnerability

If private vulnerability reporting is enabled for the published repository, use GitHub's **Report a vulnerability** form under its Security tab. Otherwise, open a public issue that contains no exploit details and ask the maintainer for a private contact channel. Do not include sensitive details in a public issue.

Include the affected macOS version, Mutelet revision or version, input device type, reproduction steps, and impact. A maintainer will acknowledge the report as soon as practical and coordinate disclosure after a fix is available.

## Security boundaries

Mutelet changes Core Audio mute and volume controls but does not provide a hardware-enforced privacy boundary. Volume-only inputs and third-party audio routing can behave differently; see [Device compatibility](docs/DEVICE_COMPATIBILITY.md). Use a hardware mute switch when a guaranteed physical disconnect is required.
