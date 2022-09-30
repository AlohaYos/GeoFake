//
//  GeoFakeCommon.h
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "GeoFake.h"

@interface CLFakeHeading : CLHeading
@property(readwrite, nonatomic) CLLocationDirection magneticHeading;
@property(readwrite, nonatomic) CLLocationDirection trueHeading;
@property(readwrite, nonatomic) CLLocationDirection headingAccuracy;
@property(readwrite, nonatomic) CLHeadingComponentValue x;
@property(readwrite, nonatomic) CLHeadingComponentValue y;
@property(readwrite, nonatomic) CLHeadingComponentValue z;
@property(readwrite, nonatomic) NSDate *timestamp;
@end

@interface GFLocationProvider : NSObject
@property (nonatomic, strong) CLLocation *location;
@property (nonatomic, strong) CLHeading *heading;
@property (nonatomic, strong) CLHeading *throttledHeading;
@property (nonatomic, strong) CLHeading *currentVehicleHeading;
+ (GFLocationProvider *)sharedProvider;
//- (CLHeading*)currentVehicleHeading;
@end

@interface CMFakeMotionActivity : CMMotionActivity
@property(readwrite, nonatomic) BOOL stationary;
@property(readwrite, nonatomic) BOOL walking;
@property(readwrite, nonatomic) BOOL running;
@property(readwrite, nonatomic) BOOL automotive;
@property(readwrite, nonatomic) BOOL unknown;
@property(readwrite, nonatomic) CMMotionActivityConfidence confidence;
@property(readwrite, nonatomic) NSDate *startDate;
@end

@interface CLLocationManager (GeoFake)
- (void)updateFakedLocation;
@end

@interface MKMapView (GeoFake)
- (void)updateFakedLocation;
@end

