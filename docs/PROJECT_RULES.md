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
- Historical release records may retain immutable historical target metadata because that describes the release, not the current development pin.
- Upstream-source-shape expectations must be keyed by commit under `compat/libinput/<LIBINPUT_COMMIT>/`; scripts must not silently reuse counts or assumptions validated against another libinput revision.
- A re-pin is intentionally incomplete until the new commit has its own reviewed compatibility/expectations data. Missing commit-specific data must fail closed rather than inheriting the previous pin's assumptions.
- Re-pinning upstream requires changing `UPSTREAM` first, then validating/regenerating version-specific patches, compatibility manifests, or artifacts whose contents depend on that upstream revision.

## Production patch discipline

Every production patch is pinned to an explicit upstream commit. For the current line, that commit is `LIBINPUT_COMMIT` from `UPSTREAM`.

A production patch must be generated against a real pristine checkout of that revision. Before release:

```text
git apply --check
full Meson configuration
full Ninja build
git diff --check
safe install/cache verification
fresh-session runtime mapping verification
interactive behavioral smoke test
```

Synthetic/reconstructed hunk preimages are useful secondary diagnostics only. They are not sufficient release validation.

Do not claim a full integration build or runtime test unless it actually happened with the intended binary identified.

## Installation discipline

- The managed default prefix is `/usr/local`; do not hardcode `/usr` merely to force cache precedence.
- The installer must derive the configured prefix/install map from Meson rather than assume where a previous custom libinput lives.
- Before installation on Debian/Ubuntu, refuse to overwrite destinations owned by dpkg. Direct package-path replacement requires an explicit Debian packaging or `dpkg-divert` design.
- Do not automatically remove another self-compiled libinput in a different prefix. Install the candidate, run `ldconfig`, and fail closed if another copy remains first in the cache.
- Do not normally run `ninja uninstall` before replacing a compatible custom build in the same prefix; avoid creating an interval where no usable SONAME exists.
- Treat old uninstall manifests as potentially stale. If another build has since installed over the same destinations, an old build tree's `ninja uninstall` may delete the newer build's files.
- After installing a shared-library replacement, run `ldconfig` before restarting the graphical session.
- Describe `ldconfig -p` results as **cache selection**, not proof of what a running process mapped.
- Cache verification is by exact ELF Build ID of the first cache entry for the required SONAME, not merely by checking that some `libinput.so.10` exists.
- Runtime verification after restart must inspect actual process mappings (e.g. `/proc/<pid>/maps`) and compare their ELF Build IDs with the build artifact. `tools/verify-runtime-libinput.sh` is the preferred helper.
- If cache or runtime identity does not match the build artifact, report the observed path/Build ID and do not claim the candidate is active.
- Package upgrades may rebuild the cache or change the distro library. Reverify cache/runtime selection after relevant upgrades.
- If a graphical session fails after installation, preserve evidence before recovery changes when practical: record `journalctl --list-boots`, inspect the failed boot's relevant logs, and capture `ldconfig -p` output.
- Do not promote a plausible loader/cache explanation to a confirmed cause without evidence. Distinguish confirmed facts from hypotheses in durable docs.

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
