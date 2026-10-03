class_name PbReader
extends RefCounted
## Bounded protobuf wire-format reader over a PackedByteArray (untrusted input).
##
## Supports wire types 0 (varint), 1 (fixed64), 2 (length-delimited) and 5
## (fixed32). Groups (3, 4) and the reserved types are rejected. Limits: varints
## are at most 10 bytes, a length may not exceed the bytes that remain in the
## reader's window, and field numbers must be 1..536870911. Any violation sets
## `error` (and stops further reads) instead of raising or reading out of range.
##
## Usage: `while r.read_tag(): match r.field: ...`, then check `r.error`.

const WIRE_VARINT := 0
const WIRE_FIXED64 := 1
const WIRE_LEN := 2
const WIRE_FIXED32 := 5
const MAX_VARINT_BYTES := 10
const MAX_FIELD_NUMBER := 536870911

var buf: PackedByteArray
var pos: int
var end: int
var error: String = ""
## Field number and wire type of the tag read last.
var field: int = 0
var wire: int = 0

func _init(buffer: PackedByteArray, start: int = 0, stop: int = -1) -> void:
	buf = buffer
	pos = start
	end = buffer.size() if stop < 0 else stop
	if start < 0 or end > buffer.size() or start > end:
		error = "parse error: reader window %d..%d is outside the %d-byte buffer" % [start, end, buffer.size()]
		pos = end

func eof() -> bool:
	return pos >= end

func remaining() -> int:
	return end - pos

func _fail(message: String) -> void:
	if error == "":
		error = "parse error: %s at byte %d" % [message, pos]
	pos = end

## Reads the next tag. Returns false at the end of the window or on error.
func read_tag() -> bool:
	if error != "" or pos >= end:
		return false
	var key := read_varint()
	if error != "":
		return false
	field = key >> 3
	wire = key & 7
	if field < 1 or field > MAX_FIELD_NUMBER:
		_fail("invalid field number %d" % field)
		return false
	if wire != WIRE_VARINT and wire != WIRE_FIXED64 and wire != WIRE_LEN and wire != WIRE_FIXED32:
		_fail("unsupported wire type %d (field %d)" % [wire, field])
		return false
	return true

## Reads one varint (up to 10 bytes). Negative int64 values wrap as in protobuf.
func read_varint() -> int:
	if error != "":
		return 0
	var result := 0
	var shift := 0
	for i in MAX_VARINT_BYTES:
		if pos >= end:
			_fail("truncated varint")
			return 0
		var b := buf[pos]
		pos += 1
		if shift < 64:
			result |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			return result
		shift += 7
	_fail("varint longer than %d bytes" % MAX_VARINT_BYTES)
	return 0

func read_fixed32_bits() -> int:
	if error != "":
		return 0
	if end - pos < 4:
		_fail("truncated fixed32")
		return 0
	var value := buf.decode_u32(pos)
	pos += 4
	return value

func read_float() -> float:
	if error != "":
		return 0.0
	if end - pos < 4:
		_fail("truncated fixed32")
		return 0.0
	var value := buf.decode_float(pos)
	pos += 4
	return value

func read_fixed64_bits() -> int:
	if error != "":
		return 0
	if end - pos < 8:
		_fail("truncated fixed64")
		return 0
	var value := buf.decode_s64(pos)
	pos += 8
	return value

## Reads a length prefix and returns the [start, stop) window of the payload,
## advancing past it. Returns an empty window and sets `error` when the length
## exceeds the remaining bytes.
func read_len_window() -> Vector2i:
	var length := read_varint()
	if error != "":
		return Vector2i(pos, pos)
	if length < 0 or length > end - pos:
		_fail("length %d exceeds the %d remaining bytes (field %d)" % [length, end - pos, field])
		return Vector2i(pos, pos)
	var window := Vector2i(pos, pos + length)
	pos += length
	return window

## A reader over the next length-delimited payload (shares the buffer, no copy).
func read_sub_reader() -> PbReader:
	var window := read_len_window()
	if error != "":
		return PbReader.new(buf, end, end)
	return PbReader.new(buf, window.x, window.y)

func read_string() -> String:
	var window := read_len_window()
	if error != "" or window.y == window.x:
		return ""
	return buf.slice(window.x, window.y).get_string_from_utf8()

func read_bytes() -> PackedByteArray:
	var window := read_len_window()
	if error != "":
		return PackedByteArray()
	return buf.slice(window.x, window.y)

## Skips the value of the current tag.
func skip_value() -> void:
	match wire:
		WIRE_VARINT:
			read_varint()
		WIRE_FIXED64:
			if end - pos < 8:
				_fail("truncated fixed64")
			else:
				pos += 8
		WIRE_LEN:
			read_len_window()
		WIRE_FIXED32:
			if end - pos < 4:
				_fail("truncated fixed32")
			else:
				pos += 4
		_:
			_fail("cannot skip wire type %d" % wire)
