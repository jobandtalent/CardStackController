//  RVLBeaconManager.m
//  Pods
//
//  Created by Bobby Skinner on 3/1/16.
//
//
//  NOTE: This file is structured strangely to
//        facilitate using the file indepandantly
//        not for logical code separation

#import <UIKit/UIKit.h>
#import "RVLBeaconManager.h"

// NOTE: This dependance returned as a result
#import "RVLLocation.h"
#import "Reveal.h"
#import <math.h>

#define LOG       \
    if (self.log) \
    self.log
#define VERBOSE          \
    if (self.logVerbose) \
    self.logVerbose

#ifndef objc_dynamic_cast
#define objc_dynamic_cast(TYPE, object)                                       \
    ({                                                                        \
        TYPE *dyn_cast_object = (TYPE *)(object);                             \
        [dyn_cast_object isKindOfClass:[TYPE class]] ? dyn_cast_object : nil; \
    })
#endif

#define kFoundBeaconsKey        @"FOUND_BEACONS_LIST"

#define EDDYSTONE_UID           0
#define EDDYSTONE_URL           16
#define EDDYSTONE_TLM           32

#pragma pack(1)
typedef struct securecastBeaconHeader
{
    uint16_t vendor;
    uint32_t key;
    uint8_t payload[16];
} securecastBeaconHeader_t;
#pragma pack()

@interface RevealBluetoothObject () <CBPeripheralDelegate>
@end

#pragma mark - RVLBeaconManager -

@interface RVLBeaconManager () <CBCentralManagerDelegate>

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) NSDate *scanStarted;
@property (nonatomic, strong) NSMutableDictionary *vendors;
@property (nonatomic, strong) NSTimer *ticker;

@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) NSMutableArray *statusBlocks;
@property (nonatomic, strong) NSMutableArray *beaconRegions;

@property (nonatomic, assign) BOOL hasBluetooth;
@property (nonatomic, assign) BOOL enableGeocoder;
@property (nonatomic, assign) CLLocationCoordinate2D userCoordinate;
@property (nonatomic, strong) CLLocation *userLocation;
@property (nonatomic, strong) NSMutableArray *pendingBeacons;
@property (nonatomic, strong) NSTimer *timeoutTicker;
@property (nonatomic, strong) NSMutableDictionary* incompleteBeacons;
@property (nonatomic, strong) NSTimer* sendTimer;

@end

@implementation RVLBeaconManager

+ (RVLBeaconManager *)sharedManager
{
    static RVLBeaconManager *_sharedInstance;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      _sharedInstance = [[RVLBeaconManager alloc] init];
    });

    return _sharedInstance;
}

+ (RVLLocationServiceType)locationServiceType
{
    RVLLocationServiceType result = RVLLocationServiceTypeNone;
    
    if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"])
        result = RVLLocationServiceTypeInUse;
    else if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationAlwaysUsageDescription"])
        result = RVLLocationServiceTypeAlways;
    
    return result;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.distanceCalculator = [CurveFittedDistanceCalculator new];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            self.locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.distanceFilter = 100;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
            self.locationManager.pausesLocationUpdatesAutomatically = NO;
        });
        
        self.pendingBeacons = [NSMutableArray array];
        self.cachedBeacons = [CCObjectCache new];
        self.minRSSI = -90;
        self.maxRSSI = 0;

        _status = @"....";
        _beaconRegions = [@[] mutableCopy];
        _statusBlocks = [@[] mutableCopy];
        _hasBluetooth = NO;
        _enableGeocoder = YES;
        self.proximityTimeout = 30.0;
        [self loadFoundBeacons];
        
        //commented out these observers unless we start using the callbacks in the future
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(applicationWillResignActive:)
//                                                     name:UIApplicationWillResignActiveNotification
//                                                   object:nil];
//
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(applicationDidBecomeActive:)
//                                                     name:UIApplicationDidBecomeActiveNotification
//                                                   object:nil];
        
        
        
        // add default vendors
        self.vendors = [NSMutableDictionary dictionary];
        
        //[self add:@"Gimbal" withCode: BEACON_TYPE_GIMBAL];
        //[self add:@"TILE" withCode: BEACON_SERVICE_TILE];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// stop doing address lookups in the background
- (void)applicationWillResignActive:(NSNotification *)notification
{
    //    [self stop];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    //    [self  start];
}

- (void)startScanner
{
    // Setup RevealScanner to scan for beacons that dont use the iBeacon
    // standard
    [self setIncludeUnknownVendors:NO];
    [self setShowUnknownDevices:NO];
    [self setCaptureAllDevices:NO];
    
    LOG( @"INFO", @"Looking for these beacons in addition to standard iBeacons:\n%@", self.vendors );

    [self start];
}

/**
 *  save all beacons to user defaults
 */
- (void)storeFoundBeacons
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:self.cachedBeacons forKey:@"cachedBeacons"];
    [archiver finishEncoding];

    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSArray *urls = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSString *url = [NSString stringWithFormat:@"%@", urls[0]];
    NSURL *destination = [NSURL URLWithString:[url stringByAppendingPathComponent:@"beacons.arc"]];
    NSError *error = nil;

    if (![data writeToURL:destination
                  options:NSDataWritingAtomic
                    error:&error])
    {
        LOG(@"ERROR", @"Error saving beacons to %@:\n%@", destination, error);
    }
}

/**
 *  load all saved beacons
 */
- (void)loadFoundBeacons
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSArray *urls = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSString *url = [NSString stringWithFormat:@"%@", urls[0]];
    NSURL *source = [NSURL URLWithString:[url stringByAppendingPathComponent:@"beacons.arc"]];

    NSData *data = [NSData dataWithContentsOfURL:source];
    if (data)
    {
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        CCObjectCache *savedBeacons = [unarchiver decodeObjectForKey:@"cachedBeacons"];
        if (savedBeacons)
            self.cachedBeacons = savedBeacons;
    }
}

- (void)addStatusBlock:(RVLBlueToothStatusBlock)block
{
    [self.statusBlocks addObject:block];

    if (self.central == nil)
    {
        NSDictionary *btOptions = @{};

        if (CBCentralManagerOptionShowPowerAlertKey != nil)
        {
            // Check that CBCentralManagerOptionShowPowerAlertKey is available b/c
            // it's weakly linked
            // (docs say you have to explicitly compare to nil, can't do
            // !CBCentralManagerOptionShowPowerAlertKey
            btOptions = @{ CBCentralManagerOptionShowPowerAlertKey : @NO,
                           CBCentralManagerOptionRestoreIdentifierKey: [NSString stringWithFormat:@"%@.status", [NSBundle mainBundle].bundleIdentifier] };
        }

        self.central = [[CBCentralManager alloc] initWithDelegate:self
                                                            queue:nil
                                                          options:btOptions];
    }
}

- (void)addBeacon:(NSString *)beaconID
{
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:beaconID];
    if (uuid)
    {
        CLBeaconRegion *beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:uuid
                                                                          identifier:beaconID];
        beaconRegion.notifyEntryStateOnDisplay = YES;
        
        if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedAlways /* || [CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorized */)
        {
            [[self locationManager] stopRangingBeaconsInRegion:beaconRegion];
            [[self locationManager] startMonitoringForRegion:beaconRegion];
        }
        
        [self.beaconRegions addObject:beaconRegion];
        
        // Commenting out because it seems like it is redundant to have requesting state as well as start Monitoring/ranging calls above
        //[[self locationManager] requestStateForRegion:beaconRegion];
    }
}

/**
 *  @brief Check to see if bluetooth is currently available
 *
 *  @return YES is Bluetooth is available and turned on
 */
- (BOOL) isBluetoothAvailable
{
    if ( ![self.status isEqualToString: @"Unsupported"] && ![self.status isEqualToString: @"Unauthorized"] && ![self.status isEqualToString: @"off"])
        return YES;
    else
        return NO;
}

- (void)locationManager:(CLLocationManager *)manager
    monitoringDidFailForRegion:(CLRegion *)region
                     withError:(NSError *)error
{
    // If we encounter an error here, we've hit our cap of monitoring
    [self stopIBeaconMonitoring];
    
    if ( [self isBluetoothAvailable] ) {
        
        for (CLBeaconRegion* region in self.beaconRegions) {
            [[self locationManager] startMonitoringForRegion:region];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error
{
    //VERBOSE( @"ERROR", @"RVLBeaconManager rangingBeaconsDidFailForRegion %@", error );
}

- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region
{
    [self processBeacons:beacons forRegion:region];
}

- (RVLCacheState) updateCacheWithBeacon:(RVLBeacon*)beacon
{
    RVLCacheState result = RVLCacheStateNew;
    RVLBeacon* existing = self.cachedBeacons[beacon.rvlUniqString];
    
    if ( existing )
    {
        if ( beacon.proximityInMeters < existing.proximityInMeters )
        {
            result = RVLCacheStateCloser;
            
            existing.proximityInteger = beacon.proximityInteger;
            existing.accuracy = beacon.accuracy;
            existing.discoveryTime = [NSDate date];
        }
        else
            result = RVLCacheStateExisting;
    }
    else
    {
        self.cachedBeacons[beacon.rvlUniqString] = beacon;
    }
    
    
    return result;
}

- (void) processBeacon:(RVLBeacon*) beacon
{
    RVLBeacon* realBeacon = [[self incompleteBeacons] valueForKey: beacon.rvlUniqString];
    
    if ( realBeacon )
    {
        LOG( @"BEACON", @"processBeacon combining %@ %@", beacon.type, beacon.rvlUniqString );
        [realBeacon combineWith: beacon];
    }
    else
    {
        LOG( @"BEACON", @"processBeacon new %@ %@", beacon.type, beacon.rvlUniqString );
        realBeacon = beacon;
    }
    
    BOOL readyToSend = [realBeacon readyToSend];
    
    if ( readyToSend || [beacon timeoutWaitingToSend] )
    {
        [self sendBeacon: realBeacon];
    }
    else
    {
        if ( self.incompleteBeacons == nil )
            self.incompleteBeacons = [NSMutableDictionary dictionary];
        
        self.incompleteBeacons[realBeacon.rvlUniqString] = realBeacon;
    }
}


- (void) saveIncompeteBeacon:(RVLBeacon*)beacon
{
    if ( self.incompleteBeacons == nil )
        self.incompleteBeacons = [NSMutableDictionary dictionary];
    
    self.incompleteBeacons[beacon.rvlUniqString] = beacon;
    
    [self scheduleTimerForBeacon: beacon];
}

- (void)sendBeacon:(RVLBeacon*)beacon
{
    RVLLog( @"Sending beacon found to Server: %@", beacon.rvlUniqString);
    
    if ( ![beacon location] )
        beacon.location = [[[Reveal sharedInstance] locationManager] userLocation];
    
    if ( ![beacon placemark] )
        beacon.placemark = [[[Reveal sharedInstance] locationManager] userPlacemark];
    
    id <RVLBeaconService> beaconManager = [[Reveal sharedInstance] beaconManager];
    
    if ( [[beaconManager delegate] respondsToSelector: @selector(foundBeaconOfType:identifier:data:)] )
        [[beaconManager delegate] foundBeaconOfType: beacon.type identifier: beacon.rvlUniqString data: [beacon dictionary]];
    
    [[RVLWebServices sharedWebServices] sendNotificationOfBeacon: beacon result:^(BOOL success, NSDictionary *result, NSError *error)
     {
         //If there was a failure, don't add beacon to "old" list, so that it will be sent again if it is found again
         if (success)
         {
             beacon.sentTime = [NSDate date];
             LOG( @"COMM", @"Beacon data sent successfully for %@", beacon.rvlUniqString );
             [Reveal sharedInstance].personas = objc_dynamic_cast(NSArray, [result objectForKey:@"personas"]);
             
             self.cachedBeacons[[beacon rvlUniqString]] = beacon;
             [self.incompleteBeacons removeObjectForKey: [beacon rvlUniqString]];
         }
         else
         {
             // TODO: handle resend here
         }
     }];
    
    [[self incompleteBeacons] removeObjectForKey: beacon.rvlUniqString];
}

- (void)processBeacons:(NSArray *)beacons forRegion:(CLBeaconRegion *)region
{
    NSString *regionKey = region.proximityUUID.UUIDString; // [RVLBlueToothManager revealKey: region.proximityUUID.UUIDString];
    LOG( @"INFO",@"Found iBeacon beacons in region: %@", regionKey );
    
    NSMutableDictionary *oldBeacons = [NSMutableDictionary dictionaryWithDictionary:[self.cachedBeacons dictionaryMatching:@{ @"group" : regionKey }]];
    
    BOOL dirtySet = NO;
    
    // Remove beacons in this region that have gone away
    BOOL lostBeacon;
    NSMutableArray *beaconsToRemove = [NSMutableArray array];
    
    for (NSString *uniqId in [oldBeacons allValues])
    {
        lostBeacon = YES;
        for (CLBeacon *beacon in beacons)
        {
            if ([uniqId isEqualToString:[RVLBeacon rvlUniqStringWithBeacon:beacon]])
            {
                lostBeacon = NO;
            }
        }
        if (lostBeacon)
        {
            dirtySet = YES;
            [beaconsToRemove addObject:uniqId]; // can't mutate oldBeacons while enumerating it
        }
    }
    for (NSString *uniqId in beaconsToRemove)
    {
        if ( [[self delegate] respondsToSelector: @selector(leaveBeaconOfType:identifier:)] )
        {
            RVLBeacon* beacon = self.cachedBeacons[uniqId];
            [[self delegate] leaveBeaconOfType: beacon.type identifier: beacon.rvlUniqString];
        }
        
        [self.cachedBeacons removeObjectForKey:uniqId];
    }
    
    // log new beacons
    for (CLBeacon *beacon in beacons)
    {
        RVLBeacon *rvl = [[RVLBeacon alloc] initWithBeacon:beacon];
        RVLBeacon* existing = self.cachedBeacons[rvl.rvlUniqString];
        
        if ( !existing )
            [rvl saveWhenReady];
    }
    
    //Once we have the beacons, we can stop ranging for the location until a new beacon comes in
    if ( ![[Reveal sharedInstance] useManagedBackgroundMode] )
    {
        [self.locationManager stopRangingBeaconsInRegion:region];
        [self.locationManager startMonitoringForRegion:region];
    }
    
    if (dirtySet)
        [self storeFoundBeacons];
}

- (void)processRawBeacon:(RevealScannerRawBeacon *)beacon
{
    // If the beacon is an eddystone, we get a partial beacon first, and then the full one, this check makes sure we only send the full beacons
    if (beacon.complete)
    {
        RVLBeacon *revealBeacon = [self beaconFromRawBeacon: beacon];
        
        NSString *uuidString = [beacon ident:1];
        if ([uuidString length])
            revealBeacon.proximityUUID = [[NSUUID alloc] initWithUUIDString:uuidString];
        
        revealBeacon.major = [beacon ident:2];
        revealBeacon.rssi = @([beacon rssi]);
        revealBeacon.accuracy = @-100.0;
        
        [revealBeacon calculateDistance];
        
        RVLBeacon* existing = self.cachedBeacons[revealBeacon.rvlUniqString];
        
        if ( !existing )
            [revealBeacon saveWhenReady];
    }
}


- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    if ( [region isKindOfClass: [CLBeaconRegion class]] )
    {
        if (state == CLRegionStateInside)
        {
            [self.locationManager stopMonitoringForRegion: region];
            [self.locationManager startRangingBeaconsInRegion: (CLBeaconRegion*)region];
        }
        else
        {
            if ( ![[Reveal sharedInstance] useManagedBackgroundMode] )
            {
                [self.locationManager stopRangingBeaconsInRegion: (CLBeaconRegion*)region];
                [self.locationManager startMonitoringForRegion: (CLBeaconRegion*)region];
            }
        }
    }
}

- (void)shutdownMonitor
{
    [self stopIBeaconMonitoring];
    
    // Stop non-iBeacon scanning
    [self stop];
}

- (void) stopIBeaconMonitoring {
    NSSet *ranged = [NSSet set];
    NSSet *monitored = [NSSet set];
    
    @synchronized(self)
    {
        if ([[self locationManager] rangedRegions])
            ranged = [NSSet setWithSet:[[self locationManager] rangedRegions]];
        
        if ([[self locationManager] monitoredRegions])
            monitored = [NSSet setWithSet:[[self locationManager] monitoredRegions]];
    }
    
    for (CLBeaconRegion *bRegion in ranged)
    {
        [[self locationManager] stopRangingBeaconsInRegion:bRegion];
    }
    
    for (CLRegion *region in monitored)
    {
        [self.locationManager stopMonitoringForRegion:region];
    }
}


- (void)timerExpired:(id)sender
{
    [self sendPendingBeacons];
}

- (void)sendPendingBeacons
{
    [self.timeoutTicker invalidate];
    self.timeoutTicker = nil;

    @synchronized(self)
    {
        NSArray *array = [NSArray arrayWithArray:self.pendingBeacons];
        if ([array count])
        {
            for (RVLBeacon *reveal in [NSArray arrayWithArray:self.pendingBeacons])
            {
                self.cachedBeacons[reveal.rvlUniqString] = reveal;

                [reveal saveWhenReady];
                [self.pendingBeacons removeObject:reveal];
            }
        }
    }
}

- (void) scheduleTimerForBeacon:(RVLBeacon*)beacon
{
    if ( ![[self sendTimer] isValid] )
    {
        [self clearTimer];
        
        id <RVLBeaconService> beaconManager = [[Reveal sharedInstance] beaconManager];
        self.sendTimer = [NSTimer scheduledTimerWithTimeInterval: beaconManager.proximityTimeout / 4.0
                                                          target: self
                                                        selector: @selector(minimumProximityAchieved)
                                                        userInfo: nil
                                                         repeats: YES];
    }
}

- (void) minimumProximityAchieved
{
    //[self clearTimer];

    for ( RVLBeacon* beacon in [NSArray arrayWithArray: [[self incompleteBeacons] allValues]] )
    {
        if ( [beacon timeoutWaitingToSend] )
        {
            [self processBeacon: beacon];
            
        }
    }
    
    if ( [[self incompleteBeacons] count] < 1 )
        [self clearTimer];
}


- (void) clearTimer
{
    if ( self.sendTimer )
        [self.sendTimer invalidate];
    
    self.sendTimer = nil;
}

#pragma mark -
#pragma mark - RevealScanner -
#pragma mark -

- (void)start
{
    if (self.scanDuration > 0.0)
    {
        // if we are iOS 8 or higher use a serial queue to be nice to the server
        if ( [[[UIDevice currentDevice] systemVersion] integerValue] < 8 )
            self.queue = dispatch_queue_create( "com.swirl", NULL );
        else
            self.queue = dispatch_queue_create("com.swirl", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos_class_main(), 0));
        
        // Use core bluetooth to get non iBeacon beacons
        self.central = [[CBCentralManager alloc] initWithDelegate:self
                                                            queue:self.queue
                                                          options:@{
                                                              CBCentralManagerOptionRestoreIdentifierKey : [NSString stringWithFormat:@"%@.beacons", [NSBundle mainBundle].bundleIdentifier]
                                                          }];

        [self.ticker invalidate];
        self.ticker = [NSTimer scheduledTimerWithTimeInterval:self.scanDuration
                                                       target:self
                                                     selector:@selector(scannerTimerExpired:)
                                                     userInfo:nil
                                                      repeats:NO];
    }
}

- (void)setScanDuration:(NSTimeInterval)scanDuration
{
    if (_scanDuration != scanDuration)
    {
        _scanDuration = scanDuration;
    }
}

- (void)setScanInterval:(NSTimeInterval)scanInterval
{
    if (_scanInterval != scanInterval)
    {
        _scanInterval = scanInterval;
    }
}

- (void)stop
{
    [self stopScanning];

    self.central = nil;
    self.queue = nil;
}

- (void)addVendorNamed:(NSString *)name withCode:(NSInteger)code
{
    self.vendors[@(code)] = name;
}

- (BOOL)startScanning
{
    BOOL result = NO;
    
    if (self.scanStarted == 0)
    {
        if ( [self isBluetoothAvailable] )
        {
            [self.central scanForPeripheralsWithServices:nil
                                                 options:nil];
            self.scanStarted = [NSDate date];
            result = YES;

            LOG( @"NOTICE",  @"RevealScanner startScanning called duration: %f iBeacon managed background %d ", self.scanDuration, [[Reveal sharedInstance] useManagedBackgroundMode] );
            
            if ( [[Reveal sharedInstance] useManagedBackgroundMode] )
            {
                for (CLBeaconRegion* region in self.beaconRegions)
                    [self.locationManager startRangingBeaconsInRegion: region];
            }
            
            [self checkForTimedOutBeacons];
        }
    }
    
    return result;
}

- (void) checkForTimedOutBeacons
{
    // search for all partial beacons that are older than 30 seconds so that
    // they can be transmitted as partials (since some eddy stones) do not send
    // all of the components).
    for( NSString* key in self.bluetoothDevices.dictionary.allKeys )
    {
        RevealScannerRawBeacon* beacon = [self.bluetoothDevices[key] beacon];
        if ( !beacon.complete && ( [beacon age] > [[RVLBeaconManager sharedManager] eddystoneTimeOut] ) )
        {
            // we must have only got one part, so we are going to consider this one complete
            beacon.complete = YES;
            [self processRawBeacon: beacon];
            
        }
    }
}

- (void)stopScanning
{
    if (self.scanStarted)
    {
        [self.central stopScan];
        self.scanStarted = nil;
        
        if (self.ticker)
            [self.ticker invalidate];
        //RVLLog( @"RevealScanner stopScanning called interval: %f", self.scanInterval );
        
        
        
        if ( [[Reveal sharedInstance] useManagedBackgroundMode] )
        {
            for (CLBeaconRegion* region in self.beaconRegions)
                [self.locationManager stopRangingBeaconsInRegion: region];
        }
    }
}



- (void)scannerTimerExpired:(id)sender
{
    if (self.scanStarted)
    {
        [self stopScanning];

        if (self.scanInterval > 0.0)
        {
            [self.ticker invalidate];
            self.ticker = [NSTimer scheduledTimerWithTimeInterval:self.scanInterval
                                                           target:self
                                                         selector:@selector(scannerTimerExpired:)
                                                         userInfo:nil
                                                          repeats:NO];
        }
    }
    else
    {
        if ( [self startScanning] )
        {
            if (self.scanDuration > 0.0)
            {
                [self.ticker invalidate];
                self.ticker = [NSTimer scheduledTimerWithTimeInterval:self.scanDuration
                                                               target:self
                                                             selector:@selector(scannerTimerExpired:)
                                                             userInfo:nil
                                                              repeats:NO];
            }
        }
        else
        {
            if (self.scanInterval > 0.0)
            {
                [self.ticker invalidate];
                self.ticker = [NSTimer scheduledTimerWithTimeInterval:self.scanInterval
                                                               target:self
                                                             selector:@selector(scannerTimerExpired:)
                                                             userInfo:nil
                                                              repeats:NO];
            }
        }
    }
}

#pragma mark - core bluetooth delegate -

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    self.hasBluetooth = NO;
    switch (central.state)
    {
        case CBCentralManagerStateUnknown:
            self.status = @"Unknown";
            break;
        case CBCentralManagerStateResetting:
            self.status = @"Resetting";
            break;
        case CBCentralManagerStateUnsupported:
            self.status = @"Unsupported";
            break;
        case CBCentralManagerStateUnauthorized:
            self.status = @"Unauthorized";
            break;
        case CBCentralManagerStatePoweredOff:
            self.status = @"Off";
            break;
        case CBCentralManagerStatePoweredOn:
            self.status = @"On";
            self.hasBluetooth = YES;
            break;
        default:
            self.status = @"State failure!";
            break;
    }
    
    LOG(@"DEBUG", @"BT Central Manager did update state, new state is %@", self.status);
    
    for (RVLBlueToothStatusBlock block in self.statusBlocks)
    {
        block((CBCentralManagerState) central.state);
    }
    
    if (self.central.state == CBCentralManagerStatePoweredOn)
        [self startScanning];
}

- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary *)state
{
    if ([state objectForKey:CBCentralManagerRestoredStateScanServicesKey] != nil)
        self.scanStarted = [NSDate date];
    ;
}

- (RVLBeacon* _Nullable) beaconFromRawBeacon:(RevealScannerRawBeacon* _Nonnull)beacon
{
    RVLBeacon* result = nil;
    
    if ( beacon.vendorCode == BEACON_SERVICE_EDDYSTONE )
    {
        result = [[RVLEddyStoneBeacon alloc] initWithRawBeacon:beacon];
    }
    else if ( beacon.vendorCode == BEACON_SERVICE_TILE )
    {
        result = [[RVLTileBeacon alloc] initWithRawBeacon:beacon];
    }
    else
    {
        result = [[RVLSecurecastBeacon alloc] initWithRawBeacon:beacon];
    }
    
    return result;
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)originalPeripheral
     advertisementData:(NSDictionary *)advertisement
                  RSSI:(NSNumber *)rssi
{
    @synchronized ( self )
    {
        int rssiInt = [rssi intValue];

    __strong CBPeripheral* peripheral = originalPeripheral;
        NSString *name = advertisement[@"kCBAdvDataLocalName"];
        NSData *data = advertisement[CBAdvertisementDataManufacturerDataKey];
        NSArray *uuids = advertisement[CBAdvertisementDataServiceUUIDsKey];
        securecastBeaconHeader_t *header = nil;
        NSString *beaconType = nil;

        RevealBluetoothObject *device = nil;
        
        if ( [data length] )
            header = (securecastBeaconHeader_t *)data.bytes;

        if (self.bluetoothDevices == nil)
            self.bluetoothDevices = [CCObjectCache<NSString *, RevealBluetoothObject *> new];

        NSString *pid = [peripheral.identifier UUIDString];

        device = self.bluetoothDevices[pid];

        if (!device)
            device = [RevealBluetoothObject new];

        device.identifier = pid;
        device.peripheral = peripheral;
        device.advertisement = advertisement;
        device.dateTime = [NSDate date];
        device.uuids = uuids;
        device.count++;

        NSDictionary *adv = device.advertisement[@"kCBAdvDataServiceData"];
        NSMutableDictionary *services = [NSMutableDictionary dictionary];
        [device setServices:services];
        
        NSData *tileData = nil;

        for (CBUUID *service in adv)
        {
            services[service.UUIDString] = adv[service];
        }
        
        for( CBUUID * service in uuids )
        {
            device.serviceUUID = service.UUIDString;
            
            if ( [device.serviceUUID isEqualToString: BEACON_SERVICE_TILE_STRING] )
                tileData = [NSData new];
        }

        NSData *serviceData = nil;
        NSData *eddyData = services[BEACON_SERVICE_EDDYSTONE_STRING];

        if (self.captureAllDevices || eddyData || tileData || device.serviceUUID )
            self.bluetoothDevices[pid] = device;

        if (self.captureAllDevices && device.connectable)
        {
            peripheral.delegate = device;

            [self.central cancelPeripheralConnection:peripheral];
            [self.central connectPeripheral:peripheral options:nil];
        }
        
        // DEBUG: this line is useful when debugging blutooth issues
        //VERBOSE( @"INFO", @"Bluetooth device: %@ - %@\nServices:\n%@\nUUIDs:\n%@", device.identifier, device.name, services, uuids );

        if (self.foundDevice)
            self.foundDevice(self, advertisement, peripheral);

        if ( eddyData || tileData )
        {
            // handle eddystone and tile
            RevealScannerRawBeacon *beacon = nil;
            
            if ( tileData )
            {
                serviceData = tileData;
                beacon = [self tileStoneBeaconWithPeripheral: peripheral
                                           advertisementData: advertisement
                                                        RSSI: rssiInt
                                                        data: tileData];
            }
            else if ( eddyData )
            {
                serviceData = eddyData;
                beacon = [self eddyStoneBeaconWithPeripheral:peripheral
                                           advertisementData:advertisement
                                                        RSSI:rssiInt
                                                        data:eddyData];
            }
            
            if ( beacon )
            {
                beacon.uuids = uuids;
                beacon.services = services;
                

                if (device)
                    device.beacon = beacon;

                if ( beacon.complete )
                {
                    [self processRawBeacon: beacon];
                }
            }
        }
        else if (header)
        {
            BOOL secureCast = NO;
            
            // handle others
            beaconType = self.vendors[@(header->vendor)];
            
            if ( beaconType == nil )
            {
                NSArray* suuids = device.advertisement[@"kCBAdvDataServiceUUIDs"];
                
                if ( [suuids isKindOfClass: [NSArray class]] )
                {
                    for (CBUUID *service in suuids )
                    {
                        unsigned serviceCode = 0;
                        NSScanner *scanner = [NSScanner scannerWithString:service.UUIDString];
                        
                        [scanner scanHexInt: &serviceCode];
                        beaconType = self.vendors[@(serviceCode)];
                        
                        if ( beaconType )
                        {
                            secureCast = YES;
                            break;
                        }
                    }
                }
            }

            if ((beaconType == nil) && self.includeUnknownVendors)
                beaconType = name;

            if (beaconType || self.includeUnknownVendors || secureCast )
            {
                RevealScannerRawBeacon *beacon = [RevealScannerRawBeacon new];
                
                if ( ( beaconType == nil ) && secureCast )
                    beaconType = @"SecureCast";

                beacon.vendorName = beaconType;
                beacon.vendorCode = header->vendor;
                beacon.key = header->key;
                beacon.payload = [NSData dataWithBytes:header->payload length:sizeof(header->payload)];
                beacon.advertisement = advertisement;
                beacon.uuids = uuids;
                beacon.rssi = rssiInt;
                beacon.bluetoothIdentifier = peripheral.identifier;
                beacon.services = services;
                
                beacon.complete = YES;
                
                if ( secureCast )
                {
                    beacon.vendorId = [NSString stringWithFormat: @"%x", header->key];
                    
                    // DEBUG: this item should be uncommented if debugging Securcast beacon issues
                    //VERBOSE( @"INFO", @"Bluetooth raw beacon: %@ - %@\n    SD=%@\n  Data=%@\nAdvertisement:\n%@", device.identifier, device.name, serviceData, data, advertisement );
                }

                if (device)
                    device.beacon = beacon;

                [self processRawBeacon: beacon];
            }
            else
            {
                VERBOSE(@"WARNING", @"Excluded potential beacon: %d: %@ (%d)", (int)header->vendor, name, (int)header->key );
            }
        }
        else if (self.showUnknownDevices)
        {
            NSMutableString *debugStr = [NSMutableString string];

            [debugStr appendFormat:@"CBPeriperal: %@ %d ", peripheral, rssiInt];

            if (header)
                [debugStr appendFormat:@"[id: %d key: %d] ", header->vendor, header->key];

            if (data)
                [debugStr appendFormat:@"DATA: %@ ", [data base64EncodedStringWithOptions:0]];

            for (id uuid in uuids)
                [debugStr appendFormat:@"\n    %@ ", uuid];

            if ([advertisement count] > 0)
                [debugStr appendFormat:@"\n%@", advertisement];

            LOG(@"DEBUG", @"Unknown bluetooth device:\n%@", debugStr);
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    RevealBluetoothObject *per = self.bluetoothDevices[peripheral.identifier.UUIDString];
    LOG(@"DEBUG", @"Connected to %@ named: %@", peripheral.identifier.UUIDString, peripheral.name);

    if (peripheral.services)
    {
        if (per)
            [per peripheral:peripheral didDiscoverServices:nil]; //already discovered services, DO NOT re-discover. Just pass along the peripheral.
    }
    else
    {
        [peripheral discoverServices:nil]; //yet to discover, normal path. Discover your services needed
    }
}

- (RevealScannerRawBeacon *)tileStoneBeaconWithPeripheral:(CBPeripheral *)peripheral
                                        advertisementData:(NSDictionary *)advertisement
                                                     RSSI:(int)rssiInt
                                                     data:(NSData *)serviceData
{
    // handle tile
    RevealScannerRawBeacon *beacon = nil;
    RevealBluetoothObject *cachedObject = self.bluetoothDevices[peripheral.identifier.UUIDString];
    
    if (cachedObject)
        beacon = cachedObject.beacon;
    
    if (!beacon)
        beacon = [RevealScannerRawBeacon new];
    
    beacon.vendorName = @"Tile";
    
    beacon.vendorCode = BEACON_SERVICE_TILE;
    beacon.payload = serviceData;
    beacon.advertisement = advertisement;
    beacon.rssi = rssiInt;
    beacon.bluetoothIdentifier = peripheral.identifier;
    beacon.characteristics = cachedObject.characteristics;
    if (beacon.bluetoothIdentifier == nil)
        beacon.extendedData = [NSMutableDictionary dictionary];
    
    beacon.payload = serviceData;

    
    beacon.complete = YES;
    
    return beacon;
}

- (RevealScannerRawBeacon *)eddyStoneBeaconWithPeripheral:(CBPeripheral *)peripheral
                                        advertisementData:(NSDictionary *)advertisement
                                                     RSSI:(int)rssiInt
                                                     data:(NSData *)originalServiceData
{
    // handle eddystone
    RevealScannerRawBeacon *beacon = nil;
    
    @synchronized ( self )
    {
        RevealBluetoothObject *cachedObject = self.bluetoothDevices[peripheral.identifier.UUIDString];
    __strong NSData* serviceData = originalServiceData;

        if (cachedObject)
            beacon = cachedObject.beacon;

        if (!beacon)
            beacon = [RevealScannerRawBeacon new];

        beacon.vendorName = @"Eddystone";

        beacon.vendorCode = BEACON_SERVICE_EDDYSTONE;
        beacon.payload = serviceData;
        beacon.advertisement = advertisement;
        beacon.rssi = rssiInt;
        beacon.bluetoothIdentifier = peripheral.identifier;
        beacon.characteristics = cachedObject.characteristics;
        if (beacon.bluetoothIdentifier == nil)
            beacon.extendedData = [NSMutableDictionary dictionary];

        unsigned char const *data = serviceData.bytes;
    
    //LOG( @"STANDOUT", @"EDDYSTONE type %x found", (unsigned int) *data );

        if (data)
        {
            switch (*data)
            {
                case EDDYSTONE_UID:
                    // UID
                    {
                        NSMutableString *ns = [NSMutableString new];
                        for (int i = 2; i < 12; i++)
                            [ns appendFormat:@"%02X", data[i]];

                        NSMutableString *instance = [NSMutableString new];
                        for (int i = 12; i < 18; i++)
                            [instance appendFormat:@"%02X", data[i]];

                        if (beacon.extendedData == nil)
                            beacon.extendedData = [NSMutableDictionary dictionary];

                        beacon.extendedData[@"namespace"] = ns;
                        beacon.extendedData[@"instance"] = [NSString stringWithFormat: @"0x%@", instance];
                        
                        
                        //VERBOSE( @"STANDOUT", @"Partial eddystone (UID): %@ : %@", ns, instance);
                        
                        if (beacon.url)
                            beacon.complete = YES;
                    }

                    break;

                case EDDYSTONE_URL:
                    // URL
                    {
                        NSURL* url = [RVLBeaconManager urlFromEddyStoneEncoding:data + 2 count:[serviceData length] - 2];
                        if ( [url isKindOfClass:[NSURL class]] )
                        {
                        beacon.url = url;
                            
                        //VERBOSE( @"STANDOUT", @"Partial eddystone (URL): %@ : %@", beacon.identifier, beacon.url );
                        beacon.complete = YES;
                        }
                    }
                    break;

                case EDDYSTONE_TLM:
                    // TLM
                    //VERBOSE( @"STANDOUT", @"Partial eddystone (TLM): %@ : %@", beacon.identifier, serviceData );
                    break;

                default:
                    break;
            }
        }
    }

    return beacon;
}

- (NSString *)descriptionWithDetails:(BOOL)includeDetails includeUnknowns:(BOOL)unknowns
{
    NSMutableString *result = [NSMutableString stringWithFormat:@"%@ duration: %f interval: %f",
                                                                [super description], [self scanDuration], [self scanInterval]];

    if (includeDetails)
    {
        NSDictionary *devices = [self.bluetoothDevices dictionary];

        for (RevealBluetoothObject *device in [devices allValues])
        {
            if (device.beacon || device.peripheral.name || [device.advertisement count] > 1 || unknowns)
            {
                [result appendFormat:@"\n    %@", device.identifier];
                if (device.peripheral.name)
                    [result appendFormat:@" \"%@\"", device.peripheral.name];

                if (device.beacon)
                {
                    [result appendFormat:@"=BEACON %ld", (long)device.beacon.vendorCode];

                    if (device.beacon.vendorCode)
                        [result appendFormat:@" %@", device.beacon.vendorName];

                    if (device.beacon.local)
                        [result appendFormat:@" local: %ld key: %ld", (long)device.beacon.local, (long)device.beacon.key];

                    if (device.beacon.payload)
                        [result appendFormat:@" payload: %@", device.beacon.payload];
                }
                else if ([device.advertisement isKindOfClass:[NSDictionary class]])
                {
                    id mfgData = device.advertisement[@"kCBAdvDataManufacturerData"];
                    if (mfgData)
                        [result appendFormat:@"MFG: %@", mfgData];

                    NSDictionary *adv = device.advertisement[@"kCBAdvDataServiceData"];
                    if (adv)
                    {
                        for (NSString *key in adv)
                        {
                            [result appendFormat:@" %@:\"%@\"=%@", [key class], key, adv[key]];
                        }
                    }

                    NSArray *uuids = device.advertisement[@"kCBAdvDataServiceUUIDs"];
                    if (uuids)
                    {
                        [result appendString:@" UUIDS:"];
                        for (id uuid in uuids)
                            [result appendFormat:@" %@", uuid];
                    }

                    for (CBService *service in device.peripheral.services)
                    {
                        [result appendFormat:@"\n   %@", service];
                    }

                    //                    if ( device.peripheral.name )
                    //                        [result appendFormat: @"\n%@", device.advertisement ];
                }
            }
        }
    }

    return result;
}

- (NSString *)description
{
    return [self descriptionWithDetails:YES includeUnknowns:NO];
}

+ (NSURL *)urlFromEddyStoneEncoding:(const unsigned char *)bytes count:(NSInteger)count
{
    NSMutableString *urlString = [NSMutableString string];
    NSArray *schemePrefixes = @[
        @"http://www.",
        @"https:/www.",
        @"http://",
        @"https://"
    ];

    NSArray *urlEncodings = @[
        @".com/",
        @".org/",
        @".edu/",
        @".net/",
        @".info/",
        @".biz/",
        @".gov/",
        @".com",
        @".org",
        @".edu",
        @".net",
        @".info",
        @".biz",
        @".gov"
    ];

    [urlString appendString:schemePrefixes[*bytes % [schemePrefixes count]]];

    for (int i = 1; i < count; i++)
    {
        char c = bytes[i];

        if (c < [urlEncodings count])
            [urlString appendString:urlEncodings[c]];
        else
            [urlString appendFormat:@"%c", c];
    }

    return [NSURL URLWithString:urlString];
}

@end

@implementation CurveFittedDistanceCalculator

- (instancetype) init
{
    self = [super init];
    
    if ( self )
    {
        self.txPower = -47;
        
        self.mCoefficient1 = 0.8229884;
        self.mCoefficient2 = 6.6525179;
        self.mCoefficient3 = 0.1820634;
    }
    
    return self;
}

- (double) calculateDistanceWithRSSI: (double) rssi
{
    return [self calculateDistanceWithPower: self.txPower andRSSI: rssi];
}

- (double) calculateDistanceWithPower:(int)txPower andRSSI: (double) rssi
{
    if ( (rssi == 0) || ( rssi == 127 ) )
        return -1.0; // if we cannot determine accuracy, return -1.
    
    double ratio = fabs( rssi*1.0/txPower );
    double distance;
    if (ratio < 1.0) {
        distance =  pow(ratio,10);
    }
    else {
        distance =  (self.mCoefficient1)*pow(ratio, self.mCoefficient2) + self.mCoefficient3;
    }
    
    // DEBUG: this debug is useful in testing so enable it to debug distance calculations
    //RVLLog( @"calculateDistanceWithPower: %d RSSI: %0.4f - ratio=%.6f distance=%.3f", (int)txPower, (float)rssi, (float)ratio, (float)distance );
    
    return distance;
}

@end

#pragma mark - Third Party code -
#pragma mark CCObjectCacheEntry -

/**   CCObjectCache.m
 Copyright (c) 2016 CrossComm, Inc.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

@interface CCObjectCacheEntry : NSObject <NSCoding>

@property (nonatomic, strong) id<NSCopying> key;
@property (nonatomic, strong) id object;
@property (nonatomic, strong) NSDate *dateIn;
@property (nonatomic, strong) NSDate *dateOut;
@property (nonatomic, strong) NSMutableDictionary *tags;

- (void)setTagNamed:(NSString *)tagName to:(id<NSObject>)value;

- (id<NSObject>)valueForTag:(NSString *)tagName;

- (BOOL)match:(NSDictionary *)tags;

@end

@implementation CCObjectCacheEntry

- (instancetype)init
{
    return [super init];
}

- (void)setTagNamed:(NSString *)tagName to:(id<NSObject>)value
{
    if (!self.tags)
        self.tags = [NSMutableDictionary dictionary];

    self.tags[tagName] = value;
}

- (id<NSObject>)valueForTag:(NSString *)tagName
{
    return [[self tags] valueForKey:tagName];
}

- (BOOL)match:(NSDictionary *)tags
{
    for (NSString *tagsKey in [tags allKeys])
    {
        id<NSObject> tagValue = [[self tags] valueForKey:tagsKey];

        if (!tagValue)
            return NO;

        if (![tagValue isEqual:tags[tagsKey]])
            return NO;
    }

    return YES; // multiple returns
}

#pragma mark - NSCoding -

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.key forKey:@"key"];
    [coder encodeObject:self.object forKey:@"object"];
    [coder encodeObject:self.dateIn forKey:@"dateIn"];
    [coder encodeObject:self.dateOut forKey:@"dateOut"];
    [coder encodeObject:self.tags forKey:@"tags"];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [self init];

    if (self)
    {
        self.key = [decoder decodeObjectForKey:@"key"];
        self.object = [decoder decodeObjectForKey:@"object"];
        self.dateIn = [decoder decodeObjectForKey:@"dateIn"];
        self.dateOut = [decoder decodeObjectForKey:@"dateOut"];
        self.tags = [decoder decodeObjectForKey:@"tags"];
    }

    return self;
}

@end

#pragma mark - Object Cache -

@interface CCObjectCache <KeyType, ObjectType>
()

    @property(nonatomic, strong) NSMutableDictionary<KeyType, CCObjectCacheEntry *> *items;

@end

@implementation CCObjectCache

- (id)init
{
    self = [super init];

    if (self)
    {
        self.resetOnEveryAccess = NO;
        self.resetOnEveryAdd = NO;
        self.cacheTime = 1.0 * 60.0 * 60.0;
        self.items = [NSMutableDictionary dictionary];
    }

    return self;
}

- (id)objectForKey:(id<NSCopying>)key
{
    [self purgeOld];

    id result = nil;
    CCObjectCacheEntry *entry = self.items[key];
    NSDate *now = [NSDate date];

    if (entry)
    {
        if (self.resetOnEveryAccess)
            entry.dateOut = [NSDate dateWithTimeInterval:self.cacheTime
                                               sinceDate:now];

        result = entry.object;

        if ([self.delegate respondsToSelector:@selector(objectCache:willAccessObject:)])
            [self.delegate objectCache:self willAccessObject:entry.object];
    }

    return result;
}

- (BOOL)setObject:(id)obj forKey:(id<NSCopying>)key
{
    //NSAssert( [obj conformsToProtocol: @protocol(NSCoding)], @"Object is does not implement <NSCoding>:\n%@", obj );
    [self purgeOld];

    BOOL result = NO;
    CCObjectCacheEntry *entry = self.items[key];
    NSDate *now = [NSDate date];

    if (entry)
    {
        if (self.resetOnEveryAdd)
            entry.dateOut = [NSDate dateWithTimeInterval:self.cacheTime
                                               sinceDate:now];
    }
    else
    {
        entry = [CCObjectCacheEntry new];

        entry.key = key;
        entry.object = obj;
        entry.dateIn = now;
        entry.dateOut = [NSDate dateWithTimeInterval:self.cacheTime
                                           sinceDate:now];

        [self.items setObject:entry forKey:key];

        if ([self.delegate respondsToSelector:@selector(objectCache:didAddObject:)])
            [self.delegate objectCache:self didAddObject:obj];

        result = YES;
    }

    return result;
}

- (void)removeObjectForKey:(id<NSCopying>)aKey
{
    [self.items removeObjectForKey:aKey];
}

- (void)loadWithDictionary:(NSDictionary *)dict
{
    for (id<NSCopying> key in dict)
        self[key] = dict[key];
}

- (NSDictionary *)dictionary
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[[self items] count]];

    for (id<NSCopying> key in [[self items] allKeys])
        result[key] = self[key];

    return result;
}

- (NSDictionary *)dictionaryMatching:(NSDictionary *)matchCriteria
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[[self items] count]];

    for (id<NSCopying> key in [[self items] allKeys])
    {
        CCObjectCacheEntry *entry = self.items[key];

        if ([entry match:matchCriteria])
            result[key] = entry.object;
    }

    return result;
}

+ (CCObjectCache *)objectCacheWithDictionary:(NSDictionary *)dict
{
    CCObjectCache *result = [CCObjectCache new];

    [result loadWithDictionary:dict];

    return result;
}

// remove old cached entries - this wil get called on each access - it could be
// called on a timer to allow entries to go away faster, but then we would steal
// time in the background. Which may not be desirable.
- (void)purgeOld
{
    NSDate *now = [NSDate date];

    if ( [[self items] count] > 0 )
    {
        for (CCObjectCacheEntry *item in [NSArray arrayWithArray:[[self items] allValues]])
        {
            if ([now compare:item.dateOut] == NSOrderedDescending)
            {
                //VERBOSE( @"DEBUG", @"purgeOld removing %@ with out time: %@", item.key, item.dateOut);

                if ([self.delegate respondsToSelector:@selector(objectCache:willRemoveObject:)])
                    [self.delegate objectCache:self willRemoveObject:item.object];

                [[self items] removeObjectForKey:item.key];
            }
        }
    }
}

- (BOOL)setValue:(id<NSObject>)value forTag:(NSString *)tagName forKey:(id<NSCopying>)key
{
    BOOL result = false;
    CCObjectCacheEntry *entry = self[key];

    if (entry)
    {
        [entry setTagNamed:(NSString *)key to:value];
        result = true;
    }

    return result;
}

- (id<NSObject>)valueForTag:(NSString *)tagName forKey:(id<NSCopying>)key
{
    id<NSObject> result = nil;
    CCObjectCacheEntry *entry = self[key];

    if (entry)
        result = [entry valueForTag:tagName];

    return result;
}

- (NSDictionary *)tagsForKey:(id<NSCopying>)key
{
    NSDictionary *result = nil;
    CCObjectCacheEntry *entry = self[key];

    if (entry)
        result = entry.tags;

    return result;
}

- (BOOL)setTags:(NSDictionary *)tags forKey:(id<NSCopying>)key
{
    BOOL result = false;
    CCObjectCacheEntry *entry = self.items[key];

    if (entry)
    {
        entry.tags = [NSMutableDictionary dictionaryWithDictionary:tags];
        result = true;
    }

    return result;
}

#pragma mark - debugging support -

- (NSString *)descriptionWithDetails:(BOOL)showDetails
{
    NSMutableString *result = [NSMutableString stringWithFormat:@"%@ Contains %ld items", [super description], (long)[[self items] count]];

    if (showDetails)
    {
        NSArray *array = [[[self items] allValues] sortedArrayWithOptions:NSSortStable
                                                          usingComparator:^NSComparisonResult(CCObjectCacheEntry *obj1, CCObjectCacheEntry *obj2) {
                                                            return [obj1.dateOut compare:obj2.dateOut];
                                                          }];

        for (CCObjectCacheEntry *entry in array)
        {
            [result appendFormat:@"\n    %@ (%@) = %@ %p", entry.key, entry.dateOut, [entry.object class], entry.object];
        }
    }

    return result;
}

- (NSString *)description
{
    return [self descriptionWithDetails:YES];
}

#pragma mark - modern obj-c -

- (void)setObject:(id)obj forKeyedSubscript:(id)key
{
    [self setObject:obj forKey:key];
}

- (id)objectForKeyedSubscript:(id)key
{
    return [self objectForKey:key];
}

#pragma mark - NSCoding -

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:self.cacheTime forKey:@"cacheTime"];
    [coder encodeBool:self.resetOnEveryAccess forKey:@"resetOnEveryAccess"];
    [coder encodeBool:self.resetOnEveryAdd forKey:@"resetOnEveryAdd"];
    [coder encodeObject:self.items forKey:@"items"];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [self init];

    if (self)
    {
        self.cacheTime = [decoder decodeDoubleForKey:@"cacheTime"];
        self.resetOnEveryAccess = [decoder decodeBoolForKey:@"resetOnEveryAccess"];
        self.resetOnEveryAdd = [decoder decodeBoolForKey:@"resetOnEveryAdd"];
        self.items = [decoder decodeObjectForKey:@"items"];
    }

    return self;
}

@end
