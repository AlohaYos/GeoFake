GeoFake.framework
=======

Simulate Location and Motion information for Debugging iOS apps. GeoFake framework works with <a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a>.

<img src="http://newtonjapan.com/GeoPlayer/wp-content/uploads/2014/01/debug_desk.png" alt="debug_desk" title="debug_desk" width="500" height="278" class="alignnone size-full wp-image-328" />

If you ever build your iOS app using GPS, you probably experienced the difficulty of debugging it on the desk.

Unless testing your app in outdoor field, you can not realize unstable behavior of GPS, Cell-tower and WiFi.

Your fitness app draw your running route on the map exactly ?<br />
Your travel app get correct information while you are walking around ?<br />
These apps need moving-around-test in outdoor many times.

For such case, iOS simulator has location-simulation debug feature.
But that simulation is not good enouth, because it is NOT using real information.

<img src="http://newtonjapan.com/GeoPlayer/wp-content/uploads/2014/01/DiamondheadRun.png" alt="DiamondheadRun" title="DiamondheadRun" width="500" height="333" class="alignnone size-full wp-image-329" />

<strong>Playback real GPS movement</strong>

GPS signal jumps from entrance to exit of tunnel, for example.
<a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> can record such unusual behaviors and can playback them.
These recording data will be very important debug resource for your job on the desk.

<img src="http://newtonjapan.com/GeoPlayer/wp-content/uploads/2014/01/connect_iphones.png" alt="connect_iphones" title="connect_iphones" width="489" height="343" class="alignnone size-full wp-image-354" />

<strong>Playback GPX data</strong>

<a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> playbacks GPX data and playback speed is same as recording speed.
If you have marathon data of three-hour-finisher in iPhone(A), you can playback it in three hours and send location information of each second to iPhone(B) via Bluetooth.

iPhone(B) receives that location information and act as if running that marathon right now. You can debug your GPS app in iPhone(B) using information from iPhone(A) like this.

<strong>Playback motion data</strong>

Also <a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> can send motion information to iPhone(B). When using iPhone with M7 processor, <a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> can record location and motion data at the same time. Motion data are activities like walking, running or stopping.

<img src="http://newtonjapan.com/GeoPlayer/wp-content/uploads/2014/01/debug_code.png" alt="debug_code" title="debug_code" width="500" height="330" class="alignnone size-full wp-image-333" />

<strong>Geo fence debugging</strong>

Using <a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> and GeoFake framework, you can test your GeoFence app on the desk.

<strong>Precise simulation in manual mode</strong>

<a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a> has manual operation mode. When you move <a href="http://newtonjapan.com/GeoPlayer/" target=_blank>GeoPlayer</a>'s map with your finger, the map of iPhone(B) will follow your finger movement. So, you can simulate location precisely while debugging.

<hr />

<strong>How to debug your GPS/Motion app with GeoFake.framework</strong>

<a href="http://newtonjapan.com/GeoPlayer/debug-motion-app-with-geoplayer" target=_blank>Video tutorial available here.</a>

  1. add Framework
 
		GeoFake.framework
 
  2. import header file
 
		#import <GeoFake/GeoFake.h>
 
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

			if([CMMotionActivityManager isActivityAvailable]) {
		#ifdef	GEO_FAKE
			  [[GeoFake sharedFake] startActivityUpdatesWithHandler:motionHandler];
		#else
				_activityManager = [[CMMotionActivityManager alloc]init];
				[_activityManager startActivityUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:motionHandler];
		#endif
			}
 
  5. set link flag at "Build Settings"
 
		Linking
			Other Linker Flags "-ObjC -all_load"
 
  6. build and run !

<hr />

<strong>How to connect with GeoPlayer</strong>

<a href="http://newtonjapan.com/GeoPlayer/connect-to-geoplayer-clients" target=_blank>Please visit this website.</a>

<hr />

<strong>GeoFake Class Interface</strong>
<pre><code>@interface GeoFake : NSObject<br />
// Shared instance
+ (GeoFake *)sharedFake;

// Fake CoreLocation (Location update)
- (void)setLocationManager:(CLLocationManager*)locMan mapView:(MKMapView*)mapView;
- (void)startUpdatingLocation;
- (void)stopUpdatingLocation;
- (void)startUpdatingHeading;
- (void)stopUpdatingHeading;

// Fake CoreLocation (Region monitoring)
- (void)startMonitoringForRegion:(CLRegion *)region;
- (void)stopMonitoringForRegion:(CLRegion *)region;
- (NSSet*)monitoredRegions;
- (void)requestStateForRegion:(CLRegion *)region;

// Fake CoreMotion (Motion activity)
- (void)startActivityUpdatesWithHandler:(CMMotionActivityHandler)handler;
- (void)stopActivityUpdates;

@end
</code></pre>
