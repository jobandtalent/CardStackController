//
//  RevealSDK.h
//  RevealSDK
//
//  Created by Sean Doherty on 1/8/2015.
//  Copyright (c) 2015 StepLeader Digital. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

//! Project version number for Reveal9Plus.
FOUNDATION_EXPORT double RevealVersionNumber;

//! Project version string for Reveal9Plus.
FOUNDATION_EXPORT const unsigned char RevealVersionString[];


#ifndef INCLUDE_REVEAL_LOCATION_MANAGER
#define INCLUDE_REVEAL_LOCATION_MANAGER     1
#endif

@class CLPlacemark;
@class CLBeacon;
@class CLBeaconRegion;
@class CBPeripheral;
@class CLLocation;
@class RevealBluetoothObject;
@class RVLBeacon;
@class Reveal;
@class CurveFittedDistanceCalculator;

#define RVL_IMMEDIATE_RADIUS                    3.0
#define RVL_NEAR_RADIUS                         15.0
#define RVL_FAR_RADIUS                          100.0
#define RVL_UNKNOWN_RADIUS                      99999999999.0

//TODO: decide if we need the <NSObject>... look at apple delegate examples
@protocol RVLBeaconDelegate <NSObject>
@optional
- (void) foundBeaconOfType:(NSString* _Nonnull) type identifier:(NSString* _Nonnull) identifier data:(NSDictionary* _Nullable) data;

@optional
- (void) leaveBeaconOfType:(NSString*  _Nonnull) type identifier:(NSString*  _Nonnull) identifier;

@end

@protocol RVLBeaconService <NSObject>

/**
 *  A delegate to receive callbacks when beacons are found
 */
@property (nonatomic, weak, nullable) id <RVLBeaconDelegate> delegate;

/**
 *  The time that you will wait before sending a beacon that is not "near"
 */
@property (nonatomic, assign) NSTimeInterval proximityTimeout;

//TODO: finish refactoring to these interfaces
//- (void) startBeaconScanning:(NSArray *  _Nullable)targetBeacons;

//TODO: finish refactoring to these interfaces
//- (void) stopBeaconScanning;

/**
 Send the specified beacon to the server

 @param beacon the beacon to send
 */
//- (void)sendBeacon:(RVLBeacon*)beacon;


- (void) processBeacon:(RVLBeacon* _Nonnull) beacon;

/**
 Save a beacon that isn't ready to be sent yet

 @param beacon the beacon to send
 */
- (void)saveIncompeteBeacon:(RVLBeacon* _Nonnull)beacon;

@end

@protocol RVLLocationService <NSObject>

/**
 *  The last known location for the current user
 */
@property (nonatomic, strong, nullable) CLLocation *userLocation;

/**
 *  The address (placemark) to be passed to the server
 */
@property (nonatomic, strong, nullable) CLPlacemark *userPlacemark;

/**
 *  The time the location time shuld be considered valid
 */
@property (nonatomic, assign) NSTimeInterval locationRetainTime;

/**
 *  Start monitoring location services. If your bundle contains the
 *  NSLocationWhenInUseUsageDescription string then requestWhenInUseAuthorization
 *  will be called, otherwise if NSLocationAlwaysUsageDescription is provided
 *  then requestAlwaysAuthorization will be called. If neither string is present
 *  then location services will net be started.
 */
- (void) startLocationMonitoring;

/**
 *  stop monitoring location changes
 */
- (void) stopLocationMonitoring;

/**
 *  Allows functions that need a valid location to wait for a valid location to be available (placemark if possible)
 *  If there is already a valid location available, then the callback returns immediately, otherwise, the callback waits until
 *  there is a valid location or a timeout, in which case the best location we can find will be used
 *
 *  @param callback The method to call when a valid location is available
 */
- (void) waitForValidLocation:( void (^ _Nullable)())  callback;

@end

/**
 *  Server selection
 */
typedef NS_ENUM(NSInteger, RVLServiceType) {
    /**
     *  Server for testing only
     */
    RVLServiceTypeSandbox,
    /**
     *  Server for real world use
     */
    RVLServiceTypeProduction
};


//  Location manager constants
typedef NS_ENUM(NSInteger, RVLLocationServiceType) {
    // Location disabled
    RVLLocationServiceTypeNone = 0,
    
    // While in use location detection selected
    RVLLocationServiceTypeInUse,
    
    //  Always location detection selected
    RVLLocationServiceTypeAlways
};

@interface Reveal : NSObject

/**
 *  The server you wish to connect to, may be
 *  RVLServiceTypeProduction or RVLServiceTypeSandbox
 */
@property (assign,nonatomic) RVLServiceType serviceType;

/**
 *  Array of strings, each containing a UUID.  These UUIDs
 *  will override the list retrieved from the Reveal
 *  server.  This is useful to debug/verify that the SDK
 *  can detect a known iBeacon when testing.  This is a
 *  development feature and should not be used in production.
 *  In order to override the UUIDs from the server, this
 * property should be set before starting the service.
 */
@property (nonatomic, strong, nullable) NSArray <NSString*> *debugUUIDs;

/**
 *  Debug flag for the SDK.  If this value is YES, the SDK
 *  will log debugging information to the console.
 *  Default value is NO.
 *  This can be toggled during the lifetime of the SDK usage.
 */
@property (nonatomic, assign) BOOL debug;

/**
 *  An option to allow a developer to manually disable beacon scanning
 *  Default value is YES
 */
@property (nonatomic, assign) BOOL beaconScanningEnabled;

/**
 *  Accessor properties for the SDK.
 *  At any time, the client can access the list of errors
 *  and the list of personas.  Both are arrays of NSStrings.
 *  Values may be nil.
 */
@property (nonatomic, strong, nullable) NSArray <NSString*> *personas;

/**
 *  get the version of the SDK
 */
@property (nonatomic, strong, nonnull) NSString* version;

/**
 *  The location manager to use for retrieving the current location.
 */
@property (nonatomic, strong, nullable) id <RVLLocationService> locationManager;

/**
 *  The delegate is called whenever beacons are discovered or removed
 */
@property (nonatomic, weak, nullable) id <RVLBeaconDelegate> delegate;

/**
 *  The active beacon manager
 */
@property (nonatomic, strong, nullable) id <RVLBeaconService> beaconManager;

@property (readonly, nullable) CurveFittedDistanceCalculator* distanceCalculator;

/**
 *  SDK singleton.  All SDK access should occur through this object.
 *
 *  @return the instance
 */
+ (Reveal* _Nonnull) sharedInstance;

/**
 *  Start the SDK with the specified SDK
 *
 *  @param key the API key
 *
 */
-(Reveal* _Nonnull) setupWithAPIKey:(NSString* _Nonnull) key;

/**
 *  Start the SDK with the specified SDK
 *
 *  @param key         the API key
 *  @param serviceType The type
 */
-(Reveal* _Nonnull) setupWithAPIKey:(NSString* _Nonnull) key andServiceType:(RVLServiceType) serviceType;

/**
 *  Start the SDK service.  The SDK will contact the API and retrieve
 *  further configuration info.  Background beacon scanning will begin
 *  and beacons will be logged via the API.
 */
-(void) start;

/**
 *   Notify the SDK that the app is restarting.  To be called in applicationDidBecomeActive
 */
-(void) restart;

/**
 *  list of beacons encountered for debugging only
 */
- (NSDictionary *  _Nullable) beacons;

/**
 *  list of bluetooth devices encountered for debugging if enabled
 */
- (NSDictionary *  _Nullable)devices;

/**
 *  The type of location service requested
 */
- (RVLLocationServiceType)locationServiceType;

/**
 *  Indicates whether the of beacons should be stopped when entering the 
 *  background, even if always is selected.
 */
- (BOOL) useManagedBackgroundMode;

// Bluetooth testing API should be treated as deprecated
@property (nonatomic) BOOL captureAllDevices;

// all discovered bluetooth devices (for debugging only)
@property (readonly, nullable) NSDictionary<NSString*, RevealBluetoothObject*>* bluetoothDevices;

@end

#pragma mark - models -

#ifndef REVEAL_MODEL_DEFINED
#define REVEAL_MODEL_DEFINED

// known beacon verndor codes
#define BEACON_TYPE_GIMBAL              140
#define BEACON_TYPE_SWIRL               181

// extra beacon (Gimbal?)
#define BEACON_UNKNOWN_A                349

// known service types
#define BEACON_SERVICE_EDDYSTONE        0xfeaa
#define BEACON_SERVICE_EDDYSTONE_STRING @"FEAA"
#define BEACON_SERVICE_TILE_STRING      @"FEED"

#define BEACON_SERVICE_SECURECAST       0xfeeb
#define BEACON_SERVICE_UNKNOWN_A        0xfefd
#define BEACON_SERVICE_UNKNOWN_B        0x180f
#define BEACON_SERVICE_TILE             0xfeed
#define BEACON_SERVICE_ESTIMOTE         0x180a

#define RVLBeaconProximityUUID          @"proximityUUID"
#define RVLBeaconMajor                  @"major"            // iBeacon only
#define RVLBeaconMinor                  @"minor"            // iBeacon only
#define RVLBeaconProximity              @"proximity"
#define RVLBeaconProximityInteger       @"proximityInteger"
#define RVLBeaconAccuracy               @"accuracy"
#define RVLBeaconRSSI                   @"rssi"
#define RVLBeaconUniqString             @"identity"
#define RVLBeaconDiscoveryTime          @"discoveryTime"
#define RVLBeaconSentTime               @"sentTime"
#define RVLBeaconType                   @"type"
#define RVLBeaconPayload                @"payload"
#define RVLBeaconLocation               @"location"
#define RVLBeaconKey                    @"key"              // secure cast only
#define RVLBeaconLocal                  @"local"            // secure cast only

/**
 *  The raw beacon scanner builds this information about a given beacon.
 *
 *  NOTE: The items that are not documented may be temporary and should
 *        not be relied upon
 */
@interface RevealScannerRawBeacon : NSObject <NSCoding>

/**
 *  The name of the vendor if known
 */
@property (nonatomic, strong, nullable) NSString* vendorName;

/**
 *  The numeric code representing the vendor if known
 */
@property (nonatomic, assign) NSInteger vendorCode;
@property (nonatomic, assign) NSInteger key;

/**
 *  identifier for securecast beacons
 */
@property (nonatomic, assign) NSInteger local;

/**
 *  The data for the beacon - this is usually the entire data packet 
 *  in un-decoded form
 */
@property (nonatomic, strong, nullable) NSData* payload;
@property (nonatomic, strong, nullable) NSDictionary* advertisement;
@property (nonatomic, strong, nullable) NSArray* uuids;
@property (readonly, nonnull) NSString* identifier;
@property (nonatomic, assign) NSInteger rssi;
@property (readonly, nullable) NSString* payloadString;
@property (nonatomic, strong, nullable) NSUUID* bluetoothIdentifier;
@property (nonatomic, strong, nullable) NSMutableDictionary* services;
@property (nonatomic, strong, nullable) NSMutableDictionary* extendedData;
@property (nonatomic, strong, nullable) NSDictionary <NSString*, NSData*>* characteristics;
@property (nonatomic, strong, nullable) NSDate   * discoveryTime;
@property (readonly) NSTimeInterval age;


/**
 *  The URL associated with the beacon. Currently only useful 
 *  with eddystone beacons.
 */
@property (nonatomic, strong, nullable) NSURL* url;

/**
 *  Indicates that the beacon has been completely received. This
 *  is used in multi part beacons to prevent a partial beacon 
 *  from being reported. Currently only useful with eddystone 
 *  beacons.
 */
@property (nonatomic, assign) BOOL complete;
@property (nonatomic, strong, nullable) NSString* vendorId;

- (NSString* _Nullable)ident:(NSInteger)index;

@end

/**
 *
 */
@interface RevealBluetoothObject : NSObject

@property (nonatomic, strong, nullable) NSString* identifier;
@property (nonatomic, strong, nullable) CBPeripheral* peripheral;
@property (nonatomic, strong, nullable) NSDictionary* advertisement;
@property (nonatomic, strong, nullable) RevealScannerRawBeacon* beacon;
@property (nonatomic, strong, nullable) NSDictionary* services;
@property (nonatomic, strong, nullable) NSDate* dateTime;
@property (nonatomic, strong, nullable) NSArray* uuids;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, strong, nullable) NSMutableDictionary* characteristics;
@property (nonatomic, strong, nullable) NSString* serviceUUID;

@property (readonly) BOOL connectable;

@property (readonly, nullable) NSString* name;

+ (NSString*_Nullable) serviceName:(NSString* _Nullable)serviceName;
+ (NSString*_Nullable) data:(id _Nullable)data;

@end

@interface RVLBeacon : NSObject <NSCoding>

/**
 *  This is the identifying element for a group of iBeacons. Typically
 *  it identifies a group of beacons by a particular user. You then use
 *  the major and minor to identify a particular beacon
 */
@property (nonatomic, strong)   NSUUID   * _Nullable proximityUUID;

/**
 *  Used by iBeacons as an identifying element
 */
@property (nonatomic, strong)   NSString * _Nullable major;

/**
 *  Used by iBeacons as an identifying element
 */
@property (nonatomic, strong)   NSString * _Nullable minor;

/**
 *  Provides an estimation of how close you are to this beacon
 */
@property (readonly, nonnull)     NSString * proximity;

/**
 *  Provides an estimation of how close you are to this beacon as a 
 *  numeric enumeration
 */
@property (nonatomic, assign) NSInteger proximityInteger;

/**
 *  Provides an indication of how accurate the measurement is
 */
@property (nonatomic, strong)   NSNumber * _Nullable accuracy;

/**
 *  Signal strength
 */
@property (nonatomic, strong)   NSNumber * _Nullable rssi;

/**
 *  unique id of beacon
 */
@property (nonatomic, readonly, nonnull) NSString * rvlUniqString;

/**
 *  The time that the beacon was encountered
 */
@property (nonatomic, strong, nullable)   NSDate   * discoveryTime;

/**
 *  The time that the reveal server was notified of the beacon
 */
@property (nonatomic, strong, nullable)   NSDate   *sentTime;

/**
 *  The type of beacon
 */
@property (readonly, nonnull)            NSString* type;

/**
 *  Indicates if the raw beacon was successfully encoded
 */
@property (readonly)            BOOL decoded;

/**
 *  The location where beacon was discovered
 */
@property (nonatomic, strong, nullable)   CLLocation* location;

/**
 *  The address of the discover location
 */
@property (nonatomic, strong, nullable)   CLPlacemark* placemark;

/**
 *  The data from a non iBeacon that has been discovered.
 */
@property (nonatomic, strong, nullable) RevealScannerRawBeacon* rawBeacon;

/**
 *  The proximity represented as an numeric representation
 */
@property (readonly) double proximityInMeters;

/**
 *  Build a unique string to identify this beacon
 *
 *  @param beacon the beacon you want to represent
 *
 *  @return string identifying this beacon
 */
+ (NSString* _Nonnull)rvlUniqStringWithBeacon:(CLBeacon* _Nonnull) beacon;

/**
 *  Get a dictionary that is will encode as JSON
 *
 *  @return the dictionary
 */
- (NSDictionary<NSString*,id>* _Nonnull) dictionary;

- (instancetype _Nonnull) initWithBeacon:(CLBeacon * _Nonnull )beacon;
- (instancetype _Nonnull) initWithBeaconRegion:(CLBeaconRegion * _Nonnull)beaconRegion;
- (instancetype _Nonnull) initWithRawBeacon:(RevealScannerRawBeacon* _Nonnull)beacon;

/**
 See if the beacon is ready to send now

 @return YES if the beacon is ready to go, NO if not
 */
- (BOOL) readyToSend;

/**
 Send the beacon to the server if it is ready, otherwise queue it to be sent 
 at a later time so we can wait for better accuracy or for a location to be 
 retrieved.

 @return true if the beacon was sent now, false if queued for later
 */
- (BOOL) saveWhenReady;


/**
 Determine if the time to wait for closer proximity has expired

 @return true if expired - false otherwise
 */
- (BOOL) timeoutWaitingToSend;

/**
 Combine the data from the new beacon with this one

 @param beacon The new beacon

 @return true if the new location is closer
 */
- (BOOL) combineWith:(RVLBeacon* _Nonnull)beacon;

/**
 Recalculate the distance from the beacon
 
 @note this is exposed for testing and will be removed from future versions 
       so don't rely on it.
 */
- (void) calculateDistance;

@end

#pragma mark - Eddystone object -

@interface RVLEddyStoneBeacon : RVLBeacon

@end

#pragma mark - Tile object -

@interface RVLTileBeacon : RVLBeacon

@end

#pragma mark - Tile object -

@interface RVLSecurecastBeacon : RVLBeacon

@end

#endif

/**
 *  The Web Services class provides the interface to send beacon data to the Reveal server
 */
@interface RVLWebServices : NSObject

/**
 *  The API Key
 */
@property (nonatomic, nullable) NSString* apiKey;

/**
 *  The URL for the server to send information to
 */
@property (nonatomic, strong, nullable) NSString* apiUrl;

/**
 *  provide a routine to perform logging functionality
 */
@property (nonatomic, assign, nullable) void (*log)( NSString* _Nonnull type, NSString * _Nonnull format, ...);

/**
 *  provide a routine to perform logging functionality, these logs will
 *  only be included if the verbose setting is selected.
 */
@property (nonatomic, assign, nullable) void (*logVerbose)( NSString* _Nonnull type, NSString * _Nonnull format, ...);

/**
 *  The git hash for the current build
 */
@property (nonatomic, strong, nullable) NSString* build;

/**
 *  Get the Web Service manager to communicate with the Reveal server
 *
 *  @return the shared instance of the Web Services class
 */
+ (RVLWebServices* _Nonnull) sharedWebServices;

/**
 *  register the device with reveal, sending the device information. it
 *  returns a dictionary containing scan durations as wells as persona's
 *  to update the client settings from.
 *
 *  Keys:
 *
 *      cache_ttl - time to keep location entries in the cache to prevent
 *                  duplication
 *      scan_interval - time to wait between scans
 *      scan_length - duration to scan for beacons on each pass
 *      discovery_enabled - beacon scanning is requested, if false the client
 *                   should not scan
 *      beacons - list of beacons to scan for
 *
 *  @param result callback to receive the response from the server
 */
- (void) registerDeviceWithResult:(void (^ _Nonnull)(BOOL success, NSDictionary* _Nullable result, NSError* _Nullable error))result;

/**
 *  Notify the server of a new beacon discovery
 *
 *  @param beacon the beacon's details
 *  @param result callback to receive the response from the server
 */
- (void) sendNotificationOfBeacon:(RVLBeacon* _Nonnull ) beacon
                           result:(void (^_Nullable)(BOOL success, NSDictionary* _Nullable result, NSError* _Nullable error))result;

- (void) sendInfo:(NSDictionary* _Nonnull)jsonableDictionary
           result:(void (^ _Nullable)(BOOL success, NSDictionary*  _Nonnull result, NSError*  _Nonnull error))result;
/**
 *  Get the current IP address
 *
 *  @param preferIPv4 I want the old style
 *
 *  @return the best IP address available
 */
- (NSString * _Nullable)getIPAddress:(BOOL)preferIPv4;

/**
 *  Get all IP addresses
 *
 *  @return array of IP Addresses
 */
- (NSDictionary * _Nullable)getIPAddresses;

/**
 *  The version of the SDK
 */
- (NSString* _Nonnull) version;

@end

@interface CurveFittedDistanceCalculator : NSObject

@property (nonatomic, assign) double mCoefficient1;
@property (nonatomic, assign) double mCoefficient2;
@property (nonatomic, assign) double mCoefficient3;
@property (nonatomic, assign) int txPower;

- (double) calculateDistanceWithPower:(int)txPower andRSSI: (double) rssi;
- (double) calculateDistanceWithRSSI: (double) rssi;

@end

void RVLLog(NSString * _Nonnull format, ...) NS_FORMAT_FUNCTION(1,2);
void RVLLogWithType(NSString* _Nonnull type, NSString * _Nonnull format, ...) NS_FORMAT_FUNCTION(2,3);
void RVLLogVerbose(NSString* _Nonnull type, NSString * _Nonnull format, ...) NS_FORMAT_FUNCTION(2,3);

@interface RVLDebugLog : NSObject

/**
 *  Enable debugs
 */
@property (nonatomic, assign) BOOL enabled;

/**
 *  Include verbose logs
 */
@property (nonatomic, assign) BOOL verbose;

/**
 *  Enable the use of color in the logs - Requires the installation of
 *  XCodeColors: https://github.com/robbiehanson/XcodeColors
 *
 *  Available via Alcatraz http://alcatraz.io/
 */
@property (nonatomic, assign) BOOL useColor;

+ (instancetype _Nonnull)sharedLog;

/**
 *  Log the specified string as type "DEBUG"
 *
 *  @param aString the string to log
 */
- (void) log:(NSString *  _Nonnull)aString;

/**
 *  Log the specified string to the console
 *
 *  @param aString the string to log
 *  @param type    the type of log
 */
- (void) log:(NSString *  _Nonnull)aString ofType:(NSString* _Nonnull)type;

/**
 *  Log the specified string only if verbose logging is enabled
 *
 *  @param aString the string to log
 *  @param type    the type of log
 */
- (void) logVerbose:(NSString * _Nonnull)aString ofType:(NSString* _Nonnull)type;

@end
