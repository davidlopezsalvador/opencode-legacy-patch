# opencode-legacy-patch

Restores the **legacy UI of OpenCode Desktop (Windows)** by patching the one-line
"sunset date" that OpenCode forced on 2026-09-14 to push everyone onto the new UI.

- **Method**: *same-length* binary patch over the installed app's `app.asar` (no recompiling, no toolchain, no third-party binaries).
- **Tested on**: OpenCode Desktop **1.18.35** (Electron 42), Windows, 2026-10-07.
- **Works with**: 1.18.34 and 1.18.35 (same literal). The script searches for the pattern dynamically, so it also works on future versions **as long as upstream keeps the constant**.

---

## Quick start

Script: [`patch-legacy.ps1`](./patch-legacy.ps1)

```powershell
# 1) Patch (idempotent; works with the app open or closed)
& ".\patch-legacy.ps1"

# 2) Show status (touches nothing)
& ".\patch-legacy.ps1" -Mode status

# 3) Back to 100% official state (close the app first)
& ".\patch-legacy.ps1" -Mode restore
```

After patching: **restart OpenCode**. If your `newLayoutDesigns` preference was already
forced to `true` (the normal case after the sunset), the old-interface toggle appears in
Settings → enable it. With an eligible profile and an undefined preference, the legacy UI
comes up directly without touching anything.

---

## What it does exactly

### 1. Sunset patch in `app.asar`

In `packages/app/src/context/settings.tsx` (compiled inside the asar):

```js
const oldInterfaceSunset = new Date(2026, 8, 14);   // official
const oldInterfaceSunset = new Date(2099, 8, 14);   // patched
```

- The literal is searched **dynamically**; the script requires **exactly 1 occurrence** (if upstream changes it, the script aborts without touching anything).
- **Same-length** replacement (2026 → 2099, 4→4 chars): the asar header only stores file sizes, not hashes → the asar stays valid after writing.
- Post-write verification re-reads the file (2026×0, 2099×1).

Why it works: the UI is decided by
`resolveNewLayoutDesigns(retired, preference, fallback) = retired ? true : (preference ?? fallback)`.
With `retired=false` (date in the future), the user's preference wins and, if it is
undefined, the fallback `legacyNewLayoutDesignsDefault = false` applies for eligible
profiles → legacy UI by default.

### 2. Updater neutralization

The Electron updater schedules `void updater.start()` + a `check()` every 10 minutes in
`packages/desktop/src/main/index.ts` (`autoDownload=false`, but it downloads automatically
when a newer version exists). If left alive, it would download a new version and, on
"restart to update", **restore the official asar and silently wipe the patch**.

Fix: rewrite `resources\app-update.yml` (outside the asar, not covered by Authenticode)
to point at a nonexistent repo → every check ends in `HttpError: 404` → silent `error`
state (error dialogs only open from the menu/IPC). Evidence after the restart:

```
updater state changed { from: 'checking', to: 'error' }
Error: HttpError: 404
```

Result: **OpenCode frozen on 1.18.35** until you decide to update.

### 3. Backup + rollback

The first run creates:

```
%LOCALAPPDATA%\Temp\opencode\legacy-backup-<timestamp>\
    app.asar.bak
    app-update.yml.bak
```

`-Mode restore` reverts both files (it never overwrites a backup with an already-patched
asar: the first backup is kept as the true original).

---

## Verification performed (2026-10-07)

| Check | Result |
|---|---|
| Version | `app starting { version: '1.18.35' }` after relaunch ✅ |
| Literal in asar (1.18.35) | `new Date(2026, 8, 14)` ×1 (confirmed before patching) ✅ |
| After patching | 2026×0, 2099×1 ✅ |
| Hot patch | wrote the asar with the app running → allowed by Windows ✅ |
| Updater | silent 404, no downloads or dialogs ✅ |
| `opencode.settings` | `oldLayoutEligible: true` (toggle available) ✅ |
| Renderer store (`default.dat`) | `showCustomAgents: true`, `layoutTransitionEligible: true`; `newLayoutDesigns` false after the toggle ✅ |
| Legacy UI | active and persistent ✅ |

Safety analysis of the approach:

- **Electron fuses**: `embedded_asar_integrity_validation` defaults to `0` in Electron 42 and `electron-builder.config.ts` configures no fuses → no asar integrity validation.
- **Authenticode**: signs only `OpenCode.exe` (untouched) → no SmartScreen or execution impact.
- **Code cache**: V8 validates source content → it recompiles on its own; no need to clear `Code Cache`.

---

## Updating in the future (workflow)

```powershell
# 1. Close OpenCode and go back to official
& ".\patch-legacy.ps1" -Mode restore

# 2. Open OpenCode → Settings → Check for updates → restart

# 3. Patch again
& ".\patch-legacy.ps1"
# If the literal no longer exists (upstream change), the script detects it and touches nothing.

# 4. Restart → Settings → flip the legacy UI toggle if needed
```

---

## Known limitations and risks

1. **Frozen updates**: while the updater is neutralized, no official bugfixes arrive.
   Update manually with the workflow above.
2. **Upstream literal**: if `new Date(2026, 8, 14)` disappears or changes format, the
   script fails safe (fail-closed) and needs revisiting.
3. **Future integrity fuse**: if a release enables `embedded_asar_integrity_validation`,
   the app would not boot with the patched asar → run `-Mode restore`.
4. **A 1-line patch, not a fork**: it does not replace the UI code; it only stops
   OpenCode from *forcing* the new one. The legacy UI is the legacy code upstream still ships.

---

## Background

- The 2026-09-14 sunset (`oldInterfaceSunset`) forced `newLayoutDesigns=true` on every
  profile → the previous workaround (`default.dat → false`) stopped working.
- Issue: [anomalyco/opencode#38230](https://github.com/anomalyco/opencode/issues/38230)
  (public 👍 vote and comment).
- Community fork `kuznecov-anatoliy/opencode-old-interface`: analyzed and rejected
  (actual base is upstream v1.18.30, 3 minor patches, unsigned binaries).
- Build from source (plan C): rejected for cost (bun + toolchain + maintenance).
- Plan D (this repo): patch on top of the installed app → 5 minutes, reversible.

---

## Files

| File | Description |
|---|---|
| `patch-legacy.ps1` | Script with `patch` (default) / `restore` / `status` modes |
| `README.md` | This document |

## License

MIT — use/share at your discretion.
