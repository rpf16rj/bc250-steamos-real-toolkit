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

7. Build the release zip (excludes `.git`, gitignored build caches/vendored
   kernel trees, etc. — anything not tracked by git is naturally excluded
   since `git archive` only packs tracked files):
   ```bash
   git archive --format=zip -o /tmp/bc250-steamos-real-toolkit-vX.Y.Z.zip vX.Y.Z
   ```

8. Create the GitHub Release:
   - If the `gh` CLI is installed and authenticated (`gh auth status`):
     ```bash
     gh release create vX.Y.Z /tmp/bc250-steamos-real-toolkit-vX.Y.Z.zip \
       --title "vX.Y.Z" \
       --notes-file <(sed -n '/^## vX.Y.Z/,/^## v/p' CHANGELOG.md | sed '$d')
     ```
     Also upload the same zip a second time under a **fixed** asset name so
     the README's "latest release" link never changes across versions:
     ```bash
     cp /tmp/bc250-steamos-real-toolkit-vX.Y.Z.zip /tmp/bc250-steamos-real-toolkit-latest.zip
     gh release upload vX.Y.Z /tmp/bc250-steamos-real-toolkit-latest.zip
     ```
   - Otherwise (no `gh` CLI / no token available to this session): tell the
     user the tag is pushed, and ask them to open
     `https://github.com/<owner>/<repo>/releases/new?tag=vX.Y.Z` in a
     browser, paste in the English changelog section as the release notes,
     and upload `/tmp/bc250-steamos-real-toolkit-vX.Y.Z.zip` twice as
     assets: once as-is, and once renamed to
     `bc250-steamos-real-toolkit-latest.zip` (so the stable "latest" download
     link keeps working release after release).

9. The README's Quick Start section already links to
   `.../releases/latest` (release page) and, where a direct download link is
   used, `.../releases/latest/download/bc250-steamos-real-toolkit-latest.zip`
   — no README changes needed for a routine release unless install
   instructions themselves changed.
