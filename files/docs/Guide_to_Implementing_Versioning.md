# Guide to Implementing Versioning

A step-by-step guide summarizing our conversation on versioning,
specifically choosing the Manual Approach. The main focus is on the core
steps that directly support your goals with Semantic Versioning and
manual releases. Now updated with Release Drafter integration for
automated changelogs from PR labels, enhancing manual processes without
automating tags/releases.

## 1. Main Flow: Versioning After Branch Work and PR Merge

When working in branches (e.g., for PR #98 on user feedback or new
feature implementation), follow this sequence to ensure tags and
releases mark reviewed, merged, and tested code—aligning with SemVer
for the game app.

Key insight: Tagging post-merge on main keeps versions stable and deployable,
as merges trigger CI/CD (e.g., GDLint in lint_test_build.yml and deploy.yml).
With Release Drafter, PRs auto-generate changelog previews, feeding into releases.

### Action to take (Step by Step Guide)

1. Wait until review is over (e.g., approve PR #98 on GitHub)—Release
   Drafter previews changelog via workflow (#113).
2. Merge the code to main (click "Merge pull request")—triggers Drafter to
   update draft release notes.
3. Confirm it passes CI/CD (including deployment to itch.io via export workflows).
4. Create a new tag v0.2.1 working from the main branch:
   - In PowerShell, switch to main (git checkout main)
   - Pull updates (git pull origin main)
   - Then git tag v0.2.1 (on the merge commit)
5. Make a push to the origin: git push origin v0.2.1 (verify in GitHub's Tags tab)
6. Manually create the release on GitHub:
   - Go to Releases tab > Draft a new release > Select v0.2.1
   - Edit auto-drafted notes (from Release Drafter, e.g., categorized changes)
   - Add title/notes (e.g., "v0.2.1 - User Feedback Phase 1; merged PR #98")
   - Publish

## 2. Adopting Semantic Versioning (SemVer) with Git Tags

- **The approach**: Use tags for immutable snapshots instead of branches.
  Follow SemVer: `vX.Y.Z` where X is major (breaking changes), Y is minor
  (new features), Z is patch (fixes). With Release Drafter, labels drive increments
  (e.g., 'major' for X, 'minor' for Y, 'patch' for Z).
- **Key insight**: Tags point to specific commits, making it easy to check-out
  old versions. Drafter's version-resolver suggests next versions based on labels.

### Action to take for adding

- `git tag v0.3.1` (on desired commit)
- Push: `git push origin v0.3.1`

### Action to take for deleting

- Local: `git tag -d v0.3.0` (verify with `git tag -l`)
- Remote (if pushed): `git push origin --delete v0.3.0`

## 3. Creating GitHub Releases Manually (Old Approach)

- **The approach**: A release builds on a tag, adding notes, assets, and metadata.
  `Create Release from Tag` in GitHub drafts a release for your tag (e.g., v0.3.0),
  without altering code. Release Drafter pre-fills notes from merged PRs.
- **Key insight**: This enhances shareability—releases appear in the Releases tab,
  notify watchers, and auto-generate source code zips. It fits your CI/CD (deploy.yml
  and lint_test_build.yml) without changes, as deploys happen on main pushes, and
  releases are post-deploy annotations with Drafter's automation.

- **Action to take**:

  1. After merging to main and confirming deployment (e.g., via curl health check
     in deploy.yml), create/push a tag as in Step 3.
  2. In GitHub: Go to your `repo > Releases tab > Tags (as in your screenshot) >`
     `Select your tag (e.g., v0.3.0) > Click "Create Release from Tag."`
  3. In the draft: Edit Drafter-generated notes (categorized by labels like
     'enhancement' for features).
     Add a title (e.g., "v0.3.0 - Coin Filtering Update"), release
     notes (e.g., "Fixed MySQL query bug; added Gunicorn optimizations"), mark as
     stable (not pre-release), and attach optional assets (e.g., a manual export
     of staticfiles or Godot HTML5 build).
  4. Publish the release. Observe: It auto-adds source code assets and updates the
     "latest" label.

- **Learning tie-in**: Test the release process end-to-end—after publishing, download
  the zip and run tests locally to verify stability, reinforcing your testing mastery.

## 4. Integrating Release Drafter for Automated Changelogs

- **The approach**: Release Drafter drafts release notes as PRs merge, categorizing
  changes by labels (e.g., '🚀 Features' for 'enhancement'). It resolves next SemVer
  version based on labels ('major', 'minor', 'patch').
- **Key insight**: Complements manual tagging—PR previews (#113 workflow) give early
  feedback, and merges update a draft release for easy manual publishing. Fits Godot
  projects by labeling PRs for game changes (e.g., 'bug' for input fixes).

- **Setup and Configuration (.github/release-drafter.yml):**
