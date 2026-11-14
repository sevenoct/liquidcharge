#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

@interface PSListController : UIViewController {
    NSArray *_specifiers;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end

@interface LCRootListController : PSListController
@end
@interface LCGlassListController : PSListController
@end

static void LCPost(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, YES);
}

@implementation LCRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)previewCharging { LCPost(CFSTR("com.example.liquidcharge/preview-on")); }
- (void)previewDisconnected { LCPost(CFSTR("com.example.liquidcharge/preview-off")); }
- (void)resetDefaults {
    CFStringRef dom = CFSTR("com.example.liquidcharge");
    CFArrayRef keys = CFPreferencesCopyKeyList(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    CFPreferencesAppSynchronize(dom);
    LCPost(CFSTR("com.example.liquidcharge/prefs"));
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

@implementation LCGlassListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Glass" target:self];
    return _specifiers;
}
@end
