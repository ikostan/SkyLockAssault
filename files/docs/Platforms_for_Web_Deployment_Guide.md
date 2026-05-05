# Free Web Browser Game Deployment Platforms

## Summary of zero-cost publishing platforms for Godot v4.5 HTML5/WebGL games

## Project Context

We're building **SkyLockAssault** — a totally free-to-play browser
game in **Godot v4.5** on **Windows 10 64-bit**. This is our learning
journey into game dev, so we're keeping everything practical,
low-friction, and focused on **automatic deploys** via GitHub Actions
+ CI/CD where possible.

This `.md` file is your living playbook. Update it as you go (e.g. mark
new platforms as "Deployed: ✅ Yes").

**Target**: Automatic GitHub Actions deploys where possible.

---

## Why Web Platforms for a Free F2P Godot Game?

- **Zero cost to publish** (no Steam $100 fee)
- **Instant browser play** (Godot WebGL export = one ZIP)
- **High traffic** for casual games like SkyLockAssault
- **Ad revenue or donations** without forcing monetization
- **GitHub Actions** = push → auto-deploy (your dream workflow)

---

## Platform Comparison (Feb 2026)

<!-- markdownlint-disable line-length MD060 -->
| Platform             | Free Publish | Official Automation      | Playwright Feasible? | Traffic / Reach     | Godot v4.5 Win10 Tip                     | Deployed | Priority for You       |
|----------------------|--------------|--------------------------|----------------------|---------------------|------------------------------------------|----------|------------------------|
| **itch.io**          | Yes          | ✅ butler CLI             | Not needed           | Indie + discovery   | Native Godot + godot-ci Actions          | ✅ Yes    | ★★★★★ (Start here)     |
| **Poki**             | Yes          | ✅ poki-cli               | Not needed           | Massive casual      | Official Godot plugin + CLI in Actions   | ❌ No     | ★★★★★ (High traffic)   |
| **Viverse**          | Yes          | ✅ VIVERSE CLI            | Not needed           | 3D/WebXR focus      | Godot WebGL + npm CLI (2026 update)      | ❌ No     | ★★★★ (Future-proof)    |
| **Game Jolt**        | Yes          | ✅ CLI                    | Not needed           | Indie community     | Simple ZIP upload script                 | ❌ No     | ★★★★                   |
| **iDev.games**       | Yes          | ❌ No                     | ✅ Very easy          | Instant publish     | Simplest form → Playwright target        | ❌ No     | ★★★★ (Bonus)           |
| **GameMonetize**     | Yes          | ❌ No                     | ✅ Easy               | Ad network          | ZIP drop in dashboard                    | ❌ No     | ★★★★ (Revenue)         |
| **CrazyGames**       | Yes          | ❌ No                     | ✅ Possible           | Huge casual         | CAPTCHA risk → manual safer              | ❌ No     | ★★★ (Risky)            |
| **Y8.com**           | Yes          | ❌ No                     | ✅ Possible           | Classic portal      | Basic form                               | ❌ No     | ★★★                    |
| **GameDistribution** | Yes          | ❌ No                     | ✅ Possible           | B2B distribution    | SDK mandatory first                      | ❌ No     | ★★★                    |
| **GamePix**          | Yes          | ❌ No                     | ✅ Possible           | Global partners     | Dashboard ZIP                            | ❌ No     | ★★★                    |
| **Newgrounds**       | Yes          | ❌ No                     | ✅ Partial            | Community           | Manual + API for scores only             | ❌ No     | ★★                     |
| **SoftGames**        | Yes          | ❌ No                     | ✅ Possible           | Messenger games     | Submit form                              | ❌ No     | ★★ (Low priority)      |
<!-- markdownlint-enable line-length MD060 -->

---

## Why Most Platforms Refuse Official Automation (Deep Dive)

All "❌ No" platforms require **manual moderation** to fight spam/low-quality
uploads. Here's the exact reason from their docs/portals (Feb 2026):

<!-- markdownlint-disable line-length -->
| Platform             | Reason for No Publish API/CLI                                                                                |
|----------------------|--------------------------------------------------------------------------------------------------------------|
| **iDev.games**       | API only for in-game data (Game DB / shop). Upload is manual for "instant publish + later verification".     |
| **CrazyGames**       | Portal is ZIP + form + manual review. SDK only for ads. UI changes often → bots break.                       |
| **Y8.com**           | Simple upload form → human approval step for quality.                                                        |
| **GameMonetize**     | You integrate SDK, then manual ZIP in admin dashboard. They handle distribution.                             |
| **GameDistribution** | SDK mandatory for stats/ads → portal upload only.                                                            |
| **Newgrounds**       | Project system is manual. In-game API (medals/scores) exists, but upload API is a long-open feature request. |
| **GamePix**          | Dashboard submit after SDK. No automation.                                                                   |
| **SoftGames**        | Pure submit form + manual review.                                                                            |
<!-- markdownlint-enable line-length -->

**Core reason across all**: Manual moderation prevents spam and low-quality content.

**Bottom line:** Moderation = quality control. Playwright can fake the clicks,
but it's maintenance work.

---

## Automation Strategy

- 100% Auto: itch.io, Poki, Viverse, Game Jolt
- Playwright Auto: iDev.games, GameMonetize (easiest)
- Manual + Occasional: CrazyGames, Y8, GameDistribution, GamePix, Newgrounds,
  SoftGames

---

## Recommended Workflow for SkyLockAssault (Your Learning Path)

### Phase 1: 100% Automatic (Do This First)

1. **itch.io** — Set up butler + GitHub Actions (you already did this ✅)
2. **Poki** — Add poki-cli (high traffic + official Godot support)
3. **Viverse** — Add VIVERSE CLI (modern 3D/WebXR bonus)

### Phase 2: Semi-Auto Bonus (Playwright)

- **iDev.games** + **GameMonetize** (easiest forms)
- Update every 2–4 weeks via one shared script

### Phase 3: Manual Once + Occasional Updates

- CrazyGames, Y8, GameDistribution, GamePix, Newgrounds, SoftGames, Game Jolt

**Goal:** Push to `main` → 10+ platforms updated automatically.

---

## Godot v4.5 Export Tips (Win10)

```bash
# In your project root (run from PowerShell or Git Bash)
godot --export "Web" "build/sky-lock-assault"
cd build/sky-lock-assault
Compress-Archive -Path * -DestinationPath ../skylockassault.zip
```

Always include `index.html` at ZIP root.

---

## Automation Setup Quick Starts

### itch.io (Already Done)

Use `butler` + godot-ci GitHub Action.

### Poki (Next)

<!-- markdownlint-disable line-length -->
```yaml
# .github/workflows/poki.yml
- uses: actions/setup-node@v4
- run: npx @poki/cli upload --game-id YOUR_ID --token ${{ secrets.POKI_TOKEN }} build.zip
```
<!-- markdownlint-enable line-length -->

### Viverse (2026 CLI)

```bash
npm install -g @viverse/cli
viverse-cli publish --app-id YOUR_APP --file skylockassault.zip
```
