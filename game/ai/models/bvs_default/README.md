# BVS default

PLACEHOLDER - replaced in S5 by the trained model.

This is a random-weight `bvs-schema-2` policy (MLP 102 -> 64 -> 64 -> 21, Tanh)
exported with `cd training && uv run python -m bvs_training.export --random-init`.
It only exists so the in-game plumbing (the "AI: BVS default" entry in character
select, the offline bundled load, the web export) can be built and tested before
the trained model is ready. It plays badly on purpose; do not ship it as the
final default.

Files:

- `model.onnx`: the logits head of the policy (ops: Gemm, Tanh).
- `bvs.json`: the sidecar (`bvs-model/1`): schema version, observation size,
  action branches, `action_repeat`, provenance.

The game loads these from `res://` with no network (desktop and web). The
`export_presets.cfg` `include_filter` keeps them in the exported package.
