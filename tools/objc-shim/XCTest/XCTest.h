#pragma once
// Stand-in for compile checking only: assertions type-check their arguments.
#import <Foundation/Foundation.h>
@interface XCTestCase : NSObject
- (void)measureBlock:(void (^)(void))block;
@end
#define XCTAssertNil(a, ...) ((void)(a))
#define XCTAssertNotNil(a, ...) ((void)(a))
#define XCTAssertTrue(a, ...) ((void)(a))
#define XCTAssertFalse(a, ...) ((void)(a))
#define XCTAssertEqual(a, b, ...) ((void)((a) == (b)))
#define XCTAssertEqualObjects(a, b, ...) ((void)(a), (void)(b))
