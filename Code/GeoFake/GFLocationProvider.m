//
//  GFLocationProvider.m
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "GeoFakeCommon.h"

@implementation GFLocationProvider

@synthesize location = _location;
@synthesize currentVehicleHeading = _currentVehicleHeading;

+ (GFLocationProvider *)sharedProvider {
    static GFLocationProvider *sharedProvider = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedProvider = [[self alloc] init];
        sharedProvider.location = [[CLLocation alloc]initWithLatitude:0 longitude:0];
    });
    return sharedProvider;
}

- (CLLocation *)lastLocation {
    return _location;
}

- (int)lastLocationSource {
    return 0;
}

- (int)locationSource {
    return 0;
}

- (double)expectedGpsUpdateInterval {
    return 5;
}

- (BOOL)hasLocation {
    return YES;
}

- (BOOL)isHeadingServicesAvailable {
    return YES;
}

//- (CLHeading*)currentVehicleHeading {
//    return _currentVehicleHeading;
//}

@end
