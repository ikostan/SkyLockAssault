# Guide to Implementing Versioning

A step-by-step guide summarizing our conversation on versioning,
specifically choosing the Manual Approach. The main focus on the core
steps that directly support your goals with Semantic Versioning and
manual releases.

## 1. Main Flow: Versioning After Branch Work and PR Merge

When working in branches (e.g., for PR #98 on user feedback or new
feature implementation), follow this sequence to ensure tags and
releases mark reviewed, merged, and tested code—aligning with SemVer
for the game app.

Key insight: Tagging post-merge on main keeps versions stable and deployable,
as merges trigger CI/CD (e.g., GDLint in lint_test_build.yml and deploy.yml).

### Action to take (Step by Step Guide)

1. wait until review is over (e.g., approve PR #98 on GitHub)
2. merge the code to main (click "Merge pull request")
3. confirm it passes CI/CD (including deployment to VPS)
4. create a new tag v0.2.1 working from the main branch:
   - In `CMD` terminal, switch to main (git checkout main)
   - pull updates (git pull origin main)
   - then git tag v0.2.1 (on the merge commit)
5. Make a push to the origin: git push origin v0.2.1 (verify in GitHub's Tags tab)
6. Manually create the release on GitHub:
   - Go to Releases tab > Draft a new release > Select v0.2.1
   - Add title/notes (e.g., "v0.2.1 - User Feedback Phase 1; merged PR #98")
   - Publish

## 2. Adopting Semantic Versioning (SemVer) with Git Tags

- **The approach**: Use tags for immutable snapshots instead of branches.
  Follow SemVer: `vX.Y.Z` where X is major (breaking changes), Y is minor
  (new features), Z is patch (fixes).
- **Key insight**: Tags point to specific commits, making it easy to check-out
  old versions (e.g., `git checkout v0.3.0`).
- **Action to take**: From `CMD` terminal, tag your next stable commit:
  `git tag v0.4.0` (after a minor feature), then `git push origin v0.4.0`.
- View it in GitHub's Tags tab.

### 2.1: Verifying Tags Locally and Remotely

Always check where tags exist (e.g., your output showed v0.3.0 local but not remote).
Key insight: Local tags aren't auto-pushed; use commands to sync and inspect.

Action to take:

- Local list: `git tag -l` (e.g., shows v0.1.0, v0.1.5, v0.2.0, v0.2.1).
- Fetch remote: `git fetch --tags`.
- Remote list: `git ls-remote --tags origin`
  (e.g., shows hashes like 282c817 for v0.1.0).

### 2.2: Adding and Deleting Tags

Add tags for milestones; delete if mistaken (e.g., v0.3.0 deleted locally
as "Deleted tag 'v0.3.0' (was e39fcab)").
**Key insight**: Deletion removes the pointer, not commits—safe for cleanup.

#### Action to take for adding

- `git tag v0.3.1` (on desired commit)
- Push: `git push origin v0.3.1`

#### Action to take for deleting

- Local: `git tag -d v0.3.0` (verify with `git tag -l`)
- Remote (if pushed): `git push origin --delete v0.3.0`

## 3. Creating GitHub Releases Manually (Your Chosen Approach)

- **The approach**: A release builds on a tag, adding notes, assets, and metadata.
  `Create Release from Tag` in GitHub drafts a release for your tag (e.g., v0.3.0),
  without altering code.
- **Key insight**: This enhances shareability—releases appear in the Releases tab,
  notify watchers, and auto-generate source code zips. It fits your CI/CD (deploy.yml
  and lint_test_build.yml) without changes, as deploys happen on main pushes, and
  releases are post-deploy annotations.
- **Action to take**:

  1. After merging to main and confirming deployment (e.g., via curl health check
     in deploy.yml), create/push a tag as in Step 3.
  2. In GitHub: Go to your `repo > Releases tab > Tags (as in your screenshot) >`
     `Select your tag (e.g., v0.3.0) > Click "Create Release from Tag."`
  3. In the draft: Add a title (e.g., "v0.3.0 - Coin Filtering Update"), release
     notes (e.g., "Fixed MySQL query bug; added Gunicorn optimizations"), mark as
     stable (not pre-release), and attach optional assets (e.g., a manual export
     of staticfiles).
  4. Publish the release. Observe: It auto-adds source code assets and updates the
     "latest" label.

- **Learning tie-in**: Test the release process end-to-end—after publishing, download
  the zip and run tests locally to verify stability, reinforcing your testing mastery.
