//
//  WebViewController.m
//  GeoFence
//
//  Copyright (c) 2014 Newton Japan. All rights reserved.
//

#import "WebViewController.h"

@interface WebViewController ()
@property (weak, nonatomic) IBOutlet UIWebView *webView;

@end

@implementation WebViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated
{
	[self loadWebPage];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)loadWebPage
{
	NSString *urlString = [NSString stringWithFormat:@"http://newtonworks.sakura.ne.jp/wp/LocatedItems/%02d-%02d/", [self.majorNumber intValue], [self.minorNumber intValue]];
	
	[self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
}

- (void)loadWebPageMajor:(NSNumber *)majorNumber minor:(NSNumber *)minorNumber
{
	if(([self.majorNumber intValue] != [majorNumber intValue]) || ([self.minorNumber intValue] != [minorNumber intValue])) {
		self.majorNumber = majorNumber;
		self.minorNumber = minorNumber;
		[self loadWebPage];
	}
}

@end
