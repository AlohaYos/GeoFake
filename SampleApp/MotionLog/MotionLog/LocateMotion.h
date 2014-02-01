//
//  LocateMotion.h
//  MotionLog
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>

@interface LocateMotion : NSObject

@property (nonatomic, strong)	CLLocation		 *location;
@property (nonatomic, strong)	CMMotionActivity *activity;

- (id)initWithLocation:(CLLocation*)location andActivity:(CMMotionActivity*)activity;
- (BOOL)isSameActivity:(LocateMotion*)anotherLocateMotion;

@end
