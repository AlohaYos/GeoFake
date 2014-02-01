//
//  WebViewController.h
//  GeoFence
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface WebViewController : UIViewController <UIWebViewDelegate>

@property (strong, nonatomic)	NSNumber *majorNumber;
@property (strong, nonatomic)	NSNumber *minorNumber;

- (void)loadWebPageMajor:(NSNumber *)majorNumber minor:(NSNumber *)minorNumber;

@end
