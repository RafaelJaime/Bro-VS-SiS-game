class_name OnnxModelParser
extends RefCounted
## Parses an ONNX ModelProto (untrusted bytes) into plain data, GDScript only.
##
## Fields read (numbers from onnx.proto), everything else is skipped:
##   ModelProto      ir_version=1, graph=7, opset_import=8 (domain=1, version=2)
##   GraphProto      node=1, initializer=5, input=11, output=12  (sparse_initializer=15 rejected)
##   NodeProto       input=1, output=2, name=3, op_type=4, attribute=5, domain=7
##   AttributeProto  name=1, f=2, i=3, s=4, t=5, floats=7, ints=8, type=20
##                   (graph-valued g=6 / graphs=11 and sparse_tensor=22 rejected)
##   TensorProto     dims=1, data_type=2, float_data=4, int64_data=7, name=8, raw_data=9
##                   (external_data=13 / data_location=14 rejected; FLOAT and INT64 only)
##   ValueInfoProto  name=1, type=2 -> tensor_type=1 -> elem_type=1, shape=2 -> dim=1
##                   -> dim_value=1 | dim_param=2
## Default operator domain only ("" or "ai.onnx"), opset 13..18.
## Limits (overridable for tests through `limits`): file 16 MiB, 512 nodes,
## 512 initializers, 4M elements per tensor. Failures return a ParsedModel whose
## `error` is a human-readable reason; nothing is thrown.

const MIN_OPSET := 13
const MAX_OPSET := 18
const DEFAULT_LIMITS := {
	"max_bytes": 16777216,
	"max_nodes": 512,
	"max_initializers": 512,
	"max_tensor_elements": 4194304,
}

class NodeDef extends RefCounted:
	var name: String = ""
	var op: String = ""
	var domain: String = ""
	var inputs: PackedStringArray = PackedStringArray()
	var outputs: PackedStringArray = PackedStringArray()
	## Attribute name -> float | int | String | OnnxTensor | PackedFloat32Array | PackedInt64Array.
	var attrs: Dictionary = {}

	func label() -> String:
		return name if name != "" else "%s(%s)" % [op, ",".join(outputs)]

class ValueInfo extends RefCounted:
	var name: String = ""
	var elem_type: int = 0
	var has_shape: bool = false
	## Dimension sizes; -1 for a dynamic or unknown dimension.
	var dims: PackedInt32Array = PackedInt32Array()

class ParsedModel extends RefCounted:
	var error: String = ""
	var opset: int = 0
	var nodes: Array[NodeDef] = []
	var initializers: Dictionary = {}
	var inputs: Array[ValueInfo] = []
	var outputs: Array[ValueInfo] = []

	func ok() -> bool:
		return error == ""

var _limits: Dictionary
var _err: String = ""

static func parse(bytes: PackedByteArray, limits: Dictionary = {}) -> ParsedModel:
	return OnnxModelParser.new(limits)._run(bytes)

func _init(limits: Dictionary = {}) -> void:
	_limits = DEFAULT_LIMITS.duplicate()
	_limits.merge(limits, true)

func _fail(message: String) -> void:
	if _err == "":
		_err = message

## Pulls a reader failure into the parser state; true while parsing may continue.
func _alive(r: PbReader) -> bool:
	if r.error != "":
		_fail(r.error)
	return _err == ""

func _run(bytes: PackedByteArray) -> ParsedModel:
	var model := ParsedModel.new()
	if bytes.is_empty():
		model.error = "parse error: empty file"
		return model
	if bytes.size() > int(_limits.max_bytes):
		model.error = "model file is too large (%d bytes, limit %d)" % [bytes.size(), int(_limits.max_bytes)]
		return model
	var r := PbReader.new(bytes)
	var graph_window := Vector2i(-1, -1)
	var opsets: Dictionary = {}
	while _alive(r) and r.read_tag():
		if r.field == 7 and r.wire == PbReader.WIRE_LEN:
			graph_window = r.read_len_window()
		elif r.field == 8 and r.wire == PbReader.WIRE_LEN:
			_read_opset(r.read_sub_reader(), opsets)
		else:
			r.skip_value()
	_alive(r)
	if _err == "" and graph_window.x < 0:
		_fail("parse error: model has no graph")
	if _err == "":
		if not opsets.has("") and not opsets.has("ai.onnx"):
			_fail("parse error: model has no opset import for the default domain")
		else:
			model.opset = int(opsets.get("", opsets.get("ai.onnx", 0)))
			if model.opset < MIN_OPSET or model.opset > MAX_OPSET:
				_fail("opset %d is not supported (need %d to %d)" % [model.opset, MIN_OPSET, MAX_OPSET])
	if _err == "":
		_read_graph(PbReader.new(bytes, graph_window.x, graph_window.y), model)
	model.error = _err
	return model

func _read_opset(r: PbReader, opsets: Dictionary) -> void:
	var domain := ""
	var version := 0
	while _alive(r) and r.read_tag():
		if r.field == 1 and r.wire == PbReader.WIRE_LEN:
			domain = r.read_string()
		elif r.field == 2 and r.wire == PbReader.WIRE_VARINT:
			version = r.read_varint()
		else:
			r.skip_value()
	_alive(r)
	opsets[domain] = version

func _read_graph(r: PbReader, model: ParsedModel) -> void:
	while _alive(r) and r.read_tag():
		if r.wire != PbReader.WIRE_LEN:
			r.skip_value()
			continue
		match r.field:
			1:
				if model.nodes.size() >= int(_limits.max_nodes):
					_fail("model has more than %d nodes" % int(_limits.max_nodes))
					return
				model.nodes.append(_read_node(r.read_sub_reader()))
			5:
				if model.initializers.size() >= int(_limits.max_initializers):
					_fail("model has more than %d initializers" % int(_limits.max_initializers))
					return
				var tensor_name := ""
				var tensor := _read_tensor(r.read_sub_reader())
				if tensor != null:
					tensor_name = tensor.get_meta("name", "")
					model.initializers[tensor_name] = tensor
			11:
				model.inputs.append(_read_value_info(r.read_sub_reader()))
			12:
				model.outputs.append(_read_value_info(r.read_sub_reader()))
			15:
				_fail("sparse initializers are not supported")
				return
			_:
				r.skip_value()
	_alive(r)

func _read_node(r: PbReader) -> NodeDef:
	var node := NodeDef.new()
	while _alive(r) and r.read_tag():
		if r.wire != PbReader.WIRE_LEN:
			r.skip_value()
			continue
		match r.field:
			1:
				node.inputs.append(r.read_string())
			2:
				node.outputs.append(r.read_string())
			3:
				node.name = r.read_string()
			4:
				node.op = r.read_string()
			5:
				_read_attribute(r.read_sub_reader(), node)
			7:
				node.domain = r.read_string()
			_:
				r.skip_value()
	_alive(r)
	return node

func _read_attribute(r: PbReader, node: NodeDef) -> void:
	var attr_name := ""
	var value: Variant = null
	var attr_type := 0
	var floats := PackedFloat32Array()
	var ints := PackedInt64Array()
	while _alive(r) and r.read_tag():
		match r.field:
			1:
				if r.wire == PbReader.WIRE_LEN:
					attr_name = r.read_string()
				else:
					r.skip_value()
			2:
				if r.wire == PbReader.WIRE_FIXED32:
					value = r.read_float()
				else:
					r.skip_value()
			3:
				if r.wire == PbReader.WIRE_VARINT:
					value = r.read_varint()
				else:
					r.skip_value()
			4:
				if r.wire == PbReader.WIRE_LEN:
					value = r.read_string()
				else:
					r.skip_value()
			5:
				if r.wire == PbReader.WIRE_LEN:
					value = _read_tensor(r.read_sub_reader())
				else:
					r.skip_value()
			6, 11:
				_fail("graph-valued attribute '%s' on node %s is not supported" % [attr_name, node.label()])
				return
			22:
				_fail("sparse tensor attribute '%s' on node %s is not supported" % [attr_name, node.label()])
				return
			7:
				if r.wire == PbReader.WIRE_LEN:
					var window := r.read_len_window()
					if (window.y - window.x) % 4 != 0:
						_fail("attribute '%s' has a float list of %d bytes" % [attr_name, window.y - window.x])
						return
					floats.append_array(r.buf.slice(window.x, window.y).to_float32_array())
				elif r.wire == PbReader.WIRE_FIXED32:
					floats.append(r.read_float())
				else:
					r.skip_value()
			8:
				if r.wire == PbReader.WIRE_LEN:
					var sub := r.read_sub_reader()
					while _alive(sub) and not sub.eof():
						ints.append(sub.read_varint())
				elif r.wire == PbReader.WIRE_VARINT:
					ints.append(r.read_varint())
				else:
					r.skip_value()
			20:
				attr_type = r.read_varint() if r.wire == PbReader.WIRE_VARINT else 0
			_:
				r.skip_value()
	_alive(r)
	if _err != "":
		return
	if attr_type == 5 or attr_type == 10:
		_fail("graph-valued attribute '%s' on node %s is not supported" % [attr_name, node.label()])
		return
	if value == null and floats.is_empty() and ints.is_empty():
		# proto2 omits default values; the declared type tells what the attribute is.
		match attr_type:
			1:
				value = 0.0
			2:
				value = 0
			3:
				value = ""
	if attr_type == 6 or not floats.is_empty():
		value = floats
	elif attr_type == 7 or not ints.is_empty():
		value = ints
	node.attrs[attr_name] = value

func _read_tensor(r: PbReader) -> OnnxTensor:
	var dims := PackedInt32Array()
	var data_type := 0
	var tensor_name := ""
	var raw := PackedByteArray()
	var has_raw := false
	var float_data := PackedFloat32Array()
	var int_data := PackedInt64Array()
	var has_float := false
	var has_int := false
	var external := false
	while _alive(r) and r.read_tag():
		match r.field:
			1:
				if r.wire == PbReader.WIRE_LEN:
					var sub := r.read_sub_reader()
					while _alive(sub) and not sub.eof():
						dims.append(sub.read_varint())
				elif r.wire == PbReader.WIRE_VARINT:
					dims.append(r.read_varint())
				else:
					r.skip_value()
			2:
				data_type = r.read_varint() if r.wire == PbReader.WIRE_VARINT else 0
			4:
				has_float = true
				if r.wire == PbReader.WIRE_LEN:
					var window := r.read_len_window()
					if (window.y - window.x) % 4 != 0:
						_fail("tensor float_data has %d bytes, not a multiple of 4" % (window.y - window.x))
						return null
					float_data.append_array(r.buf.slice(window.x, window.y).to_float32_array())
				elif r.wire == PbReader.WIRE_FIXED32:
					float_data.append(r.read_float())
				else:
					r.skip_value()
			7:
				has_int = true
				if r.wire == PbReader.WIRE_LEN:
					var sub2 := r.read_sub_reader()
					while _alive(sub2) and not sub2.eof():
						int_data.append(sub2.read_varint())
				elif r.wire == PbReader.WIRE_VARINT:
					int_data.append(r.read_varint())
				else:
					r.skip_value()
			8:
				tensor_name = r.read_string() if r.wire == PbReader.WIRE_LEN else ""
			9:
				if r.wire == PbReader.WIRE_LEN:
					raw = r.read_bytes()
					has_raw = true
				else:
					r.skip_value()
			13, 14:
				external = true
				r.skip_value()
			_:
				r.skip_value()
	if not _alive(r):
		return null
	var label := "'%s'" % tensor_name
	if external:
		_fail("tensor %s uses external data, which is not supported" % label)
		return null
	if data_type != OnnxTensor.FLOAT and data_type != OnnxTensor.INT64:
		_fail("tensor %s has unsupported data type %d (only float32 weights and int64 constants)" % [label, data_type])
		return null
	var count := 1
	for d in dims:
		if d < 0:
			_fail("tensor %s has a negative dimension" % label)
			return null
		count *= d
		if count > int(_limits.max_tensor_elements):
			_fail("tensor %s is too large (limit %d elements)" % [label, int(_limits.max_tensor_elements)])
			return null
	if dims.size() > OnnxTensor.MAX_RANK:
		_fail("tensor %s has rank %d (limit %d)" % [label, dims.size(), OnnxTensor.MAX_RANK])
		return null
	var tensor := OnnxTensor.new()
	tensor.dtype = data_type
	tensor.shape = dims
	tensor.set_meta("name", tensor_name)
	if data_type == OnnxTensor.FLOAT:
		if has_raw:
			if raw.size() != count * 4:
				_fail("tensor %s raw_data has %d bytes, expected %d" % [label, raw.size(), count * 4])
				return null
			tensor.data = raw.to_float32_array()
		elif has_float:
			if float_data.size() != count:
				_fail("tensor %s float_data has %d values, expected %d" % [label, float_data.size(), count])
				return null
			tensor.data = float_data
		elif count != 0:
			_fail("tensor %s has no data" % label)
			return null
	else:
		if has_raw:
			if raw.size() != count * 8:
				_fail("tensor %s raw_data has %d bytes, expected %d" % [label, raw.size(), count * 8])
				return null
			for k in count:
				tensor.ints.append(raw.decode_s64(k * 8))
		elif has_int:
			if int_data.size() != count:
				_fail("tensor %s int64_data has %d values, expected %d" % [label, int_data.size(), count])
				return null
			tensor.ints = int_data
		elif count != 0:
			_fail("tensor %s has no data" % label)
			return null
	return tensor

func _read_value_info(r: PbReader) -> ValueInfo:
	var info := ValueInfo.new()
	while _alive(r) and r.read_tag():
		if r.field == 1 and r.wire == PbReader.WIRE_LEN:
			info.name = r.read_string()
		elif r.field == 2 and r.wire == PbReader.WIRE_LEN:
			_read_type(r.read_sub_reader(), info)
		else:
			r.skip_value()
	_alive(r)
	return info

func _read_type(r: PbReader, info: ValueInfo) -> void:
	while _alive(r) and r.read_tag():
		if r.field == 1 and r.wire == PbReader.WIRE_LEN:
			var t := r.read_sub_reader()
			while _alive(t) and t.read_tag():
				if t.field == 1 and t.wire == PbReader.WIRE_VARINT:
					info.elem_type = t.read_varint()
				elif t.field == 2 and t.wire == PbReader.WIRE_LEN:
					info.has_shape = true
					_read_shape(t.read_sub_reader(), info)
				else:
					t.skip_value()
			_alive(t)
		else:
			r.skip_value()
	_alive(r)

func _read_shape(r: PbReader, info: ValueInfo) -> void:
	while _alive(r) and r.read_tag():
		if r.field == 1 and r.wire == PbReader.WIRE_LEN:
			var d := r.read_sub_reader()
			var size := -1
			while _alive(d) and d.read_tag():
				if d.field == 1 and d.wire == PbReader.WIRE_VARINT:
					size = d.read_varint()
				else:
					d.skip_value()
			_alive(d)
			info.dims.append(size)
		else:
			r.skip_value()
	_alive(r)
