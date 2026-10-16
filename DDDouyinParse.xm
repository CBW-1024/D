
// DDDouyinParse —— 微信内抖音分享链接解析插件（Theos / Logos 单文件）
//
// 管线：识别抖音链接 → 挂主窗口的离屏 WKWebView 抓官方分享页 SSR → 提取去水印直链（视频 / 图集）
//      → 面板「发送 / 预览 / 存相册」
// 抓取部分逐指令还原自 PKC（PKCWeChatTools.dylib 的 KTSbtohnheiubqgnumbhtvssnpulxfbo）：
// WebView 必须 addSubview 到 app 主窗口（只是 hidden），否则 WebContent 进程不被调度、JS 不跑，
// 表现就是「时好时坏」。详见下方抓取小节的反汇编注释。
//
// 私有类一律用 %c() 在运行时取，编译期不产生链接符号；下方只声明插件用到的方法。
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVKit/AVKit.h>
#import <unistd.h>     // sleep() —— PKC 重载循环原样用的就是这个

#pragma mark - 微信私有类声明

@interface WeToast : NSObject
+ (instancetype)toast;
- (void)setLoadingStyle:(BOOL)style;
- (void)showToastWithText:(NSString *)text;
- (void)showDoneToastWithText:(NSString *)text;
- (void)showErrorToastWithText:(NSString *)text;
- (void)hideWithAnimated:(int)animated;
@end

@interface CMessageWrap : NSObject
@property (retain, nonatomic) NSString *m_nsContent;
@property (nonatomic) unsigned int m_uiMessageType;
@property (retain, nonatomic) NSString *m_nsFromUsr;
@property (retain, nonatomic) NSString *m_nsToUsr;
@property (retain, nonatomic) NSString *m_nsTitle;
@property (nonatomic) unsigned int m_uiStatus;
@property (nonatomic) unsigned int m_uiCreateTime;
- (id)initWithMsgType:(long long)type;
+ (BOOL)isSenderFromMsgWrap:(id)wrap;
@end

@interface SettingUtil : NSObject
+ (id)getLocalUsrName:(unsigned int)arg1;
@end

@interface BaseMsgContentViewController : UIViewController
- (NSString *)getCurrentChatName;
@end

@interface BaseMsgContentLogicController : NSObject
- (instancetype)init;
- (CMessageWrap *)FormImageMsg:(NSString *)arg1 withImage:(UIImage *)arg2 withData:(NSData *)arg3;
- (void)AddVideoMsg:(NSString *)fromUsr ToUsr:(NSString *)toUsr VideoInfo:(id)info;
@end

@interface MMContext : NSObject
+ (id)activeUserContext;
- (id)getService:(Class)arg1;
@end

@interface CMessageMgr : NSObject
- (id)AddVideoMsg:(NSString *)fromUsr ToUsr:(NSString *)toUsr VideoInfo:(id)info;
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap;
@end

@protocol DDPMsgExtendOperation <NSObject>
- (void)setImage:(UIImage *)arg1 withData:(NSData *)arg2 isOriginImage:(BOOL)arg3;
@end
@interface CMessageWrap (DDP)
- (id<DDPMsgExtendOperation>)m_extendInfoWithMsgType;
@end

@interface CUtility : NSObject
+ (NSString *)GetMMUserAgent;
@end

@interface CRUtils : NSObject
+ (NSString *)md5:(NSString *)str;
@end

// MMMenuItem 直接继承 NSObject（无 title getter），识别注入项一律走 userInfo 打标记。
@interface MMMenuItem : NSObject
@property (nonatomic, retain) id userInfo;
- (instancetype)initWithTitle:(NSString *)title svgName:(NSString *)svgName target:(id)target action:(SEL)action;
- (void)setMenuType:(long long)type;
@end

@interface WCActionSheet : NSObject
- (instancetype)initWithTitle:(NSString *)title cancelButtonTitle:(NSString *)cancelTitle;
- (long long)addButtonWithTitle:(NSString *)title eventAction:(void (^)(void))action;
- (void)showInView:(UIView *)view;
@end

@interface WCTableViewManager : NSObject
- (instancetype)initWithFrame:(struct CGRect)arg1 style:(long long)arg2;
- (void)clearAllSection;
- (id)getTableView;
- (void)addSection:(id)arg1;
- (void)reloadTableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (id)defaultSection;
- (void)addCell:(id)arg1;
- (void)setHeaderTitle:(id)arg1;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 on:(BOOL)arg4;
+ (id)normalCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// 微信自定义菜单控制器：气泡菜单与浮窗预览菜单最终都经 setMenuItems: 装配，故在此统一注入
@interface MMMenuController : NSObject
- (void)setMenuItems:(id)items;
@end


// 可缩放单图页：UIScrollView + UIImageView，支持捏合/双击缩放，背景随深色模式
@interface DDPPhotoPage : UIViewController <UIScrollViewDelegate>
@property (nonatomic, copy) NSString *path;
@end
@implementation DDPPhotoPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sv.minimumZoomScale = 1.0;
    sv.maximumZoomScale = 4.0;
    sv.delegate = self;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:self.path]];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = sv.bounds;
    iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [sv addSubview:iv];
    [self.view addSubview:sv];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return scrollView.subviews.firstObject;
}
@end

// 多图浏览器：UIPageViewController 左右滑切换
@interface DDPPhotoBrowser : UIPageViewController <UIPageViewControllerDataSource>
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, copy) void (^onSaveCurrent)(NSString *path);
@end
@implementation DDPPhotoBrowser
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.dataSource = self;
    if (self.paths.count)
        [self setViewControllers:@[[self pageAt:0]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(ddp_dismiss:)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStylePlain target:self action:@selector(ddp_saveCurrent:)];
}
- (DDPPhotoPage *)pageAt:(NSInteger)i {
    DDPPhotoPage *p = [[DDPPhotoPage alloc] init];
    p.path = self.paths[i];
    return p;
}
- (UIViewController *)pageViewController:(UIPageViewController *)pc viewControllerBeforeViewController:(UIViewController *)vc {
    NSInteger i = [self.paths indexOfObject:[(DDPPhotoPage *)vc path]];
    return (i > 0) ? [self pageAt:i - 1] : nil;
}
- (UIViewController *)pageViewController:(UIPageViewController *)pc viewControllerAfterViewController:(UIViewController *)vc {
    NSInteger i = [self.paths indexOfObject:[(DDPPhotoPage *)vc path]];
    return (i < (NSInteger)self.paths.count - 1) ? [self pageAt:i + 1] : nil;
}
- (void)ddp_dismiss:(id)sender { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)ddp_saveCurrent:(id)sender {
    DDPPhotoPage *cur = (DDPPhotoPage *)self.viewControllers.firstObject;
    if (cur.path && self.onSaveCurrent) self.onSaveCurrent(cur.path);
}
@end

// 视频信息构造（微信私有类）
@interface CaptureVideoInfo : NSObject
- (void)setVideo_path:(id)path;
- (void)setThumb_path:(id)path;
- (void)setVideo_size:(unsigned int)size;
- (void)setVideo_time:(unsigned int)time;
- (void)setVideo_width:(unsigned int)width;
- (void)setVideo_height:(unsigned int)height;
- (void)setThumb_size:(unsigned int)size;
- (void)setM_videoCreateTime:(unsigned int)createTime;
- (void)setM_uiIsSenderStatus:(unsigned int)senderStatus;
- (void)setM_nsSpecifiedChatName:(id)chatName;
@end

#pragma mark - 日志（落盘 tmp/DDDParse.log）

static inline NSString *DDDLogPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse.log"];
}
static void DDDWriteLog(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSString *path = DDDLogPath();
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile];
}
static NSString *DDDReadLog(void) {
    return [NSString stringWithContentsOfFile:DDDLogPath() encoding:NSUTF8StringEncoding error:nil];
}
static void DDDClearLog(void) {
    [[NSFileManager defaultManager] removeItemAtPath:DDDLogPath() error:nil];
}
#define DDDLog(fmt, ...) do { NSString *__s = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; NSLog(@"[DDDParse] %@", __s); DDDWriteLog(__s); } while (0)

// 同一 key 只落一次：用于高频路径（每来一条消息都会跑的判定），
// 既能看出「这段到底走没走过」，又不会把日志刷爆。用来甄别死代码。
// ⚠️ 坑：clang 的 ObjC 预处理不把 [...] 当保护组，方括号里的逗号会被切成多个宏实参。
//    所以 key 不要写成 DDDLogOnce([NSString stringWithFormat:@"x-%u", n], ...)，
//    必须先算成局部变量再传（CI 已在 arm64/arm64e 上验证过这个写法会编译失败）。
static NSMutableSet *gDDDOnceKeys(void) {
    static NSMutableSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}
// 注意：AddMsg 在微信消息线程、菜单在主线程，set 会被并发访问，故加锁（锁内只做查/插，很快）
#define DDDLogOnce(key, fmt, ...) do { \
    NSString *__k = (key); \
    BOOL __first = NO; \
    NSMutableSet *__s = gDDDOnceKeys(); \
    @synchronized (__s) { if (![__s containsObject:__k]) { [__s addObject:__k]; __first = YES; } } \
    if (__first) DDDLog(fmt, ##__VA_ARGS__); \
} while (0)

#pragma mark - 配置

static NSString * const kDDPEnabledKey = @"DDDouyinParseEnabled";
@interface DDPConfig : NSObject
@property (nonatomic, assign) BOOL enabled;
+ (instancetype)shared;
@end
@implementation DDPConfig
+ (instancetype)shared {
    static DDPConfig *i; static dispatch_once_t once; dispatch_once(&once, ^{ i = [[self alloc] init]; }); return i;
}
- (instancetype)init {
    if (self = [super init]) _enabled = [NSUserDefaults.standardUserDefaults boolForKey:kDDPEnabledKey];
    return self;
}
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kDDPEnabledKey]; }
@end

#pragma mark - 工具函数

static BOOL DDPContainsDouyinLink(NSString *text) {
    BOOL r = [text containsString:@"douyin.com"];
    DDDLogOnce((r ? @"contain-Y" : @"contain-N"), @"[工具] DDPContainsDouyinLink=%d", r);
    return r;
}

// 排除直播：抖音直播分享文案含「正在直播」
static BOOL DDPIsDouyinLiveText(NSString *text) {
    BOOL r = [text containsString:@"正在直播"];
    DDDLogOnce((r ? @"live-Y" : @"live-N"), @"[工具] DDPIsDouyinLiveText=%d", r);
    return r;
}

static BOOL DDPIsOutgoing(CMessageWrap *wrap) { return [%c(CMessageWrap) isSenderFromMsgWrap:wrap]; }

// 抽取文本中的第一个抖音 http(s) URL（只认 douyin.com，避免文案里其他链接抢先被抠走）
static NSString *DDPExtractURL(NSString *text) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s\"']+" options:0 error:nil];
    NSUInteger seen = 0;
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        seen++;
        NSString *u = [text substringWithRange:m.range];
        if ([u containsString:@"douyin.com"]) {
            DDDLog(@"[工具] DDPExtractURL：扫到第 %lu 个 URL 命中 → %@", (unsigned long)seen, u);
            return u;
        }
    }
    DDDLog(@"[工具] DDPExtractURL：扫了 %lu 个 URL，无 douyin.com", (unsigned long)seen);
    return nil;
}

// 去水印：/playwm/ → /play/，清晰度固定 720p
static NSString *DDPRemoveWatermark(NSString *url) {
    NSString *clean = [url stringByReplacingOccurrencesOfString:@"/playwm/" withString:@"/play/"];
    NSRegularExpression *reRatio = [NSRegularExpression regularExpressionWithPattern:@"ratio=\\d+p" options:0 error:nil];
    clean = [reRatio stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@"ratio=720p"];
    if ([clean rangeOfString:@"ratio="].location == NSNotFound) {
        NSString *sep = ([clean rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
        clean = [clean stringByAppendingFormat:@"%@ratio=720p", sep];
    }
    BOOL changed = ![clean isEqualToString:url];
    DDDLogOnce((changed ? @"wm-Y" : @"wm-N"), @"[工具] 去水印%@\n    前 %@\n    后 %@",
               changed ? @"生效" : @"无变化（若恒无变化则本函数可简化）", url, clean);
    return clean;
}

// 视频缓存路径 <md5>.mp4（md5 用微信原生 CRUtils）
static NSString *DDPTempPath(NSString *url) {
    NSString *md5 = [%c(CRUtils) md5:url];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[md5 stringByAppendingString:@".mp4"]];
}
// 图片缓存路径 <md5>.<ext>
static NSString *DDPTempPathExt(NSString *url, NSString *ext) {
    NSString *md5 = [%c(CRUtils) md5:url];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", md5, ext]];
}
// 取 URL 后缀作为临时文件扩展名（默认 jpg）
static NSString *DDPImageExt(NSString *url) {
    NSString *ue = [url pathExtension].lowercaseString;
    NSString *r = ue.length ? ue : @"jpg";
    DDDLogOnce([@"ext-" stringByAppendingString:r], @"[工具] DDPImageExt：%@ → %@%@", url, r, ue.length ? @"" : @"（走默认 jpg 兜底）");
    return r;
}

// 主窗口：单主窗口 app，直接取 AppDelegate.window，不遍历场景
// 注：与上面的 DDPHostWindow() 功能重复（后者多了 connectedScenes 兜底），留着看日志确认调用点
static inline UIWindow *DDPKeyWindow(void) {
    UIWindow *w = UIApplication.sharedApplication.delegate.window;
    DDDLogOnce((w ? @"keywin-Y" : @"keywin-N"), @"[工具] DDPKeyWindow 被调用，返回%@", w ? @"窗口" : @"nil");
    return w;
}

static WeToast *DDPToast(void) { return [%c(WeToast) toast]; }
static WeToast *gDDPBusyToast;
static void DDPHideLoading(void) {
    void (^work)(void) = ^{ [gDDPBusyToast hideWithAnimated:YES]; gDDPBusyToast = nil; };
    if ([NSThread isMainThread]) work(); else dispatch_async(dispatch_get_main_queue(), work);
}
static void DDPShowLoading(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DDPHideLoading();
        WeToast *t = DDPToast(); [t setLoadingStyle:YES]; [t showToastWithText:text]; gDDPBusyToast = t;
    });
}
static void DDPShowError(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{ DDPHideLoading(); [DDPToast() showErrorToastWithText:text]; });
}
static void DDPShowDone(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{ DDPHideLoading(); [DDPToast() showDoneToastWithText:text]; });
}

#pragma mark - 抓取：逐指令还原 PKC 的 KTSbtohnheiubqgnumbhtvssnpulxfbo

// 反汇编基准（PKCWeChatTools.dylib / arm64 / vmaddr==fileoff，全部按字节核对过）：
//   -init                                 @0x3c340
//   -fetchHTMLFromURL:completion:         @0x3c6d8
//   -webView:didStartProvisionalNavigation:@0x3cd08   （空函数，只有一条 ret）
//   -webView:didFinishNavigation:         @0x3cd0c
//     └ 延时 block                         @0x3cdd4
//        └ JS 回调 block                   @0x3ce34
//   -cleanupWebView                        @0x3d148
//   窗口容器 sub_0x3c5f0：[UIApplication sharedApplication].delegate.window，
//                       取不到再退回首个 connectedScene 的 window
//
// 「时好时坏」的根凶就在这里：PKC 把单例 WKWebView **addSubview 到 app 主窗口**（只是 hidden=YES）。
// 挂窗之后 WebContent 进程才被正常调度、页面 JS 才会执行；WebView 游离在窗口之外时，
// 偶尔能出结果、偶尔不出——这正是旧实现不稳定的原因，本次按 PKC 原样修掉。
//
// ZDY 的「官方 API」路线（ttwid 注册 / aweme/detail / iesdouyin）已整条移除，原因：
//   · aweme/detail 要 uifid —— 由 ArgusSecurityPlugin 的 JS 挑战在真实 WebView 里种下，
//     而 iOS 上 WKWebView 的 cookie 罐与 NSURLSession 互不共享，纯 NSURLSession 永远拿不到
//     uifid（对真实端点验证过：带有效 ttwid 依旧 403 Uifid Not Found）。
//   · iesdouyin 要 X-Gorgon 签名，同样过不去。
// 唯一稳定可用的就是下面这条 WebView SSR 路线。

typedef NS_ENUM(NSInteger, DDPMediaType) {
    DDPMediaTypeUnknown = -1,
    DDPMediaTypeVideo   = 0,
    DDPMediaTypeImage   = 1,
};
static const NSInteger DDPCodeGallery = 0xF4161;   // PKC 的图集标记，原值就是 0xF4161

// PKC 的窗口容器（sub_0x3c5f0）
static UIWindow *DDPHostWindow(void) {
    UIWindow *w = UIApplication.sharedApplication.delegate.window;
    if (w) return w;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            UIWindow *fw = [(UIWindowScene *)sc windows].firstObject;
            if (fw) return fw;
        }
    }
    return nil;
}

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, assign) BOOL warmingUp;      // 预热导航期间跳过抠 HTML
@property (nonatomic, assign) double startAt;      // 本次抓取起点（CFAbsoluteTime），用于耗时日志
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger code, NSError *error);
+ (instancetype)sharedFetcher;
+ (void)ddpWarmup;                                              // 预热：建单例 + 挂窗 + 冷启动 WebContent
+ (void)ddpWarmupStep:(int)step;                                // 预热内部：主窗口未就绪时退避重试挂窗
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger code, NSError *error))completion;
- (void)cleanupWebView;
- (void)ddpRetryLoop:(NSURLRequest *)req;                       // PKC block@0x3cae8
- (void)ddpHandleHTML:(id)result error:(NSError *)error;        // PKC block@0x3ce34
- (NSInteger)extractDurationFromHTML:(NSString *)html;          // PKC @0xe2210
@end

@implementation DDPWebFetcher
+ (instancetype)sharedFetcher {
    static DDPWebFetcher *i; static dispatch_once_t once; dispatch_once(&once, ^{ i = [[self alloc] init]; }); return i;
}

// PKC -init@0x3c340：建一次 WKWebView → 开 JS → 换 UA → 设代理 → 挂主窗口 → frame=窗口 bounds → hidden=YES
// 注意：本方法很可能被 %ctor 的预热在极早期调用，此时 app 主窗口可能还没建好（win=nil）。
// 挂不上的话由 -fetchHTMLFromURL: 的补挂分支兜底（见下）。
- (instancetype)init {
    if (self = [super init]) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;   // 等价 PKC 的 [prefs setJavaScriptEnabled:YES]
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        NSString *ua = [%c(CUtility) GetMMUserAgent];
        _webView.customUserAgent = ua;
        _webView.navigationDelegate = self;
        UIWindow *win = DDPHostWindow();
        if (win) { [win addSubview:_webView]; _webView.frame = win.bounds; }
        _webView.hidden = YES;
        DDDLog(@"WebView init：挂窗=%@ UA长度=%lu", win ? @"成功" : @"失败(待补挂)", (unsigned long)ua.length);
    }
    return self;
}

// 预热（实测必需）：PKC 的 WebView 是常驻单例、tweak 初始化时就建好并已跑过页面，
// 所以它的首轮（等 retries=2 秒）就能命中。我们原来是懒加载，第一次解析才 init，
// 冷启动 WebContent 进程 2 秒根本不够 → 首轮必 miss → 只能靠后面几轮硬撞，实测 58 秒。
// 这里把冷启动成本提前付掉：建单例 + 挂窗 + 跑一个空文档把 WebContent 进程拉起来。
+ (void)ddpWarmup {
    dispatch_async(dispatch_get_main_queue(), ^{ [self ddpWarmupStep:0]; });
}
+ (void)ddpWarmupStep:(int)step {
    DDPWebFetcher *f = [self sharedFetcher];
    if (!f.webView.window) {                       // 还没真正挂到窗口层级上
        UIWindow *win = DDPHostWindow();
        if (!win) {
            if (step >= 20) { DDDLog(@"预热：等了 20 次仍无主窗口，放弃（将退化为懒加载+补挂）"); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self ddpWarmupStep:step + 1]; });
            return;
        }
        [win addSubview:f.webView];
        f.webView.frame = win.bounds;
        f.webView.hidden = YES;
        DDDLog(@"预热：第 %d 次尝试挂窗成功", step);
    }
    f.warmingUp = YES;                             // 预热导航不参与抠 HTML
    [f.webView loadHTMLString:@"<!DOCTYPE html><html><body>ddp</body></html>" baseURL:nil];
    DDDLog(@"预热：已发起空文档导航 step=%d", step);
}

// PKC -fetchHTMLFromURL:completion:@0x3c6d8
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger code, NSError *error))completion {
    self.completion = completion;
    self.hasCompleted = NO;
    self.startAt = CFAbsoluteTimeGetCurrent();
    // 预热导航可能还没回来（WebContent 进程启动慢），此时用户就开始解析了；
    // 若不清标志，这次真实导航的 didFinish 会被当成预热而跳过，白白吃掉首轮机会。
    self.warmingUp = NO;
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        NSError *err = [NSError errorWithDomain:@"InvalidURL" code:1001
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL string"}];
        DDDLog(@"fetchHTMLFromURL: URL 非法 → %@", url);
        if (completion) completion(nil, 0, err);
        return;
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];

    // 补挂：预热若因主窗口还没建好而没挂上，这里再试一次。
    // 判定用 webView.window（是否真在窗口层级里），而不是 navigationDelegate —— 后者 init 时就设过、
    // 永远非空，照 PKC 原样写的那个分支是死的，永远不会补挂。
    if (!_webView.window) {
        UIWindow *win = DDPHostWindow();
        if (win) {
            [win addSubview:_webView];
            _webView.frame = win.bounds;
            DDDLog(@"fetchHTMLFromURL: WebView 未挂窗 → 已补挂");
        } else {
            DDDLog(@"fetchHTMLFromURL: 警告——拿不到主窗口，WebView 游离（解析大概率失败）");
        }
        _webView.navigationDelegate = self;
    }
    _webView.hidden = YES;

    DDDLog(@"fetchHTMLFromURL: %@（挂窗=%@）", url, _webView.window ? @"是" : @"否");
    // PKC：dispatch_async(全局队列, block@0x3cae8) 跑重载驱动
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [self ddpRetryLoop:req]; });
}

// PKC 的重载驱动 block@0x3cae8：
//   retries=1 → while(retries!=0 && retries<11){ 主队列 loadRequest; retries++; sleep(retries+10); }
//   最多 11 轮，全 miss 才回调 error 500；一旦命中（hasCompleted）立刻退出
- (void)ddpRetryLoop:(NSURLRequest *)req {
    self.retries = 1;
    int round = 0;
    if (self.hasCompleted) { [self cleanupWebView]; return; }
    while (self.retries != 0 && self.retries < 11) {
        round++;
        DDDLog(@"[轮%d] loadRequest（retries=%u，累计%.1fs）", round, self.retries, CFAbsoluteTimeGetCurrent() - self.startAt);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView loadRequest:req];
            self.retries = self.retries + 1;
        });
        // 这里读到的 retries 可能是 1 也可能是 2：主队列那个 block 是否已执行不确定（PKC 原样竞态）
        unsigned sl = (unsigned)(self.retries + 10);
        DDDLog(@"[轮%d] sleep(%u)s 开始（累计%.1fs）", round, sl, CFAbsoluteTimeGetCurrent() - self.startAt);
        sleep(sl);
        if (self.hasCompleted) {
            DDDLog(@"[轮%d] 唤醒，已命中 → 退出（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
            break;
        }
        DDDLog(@"[轮%d] 唤醒，未命中 → 再来一轮（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
    }
    if (self.retries >= 11 && self.completion && !self.hasCompleted) {
        self.hasCompleted = YES;
        NSError *err = [NSError errorWithDomain:@"DDP" code:500
                                      userInfo:@{NSLocalizedDescriptionKey: @"页面加载超时，请重试"}];
        DDDLog(@"[轮%d] 达到 11 轮上限，放弃（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
        self.completion(nil, 0, err);
    }
    [self cleanupWebView];
}

// PKC -webView:didStartProvisionalNavigation:@0x3cd08 —— 空实现（原样保留）
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {}

// PKC -webView:didFinishNavigation:@0x3cd0c：等 retries 秒再抠 outerHTML
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // 预热导航：只用来把 WebContent 进程拉起来，不抠 HTML（否则空文档会走一遍 miss 分支）
    if (self.warmingUp) {
        self.warmingUp = NO;
        DDDLog(@"预热：空文档导航完成，WebContent 进程已就绪");
        return;
    }
    int64_t delay = (int64_t)((unsigned long long)self.retries * NSEC_PER_SEC) + 5;   // PKC: (int64_t)(retries*1e9 + 5.0)
    DDDLog(@"didFinish（累计%.1fs）→ 等 %llds 再抠 outerHTML（retries=%u）",
           CFAbsoluteTimeGetCurrent() - self.startAt, (long long)(delay / NSEC_PER_SEC), self.retries);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
            [self ddpHandleHTML:result error:error];
        }];
    });
}

// PKC 的 JS 回调 block@0x3ce34：还原转义 → 风控提示 → 打标记 → 命中才回调
- (void)ddpHandleHTML:(id)result error:(NSError *)error {
    double el = CFAbsoluteTimeGetCurrent() - self.startAt;
    if (error) { DDDLog(@"抠HTML：JS 报错 %@（累计%.1fs）", error.localizedDescription, el); return; }
    if (![result isKindOfClass:[NSString class]]) { DDDLog(@"抠HTML：结果非字符串，跳过（累计%.1fs）", el); return; }
    NSMutableString *html = [NSMutableString string];
    [html setString:result];
    NSRange full = NSMakeRange(0, html.length);
    // 逐步记录替换处数：哪一步恒为 0 就说明它没在干活，可以删
    NSUInteger len0 = html.length;
    NSUInteger n1 = [html replaceOccurrencesOfString:@"\\u0026" withString:@"&" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    NSUInteger n2 = [html replaceOccurrencesOfString:@"amp;" withString:@"" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    NSUInteger n3 = [html replaceOccurrencesOfString:@"u002F" withString:@"/" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    NSUInteger n4 = [html replaceOccurrencesOfString:@"\\" withString:@"" options:NSCaseInsensitiveSearch range:full];
    DDDLog(@"[清洗] 长度 %lu→%lu｜\\u0026→& %lu 处｜amp;→空 %lu 处｜u002F→/ %lu 处｜\\→空 %lu 处",
           (unsigned long)len0, (unsigned long)html.length,
           (unsigned long)n1, (unsigned long)n2, (unsigned long)n3, (unsigned long)n4);

    BOOL risk = [html containsString:@"验证码中间页"];
    if (risk) [DDPToast() showToastWithText:@"被检测了，请验证后再试"];
    _webView.hidden = !risk;

    NSInteger dur = [self extractDurationFromHTML:html];
    BOOL gallery = [html containsString:@"aweme-share-swiper-item"] || [html containsString:@"aweme-slides-swiper-item"];
    BOOL video   = [html containsString:@"video_id="];
    DDDLog(@"抠HTML：长度=%lu gallery=%d video=%d dur=%ld risk=%d（累计%.1fs）",
           (unsigned long)html.length, gallery, video, (long)dur, risk, el);
    // 三类标记全无 → 不回调，交给重载循环再来一轮（PKC 原样；
    // PKC 还比了一个 dur==0xF4161，那是死分支：dur 是「秒」，永远不可能等于 0xF4161）
    if (!gallery && !video && dur != DDPCodeGallery) {
        DDDLog(@"抠HTML：三个标记全无 → 本轮 miss，等重载循环");
        return;
    }

    NSInteger code = gallery ? DDPCodeGallery : dur;
    if (self.completion && !self.hasCompleted) {
        self.hasCompleted = YES;
        DDDLog(@"抠HTML：命中 code=%ld → 回调（总耗时 %.1fs）", (long)code, CFAbsoluteTimeGetCurrent() - self.startAt);
        self.completion(html, code, nil);
    }
    self.retries = 0;   // 通知重载循环收工
}

// PKC -extractDurationFromHTML:@0xe2210：正则 "bit_rate":null,"duration":(\d+)，组1 / 1000
- (NSInteger)extractDurationFromHTML:(NSString *)html {
    if (!html.length) return 0;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\"bit_rate\":null,\"duration\":(\\d+)"
                                                                       options:0 error:&err];
    if (err) return 0;
    NSTextCheckingResult *m = [re firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (!m || m.numberOfRanges < 2) {
        DDDLog(@"[抽取·时长] 未匹配到 \"bit_rate\":null,\"duration\" → 0（图集页正常；视频页若恒 0 则正则需修）");
        return 0;
    }
    NSInteger d = [[html substringWithRange:[m rangeAtIndex:1]] intValue] / 1000;
    DDDLog(@"[抽取·时长] 原始 %@ → %ld 秒", [html substringWithRange:[m rangeAtIndex:1]], (long)d);
    return d;
}

// PKC -cleanupWebView@0x3d148：webView.hidden=YES（并清掉 RwFlag，我们无此标志位）
- (void)cleanupWebView {
    if (_webView) _webView.hidden = YES;
}
@end

#pragma mark - 解析引擎

@interface DDPEngine : NSObject
+ (instancetype)shared;
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion;
- (NSData *)downloadVideoFromURL:(NSString *)url;
@end

@implementation DDPEngine
+ (instancetype)shared {
    static DDPEngine *i; static dispatch_once_t once; dispatch_once(&once, ^{ i = [[self alloc] init]; }); return i;
}
// 视频：正则抠 playwm 直链并去水印、去重
- (NSArray<NSString *> *)extractVideoLinksFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+"
        options:NSRegularExpressionCaseInsensitive error:nil];
    NSUInteger raw = 0, skipped = 0, dup = 0;
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        raw++;
        NSString *u = [[html substringWithRange:m.range] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        if ([u containsString:@"video_id=https:"]) { skipped++; continue; }
        NSString *clean = DDPRemoveWatermark(u);
        if (![result containsObject:clean]) [result addObject:clean]; else dup++;
    }
    DDDLog(@"[抽取·视频] 正则命中 %lu 个｜video_id 过滤掉 %lu 个｜重复去重 %lu 个｜最终 %lu 个",
           (unsigned long)raw, (unsigned long)skipped, (unsigned long)dup, (unsigned long)result.count);
    return [result copy];
}

// 图集：只取第一个 "images" 容器（页面会把同一份图集重复嵌入多次，实测首个容器即完整图集）
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *decoded = [html mutableCopy];
    NSUInteger len0 = decoded.length;
    NSUInteger g1 = [decoded replaceOccurrencesOfString:@"\\u002f" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    NSUInteger g2 = [decoded replaceOccurrencesOfString:@"\\/" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    NSUInteger g3 = [decoded replaceOccurrencesOfString:@"\\\"" withString:@"\"" options:0 range:NSMakeRange(0, decoded.length)];
    NSUInteger g4 = [decoded replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, decoded.length)];
    DDDLog(@"[抽取·图集] 解码 %lu→%lu｜\\u002f→/ %lu｜\\/→/ %lu｜\\\"→\" %lu｜&quot;→\" %lu",
           (unsigned long)len0, (unsigned long)decoded.length,
           (unsigned long)g1, (unsigned long)g2, (unsigned long)g3, (unsigned long)g4);

    // 统计 "images" 出现次数：若多于 1 次，说明「只取第一个容器」这条假设有风险
    NSUInteger imgCount = 0;
    NSRange sr = NSMakeRange(0, decoded.length);
    while (sr.length > 0) {
        NSRange f = [decoded rangeOfString:@"\"images\"" options:NSCaseInsensitiveSearch range:sr];
        if (f.location == NSNotFound) break;
        imgCount++;
        NSUInteger next = NSMaxRange(f);
        if (next >= decoded.length) break;
        sr = NSMakeRange(next, decoded.length - next);
    }
    NSRange cr = [decoded rangeOfString:@"\"images\"" options:NSCaseInsensitiveSearch];
    if (cr.location == NSNotFound) { DDDLog(@"[抽取·图集] 无 \"images\" 容器 → 空"); return @[]; }
    DDDLog(@"[抽取·图集] \"images\" 共 %lu 处，取首个 @%lu%@",
           (unsigned long)imgCount, (unsigned long)cr.location,
           imgCount > 1 ? @"（多处：首容器即完整图集 这条假设需复核）" : @"");
    NSRange br = [decoded rangeOfString:@":[" options:0 range:NSMakeRange(cr.location, MIN(decoded.length - cr.location, 64))];
    NSInteger arrOpen = (br.location != NSNotFound) ? ((NSInteger)br.location + (NSInteger)br.length - 1) : -1;
    NSInteger arrEnd = -1, depth = 0;
    for (NSInteger i = arrOpen; i >= 0 && i < (NSInteger)decoded.length; i++) {
        unichar ch = [decoded characterAtIndex:i];
        if (ch == '[') depth++;
        else if (ch == ']') { depth--; if (depth == 0) { arrEnd = i; break; } }
    }
    if (arrEnd > arrOpen) {
        NSString *seg = [decoded substringWithRange:NSMakeRange(arrOpen, arrEnd - arrOpen + 1)];
        NSRegularExpression *reU = [NSRegularExpression
            regularExpressionWithPattern:@"\"url_list\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\""
            options:NSRegularExpressionCaseInsensitive error:nil];
        for (NSTextCheckingResult *m in [reU matchesInString:seg options:0 range:NSMakeRange(0, seg.length)]) {
            [result addObject:[[seg substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]];
        }
        DDDLog(@"[抽取·图集] 容器长度 %lu，url_list 抠出 %lu 张", (unsigned long)seg.length, (unsigned long)result.count);
    } else {
        DDDLog(@"[抽取·图集] 数组边界未闭合（arrOpen=%ld arrEnd=%ld）→ 空", (long)arrOpen, (long)arrEnd);
    }
    return [result copy];
}
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    DDDLog(@"parseDouyinURL 入参=%@", url);
    // 唯一路线：PKC 那套「挂主窗口的离屏 WKWebView」抓 SSR HTML。
    // aweme/detail 等 web API 需要 uifid（由 ArgusSecurityPlugin 的 JS 挑战在真实 WebView 里种下），
    // 而 iOS 上 WKWebView 的 cookie 罐与 NSURLSession 互不共享，纯 NSURLSession 永远拿不到 uifid，
    // 故 API 路线结构性过不了风控（已对真实端点验证：403 Uifid Not Found），已整条移除。
    [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSInteger code, NSError *err) {
        if (html.length) {
            NSArray *videos = [self extractVideoLinksFromHTML:html];
            if (videos.count) {
                DDDLog(@"parseDouyinURL → 命中视频 code=%ld", (long)code);
                if (completion) completion(DDPMediaTypeVideo, videos.firstObject, nil, nil);
                return;
            }
            NSArray *images = [self extractGalleryImagesFromHTML:html];
            if (images.count) {
                DDDLog(@"parseDouyinURL → 命中图集 数=%lu code=%ld", (unsigned long)images.count, (long)code);
                if (completion) completion(DDPMediaTypeImage, nil, images, nil);
                return;
            }
            DDDLog(@"parseDouyinURL → 有 HTML 但抠不到直链 code=%ld", (long)code);
        } else {
            DDDLog(@"parseDouyinURL → 没拿到 HTML code=%ld err=%@", (long)code, err);
        }
        if (completion) completion(DDPMediaTypeUnknown, nil, nil,
                                   err ?: [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
    }];
}
// 同步下载（信号量阻塞）
- (NSData *)downloadVideoFromURL:(NSString *)url {
    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";
    [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    [request setValue:url forHTTPHeaderField:@"Referer"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    NSString *ua = [%c(CUtility) GetMMUserAgent];
    [request setValue:(ua.length ? ua : @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15") forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSData *result = nil; __block NSInteger dcode = -1; __block NSString *derr = nil;
    double t0 = CFAbsoluteTimeGetCurrent();
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) dcode = (NSInteger)((NSHTTPURLResponse *)resp).statusCode;
        derr = err.localizedDescription;
        if (!err && data) result = data;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    DDDLog(@"[下载] 字节=%lu HTTP=%ld 耗时=%.2fs err=%@ url=%@",
           (unsigned long)(result ? result.length : 0), (long)dcode, CFAbsoluteTimeGetCurrent() - t0, derr ?: @"nil",
           ([url length] > 120) ? [[url substringToIndex:120] stringByAppendingString:@"…"] : url);
    return result;
}
@end

#pragma mark - 面板与服务

static BOOL gDDPDyTcEnable;   // 一次性放行：防「直接发送」重发被自己拦截

static CMessageMgr *DDPMessageMgr(void) {
    return [[%c(MMContext) activeUserContext] getService:%c(CMessageMgr)];
}
// 取当前会话名：在 VC 树里找 BaseMsgContentViewController
static NSString *DDPCurrentChatName(void) {
    UIViewController *vc = DDPKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    NSMutableArray *stack = vc ? [NSMutableArray arrayWithObject:vc] : [NSMutableArray array];
    while (stack.count) {
        UIViewController *cur = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([cur isKindOfClass:%c(BaseMsgContentViewController)]) {
            NSString *name = [(BaseMsgContentViewController *)cur getCurrentChatName];
            if (name.length) return name;
        }
        if (cur.childViewControllers.count) [stack addObjectsFromArray:cur.childViewControllers];
        if (cur.presentedViewController) [stack addObject:cur.presentedViewController];
    }
    return nil;
}
// 自建 CMessageWrap 走 AddMsg 发送（先置 gDDPDyTcEnable 放行自身重发）
static void DDPSendTextMsg(NSString *content, NSString *user) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CMessageWrap *wrap = [[%c(CMessageWrap) alloc] initWithMsgType:1];
        wrap.m_nsFromUsr   = [%c(SettingUtil) getLocalUsrName:0];
        wrap.m_nsToUsr     = user;
        wrap.m_uiStatus    = 4;
        wrap.m_nsContent   = content;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        gDDPDyTcEnable = YES;
        [DDPMessageMgr() AddMsg:user MsgWrap:wrap];
    });
}

@interface DDPPanel : NSObject
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user;
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user;
+ (void)handleParseSend:(NSString *)url user:(NSString *)user;
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc;
+ (void)handleParseLink:(NSString *)url user:(NSString *)user;
+ (void)handleSaveAlbum:(NSString *)url;
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user;
+ (NSString *)generateThumbnailForVideoPath:(NSString *)path;
+ (void)sendImageAtPath:(NSString *)path toUser:(NSString *)user;
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls user:(NSString *)user finish:(void(^)(void))finish;
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc;
+ (void)saveVideoToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion;
+ (void)saveImageToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion;
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish;
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)shareURL user:(NSString *)user finish:(void(^)(void))finish;
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion;
+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc;
@end

@implementation DDPPanel

+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    NSString *url = DDPExtractURL(content);
    if (!url.length) return NO;
    UIViewController *top = DDPKeyWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    WCActionSheet *sheet = [[%c(WCActionSheet) alloc] initWithTitle:@"抖音解析" cancelButtonTitle:@"取消"];
    [sheet addButtonWithTitle:@"直接发送" eventAction:^{ [DDPPanel handleDirectSend:content user:user]; }];
    [sheet addButtonWithTitle:@"解析发送" eventAction:^{ [DDPPanel handleParseSend:url user:user]; }];
    [sheet addButtonWithTitle:@"解析预览" eventAction:^{ [DDPPanel handleParsePreview:url fromVC:top]; }];
    [sheet addButtonWithTitle:@"解析链接" eventAction:^{ [DDPPanel handleParseLink:url user:user]; }];
    [sheet addButtonWithTitle:@"保存相册" eventAction:^{ [DDPPanel handleSaveAlbum:url]; }];
    [sheet showInView:DDPKeyWindow()];
    return YES;
}

+ (void)handleDirectSend:(NSString *)content user:(NSString *)user {
    gDDPDyTcEnable = YES;
    DDPSendTextMsg(content, user);
}

+ (void)handleParseSend:(NSString *)url user:(NSString *)user {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) { DDPShowError(@"解析失败"); return; }
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) [self sendVideoForURL:videoURL shareURL:url user:user finish:finish];
        else [self sendImagesForURLs:imageURLs user:user finish:finish];
    }];
}

// 下载视频直链并发到聊天
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)url user:(NSString *)user finish:(void(^)(void))finish {
    NSString *path = DDPTempPath(url);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
        if (![data writeToFile:path atomically:YES]) { DDPShowError(@"解析失败"); return; }
        if (finish) finish();
        [DDPPanel sendVideoAtPath:path toUser:user];
    });
}

// 下载图片直链并批量存相册
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSInteger total = 0, done = 0, failed = 0;
        dispatch_queue_t q = dispatch_queue_create("ddp.save", DISPATCH_QUEUE_SERIAL);
        for (NSString *imgURL in urls) {
            NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
            if (!data.length) continue;
            NSString *path = DDPTempPathExt(imgURL, DDPImageExt(imgURL));
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
            if (![data writeToFile:path atomically:YES]) continue;
            total++;
            [DDPPanel saveImageToAlbumAtPath:path completion:^(BOOL success) {
                dispatch_async(q, ^{
                    done++; if (!success) failed++;
                    if (done < total) return;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (failed == 0) DDPShowDone(@"保存成功");
                        else if (failed < total) DDPShowDone(@"部分保存成功");
                        else DDPShowError(@"保存失败");
                    });
                });
            }];
        }
        if (total == 0 && finish) finish();
    });
}

// 生成视频缩略图：取第 0.5s 帧 → JPEG
+ (NSString *)generateThumbnailForVideoPath:(NSString *)path {
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVAsset assetWithURL:[NSURL fileURLWithPath:path]]];
    gen.appliesPreferredTrackTransform = YES;
    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 2) actualTime:NULL error:NULL];
    NSData *jpg = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.5);
    if (cg) CGImageRelease(cg);
    if (!jpg) return nil;
    NSString *thumbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.jpg", [[NSUUID UUID] UUIDString]]];
    [jpg writeToFile:thumbPath atomically:YES];
    return thumbPath;
}

// 发视频消息：手动构造 CaptureVideoInfo（不走 genVideoInfoWithVideoUrl:，否则传本地 fileURL 属性不全→发送崩溃）
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) return;
        NSString *thumbPath = [self generateThumbnailForVideoPath:path];

        id info = [[%c(CaptureVideoInfo) alloc] init];
        if (!info) return;   // info 为空时传给 AddVideoMsg 会崩

        NSFileManager *fm = [NSFileManager defaultManager];
        unsigned long long fileSize = 0;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs) fileSize = [attrs fileSize];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        Float64 seconds = CMTimeGetSeconds(asset.duration);
        if (!(seconds > 0)) seconds = 1;
        unsigned int width = 0, height = 0;
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        if (track) {
            CGSize sz = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
            width = (unsigned int)llround(fabs(sz.width));
            height = (unsigned int)llround(fabs(sz.height));
        }
        unsigned int thumbSize = 0;
        NSDictionary *thumbAttrs = [fm attributesOfItemAtPath:thumbPath error:nil];
        if (thumbAttrs) thumbSize = (unsigned int)[thumbAttrs fileSize];

        [info setVideo_path:path];
        if (thumbPath) [info setThumb_path:thumbPath];
        [info setVideo_size:(unsigned int)MIN(fileSize, 0xFFFFFFFFu)];
        [info setVideo_time:(unsigned int)MAX(1, (int)llround(seconds))];
        [info setVideo_width:width];
        [info setVideo_height:height];
        [info setThumb_size:thumbSize];
        [info setM_videoCreateTime:(unsigned int)[[NSDate date] timeIntervalSince1970]];
        [info setM_uiIsSenderStatus:1];
        [info setM_nsSpecifiedChatName:chatName];

        NSString *from = [%c(SettingUtil) getLocalUsrName:0];
        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        if (ctrl) [ctrl AddVideoMsg:from ToUsr:chatName VideoInfo:info];
        else [DDPMessageMgr() AddVideoMsg:from ToUsr:chatName VideoInfo:info];
    });
}

// 发图片消息（wrap 由 BaseMsgContentLogicController.FormImageMsg 构造）
+ (void)sendImageAtPath:(NSString *)path toUser:(NSString *)user {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) return;
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        NSData *data = UIImagePNGRepresentation(image);
        if (!data.length) return;
        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        CMessageWrap *wrap = [ctrl FormImageMsg:chatName withImage:image withData:data];
        id<DDPMsgExtendOperation> ext = [wrap m_extendInfoWithMsgType];
        [ext setImage:image withData:data isOriginImage:YES];
        [DDPMessageMgr() AddMsg:chatName MsgWrap:wrap];   // 图片消息不会命中抖音面板拦截
    });
}

// 下载图片直链并逐张发进聊天
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls user:(NSString *)user finish:(void(^)(void))finish {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL anySent = NO;
        for (NSString *imgURL in urls) {
            @autoreleasepool {
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
                if (!data.length) continue;
                NSString *path = DDPTempPathExt(imgURL, DDPImageExt(imgURL));
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                if ([data writeToFile:path atomically:YES]) {
                    [DDPPanel sendImageAtPath:path toUser:user];
                    anySent = YES;
                }
            }
        }
        if (!anySent) DDPShowError(@"解析失败");
        else if (finish) finish();
    });
}

+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) { DDPShowError(@"解析失败"); return; }
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            NSString *path = DDPTempPath(url);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                if ([data writeToFile:path atomically:YES])
                    dispatch_async(dispatch_get_main_queue(), ^{ [DDPPanel playVideoAtPath:path fromVC:vc]; });
                finish();
            });
        } else {
            [DDPPanel downloadImagesLocally:imageURLs completion:^(NSArray<NSString *> *paths) {
                if (paths.count) [DDPPanel presentImageViewer:paths fromVC:vc];
                finish();
            }];
        }
    }];
}

// 视频预览：系统 AVPlayerViewController（自带关闭 + 画中画按钮），不自定义、不内置保存
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc {
    AVPlayerViewController *pvc = [[AVPlayerViewController alloc] init];
    pvc.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    pvc.allowsPictureInPicturePlayback = YES;
    [vc presentViewController:pvc animated:YES completion:^{ [pvc.player play]; }];
}

// 下载图片直链到本地缓存（供预览，不存相册；复用 MD5 缓存）
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion {
    double t0 = CFAbsoluteTimeGetCurrent();
    DDDLog(@"[下载·图集] 开始串行下载 %lu 张", (unsigned long)urls.count);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *out = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *imgURL in urls) {
            NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
            NSString *path = DDPTempPathExt(imgURL, DDPImageExt(imgURL));
            if (data.length) {
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                [data writeToFile:path atomically:YES];
            }
            if ([fm fileExistsAtPath:path]) [out addObject:path];
        }
        DDDLog(@"[下载·图集] %lu 张串行下载完成 成功 %lu 张 总耗时 %.2fs",
               (unsigned long)urls.count, (unsigned long)out.count, CFAbsoluteTimeGetCurrent() - t0);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(out); });
    });
}

+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc {
    DDPPhotoBrowser *browser = [[DDPPhotoBrowser alloc] init];
    browser.paths = paths;
    browser.onSaveCurrent = ^(NSString *path) {
        [DDPPanel saveImageToAlbumAtPath:path completion:^(BOOL success) {
            if (success) DDPShowDone(@"保存成功"); else DDPShowError(@"保存失败");
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    [vc presentViewController:nav animated:YES completion:nil];
}

+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDDLog(@"[面板] handleParseLink 入口 url=%@ user=%@", url, user.length ? user : @"(空→取当前会话)");
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || type == DDPMediaTypeUnknown) { DDDLog(@"[面板] handleParseLink 失败 err=%@", err); DDPShowError(@"解析失败"); return; }
            DDDLog(@"[面板] handleParseLink 成功 type=%ld", (long)type);
            DDPHideLoading();
            NSString *link = (type == DDPMediaTypeVideo) ? videoURL : [imageURLs componentsJoinedByString:@"\n"];
            NSString *target = user.length ? user : DDPCurrentChatName();
            if (link.length && target.length) DDPSendTextMsg(link, target);
        });
    }];
}

+ (void)handleSaveAlbum:(NSString *)url {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) { DDPShowError(@"解析失败"); return; }
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            NSString *path = DDPTempPath(url);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                if ([data writeToFile:path atomically:YES])
                    [DDPPanel saveVideoToAlbumAtPath:path completion:^(BOOL success) {
                        if (success) DDPShowDone(@"保存成功"); else DDPShowError(@"保存失败");
                    }];
                else DDPShowError(@"解析失败");
            });
        } else {
            [self downloadAndSaveImages:imageURLs finish:finish];
        }
    }];
}

// 存相册（视频）
+ (void)saveVideoToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) { if (completion) completion(NO); return; }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) { if (completion) completion(success); }];
    }];
}

// 存相册（图片）：直接写原始字节（不经 UIImage 解码，避免重编码）。
// creationRequestForAssetFromImageData: 在 iOS 15 已移除，改用 creationRequestForAsset + addResource
+ (void)saveImageToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) { if (completion) completion(NO); return; }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) { if (completion) completion(NO); return; }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            [req addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
            req.creationDate = [NSDate date];
        } completionHandler:^(BOOL success, NSError *error) {
            if (!success) DDDLog(@"saveImageToAlbumAtPath: 失败 %@", error);
            if (completion) completion(success);
        }];
    }];
}

@end

#pragma mark - Hook：长按菜单「解析 / 预览」

// 从消息对象取判定文本：文本消息用 m_nsContent，其余（分享卡片等）用 m_nsTitle
static NSString *ddp_wrapContent(CMessageWrap *wrap) {
    return wrap ? ((wrap.m_uiMessageType == 1) ? wrap.m_nsContent : wrap.m_nsTitle) : nil;
}
// 菜单对应的消息与宿主 VC：由 BaseMsgContentViewController willShowMenuController: 直传并缓存。
// 微信在该回调里把消息对象(inMsgWrap)直接交给插件，无需从 cell 反查，也没有时序风险。
// 不清空——下次菜单显示时会被覆盖；handler 在菜单点击时才触发，清空会导致拿不到消息。
static CMessageWrap *gDDPMenuWrap;
static UIViewController *gDDPMenuVC;
// 注入菜单项（已注入则跳过）；用 action 派生的 userInfo 去重（MMMenuItem 无 title getter）
static NSArray *ddp_inject_item(id cell, NSArray *original, BOOL enabled, NSString *title, NSString *svgName, SEL action, long long menuType) {
    if (!enabled) return original;
    NSString *token = [@"ddp:" stringByAppendingString:NSStringFromSelector(action)];
    for (MMMenuItem *it in original)
        if ([it.userInfo isKindOfClass:[NSString class]] && [(NSString *)it.userInfo isEqualToString:token]) {
            DDDLogOnce([@"skipdup-" stringByAppendingString:token], @"[Hook] 菜单项已存在 → 跳过重复注入（%@）", token);
            return original;
        }
    MMMenuItem *item = [[%c(MMMenuItem) alloc] initWithTitle:title svgName:svgName target:cell action:action];
    if (!item) return original;   // item 为空时 addObject:nil 会崩
    [item setUserInfo:token];
    [item setMenuType:menuType];
    NSMutableArray *items = [NSMutableArray arrayWithArray:original];
    [items addObject:item];
    return items;
}

// 菜单显示前的统一入口：微信把消息对象(inMsgWrap)直接传进来，覆盖气泡菜单与浮窗预览菜单。
// 只 hook 2 参重载——实测它每次菜单都最先被调用（4 参在其后），且缓存在 %orig 之前完成，
// 到 setMenuItems: 时必然已就绪；4 参独有的 menuSourceType/buttonList 我们并未使用。
%hook BaseMsgContentViewController
- (void)willShowMenuController:(id)menu inMsgWrap:(id)wrap {
    gDDPMenuWrap = wrap; gDDPMenuVC = self;
    %orig;
}
%new
- (void)ddp_vcParse:(id)sender {
    NSString *url = DDPExtractURL(ddp_wrapContent(gDDPMenuWrap));
    if (url.length) [DDPPanel handleParseSend:url user:DDPCurrentChatName()];
}
%new
- (void)ddp_vcPreview:(id)sender {
    NSString *url = DDPExtractURL(ddp_wrapContent(gDDPMenuWrap));
    if (url.length) [DDPPanel handleParsePreview:url fromVC:self];
}
%end

#pragma mark - Hook：MMMenuController setMenuItems（统一菜单注入点）

// 唯一注入点：气泡菜单与浮窗预览菜单最终都经此装配。
// 消息内容来自 willShowMenuController: 直传的 gDDPMenuWrap，菜单项 target 用宿主 VC。
// 已存在同 token 项时 ddp_inject_item 会跳过，不会重复。
%hook MMMenuController
- (void)setMenuItems:(NSArray *)items {
    NSString *content = ddp_wrapContent(gDDPMenuWrap);
    BOOL enabled = DDPConfig.shared.enabled
                   && DDPContainsDouyinLink(content) && !DDPIsDouyinLiveText(content);
    DDDLogOnce((enabled ? @"menu-Y" : @"menu-N"),
               @"[Hook] setMenuItems：注入=%d（开关=%d 含抖音=%d 直播=%d）原始项数=%lu",
               enabled, DDPConfig.shared.enabled, content ? DDPContainsDouyinLink(content) : 0,
               content ? DDPIsDouyinLiveText(content) : 0, (unsigned long)items.count);
    NSArray *all = ddp_inject_item(gDDPMenuVC, items, enabled, @"解析", @"icons_filled_search", @selector(ddp_vcParse:), 1010);
    all = ddp_inject_item(gDDPMenuVC, all, enabled, @"预览", @"icons_filled_play", @selector(ddp_vcPreview:), 1011);
    %orig(all);
}
%end

#pragma mark - Hook：CMessageMgr AddMsg（弹面板的真正入口）

// 仅处理自己发出的消息，命中抖音链接则弹面板并拦截（不调 %orig）；「直接发送」先置 gDDPDyTcEnable 一次性放行
%hook CMessageMgr
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap {
    do {
        if (!DDPConfig.shared.enabled || !wrap) { DDDLogOnce(@"addmsg-off", @"[Hook] AddMsg 跳过：开关=%d wrap=%@", DDPConfig.shared.enabled, wrap ? @"有" : @"nil"); break; }
        if (!DDPIsOutgoing(wrap)) { DDDLogOnce(@"addmsg-in", @"[Hook] AddMsg 跳过：非本人发出"); break; }
        unsigned int mt = wrap.m_uiMessageType;
        if (mt != 1 && mt != 49 && mt != 62) {
            // key 必须先算成变量再传：宏参数按逗号切分，直接把 stringWithFormat: 写进去会被切成两半
            NSString *mtKey = [NSString stringWithFormat:@"addmsg-mt-%u", mt];
            DDDLogOnce(mtKey, @"[Hook] AddMsg 跳过：消息类型 %u 不在 1/49/62（记录实际出现过的类型）", mt);
            break;
        }
        BOOL bypass = gDDPDyTcEnable; gDDPDyTcEnable = NO;       // 复位须在检测前
        if (bypass) { DDDLogOnce(@"addmsg-bypass", @"[Hook] AddMsg 放行：一次性 bypass（直接发送的重发）"); break; }
        NSString *content = wrap.m_nsContent;
        if (!DDPContainsDouyinLink(content)) content = wrap.m_nsTitle;
        if (!DDPContainsDouyinLink(content)) { DDDLogOnce(@"addmsg-nolink", @"[Hook] AddMsg 跳过：正文与 m_nsTitle 都不含 douyin.com"); break; }
        if (DDPIsDouyinLiveText(content)) { DDDLogOnce(@"addmsg-live", @"[Hook] AddMsg 跳过：直播文案"); break; }
        NSString *target = usr.length ? usr : wrap.m_nsToUsr;
        DDDLog(@"[Hook] AddMsg 命中抖音链接 → 弹面板（user=%@ 类型=%u）", target, mt);
        if ([DDPPanel showForContent:content user:target]) return;   // 命中后拦截
    } while (0);
    %orig;
}
%end

#pragma mark - 设置界面

@interface DDPDouyinParseSettingsViewController : UIViewController
@property (nonatomic, strong) id tableViewMgr;
@end
@implementation DDPDouyinParseSettingsViewController
- (void)ensureTableViewMgr { if (!_tableViewMgr) _tableViewMgr = [[%c(WCTableViewManager) alloc] initWithFrame:[UIScreen mainScreen].bounds style:UITableViewStyleInsetGrouped]; }
- (instancetype)init { if (self = [super init]) [self ensureTableViewMgr]; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD抖音解析";
    [self ensureTableViewMgr];
    [self buildTable];
    UITableView *tv = [_tableViewMgr getTableView];
    self.view.backgroundColor = tv.backgroundColor;
    tv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:tv];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *tv = [_tableViewMgr getTableView];
    tv.frame = CGRectMake(0, self.view.safeAreaInsets.top, self.view.bounds.size.width, self.view.bounds.size.height - self.view.safeAreaInsets.top);
}
- (void)buildTable {
    [_tableViewMgr clearAllSection];
    id sec = [%c(WCTableViewSectionManager) defaultSection];
    [sec setHeaderTitle:@"解析设置"];
    [sec addCell:[%c(WCTableViewCellManager) switchCellForSel:@selector(onEnabledSwitch:) target:self title:@"启用抖音解析" on:DDPConfig.shared.enabled]];
    [_tableViewMgr addSection:sec];
    id logSec = [%c(WCTableViewSectionManager) defaultSection];
    [logSec setHeaderTitle:@"日志"];
    [logSec addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onExportLog:) target:self title:@"导出日志"]];
    [logSec addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onClearLog:) target:self title:@"清空日志"]];
    [_tableViewMgr addSection:logSec];
    [_tableViewMgr reloadTableView];
}
- (void)onEnabledSwitch:(UISwitch *)sender { DDPConfig.shared.enabled = sender.isOn; }
- (void)onExportLog:(id)sender {
    NSString *log = DDDReadLog();
    if (!log.length) return;
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse_export.txt"];
    [log writeToFile:exportPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:exportPath]] applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        avc.popoverPresentationController.sourceView = self.view;
        avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
        avc.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:avc animated:YES completion:nil];
}
- (void)onClearLog:(id)sender { DDDClearLog(); }
@end

#pragma mark - 注册入口

%ctor {
    Class mgrCls = objc_getClass("WCPluginsMgr");
    if (mgrCls) {
        [[mgrCls sharedInstance] registerControllerWithTitle:@"DD抖音解析"
                                                     version:@"1.2.2"
                                                  controller:@"DDPDouyinParseSettingsViewController"];
    }
    // 预热：把 WebContent 进程冷启动的成本提前付掉（tweak 加载时就在后台建好 WebView 并跑一个空文档）。
    // 不预热的话第一次解析要冷启动，首轮等 2 秒必然不够 → 靠后面几轮硬撞，实测 58 秒。
    [DDPWebFetcher ddpWarmup];
}
