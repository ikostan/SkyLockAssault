# Security Policy

## Supported Versions

This policy applies to the latest stable release of SkyLockAssault, built with
Godot v4.5. We prioritize security for web exports (HTML5) deployed to itch.io.

| Version | Supported      |
|---------|----------------|
| 1.x     | ✅ Yes (latest) |
| < 1.x   | ❌ No           |

As a Godot-based top-down combat game, we have minimal external dependencies
(e.g., no Node.js runtime), reducing vuln surface. Focus areas: GDScript logic,
scene exports, and web fuel/weapons mechanics.

## Severity Levels

We classify vulnerabilities using Common Vulnerability Scoring System (CVSS v3.1)
ranges for consistency. This helps prioritize fixes based on impact.

<!-- markdownlint-disable line-length -->
| Severity | CVSS Score | Description & Examples (Godot-Specific)                                                                                                                                                                                                        |
|----------|------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Critical | 9.0–10.0   | Immediate threat: Full compromise, remote code execution, or data loss. E.g., Arbitrary script injection in exported HTML5 binary allowing cheat execution in browser; SQL-like injection in save files leading to total game state overwrite. |
| High     | 7.0–8.9    | Significant risk: Unauthorized access or disruption. E.g., Server-side request forgery via Godot's HTTPRequest node; Cross-site scripting (XSS) in web UI exposing player inputs.                                                              |
| Medium   | 4.0–6.9    | Moderate impact: Often misconfigs aiding chained attacks. E.g., Reflected XSS in debug console; Missing input validation in fuel mechanics allowing minor cheats.                                                                              |
| Low      | 0.1–3.9    | Minor weakness: Little direct exploitability. E.g., Verbose error messages revealing Godot version; Missing secure cookie flags in web sessions.                                                                                               |
<!-- markdownlint-enable line-length -->

If CVSS doesn't fit, we adjust based on factors like exploit ease or affected
users (e.g., web vs. desktop builds).

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
- Do **not** disclose publicly (e.g., no X posts or itch.io comments) until resolved.

We'll acknowledge reports within **48 hours**.

## Disclosure Process

We follow coordinated disclosure:

1. Acknowledge receipt (within 48 hours).
2. Triage & validate severity (using levels above).
3. Fix in a private branch.
4. Release patch + advisory.
5. Credit reporter (with consent).

**SLA Targets by Severity (Post-Triage):**  
These are goals for a small team—actual times may vary based on complexity.

- Critical: Fix within 14 days.  
- High: Fix within 30 days.  
- Medium: Fix within 60 days.  
- Low: Fix within 90 days.  

For questions, reference [GitHub Security Advisories docs](https://docs.github.com/en/code-security/security-advisories).

Thank you for helping secure SkyLockAssault! 🚀
