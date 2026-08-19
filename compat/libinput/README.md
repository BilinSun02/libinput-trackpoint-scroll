# libinput compatibility expectations

Files under this directory record integration assumptions that depend on the exact upstream libinput source shape.

Each supported upstream revision has its own directory named by the full libinput commit SHA:

```text
compat/libinput/<LIBINPUT_COMMIT>/
```

`UPSTREAM` remains the authoritative current pin. Automation derives the compatibility directory from `LIBINPUT_COMMIT`; it must not fall back to a manifest belonging to another commit.

For the 0.1.0 timestamp adapter, `usec-boundary.json` records the expected number of call sites in each conversion family. The fixer computes its total from that manifest; there is no independent hardcoded total in the fixer.

The fixer recognizes call sites structurally by function name and parsed C argument positions rather than by exact whitespace/layout or the ordering of unrelated middle arguments. The commit-specific manifest still supplies the authoritative multiplicities, so more tolerant source recognition does not weaken the pin: a missing, extra, or differently shaped boundary site still fails validation.

When re-pinning libinput:

1. update `UPSTREAM`;
2. inspect the new upstream source and integration patch;
3. create and review `compat/libinput/<new-commit>/` expectations for the new source shape;
4. regenerate/revalidate affected patch artifacts and complete the real Meson/Ninja validation.

A missing manifest for the pinned commit is intentional fail-closed behavior: it means that revision has not yet been reviewed for these source-shape assumptions.
