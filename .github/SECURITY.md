# Security Policy

## Supported Versions

This policy applies to the latest stable release of SkyLockAssault, built with
Godot v4.5. We prioritize security for web exports (HTML5) deployed to itch.io.

| Version | Supported          |
|---------|--------------------|
| 1.x     | ✅ Yes (latest)    |
| < 1.x   | ❌ No              |

As a Godot-based top-down combat game, we have minimal external dependencies
(e.g., no Node.js runtime), reducing vuln surface. Focus areas: GDScript logic,
scene exports, and web fuel/weapons mechanics.

## Reporting a Vulnerability

We take security seriously and appreciate your efforts to disclose responsibly.
Please report vulnerabilities privately:

- **Preferred Method:** Create a draft security advisory via the
  [Security tab](https://github.com/ikostan/SkyLockAssault/security/advisories/new)
  on GitHub. Include:
  - Description of the vulnerability (e.g., "Potential XSS in web-exported UI via
    unescaped player input").
  - Reproduction steps (e.g., "In browser console: inject script during level load;
    tested on Chrome 120+").
  - Impact (e.g., "Could allow fuel cheat in multiplayer preview").
  - Environment (e.g., "Godot v4.5 export to Win10/Chrome").
- **Alternative:** Email [your-email@example.com] (replace with maintainer's contact)
  with the same details.
- Do **not** disclose publicly (e.g., no X posts or itch.io comments) until resolved.

We'll acknowledge reports within **48 hours** and aim to resolve/fix within **90 days**,
depending on severity.

## Disclosure Process

We follow coordinated disclosure:
1. Triage & validate.
2. Fix in a private branch.
3. Release patch + advisory.
4. Credit reporter (with consent).

For questions, reference [GitHub Security Advisories docs](https://docs.github.com/en/code-security/security-advisories).

Thank you for helping secure SkyLockAssault! 🚀
