class_name OnnxPolicyModel
extends RefCounted
## A loaded ONNX policy: compiled graph + bvs.json sidecar + provenance.
##
## `load_bytes(onnx, sidecar)` parses and compiles untrusted bytes and returns
## `{"model": OnnxPolicyModel | null, "error": String}`; a failed load never
## yields a usable model. `validate(schema)` cross-checks the graph against a
## schema class (input [1|dyn, OBS_DIM], output last dim LOGITS). `infer(obs)`
## returns the logits of the first graph output; on a wrong input length it
## returns an empty array and sets `last_error` (no partial output).
## An extra graph input (godot_rl `state_ins`) is fed zeros; the output used is
## the one named by sidecar `onnx.output`, else the first.

var repo_id: String = ""
var revision: String = ""
var sidecar: Dictionary = {}
var label: String = ""
var last_error: String = ""
## Number of times the bytes were parsed for this model (always 1: weights are parsed at load).
var parse_count: int = 0

var _graph: OnnxGraph
var _output_index: int = 0

static func load_bytes(onnx: PackedByteArray, sidecar_data: Dictionary = {}, limits: Dictionary = {}) -> Dictionary:
	var parsed := OnnxModelParser.parse(onnx, limits)
	if not parsed.ok():
		return {"model": null, "error": parsed.error}
	var graph := OnnxGraph.compile(parsed, limits)
	if not graph.ok():
		return {"model": null, "error": graph.error}
	var model := OnnxPolicyModel.new()
	model._graph = graph
	model.parse_count = 1
	model.sidecar = sidecar_data
	model.label = str(sidecar_data.get("label", ""))
	var onnx_info: Variant = sidecar_data.get("onnx", null)
	if onnx_info is Dictionary and (onnx_info as Dictionary).has("output"):
		var wanted := str((onnx_info as Dictionary)["output"])
		var index := graph.output_names.find(wanted)
		if index < 0:
			return {"model": null, "error": "the sidecar names output '%s' but the model has %s" % [wanted, str(Array(graph.output_names))]}
		model._output_index = index
	return {"model": model, "error": ""}

## Loads `model.onnx` and `bvs.json` from a res:// (or any readable) directory.
static func load_res(dir: String) -> Dictionary:
	var onnx_path := dir.path_join("model.onnx")
	var sidecar_path := dir.path_join("bvs.json")
	if not FileAccess.file_exists(onnx_path):
		return {"model": null, "error": "missing %s" % onnx_path}
	var sidecar_data: Dictionary = {}
	if FileAccess.file_exists(sidecar_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
		if parsed is Dictionary:
			sidecar_data = parsed
		else:
			return {"model": null, "error": "%s is not a JSON object" % sidecar_path}
	var result := load_bytes(FileAccess.get_file_as_bytes(onnx_path), sidecar_data)
	if result.model != null:
		result.model.label = result.model.label if result.model.label != "" else dir.get_file()
	return result

func input_dim() -> int:
	return _graph.input_dim

func output_dim() -> int:
	var shape := _graph.output_shapes[_output_index]
	return shape[shape.size() - 1] if not shape.is_empty() else 0

func input_name() -> String:
	return _graph.input_name

func output_name() -> String:
	return _graph.output_names[_output_index]

func extra_input_names() -> PackedStringArray:
	return PackedStringArray(_graph.extra_inputs.keys())

func op_count() -> int:
	return _graph._steps.size()

## Checks the model against a schema script exposing the OBS_DIM and LOGITS constants. Returns
## "" when compatible, else a reason a player can read.
func validate(schema: Script) -> String:
	var constants := schema.get_script_constant_map()
	return validate_dims(int(constants.get("OBS_DIM", -1)), int(constants.get("LOGITS", -1)))

## Same check with explicit dimensions.
func validate_dims(obs_dim: int, logits: int) -> String:
	if _graph.input_dim != obs_dim:
		return "This model expects %d inputs; this game provides %d" % [_graph.input_dim, obs_dim]
	if output_dim() != logits:
		return "This model produces %d outputs; this game expects %d" % [output_dim(), logits]
	return ""

## Logits for one observation, or an empty array (and `last_error`) on failure.
func infer(obs: PackedFloat32Array) -> PackedFloat32Array:
	var result := infer_checked(obs)
	return result.logits

## Like infer() but returns {"logits": PackedFloat32Array, "error": String}.
func infer_checked(obs: PackedFloat32Array) -> Dictionary:
	if obs.size() != _graph.input_dim:
		last_error = "expected %d inputs, got %d" % [_graph.input_dim, obs.size()]
		return {"logits": PackedFloat32Array(), "error": last_error}
	last_error = ""
	var outputs := _graph.run_all(obs)
	return {"logits": outputs[_output_index].data, "error": ""}
