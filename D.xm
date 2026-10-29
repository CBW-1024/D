// DDiPad - 登录页 iPhone/iPad 切换，伪装 iPad 登录（单文件版）

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 微信类声明

@interface WCAccountLoginLastUserViewController : UIViewController
@property (nonatomic, strong) UIButton *bothDeviceButton;
- (BOOL)isBakDeviceOrPad;
- (void)refreshView;
// 插件新增方法（%new）
- (void)ddipad_loginModeChanged:(UISegmentedControl *)seg;
- (void)ddipad_loginModeCancel;
- (void)ddipad_loginModeConfirmRestart;
@end

@interface WCAccountMainLoginViewController : UIViewController
@property (nonatomic, strong) UIButton *bothDeviceButton;
// 插件新增方法（%new）
- (void)ddipad_loginModeChanged:(UISegmentedControl *)seg;
- (void)ddipad_loginModeCancel;
- (void)ddipad_loginModeConfirmRestart;
@end

@interface DeviceInfo : NSObject
+ (BOOL)isiPad;
+ (BOOL)isiPadOrVision;
@end

@interface CAppUtil : NSObject
+ (id)getDeviceType;
+ (id)getCurrentDeviceName;
@end

@interface CommonAffClientUtilsObjcStatic : NSObject
+ (id)getDeviceType;
@end

@interface MatrixDeviceInfo : NSObject
+ (BOOL)isiPad;
+ (id)getDeviceType;
@end

@interface DeviceUtility : NSObject
+ (id)SystemNameForDeviceType;
@end

@interface BaseRequest : NSObject
@property (retain, nonatomic) NSData *deviceType;
@end

@interface ManualAuthAesReqData : NSObject
@property (retain, nonatomic) NSString *deviceType;
@property (retain, nonatomic) NSString *deviceModel;
@property (retain, nonatomic) NSString *deviceName;
@property (retain, nonatomic) NSString *iphoneVer;
@property (retain, nonatomic) NSString *softType;
@end

@interface AutoAuthAesReqData : NSObject
@property (retain, nonatomic) NSString *deviceType;
@property (retain, nonatomic) NSString *deviceName;
@property (retain, nonatomic) NSString *softType;
@end

@interface NewSyncRequest : NSObject
@property (retain, nonatomic) NSString *deviceType;
@end

@interface AxAuthRequest : NSObject
@property (retain, nonatomic) NSString *deviceType;
@property (retain, nonatomic) NSString *deviceName;
@property (retain, nonatomic) NSString *softType;
@end

@interface WCUIAlertView : NSObject
+ (id)showAlertWithTitle:(id)arg1 message:(id)arg2 btnTitle:(id)arg3 target:(id)arg4 sel:(SEL)arg5 btnTitle:(id)arg6 target:(id)arg7 sel:(SEL)arg8;
@end

#pragma mark - 配置类

#define kDDiPadIPadLoginModeKey @"ddipad_ipad_login_mode"

@interface DDiPadConfig : NSObject
+ (BOOL)iPadLoginModeEnabled;
+ (void)setIPadLoginModeEnabled:(BOOL)enabled;
@end

@implementation DDiPadConfig

+ (BOOL)iPadLoginModeEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDDiPadIPadLoginModeKey];
}

+ (void)setIPadLoginModeEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDDiPadIPadLoginModeKey];
    [defaults synchronize];
}

@end

#pragma mark - hook 逻辑

static BOOL sDDiPadLoginPageVisible = NO;

static const void *kDDiPadLoginModeSegKey = &kDDiPadLoginModeSegKey;
static const void *kDDiPadLoginModePendingKey = &kDDiPadLoginModePendingKey;

// 是否启用伪装（开关持久化在 NSUserDefaults，直接读取即可）
static BOOL DDiPadLoginOn(void) {
    return [DDiPadConfig iPadLoginModeEnabled];
}

// 仅在登录页生效（进主界面后保持手机功能）
static BOOL DDiPadLoginUISpoofOn(void) {
    return DDiPadLoginOn() && sDDiPadLoginPageVisible;
}

// 将设备标识字符串伪装为 iPad
static NSString *DDiPadifyDeviceString(NSString *s) {
    if (!DDiPadLoginOn()) {
        return s;
    }
    if (s.length == 0) {
        return @"iPad";
    }
    if ([s rangeOfString:@"iPad" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return s;
    }
    NSString *n = [s stringByReplacingOccurrencesOfString:@"iPhone"
    withString:@"iPad"
    options:NSCaseInsensitiveSearch
    range:NSMakeRange(0, s.length)];
    if ([n rangeOfString:@"iPad"].location != NSNotFound) {
        return n;
    }
    return [@"iPad " stringByAppendingString:s];
}

// NSData 形式同上
static NSData *DDiPadifyDeviceData(NSData *data) {
    if (!DDiPadLoginOn() || data.length == 0) {
        return data;
    }
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) {
        return data;
    }
    NSString *n = DDiPadifyDeviceString(s);
    if ([n isEqualToString:s]) {
        return data;
    }
    return [n dataUsingEncoding:NSUTF8StringEncoding];
}

// 挂起并退出，由越狱看门狗重启微信
static void DDiPadLoginModeRestartWeChat(void) {
    UIApplication *app = [UIApplication sharedApplication];
    [app performSelector:@selector(suspend)];
    [NSThread sleepForTimeInterval:0.3];
    exit(0);
}

static UISegmentedControl *DDiPadLoginModeSegment(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kDDiPadLoginModeSegKey);
}

// 同步分段控件选中状态
static void DDiPadLoginModeSyncSegment(UIViewController *vc) {
    UISegmentedControl *seg = DDiPadLoginModeSegment(vc);
    if (!seg) {
        return;
    }
    NSNumber *pending = objc_getAssociatedObject(vc, kDDiPadLoginModePendingKey);
    BOOL pad = pending ? pending.boolValue : [DDiPadConfig iPadLoginModeEnabled];
    NSInteger idx = pad ? 1 : 0;
    if (seg.selectedSegmentIndex != idx) {
        seg.selectedSegmentIndex = idx;
    }
}

// 计算右侧预留空间，避免遮挡其它控件
static CGFloat DDiPadLoginModeRightReserved(UIView *host, UIView *seg) {
    CGFloat reserve = 16.0;
    CGFloat topBand = MAX(host.safeAreaInsets.top, 20.0) + 52.0;
    for (UIView *v in host.subviews) {
        if (v == seg || v.hidden || v.alpha < 0.05) {
            continue;
        }
        CGRect f = v.frame;
        if (CGRectGetMaxY(f) < 8.0 || CGRectGetMinY(f) > topBand) {
            continue;
        }
        if (CGRectGetMinX(f) < host.bounds.size.width * 0.55) {
            continue;
        }
        reserve = MAX(reserve, host.bounds.size.width - CGRectGetMinX(f) + 8.0);
    }
    return reserve;
}

// 把分段控件布局到登录页右上角
static void DDiPadLoginModeLayoutControl(UIViewController *vc) {
    UIView *host = vc.view;
    UISegmentedControl *seg = DDiPadLoginModeSegment(vc);
    if (!host || !seg) {
        return;
    }
    if (seg.superview != host) {
        [host addSubview:seg];
    }
    CGFloat w = 132.0;
    CGFloat h = 31.0;
    CGFloat y = host.safeAreaInsets.top;
    if (y < 20.0) {
        y = 20.0;
    }
    y += 4.0;
    CGFloat x = host.bounds.size.width - DDiPadLoginModeRightReserved(host, seg) - w;
    if (x < 12.0) {
        x = 12.0;
    }
    seg.hidden = NO;
    seg.alpha = 1.0;
    seg.frame = CGRectMake(x, y, w, h);
    if (DDiPadLoginOn() && [vc respondsToSelector:@selector(bothDeviceButton)]) {
        UIButton *both = [(id)vc bothDeviceButton];
        if ([both isKindOfClass:[UIButton class]]) {
            both.hidden = NO;
            both.alpha = 1.0;
            both.userInteractionEnabled = YES;
            [both.superview bringSubviewToFront:both];
        }
    }
    [host bringSubviewToFront:seg];
    DDiPadLoginModeSyncSegment(vc);
}

// 安装 iPhone/iPad 分段控件
static void DDiPadLoginModeInstallControl(UIViewController *vc) {
    if (DDiPadLoginModeSegment(vc)) {
        DDiPadLoginModeLayoutControl(vc);
        return;
    }
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[ @"iPhone", @"iPad" ]];
    seg.selectedSegmentIndex = [DDiPadConfig iPadLoginModeEnabled] ? 1 : 0;
    [seg addTarget:vc action:@selector(ddipad_loginModeChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(vc, kDDiPadLoginModeSegKey, seg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc.view addSubview:seg];
    DDiPadLoginModeLayoutControl(vc);
}

#pragma mark - 登录页

%hook WCAccountLoginLastUserViewController

- (void)viewDidLoad {
    sDDiPadLoginPageVisible = YES;
    %orig;
    DDiPadLoginModeInstallControl(self);
    if (DDiPadLoginOn() && [self respondsToSelector:@selector(refreshView)]) {
        [self refreshView];
        DDiPadLoginModeInstallControl(self);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    sDDiPadLoginPageVisible = YES;
    %orig;
    DDiPadLoginModeInstallControl(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    sDDiPadLoginPageVisible = NO;
}

- (BOOL)isBakDeviceOrPad {
    if (DDiPadLoginOn()) {
        return YES;
    }
    BOOL orig = %orig;
    return orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DDiPadLoginModeInstallControl(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    DDiPadLoginModeLayoutControl(self);
}

- (void)refreshView {
    %orig;
    DDiPadLoginModeInstallControl(self);
}

%new
- (void)ddipad_loginModeChanged:(UISegmentedControl *)seg {
    BOOL wantPad = seg.selectedSegmentIndex == 1;
    BOOL current = [DDiPadConfig iPadLoginModeEnabled];
    if (wantPad == current) {
        objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, @(wantPad), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    Class alertClass = objc_getClass("WCUIAlertView");
    if (alertClass && [alertClass respondsToSelector:@selector(showAlertWithTitle:message:btnTitle:target:sel:btnTitle:target:sel:)]) {
        [alertClass showAlertWithTitle:@"提示"
        message:@"切换登录模式需要重启微信"
        btnTitle:@"取消"
        target:self
        sel:@selector(ddipad_loginModeCancel)
        btnTitle:@"立即重启"
        target:self
        sel:@selector(ddipad_loginModeConfirmRestart)];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
    message:@"切换登录模式需要重启微信"
    preferredStyle:UIAlertControllerStyleAlert];
    WCAccountLoginLastUserViewController *vc = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [vc ddipad_loginModeCancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [vc ddipad_loginModeConfirmRestart];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)ddipad_loginModeCancel {
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DDiPadLoginModeSyncSegment(self);
}

%new
- (void)ddipad_loginModeConfirmRestart {
    NSNumber *pending = objc_getAssociatedObject(self, kDDiPadLoginModePendingKey);
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL wantPad = pending ? pending.boolValue : (DDiPadLoginModeSegment(self).selectedSegmentIndex == 1);
    [DDiPadConfig setIPadLoginModeEnabled:wantPad];
    DDiPadLoginModeRestartWeChat();
}

%end

#pragma mark - 主登录页（无存储账号 / 首次登录）

%hook WCAccountMainLoginViewController

- (void)viewDidLoad {
    sDDiPadLoginPageVisible = YES;
    %orig;
    DDiPadLoginModeInstallControl(self);
}

- (void)viewWillAppear:(BOOL)animated {
    sDDiPadLoginPageVisible = YES;
    %orig;
    DDiPadLoginModeInstallControl(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    sDDiPadLoginPageVisible = NO;
}

- (void)viewDidLayoutSubviews {
    %orig;
    DDiPadLoginModeLayoutControl(self);
}

%new
- (void)ddipad_loginModeChanged:(UISegmentedControl *)seg {
    BOOL wantPad = seg.selectedSegmentIndex == 1;
    BOOL current = [DDiPadConfig iPadLoginModeEnabled];
    if (wantPad == current) {
        objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, @(wantPad), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    Class alertClass = objc_getClass("WCUIAlertView");
    if (alertClass && [alertClass respondsToSelector:@selector(showAlertWithTitle:message:btnTitle:target:sel:btnTitle:target:sel:)]) {
        [alertClass showAlertWithTitle:@"提示"
        message:@"切换登录模式需要重启微信"
        btnTitle:@"取消"
        target:self
        sel:@selector(ddipad_loginModeCancel)
        btnTitle:@"立即重启"
        target:self
        sel:@selector(ddipad_loginModeConfirmRestart)];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
    message:@"切换登录模式需要重启微信"
    preferredStyle:UIAlertControllerStyleAlert];
    WCAccountMainLoginViewController *vc = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [vc ddipad_loginModeCancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [vc ddipad_loginModeConfirmRestart];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)ddipad_loginModeCancel {
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DDiPadLoginModeSyncSegment(self);
}

%new
- (void)ddipad_loginModeConfirmRestart {
    NSNumber *pending = objc_getAssociatedObject(self, kDDiPadLoginModePendingKey);
    objc_setAssociatedObject(self, kDDiPadLoginModePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL wantPad = pending ? pending.boolValue : (DDiPadLoginModeSegment(self).selectedSegmentIndex == 1);
    [DDiPadConfig setIPadLoginModeEnabled:wantPad];
    DDiPadLoginModeRestartWeChat();
}

%end

#pragma mark - 设备伪装

%hook DeviceInfo
+ (BOOL)isiPad {
    if (DDiPadLoginUISpoofOn()) {
        return YES;
    }
    BOOL orig = %orig;
    return orig;
}
+ (BOOL)isiPadOrVision {
    if (DDiPadLoginUISpoofOn()) {
        return YES;
    }
    BOOL orig = %orig;
    return orig;
}
%end

%hook MatrixDeviceInfo
+ (BOOL)isiPad {
    if (DDiPadLoginUISpoofOn()) {
        return YES;
    }
    BOOL orig = %orig;
    return orig;
}
+ (id)getDeviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook DeviceUtility
+ (id)SystemNameForDeviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook CAppUtil
+ (id)getDeviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
+ (id)getCurrentDeviceName {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook CommonAffClientUtilsObjcStatic
+ (id)getDeviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook BaseRequest
- (void)setDeviceType:(NSData *)deviceType {
    %orig(DDiPadifyDeviceData(deviceType));
}
- (NSData *)deviceType {
    NSData *orig = %orig;
    return DDiPadifyDeviceData(orig);
}
%end

%hook ManualAuthAesReqData
- (void)setDeviceType:(NSString *)deviceType {
    %orig(DDiPadifyDeviceString(deviceType));
}
- (NSString *)deviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setDeviceModel:(NSString *)deviceModel {
    %orig(DDiPadifyDeviceString(deviceModel));
}
- (NSString *)deviceModel {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setDeviceName:(NSString *)deviceName {
    %orig(DDiPadifyDeviceString(deviceName));
}
- (NSString *)deviceName {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setIphoneVer:(NSString *)iphoneVer {
    %orig(DDiPadifyDeviceString(iphoneVer));
}
- (NSString *)iphoneVer {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setSoftType:(NSString *)softType {
    %orig(DDiPadifyDeviceString(softType));
}
- (NSString *)softType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook AutoAuthAesReqData
- (void)setDeviceType:(NSString *)deviceType {
    %orig(DDiPadifyDeviceString(deviceType));
}
- (NSString *)deviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setDeviceName:(NSString *)deviceName {
    %orig(DDiPadifyDeviceString(deviceName));
}
- (NSString *)deviceName {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setSoftType:(NSString *)softType {
    %orig(DDiPadifyDeviceString(softType));
}
- (NSString *)softType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook NewSyncRequest
- (void)setDeviceType:(NSString *)deviceType {
    %orig(DDiPadifyDeviceString(deviceType));
}
- (NSString *)deviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%hook AxAuthRequest
- (void)setDeviceType:(NSString *)deviceType {
    %orig(DDiPadifyDeviceString(deviceType));
}
- (NSString *)deviceType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setDeviceName:(NSString *)deviceName {
    %orig(DDiPadifyDeviceString(deviceName));
}
- (NSString *)deviceName {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
- (void)setSoftType:(NSString *)softType {
    %orig(DDiPadifyDeviceString(softType));
}
- (NSString *)softType {
    NSString *orig = %orig;
    return DDiPadifyDeviceString(orig);
}
%end

%ctor {
    %init;
}
