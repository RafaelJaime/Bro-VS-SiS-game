# ONNX MLP Inference Specification

## Purpose

A pure-GDScript ONNX reader and MLP interpreter so policies run identically on desktop and in the non-.NET web build. Only feed-forward MLPs within a fixed op whitelist are supported. Verification: `tests/smoke/onnx_golden.gd` against Python onnxruntime golden fixtures.

## Requirements

### Requirement: ONNX model parsing

The system MUST parse an ONNX `ModelProto` byte buffer in GDScript, reading the graph nodes, initializers (float32 as raw data or float data), and graph inputs/outputs, with no .NET, GDExtension, or JavaScript bridge. Parsing MUST not mutate the input buffer and MUST be deterministic.

#### Scenario: Parse export
- GIVEN the committed default model bytes
- WHEN parsed
- THEN the graph exposes its input name and dimension, output name and dimension, the node list, and all initializers

#### Scenario: Raw and float data encodings
- GIVEN two fixtures encoding the same weights, one as raw data and one as float data
- WHEN both are parsed and run on the same input
- THEN the outputs are equal

#### Scenario: Same result on every platform
- GIVEN the same model and input
- WHEN run in the desktop editor and in the web export
- THEN outputs match within the golden tolerance

### Requirement: Operator whitelist

The interpreter MUST support exactly the ops the export emits at opset 17 as fixed in the design (baseline: `Gemm`, `MatMul`, `Add`, `Relu`, `Tanh`, `Sigmoid`, `Identity`, `Constant`, `Flatten`, `Reshape`, `Concat`, `Slice`, `Squeeze`, `Unsqueeze`, and `ArgMax` if emitted). Any other op MUST cause the load to fail with an error naming the op. Extending the whitelist MUST be accompanied by golden coverage of the new op.

#### Scenario: Supported ops
- GIVEN a model using only whitelisted ops
- WHEN loaded
- THEN loading succeeds

#### Scenario: Unsupported op rejected
- GIVEN a model containing a `Conv` node
- WHEN loaded
- THEN loading fails with an error naming `Conv` and no partially built model is usable

#### Scenario: Unsupported attribute
- GIVEN a `Gemm` node with an attribute combination the interpreter does not implement
- WHEN loaded
- THEN loading fails with an error naming the node and attribute

### Requirement: Input validation and shape errors

The interpreter MUST reject at load time: external-data tensors, non-float32 weights, a missing graph input or output, and shape mismatches between consecutive nodes. At run time it MUST reject an input whose length differs from the model's input dimension. Errors MUST be returned to the caller as a result with a human-readable reason and MUST NOT crash the game or return partial output.

#### Scenario: Wrong input length
- GIVEN a model with input dim 40
- WHEN run on a vector of length 39
- THEN an error stating expected 40 and got 39 is returned and no output is produced

#### Scenario: External data
- GIVEN a model whose initializer uses external data
- WHEN loaded
- THEN loading fails with a clear external-data error

#### Scenario: Truncated or corrupt buffer
- GIVEN a model buffer truncated mid-node or filled with random bytes
- WHEN parsed
- THEN loading fails with a parse error and does not hang or crash

#### Scenario: Empty buffer
- GIVEN a zero-length buffer
- WHEN parsed
- THEN loading fails with a parse error

### Requirement: Numerical parity with onnxruntime

For every golden fixture, the interpreter output MUST match the onnxruntime output within an absolute tolerance of 1e-4, and the decoded argmax action (per branch) MUST match exactly. Fixtures MUST include a fixed synthetic set and recorded in-game observations.

#### Scenario: Output within tolerance
- GIVEN the committed golden fixtures
- WHEN each observation is run through the interpreter
- THEN every output element differs from the expected by at most 1e-4

#### Scenario: Argmax exact
- GIVEN the committed golden fixtures
- WHEN actions are decoded from the interpreter output
- THEN every branch index equals the expected index

#### Scenario: Edge-value inputs
- GIVEN fixtures with all-zero, all-one, and range-extreme observations
- WHEN run
- THEN parity holds and no output element is NaN

### Requirement: Inference cost

A forward pass of the shipped default model MUST run without allocating per-call graph structures (weights are parsed once at load). The cost MUST be small enough to run once per `action_repeat` ticks without frame hitches in the web export.

#### Scenario: Weights parsed once
- GIVEN a loaded model run 100 times
- WHEN parse invocations are counted
- THEN parsing occurred once

#### Scenario: Frame cost on web
- GIVEN the web export with the default model driving one fighter
- WHEN a match is played and frame times are sampled
- THEN no frame exceeds the 60 FPS budget because of inference (measured, recorded in the verification report)

### Requirement: Golden fixture generation

A Python script MUST run the exported model in onnxruntime on the fixed and recorded observations and write the JSON fixtures consumed by the smoke test. Regenerating with an unchanged model MUST produce byte-identical fixtures.

#### Scenario: Reproducible fixtures
- GIVEN an unchanged model and observation set
- WHEN the golden script runs twice
- THEN both outputs are byte-identical

#### Scenario: Python-side check
- GIVEN the generated fixtures
- WHEN a Python check recomputes the outputs with onnxruntime
- THEN they match the stored values exactly
