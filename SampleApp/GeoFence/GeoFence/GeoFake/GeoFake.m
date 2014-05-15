//
//  GeoFake.m
//
//  Copyright (c) 2014 Yoshiyuki Hashimoto. All rights reserved.
//

#import "GeoFakeCommon.h"

#define MAX_REGIONS	20

@implementation GeoFake {
	MCPeerID	*_myPeerID;
	MCSession	*_session;
	MCAdvertiserAssistant	*_assistant;
	
	CLLocationManager	*_locationManager;
	MKMapView			*_mapView;
	BOOL					_updateLocation;
	BOOL					_updateHeading;
	
	CMMotionActivityHandler	_motionHandler;
	BOOL					_updateMotion;
	
	NSMutableArray		*_regions;
	NSMutableArray		*_lastRegionState;
}

+ (GeoFake *)sharedFake {
    static GeoFake *sharedFake = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedFake = [[self alloc] initWithClientName:[[UIDevice currentDevice] name]];
    });
	
    return sharedFake;
}

- (id)initWithClientName:(NSString*)name {
	_myPeerID = [[MCPeerID alloc] initWithDisplayName:name];
	_session = [[MCSession alloc] initWithPeer:_myPeerID];
	_session.delegate = (id<MCSessionDelegate>)self;
	_assistant = [[MCAdvertiserAssistant alloc] initWithServiceType:@"GeoFake" discoveryInfo:nil session:_session];
	_assistant.delegate = self;

	_regions = [[NSMutableArray alloc] initWithCapacity:1];
	_lastRegionState = [[NSMutableArray alloc] initWithCapacity:1];
	
	[self start];
	
	return self;
}

- (void)dealloc {
	[self stop];
}

#pragma mark - CoreLocation fake job

- (void)setLocationManager:(CLLocationManager*)locMan mapView:(MKMapView*)mapView {
	[self setLocationmanager:locMan];
	[self setMapView:mapView];
}

- (void)setLocationmanager:(CLLocationManager*)locMan {
	_locationManager = locMan;
}

- (void)setMapView:(MKMapView*)mapView {
	_mapView = mapView;
}

- (void)startUpdatingLocation {
	_updateLocation = YES;
}

- (void)stopUpdatingLocation {
	_updateLocation = NO;
}

- (void)startUpdatingHeading {
	_updateHeading = YES;
}

- (void)stopUpdatingHeading {
	_updateHeading = NO;
}

#pragma mark - CoreLocation fake job (Region)

- (void)startMonitoringForRegion:(CLRegion *)region {
	
	[_regions addObject:region];
	[_lastRegionState addObject:[NSNumber numberWithInt:CLRegionStateUnknown]];
	
	if ([_locationManager.delegate respondsToSelector:@selector(locationManager:didStartMonitoringForRegion:)]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[_locationManager.delegate locationManager:_locationManager didStartMonitoringForRegion:region];
		});
	}
}

- (void)stopMonitoringForRegion:(CLRegion *)region {

	for(int i=0; i < _regions.count; i++) {
		CLRegion* rg = [_regions objectAtIndex:i];
		if([rg.identifier isEqualToString:region.identifier]) {
			[_regions removeObjectAtIndex:i];
			[_lastRegionState removeObjectAtIndex:i];
			break;
		}
	}
}

- (NSSet*)monitoredRegions {
	
	return [NSSet setWithArray:_regions];
}

- (void)requestStateForRegion:(CLRegion *)region {

	CLRegionState state = CLRegionStateUnknown;

	for(int i=0; i < _regions.count; i++) {
		CLRegion* rg = [_regions objectAtIndex:i];
		if([rg.identifier isEqualToString:region.identifier]) {
			state = CLRegionStateOutside;
			if([self isCurrentLocationInsideRegion:rg]) {
				state = CLRegionStateInside;
			}
			
			if ([_locationManager.delegate respondsToSelector:@selector(locationManager:didDetermineState:forRegion:)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[_locationManager.delegate locationManager:_locationManager didDetermineState:state forRegion:region];
				});
			}
			
			break;
		}
	}
}


#pragma mark - CoreMotion fake job

- (void)startActivityUpdatesWithHandler:(CMMotionActivityHandler)handler {
	_motionHandler = handler;
	_updateMotion = YES;
}

- (void)stopActivityUpdates {
	_updateMotion = NO;
}

#pragma mark - Peer connect job

- (void)start {
	[_assistant start];
}

- (void)stop {
	[_assistant stop];
}

#pragma mark - Session delegate job

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    NSString *receivedMessage = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
	
	NSArray *comp = [receivedMessage componentsSeparatedByString:@","];
	NSString *messageType  = [[comp objectAtIndex:0] substringFromIndex:0];
	
	if([messageType isEqualToString:@"{Location}"]) {
		[self updateLocationJob:receivedMessage];
	}
	if([messageType isEqualToString:@"{Motion}"]) {
		[self updateMotionJob:receivedMessage];
	}
}

- (void)updateLocationJob:(NSString*)locationMessage {
	
	NSArray *comp = [locationMessage componentsSeparatedByString:@","];
	NSString *latStr  = [[comp objectAtIndex:1] substringFromIndex:0];
	NSString *lonStr  = [[comp objectAtIndex:2] substringFromIndex:0];
	NSString *heading = [[comp objectAtIndex:3] substringFromIndex:0];
	
	CLLocation *locationToSend = [[CLLocation alloc]initWithCoordinate:CLLocationCoordinate2DMake([latStr doubleValue], [lonStr doubleValue]) altitude:0 horizontalAccuracy:0 verticalAccuracy:0 course:0 speed:0 timestamp:[NSDate new]];
	[[GFLocationProvider sharedProvider] setLocation:locationToSend];
	
	CLFakeHeading *head = [CLFakeHeading new];
	head.magneticHeading = [heading doubleValue];
	head.trueHeading = [heading doubleValue];
	head.headingAccuracy = 20;
	head.timestamp = [NSDate date];
	[[GFLocationProvider sharedProvider] setHeading:head];
	[[GFLocationProvider sharedProvider] setCurrentVehicleHeading:head];
	[[GFLocationProvider sharedProvider] setThrottledHeading:head];
	
	[_locationManager performSelector:@selector(updateFakedLocation)];
	[_mapView performSelector:@selector(updateFakedLocation)];

	[self checkRegions];
}

- (BOOL)isCurrentLocationInsideRegion:(CLRegion*)checkRegion {
	
	if ([checkRegion respondsToSelector:@selector(containsCoordinate:)]) {
		CLCircularRegion* crg = (CLCircularRegion*)checkRegion;
		CLLocation *locationToCheck = [GFLocationProvider sharedProvider].location;
		BOOL isInside = [crg containsCoordinate:locationToCheck.coordinate];
		return isInside;
	}
	else {
		return NO;
	}
}

- (void)checkRegions {
	
	for(int i=0; i < _regions.count; i++) {
		CLRegion* rg = [_regions objectAtIndex:i];

		NSNumber *lastState = [_lastRegionState objectAtIndex:i];
		
		// Inside of region
		if([self isCurrentLocationInsideRegion:rg]) {
			if([lastState intValue] != CLRegionStateInside) {
				if([lastState intValue] != CLRegionStateUnknown) {
					[self requestStateForRegion:rg];
					if ([_locationManager.delegate respondsToSelector:@selector(locationManager:didEnterRegion:)]) {
						dispatch_async(dispatch_get_main_queue(), ^{
							[_locationManager.delegate locationManager:_locationManager didEnterRegion:rg];
						});
					}
				}
			}
			[_lastRegionState replaceObjectAtIndex:i withObject:[NSNumber numberWithInt:CLRegionStateInside]];
		}
		// Outside of region
		else {
			if([lastState intValue] != CLRegionStateOutside) {
				if([lastState intValue] != CLRegionStateUnknown) {
					[self requestStateForRegion:rg];
					if ([_locationManager.delegate respondsToSelector:@selector(locationManager:didExitRegion:)]) {
						dispatch_async(dispatch_get_main_queue(), ^{
							[_locationManager.delegate locationManager:_locationManager didExitRegion:rg];
						});
					}
				}
			}
			[_lastRegionState replaceObjectAtIndex:i withObject:[NSNumber numberWithInt:CLRegionStateOutside]];
		}
	}
}


- (void)updateMotionJob:(NSString*)motionMessage {
	
	if(_motionHandler) {
		NSArray *comp         = [motionMessage componentsSeparatedByString:@","];
		NSString *stationary  = [[comp objectAtIndex:1] substringFromIndex:0];
		NSString *walking     = [[comp objectAtIndex:2] substringFromIndex:0];
		NSString *running     = [[comp objectAtIndex:3] substringFromIndex:0];
		NSString *automotive  = [[comp objectAtIndex:4] substringFromIndex:0];
		NSString *unknown     = [[comp objectAtIndex:5] substringFromIndex:0];
		NSString *confidence  = [[comp objectAtIndex:6] substringFromIndex:0];
		
		CMFakeMotionActivity* fakeMotion = [CMFakeMotionActivity new];
		fakeMotion.stationary = (BOOL)[stationary intValue];
		fakeMotion.walking = (BOOL)[walking intValue];
		fakeMotion.running = (BOOL)[running intValue];
		fakeMotion.automotive = (BOOL)[automotive intValue];
		fakeMotion.unknown = (BOOL)[unknown intValue];
		fakeMotion.confidence = (CMMotionActivityConfidence)[confidence intValue];
		fakeMotion.startDate = [NSDate date];
		
		_motionHandler(fakeMotion);
	}
}


@end
