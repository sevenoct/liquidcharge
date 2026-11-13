// LiquidCharge - popup "liquid glass" saat charger connect / disconnect
// Target: iOS 15 (SpringBoard). Build dengan Theos.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define LC_W 300.0
#define LC_H 72.0
#define LC_SHOW_SECONDS 3.0

@interface UIWindow (LCPrivate)
- (void)_setSecure:(BOOL)secure;
@end

#pragma mark - Window (tembus sentuhan)

@interface LCWindow : UIWindow
@end

@implementation LCWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

#pragma mark - Gauge cairan (lingkaran berisi gelombang)

@interface LCGaugeView : UIView
@property (nonatomic, assign) CGFloat level;
@property (nonatomic, assign) BOOL charging;
@property (nonatomic, strong) UIColor *liquidColor;
@property (nonatomic, copy) void (^onLevel)(CGFloat shown);
- (void)setSymbol:(NSString *)name;
- (void)start;
- (void)stop;
@end

@implementation LCGaugeView {
    CAShapeLayer *_back;
    CAShapeLayer *_front;
    CAShapeLayer *_ring;
    UIImageView *_icon;
    CADisplayLink *_link;
    CGFloat _phase;
    CGFloat _shown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];

        _back = [CAShapeLayer layer];
        _front = [CAShapeLayer layer];
        [self.layer addSublayer:_back];
        [self.layer addSublayer:_front];

        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 0.75, 0.75)].CGPath;
        _ring.fillColor = nil;
        _ring.strokeColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
        _ring.lineWidth = 1.5;
        [self.layer addSublayer:_ring];

        _icon = [[UIImageView alloc] initWithFrame:self.bounds];
        _icon.contentMode = UIViewContentModeCenter;
        _icon.tintColor = [UIColor whiteColor];
        _icon.layer.shadowColor = [UIColor blackColor].CGColor;
        _icon.layer.shadowOpacity = 0.35;
        _icon.layer.shadowRadius = 2;
        _icon.layer.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_icon];
    }
    return self;
}

- (void)setSymbol:(NSString *)name {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    _icon.image = [UIImage systemImageNamed:name withConfiguration:cfg];
}

- (void)setLiquidColor:(UIColor *)liquidColor {
    _liquidColor = liquidColor;
    _back.fillColor = [liquidColor colorWithAlphaComponent:0.45].CGColor;
    _front.fillColor = [liquidColor colorWithAlphaComponent:0.85].CGColor;
}

- (UIBezierPath *)pathWithAmp:(CGFloat)amp phase:(CGFloat)ph {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat base = h * (1.0 - _shown);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(0, h)];
    for (CGFloat x = 0; x <= w; x += 1.5) {
        CGFloat y = base + amp * sinf((x / w) * 2.0 * M_PI + ph);
        [p addLineToPoint:CGPointMake(x, y)];
    }
    [p addLineToPoint:CGPointMake(w, h)];
    [p closePath];
    return p;
}

- (void)tick {
    _phase += 0.11;
    _shown += (_level - _shown) * 0.07;
    CGFloat edge = MIN(_shown, 1.0 - _shown);
    CGFloat amp = 1.0 + 3.0 * MIN(1.0, edge * 6.0);
    _back.path = [self pathWithAmp:amp phase:_phase + 1.8].CGPath;
    _front.path = [self pathWithAmp:amp * 0.8 phase:_phase * 1.3].CGPath;
    if (self.onLevel) self.onLevel(_shown);
}

- (void)start {
    _shown = 0;
    _phase = 0;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    if (self.charging) {
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0;
        pulse.toValue = @1.22;
        pulse.duration = 0.65;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_icon.layer addAnimation:pulse forKey:@"pulse"];
    }
}

- (void)stop {
    [_link invalidate];
    _link = nil;
    [_icon.layer removeAllAnimations];
    self.onLevel = nil;
}

@end

#pragma mark - Popup liquid glass

@interface LCPopupView : UIView
- (instancetype)initWithLevel:(CGFloat)level charging:(BOOL)charging;
- (void)playIn;
- (void)playOutWithCompletion:(void (^)(void))completion;
- (void)stopAnimations;
@end

@implementation LCPopupView {
    LCGaugeView *_gauge;
    UIView *_glow;
    CAGradientLayer *_sheen;
    UILabel *_title;
    UILabel *_subtitle;
    UILabel *_percent;
    BOOL _charging;
}

- (instancetype)initWithLevel:(CGFloat)level charging:(BOOL)charging {
    if ((self = [super initWithFrame:CGRectMake(0, 0, LC_W, LC_H)])) {
        _charging = charging;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

        UIColor *accent;
        if (charging) {
            accent = [UIColor colorWithRed:0.30 green:0.86 blue:0.47 alpha:1];
        } else if (level <= 0.20) {
            accent = [UIColor colorWithRed:1.00 green:0.33 blue:0.30 alpha:1];
        } else {
            accent = [UIColor colorWithRed:0.62 green:0.82 blue:1.00 alpha:1];
        }

        CGRect b = self.bounds;
        CGFloat r = LC_H / 2.0;
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:r];

        // bayangan jatuh
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 18;
        self.layer.shadowOffset = CGSizeMake(0, 8);
        self.layer.shadowPath = shape.CGPath;

        // glow berdenyut di belakang kaca (tembus blur)
        _glow = [[UIView alloc] initWithFrame:b];
        _glow.backgroundColor = [UIColor clearColor];
        _glow.layer.shadowColor = accent.CGColor;
        _glow.layer.shadowOpacity = 0.0;
        _glow.layer.shadowRadius = 16;
        _glow.layer.shadowOffset = CGSizeZero;
        _glow.layer.shadowPath = shape.CGPath;
        [self addSubview:_glow];

        // kaca
        UIView *glass = [[UIView alloc] initWithFrame:b];
        glass.layer.cornerRadius = r;
        glass.layer.masksToBounds = YES;
        [self addSubview:glass];

        UIVisualEffectView *blur = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        blur.frame = b;
        [glass addSubview:blur];

        CAGradientLayer *tint = [CAGradientLayer layer];
        tint.frame = b;
        tint.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.05].CGColor,
            (id)[accent colorWithAlphaComponent:0.16].CGColor
        ];
        tint.startPoint = CGPointMake(0, 0);
        tint.endPoint = CGPointMake(1, 1);
        [glass.layer addSublayer:tint];

        // kilau yang menyapu saat muncul
        _sheen = [CAGradientLayer layer];
        _sheen.frame = CGRectMake(-80, 0, 80, LC_H);
        _sheen.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.38].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor
        ];
        _sheen.startPoint = CGPointMake(0, 0);
        _sheen.endPoint = CGPointMake(1, 0.45);
        [glass.layer addSublayer:_sheen];

        // pinggiran kaca (gradient stroke: terang di sudut, redup di tengah)
        CAGradientLayer *edge = [CAGradientLayer layer];
        edge.frame = b;
        edge.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.95].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.75].CGColor
        ];
        edge.startPoint = CGPointMake(0, 0);
        edge.endPoint = CGPointMake(1, 1);
        CAShapeLayer *edgeMask = [CAShapeLayer layer];
        edgeMask.frame = b;
        edgeMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.6, 0.6)
                                                   cornerRadius:r - 0.6].CGPath;
        edgeMask.fillColor = nil;
        edgeMask.strokeColor = [UIColor blackColor].CGColor;
        edgeMask.lineWidth = 1.2;
        edge.mask = edgeMask;
        [self.layer addSublayer:edge];

        // gauge
        _gauge = [[LCGaugeView alloc] initWithFrame:CGRectMake(14, 14, 44, 44)];
        _gauge.level = level;
        _gauge.charging = charging;
        _gauge.liquidColor = accent;
        [_gauge setSymbol:charging ? @"bolt.fill" : @"bolt.slash.fill"];
        [self addSubview:_gauge];

        // teks
        _title = [[UILabel alloc] initWithFrame:CGRectMake(68, 15, LC_W - 68 - 74, 21)];
        _title.text = charging ? @"Charger Connected" : @"Charger Disconnected";
        _title.textColor = [UIColor whiteColor];
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _title.adjustsFontSizeToFitWidth = YES;
        _title.minimumScaleFactor = 0.8;
        [self addSubview:_title];

        _subtitle = [[UILabel alloc] initWithFrame:CGRectMake(68, 36, LC_W - 68 - 74, 18)];
        _subtitle.text = charging ? @"Charging" : @"On battery";
        _subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.68];
        _subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        [self addSubview:_subtitle];

        _percent = [[UILabel alloc] initWithFrame:CGRectMake(LC_W - 80, 20, 66, 32)];
        _percent.text = @"0%";
        _percent.textAlignment = NSTextAlignmentRight;
        _percent.textColor = [UIColor whiteColor];
        _percent.font = [UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightBold];
        [self addSubview:_percent];

        __weak UILabel *wp = _percent;
        _gauge.onLevel = ^(CGFloat shown) {
            wp.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(shown * 100.0)];
        };
    }
    return self;
}

- (void)playIn {
    CGFloat dy = -(self.frame.origin.y + LC_H + 30);
    self.alpha = 0;
    self.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, dy), 0.6, 0.6);

    [UIView animateWithDuration:0.8
                          delay:0
         usingSpringWithDamping:0.68
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];

    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue = @(-40);
    sweep.toValue = @(LC_W + 40);
    sweep.duration = 1.0;
    sweep.beginTime = CACurrentMediaTime() + 0.25;
    sweep.fillMode = kCAFillModeBackwards;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_sheen addAnimation:sweep forKey:@"sweep"];

    // glow berdenyut
    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    glow.fromValue = @0.15;
    glow.toValue = @(_charging ? 0.75 : 0.40);
    glow.duration = _charging ? 0.75 : 1.1;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    glow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_glow.layer addAnimation:glow forKey:@"glow"];

    [_gauge start];

    @try {
        UIImpactFeedbackGenerator *g =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [g impactOccurred];
    } @catch (__unused NSException *e) {}
}

- (void)playOutWithCompletion:(void (^)(void))completion {
    CGFloat dy = -(self.frame.origin.y + LC_H + 30);
    [UIView animateWithDuration:0.4
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, dy), 0.7, 0.7);
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

- (void)stopAnimations {
    [_gauge stop];
    [_glow.layer removeAllAnimations];
    [_sheen removeAllAnimations];
}

@end

#pragma mark - Presenter

static LCWindow *gWin = nil;
static LCPopupView *gPopup = nil;
static dispatch_block_t gDismiss = nil;
static BOOL gPlugged = NO;

static BOOL LCIsPlugged(void) {
    UIDeviceBatteryState s = [UIDevice currentDevice].batteryState;
    return (s == UIDeviceBatteryStateCharging || s == UIDeviceBatteryStateFull);
}

static void LCTeardown(void) {
    if (gDismiss) {
        dispatch_block_cancel(gDismiss);
        gDismiss = nil;
    }
    [gPopup stopAnimations];
    [gPopup removeFromSuperview];
    gPopup = nil;
    gWin.hidden = YES;
    gWin = nil;
}

static void LCPresent(BOOL charging) {
    LCTeardown();

    float lvl = [UIDevice currentDevice].batteryLevel;
    if (lvl < 0) lvl = 0;

    LCWindow *win = [[LCWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.windowLevel = UIWindowLevelAlert + 1000;
    win.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = NO;
    win.rootViewController = vc;

    if ([win respondsToSelector:@selector(_setSecure:)]) {
        [win _setSecure:YES]; // supaya tampil juga di lockscreen
    }
    win.hidden = NO;
    [win layoutIfNeeded];

    CGFloat top = win.safeAreaInsets.top;
    CGFloat y = (top > 24) ? (top - 10) : 12; // di bawah notch kalau ada

    LCPopupView *popup = [[LCPopupView alloc] initWithLevel:lvl charging:charging];
    popup.center = CGPointMake(CGRectGetMidX(win.bounds), y + LC_H / 2.0);
    [vc.view addSubview:popup];

    gWin = win;
    gPopup = popup;
    [popup playIn];

    __weak LCPopupView *weakPopup = popup;
    dispatch_block_t block = dispatch_block_create(0, ^{
        LCPopupView *p = weakPopup;
        [p playOutWithCompletion:^{
            if (gPopup == p) LCTeardown();
        }];
    });
    gDismiss = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LC_SHOW_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

#pragma mark - Hook

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        gPlugged = LCIsPlugged();

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIDeviceBatteryStateDidChangeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            BOOL now = LCIsPlugged();
            if (now == gPlugged) return; // Charging -> Full dll tidak dihitung
            gPlugged = now;

            // beri jeda sedikit biar level baterai sudah ter-update
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                LCPresent(now);
            });
        }];
    });
}

%end
