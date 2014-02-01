//
//  GeoFenceViewController.m
//  GeoFence
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "GeoFenceViewController.h"
#import "WebViewController.h"
#import <GeoFake/GeoFake.h>

#pragma mark - GeoFence distance

#define FENCE_1		100.0
#define FENCE_2		500.0
#define FENCE_3		1000.0

#pragma mark - Annotations

@interface CenterAnnotation : NSObject <MKAnnotation>
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@end

@implementation CenterAnnotation

- (id)initWithCoordinate:(CLLocationCoordinate2D)coord {
	if( nil != (self = [super  init]) ){
		self.coordinate = coord;
	}
	return self;
}

@end

@interface CenterAnnotationView : MKAnnotationView
@end

@implementation CenterAnnotationView
- (id)initWithAnnotation:(id <MKAnnotation>)annotation reuseIdentifier:(NSString*)reuseIdentifier
{
	self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
	if( self ){
		UIImage* image = [UIImage imageNamed:@"target"];
		self.frame = CGRectMake(self.frame.origin.x,self.frame.origin.y,image.size.width,image.size.height);
		self.image = image;
	}
	return self;
}
@end


#pragma mark - GeoFenceViewController

@interface GeoFenceViewController ()

@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UISwitch *fenceSwitch;

@end

@implementation GeoFenceViewController {
	BOOL				_didLoadData;
	CLLocationManager	*_locationManager;
	BOOL				_showingWebPage;
	WebViewController	*_webVC;
	NSNumber			*_webMajorNumber;
	NSNumber			*_webMinorNumber;

	// GeoFence
	CLLocationCoordinate2D _centerLocation;
	CenterAnnotation	*_centerAnnotation;
	CLCircularRegion	*_regionNearby;
	CLCircularRegion	*_regionBlock;
	CLCircularRegion	*_regionTown;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	_didLoadData = NO;
	[self loadData];
	
	_showingWebPage = NO;

	_locationManager = [[CLLocationManager alloc] init];
	_locationManager.delegate = self;
	_locationManager.desiredAccuracy = kCLLocationAccuracyBest;
	_locationManager.distanceFilter = kCLDistanceFilterNone;

#ifdef	GEO_FAKE
	[[GeoFake sharedFake] setLocationManager:_locationManager mapView:_mapView];
	[[GeoFake sharedFake] startUpdatingLocation];
#else
	[_locationManager startUpdatingLocation];
#endif

	[self setGeofenceAt:_centerLocation];
	[self monitoring:YES];

	if(_didLoadData) {
		MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(_centerLocation, (FENCE_3*3.0), (FENCE_3*3.0));
		[_mapView setRegion:region animated:YES];
		
		_fenceSwitch.on = YES;
	}else{
		MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(_mapView.userLocation.location.coordinate, (FENCE_3*3.0), (FENCE_3*3.0));
		[_mapView setRegion:region animated:YES];
		_fenceSwitch.on = NO;
	}
}

- (void)viewDidAppear:(BOOL)animated {
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - GeoFence job

- (void)setGeofenceAt:(CLLocationCoordinate2D)geofenceCenter {

	[_mapView removeOverlays:_mapView.overlays];

	_centerLocation = geofenceCenter;
	
	MKCircle *_fenceRange1 = [MKCircle circleWithCenterCoordinate:_centerLocation radius:FENCE_1];
	MKCircle *_fenceRange2 = [MKCircle circleWithCenterCoordinate:_centerLocation radius:FENCE_2];
	MKCircle *_fenceRange3 = [MKCircle circleWithCenterCoordinate:_centerLocation radius:FENCE_3];

	[_mapView addOverlay:_fenceRange1 level:MKOverlayLevelAboveRoads];
	[_mapView addOverlay:_fenceRange2 level:MKOverlayLevelAboveRoads];
	[_mapView addOverlay:_fenceRange3 level:MKOverlayLevelAboveRoads];

	_regionNearby = [[CLCircularRegion alloc] initWithCenter:_fenceRange1.coordinate radius:_fenceRange1.radius identifier:@"nearby"];
	_regionNearby.notifyOnEntry = YES;
	_regionNearby.notifyOnExit  = YES;
	_regionBlock  = [[CLCircularRegion alloc] initWithCenter:_fenceRange2.coordinate radius:_fenceRange2.radius identifier:@"nextBlock"];
	_regionBlock.notifyOnEntry = YES;
	_regionBlock.notifyOnExit  = YES;
	_regionTown = [[CLCircularRegion alloc] initWithCenter:_fenceRange3.coordinate radius:_fenceRange3.radius identifier:@"nextTown"];
	_regionTown.notifyOnEntry = YES;
	_regionTown.notifyOnExit  = YES;
}

- (void)monitoring:(BOOL)flag {
	
	if(flag == YES) {
#ifdef	GEO_FAKE
		[[GeoFake sharedFake] startMonitoringForRegion:_regionNearby];
		[[GeoFake sharedFake] startMonitoringForRegion:_regionBlock];
		[[GeoFake sharedFake] startMonitoringForRegion:_regionTown];
		[[GeoFake sharedFake] requestStateForRegion:_regionNearby];
#else
		[_locationManager startMonitoringForRegion:_regionNearby];
		[_locationManager startMonitoringForRegion:_regionBlock];
		[_locationManager startMonitoringForRegion:_regionTown];
		[_locationManager requestStateForRegion:_regionNearby];
		NSSet* regions=[_locationManager monitoredRegions];
#endif
	}
	else {
#ifdef	GEO_FAKE
		NSArray *regions = [[[GeoFake sharedFake] monitoredRegions] allObjects];
#else
		NSArray *regions = [[_locationManager monitoredRegions] allObjects];
#endif
		for (int i = 0; i < [regions count]; i++) {
#ifdef	GEO_FAKE
			[[GeoFake sharedFake] stopMonitoringForRegion:[regions objectAtIndex:i]];
#else
			[_locationManager stopMonitoringForRegion:[regions objectAtIndex:i]];
#endif
		}
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *latestLocation = [locations firstObject];
	[_mapView setCenterCoordinate:latestLocation.coordinate animated:YES];
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region{
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    NSLog(@"%@",error);
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
	NSString *alertStr;
	
	if([region.identifier isEqualToString:@"nextTown"]) {
		alertStr = [NSString stringWithFormat:@"Enter into GeoFence of %.0fm", FENCE_3];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:6]];
	}
	if([region.identifier isEqualToString:@"nextBlock"]) {
		alertStr = [NSString stringWithFormat:@"Enter into GeoFence of %.0fm", FENCE_2];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:5]];
	}
	if([region.identifier isEqualToString:@"nearby"]) {
		alertStr = [NSString stringWithFormat:@"Enter into GeoFence of %.0fm", FENCE_1];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:4]];
	}
	
	if([alertStr length] > 0) {
		UILocalNotification *notification = [[UILocalNotification alloc] init];
		notification.alertBody = alertStr;
		notification.soundName = UILocalNotificationDefaultSoundName;
		[[UIApplication sharedApplication] cancelAllLocalNotifications];
		[[UIApplication sharedApplication] presentLocalNotificationNow:notification];
	}
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
	NSString *alertStr;
	
	if([region.identifier isEqualToString:@"nearby"]) {
		alertStr = [NSString stringWithFormat:@"Exit from GeoFence of %.0fm", FENCE_1];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:1]];
	}
	if([region.identifier isEqualToString:@"nextBlock"]) {
		alertStr = [NSString stringWithFormat:@"Exit from GeoFence of %.0fm", FENCE_2];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:2]];
	}
	if([region.identifier isEqualToString:@"nextTown"]) {
		alertStr = [NSString stringWithFormat:@"Exit from GeoFence of %.0fm", FENCE_3];
		[self openWebPageMajor:[NSNumber numberWithInt:5] minor:[NSNumber numberWithInt:3]];
	}
	
	if([alertStr length] > 0) {
		UILocalNotification *notification = [[UILocalNotification alloc] init];
		notification.alertBody = alertStr;
		notification.soundName = UILocalNotificationDefaultSoundName;
		[[UIApplication sharedApplication] cancelAllLocalNotifications];
		[[UIApplication sharedApplication] presentLocalNotificationNow:notification];
	}
}

#pragma mark - Map job

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id < MKOverlay >)overlay {
	
	MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle*)overlay];
	
	renderer.strokeColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
	renderer.lineWidth = 1.0;
	renderer.fillColor = [[UIColor redColor] colorWithAlphaComponent:0.2];
	
	return (MKOverlayRenderer*)renderer;
}

- (MKAnnotationView *)mapView:(MKMapView *)theMapView viewForAnnotation:(id <MKAnnotation>)annotation {
	
	if ([annotation isKindOfClass:[MKUserLocation class]])
		return nil;
	
	if ([annotation isKindOfClass:[CenterAnnotation class]]) {
		MKAnnotationView* annotationView = [_mapView  dequeueReusableAnnotationViewWithIdentifier:@"CenterAnnotation"];
		if( annotationView ){
			annotationView.annotation = annotation;
		}
		else{
			annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"CenterAnnotation"];
		}
		annotationView.image = [UIImage imageNamed:@"target"];
		return annotationView;
	}
	
	return nil;
}

- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated {
	if(_centerAnnotation){
		[_mapView removeAnnotation:_centerAnnotation];
	}
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
	
	if(_centerAnnotation){
		_centerAnnotation.coordinate = _mapView.region.center;
	}
	else {
		_centerAnnotation = [[CenterAnnotation alloc] initWithCoordinate:_mapView.region.center];
	}
	
	[_mapView addAnnotation:_centerAnnotation];
}


#pragma mark - Web job

-(void)openWebPageMajor:(NSNumber *)majorNumber minor:(NSNumber *)minorNumber
{
	if(_showingWebPage == NO) {
		_showingWebPage = YES;
		_webMajorNumber = majorNumber;
		_webMinorNumber = minorNumber;
		[self performSegueWithIdentifier:@"showWebPage" sender:self];
	}
	else {
		[_webVC loadWebPageMajor:majorNumber minor:minorNumber];
	}

	[NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(closeWebPage) userInfo:Nil repeats:NO];
}

-(void)closeWebPage
{
	if(_showingWebPage == YES) {
		[self dismissViewControllerAnimated:YES completion:nil];
		_showingWebPage = NO;
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ( [[segue identifier] isEqualToString:@"showWebPage"] ) {
        WebViewController *nextViewController = [segue destinationViewController];
		_webVC = nextViewController;
        nextViewController.majorNumber = _webMajorNumber;
        nextViewController.minorNumber = _webMinorNumber;
    }
}

#pragma mark - Save/Load data

- (void)saveData {
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
						  [NSNumber numberWithDouble:_centerLocation.latitude], @"latitude",
						  [NSNumber numberWithDouble:_centerLocation.longitude], @"longitude",
						  nil
						  ];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:dict forKey:@"GeofenceData"];
}

- (void)loadData {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *dict = [defaults dictionaryForKey:@"GeofenceData"];
	if(dict) {
		_didLoadData = YES;
		_centerLocation = CLLocationCoordinate2DMake([[dict valueForKey:@"latitude"] doubleValue], [[dict valueForKey:@"longitude"] doubleValue]);
	}
}


- (IBAction)fenceSwitchValueChanged:(id)sender {
	UISwitch *sw = sender;
	[self monitoring:sw.on];
}

- (IBAction)fenceCenterButtonPushed:(id)sender {
	
	[self setGeofenceAt:_mapView.region.center];
	[self saveData];

	if(_fenceSwitch.on) {
		[self monitoring:NO];
		[self monitoring:YES];
	}
}

@end
