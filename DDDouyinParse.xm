
// DDDouyinParse：微信抖音链接解析（完整复刻 PKC 实现）。
// 功能：识别消息中的抖音链接，用 WKWebView 渲染抓取页面 HTML，提取无水印视频地址，
//       支持直接发送/解析发送/解析预览/解析链接/保存相册。
// 面板：微信原生底部操作菜单 WCActionSheet（addButtonWithTitle: / setDelegate: / showInView:），按钮点击 delegate 回调，无备用面板。
// 长按菜单：对齐 PKC —— hook BaseMessageCellView canShowForwardMenuItem: 保存当前消息，
//           hook MMMenuController setMenuItems: 追加 MMMenuItem（解析/预览）。
//
// 对齐 PKC 的关键实现：
//   - DDPWebFetcher 复刻 ORZeljybnjfw（WKWebView 渲染抓取，30s 超时，重试循环，GetMMUserAgent）
//   - 解析链复刻 fetchRenderedHTMLContentYl:（缓存→抓 HTML→extractVideoLinksFromHTML→去水印）
//   - 视频提取 extractVideoLinksFromHTML:（正则 playwm、CaseInsensitive、去重、跳过 video_id=https、&amp;→&）
//   - 去水印 removeWatermarkFromVideoURL:（/playwm/→/play/、ratio=\d+p→ratio=1080p）
//   - 缓存 stringToMD5: → %@_1.mp4 存 NSTemporaryDirectory，>2 字节复用
//   - 下载 downloadVideoFromURL:headers:（GetMMUserAgent + Referer=URL + Accept 通配符 + Range bytes=0-）
//   - 保存相册 pkcSaveVideoToAlbum:（PHPhotoLibrary + PHAssetCreationRequest）
//   - 长按菜单 hook MMMenuController setMenuItems:（对齐 PKC）
//   - 面板对齐 PKC：微信原生 WCActionSheet 底部菜单，按钮顺序与 PKC 一致，无备用面板
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonCrypto.h>
#import <AVKit/AVKit.h>
#import <unistd.h>
#import <string.h>

#pragma mark - 文件日志

// 日志写到 App 沙盒 tmp（Filza 可访问），DDDParse.log，便于复现后抓取
static inline NSString *DDDLogPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse.log"];
}
static void DDDWriteLog(NSString *msg) {
    if (!msg.length) return;
    @try {
        NSString *path = DDDLogPath();
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    } @catch (...) {}
}
// 读取日志全文（导出用）
static inline NSString *DDDReadLog(void) {
    @try {
        NSString *path = DDDLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    } @catch (...) { return nil; }
}
// 清空日志文件
static inline void DDDClearLog(void) {
    @try {
        NSString *path = DDDLogPath();
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    } @catch (...) {}
}
// 诊断日志（真机调试用，前缀 [DDDParse]；同时落盘到 DDDParse.log）
#define DDDLog(fmt, ...) do { NSString *__ddds = [NSString stringWithFormat:fmt, ##__VA_ARGS__]; NSLog(@"[DDDParse] %@", __ddds); DDDWriteLog(__ddds); } while (0)

#pragma mark - 微信私有接口声明

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
// 对齐 PKC：判断该消息是否为「自己发出」的（PKC 在 AddMsg hook 里用它区分收/发）
+ (BOOL)isSenderFromMsgWrap:(id)wrap;
@end

// 对齐 PKC sendMsg:toUser:：用 [SettingUtil getLocalUsrName:0] 取本人 wxid
@interface SettingUtil : NSObject
+ (id)getLocalUsrName:(unsigned int)arg1;
@end

@interface BaseMsgContentViewController : UIViewController
- (NSString *)getCurrentChatName;
@end

@interface BaseMsgContentLogicController : NSObject
- (void)SendTextMessage:(NSString *)text;
- (NSString *)getCurrentChatName;
@end

@interface MMServiceCenter : NSObject
- (id)getService:(Class)arg1;
@end

@interface MMContext : NSObject
+ (id)currentContext;
+ (id)activeUserContext;          // 对齐 PKC sendMsg:toUser: 用的是 activeUserContext
- (id)getService:(Class)arg1;     // PKC：[[MMContext activeUserContext] getService:CMessageMgr]
@property (readonly, nonatomic) MMServiceCenter *serviceCenter;
@end

@interface CMessageMgr : NSObject
// 真实签名（微信头）：- (id)AddVideoMsg:ToUsr:VideoInfo: / - (void)AddMsg:MsgWrap:
- (id)AddVideoMsg:(NSString *)path ToUsr:(NSString *)usr VideoInfo:(id)info;
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
@end

// 微信 UA（对齐 PKC 的 CUtility GetMMUserAgent）
@interface CUtility : NSObject
+ (NSString *)GetMMUserAgent;
@end

// 面板使用微信原生底部操作菜单：WCActionSheet（微信 app 内部组件，非系统 UIAlertController）
// WCActionSheet 模拟 UIActionSheet API：addButtonWithTitle: / setDelegate: / showInView:，
// 点击按钮回调 delegate 的 actionSheet:didDismissWithButtonIndex:（兼容 clickedButtonAtIndex:）

// 微信聊天长按消息菜单控制器（对齐 PKC：hook setMenuItems: 追加 MMMenuItem）
@interface MMMenuController : NSObject
+ (instancetype)sharedMenuController;
- (void)setMenuItems:(id)menuItems;
@property (readonly, nonatomic) NSArray *currentMenuItems;
@end

// 微信菜单项（对齐 PKC：用 initWithTitle:icon:target:action: 创建）
@interface MMMenuItem : NSObject
- (instancetype)initWithTitle:(NSString *)title icon:(UIImage *)icon target:(id)target action:(SEL)action;
- (instancetype)initWithTitle:(NSString *)title svgName:(NSString *)svgName target:(id)target action:(SEL)action;
@property (retain, nonatomic) UIImage *iconImage;
@property (nonatomic, weak) id target;
@end

// 微信消息 cell（对齐 PKC：hook canShowForwardMenuItem: 保存当前长按消息）
@interface BaseMessageCellView : UIView
- (BOOL)canShowForwardMenuItem;
@end

#pragma mark - 配置

static NSString * const kDDPEnabledKey = @"DDDouyinParseEnabled";

@interface DDPConfig : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL webFetchEnable;   // 对齐 PKC pkcDyJxHtEnable：走 WKWebView 渲染抓取
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
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kDDPEnabledKey] == nil) {
            _enabled = YES;   // 首次安装默认开启，避免“装了没效果”
            [ud setBool:YES forKey:kDDPEnabledKey];
            DDDLog(@"首次启动，默认开启 enabled=YES");
        } else {
            _enabled = [ud boolForKey:kDDPEnabledKey];
        }
        _webFetchEnable = YES;   // 默认走 WKWebView 渲染抓取（抖音页面需 JS 渲染）
        DDDLog(@"DDPConfig init enabled=%d", _enabled);
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDDPEnabledKey];
}

@end

#pragma mark - 工具函数（对齐 PKC 实现）

// 对齐 PKC MTwkz... 抖音分支（0xfb2d4）：严格只认这三个串
//   containsString:@"douyin.com/video" || @"v.douyin.com" || @"douyin.com/note"
static inline BOOL DDPContainsDouyinLink(NSString *text) {
    if (!text.length) return NO;
    return [text containsString:@"douyin.com/video"]
        || [text containsString:@"v.douyin.com"]
        || [text containsString:@"douyin.com/note"];
}

// 对齐 PKC（0xfb310）：命中"正在直播"直接放行，不弹面板
static inline BOOL DDPIsDouyinLiveText(NSString *text) {
    return text.length && [text containsString:@"正在直播"];
}

// 自包含“是否自己发出的消息”判定：不再硬性依赖 PKC 的 isSenderFromMsgWrap:
//   1) 若该 selector 在运行时存在（微信原生或环境提供），直接采用其结果（与 PKC 一致）；
//   2) 否则比对 m_nsFromUsr 与本机 wxid（SettingUtil getLocalUsrName:0）；
//   3) 仍无法判定时按“已发送”处理，确保能弹面板（抖音链接内容检测会二次过滤，避免误弹）。
// 目的：当 DDDouyinParse 独立安装、isSenderFromMsgWrap: 不存在时，AddMsg 不再因
//      respondsToSelector: 失败而直接 break，导致“发链接永远不弹面板”。
static BOOL DDPIsOutgoing(CMessageWrap *wrap) {
    Class wrapCls = objc_getClass("CMessageWrap");
    if (wrapCls && [wrapCls respondsToSelector:@selector(isSenderFromMsgWrap:)]) {
        @try { return (BOOL)[wrapCls isSenderFromMsgWrap:wrap]; } @catch (...) {}
    }
    Class setCls = objc_getClass("SettingUtil");
    NSString *me = nil;
    if (setCls && [setCls respondsToSelector:@selector(getLocalUsrName:)]) {
        @try { me = [setCls getLocalUsrName:0]; } @catch (...) {}
    }
    NSString *from = nil;
    @try { from = wrap.m_nsFromUsr; } @catch (...) {}
    if (me.length && from.length) return [from isEqualToString:me];
    DDDLog(@"DDPIsOutgoing: 无法判定发送方，按“已发送”处理（wrap=%p from=%@）", wrap, from);
    return YES;
}

// 对齐 PKC getDyUrlFromString: 的正则：https?://[^\s"']+
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

// 对齐 PKC removeWatermarkFromVideoURL:
static inline NSString *DDPRemoveWatermark(NSString *url) {
    if (!url.length) return nil;
    NSString *clean = [url stringByReplacingOccurrencesOfString:@"/playwm/" withString:@"/play/"];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"ratio=\\d+p"
                                                                          options:0
                                                                            error:nil];
    if (re) {
        clean = [re stringByReplacingMatchesInString:clean options:0 range:NSMakeRange(0, clean.length) withTemplate:@"ratio=1080p"];
    }
    return clean;
}

// 对齐 PKC stringToMD5:（自实现 MD5，避免依赖已废弃的 CC_MD5，结果 %02x 小写与 CC_MD5 一致）
// 纯 C MD5 实现（RFC 1321）
static inline uint32_t DDPmd5Rotl(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }

static inline void DDPmd5Block(uint32_t *s, const uint8_t *p) {
    static const uint32_t K[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391};
    static const uint8_t R[64] = {7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
                                  5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
                                  4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
                                  6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21};
    uint32_t a=s[0], b=s[1], c=s[2], d=s[3];
    uint32_t M[16];
    for (int i = 0; i < 16; i++)
        M[i] = (uint32_t)p[i*4] | ((uint32_t)p[i*4+1]<<8) | ((uint32_t)p[i*4+2]<<16) | ((uint32_t)p[i*4+3]<<24);
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if (i < 16)      { f = (b & c) | (~b & d);      g = i; }
        else if (i < 32) { f = (d & b) | (~d & c);      g = (5*i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d;               g = (3*i + 5) % 16; }
        else             { f = c ^ (b | ~d);            g = (7*i) % 16; }
        uint32_t tmp = d;
        d = c; c = b;
        b = b + DDPmd5Rotl(a + f + K[i] + M[g], R[i]);
        a = tmp;
    }
    s[0]+=a; s[1]+=b; s[2]+=c; s[3]+=d;
}

static inline void DDPmd5(const uint8_t *data, size_t len, uint8_t out[16]) {
    uint32_t s[4] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476};
    size_t n = len;
    uint8_t block[64];
    size_t i = 0;
    while (n >= 64) {
        memcpy(block, data + i, 64);
        DDPmd5Block(s, block);
        i += 64; n -= 64;
    }
    size_t rem = len - i;
    memcpy(block, data + i, rem);
    block[rem] = 0x80;
    if (rem >= 56) {
        memset(block + rem + 1, 0, 64 - rem - 1);
        DDPmd5Block(s, block);
        memset(block, 0, 56);
    } else {
        memset(block + rem + 1, 0, 56 - rem - 1);
    }
    uint64_t bitlen = (uint64_t)len * 8;
    for (int j = 0; j < 8; j++) block[56 + j] = (uint8_t)(bitlen >> (j * 8));
    DDPmd5Block(s, block);
    for (int j = 0; j < 4; j++) {
        out[j*4]   = (uint8_t)(s[j]);
        out[j*4+1] = (uint8_t)(s[j] >> 8);
        out[j*4+2] = (uint8_t)(s[j] >> 16);
        out[j*4+3] = (uint8_t)(s[j] >> 24);
    }
}

static inline NSString *DDPMD5(NSString *str) {
    if (!str.length) return nil;
    const char *c = [str UTF8String];
    if (!c) return nil;
    unsigned char digest[16];
    DDPmd5((const uint8_t *)c, strlen(c), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

// 对齐 PKC：%@_1.mp4 存 NSTemporaryDirectory
static inline NSString *DDPTempPath(NSString *url) {
    NSString *md5 = DDPMD5(url);
    if (!md5) return nil;
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1.mp4", md5]];
}

// 获取当前活跃 UIWindowScene 的 keyWindow（iOS 18+，使用 connectedScenes/UIWindowScene，不兼容旧系统）
// 无活跃场景时返回 nil，调用方需判空
static inline UIWindow *DDPKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        if (ws.keyWindow) return ws.keyWindow;
        return ws.windows.firstObject;
    }
    return nil;
}

// 对齐 PKC：文件存在且 >2 字节才复用
static inline BOOL DDPFileUsable(NSString *path) {
    if (!path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return NO;
    NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
    return attr.fileSize > 2;
}

static inline void DDPCopyToPasteboard(NSString *text) {
    if (!text.length) return;
    UIPasteboard.generalPasteboard.string = text;
}

// ---- 微信系统提示（对齐 PKC 截图中的「抖音解析后台任务开始」气泡） ----
// 统一使用微信内部 SystemTipController tipsVC:msg:type:… 在聊天中插入系统提示气泡
// 无备用 HUD Toast；若该 API 不可用则静默落日志（不弹任何 UI）
static inline void DDPShowSystemTip(NSString *msg) {
    if (!msg.length) return;
    static Class tipCls = Nil;
    static SEL tipSel = NULL;
    static BOOL tipChecked = NO;
    if (!tipChecked) {
        tipChecked = YES;
        tipCls = NSClassFromString(@"SystemTipController");
        if (tipCls) tipSel = NSSelectorFromString(@"tipsVC:msg:type:placeholder:defaultText:blk:");
        if (!tipCls || ![tipCls respondsToSelector:tipSel]) {
            Class altCls = NSClassFromString(@"CBaseMsgPackHelper");
            SEL altSel = NSSelectorFromString(@"addSystemTip:toChat:");
            if (altCls && [altCls respondsToSelector:altSel]) { tipCls = altCls; tipSel = altSel; }
            else { tipCls = Nil; tipSel = NULL; }
        }
    }
    if (tipCls && tipSel) {
        DDDLog(@"DDPShowSystemTip: %@ msg=%@", tipCls, msg);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *window = DDPKeyWindow();
            UIViewController *vc = window.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            if (vc) {
                @try {
                    ((void(*)(id, SEL, id, id, NSInteger, NSString *, NSString *, id))objc_msgSend)(tipCls, tipSel, vc, msg, 0, @"", @"", nil);
                } @catch (NSException *e) {
                    DDDLog(@"DDPShowSystemTip: 异常 %@", e);
                }
            }
        });
    } else {
        DDDLog(@"DDPShowSystemTip: 系统提示不可用（静默）msg=%@", msg);
    }
}

#pragma mark - DDPWebFetcher（复刻 PKC ORZeljybnjfw：WKWebView 渲染抓取）

// completion 参数：(html, errCode)。errCode == DDPCodeGallery(16737) 表示图集，
// 否则为 0 表示视频。对齐 PKC webView:didFinishNavigation: 的类型码。
static const NSInteger DDPCodeGallery = 0x4161;   // 16737
static const NSInteger DDPMaxRetries = 11;         // 对齐 PKC：最多重试 11 次，直到渲染 HTML 含 playwm


@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, strong) NSURLRequest *ddpRequest;   // 当前抓取请求（重试 reload 时复用）
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger errCode);
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion;
- (void)cleanupWebView;
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code;   // 统一收尾（仅首次触发）
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
        // 对齐 PKC init：WKWebViewConfiguration + allowsContentJavaScript:YES（替代已废弃的 javaScriptEnabled）
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKWebpagePreferences *pagePrefs = [[WKWebpagePreferences alloc] init];
        pagePrefs.allowsContentJavaScript = YES;
        config.defaultWebpagePreferences = pagePrefs;

        // 对齐 PKC：ORZeljybnjfw 不注入任何脚本，纯靠 WKWebView 渲染后取 outerHTML
        // （PKC 无 XHR/fetch 拦截，仅靠微信 UA + 渲染 HTML 提取 playwm 正则）

        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];

        // 用微信 UA（对齐 PKC：CUtility GetMMUserAgent）。PKC 靠它让抖音返回含 playwm 的真视频页。
        NSString *ua = nil;
        Class cUtil = NSClassFromString(@"CUtility");
        if (cUtil && [cUtil respondsToSelector:@selector(GetMMUserAgent)]) {
            ua = [cUtil GetMMUserAgent];
        }
        if (!ua.length) {
            // 兜底：部分微信版本 GetMMUserAgent 拿不到，用硬编码微信 UA，确保抖音仍返回视频页
            ua = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.40(0x18004025) NetType/WIFI Language/zh_CN";
        }
        DDDLog(@"DDPWebFetcher: 设置 UA=%@", ua);
        if (ua.length) _webView.customUserAgent = ua;

        _webView.navigationDelegate = self;

        // 加到 keyWindow，全屏 frame，初始隐藏（对齐 PKC）
        UIWindow *keyWindow = DDPKeyWindow();
        if (keyWindow) {
            [keyWindow addSubview:_webView];
            _webView.frame = keyWindow.bounds;
        }
        _webView.hidden = YES;
    }
    return self;
}

// 对齐 PKC fetchHTMLFromURL:completion:
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion {
    DDDLog(@"fetchHTMLFromURL: 开始 url=%@ webView=%p delegate=%@ keyWindow=%@",
           url, _webView, _webView.navigationDelegate ? @"Y" : @"N", DDPKeyWindow() ? @"Y" : @"N");
    self.completion = completion;
    self.hasCompleted = NO;

    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        DDDLog(@"fetchHTMLFromURL: URL 非法，直接失败");
        if (completion) completion(nil, -1);
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:30.0];   // 对齐 PKC 30 秒超时

    // 对齐 PKC：读配置 pkcDyJxHtEnable（boolValue），决定是否走 WKWebView 路径
    BOOL webFetch = DDPConfig.shared.webFetchEnable;

    // 对齐 PKC：仅当 webFetch 开启 且 webView 的 navigationDelegate 尚未（重新）设置时，补设 delegate 并加入窗口
    if (webFetch && !_webView.navigationDelegate) {
        _webView.navigationDelegate = self;
        UIWindow *keyWindow = DDPKeyWindow();
        if (keyWindow) {
            [keyWindow addSubview:_webView];
            _webView.frame = keyWindow.bounds;
        }
    }
    _webView.hidden = YES;

    self.ddpRequest = request;
    self.retries = 0;
    // 对齐 PKC：发起首次加载；若渲染 HTML 不含 playwm，由 handleRenderedHTML 递增 retries 并 reload 重试，
    // 直到命中 playwm 或达到 DDPMaxRetries 上限（didFinishNavigation 每次等 (retries+5) 秒给 JS 渲染留时间）。
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadRequest:request];
    });
}

// 对齐 PKC webView:didFinishNavigation:：延迟后取渲染后的 outerHTML
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    DDDLog(@"DDPWebFetcher: didFinishNavigation retries=%u", self.retries);
    __weak typeof(self) wself = self;
    // 对齐 PKC：dispatch_after(retries 秒 + 5 秒)，给 JS 渲染留时间
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)((self.retries * 1.0 + 5.0) * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
            if (error) { DDDLog(@"DDPWebFetcher: evalJS 失败 %@", error); [wself ddFinishWithHTML:nil code:-2]; return; }
            @try {
                [wself handleRenderedHTML:(result ? [NSString stringWithFormat:@"%@", result] : @"")];
            } @catch (NSException *e) {
                DDDLog(@"DDPWebFetcher: handleRenderedHTML 异常 %@", e);
                [wself ddFinishWithHTML:nil code:-2];
            }
        }];
    });
}

// 加载失败 / 进程崩溃：对齐 PKC 缺失的兜底——直接以失败结束，避免反复 loadRequest 引发异常
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

// 统一收尾：仅首次触发，避免重复回调
- (void)ddFinishWithHTML:(NSString *)html code:(NSInteger)code {
    DDDLog(@"ddFinishWithHTML: code=%ld htmlLen=%lu", (long)code, (unsigned long)(html ? html.length : 0));
    if (self.hasCompleted) return;
    self.hasCompleted = YES;
    if (self.completion) self.completion(html, code);
    self.retries = 0;
    [self cleanupWebView];
}

// 对齐 PKC webView:didFinishNavigation: 的 block 内逻辑
- (void)handleRenderedHTML:(NSString *)html {
    if (!html.length) { [self ddFinishWithHTML:nil code:-2]; return; }

    // 对齐 PKC didFinishNavigation block（43490-43530）：先把 JSON/HTML 转义还原，正则才能命中。
    // 关键：PKC 用的是 \u0026->& / amp;->空 / \u002F->/，绝不会"删除所有反斜杠"——
    // 否则 https:\u002F\u002F... 会被弄成 https:u002Fu002F...（双斜杠变单斜杠），playwm 正则永远匹配不上。
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

    DDDLog(@"handleRenderedHTML: cleanLen=%lu 含playwm=%d 含video_id=%d 含swiper=%d",
           (unsigned long)clean.length,
           [clean containsString:@"playwm"],
           [clean containsString:@"video_id="],
           [clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"]);

    // 图集特征检测（对齐 PKC 的类型码判定）
    NSInteger code = 0;
    if ([clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"]) {
        code = DDPCodeGallery;
    }

    // 对齐 PKC：仅当命中 playwm（或图集）才算成功；否则重试，直到 DDPMaxRetries 上限。
    if (code == DDPCodeGallery || [clean containsString:@"playwm"]) {
        [self ddFinishWithHTML:clean code:code];
        return;
    }
    if (self.retries < DDPMaxRetries) {
        self.retries += 1;
        DDDLog(@"handleRenderedHTML: 未命中 playwm，重试 (%u/%d) url=%@", self.retries, DDPMaxRetries, self.ddpRequest.URL);
        [self.webView loadRequest:self.ddpRequest];
        return;
    }
    DDDLog(@"handleRenderedHTML: 重试耗尽仍未命中 playwm url=%@", self.ddpRequest.URL);
    [self ddFinishWithHTML:nil code:500];
}

// 对齐 PKC cleanupWebView
- (void)cleanupWebView {
    _webView.hidden = YES;
}

- (WKWebView *)webView {
    return _webView;
}

@end

#pragma mark - 解析引擎（对齐 PKC fetchRenderedHTMLContentYl: + extractVideoLinksFromHTML: + downloadVideoFromURL:headers:）

@interface DDPEngine : NSObject
+ (instancetype)shared;
- (void)parseDouyinURL:(NSString *)url completion:(void (^)(NSString *videoURL, NSError *err))completion;
- (NSData *)downloadVideoFromURL:(NSString *)url headers:(NSDictionary *)headers;
@end

@implementation DDPEngine

+ (instancetype)shared {
    static DDPEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 对齐 PKC extractVideoLinksFromHTML:（0xe8038）：单一 playwm 正则 → matchesInString 取所有 →
// 遍历每个 URL：&amp;→& 还原（0xe81cc）→ 跳过 video_id=https:（0xe8204）→ removeWatermark 去水印 → 去重
- (NSArray *)extractVideoLinksFromHTML:(NSString *)html {
    if (!html.length) return @[];

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+"
                                                                          options:NSRegularExpressionCaseInsensitive error:nil];
    if (!re) return @[];
    NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        NSString *u = [html substringWithRange:m.range];
        u = [u stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];   // 对齐 PKC e81cc
        if ([u containsString:@"video_id=https:"]) continue;                     // 对齐 PKC e8204
        NSString *clean = DDPRemoveWatermark(u);                                  // /playwm/→/play/ + ratio=1080p
        if (clean.length && ![result containsObject:clean]) [result addObject:clean];
    }
    DDDLog(@"extractVideoLinks: 候选数=%lu 首个=%@", (unsigned long)result.count, result.firstObject);
    return [result copy];
}


// 对齐 PKC fetchRenderedHTMLContentYl:：缓存检查 → WKWebView 抓 HTML → 提取视频链接
- (void)parseDouyinURL:(NSString *)url completion:(void (^)(NSString *videoURL, NSError *err))completion {
    if (!url.length) { if (completion) completion(nil, [NSError errorWithDomain:@"DDP" code:-1 userInfo:nil]); return; }

    // 缓存检查：MD5_1.mp4 >2 字节则直接复用
    NSString *tempPath = DDPTempPath(url);
    if (tempPath && DDPFileUsable(tempPath)) {
        if (completion) completion(tempPath, nil);
        return;
    }

    __weak typeof(self) wself = self;
    [[DDPWebFetcher sharedFetcher] fetchHTMLFromURL:url completion:^(NSString *html, NSInteger errCode) {
        __strong typeof(self) sself = wself;
        if (!sself) return;
        DDDLog(@"parseDouyinURL 回调: htmlLen=%lu errCode=%ld 线程=%@",
               (unsigned long)(html ? html.length : 0), (long)errCode,
               [NSThread isMainThread] ? @"main" : @"bg");
        @try {
            if (!html.length) {
                if (completion) completion(nil, [NSError errorWithDomain:@"DDP" code:-2 userInfo:nil]);
                return;
            }
            NSArray *urls = [sself extractVideoLinksFromHTML:html];
            DDDLog(@"parseDouyinURL: 匹配到视频链接数=%lu", (unsigned long)urls.count);
            if (urls.count == 0) {
                if (completion) completion(nil, [NSError errorWithDomain:@"DDP" code:-3 userInfo:nil]);
                return;
            }
            if (completion) completion(urls.firstObject, nil);
        } @catch (NSException *e) {
            DDDLog(@"parseDouyinURL 异常 %@", e);
            if (completion) completion(nil, [NSError errorWithDomain:@"DDP" code:-5 userInfo:nil]);
        }
    }];
}

// 对齐 PKC downloadVideoFromURL:headers:（GetMMUserAgent + Referer=URL + 同步返回）
- (NSData *)downloadVideoFromURL:(NSString *)url headers:(NSDictionary *)headers {
    if (!url.length) return nil;

    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    if (!nsurl) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";

    // 对齐 PKC：传入 headers 时跳过 user-agent/accept，其余逐一设置
    if (headers.count) {
        [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            NSString *lower = key.lowercaseString;
            if ([lower isEqualToString:@"user-agent"] || [lower isEqualToString:@"accept"]) return;
            [request setValue:value forHTTPHeaderField:key];
        }];
    } else {
        // 对齐 PKC 默认 headers
        [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
        [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
        [request setValue:url forHTTPHeaderField:@"Referer"];
        [request setValue:@"strict-origin-when-cross-origin" forHTTPHeaderField:@"Referrer-Policy"];
    }
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];

    // 微信 UA（对齐 PKC：CUtility GetMMUserAgent）
    NSString *ua = nil;
    Class cUtil = NSClassFromString(@"CUtility");
    if (cUtil && [cUtil respondsToSelector:@selector(GetMMUserAgent)]) {
        ua = [cUtil GetMMUserAgent];
    }
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

// 一次性放行标志：对齐 PKC 的 pkcDyTcEnable
//   拦截前检查（YES 则放行并复位，见 MTwkz 0xf98a4 / 0xf9924）
//   「直接发送」按钮点击时置 YES（对齐 dyzzfs: 0x8a5dc）
static BOOL gDDPDyTcEnable;

// 面板 Data 兜底（对齐 PKC：正常路径从 [sender m_userData] 取 content/user）
static NSString *gDDPPanelContent;
static NSString *gDDPPanelUser;

// 取 CMessageMgr 服务（对齐 PKC：优先 activeUserContext，回退 currentContext）
static CMessageMgr *DDPMessageMgr(void) {
    Class ctxCls = objc_getClass("MMContext");
    Class mgrCls = objc_getClass("CMessageMgr");
    if (!ctxCls || !mgrCls) return nil;
    if ([ctxCls respondsToSelector:@selector(activeUserContext)]) {
        id ctx = [ctxCls activeUserContext];
        if ([ctx respondsToSelector:@selector(getService:)]) {
            CMessageMgr *mgr = [ctx getService:mgrCls];
            if (mgr) return mgr;
        }
    }
    if ([ctxCls respondsToSelector:@selector(currentContext)]) {
        MMContext *ctx = [ctxCls currentContext];
        return [ctx.serviceCenter getService:mgrCls];
    }
    return nil;
}

// 取当前会话名（对齐 PKC：[[pkc pkcBC] getCurrentChatName]，这里用栈顶聊天 VC）
static NSString *DDPCurrentChatName(void) {
    UIWindow *window = DDPKeyWindow();
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    NSMutableArray *stack = [NSMutableArray array];
    if (vc) [stack addObject:vc];
    while (stack.count) {
        UIViewController *cur = stack.firstObject;
        [stack removeObjectAtIndex:0];
        // 对齐 PKC（e4afc getCurrentChatName）：不依赖具体聊天 VC 类名，
        // 只要响应 getCurrentChatName 即取当前会话名（iOS18 类名变化也能命中）
        if ([cur respondsToSelector:@selector(getCurrentChatName)]) {
            NSString *name = (NSString *)[cur performSelector:@selector(getCurrentChatName)];
            if ([name isKindOfClass:NSString.class] && name.length) return name;
        }
        if (cur.childViewControllers.count) [stack addObjectsFromArray:cur.childViewControllers];
        if (cur.presentedViewController) [stack addObject:cur.presentedViewController];
    }
    return nil;
}

// 对齐 PKC sendMsg:toUser:（0x768a0）：自建 CMessageWrap 走 CMessageMgr AddMsg 真正发送
static void DDPSendTextMsg(NSString *content, NSString *user) {
    if (!content.length || !user.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 先清掉调用方的提前置位：真正的放行只在下面 AddMsg 前一行打开，
        // 这样任何失败路径都不会让标志残留（否则下一条真链接会被误放行）
        gDDPDyTcEnable = NO;

        Class wrapCls = objc_getClass("CMessageWrap");
        Class mgrCls  = objc_getClass("CMessageMgr");
        Class ctxCls  = objc_getClass("MMContext");
        Class setCls  = objc_getClass("SettingUtil");
        if (!wrapCls || !mgrCls || !ctxCls) { DDPShowSystemTip(@"发送失败"); return; }

        CMessageWrap *wrap = [[wrapCls alloc] initWithMsgType:1];
        if (!wrap) { DDPShowSystemTip(@"发送失败"); return; }
        if (setCls && [setCls respondsToSelector:@selector(getLocalUsrName:)]) {
            wrap.m_nsFromUsr = [setCls getLocalUsrName:0];   // 对齐 PKC：getLocalUsrName:0
        }
        wrap.m_nsToUsr      = user;
        wrap.m_uiStatus     = 4;                             // 对齐 PKC：m_uiStatus = 4
        wrap.m_nsContent    = content;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];

        // 对齐 PKC：[[MMContext activeUserContext] getService:[CMessageMgr class]]
        CMessageMgr *mgr = nil;
        if ([ctxCls respondsToSelector:@selector(activeUserContext)]) {
            id ctx = [ctxCls activeUserContext];
            if ([ctx respondsToSelector:@selector(getService:)]) mgr = [ctx getService:mgrCls];
        }
        if (!mgr && [ctxCls respondsToSelector:@selector(currentContext)]) {
            MMContext *ctx = [ctxCls currentContext];
            mgr = [ctx.serviceCenter getService:mgrCls];
        }
        if (!mgr) { DDPShowSystemTip(@"发送失败"); return; }

        gDDPDyTcEnable = YES;                                // 一次性放行，避免自己的重发被再次拦截
        [mgr AddMsg:user MsgWrap:wrap];
        DDDLog(@"DDPSendTextMsg: 已发送 user=%@ len=%lu", user, (unsigned long)content.length);
    });
}

// DDPPanel 接口声明（必须先于 DDPPanelHandler，供其回调调用类方法）
@interface DDPPanel : NSObject
// 对齐 PKC tipsTitle:Msg:Type:8：title=@"抖音解析"、message=原文、Data=@{content,user}
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user;
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user;
+ (void)handleParseSend:(NSString *)url user:(NSString *)user force:(BOOL)force;
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc;
+ (void)handleParseLink:(NSString *)url user:(NSString *)user;
+ (void)handleSaveAlbum:(NSString *)url;
// 内部辅助（供上面各 handler 互相调用，需前置声明避免 clang 找不到类方法）
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user;
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc;
+ (void)saveVideoToAlbumAtPath:(NSString *)path;
@end

@interface DDPPanelHandler : NSObject
+ (instancetype)shared;
- (void)onDirectSend:(id)sender;      // 对齐 dyzzfs:
- (void)onParseSend:(id)sender;       // 对齐 dyjxfs:   → pkcDyVideoJx:to:
- (void)onParsePreview:(id)sender;    // 对齐 dyjxyl:   → pkcDyVideoJxYl:
- (void)onParseLink:(id)sender;       // 对齐 dyjxlj:   → pkcDyVideoJx:to:flag:0 type:1
- (void)onSaveAlbum:(id)sender;       // 对齐 dyjxSave: → pkcDyVideoJx:to:flag:0 type:2
- (void)onCancel:(id)sender;
@end

@implementation DDPPanelHandler
+ (instancetype)shared {
    static DDPPanelHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 对齐 PKC：所有按钮回调都从 sender（面板本身）的 m_userData 取 content / user
+ (NSString *)contentFromSender:(id)sender {
    if ([sender respondsToSelector:@selector(m_userData)]) {
        id data = [sender m_userData];
        if ([data respondsToSelector:@selector(valueForKey:)]) {
            NSString *c = [data valueForKey:@"content"];
            if ([c isKindOfClass:NSString.class] && c.length) return c;
        }
    }
    return gDDPPanelContent;
}
+ (NSString *)userFromSender:(id)sender {
    if ([sender respondsToSelector:@selector(m_userData)]) {
        id data = [sender m_userData];
        if ([data respondsToSelector:@selector(valueForKey:)]) {
            NSString *u = [data valueForKey:@"user"];
            if ([u isKindOfClass:NSString.class] && u.length) return u;
        }
    }
    return gDDPPanelUser;
}

- (void)onDirectSend:(id)sender {
    NSString *content = [DDPPanelHandler contentFromSender:sender];
    NSString *user    = [DDPPanelHandler userFromSender:sender];
    [DDPPanel handleDirectSend:content user:user];
}
- (void)onParseSend:(id)sender {
    NSString *url  = DDPExtractURL([DDPPanelHandler contentFromSender:sender]);
    NSString *user = [DDPPanelHandler userFromSender:sender];
    if (url.length) [DDPPanel handleParseSend:url user:user force:NO];
}
- (void)onParsePreview:(id)sender {
    NSString *url = DDPExtractURL([DDPPanelHandler contentFromSender:sender]);
    if (!url.length) return;
    UIWindow *window = DDPKeyWindow();
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [DDPPanel handleParsePreview:url fromVC:topVC];
}
- (void)onParseLink:(id)sender {
    NSString *url  = DDPExtractURL([DDPPanelHandler contentFromSender:sender]);
    NSString *user = [DDPPanelHandler userFromSender:sender];
    if (url.length) [DDPPanel handleParseLink:url user:user];
}
- (void)onSaveAlbum:(id)sender {
    NSString *url = DDPExtractURL([DDPPanelHandler contentFromSender:sender]);
    if (url.length) [DDPPanel handleSaveAlbum:url];
}
- (void)onCancel:(id)sender { /* 对齐 PKC getTipsCancel:：什么都不做，消息已被拦截 */ }

#pragma mark - 微信原生 WCActionSheet delegate（点击底部面板按钮回调）
// WCActionSheet 模拟 UIActionSheetDelegate：两种回调名都实现，覆盖不同微信版本
- (void)actionSheet:(id)sheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [self ddpDispatchButtonIndex:buttonIndex];
}
- (void)actionSheet:(id)sheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    [self ddpDispatchButtonIndex:buttonIndex];
}
- (void)ddpDispatchButtonIndex:(NSInteger)idx {
    // 按钮顺序对齐 PKC：0 直接发送 / 1 解析发送 / 2 解析预览 / 3 解析链接 / 4 保存相册 / 5 取消
    switch (idx) {
        case 0: [self onDirectSend:sheet];   break;
        case 1: [self onParseSend:sheet];    break;
        case 2: [self onParsePreview:sheet]; break;
        case 3: [self onParseLink:sheet];    break;
        case 4: [self onSaveAlbum:sheet];    break;
        default: break; // 取消 / 点遮罩
    }
}
@end

@implementation DDPPanel

// 微信原生底部操作面板：WCActionSheet（微信 app 内部使用的圆角菜单，区别于系统 UIAlertController）
// 5 个操作按钮 + 取消，无「解析转圈」，按钮点击走 WCActionSheet delegate 回 DDPPanelHandler（按 index 分发）
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    if (!content.length) return NO;

    @try {
        UIWindow *window = DDPKeyWindow();
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top) { DDDLog(@"DDPanel: 找不到顶层 VC"); return NO; }

        gDDPPanelContent = content;
        gDDPPanelUser = user;

        // 微信原生面板类 WCActionSheet（微信内部底部菜单组件；无备用 UIAlertController）
        Class wcSheet = NSClassFromString(@"WCActionSheet");
        if (!wcSheet || ![wcSheet instancesRespondToSelector:@selector(addButtonWithTitle:)] ||
            ![wcSheet instancesRespondToSelector:@selector(setDelegate:)] ||
            (![wcSheet instancesRespondToSelector:@selector(showInView:)] &&
             ![wcSheet instancesRespondToSelector:@selector(show)])) {
            DDDLog(@"DDPanel: WCActionSheet 不可用，面板未弹出");
            return NO;
        }

        id sheet = [wcSheet instancesRespondToSelector:@selector(initWithTitle:)]
            ? [[wcSheet alloc] initWithTitle:@"抖音解析"]
            : [[wcSheet alloc] init];
        if (!sheet) { DDDLog(@"DDPanel: WCActionSheet 初始化失败"); return NO; }

        // 按钮顺序对齐 PKC：dyzzfs → dyjxfs → dyjxyl → dyjxlj → dyjxSave → 取消
        [sheet addButtonWithTitle:@"直接发送"];
        [sheet addButtonWithTitle:@"解析发送"];
        [sheet addButtonWithTitle:@"解析预览"];
        [sheet addButtonWithTitle:@"解析链接"];
        [sheet addButtonWithTitle:@"保存相册"];
        [sheet addButtonWithTitle:@"取消"];
        if ([sheet respondsToSelector:@selector(setCancelButtonIndex:)]) {
            [sheet setCancelButtonIndex:5];
        }

        DDPPanelHandler *handler = [DDPPanelHandler shared];
        if ([sheet respondsToSelector:@selector(setDelegate:)]) {
            [sheet setDelegate:(id)handler];
        } else {
            @try { [sheet setValue:handler forKey:@"delegate"]; } @catch (NSException *e) {}
        }

        if ([sheet respondsToSelector:@selector(showInView:)]) {
            [sheet showInView:top.view];
        } else {
            [sheet show];
        }
        DDDLog(@"DDPanel: 微信原生面板已 show user=%@ (WCActionSheet)", user);
        return YES;
    } @catch (NSException *e) {
        DDDLog(@"DDPanel: 异常 %@", e);
        return NO;
    }
}

// 直接发送：对齐 PKC dyzzfs:（0x8a4d0）
//   setPkcDyTcEnable:YES → sendMsg:content toUser:user（自建 CMessageWrap 走 CMessageMgr AddMsg）
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user {
    if (!content.length) return;
    if (!user.length) { DDPShowSystemTip(@"发送失败"); return; }
    gDDPDyTcEnable = YES;              // 先置位，确保重发不会被自己再次拦截
    DDPSendTextMsg(content, user);
}

// 解析发送：对齐 PKC pkcDyVideoJx:to:flag:type:（flag=force 忽略缓存，type=0 发视频）
+ (void)handleParseSend:(NSString *)url user:(NSString *)user force:(BOOL)force {
    DDDLog(@"handleParseSend: 开始 url=%@ user=%@", url, user);
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(NSString *videoURL, NSError *err) {
        @try {
            if (err || !videoURL) {
                DDDLog(@"handleParseSend: 解析失败 url=%@ err=%@", url, err);
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败，请检查网络重试！"); });
                return;
            }
            DDDLog(@"handleParseSend: 解析成功 videoURL=%@ user=%@", videoURL, user);
            NSString *path = DDPTempPath(url);
            // 对齐 PKC（0xe5da8 cbnz flag）：flag=1 时忽略本地缓存，强制重新下载
            if (!force && DDPFileUsable(path)) {
                [DDPPanel sendVideoAtPath:path toUser:user];
                return;
            }
            // 后台队列下载，避免阻塞主线程
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL headers:nil];
                BOOL ok = NO;
                if (data.length) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    ok = [data writeToFile:path atomically:YES];
                }
                if (ok) {
                    [DDPPanel sendVideoAtPath:path toUser:user];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"下载失败"); });
                }
            });
        } @catch (NSException *e) {
            DDDLog(@"handleParseSend 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
        }
    }];
}

// 发送视频消息（对齐 PKC sendVideo:videoPath: → CMessageMgr AddVideoMsg:ToUsr:VideoInfo:）
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 解析完成
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) {
            DDPShowSystemTip(@"发送失败");
            return;
        }
        CMessageMgr *msgMgr = DDPMessageMgr();
        if (msgMgr && [msgMgr respondsToSelector:@selector(AddVideoMsg:ToUsr:VideoInfo:)]) {
            DDPShowSystemTip(@"解析成功，正在发送");
            [msgMgr AddVideoMsg:path ToUsr:chatName VideoInfo:path];
        } else {
            DDPShowSystemTip(@"发送失败");
        }
    });
}

// 解析预览：解析后用 AVPlayer 播放
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(NSString *videoURL, NSError *err) {
        @try {
            if (err || !videoURL) {
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
                return;
            }
            NSString *path = DDPTempPath(url);
            if (DDPFileUsable(path)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 解析完成，播放视频
                    [DDPPanel playVideoAtPath:path fromVC:vc];
                });
                return;
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL headers:nil];
                if (data.length) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    [data writeToFile:path atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // 解析完成，播放视频
                        [DDPPanel playVideoAtPath:path fromVC:vc];
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"下载失败"); });
                }
            });
        } @catch (NSException *e) {
            DDDLog(@"handleParsePreview 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
        }
    }];
}

+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc {
    if (!path.length || !vc) return;
    AVPlayerViewController *player = [[AVPlayerViewController alloc] init];
    player.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    [vc presentViewController:player animated:YES completion:^{ [player.player play]; }];
}

// 解析链接：对齐 PKC dyjxlj: → pkcDyVideoJx:to:flag:0 type:1
//   type==1 分支（0xe6430 → 0xe6774）把解析出的链接通过 sendMsg:toUser: 作为文本消息发到会话；
//   这里同时复制一份到剪贴板，方便用户二次使用（不改变对齐语义）
+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(NSString *videoURL, NSError *err) {
        @try {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err || !videoURL) { DDPShowSystemTip(@"解析失败"); return; }
                // 解析完成
                DDPCopyToPasteboard(videoURL);
                NSString *target = user.length ? user : DDPCurrentChatName();
                if (target.length) {
                    DDPSendTextMsg(videoURL, target);   // 对齐 PKC：链接以文本消息发到会话
                    DDPShowSystemTip(@"已发送解析链接");
                } else {
                    DDPShowSystemTip(@"已复制无水印链接");
                }
            });
        } @catch (NSException *e) {
            DDDLog(@"handleParseLink 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
        }
    }];
}

// 保存相册：对齐 PKC pkcSaveVideoToAlbum:（PHPhotoLibrary + PHAssetCreationRequest）
+ (void)handleSaveAlbum:(NSString *)url {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(NSString *videoURL, NSError *err) {
        @try {
            if (err || !videoURL) {
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
                return;
            }
            NSString *path = DDPTempPath(url);
            if (DDPFileUsable(path)) {
                // 解析完成
                [DDPPanel saveVideoToAlbumAtPath:path];
                return;
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL headers:nil];
                BOOL ok = NO;
                if (data.length) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    ok = [data writeToFile:path atomically:YES];
                }
                if (ok) {
                    // 下载完成
                    [DDPPanel saveVideoToAlbumAtPath:path];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"保存失败"); });
                }
            });
        } @catch (NSException *e) {
            DDDLog(@"handleSaveAlbum 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"保存失败"); });
        }
    }];
}

// 对齐 PKC pkcSaveVideoToAlbum:
+ (void)saveVideoToAlbumAtPath:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"未授权相册权限"); });
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) DDPShowSystemTip(@"已保存到相册");
                else DDPShowSystemTip(@"保存失败");
            });
        }];
    }];
}

@end

#pragma mark - Hook：消息长按菜单（对齐 PKC：canShowForwardMenuItem 存消息 + setMenuItems 加 MMMenuItem）

// 保存当前长按消息，供菜单回调使用（对齐 PKC pkcMsgWrap/tempMsgWrap）
static __weak CMessageWrap *gDDPCurrentMsgWrap;

// 菜单点击回调处理单例（对齐 PKC：MMMenuItem 的 target 指向单例，action 为 onPkcDyVideoJx:）
@interface DDPMenuHandler : NSObject
+ (instancetype)shared;
- (void)onPkcDyVideoJx:(id)sender;    // 解析发送
- (void)onPkcDyVideoJxYl:(id)sender;  // 解析预览
@end

@implementation DDPMenuHandler

+ (instancetype)shared {
    static DDPMenuHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 从保存的当前长按消息取内容（对齐 PKC：type==1 用 m_nsContent，否则 m_nsTitle）
+ (NSString *)currentContent {
    CMessageWrap *wrap = gDDPCurrentMsgWrap;
    if (!wrap) return nil;
    return (wrap.m_uiMessageType == 1) ? wrap.m_nsContent : wrap.m_nsTitle;
}

- (void)onPkcDyVideoJx:(id)sender {
    if (!DDPConfig.shared.enabled) return;
    @try {
        NSString *content = [DDPMenuHandler currentContent];
        if (!content.length) { DDDLog(@"onPkcDyVideoJx: content 为空（长按消息未保存？）"); return; }
        NSString *url = DDPExtractURL(content);
        if (!url.length) { DDDLog(@"onPkcDyVideoJx: 未提取到 URL content=%@", content); DDPShowSystemTip(@"未提取到链接"); return; }
        NSString *chat = DDPCurrentChatName();
        DDDLog(@"onPkcDyVideoJx: 解析发送 url=%@ chat=%@", url, chat);
        // 对齐 PKC onPkcDyVideoJx:（0x38b2e5）→ pkcDyVideoJx:to:，to 取当前会话名
        [DDPPanel handleParseSend:url user:chat force:NO];
    } @catch (NSException *e) {
        DDDLog(@"onPkcDyVideoJx 异常 %@", e);
        DDPShowSystemTip(@"解析失败");
    }
}

- (void)onPkcDyVideoJxYl:(id)sender {
    if (!DDPConfig.shared.enabled) return;
    @try {
        NSString *content = [DDPMenuHandler currentContent];
        if (!content.length) return;
        NSString *url = DDPExtractURL(content);
        if (!url.length) { DDPShowSystemTip(@"未提取到链接"); return; }
        UIViewController *topVC = nil;
        UIWindow *window = DDPKeyWindow();
        if (window) topVC = window.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        if (topVC) [DDPPanel handleParsePreview:url fromVC:topVC];
    } @catch (NSException *e) {
        DDDLog(@"onPkcDyVideoJxYl 异常 %@", e);
        DDPShowSystemTip(@"解析失败");
    }
}

@end

// 对齐 PKC：长按消息时保存当前消息（canShowForwardMenuItem: 是微信长按消息会调用的方法）
%hook BaseMessageCellView

- (BOOL)canShowForwardMenuItem {
    BOOL ret = %orig;
    // 通过 viewModel → messageWrap 取当前长按的消息（对齐 PKC valueForKey 取值）
    id viewModel = [self valueForKey:@"viewModel"];
    CMessageWrap *wrap = viewModel ? [viewModel valueForKey:@"messageWrap"] : nil;
    gDDPCurrentMsgWrap = wrap;
    DDDLog(@"canShowForwardMenuItem: viewModel=%@ messageWrap=%@ content=%@",
           viewModel?@"Y":@"N", wrap?@"Y":@"N", [DDPMenuHandler currentContent]);
    return ret;
}

%end

// 对齐 PKC：hook MMMenuController setMenuItems: 追加"解析/预览"两个 MMMenuItem
%hook MMMenuController

- (void)setMenuItems:(id)menuItems {
    // 微信 setter 通常收不可变 NSArray，先转可变再回传，确保我们能追加按钮
    NSMutableArray *items;
    if ([menuItems isKindOfClass:[NSMutableArray class]]) {
        items = menuItems;
    } else {
        items = menuItems ? [NSMutableArray arrayWithArray:menuItems] : [NSMutableArray array];
    }

    DDDLog(@"setMenuItems: 触发 原类型=%@ 元素数=%lu", NSStringFromClass([menuItems class]), (unsigned long)[items count]);

    // 开关关闭：原样下发，不加按钮
    if (!DDPConfig.shared.enabled) { DDDLog(@"setMenuItems: 开关关闭，跳过"); %orig(items); return; }

    // 检查当前长按消息是否含抖音链接
    NSString *content = [DDPMenuHandler currentContent];
    if (!content.length) { DDDLog(@"setMenuItems: content 为空（消息未保存？）"); %orig(items); return; }
    if (!DDPContainsDouyinLink(content)) { DDDLog(@"setMenuItems: content 不含抖音链接"); %orig(items); return; }

    Class itemCls = objc_getClass("MMMenuItem");
    DDDLog(@"setMenuItems: MMMenuItem 类=%@", itemCls?@"存在":@"不存在");
    if (!itemCls) { %orig(items); return; }

    // 对齐 PKC（0x17b614 / 0x17b61c 等）：用微信内部 SVG 图标 icons_filled_heart，
    // 由微信菜单按自身 tintColor 上色（SF Symbol 会渲染成系统蓝、与菜单色调不一致 → 图标颜色不对）
    id target = [DDPMenuHandler shared];

    id parseItem = [itemCls alloc];
    parseItem = [parseItem initWithTitle:@"解析" svgName:@"icons_filled_heart" target:target action:@selector(onPkcDyVideoJx:)];
    if (parseItem) [items addObject:parseItem];

    id previewItem = [itemCls alloc];
    previewItem = [previewItem initWithTitle:@"预览" svgName:@"icons_filled_heart" target:target action:@selector(onPkcDyVideoJxYl:)];
    if (previewItem) [items addObject:previewItem];

    DDDLog(@"setMenuItems: 已追加解析/预览，当前元素数=%lu", (unsigned long)[items count]);
    %orig(items);   // 最后一次性下发（含新按钮），兼容 setter copy 语义
}

%end

#pragma mark - Hook：CMessageMgr AddMsg（PKC 弹面板的真正入口）

// 完全对齐 PKC 的 CMessageMgr AddMsg:MsgWrap: hook（0x15b8c8）：
//   1. [CMessageWrap isSenderFromMsgWrap:wrap]  → 只处理"自己发出"的消息（0x15ba0c）
//   2. wrap.m_uiMessageType == 1                → 只处理文本消息
//   3. MTwkz…:usr msg:wrap fsly:1               → 内部做抖音检测（0xfb2d4 三串 + 排除"正在直播" 0xfb310）
//      命中则 tipsTitle:…Type:8 Data:@{content,user} 弹面板并返回 YES（0xfb39c w19=1）
//   4. handled == YES → 直接 ret，不调用 %orig（0x15ba48 → 0x15bf94 ret），即"吞掉"这条消息
//   面板里点「直接发送」时先置 pkcDyTcEnable=YES 再重发，MTwkz 入口见到该标志就放行并复位（一次性）
%hook CMessageMgr

- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap {
    // 诊断：确认 hook 是否真的被触发（每条收/发消息都打印一次）
    @try {
        NSString *c = wrap.m_nsContent;
        DDDLog(@"AddMsg hook 触发: type=%u from=%@ to=%@ content=%@",
               (unsigned int)wrap.m_uiMessageType, wrap.m_nsFromUsr, wrap.m_nsToUsr,
               [c length] > 120 ? [c substringToIndex:120] : c);
    } @catch (...) {}
    do {
        if (!DDPConfig.shared.enabled || !wrap) break;

        // 自包含发送方判定：优先 isSenderFromMsgWrap:，缺失则比对本机 wxid，仍不定按“已发送”
        if (!DDPIsOutgoing(wrap)) break;          // 对齐 PKC：仅自己发出的消息
        if (![wrap respondsToSelector:@selector(m_uiMessageType)]) break;
        // 对齐 PKC AddMsg hook（0x15b934-0x15b960）：允许 type 1 / 0x31(49) / 0x3e(62)
        // 你的 iOS18 微信发送抖音链接常被识别为类型 49（链接卡片），只判 ==1 会整条跳过、不弹面板
        unsigned int ddMT = wrap.m_uiMessageType;
        if (ddMT != 1 && ddMT != 49 && ddMT != 62) break;

        // 进入 MTwkz 等价区间。对齐 PKC pkcDyTcEnable 的两处语义：
        //   0xf98a4 入口闸门：为 YES 时本次直接放行（不弹面板）
        //   0xf992c 尾部复位：只要走过 MTwkz 就置回 NO（无论是否命中抖音）
        // 复位必须放在抖音检测之前，否则发一条普通文本后 flag 会残留，导致下次真链接不弹面板
        BOOL bypassOnce = gDDPDyTcEnable;
        gDDPDyTcEnable = NO;
        if (bypassOnce) {
            DDDLog(@"AddMsg: 一次性放行（DyTcEnable 已复位）usr=%@", usr);
            break;
        }

        // 对齐 PKC 15b9e0(type==1 取 m_nsContent) / 15bd98(type 49/62 取 m_nsTitle)
        // 链接卡片(type 49/62)的抖音链接可能在 m_nsTitle 或 m_nsContent(XML)里；
        // 默认查 m_nsContent，不含链接再回退 m_nsTitle，任一命中即弹面板（避免漏抓）
        NSString *rawContent = wrap.m_nsContent;
        NSString *rawTitle   = wrap.m_nsTitle;
        NSString *content = rawContent;
        if (!DDPContainsDouyinLink(content) && DDPContainsDouyinLink(rawTitle)) content = rawTitle;
        if (!DDPContainsDouyinLink(content)) break;              // 对齐 PKC 0xfb2d4：三串检测
        if (DDPIsDouyinLiveText(content)) break;                 // 对齐 PKC 0xfb310：排除"正在直播"

        // 对齐 PKC：Data 的 user 取 AddMsg 第一个参数（会话对象，见 0xfb350 [sp+0x50]）
        NSString *target = usr.length ? usr : wrap.m_nsToUsr;
        if ([DDPPanel showForContent:content user:target]) {
            DDDLog(@"AddMsg: 命中抖音链接，已弹面板并拦截消息 usr=%@", target);
            return;   // 对齐 PKC：handled 后直接 ret，不走 %orig（消息不入库、不发送）
        }
        // 面板未弹出（DTX 类缺失等）→ 放行原发送，避免吞消息
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
    Class mgrCls = objc_getClass("WCTableViewManager");
    if (!mgrCls) return;
    WCTableViewManager *mgr = [mgrCls alloc];
    _tableViewMgr = [mgr initWithFrame:[UIScreen mainScreen].bounds style:UITableViewStyleInsetGrouped];
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
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];
}

- (void)buildTable {
    Class cellCls = objc_getClass("WCTableViewCellManager");
    Class secCls  = objc_getClass("WCTableViewSectionManager");
    if (!cellCls || !secCls || !_tableViewMgr) return;
    [self.tableViewMgr clearAllSection];
    WCTableViewSectionManager *section = [secCls defaultSection];
    [section addCell:[cellCls switchCellForSel:@selector(onEnabledSwitch:) target:self title:@"抖音解析" on:DDPConfig.shared.enabled]];
    [self.tableViewMgr addSection:section];

    // 日志分组：导出 / 清空（真机调试排障用）
    WCTableViewSectionManager *logSection = [secCls defaultSection];
    if ([cellCls respondsToSelector:@selector(normalCellForSel:target:title:)]) {
        [logSection addCell:[cellCls normalCellForSel:@selector(onExportLog:) target:self title:@"导出日志"]];
        [logSection addCell:[cellCls normalCellForSel:@selector(onClearLog:) target:self title:@"清空日志"]];
        [self.tableViewMgr addSection:logSection];
    }
    [self.tableViewMgr reloadTableView];
}

- (void)onEnabledSwitch:(UISwitch *)sender { DDPConfig.shared.enabled = sender.isOn; [self buildTable]; }

// 导出日志：复制一份独立的 txt，再用系统分享面板发出（避免与正在追加写入的 DDDParse.log 抢文件）
- (void)onExportLog:(id)sender {
    @try {
        NSString *log = DDDReadLog();
        if (!log.length) { DDPShowSystemTip(@"暂无可导出日志"); return; }
        NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDDParse_export.txt"];
        [log writeToFile:exportPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        NSURL *url = [NSURL fileURLWithPath:exportPath];
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        // iPad 需要 popover 锚点，否则 present 会崩
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            avc.popoverPresentationController.sourceView = self.view;
            avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                       CGRectGetMidY(self.view.bounds), 0, 0);
            avc.popoverPresentationController.permittedArrowDirections = 0;
        }
        [self presentViewController:avc animated:YES completion:nil];
    } @catch (NSException *e) {
        DDDLog(@"导出日志异常 %@", e);
        DDPShowSystemTip(@"导出失败");
    }
}

// 清空日志：二次确认后删除 DDDParse.log
- (void)onClearLog:(id)sender {
    @try {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                       message:@"确定要清空 DDDParse.log 吗？"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
            DDDClearLog();
            DDPShowSystemTip(@"日志已清空");
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } @catch (NSException *e) {
        DDDLog(@"清空日志异常 %@", e);
    }
}

@end

#pragma mark - 注册

%ctor {
    @autoreleasepool {
        DDDLog(@"%%ctor: DDDouyinParse 已加载");
        Class mgr = objc_getClass("WCPluginsMgr");
        if (mgr && [mgr respondsToSelector:@selector(sharedInstance)]) {
            [[mgr sharedInstance] registerControllerWithTitle:@"DD抖音解析"
                                                      version:@"1.0.0"
                                                   controller:@"DDPDouyinParseSettingsViewController"];
        }
    }
}
