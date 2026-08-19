# Project rules

## Repository as source of truth

Important project knowledge must not live only in chat. When a discussion changes behavior, defaults, architecture, invariants, build requirements, debugging lessons, validation expectations, or contribution conventions, update this repository and/or the `core/` repository as appropriate.

Porting handoff documents are the intended exception. Durable conclusions from porting work that affect the shared engine or this integration still belong in the repositories.

## Scope discipline

- Put reusable motion-processing behavior in `core/` when it can be expressed without libinput-specific types or policies.
- Keep device routing, libinput event delivery, keyboard integration, upstream filter wrappers, filesystem configuration, and installation details here.
- Do not create duplicate implementations of the same algorithm in both repositories after a feature has been migrated.
- Avoid chronicles for their own sake. Record current behavior, rationale that prevents regressions, failed design classes that remain relevant, and migration constraints.

## Upstream pin discipline

The root-level `UPSTREAM` file is the single source of truth for the current development line's upstream libinput repository URL, version, and commit.

- Automation that needs the current pin must source or parse `UPSTREAM`; do not embed another current commit/version literal in scripts.
- Human-facing documentation that describes the current target should refer readers to `UPSTREAM` rather than duplicate the pin.
- Historical release records may retain their immutable historical target metadata because that describes the release, not the current development pin.
- Upstream-source-shape expectations must be keyed by commit under `compat/libinput/<LIBINPUT_COMMIT>/`; scripts must not silently reuse counts or assumptions validated against another libinput revision.
- A re-pin is intentionally incomplete until the new commit has its own reviewed compatibility/expectations data. Missing commit-specific data must fail closed rather than inheriting the previous pin's assumptions.
- Re-pinning upstream requires changing `UPSTREAM` first, then validating/regenerating any version-specific patches, compatibility manifests, or artifacts whose contents inherently depend on that upstream revision.

## Production patch discipline

Every production patch is pinned to an explicit upstream commit. For the current line, that commit is `LIBINPUT_COMMIT` from `UPSTREAM`.

A production patch must be generated against a real pristine checkout of that revision. Before release:

```text
git apply --check
full Meson configuration
full Ninja build
git diff --check
interactive behavioral smoke test
safe install/loader verification
```

Synthetic/reconstructed hunk preimages are useful secondary diagnostics only. They are not sufficient release validation.

Do not claim a full integration build happened unless it actually did.

## Installation discipline

- Replacing one `/usr/local` project build with another compatible build should install the replacement directly; do not normally run `ninja uninstall` first.
- After installing a shared-library replacement, run `ldconfig` before restarting the graphical session.
- Verify loader-visible `libinput.so*` paths resolve to real files before logout/reboot. `tools/install-managed-libinput.sh` is the preferred managed-tree path.
- `ninja uninstall` is for intentionally removing a custom build, not the ordinary first step of an upgrade.
- If a graphical session fails after installation, preserve evidence before recovery changes when practical: record `journalctl --list-boots`, inspect the failed boot's display-manager and high-priority logs, and capture `ldconfig -p` output.
- Do not promote a plausible loader/cache explanation to a confirmed cause without evidence. Preserve unresolved installation incidents as unresolved.

## Naming and source conventions

- Namespace new integration helpers, e.g. `evdev_trackpoint_scroll_*`; a previous generic helper name collided with an existing symbol and was caught only by compilation.
- Keep units explicit in names and comments.
- Do not silently rename existing internal upstream symbols only at custom call sites.
- Current profile terminology is `affine`, `quadratic`, `adaptive`, `hyperbolic`.
- Do not reintroduce retired incorrect profile terminology, including as a compatibility alias.

## Behavioral invariants

The integration must preserve the shared core invariants and additionally:

- scroll acceleration remains independent of cursor acceleration;
- free mode stays immediate and two-dimensional;
- locked mode preserves ordinary libinput buildup/axis locking;
- Shift ordering remains significant;
- Scroll Lock remains visible to normal software;
- only fresh physical Scroll Lock presses toggle the custom default;
- no-scroll middle-click suppression never breaks scrolling or creates unmatched button state;
- stop is posted only for a sequence that became public;
- release cancels pending reconstructed tail.
