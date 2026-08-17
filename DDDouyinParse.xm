
// DDDouyinParse：微信抖音链接解析（复刻 PKCWeChatTools 混淆类 GXYeazddpmkzikglugu）。
// 流程：识别消息 → 隐藏 WKWebView 抓分享页 HTML → 正则提取/去水印 → 面板发送/预览/保存。
// 面板用微信原生 WCActionSheet；长按菜单 hook MMMenuController 追加"解析/预览"。去水印不依赖微信私有 API。
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

// 日志写入沙盒 tmp/DDDParse.log（Filza 可访问）
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
// 读取日志全文
static inline NSString *DDDReadLog(void) {
    @try {
        NSString *path = DDDLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    } @catch (...) { return nil; }
}
// 清空日志
static inline void DDDClearLog(void) {
    @try {
        NSString *path = DDDLogPath();
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    } @catch (...) {}
}
// 诊断日志（前缀 [DDDParse]，同时落盘）
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
+ (BOOL)isSenderFromMsgWrap:(id)wrap;   // 判断消息是否自己发出（PKC AddMsg 区分收发）
@end

@interface SettingUtil : NSObject  // 取本机 wxid（getLocalUsrName:0）
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
+ (id)activeUserContext;   // PKC 用 activeUserContext 取服务
- (id)getService:(Class)arg1;
@property (readonly, nonatomic) MMServiceCenter *serviceCenter;
@end

@interface CMessageMgr : NSObject
- (id)AddVideoMsg:(NSString *)path ToUsr:(NSString *)usr VideoInfo:(id)info;  // 微信真实签名（头文件）
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
@end

@interface CUtility : NSObject  // 微信 UA（GetMMUserAgent）
+ (NSString *)GetMMUserAgent;
@end

// 面板用微信原生 WCActionSheet（模拟 UIActionSheet：addButtonWithTitle:/setDelegate:/showInView:）

@interface MMMenuController : NSObject  // 长按菜单控制器（hook setMenuItems: 追加项）
+ (instancetype)sharedMenuController;
- (void)setMenuItems:(id)menuItems;
@property (readonly, nonatomic) NSArray *currentMenuItems;
@end

@interface MMMenuItem : NSObject  // 菜单项
- (instancetype)initWithTitle:(NSString *)title icon:(UIImage *)icon target:(id)target action:(SEL)action;
- (instancetype)initWithTitle:(NSString *)title svgName:(NSString *)svgName target:(id)target action:(SEL)action;
@property (retain, nonatomic) UIImage *iconImage;
@property (nonatomic, weak) id target;
@end

@interface BaseMessageCellView : UIView  // 消息 cell（hook canShowForwardMenuItem: 存当前消息）
- (BOOL)canShowForwardMenuItem;
@end

#pragma mark - 配置

static NSString * const kDDPEnabledKey = @"DDDouyinParseEnabled";

@interface DDPConfig : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL webFetchEnable;   // 是否走 WKWebView 渲染（对应 PKC pkcDyJxHtEnable）
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
            _enabled = YES;   // 首次默认开启
            [ud setBool:YES forKey:kDDPEnabledKey];
            DDDLog(@"首次启动，默认开启 enabled=YES");
        } else {
            _enabled = [ud boolForKey:kDDPEnabledKey];
        }
        _webFetchEnable = YES;   // 抖音页面需 JS 渲染
        DDDLog(@"DDPConfig init enabled=%d", _enabled);
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDDPEnabledKey];
}

@end

#pragma mark - 工具函数

// 抖音链接检测：仅认这三类（对齐 PKC 0xfb2d4）
static inline BOOL DDPContainsDouyinLink(NSString *text) {
    if (!text.length) return NO;
    return [text containsString:@"douyin.com/video"]
        || [text containsString:@"v.douyin.com"]
        || [text containsString:@"douyin.com/note"];
}

// 排除"正在直播"（对齐 PKC 0xfb310）
static inline BOOL DDPIsDouyinLiveText(NSString *text) {
    return text.length && [text containsString:@"正在直播"];
}

// 发送方判定：优先 isSenderFromMsgWrap:，缺失则比对本机 wxid，仍不定按已发送（保证面板能弹）
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

// 正则提取 URL（对齐 PKC getDyUrlFromString:）
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

// 去水印：/playwm/→/play/ + ratio=1080p（对齐 PKC removeWatermarkFromVideoURL:）
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

// 自实现 MD5（RFC1321），避免依赖废弃的 CC_MD5
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

// 缓存路径 MD5_1.mp4（对齐 PKC）
static inline NSString *DDPTempPath(NSString *url) {
    NSString *md5 = DDPMD5(url);
    if (!md5) return nil;
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1.mp4", md5]];
}

// 取当前 foreground 的 keyWindow（iOS 13+ 多场景）
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

// 文件存在且 >2 字节才复用
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

// PKC 风格提示气泡：纯文字药丸，屏幕顶部居中，2 秒后淡出；颜色跟随系统深浅模式
static inline void DDPShowPKCTip(NSString *msg) {
    if (!msg.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = DDPKeyWindow();
        if (!win) { DDDLog(@"DDPShowPKCTip: 无 keyWindow"); return; }

        // 文字尺寸
        UILabel *textLbl = [[UILabel alloc] init];
        textLbl.text = msg;
        textLbl.font = [UIFont systemFontOfSize:15];
        textLbl.numberOfLines = 1;
        [textLbl sizeToFit];

        // 动态颜色：浅色模式白底深字，深色模式深底白字
        UIColor *bgColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            if (t.userInterfaceStyle == UIUserInterfaceStyleDark)
                return [UIColor colorWithWhite:0.15 alpha:0.92];
            return [UIColor colorWithWhite:1 alpha:0.95];
        }];
        UIColor *txtColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            if (t.userInterfaceStyle == UIUserInterfaceStyleDark)
                return [UIColor whiteColor];
            return [UIColor labelColor];
        }];
        textLbl.textColor = txtColor;

        CGFloat padX = 16, padY = 10;
        CGFloat containerW = textLbl.bounds.size.width + padX * 2;
        CGFloat containerH = textLbl.bounds.size.height + padY * 2;
        CGFloat containerX = (win.bounds.size.width - containerW) / 2;
        CGFloat containerY = 0;
        if (@available(iOS 11.0, *)) containerY = win.safeAreaInsets.top + 60;
        else containerY = 80;

        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(containerX, containerY, containerW, containerH)];
        container.backgroundColor = bgColor;
        container.layer.cornerRadius = containerH / 2;
        // masksToBounds=NO 才能让阴影显示；文字内缩在圆角内不会溢出
        container.layer.masksToBounds = NO;
        // 浅色模式白底靠阴影浮起，深色模式深底靠阴影区分
        container.layer.shadowColor = [UIColor blackColor].CGColor;
        container.layer.shadowOpacity = 0.18;
        container.layer.shadowOffset = CGSizeMake(0, 2);
        container.layer.shadowRadius = 6;
        container.alpha = 0;
        container.transform = CGAffineTransformMakeScale(0.9, 0.9);

        textLbl.frame = CGRectMake(padX,
                                   (containerH - textLbl.bounds.size.height) / 2,
                                   textLbl.bounds.size.width,
                                   textLbl.bounds.size.height);
        [container addSubview:textLbl];

        [win addSubview:container];

        [UIView animateWithDuration:0.2 animations:^{
            container.alpha = 1;
            container.transform = CGAffineTransformIdentity;
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{
                container.alpha = 0;
                container.transform = CGAffineTransformMakeScale(0.9, 0.9);
            } completion:^(BOOL finished) {
                [container removeFromSuperview];
            }];
        });

        DDDLog(@"DDPShowPKCTip: msg=%@", msg);
    });
}

// 系统提示（统一走 PKC 风格药丸提示）
static inline void DDPShowSystemTip(NSString *msg) {
    DDPShowPKCTip(msg);
}

#pragma mark - DDPWebFetcher（复刻 PKC ORZeljybnjfw：WKWebView 渲染抓取）

// completion: (html, errCode)，DDPCodeGallery 表示图集
static const NSInteger DDPCodeGallery = 0x4161;   // 16737
static const NSInteger DDPMaxRetries = 11;         // 最多重试 11 次（对齐 PKC）

@interface DDPWebFetcher : NSObject <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, assign) unsigned int retries;
@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, strong) NSURLRequest *ddpRequest;   // 当前请求（重试复用）
@property (nonatomic, copy) void (^completion)(NSString *html, NSInteger errCode);
- (void)fetchHTMLFromURL:(NSString *)url completion:(void (^)(NSString *html, NSInteger errCode))completion;
- (void)cleanupWebView;
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

        // 设微信 UA（CUtility GetMMUserAgent），让抖音返回含 playwm 的页面
        NSString *ua = nil;
        Class cUtil = NSClassFromString(@"CUtility");
        if (cUtil && [cUtil respondsToSelector:@selector(GetMMUserAgent)]) {
            ua = [cUtil GetMMUserAgent];
        }
        if (!ua.length) {
            ua = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.40(0x18004025) NetType/WIFI Language/zh_CN";
        }
        DDDLog(@"DDPWebFetcher: 设置 UA=%@", ua);
        if (ua.length) _webView.customUserAgent = ua;

        _webView.navigationDelegate = self;

        // 加 keyWindow、全屏、隐藏
        UIWindow *keyWindow = DDPKeyWindow();
        if (keyWindow) {
            [keyWindow addSubview:_webView];
            _webView.frame = keyWindow.bounds;
        }
        _webView.hidden = YES;
    }
    return self;
}

// 开始抓取（对齐 PKC fetchHTMLFromURL:completion:）
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
                                         timeoutInterval:30.0];   // 30s 超时

    // 按配置决定是否走 WKWebView
    BOOL webFetch = DDPConfig.shared.webFetchEnable;

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
    // 首次加载，未命中 playwm 则重试
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadRequest:request];
    });
}

// 加载完延迟取 outerHTML（对齐 PKC webView:didFinishNavigation:）
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    DDDLog(@"DDPWebFetcher: didFinishNavigation retries=%u", self.retries);
    __weak typeof(self) wself = self;
    // 延迟 (retries+5)s 等 JS 渲染
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
    DDDLog(@"ddFinishWithHTML: code=%ld htmlLen=%lu", (long)code, (unsigned long)(html ? html.length : 0));
    if (self.hasCompleted) return;
    self.hasCompleted = YES;
    if (self.completion) self.completion(html, code);
    self.retries = 0;
    [self cleanupWebView];
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

        DDDLog(@"handleRenderedHTML: cleanLen=%lu 含playwm=%d 含video_id=%d 含swiper=%d",
               (unsigned long)clean.length,
               [clean containsString:@"playwm"],
               [clean containsString:@"video_id="],
               [clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"]);

    // 图集特征检测
    NSInteger code = 0;
    if ([clean containsString:@"aweme-share-swiper-item"] || [clean containsString:@"aweme-slides-swiper-item"]) {
        code = DDPCodeGallery;
    }

    // 命中 playwm/图集即成功，否则重试
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

// 清理 webView
- (void)cleanupWebView {
    _webView.hidden = YES;
}

- (WKWebView *)webView {
    return _webView;
}

@end

#pragma mark - 解析引擎：抓 HTML → 提取去水印链接 → 下载

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

// 正则提取 playwm 直链并去水印、去重（对齐 PKC extractVideoLinksFromHTML:）
- (NSArray *)extractVideoLinksFromHTML:(NSString *)html {
    if (!html.length) return @[];

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https://aweme\\.snssdk\\.com/aweme/v1/playwm/\\?[^\"\\s]+"
                                                                          options:NSRegularExpressionCaseInsensitive error:nil];
    if (!re) return @[];
    NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        NSString *u = [html substringWithRange:m.range];
        u = [u stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];   // &amp;→&
        if ([u containsString:@"video_id=https:"]) continue;                     // 跳过 video_id=https:
        NSString *clean = DDPRemoveWatermark(u);                                  // 去水印
        if (clean.length && ![result containsObject:clean]) [result addObject:clean];
    }
    DDDLog(@"extractVideoLinks: 候选数=%lu 首个=%@", (unsigned long)result.count, result.firstObject);
    return [result copy];
}


// 解析入口：缓存 → 抓 HTML → 提取链接（对齐 PKC fetchRenderedHTMLContentYl:）
- (void)parseDouyinURL:(NSString *)url completion:(void (^)(NSString *videoURL, NSError *err))completion {
    if (!url.length) { if (completion) completion(nil, [NSError errorWithDomain:@"DDP" code:-1 userInfo:nil]); return; }

    // 命中缓存直接返回
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

// 同步下载（对齐 PKC downloadVideoFromURL:headers:）
- (NSData *)downloadVideoFromURL:(NSString *)url headers:(NSDictionary *)headers {
    if (!url.length) return nil;

    NSString *encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *nsurl = [NSURL URLWithString:encoded];
    if (!nsurl) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    request.HTTPMethod = @"GET";

    // 传入 headers 时跳过 UA/Accept
    if (headers.count) {
        [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            NSString *lower = key.lowercaseString;
            if ([lower isEqualToString:@"user-agent"] || [lower isEqualToString:@"accept"]) return;
            [request setValue:value forHTTPHeaderField:key];
        }];
    } else {
        // 默认 headers
        [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-language"];
        [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
        [request setValue:url forHTTPHeaderField:@"Referer"];
        [request setValue:@"strict-origin-when-cross-origin" forHTTPHeaderField:@"Referrer-Policy"];
    }
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];

    // 微信 UA（CUtility GetMMUserAgent）
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

// 一次性放行标志（对应 PKC pkcDyTcEnable）
static BOOL gDDPDyTcEnable;

// content/user 兜底
static NSString *gDDPPanelContent;
static NSString *gDDPPanelUser;

// 取 CMessageMgr（优先 activeUserContext）
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

// 取当前会话名（遍历 VC 响应 getCurrentChatName）
static NSString *DDPCurrentChatName(void) {
    UIWindow *window = DDPKeyWindow();
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    NSMutableArray *stack = [NSMutableArray array];
    if (vc) [stack addObject:vc];
    while (stack.count) {
        UIViewController *cur = stack.firstObject;
        [stack removeObjectAtIndex:0];
        // 不依赖具体类名，响应即命中（iOS18 类名变化也能命中）
        if ([cur respondsToSelector:@selector(getCurrentChatName)]) {
            NSString *name = (NSString *)[cur performSelector:@selector(getCurrentChatName)];
            if ([name isKindOfClass:NSString.class] && name.length) return name;
        }
        if (cur.childViewControllers.count) [stack addObjectsFromArray:cur.childViewControllers];
        if (cur.presentedViewController) [stack addObject:cur.presentedViewController];
    }
    return nil;
}

// 自建 CMessageWrap 走 AddMsg 发送（对齐 PKC sendMsg:toUser:）
static void DDPSendTextMsg(NSString *content, NSString *user) {
    if (!content.length || !user.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 先清标志，仅 AddMsg 前一行打开，避免失败路径残留
        gDDPDyTcEnable = NO;

        Class wrapCls = objc_getClass("CMessageWrap");
        Class mgrCls  = objc_getClass("CMessageMgr");
        Class ctxCls  = objc_getClass("MMContext");
        Class setCls  = objc_getClass("SettingUtil");
        if (!wrapCls || !mgrCls || !ctxCls) { DDPShowSystemTip(@"发送失败"); return; }

        CMessageWrap *wrap = [[wrapCls alloc] initWithMsgType:1];
        if (!wrap) { DDPShowSystemTip(@"发送失败"); return; }
        if (setCls && [setCls respondsToSelector:@selector(getLocalUsrName:)]) {
            wrap.m_nsFromUsr = [setCls getLocalUsrName:0];   // 取本机 wxid
        }
        wrap.m_nsToUsr      = user;
        wrap.m_uiStatus     = 4;                             // m_uiStatus = 4
        wrap.m_nsContent    = content;
        wrap.m_uiCreateTime = (unsigned int)[[NSDate date] timeIntervalSince1970];

        // 取服务
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

        gDDPDyTcEnable = YES;                                // 一次性放行，避免重发被拦截
        [mgr AddMsg:user MsgWrap:wrap];
        DDDLog(@"DDPSendTextMsg: 已发送 user=%@ len=%lu", user, (unsigned long)content.length);
    });
}

// DDPPanel 接口声明（需前置声明，供 DDPPanelHandler 回调调用类方法）
@interface DDPPanel : NSObject
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user;
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user;
+ (void)handleParseSend:(NSString *)url user:(NSString *)user force:(BOOL)force;
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc;
+ (void)handleParseLink:(NSString *)url user:(NSString *)user;
+ (void)handleSaveAlbum:(NSString *)url;
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user;
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc;
+ (void)saveVideoToAlbumAtPath:(NSString *)path;
@end

@interface DDPPanelHandler : NSObject
+ (instancetype)shared;
- (void)onDirectSend:(id)sender;      // 直接发送
- (void)onParseSend:(id)sender;       // 解析发送
- (void)onParsePreview:(id)sender;    // 解析预览
- (void)onParseLink:(id)sender;       // 解析链接
- (void)onSaveAlbum:(id)sender;       // 保存相册
- (void)onCancel:(id)sender;
@end

@implementation DDPPanelHandler
+ (instancetype)shared {
    static DDPPanelHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 从 sender.m_userData 取 content/user
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
- (void)onCancel:(id)sender { /* 取消：不操作（消息已被拦截） */ }

#pragma mark - WCActionSheet delegate（点击底部面板按钮回调）
// 同一 sheet 的 clicked/dismiss 两个回调都可能触发，用关联对象保证只分发一次
static const char kDDPActionSheetHandledKey;

- (void)actionSheet:(id)sheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [self ddpDispatchSheet:sheet buttonIndex:buttonIndex];
}
- (void)actionSheet:(id)sheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    [self ddpDispatchSheet:sheet buttonIndex:buttonIndex];
}
- (void)ddpDispatchSheet:(id)sheet buttonIndex:(NSInteger)idx {
    if (!sheet) return;
    NSNumber *handled = objc_getAssociatedObject(sheet, &kDDPActionSheetHandledKey);
    if (handled.boolValue) return;
    objc_setAssociatedObject(sheet, &kDDPActionSheetHandledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 按钮索引：0直接发送 1解析发送 2预览 3链接 4保存；原生取消走 default
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

// 微信原生底部面板 WCActionSheet
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    if (!content.length) return NO;

    @try {
        UIWindow *window = DDPKeyWindow();
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top) { DDDLog(@"DDPanel: 找不到顶层 VC"); return NO; }

        gDDPPanelContent = content;
        gDDPPanelUser = user;

        // 微信原生面板类 WCActionSheet
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

        // 按钮顺序：直接发送 → 解析发送 → 解析预览 → 解析链接 → 保存相册
        // 不主动加“取消”，WCActionSheet 自身已带原生取消按钮
        [sheet addButtonWithTitle:@"直接发送"];
        [sheet addButtonWithTitle:@"解析发送"];
        [sheet addButtonWithTitle:@"解析预览"];
        [sheet addButtonWithTitle:@"解析链接"];
        [sheet addButtonWithTitle:@"保存相册"];

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

// 直接发送（对齐 PKC dyzzfs:）
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user {
    if (!content.length) return;
    if (!user.length) { DDPShowSystemTip(@"发送失败"); return; }
    gDDPDyTcEnable = YES;              // 先置位，确保重发不会被自己再次拦截
    DDPSendTextMsg(content, user);
}

// 解析发送（对齐 PKC pkcDyVideoJx:to:flag:type:，type=0 发视频）
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
            // flag=1 忽略缓存
            if (!force && DDPFileUsable(path)) {
                [DDPPanel sendVideoAtPath:path toUser:user];
                return;
            }
            // 后台下载
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

// 发视频消息（CMessageMgr AddVideoMsg:ToUsr:VideoInfo:）
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
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

// 解析预览（AVPlayer 播放）
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

// 解析链接（对齐 PKC dyjxlj:，type=1 以文本消息发送）
+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(NSString *videoURL, NSError *err) {
        @try {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err || !videoURL) { DDPShowSystemTip(@"解析失败"); return; }
                DDPCopyToPasteboard(videoURL);
                NSString *target = user.length ? user : DDPCurrentChatName();
                if (target.length) {
                    DDPSendTextMsg(videoURL, target);   // 链接以文本消息发出
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

// 保存相册（PHPhotoLibrary + PHAssetCreationRequest）
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

// 保存到相册
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

#pragma mark - Hook：长按菜单（canShowForwardMenuItem 存消息 + setMenuItems 加项）

// 当前长按消息（供菜单回调）
static __weak CMessageWrap *gDDPCurrentMsgWrap;

// 菜单回调单例
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

// 取当前消息内容（type 1 用 m_nsContent，否则 m_nsTitle）
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
        [DDPPanel handleParseSend:url user:chat force:NO];   // 解析发送（to 取当前会话）
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

// 长按消息时保存当前消息
%hook BaseMessageCellView

- (BOOL)canShowForwardMenuItem {
    BOOL ret = %orig;
    // 经 viewModel.messageWrap 取消息
    id viewModel = [self valueForKey:@"viewModel"];
    CMessageWrap *wrap = viewModel ? [viewModel valueForKey:@"messageWrap"] : nil;
    gDDPCurrentMsgWrap = wrap;
    DDDLog(@"canShowForwardMenuItem: viewModel=%@ messageWrap=%@ content=%@",
           viewModel?@"Y":@"N", wrap?@"Y":@"N", [DDPMenuHandler currentContent]);
    return ret;
}

%end

// hook setMenuItems: 追加"解析/预览"
%hook MMMenuController

- (void)setMenuItems:(id)menuItems {
    // 转可变数组追加
    NSMutableArray *items;
    if ([menuItems isKindOfClass:[NSMutableArray class]]) {
        items = menuItems;
    } else {
        items = menuItems ? [NSMutableArray arrayWithArray:menuItems] : [NSMutableArray array];
    }

    DDDLog(@"setMenuItems: 触发 原类型=%@ 元素数=%lu", NSStringFromClass([menuItems class]), (unsigned long)[items count]);

    // 开关关闭：原样下发
    if (!DDPConfig.shared.enabled) { DDDLog(@"setMenuItems: 开关关闭，跳过"); %orig(items); return; }

    // 检查当前长按消息是否含抖音链接
    NSString *content = [DDPMenuHandler currentContent];
    if (!content.length) { DDDLog(@"setMenuItems: content 为空（消息未保存？）"); %orig(items); return; }
    if (!DDPContainsDouyinLink(content)) { DDDLog(@"setMenuItems: content 不含抖音链接"); %orig(items); return; }

    Class itemCls = objc_getClass("MMMenuItem");
    DDDLog(@"setMenuItems: MMMenuItem 类=%@", itemCls?@"存在":@"不存在");
    if (!itemCls) { %orig(items); return; }

    // 用微信内部 SVG 图标，避免 SF Symbol 色调不一致
    id target = [DDPMenuHandler shared];

    id parseItem = [itemCls alloc];
    parseItem = [parseItem initWithTitle:@"解析" svgName:@"icons_filled_heart" target:target action:@selector(onPkcDyVideoJx:)];
    if (parseItem) [items addObject:parseItem];

    id previewItem = [itemCls alloc];
    previewItem = [previewItem initWithTitle:@"预览" svgName:@"icons_filled_heart" target:target action:@selector(onPkcDyVideoJxYl:)];
    if (previewItem) [items addObject:previewItem];

    DDDLog(@"setMenuItems: 已追加解析/预览，当前元素数=%lu", (unsigned long)[items count]);
    %orig(items);   // 一次性下发（含新按钮），兼容 setter copy 语义
}

%end

#pragma mark - Hook：CMessageMgr AddMsg（弹面板的真正入口）

// 对齐 PKC CMessageMgr AddMsg:MsgWrap: hook：
//   1. 仅处理自己发出的消息；2. 文本(type 1)/链接卡片(49)/其他(62)；
//   3. 三串抖音检测 + 排除"正在直播"，命中弹面板并拦截（不调 %orig）；
//   4. 「直接发送」先置 pkcDyTcEnable 重发，入口见该标志即一次性放行。
%hook CMessageMgr

- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap {
    // 诊断日志
    @try {
        NSString *c = wrap.m_nsContent;
        DDDLog(@"AddMsg hook 触发: type=%u from=%@ to=%@ content=%@",
               (unsigned int)wrap.m_uiMessageType, wrap.m_nsFromUsr, wrap.m_nsToUsr,
               [c length] > 120 ? [c substringToIndex:120] : c);
    } @catch (...) {}
    do {
        if (!DDPConfig.shared.enabled || !wrap) break;

        // 发送方判定
        if (!DDPIsOutgoing(wrap)) break;          // 仅自己发出的消息
        if (![wrap respondsToSelector:@selector(m_uiMessageType)]) break;
        // 允许文本(1)/链接卡片(49)/其他(62)，避免漏抓
        unsigned int ddMT = wrap.m_uiMessageType;
        if (ddMT != 1 && ddMT != 49 && ddMT != 62) break;

        // 一次性放行标志（pkcDyTcEnable）：入口闸门前读取并复位，再判抖音（复位须在检测前，否则会残留）
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
        if (DDPIsDouyinLiveText(content)) break;                 // 排除"正在直播"

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

    // 日志分组
    WCTableViewSectionManager *logSection = [secCls defaultSection];
    if ([cellCls respondsToSelector:@selector(normalCellForSel:target:title:)]) {
        [logSection addCell:[cellCls normalCellForSel:@selector(onExportLog:) target:self title:@"导出日志"]];
        [logSection addCell:[cellCls normalCellForSel:@selector(onClearLog:) target:self title:@"清空日志"]];
        [self.tableViewMgr addSection:logSection];
    }
    [self.tableViewMgr reloadTableView];
}

- (void)onEnabledSwitch:(UISwitch *)sender { DDPConfig.shared.enabled = sender.isOn; [self buildTable]; }

// 导出日志（另存 txt 分享）
- (void)onExportLog:(id)sender {
    @try {
        NSString *log = DDDReadLog();
        if (!log.length) { DDPShowSystemTip(@"暂无可导出日志"); return; }
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
    } @catch (NSException *e) {
        DDDLog(@"导出日志异常 %@", e);
        DDPShowSystemTip(@"导出失败");
    }
}

// 清空日志（二次确认）
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
