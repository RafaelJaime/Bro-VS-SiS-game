class_name OnnxGraph
extends RefCounted
## Compiles a ParsedModel into a flat plan and evaluates it (float32 tensors).
##
## Compile: Kahn topological sort (cycles and unknown inputs rejected), shape
## inference with the model input bound to [1, input_dim], constant folding of
## Constant nodes, and pre-transposition of constant Gemm/MatMul weights to
## row-major [N][K]. Run: walks the plan; no graph structures are allocated per call.
##
## Whitelist (15 ops): Gemm (alpha, beta, transA, transB, C as scalar / [N] /
## [1,N] / [M,1] / [M,N]), MatMul (2-D), Add and Mul (same shape, a trailing
## vector or a scalar), Relu, Tanh, Sigmoid, Clip (constant min/max inputs),
## Identity, Flatten (axis), Reshape (constant shape; 0 and -1 allowed),
## Squeeze, Unsqueeze (constant axes), Concat (axis), Constant (value, value_float,
## value_floats, value_int, value_ints). Any other op, op domain or attribute is an
## error naming it. Limits: 250k multiply-adds per inference (`max_macs`).

const DEFAULT_MAX_MACS := 250000
const WHITELIST: PackedStringArray = [
	"Gemm", "MatMul", "Add", "Mul", "Relu", "Tanh", "Sigmoid", "Clip", "Identity",
	"Flatten", "Reshape", "Squeeze", "Unsqueeze", "Concat", "Constant",
]
const ALLOWED_ATTRS := {
	"Gemm": ["alpha", "beta", "transA", "transB"],
	"MatMul": [], "Add": [], "Mul": [], "Relu": [], "Tanh": [], "Sigmoid": [], "Clip": [],
	"Identity": [], "Flatten": ["axis"], "Reshape": ["allowzero"], "Squeeze": [],
	"Unsqueeze": [], "Concat": ["axis"],
	"Constant": ["value", "value_float", "value_floats", "value_int", "value_ints"],
}

class Step extends RefCounted:
	var op: String = ""
	var label: String = ""
	## Input slots; -1 marks an omitted optional input.
	var ins: PackedInt32Array = PackedInt32Array()
	var out: int = -1
	var out_shape: PackedInt32Array = PackedInt32Array()
	var alpha: float = 1.0
	var beta: float = 1.0
	var trans_a: bool = false
	var m: int = 0
	var n: int = 0
	var k: int = 0
	## Gemm/MatMul weights as row-major [N][K]; empty when B is not constant.
	var weights: PackedFloat32Array = PackedFloat32Array()
	var b_trans: bool = false
	var c_mode: int = 0
	var lo: float = 0.0
	var hi: float = 0.0
	var axis: int = 0

const C_NONE := 0
const C_SCALAR := 1
const C_ROW := 2
const C_COLUMN := 3
const C_FULL := 4

var error: String = ""
var input_name: String = ""
var input_dim: int = 0
## Extra graph inputs (godot_rl style `state_ins`): name -> shape, fed zeros.
var extra_inputs: Dictionary = {}
var output_names: PackedStringArray = PackedStringArray()
var output_shapes: Array[PackedInt32Array] = []
var macs: int = 0

var _steps: Array[Step] = []
var _values: Array = []
var _slot_count: int = 0
var _input_slot: int = -1
var _extra_slots: Dictionary = {}
var _output_slots: PackedInt32Array = PackedInt32Array()
var _shapes: Array = []
var _slots: Dictionary = {}
var _max_macs: int = DEFAULT_MAX_MACS

static func compile(model: OnnxModelParser.ParsedModel, limits: Dictionary = {}) -> OnnxGraph:
	var graph := OnnxGraph.new()
	graph._max_macs = int(limits.get("max_macs", DEFAULT_MAX_MACS))
	graph._compile(model)
	return graph

func ok() -> bool:
	return error == ""

func _fail(message: String) -> void:
	if error == "":
		error = message

func _new_slot(value_name: String, shape: PackedInt32Array, value: Variant = null) -> int:
	var slot := _slot_count
	_slot_count += 1
	_slots[value_name] = slot
	_shapes.append(shape)
	_values.append(value)
	return slot

# ------------------------------------------------------------------ compile

func _compile(model: OnnxModelParser.ParsedModel) -> void:
	if not model.ok():
		_fail(model.error)
		return
	_bind_inputs(model)
	if error != "":
		return
	var produced: Dictionary = {}
	for i in model.nodes.size():
		var node: OnnxModelParser.NodeDef = model.nodes[i]
		_check_node(node)
		if error != "":
			return
		for out_name in node.outputs:
			if out_name == "":
				continue
			if produced.has(out_name) or _slots.has(out_name):
				_fail("tensor '%s' is produced twice (node %s)" % [out_name, node.label()])
				return
			produced[out_name] = i
	var order := _topological_order(model, produced)
	if error != "":
		return
	for index in order:
		_compile_node(model.nodes[index])
		if error != "":
			return
	if model.outputs.is_empty():
		_fail("the graph has no outputs")
		return
	for info in model.outputs:
		if not _slots.has(info.name):
			_fail("graph output '%s' is never produced" % info.name)
			return
		output_names.append(info.name)
		_output_slots.append(_slots[info.name])
		output_shapes.append(_shapes[_slots[info.name]])
	if macs > _max_macs:
		_fail("model needs %d multiply-adds per inference (limit %d)" % [macs, _max_macs])

func _bind_inputs(model: OnnxModelParser.ParsedModel) -> void:
	for init_name in model.initializers:
		var tensor: OnnxTensor = model.initializers[init_name]
		_new_slot(init_name, tensor.shape, tensor)
	# Older exporters list initializers as graph inputs too; those are not real inputs.
	var real: Array[OnnxModelParser.ValueInfo] = []
	for info in model.inputs:
		if not model.initializers.has(info.name):
			real.append(info)
	if real.is_empty():
		_fail("the graph has no input")
		return
	var primary: OnnxModelParser.ValueInfo = real[0]
	if primary.elem_type != OnnxTensor.FLOAT:
		_fail("input '%s' must be float32" % primary.name)
		return
	if not primary.has_shape or primary.dims.size() != 2:
		_fail("input '%s' must have shape [1, N]" % primary.name)
		return
	if primary.dims[0] != 1 and primary.dims[0] != -1:
		_fail("input '%s' must have batch size 1 or a dynamic batch, not %d" % [primary.name, primary.dims[0]])
		return
	if primary.dims[1] < 1:
		_fail("input '%s' must have a fixed width" % primary.name)
		return
	input_name = primary.name
	input_dim = primary.dims[1]
	_input_slot = _new_slot(primary.name, PackedInt32Array([1, input_dim]))
	for i in range(1, real.size()):
		var info: OnnxModelParser.ValueInfo = real[i]
		var shape := PackedInt32Array()
		for d in info.dims:
			shape.append(1 if d < 0 else d)
		if info.elem_type != OnnxTensor.FLOAT or OnnxTensor.count_of(shape) < 0:
			_fail("extra input '%s' must be a small float32 tensor" % info.name)
			return
		extra_inputs[info.name] = shape
		_extra_slots[info.name] = _new_slot(info.name, shape, OnnxTensor.zeros(shape))

func _check_node(node: OnnxModelParser.NodeDef) -> void:
	if node.domain != "" and node.domain != "ai.onnx":
		_fail("unsupported operator domain '%s' (node %s)" % [node.domain, node.label()])
		return
	if not WHITELIST.has(node.op):
		_fail("unsupported operator %s (node %s)" % [node.op, node.label()])
		return
	for attr_name in node.attrs:
		if not (ALLOWED_ATTRS[node.op] as Array).has(attr_name):
			_fail("unsupported attribute '%s' on %s node %s" % [attr_name, node.op, node.label()])
			return
	if node.outputs.size() != 1:
		_fail("%s node %s must have exactly one output" % [node.op, node.label()])

func _topological_order(model: OnnxModelParser.ParsedModel, produced: Dictionary) -> PackedInt32Array:
	var count := model.nodes.size()
	var pending := PackedInt32Array()
	pending.resize(count)
	var consumers: Array = []
	consumers.resize(count)
	for i in count:
		consumers[i] = PackedInt32Array()
	for i in count:
		var node: OnnxModelParser.NodeDef = model.nodes[i]
		var seen: Dictionary = {}
		for input_name_ in node.inputs:
			if input_name_ == "" or seen.has(input_name_):
				continue
			seen[input_name_] = true
			if produced.has(input_name_):
				pending[i] += 1
				var list: PackedInt32Array = consumers[produced[input_name_]]
				list.append(i)
				consumers[produced[input_name_]] = list
			elif not _slots.has(input_name_):
				_fail("node %s reads unknown tensor '%s'" % [node.label(), input_name_])
				return PackedInt32Array()
	var ready: Array[int] = []
	for i in count:
		if pending[i] == 0:
			ready.append(i)
	var order := PackedInt32Array()
	while not ready.is_empty():
		var current: int = ready.pop_front()
		order.append(current)
		for c in (consumers[current] as PackedInt32Array):
			pending[c] -= 1
			if pending[c] == 0:
				ready.append(c)
	if order.size() != count:
		for i in count:
			if pending[i] > 0:
				_fail("the graph has a cycle (node %s)" % model.nodes[i].label())
				break
		return PackedInt32Array()
	return order

func _shape_fail(step: Step, detail: String) -> void:
	_fail("shape mismatch at %s %s: %s" % [step.op, step.label, detail])

func _const(slot: int) -> OnnxTensor:
	return _values[slot] as OnnxTensor if slot >= 0 else null

func _attr_int(node: OnnxModelParser.NodeDef, attr_name: String, default_value: int) -> int:
	var v: Variant = node.attrs.get(attr_name, default_value)
	return int(v) if typeof(v) == TYPE_INT else default_value

func _attr_float(node: OnnxModelParser.NodeDef, attr_name: String, default_value: float) -> float:
	var v: Variant = node.attrs.get(attr_name, default_value)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else default_value

func _compile_node(node: OnnxModelParser.NodeDef) -> void:
	if node.op == "Constant":
		_compile_constant(node)
		return
	var step := Step.new()
	step.op = node.op
	step.label = node.label()
	for in_name in node.inputs:
		step.ins.append(-1 if in_name == "" else int(_slots[in_name]))
	for i in step.ins.size():
		var is_index_input := i == 1 and (node.op == "Reshape" or node.op == "Squeeze" or node.op == "Unsqueeze")
		var constant := _const(step.ins[i])
		if constant != null and constant.dtype != OnnxTensor.FLOAT and not is_index_input:
			_fail("%s node %s reads an int64 tensor as data" % [node.op, step.label])
			return
	var in_shapes: Array = []
	for slot in step.ins:
		in_shapes.append(_shapes[slot] if slot >= 0 else null)
	var out_shape := PackedInt32Array()
	match node.op:
		"Gemm":
			out_shape = _infer_gemm(step, node, in_shapes)
		"MatMul":
			out_shape = _infer_matmul(step, in_shapes)
		"Add", "Mul":
			if step.ins.size() != 2 or step.ins.has(-1):
				_shape_fail(step, "needs two inputs")
				return
			var broadcast: Variant = _broadcast(in_shapes[0], in_shapes[1])
			if broadcast == null:
				_shape_fail(step, "cannot broadcast %s with %s" % [str(Array(in_shapes[0])), str(Array(in_shapes[1]))])
				return
			out_shape = broadcast
		"Relu", "Tanh", "Sigmoid", "Identity":
			if step.ins.size() != 1 or step.ins[0] < 0:
				_shape_fail(step, "needs one input")
				return
			out_shape = in_shapes[0]
		"Clip":
			out_shape = _infer_clip(step, in_shapes)
		"Flatten":
			out_shape = _infer_flatten(step, node, in_shapes)
		"Reshape":
			out_shape = _infer_reshape(step, node, in_shapes)
		"Squeeze":
			out_shape = _infer_squeeze(step, in_shapes)
		"Unsqueeze":
			out_shape = _infer_unsqueeze(step, in_shapes)
		"Concat":
			out_shape = _infer_concat(step, node, in_shapes)
	if error != "":
		return
	if OnnxTensor.count_of(out_shape) < 0:
		_shape_fail(step, "output %s is too large" % str(Array(out_shape)))
		return
	step.out_shape = out_shape
	step.out = _new_slot(node.outputs[0], out_shape)
	_steps.append(step)

func _compile_constant(node: OnnxModelParser.NodeDef) -> void:
	var tensor: OnnxTensor = null
	if node.attrs.has("value") and node.attrs["value"] is OnnxTensor:
		tensor = node.attrs["value"]
	elif node.attrs.has("value_float"):
		tensor = OnnxTensor.float_tensor(PackedInt32Array(), PackedFloat32Array([float(node.attrs["value_float"])]))
	elif node.attrs.has("value_floats") and node.attrs["value_floats"] is PackedFloat32Array:
		var floats: PackedFloat32Array = node.attrs["value_floats"]
		tensor = OnnxTensor.float_tensor(PackedInt32Array([floats.size()]), floats)
	elif node.attrs.has("value_int"):
		tensor = OnnxTensor.new()
		tensor.dtype = OnnxTensor.INT64
		tensor.ints = PackedInt64Array([int(node.attrs["value_int"])])
	elif node.attrs.has("value_ints") and node.attrs["value_ints"] is PackedInt64Array:
		tensor = OnnxTensor.new()
		tensor.dtype = OnnxTensor.INT64
		tensor.ints = node.attrs["value_ints"]
		tensor.shape = PackedInt32Array([tensor.ints.size()])
	if tensor == null:
		_fail("Constant node %s has no usable value attribute" % node.label())
		return
	_new_slot(node.outputs[0], tensor.shape, tensor)

# ---- shape inference per op

func _infer_gemm(step: Step, node: OnnxModelParser.NodeDef, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() < 2 or step.ins.size() > 3 or step.ins[0] < 0 or step.ins[1] < 0:
		_shape_fail(step, "needs inputs A, B and an optional C")
		return PackedInt32Array()
	var a: PackedInt32Array = in_shapes[0]
	var b: PackedInt32Array = in_shapes[1]
	if a.size() != 2 or b.size() != 2:
		_shape_fail(step, "A and B must be 2-D, got %s and %s" % [str(Array(a)), str(Array(b))])
		return PackedInt32Array()
	step.alpha = _attr_float(node, "alpha", 1.0)
	step.beta = _attr_float(node, "beta", 1.0)
	step.trans_a = _attr_int(node, "transA", 0) != 0
	step.b_trans = _attr_int(node, "transB", 0) != 0
	step.m = a[1] if step.trans_a else a[0]
	step.k = a[0] if step.trans_a else a[1]
	var kb := b[1] if step.b_trans else b[0]
	step.n = b[0] if step.b_trans else b[1]
	if step.k != kb:
		_shape_fail(step, "A has K=%d but B has K=%d" % [step.k, kb])
		return PackedInt32Array()
	if step.ins.size() == 3 and step.ins[2] >= 0:
		var c: PackedInt32Array = in_shapes[2]
		step.c_mode = _c_mode(c, step.m, step.n)
		if step.c_mode < 0:
			_shape_fail(step, "C %s cannot broadcast to [%d, %d]" % [str(Array(c)), step.m, step.n])
			return PackedInt32Array()
	else:
		step.c_mode = C_NONE
	_prepare_weights(step, b, step.b_trans)
	macs += step.m * step.n * step.k
	return PackedInt32Array([step.m, step.n])

func _c_mode(c: PackedInt32Array, m: int, n: int) -> int:
	var total := OnnxTensor.count_of(c)
	if c.size() > 2:
		return -1
	if total == 1:
		return C_SCALAR
	if c.size() == 1 and c[0] == n:
		return C_ROW
	if c.size() == 2 and c[0] == 1 and c[1] == n:
		return C_ROW
	if c.size() == 2 and c[0] == m and c[1] == 1:
		return C_COLUMN
	if c.size() == 2 and c[0] == m and c[1] == n:
		return C_FULL
	return -1

## Stores constant B as row-major [N][K] (what the inner loop wants).
func _prepare_weights(step: Step, b_shape: PackedInt32Array, transposed_in_file: bool) -> void:
	var b_const := _const(step.ins[1])
	if b_const == null:
		return
	if transposed_in_file:
		step.weights = b_const.data
		return
	var w := PackedFloat32Array()
	w.resize(step.n * step.k)
	var rows := b_shape[0]
	var cols := b_shape[1]
	for r in rows:
		for c in cols:
			w[c * rows + r] = b_const.data[r * cols + c]
	step.weights = w

func _infer_matmul(step: Step, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() != 2 or step.ins.has(-1):
		_shape_fail(step, "needs two inputs")
		return PackedInt32Array()
	var a: PackedInt32Array = in_shapes[0]
	var b: PackedInt32Array = in_shapes[1]
	if a.size() != 2 or b.size() != 2:
		_shape_fail(step, "only 2-D operands are supported, got %s and %s" % [str(Array(a)), str(Array(b))])
		return PackedInt32Array()
	if a[1] != b[0]:
		_shape_fail(step, "inner dimensions differ (%d vs %d)" % [a[1], b[0]])
		return PackedInt32Array()
	step.m = a[0]
	step.k = a[1]
	step.n = b[1]
	step.c_mode = C_NONE
	_prepare_weights(step, b, false)
	macs += step.m * step.n * step.k
	return PackedInt32Array([step.m, step.n])

## Elementwise broadcasting: same shape, a scalar-like operand, or a trailing-dims
## operand. Returns the output shape or null.
func _broadcast(a: PackedInt32Array, b: PackedInt32Array) -> Variant:
	if a == b:
		return a
	var hi := a
	var lo := b
	if b.size() > a.size() or (b.size() == a.size() and OnnxTensor.count_of(b) > OnnxTensor.count_of(a)):
		hi = b
		lo = a
	if OnnxTensor.count_of(lo) == 1 and lo.size() <= hi.size():
		return hi
	if lo.size() < hi.size():
		var offset := hi.size() - lo.size()
		for i in lo.size():
			if lo[i] != hi[offset + i]:
				return null
		return hi
	return null

func _infer_clip(step: Step, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() < 1 or step.ins.size() > 3 or step.ins[0] < 0:
		_shape_fail(step, "needs an input and optional min and max")
		return PackedInt32Array()
	step.lo = -INF
	step.hi = INF
	for i in range(1, step.ins.size()):
		if step.ins[i] < 0:
			continue
		var bound := _const(step.ins[i])
		if bound == null or bound.dtype != OnnxTensor.FLOAT or bound.data.size() != 1:
			_fail("Clip %s needs constant scalar float bounds" % step.label)
			return PackedInt32Array()
		if i == 1:
			step.lo = bound.data[0]
		else:
			step.hi = bound.data[0]
	return in_shapes[0]

func _infer_flatten(step: Step, node: OnnxModelParser.NodeDef, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() != 1 or step.ins[0] < 0:
		_shape_fail(step, "needs one input")
		return PackedInt32Array()
	var s: PackedInt32Array = in_shapes[0]
	var axis := _attr_int(node, "axis", 1)
	if axis < 0:
		axis += s.size()
	if axis < 0 or axis > s.size():
		_shape_fail(step, "axis %d is out of range for rank %d" % [_attr_int(node, "axis", 1), s.size()])
		return PackedInt32Array()
	var outer := 1
	var inner := 1
	for i in s.size():
		if i < axis:
			outer *= s[i]
		else:
			inner *= s[i]
	return PackedInt32Array([outer, inner])

func _infer_reshape(step: Step, node: OnnxModelParser.NodeDef, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() != 2 or step.ins.has(-1):
		_shape_fail(step, "needs data and shape inputs")
		return PackedInt32Array()
	if _attr_int(node, "allowzero", 0) != 0:
		_fail("unsupported attribute 'allowzero' on Reshape node %s" % step.label)
		return PackedInt32Array()
	var target := _const(step.ins[1])
	if target == null or target.dtype != OnnxTensor.INT64:
		_fail("Reshape %s needs a constant int64 shape" % step.label)
		return PackedInt32Array()
	var s: PackedInt32Array = in_shapes[0]
	var total := OnnxTensor.count_of(s)
	var out := PackedInt32Array()
	var known := 1
	var infer_at := -1
	for i in target.ints.size():
		var d := int(target.ints[i])
		if d == 0:
			if i >= s.size():
				_shape_fail(step, "shape entry %d copies a missing input dimension" % i)
				return PackedInt32Array()
			d = s[i]
		elif d == -1:
			if infer_at >= 0:
				_shape_fail(step, "more than one -1 in the target shape")
				return PackedInt32Array()
			infer_at = i
			d = 1
		elif d < 0:
			_shape_fail(step, "negative target dimension %d" % d)
			return PackedInt32Array()
		out.append(d)
		known *= d
		if known > OnnxTensor.MAX_ELEMENTS:
			_shape_fail(step, "target shape is too large")
			return PackedInt32Array()
	if infer_at >= 0:
		if known == 0 or total % known != 0:
			_shape_fail(step, "cannot infer the -1 dimension (%d elements into %d)" % [total, known])
			return PackedInt32Array()
		out[infer_at] = total / known
		known *= out[infer_at]
	if known != total:
		_shape_fail(step, "%d input elements do not fit the target shape" % total)
		return PackedInt32Array()
	return out

func _const_axes(step: Step, slot_index: int) -> Variant:
	if step.ins.size() <= slot_index or step.ins[slot_index] < 0:
		return null
	var axes := _const(step.ins[slot_index])
	if axes == null or axes.dtype != OnnxTensor.INT64:
		_fail("%s %s needs constant int64 axes" % [step.op, step.label])
		return null
	return axes.ints

func _infer_squeeze(step: Step, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() < 1 or step.ins.size() > 2 or step.ins[0] < 0:
		_shape_fail(step, "needs data and optional axes")
		return PackedInt32Array()
	var s: PackedInt32Array = in_shapes[0]
	var axes: Variant = _const_axes(step, 1)
	if error != "":
		return PackedInt32Array()
	var drop: Dictionary = {}
	if axes == null:
		for i in s.size():
			if s[i] == 1:
				drop[i] = true
	else:
		for raw_axis in (axes as PackedInt64Array):
			var axis := int(raw_axis)
			if axis < 0:
				axis += s.size()
			if axis < 0 or axis >= s.size() or s[axis] != 1:
				_shape_fail(step, "cannot squeeze axis %d of %s" % [int(raw_axis), str(Array(s))])
				return PackedInt32Array()
			drop[axis] = true
	var out := PackedInt32Array()
	for i in s.size():
		if not drop.has(i):
			out.append(s[i])
	return out

func _infer_unsqueeze(step: Step, in_shapes: Array) -> PackedInt32Array:
	if step.ins.size() != 2 or step.ins.has(-1):
		_shape_fail(step, "needs data and axes")
		return PackedInt32Array()
	var s: PackedInt32Array = in_shapes[0]
	var axes: Variant = _const_axes(step, 1)
	if error != "" or axes == null:
		return PackedInt32Array()
	var rank := s.size() + (axes as PackedInt64Array).size()
	var inserted: Dictionary = {}
	for raw_axis in (axes as PackedInt64Array):
		var axis := int(raw_axis)
		if axis < 0:
			axis += rank
		if axis < 0 or axis >= rank or inserted.has(axis):
			_shape_fail(step, "invalid axis %d for output rank %d" % [int(raw_axis), rank])
			return PackedInt32Array()
		inserted[axis] = true
	var out := PackedInt32Array()
	var source := 0
	for i in rank:
		if inserted.has(i):
			out.append(1)
		else:
			out.append(s[source])
			source += 1
	return out

func _infer_concat(step: Step, node: OnnxModelParser.NodeDef, in_shapes: Array) -> PackedInt32Array:
	if step.ins.is_empty() or step.ins.has(-1):
		_shape_fail(step, "needs at least one input")
		return PackedInt32Array()
	if not node.attrs.has("axis"):
		_fail("Concat node %s needs an axis attribute" % step.label)
		return PackedInt32Array()
	var first: PackedInt32Array = in_shapes[0]
	var axis := _attr_int(node, "axis", 0)
	if axis < 0:
		axis += first.size()
	if axis < 0 or axis >= first.size():
		_shape_fail(step, "axis %d is out of range for rank %d" % [_attr_int(node, "axis", 0), first.size()])
		return PackedInt32Array()
	step.axis = axis
	var out := first.duplicate()
	out[axis] = 0
	for shape_variant in in_shapes:
		var s: PackedInt32Array = shape_variant
		if s.size() != first.size():
			_shape_fail(step, "inputs have different ranks")
			return PackedInt32Array()
		for i in s.size():
			if i != axis and s[i] != first[i]:
				_shape_fail(step, "dimension %d differs (%d vs %d)" % [i, s[i], first[i]])
				return PackedInt32Array()
		out[axis] += s[axis]
	return out

# ------------------------------------------------------------------ run

## Runs the plan. `obs` must have `input_dim` elements (the caller checks and
## reports the mismatch). Returns the first model output.
func run(obs: PackedFloat32Array) -> OnnxTensor:
	_values[_input_slot] = OnnxTensor.float_tensor(PackedInt32Array([1, input_dim]), obs)
	for step in _steps:
		_values[step.out] = _eval(step)
	return _values[_output_slots[0]]

## Same as run() but returns every model output, in graph order.
func run_all(obs: PackedFloat32Array) -> Array[OnnxTensor]:
	run(obs)
	var outputs: Array[OnnxTensor] = []
	for slot in _output_slots:
		outputs.append(_values[slot])
	return outputs

func _eval(step: Step) -> OnnxTensor:
	match step.op:
		"Gemm", "MatMul":
			return _eval_gemm(step)
		"Add":
			return _eval_binary(step, true)
		"Mul":
			return _eval_binary(step, false)
		"Relu":
			return _eval_unary(step, 0)
		"Tanh":
			return _eval_unary(step, 1)
		"Sigmoid":
			return _eval_unary(step, 2)
		"Clip":
			return _eval_clip(step)
		"Concat":
			return _eval_concat(step)
		_:
			# Identity, Flatten, Reshape, Squeeze, Unsqueeze keep the data untouched.
			return OnnxTensor.float_tensor(step.out_shape, (_values[step.ins[0]] as OnnxTensor).data)

func _eval_gemm(step: Step) -> OnnxTensor:
	var a: PackedFloat32Array = (_values[step.ins[0]] as OnnxTensor).data
	var w: PackedFloat32Array = step.weights
	if w.is_empty() and step.n * step.k > 0:
		w = _transpose_dynamic(step)
	var m := step.m
	var n := step.n
	var k := step.k
	var out := PackedFloat32Array()
	out.resize(m * n)
	var c := PackedFloat32Array()
	if step.c_mode != C_NONE:
		c = (_values[step.ins[2]] as OnnxTensor).data
	var alpha := step.alpha
	var beta := step.beta
	var k4 := k - (k % 4)
	for i in m:
		for j in n:
			var acc := 0.0
			var wo := j * k
			if step.trans_a:
				for t in k:
					acc += a[t * m + i] * w[wo + t]
			else:
				var ao := i * k
				var t := 0
				while t < k4:
					acc += a[ao + t] * w[wo + t] + a[ao + t + 1] * w[wo + t + 1] + a[ao + t + 2] * w[wo + t + 2] + a[ao + t + 3] * w[wo + t + 3]
					t += 4
				while t < k:
					acc += a[ao + t] * w[wo + t]
					t += 1
			var value := alpha * acc if alpha != 1.0 else acc
			match step.c_mode:
				C_SCALAR:
					value += beta * c[0]
				C_ROW:
					value += beta * c[j]
				C_COLUMN:
					value += beta * c[i]
				C_FULL:
					value += beta * c[i * n + j]
			out[i * n + j] = value
	return OnnxTensor.float_tensor(step.out_shape, out)

## B was not constant: transpose it for this call.
func _transpose_dynamic(step: Step) -> PackedFloat32Array:
	var b: OnnxTensor = _values[step.ins[1]]
	var w := PackedFloat32Array()
	w.resize(step.n * step.k)
	if step.b_trans:
		return b.data
	var rows := b.shape[0]
	var cols := b.shape[1]
	for r in rows:
		for c in cols:
			w[c * rows + r] = b.data[r * cols + c]
	return w

func _eval_binary(step: Step, is_add: bool) -> OnnxTensor:
	var a: PackedFloat32Array = (_values[step.ins[0]] as OnnxTensor).data
	var b: PackedFloat32Array = (_values[step.ins[1]] as OnnxTensor).data
	var total := OnnxTensor.count_of(step.out_shape)
	var out := PackedFloat32Array()
	out.resize(total)
	var na := a.size()
	var nb := b.size()
	for i in total:
		var x := a[i % na] if na != total else a[i]
		var y := b[i % nb] if nb != total else b[i]
		out[i] = x + y if is_add else x * y
	return OnnxTensor.float_tensor(step.out_shape, out)

func _eval_unary(step: Step, kind: int) -> OnnxTensor:
	var src: PackedFloat32Array = (_values[step.ins[0]] as OnnxTensor).data
	var out := PackedFloat32Array()
	out.resize(src.size())
	for i in src.size():
		var x := src[i]
		match kind:
			0:
				out[i] = x if x > 0.0 else 0.0
			1:
				out[i] = tanh(x)
			_:
				out[i] = 1.0 / (1.0 + exp(-x))
	return OnnxTensor.float_tensor(step.out_shape, out)

func _eval_clip(step: Step) -> OnnxTensor:
	var src: PackedFloat32Array = (_values[step.ins[0]] as OnnxTensor).data
	var out := PackedFloat32Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = minf(maxf(src[i], step.lo), step.hi)
	return OnnxTensor.float_tensor(step.out_shape, out)

func _eval_concat(step: Step) -> OnnxTensor:
	var first: OnnxTensor = _values[step.ins[0]]
	var outer := 1
	for i in step.axis:
		outer *= first.shape[i]
	var out := PackedFloat32Array()
	for o in outer:
		for slot in step.ins:
			var t: OnnxTensor = _values[slot]
			var chunk := t.data.size() / outer
			out.append_array(t.data.slice(o * chunk, (o + 1) * chunk))
	return OnnxTensor.float_tensor(step.out_shape, out)
