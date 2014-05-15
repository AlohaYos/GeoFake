//
//  GeoFake.h
//
//  Copyright (c) 2014 Yoshiyuki Hashimoto. All rights reserved.
//
/*
 
 To implement GeoFake feature, only you have to do is:
 
  1. add GeoFake library to your project
 
  2. import header file
 
		#import "GeoFake.h"
 
  3. initialize location update

		#ifdef	GEO_FAKE
			[[GeoFake sharedFake] setLocationManager:_locationManager mapView:_mapView];
			[[GeoFake sharedFake] startUpdatingLocation];
			[[GeoFake sharedFake] startUpdatingHeading];
		#else
			[_locationManager startUpdatingLocation];
			[_locationManager startUpdatingHeading];
		#endif

  4. initialize motion update (if needed)

		void (^motionHandler)(CMMotionActivity *activity) = ^void(CMMotionActivity *activity){
				_motionActivity = activity;		// whatever you need to do
		};

		#ifdef	GEO_FAKE
			[[GeoFake sharedFake] startActivityUpdatesWithHandler:motionHandler];
		#else
			if([CMMotionActivityManager isActivityAvailable]) {
				_activityManager = [[CMMotionActivityManager alloc]init];
				[_activityManager startActivityUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:motionHandler];
			}
		#endif
 
  5. build and run !

 */

#ifdef DEBUG
  #define GEO_FAKE	1
#endif

#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <MapKit/MapKit.h>

@interface GeoFake : NSObject <MCAdvertiserAssistantDelegate>
+ (GeoFake *)sharedFake;
- (void)setLocationManager:(CLLocationManager*)locMan mapView:(MKMapView*)mapView;
- (void)startUpdatingLocation;
- (void)stopUpdatingLocation;
- (void)startUpdatingHeading;
- (void)stopUpdatingHeading;
- (void)startMonitoringForRegion:(CLRegion *)region;
- (void)stopMonitoringForRegion:(CLRegion *)region;
- (NSSet*)monitoredRegions;
- (void)requestStateForRegion:(CLRegion *)region;

- (void)startActivityUpdatesWithHandler:(CMMotionActivityHandler)handler;
- (void)stopActivityUpdates;
@end

