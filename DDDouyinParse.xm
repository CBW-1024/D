
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
#import <QuickLook/QuickLook.h>   // 系统图片预览 QLPreviewController（自带导航栏，无需自定义）
#import <unistd.h>     // usleep() —— 重载循环的等待节拍（PKC 原样用的是 sleep 死等，已改）

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
// 注：不要声明/使用 m_nsTitle —— 已核 8.0.79 头文件，CMessageWrap : NSObject 没有这个方法，
// 也没有任何分类补充它，访问会 unrecognized selector 崩溃。链接卡片的 URL 同样在 m_nsContent（XML）里。
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


// 系统预览：直接用 QLPreviewController（自带导航栏「完成」+ 分享/保存，无需自定义导航）。
// 自己当自己的 dataSource：dataSource 是 weak，self 由 present 体系强引用，不会提前释放。
@interface DDPQLViewer : QLPreviewController <QLPreviewControllerDataSource>
@property (nonatomic, copy) NSArray<NSURL *> *urls;
@end
@implementation DDPQLViewer
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return (NSInteger)self.urls.count;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.urls[index];   // NSURL 本就遵循 QLPreviewItem
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

// 正则只编译一次并缓存：原先每处都在函数里现编译，
// 其中 extractDurationFromHTML 会被轮询每 1.2s 调一次（最多 12 次），白白重复编译。
#define DDPRegex(var, pattern, opts) \
    static NSRegularExpression *var; static dispatch_once_t var##_once; \
    dispatch_once(&var##_once, ^{ var = [NSRegularExpression regularExpressionWithPattern:(pattern) options:(opts) error:nil]; })

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
// 开关就一个 BOOL，直接读写 NSUserDefaults 即可，不需要专门建个单例类来缓存
static BOOL DDPEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDDPEnabledKey];
}
static void DDPSetEnabled(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kDDPEnabledKey];
}

#pragma mark - 工具函数

// 后台队列（全局并发），各处下载/耗时操作统一用它
#define DDPBg() dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

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
    // 排除 < > ：链接卡片的 m_nsContent 是 XML（<url>https://...</url>），
    // 不排除的话会把 </url> 一并吃进 URL 里
    DDPRegex(re, @"https?://[^\\s\"'<>]+", 0);
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
    DDPRegex(reRatio, @"ratio=\\d+p", 0);
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

// 缓存路径 <md5>.<ext>（md5 用微信原生 CRUtils）
static NSString *DDPTempPathExt(NSString *url, NSString *ext) {
    NSString *md5 = [%c(CRUtils) md5:url];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", md5, ext]];
}
// 视频缓存路径固定 .mp4
static NSString *DDPTempPath(NSString *url) { return DDPTempPathExt(url, @"mp4"); }
// 取 URL 后缀作为临时文件扩展名（默认 jpg）
// 必须先截掉 ?/# 再取：图片直链形如 ...q80.webp?lk3s=xxx&x-expires=xxx，
// 直接 pathExtension 会把整个 query 当成扩展名，临时文件名变成 <md5>.webp?lk3s=... 又脏又长
static NSString *DDPImageExt(NSString *url) {
    // 不需要 url 的 nil 兜底：传 nil 时 pathExtension 也返回 nil，照样走下面的 @\"jpg\"
    NSString *s = url;
    NSRange t = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (t.location != NSNotFound) s = [s substringToIndex:t.location];
    NSString *ue = [s pathExtension].lowercaseString;
    NSString *r = ue.length ? ue : @"jpg";
    DDDLogOnce([@"ext-" stringByAppendingString:r], @"[工具] DDPImageExt：%@ → %@%@", url, r, ue.length ? @"" : @"（走默认 jpg 兜底）");
    return r;
}

// 主窗口统一用 DDPHostWindow()（见下方抓取区定义）。
// 原先这里还有个 DDPKeyWindow()，功能与之重复，已合并。

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

// 8.0.79 头文件确认 MicroMessengerAppDelegate 有 -(id)window，
// 且实测 %ctor 预热时它就已可用（日志恒为「挂窗=成功」），
// 故不再需要 connectedScenes 兜底——窗口获取收敛到这一行。
static UIWindow *DDPHostWindow(void) {
    return UIApplication.sharedApplication.delegate.window;
}

// 把 WebView 挂上主窗口。必须挂（虽然 hidden）：游离在窗口层级外的 WKWebView
// 其 WebContent 进程不被调度、JS 不跑，表现就是「时好时坏」——这是整个插件稳定性的关键。
static void DDPAttachWebView(WKWebView *wv) {
    UIWindow *win = DDPHostWindow();
    [win addSubview:wv];
    wv.frame = win.bounds;
    wv.hidden = YES;
}

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, assign) BOOL warmingUp;      // 预热导航期间跳过抠 HTML
@property (nonatomic, assign) int  pollTicks;      // 本轮 reload 内已轮询到第几拍
@property (nonatomic, assign) NSUInteger lastHTMLLen;   // 上一拍的 HTML 长度
@property (nonatomic, assign) int  sameLenTicks;   // 长度连续相同的拍数
@property (nonatomic, assign) BOOL reloadNow;      // 本轮已判定无望，通知重载循环提前 reload
@property (nonatomic, assign) double startAt;      // 本次抓取起点（CFAbsoluteTime），用于耗时日志
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger code, NSError *error);
+ (instancetype)sharedFetcher;
+ (void)ddpWarmup;                                              // 预热：建单例 + 挂窗 + 冷启动 WebContent
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger code, NSError *error))completion;
- (void)cleanupWebView;
- (void)ddpRetryLoop:(NSURLRequest *)req;                       // PKC block@0x3cae8
- (void)ddpPollHTML:(WKWebView *)webView;                       // 一轮 reload 内的多次采样（替代 PKC 的固定延时）
- (BOOL)ddpHandleHTML:(id)result error:(NSError *)error;        // PKC block@0x3ce34，返回是否命中
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
        DDPAttachWebView(_webView);
        DDDLog(@"WebView init：挂窗=%@ UA长度=%lu", _webView.window ? @"成功" : @"失败", (unsigned long)ua.length);
    }
    return self;
}

// 预热（实测必需）：PKC 的 WebView 是常驻单例、tweak 初始化时就建好并已跑过页面，
// 所以它的首轮（等 retries=2 秒）就能命中。我们原来是懒加载，第一次解析才 init，
// 冷启动 WebContent 进程 2 秒根本不够 → 首轮必 miss → 只能靠后面几轮硬撞，实测 58 秒。
// 这里把冷启动成本提前付掉：建单例 + 挂窗 + 跑一个空文档把 WebContent 进程拉起来。
+ (void)ddpWarmup {
    dispatch_async(dispatch_get_main_queue(), ^{
        DDPWebFetcher *f = [self sharedFetcher];     // init 里已经挂窗，这里不再补挂
        f.warmingUp = YES;                           // 预热导航不参与抠 HTML
        [f.webView loadHTMLString:@"<!DOCTYPE html><html><body>ddp</body></html>" baseURL:nil];
        DDDLog(@"预热：已发起空文档导航（挂窗=%@）", f.webView.window ? @"是" : @"否");
    });
}

// PKC -fetchHTMLFromURL:completion:@0x3c6d8
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger code, NSError *error))completion {
    self.completion = completion;
    self.hasCompleted = NO;
    self.startAt = CFAbsoluteTimeGetCurrent();
    // 预热导航可能还没回来（WebContent 进程启动慢），此时用户就开始解析了；
    // 若不清标志，这次真实导航的 didFinish 会被当成预热而跳过，白白吃掉首轮机会。
    self.warmingUp = NO;
    self.pollTicks = 0;         // 每轮状态一并重置，防止上一次解析的残留串到这次
    self.lastHTMLLen = 0;
    self.sameLenTicks = 0;
    self.reloadNow = NO;
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        NSError *err = [NSError errorWithDomain:@"InvalidURL" code:1001
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL string"}];
        DDDLog(@"fetchHTMLFromURL: URL 非法 → %@", url);
        if (completion) completion(nil, 0, err);
        return;
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];

    // 挂窗已在 init 完成，这里不再补挂——原先那三层补挂（init 判空 / 预热补挂 / 抓取补挂）
    // 日志里一次都没触发过。挂窗状态仍打出来，方便万一出问题时一眼看出。
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
        // 这里也偏离 PKC：PKC 是 sleep(retries+10) 死等，页面早就判完了也照样睡满。
        // 实测视频页轮1 拿到的是固定中间页（长度 7 拍恒为 50993，等也没用），
        // 于是这 11 秒纯属白睡。改成：可被「已命中」或「本轮已判定无望」提前唤醒。
        unsigned budget = (unsigned)(self.retries + 10);
        DDDLog(@"[轮%d] 等待本轮结果（上限 %us，可提前唤醒）", round, budget);
        double deadline = CFAbsoluteTimeGetCurrent() + budget;
        while (!self.hasCompleted && !self.reloadNow && CFAbsoluteTimeGetCurrent() < deadline) {
            usleep(200 * 1000);      // 0.2s 一跳
        }
        if (self.reloadNow) {
            self.reloadNow = NO;
            DDDLog(@"[轮%d] 本轮已判定无望 → 提前 reload（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
            continue;                                                    // 直接进下一轮
        }
        if (self.hasCompleted) {
            DDDLog(@"[轮%d] 已命中 → 退出（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
            break;
        }
        DDDLog(@"[轮%d] 等到上限仍未判定 → 再来一轮（累计%.1fs）", round, CFAbsoluteTimeGetCurrent() - self.startAt);
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

// 这里偏离 PKC：PKC 是「didFinish 后固定等 retries 秒，抠一次，不中就等下一轮 reload」。
// 实测问题：图集页是 SSR 直出，2 秒够；视频页是 SPA，轮1 只拿到 50993 字符（三标记全无）就判 miss，
// 白等 11 秒后轮2 才拿到 143233 字符命中 —— 视频总耗时 16.1s。
// 改成：didFinish 后按固定间隔反复抠，命中即回调，不再赌一个固定延时。
static const NSInteger DDPMaxPoll = 12;          // 最多轮询 12 次
static const double    DDMPollGap = 1.2;         // 每次间隔 1.2 秒（12 次 ≈ 14.4s 覆盖）

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // 预热导航：只用来把 WebContent 进程拉起来，不抠 HTML（否则空文档会走一遍 miss 分支）
    if (self.warmingUp) {
        self.warmingUp = NO;
        DDDLog(@"预热：空文档导航完成，WebContent 进程已就绪");
        return;
    }
    DDDLog(@"didFinish（累计%.1fs）→ 开始轮询抠 HTML（间隔 %.1fs，最多 %ld 次）",
           CFAbsoluteTimeGetCurrent() - self.startAt, DDMPollGap, (long)DDPMaxPoll);
    self.pollTicks = 0;
    [self ddpPollHTML:webView];
}

// 一轮 reload 内的多次采样：JS 还没渲染完就下一拍再来，命中即停
- (void)ddpPollHTML:(WKWebView *)webView {
    if (self.hasCompleted) return;
    self.pollTicks = self.pollTicks + 1;
    int tick = self.pollTicks;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DDMPollGap * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.hasCompleted) return;                       // 已被别的拍命中
        [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
            BOOL hit = [self ddpHandleHTML:result error:error];
            if (hit || self.hasCompleted) return;                        // 命中，收工
            if (self.sameLenTicks >= 1) {
                // 连续两拍长度一模一样 → 页面已经定型且没有我们要的标记，再等无意义
                DDDLog(@"[轮询] 第 %d 拍长度与上一拍相同（%lu）→ 本轮无望，提前 reload（累计%.1fs）",
                       tick, (unsigned long)self.lastHTMLLen, CFAbsoluteTimeGetCurrent() - self.startAt);
                self.reloadNow = YES;
                return;
            }
            if (tick < DDPMaxPoll) {
                DDDLog(@"[轮询] 第 %d 拍未命中，再来（累计%.1fs）", tick, CFAbsoluteTimeGetCurrent() - self.startAt);
                [self ddpPollHTML:webView];
            } else {
                DDDLog(@"[轮询] 第 %d 拍仍未命中，已达上限 → 交给重载循环（累计%.1fs）",
                       tick, CFAbsoluteTimeGetCurrent() - self.startAt);
            }
        }];
    });
}

// PKC 的 JS 回调 block@0x3ce34：还原转义 → 风控提示 → 打标记 → 命中才回调
// 返回是否命中，供 -ddpPollHTML: 决定要不要继续下一拍
- (BOOL)ddpHandleHTML:(id)result error:(NSError *)error {
    double el = CFAbsoluteTimeGetCurrent() - self.startAt;
    if (error) { DDDLog(@"抠HTML：JS 报错 %@（累计%.1fs）", error.localizedDescription, el); return NO; }
    if (![result isKindOfClass:[NSString class]]) { DDDLog(@"抠HTML：结果非字符串，跳过（累计%.1fs）", el); return NO; }
    NSMutableString *html = [NSMutableString string];
    [html setString:result];
    NSRange full = NSMakeRange(0, html.length);
    // 3 步清洗（原第 1 步 \u0026→& 经 4 次采样恒为 0 处，已删）
    NSUInteger len0 = html.length;
    NSUInteger n2 = [html replaceOccurrencesOfString:@"amp;" withString:@"" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    NSUInteger n3 = [html replaceOccurrencesOfString:@"u002F" withString:@"/" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    NSUInteger n4 = [html replaceOccurrencesOfString:@"\\" withString:@"" options:NSCaseInsensitiveSearch range:full];
    DDDLog(@"[清洗] 长度 %lu→%lu｜amp;→空 %lu 处｜u002F→/ %lu 处｜\\→空 %lu 处",
           (unsigned long)len0, (unsigned long)html.length,
           (unsigned long)n2, (unsigned long)n3, (unsigned long)n4);

    // 长度连续不变 = 页面不会再变。实测视频页首次返回的是固定中间页（长度 7 拍恒为 50993），
    // 再等也等不出内容，只有 reload 才拿得到真页面，所以用这个信号触发提前 reload。
    if (html.length == self.lastHTMLLen) self.sameLenTicks = self.sameLenTicks + 1;
    else self.sameLenTicks = 0;
    self.lastHTMLLen = html.length;

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
        DDDLog(@"抠HTML：三个标记全无 → 本拍 miss");
        return NO;
    }

    NSInteger code = gallery ? DDPCodeGallery : dur;
    if (self.completion && !self.hasCompleted) {
        self.hasCompleted = YES;
        DDDLog(@"抠HTML：命中 code=%ld → 回调（总耗时 %.1fs）", (long)code, CFAbsoluteTimeGetCurrent() - self.startAt);
        self.completion(html, code, nil);
    }
    self.retries = 0;   // 通知重载循环收工
    return YES;
}

// PKC -extractDurationFromHTML:@0xe2210：正则 "bit_rate":null,"duration":(\d+)，组1 / 1000
- (NSInteger)extractDurationFromHTML:(NSString *)html {
    // 不需要 html 判空和 re 判空：空串交给下面的 firstMatch 返回 nil 兜住，
    // re 是硬编码 pattern 不可能编译失败（真为 nil 时给 nil 发消息也返回 nil）
    DDPRegex(re, @"\"bit_rate\":null,\"duration\":(\\d+)", 0);
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
// 视频：正则抠 playwm 直链、过滤图集页的误命中、去水印
- (NSArray<NSString *> *)extractVideoLinksFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    DDPRegex(re, @"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+", NSRegularExpressionCaseInsensitive);
    NSUInteger raw = 0, skipped = 0;
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        raw++;
        NSString *u = [[html substringWithRange:m.range] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        // 图集页也会命中这个正则（video_id 里套了另一个 URL），必须过滤掉，否则图集会误判成视频
        if ([u containsString:@"video_id=https:"]) { skipped++; continue; }
        [result addObject:DDPRemoveWatermark(u)];   // 不去重：调用方只取 firstObject，重复无影响
    }
    DDDLog(@"[抽取·视频] 正则命中 %lu 个｜video_id 过滤掉 %lu 个｜最终 %lu 个",
           (unsigned long)raw, (unsigned long)skipped, (unsigned long)result.count);
    return [result copy];
}

// 图集：只取第一个 "images" 容器（页面会把同一份图集重复嵌入多次，实测首个容器即完整图集）
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *decoded = [html mutableCopy];
    NSUInteger len0 = decoded.length;
    // 只保留 &quot;→" ：原先的 \u002f / \/ / \" 三步经采样恒为 0 处，
    // 因为 ddpHandleHTML 的「\→空」已把所有反斜杠删光（采样数据自洽：316×5=1580=长度差）
    NSUInteger g4 = [decoded replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, decoded.length)];
    DDDLog(@"[抽取·图集] 解码 %lu→%lu｜&quot;→\" %lu 处",
           (unsigned long)len0, (unsigned long)decoded.length, (unsigned long)g4);

    // 取首个 "images" 容器。这条假设经两次采样验证：
    //   单图图集 → 1 处容器，抠出 1 张；7 图图集 → 3 处容器，首容器即含全部 7 张。
    // 原先这里还额外遍历全文统计出现次数（只为打日志），与下面这次查找重复，已删。
    NSRange cr = [decoded rangeOfString:@"\"images\"" options:NSCaseInsensitiveSearch];
    if (cr.location == NSNotFound) { DDDLog(@"[抽取·图集] 无 \"images\" 容器 → 空"); return @[]; }
    DDDLog(@"[抽取·图集] 首个 \"images\" @%lu", (unsigned long)cr.location);
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
        DDPRegex(reU, @"\"url_list\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\"", NSRegularExpressionCaseInsensitive);
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
                completion(DDPMediaTypeVideo, videos.firstObject, nil, nil);   // 调 nil block 本就是 no-op，所有调用方都必传 block，不再判空
                return;
            }
            NSArray *images = [self extractGalleryImagesFromHTML:html];
            if (images.count) {
                DDDLog(@"parseDouyinURL → 命中图集 数=%lu code=%ld", (unsigned long)images.count, (long)code);
                completion(DDPMediaTypeImage, nil, images, nil);   // 同上，不再判空
                return;
            }
            DDDLog(@"parseDouyinURL → 有 HTML 但抠不到直链 code=%ld", (long)code);
        } else {
            DDDLog(@"parseDouyinURL → 没拿到 HTML code=%ld err=%@", (long)code, err);
        }
        completion(DDPMediaTypeUnknown, nil, nil,
                   err ?: [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);   // err 兜底必须留（失败路径 err 可能本就 nil）
    }];
}
// 同步下载（信号量阻塞）
- (NSData *)downloadVideoFromURL:(NSString *)url {
    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";
    [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
    // 原先带 Range: bytes=0- —— 它等价于「从第 0 字节到末尾」即全量，并不产生任何断点续传效果，
    // 只让 CDN 统一回 206 而不是 200，已删。
    [request setValue:url forHTTPHeaderField:@"Referer"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    // 头文件已确认 CUtility.GetMMUserAgent 存在，且实测稳定返回 171 字符，去掉写死的 UA 兜底
    [request setValue:[%c(CUtility) GetMMUserAgent] forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    // 不设 timeoutIntervalForRequest：默认就是 60s
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSData *result = nil; __block NSInteger dcode = -1; __block NSString *derr = nil;
    double t0 = CFAbsoluteTimeGetCurrent();
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        // https 请求的响应必然是 NSHTTPURLResponse，不需要 isKindOfClass 判断
        dcode = (NSInteger)((NSHTTPURLResponse *)resp).statusCode;
        derr = err.localizedDescription;
        result = data;                       // 出错时 data 本身也是 nil，不需要再判 err
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
    UIViewController *vc = DDPHostWindow().rootViewController;
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
+ (void)ddpParse:(NSString *)url then:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs))then;
+ (void)ddpFetchVideo:(NSString *)videoURL forURL:(NSString *)url then:(void (^)(NSString *path))then;
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
+ (NSArray<NSString *> *)ddpFetchImages:(NSArray<NSString *> *)urls;   // 「存相册」与「预览」共用的串行下载
+ (NSString *)ddpFetchToPath:(NSString *)path fromURL:(NSString *)url;  // 单个下载+落盘，失败返回 nil
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)shareURL user:(NSString *)user finish:(void(^)(void))finish;
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion;
+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc;
@end

@implementation DDPPanel

+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    NSString *url = DDPExtractURL(content);
    if (!url.length) return NO;
    UIViewController *top = DDPHostWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    WCActionSheet *sheet = [[%c(WCActionSheet) alloc] initWithTitle:@"抖音解析" cancelButtonTitle:@"取消"];
    [sheet addButtonWithTitle:@"直接发送" eventAction:^{ [DDPPanel handleDirectSend:content user:user]; }];
    [sheet addButtonWithTitle:@"解析发送" eventAction:^{ [DDPPanel handleParseSend:url user:user]; }];
    [sheet addButtonWithTitle:@"解析预览" eventAction:^{ [DDPPanel handleParsePreview:url fromVC:top]; }];
    [sheet addButtonWithTitle:@"解析链接" eventAction:^{ [DDPPanel handleParseLink:url user:user]; }];
    [sheet addButtonWithTitle:@"保存相册" eventAction:^{ [DDPPanel handleSaveAlbum:url]; }];
    [sheet showInView:DDPHostWindow()];
    return YES;
}

+ (void)handleDirectSend:(NSString *)content user:(NSString *)user {
    gDDPDyTcEnable = YES;
    DDPSendTextMsg(content, user);
}

// 四个解析入口（发送/预览/链接/存相册）共用的样板：
// loading → 解析 → 失败统一提示，成功才回调 then
+ (void)ddpParse:(NSString *)url then:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs))then {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) { DDDLog(@"[面板] 解析失败 err=%@", err); DDPShowError(@"解析失败"); return; }
        DDDLog(@"[面板] 解析成功 type=%ld", (long)type);
        then(type, videoURL, imageURLs);   // 调 nil block 本就是 no-op，四个入口都必传 block，不再判空
    }];
}

+ (void)handleParseSend:(NSString *)url user:(NSString *)user {
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) [self sendVideoForURL:videoURL shareURL:url user:user finish:finish];
        else [self sendImagesForURLs:imageURLs user:user finish:finish];
    }];
}

// 下载视频直链并发到聊天
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)url user:(NSString *)user finish:(void(^)(void))finish {
    NSString *path = DDPTempPath(url);
    dispatch_async(DDPBg(), ^{
        if (![DDPPanel ddpFetchToPath:path fromURL:videoURL]) { DDPShowError(@"解析失败"); return; }
        if (finish) finish();
        [DDPPanel sendVideoAtPath:path toUser:user];
    });
}

// 下载并落盘到指定路径，失败返回 nil。视频与图片共用——原先这 5 处各抄了一遍
// 「downloadVideoFromURL → 删旧文件 → writeToFile」，现统一。
+ (NSString *)ddpFetchToPath:(NSString *)path fromURL:(NSString *)url {
    NSData *data = [[DDPEngine shared] downloadVideoFromURL:url];
    if (!data.length) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
    return [data writeToFile:path atomically:YES] ? path : nil;
}

// 串行下载一组图片直链到本地缓存，返回成功落盘的路径。
// 原先 downloadAndSaveImages: 与 downloadImagesLocally: 各抄了一遍这段循环，现合并。
+ (NSArray<NSString *> *)ddpFetchImages:(NSArray<NSString *> *)urls {
    double t0 = CFAbsoluteTimeGetCurrent();
    DDDLog(@"[下载·图集] 开始串行下载 %lu 张", (unsigned long)urls.count);
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *imgURL in urls) {
        NSString *p = [self ddpFetchToPath:DDPTempPathExt(imgURL, DDPImageExt(imgURL)) fromURL:imgURL];
        if (p) [out addObject:p];
    }
    DDDLog(@"[下载·图集] %lu 张串行下载完成 成功 %lu 张 总耗时 %.2fs",
           (unsigned long)urls.count, (unsigned long)out.count, CFAbsoluteTimeGetCurrent() - t0);
    return out;
}

+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish {
    dispatch_async(DDPBg(), ^{
        NSArray *paths = [self ddpFetchImages:urls];
        NSInteger total = paths.count;
        if (total == 0) {
            DDDLog(@"[面板] 图集全部下载失败，无图可存");
            if (finish) dispatch_async(dispatch_get_main_queue(), finish);
            return;
        }
        __block NSInteger done = 0, failed = 0;
        dispatch_queue_t q = dispatch_queue_create("ddp.save", DISPATCH_QUEUE_SERIAL);
        for (NSString *path in paths) {
            [DDPPanel saveImageToAlbumAtPath:path completion:^(BOOL success) {
                dispatch_async(q, ^{
                    done++; if (!success) failed++;
                    if (done < total) return;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        DDDLog(@"[面板] 存相册完成 %ld/%ld 失败 %ld", (long)done, (long)total, (long)failed);
                        if (failed == 0) DDPShowDone(@"保存成功");
                        else if (failed < total) DDPShowDone(@"部分保存成功");
                        else DDPShowError(@"保存失败");
                    });
                });
            }];
        }
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

        // 头文件已确认 CaptureVideoInfo 在 8.0.79 存在，init 不会返回 nil
        id info = [[%c(CaptureVideoInfo) alloc] init];

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
        // 8.0.79 头文件已确认 BaseMsgContentLogicController 存在且 init 不返回 nil，不保留 CMessageMgr 旧路径兜底
        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        [ctrl AddVideoMsg:from ToUsr:chatName VideoInfo:info];
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
    dispatch_async(DDPBg(), ^{
        BOOL anySent = NO;
        for (NSString *imgURL in urls) {
            @autoreleasepool {
                NSString *p = [self ddpFetchToPath:DDPTempPathExt(imgURL, DDPImageExt(imgURL)) fromURL:imgURL];
                if (!p) continue;
                [DDPPanel sendImageAtPath:p toUser:user];    // 下一张发一张，保持渐进
                anySent = YES;
            }
        }
        if (!anySent) DDPShowError(@"解析失败");
        else if (finish) finish();
    });
}

// 视频分支共用：下载到本地缓存，成功后在「后台线程」回调 path（调用方自己决定要不要切主线程）；
// 下载失败统一提示。原先 handleParsePreview / handleSaveAlbum 各写了一遍这段。
+ (void)ddpFetchVideo:(NSString *)videoURL forURL:(NSString *)url then:(void (^)(NSString *path))then {
    NSString *path = DDPTempPath(url);
    dispatch_async(DDPBg(), ^{
        NSString *p = [self ddpFetchToPath:path fromURL:videoURL];
        if (!p) { DDPShowError(@"解析失败"); return; }
        if (then) then(p);
    });
}

+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            [self ddpFetchVideo:videoURL forURL:url then:^(NSString *p) {
                dispatch_async(dispatch_get_main_queue(), ^{ [DDPPanel playVideoAtPath:p fromVC:vc]; finish(); });
            }];
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
    pvc.entersFullScreenWhenPlaybackBegins = NO;   // 显式关闭自动全屏，保住 pageSheet 半模态
    pvc.modalPresentationStyle = UIModalPresentationPageSheet;   // 半模态卡片：顶部/底部露出微信，与图片预览一致
    [vc presentViewController:pvc animated:YES completion:^{ [pvc.player play]; }];
}

// 下载图片直链到本地缓存（供预览，不存相册；复用 MD5 缓存）
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion {
    dispatch_async(DDPBg(), ^{
        NSArray *out = [self ddpFetchImages:urls];       // 与「存相册」共用同一段串行下载
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(out); });
    });
}

+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc {
    DDPQLViewer *qlc = [[DDPQLViewer alloc] init];
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *p in paths) [urls addObject:[NSURL fileURLWithPath:p]];
    qlc.urls = urls;
    qlc.dataSource = qlc;            // 自己当自己的数据源（weak，self 由 present 体系强引用）
    qlc.currentPreviewItemIndex = 0;
    qlc.modalPresentationStyle = UIModalPresentationPageSheet;   // 半模态卡片：顶部/底部露出微信，不全屏盖死导航栏
    [vc presentViewController:qlc animated:YES completion:nil];
}

+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDDLog(@"[面板] handleParseLink 入口 url=%@ user=%@", url, user.length ? user : @"(空→取当前会话)");
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DDPHideLoading();
            NSString *link = (type == DDPMediaTypeVideo) ? videoURL : [imageURLs componentsJoinedByString:@"\n"];
            NSString *target = user.length ? user : DDPCurrentChatName();
            if (link.length && target.length) DDPSendTextMsg(link, target);
        });
    }];
}

+ (void)handleSaveAlbum:(NSString *)url {
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            [self ddpFetchVideo:videoURL forURL:url then:^(NSString *p) {
                [DDPPanel saveVideoToAlbumAtPath:p completion:^(BOOL success) {
                    if (success) DDPShowDone(@"保存成功"); else DDPShowError(@"保存失败");
                }];
            }];
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

// 从消息对象取判定文本。链接卡片（类型 49）的 URL 也在 m_nsContent 里（XML appmsg 的 <url>），
// 所以统一取 m_nsContent 即可——原先按类型分流到 m_nsTitle，但该方法在 8.0.79 的 CMessageWrap 上不存在，
// 长按非文本消息会直接 unrecognized selector 崩溃。
static NSString *ddp_wrapContent(CMessageWrap *wrap) {
    return wrap.m_nsContent;
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
    // 头文件已确认 MMMenuItem / initWithTitle:svgName:target:action: 在 8.0.79 存在，
    // 不再需要「创建失败」的兜底（原先那句 if (!item) return original; 永不可能命中）
    MMMenuItem *item = [[%c(MMMenuItem) alloc] initWithTitle:title svgName:svgName target:cell action:action];
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
    BOOL enabled = DDPEnabled()
                   && DDPContainsDouyinLink(content) && !DDPIsDouyinLiveText(content);
    DDDLogOnce((enabled ? @"menu-Y" : @"menu-N"),
               @"[Hook] setMenuItems：注入=%d（开关=%d 含抖音=%d 直播=%d）原始项数=%lu",
               enabled, DDPEnabled(), content ? DDPContainsDouyinLink(content) : 0,
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
        if (!DDPEnabled() || !wrap) { DDDLogOnce(@"addmsg-off", @"[Hook] AddMsg 跳过：开关=%d wrap=%@", DDPEnabled(), wrap ? @"有" : @"nil"); break; }
        if (!DDPIsOutgoing(wrap)) { DDDLogOnce(@"addmsg-in", @"[Hook] AddMsg 跳过：非本人发出"); break; }
        unsigned int mt = wrap.m_uiMessageType;
        if (mt != 1) {
            DDDLogOnce(@"addmsg-nottext", @"[Hook] AddMsg 跳过：消息类型 %u 不是文本(1)", mt);
            break;
        }
        BOOL bypass = gDDPDyTcEnable; gDDPDyTcEnable = NO;       // 复位须在检测前
        if (bypass) { DDDLogOnce(@"addmsg-bypass", @"[Hook] AddMsg 放行：一次性 bypass（直接发送的重发）"); break; }
        NSString *content = wrap.m_nsContent;
        if (!DDPContainsDouyinLink(content)) { DDDLogOnce(@"addmsg-nolink", @"[Hook] AddMsg 跳过：m_nsContent 不含 douyin.com"); break; }
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
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD抖音解析";
    [self ensureTableViewMgr];   // viewDidLoad 无论微信用 init 还是 initWithNibName: 都必跑，单一保底即可；init 里再调是重复且可能永不触发
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
    [sec addCell:[%c(WCTableViewCellManager) switchCellForSel:@selector(onEnabledSwitch:) target:self title:@"启用抖音解析" on:DDPEnabled()]];
    [_tableViewMgr addSection:sec];
    id logSec = [%c(WCTableViewSectionManager) defaultSection];
    [logSec setHeaderTitle:@"日志"];
    [logSec addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onExportLog:) target:self title:@"导出日志"]];
    [logSec addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onClearLog:) target:self title:@"清空日志"]];
    [_tableViewMgr addSection:logSec];
    [_tableViewMgr reloadTableView];
}
- (void)onEnabledSwitch:(UISwitch *)sender { DDPSetEnabled(sender.isOn); }
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
                                                     version:@"1.3.13"
                                                  controller:@"DDPDouyinParseSettingsViewController"];
    }
    // 预热：把 WebContent 进程冷启动的成本提前付掉（tweak 加载时就在后台建好 WebView 并跑一个空文档）。
    // 不预热的话第一次解析要冷启动，首轮等 2 秒必然不够 → 靠后面几轮硬撞，实测 58 秒。
    [DDPWebFetcher ddpWarmup];
}
