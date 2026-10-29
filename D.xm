//
//  DDiPad.xm
//  登录页 iPhone / iPad 切换：伪装 iPad 登录，可与手机同时在线
//  单文件版：微信类声明 + 配置类 + hook 逻辑全部内联
//  微信类签名已对照微信 8.0.80 头文件核验
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>


#pragma mark - 微信类手动前向声明（对照 8.0.80 头文件核验，不 import dump）

@interface WCAccountLoginLastUserViewController : UIViewController
@property (nonatomic, strong) UIButton *bothDeviceButton;   // 真实: out/WeChat/headers/WCAccountLoginLastUserViewController.h L50
- (BOOL)isBakDeviceOrPad;                                   // 真实 L128
- (void)refreshView;                                        // 真实 L124
@end

#pragma mark - 设备信息判定

@interface DeviceInfo : NSObject
+ (BOOL)isiPad;                                             // 真实: DeviceInfo.h L63
+ (BOOL)isiPadOrVision;                                     // 真实 L64
@end

@interface CAppUtil : NSObject
+ (id)getDeviceType;                                        // 真实: CAppUtil.h L146
+ (id)getCurrentDeviceName;                                 // 真实 L154
@end

@interface CommonAffClientUtilsObjcStatic : NSObject
+ (id)getDeviceType;                                        // 真实: CommonAffClientUtilsObjcStatic.h L5
@end

@interface MatrixDeviceInfo : NSObject
+ (BOOL)isiPad;                                             // 真实: MatrixDeviceInfo.h L5
+ (id)getDeviceType;                                        // 真实 L7
@end

@interface DeviceUtility : NSObject
+ (id)SystemNameForDeviceType;                              // 真实: DeviceUtility.h L6
@end

#pragma mark - 鉴权请求（device 字段伪装目标）

@interface BaseRequest : NSObject
@property (retain, nonatomic) NSData *deviceType;           // 真实: BaseRequest.h L9
@end

@interface ManualAuthAesReqData : NSObject
@property (retain, nonatomic) NSString *deviceType;         // 真实: ManualAuthAesReqData.h L13
@property (retain, nonatomic) NSString *deviceModel;        // 真实 L19
@property (retain, nonatomic) NSString *deviceName;         // 真实 L12
@property (retain, nonatomic) NSString *iphoneVer;          // 真实 L24
@property (retain, nonatomic) NSString *softType;          // 真实 L8
@end

@interface AutoAuthAesReqData : NSObject
@property (retain, nonatomic) NSString *deviceType;         // 真实: AutoAuthAesReqData.h L14
@property (retain, nonatomic) NSString *deviceName;        // 真实 L13
@property (retain, nonatomic) NSString *softType;          // 真实 L9
@end

@interface NewSyncRequest : NSObject
@property (retain, nonatomic) NSString *deviceType;         // 真实: NewSyncRequest.h L9
@end

@interface AxAuthRequest : NSObject
@property (retain, nonatomic) NSString *deviceType;         // 真实: AxAuthRequest.h L12
@property (retain, nonatomic) NSString *deviceName;         // 真实 L11
@property (retain, nonatomic) NSString *softType;          // 真实 L9
@end

#pragma mark - 弹窗（运行时 objc_getClass 获取，此处补签名消除编译警告）

@interface WCUIAlertView : NSObject
+ (id)showAlertWithTitle:(id)arg1 message:(id)arg2 btnTitle:(id)arg3 target:(id)arg4 sel:(SEL)arg5 btnTitle:(id)arg6 target:(id)arg7 sel:(SEL)arg8; // 真实: WCUIAlertView.h L13
@end

#pragma mark - DDiPad 配置类（NSUserDefaults 持久化）

// 持久化开关所用的 NSUserDefaults key（修复：原合并脚本从 @interface 截断，丢掉了该宏定义）
#define kDDiPadIPadLoginModeKey @"ddipad_ipad_login_mode"

@interface DDiPadConfig : NSObject

/// 是否启用 iPad 登录伪装模式
+ (BOOL)iPadLoginModeEnabled;

/// 设置并持久化 iPad 登录伪装开关
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

#pragma mark - 插件逻辑（hook）


static BOOL sDDiPadLogin = NO;
static BOOL sDDiPadLoginPageVisible = NO;

static const void *kDDiPadLoginModeSegKey = &kDDiPadLoginModeSegKey;
static const void *kDDiPadLoginModePendingKey = &kDDiPadLoginModePendingKey;

// 微信类前向声明已移至 WeChatHeaders.h（手动声明，对照 8.0.80 头文件核验）

static BOOL DDiPadLoginOn(void) {
    return sDDiPadLogin || [DDiPadConfig iPadLoginModeEnabled];
}

static BOOL DDiPadLoginUISpoofOn(void) {
    return DDiPadLoginOn() && sDDiPadLoginPageVisible;
}

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

static void DDiPadLoginModeRestartWeChat(void) {
    UIApplication *app = [UIApplication sharedApplication];
    [app performSelector:@selector(suspend)];
    [NSThread sleepForTimeInterval:0.3];
    exit(0);
}

static UISegmentedControl *DDiPadLoginModeSegment(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kDDiPadLoginModeSegKey);
}

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
    seg.frame = CGRectMake(x, y, w, h);
    if (DDiPadLoginOn() && [vc respondsToSelector:@selector(bothDeviceButton)]) {
        UIButton *both = [(WCAccountLoginLastUserViewController *)vc bothDeviceButton];
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

#pragma mark - 登录页分段控件

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

#pragma mark - 伪装 iPad 登录（仅登录页按 iPad 显示，进主界面后保持手机功能）

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
    sDDiPadLogin = [DDiPadConfig iPadLoginModeEnabled];
}
