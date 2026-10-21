#import "MTGCard.h"

// Scalar getters return 0/NO on failure, so test the error after each call.
#define YYL_CHECK(e) do { if (e) { if (error) *error = (e); return nil; } } while (0)

@implementation MTGSet
- (nullable instancetype)initWithJSON:(YYLJSONValue *)json error:(NSError **)error {
    if (!(self = [super init])) return nil;
    NSError *e = nil;
    _code = [json stringForKey:@"code" error:&e]; YYL_CHECK(e);
    _name = [json stringForKey:@"name" error:&e]; YYL_CHECK(e);
    return self;
}
- (void)encodeWithWriter:(YYLJSONWriter *)w {
    [w object:^{
        [w setString:self.code forKey:@"code"];
        [w setString:self.name forKey:@"name"];
    }];
}
@end

@implementation MTGCard
- (nullable instancetype)initWithJSON:(YYLJSONValue *)json error:(NSError **)error {
    if (!(self = [super init])) return nil;
    NSError *e = nil;
    _cardID = [json int64ForKey:@"id" error:&e];                       YYL_CHECK(e);
    _name = [json stringForKey:@"name" error:&e];                      YYL_CHECK(e);
    _cmc = [json doubleForKey:@"cmc" error:&e];                        YYL_CHECK(e);
    _reserved = [json boolForKey:@"reserved" error:&e];                YYL_CHECK(e);
    _flavorText = [json optionalStringForKey:@"flavor_text" error:&e]; YYL_CHECK(e);  // missing/null → nil
    _power = [json optionalNumberForKey:@"power" error:&e];            YYL_CHECK(e);
    _colors = [json stringsForKey:@"colors" error:&e];                 YYL_CHECK(e);
    YYLJSONValue *set = [json objectForKey:@"set" error:&e];           YYL_CHECK(e);
    _set = [[MTGSet alloc] initWithJSON:set error:&e];                 YYL_CHECK(e);
    NSMutableArray *reprints = [NSMutableArray array];
    [json enumerateObjectsForKey:@"reprints" error:&e usingBlock:^BOOL(YYLJSONValue *o, NSUInteger i, NSError **err) {
        MTGSet *s = [[MTGSet alloc] initWithJSON:o error:err];
        if (s) [reprints addObject:s];
        return s != nil;
    }];
    YYL_CHECK(e);
    _reprints = reprints;
    return self;
}

- (void)encodeWithWriter:(YYLJSONWriter *)w {
    [w object:^{
        [w setInt64:self.cardID forKey:@"id"];
        [w setString:self.name forKey:@"name"];
        [w setDouble:self.cmc forKey:@"cmc"];
        [w setBool:self.reserved forKey:@"reserved"];
        [w setString:self.flavorText forKey:@"flavor_text"];   // nil → omitted (default nilStrategy)
        [w setNumber:self.power forKey:@"power"];
        [w setStrings:self.colors forKey:@"colors"];
        [w key:@"set"]; [self.set encodeWithWriter:w];
        [w array:^{ for (MTGSet *s in self.reprints) [s encodeWithWriter:w]; } key:@"reprints"];
    }];
}

+ (nullable NSArray<MTGCard *> *)cardsFromData:(NSData *)data error:(NSError **)error {
    YYLJSONValue *root = [YYLJSONDocument parse:data error:error];
    NSArray<YYLJSONValue *> *items = [root elementsWithError:error];
    if (!items) return nil;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
    for (YYLJSONValue *item in items) {
        MTGCard *c = [[MTGCard alloc] initWithJSON:item error:error];
        if (!c) return nil;
        [out addObject:c];
    }
    return out;
}

+ (nullable NSData *)dataForCards:(NSArray<MTGCard *> *)cards error:(NSError **)error {
    return [YYLJSONWriter encode:^(YYLJSONWriter *w) {
        [w array:^{ for (MTGCard *c in cards) [c encodeWithWriter:w]; }];
    } error:error];
}
@end
