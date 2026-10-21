#if defined(__APPLE__)
#import "YYLiteObjC.h"
#include "yyjson.h"
#include "yylite_writer.h"

#if !__has_feature(objc_arc)
#error "YYLiteObjC requires ARC"
#endif

NSErrorDomain const YYLJSONErrorDomain = @"YYLJSONErrorDomain";
NSErrorUserInfoKey const YYLJSONErrorPathKey = @"path";
NSErrorUserInfoKey const YYLJSONErrorExpectedKey = @"expected";
NSErrorUserInfoKey const YYLJSONErrorFoundKey = @"found";
NSErrorUserInfoKey const YYLJSONErrorParseCodeKey = @"parseCode";
NSErrorUserInfoKey const YYLJSONErrorParsePositionKey = @"parsePosition";

static NSError *YYLError(NSInteger code, NSString *path, NSString *expected, NSString *found) {
    NSString *desc = [NSString stringWithFormat:@"%@: expected %@, found %@", path, expected, found];
    return [NSError errorWithDomain:YYLJSONErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey: desc, YYLJSONErrorPathKey: path,
        YYLJSONErrorExpectedKey: expected, YYLJSONErrorFoundKey: found }];
}

static NSString *YYLTypeName(yyjson_val *v) {
    if (!v) return @"missing";
    switch (yyjson_get_type(v)) {
        case YYJSON_TYPE_NULL: return @"null";
        case YYJSON_TYPE_BOOL: return @"bool";
        case YYJSON_TYPE_NUM:  return @"number";
        case YYJSON_TYPE_STR:  return @"string";
        case YYJSON_TYPE_ARR:  return @"array";
        default:               return @"object";
    }
}

/* Path of `target` from the root; only computed when an error is reported. */
static BOOL YYLWalk(yyjson_val *v, yyjson_val *target, NSMutableString *path) {
    if (v == target) return YES;
    NSUInteger mark = path.length;
    if (yyjson_is_obj(v)) {
        yyjson_obj_iter it = yyjson_obj_iter_with(v);
        yyjson_val *k;
        while ((k = yyjson_obj_iter_next(&it))) {
            [path appendString:@"."];
            [path appendString:[[NSString alloc] initWithBytes:yyjson_get_str(k) length:yyjson_get_len(k)
                                                     encoding:NSUTF8StringEncoding]];
            if (YYLWalk(yyjson_obj_iter_get_val(k), target, path)) return YES;
            [path deleteCharactersInRange:NSMakeRange(mark, path.length - mark)];
        }
    } else if (yyjson_is_arr(v)) {
        yyjson_arr_iter it = yyjson_arr_iter_with(v);
        yyjson_val *e; size_t i = 0;
        while ((e = yyjson_arr_iter_next(&it))) {
            [path appendFormat:@"[%zu]", i++];
            if (YYLWalk(e, target, path)) return YES;
            [path deleteCharactersInRange:NSMakeRange(mark, path.length - mark)];
        }
    }
    return NO;
}

#pragma mark - Document

@interface YYLJSONValue ()
- (instancetype)initWithVal:(yyjson_val *)val doc:(YYLJSONDocument *)doc;
@end

@interface YYLJSONDocument ()
- (NSString *)pathTo:(yyjson_val *)target;
@end

@implementation YYLJSONDocument {
@public
    yyjson_doc *_doc;
}

- (instancetype)init { @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"use initWithData:error:" userInfo:nil]; }

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if ((self = [super init])) {
        yyjson_read_err err;
        /* yyjson writes to the input only with YYJSON_READ_INSITU, which is not used. */
        _doc = yyjson_read_opts((char *)data.bytes, data.length, 0, NULL, &err);
        if (!_doc) {
            if (error) *error = [NSError errorWithDomain:YYLJSONErrorDomain code:YYLJSONErrorParse userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"$: invalid JSON (yyjson error %u at byte %zu)", err.code, err.pos],
                YYLJSONErrorPathKey: @"$", YYLJSONErrorExpectedKey: @"valid JSON", YYLJSONErrorFoundKey: @"parse error",
                YYLJSONErrorParseCodeKey: @(err.code), YYLJSONErrorParsePositionKey: @(err.pos) }];
            return nil;
        }
    }
    return self;
}

+ (nullable YYLJSONValue *)parse:(NSData *)data error:(NSError **)error {
    return [[YYLJSONDocument alloc] initWithData:data error:error].root;
}

- (void)dealloc { yyjson_doc_free(_doc); }

- (YYLJSONValue *)root { return [[YYLJSONValue alloc] initWithVal:yyjson_doc_get_root(_doc) doc:self]; }

- (NSString *)pathTo:(yyjson_val *)target {
    NSMutableString *p = [NSMutableString stringWithString:@"$"];
    return YYLWalk(yyjson_doc_get_root(_doc), target, p) ? p : @"$?";
}
@end

#pragma mark - Value

@implementation YYLJSONValue {
    yyjson_val *_val;
    YYLJSONDocument *_doc;   /* strong: keeps the yyjson memory alive */
}

- (instancetype)init { @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"values come from YYLJSONDocument" userInfo:nil]; }
- (instancetype)initWithVal:(yyjson_val *)val doc:(YYLJSONDocument *)doc {
    if ((self = [super init])) { _val = val; _doc = doc; }
    return self;
}
- (YYLJSONDocument *)document { return _doc; }

static inline yyjson_val *YYLGet(yyjson_val *obj, NSString *key) {
    const char *k = key.UTF8String;
    return yyjson_obj_getn(obj, k, strlen(k));
}

/* Failure for `key` in self: missing / self not an object / wrong type. Returns NO for convenience. */
- (BOOL)fail:(NSError **)error key:(NSString *)key value:(yyjson_val *)v expected:(NSString *)expected {
    if (!error) return NO;
    if (!v && !yyjson_is_obj(_val)) {
        *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"object", YYLTypeName(_val));
    } else if (!v) {
        *error = YYLError(YYLJSONErrorMissing, [[_doc pathTo:_val] stringByAppendingFormat:@".%@", key], expected, @"missing");
    } else {
        NSString *found = YYLTypeName(v);
        if (yyjson_is_num(v) && [expected hasPrefix:@"Int"]) found = yyjson_is_real(v) ? @"non-integer number" : @"out-of-range number";
        *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:v], expected, found);
    }
    return NO;
}

- (YYLJSONType)type {
    switch (yyjson_get_type(_val)) {
        case YYJSON_TYPE_BOOL: return YYLJSONTypeBool;
        case YYJSON_TYPE_NUM: return YYLJSONTypeNumber;
        case YYJSON_TYPE_STR: return YYLJSONTypeString;
        case YYJSON_TYPE_ARR: return YYLJSONTypeArray;
        case YYJSON_TYPE_OBJ: return YYLJSONTypeObject;
        default: return YYLJSONTypeNull;
    }
}
- (BOOL)isNull { return yyjson_is_null(_val); }
- (NSUInteger)count { return yyjson_is_arr(_val) ? yyjson_arr_size(_val) : yyjson_obj_size(_val); }
- (NSArray<NSString *> *)keys {
    NSMutableArray *out = [NSMutableArray array];
    yyjson_obj_iter it;
    if (!yyjson_obj_iter_init(_val, &it)) return out;
    yyjson_val *k;
    while ((k = yyjson_obj_iter_next(&it)))
        [out addObject:[[NSString alloc] initWithBytes:yyjson_get_str(k) length:yyjson_get_len(k) encoding:NSUTF8StringEncoding]];
    return out;
}
- (BOOL)containsKey:(NSString *)key { return YYLGet(_val, key) != NULL; }
- (nullable YYLJSONValue *)memberForKey:(NSString *)key {
    yyjson_val *v = YYLGet(_val, key);
    return v ? [[YYLJSONValue alloc] initWithVal:v doc:_doc] : nil;
}
- (nullable YYLJSONValue *)elementAtIndex:(NSUInteger)index {
    yyjson_val *v = yyjson_arr_get(_val, index);
    return v ? [[YYLJSONValue alloc] initWithVal:v doc:_doc] : nil;
}

static inline BOOL YYLInt64(yyjson_val *v, int64_t *out) {
    if (yyjson_is_sint(v)) { *out = yyjson_get_sint(v); return YES; }
    if (yyjson_is_uint(v) && yyjson_get_uint(v) <= INT64_MAX) { *out = (int64_t)yyjson_get_uint(v); return YES; }
    return NO;
}
static inline NSString *YYLString(yyjson_val *v) {
    return [[NSString alloc] initWithBytes:yyjson_get_str(v) length:yyjson_get_len(v) encoding:NSUTF8StringEncoding];
}

- (int64_t)int64ForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key); int64_t x;
    if (v && YYLInt64(v, &x)) return x;
    [self fail:error key:key value:v expected:@"Int"]; return 0;
}
- (NSInteger)integerForKey:(NSString *)key error:(NSError **)error { return (NSInteger)[self int64ForKey:key error:error]; }
- (uint64_t)uint64ForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_uint(v)) return yyjson_get_uint(v);
    if (v && yyjson_is_sint(v) && yyjson_get_sint(v) >= 0) return (uint64_t)yyjson_get_sint(v);
    [self fail:error key:key value:v expected:@"UInt"]; return 0;
}
- (double)doubleForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_num(v)) return yyjson_get_num(v);
    [self fail:error key:key value:v expected:@"Double"]; return 0;
}
- (float)floatForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_num(v)) return (float)yyjson_get_num(v);
    [self fail:error key:key value:v expected:@"Float"]; return 0;
}
- (BOOL)boolForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_bool(v)) return yyjson_get_bool(v);
    [self fail:error key:key value:v expected:@"Bool"]; return NO;
}
- (nullable NSString *)stringForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_str(v)) return YYLString(v);
    [self fail:error key:key value:v expected:@"String"]; return nil;
}
- (nullable NSString *)optionalStringForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (!v || yyjson_is_null(v)) return nil;
    if (yyjson_is_str(v)) return YYLString(v);
    [self fail:error key:key value:v expected:@"String"]; return nil;
}
static NSNumber *YYLNumber(yyjson_val *v) {
    if (yyjson_is_bool(v)) return yyjson_get_bool(v) ? @YES : @NO;
    if (yyjson_is_sint(v)) return @(yyjson_get_sint(v));
    if (yyjson_is_uint(v)) return @(yyjson_get_uint(v));
    if (yyjson_is_real(v)) return @(yyjson_get_real(v));
    return nil;
}
- (nullable NSNumber *)optionalNumberForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (!v || yyjson_is_null(v)) return nil;
    NSNumber *n = YYLNumber(v);
    if (!n) [self fail:error key:key value:v expected:@"Number"];
    return n;
}
- (nullable NSArray<NSString *> *)stringsForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *a = YYLGet(_val, key);
    if (!a || !yyjson_is_arr(a)) { [self fail:error key:key value:a expected:@"[String]"]; return nil; }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:yyjson_arr_size(a)];
    yyjson_arr_iter it = yyjson_arr_iter_with(a); yyjson_val *e;
    while ((e = yyjson_arr_iter_next(&it))) {
        if (!yyjson_is_str(e)) { [self fail:error key:key value:e expected:@"String"]; return nil; }
        [out addObject:YYLString(e)];
    }
    return out;
}
- (nullable NSArray<NSNumber *> *)numbersForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *a = YYLGet(_val, key);
    if (!a || !yyjson_is_arr(a)) { [self fail:error key:key value:a expected:@"[Number]"]; return nil; }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:yyjson_arr_size(a)];
    yyjson_arr_iter it = yyjson_arr_iter_with(a); yyjson_val *e;
    while ((e = yyjson_arr_iter_next(&it))) {
        NSNumber *n = YYLNumber(e);
        if (!n) { [self fail:error key:key value:e expected:@"Number"]; return nil; }
        [out addObject:n];
    }
    return out;
}
- (nullable YYLJSONValue *)objectForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (v && yyjson_is_obj(v)) return [[YYLJSONValue alloc] initWithVal:v doc:_doc];
    [self fail:error key:key value:v expected:@"object"]; return nil;
}
- (nullable YYLJSONValue *)optionalObjectForKey:(NSString *)key error:(NSError **)error {
    yyjson_val *v = YYLGet(_val, key);
    if (!v || yyjson_is_null(v)) return nil;
    if (yyjson_is_obj(v)) return [[YYLJSONValue alloc] initWithVal:v doc:_doc];
    [self fail:error key:key value:v expected:@"object"]; return nil;
}
- (BOOL)enumerateObjectsForKey:(NSString *)key error:(NSError **)error
                    usingBlock:(BOOL (NS_NOESCAPE ^)(YYLJSONValue *, NSUInteger, NSError **))block {
    yyjson_val *a = YYLGet(_val, key);
    if (!a || !yyjson_is_arr(a)) return [self fail:error key:key value:a expected:@"[object]"];
    yyjson_arr_iter it = yyjson_arr_iter_with(a); yyjson_val *e; NSUInteger i = 0;
    while ((e = yyjson_arr_iter_next(&it))) {
        if (!yyjson_is_obj(e)) return [self fail:error key:key value:e expected:@"object"];
        if (!block([[YYLJSONValue alloc] initWithVal:e doc:_doc], i++, error)) return NO;
    }
    return YES;
}
- (nullable NSArray<YYLJSONValue *> *)objectsForKey:(NSString *)key error:(NSError **)error {
    NSMutableArray *out = [NSMutableArray array];
    BOOL ok = [self enumerateObjectsForKey:key error:error usingBlock:^BOOL(YYLJSONValue *o, NSUInteger i, NSError **e) {
        [out addObject:o]; return YES;
    }];
    return ok ? out : nil;
}

- (nullable NSString *)stringValueWithError:(NSError **)error {
    if (yyjson_is_str(_val)) return YYLString(_val);
    if (error) *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"String", YYLTypeName(_val));
    return nil;
}
- (int64_t)int64ValueWithError:(NSError **)error {
    int64_t x;
    if (YYLInt64(_val, &x)) return x;
    if (error) *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"Int", YYLTypeName(_val));
    return 0;
}
- (double)doubleValueWithError:(NSError **)error {
    if (yyjson_is_num(_val)) return yyjson_get_num(_val);
    if (error) *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"Double", YYLTypeName(_val));
    return 0;
}
- (BOOL)boolValueWithError:(NSError **)error {
    if (yyjson_is_bool(_val)) return yyjson_get_bool(_val);
    if (error) *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"Bool", YYLTypeName(_val));
    return NO;
}
- (nullable NSArray<YYLJSONValue *> *)elementsWithError:(NSError **)error {
    if (!yyjson_is_arr(_val)) {
        if (error) *error = YYLError(YYLJSONErrorTypeMismatch, [_doc pathTo:_val], @"array", YYLTypeName(_val));
        return nil;
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:yyjson_arr_size(_val)];
    yyjson_arr_iter it = yyjson_arr_iter_with(_val); yyjson_val *e;
    while ((e = yyjson_arr_iter_next(&it))) [out addObject:[[YYLJSONValue alloc] initWithVal:e doc:_doc]];
    return out;
}
@end

#pragma mark - Writer

@implementation YYLJSONWriter {
    yylite_writer _w;
    NSError *_error;
}

- (instancetype)init { @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"use +encode:error:" userInfo:nil]; }
- (instancetype)initPretty:(BOOL)pretty {
    if ((self = [super init])) {
        if (!yylite_w_init(&_w, 4096, pretty)) return nil;
    }
    return self;
}
- (void)dealloc { yylite_w_free(&_w); }

+ (nullable NSData *)encode:(void (NS_NOESCAPE ^)(YYLJSONWriter *))block error:(NSError **)error {
    return [self encodePretty:NO nilStrategy:YYLJSONNilOmit block:block error:error];
}
+ (nullable NSData *)encodePretty:(BOOL)pretty nilStrategy:(YYLJSONNilStrategy)nilStrategy
                            block:(void (NS_NOESCAPE ^)(YYLJSONWriter *))block error:(NSError **)error {
    YYLJSONWriter *w = [[YYLJSONWriter alloc] initPretty:pretty];
    if (!w) { if (error) *error = YYLError(YYLJSONErrorMemory, @"$", @"memory", @"allocation failure"); return nil; }
    w.nilStrategy = nilStrategy;
    block(w);
    if (w->_error) { if (error) *error = w->_error; return nil; }
    if (w->_w.failed) { if (error) *error = YYLError(YYLJSONErrorMemory, @"$", @"memory", @"allocation failure"); return nil; }
    size_t len = 0;
    uint8_t *bytes = yylite_w_take(&w->_w, &len);
    return [NSData dataWithBytesNoCopy:bytes length:len freeWhenDone:YES];   /* no copy */
}

static inline void YYLKey(yylite_writer *w, NSString *key) {
    const char *k = key.UTF8String;
    yylite_w_key(w, k, strlen(k));
}
static inline void YYLStr(yylite_writer *w, NSString *s) {
    yylite_w_string(w, s.UTF8String, [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

- (void)key:(NSString *)key { YYLKey(&_w, key); }
- (void)object:(void (NS_NOESCAPE ^)(void))body { yylite_w_begin(&_w, '{'); body(); yylite_w_end(&_w, '}'); }
- (void)object:(void (NS_NOESCAPE ^)(void))body key:(NSString *)key { YYLKey(&_w, key); [self object:body]; }
- (void)array:(void (NS_NOESCAPE ^)(void))body { yylite_w_begin(&_w, '['); body(); yylite_w_end(&_w, ']'); }
- (void)array:(void (NS_NOESCAPE ^)(void))body key:(NSString *)key { YYLKey(&_w, key); [self array:body]; }

- (void)nonFinite:(double)v key:(NSString *)key {
    if (!_nonFiniteAsNull && !_error)
        _error = YYLError(YYLJSONErrorNonFinite, key ? [@"$…." stringByAppendingString:key] : @"$…",
                          @"finite number", isnan(v) ? @"NaN" : @"Infinity");
}

- (void)setInteger:(NSInteger)v forKey:(NSString *)key { YYLKey(&_w, key); yylite_w_int(&_w, v); }
- (void)setInt64:(int64_t)v forKey:(NSString *)key { YYLKey(&_w, key); yylite_w_int(&_w, v); }
- (void)setUInt64:(uint64_t)v forKey:(NSString *)key { YYLKey(&_w, key); yylite_w_uint(&_w, v); }
- (void)setDouble:(double)v forKey:(NSString *)key {
    YYLKey(&_w, key);
    if (!yylite_w_double(&_w, v)) [self nonFinite:v key:key];
}
- (void)setFloat:(float)v forKey:(NSString *)key {
    YYLKey(&_w, key);
    if (!yylite_w_float(&_w, v)) [self nonFinite:v key:key];
}
- (void)setBool:(BOOL)v forKey:(NSString *)key { YYLKey(&_w, key); yylite_w_bool(&_w, v); }
- (void)setString:(nullable NSString *)v forKey:(NSString *)key {
    if (!v) { [self setNilForKey:key]; return; }
    YYLKey(&_w, key); YYLStr(&_w, v);
}
- (void)setNumber:(nullable NSNumber *)v forKey:(NSString *)key {
    if (!v) { [self setNilForKey:key]; return; }
    YYLKey(&_w, key); [self addNumber:v];
}
- (void)setStrings:(nullable NSArray<NSString *> *)v forKey:(NSString *)key {
    if (!v) { [self setNilForKey:key]; return; }
    YYLKey(&_w, key);
    yylite_w_begin(&_w, '[');
    for (NSString *s in v) YYLStr(&_w, s);
    yylite_w_end(&_w, ']');
}
- (void)setNullForKey:(NSString *)key { YYLKey(&_w, key); yylite_w_null(&_w); }
- (void)setNilForKey:(NSString *)key { if (_nilStrategy == YYLJSONNilWriteNull) [self setNullForKey:key]; }

- (void)addInteger:(NSInteger)v { yylite_w_int(&_w, v); }
- (void)addDouble:(double)v { if (!yylite_w_double(&_w, v)) [self nonFinite:v key:nil]; }
- (void)addBool:(BOOL)v { yylite_w_bool(&_w, v); }
- (void)addString:(NSString *)v { YYLStr(&_w, v); }
- (void)addNull { yylite_w_null(&_w); }
- (void)addNumber:(NSNumber *)v {
    if (v == (id)@YES || v == (id)@NO) { yylite_w_bool(&_w, v.boolValue); return; }   /* boolean singletons */
    const char *t = v.objCType;
    if (t[0] == 'f' || t[0] == 'd') { [self addDouble:v.doubleValue]; return; }
    if (t[0] == 'Q' || t[0] == 'L' || t[0] == 'I' || t[0] == 'S' || t[0] == 'C') { yylite_w_uint(&_w, v.unsignedLongLongValue); return; }
    yylite_w_int(&_w, v.longLongValue);
}
@end
#endif /* __APPLE__ */
