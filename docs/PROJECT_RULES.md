# Project rules

## Repository as source of truth

Important project knowledge must not live only in chat. When a discussion changes behavior, defaults, architecture, invariants, build requirements, debugging lessons, validation expectations, or contribution conventions, update this repository and/or the `core/` repository as appropriate.

Porting handoff documents are the intended exception. Durable conclusions from porting work that affect the shared engine or this integration still belong in the repositories.

## Scope discipline

- Put reusable motion-processing behavior in `core/` when it can be expressed without libinput-specific types or policies.
- Keep device routing, libinput event delivery, keyboard integration, upstream filter wrappers, filesystem configuration, and installation details here.
- Do not create duplicate implementations of the same algorithm in both repositories after a feature has been migrated.
- Avoid chronicles for their own sake. Record current behavior, rationale that prevents regressions, failed design classes that remain relevant, and migration constraints.

## Production patch discipline

Every production patch is pinned to an explicit upstream commit. For the current line that commit is:

```text
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

A production patch must be generated against a real pristine checkout of that revision. Before release:

```text
git apply --check
full Meson configuration
full Ninja build
git diff --check
```

Synthetic/reconstructed hunk preimages are useful secondary diagnostics only. They are not sufficient release validation.

Do not claim a full integration build happened unless it actually did.

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
