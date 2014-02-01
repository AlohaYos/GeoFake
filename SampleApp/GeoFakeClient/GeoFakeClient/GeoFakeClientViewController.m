//
//  GeoFakeClientViewController.m
//  GeoFakeClient
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "GeoFakeClientViewController.h"
#import <GeoFake/GeoFake.h>


@interface GeoFakeClientViewController ()
@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@end

@implementation GeoFakeClientViewController {
	CLLocationManager *_locationManager;
	CLLocationCoordinate2D _centerLocation;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	_locationManager = [[CLLocationManager alloc]init];
    [_locationManager setDelegate:self];

#ifdef	GEO_FAKE
	[[GeoFake sharedFake] setLocationManager:_locationManager mapView:_mapView];
	[[GeoFake sharedFake] startUpdatingLocation];
	[[GeoFake sharedFake] startUpdatingHeading];
#else
	[_locationManager startUpdatingLocation];
	[_locationManager startUpdatingHeading];
#endif

	
}

- (void)viewDidAppear:(BOOL)animated {
	MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(_centerLocation, 500, 500);
	[_mapView setRegion:region animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - CoreLocation delegate job

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *latestLocation = [locations firstObject];

	NSLog(@"didUpdateLocations %lu(%f,%f)", (unsigned long)[locations count], latestLocation.coordinate.latitude, latestLocation.coordinate.longitude);

	[_mapView setCenterCoordinate:latestLocation.coordinate animated:YES];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
	NSLog(@"didUpdateHeading (%f,%f)", newHeading.magneticHeading, newHeading.trueHeading);
	
	_mapView.camera.heading = newHeading.trueHeading;
}

@end
