
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

#pragma mark - 抖音官方 API 路线（对齐 ZDY：ttwid 注册 + aweme/detail + iesdouyin 兜底）

// 枚举提前到此处，供 API 模块与 DDPEngine 共用
typedef NS_ENUM(NSInteger, DDPMediaType) {
    DDPMediaTypeUnknown = -1,
    DDPMediaTypeVideo   = 0,
    DDPMediaTypeImage   = 1,
};

static NSString * const kDDPDesktopUA = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

// 从 URL/文本提取 aweme_id（优先 /video|note|slides/<id>，后备 modal_id|aweme_id|item_ids?|itemId=）
static NSString *DDPExtractAwemeId(NSString *text) {
    NSArray *pres = @[
        @"/(?:share/)?(?:video|note|slides)/(\\d{15,25})",
        @"(?:modal_id|aweme_id|item_ids?|itemId)[=:\"](\\d{15,25})"
    ];
    for (NSString *pat in pres) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *ms = [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        if (ms.count) return [text substringWithRange:[ms.firstObject rangeAtIndex:1]];
    }
    return nil;
}

// 取 douyin.com / iesdouyin.com 域名的 cookie 拼成 Cookie 头；extraTtwid 非 nil 时追加到最前
static NSString *DDPDouyinCookieHeader(NSString *extraTtwid) {
    NSMutableArray *parts = [NSMutableArray array];
    if (extraTtwid.length) [parts addObject:[NSString stringWithFormat:@"ttwid=%@", extraTtwid]];
    NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in store.cookies) {
        NSString *dom = c.domain ?: @"";
        if ([dom containsString:@"douyin.com"] || [dom containsString:@"iesdouyin.com"])
            [parts addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
    }
    return [parts componentsJoinedByString:@"; "];
}

// 同步 HTTP（后台线程调用，信号量阻塞）。返回 data；HTTP 状态码写入 *outCode（失败写 -1）
static NSData *DDPApiHttp(NSString *url, NSString *method, NSDictionary *headers, NSData *body, NSTimeInterval timeout, NSInteger *outCode) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = method ?: @"GET";
    req.timeoutInterval = timeout;
    [req setValue:kDDPDesktopUA forHTTPHeaderField:@"User-Agent"];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [req setValue:v forHTTPHeaderField:k]; }];
    if (body) { [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; req.HTTPBody = body; }
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSData *result = nil; __block NSInteger code = -1;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) code = (NSInteger)((NSHTTPURLResponse *)resp).statusCode;
        if (!err && data) result = data;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    if (outCode) *outCode = code;
    return result;
}

// 递归定位含 aweme_id==targetId 且带 video/images/image_post_info 的详情对象
static id DDPJsonFindAweme(id obj, NSString *targetId) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)obj;
        id aid = d[@"aweme_id"];
        if (aid != nil) {
            BOOL match = [[NSString stringWithFormat:@"%@", aid] isEqualToString:targetId];
            BOOL hasMedia = d[@"video"] != nil || d[@"images"] != nil || d[@"image_post_info"] != nil;
            if (match && hasMedia) return d;
        }
        for (id key in d) { id r = DDPJsonFindAweme(d[key], targetId); if (r) return r; }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id el in (NSArray *)obj) { id r = DDPJsonFindAweme(el, targetId); if (r) return r; }
    }
    return nil;
}

// 水印/官方 logo 链判定（命中即丢弃）
static BOOL DDPUrlIsWatermark(NSString *u) {
    NSArray *bad = @[@"playwm", @"watermark", @"tplv-dy-water", @"/logo/", @"logo_type", @"wm_video", @"_wm_"];
    for (NSString *b in bad) if ([u containsString:b]) return YES;
    return NO;
}

// 图集：images[].download_addr.url_list[0]（回退 image_post_info.images）
static NSArray *DDPExtractImageURLsFromJson(NSDictionary *aweme) {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *images = aweme[@"images"];
    if (![images isKindOfClass:[NSArray class]]) {
        NSDictionary *ipo = aweme[@"image_post_info"];
        if ([ipo isKindOfClass:[NSDictionary class]]) images = ipo[@"images"];
    }
    for (NSDictionary *img in images) {
        if (![img isKindOfClass:[NSDictionary class]]) continue;
        NSString *u = nil;
        NSDictionary *da = img[@"download_addr"];
        if ([da isKindOfClass:[NSDictionary class]]) u = [da[@"url_list"] firstObject] ?: [da[@"download_url_list"] firstObject];
        if (!u.length) u = [img[@"url_list"] firstObject];
        if (u.length && ![out containsObject:u]) [out addObject:u];
    }
    return out;
}

// 视频：play_addr → play_addr_h264 → play_addr_265 → download_addr → play_addr_lowbr，遍历 url_list 取首条干净直链
static NSString *DDPFirstPlayURL(NSDictionary *video) {
    NSArray *keys = @[@"play_addr", @"play_addr_h264", @"play_addr_265", @"download_addr", @"play_addr_lowbr"];
    for (NSString *k in keys) {
        NSDictionary *pa = video[k];
        if (![pa isKindOfClass:[NSDictionary class]]) continue;
        NSArray *list = pa[@"url_list"];
        if (![list isKindOfClass:[NSArray class]]) list = pa[@"download_url_list"];
        if (![list isKindOfClass:[NSArray class]] && pa[@"url"]) list = @[pa[@"url"]];
        for (id u in list) {
            if ([u isKindOfClass:[NSString class]] && ((NSString *)u).length && !DDPUrlIsWatermark(u)) return u;
        }
    }
    return nil;
}

@interface DDPApiParser : NSObject
+ (instancetype)shared;
- (void)parseURL:(NSString *)url completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion;
- (NSString *)resolveCanonicalURL:(NSString *)url;   // 跟随 302 把短链展开成带 aweme_id 的真实 URL
@end

@implementation DDPApiParser {
    dispatch_queue_t _apiQueue;
    NSString *_cachedTtwid;
}
+ (instancetype)shared { static DDPApiParser *i; static dispatch_once_t once; dispatch_once(&once, ^{ i = [[self alloc] init]; }); return i; }
- (instancetype)init { if (self = [super init]) _apiQueue = dispatch_queue_create("ddp.api", DISPATCH_QUEUE_SERIAL); return self; }

- (void)parseURL:(NSString *)url completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    dispatch_async(_apiQueue, ^{
        // workingURL 承载「可能被短链重定向展开后的 URL」，避免直接改参数 url（block 捕获不可赋值）
        NSString *workingURL = [url copy];
        NSString *awemeId = DDPExtractAwemeId(workingURL);
        DDDLog(@"[API] 入参=%@ aweme_id=%@", url, awemeId ?: @"(null)");
        // 短链（v.douyin.com/iRxxx 之类）里没有数字 ID，需先展开成真实 URL 才能走 API
        // 对齐 ZDY 的 ZJHRedirectDelegate 重定向捕获手法：跟随 302 拿最终 URL
        if (!awemeId.length) {
            NSString *resolved = [self resolveCanonicalURL:workingURL];
            if (resolved.length && ![resolved isEqualToString:workingURL]) {
                workingURL = resolved;
                awemeId = DDPExtractAwemeId(workingURL);
                DDDLog(@"[API] 短链重定向解析: %@ → %@", url, workingURL);
                DDDLog(@"[API] 短链展开后 aweme_id=%@", awemeId ?: @"(null)");
            }
        }
        if (!awemeId.length) {
            DDDLog(@"[API] 未提取到 aweme_id，放弃 API 路线（交给 WebView 兜底）");
            if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP-API" code:-10 userInfo:@{@"reason":@"no aweme_id"}]);
            return;
        }
        NSString *ttwid = [self registerTtwid];
        DDDLog(@"[API] ttwid=%@", ttwid ?: @"(空)");
        NSDictionary *detail = [self fetchDetail:awemeId ttwid:ttwid];
        if (!detail) detail = [self fetchIesDouyin:awemeId ttwid:ttwid];
        if (!detail) {
            DDDLog(@"[API] 主/备端点均无数据，交给 WebView 兜底");
            if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP-API" code:-11 userInfo:@{@"reason":@"no api data"}]);
            return;
        }
        NSArray *images = DDPExtractImageURLsFromJson(detail);
        NSString *video = nil;
        NSDictionary *videoObj = detail[@"video"];
        if ([videoObj isKindOfClass:[NSDictionary class]]) video = DDPFirstPlayURL(videoObj);
        if (video.length) { DDDLog(@"[API] ★视频直链命中"); if (completion) completion(DDPMediaTypeVideo, video, nil, nil); }
        else if (images.count) { DDDLog(@"[API] ★图集命中 数=%lu", (unsigned long)images.count); if (completion) completion(DDPMediaTypeImage, nil, images, nil); }
        else { DDDLog(@"[API] 取到详情对象但无直链字段，交给 WebView 兜底"); if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP-API" code:-12 userInfo:@{@"reason":@"no media field"}]); }
    });
}

- (NSString *)registerTtwid {
    @synchronized (self) { if (_cachedTtwid.length) return _cachedTtwid; }
    NSDictionary *body = @{@"region":@"cn", @"aid":@6383, @"needFid":@NO, @"service":@"www.douyin.com",
        @"migrate_info":@{@"ticket":@"source", @"source":@"node"}, @"cbUrlProtocol":@"https", @"union":@YES};
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSInteger code = 0;
    NSData *resp = DDPApiHttp(@"https://ttwid.bytedance.com/ttwid/union/register/", @"POST",
        @{@"Accept":@"application/json"}, data, 20.0, &code);
    DDDLog(@"[API] ttwid注册 HTTP=%ld 字节=%lu", (long)code, (unsigned long)(resp ? resp.length : 0));
    NSString *t = nil;
    if (resp.length) {
        id json = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            id d = json[@"data"];
            if ([d isKindOfClass:[NSDictionary class]]) t = d[@"ttwid"];
            if (!t) t = json[@"ttwid"];
        }
    }
    if ([t isKindOfClass:[NSString class]] && ((NSString *)t).length) { @synchronized (self) { _cachedTtwid = t; } }
    return t;
}

- (NSDictionary *)fetchDetail:(NSString *)awemeId ttwid:(NSString *)ttwid {
    NSString *url = [NSString stringWithFormat:@"https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=%@&aid=6383&device_platform=webapp&channel=channel_pc_web&version_code=170400&version_name=17.4.0&request_from=web&pc_client_type=1&os_version=10.15.7&browser_language=zh-CN&browser_platform=MacIntel&browser_name=Chrome&browser_version=120.0.0.0&platform=PC&cookie_enabled=true", awemeId];
    NSMutableDictionary *headers = [@{@"Accept":@"application/json, text/plain, */*", @"Accept-Language":@"zh-CN,zh;q=0.9",
        @"Referer":@"https://www.douyin.com/", @"Origin":@"https://www.douyin.com"} mutableCopy];
    NSString *cookie = DDPDouyinCookieHeader(ttwid);
    if (cookie.length) headers[@"Cookie"] = cookie;
    NSInteger code = 0;
    NSData *resp = DDPApiHttp(url, @"GET", headers, nil, 25.0, &code);
    DDDLog(@"[API] aweme/detail HTTP=%ld 字节=%lu", (long)code, (unsigned long)(resp ? resp.length : 0));
    if (!resp.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = DDPJsonFindAweme(json, awemeId);
    if (d) DDDLog(@"[API] aweme/detail 命中详情对象");
    return d;
}

- (NSDictionary *)fetchIesDouyin:(NSString *)awemeId ttwid:(NSString *)ttwid {
    NSString *url = [NSString stringWithFormat:@"https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=%@", awemeId];
    NSMutableDictionary *headers = [@{@"Accept":@"application/json", @"Referer":@"https://www.iesdouyin.com/"} mutableCopy];
    NSString *cookie = DDPDouyinCookieHeader(ttwid);
    if (cookie.length) headers[@"Cookie"] = cookie;
    NSInteger code = 0;
    NSData *resp = DDPApiHttp(url, @"GET", headers, nil, 20.0, &code);
    DDDLog(@"[API] iesdouyin HTTP=%ld 字节=%lu", (long)code, (unsigned long)(resp ? resp.length : 0));
    if (!resp.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = DDPJsonFindAweme(json, awemeId);
    if (d) DDDLog(@"[API] iesdouyin 命中详情对象");
    return d;
}

// 跟随 HTTP 302 把短链（v.douyin.com/iRxxx 等）展开成真实 URL。
// 默认 NSURLSession 会自动跟随重定向，最终 response.URL 即规范页地址（含数字 aweme_id）。
// 对齐 ZDY 的 ZJHRedirectDelegate：捕获重定向目标，得到 www.douyin.com/video/<id> 这类带 ID 的 URL。
- (NSString *)resolveCanonicalURL:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    if (!u) return url;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    req.HTTPMethod = @"GET";
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    __block NSString *final = url;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (resp.URL.absoluteString.length) final = resp.URL.absoluteString;
        dispatch_semaphore_signal(sema);
    }] resume];
    long ws = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)20 * NSEC_PER_SEC));
    [session finishTasksAndInvalidate];
    if (ws != 0) { DDDLog(@"[API] 短链展开超时/失败，沿用原 URL"); return url; }
    if (final.length && ![final isEqualToString:url]) {
        DDDLog(@"[API] 短链重定向解析: %@ → %@", url, final);
        return final;
    }
    return url;
}
@end

#pragma mark - 抓取（离屏 WKWebView，轮询 playwm）

static const NSInteger DDPCodeGallery = 0x4161;   // 图集类型标记
static const NSInteger DDPMaxRetries = 3;          // 最多重载 3 次（实测 1~2 轮即出直链）

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, strong) NSURLRequest *ddpRequest;
@property (nonatomic, assign) NSTimeInterval fetchStart;
@property (nonatomic, assign) NSUInteger lastCleanLen;
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
        _webView.customUserAgent = [%c(CUtility) GetMMUserAgent];
        _webView.navigationDelegate = self;
        _webView.hidden = YES;   // WKWebView 独立进程渲染，无需挂窗口；hidden 防误显示
    }
    return self;
}
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion {
    self.completion = completion; self.hasCompleted = NO;
    NSURL *nsurl = [NSURL URLWithString:url];
    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
    self.ddpRequest = request; self.retries = 0; self.lastCleanLen = 0;
    self.fetchStart = CFAbsoluteTimeGetCurrent();
    dispatch_async(dispatch_get_main_queue(), ^{ [self.webView loadRequest:request]; });
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // v.douyin.com 短链会 302 到 iesdouyin.com/share/<type>/<id>，该落地页无图集/直链数据；
    // 提取 type+id 改加载规范 www.douyin.com/<type>/<id>（已非 share 路径，不会循环重导）
    NSString *u = webView.URL.absoluteString ?: @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/share/(note|video)/(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:u options:0 range:NSMakeRange(0, u.length)];
    if (m) {
        NSString *type = [u substringWithRange:[m rangeAtIndex:1]];
        NSString *awemeId = [u substringWithRange:[m rangeAtIndex:2]];
        NSString *canon = [NSString stringWithFormat:@"https://www.douyin.com/%@/%@", type, awemeId];
        // 图集：分享页只有渲染后的 DOM <img>、没有内嵌 JSON "images"，必须跳规范地址才取得到 url_list。
        // 同时把 ddpRequest 换成规范地址——否则 handleRenderedHTML 的重试会重载原始短链，
        // 再次 302 回 share 页并触发本跳转，形成「短链↔规范地址」死循环。
        if ([type caseInsensitiveCompare:@"note"] == NSOrderedSame) {
            NSURLRequest *canonReq = [NSURLRequest requestWithURL:[NSURL URLWithString:canon]];
            self.ddpRequest = canonReq;
            self.fetchStart = CFAbsoluteTimeGetCurrent();
            [webView loadRequest:canonReq];
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
            [html containsString:@"aweme-share-swiper-item"] ||
            [html containsString:@"aweme-slides-swiper-item"]) {
            [strong handleRenderedHTML:html];
            return;
        }
        if (waited > 5.0) { [strong handleRenderedHTML:html]; return; }
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
    self.retries = 0;
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

    NSInteger code = ([clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"]) ? DDPCodeGallery : 0;
    if (code == DDPCodeGallery || [clean containsString:@"playwm"]) { [self ddFinishWithHTML:clean code:code]; return; }
    // 重载拿回完全相同的 HTML：再试也不会有新内容，直接放弃
    if (self.lastCleanLen == clean.length) { [self ddFinishWithHTML:nil code:500]; return; }
    self.lastCleanLen = clean.length;
    if (self.retries < DDPMaxRetries) {
        self.retries += 1;
        [self.webView loadRequest:self.ddpRequest];
        return;
    }
    [self ddFinishWithHTML:nil code:500];
}
- (WKWebView *)webView { return _webView; }
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
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *u = [[html substringWithRange:m.range] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        if ([u containsString:@"video_id=https:"]) continue;
        NSString *clean = DDPRemoveWatermark(u);
        if (![result containsObject:clean]) [result addObject:clean];
    }
    DDDLog(@"extractVideoLinks: 候选数=%lu", (unsigned long)result.count);
    return [result copy];
}

// 图集：只取第一个 "images" 容器（页面会把同一份图集重复嵌入多次，实测首个容器即完整图集）
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableString *decoded = [html mutableCopy];
    [decoded replaceOccurrencesOfString:@"\\u002f" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    [decoded replaceOccurrencesOfString:@"\\/" withString:@"/" options:0 range:NSMakeRange(0, decoded.length)];
    [decoded replaceOccurrencesOfString:@"\\\"" withString:@"\"" options:0 range:NSMakeRange(0, decoded.length)];
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
        NSRegularExpression *reU = [NSRegularExpression
            regularExpressionWithPattern:@"\"url_list\"\\s*:\\s*\\[\\s*\"(https?://[^\"]+)\""
            options:NSRegularExpressionCaseInsensitive error:nil];
        for (NSTextCheckingResult *m in [reU matchesInString:seg options:0 range:NSMakeRange(0, seg.length)]) {
            [result addObject:[[seg substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]];
        }
    }
    return [result copy];
}
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    DDDLog(@"parseDouyinURL 入参=%@", url);
    // API 优先（对齐 ZDY 官方路线：ttwid + aweme/detail，能过分享页 sec_did 封锁），失败再回退 WebView SSR 路线
    [[DDPApiParser shared] parseURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err == nil && type != DDPMediaTypeUnknown && (videoURL.length || imageURLs.count)) {
            DDDLog(@"parseDouyinURL → API 命中 type=%ld", (long)type);
            if (completion) completion(type, videoURL, imageURLs, nil);
            return;
        }
        DDDLog(@"parseDouyinURL → API 未命中(err=%@)，回退 WebView 路线", err);
        [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSInteger errCode) {
            if (!html.length) { if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-2 userInfo:nil]); return; }
            NSArray *videos = [self extractVideoLinksFromHTML:html];
            if (videos.count) { if (completion) completion(DDPMediaTypeVideo, videos.firstObject, nil, nil); return; }
            NSArray *images = [self extractGalleryImagesFromHTML:html];
            if (images.count) { if (completion) completion(DDPMediaTypeImage, nil, images, nil); return; }
            if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
        }];
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
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) dcode = (NSInteger)((NSHTTPURLResponse *)resp).statusCode;
        derr = err.localizedDescription;
        if (!err && data) result = data;
        dispatch_semaphore_signal(sema);
    }] resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    DDDLog(@"downloadMedia: 字节=%lu HTTP=%ld err=%@ url=%@", (unsigned long)(result ? result.length : 0), (long)dcode, derr ?: @"nil", ([url length] > 120) ? [[url substringToIndex:120] stringByAppendingString:@"…"] : url);
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
                                                     version:@"1.1.0"
                                                  controller:@"DDPDouyinParseSettingsViewController"];
    }
}
