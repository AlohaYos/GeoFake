//
//  MKMapView+GeoFake.m
//
//  Copyright (c) 2014 Yoshiyuki Hashimoto. All rights reserved.
//

#import <objc/runtime.h>
#import "GeoFakeCommon.h"

@implementation MKMapView (FakeLocations)

- (void)updateFakedLocation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [self performSelector:@selector(resumeUserLocationUpdates)];
    [self performSelector:@selector(resumeUserHeadingUpdates)];
    [self swizzled_locationManagerUpdatedLocation:[GFLocationProvider sharedProvider]];
    [self swizzled_locationManagerUpdatedHeading:[GFLocationProvider sharedProvider]];
    [self performSelector:@selector(pauseUserLocationUpdates)];
    [self performSelector:@selector(pauseUserHeadingUpdates)];
#pragma clan diagnostic pop
	
    id userAnnotation = [self.userLocation performSelector:@selector(annotation)];
    SEL theSelector = NSSelectorFromString(@"setCoordinate:");
    NSInvocation *anInvocation = [NSInvocation invocationWithMethodSignature: [[userAnnotation class]instanceMethodSignatureForSelector:theSelector]];
    
    [anInvocation setSelector:theSelector];
    [anInvocation setTarget:userAnnotation];
    CLLocationCoordinate2D coordinateToSet = [GFLocationProvider sharedProvider].location.coordinate;
    [anInvocation setArgument:&coordinateToSet atIndex:2];
    [anInvocation performSelector:@selector(invoke)];

    id userAnnotationView = [self performSelector:@selector(userLocationView)];
    if (userAnnotationView) {
        SEL setCoordinateSelector = NSSelectorFromString(@"setPresentationCoordinate:");
        NSInvocation *viewIncovation = [NSInvocation invocationWithMethodSignature: [[userAnnotationView class]instanceMethodSignatureForSelector:setCoordinateSelector]];
        
        [viewIncovation setSelector:setCoordinateSelector];
        [viewIncovation setTarget:userAnnotationView];
        [viewIncovation setArgument:&coordinateToSet atIndex:2];
        [viewIncovation performSelector:@selector(invoke)];
    }
}

#pragma mark - Method swizzeling

- (void)swizzled_locationManagerUpdatedLocation:(id)manager {
    [self swizzled_locationManagerUpdatedLocation:manager];
}

- (void)swizzled_locationManagerUpdatedHeading:(id)manager {
    [self swizzled_locationManagerUpdatedHeading:manager];
}


+ (void)load
{
    Method originalUpdateLocation, swizzledUpdateLocation;
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wundeclared-selector"
    originalUpdateLocation = class_getInstanceMethod(self, @selector(locationManagerUpdatedLocation:));
    #pragma clan diagnostic pop
    swizzledUpdateLocation = class_getInstanceMethod(self, @selector(swizzled_locationManagerUpdatedLocation:));
    method_exchangeImplementations(originalUpdateLocation, swizzledUpdateLocation);
    
    Method originalUpdateHeading, swizzledUpdateHeading;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    originalUpdateHeading = class_getInstanceMethod(self, @selector(locationManagerUpdatedHeading:));
#pragma clan diagnostic pop
    swizzledUpdateHeading = class_getInstanceMethod(self, @selector(swizzled_locationManagerUpdatedHeading:));
    method_exchangeImplementations(originalUpdateHeading, swizzledUpdateHeading);
}

@end

