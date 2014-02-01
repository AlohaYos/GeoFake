//
//  LocateMotion.m
//  MotionLog
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "LocateMotion.h"

@implementation LocateMotion

- (id)initWithLocation:(CLLocation*)location andActivity:(CMMotionActivity*)activity {

	_location = location;
	_activity = activity;

	return self;
}

- (BOOL)isSameActivity:(LocateMotion*)lm {
	if(
	   (_activity.stationary == lm.activity.stationary) &&
	   (_activity.walking == lm.activity.walking) &&
	   (_activity.running == lm.activity.running) &&
	   (_activity.automotive == lm.activity.automotive) &&
	   (_activity.unknown == lm.activity.unknown)
	   ) {
		return YES;
	}
	
	return NO;
}

@end

