extends SceneTree
## GDScript ONNX interpreter: protobuf reader bounds, parity with onnxruntime on the
## committed op fixtures (tests/fixtures/onnx/ops, made by training/bvs_training/
## gen_op_fixtures.py), load-time rejections, input validation, the 102-64-64-21
## MLP parity and its inference cost. Run headless.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const OPS_DIR := "res://tests/fixtures/onnx/ops/"
## Time budget per inference (headless desktop); the design target is 1 ms.
const MAX_INFERENCE_USEC := 2000.0
const PERF_RUNS := 200

var _max_error: float = 0.0

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	_check_reader(s)
	_check_op_fixtures(s)
	_check_rejections(s)
	_check_limits(s)
	_check_input_validation(s)
	_check_encodings(s)
	_check_mlp(s)
	_check_sidecar_and_schema(s)
	s.finish()

# ------------------------------------------------------------------ helpers

func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _bytes(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(OPS_DIR + name + ".onnx")

func _floats(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in values:
		out.append(float(v))
	return out

func _load(name: String) -> Dictionary:
	return OnnxPolicyModel.load_bytes(_bytes(name))

func _all_finite(values: PackedFloat32Array) -> bool:
	for v in values:
		if is_nan(v) or is_inf(v):
			return false
	return true

# ------------------------------------------------------------------ (a) reader

func _check_reader(s: Smoke) -> void:
	var r := PbReader.new(PackedByteArray([0xAC, 0x02]))
	s.check("reader: varint 300", r.read_varint() == 300 and r.error == "")
	r = PbReader.new(PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]))
	s.check("reader: ten-byte varint wraps to int64 -1", r.read_varint() == -1 and r.error == "")
	var too_long := PackedByteArray()
	for i in 11:
		too_long.append(0x80)
	too_long.append(0x01)
	r = PbReader.new(too_long)
	r.read_varint()
	s.check("reader: varint over 10 bytes is rejected", r.error.contains("varint"), r.error)
	r = PbReader.new(PackedByteArray([0x80]))
	r.read_varint()
	s.check("reader: truncated varint is rejected", r.error.contains("truncated"), r.error)
	# field 1, length-delimited, length 5 but only 2 payload bytes.
	r = PbReader.new(PackedByteArray([0x0A, 0x05, 0x01, 0x02]))
	s.check("reader: tag read", r.read_tag() and r.field == 1 and r.wire == PbReader.WIRE_LEN)
	r.read_len_window()
	s.check("reader: length beyond the remaining bytes is rejected", r.error.contains("exceeds"), r.error)
	for wire_type in [3, 4, 6, 7]:
		r = PbReader.new(PackedByteArray([(1 << 3) | wire_type, 0x00]))
		s.check("reader: wire type %d is rejected" % wire_type, not r.read_tag() and r.error.contains("wire type"), r.error)
	r = PbReader.new(PackedByteArray([0x00, 0x01]))
	s.check("reader: field number 0 is rejected", not r.read_tag() and r.error.contains("field number"), r.error)
	var float_bytes := PackedByteArray([0x15, 0, 0, 0, 0])
	float_bytes.encode_float(1, 1.5)
	r = PbReader.new(float_bytes)
	s.check("reader: fixed32 float", r.read_tag() and r.wire == PbReader.WIRE_FIXED32 and r.read_float() == 1.5 and r.eof())
	r = PbReader.new(PackedByteArray([0x15, 0, 0]))
	r.read_tag()
	r.read_float()
	s.check("reader: truncated fixed32 is rejected", r.error.contains("truncated"), r.error)
	r = PbReader.new(PackedByteArray([1, 2, 3]), 2, 9)
	s.check("reader: window outside the buffer is rejected", r.error.contains("window"), r.error)
	r = PbReader.new(PackedByteArray([0x08, 0x96, 0x01, 0x12, 0x02, 0xAA, 0xBB, 0x18, 0x07]))
	var seen := 0
	while r.read_tag():
		seen += 1
		r.skip_value()
	s.check("reader: skips varint and length-delimited fields", seen == 3 and r.error == "" and r.eof(), "fields=%d" % seen)

# ------------------------------------------------------------------ (b) op parity

func _check_op_fixtures(s: Smoke) -> void:
	var manifest: Dictionary = _json(OPS_DIR + "manifest.json")
	s.check("fixtures: manifest lists op fixtures", manifest.ok.size() >= 50, "%d ok fixtures" % manifest.ok.size())
	var failed: Array[String] = []
	var cases_run := 0
	for name in manifest.ok:
		var spec: Dictionary = _json(OPS_DIR + name + ".json")
		var loaded := _load(name)
		if loaded.model == null:
			failed.append("%s: load failed: %s" % [name, loaded.error])
			continue
		var model: OnnxPolicyModel = loaded.model
		var tolerance := float(spec.tolerance)
		for case_spec in spec.cases:
			var obs := _floats(case_spec.input)
			var expected := _floats(case_spec.expected)
			var got := model.infer(obs)
			cases_run += 1
			if got.size() != expected.size():
				failed.append("%s: output has %d values, expected %d" % [name, got.size(), expected.size()])
				continue
			if not _all_finite(got):
				failed.append("%s: output has NaN or inf" % name)
				continue
			for i in expected.size():
				var diff := absf(got[i] - expected[i])
				_max_error = maxf(_max_error, diff)
				if diff > tolerance:
					failed.append("%s: element %d differs by %s" % [name, i, str(diff)])
					break
	s.check("parity: every op fixture matches onnxruntime within 1e-4", failed.is_empty(), "; ".join(failed.slice(0, 5)))
	print("INFO onnx golden: %d fixtures, %d cases, max abs error %s" % [manifest.ok.size(), cases_run, str(_max_error)])
	s.check("parity: max abs error is at most 1e-4", _max_error <= 1e-4, str(_max_error))

# ------------------------------------------------------------------ (c) rejections

func _check_rejections(s: Smoke) -> void:
	var manifest: Dictionary = _json(OPS_DIR + "manifest.json")
	s.check("rejections: manifest lists rejection fixtures", manifest.reject.size() >= 15, "%d fixtures" % manifest.reject.size())
	for name in manifest.reject:
		var spec: Dictionary = _json(OPS_DIR + name + ".json")
		var loaded := _load(name)
		var reason := str(loaded.error)
		var named := reason.to_lower().contains(str(spec.reject).to_lower())
		s.check("rejection %s: load fails naming the cause" % name, loaded.model == null and named, "expected '%s', got '%s'" % [spec.reject, reason])

# ------------------------------------------------------------------ limits

func _check_limits(s: Smoke) -> void:
	var big := PackedByteArray()
	big.resize(OnnxModelParser.DEFAULT_LIMITS.max_bytes + 1)
	var too_big := OnnxPolicyModel.load_bytes(big)
	s.check("limits: a file over 16 MiB is rejected", too_big.model == null and str(too_big.error).contains("too large"), str(too_big.error))
	var mlp := _bytes("mlp_102_64_64_21")
	var few_nodes := OnnxPolicyModel.load_bytes(mlp, {}, {"max_nodes": 2})
	s.check("limits: more nodes than allowed is rejected", few_nodes.model == null and str(few_nodes.error).contains("nodes"), str(few_nodes.error))
	var few_inits := OnnxPolicyModel.load_bytes(mlp, {}, {"max_initializers": 2})
	s.check("limits: more initializers than allowed is rejected", few_inits.model == null and str(few_inits.error).contains("initializers"), str(few_inits.error))
	var small_tensor := OnnxPolicyModel.load_bytes(mlp, {}, {"max_tensor_elements": 100})
	s.check("limits: an oversized tensor is rejected", small_tensor.model == null and str(small_tensor.error).contains("too large"), str(small_tensor.error))
	var few_macs := OnnxPolicyModel.load_bytes(mlp, {}, {"max_macs": 1000})
	s.check("limits: a model over the multiply-add budget is rejected", few_macs.model == null and str(few_macs.error).contains("multiply-adds"), str(few_macs.error))
	var mlp_model: OnnxPolicyModel = _load("mlp_102_64_64_21").model
	s.check("limits: the reference MLP is under the 250k budget", mlp_model != null and mlp_model._graph.macs == 102 * 64 + 64 * 64 + 64 * 21, "macs=%d" % mlp_model._graph.macs)
	var corrupted := mlp.duplicate()
	for i in range(40, 80):
		corrupted[i] = (corrupted[i] + 91) % 256
	var started := Time.get_ticks_msec()
	var corrupt_result := OnnxPolicyModel.load_bytes(corrupted)
	s.check("limits: a corrupted buffer returns promptly (error or model, no hang)", Time.get_ticks_msec() - started < 2000 and (corrupt_result.model != null or str(corrupt_result.error) != ""))
	var mutated_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for round_index in 60:
		var copy := mlp.duplicate()
		for flips in 3:
			copy[rng.randi() % copy.size()] = rng.randi() % 256
		var result := OnnxPolicyModel.load_bytes(copy)
		if result.model == null and str(result.error) == "":
			mutated_ok = false
	s.check("limits: random byte mutations always end as a model or a reason", mutated_ok)

# ------------------------------------------------------------------ (d) input validation

func _check_input_validation(s: Smoke) -> void:
	var model: OnnxPolicyModel = _load("mlp_102_64_64_21").model
	var short := model.infer_checked(PackedFloat32Array([1.0, 2.0, 3.0]))
	s.check("input: wrong length returns the expected and got sizes and no output", str(short.error).contains("expected 102") and str(short.error).contains("got 3") and short.logits.is_empty(), str(short.error))
	var shorter_by_one := PackedFloat32Array()
	shorter_by_one.resize(101)
	var one_less := model.infer_checked(shorter_by_one)
	s.check("input: 101 values for 102 is rejected", str(one_less.error).contains("expected 102 inputs, got 101"), str(one_less.error))
	s.check("input: infer() returns an empty array and records last_error", model.infer(shorter_by_one).is_empty() and model.last_error != "")
	var ok := model.infer_checked(PackedFloat32Array())
	s.check("input: empty observation is rejected", str(ok.error).contains("got 0"), str(ok.error))

# ------------------------------------------------------------------ encodings

func _check_encodings(s: Smoke) -> void:
	var raw: OnnxPolicyModel = _load("gemm_raw_data").model
	var floats: OnnxPolicyModel = _load("gemm_float_data").model
	var obs := PackedFloat32Array([0.3, -0.7, 1.1, 0.0, 2.5, -1.4])
	var a := raw.infer(obs)
	var b := floats.infer(obs)
	s.check("encodings: raw_data and float_data give the same output", a.size() == 3 and a == b, "%s vs %s" % [str(a), str(b)])

# ------------------------------------------------------------------ (e) MLP, edge values, cost

func _check_mlp(s: Smoke) -> void:
	var loaded := _load("mlp_102_64_64_21")
	s.check("mlp: 102-64-64-21 loads", loaded.model != null, str(loaded.error))
	var model: OnnxPolicyModel = loaded.model
	var spec: Dictionary = _json(OPS_DIR + "mlp_102_64_64_21.json")
	var mlp_error := 0.0
	for case_spec in spec.cases:
		var got := model.infer(_floats(case_spec.input))
		var expected := _floats(case_spec.expected)
		for i in expected.size():
			mlp_error = maxf(mlp_error, absf(got[i] - expected[i]))
	s.check("mlp: parity with onnxruntime within 1e-4 on %d cases (zeros, ones, +-5, mixed)" % spec.cases.size(), mlp_error <= 1e-4, "max error %s" % str(mlp_error))
	print("INFO onnx mlp 102-64-64-21 max abs error %s" % str(mlp_error))
	# Edge values far outside the schema clip range: still finite.
	var finite := true
	for fill in [0.0, 1.0, -1.0, 5.0, -5.0, 1.0e6, -1.0e6]:
		var obs := PackedFloat32Array()
		obs.resize(model.input_dim())
		obs.fill(fill)
		finite = finite and _all_finite(model.infer(obs))
	s.check("edge: extreme observations never produce NaN or inf", finite)
	# Weights are parsed once: running does not parse again.
	var obs2 := PackedFloat32Array()
	obs2.resize(model.input_dim())
	for i in 100:
		model.infer(obs2)
	s.check("cost: weights are parsed once for 100 runs", model.parse_count == 1)
	# Inference cost.
	for warm in 20:
		model.infer(obs2)
	var start := Time.get_ticks_usec()
	for i in PERF_RUNS:
		model.infer(obs2)
	var per_run := float(Time.get_ticks_usec() - start) / float(PERF_RUNS)
	print("INFO onnx inference cost: %.1f us per inference (102-64-64-21, %d runs, headless)" % [per_run, PERF_RUNS])
	s.check("cost: inference stays under %d us" % int(MAX_INFERENCE_USEC), per_run <= MAX_INFERENCE_USEC, "%.1f us" % per_run)
	var relu_model: OnnxPolicyModel = _load("mlp_matmul_relu_102_32_21").model
	s.check("mlp: MatMul + Add + Relu variant loads and runs", relu_model != null and relu_model.infer(obs2).size() == 21)

# ------------------------------------------------------------------ sidecar and schema

func _check_sidecar_and_schema(s: Smoke) -> void:
	var mlp: OnnxPolicyModel = _load("mlp_102_64_64_21").model
	s.check("schema: the 102 to 21 MLP validates against bvs-schema-2", mlp.validate(BvsSchemaV2) == "", mlp.validate(BvsSchemaV2))
	var narrow: OnnxPolicyModel = _load("gemm_float_data").model
	var reason := narrow.validate(BvsSchemaV2)
	s.check("schema: a 6-input model is rejected with a readable reason", reason == "This model expects 6 inputs; this game provides 102", reason)
	s.check("schema: dynamic batch input is accepted", _load("dynamic_batch_dim").model != null)
	var state_model: OnnxPolicyModel = _load("extra_state_input_and_output").model
	s.check("godot_rl style: an extra state input is fed zeros", state_model != null and state_model.extra_input_names() == PackedStringArray(["state_ins"]) and state_model.infer(PackedFloat32Array([1, 2, 3, 4, 5, 6])).size() == 6)
	var named := OnnxPolicyModel.load_bytes(_bytes("extra_state_input_and_output"), {"onnx": {"output": "state_outs"}, "label": "named"})
	s.check("sidecar: onnx.output selects the output and label is kept", named.model != null and named.model.output_name() == "state_outs" and named.model.label == "named")
	var missing := OnnxPolicyModel.load_bytes(_bytes("extra_state_input_and_output"), {"onnx": {"output": "nope"}})
	s.check("sidecar: an unknown output name is rejected", missing.model == null and str(missing.error).contains("nope"), str(missing.error))
