# Versioning

The repository begins its explicit project-version history at **0.0.14**. Earlier experimental patch numbers are not reconstructed into SemVer releases.

## 0.0.14 — known-working pre-core baseline

0.0.14 is the historical distribution previously called **v14**. It is preserved under `releases/0.0.14/` from the exact supplied working bundle rather than regenerated from documentation.

Properties:

- targets libinput 1.31.0 commit `659967488e1e66d7fb7210c6b86860c8e1e5bed4`;
- contains the behavior documented in the historical v14 guide;
- has been used successfully for weeks in normal daily operation;
- keeps startup/coalescing/reconstruction/memoryless-profile logic inline in the libinput patch;
- does not use the `core/` submodule.

Treat 0.0.14 as the compatibility reference when validating refactors.

## 0.1.0 — core-backed line

`VERSION` is now `0.1.0`. This line is the first architecture in which reusable motion processing is required to come from the pinned `core/` submodule instead of being duplicated inline in the libinput patch.

The intended behavioral contract is equivalence with 0.0.14 unless a change is separately documented and tested. The migration must preserve startup fixed-step/coalescing/rebound behavior, sustained reconstruction, profile behavior, release cancellation, free/locked modes, Shift and Scroll Lock semantics, public-post bookkeeping, and middle-click suppression.

0.1.0 is not considered release-complete merely because the repository version has been bumped: the production patch must actually link the shared core, build against the pristine pinned libinput source, and pass the equivalence and interactive checks documented in `CORE_MIGRATION.md`.

## Rule for future versions

Version changes and their behavioral or architectural significance belong in this file. Important version-related decisions made in discussion must be recorded here or in another linked repository document before they are treated as durable project state.
