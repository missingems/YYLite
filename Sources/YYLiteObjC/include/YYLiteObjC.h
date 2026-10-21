// YYLiteObjC: Objective-C API over the same patched yyjson reader and the shared C writer core
// (yylite_writer.c) that the Swift YYLite module uses. Apple platforms only.
#if defined(__APPLE__) && defined(__OBJC__)
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain. userInfo carries the same fields as Swift's JSONError.
FOUNDATION_EXPORT NSErrorDomain const YYLJSONErrorDomain;
FOUNDATION_EXPORT NSErrorUserInfoKey const YYLJSONErrorPathKey;          // NSString, e.g. @"$.cards[3].name"
FOUNDATION_EXPORT NSErrorUserInfoKey const YYLJSONErrorExpectedKey;      // NSString, e.g. @"String"
FOUNDATION_EXPORT NSErrorUserInfoKey const YYLJSONErrorFoundKey;         // NSString, e.g. @"missing", @"null", @"number"
FOUNDATION_EXPORT NSErrorUserInfoKey const YYLJSONErrorParseCodeKey;     // NSNumber, yyjson read error code
FOUNDATION_EXPORT NSErrorUserInfoKey const YYLJSONErrorParsePositionKey; // NSNumber, byte offset

typedef NS_ERROR_ENUM(YYLJSONErrorDomain, YYLJSONErrorCode) {
    YYLJSONErrorParse = 1,        ///< invalid JSON
    YYLJSONErrorMissing = 2,      ///< required key missing
    YYLJSONErrorTypeMismatch = 3, ///< present but wrong type (incl. null for a required value)
    YYLJSONErrorNonFinite = 4,    ///< NaN/Infinity written with nonFiniteAsNull == NO
    YYLJSONErrorMemory = 5,
};

typedef NS_ENUM(NSInteger, YYLJSONType) {
    YYLJSONTypeNull, YYLJSONTypeBool, YYLJSONTypeNumber, YYLJSONTypeString, YYLJSONTypeArray, YYLJSONTypeObject,
};

@class YYLJSONValue;

/// Owns a parsed, immutable document. Every YYLJSONValue retains its document, so values stay valid
/// as long as you hold them. Read a document from one thread at a time.
@interface YYLJSONDocument : NSObject
- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (nullable YYLJSONValue *)parse:(NSData *)data error:(NSError **)error;   ///< convenience: document's root
@property (nonatomic, readonly) YYLJSONValue *root;
@end

/// A view of one value in a document. Getters follow these rules:
///  - required getters: missing / null / wrong type → returns 0, NO or nil and sets *error.
///    For scalar getters, check *error (or pass a non-NULL error and test it) to detect failure.
///  - optional getters: missing or null → nil without error; wrong type → nil and *error.
/// Each nested object / element returned is a new small wrapper object (one allocation).
@interface YYLJSONValue : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) YYLJSONDocument *document;
@property (nonatomic, readonly) YYLJSONType type;
@property (nonatomic, readonly) BOOL isNull;
@property (nonatomic, readonly) NSUInteger count;                     ///< elements / members, 0 for scalars
@property (nonatomic, readonly) NSArray<NSString *> *keys;

- (BOOL)containsKey:(NSString *)key;
- (nullable YYLJSONValue *)memberForKey:(NSString *)key;               ///< raw access, nil if missing
- (nullable YYLJSONValue *)elementAtIndex:(NSUInteger)index;

- (NSInteger)integerForKey:(NSString *)key error:(NSError **)error;
- (int64_t)int64ForKey:(NSString *)key error:(NSError **)error;
- (uint64_t)uint64ForKey:(NSString *)key error:(NSError **)error;
- (double)doubleForKey:(NSString *)key error:(NSError **)error;         ///< integers accepted
- (float)floatForKey:(NSString *)key error:(NSError **)error;
- (BOOL)boolForKey:(NSString *)key error:(NSError **)error;
- (nullable NSString *)stringForKey:(NSString *)key error:(NSError **)error;
- (nullable NSString *)optionalStringForKey:(NSString *)key error:(NSError **)error;
- (nullable NSNumber *)optionalNumberForKey:(NSString *)key error:(NSError **)error; ///< number or bool
- (nullable NSArray<NSString *> *)stringsForKey:(NSString *)key error:(NSError **)error;
- (nullable NSArray<NSNumber *> *)numbersForKey:(NSString *)key error:(NSError **)error;
- (nullable YYLJSONValue *)objectForKey:(NSString *)key error:(NSError **)error;
- (nullable YYLJSONValue *)optionalObjectForKey:(NSString *)key error:(NSError **)error;
- (nullable NSArray<YYLJSONValue *> *)objectsForKey:(NSString *)key error:(NSError **)error;
/// Calls block for each object in the array at key, without building an NSArray. Stops at the first NO.
- (BOOL)enumerateObjectsForKey:(NSString *)key error:(NSError **)error
                    usingBlock:(BOOL (NS_NOESCAPE ^)(YYLJSONValue *object, NSUInteger index, NSError **error))block;

// The value itself
- (nullable NSString *)stringValueWithError:(NSError **)error;
- (int64_t)int64ValueWithError:(NSError **)error;
- (double)doubleValueWithError:(NSError **)error;
- (BOOL)boolValueWithError:(NSError **)error;
- (nullable NSArray<YYLJSONValue *> *)elementsWithError:(NSError **)error;
@end

typedef NS_ENUM(NSInteger, YYLJSONNilStrategy) { YYLJSONNilOmit = 0, YYLJSONNilWriteNull = 1 };

/// Streaming writer over the shared C core. Keyed setters are for inside -object:, add… for arrays.
@interface YYLJSONWriter : NSObject
+ (nullable NSData *)encode:(void (NS_NOESCAPE ^)(YYLJSONWriter *w))block error:(NSError **)error;
+ (nullable NSData *)encodePretty:(BOOL)pretty nilStrategy:(YYLJSONNilStrategy)nilStrategy
                            block:(void (NS_NOESCAPE ^)(YYLJSONWriter *w))block error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic) YYLJSONNilStrategy nilStrategy;   ///< for nil strings/numbers/arrays/objects; default omit
@property (nonatomic) BOOL nonFiniteAsNull;             ///< NO (default): NaN/Inf makes encode fail

- (void)key:(NSString *)key;
- (void)object:(void (NS_NOESCAPE ^)(void))body;
- (void)object:(void (NS_NOESCAPE ^)(void))body key:(NSString *)key;
- (void)array:(void (NS_NOESCAPE ^)(void))body;
- (void)array:(void (NS_NOESCAPE ^)(void))body key:(NSString *)key;

- (void)setInteger:(NSInteger)v forKey:(NSString *)key;
- (void)setInt64:(int64_t)v forKey:(NSString *)key;
- (void)setUInt64:(uint64_t)v forKey:(NSString *)key;
- (void)setDouble:(double)v forKey:(NSString *)key;
- (void)setFloat:(float)v forKey:(NSString *)key;
- (void)setBool:(BOOL)v forKey:(NSString *)key;
- (void)setString:(nullable NSString *)v forKey:(NSString *)key;        ///< nil → nilStrategy
- (void)setNumber:(nullable NSNumber *)v forKey:(NSString *)key;        ///< nil → nilStrategy
- (void)setStrings:(nullable NSArray<NSString *> *)v forKey:(NSString *)key;
- (void)setNullForKey:(NSString *)key;
- (void)setNilForKey:(NSString *)key;                                  ///< null or nothing, per nilStrategy

- (void)addInteger:(NSInteger)v;
- (void)addDouble:(double)v;
- (void)addBool:(BOOL)v;
- (void)addString:(NSString *)v;
- (void)addNumber:(NSNumber *)v;
- (void)addNull;
@end

NS_ASSUME_NONNULL_END
#endif
