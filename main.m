#import <AppKit/AppKit.h>
#import <Quartz/Quartz.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>

int maxDisplays = 32;

NSArray *getAllDisplayIDs() {
    CGDirectDisplayID activeDisplays[maxDisplays];
    uint32_t displayCount;

    CGError result = CGGetActiveDisplayList(maxDisplays, activeDisplays, &displayCount);
    if (result != kCGErrorSuccess) {
        NSLog(@"Error obtaining display list");
        return @[];
    }

    NSMutableArray *displayIDs = [NSMutableArray array];
    for (uint32_t i = 0; i < displayCount; i++) {
        [displayIDs addObject:@(activeDisplays[i])];
    }
    return displayIDs;
}

NSString *getLastWallpaperPath() {
    NSString *writableDir = [NSHomeDirectory() stringByAppendingPathComponent:@"WallpaperApp"];
    NSString *filePath = [writableDir stringByAppendingPathComponent:@"last_wallpaper.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (json && json[@"path"]) {
            return json[@"path"];
        }
    }
    return [[NSBundle mainBundle] pathForResource:@"bg" ofType:@"gif"];
}

void saveLastWallpaperPath(NSString *filePath) {
    NSString *writableDir = [NSHomeDirectory() stringByAppendingPathComponent:@"WallpaperApp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:writableDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *jsonPath = [writableDir stringByAppendingPathComponent:@"last_wallpaper.json"];
    NSDictionary *json = @{@"path": filePath};
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    [data writeToFile:jsonPath atomically:YES];
}

@interface WallpaperWindow : NSWindow
@property (nonatomic) CGDirectDisplayID displayID;
@property (strong) NSImageView *imageView;
@property (strong) AVPlayerLayer *playerLayer;
@property (strong) AVPlayer *player;
@property (strong) NSString *lastWallpaperPath;
- (instancetype)initWithDisplayID:(CGDirectDisplayID)displayID;
- (void)setWallpaper:(NSString *)filePath;
@end

@implementation WallpaperWindow

- (instancetype)initWithDisplayID:(CGDirectDisplayID)displayID {
    self.displayID = displayID;
    CGRect screenRect = CGDisplayBounds(displayID);

    self = [super initWithContentRect:screenRect
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        [self setLevel:kCGDesktopWindowLevel - 1];
        [self setOpaque:YES];
        [self setIgnoresMouseEvents:YES];
        [self setCollectionBehavior:NSWindowCollectionBehaviorStationary |
                                     NSWindowCollectionBehaviorCanJoinAllSpaces |
                                     NSWindowCollectionBehaviorIgnoresCycle];
        [self setFrame:screenRect display:YES];

        self.lastWallpaperPath = getLastWallpaperPath();
        [self setWallpaper:self.lastWallpaperPath];

        [self makeKeyAndOrderFront:nil];
    }
    return self;
}

- (void)setWallpaper:(NSString *)filePath {
    if ([[filePath lowercaseString] hasSuffix:@".mp4"] || [[filePath lowercaseString] hasSuffix:@".mov"]) {
        [self playVideo:filePath];
    } else {
        [self displayImage:filePath];
    }
}

- (void)playVideo:(NSString *)filePath {
    NSView *contentView = [self contentView];
    if (!contentView) {
        NSLog(@"Content view is not available.");
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    self.player = [AVPlayer playerWithURL:fileURL];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if ([tracks count] > 0) {
        AVAssetTrack *track = tracks[0];
        CGSize naturalSize = [track naturalSize];
        CGFloat videoWidth = naturalSize.width;
        CGFloat videoHeight = naturalSize.height;

        CGRect screenRect = CGDisplayBounds(self.displayID);
        CGFloat screenWidth = screenRect.size.width;
        CGFloat screenHeight = screenRect.size.height;

        CGFloat scaleFactorX = screenWidth / videoWidth;
        CGFloat scaleFactorY = screenHeight / videoHeight;
        CGFloat scaleFactor = MAX(scaleFactorX, scaleFactorY);

        CGFloat newWidth = videoWidth * scaleFactor;
        CGFloat newHeight = videoHeight * scaleFactor;

        CGFloat x = (screenWidth - newWidth) / 2;
        CGFloat y = (screenHeight - newHeight) / 2;
        CGRect videoFrame = CGRectMake(x, y, newWidth, newHeight);

        [self.playerLayer setFrame:videoFrame];

        if (![contentView layer]) {
            [contentView setWantsLayer:YES];
        }
        [[contentView layer] addSublayer:self.playerLayer];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerItemDidReachEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:[self.player currentItem]];

        [self.player play];
        saveLastWallpaperPath(filePath);
    } else {
        NSLog(@"Unable to get video dimensions.");
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    [self.player seekToTime:kCMTimeZero];
    [self.player play];
}

- (void)displayImage:(NSString *)filePath {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:filePath];
    if (!image) {
        NSLog(@"Failed to load image.");
        return;
    }

    if (self.imageView) {
        [self.imageView removeFromSuperview];
        self.imageView = nil;
    }

    CGRect screenRect = CGDisplayBounds(self.displayID);
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;

    CGFloat imageWidth = [image size].width;
    CGFloat imageHeight = [image size].height;

    CGFloat scaleFactorX = screenWidth / imageWidth;
    CGFloat scaleFactorY = screenHeight / imageHeight;
    CGFloat scaleFactor = MAX(scaleFactorX, scaleFactorY);

    CGFloat newWidth = imageWidth * scaleFactor;
    CGFloat newHeight = imageHeight * scaleFactor;

    CGFloat x = (screenWidth - newWidth) / 2;
    CGFloat y = (screenHeight - newHeight) / 2;
    NSRect imageFrame = NSMakeRect(x, y, newWidth, newHeight);

    self.imageView = [[NSImageView alloc] initWithFrame:imageFrame];
    [self.imageView setImage:image];
    [self.imageView setAnimates:YES];
    [self.imageView setImageScaling:NSImageScaleAxesIndependently];

    [[self contentView] addSubview:self.imageView];

    saveLastWallpaperPath(filePath);
}

@end

@interface AboutWindow : NSWindow
- (instancetype)init;
@end

@implementation AboutWindow

- (instancetype)init {
    NSSize size = NSMakeSize(350, 200);
    self = [super initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        [self setTitle:@"About LiveLayer"];

        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"icns"];
        NSImage *appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];

        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 100, 64, 64)];
        [iconView setImage:appIcon];

        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(100, 80, 230, 100)];
        [label setStringValue:@"LiveLayer\n\nA Live Wallpaper App for macOS by Eric Pan\nDeveloped during HackClub HighSeas 2024."];
        [label setEditable:NO];
        [label setBezeled:NO];
        [label setDrawsBackground:NO];
        [label setSelectable:NO];
        [label setFont:[NSFont systemFontOfSize:13]];
        [label setAlignment:NSTextAlignmentLeft];

        [[self contentView] addSubview:iconView];
        [[self contentView] addSubview:label];

        [self center];
        [self makeKeyAndOrderFront:nil];
    }
    return self;
}

@end

@interface WallpaperApp : NSApplication
@property (strong) NSMutableArray *windows;
@property (strong) NSStatusItem *statusItem;
- (void)run;
- (void)aboutApp:(id)sender;
- (void)changeWallpaper:(id)sender;
@end

@implementation WallpaperApp

- (void)run {
    [self setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.windows = [NSMutableArray array];

    NSArray *displayIDs = getAllDisplayIDs();
    for (NSNumber *displayIDNum in displayIDs) {
        CGDirectDisplayID displayID = [displayIDNum unsignedIntValue];
        WallpaperWindow *window = [[WallpaperWindow alloc] initWithDisplayID:displayID];
        [self.windows addObject:window];
    }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setTitle:@"🖥️"];
    NSMenu *statusMenu = [[NSMenu alloc] init];

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About"
                                                       action:@selector(aboutApp:)
                                                keyEquivalent:@""];
    [statusMenu addItem:aboutItem];

    NSMenuItem *changeWallpaperItem = [[NSMenuItem alloc] initWithTitle:@"Change Wallpaper"
                                                                 action:@selector(changeWallpaper:)
                                                          keyEquivalent:@""];
    [statusMenu addItem:changeWallpaperItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@""];
    [statusMenu addItem:quitItem];

    [self.statusItem setMenu:statusMenu];

    [NSApp run];
}

- (void)aboutApp:(id)sender {
    AboutWindow *aboutWindow = [[AboutWindow alloc] init];
    [aboutWindow makeKeyAndOrderFront:nil];
}

- (void)changeWallpaper:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setAllowedFileTypes:@[@"gif", @"jpg", @"png", @"jpeg", @"mp4", @"mov"]];

    if ([panel runModal] == NSModalResponseOK) {
        NSString *selectedPath = [[panel URL] path];
        NSString *resolvedPath = [selectedPath stringByResolvingSymlinksInPath];
        if (resolvedPath) {
            for (WallpaperWindow *window in self.windows) {
                [window setWallpaper:resolvedPath];
            }
        }
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        WallpaperApp *app = (WallpaperApp *)[WallpaperApp sharedApplication];
        [app run];
    }
    return 0;
}
