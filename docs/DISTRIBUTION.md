# Shipping WaterBar

## What the build produces

```bash
bash WaterBar/package.sh
```

- `WaterBar/WaterBar.app` — universal (arm64 + x86_64), macOS 13+, no runtime
  dependencies. The engine is compiled in; there is no Python, no helper
  binary, nothing to install alongside it.
- `dist/WaterBar-<version>.dmg` — ~800 KB, drag-to-Applications window.
- `dist/WaterBar-<version>.dmg.sha256`

The version lives in one place, `WaterBar/Sources/WaterBar/Version.swift`.
`build.sh` reads it and stamps `Info.plist`, so the binary and the bundle can't
disagree.

## Signing: where this currently stands

ClaudeUsageBar, for comparison, is signed `Developer ID Application` and
notarized. That needs a **paid Apple Developer Program membership** ($99/yr).
An "Apple Development" certificate — the free kind — is not enough; Gatekeeper
rejects it for anything distributed outside the App Store.

Without one, `build.sh` falls back to an **ad-hoc signature**. The app runs
perfectly, but a Mac that downloaded it will refuse to open it the first time:

> "WaterBar" cannot be opened because Apple cannot check it for malicious software.

What the user has to do about it depends on their macOS version, and this
caught us out once already:

- **macOS 15 Sequoia and later** — System Settings → Privacy & Security →
  Security → **Open Anyway**. Apple [removed the Control-click override in
  Sequoia](https://developer.apple.com/news/?id=saqachfa); instructions that
  still say "right-click → Open" are wrong on every current Mac.
- **macOS 13–14** — Control-click the app → Open → Open.
- **Any version** — `xattr -dr com.apple.quarantine /Applications/WaterBar.app`.

The Homebrew cask does the last one automatically in its `postflight`, which is
why Homebrew is the install route worth pushing people toward.

### Turning on real signing later

Nothing needs editing. `build.sh` and `package.sh` look for a
`Developer ID Application` certificate in the keychain and use it the moment one
exists, switching on the hardened runtime and a secure timestamp. To also
notarize:

```bash
# once
xcrun notarytool store-credentials waterbar \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

# per release
NOTARY_PROFILE=waterbar bash WaterBar/package.sh --notarize
```

That submits the DMG, waits, and staples the ticket. Then delete the
`postflight` block from `Casks/waterbar.rb` — once notarized, Homebrew's normal
quarantine handling is the safer behaviour.

## Cutting a release

```bash
bash scripts/release.sh 1.1.0
```

It stamps the version, runs the engine parity check, builds and packages,
computes the sha256, rewrites `Casks/waterbar.rb`, commits, tags, pushes, and
creates the GitHub release with the DMG attached.

First time only, the repo has to exist:

```bash
git init && git add -A && git commit -m "Initial commit"
gh repo create waterbar --public --source=. --push
```

## The Homebrew tap

Homebrew looks for casks in a repo named `homebrew-<tap>`. So:

```bash
gh repo create homebrew-tap --public --clone
mkdir -p homebrew-tap/Casks
cp Casks/waterbar.rb homebrew-tap/Casks/
cd homebrew-tap && git add -A && git commit -m "waterbar 1.0.0" && git push
```

Then anyone can install with:

```bash
brew install --cask bmoresca/tap/waterbar
```

On each release, copy the regenerated `Casks/waterbar.rb` over and push again.

## Two engines, one ledger

The Swift engine in the app and `plugin/engine/water.py` are separate
implementations of the same arithmetic. That's deliberate — the app must work
with no interpreter installed, and the plugin must work on machines without the
app (including Linux and Windows). The risk is that they drift.

`scripts/parity-check.sh` is the guard: it runs both against a frozen copy of
your transcripts in throwaway config directories and asserts the resulting
ledgers are **byte-identical** and `state.json` matches field for field.
`release.sh` runs it before every build.

If you change the model constants or the scan logic, change both sides and run:

```bash
bash scripts/parity-check.sh
```

Two subtleties that parity depends on, both already handled:

- Python's `round()` rounds the *decimal* representation. `(x * 10000).rounded() / 10000`
  disagrees with it near boundaries, so the Swift side rounds via `printf`.
- The running total is rounded once per row, not once at the end.

## Release checklist

- [ ] `bash scripts/parity-check.sh` passes
- [ ] `lipo -archs WaterBar/WaterBar.app/Contents/MacOS/WaterBar` → `x86_64 arm64`
- [ ] The DMG opens and the drag-to-Applications window looks right
- [ ] `WaterBar version` from inside the mounted DMG prints the new version
- [ ] Launch from `/Applications`, confirm the menu bar readout appears
- [ ] `Casks/waterbar.rb` sha256 matches `dist/*.dmg.sha256`

## The website

`site/index.html` is generated, not hand-maintained:

```bash
bash scripts/demo-screenshot.sh   # popover screenshot, from FAKE data
python3 site/build.py             # imports the real engine
```

**Never render the published screenshot from your own ledger.** The popover
lists your thirstiest projects *by name*, so a screenshot taken against
`~/.claude` publishes your project - and client - names to the README, the
landing page, and every social preview of it. `scripts/demo-screenshot.sh`
renders it against a synthetic ledger instead; use nothing else.

The achievement grid and the milestone amounts come from `water.MILESTONES` and
`water.format_ml()`, and the animated spinner verbs from `water.VERB_TEMPLATES`,
so the marketing page cannot claim something the app doesn't do. `release.sh`
regenerates and redeploys it as part of cutting a release.

Deploy manually with:

```bash
cd site && vercel deploy --prod
```

The project is `watercount` under `bmorescas-projects`, already linked.

### DNS

`watercount.betomoresca.com` is attached to the project and verified, but
`betomoresca.com` is on Namecheap, so the record has to be added there:

| Type | Host | Value |
|---|---|---|
| CNAME | `watercount` | `9ff2b2e167ed4f0b.vercel-dns-017.com.` |

Check it with `vercel domains verify watercount.betomoresca.com`. Until it
resolves, the site is live at its `*.vercel.app` deployment URL.
