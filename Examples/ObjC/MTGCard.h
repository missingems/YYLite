#import <Foundation/Foundation.h>
#import "YYLiteObjC.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTGSet : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
- (nullable instancetype)initWithJSON:(YYLJSONValue *)json error:(NSError **)error;
- (void)encodeWithWriter:(YYLJSONWriter *)w;
@end

@interface MTGCard : NSObject
@property (nonatomic) int64_t cardID;                  // "id"
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double cmc;
@property (nonatomic) BOOL reserved;
@property (nonatomic, copy, nullable) NSString *flavorText;   // "flavor_text", optional
@property (nonatomic, nullable) NSNumber *power;              // optional number
@property (nonatomic, copy) NSArray<NSString *> *colors;
@property (nonatomic) MTGSet *set;
@property (nonatomic, copy) NSArray<MTGSet *> *reprints;

- (nullable instancetype)initWithJSON:(YYLJSONValue *)json error:(NSError **)error;
- (void)encodeWithWriter:(YYLJSONWriter *)w;

+ (nullable NSArray<MTGCard *> *)cardsFromData:(NSData *)data error:(NSError **)error;  // top-level array
+ (nullable NSData *)dataForCards:(NSArray<MTGCard *> *)cards error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
