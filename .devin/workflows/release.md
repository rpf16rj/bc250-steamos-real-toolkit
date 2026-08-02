---
description: Cut a new numbered release (GitFlow) with EN/PT changelogs and a downloadable zip
---

Branching model: `develop` is where all ongoing work happens (commit directly
or via short-lived feature branches merged into `develop`). `main` only ever
receives fast-forward-free merges from `develop` at release time, and every
commit on `main` corresponds to exactly one tagged release `vX.Y.Z`.

When the user asks to "lançar uma versão" / "cut a release" / "release a new
version", follow these steps:

1. Make sure all intended work is committed and pushed on `develop`.
   ```bash
   git checkout develop
   git status --short   # must be clean
   ```

2. Decide the version bump (ask the user if ambiguous):
   - **patch** (`X.Y.Z` → `X.Y.Z+1`): bug fixes only, no new features/behavior changes.
   - **minor** (`X.Y.Z` → `X.Y+1.0`): new features/patches added, backward compatible.
   - **major** (`X.Y.Z` → `X+1.0.0`): breaking changes (e.g. install-path changes, removed features).
   Read the current version from `VERSION` at the repo root and compute the new one.

3. Write the new release's changelog entry **at the top** of both:
   - `CHANGELOG.md` (English) — new `## vX.Y.Z — YYYY-MM-DD` heading above the
     previous top entry, bullets grouped as **Added** / **Changed** / **Fixed** / **Removed**.
   - `CHANGELOG.pt-br.md` (Portuguese) — same structure, translated (não é
     tradução literal palavra-por-palavra, mas mesmo conteúdo/estrutura).
   Base the bullets on the commits/diffs since the last release tag
   (`git log <last-tag>..HEAD --oneline`) and on this session's own knowledge
   of what changed.

4. Update the `VERSION` file to the new version (no `v` prefix, e.g. `1.1.0`).

5. Commit on `develop`:
   ```bash
   git add VERSION CHANGELOG.md CHANGELOG.pt-br.md
   git commit -m "chore(release): vX.Y.Z"
   git push origin develop
   ```

6. Merge into `main` and tag:
   ```bash
   git checkout main
   git pull origin main
   git merge --no-ff develop -m "release: vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   git checkout develop
   ```

7. That's it — pushing the tag in step 6 triggers
   `.github/workflows/release.yml` on GitHub Actions, which:
   - extracts the `## vX.Y.Z` section from `CHANGELOG.md` as the release notes,
   - builds `bc250-steamos-real-toolkit-vX.Y.Z.zip` via `git archive` on the
     tag (only git-tracked files, so build caches/vendored kernel trees are
     naturally excluded),
   - also publishes a copy under the **fixed** name
     `bc250-steamos-real-toolkit-latest.zip`, so the README's "latest
     release" download link never changes across versions,
   - and creates the GitHub Release itself using the built-in
     `GITHUB_TOKEN` — no manual step, `gh` CLI, or personal access token
     needed.
   Check the **Actions** tab on GitHub to confirm the `Release` workflow
   run succeeded, then verify the new release appears under
   `https://github.com/<owner>/<repo>/releases`.

8. The README's Quick Start section already links to
   `.../releases/latest/download/bc250-steamos-real-toolkit-latest.zip`
   — no README changes needed for a routine release unless install
   instructions themselves changed.

**Note:** if `.github/workflows/release.yml` didn't exist yet (or changed)
at the commit a tag points to, GitHub Actions won't run it for that tag.
When bootstrapping this workflow for the first time, or after editing the
release workflow itself, delete and re-push the tag once the workflow file
is merged into `main` so it points at a commit that actually contains it:
```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```
