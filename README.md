# YYLite

This library is for decoding and encoding JSON with small, hand-shaped Swift **final classes** (or
Objective-C `NSObject` classes). Swift calls a size-patched copy of [yyjson](https://github.com/ibireme/yyjson)
directly. It has no Codable, no generics in the public API and no model protocols, so each property
costs only a few instructions, and the binary carries no per-type Codable metadata or witness tables.

* **Size**: with all 50 benchmark models (660 properties) decoding and encoding, it adds **185 KB** of
  code. The Foundation Codable equivalent adds **473 KB** (Linux aarch64 proxy, see below).
* **Speed** (Linux x86-64): decode is about **14x** faster than `JSONDecoder` and encode about **17x**
  faster than `JSONEncoder`.

```
Package.swift            products: YYLite (Swift, all platforms); YYLiteObjC (Apple only)
Sources/CYYJSON          yyjson 0.13.0 + patches/yyjson-size-opt.patch (read-only build,
                         symbols renamed yylite_*), plus yylite_writer.{h,c}: the C writer core
                         shared by Swift and ObjC
Sources/YYLite           JSONDocument, JSON, JSONError, JSONWriter (Swift)
Sources/YYLiteObjC       YYLJSONDocument, YYLJSONValue, YYLJSONWriter (ObjC over the same C)
tools/yylite-gen.py      optional codegen: spec JSON → model classes (decode + encode)
tools/objc-compile-check.sh   compile-only ObjC check with stand-in headers (no Apple SDK needed)
Examples/                Cards.generated.swift (+ spec), ObjC/MTGCard.{h,m}
Tests/                   YYLiteTests, GeneratedExampleTests, YYLiteObjCTests (Mac only)
Benchmarks/              separate package: 50-model benchmark, size probes, Option A experiment
```

## Quick start (Swift)

```swift
import YYLite

final class SetInfo {
    let code: String, name: String
    init(_ j: JSON) throws { code = try j.string("code"); name = try j.string("name") }
    func encode(_ w: JSONWriter) { w.object { w.string("code", code); w.string("name", name) } }
}

final class Card {
    let id: Int, name: String, manaCost: String?, cmc: Double, colors: [String], set: SetInfo
    let printings: [SetInfo], foil: Bool

    init(_ j: JSON) throws {
        id = try j.int("id")
        name = try j.string("name")
        manaCost = try j.optionalString("mana_cost")      // missing or null → nil
        cmc = try j.double("cmc")                         // ints are accepted too
        colors = try j.strings("colors")
        set = try SetInfo(j.object("set"))
        printings = try j.objects("printings").map(SetInfo.init)
        foil = try j.bool("foil", default: false)         // missing or null → default
    }

    func encode(_ w: JSONWriter) {
        w.object {
            w.int("id", id); w.string("name", name); w.optionalString("mana_cost", manaCost)
            w.double("cmc", cmc); w.strings("colors", colors)
            w.key("set"); set.encode(w)
            w.array("printings") { for p in printings { p.encode(w) } }
            w.bool("foil", foil)
        }
    }
}

let cards = try JSON.parse(data).elements().map(Card.init)          // decode
let out = try JSONWriter.encode { w in w.array { for c in cards { c.encode(w) } } }   // → Data
let pretty = try JSONWriter.encode(pretty: true) { w in cards[0].encode(w) }
```

### Reading API (`JSON`)
| | required (throws if missing/null/wrong) | optional (missing/null → nil) | default |
|---|---|---|---|
| scalars | `int` `int64` `uint` `double` `float` `bool` `string` `(key)` | `optionalInt(key)` … | `int(key, default: 0)` … |
| arrays | `strings` `ints` `doubles` `bools` `(key)` | `optionalStrings(key)` … | |
| objects | `object(key)`, `objects(key)`, `forEachObject(key) { }` | `optionalObject`, `optionalObjects` | |
| the value itself | `int()` `double()` `string()` … `elements()` | | |
| raw | `type`, `isNull`, `count`, `j["key"]`, `j[3]`, `contains`, `keys`, `forEachMember`, `forEachElement` | | |

Keys in getters are `StaticString` (literals), so there is no String bridging on the hot path.
Use `j["runtime key"]` for keys you only know at run time.

`objects(key).map(X.init)` and `forEachObject` are equally fast. The generator uses `.map`
because it measured smaller (111.8 KB vs 118.0 KB for the 50 models).

### Writing API (`JSONWriter`)
* `JSONWriter.encode(pretty:nilStrategy:nonFinite:) { w in … } throws -> Data`. Bytes stream
  straight into one buffer with no tree, and the resulting `Data` takes that buffer without a copy.
* Keyed calls go inside `object { }`: `int("k", v)`, `string`, `double`, `float`, `bool`,
  `uint`, `int64`, `null("k")`, `optionalX("k", v)`, `strings/ints/doubles/bools("k", [..])`,
  `object("k") { }`, `array("k") { }`, and `key("k")` followed by any unkeyed value.
* Unkeyed calls go inside `array { }`: `int(v)`, `string(v)`, `object { }`, … .
* **nil** is omitted by default, matching synthesized Codable + `JSONEncoder`. Use
  `nilStrategy: .null` to write `null` instead.
* **NaN/±Infinity** throw by default, as `JSONEncoder` does. The error path names the key, e.g.
  `$….x`. Use `nonFinite: .null` to write `null` instead.
* **Doubles** are written with Swift's shortest round-trip text (`Double.description`): `0.1`,
  `5e-324`, `-0.0`, and `3.0` for integral values. Every double re-parses bit-exactly (tested on
  20k random bit patterns + edge cases). Integers cover the full `Int.min…UInt64.max` range.
* **Strings** escape `"` `\` and control characters (`\n \t \r \b \f`, otherwise `\u00XX`).
  `/` and non-ASCII are written as raw UTF-8, as `JSONEncoder` does (except that it escapes `/`).

### Codegen (optional)
```
python3 tools/yylite-gen.py Examples/cards.spec.json -o Cards.generated.swift
```
The spec maps each model to its properties, keyed by JSON key, e.g.
`{"id": "Int", "mana_cost": "String?", "set": "SetInfo", "printings": "[Printing]",
"foil": {"type": "Bool", "default": false}}`. `"@entry": true` adds `init(data:)` and
`jsonData(pretty:)`. Run `--help` for the full format. `--kind struct` emits structs with the same
API instead of final classes. For the 50 models these were 73% more model code and 3–6% slower
to decode, so classes stay the default (see `Benchmarks/STRUCT-VS-CLASS.md`).

## Lifetime and threading
* A `JSON` value holds a strong reference to its `JSONDocument`, so values stay valid as long as
  you hold them: `let o = try JSON.parse(d).object("x")` is safe. `String`s and numbers you read
  are copies and do not keep the document alive.
* **A document is not thread-safe**, even for reads: lookups update a small per-document cursor
  cache, which makes in-order key reads O(1). Decode a document on one thread at a time. Parsing
  separate documents concurrently is fine. `JSONWriter` is single-threaded too.
* Memory: yyjson's tree is about 16 B per value plus the copied input, freed when the document
  deinitialises.

## Errors
Every failure is one `JSONError` (Swift) or one `NSError` in `YYLJSONErrorDomain` (ObjC):
```
$.cards[3].set.code: expected String, found number
$.cards[0].cmc: expected Double, found missing
$.items[2].count: expected Int, found non-integer number
$: invalid JSON (yyjson error 3 at byte 6)        // parseCode, parsePosition
```
The fields are `path`, `expected`, `found`, plus `parseCode` and `parsePosition` for parse
errors. The path is computed only when an error is thrown, by searching from the root, so the
success path pays nothing for it.

## Objective-C (`YYLiteObjC`, Apple platforms only)
This is pure ObjC over the same yyjson reader and the same C writer core (`yylite_writer.c`),
with no Swift in between.
```objc
#import "YYLiteObjC.h"   // or @import YYLiteObjC;

- (nullable instancetype)initWithJSON:(YYLJSONValue *)json error:(NSError **)error {
    if (!(self = [super init])) return nil;
    NSError *e = nil;      // YYL_CHECK(e): if (e) { *error = e; return nil; }
    _cardID = [json int64ForKey:@"id" error:&e];                       YYL_CHECK(e);
    _name = [json stringForKey:@"name" error:&e];                      YYL_CHECK(e);
    _flavorText = [json optionalStringForKey:@"flavor_text" error:&e]; YYL_CHECK(e);  // missing/null → nil
    _power = [json optionalNumberForKey:@"power" error:&e];            YYL_CHECK(e);
    _colors = [json stringsForKey:@"colors" error:&e];                 YYL_CHECK(e);
    YYLJSONValue *set = [json objectForKey:@"set" error:&e];           YYL_CHECK(e);
    _set = [[MTGSet alloc] initWithJSON:set error:&e];                 YYL_CHECK(e);
    ...
    return self;
}
- (void)encodeWithWriter:(YYLJSONWriter *)w {
    [w object:^{
        [w setInt64:self.cardID forKey:@"id"];
        [w setString:self.flavorText forKey:@"flavor_text"];     // nil → omitted (nilStrategy)
        [w setStrings:self.colors forKey:@"colors"];
        [w key:@"set"]; [self.set encodeWithWriter:w];
        [w array:^{ for (MTGSet *s in self.reprints) [s encodeWithWriter:w]; } key:@"reprints"];
    }];
}
YYLJSONValue *root = [YYLJSONDocument parse:data error:&error];
NSData *out = [YYLJSONWriter encode:^(YYLJSONWriter *w) { [card encodeWithWriter:w]; } error:&error];
```
The full example is in `Examples/ObjC/MTGCard.m`.

* Scalar getters return 0 or `NO` on failure and set `*error`, so **check the error, not the
  value**. Object getters return nil.
* Cost: each `YYLJSONValue` (from `objectForKey:`, `objectsForKey:`, `elementAtIndex:`, `root`)
  is one small heap object that retains the document. Scalars and strings need no wrapper. Key
  lookups convert the `NSString` key with `-UTF8String`, which is cheap for ASCII constant strings.
  Use `enumerateObjectsForKey:usingBlock:` to avoid building an `NSArray` of wrappers.
* Doubles are written by the C core with the shortest `%.15g`/`%.16g`/`%.17g` text that
  round-trips through `strtod`. This is not always the shortest possible text: `5e-324` becomes
  `4.94065645841247e-324`, which still re-parses to the same bits.
* Unverified on device: see the status table below.

## Size and speed

Size is measured on a Linux proxy: the Static Linux SDK for aarch64-musl, `-Osize`,
`-function-sections`, `-internalize-at-link`, `--gc-sections`, with linked bytes attributed from
the lld map (`Benchmarks/measure.sh`). The figures are app bytes; Swift stdlib and Foundation are
excluded because they ship in the OS on iOS. "No eh" leaves out `.eh_frame`, which is replaced
by much smaller compact unwind on iOS.

| 50 models (660 properties) | decode only | no eh | decode + encode | no eh |
|---|---:|---:|---:|---:|
| **YYLite**: generated models | 111,789 | 96,205 | 142,381 | 117,413 |
| YYLite Swift core | 27,570 | 22,290 | 30,950 | 24,762 |
| CYYJSON (yyjson reader + C writer) | 9,684 | 8,696 | 12,044 | 10,500 |
| **YYLite total** | **149,043** | **127,191** | **185,375** | **152,675** |
| Codable structs + Foundation | 406,161 (Decodable) | 280,309 | 473,093 (Codable) | 347,133 |
| Earlier hand-written classes + yyjson | 203,261 | | n/a | |

* The library alone (core reader + writer, measured with a single tiny model) is 28,954 B of
  Swift plus 12,044 B of C, about **41 KB** (33.6 KB without eh).
* Encoding all 50 models adds 30.6 KB of model code plus about 6 KB of core.
* Generated code is about 27% smaller than the earlier hand-written C-calling classes: shared
  getters versus inlined C calls, measured with the same flags.

Speed is measured on Linux x86-64 with swift-corelibs Foundation, not Apple's
(`Benchmarks: swift run -c release Bench50`). The file is models50.json, 1.18 MB and 2000 objects.

| | median |
|---|---:|
| Foundation `JSONDecoder` → structs | 56.7–58.0 ms |
| YYLite → classes | 4.08 ms (parse 1.9 + map 2.3) |
| earlier hand-written classes | 3.75–3.87 ms (YYLite is 6–9% slower: the price of the ergonomic API) |
| Foundation `JSONEncoder` ← structs | 37.6–40.1 ms |
| YYLite `JSONWriter` ← classes | 2.14–2.31 ms |

**Encode design.** Two options were evaluated:
* **(A)** Building a yyjson mutable document and calling `yyjson_mut_write`. This adds 14.5 KB of
  C. Even the C-only lower bound was 3.9 ms (building the tree alone was 0.67 ms). With
  `FAST_FP_CONV` off, it writes 17-digit `%.17g` doubles, so `0.1` becomes `0.10000000000000001`.
* **(B)** A direct streaming writer. This adds 2.4 KB of C (`yylite_writer.c`) and runs at
  2.1–2.3 ms, with shortest doubles from Swift.

**B was chosen.** The writer core is in C so that Swift and ObjC share it. Its string escaper
copies plain runs 8 bytes at a time; the byte-at-a-time `minsize` version made encode 40% slower.

## Tests
Run `swift test`; `swift test --sanitize=address` is ASan-clean, apart from XCTest's own
test-list allocations.
* **DecodeTests**: every getter and its optional/default variants, arrays, raw access, error
  paths and messages, invalid JSON code and position, and document lifetime.
* **EncodeTests**: exact model round-trip, pretty output equal to compact, escaping, numbers
  (`Int.min/max`, `UInt64.max`, `-0.0`, `1e308`, `5e-324`, `0.1`), non-finite values, and nesting
  with buffer growth.
* **CoreTests**: C double/float formatting (the ObjC path, 20k random doubles round-trip
  bit-exactly), C string and integer output, escaping fuzz checked against JSONSerialization, and
  lookup-cursor order independence.
* **GeneratedExampleTests**: the codegen output.
* **Benchmarks/Bench50Tests** (`cd Benchmarks && swift test`): all 50 models decode equal to
  Foundation, round-trip, and cross-decode both ways with Foundation.
* **YYLiteObjCTests** (Mac: `swift test --filter YYLiteObjCTests`): MTGCard decode, exact
  round-trip, error paths, raw access and lifetime, writer numbers, escaping and nil, pretty
  output, and a measure block.

### Status of the ObjC target
| | |
|---|---|
| compiles for arm64-apple-ios15 against **stand-in** headers (`tools/objc-compile-check.sh`, `-Wall -Wextra`, ARC) | ✅ done on Linux |
| object size (`.o`, excluding unwind/debug) | YYLiteObjC.o 22.4 KB, MTGCard.o (2 classes, 11 props) 8.4 KB; shares CYYJSON (~12 KB linked) |
| built against the real iOS/macOS SDK, linked, tests run | ❌ **not verified**: needs a Mac (`swift test`) |

ObjC methods are never dead-stripped, so the ObjC `.o` size is close to what the app pays. The
stand-in headers only declare what the code uses, so a real-SDK build may still raise warnings
such as nullability or deprecation.

## Upgrading yyjson
1. Replace `Sources/CYYJSON/yyjson.c` and `include/yyjson.h` with the new release.
2. Apply `patches/yyjson-size-opt.patch`, which only touches `yyjson.c`, and fix any rejects. It
   is guarded by `YYJSON_SIZE_OPT`.
3. Re-add the symbol-prefix block right after `#define YYJSON_H` in `yyjson.h`. It contains one
   `#define yyjson_x yylite_yyjson_x` per extern function. To list them:
   `nm -g --defined-only <built yyjson.o> | grep yyjson_`.
4. Run `swift test`, `Benchmarks/measure.sh` and `tools/objc-compile-check.sh`.

## Limitations
* Not thread-safe per document (see above). There is no `Sendable`.
* Getter keys must be literals (`StaticString`); use the subscript for runtime keys.
* Model class names that match Foundation types (`Locale`, `Thread`, `Notification`,
  `Dimension` …) become ambiguous in files that also `import Foundation`. Rename them or qualify
  them as `MyModule.Locale`.
* JSON is read-only: there is no in-place mutation. Use the writer to produce new JSON.
* No `Date`, `URL` or `Decimal` helpers. Read a `String` or `Double` and convert in the
  initializer.
* Numbers: `int()` rejects non-integers and out-of-range values; `double()` accepts integers
  (large ones lose precision past 2^53).
* All size numbers are a Linux/ELF proxy. On iOS each Swift class also carries class metadata, and
  Mach-O plus compact unwind changes the totals, so measure in your app with the linker map
  (`-Xlinker -map`).
* yyjson's input copy: the document reads non-insitu, so input `Data` can be released after parsing.
