class_name OnnxTensor
extends RefCounted
## A dense tensor of the ONNX interpreter: row-major float32 `data` (dtype FLOAT)
## or int64 `ints` (dtype INT64, shape/axes constants only).
##
## Limits: at most MAX_ELEMENTS elements and MAX_RANK dimensions, so a hostile
## model cannot request a huge allocation.

const FLOAT := 1
const INT64 := 7
const MAX_ELEMENTS := 4194304
const MAX_RANK := 8

var dtype: int = FLOAT
var shape: PackedInt32Array = PackedInt32Array()
var data: PackedFloat32Array = PackedFloat32Array()
var ints: PackedInt64Array = PackedInt64Array()

static func float_tensor(tensor_shape: PackedInt32Array, values: PackedFloat32Array) -> OnnxTensor:
	var t := OnnxTensor.new()
	t.shape = tensor_shape
	t.data = values
	return t

static func zeros(tensor_shape: PackedInt32Array) -> OnnxTensor:
	var t := OnnxTensor.new()
	t.shape = tensor_shape
	t.data.resize(max(count_of(tensor_shape), 0))
	return t

## Element count of a shape, or -1 when a dimension is negative, the rank is above
## MAX_RANK or the count exceeds MAX_ELEMENTS.
static func count_of(tensor_shape: PackedInt32Array) -> int:
	if tensor_shape.size() > MAX_RANK:
		return -1
	var total := 1
	for d in tensor_shape:
		if d < 0:
			return -1
		total *= d
		if total > MAX_ELEMENTS:
			return -1
	return total

func count() -> int:
	return data.size() if dtype == FLOAT else ints.size()

func shape_text() -> String:
	return str(Array(shape))
