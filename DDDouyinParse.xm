// DDDouyinParse —— 微信内抖音分享链接解析插件（v1.0.0）
// 识别抖音分享链接，抓取分享页提取无水印视频 / 图集直链，支持发送 / 预览 / 存相册。
//
// 模块：配置 / 工具 / 抓取 / 解析引擎 / 面板与服务 / Hook / 设置 / 注册

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVFoundation/AVFoundation.h>
#import <QuickLook/QuickLook.h>
#import <unistd.h> // usleep

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
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

@interface MMMenuController : NSObject
- (void)setMenuItems:(id)items;
@end

// 用系统 QLPreviewController 预览（自带导航栏与分享/保存）
@interface DDPQLViewer : QLPreviewController <QLPreviewControllerDataSource>
@property (nonatomic, copy) NSArray<NSURL *> *urls;
@end
@implementation DDPQLViewer
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return (NSInteger)self.urls.count;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.urls[index];
}
@end

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

#pragma mark - 配置

static NSString * const kDDPEnabledKey = @"DDDouyinParseEnabled";

static BOOL DDPEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDDPEnabledKey];
}
static void DDPSetEnabled(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kDDPEnabledKey];
}

#pragma mark - 工具函数

// 后台并发队列
static dispatch_queue_t DDPBg(void) {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

// 编译并缓存正则
static NSRegularExpression *DDPRegex(NSString *pattern, NSRegularExpressionOptions opts) {
    static NSMutableDictionary<NSString *, NSRegularExpression *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%ld|%@", (long)opts, pattern];
    NSRegularExpression *re = nil;
    @synchronized(cache) {
        re = cache[key];
        if (!re) {
            re = [NSRegularExpression regularExpressionWithPattern:pattern options:opts error:nil];
            if (re) cache[key] = re;
        }
    }
    return re;
}

static BOOL DDPIsDouyinLiveText(NSString *text) {
    return [text containsString:@"正在直播"];
}

static BOOL DDPIsOutgoing(CMessageWrap *wrap) { return [%c(CMessageWrap) isSenderFromMsgWrap:wrap]; }

// 抽取第一个抖音链接
static NSString *DDPExtractURL(NSString *text) {
    NSRegularExpression *re = DDPRegex(@"https?://[^\\s\"'<>]+", 0);
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *u = [text substringWithRange:m.range];
        if ([u containsString:@"douyin.com"]) return u;
    }
    return nil;
}

// 去水印：playwm→play，固定 720p
static NSString *DDPRemoveWatermark(NSString *url) {
    NSString *clean = [url stringByReplacingOccurrencesOfString:@"/playwm/" withString:@"/play/"];
    NSRegularExpression *reRatio = DDPRegex(@"ratio=\\d+p", 0);
    clean = [reRatio stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@"ratio=720p"];
    if ([clean rangeOfString:@"ratio="].location == NSNotFound) {
        NSString *sep = ([clean rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
        clean = [clean stringByAppendingFormat:@"%@ratio=720p", sep];
    }
    return clean;
}

// 以 URL 的 md5 作临时文件名（复用微信 CRUtils）
static NSString *DDPTempPathExt(NSString *url, NSString *ext) {
    NSString *md5 = [%c(CRUtils) md5:url];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", md5, ext]];
}
static NSString *DDPTempPath(NSString *url) { return DDPTempPathExt(url, @"mp4"); }

// URL 后缀作扩展名（默认 jpg，先截断 ?/#）
static NSString *DDPImageExt(NSString *url) {
    NSString *s = url;
    NSRange t = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (t.location != NSNotFound) s = [s substringToIndex:t.location];
    NSString *ue = [s pathExtension].lowercaseString;
    return ue.length ? ue : @"jpg";
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

#pragma mark - 抓取

typedef NS_ENUM(NSInteger, DDPMediaType) {
    DDPMediaTypeUnknown = -1,
    DDPMediaTypeVideo   = 0,
    DDPMediaTypeImage   = 1,
};
// WebView 必须挂主窗口，否则后台进程不调度、解析时好时坏
static UIWindow *DDPHostWindow(void) {
    return UIApplication.sharedApplication.delegate.window;
}

// 挂载 WebView 到主窗口（hidden）
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
@property (nonatomic, assign) int pollTicks;          // 本轮 reload 内已轮询到第几拍
@property (nonatomic, assign) NSUInteger lastHTMLLen; // 上一拍的 HTML 长度
@property (nonatomic, assign) int sameLenTicks;       // 长度连续相同的拍数
@property (nonatomic, assign) BOOL reloadNow;         // 本轮已判定无望，通知重载循环提前 reload
@property (nonatomic, copy) void (^completion)(NSString *html, NSError *error);
+ (instancetype)sharedFetcher;
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSError *error))completion;
- (void)cleanupWebView;
- (void)ddpRetryLoop:(NSURLRequest *)req;
- (void)ddpPollHTML:(WKWebView *)webView;
- (BOOL)ddpHandleHTML:(id)result error:(NSError *)error;
@end

@implementation DDPWebFetcher
+ (instancetype)sharedFetcher {
    static DDPWebFetcher *i;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ i = [[self alloc] init]; });
    return i;
}

- (instancetype)init {
    if (self = [super init]) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        _webView.customUserAgent = [%c(CUtility) GetMMUserAgent];
        _webView.navigationDelegate = self;
        DDPAttachWebView(_webView);
    }
    return self;
}

- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSError *error))completion {
    self.completion = completion;
    self.hasCompleted = NO;
    self.pollTicks = 0;
    self.lastHTMLLen = 0;
    self.sameLenTicks = 0;
    self.reloadNow = NO;
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        NSError *err = [NSError errorWithDomain:@"InvalidURL" code:1001
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL string"}];
        if (completion) completion(nil, err);
        return;
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:u cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    _webView.hidden = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [self ddpRetryLoop:req]; });
}

// 多次 reload 逼出真实内容，最多 3 轮
- (void)ddpRetryLoop:(NSURLRequest *)req {
    self.retries = 1;
    while (self.retries < 3) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView loadRequest:req];
            self.retries = self.retries + 1;
        });
        unsigned budget = (unsigned)(self.retries + 5);
        double deadline = CFAbsoluteTimeGetCurrent() + budget;
        while (!self.hasCompleted && !self.reloadNow && CFAbsoluteTimeGetCurrent() < deadline) {
            usleep(200 * 1000);
        }
        if (self.reloadNow) {
            self.reloadNow = NO;
            continue;
        }
        if (self.hasCompleted) break;
    }
    if (self.retries >= 3 && self.completion && !self.hasCompleted) {
        self.hasCompleted = YES;
        NSError *err = [NSError errorWithDomain:@"DDP" code:500
                                      userInfo:@{NSLocalizedDescriptionKey: @"解析无效"}];
        self.completion(nil, err);
    }
    [self cleanupWebView];
}

// 反复采样 HTML，命中即停
static const NSInteger DDPMaxPoll = 6;   // 最多轮询 6 次
static const double    DDMPollGap = 1.0; // 每次间隔 1.0 秒

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.pollTicks = 0;
    [self ddpPollHTML:webView];
}

- (void)ddpPollHTML:(WKWebView *)webView {
    if (self.hasCompleted) return;
    self.pollTicks = self.pollTicks + 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DDMPollGap * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.hasCompleted) return;
        [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
            BOOL hit = [self ddpHandleHTML:result error:error];
            if (hit || self.hasCompleted) return;
            if (self.sameLenTicks >= 1) { // 长度不变 → 提前 reload
                self.reloadNow = YES;
                return;
            }
            if (self.pollTicks < DDPMaxPoll) {
                [self ddpPollHTML:webView];
            }
        }];
    });
}

// 校验命中并返回
- (BOOL)ddpHandleHTML:(id)result error:(NSError *)error {
    if (error) return NO;
    if (![result isKindOfClass:[NSString class]]) return NO;
    NSMutableString *html = [NSMutableString string];
    [html setString:result];
    NSRange full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"amp;" withString:@"" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"u002F" withString:@"/" options:NSCaseInsensitiveSearch range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"\\" withString:@"" options:NSCaseInsensitiveSearch range:full];

    if (html.length == self.lastHTMLLen) self.sameLenTicks = self.sameLenTicks + 1;
    else self.sameLenTicks = 0;
    self.lastHTMLLen = html.length;

    BOOL gallery = [html containsString:@"aweme-share-swiper-item"] || [html containsString:@"aweme-slides-swiper-item"];
    BOOL video   = [html containsString:@"video_id="];
    NSString *fail = [self ddpFailReason];
    if (fail) {
        if (self.completion && !self.hasCompleted) {
            self.hasCompleted = YES;
            NSError *err = [NSError errorWithDomain:@"DDP" code:501
                                          userInfo:@{NSLocalizedDescriptionKey: fail}];
            self.completion(nil, err);
        }
        self.retries = 0;
        return YES;
    }
    if (!gallery && !video) return NO;

    if (self.completion && !self.hasCompleted) {
        self.hasCompleted = YES;
        self.completion(html, nil);
    }
    self.retries = 0;
    return YES;
}

// 直播链接快速失败（按跳转后域名判定）
- (NSString *)ddpFailReason {
    NSString *url = self.webView.URL.absoluteString;
    if ([url containsString:@"webcast.amemv.com"] ||
        [url containsString:@"live.douyin.com"]) {
        return @"直播不支持";
    }
    return nil;
}

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
    static DDPEngine *i;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ i = [[self alloc] init]; });
    return i;
}

// 抠视频直链（playwm），过滤图集页误命中
- (NSArray<NSString *> *)extractVideoLinksFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSRegularExpression *re = DDPRegex(@"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+", NSRegularExpressionCaseInsensitive);
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *u = [[html substringWithRange:m.range] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        if ([u containsString:@"video_id=https:"]) continue;
        [result addObject:DDPRemoveWatermark(u)];
    }
    return [result copy];
}

// 抠图集直链：首个 images 容器的 url_list
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *decoded = [html mutableCopy];
    [decoded replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, decoded.length)];

    NSRange cr = [decoded rangeOfString:@"\"images\"" options:NSCaseInsensitiveSearch];
    if (cr.location == NSNotFound) return @[];
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
        NSRegularExpression *reU = DDPRegex(@"\"url_list\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\"", NSRegularExpressionCaseInsensitive);
        for (NSTextCheckingResult *m in [reU matchesInString:seg options:0 range:NSMakeRange(0, seg.length)]) {
            [result addObject:[[seg substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]];
        }
    }
    return [result copy];
}

- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSError *err) {
        if (html.length) {
            NSArray *videos = [self extractVideoLinksFromHTML:html];
            if (videos.count) {
                completion(DDPMediaTypeVideo, videos.firstObject, nil, nil);
                return;
            }
            NSArray *images = [self extractGalleryImagesFromHTML:html];
            if (images.count) {
                completion(DDPMediaTypeImage, nil, images, nil);
                return;
            }
        }
        completion(DDPMediaTypeUnknown, nil, nil,
                   err ?: [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
    }];
}

// 同步下载
- (NSData *)downloadVideoFromURL:(NSString *)url {
    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";
    [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
    [request setValue:url forHTTPHeaderField:@"Referer"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:[%c(CUtility) GetMMUserAgent] forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        result = data;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    return result;
}
@end

#pragma mark - 面板与服务

static BOOL gDDPDyTcEnable; // 一次性放行：防「直接发送」重发被自己拦截

static CMessageMgr *DDPMessageMgr(void) {
    return [[%c(MMContext) activeUserContext] getService:%c(CMessageMgr)];
}

// 查找当前聊天页会话名
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

// 自建 CMessageWrap 走 AddMsg 发送
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
+ (void)saveVideoToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion;
+ (void)saveImageToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion;
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish;
+ (NSArray<NSString *> *)ddpFetchImages:(NSArray<NSString *> *)urls;
+ (NSString *)ddpFetchToPath:(NSString *)path fromURL:(NSString *)url;
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)shareURL user:(NSString *)user finish:(void(^)(void))finish;
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

// 解析样板：loading→解析→失败提示
+ (void)ddpParse:(NSString *)url then:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs))then {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) { DDPShowError(err.localizedDescription ?: @"解析失败"); return; }
        then(type, videoURL, imageURLs);
    }];
}

+ (void)handleParseSend:(NSString *)url user:(NSString *)user {
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) [self sendVideoForURL:videoURL shareURL:url user:user finish:finish];
        else [self sendImagesForURLs:imageURLs user:user finish:finish];
    }];
}

// 下载视频并发送（复用 ddpFetchVideo）
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)url user:(NSString *)user finish:(void(^)(void))finish {
    [self ddpFetchVideo:videoURL forURL:url then:^(NSString *p) {
        if (finish) finish();
        if (p.length) [DDPPanel sendVideoAtPath:p toUser:user];
    }];
}

// 下载落盘，失败返回 nil（视频/图片共用）
+ (NSString *)ddpFetchToPath:(NSString *)path fromURL:(NSString *)url {
    NSData *data = [[DDPEngine shared] downloadVideoFromURL:url];
    if (!data.length) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
    return [data writeToFile:path atomically:YES] ? path : nil;
}

// 串行下载图片，返回成功路径
+ (NSArray<NSString *> *)ddpFetchImages:(NSArray<NSString *> *)urls {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *imgURL in urls) {
        NSString *p = [self ddpFetchToPath:DDPTempPathExt(imgURL, DDPImageExt(imgURL)) fromURL:imgURL];
        if (p) [out addObject:p];
    }
    return out;
}

+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish {
    dispatch_async(DDPBg(), ^{
        NSArray *paths = [self ddpFetchImages:urls];
        NSInteger total = paths.count;
        if (total == 0) {
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
                        if (failed == 0) DDPShowDone(@"保存成功");
                        else DDPShowError(@"保存失败");
                    });
                });
            }];
        }
    });
}

// 生成视频缩略图（第 0.5s 帧）
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

// 手动构造 CaptureVideoInfo（否则发本地视频崩溃）
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) return;
        NSString *thumbPath = [self generateThumbnailForVideoPath:path];
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
        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        [ctrl AddVideoMsg:from ToUsr:chatName VideoInfo:info];
    });
}

// 发图片消息
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
        [DDPMessageMgr() AddMsg:chatName MsgWrap:wrap];
    });
}

// 逐张下载并发送
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls user:(NSString *)user finish:(void(^)(void))finish {
    dispatch_async(DDPBg(), ^{
        BOOL anySent = NO;
        for (NSString *imgURL in urls) {
            @autoreleasepool {
                NSString *p = [self ddpFetchToPath:DDPTempPathExt(imgURL, DDPImageExt(imgURL)) fromURL:imgURL];
                if (!p) continue;
                [DDPPanel sendImageAtPath:p toUser:user];
                anySent = YES;
            }
        }
        if (!anySent) DDPShowError(@"发送失败");
        else if (finish) finish();
    });
}

// 下载视频到缓存，成功后回调
+ (void)ddpFetchVideo:(NSString *)videoURL forURL:(NSString *)url then:(void (^)(NSString *path))then {
    NSString *path = DDPTempPath(url);
    dispatch_async(DDPBg(), ^{
        NSString *p = [self ddpFetchToPath:path fromURL:videoURL];
        if (!p) { DDPShowError(@"下载失败"); return; }
        if (then) then(p);
    });
}

+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    [self ddpParse:url then:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs) {
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            [self ddpFetchVideo:videoURL forURL:url then:^(NSString *p) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (p.length) [DDPPanel presentImageViewer:@[p] fromVC:vc]; finish(); });
            }];
        } else {
            dispatch_async(DDPBg(), ^{
                NSArray *out = [self ddpFetchImages:imageURLs];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (out.count) [DDPPanel presentImageViewer:out fromVC:vc];
                    finish();
                });
            });
        }
    }];
}

+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
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

// 半模态：不全屏盖死导航栏
+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc {
    DDPQLViewer *qlc = [[DDPQLViewer alloc] init];
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *p in paths) [urls addObject:[NSURL fileURLWithPath:p]];
    qlc.urls = urls;
    qlc.dataSource = qlc;
    qlc.currentPreviewItemIndex = 0;
    qlc.modalPresentationStyle = UIModalPresentationPageSheet;
    // 半屏，可上拖全屏
    qlc.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    qlc.sheetPresentationController.prefersGrabberVisible = YES;
    [vc presentViewController:qlc animated:YES completion:nil];
}

// 存视频到相册
+ (void)saveVideoToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) { if (completion) completion(NO); return; }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) { if (completion) completion(success); }];
    }];
}

// 存图片到相册（直接写原始字节）
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
            if (completion) completion(success);
        }];
    }];
}

@end

#pragma mark - Hook：长按菜单「解析 / 预览」

// 取消息文本
static NSString *ddp_wrapContent(CMessageWrap *wrap) {
    return wrap.m_nsContent;
}

// 菜单对应的消息与宿主 VC（由 willShowMenuController 缓存）
static CMessageWrap *gDDPMenuWrap;
static UIViewController *gDDPMenuVC;

// 注入菜单项（已注入则跳过，用 userInfo token 去重）
static NSArray *ddp_inject_item(id cell, NSArray *original, BOOL enabled, NSString *title, NSString *svgName, SEL action, long long menuType) {
    if (!enabled) return original;
    NSString *token = [@"ddp:" stringByAppendingString:NSStringFromSelector(action)];
    for (MMMenuItem *it in original)
        if ([it.userInfo isKindOfClass:[NSString class]] && [(NSString *)it.userInfo isEqualToString:token]) return original;
    MMMenuItem *item = [[%c(MMMenuItem) alloc] initWithTitle:title svgName:svgName target:cell action:action];
    [item setUserInfo:token];
    [item setMenuType:menuType];
    NSMutableArray *items = [NSMutableArray arrayWithArray:original];
    [items addObject:item];
    return items;
}

// 微信菜单显示前直传消息对象，覆盖气泡与浮窗预览菜单
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

// 气泡与浮窗菜单都经此装配，已存在同 token 项时跳过
%hook MMMenuController
- (void)setMenuItems:(NSArray *)items {
    NSString *content = ddp_wrapContent(gDDPMenuWrap);
    BOOL enabled = DDPEnabled()
                   && DDPExtractURL(content).length && !DDPIsDouyinLiveText(content);
    NSArray *all = ddp_inject_item(gDDPMenuVC, items, enabled, @"解析", @"icons_filled_search", @selector(ddp_vcParse:), 1010);
    all = ddp_inject_item(gDDPMenuVC, all, enabled, @"预览", @"icons_filled_play", @selector(ddp_vcPreview:), 1011);
    %orig(all);
}
%end

#pragma mark - Hook：CMessageMgr AddMsg（弹面板的入口）

// 拦截自己发出的抖音链接文本，弹面板
%hook CMessageMgr
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap {
    do {
        if (!DDPEnabled() || !wrap) break;
        if (!DDPIsOutgoing(wrap)) break;
        unsigned int mt = wrap.m_uiMessageType;
        if (mt != 1) break;
        BOOL bypass = gDDPDyTcEnable; gDDPDyTcEnable = NO; // 复位须在检测前
        if (bypass) break;
        NSString *content = wrap.m_nsContent;
        if (!DDPExtractURL(content)) break;
        if (DDPIsDouyinLiveText(content)) break;
        NSString *target = usr.length ? usr : wrap.m_nsToUsr;
        if ([DDPPanel showForContent:content user:target]) return; // 命中后拦截
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
    [sec addCell:[%c(WCTableViewCellManager) switchCellForSel:@selector(onEnabledSwitch:) target:self title:@"启用抖音解析" on:DDPEnabled()]];
    [_tableViewMgr addSection:sec];
    [_tableViewMgr reloadTableView];
}
- (void)onEnabledSwitch:(UISwitch *)sender { DDPSetEnabled(sender.isOn); }
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
