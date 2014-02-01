//
//  MotionLogViewController.m
//  MotionLog
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import <CoreMotion/CoreMotion.h>
#import <MapKit/MapKit.h>
#import <GeoFake/GeoFake.h>

#import "MotionLogViewController.h"
#import "LocateMotion.h"

#pragma mark - ColorPolyline class

@interface ColorPolyline : MKPolyline
@property (strong, nonatomic) UIColor	*drawColor;
@end

@implementation ColorPolyline
@end


#pragma mark - MotionLogViewController

@interface MotionLogViewController ()
@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@end

@implementation MotionLogViewController {
	CLLocationManager		*_locationManager;
	NSMutableArray			*_locationItems;
	CMMotionActivityManager *_activityManager;
	CMMotionActivity		*_motionActivity;
	BOOL					_deferredLocationUpdates;
	NSString				*_lastAnnotation;
}

- (void)viewDidLoad {
    [super viewDidLoad];

	_locationItems = [NSMutableArray array];
	_motionActivity = nil;
	_deferredLocationUpdates = NO;
	_lastAnnotation = @"";
	
	_locationManager = [[CLLocationManager alloc] init];
	_locationManager.delegate = self;
	_locationManager.activityType = CLActivityTypeAutomotiveNavigation;
	_locationManager.distanceFilter = kCLDistanceFilterNone;
	_locationManager.desiredAccuracy = kCLLocationAccuracyBest;

#ifdef	GEO_FAKE
	[[GeoFake sharedFake] setLocationManager:_locationManager mapView:_mapView];
	[[GeoFake sharedFake] startUpdatingLocation];
	[[GeoFake sharedFake] startUpdatingHeading];
#else
	[_locationManager startUpdatingLocation];
#endif

	[self startGettingMotionActivity];
}

- (void)viewDidAppear:(BOOL)animated {
	[_mapView setUserTrackingMode:MKUserTrackingModeFollow animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	if([CMMotionActivityManager isActivityAvailable]) {
		[self stopGettingMotionActivity];
	}
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Location Job

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
	
	for(CLLocation *loc in locations) {
		LocateMotion *lm = [[LocateMotion alloc] initWithLocation:loc andActivity:_motionActivity];
		if(_locationItems.count > 1) {
			LocateMotion *lastLM = [_locationItems lastObject];
			if(![lastLM isSameActivity:lm]) {
				[self drawActivity];
			}
		}
		[_locationItems addObject:lm];
	}

	if(!_deferredLocationUpdates) {
		CLLocationDistance	distance = 100.0;
		NSTimeInterval		time = 30.0;
		[_locationManager allowDeferredLocationUpdatesUntilTraveled:distance timeout:time];
		_deferredLocationUpdates = YES;
	}
}

-(void)locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {

	_deferredLocationUpdates = NO;

	[self drawActivity];
}


#pragma mark - Motion Job

- (void)startGettingMotionActivity {


	void (^motionHandler)(CMMotionActivity *activity) = ^void(CMMotionActivity *activity){
        dispatch_async(dispatch_get_main_queue(), ^{
			_motionActivity = activity;
        });
    };
	
#ifdef GEO_FAKE
	[[GeoFake sharedFake] startActivityUpdatesWithHandler:motionHandler];
#else
	if([CMMotionActivityManager isActivityAvailable]) {
		_activityManager = [[CMMotionActivityManager alloc]init];
		[_activityManager startActivityUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:motionHandler];
	}
#endif
}

- (void)stopGettingMotionActivity {

#ifdef GEO_FAKE
	[[GeoFake sharedFake] stopActivityUpdates];
#else
	[_activityManager stopActivityUpdates];
#endif
    
	_activityManager = nil;
}

#pragma mark - Map job

- (void)drawActivity {
	if(_locationItems) {
		
		if(_locationItems.count > 1) {

			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			NSString *outputDateFormatterStr= @"HH:mm";
			[dateFormatter setTimeZone:[NSTimeZone defaultTimeZone]];
			[dateFormatter setDateFormat:outputDateFormatterStr];

			CLLocationCoordinate2D coordinates[500];
			for (int index = 0; index < _locationItems.count; index++) {
				LocateMotion *lm = [_locationItems objectAtIndex:index];
				CLLocationCoordinate2D coordinate = lm.location.coordinate;
				coordinates[index] = coordinate;

				NSString *annStr = [dateFormatter stringForObjectValue:lm.location.timestamp];
				int minute = [[annStr substringFromIndex:3] intValue];
				if(minute%5==0) {
					if(![annStr isEqualToString:_lastAnnotation]) {
						MKPointAnnotation *point = [[MKPointAnnotation alloc] init];
						point.coordinate = coordinate;
						point.title = annStr;
						[_mapView addAnnotation:point];
						[_mapView selectAnnotation:point animated:YES];
						_lastAnnotation = annStr;
					}
				}
			}
			
			ColorPolyline *polyLine = [ColorPolyline polylineWithCoordinates:coordinates count:_locationItems.count];
			polyLine.drawColor = [self getActivityColor:[_locationItems lastObject]];
			[_mapView addOverlay:polyLine level:MKOverlayLevelAboveRoads];

			for (int index = 0; index < _locationItems.count-1; index++) {
				[_locationItems removeObjectAtIndex:0];
			}
		}
	}
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id < MKOverlay >)overlay {
	
	ColorPolyline *polyline = (ColorPolyline*)overlay;

	MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:polyline];
	renderer.strokeColor = [polyline.drawColor colorWithAlphaComponent:0.7];
	renderer.lineWidth = 10.0;

	return (MKOverlayRenderer*)renderer;
}

- (UIColor *)getActivityColor:(LocateMotion*)lm {
	if(lm.activity.stationary)	return [UIColor colorWithRed:0.0 green:102.0f/255.0f blue:204.0f/255.0f alpha:1.0];
	if(lm.activity.walking)		return [UIColor colorWithRed:1.0 green:204.0f/255.0f blue:102.0f/255.0f alpha:1.0];
	if(lm.activity.running)		return [UIColor colorWithRed:1.0 green:102.0f/255.0f blue:102.0f/255.0f alpha:1.0];
	if(lm.activity.automotive)	return [UIColor colorWithRed:0.0 green:128.0f/255.0f blue:128.0f/255.0f alpha:1.0];
	
	return [UIColor grayColor];
}

@end
