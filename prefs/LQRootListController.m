#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

@interface PSListController : UIViewController {
    NSArray *_specifiers;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface LQRootListController : PSListController
@end
@interface LQGlassListController : PSListController
@end

static void LQPost(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, YES);
}

@implementation LQRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)previewCharging { LQPost(CFSTR("com.hasan.liquidglasscharge/preview-on")); }
- (void)previewDisconnected { LQPost(CFSTR("com.hasan.liquidglasscharge/preview-off")); }
- (void)resetDefaults {
    CFStringRef dom = CFSTR("com.hasan.liquidglasscharge");
    CFArrayRef keys = CFPreferencesCopyKeyList(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    CFPreferencesAppSynchronize(dom);
    LQPost(CFSTR("com.hasan.liquidglasscharge/prefs"));
    [self reloadSpecifiers];
}
- (void)respring {
    NSArray *tries = @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload"];
    for (NSString *p in tries) {
        if (![NSFileManager.defaultManager fileExistsAtPath:p]) continue;
        pid_t pid;
        char *args[] = {(char *)"sbreload", NULL};
        posix_spawn(&pid, p.fileSystemRepresentation, NULL, NULL, args, environ);
        return;
    }
    pid_t pid;
    char *args[] = {(char *)"killall", (char *)"-9", (char *)"SpringBoard", NULL};
    posix_spawnp(&pid, "killall", NULL, NULL, args, environ);
}
@end

@implementation LQGlassListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Glass" target:self];
    return _specifiers;
}
@end
