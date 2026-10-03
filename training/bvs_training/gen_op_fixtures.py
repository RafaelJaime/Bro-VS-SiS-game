"""Generate the ONNX interpreter fixtures under tests/fixtures/onnx/ops/.

One synthetic model per whitelisted op (and per interesting attribute/encoding
variant) plus rejection fixtures, built with `onnx.helper`. Expected outputs come
from onnxruntime. Output is deterministic: seeded data, deterministic protobuf
serialization and sorted JSON, so a re-run is byte-identical.

    cd training && uv run python -m bvs_training.gen_op_fixtures

Layout of each fixture pair:
    <name>.onnx   the model bytes
    <name>.json   {"cases": [{"input": [...], "expected": [...]}], "tolerance": 1e-4}
                  or, for rejections, {"reject": "<substring of the load error>"}
    manifest.json ordered lists of accepted and rejected fixture names
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper

from bvs_training.onnx_ops import audit

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "tests" / "fixtures" / "onnx" / "ops"
TOLERANCE = 1e-4
N = 6  # input width of the per-op fixtures
F = TensorProto.FLOAT
I64 = TensorProto.INT64


# ------------------------------------------------------------------ builders


def f32(values, shape=None) -> np.ndarray:
    arr = np.asarray(values, dtype=np.float32)
    return arr.reshape(shape) if shape is not None else arr


def init(name: str, arr: np.ndarray, raw: bool = False) -> TensorProto:
    """A float32 or int64 initializer, as float_data/int64_data or raw_data."""
    dtype = F if arr.dtype == np.float32 else I64
    if raw:
        return helper.make_tensor(name, dtype, arr.shape, arr.tobytes(), raw=True)
    return helper.make_tensor(name, dtype, arr.shape, arr.flatten().tolist())


def i64(name: str, values, raw: bool = False) -> TensorProto:
    return init(name, np.asarray(values, dtype=np.int64), raw)


def vi(name: str, shape) -> onnx.ValueInfoProto:
    return helper.make_tensor_value_info(name, F, shape)


def make_model(nodes, inputs, outputs, inits=(), opset: int = 17, name: str = "g") -> onnx.ModelProto:
    graph = helper.make_graph(nodes, name, inputs, outputs, list(inits))
    model = helper.make_model(
        graph,
        opset_imports=[helper.make_opsetid("", opset)],
        producer_name="bvs-fixtures",
    )
    model.ir_version = 8
    return model


def serialize(model: onnx.ModelProto) -> bytes:
    return model.SerializeToString(deterministic=True)


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, sort_keys=True, indent=1) + "\n")


def input_cases(rng: np.random.Generator, width: int) -> list[np.ndarray]:
    """Random, zeros and a wide ramp so Relu/Clip/Tanh saturation is covered."""
    return [
        rng.uniform(-2.0, 2.0, size=width).astype(np.float32),
        np.zeros(width, dtype=np.float32),
        np.linspace(-6.0, 6.0, width).astype(np.float32),
    ]


def run_ort(model: onnx.ModelProto, feed_first: np.ndarray) -> np.ndarray:
    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(serialize(model), options, providers=["CPUExecutionProvider"])
    feed = {}
    for index, spec in enumerate(session.get_inputs()):
        if index == 0:
            feed[spec.name] = feed_first.reshape(1, -1)
        else:
            shape = [d if isinstance(d, int) else 1 for d in spec.shape]
            feed[spec.name] = np.zeros(shape, dtype=np.float32)
    return session.run(None, feed)[0]


# ------------------------------------------------------------------ fixture set


class Fixtures:
    def __init__(self) -> None:
        self.ok: dict[str, tuple[bytes, dict]] = {}
        self.rejects: dict[str, tuple[bytes, str]] = {}
        self.seed = 0

    def add(self, name: str, model: onnx.ModelProto, width: int = N, cases=None) -> None:
        problems = audit(model)
        if problems:
            raise SystemExit(f"{name}: fixture violates the whitelist: {problems}")
        self.seed += 1
        rng = np.random.default_rng(1000 + self.seed)
        inputs = cases if cases is not None else input_cases(rng, width)
        out_cases = []
        for case in inputs:
            expected = run_ort(model, case).astype(np.float32).flatten()
            out_cases.append({"input": [float(v) for v in case], "expected": [float(v) for v in expected]})
        self.ok[name] = (serialize(model), {"cases": out_cases, "tolerance": TOLERANCE})

    def reject(self, name: str, data: bytes, reason: str) -> None:
        self.rejects[name] = (data, reason)


def weights(rng: np.random.Generator, *shape: int) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, size=shape).astype(np.float32)


def build_ops(fx: Fixtures) -> None:
    rng = np.random.default_rng(7)
    x = vi("x", [1, N])
    W = weights(rng, N, 3)
    WT = np.ascontiguousarray(W.T)  # [3, N] for transB
    B = weights(rng, 3)

    def unary(name: str, op: str, **attrs) -> None:
        fx.add(name, make_model([helper.make_node(op, ["x"], ["y"], **attrs)], [x], [vi("y", [1, N])]))

    # Gemm: attribute and C-broadcast variants, both tensor encodings.
    for raw in (False, True):
        suffix = "raw" if raw else "float"
        fx.add(
            f"gemm_{suffix}_data",
            make_model(
                [helper.make_node("Gemm", ["x", "W", "B"], ["y"])],
                [x], [vi("y", [1, 3])], [init("W", W, raw), init("B", B, raw)],
            ),
        )
    fx.add(
        "gemm_no_c",
        make_model([helper.make_node("Gemm", ["x", "W"], ["y"])], [x], [vi("y", [1, 3])], [init("W", W)]),
    )
    fx.add(
        "gemm_alpha_beta_transb",
        make_model(
            [helper.make_node("Gemm", ["x", "WT", "C"], ["y"], alpha=0.5, beta=2.0, transB=1)],
            [x], [vi("y", [1, 3])], [init("WT", WT), init("C", weights(rng, 1, 3))],
        ),
    )
    fx.add(
        "gemm_c_vector",
        make_model(
            [helper.make_node("Gemm", ["x", "W", "C"], ["y"], beta=0.75)],
            [x], [vi("y", [1, 3])], [init("W", W), init("C", B)],
        ),
    )
    # transA turns the [1, N] input into [N, 1] (M = N, K = 1): C may then be [M, N].
    fx.add(
        "gemm_transa_c_full",
        make_model(
            [helper.make_node("Gemm", ["x", "Wk", "C"], ["y"], transA=1, alpha=1.5)],
            [x], [vi("y", [N, 3])], [init("Wk", weights(rng, 1, 3)), init("C", weights(rng, N, 3))],
        ),
    )
    fx.add(
        "gemm_transa_transb",
        make_model(
            [helper.make_node("Gemm", ["x", "Wk"], ["y"], transA=1, transB=1)],
            [x], [vi("y", [N, 2])], [init("Wk", weights(rng, 2, 1))],
        ),
    )

    fx.add(
        "matmul",
        make_model([helper.make_node("MatMul", ["x", "W"], ["y"])], [x], [vi("y", [1, 3])], [init("W", W)]),
    )

    # Elementwise Add / Mul: same shape, trailing vector, scalar, scalar-as-[1], both operand orders.
    for op in ("Add", "Mul"):
        low = op.lower()
        same = weights(rng, 1, N)
        vec = weights(rng, N)
        scalar = f32(0.5)
        fx.add(
            f"{low}_same_shape",
            make_model([helper.make_node(op, ["x", "c"], ["y"])], [x], [vi("y", [1, N])], [init("c", same)]),
        )
        fx.add(
            f"{low}_trailing_vector",
            make_model([helper.make_node(op, ["x", "c"], ["y"])], [x], [vi("y", [1, N])], [init("c", vec)]),
        )
        fx.add(
            f"{low}_scalar_first",
            make_model([helper.make_node(op, ["c", "x"], ["y"])], [x], [vi("y", [1, N])], [init("c", scalar)]),
        )
        fx.add(
            f"{low}_scalar_one_element",
            make_model([helper.make_node(op, ["x", "c"], ["y"])], [x], [vi("y", [1, N])], [init("c", f32([2.0]))]),
        )
        fx.add(
            f"{low}_two_dynamic_inputs",
            make_model(
                [helper.make_node("Tanh", ["x"], ["t"]), helper.make_node(op, ["x", "t"], ["y"])],
                [x], [vi("y", [1, N])],
            ),
        )

    unary("relu", "Relu")
    unary("tanh", "Tanh")
    unary("sigmoid", "Sigmoid")
    unary("identity", "Identity")

    # Clip (opset 13+: bounds are optional inputs).
    fx.add(
        "clip_min_max",
        make_model(
            [helper.make_node("Clip", ["x", "lo", "hi"], ["y"])],
            [x], [vi("y", [1, N])], [init("lo", f32(-1.0)), init("hi", f32(1.5))],
        ),
    )
    fx.add(
        "clip_min_only",
        make_model(
            [helper.make_node("Clip", ["x", "lo"], ["y"])],
            [x], [vi("y", [1, N])], [init("lo", f32(-0.5))],
        ),
    )
    fx.add(
        "clip_max_only",
        make_model(
            [helper.make_node("Clip", ["x", "", "hi"], ["y"])],
            [x], [vi("y", [1, N])], [init("hi", f32(0.25))],
        ),
    )

    # Shape ops. Axes and shapes are INT64 initializers (both encodings).
    fx.add(
        "flatten_axis1",
        make_model(
            [helper.make_node("Reshape", ["x", "s"], ["r"]), helper.make_node("Flatten", ["r"], ["y"], axis=1)],
            [x], [vi("y", [1, N])], [i64("s", [1, 2, 3])],
        ),
    )
    fx.add(
        "flatten_axis2",
        make_model(
            [helper.make_node("Reshape", ["x", "s"], ["r"]), helper.make_node("Flatten", ["r"], ["y"], axis=2)],
            [x], [vi("y", [2, 3])], [i64("s", [1, 2, 3])],
        ),
    )
    fx.add(
        "flatten_axis0",
        make_model([helper.make_node("Flatten", ["x"], ["y"], axis=0)], [x], [vi("y", [1, N])]),
    )
    fx.add(
        "reshape_basic",
        make_model(
            [helper.make_node("Reshape", ["x", "s"], ["y"])], [x], [vi("y", [3, 2])], [i64("s", [3, 2])]
        ),
    )
    fx.add(
        "reshape_infer_dim",
        make_model(
            [helper.make_node("Reshape", ["x", "s"], ["y"])], [x], [vi("y", [3, 2])], [i64("s", [-1, 2], raw=True)]
        ),
    )
    fx.add(
        "reshape_copy_dim",
        make_model(
            [helper.make_node("Reshape", ["x", "s"], ["y"])], [x], [vi("y", [1, N])], [i64("s", [0, -1])]
        ),
    )
    fx.add(
        "reshape_constant_node_shape",
        make_model(
            [
                helper.make_node(
                    "Constant", [], ["s"], value=helper.make_tensor("v", I64, [2], [2, 3])
                ),
                helper.make_node("Reshape", ["x", "s"], ["y"]),
            ],
            [x], [vi("y", [2, 3])],
        ),
    )
    fx.add(
        "squeeze_axes",
        make_model(
            [helper.make_node("Squeeze", ["x", "a"], ["y"])], [x], [vi("y", [N])], [i64("a", [0])]
        ),
    )
    fx.add(
        "squeeze_no_axes",
        make_model(
            [helper.make_node("Unsqueeze", ["x", "a"], ["u"]), helper.make_node("Squeeze", ["u"], ["y"])],
            [x], [vi("y", [N])], [i64("a", [0, 2], raw=True)],
        ),
    )
    fx.add(
        "unsqueeze_front",
        make_model(
            [helper.make_node("Unsqueeze", ["x", "a"], ["y"])], [x], [vi("y", [1, 1, N])], [i64("a", [0])]
        ),
    )
    fx.add(
        "unsqueeze_negative_axis",
        make_model(
            [helper.make_node("Unsqueeze", ["x", "a"], ["y"])], [x], [vi("y", [1, N, 1])], [i64("a", [-1])]
        ),
    )
    fx.add(
        "concat_axis1",
        make_model(
            [helper.make_node("Concat", ["x", "c"], ["y"], axis=1)],
            [x], [vi("y", [1, N + 2])], [init("c", weights(rng, 1, 2))],
        ),
    )
    fx.add(
        "concat_axis0_three_inputs",
        make_model(
            [helper.make_node("Concat", ["x", "c", "x"], ["y"], axis=0)],
            [x], [vi("y", [3, N])], [init("c", weights(rng, 1, N))],
        ),
    )
    fx.add(
        "concat_negative_axis",
        make_model(
            [helper.make_node("Concat", ["c", "x"], ["y"], axis=-1)],
            [x], [vi("y", [1, N + 2])], [init("c", weights(rng, 1, 2))],
        ),
    )

    # Constant node value forms.
    fx.add(
        "constant_tensor_add",
        make_model(
            [
                helper.make_node(
                    "Constant", [], ["c"], value=helper.make_tensor("v", F, [1, N], weights(rng, 1, N).flatten().tolist())
                ),
                helper.make_node("Add", ["x", "c"], ["y"]),
            ],
            [x], [vi("y", [1, N])],
        ),
    )
    fx.add(
        "constant_value_float",
        make_model(
            [
                helper.make_node("Constant", [], ["c"], value_float=1.25),
                helper.make_node("Add", ["x", "c"], ["y"]),
            ],
            [x], [vi("y", [1, N])],
        ),
    )
    fx.add(
        "constant_value_floats",
        make_model(
            [
                helper.make_node("Constant", [], ["c"], value_floats=[0.5, -0.5, 1.0, -1.0, 2.0, -2.0]),
                helper.make_node("Mul", ["x", "c"], ["y"]),
            ],
            [x], [vi("y", [1, N])],
        ),
    )

    # Structure and encodings.
    fx.add(
        "initializer_also_graph_input",
        make_model(
            [helper.make_node("Add", ["x", "c"], ["y"])],
            [x, vi("c", [1, N])], [vi("y", [1, N])], [init("c", weights(rng, 1, N))],
        ),
    )
    fx.add(
        "unsorted_nodes",
        make_model(
            [helper.make_node("Tanh", ["a"], ["y"]), helper.make_node("Add", ["x", "c"], ["a"])],
            [x], [vi("y", [1, N])], [init("c", weights(rng, 1, N))],
        ),
    )
    fx.add(
        "dynamic_batch_dim",
        make_model(
            [helper.make_node("Add", ["x", "c"], ["y"])],
            [vi("x", ["batch", N])], [vi("y", ["batch", N])], [init("c", weights(rng, N))],
        ),
    )
    fx.add(
        "opset_13",
        make_model(
            [helper.make_node("Gemm", ["x", "W", "B"], ["y"])],
            [x], [vi("y", [1, 3])], [init("W", W), init("B", B)], opset=13,
        ),
    )
    fx.add(
        "opset_18",
        make_model(
            [helper.make_node("Gemm", ["x", "W", "B"], ["y"])],
            [x], [vi("y", [1, 3])], [init("W", W), init("B", B)], opset=18,
        ),
    )
    fx.add(
        "extra_state_input_and_output",
        make_model(
            [
                helper.make_node("Add", ["x", "state_ins"], ["output"]),
                helper.make_node("Identity", ["state_ins"], ["state_outs"]),
            ],
            [x, vi("state_ins", [1])], [vi("output", [1, N]), vi("state_outs", [1])],
        ),
    )


def build_mlps(fx: Fixtures) -> None:
    """A 102 -> 64 -> 64 -> 21 Tanh MLP (the reference policy shape) and variants."""
    rng = np.random.default_rng(42)

    def dense(i: int, o: int):
        return weights(rng, i, o) * np.float32(np.sqrt(2.0 / (i + o))), weights(rng, o) * np.float32(0.1)

    w1, b1 = dense(102, 64)
    w2, b2 = dense(64, 64)
    w3, b3 = dense(64, 21)
    # torch stores Linear weights as [out, in] and exports Gemm(transB=1).
    nodes = [
        helper.make_node("Gemm", ["obs", "w1", "b1"], ["h1"], alpha=1.0, beta=1.0, transB=1),
        helper.make_node("Tanh", ["h1"], ["a1"]),
        helper.make_node("Gemm", ["a1", "w2", "b2"], ["h2"], alpha=1.0, beta=1.0, transB=1),
        helper.make_node("Tanh", ["h2"], ["a2"]),
        helper.make_node("Gemm", ["a2", "w3", "b3"], ["logits"], alpha=1.0, beta=1.0, transB=1),
    ]
    inits = [
        init("w1", np.ascontiguousarray(w1.T), raw=True), init("b1", b1, raw=True),
        init("w2", np.ascontiguousarray(w2.T), raw=True), init("b2", b2, raw=True),
        init("w3", np.ascontiguousarray(w3.T), raw=True), init("b3", b3, raw=True),
    ]
    model = make_model(nodes, [vi("obs", [1, 102])], [vi("logits", [1, 21])], inits)
    edge = np.random.default_rng(99)
    cases = [
        edge.uniform(-1.0, 1.0, 102).astype(np.float32),
        edge.uniform(-1.0, 1.0, 102).astype(np.float32),
        edge.uniform(-5.0, 5.0, 102).astype(np.float32),
        np.zeros(102, dtype=np.float32),
        np.ones(102, dtype=np.float32),
        np.full(102, 5.0, dtype=np.float32),  # clip upper bound of the schema
        np.full(102, -5.0, dtype=np.float32),  # clip lower bound: negative saturation
        np.where(np.arange(102) % 2 == 0, 5.0, -5.0).astype(np.float32),
    ]
    fx.add("mlp_102_64_64_21", model, cases=cases)

    # Same net written the way other exporters do: MatMul + Add, Relu, [in, out] weights.
    nodes2 = [
        helper.make_node("MatMul", ["obs", "m1"], ["p1"]),
        helper.make_node("Add", ["p1", "c1"], ["q1"]),
        helper.make_node("Relu", ["q1"], ["r1"]),
        helper.make_node("MatMul", ["r1", "m2"], ["p2"]),
        helper.make_node("Add", ["p2", "c2"], ["logits"]),
    ]
    mw1, mb1 = dense(102, 32)
    mw2, mb2 = dense(32, 21)
    model2 = make_model(
        nodes2, [vi("obs", [1, 102])], [vi("logits", [1, 21])],
        [init("m1", mw1), init("c1", mb1), init("m2", mw2), init("c2", mb2)],
    )
    fx.add("mlp_matmul_relu_102_32_21", model2, cases=cases[:4] + cases[5:7])

    # Sigmoid head with a Clip on the observation, as a defensive exporter might emit.
    nodes3 = [
        helper.make_node("Clip", ["obs", "lo", "hi"], ["c"]),
        helper.make_node("Gemm", ["c", "g1", "gb1"], ["h"]),
        helper.make_node("Sigmoid", ["h"], ["s"]),
        helper.make_node("Gemm", ["s", "g2", "gb2"], ["logits"]),
    ]
    gw1, gb1 = dense(102, 16)
    gw2, gb2 = dense(16, 21)
    model3 = make_model(
        nodes3, [vi("obs", [1, 102])], [vi("logits", [1, 21])],
        [init("lo", f32(-5.0)), init("hi", f32(5.0)), init("g1", gw1), init("gb1", gb1), init("g2", gw2), init("gb2", gb2)],
    )
    fx.add("mlp_clip_sigmoid_102_16_21", model3, cases=[cases[2], cases[5], cases[6]])


def build_rejects(fx: Fixtures) -> None:
    rng = np.random.default_rng(5)
    x = vi("x", [1, 4])
    y = vi("y", [1, 3])
    W = weights(rng, 4, 3)

    def gemm_model(**kwargs) -> onnx.ModelProto:
        base = dict(
            nodes=[helper.make_node("Gemm", ["x", "W"], ["y"])],
            inputs=[x], outputs=[y], inits=[init("W", W)],
        )
        base.update(kwargs)
        return make_model(**base)

    valid = serialize(gemm_model())

    fx.reject("reject_unknown_op_lstm", serialize(make_model(
        [helper.make_node("LSTM", ["x"], ["y"], hidden_size=3)], [x], [y])), "LSTM")
    fx.reject("reject_unknown_op_conv", serialize(make_model(
        [helper.make_node("Conv", ["x", "W"], ["y"])], [x], [y], [init("W", W)])), "Conv")
    external = helper.make_tensor("W", F, [4, 3], [0.0] * 12)
    external.ClearField("float_data")
    external.data_location = TensorProto.EXTERNAL
    entry = external.external_data.add()
    entry.key = "location"
    entry.value = "weights.bin"
    fx.reject("reject_external_data", serialize(gemm_model(inits=[external])), "external")
    sparse_model = gemm_model(inits=[init("W", W)])
    sparse = sparse_model.graph.sparse_initializer.add()
    sparse.values.CopyFrom(helper.make_tensor("S", F, [1], [1.0]))
    sparse.dims.append(4)
    fx.reject("reject_sparse_initializer", serialize(sparse_model), "sparse")
    fx.reject("reject_dim_mismatch", serialize(gemm_model(inits=[init("W", weights(rng, 5, 3))])), "shape")
    fx.reject("reject_truncated", valid[: int(len(valid) * 0.6)], "parse")
    fx.reject("reject_empty", b"", "empty")
    fx.reject("reject_random_bytes", bytes(rng.integers(0, 256, 300, dtype=np.uint8)), "parse")
    double = helper.make_tensor("W", TensorProto.DOUBLE, [4, 3], [0.5] * 12)
    fx.reject("reject_non_float32_weights", serialize(gemm_model(inits=[double])), "data type")
    graph_attr = helper.make_node("Identity", ["x"], ["y"])
    body = helper.make_graph([], "body", [], [])
    graph_attr.attribute.append(helper.make_attribute("body", body))
    fx.reject("reject_graph_attribute", serialize(make_model([graph_attr], [x], [vi("y", [1, 4])])), "graph")
    fx.reject("reject_missing_output", serialize(gemm_model(outputs=[vi("nope", [1, 3])])), "output")
    fx.reject("reject_cycle", serialize(make_model(
        [helper.make_node("Add", ["x", "b"], ["a"]), helper.make_node("Add", ["x", "a"], ["b"])],
        [x], [vi("b", [1, 4])])), "cycle")
    fx.reject("reject_unknown_input", serialize(make_model(
        [helper.make_node("Add", ["x", "ghost"], ["y"])], [x], [vi("y", [1, 4])])), "ghost")
    fx.reject("reject_opset_old", serialize(gemm_model_with_opset(11)), "opset")
    fx.reject("reject_opset_new", serialize(gemm_model_with_opset(21)), "opset")
    fx.reject("reject_unsupported_attribute", serialize(make_model(
        [helper.make_node("Gemm", ["x", "W"], ["y"], mystery=1)], [x], [y], [init("W", W)])), "mystery")
    fx.reject("reject_no_graph", b"\x08\x08", "graph")  # ir_version only


def gemm_model_with_opset(opset: int) -> onnx.ModelProto:
    rng = np.random.default_rng(5)
    return make_model(
        [helper.make_node("Gemm", ["x", "W"], ["y"])], [vi("x", [1, 4])], [vi("y", [1, 3])],
        [init("W", weights(rng, 4, 3))], opset=opset,
    )


# ------------------------------------------------------------------ main


def generate(out_dir: Path = OUT_DIR) -> list[str]:
    fx = Fixtures()
    build_ops(fx)
    build_mlps(fx)
    build_rejects(fx)
    out_dir.mkdir(parents=True, exist_ok=True)
    keep = set()
    for name, (data, payload) in fx.ok.items():
        (out_dir / f"{name}.onnx").write_bytes(data)
        write_json(out_dir / f"{name}.json", payload)
        keep |= {f"{name}.onnx", f"{name}.json"}
    for name, (data, reason) in fx.rejects.items():
        (out_dir / f"{name}.onnx").write_bytes(data)
        write_json(out_dir / f"{name}.json", {"reject": reason})
        keep |= {f"{name}.onnx", f"{name}.json"}
    write_json(out_dir / "manifest.json", {"ok": sorted(fx.ok), "reject": sorted(fx.rejects)})
    keep.add("manifest.json")
    for stale in out_dir.iterdir():
        if stale.name not in keep:
            stale.unlink()
    return sorted(keep)


def main() -> int:
    files = generate()
    print(f"wrote {len(files)} files to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
