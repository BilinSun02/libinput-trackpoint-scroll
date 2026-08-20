# Versioning

The repository begins its explicit project-version history at **0.0.14**. Earlier experimental patch numbers are not reconstructed into SemVer releases.

## 0.0.14 — known-working pre-core baseline

0.0.14 is the historical distribution previously called **v14**. It is preserved under `releases/0.0.14/` from the exact supplied working bundle rather than regenerated from documentation.

Properties:

- targets the historical upstream revision recorded with that release;
- contains the behavior documented in the historical v14 guide;
- has been used successfully for weeks in normal daily operation;
- keeps startup/coalescing/reconstruction/memoryless-profile logic inline in the libinput patch;
- does not use the `core/` submodule.

Treat 0.0.14 as the compatibility reference when validating refactors.

## 0.1.0 — core-backed line

`VERSION` is `0.1.0`. This is the first line in which reusable motion processing comes from the pinned `core/` submodule instead of being duplicated inline in the libinput patch.

The current upstream libinput revision is defined by the root `UPSTREAM` file. The candidate is pinned to core commit:

```text
133df50ea5ce58e71e3fed3240c26999ee689386
```

The stored base replacement patch has uncompressed SHA-256:

```text
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016
```

The current corrected candidate also includes the documented Meson and timestamp-boundary corrections applied by the managed preparation workflow. Those corrections should be folded into the canonical patch before final release packaging.

The intended behavioral contract remains equivalence with 0.0.14 unless a change is separately documented and tested. The candidate preserves the startup fixed-step/coalescing/rebound behavior, causal reconstruction, profile behavior, release cancellation, free/locked modes, Shift and Scroll Lock semantics, public-post bookkeeping, and middle-click suppression while delegating reusable mechanics to the submodule.

### Current validation status

Completed validation includes:

- strict core unit and sanitizer tests;
- standalone reference-trace equivalence against the pre-extraction algorithm for the portable profile paths;
- patch application/whitespace checks;
- strict syntax checking of the integration-owned C block with mock host definitions;
- real Meson configuration against the pinned libinput source;
- real Ninja compilation after correcting the explicit `usec_t`/`uint64_t` adapter boundary;
- verified installation where the first `ldconfig` cache entry for `libinput.so.10` has the build artifact's ELF Build ID;
- a fresh normal graphical boot after that installation;
- post-reboot live process mappings whose `libinput.so.10` Build ID matches the build artifact;
- host behavior checks for free scrolling/release cancellation, Shift-before-middle, post-middle Shift toggle semantics, Scroll Lock default/latching, and middle-click suppression enabled/disabled;
- adaptive reset wiring verified directly: the integration transform reset calls the upstream adaptive filter restart, and the shared engine invokes that reset on gesture begin/end, in-gesture restart, and idle burst rearm.

Therefore 0.1.0 has passed real host build, verified runtime identity, and the integration-owned behavior matrix. It remains a release candidate only because the temporary Meson and timestamp-boundary corrections still need to be folded into one canonical replacement patch and that final artifact must receive a clean pristine-checkout build/install/runtime verification.

## Rule for future versions

Version changes and their behavioral or architectural significance belong in this file. Important version-related decisions made in discussion must be recorded here or in another linked repository document before they are treated as durable project state.
