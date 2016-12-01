//
//  RVLLocation.m
//  Pods
//
//  Created by Bobby Skinner on 3/1/16.
//
//  NOTE: This file is structured strangely to
//        facilitate using the file indepandantly
//        not for logical code separation

#import "RVLLocation.h"
#import "Reveal.h"

#define LOG       \
    if (self.log) \
    self.log

#ifndef objc_dynamic_cast
#define objc_dynamic_cast(TYPE, object)                                       \
    ({                                                                        \
        TYPE *dyn_cast_object = (TYPE *)(object);                             \
        [dyn_cast_object isKindOfClass:[TYPE class]] ? dyn_cast_object : nil; \
    })
#endif

typedef void (^Callback)();

@interface PlacemarkListener : NSObject

@property (nonatomic, strong) NSTimer * timeoutTimer;
@property (nonatomic, strong) Callback callback;
@property (nonatomic, strong) Callback completion;
@property (nonatomic, readonly) BOOL didExecute;

@end

@implementation PlacemarkListener

- (instancetype)initWithTimeout:(NSTimeInterval)timeout
{
    self = [super init];
    
    if (timeout)
    {
        _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(listenerExpired:) userInfo:nil repeats:NO];
    }
    
    return self;
}

-(void)listenerExpired:(NSTimer*)timer
{
    [self executeCallback];
}

-(void)executeCallback
{
    @synchronized(self)
    {
        if (_didExecute != YES) {
            if (_callback != nil)
            {
                dispatch_async(dispatch_get_main_queue(), ^
                               {
                                   _callback();
                               });
            }
            _didExecute = YES;
            if (self.timeoutTimer != nil) {
                [self.timeoutTimer invalidate];
            }
            if (_completion != nil)
            {
                dispatch_async(dispatch_get_main_queue(), ^
                               {
                                   _completion();
                               });
            }
        }
    }
}

-(void)dealloc {
    if (self.timeoutTimer != nil) {
        [self.timeoutTimer invalidate];
    }
}
@end

@interface RVLLocation () <CLLocationManagerDelegate>

// Core location reference
@property (nonatomic, strong) CLLocationManager *locationManager;

// time of the last geolocation update
@property (nonatomic, strong) NSDate *locationTime;

// time of the last location update
@property (nonatomic, strong) NSDate *userLocationTime;

// list of active monitors for location changes
@property (nonatomic, strong) NSMutableArray * placemarkListeners;

@end

@implementation RVLLocation

+ (RVLLocation *)sharedManager
{
    static dispatch_once_t onceToken;
    static RVLLocation *sharedInstance = nil;

    dispatch_once(&onceToken, ^{
      sharedInstance = [[RVLLocation alloc] init];
    });

    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        // setup defaults
        self.locationRetainTime = 60000.0;
        self.enableGeocoder = YES;
        self.locationTime = [NSDate distantPast];

        self.placemarkListeners = [NSMutableArray array];

        dispatch_async( dispatch_get_main_queue(), ^
        {
            self.locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.distanceFilter = 100;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
            self.locationManager.pausesLocationUpdatesAutomatically = NO;
            if ( [self.locationManager respondsToSelector: @selector(requestLocation)] )
                [self.locationManager requestLocation];
            self.userLocation = [self.locationManager location];
        });
    
    }

    return self;
}

- (void)startLocationMonitoring
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Must set up locationManager on main thread or no callbacks!
        switch ([[Reveal sharedInstance] locationServiceType])
        {
            case RVLLocationServiceTypeAlways:
                if ( [self.locationManager respondsToSelector: @selector(requestAlwaysAuthorization)] )
                    [self.locationManager requestAlwaysAuthorization];
                LOG(@"INFO", @"Starting location monitoring ALWAYS");
                break;

            case RVLLocationServiceTypeInUse:
                if ( [self.locationManager respondsToSelector: @selector(requestAlwaysAuthorization)] )
                    [self.locationManager requestWhenInUseAuthorization];
                LOG(@"INFO", @"Starting location monitoring IN USE");
                break;

            default:
                LOG(@"ERROR", @"Locations services must be setup for proper operation");
                break;
        }

        [self.locationManager startUpdatingLocation];
        self.userLocation = self.locationManager.location;

        });
}

- (void)stopLocationMonitoring
{
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.locationManager stopUpdatingLocation];
    });
}

- (BOOL)isLocationCurrent
{
    NSTimeInterval interval = [self.userLocation.timestamp timeIntervalSinceNow];
    
    if (interval < -60000.0)
        return NO;
    else
        return YES;
}

- (void) waitForValidLocation:(void (^)())callback
{
    if ( self.isLocationCurrent && self.userPlacemark )
    {
        callback();
    }
    else
    {
        __weak RVLLocation* me = self;

        PlacemarkListener * placemarkListener = [[PlacemarkListener alloc] initWithTimeout:30];
        __weak PlacemarkListener* weakListener = placemarkListener;
        
        [placemarkListener setCallback:callback];
        [placemarkListener setCompletion:^{
            // upon completion, remove object from array of placemark listeners
            
            @synchronized(me.placemarkListeners)
            {
                [me.placemarkListeners removeObject: weakListener];
            }
        }];
        @synchronized(self.placemarkListeners)
        {
            [self.placemarkListeners addObject:placemarkListener];
        }
    }
}

- (void)setUserLocation:(CLLocation *)userLocation
{
    if (userLocation != nil)
    {
        _userLocation = userLocation;
        self.userCoordinate = userLocation.coordinate;
        self.userLocationTime = [NSDate date];
    }
}

- (void)setUserCoordinate:(CLLocationCoordinate2D)coordinate
{
    __weak RVLLocation* me = self;
    
    _userCoordinate = coordinate;
    if (self.enableGeocoder)
    {
        CLGeocoder *geoCoder = [[CLGeocoder alloc] init];
        CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude
                                                          longitude:coordinate.longitude];
        [geoCoder reverseGeocodeLocation:location
                       completionHandler:^(NSArray *placemarks, NSError *error)
                        {
                            if (error)
                            {
                                LOG(@"%@", [error localizedDescription]);
                                return;
                            }

                            me.locationTime = [NSDate date];
                            me.userPlacemark = objc_dynamic_cast(CLPlacemark, [placemarks firstObject]);

                            [me executeAllPlacemarkListeners];
                            
                        }];
    }
}
-(void)executeAllPlacemarkListeners
{
    NSArray * placemarkListenersCopy = [NSArray arrayWithArray:self.placemarkListeners];
    
    for (PlacemarkListener * placemarkListener in placemarkListenersCopy)
    {
        [placemarkListener executeCallback];
    }

}

#pragma mark - CLLocationManagerDelegate -

-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations
{
    CLLocation *newLocation = [locations lastObject];

    [self setUserLocation:newLocation];

    if ([self.passThroughDelegate respondsToSelector:@selector(locationManager:didUpdateLocations:)])
        [self.passThroughDelegate locationManager:manager didUpdateLocations:locations];
}

- (void)locationManager:(CLLocationManager *)manager
      didDetermineState:(CLRegionState)state
              forRegion:(CLRegion *)region
{
    if ([self.passThroughDelegate respondsToSelector:@selector(locationManager:didDetermineState:forRegion:)])
        [self.passThroughDelegate locationManager:manager
                                didDetermineState:state
                                        forRegion:region];
}

- (void)locationManager:(CLLocationManager *)manager
    monitoringDidFailForRegion:(CLRegion *)region
                     withError:(NSError *)error
{
    if ([self.passThroughDelegate respondsToSelector:@selector(locationManager:monitoringDidFailForRegion:withError:)])
        [self.passThroughDelegate locationManager:manager
                       monitoringDidFailForRegion:region
                                        withError:error];
}

- (void)locationManager:(CLLocationManager *)manager
    rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region
                         withError:(NSError *)error
{
    if ([self.passThroughDelegate respondsToSelector:@selector(locationManager:rangingBeaconsDidFailForRegion:withError:)])
        [self.passThroughDelegate locationManager:manager
                   rangingBeaconsDidFailForRegion:region
                                        withError:error];
}

- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region
{
    if ([self.passThroughDelegate respondsToSelector:@selector(locationManager:didRangeBeacons:inRegion:)])
        [self.passThroughDelegate locationManager:manager
                                  didRangeBeacons:beacons
                                         inRegion:region];
}

@end
