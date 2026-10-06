package cyb

// xoshiro256** seeded by splitmix64. Our own generator, so a seed gives the same
// sequence on every target and tests are deterministic.

Rng :: struct {
	s: [4]u64,
}

splitmix64 :: proc(x: ^u64) -> u64 {
	x^ += 0x9E3779B97F4A7C15
	z := x^
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

rng_seed :: proc(r: ^Rng, seed: u64) {
	state := seed
	for i in 0 ..< 4 {
		r.s[i] = splitmix64(&state)
	}
}

rotl :: proc(x: u64, k: u64) -> u64 {
	return (x << k) | (x >> (64 - k))
}

rng_next :: proc(r: ^Rng) -> u64 {
	result := rotl(r.s[1] * 5, 7) * 9
	t := r.s[1] << 17
	r.s[2] ~= r.s[0]
	r.s[3] ~= r.s[1]
	r.s[1] ~= r.s[2]
	r.s[0] ~= r.s[3]
	r.s[2] ~= t
	r.s[3] = rotl(r.s[3], 45)
	return result
}

// Uniform integer in [lo, hi], both ends included, with no modulo bias.
// (The original game's roll ignored lo and returned 0 .. hi-lo.)
rng_roll :: proc(r: ^Rng, lo, hi: int) -> int {
	assert(hi >= lo)
	span := u64(hi - lo + 1)
	threshold := (~span + 1) % span
	x := rng_next(r)
	for _ in 0 ..< 64 {
		if x >= threshold {
			break
		}
		x = rng_next(r)
	}
	return lo + int(x % span)
}
