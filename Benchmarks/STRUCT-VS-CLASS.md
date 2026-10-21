# 50 models as `struct` vs `final class` (YYLite)

Same spec, same generator (`tools/yylite-gen.py --kind struct`), same `init(_ j: JSON) throws` /
`encode(_ w: JSONWriter)`; only `final class` → `struct` (and `convenience init(data:)` → `init(data:)`).
Targets: `Models50` (classes), `Models50S` (structs). Library API unchanged.

Verification: struct decode equal to Foundation field by field (2000 objects, nested), struct encode
**byte-identical** to the class encode, round trip and reading Foundation's output equal
(`Bench50` preconditions + `Bench50Tests/StructVariantTests`).

## Size (Static Linux SDK aarch64-musl, -Osize, function-sections + internalize-at-link, gc-sections, lld map)
| bytes | classes | structs | Codable structs |
|---|---:|---:|---:|
| model code, decode only | 111,789 | 212,044 (+90%) | 406,161 (Decodable) |
| model code, decode + encode | 142,381 | 246,912 (+73%) | 473,093 |
| … without .eh_frame | 117,413 | 200,504 (+71%) | 347,133 |
| total with core (30,950) + C (12,044), both directions | 185,375 | 289,906 | 473,093 |
| … without .eh_frame | 152,675 | 235,766 | 347,133 |

Where the struct extra ~90 KB of `.text` goes (decode + encode):
* value witnesses (copy/assign/destroy per struct): 41 KB, 361 functions; classes need none.
* `[Model]` array code specialised per element type (`_consumeAndCreateNew`, `_createNewBuffer`, …):
  ~26 KB; classes share one reference-type version.
* larger initializers (65 vs 50 KB): field-by-field cleanup on throw, indirect returns of big values.

iOS caveat: on Apple platforms each Swift class also gets Objective-C-compatible class data
(class metadata ~100–200 B/class, plus an ivar list entry, name string and offset per stored
property, very roughly 25–40 B/property). That is not present on Linux. Estimate for these 51
classes / 660 properties: **~25–35 KB extra for classes on iOS**. That would narrow, not remove,
the ~105 KB struct penalty. This is an estimate, not measured; check with `-Xlinker -map` in an iOS build.

## Speed (Linux x86-64, models50.json 1.18 MB, median of 101 runs, 3 runs → range)
| | median |
|---|---:|
| Foundation JSONDecoder → Codable structs | 56.0–57.3 ms |
| YYLite → classes | 4.00–4.07 ms |
| YYLite → structs | 4.17–4.26 ms (+3–6%) |
| map only (pre-parsed): classes / structs | 2.11–2.18 / 2.40–2.67 ms (+14–23%) |
| Foundation JSONEncoder ← Codable structs | 37.4–37.7 ms |
| YYLite encode ← classes | 2.13–2.16 ms |
| YYLite encode ← structs | 2.15–2.39 ms (≈ same, noisy) |

## Allocations per operation (LD_PRELOAD malloc counter, `malloccount/` + `alloc50`)
| | allocs | live while result held | bytes requested |
|---|---:|---:|---:|
| Foundation decode → structs | 213,698 | 15,643 | 24.6 MB |
| YYLite decode → classes | 21,107 | 20,398 | 6.07 MB |
| YYLite decode → structs | 16,352 | 15,643 | 5.97 MB |
| Foundation encode | 144,981 | — | 21.2 MB |
| YYLite encode (classes or structs) | 14 | — | 4.19 MB |

Structs save exactly one heap object per model instance (4,755 here, -23% allocs). Strings and
arrays still allocate, so the live object count is the same as Foundation's structs.

## Copy cost
Struct sizes: Event 552 B (29 props, nested structs inline), Product 609 B, Employee 376 B,
Order 304 B, Root50 400 B; a class reference is 8 B. Copying a struct means memcpy plus one retain
per String/array field (and release later). Copying every element once into a new array:
* `[Event]`: classes 14–17 ns per element, structs 253–262 ns (about 16x).
* `[Employee]`: classes 14 ns, structs 135–144 ns (about 10x).

This is paid by `let e = events[i]` when it escapes, by `map { $0 }`, by storing into another
collection or a dictionary, by capturing in an escaping closure, and by any mutation of a shared
copy. Read-only access in place (`events[i].budget`, `for e in events` that the optimiser keeps
borrowed) is usually free.

## Recommendation
Keep `final class` as the default. It is ~105 KB smaller for 50 models on this proxy (maybe
~70–80 KB after iOS class metadata), 3–6% faster to decode, the same speed to encode, and cheap
to pass around. It is also immutable (`let` fields), so it keeps most of the value semantics
people want from structs.

Use `--kind struct` only for a few small, hot leaf types (a handful of scalar fields, no nested
models or arrays), where saving one allocation each matters and copies are trivial. Avoid it for
big models (25+ properties or nested arrays of models).
