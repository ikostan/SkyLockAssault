# Commit Signing Setup for GitHub Desktop (Fixing Unverified Commits)

This section documents the resolution for issue
[#109: Fix GitHub Desktop Commits Not Verified](https://github.com/ikostan/SkyLockAssault/issues/109)
in the SkyLockAssault project. Implementing commit signing ensures that
commits are verified on GitHub, adding a layer of security and trust to
the repository. This is particularly useful for open-source Godot
projects like this top-down web browser game, where CI/CD pipelines
(e.g., for HTML5 exports to itch.io) rely on trustworthy code history.

The setup is tailored for Windows 10 64-bit, using GitHub Desktop v3.5,
and integrates with Godot 4.5 development workflows. It uses GPG
(GNU Privacy Guard) for signing, as it's straightforward and doesn't
require SSH alternatives unless preferred.

## Prerequisites

- GitHub Desktop v3.5 installed.
- Git installed (comes with GitHub Desktop; verify with `git --version`
  in `PowerShell`).
- A GitHub account with a verified email (check at github.com/settings/emails).
- No prior GPG setup conflicts—backup your existing `.gitconfig` if modified.

## Step-by-Step Guide

### 1. Install Gpg4win (Minimal Components)

Download the latest Gpg4win from the official site:
[gpg4win.org](https://gpg4win.org). During installation:

- Select only **GnuPG** (core tools) and **Kleopatra** (key manager GUI).
- Uncheck unnecessary components like GpgOL, GpgEX, and Browser Integration
  to keep the setup lightweight.
- Complete the installation. This adds `gpg` to your system
  (default path: `C:\Program Files (x86)\GnuPG\bin`).

If `gpg` isn't recognized in `PowerShell`, add the bin path to your system PATH:
- Right-click `This PC` > `Properties` > `Advanced system settings` >
  `Environment Variables` > `System variables` > `Path` > `Edit` > `New` > 
  Add `C:\Program Files (x86)\GnuPG\bin` > `OK`.

### 2. Generate a GPG Key Pair

1. Open Kleopatra from the Start menu.
2. Click **File > New Key Pair**.
3. Use your real name and GitHub-verified email.
4. In Advanced Settings:
   - Key type: RSA (default) or ed25519 for modern security.
   - Key size: 4096 bits for strength.
   - Optionally enable "Authentication" subkey.
   - Set expiration (e.g., 3 years) or unlimited.
5. Set a strong passphrase (recommended for security; you'll enter it during commits).
6. Generate the key—it may take a minute.

### 3. Export and Upload Public Key to GitHub

1. In Kleopatra, right-click your new key > **Export**.
2. Save as a `.asc` file or copy the ASCII-armored content.
3. Go to github.com/settings/keys > **New GPG key**.
4. Paste the public key content
   (starts with `-----BEGIN PGP PUBLIC KEY BLOCK-----`) and add it.
5. Verify: Your key should appear in the GPG keys list with the
   correct Key ID (e.g., `ABCDEF1234567890`).

### 4. Configure Git for Automatic Signing

Edit your global `.gitconfig` file (located at `C:\Users\YourUsername\.gitconfig`)
using Notepad or PyCharm. Add or update these sections:

```ini
[user]
name =        # Your GitHub name
email =       # Must match the key's email
signingkey =  # Your long key ID (from step 5 below)

[commit]
gpgsign = true  # Auto-sign all commits
```

- **Finding Your Long Key ID**: In PowerShell, run:
  ```bash
  gpg --list-secret-keys --keyid-format=long
  ```
  
  Use the 16-hex digit ID after the slash on the "sec" line (primary key).
- If using a subkey, append `!` (e.g., `0C2A685FB6E880DA1!`).

### 5. Test Commit Signing in GitHub Desktop

1. Open your SkyLockAssault repo in GitHub Desktop.
2. Make a small change (e.g., add a line to `README.md`).
3. Commit the change—enter your passphrase if set.
4. Push to GitHub.
5. Check the commit on `github.com/ikostan/SkyLockAssault/commits/main`,
   it should show **Verified** with a green checkmark.

### Troubleshooting Common Issues

- **"gpg: signing failed"**: Ensure email matches exactly (case-sensitive).
  Run `git config --global user.email` to verify. Restart GitHub Desktop.
- **Key not found**: Double-check the signingkey ID with the gpg command.
  Use the long format (16 hex digits).
- **Passphrase prompt missing**: If no popup, test in PowerShell:
  `cd path/to/SkyLockAssault` then `git commit -S -m "Test signed commit"`.
- **PATH issues**: If gpg commands fail, confirm the bin path is in system
  `PATH` and restart PowerShell/GitHub Desktop.
- **Unsigned old commits**: Signing applies forward; rebase or cherry-pick
  for history if needed (not recommended for public repos).
- **Godot-specific notes**: This doesn't affect Godot Editor or Docker
  testing—commits remain verifiable in CI/CD for HTML5 exports.

## Why This Matters for SkyLockAssault

- Enhances repo security for open-source collaboration.
- Integrates with branch protection (#110) to require signed commits on main.
- Ensures trustworthy deploys to itch.io via GitHub Actions, preventing
  tampered code in web builds.

For more on Godot workflows, see the main
[README.md](https://github.com/ikostan/SkyLockAssault/blob/main/README.md).
If issues persist, reference GitHub docs or open a new issue.

This fix was implemented on October 06, 2025, as part of Milestone 3.
