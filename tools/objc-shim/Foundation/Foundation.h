#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <math.h>

#ifndef FOUNDATION_EXPORT
#define FOUNDATION_EXPORT extern
#endif

typedef signed char BOOL;
#ifndef YES
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#endif
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef unsigned short unichar;

#define NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_END
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NS_ERROR_ENUM(_domain, _name) enum _name : NSInteger _name; enum _name : NSInteger
#define NS_SWIFT_NAME(x)
#define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
#define NS_UNAVAILABLE __attribute__((unavailable))
#define NS_NOESCAPE __attribute__((noescape))
typedef struct _NSRange { NSUInteger location, length; } NSRange;
static inline NSRange NSMakeRange(NSUInteger l, NSUInteger n) { NSRange r = {l, n}; return r; }
#define NSUTF8StringEncoding 4
typedef NSUInteger NSStringEncoding;
#ifndef nil
#define nil ((id)0)
#endif
#ifndef Nil
#define Nil ((Class)0)
#endif

#ifdef __OBJC__
#import <objc/runtime.h>

@class NSString; @class NSData; @class NSArray; @class NSDictionary;
@class NSMutableArray; @class NSMutableDictionary; @class NSMutableString;
@class NSNumber; @class NSError; @class NSNull; @class NSValue; @class NSObject;
@class NSCharacterSet; @class NSException;

typedef NSString *NSErrorDomain;
typedef NSString *NSErrorUserInfoKey;
FOUNDATION_EXPORT NSErrorUserInfoKey const NSLocalizedDescriptionKey;
FOUNDATION_EXPORT NSString *NSStringFromClass(Class cls);

@interface NSObject
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
- (void)setValue:(id)value forKey:(NSString *)key;
- (id)valueForKey:(NSString *)key;
+ (BOOL)respondsToSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector;
+ (Class)class;
+ (BOOL)isSubclassOfClass:(Class)aClass;
- (BOOL)isKindOfClass:(Class)aClass;
@end

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)s;
+ (instancetype)stringWithFormat:(NSString *)fmt, ...;
- (instancetype)initWithBytes:(const void *)b length:(NSUInteger)n encoding:(NSStringEncoding)enc;
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)enc;
- (NSString *)stringByAppendingString:(NSString *)s;
- (NSString *)stringByAppendingFormat:(NSString *)fmt, ...;
- (BOOL)hasPrefix:(NSString *)s;
- (instancetype)initWithFormat:(NSString *)fmt arguments:(va_list)args;
- (instancetype)initWithData:(NSData *)d encoding:(NSStringEncoding)enc;
- (NSData *)dataUsingEncoding:(NSStringEncoding)enc;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (BOOL)containsString:(NSString *)s;
@property (readonly) NSUInteger length;
- (unichar)characterAtIndex:(NSUInteger)i;
@property (readonly) const char *UTF8String;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)n;
+ (instancetype)stringWithString:(NSString *)s;
- (void)deleteCharactersInRange:(NSRange)r;
- (void)appendString:(NSString *)s;
- (void)appendFormat:(NSString *)fmt, ...;
@end

@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)b;
+ (NSNumber *)numberWithChar:(char)c;
+ (NSNumber *)numberWithInt:(int)i;
+ (NSNumber *)numberWithLong:(long)l;
+ (NSNumber *)numberWithLongLong:(long long)n;
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)n;
+ (NSNumber *)numberWithFloat:(float)f;
+ (NSNumber *)numberWithDouble:(double)d;
+ (NSNumber *)numberWithInteger:(NSInteger)i;
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)i;
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)i;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)i;
@property (readonly) BOOL boolValue;
@property (readonly) double doubleValue;
@property (readonly) long long longLongValue;
@property (readonly) unsigned long long unsignedLongLongValue;
@property (readonly) const char *objCType;
@end

@interface NSData : NSObject
@property (readonly) NSUInteger length;
@property (readonly) const void *bytes;
+ (instancetype)dataWithBytesNoCopy:(void *)b length:(NSUInteger)n freeWhenDone:(BOOL)f;
@end

@interface NSArray<__covariant ObjectType> : NSObject
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)i;
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id[])objs count:(NSUInteger)n;
- (NSUInteger)countByEnumeratingWithState:(void *)state objects:(id *)buf count:(NSUInteger)len;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id[])objs count:(NSUInteger)n;
+ (instancetype)arrayWithCapacity:(NSUInteger)n;
- (void)addObject:(id)obj;
@end

@interface NSDictionary<__covariant K, __covariant V> : NSObject
+ (instancetype)dictionaryWithObjects:(const id[])objs forKeys:(const id[])keys count:(NSUInteger)cnt;
- (id)objectForKeyedSubscript:(id)key;
@end

@interface NSMutableDictionary<K, V> : NSDictionary<K, V>
+ (instancetype)dictionaryWithCapacity:(NSUInteger)n;
- (void)setObject:(id)obj forKeyedSubscript:(id)key;
@end

@interface NSNull : NSObject
+ (NSNull *)null;
@end

@interface NSValue : NSObject
+ (NSValue *)valueWithPointer:(const void *)p;
@property (readonly) const void *pointerValue;
@end

@interface NSError : NSObject
+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)info;
@property (readonly) NSInteger code;
@property (readonly) NSErrorDomain domain;
@property (readonly) NSDictionary *userInfo;
@property (readonly) NSString *localizedDescription;
@end

FOUNDATION_EXPORT NSString *const NSInvalidArgumentException;
@interface NSException : NSObject
+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)info;
@end

@interface NSJSONSerialization : NSObject
+ (id)JSONObjectWithData:(NSData *)d options:(NSUInteger)o error:(NSError **)e;
@end

@interface NSCharacterSet : NSObject
+ (NSCharacterSet *)uppercaseLetterCharacterSet;
- (BOOL)characterIsMember:(unichar)c;
@end
#endif
