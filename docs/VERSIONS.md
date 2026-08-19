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

`VERSION` is `0.1.0`. This is the first line in which reusable motion processing comes from the pinned `core/` submodule instead of being duplicated inline in the libinput patch.

A core-backed replacement patch now exists under `patches/` and is pinned to core commit:

```text
133df50ea5ce58e71e3fed3240c26999ee689386
```

Uncompressed patch SHA-256:

```text
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016
```

The intended behavioral contract remains equivalence with 0.0.14 unless a change is separately documented and tested. The candidate preserves the startup fixed-step/coalescing/rebound behavior, causal reconstruction, profile behavior, release cancellation, free/locked modes, Shift and Scroll Lock semantics, public-post bookkeeping, and middle-click suppression while delegating reusable mechanics to the submodule.

### Current validation status

Algorithm/static validation has passed:

- strict core unit and sanitizer tests;
- standalone reference-trace equivalence against the pre-extraction algorithm for the portable profile paths;
- patch application/whitespace checks on the reconstructed pristine source map;
- strict syntax checking of the integration-owned C block with mock host definitions.

A real Meson/Ninja build against the complete pristine libinput tree has **not** yet run in the current environment because Meson was unavailable and could not be installed from the network. Interactive verification of the core-backed build is also pending.

Therefore 0.1.0 is an implemented development/release candidate, not yet a fully validated replacement for 0.0.14.

## Rule for future versions

Version changes and their behavioral or architectural significance belong in this file. Important version-related decisions made in discussion must be recorded here or in another linked repository document before they are treated as durable project state.
