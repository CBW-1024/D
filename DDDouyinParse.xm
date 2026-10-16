
// DDDouyinParse —— 微信内抖音分享链接解析插件（Theos / Logos 单文件）
//
// 管线：识别抖音链接 → 离屏 WKWebView 抓官方分享页 → 提取去水印直链（视频 / 图集）→ 面板「发送 / 预览 / 存相册」
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

static BOOL DDPContainsDouyinLink(NSString *text) { return [text containsString:@"douyin.com"]; }

// 排除直播：抖音直播分享文案含「正在直播」
static BOOL DDPIsDouyinLiveText(NSString *text) { return [text containsString:@"正在直播"]; }

static BOOL DDPIsOutgoing(CMessageWrap *wrap) { return [%c(CMessageWrap) isSenderFromMsgWrap:wrap]; }

// 抽取文本中的第一个抖音 http(s) URL（只认 douyin.com，避免文案里其他链接抢先被抠走）
static NSString *DDPExtractURL(NSString *text) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s\"']+" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *u = [text substringWithRange:m.range];
        if ([u containsString:@"douyin.com"]) return u;
    }
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
    return ue.length ? ue : @"jpg";
}

// 主窗口：单主窗口 app，直接取 AppDelegate.window，不遍历场景
static inline UIWindow *DDPKeyWindow(void) { return UIApplication.sharedApplication.delegate.window; }

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

#pragma mark - 抓取（离屏 WKWebView，轮询 playwm）

static const NSInteger DDPCodeGallery = 0x4161;   // 图集类型标记

// 抓取用 UA：抖音按 UA 分流，视频与图集诉求冲突，必须按类型分别设置：
// ① 移动版 Safari（默认）：视频短链 302 到 iesdouyin.com/share/video/<id> 分享页，内嵌 playwm，视频解析可用；
//    但移动 UA 下 www.douyin.com/note/<id> 会给壳页，图集取不到数据。
// ② 桌面版 Safari：www.douyin.com/note/<id> 给 900KB 真页（含图集数据）；但桌面 UA 下视频短链 302 到
//    www.douyin.com/video/<id> 的 SPA 壳页（数据走 XHR，outerHTML 无 playwm），视频解析失败。
// ③ 微信 UA(原 GetMMUserAgent) 最差：被当 App 内嵌 webview，图集/视频都发壳页。
// 统一策略：全程只用移动版 Safari UA（视频/图集/下载都一致）。
static NSString *const DDPMobileUA  = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1";

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, assign) NSTimeInterval fetchStart;
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger errCode);
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion;
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code;
+ (instancetype)sharedFetcher;
@end

@implementation DDPWebFetcher {
    WKWebView *_webView;
}
+ (instancetype)sharedFetcher {
    static DDPWebFetcher *i; static dispatch_once_t once; dispatch_once(&once, ^{ i = [[self alloc] init]; }); return i;
}
- (instancetype)init {
    if (self = [super init]) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;   // 替代已废弃的 javaScriptEnabled
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        _webView.customUserAgent = DDPMobileUA;   // 全程移动 UA
        _webView.navigationDelegate = self;
        _webView.hidden = YES;   // WKWebView 独立进程渲染，无需挂窗口；hidden 防误显示
    }
    return self;
}
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion {
    self.completion = completion;     self.hasCompleted = NO;
    // 全程移动 UA（已统一，无需按类型切换）
    self.webView.customUserAgent = DDPMobileUA;
    NSURL *nsurl = [NSURL URLWithString:url];
    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    self.fetchStart = CFAbsoluteTimeGetCurrent();
    dispatch_async(dispatch_get_main_queue(), ^{ [self.webView loadRequest:request]; });
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // v.douyin.com 短链会 302 到 iesdouyin.com/share/<type>/<id>，该落地页无图集/直链数据；
    // 提取 type+id 改加载规范 www.douyin.com/<type>/<id>（已非 share 路径，不会循环重导）
    NSString *u = webView.URL.absoluteString ?: @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/share/(note|video)/(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:u options:0 range:NSMakeRange(0, u.length)];
    DDDLog(@"[fetch] didFinish url=%@ share匹配=%@", u, m ? @"YES" : @"NO");
    if (m) {
        NSString *type = [u substringWithRange:[m rangeAtIndex:1]];
        NSString *awemeId = [u substringWithRange:[m rangeAtIndex:2]];
        NSString *canon = [NSString stringWithFormat:@"https://www.douyin.com/%@/%@", type, awemeId];
        // 图集：移动 UA 下统一跳规范地址（不再切桌面 UA）。若仍拿壳页，下一步考虑不跳、留在 iesdouyin.com/share/note
        if ([type caseInsensitiveCompare:@"note"] == NSOrderedSame) {
            self.fetchStart = CFAbsoluteTimeGetCurrent();
            DDDLog(@"[fetch] note → 跳规范 %@", canon);
            [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:canon]]];
            return;
        }
        // 视频：分享页自带播放器，JS 执行后 playwm 会进 DOM，留在当前页轮询即可
        // （实测 attempt=0 即命中；跳到裸规范地址反而会丢分享授权参数）
    }
    [self pollHTML:webView attempt:0];
}
// 抖音 H5 懒加载：首轮 outerHTML 常无 playwm，故每 0.5s 轮询，命中即收，最多 5s
- (void)pollHTML:(WKWebView *)webView attempt:(NSUInteger)attempt {
    if (self.hasCompleted) return;
    __weak typeof(self) wself = self;
    [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
        __strong typeof(wself) strong = wself;
        if (!strong) return;
        if (error) { [strong ddFinishWithHTML:nil code:-2]; return; }
        NSString *html = result ? [NSString stringWithFormat:@"%@", result] : @"";
        NSTimeInterval waited = CFAbsoluteTimeGetCurrent() - strong.fetchStart;
        if ([html containsString:@"playwm"] ||
            [html containsString:@"urlList"] ||
            [html containsString:@"\"images\""]) {
            DDDLog(@"[fetch] 轮询命中标记 len=%lu waited=%.1f", (unsigned long)html.length, waited);
            [strong handleRenderedHTML:html];
            return;
        }
        if (waited > 5.0) {
            DDDLog(@"[fetch] 超时收尾 len=%lu（无 playwm/swiper 标记）", (unsigned long)html.length);
            [strong handleRenderedHTML:html]; return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [strong pollHTML:webView attempt:attempt + 1];
        });
    }];
}
// 网络失败 / 渲染进程崩溃：直接收尾，避免永久挂起
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self ddFinishWithHTML:nil code:-3];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self ddFinishWithHTML:nil code:-3];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self ddFinishWithHTML:nil code:-4];
}
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code {
    if (self.hasCompleted) return;
    self.hasCompleted = YES;
    if (self.completion) self.completion(html, code);
}
- (void)handleRenderedHTML:(NSString *)html {
    if (!html.length) { [self ddFinishWithHTML:nil code:-2]; return; }
    // 还原转义（否则 https:\u002F 会被弄乱，playwm 正则匹配不上）
    NSMutableString *clean = [NSMutableString stringWithString:html];
    NSRange full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\u0026" withString:@"&" options:NSLiteralSearch range:full];
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"amp;" withString:@"" options:NSLiteralSearch range:full];
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\u002F" withString:@"/" options:NSLiteralSearch range:full];
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\/" withString:@"/" options:NSLiteralSearch range:full];
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\u001D" withString:@"" options:NSLiteralSearch range:full];

    NSInteger code = ([clean containsString:@"urlList"] || [clean containsString:@"\"images\""]) ? DDPCodeGallery : 0;
    // 不重试：命中与否都把 HTML 交出去，由解析层（直链正则 / 图集容器）做最终判定
    [self ddFinishWithHTML:clean code:code];
}
- (WKWebView *)webView { return _webView; }
@end

#pragma mark - 解析引擎

typedef NS_ENUM(NSInteger, DDPMediaType) {
    DDPMediaTypeUnknown = -1,
    DDPMediaTypeVideo   = 0,
    DDPMediaTypeImage   = 1,
};

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
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *u = [[html substringWithRange:m.range] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        if ([u containsString:@"video_id=https:"]) continue;
        NSString *clean = DDPRemoveWatermark(u);
        if (![result containsObject:clean]) [result addObject:clean];
    }
    DDDLog(@"extractVideoLinks: 候选数=%lu", (unsigned long)result.count);
    return [result copy];
}

// 图集：抖音当前结构 "images":[{ "width":.., "uri":"..", "urlList":["https://...", ...] }]
// 关键：字段是驼峰 urlList（非旧版 url_list）；整页已无 gallery-container / swiper 等 DOM 标记，PKC 老正则失效。
// 只取第一个 images 容器（页面会把同一份图集重复嵌入，首个即完整图集），每个对象取 urlList 首个 URL。
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *decoded = [html mutableCopy];
    [decoded replaceOccurrencesOfString:@"\\u002f" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    [decoded replaceOccurrencesOfString:@"\\/" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    [decoded replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, decoded.length)];

    // 主路径：取第一个 "images":[ 容器，内部每个 "urlList":[ 取首个 https URL
    NSRange cr = [decoded rangeOfString:@"\"images\"" options:NSCaseInsensitiveSearch];
    if (cr.location != NSNotFound) {
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
                regularExpressionWithPattern:@"\"urlList\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\""
                options:NSRegularExpressionCaseInsensitive error:nil];
            for (NSTextCheckingResult *m in [reU matchesInString:seg options:0 range:NSMakeRange(0, seg.length)]) {
                NSString *src = [[seg substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
                if (src.length && ![result containsObject:src]) [result addObject:src];
            }
        }
    }

    // 兜底：urlList 改名/降级时，回退蛇形 url_list（同族、低风险，仍限定在 images 容器内）
    if (result.count == 0) {
        NSRange cr2 = [decoded rangeOfString:@"\"url_list\"" options:NSCaseInsensitiveSearch];
        if (cr2.location != NSNotFound) {
            NSRange br2 = [decoded rangeOfString:@":[" options:0 range:NSMakeRange(cr2.location, MIN(decoded.length - cr2.location, 64))];
            NSInteger a2 = (br2.location != NSNotFound) ? ((NSInteger)br2.location + (NSInteger)br2.length - 1) : -1;
            NSInteger e2 = -1, d2 = 0;
            for (NSInteger i = a2; i >= 0 && i < (NSInteger)decoded.length; i++) {
                unichar ch = [decoded characterAtIndex:i];
                if (ch == '[') d2++;
                else if (ch == ']') { d2--; if (d2 == 0) { e2 = i; break; } }
            }
            if (e2 > a2) {
                NSString *seg = [decoded substringWithRange:NSMakeRange(a2, e2 - a2 + 1)];
                NSRegularExpression *reU = [NSRegularExpression
                    regularExpressionWithPattern:@"\"url_list\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\""
                    options:NSRegularExpressionCaseInsensitive error:nil];
                for (NSTextCheckingResult *m in [reU matchesInString:seg options:0 range:NSMakeRange(0, seg.length)]) {
                    NSString *src = [[seg substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
                    if (src.length && ![result containsObject:src]) [result addObject:src];
                }
            }
        }
    }
    DDDLog(@"[gallery] urlList命中 %lu 张", (unsigned long)result.count);
    return [result copy];
}
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSInteger errCode) {
        DDDLog(@"[parse] 收到 HTML errCode=%ld len=%lu url=%@", (long)errCode, (unsigned long)html.length, url);
        if (!html.length) { if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-2 userInfo:nil]); return; }
        NSArray *videos = [self extractVideoLinksFromHTML:html];
        if (videos.count) { if (completion) completion(DDPMediaTypeVideo, videos.firstObject, nil, nil); return; }
        NSArray *images = [self extractGalleryImagesFromHTML:html];
        if (images.count) { if (completion) completion(DDPMediaTypeImage, nil, images, nil); return; }
        if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
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
    [request setValue:DDPMobileUA forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data) result = data;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
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
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || type == DDPMediaTypeUnknown) { DDPShowError(@"解析失败"); return; }
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
        if ([it.userInfo isKindOfClass:[NSString class]] && [(NSString *)it.userInfo isEqualToString:token]) return original;
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
        if (!DDPConfig.shared.enabled || !wrap) break;
        if (!DDPIsOutgoing(wrap)) break;                       // 仅自己发出的消息
        unsigned int mt = wrap.m_uiMessageType;
        if (mt != 1 && mt != 49 && mt != 62) break;            // 文本 / 链接卡片 / 其他
        BOOL bypass = gDDPDyTcEnable; gDDPDyTcEnable = NO;       // 复位须在检测前
        if (bypass) break;
        NSString *content = wrap.m_nsContent;
        if (!DDPContainsDouyinLink(content)) content = wrap.m_nsTitle;
        if (!DDPContainsDouyinLink(content)) break;
        if (DDPIsDouyinLiveText(content)) break;
        NSString *target = usr.length ? usr : wrap.m_nsToUsr;
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
                                                     version:@"1.0.0"
                                                  controller:@"DDPDouyinParseSettingsViewController"];
    }
}
