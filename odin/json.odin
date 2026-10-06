package cyb

// A small JSON reader and writer, just enough for the save files.
//
// The reader needs no allocator: nodes and decoded strings live in fixed pools
// inside a Json_Doc, so nothing can leak and hostile input is bounded (input
// length, node count, string bytes and nesting depth all have limits).

import "core:fmt"
import "core:strconv"
import "core:unicode/utf8"

JSON_MAX_INPUT :: 32768
JSON_MAX_NODES :: 512
JSON_POOL_SIZE :: 16384
JSON_MAX_DEPTH :: 8
JSON_MAX_SAFE_INT :: 1 << 53

Json_Kind :: enum u8 {
	Null,
	Bool,
	Number,
	String,
	Array,
	Object,
}

// Node 0 is "no node". Children of an array or object are a linked list:
// `first` is the first child, `next` the next sibling. Object children carry their key.
Json_Node :: struct {
	kind:    Json_Kind,
	boolean: bool,
	num:     f64,
	str:     string,
	key:     string,
	first:   int,
	next:    int,
}

Json_Doc :: struct {
	nodes:    [JSON_MAX_NODES]Json_Node,
	count:    int,
	pool:     [JSON_POOL_SIZE]u8,
	pool_len: int,
	root:     int,
}

@(private = "file")
Json_Parser :: struct {
	doc:   ^Json_Doc,
	text:  string,
	pos:   int,
	depth: int,
}

json_parse :: proc(doc: ^Json_Doc, text: string) -> bool {
	doc.count = 1
	doc.pool_len = 0
	doc.root = 0
	if len(text) > JSON_MAX_INPUT {
		return false
	}
	p := Json_Parser{doc = doc, text = text}
	skip_ws(&p)
	root, ok := parse_value(&p)
	if !ok {
		return false
	}
	skip_ws(&p)
	if p.pos != len(text) {
		return false
	}
	doc.root = root
	return true
}

// ---- reading helpers (0 means "not there") ----

json_kind :: proc(doc: ^Json_Doc, n: int) -> Json_Kind {
	return doc.nodes[n].kind if n > 0 else .Null
}

json_get :: proc(doc: ^Json_Doc, obj: int, key: string) -> int {
	if json_kind(doc, obj) != .Object || obj == 0 {
		return 0
	}
	for c := doc.nodes[obj].first; c != 0; c = doc.nodes[c].next {
		if doc.nodes[c].key == key {
			return c
		}
	}
	return 0
}

json_at :: proc(doc: ^Json_Doc, arr: int, index: int) -> int {
	if json_kind(doc, arr) != .Array || arr == 0 || index < 0 {
		return 0
	}
	c := doc.nodes[arr].first
	for _ in 0 ..< index {
		if c == 0 {
			return 0
		}
		c = doc.nodes[c].next
	}
	return c
}

// A whole number within +/- 2^53. (i64: int is only 32 bits in the wasm build.)
json_int :: proc(doc: ^Json_Doc, n: int) -> (value: i64, ok: bool) {
	if json_kind(doc, n) != .Number || n == 0 {
		return 0, false
	}
	x := doc.nodes[n].num
	if x != x || x < -JSON_MAX_SAFE_INT || x > JSON_MAX_SAFE_INT || x != f64(i64(x)) {
		return 0, false
	}
	return i64(x), true
}

json_string :: proc(doc: ^Json_Doc, n: int) -> (s: string, ok: bool) {
	if json_kind(doc, n) != .String || n == 0 {
		return "", false
	}
	return doc.nodes[n].str, true
}

// ---- parser ----

@(private = "file")
skip_ws :: proc(p: ^Json_Parser) {
	for p.pos < len(p.text) {
		switch p.text[p.pos] {
		case ' ', '\t', '\n', '\r':
			p.pos += 1
		case:
			return
		}
	}
}

@(private = "file")
new_node :: proc(p: ^Json_Parser, kind: Json_Kind) -> (int, bool) {
	if p.doc.count >= JSON_MAX_NODES {
		return 0, false
	}
	n := p.doc.count
	p.doc.count += 1
	p.doc.nodes[n] = {
		kind = kind,
	}
	return n, true
}

@(private = "file")
pool_put :: proc(doc: ^Json_Doc, b: u8) -> bool {
	if doc.pool_len >= JSON_POOL_SIZE {
		return false
	}
	doc.pool[doc.pool_len] = b
	doc.pool_len += 1
	return true
}

@(private = "file")
hex4 :: proc(s: string) -> (r: int, ok: bool) {
	if len(s) < 4 {
		return 0, false
	}
	for c in transmute([]u8)s[:4] {
		d: int
		switch {
		case c >= '0' && c <= '9':
			d = int(c - '0')
		case c >= 'a' && c <= 'f':
			d = int(c - 'a') + 10
		case c >= 'A' && c <= 'F':
			d = int(c - 'A') + 10
		case:
			return 0, false
		}
		r = r * 16 + d
	}
	return r, true
}

@(private = "file")
parse_string :: proc(p: ^Json_Parser) -> (s: string, ok: bool) {
	doc := p.doc
	if p.pos >= len(p.text) || p.text[p.pos] != '"' {
		return "", false
	}
	p.pos += 1
	start := doc.pool_len
	for {
		if p.pos >= len(p.text) {
			return "", false
		}
		c := p.text[p.pos]
		p.pos += 1
		switch {
		case c == '"':
			s = string(doc.pool[start:doc.pool_len])
			return s, utf8.valid_string(s)
		case c < 0x20:
			return "", false
		case c == '\\':
			if p.pos >= len(p.text) {
				return "", false
			}
			e := p.text[p.pos]
			p.pos += 1
			put: u8
			switch e {
			case '"', '\\', '/':
				put = e
			case 'b':
				put = '\b'
			case 'f':
				put = '\f'
			case 'n':
				put = '\n'
			case 'r':
				put = '\r'
			case 't':
				put = '\t'
			case 'u':
				r, rok := hex4(p.text[p.pos:])
				if !rok {
					return "", false
				}
				p.pos += 4
				if r >= 0xD800 && r <= 0xDBFF {
					if p.pos + 6 > len(p.text) || p.text[p.pos] != '\\' || p.text[p.pos + 1] != 'u' {
						return "", false
					}
					lo, lok := hex4(p.text[p.pos + 2:])
					if !lok || lo < 0xDC00 || lo > 0xDFFF {
						return "", false
					}
					p.pos += 6
					r = 0x10000 + ((r - 0xD800) << 10) + (lo - 0xDC00)
				} else if r >= 0xDC00 && r <= 0xDFFF {
					return "", false
				}
				bytes, n := utf8.encode_rune(rune(r))
				for i in 0 ..< n {
					if !pool_put(doc, bytes[i]) {
						return "", false
					}
				}
				continue
			case:
				return "", false
			}
			if !pool_put(doc, put) {
				return "", false
			}
		case:
			if !pool_put(doc, c) {
				return "", false
			}
		}
	}
}

@(private = "file")
parse_literal :: proc(p: ^Json_Parser, word: string) -> bool {
	if p.pos + len(word) > len(p.text) || p.text[p.pos:p.pos + len(word)] != word {
		return false
	}
	p.pos += len(word)
	return true
}

@(private = "file")
parse_number :: proc(p: ^Json_Parser) -> (int, bool) {
	start := p.pos
	for p.pos < len(p.text) {
		c := p.text[p.pos]
		if (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E' {
			p.pos += 1
		} else {
			break
		}
	}
	text := p.text[start:p.pos]
	value, n, ok := strconv.parse_f64_prefix(text)
	if !ok || n != len(text) || len(text) == 0 {
		return 0, false
	}
	node, nok := new_node(p, .Number)
	if !nok {
		return 0, false
	}
	p.doc.nodes[node].num = value
	return node, true
}

@(private = "file")
parse_value :: proc(p: ^Json_Parser) -> (int, bool) {
	if p.pos >= len(p.text) {
		return 0, false
	}
	switch c := p.text[p.pos]; {
	case c == '{':
		return parse_container(p, .Object)
	case c == '[':
		return parse_container(p, .Array)
	case c == '"':
		s, ok := parse_string(p)
		if !ok {
			return 0, false
		}
		n, nok := new_node(p, .String)
		if !nok {
			return 0, false
		}
		p.doc.nodes[n].str = s
		return n, true
	case c == 't':
		if !parse_literal(p, "true") {
			return 0, false
		}
		n, ok := new_node(p, .Bool)
		if ok {
			p.doc.nodes[n].boolean = true
		}
		return n, ok
	case c == 'f':
		if !parse_literal(p, "false") {
			return 0, false
		}
		return new_node(p, .Bool)
	case c == 'n':
		if !parse_literal(p, "null") {
			return 0, false
		}
		return new_node(p, .Null)
	case c == '-' || (c >= '0' && c <= '9'):
		return parse_number(p)
	}
	return 0, false
}

@(private = "file")
parse_container :: proc(p: ^Json_Parser, kind: Json_Kind) -> (int, bool) {
	if p.depth >= JSON_MAX_DEPTH {
		return 0, false
	}
	p.depth += 1
	defer p.depth -= 1
	node, ok := new_node(p, kind)
	if !ok {
		return 0, false
	}
	close: u8 = '}' if kind == .Object else ']'
	p.pos += 1 // the opening bracket
	skip_ws(p)
	if p.pos < len(p.text) && p.text[p.pos] == close {
		p.pos += 1
		return node, true
	}
	last := 0
	for {
		skip_ws(p)
		key: string
		if kind == .Object {
			k, kok := parse_string(p)
			if !kok {
				return 0, false
			}
			key = k
			skip_ws(p)
			if p.pos >= len(p.text) || p.text[p.pos] != ':' {
				return 0, false
			}
			p.pos += 1
			skip_ws(p)
		}
		child, cok := parse_value(p)
		if !cok {
			return 0, false
		}
		p.doc.nodes[child].key = key
		if last == 0 {
			p.doc.nodes[node].first = child
		} else {
			p.doc.nodes[last].next = child
		}
		last = child
		skip_ws(p)
		if p.pos >= len(p.text) {
			return 0, false
		}
		c := p.text[p.pos]
		p.pos += 1
		if c == close {
			return node, true
		}
		if c != ',' {
			return 0, false
		}
	}
}

// ---- writer ----

Json_Writer :: struct {
	buf: []u8,
	len: int,
	ok:  bool,
}

json_writer :: proc(buf: []u8) -> Json_Writer {
	return {buf = buf, ok = true}
}

json_raw :: proc(w: ^Json_Writer, s: string) {
	if !w.ok || w.len + len(s) > len(w.buf) {
		w.ok = false
		return
	}
	copy(w.buf[w.len:], s)
	w.len += len(s)
}

json_int_out :: proc(w: ^Json_Writer, n: i64) {
	tmp: [24]u8
	json_raw(w, fmt.bprintf(tmp[:], "%d", n))
}

json_string_out :: proc(w: ^Json_Writer, s: string) {
	json_raw(w, "\"")
	for c in transmute([]u8)s {
		switch {
		case c == '"':
			json_raw(w, "\\\"")
		case c == '\\':
			json_raw(w, "\\\\")
		case c < 0x20:
			tmp: [8]u8
			json_raw(w, fmt.bprintf(tmp[:], "\\u%04x", int(c)))
		case:
			one := [1]u8{c}
			json_raw(w, string(one[:]))
		}
	}
	json_raw(w, "\"")
}

json_result :: proc(w: ^Json_Writer) -> (string, bool) {
	return string(w.buf[:w.len]), w.ok
}
