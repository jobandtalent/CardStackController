//
//  RVLLocation.h
//  Pods
//
//  Created by Bobby Skinner on 3/1/16.
//
//  NOTE: This file is structured strangely to
//        facilitate using the file indepandantly
//        not for logical code separation

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "Reveal.h"

/**
 *  The location manager class manages location services for the SDK.
 *  You can chose not to use this class and provide your own location 
 *  management and chose not to use this one.
 */
@interface RVLLocation : NSObject <RVLLocationService>

#pragma mark - Properties -

/**
 *  The last known location for the current user
 */
@property (nonatomic, strong) CLLocation *userLocation;

/**
 *  The address (placemark) to be passed to the server
 */
@property (nonatomic, strong) CLPlacemark *userPlacemark;

/**
 *  The last known user coordinante
 */
@property (nonatomic, assign, readonly) CLLocationCoordinate2D userCoordinate;

/**
 *  The amount of time to consider the location current
 */
@property (nonatomic, assign) NSTimeInterval locationRetainTime;

/**
 *  Determine if the current location is recent enough to be trusted
 */
@property (readonly) BOOL isLocationCurrent;

/**
 *  use the geocoder to perform reverse geocoding
 */
@property (nonatomic, assign) BOOL enableGeocoder;

/**
 *  provide a routine to perform logging functionality
 */
@property (nonatomic, assign) void (*log)( NSString* type, NSString *format, ...);

/**
 *  The internal location manager
 */
@property (readonly) CLLocationManager *locationManager;

/**
 *  Delegate to forward locationManager delegate methods
 */
@property (nonatomic, weak) id <CLLocationManagerDelegate> passThroughDelegate;

#pragma mark - Primary API -

/**
 *  Get the shared location manager.
 *
 *  @return the shared instance
 */
+ (RVLLocation*) sharedManager;

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
- (void) waitForValidLocation:(void (^)())callback;


@end
