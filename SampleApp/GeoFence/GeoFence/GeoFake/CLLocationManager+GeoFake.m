//
//  CLLocationManager+GeoFake.m
//
//  Copyright (c) 2014 Yoshiyuki Hashimoto. All rights reserved.
//

#import "GeoFakeCommon.h"

@implementation CLLocationManager (GeoFake)

- (void)updateFakedLocation {
	CLLocation *locationToSend = [GFLocationProvider sharedProvider].location;
	if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]){
		[self.delegate locationManager:self didUpdateLocations:@[locationToSend]];
	}

	CLHeading *fakeHeading = [GFLocationProvider sharedProvider].heading;
	if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateHeading:)]){
		[self.delegate locationManager:self didUpdateHeading:(CLHeading *)fakeHeading];
	}
}


@end

