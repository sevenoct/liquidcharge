// LiquidCharge Glass - popup "liquid glass" saat charger connect / disconnect
// Target: iOS 15 (SpringBoard). Build dengan Theos.
// Setting: Settings > LiquidCharge Glass (model Default/Compact/Simple, ukuran, posisi, dan seluruh setting Liquid Glass).

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define LQ_SHOW_SECONDS 3.0

@interface UIWindow (LQPrivate)
- (void)_setSecure:(BOOL)secure;
@end

#pragma mark - Pengaturan tata letak (model, ukuran, posisi)

static NSInteger lqModel = 0;      // 0 Default, 1 Compact, 2 Simple
static CGFloat lqSize = 1.0;       // skala ukuran popup
static NSInteger lqPosition = 0;   // 0 Top, 1 Bottom
static CGFloat lqVOffset = 0;      // jarak tambahan dari tepi layar (menjauhi tepi)
static BOOL lqAccent = YES;        // warna hijau/biru/merah; NO = popup netral (putih)

#pragma mark - Pengaturan Liquid Glass (Settings > LiquidCharge Glass > Popup Glass)

#define LQ_DOMAIN CFSTR("com.hasan.liquidglasscharge")

static id LQPref(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, LQ_DOMAIN));
}
static CGFloat LQNum(NSString *k, CGFloat def) {
    id v = LQPref(k);
    return [v respondsToSelector:@selector(doubleValue)] ? (CGFloat)[v doubleValue] : def;
}
static BOOL LQBool(NSString *k, BOOL def) {
    id v = LQPref(k);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}
static CGFloat LQClamp(CGFloat v, CGFloat lo, CGFloat hi) { return MAX(lo, MIN(hi, v)); }
static UIColor *LQHexColor(id hex, CGFloat a, UIColor *def) {
    if ([hex isKindOfClass:NSString.class]) {
        NSString *h = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# \n"]];
        unsigned v = 0;
        if (h.length == 6 && [[NSScanner scannerWithString:h] scanHexInt:&v])
            return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:a];
    }
    return [def colorWithAlphaComponent:a];
}

@interface LQStyle : NSObject
@property (nonatomic) BOOL enabled, dispersion;
@property (nonatomic) CGFloat blur, refraction, index, thickness, bezel, dispStrength, corner;
@property (nonatomic) NSInteger spec;   // 0 None, 1 Border, 2 Glass, 3 iOS 26, 4 iOS 27
@property (nonatomic, strong) UIColor *lightTint, *darkTint;
+ (instancetype)loadWithPrefix:(NSString *)p;
@end
@implementation LQStyle
+ (instancetype)loadWithPrefix:(NSString *)p {
    LQStyle *s = [LQStyle new];
    #define K(x) [NSString stringWithFormat:@"%@.%@", p, x]
    s.enabled = LQBool(K(@"Enabled"), YES);
    s.blur = LQClamp(LQNum(K(@"Blur"), 20), 0, 60);
    s.refraction = LQClamp(LQNum(K(@"Refraction"), 0.35), -2, 2);
    s.index = LQClamp(LQNum(K(@"RefractiveIndex"), 1.5), 1, 2.5);
    s.thickness = LQClamp(LQNum(K(@"GlassThickness"), 1), 0.1, 4);
    s.bezel = LQClamp(LQNum(K(@"BezelWidth"), 10), 2, 60);
    s.spec = (NSInteger)LQNum(K(@"SpecularType"), 2);
    s.dispersion = LQBool(K(@"DispersionEnabled"), NO);
    s.dispStrength = LQClamp(LQNum(K(@"DispersionStrength"), 0.5), 0, 1);
    s.corner = LQClamp(LQNum(K(@"CornerRadius"), 100), 0, 100);
    s.lightTint = LQHexColor(LQPref(K(@"LightTint")), LQClamp(LQNum(K(@"LightTintAlpha"), 0.25), 0, 1), UIColor.whiteColor);
    s.darkTint = LQHexColor(LQPref(K(@"DarkTint")), LQClamp(LQNum(K(@"DarkTintAlpha"), 0.10), 0, 1), UIColor.whiteColor);
    #undef K
    return s;
}
@end

static BOOL lqMaster = YES, lqMotion = NO;
static CGFloat lqLiquidity = 1, lqQuality = 0.5, lqMotionSens = 1;
static LQStyle *lqStyle;

#pragma mark - Glass views (gaya Liquid Glass: backdrop blur + refraksi + specular rim + dispersi)

static id LQFilter(NSString *type) {
    Class CF = NSClassFromString(@"CAFilter");
    if (!CF) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(CF, NSSelectorFromString(@"filterWithType:"), type);
}

// Peta displacement: di tepi (selebar "bezel") cahaya dibelokkan; 128 = netral
static UIImage *LQDisplacementMap(CGSize sz, CGFloat radius, LQStyle *st) {
    static NSCache *cache;
    if (!cache) { cache = [NSCache new]; cache.countLimit = 24; }
    int W = MAX(2, (int)lround(sz.width)), H = MAX(2, (int)lround(sz.height));
    NSString *key = [NSString stringWithFormat:@"%d,%d,%.1f,%.1f,%.2f,%.2f,%.2f", W, H, radius, st.bezel, st.refraction, st.index, st.thickness];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    CGFloat strength = LQClamp((st.index - 1.0) * st.refraction * st.thickness * 1.6, -1, 1);
    uint8_t *buf = malloc((size_t)W * H * 4);
    float hx = W / 2.0f, hy = H / 2.0f;
    float r = (float)MIN(radius, MIN(hx, hy)), bz = (float)MAX(1, st.bezel);
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            float px = x + 0.5f - hx, py = y + 0.5f - hy;
            float qx = fabsf(px) - (hx - r), qy = fabsf(py) - (hy - r);
            float ox = MAX(qx, 0), oy = MAX(qy, 0);
            float outside = sqrtf(ox * ox + oy * oy);
            float sd = outside + MIN(MAX(qx, qy), 0) - r;     // negatif di dalam
            float d = -sd;
            uint8_t R = 128, G = 128;
            if (d >= 0 && d < bz) {
                float gx, gy;
                if (qx > 0 && qy > 0 && outside > 0) { gx = (px < 0 ? -ox : ox) / outside; gy = (py < 0 ? -oy : oy) / outside; }
                else if (qx > qy) { gx = px < 0 ? -1 : 1; gy = 0; }
                else { gx = 0; gy = py < 0 ? -1 : 1; }
                float t = 1.0f - d / bz;
                float m = powf(t, 2.2f) * (float)strength;
                R = (uint8_t)LQClamp(128 + 127 * gx * m, 0, 255);
                G = (uint8_t)LQClamp(128 + 127 * gy * m, 0, 255);
            }
            uint8_t *p = buf + ((size_t)y * W + x) * 4;
            p[0] = R; p[1] = G; p[2] = 128; p[3] = 255;
        }
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, W, H, 8, (size_t)W * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef ci = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:ci scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(ci); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(buf);
    [cache setObject:img forKey:key];
    return img;
}

// Ring tipis berwarna gradient (specular / dispersi), di-mask jadi garis tepi
@interface LQRimView : UIView
@property (nonatomic) CGFloat lineWidth;
- (void)setColors:(NSArray *)colors locations:(NSArray *)loc width:(CGFloat)w angle:(CGFloat)a;
- (void)setAngle:(CGFloat)a;
@end
@implementation LQRimView { CAShapeLayer *_mask; }
+ (Class)layerClass { return [CAGradientLayer class]; }
- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _mask = [CAShapeLayer layer];
    _mask.fillColor = NULL;
    _mask.strokeColor = UIColor.whiteColor.CGColor;
    self.layer.mask = _mask;
    _lineWidth = 1;
    return self;
}
- (void)setColors:(NSArray *)colors locations:(NSArray *)loc width:(CGFloat)w angle:(CGFloat)a {
    CAGradientLayer *gl = (CAGradientLayer *)self.layer;
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    gl.colors = cg;
    gl.locations = loc;
    _lineWidth = w;
    [self setAngle:a];
    [self setNeedsLayout];
}
- (void)setAngle:(CGFloat)a {
    CAGradientLayer *gl = (CAGradientLayer *)self.layer;
    CGFloat dx = cos(a) * 0.5, dy = sin(a) * 0.5;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gl.startPoint = CGPointMake(0.5 - dx, 0.5 - dy);
    gl.endPoint = CGPointMake(0.5 + dx, 0.5 + dy);
    [CATransaction commit];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = _lineWidth, r = self.superview.layer.cornerRadius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.frame = self.bounds;
    _mask.lineWidth = w;
    _mask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, w / 2, w / 2) cornerRadius:MAX(0, r - w / 2)].CGPath;
    [CATransaction commit];
}
@end

@interface LQGlassView : UIView
@property (nonatomic, readonly) UIView *content;
@property (nonatomic) CGFloat maxRadius;                // 0 = tanpa batas
- (void)applyStyle;
- (void)setMotionAngle:(CGFloat)a;
- (CGFloat)radiusForSize:(CGSize)s;
@end

static NSHashTable<LQGlassView *> *LQRegistry(void) {
    static NSHashTable *t;
    if (!t) t = [NSHashTable weakObjectsHashTable];
    return t;
}

// Dasar kaca = UIVisualEffectView (backdrop yang pasti menangkap wallpaper), lalu filter
// backdrop-nya diganti (blur/saturasi/refraksi) dan lapisan gelap bawaannya disembunyikan
// supaya tampilannya ditentukan oleh tint + rim kita (lebih mirip dock / Control Center).
@implementation LQGlassView {
    UIVisualEffectView *_fx;
    UIView *_tint;
    LQRimView *_red, *_blue, *_spec;
    CGFloat _motion;
    NSString *_lastKey;
    BOOL _glassOn;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    UIViewAutoresizing flex = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _fx.frame = self.bounds; _fx.autoresizingMask = flex;
    [self addSubview:_fx];

    _tint = [[UIView alloc] initWithFrame:self.bounds];
    _tint.autoresizingMask = flex; _tint.userInteractionEnabled = NO;
    [self addSubview:_tint];

    _red = [[LQRimView alloc] initWithFrame:self.bounds];
    _blue = [[LQRimView alloc] initWithFrame:self.bounds];
    _spec = [[LQRimView alloc] initWithFrame:self.bounds];
    [self addSubview:_red]; [self addSubview:_blue]; [self addSubview:_spec];

    _content = [[UIView alloc] initWithFrame:self.bounds];
    _content.autoresizingMask = flex;
    [self addSubview:_content];

    [LQRegistry() addObject:self];
    [self applyStyle];
    return self;
}
- (LQStyle *)style {
    if (!lqStyle) lqStyle = [LQStyle loadWithPrefix:@"Popup"];
    return lqStyle;
}
- (CGFloat)radiusForSize:(CGSize)s {
    CGFloat full = MIN(s.width, s.height) / 2;
    if (_maxRadius > 0) full = MIN(full, _maxRadius);
    return full * [self style].corner / 100.0;
}
- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    [self applyStyle];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    _lastKey = nil;
    [self setNeedsLayout];
}
- (void)setMotionAngle:(CGFloat)a { _motion = a; [self updateSpecAngle]; }
- (void)updateSpecAngle { [_spec setAngle:M_PI_4 + _motion]; }

- (void)applyStyle {
    LQStyle *st = [self style];
    BOOL glass = st.enabled;
    if (_glassOn && !glass) {
        // kembali ke material bawaan: set ulang effect supaya UIKit memasang filter aslinya
        _fx.effect = nil;
        _fx.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    }
    _glassOn = glass;

    BOOL isDark = self.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight;
    _tint.backgroundColor = glass ? (isDark ? st.darkTint : st.lightTint) : UIColor.clearColor;

    UIColor *(^W)(CGFloat) = ^UIColor *(CGFloat a) { return [UIColor colorWithWhite:1 alpha:a]; };
    _spec.hidden = !(glass && st.spec > 0);
    switch (st.spec) {
        // tipis & halus seperti dock / Control Center; terang hanya di sudut kiri-atas & kanan-bawah
        case 1: [_spec setColors:@[W(0.22), W(0.22)] locations:@[@0, @1] width:0.7 angle:M_PI_4]; break;
        case 2: [_spec setColors:@[W(0.50), W(0.12), W(0.05), W(0.10), W(0.30)] locations:@[@0, @0.3, @0.55, @0.8, @1] width:0.8 angle:M_PI_4]; break;
        case 3: [_spec setColors:@[W(0.70), W(0.10), W(0.03), W(0.08), W(0.55)] locations:@[@0, @0.25, @0.5, @0.75, @1] width:0.9 angle:M_PI_4]; break;
        case 4: [_spec setColors:@[W(0.45), W(0.14), W(0.06), W(0.14), W(0.40)] locations:@[@0, @0.3, @0.5, @0.7, @1] width:1.1 angle:M_PI_4]; break;
        default: break;
    }
    [self updateSpecAngle];

    BOOL disp = glass && st.dispersion && st.dispStrength > 0.01;
    _red.hidden = _blue.hidden = !disp;
    if (disp) {
        CGFloat a = 0.35 * st.dispStrength;
        UIColor *rc = [UIColor colorWithRed:1 green:0.25 blue:0.25 alpha:a], *bc = [UIColor colorWithRed:0.25 green:0.55 blue:1 alpha:a];
        [_red setColors:@[rc, rc] locations:@[@0, @1] width:0.9 angle:M_PI_4];
        [_blue setColors:@[bc, bc] locations:@[@0, @1] width:0.9 angle:M_PI_4];
        CGFloat o = 0.3 + 0.9 * st.dispStrength;
        _red.transform = CGAffineTransformMakeTranslation(-o, -o);
        _blue.transform = CGAffineTransformMakeTranslation(o, o);
    }
    _lastKey = nil;
    [self setNeedsLayout];
}

- (void)refreshFilters {
    LQStyle *st = [self style];
    if (!st.enabled) return;
    CGSize sz = self.bounds.size;
    if (sz.width < 2 || sz.height < 2) return;

    // backdrop internal milik UIVisualEffectView + sembunyikan lapisan warna bawaannya
    UIView *bd = nil;
    for (UIView *s in _fx.subviews) {
        if (strstr(object_getClassName(s), "Backdrop")) bd = s;
        else s.hidden = YES;
    }
    if (!bd) return;

    NSMutableArray *f = [NSMutableArray array];
    if (fabs(st.refraction) > 0.001 && st.index > 1.001) {
        id d = LQFilter(@"displacementMap");
        UIImage *map = LQDisplacementMap(sz, self.layer.cornerRadius, st);
        if (d && map) {
            @try {
                [d setValue:(__bridge id)map.CGImage forKey:@"inputImage"];
                [d setValue:@(st.bezel * 1.2) forKey:@"inputAmount"];
                [f addObject:d];
            } @catch (id e) {}
        }
    }
    id blur = LQFilter(@"gaussianBlur");
    if (blur) {
        @try {
            [blur setValue:@(MAX(0.5, st.blur * lqLiquidity)) forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputNormalizeEdges"];
            [f addObject:blur];
        } @catch (id e) {}
    }
    id sat = LQFilter(@"colorSaturate");
    if (sat) { @try { [sat setValue:@1.8 forKey:@"inputAmount"]; [f addObject:sat]; } @catch (id e) {} }
    if (!f.count) return;       // filter privat tidak ada -> biarkan material bawaan

    CALayer *bl = bd.layer;
    @try {
        bl.filters = f;
        if ([bl respondsToSelector:NSSelectorFromString(@"setScale:")]) [bl setValue:@(lqQuality) forKey:@"scale"];
    } @catch (id e) {}
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [_red setNeedsLayout]; [_blue setNeedsLayout]; [_spec setNeedsLayout];
    NSString *k = [NSString stringWithFormat:@"%.1f,%.1f,%.1f", self.bounds.size.width, self.bounds.size.height, self.layer.cornerRadius];
    if ([k isEqualToString:_lastKey]) return;
    _lastKey = k;
    [self refreshFilters];
}
@end


// Highlight mengikuti arah perangkat (kompas)
@interface LQMotion : NSObject
+ (void)refresh;
@end
@implementation LQMotion
+ (void)refresh {
    static CMMotionManager *mm;
    BOOL want = lqMotion && lqMaster && LQRegistry().count > 0;
    if (want && !mm) {
        mm = [CMMotionManager new];
        mm.deviceMotionUpdateInterval = 1.0 / 30;
        CMAttitudeReferenceFrame fr = ([CMMotionManager availableAttitudeReferenceFrames] & CMAttitudeReferenceFrameXMagneticNorthZVertical)
            ? CMAttitudeReferenceFrameXMagneticNorthZVertical : CMAttitudeReferenceFrameXArbitraryZVertical;
        [mm startDeviceMotionUpdatesUsingReferenceFrame:fr toQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *m, NSError *e) {
            if (!m) return;
            CGFloat a = m.attitude.yaw * lqMotionSens;
            for (LQGlassView *v in LQRegistry().allObjects) [v setMotionAngle:a];
        }];
    } else if (!want && mm) {
        [mm stopDeviceMotionUpdates];
        mm = nil;
        for (LQGlassView *v in LQRegistry().allObjects) [v setMotionAngle:0];
    }
}
@end

static void LQLoadPrefs(void) {
    CFPreferencesAppSynchronize(LQ_DOMAIN);
    lqMaster = LQBool(@"Enabled", YES);
    lqLiquidity = LQClamp(LQNum(@"Liquidity", 1), 0.2, 3);
    lqQuality = LQClamp(LQNum(@"Quality", 0.5), 0.15, 1);
    lqMotion = LQBool(@"MotionHighlights", NO);
    lqMotionSens = LQClamp(LQNum(@"MotionSensitivity", 1), 0, 3);
    lqModel = (NSInteger)LQClamp(LQNum(@"Model", 0), 0, 2);
    lqSize = LQClamp(LQNum(@"Size", 1), 0.6, 1.6);
    lqPosition = (NSInteger)LQClamp(LQNum(@"Position", 0), 0, 1);
    lqVOffset = LQClamp(LQNum(@"VerticalOffset", 0), -60, 400);
    lqAccent = LQBool(@"AccentColors", YES);
    lqStyle = [LQStyle loadWithPrefix:@"Popup"];
    for (LQGlassView *v in LQRegistry().allObjects) [v applyStyle];
    [LQMotion refresh];
}

#pragma mark - Window (tembus sentuhan)

@interface LQWindow : UIWindow
@end

@implementation LQWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

static UIImage *LQSymbolImage(NSString *name, CGFloat size) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

#pragma mark - Gauge cairan (lingkaran berisi gelombang)

@interface LQGaugeView : UIView
@property (nonatomic, assign) CGFloat level;
@property (nonatomic, assign) BOOL charging;
@property (nonatomic, assign) CGFloat symbolSize;
@property (nonatomic, strong) UIColor *liquidColor;
@property (nonatomic, copy) void (^onLevel)(CGFloat shown);
- (void)setSymbol:(NSString *)name;
- (void)start;
- (void)stop;
@end

@implementation LQGaugeView {
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
        _symbolSize = 18;
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];

        _back = [CAShapeLayer layer];
        _front = [CAShapeLayer layer];
        [self.layer addSublayer:_back];
        [self.layer addSublayer:_front];

        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 0.5, 0.5)].CGPath;
        _ring.fillColor = nil;
        _ring.strokeColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
        _ring.lineWidth = 1.0;
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
    _icon.image = LQSymbolImage(name, _symbolSize);
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
    CGFloat amp = (1.0 + 3.0 * MIN(1.0, edge * 6.0)) * (self.bounds.size.width / 44.0);
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

#pragma mark - Wash warna aksen di dalam kaca

@interface LQAccentView : UIView
@end
@implementation LQAccentView
+ (Class)layerClass { return [CAGradientLayer class]; }
- (instancetype)initWithFrame:(CGRect)f accent:(UIColor *)accent {
    if (!(self = [super initWithFrame:f])) return nil;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *g = (CAGradientLayer *)self.layer;
    g.colors = @[(id)[accent colorWithAlphaComponent:0.14].CGColor, (id)[accent colorWithAlphaComponent:0.0].CGColor, (id)[accent colorWithAlphaComponent:0.10].CGColor];
    g.startPoint = CGPointMake(0, 0);
    g.endPoint = CGPointMake(1, 1);
    return self;
}
@end

#pragma mark - Popup liquid glass (3 model: Default, Compact, Simple)

@interface LQPopupView : UIView
+ (CGSize)sizeForModel:(NSInteger)model scale:(CGFloat)k;
- (instancetype)initWithLevel:(CGFloat)level charging:(BOOL)charging model:(NSInteger)model scale:(CGFloat)k;
- (void)playInFromTop:(BOOL)top;
- (void)playOutWithCompletion:(void (^)(void))completion;
- (void)stopAnimations;
@end

@implementation LQPopupView {
    LQGlassView *_glass;
    LQGaugeView *_gauge;
    UIImageView *_boltIcon;
    UIView *_glow;
    CAGradientLayer *_sheen;
    UILabel *_percent;
    CADisplayLink *_countLink;
    CGFloat _countShown, _level;
    BOOL _charging, _fromTop;
    NSInteger _model;
    CGFloat _k;
}

+ (CGSize)sizeForModel:(NSInteger)model scale:(CGFloat)k {
    switch (model) {
        case 1: return CGSizeMake(124 * k, 48 * k);   // Compact
        case 2: return CGSizeMake(104 * k, 38 * k);   // Simple
        default: return CGSizeMake(300 * k, 72 * k);  // Default
    }
}

- (UILabel *)labelWithFrame:(CGRect)f text:(NSString *)t font:(UIFont *)font color:(UIColor *)c {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.text = t; l.font = font; l.textColor = c;
    [self addSubview:l];
    return l;
}

- (instancetype)initWithLevel:(CGFloat)level charging:(BOOL)charging model:(NSInteger)model scale:(CGFloat)k {
    CGSize sz = [LQPopupView sizeForModel:model scale:k];
    if ((self = [super initWithFrame:CGRectMake(0, 0, sz.width, sz.height)])) {
        _charging = charging; _model = model; _k = k; _level = level;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

        UIColor *accent;
        if (!lqAccent) {
            accent = [UIColor whiteColor];                  // netral: tanpa hijau/biru/merah
        } else if (charging) {
            accent = [UIColor colorWithRed:0.30 green:0.86 blue:0.47 alpha:1];
        } else if (level <= 0.20) {
            accent = [UIColor colorWithRed:1.00 green:0.33 blue:0.30 alpha:1];
        } else {
            accent = [UIColor colorWithRed:0.62 green:0.82 blue:1.00 alpha:1];
        }

        CGRect b = self.bounds;
        _glass = [[LQGlassView alloc] initWithFrame:b];
        CGFloat r = [_glass radiusForSize:b.size];
        _glass.layer.cornerRadius = r;
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:r];

        // bayangan jatuh
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.30;
        self.layer.shadowRadius = 16 * k;
        self.layer.shadowOffset = CGSizeMake(0, 7 * k);
        self.layer.shadowPath = shape.CGPath;

        // glow berdenyut di belakang kaca
        _glow = [[UIView alloc] initWithFrame:b];
        _glow.backgroundColor = [UIColor clearColor];
        _glow.layer.shadowColor = accent.CGColor;
        _glow.layer.shadowOpacity = 0.0;
        _glow.layer.shadowRadius = 14 * k;
        _glow.layer.shadowOffset = CGSizeZero;
        _glow.layer.shadowPath = shape.CGPath;
        [self addSubview:_glow];

        // kaca (renderer sama dengan GlassSearch: blur + refraksi + specular + dispersi + tint)
        [self addSubview:_glass];
        if (lqAccent) [_glass.content addSubview:[[LQAccentView alloc] initWithFrame:b accent:accent]];

        // kilau yang menyapu saat muncul
        _sheen = [CAGradientLayer layer];
        _sheen.frame = CGRectMake(-80 * k, 0, 80 * k, b.size.height);
        _sheen.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor
        ];
        _sheen.startPoint = CGPointMake(0, 0);
        _sheen.endPoint = CGPointMake(1, 0.45);
        [_glass.content.layer addSublayer:_sheen];

        UIColor *white = [UIColor whiteColor];
        if (model == 1) {
            // Compact: gauge kecil + persen
            _gauge = [[LQGaugeView alloc] initWithFrame:CGRectMake(8 * k, 8 * k, 32 * k, 32 * k)];
            _gauge.symbolSize = 13 * k;
            _percent = [self labelWithFrame:CGRectMake(46 * k, 8 * k, sz.width - 46 * k - 10 * k, 32 * k) text:@"0%"
                                       font:[UIFont monospacedDigitSystemFontOfSize:21 * k weight:UIFontWeightBold] color:white];
        } else if (model == 2) {
            // Simple: ikon petir + persen, tanpa gauge
            _boltIcon = [[UIImageView alloc] initWithFrame:CGRectMake(13 * k, 9 * k, 20 * k, 20 * k)];
            _boltIcon.contentMode = UIViewContentModeCenter;
            _boltIcon.tintColor = accent;
            _boltIcon.image = LQSymbolImage(charging ? @"bolt.fill" : @"bolt.slash.fill", 15 * k);
            [self addSubview:_boltIcon];
            _percent = [self labelWithFrame:CGRectMake(38 * k, 3 * k, sz.width - 38 * k - 12 * k, 32 * k) text:@"0%"
                                       font:[UIFont monospacedDigitSystemFontOfSize:17 * k weight:UIFontWeightSemibold] color:white];
        } else {
            // Default: gauge + judul + subtitle + persen
            _gauge = [[LQGaugeView alloc] initWithFrame:CGRectMake(14 * k, 14 * k, 44 * k, 44 * k)];
            _gauge.symbolSize = 18 * k;
            CGFloat tw = sz.width - 68 * k - 74 * k;
            UILabel *title = [self labelWithFrame:CGRectMake(68 * k, 15 * k, tw, 21 * k)
                                             text:charging ? @"Charger Connected" : @"Charger Disconnected"
                                             font:[UIFont systemFontOfSize:15 * k weight:UIFontWeightSemibold] color:white];
            title.adjustsFontSizeToFitWidth = YES;
            title.minimumScaleFactor = 0.8;
            [self labelWithFrame:CGRectMake(68 * k, 36 * k, tw, 18 * k)
                            text:charging ? @"Charging" : @"On battery"
                            font:[UIFont systemFontOfSize:12.5 * k weight:UIFontWeightMedium]
                           color:[UIColor colorWithWhite:1 alpha:0.68]];
            _percent = [self labelWithFrame:CGRectMake(sz.width - 80 * k, 20 * k, 66 * k, 32 * k) text:@"0%"
                                       font:[UIFont monospacedDigitSystemFontOfSize:24 * k weight:UIFontWeightBold] color:white];
            _percent.textAlignment = NSTextAlignmentRight;
        }

        if (_gauge) {
            _gauge.level = level;
            _gauge.charging = charging;
            _gauge.liquidColor = accent;
            [_gauge setSymbol:charging ? @"bolt.fill" : @"bolt.slash.fill"];
            [self addSubview:_gauge];
            __weak UILabel *wp = _percent;
            _gauge.onLevel = ^(CGFloat shown) {
                wp.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(shown * 100.0)];
            };
        }
    }
    return self;
}

- (void)countTick {
    _countShown += (_level - _countShown) * 0.07;
    _percent.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(_countShown * 100.0)];
}

- (CGFloat)offscreenDelta {
    CGFloat h = self.bounds.size.height;
    if (_fromTop) return -(self.frame.origin.y + h + 30);
    return [UIScreen mainScreen].bounds.size.height - self.frame.origin.y + 30;
}

- (void)playInFromTop:(BOOL)top {
    _fromTop = top;
    CGFloat dy = [self offscreenDelta];
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

    CGFloat W = self.bounds.size.width;
    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue = @(-40 * _k);
    sweep.toValue = @(W + 40 * _k);
    sweep.duration = 1.0;
    sweep.beginTime = CACurrentMediaTime() + 0.25;
    sweep.fillMode = kCAFillModeBackwards;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_sheen addAnimation:sweep forKey:@"sweep"];

    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    glow.fromValue = @0.15;
    glow.toValue = @(_charging ? 0.75 : 0.40);
    glow.duration = _charging ? 0.75 : 1.1;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    glow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    if (lqAccent) [_glow.layer addAnimation:glow forKey:@"glow"];

    if (_gauge) {
        [_gauge start];
    } else {
        _countShown = 0;
        _countLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(countTick)];
        [_countLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        if (_charging) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            pulse.fromValue = @1.0; pulse.toValue = @1.22; pulse.duration = 0.65;
            pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
            pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [_boltIcon.layer addAnimation:pulse forKey:@"pulse"];
        }
    }

    @try {
        UIImpactFeedbackGenerator *g =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [g impactOccurred];
    } @catch (__unused NSException *e) {}
}

- (void)playOutWithCompletion:(void (^)(void))completion {
    CGFloat dy = [self offscreenDelta];
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
    [_countLink invalidate];
    _countLink = nil;
    [_boltIcon.layer removeAllAnimations];
    [_glow.layer removeAllAnimations];
    [_sheen removeAllAnimations];
}

@end

#pragma mark - Presenter

static LQWindow *gWin = nil;
static LQPopupView *gPopup = nil;
static dispatch_block_t gDismiss = nil;
static BOOL gPlugged = NO;

static BOOL LQIsPlugged(void) {
    UIDeviceBatteryState s = [UIDevice currentDevice].batteryState;
    return (s == UIDeviceBatteryStateCharging || s == UIDeviceBatteryStateFull);
}

static void LQTeardown(void) {
    if (gDismiss) {
        dispatch_block_cancel(gDismiss);
        gDismiss = nil;
    }
    [gPopup stopAnimations];
    [gPopup removeFromSuperview];
    gPopup = nil;
    gWin.hidden = YES;
    gWin = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ [LQMotion refresh]; });
}

static void LQPresent(BOOL charging) {
    LQTeardown();
    LQLoadPrefs();
    if (!lqMaster) return;

    float lvl = [UIDevice currentDevice].batteryLevel;
    if (lvl < 0) lvl = 0;

    LQWindow *win = [[LQWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
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

    LQPopupView *popup = [[LQPopupView alloc] initWithLevel:lvl charging:charging model:lqModel scale:lqSize];
    CGSize ps = popup.bounds.size;
    CGFloat H = win.bounds.size.height;
    BOOL bottom = (lqPosition == 1);
    CGFloat y;
    if (!bottom) {
        CGFloat top = win.safeAreaInsets.top;
        y = ((top > 24) ? (top - 10) : 12) + lqVOffset;                 // di bawah notch kalau ada
    } else {
        CGFloat bot = win.safeAreaInsets.bottom;
        y = H - MAX(bot, 12) - 10 - ps.height - lqVOffset;              // di atas home indicator
    }
    y = MAX(0, MIN(y, H - ps.height));
    popup.center = CGPointMake(CGRectGetMidX(win.bounds), y + ps.height / 2.0);
    [vc.view addSubview:popup];

    gWin = win;
    gPopup = popup;
    [popup playInFromTop:!bottom];
    [LQMotion refresh];

    __weak LQPopupView *weakPopup = popup;
    dispatch_block_t block = dispatch_block_create(0, ^{
        LQPopupView *p = weakPopup;
        [p playOutWithCompletion:^{
            if (gPopup == p) LQTeardown();
        }];
    });
    gDismiss = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LQ_SHOW_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

#pragma mark - Notifikasi dari Settings (setting berubah / preview)

static void LQPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ LQLoadPrefs(); });
}
static void LQPreviewOn(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ [UIDevice currentDevice].batteryMonitoringEnabled = YES; LQPresent(YES); });
}
static void LQPreviewOff(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{ [UIDevice currentDevice].batteryMonitoringEnabled = YES; LQPresent(NO); });
}

#pragma mark - Hook

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        gPlugged = LQIsPlugged();

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIDeviceBatteryStateDidChangeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            BOOL now = LQIsPlugged();
            if (now == gPlugged) return; // Charging -> Full dll tidak dihitung
            gPlugged = now;

            // beri jeda sedikit biar level baterai sudah ter-update
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                LQPresent(now);
            });
        }];
    });
}

%end

%ctor {
    @autoreleasepool {
        LQLoadPrefs();
        CFNotificationCenterRef dc = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(dc, NULL, LQPrefsChanged, CFSTR("com.hasan.liquidglasscharge/prefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(dc, NULL, LQPreviewOn, CFSTR("com.hasan.liquidglasscharge/preview-on"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(dc, NULL, LQPreviewOff, CFSTR("com.hasan.liquidglasscharge/preview-off"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
