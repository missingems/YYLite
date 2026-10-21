#import <XCTest/XCTest.h>
#import "MTGCard.h"

static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static NSString *S(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }

static NSString *const kCards =
    @"[{\"id\":7,\"name\":\"Æther Ōni ✓\",\"cmc\":3.0,\"reserved\":false,\"colors\":[\"U\",\"R\"],"
     "\"set\":{\"code\":\"NEO\",\"name\":\"Kamigawa\"},\"reprints\":[{\"code\":\"M21\",\"name\":\"Core\"}]},"
     "{\"id\":8,\"name\":\"Bolt\",\"cmc\":1,\"reserved\":true,\"flavor_text\":\"\\\"Zap\\\"\\n\",\"power\":2,"
     "\"colors\":[],\"set\":{\"code\":\"LEA\",\"name\":\"Alpha\"},\"reprints\":[]}]";

@interface YYLiteObjCTests : XCTestCase
@end

@implementation YYLiteObjCTests

- (void)testDecodeModel {
    NSError *e = nil;
    NSArray<MTGCard *> *cards = [MTGCard cardsFromData:D(kCards) error:&e];
    XCTAssertNil(e); XCTAssertEqual(cards.count, 2u);
    XCTAssertEqual(cards[0].cardID, 7); XCTAssertEqualObjects(cards[0].name, @"Æther Ōni ✓");
    XCTAssertEqual(cards[0].cmc, 3.0); XCTAssertNil(cards[0].flavorText); XCTAssertNil(cards[0].power);
    XCTAssertEqualObjects(cards[0].colors, (@[@"U", @"R"])); XCTAssertEqualObjects(cards[0].set.code, @"NEO");
    XCTAssertEqualObjects(cards[0].reprints[0].name, @"Core");
    XCTAssertEqual(cards[1].cmc, 1.0); XCTAssertTrue(cards[1].reserved);
    XCTAssertEqualObjects(cards[1].flavorText, @"\"Zap\"\n"); XCTAssertEqualObjects(cards[1].power, @2);
}

- (void)testRoundTripExact {
    NSError *e = nil;
    NSArray<MTGCard *> *cards = [MTGCard cardsFromData:D(kCards) error:&e];
    NSData *out = [MTGCard dataForCards:cards error:&e];
    XCTAssertNil(e);
    XCTAssertEqualObjects(S(out),
        @"[{\"id\":7,\"name\":\"Æther Ōni ✓\",\"cmc\":3.0,\"reserved\":false,\"colors\":[\"U\",\"R\"],"
         "\"set\":{\"code\":\"NEO\",\"name\":\"Kamigawa\"},\"reprints\":[{\"code\":\"M21\",\"name\":\"Core\"}]},"
         "{\"id\":8,\"name\":\"Bolt\",\"cmc\":1.0,\"reserved\":true,\"flavor_text\":\"\\\"Zap\\\"\\n\",\"power\":2,"
         "\"colors\":[],\"set\":{\"code\":\"LEA\",\"name\":\"Alpha\"},\"reprints\":[]}]");
    // Foundation agrees it is valid JSON
    XCTAssertNotNil([NSJSONSerialization JSONObjectWithData:out options:0 error:NULL]);
    NSArray<MTGCard *> *again = [MTGCard cardsFromData:out error:&e];
    XCTAssertEqualObjects(S([MTGCard dataForCards:again error:&e]), S(out));
}

- (void)testErrorsCarryPath {
    NSError *e = nil;
    NSString *bad = [kCards stringByReplacingOccurrencesOfString:@"\"code\":\"LEA\"" withString:@"\"code\":5"];
    XCTAssertNil([MTGCard cardsFromData:D(bad) error:&e]);
    XCTAssertEqualObjects(e.domain, YYLJSONErrorDomain);
    XCTAssertEqual(e.code, YYLJSONErrorTypeMismatch);
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorPathKey], @"$[1].set.code");
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorExpectedKey], @"String");
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorFoundKey], @"number");
    XCTAssertEqualObjects(e.localizedDescription, @"$[1].set.code: expected String, found number");

    e = nil;
    NSString *missing = [kCards stringByReplacingOccurrencesOfString:@"\"cmc\":1," withString:@""];
    XCTAssertNil([MTGCard cardsFromData:D(missing) error:&e]);
    XCTAssertEqual(e.code, YYLJSONErrorMissing);
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorPathKey], @"$[1].cmc");

    e = nil;
    XCTAssertNil([YYLJSONDocument parse:D(@"{\"a\":1,}") error:&e]);
    XCTAssertEqual(e.code, YYLJSONErrorParse);
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorParsePositionKey], @6);

    e = nil;
    YYLJSONValue *v = [YYLJSONDocument parse:D(@"{\"f\":1.5,\"big\":18446744073709551615}") error:&e];
    XCTAssertEqual([v int64ForKey:@"f" error:&e], 0);
    XCTAssertEqualObjects(e.userInfo[YYLJSONErrorFoundKey], @"non-integer number");
    e = nil;
    XCTAssertEqual([v uint64ForKey:@"big" error:&e], UINT64_MAX); XCTAssertNil(e);
}

- (void)testRawAccessAndLifetime {
    YYLJSONValue *inner;
    @autoreleasepool {
        YYLJSONValue *root = [YYLJSONDocument parse:D(@"{\"a\":[1,true,null,\"x\"],\"o\":{\"k\":\"v\"}}") error:NULL];
        XCTAssertEqualObjects(root.keys, (@[@"a", @"o"]));
        XCTAssertTrue([root containsKey:@"o"]); XCTAssertFalse([root containsKey:@"z"]);
        YYLJSONValue *a = [root memberForKey:@"a"];
        XCTAssertEqual(a.type, YYLJSONTypeArray); XCTAssertEqual(a.count, 4u);
        XCTAssertTrue([a elementAtIndex:2].isNull); XCTAssertNil([a elementAtIndex:9]);
        XCTAssertEqualObjects([[a elementAtIndex:3] stringValueWithError:NULL], @"x");
        inner = [root objectForKey:@"o" error:NULL];
    }
    // the document is kept alive by `inner`
    XCTAssertEqualObjects([inner stringForKey:@"k" error:NULL], @"v");
}

- (void)testWriterNumbersEscapingNil {
    NSError *e = nil;
    NSData *d = [YYLJSONWriter encode:^(YYLJSONWriter *w) {
        [w object:^{
            [w setInt64:INT64_MIN forKey:@"min"];
            [w setUInt64:UINT64_MAX forKey:@"umax"];
            [w setDouble:-0.0 forKey:@"nz"];
            [w setDouble:0.1 forKey:@"tenth"];
            [w setDouble:1e308 forKey:@"big"];
            [w setDouble:5e-324 forKey:@"tiny"];
            [w setFloat:0.1f forKey:@"f"];
            [w setNumber:@YES forKey:@"b"];
            [w setNumber:@(2.5) forKey:@"n"];
            [w setString:nil forKey:@"gone"];
            [w setString:@"q\"\\\x01\t/é" forKey:@"s"];
            [w setNilForKey:@"gone2"];
        }];
    } error:&e];
    XCTAssertNil(e);
    NSString *s = S(d);
    XCTAssertEqualObjects(s, @"{\"min\":-9223372036854775808,\"umax\":18446744073709551615,\"nz\":-0.0,\"tenth\":0.1,"
                              "\"big\":1e+308,\"tiny\":4.94065645841247e-324,\"f\":0.1,\"b\":true,\"n\":2.5,"
                              "\"s\":\"q\\\"\\\\\\u0001\\t/é\"}");
    YYLJSONValue *r = [YYLJSONDocument parse:d error:NULL];
    XCTAssertEqual([r doubleForKey:@"tiny" error:NULL], 5e-324);
    XCTAssertEqual([r doubleForKey:@"tenth" error:NULL], 0.1);
    XCTAssertTrue(signbit([r doubleForKey:@"nz" error:NULL]));

    d = [YYLJSONWriter encodePretty:NO nilStrategy:YYLJSONNilWriteNull block:^(YYLJSONWriter *w) {
        [w object:^{ [w setString:nil forKey:@"x"]; }];
    } error:&e];
    XCTAssertEqualObjects(S(d), @"{\"x\":null}");

    d = [YYLJSONWriter encode:^(YYLJSONWriter *w) {
        [w object:^{ [w setDouble:NAN forKey:@"x"]; }];
    } error:&e];
    XCTAssertNil(d); XCTAssertEqual(e.code, YYLJSONErrorNonFinite);

    d = [YYLJSONWriter encode:^(YYLJSONWriter *w) {
        w.nonFiniteAsNull = YES;
        [w array:^{ [w addDouble:INFINITY]; [w addInteger:1]; }];
    } error:&e];
    XCTAssertEqualObjects(S(d), @"[null,1]");
}

- (void)testPretty {
    NSData *d = [YYLJSONWriter encodePretty:YES nilStrategy:YYLJSONNilOmit block:^(YYLJSONWriter *w) {
        [w object:^{ [w setInteger:1 forKey:@"a"]; [w array:^{ [w addString:@"x"]; } key:@"b"]; }];
    } error:NULL];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    XCTAssertEqualObjects(obj, (@{@"a": @1, @"b": @[@"x"]}));
    XCTAssertTrue([S(d) containsString:@"\n"]);
}

- (void)testPerformanceDecode {
    NSMutableString *json = [NSMutableString stringWithString:@"["];
    for (int i = 0; i < 2000; i++) {
        if (i) [json appendString:@","];
        [json appendFormat:@"{\"id\":%d,\"name\":\"Card %d\",\"cmc\":%d.5,\"reserved\":false,\"colors\":[\"G\"],"
                           "\"set\":{\"code\":\"S%d\",\"name\":\"Set\"},\"reprints\":[]}", i, i, i % 7, i % 30];
    }
    [json appendString:@"]"];
    NSData *data = D(json);
    [self measureBlock:^{ (void)[MTGCard cardsFromData:data error:NULL]; }];
}
@end
