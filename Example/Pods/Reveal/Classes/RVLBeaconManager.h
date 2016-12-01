//
//  RVLBeaconManager.h
//  Pods
//
//  Created by Bobby Skinner on 3/1/16.
//
//
//  NOTE: This file is structured strangly to
//        facilitate using the file independantly
//        not for logical code seperation

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import "Reveal.h"

@class CCObjectCache<KeyType, ObjectType>;

typedef void (^RVLBlueToothStatusBlock)(CBCentralManagerState state);



/**
 *  Server selection
 */
typedef NS_ENUM(NSInteger, RVLCacheState) {
    RVLCacheStateNew,
    RVLCacheStateCloser,
    RVLCacheStateExisting
};

#pragma mark - RVLBeaconManager -

@interface RVLBeaconManager : NSObject <CLLocationManagerDelegate, RVLBeaconService>

@property (nonatomic, strong, nullable) CLLocationManager* locationManager;
@property (nonatomic, copy, readonly, nullable) NSString *status;
@property (nonatomic, readonly) BOOL hasBluetooth;

@property (nonatomic, strong, nullable) CCObjectCache *cachedBeacons;

/**
 *  provide a routine to perform logging functionality
 */
@property (nonatomic, assign, nullable) void (*log)( NSString* _Nonnull type, NSString * _Nonnull format, ...);

/**
 *  provide a routine to perform logging functionality
 */
@property (nonatomic, assign, nullable) void (*logVerbose)( NSString* _Nonnull type, NSString * _Nonnull format, ...);

+ (RVLBeaconManager * _Nonnull) sharedManager;
- (void) addBeacon:(NSString * _Nonnull)beaconID;
- (void) addStatusBlock:(RVLBlueToothStatusBlock _Nonnull)block;
- (void) shutdownMonitor;

@property (nonatomic, assign) NSInteger minRSSI;
@property (nonatomic, assign) NSInteger maxRSSI;
@property (nonatomic, assign) NSTimeInterval scanDuration;
@property (nonatomic, assign) NSTimeInterval scanInterval;
@property (nonatomic, assign) NSTimeInterval eddystoneTimeOut;
@property (nonatomic, assign) NSTimeInterval proximityTimeout;
@property (nonatomic, assign) BOOL includeUnknownVendors;
@property (nonatomic, assign) BOOL showUnknownDevices;
@property (nonatomic, assign) BOOL captureAllDevices;
@property (nonatomic, strong, nullable) CCObjectCache<NSString*, RevealBluetoothObject*>* bluetoothDevices;
@property (nonatomic, strong, nullable) CurveFittedDistanceCalculator* distanceCalculator;

@property (nonatomic, weak, nullable) id <RVLBeaconDelegate> delegate;

@property (nonatomic, strong, nullable) void (^foundDevice)(RVLBeaconManager* _Nonnull scanner, NSDictionary* _Nullable advertisement, CBPeripheral* _Nullable peripheral );

- (void) start;
- (void) stop;

- (void) addVendorNamed:(NSString* _Nonnull)name withCode:(NSInteger)code;

/**
 *  @brief Start bluetooth scanning
 */
- (void) startScanner;

@end

#pragma mark - Third Party code -
#pragma mark CCObjectCache -

/**   CCObjectCache.h
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

@class CCObjectCache;

/**
 *  This delegate protocol will allow you to be notified whenever there is
 an item added, used or removed from the cache
 */
@protocol CCObjectCacheDelegate <NSObject>
@optional

/**
 *  An object has just been added to the cache
 *
 *  @param cache  the cache object
 *  @param object the object added
 */
- (void) objectCache:(CCObjectCache* _Nonnull)cache didAddObject:(id _Nonnull)object;

/**
 *  An objext will be removed from the cache
 *
 *  @param cache  the cache object
 *  @param object the object added
 */
- (void) objectCache:(CCObjectCache* _Nonnull)cache willRemoveObject:(id _Nonnull)object;

/**
 *  An object will be accessed from the queue
 *
 *  @param cache  the cache object
 *  @param object the object added
 */
- (void) objectCache:(CCObjectCache* _Nonnull)cache willAccessObject:(id _Nonnull)object;

@end

#pragma mark CCObjectCache -

/**
 *  The cache class is used to cache any generic type of object.
 *
 *  Internally it uses a dictionary rather than NSCache since it is
 *  intended to use time as the trigger to remove instead of memory
 *  usage, so if that is your concern please use NSCache instead.
 */
@interface CCObjectCache<KeyType, ObjectType>  : NSObject <NSCoding>

/**
 *  The delegate to be called when an action related to the storage
 *  or remove of items from the cache
 *
 *  @see CCObjectCacheDelegate
 */
@property (nonatomic, weak, nullable) id <CCObjectCacheDelegate> delegate;

/**
 *  The amount of time to to keep objects in the cache before discarding
 *  them
 */
@property (nonatomic, assign) NSTimeInterval cacheTime;

/**
 *  Use this option to indicate that you want the every access
 *  (not just the adds) to reset the timer for this item.
 */
@property (nonatomic, assign) BOOL resetOnEveryAccess;

/**
 *  Use this option to indicate that you want the every add
 *  to reset the timer for this item, even if the item was
 *  already in the cache.
 */
@property (nonatomic, assign) BOOL resetOnEveryAdd;

/**
 *  Look up the value in the cache and return it
 *
 *  @param key the item to find
 *
 *  @return The item or nil if not available
 */
- (ObjectType _Nullable) objectForKey:(KeyType _Nonnull)key;

/**
 *  Add an object to the cache.
 *
 *  @param obj the object to add
 *  @param key the key to retrieve it by
 *
 *  @return YES if the item was not in the queue and had
 *          to be added, NO otherwise
 */
- (BOOL)setObject:(ObjectType _Nonnull)obj forKey:(KeyType _Nonnull)key;

/**
 *  remove the item with the specified key
 *
 *  @param aKey the key you widh to remove
 */
- (void)removeObjectForKey:(KeyType _Nonnull)aKey;

/**
 *  Load the cache from a dictionary
 *
 *  @param dict the dictionary you wish to add
 */
- (void) loadWithDictionary:(NSDictionary* _Nonnull)dict;

/**
 *  Return a dictionary off all the items in the cache
 *
 *  @return All the items from their cache
 */
- (NSDictionary* _Nonnull) dictionary;

/**
 *  Return a dictionary of all items matching all the criteria in the list
 *
 *  @param matchCriteria list of tags and values to match
 *
 *  @return the matches
 */
- (NSDictionary* _Nonnull) dictionaryMatching:(NSDictionary* _Nonnull)matchCriteria;

/**
 *  Set the value for a tag item associated with this object
 *
 *  @param value   the value
 *  @param tagName the name of the object in the tag set
 *  @param key     the key of the item to add it to
 *
 *  @return YES if the item exsists in the tag - no otherwise
 */
- (BOOL) setValue:(id<NSObject> _Nonnull)value forTag:(NSString* _Nonnull)tagName forKey:(KeyType _Nonnull)key;

/**
 *  Retturn the value for the specified tag and key
 *
 *  @param tagName the name of the tag you seek
 *  @param key     the key of the object in the cache containing the value
 *
 *  @return the tag objec or nil if the tag or item does not exist
 */
- (id<NSObject> _Nullable)valueForTag:(NSString* _Nonnull)tagName forKey:(KeyType _Nonnull)key;

/**
 *  Get all the tags associated with the specified key
 *
 *  @param key the item you need the tags for
 *
 *  @return A dictionary of tags or nil if the object is not in the cache
 */
- (NSDictionary* _Nonnull)tagsForKey:(KeyType _Nonnull)key;

/**
 *  set the tages for this object, (replaces any existing tags with the new
 *  set. It does NOT combine them.
 *
 *  @param tags the tags for the object
 *  @param key  the item you wish to associate the tags with
 *
 *  @return YES if the item exsists in the tag - no otherwise
 */
- (BOOL)setTags:(NSDictionary* _Nonnull)tags forKey:(KeyType _Nonnull)key;

/**
 *  Create e new cache with items from the specified dictionary
 *
 *  @param dict the items to add
 *
 *  @return the new cache
 */
+ (CCObjectCache* _Nonnull) objectCacheWithDictionary:(NSDictionary* _Nonnull)dict;

#pragma mark - modern obj-c -

// support apples [] indexing options
- (void)setObject:(ObjectType _Nonnull)obj forKeyedSubscript:(KeyType _Nonnull)key;
- (ObjectType _Nullable)objectForKeyedSubscript:(KeyType _Nonnull) key;

@end

