
// DDDouyinParse —— 微信内抖音分享链接解析插件（Theos / Logos 单文件）
//
// 处理管线：
//   1. 在聊天中识别抖音分享链接（消息发送时触发）
//   2. 用隐藏的 WKWebView 抓取官方分享页 HTML（不注入脚本，仅渲染后取 outerHTML）
//   3. 正则提取去水印直链（视频 / 图文图集 / 幻灯片）
//   4. 弹面板让用户「发送 / 预览 / 保存」（微信原生 WCActionSheet）
//
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVKit/AVKit.h>
#import <QuickLook/QuickLook.h>

#pragma mark - 微信私有类声明（仅声明插件用到的方法）

// 注意：以下类只做声明、不参与链接。引用时一律用 Logos 的 %c(ClassName)
// （展开为 objc_getClass，运行时解析）；若直接写 [ClassName method] 或
// [ClassName alloc]，链接器会去找 _OBJC_CLASS_$_ClassName 并报
// "Undefined symbols for architecture arm64/arm64e"。

// 微信内置提示控件（方形带图标）：转圈 / ✓ / 错误 三态，运行时按类名取，编译期不产生链接符号
@interface WeToast : NSObject
+ (instancetype)toast;
- (void)setLoadingStyle:(BOOL)style;
- (void)showToastWithText:(NSString *)text;
- (void)showDoneToastWithText:(NSString *)text;    // 方形带 ✓
- (void)showErrorToastWithText:(NSString *)text;   // 方形带错误图标
- (void)hideWithAnimated:(int)animated;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
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
@property (nonatomic, copy) NSString *headerTitle;   // 头文件 37/65 行有 getter/setter
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 on:(BOOL)arg4;
+ (id)normalCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3;
+ (id)normalCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 detail:(id)arg4;
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
+ (BOOL)isSenderFromMsgWrap:(id)wrap;   // 判断消息是否自己发出（区分收发方）
@end

@interface SettingUtil : NSObject  // 取本机 wxid（getLocalUsrName:0）
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

@interface MMServiceCenter : NSObject
- (id)getService:(Class)arg1;
@end

@interface MMContext : NSObject
+ (id)currentContext;
+ (id)activeUserContext;   // 取当前登录用户上下文
- (id)getService:(Class)arg1;
@property (readonly, nonatomic) MMServiceCenter *serviceCenter;
@end

@interface CMessageMgr : NSObject
// 注意：AddVideoMsg 第一个参数是【发送方】本机 wxid，第二个参数是【接收方】。
- (id)AddVideoMsg:(NSString *)fromUsr ToUsr:(NSString *)toUsr VideoInfo:(id)info;
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap;
@end

// 图片消息扩展操作（写入原图扩展信息）
@protocol DDPMsgExtendOperation <NSObject>
- (void)setImage:(UIImage *)arg1 withData:(NSData *)arg2 isOriginImage:(BOOL)arg3;
@end

// CMessageWrap 扩展：通过 BaseMsgContentLogicController 生成图片消息
@interface CMessageWrap (DDP)
- (id<DDPMsgExtendOperation>)m_extendInfoWithMsgType;
@end

@interface CUtility : NSObject  // 微信 UA（GetMMUserAgent）
+ (NSString *)GetMMUserAgent;
@end

@interface CRUtils : NSObject   // 通用工具：md5（CRUtils.h:9），用于生成缓存文件名
+ (NSString *)md5:(NSString *)str;
@end

// 微信头文件里 MMMenuItem 直接继承 NSObject（不是 UIMenuItem），且没有 title 的 getter，
// 所以识别菜单项一律走 userInfo 打标记，不要读 title（会 unrecognized selector）。参考 DD语音包。
@interface MMMenuItem : NSObject
@property (nonatomic, retain) id userInfo;
- (instancetype)initWithTitle:(NSString *)title svgName:(NSString *)svgName target:(id)target action:(SEL)action;
// 菜单项 ID：initWithTitle: 创建默认 0，须设唯一值，否则与其他插件注入项撞车被微信去重
- (void)setMenuType:(long long)type;
@end

// 注入菜单项（参考 DD语音包 ddvp_inject_item：svg 图标 + 标题，一级平铺项）。已注入则跳过。
static NSArray *ddp_inject_item(id cell, NSArray *original, BOOL enabled, NSString *title, NSString *svgName, SEL action, long long menuType);

// 面板用微信原生 WCActionSheet（底部弹出动作面板）
@interface WCActionSheet : NSObject
- (instancetype)initWithTitle:(NSString *)title cancelButtonTitle:(NSString *)cancelTitle;
- (long long)addButtonWithTitle:(NSString *)title eventAction:(void (^)(void))action;
- (void)showInView:(UIView *)view;
@end

// 系统图片预览数据源（QLPreviewController 的 dataSource）
static const void *kDDPImageQLSourceKey = &kDDPImageQLSourceKey;

@interface DDPImageQLSource : NSObject <QLPreviewControllerDataSource>
@property (nonatomic, copy) NSArray<NSString *> *paths;
@end
@implementation DDPImageQLSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return (NSInteger)self.paths.count;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return [NSURL fileURLWithPath:self.paths[index]];
}
@end

// 视频信息构造（8.0.79 私有类，头文件已确认）
@interface CaptureVideoInfo : NSObject
+ (id)genVideoInfoWithVideoUrl:(id)url thumb:(id)thumb;
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

#pragma mark - 插件内部类声明


#pragma mark - 文件日志

// 日志写入沙盒 tmp/DDDParse.log（Filza 可访问）
static inline NSString *DDDLogPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse.log"];
}
static void DDDWriteLog(NSString *msg) {
    if (!msg.length) return;
    NSString *path = DDDLogPath();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
}
static inline NSString *DDDReadLog(void) {
    NSString *path = DDDLogPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}
static inline void DDDClearLog(void) {
    NSString *path = DDDLogPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
// 诊断日志（前缀 [DDDParse]，同时落盘）
#define DDDLog(fmt, ...) do { NSString *__ddds = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; NSLog(@"[DDDParse] %@", __ddds); DDDWriteLog(__ddds); } while (0)

#pragma mark - 配置

static NSString * const kDDPEnabledKey   = @"DDDouyinParseEnabled";

@interface DDPConfig : NSObject
@property (nonatomic, assign) BOOL enabled;
+ (instancetype)shared;
@end

@implementation DDPConfig

+ (instancetype)shared {
    static DDPConfig *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        // 不设默认开启：key 不存在即 NO，与 DD广告拦截一致
        _enabled = [NSUserDefaults.standardUserDefaults boolForKey:kDDPEnabledKey];
        DDDLog(@"DDPConfig init enabled=%d", _enabled);
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kDDPEnabledKey];
}

@end

#pragma mark - 工具函数

// 抖音链接检测：仅认这三类官方分享链接
// 抖音分享链接识别：根域名 douyin.com 一锤定音。
// 涵盖 v.douyin.com 短链（视频/图文/直播通用）与 www.douyin.com/video、/note 长链；
// 直播由 DDPIsDouyinLiveText（短链无日期）在调用处单独排除，这里无需区分。
// （若文本仅口头提及 douyin.com 而无真实链接，下一步 DDPExtractURL 抽不到 URL 会自行返回，无副作用）
static inline BOOL DDPContainsDouyinLink(NSString *text) {
    return text.length && [text containsString:@"douyin.com"];
}

// 排除抖音直播分享：v.douyin.com 短链分享中，直播文案不含发布日期 MM/DD，
// 而视频/图文分享均带日期；故"短链 + 链接后无日期"可靠指向直播。
// （直播间分享文案一般无"正在直播"字样，故改用日期特征区分；
//   仅当抖音改版致视频/图文分享不再带日期时可能误杀，届时回退即可）
static inline BOOL DDPIsDouyinLiveText(NSString *text) {
    if (!text.length) return NO;
    // 只检查 v.douyin.com 链接【之后】的尾缀：日期稳定出现在链接后，
    // 链接前的引导文案（标题）是用户自定义内容、可能碰巧含 MM/DD，不可信。
    NSRange linkR = [text rangeOfString:@"v.douyin.com"];
    if (linkR.location == NSNotFound) return NO;
    NSString *after = [text substringFromIndex:linkR.location];
    NSRange r = [after rangeOfString:@"\\d{2}/\\d{2}" options:NSRegularExpressionSearch];
    if (r.location == NSNotFound) { DDDLog(@"直播排除: 短链链接后无日期"); return YES; }
    return NO;
}

// 发送方判定：微信原生类方法（CMessageWrap.h:19）
static BOOL DDPIsOutgoing(CMessageWrap *wrap) {
    return [%c(CMessageWrap) isSenderFromMsgWrap:wrap];
}

// 正则提取链接中的 URL
static inline NSString *DDPExtractURL(NSString *text) {
    if (!text.length) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s\"']+"
                                                                          options:0
                                                                            error:&err];
    if (err) return nil;
    NSTextCheckingResult *match = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    return [text substringWithRange:match.range];
}

// 去水印：/playwm/ → /play/，清晰度固定 720p
// 稳定走 720p：正则替换已有的 ratio=NNNp；若链接本身不含 ratio=，则强制拼接 ratio=720p，避免走抖音默认档位。
// 注：抖音会忽略其不支持的 ratio（如 480p）并回退默认最高档（实测 480p 反而下到 1080p），故用 720p 作稳妥中档。
static inline NSString *DDPRemoveWatermark(NSString *url) {
    if (!url.length) return nil;
    NSString *clean = [url stringByReplacingOccurrencesOfString:@"/playwm/" withString:@"/play/"];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"ratio=\\d+p"
                                                                          options:0
                                                                            error:nil];
    if (re) {
        clean = [re stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@"ratio=720p"];
    }
    // 链接本身不含 ratio=（正则未触发）时，强制拼接 ratio=720p，确保稳定走 720p 而非抖音默认档位
    if ([clean rangeOfString:@"ratio="].location == NSNotFound) {
        NSString *sep = ([clean rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
        clean = [clean stringByAppendingFormat:@"%@ratio=720p", sep];
    }
    return clean;
}

// 下载目标路径：<md5>.mp4（md5 走微信原生 CRUtils，不再自己实现 RFC1321）
static inline NSString *DDPTempPath(NSString *url) {
    NSString *md5 = [%c(CRUtils) md5:url];
    if (!md5.length) return nil;
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[md5 stringByAppendingString:@".mp4"]];
}

// 图片缓存路径 <md5>.<ext>
static inline NSString *DDPTempPathExt(NSString *url, NSString *ext) {
    NSString *md5 = [%c(CRUtils) md5:url];
    if (!md5.length) return nil;
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", md5, ext ?: @"dat"]];
}

// 取 URL 后缀作为临时文件扩展名（本地看图 QL 预览按扩展名识别格式；默认 jpg）
static inline NSString *DDPImageExt(NSString *url) {
    NSString *ue = [url pathExtension].lowercaseString;
    return ue.length ? ue : @"jpg";
}

// 取微信主窗口（单主窗口 app，直接取 AppDelegate.window，无需遍历场景）
static inline UIWindow *DDPKeyWindow(void) {
    return UIApplication.sharedApplication.delegate.window;
}

// 解析过程提示：参考 DD语音包的方形 WeToast 三态（转圈 / ✓ / 错误）。
// loading 与结果提示共用同一控件，出结果前必须先收起 loading。
static WeToast *gDDPBusyToast = nil;   // 进行中的 loading，出结果时收起

static WeToast *DDPToast(void) {
    return [%c(WeToast) toast];
}

// 同时只保留一个 loading 实例；起新的前先收掉旧的，否则上一个转圈会永远停在屏幕上
static void DDPHideLoading(void) {
    void (^work)(void) = ^{
        [gDDPBusyToast hideWithAnimated:YES];
        gDDPBusyToast = nil;
    };
    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

static void DDPShowLoading(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDDPBusyToast) DDPHideLoading();
        WeToast *toast = DDPToast();
        [toast setLoadingStyle:YES];
        [toast showToastWithText:text];
        gDDPBusyToast = toast;
    });
}

static void DDPShowError(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DDPHideLoading();
        [DDPToast() showErrorToastWithText:text];
    });
}

// 成功提示（对勾）+ 收起加载转圈（主线程）。用于保存相册等需要正向反馈的动作
static void DDPShowDone(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DDPHideLoading();
        [DDPToast() showDoneToastWithText:text];
    });
}

#pragma mark - 解析抓取（WKWebView 渲染）

// completion: (html, errCode)，DDPCodeGallery 表示图集
static const NSInteger DDPCodeGallery = 0x4161;   // 16737
static const NSInteger DDPMaxRetries = 3;          // 最多重试 3 次（配合"HTML 未变化即停"，实测 1~2 轮足够）

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, strong) NSURLRequest *ddpRequest;   // 当前请求（重试复用）
@property (nonatomic, assign) NSTimeInterval fetchStart;    // 解析开始时间（诊断用）
@property (nonatomic, assign) NSUInteger lastCleanLen;      // 上一轮 HTML 长度（空转检测）
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger errCode);
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion;
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code;   // 统一收尾（仅触发一次）
+ (instancetype)sharedFetcher;
@end

@implementation DDPWebFetcher
{
    WKWebView *_webView;
}

+ (instancetype)sharedFetcher {
    static DDPWebFetcher *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        // WKWebView 配置（allowsContentJavaScript 替代已废弃的 javaScriptEnabled）
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKWebpagePreferences *pagePrefs = [[WKWebpagePreferences alloc] init];
        pagePrefs.allowsContentJavaScript = YES;
        config.defaultWebpagePreferences = pagePrefs;

        // 不注入脚本，纯渲染后取 outerHTML
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];

        // 微信 UA（CUtility GetMMUserAgent），让抖音返回含 playwm 的页面
        NSString *ua = [%c(CUtility) GetMMUserAgent];
        if (!ua.length) {
            ua = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.40(0x18004025) NetType/WIFI Language/zh_CN";
        }
        _webView.customUserAgent = ua;

        _webView.navigationDelegate = self;

        // 离屏抓取：WKWebView 在独立 WebContent 进程渲染，无需挂到任何窗口即可 loadRequest / 执行 JS，
        // 故不挂窗口、省掉找 keyWindow 的遍历；hidden 仅防误显示
        _webView.hidden = YES;
    }
    return self;
}

// 开始抓取
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion {
    self.completion = completion;
    self.hasCompleted = NO;

    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        DDDLog(@"fetchHTMLFromURL: URL 非法，直接失败");
        if (completion) completion(nil, -1);
        return;
    }

    // cachePolicy 用默认协议缓存，超时 30s
    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:30.0];

    self.ddpRequest = request;
    self.retries = 0;
    self.lastCleanLen = 0;
    self.fetchStart = CFAbsoluteTimeGetCurrent();
    DDDLog(@"[DDPWebFetcher] 开始解析 url=%@", request.URL.absoluteString);
    // 首次加载，未命中 playwm 则重试
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadRequest:request];
    });
}

// 导航完成：立即开始轮询取 outerHTML，命中 playwm/图集即收，不再死等固定 5s
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    DDDLog(@"[DDPWebFetcher] didFinishNavigation retries=%u 距开始%.1fs", self.retries, CFAbsoluteTimeGetCurrent() - self.fetchStart);
    [self pollHTML:webView attempt:0];
}

// 轮询检测：每 0.5s 取一次 outerHTML，出现 playwm/图集立即交回 handleRenderedHTML 收尾（提前命中）；
// 超过 5s 仍无则同样交回，让其走原有"同 HTML 即停 + 重试"逻辑。避免固定 5s 空等，且不退化最坏耗时。
- (void)pollHTML:(WKWebView *)webView attempt:(NSUInteger)attempt {
    if (self.hasCompleted) return;
    __weak typeof(self) wself = self;
    [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
        __strong typeof(wself) strong = wself;
        if (!strong) return;
        if (error) { DDDLog(@"DDPWebFetcher: evalJS 失败 %@", error); [strong ddFinishWithHTML:nil code:-2]; return; }
        NSString *html = result ? [NSString stringWithFormat:@"%@", result] : @"";
        NSTimeInterval waited = CFAbsoluteTimeGetCurrent() - strong.fetchStart;
        if ([html containsString:@"playwm"] ||
            [html containsString:@"aweme-share-swiper-item"] ||
            [html containsString:@"aweme-slides-swiper-item"]) {
            DDDLog(@"[DDPWebFetcher] 轮询第%lu次命中 playwm 距开始%.1fs", (unsigned long)attempt, waited);
            [strong handleRenderedHTML:html];
            return;
        }
        if (waited > 5.0) {
            DDDLog(@"[DDPWebFetcher] 轮询%lu次(%.1fs)未命中，交回原判定", (unsigned long)attempt, waited);
            [strong handleRenderedHTML:html];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [strong pollHTML:webView attempt:attempt + 1];
        });
    }];
}

// 失败兜底，避免反复重载
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    DDDLog(@"DDPWebFetcher: didFailProvisionalNavigation %@", error);
    [self ddFinishWithHTML:nil code:-3];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    DDDLog(@"DDPWebFetcher: didFailNavigation %@", error);
    [self ddFinishWithHTML:nil code:-3];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    DDDLog(@"DDPWebFetcher: web content process did terminate");
    [self ddFinishWithHTML:nil code:-4];
}

// 统一收尾，仅触发一次
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code {
    DDDLog(@"[DDPWebFetcher] 收尾 code=%ld htmlLen=%lu 总重试=%u 总耗时%.1fs", (long)code, (unsigned long)(html ? html.length : 0), self.retries, CFAbsoluteTimeGetCurrent() - self.fetchStart);
    if (self.hasCompleted) return;
    self.hasCompleted = YES;
    if (self.completion) self.completion(html, code);
    self.retries = 0;
}

- (void)handleRenderedHTML:(NSString *)html {
    if (!html.length) { [self ddFinishWithHTML:nil code:-2]; return; }

    // HTML 转义还原，必须逐条替换（否则 https:\u002F 会被弄乱，playwm 正则匹配不上）
    NSMutableString *clean = [NSMutableString stringWithString:html];
    NSRange full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\u0026" withString:@"&" options:NSLiteralSearch range:full];   // \u0026 -> &
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"amp;" withString:@"" options:NSLiteralSearch range:full];        // &amp; -> &
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\u002F" withString:@"/" options:NSLiteralSearch range:full];    // \u002F -> /
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\\/" withString:@"/" options:NSLiteralSearch range:full];         // \/ -> /（兜底）
    full = NSMakeRange(0, clean.length);
    [clean replaceOccurrencesOfString:@"\u001D" withString:@"" options:NSLiteralSearch range:full];       // 控制字符 0x1D

    // 图集特征检测
    NSInteger code = ([clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"])
                   ? DDPCodeGallery : 0;
    DDDLog(@"[DDPWebFetcher] 第%u轮 cleanLen=%lu playwm=%d gallery=%d 距开始%.1fs",
           self.retries, (unsigned long)clean.length, [clean containsString:@"playwm"],
           code == DDPCodeGallery, CFAbsoluteTimeGetCurrent() - self.fetchStart);


    // 命中 playwm/图集即成功
    if (code == DDPCodeGallery || [clean containsString:@"playwm"]) {
        DDDLog(@"[DDPWebFetcher] 命中成功 retries=%u（%@）", self.retries, self.retries ? @"重试有效" : @"首轮即命中");
        [self ddFinishWithHTML:clean code:code];
        return;
    }
    // 重载拿回完全相同的 HTML：再试也不会有新内容，直接收尾。
    // （实测：同一页面重载 11 次返回的是同一份 HTML，纯空转 150s 才失败）
    if (self.lastCleanLen == clean.length) {
        DDDLog(@"[DDPWebFetcher] 与上一轮 HTML 完全相同(%lu)且无 playwm，停止重试", (unsigned long)clean.length);
        [self ddFinishWithHTML:nil code:500];   // 已判定拿不到直链，传 nil 免得下游再跑一遍正则
        return;
    }
    self.lastCleanLen = clean.length;
    if (self.retries < DDPMaxRetries) {
        self.retries += 1;
        DDDLog(@"[DDPWebFetcher] 未命中，第%u次重试 距开始%.1fs", self.retries, CFAbsoluteTimeGetCurrent() - self.fetchStart);
        [self.webView loadRequest:self.ddpRequest];
        return;
    }
    DDDLog(@"[DDPWebFetcher] 重试%ld次仍未命中 playwm url=%@", (long)DDPMaxRetries, self.ddpRequest.URL);
    [self ddFinishWithHTML:nil code:500];
}

- (WKWebView *)webView {
    return _webView;
}

@end

#pragma mark - 解析引擎：抓官方分享页 HTML → 按内容类型提取直链（纯本机，不依赖任何第三方接口）

// 内容类型：视频 / 图文(图集) / 滑块(幻灯片)
typedef NS_ENUM(NSInteger, DDPMediaType) {
    DDPMediaTypeUnknown = -1,
    DDPMediaTypeVideo   = 0,
    DDPMediaTypeImage   = 1,
};

@interface DDPEngine : NSObject
+ (instancetype)shared;
// 始终返回在线直链：视频→videoURL；图文/滑块→imageURLs。绝不返回本地缓存路径
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion;
- (NSData *)downloadVideoFromURL:(NSString *)url;
@end

@implementation DDPEngine

+ (instancetype)shared {
    static DDPEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 视频：正则抠 playwm 直链并去水印、去重
- (NSArray<NSString *> *)extractVideoLinksFromHTML:(NSString *)html {
    if (!html.length) return @[];

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+"
                                                                          options:NSRegularExpressionCaseInsensitive error:nil];
    if (!re) return @[];
    NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        NSString *u = [html substringWithRange:m.range];
        u = [u stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        if ([u containsString:@"video_id=https:"]) continue;                     // 跳过 video_id=https:
        NSString *clean = DDPRemoveWatermark(u);                                  // 去水印
        if (clean.length && ![result containsObject:clean]) [result addObject:clean];
    }
    DDDLog(@"extractVideoLinks: 候选数=%lu 首个=%@", (unsigned long)result.count, result.firstObject);
    return [result copy];
}

// 图文/滑块：抠图集与幻灯片图片（两段正则）
- (NSArray<NSString *> *)extractGalleryImagesFromHTML:(NSString *)html {
    if (!html.length) return @[];
    NSMutableArray *result = [NSMutableArray array];
    // 1) 图集：class 含 gallery-container ... __carousel__image（options=1 忽略大小写）
    NSRegularExpression *re1 = [NSRegularExpression
        regularExpressionWithPattern:@"<img[^>]*src=\"([^\"]+)\"[^>]*class=\"[^\"]*gallery-container[^\"]*__carousel__image[^\"]*\""
        options:NSRegularExpressionCaseInsensitive error:nil];
    // 2) 滑块/幻灯片：aweme-slides-swiper-item 内的 img（options=9 含 DotMatchesLineSeparators，让 .*? 跨换行）
    NSRegularExpression *re2 = [NSRegularExpression
        regularExpressionWithPattern:@"<div[^>]*class=\"aweme-slides-swiper-item[^>]*>.*?<img[^>]*src=\"([^\"]+)\""
        options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators) error:nil];
    for (NSRegularExpression *re in @[re1, re2]) {
        if (!re) continue;
        NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
        for (NSTextCheckingResult *m in matches) {
            if (m.numberOfRanges < 2) continue;
            NSString *u = [html substringWithRange:[m rangeAtIndex:1]];
            u = [u stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
            if (u.length && ![result containsObject:u]) [result addObject:u];
        }
    }
    DDDLog(@"extractGalleryImages: 候选数=%lu", (unsigned long)result.count);
    return [result copy];
}

// 解析入口：本机 WKWebView 抓官方分享页 → 按内容类型提取直链（不命中本地缓存，始终返回在线直链）
- (void)parseDouyinURL:(NSString *)url
            completion:(void (^)(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err))completion {
    if (!url.length) { if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-1 userInfo:nil]); return; }

    __weak typeof(self) wself = self;
    [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSInteger errCode) {
        __strong typeof(self) sself = wself;
        if (!sself) return;
        DDDLog(@"parseDouyinURL 回调: htmlLen=%lu errCode=%ld 线程=%@",
               (unsigned long)(html ? html.length : 0), (long)errCode,
               [NSThread isMainThread] ? @"main" : @"bg");
        if (!html.length) {
            if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-2 userInfo:nil]);
            return;
        }
        NSArray *videos = [sself extractVideoLinksFromHTML:html];
        if (videos.count) {
            if (completion) completion(DDPMediaTypeVideo, videos.firstObject, nil, nil);
            return;
        }
        NSArray *images = [sself extractGalleryImagesFromHTML:html];
        if (images.count) {
            if (completion) completion(DDPMediaTypeImage, nil, images, nil);
            return;
        }
        if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
    }];
}

// 同步下载（带信号量阻塞等待）
- (NSData *)downloadVideoFromURL:(NSString *)url {
    if (!url.length) return nil;

    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    if (!nsurl) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";

    [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    [request setValue:url forHTTPHeaderField:@"Referer"];
    [request setValue:@"strict-origin-when-cross-origin" forHTTPHeaderField:@"Referrer-Policy"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];

    // 微信 UA（CUtility GetMMUserAgent）
    NSString *ua = [%c(CUtility) GetMMUserAgent];
    [request setValue:(ua.length ? ua : @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15") forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data) result = data;
        dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    return result;
}

@end

#pragma mark - 面板展示

// 一次性放行标志：防「直接发送」重发被自己拦截
static BOOL gDDPDyTcEnable;

// 取 CMessageMgr（优先 activeUserContext）
static CMessageMgr *DDPMessageMgr(void) {
    MMContext *ctx = [%c(MMContext) activeUserContext];
    if (ctx) return [ctx getService:%c(CMessageMgr)];
    return [[(MMContext *)[%c(MMContext) currentContext] serviceCenter] getService:%c(CMessageMgr)];
}

// 取当前会话名：在 VC 树里找 BaseMsgContentViewController（聊天界面）取其会话名
static NSString *DDPCurrentChatName(void) {
    UIWindow *window = DDPKeyWindow();
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    NSMutableArray *stack = [NSMutableArray array];
    if (vc) [stack addObject:vc];
    while (stack.count) {
        UIViewController *cur = stack.firstObject;
        [stack removeObjectAtIndex:0];
        // 聊天界面就是 BaseMsgContentViewController，直接按类匹配（不再靠 respondsToSelector 泛化判断）
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
    if (!content.length || !user.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        gDDPDyTcEnable = NO;
        CMessageWrap *wrap = [[%c(CMessageWrap) alloc] initWithMsgType:1];
        wrap.m_nsFromUsr   = [%c(SettingUtil) getLocalUsrName:0];   // 本机 wxid
        wrap.m_nsToUsr     = user;
        wrap.m_uiStatus    = 4;
        wrap.m_nsContent   = content;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];
        CMessageMgr *mgr = DDPMessageMgr();
        gDDPDyTcEnable = YES;                                  // 一次性放行，避免重发被拦截
        [mgr AddMsg:user MsgWrap:wrap];
    });
}

// DDPPanel 接口声明
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

// 用微信原生 WCActionSheet 展示解析选项（底部动作面板，按钮回调走 block）
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    if (!content.length) return NO;
    NSString *url = DDPExtractURL(content);
    if (!url.length) return NO;

    UIViewController *top = DDPKeyWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) return NO;

    WCActionSheet *sheet = [[%c(WCActionSheet) alloc] initWithTitle:@"抖音解析" cancelButtonTitle:@"取消"];
    if (!sheet) return NO;

    [sheet addButtonWithTitle:@"直接发送" eventAction:^{ [DDPPanel handleDirectSend:content user:user]; }];
    [sheet addButtonWithTitle:@"解析发送" eventAction:^{ [DDPPanel handleParseSend:url user:user]; }];
    [sheet addButtonWithTitle:@"解析预览" eventAction:^{ [DDPPanel handleParsePreview:url fromVC:top]; }];
    [sheet addButtonWithTitle:@"解析链接" eventAction:^{ [DDPPanel handleParseLink:url user:user]; }];
    [sheet addButtonWithTitle:@"保存相册" eventAction:^{ [DDPPanel handleSaveAlbum:url]; }];

    [sheet showInView:DDPKeyWindow()];
    return YES;
}

// 直接发送
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user {
    if (!content.length) return;
    gDDPDyTcEnable = YES;              // 先置位，确保重发不会被自己再次拦截
    DDPSendTextMsg(content, user);
}

// 解析发送
+ (void)handleParseSend:(NSString *)url user:(NSString *)user {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) {
            DDPShowError(@"解析失败");
            return;
        }
        // 下载+发送结束收起加载转圈（不再弹"解析成功"对勾）
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            [self sendVideoForURL:videoURL shareURL:url user:user finish:finish];
        } else {
            [self sendImagesForURLs:imageURLs user:user finish:finish];   // 图文/滑块：下载直链逐张发进聊天
        }
    }];
}

// 下载视频直链并发到聊天
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)url user:(NSString *)user finish:(void(^)(void))finish {
    if (!videoURL.length) { DDDLog(@"sendVideoForURL: videoURL 为空，直接结束"); if (finish) finish(); return; }
    NSString *path = DDPTempPath(url);
    DDDLog(@"sendVideoForURL: 开始下载 → %@", path);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
        BOOL ok = NO;
        if (data.length) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
            ok = [data writeToFile:path atomically:YES];
            DDDLog(@"sendVideoForURL: 下载完成 size=%lu ok=%d", (unsigned long)data.length, ok);
        } else {
            DDDLog(@"sendVideoForURL: 下载失败，data 为空");
        }
        if (!ok) {
            DDDLog(@"sendVideoForURL: 下载/写文件失败，提示并收起转圈");
            DDPShowError(@"解析失败");
            return;
        }
        // 下载完成即收起转圈（发送交给微信，不再等缩略图生成/AddVideoMsg）；随后异步触发发送
        DDDLog(@"sendVideoForURL: 下载完成，收起转圈并触发发送 → %@", path);
        if (finish) finish();
        [DDPPanel sendVideoAtPath:path toUser:user];
    });
}

// 下载图片直链并批量存相册（图文/滑块，纯本机官方直链）
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls finish:(void(^)(void))finish {
    if (!urls.count) { if (finish) finish(); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSInteger total = 0, done = 0, failed = 0;
        dispatch_queue_t q = dispatch_queue_create("ddp.save", DISPATCH_QUEUE_SERIAL);
        for (NSString *imgURL in urls) {
            NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
            if (!data.length) { DDDLog(@"downloadAndSaveImages: 下载失败跳过"); continue; }
            NSString *ext = DDPImageExt(imgURL);   // 取 URL 后缀作为临时文件扩展名
            NSString *path = DDPTempPathExt(imgURL, ext);
            DDDLog(@"下载开始(存相册图): %@ ext=%@", [path lastPathComponent], ext);
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
            if ([data writeToFile:path atomically:YES]) {
                total++;
                [DDPPanel saveImageToAlbumAtPath:path completion:^(BOOL success) {
                    dispatch_async(q, ^{
                        done++;
                        if (!success) failed++;
                        if (done < total) return;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (failed == 0) DDPShowDone(@"保存成功");
                            else if (failed < total) DDPShowDone(@"部分保存成功");
                            else DDPShowError(@"保存失败");
                        });
                    });
                }];
            }
        }
        // 全部下载失败（无保存动作）：仅收起转圈，避免卡死
        if (total == 0) { if (finish) finish(); }
    });
}

// 生成视频缩略图：AVAssetImageGenerator 取第 0.5s 帧 → JPEG 写临时目录 thumb_<UUID>.jpg → 返回路径
+ (NSString *)generateThumbnailForVideoPath:(NSString *)path {
    if (!path.length) return nil;
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVAsset assetWithURL:[NSURL fileURLWithPath:path]]];
    gen.appliesPreferredTrackTransform = YES;
    // CMTimeMake(1,2) = 0.5s
    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 2) actualTime:NULL error:NULL];
    if (!cg) return nil;
    NSData *jpg = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.5);   // 压缩质量 0.5
    CGImageRelease(cg);
    if (!jpg.length) return nil;
    NSString *thumbPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.jpg", [[NSUUID UUID] UUIDString]]];
    [jpg writeToFile:thumbPath atomically:YES];
    return thumbPath;
}

// 纯色兜底缩略图：generateThumbnailForVideoPath 取不到帧（超短视频）时，
// 写入一张纯色 JPEG，避免 VideoInfo.thumb_path 为空（参考 WeChatDouyinParser DYWriteFallbackThumb）。
+ (NSString *)fallbackThumbnailAtPath:(NSString *)videoPath {
    if (!videoPath.length) return nil;
    NSString *thumbPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.jpg", [[NSUUID UUID] UUIDString]]];
    CGSize size = CGSizeMake(360, 640);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [[UIColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.75);
    if (jpeg.length && [jpeg writeToFile:thumbPath atomically:YES]) return thumbPath;
    return nil;
}

// 发视频消息
// 流程：主线程 → 生成（取不到帧则纯色兜底）缩略图 → alloc CaptureVideoInfo + AVFoundation 读元数据并手动 set 全部属性
//       → 优先 BaseMsgContentLogicController.AddVideoMsg（与发图一致，自动刷新 UI），回退 CMessageMgr.AddVideoMsg。
// 注意：不走 CaptureVideoInfo 的 genVideoInfoWithVideoUrl: 工厂方法（其内部期望远程 URL 自行探测，传本地 fileURL 会属性不全→发送崩溃）。
//       AddVideoMsg: 第一个参数仍是【发送方】本机 wxid。
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) { DDDLog(@"sendVideoAtPath: path 为空，返回"); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) { DDDLog(@"sendVideoAtPath: chatName 为空，返回"); return; }
        DDDLog(@"sendVideoAtPath: 进入发送 path=%@ chat=%@", path, chatName);

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) { DDDLog(@"sendVideoAtPath: 文件不存在，返回"); return; }

        // 缩略图：取第 0.3s 帧，取不到（超短视频）则纯色兜底
        NSString *thumbPath = [self generateThumbnailForVideoPath:path];
        if (!thumbPath) thumbPath = [self fallbackThumbnailAtPath:path];
        DDDLog(@"sendVideoAtPath: 缩略图=%@", thumbPath ?: @"nil");

        // 手动构造 CaptureVideoInfo（参考 WeChatDouyinParser，不走 genVideoInfoWithVideoUrl:，
        // 该方法内部期望远程 URL 自行探测，传本地 fileURL 会导致属性不全进而发送崩溃）。
        id info = [[%c(CaptureVideoInfo) alloc] init];
        if (!info) { DDDLog(@"sendVideoAtPath: CaptureVideoInfo alloc 失败，返回"); return; }

        // AVFoundation 读视频元数据
        unsigned long long fileSize = 0;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs) fileSize = [attrs fileSize];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        Float64 seconds = CMTimeGetSeconds(asset.duration);
        if (!(seconds > 0)) seconds = 1;   // 覆盖 NaN 与 <=0
        unsigned int width = 0, height = 0;
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count) {
            AVAssetTrack *track = tracks.firstObject;
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
        DDDLog(@"sendVideoAtPath: VideoInfo 构造完成 size=%llu dur=%.1f %ux%u", fileSize, seconds, width, height);

        NSString *from = [%c(SettingUtil) getLocalUsrName:0];
        // 优先走 BaseMsgContentLogicController（与发图片一致，发送后自动刷新 UI），失败回退 CMessageMgr
        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        if (ctrl) {
            DDDLog(@"sendVideoAtPath: 走 logicController.AddVideoMsg");
            [ctrl AddVideoMsg:from ToUsr:chatName VideoInfo:info];
        } else {
            CMessageMgr *msgMgr = DDPMessageMgr();
            DDDLog(@"sendVideoAtPath: 走 CMessageMgr.AddVideoMsg");
            [msgMgr AddVideoMsg:from ToUsr:chatName VideoInfo:info];
        }
        DDDLog(@"sendVideoAtPath: AddVideoMsg 完成");
    });
}

// 发图片消息（CMessageMgr AddMsg:MsgWrap:；wrap 由 BaseMsgContentLogicController.FormImageMsg:withImage:withData: 构造）
+ (void)sendImageAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) { DDDLog(@"sendImageAtPath: path 为空，返回"); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) { DDDLog(@"sendImageAtPath: chatName 为空，返回"); return; }
        DDDLog(@"sendImageAtPath: 进入发送 path=%@ chat=%@", path, chatName);

        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image) { DDDLog(@"sendImageAtPath: 读图失败 path=%@", path); return; }
        NSData *data = UIImagePNGRepresentation(image);
        if (!data.length) return;

        BaseMsgContentLogicController *ctrl = [[%c(BaseMsgContentLogicController) alloc] init];
        CMessageWrap *wrap = [ctrl FormImageMsg:chatName withImage:image withData:data];

        // 写入原图扩展信息（m_extendInfoWithMsgType → setImage:withData:isOriginImage:YES）
        id<DDPMsgExtendOperation> ext = [wrap m_extendInfoWithMsgType];
        [ext setImage:image withData:data isOriginImage:YES];

        CMessageMgr *mgr = DDPMessageMgr();
        [mgr AddMsg:chatName MsgWrap:wrap];   // 图片 type=3，不会命中抖音面板拦截
        DDDLog(@"sendImageAtPath: AddMsg 完成 chat=%@", chatName);
    });
}

// 下载图片直链并逐张发进聊天（图文/滑块，纯本机官方直链）
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls user:(NSString *)user finish:(void(^)(void))finish {
    if (!urls.count) { if (finish) finish(); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL anySent = NO;
        for (NSString *imgURL in urls) {
            @autoreleasepool {
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
                if (!data.length) { DDDLog(@"sendImagesForURLs: 下载失败跳过"); continue; }
                NSString *ext = DDPImageExt(imgURL);   // 取 URL 后缀作为临时文件扩展名
                NSString *path = DDPTempPathExt(imgURL, ext);
                DDDLog(@"下载开始(发图): %@ ext=%@", [path lastPathComponent], ext);
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                if ([data writeToFile:path atomically:YES]) {
                    DDDLog(@"sendImagesForURLs: 写文件成功，触发发送 %@", [path lastPathComponent]);
                    [DDPPanel sendImageAtPath:path toUser:user];
                    anySent = YES;
                } else {
                    DDDLog(@"sendImagesForURLs: 写文件失败 %@", [path lastPathComponent]);
                }
            }
        }
        // 全部下载/发送失败才提示；部分成功则静默（已发的留下），仅收起转圈
        if (!anySent) DDPShowError(@"解析失败");
        else if (finish) finish();
    });
}

// 解析预览：视频→系统 AVPlayerViewController 播放；图文/滑块→下载后系统 QL 预览
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) {
            DDPShowError(@"解析失败");
            return;
        }
        // 下载结束收起加载转圈（不再弹"解析成功"对勾）
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            NSString *path = DDPTempPath(url);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDDLog(@"下载开始(预览视频): %@", [path lastPathComponent]);
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
                if (data.length) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    [data writeToFile:path atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^{ [DDPPanel playVideoAtPath:path fromVC:vc]; });
                }
                finish();
            });
        } else {
            [DDPPanel downloadImagesLocally:imageURLs completion:^(NSArray<NSString *> *paths) {
                if (!paths.count) { finish(); return; }
                [DDPPanel presentImageViewer:paths fromVC:vc];
                finish();
            }];
        }
    }];
}

// 视频预览：用系统 AVPlayerViewController 播放本地 mp4（iOS 14+ 画中画自动支持，无需手动开启）
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc {
    if (!path.length || !vc) return;
    AVPlayerViewController *player = [[AVPlayerViewController alloc] init];
    player.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    [vc presentViewController:player animated:YES completion:nil];
}

// 下载图片直链到本地缓存（供"直接观看"，不存相册；复用 MD5 缓存）
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion {
    if (!urls.count) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[]); }); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *out = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *imgURL in urls) {
            NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL];
            NSString *ext = DDPImageExt(imgURL);   // 取 URL 后缀作为临时文件扩展名
            NSString *path = DDPTempPathExt(imgURL, ext);
            DDDLog(@"下载开始(本地看图): %@ ext=%@", [path lastPathComponent], ext);
            if (data.length) {
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                [data writeToFile:path atomically:YES];
            }
            if ([fm fileExistsAtPath:path]) [out addObject:path];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(out); });
    });
}

// 直接观看图片：用系统 QLPreviewController 预览本地图片（多图左右滑切换、捏合缩放均由系统处理）
// 保存走 QL 系统分享菜单，故不再提供自定义"保存"按钮
+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc {
    if (!paths.count || !vc) return;
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    DDPImageQLSource *src = [[DDPImageQLSource alloc] init];
    src.paths = paths;
    ql.dataSource = src;
    // QLPreviewController.dataSource 为 assign（非 weak），用关联对象强持有 src，避免释放后野指针
    objc_setAssociatedObject(ql, kDDPImageQLSourceKey, src, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc presentViewController:ql animated:YES completion:nil];
}

// 解析链接：把提取到的直链以文本消息发出
// 视频→发无水印直链；图文/滑块→发图片直链（每行一张）
+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || type == DDPMediaTypeUnknown) { DDPShowError(@"解析失败"); return; }
            DDPHideLoading();
            NSString *link = (type == DDPMediaTypeVideo)
                ? videoURL
                : [imageURLs componentsJoinedByString:@"\n"];
            if (!link.length) return;
            NSString *target = user.length ? user : DDPCurrentChatName();
            if (target.length) DDPSendTextMsg(link, target);   // 原始直链以文本消息发出
        });
    }];
}

// 保存相册：视频→存视频；图文/滑块→下载存图片
+ (void)handleSaveAlbum:(NSString *)url {
    DDPShowLoading(@"正在解析…");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        if (err || type == DDPMediaTypeUnknown) {
            DDPShowError(@"解析失败");
            return;
        }
        // 下载结束收起加载转圈（不再弹"解析成功"对勾）
        void (^finish)(void) = ^{ DDPHideLoading(); };
        if (type == DDPMediaTypeVideo) {
            NSString *path = DDPTempPath(url);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDDLog(@"下载开始(存相册视频): %@", [path lastPathComponent]);
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL];
                BOOL ok = NO;
                if (data.length) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    ok = [data writeToFile:path atomically:YES];
                }
                if (ok) {
                    [DDPPanel saveVideoToAlbumAtPath:path completion:^(BOOL success) {
                        if (success) DDPShowDone(@"保存成功");
                        else DDPShowError(@"保存失败");
                    }];
                } else {
                    DDDLog(@"handleSaveAlbum: 视频下载/写文件失败，提示并收起转圈");
                    DDPShowError(@"解析失败");
                }
            });
        } else {
            [self downloadAndSaveImages:imageURLs finish:finish];
        }
    }];
}

// 保存到相册（视频）
+ (void)saveVideoToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            if (completion) completion(NO);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) {
            if (completion) completion(success);
        }];
    }];
}

// 保存到相册（图片，图文/滑块）
// 直接写原始字节 addResourceWithType:data:（不经 UIImage 解码，避免无谓重编码）。
// 原 creationRequestForAssetFromImageData: 在 iOS 15 废弃、新 SDK 已移除，改用更稳的 creationRequestForAsset + addResource。
+ (void)saveImageToAlbumAtPath:(NSString *)path completion:(void(^)(BOOL success))completion {
    if (!path.length) { if (completion) completion(NO); return; }
    NSData *data = [NSData dataWithContentsOfFile:path];   // 读原始字节，避免经 UIImage 解码丢帧
    if (!data.length) { if (completion) completion(NO); return; }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            if (completion) completion(NO);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            [req addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];  // 直接写原始字节
            req.creationDate = [NSDate date];   // 写入创建时间为当前时间
        } completionHandler:^(BOOL success, NSError *error) {
            if (!success) DDDLog(@"saveImageToAlbumAtPath: 写相册失败: %@", error);
            if (completion) completion(success);
        }];
    }];
}

@end

#pragma mark - Hook：长按菜单「解析 / 预览」（参考 DD语音包：hook 单元格 operationMenuItems）

// 从 cell 取当前消息内容（type 1 用 m_nsContent，否则 m_nsTitle）
static NSString *ddp_cellContent(id cell) {
    id viewModel = [(id)cell valueForKey:@"viewModel"];
    CMessageWrap *wrap = viewModel ? [viewModel valueForKey:@"messageWrap"] : nil;
    if (!wrap) return nil;
    return (wrap.m_uiMessageType == 1) ? wrap.m_nsContent : wrap.m_nsTitle;
}

// 注入菜单项（参考 DD语音包 ddvp_inject_item：svg 图标 + 标题，一级平铺项）。已注入则跳过。
// 去重标记用 action 派生的 userInfo：MMMenuItem 没有 title/action 的 getter，只能用 userInfo 做记号。
static NSArray *ddp_inject_item(id cell, NSArray *original, BOOL enabled, NSString *title, NSString *svgName, SEL action, long long menuType) {
    if (!enabled) return original;
    NSString *token = [@"ddp:" stringByAppendingString:NSStringFromSelector(action)];
    for (MMMenuItem *it in original) {
        id ui = [it userInfo];
        if ([ui isKindOfClass:[NSString class]] && [(NSString *)ui isEqualToString:token]) return original;
    }
    MMMenuItem *item = [[%c(MMMenuItem) alloc] initWithTitle:title
                                                svgName:svgName
                                                 target:cell
                                                 action:action];
    if (!item) return original;
    [item setUserInfo:token];
    [item setMenuType:menuType];
    NSMutableArray *items = [NSMutableArray arrayWithArray:original];
    [items addObject:item];
    return items;
}

// 必须 hook 具体 cell 子类，不能 hook 基类：operationMenuItems 被 70+ 个 cell 子类
// 各自实现且大多不调 super（TextMessageCellView.h:46 有自己的声明），
// 挂在 BaseMessageCellView 上不会触发。参考 DD语音包 hook VoiceMessageCellView。
%hook TextMessageCellView

- (id)operationMenuItems {
    NSArray *items = %orig;
    NSString *content = ddp_cellContent(self);
    BOOL enabled = DDPConfig.shared.enabled && content.length
                   && DDPContainsDouyinLink(content) && !DDPIsDouyinLiveText(content);
    DDDLog(@"operationMenuItems: 原生项=%lu 命中抖音=%d", (unsigned long)items.count, enabled);
    items = ddp_inject_item(self, items, enabled, @"解析", @"icons_filled_search", @selector(ddp_onParse:), 1010);
    items = ddp_inject_item(self, items, enabled, @"预览", @"icons_filled_play", @selector(ddp_onPreview:), 1011);
    return items;
}

// 给新 selector 放行（参考 DD语音包 canPerformAction）
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(ddp_onParse:) || action == @selector(ddp_onPreview:)) {
        NSString *content = ddp_cellContent(self);
        return DDPConfig.shared.enabled && content.length
               && DDPContainsDouyinLink(content) && !DDPIsDouyinLiveText(content);
    }
    BOOL origResult = %orig;
    return origResult;
}

%new
- (void)ddp_onParse:(id)sender {
    if (!DDPConfig.shared.enabled) return;
    NSString *url = DDPExtractURL(ddp_cellContent(self));
    if (!url.length) return;
    [DDPPanel handleParseSend:url user:DDPCurrentChatName()];
}

%new
- (void)ddp_onPreview:(id)sender {
    if (!DDPConfig.shared.enabled) return;
    NSString *url = DDPExtractURL(ddp_cellContent(self));
    if (!url.length) return;
    UIResponder *responder = (UIResponder *)self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            [DDPPanel handleParsePreview:url fromVC:(UIViewController *)responder];
            return;
        }
    }
}

%end

#pragma mark - Hook：CMessageMgr AddMsg（弹面板的真正入口）

// 弹面板真正入口：仅处理自己发出的消息，命中抖音链接则弹面板并拦截（不调 %orig）；
// 「直接发送」先置 gDDPDyTcEnable，入口见该标志即一次性放行。
%hook CMessageMgr

- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap {
    // 诊断日志
    if (wrap) {
        NSString *c = wrap.m_nsContent;
        DDDLog(@"AddMsg: type=%u from=%@ to=%@ content=%@",
               (unsigned int)wrap.m_uiMessageType, wrap.m_nsFromUsr, wrap.m_nsToUsr,
               c.length > 120 ? [c substringToIndex:120] : c);
    }
    do {
        if (!DDPConfig.shared.enabled || !wrap) break;

        // 发送方判定
        if (!DDPIsOutgoing(wrap)) break;          // 仅自己发出的消息
        // 允许文本(1)/链接卡片(49)/其他(62)，避免漏抓
        unsigned int ddMT = wrap.m_uiMessageType;
        if (ddMT != 1 && ddMT != 49 && ddMT != 62) break;

        // 一次性放行标志：入口闸门前读取并复位，再判抖音（复位须在检测前，否则会残留）
        BOOL bypassOnce = gDDPDyTcEnable;
        gDDPDyTcEnable = NO;
        if (bypassOnce) {
            DDDLog(@"AddMsg: 一次性放行（DyTcEnable 已复位）usr=%@", usr);
            break;
        }

        // 链接卡片(49/62)取 m_nsContent 或 m_nsTitle
        NSString *rawContent = wrap.m_nsContent;
        NSString *rawTitle   = wrap.m_nsTitle;
        NSString *content = rawContent;
        if (!DDPContainsDouyinLink(content) && DDPContainsDouyinLink(rawTitle)) content = rawTitle;
        if (!DDPContainsDouyinLink(content)) break;              // 三串抖音检测
        if (DDPIsDouyinLiveText(content)) break;                 // 排除直播（短链无日期）

        // user 取 AddMsg 首参（会话对象）
        NSString *target = usr.length ? usr : wrap.m_nsToUsr;
        if ([DDPPanel showForContent:content user:target]) {
            DDDLog(@"AddMsg: 命中抖音链接，已弹面板并拦截消息 usr=%@", target);
            return;   // 命中后拦截（不调 %orig）
        }
        // 面板未弹出则放行，避免吞消息
        DDDLog(@"AddMsg: 面板未弹出，放行原发送");
    } while (0);
    %orig;
}

%end


#pragma mark - 设置界面

@interface DDPDouyinParseSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewMgr;
@end

@implementation DDPDouyinParseSettingsViewController

- (void)ensureTableViewMgr {
    if (_tableViewMgr) return;
    _tableViewMgr = [[%c(WCTableViewManager) alloc] initWithFrame:[UIScreen mainScreen].bounds style:UITableViewStyleInsetGrouped];
}

- (instancetype)init {
    if (self = [super init]) { [self ensureTableViewMgr]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD抖音解析";
    [self ensureTableViewMgr];
    if (!_tableViewMgr) return;
    [self buildTable];
    UITableView *tableView = [self.tableViewMgr getTableView];
    self.view.backgroundColor = tableView.backgroundColor;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:tableView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = self.view.safeAreaInsets.top;
    UITableView *tableView = [self.tableViewMgr getTableView];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    tableView.frame = CGRectMake(0, top, w, h - top);
}

- (void)buildTable {
    if (!_tableViewMgr) return;
    [self.tableViewMgr clearAllSection];

    // 解析设置分组
    WCTableViewSectionManager *section = [%c(WCTableViewSectionManager) defaultSection];
    section.headerTitle = @"解析设置";
    [section addCell:[self switchCellWithTitle:@"启用抖音解析" on:DDPConfig.shared.enabled action:@selector(onEnabledSwitch:)]];
    [self.tableViewMgr addSection:section];

    // 日志分组（与总开关无关）
    WCTableViewSectionManager *logSection = [%c(WCTableViewSectionManager) defaultSection];
    logSection.headerTitle = @"日志";
    [logSection addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onExportLog:) target:self title:@"导出日志"]];
    [logSection addCell:[%c(WCTableViewCellManager) normalCellForSel:@selector(onClearLog:) target:self title:@"清空日志"]];
    [self.tableViewMgr addSection:logSection];
    [self.tableViewMgr reloadTableView];
}

- (id)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    return [%c(WCTableViewCellManager) switchCellForSel:action target:self title:title on:on];
}

- (void)onEnabledSwitch:(UISwitch *)sender   { DDPConfig.shared.enabled = sender.isOn; }

// 导出日志（另存 txt 分享）
- (void)onExportLog:(id)sender {
    NSString *log = DDDReadLog();
    if (!log.length) return;
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse_export.txt"];
    [log writeToFile:exportPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    NSURL *url = [NSURL fileURLWithPath:exportPath];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    // iPad 需 popover 锚点
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        avc.popoverPresentationController.sourceView = self.view;
        avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                   CGRectGetMidY(self.view.bounds), 0, 0);
        avc.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:avc animated:YES completion:nil];
}

// 清空日志
- (void)onClearLog:(id)sender {
    DDDClearLog();
}

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
