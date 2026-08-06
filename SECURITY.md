# Security Policy

## Supported versions

Mutelet has not published its first stable release. Security fixes currently target the latest `main` revision and will target the latest release after v1.0.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** form under the repository's Security tab. Private vulnerability reporting must be enabled before the first public binary release. If that form is unavailable, do not post vulnerability details in a public issue; the repository is not ready for security-sensitive public distribution until the maintainer enables the private channel.

Include the affected macOS version, Mutelet revision or version, input device type, reproduction steps, and impact. A maintainer will acknowledge the report as soon as practical and coordinate disclosure after a fix is available.

## Security boundaries

Mutelet changes Core Audio mute and volume controls but does not provide a hardware-enforced privacy boundary. Volume-only inputs and third-party audio routing can behave differently; see [Device compatibility](docs/DEVICE_COMPATIBILITY.md). Use a hardware mute switch when a guaranteed physical disconnect is required.
