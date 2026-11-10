#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

@interface FixtureWorkspace : NSObject
+ (id)sharedWorkspace;
- (NSArray *)runningApplications;
- (BOOL)openFile:(NSString *)file withApplication:(NSString *)application;
- (BOOL)openURLs:(NSArray *)urls withAppBundleIdentifier:(NSString *)identifier
        options:(NSWorkspaceLaunchOptions)options additionalEventParamDescriptor:(id)descriptor
        launchIdentifiers:(NSArray **)identifiers;
@end
@interface FixtureBundle : NSObject
- (id)initWithPath:(NSString *)path;
- (NSString *)bundleIdentifier;
@end
@interface FixtureURL : NSObject
- (id)initFileURLWithPath:(NSString *)path;
@end
CFURLRef FixtureURLCreate(CFAllocatorRef, CFStringRef, CFURLPathStyle, Boolean);
CFStringRef FixtureURLCopyPath(CFURLRef, CFURLPathStyle);
OSStatus FixtureFindApplication(OSType, OSType, CFStringRef, LSRolesMask, FSRef *, CFURLRef *);

#define NSWorkspace FixtureWorkspace
#define NSBundle FixtureBundle
#define NSURL FixtureURL
#define CFURLCreateWithFileSystemPath FixtureURLCreate
#define CFURLCopyFileSystemPath FixtureURLCopyPath
#define LSGetApplicationForInfo FixtureFindApplication
