"""Operator whitelist of the GDScript ONNX interpreter (mirror of design D6).

Anything outside this set is rejected by `game/ai/onnx/onnx_graph.gd`, so the
export and the fixture generator must stay inside it.
"""

from __future__ import annotations

import onnx

WHITELIST: frozenset[str] = frozenset(
    {
        "Gemm",
        "MatMul",
        "Add",
        "Mul",
        "Relu",
        "Tanh",
        "Sigmoid",
        "Clip",
        "Identity",
        "Flatten",
        "Reshape",
        "Squeeze",
        "Unsqueeze",
        "Concat",
        "Constant",
    }
)

OPSET_MIN = 13
OPSET_MAX = 18


def audit(model: onnx.ModelProto) -> list[str]:
    """Return human-readable problems; an empty list means the graph is loadable."""
    problems: list[str] = []
    for opset in model.opset_import:
        if opset.domain in ("", "ai.onnx") and not OPSET_MIN <= opset.version <= OPSET_MAX:
            problems.append(f"opset {opset.version} outside {OPSET_MIN}-{OPSET_MAX}")
    for node in model.graph.node:
        if node.op_type not in WHITELIST:
            problems.append(f"unsupported op {node.op_type} (node {node.name or '?'})")
        for attr in node.attribute:
            if attr.type in (onnx.AttributeProto.GRAPH, onnx.AttributeProto.GRAPHS):
                problems.append(f"graph attribute {attr.name} on node {node.name or node.op_type}")
    for init in model.graph.initializer:
        if init.data_location == onnx.TensorProto.EXTERNAL:
            problems.append(f"external data in initializer {init.name}")
        if init.data_type not in (onnx.TensorProto.FLOAT, onnx.TensorProto.INT64):
            problems.append(f"initializer {init.name} has unsupported data type {init.data_type}")
    return problems
