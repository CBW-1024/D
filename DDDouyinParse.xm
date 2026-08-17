
// DDDouyinParse：微信抖音链接解析（复刻 PKCWeChatTools 混淆类 GXYeazddpmkzikglugu）。
// 流程：识别消息 → 隐藏 WKWebView 抓分享页 HTML → 正则提取/去水印 → 面板发送/预览/保存。
// 面板用系统 UIAlertController actionSheet（对齐 PKC 面板风格）；长按菜单 hook MMMenuController 追加"解析/预览"。去水印不依赖微信私有 API。
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonCrypto.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <unistd.h>
#import <string.h>

// 直接观看图片查看器（完整接口提前声明，供 DDPPanel presentImageViewer: 编译期识别）
@interface DDPImageViewerController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, copy) NSArray<NSString *> *imagePaths;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIPageControl *pageCtl;
@property (nonatomic, assign) NSInteger currentIndex;
@end

// 微信自带视频播放器（PKC 预览用它播放本地 mp4，对齐 pkcDyVideoJxYl → MMMoviePlayerController）
@interface MMMoviePlayerController : UIViewController
- (instancetype)initWithMsgWrap:(id)arg1 VideoPath:(NSString *)arg2;
@end

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
- (id)AddVideoMsg:(NSString *)path ToUsr:(NSString *)usr VideoInfo:(id)info;
- (void)AddMsg:(NSString *)usr MsgWrap:(CMessageWrap *)wrap;
@end

// 图片消息扩展操作（对齐 PKC sendImg:image: 调用 IMsgExtendOperation.set外界）
@protocol DDPMsgExtendOperation <NSObject>
- (void)setImage:(UIImage *)arg1 withData:(NSData *)arg2 isOriginImage:(BOOL)arg3;
@end

// 图片消息构造（CMessageWrap 由 WeixinContentLogicController.FormImageMsg:withImage:withData: 生成；签名对齐 MsgDelegate-Protocol.h:28）
@interface CMessageWrap (DDP)
- (id<DDPMsgExtendOperation>)m_extendInfoWithMsgType;
@end

@interface WeixinContentLogicController : NSObject
- (instancetype)init;
- (CMessageWrap *)FormImageMsg:(NSString *)arg1 withImage:(UIImage *)arg2 withData:(NSData *)arg3;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
@end

@interface CUtility : NSObject  // 微信 UA（GetMMUserAgent）
+ (NSString *)GetMMUserAgent;
@end

// 面板用系统 UIAlertController actionSheet（标题"抖音解析"，message 为消息原文，5 个操作 + 取消）

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

// 图片缓存路径 MD5_1.<ext>
static inline NSString *DDPTempPathExt(NSString *url, NSString *ext) {
    NSString *md5 = DDPMD5(url);
    if (!md5) return nil;
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1.%@", md5, ext ?: @"dat"]];
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
        DDDLog(@"handleRenderedHTML: 未命中 playwm，重试 (%u/%ld) url=%@", self.retries, (long)DDPMaxRetries, self.ddpRequest.URL);
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
- (NSData *)downloadVideoFromURL:(NSString *)url headers:(NSDictionary *)headers;
@end

@implementation DDPEngine

+ (instancetype)shared {
    static DDPEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

// 视频：正则抠 playwm 直链并去水印、去重（对齐 PKC extractVideoLinksFromHTML:）
- (NSArray<NSString *> *)extractVideoLinksFromHTML:(NSString *)html {
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

// 图文/滑块：抠图集与幻灯片图片（对齐 PKC extractGalleryImagesFromHTML: 两段正则）
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
        @try {
            if (!html.length) {
                if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-2 userInfo:nil]);
                return;
            }
            // 视频优先；否则图文/滑块
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
        } @catch (NSException *e) {
            DDDLog(@"parseDouyinURL 异常 %@", e);
            if (completion) completion(DDPMediaTypeUnknown, nil, nil, [NSError errorWithDomain:@"DDP" code:-5 userInfo:nil]);
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

// DDPPanel 接口声明
@interface DDPPanel : NSObject
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user;
+ (void)handleDirectSend:(NSString *)content user:(NSString *)user;
+ (void)handleParseSend:(NSString *)url user:(NSString *)user force:(BOOL)force;
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc;
+ (void)handleParseLink:(NSString *)url user:(NSString *)user;
+ (void)handleSaveAlbum:(NSString *)url;
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user;
+ (NSString *)generateThumbnailForVideoPath:(NSString *)path;
+ (void)sendImageAtPath:(NSString *)path toUser:(NSString *)user;
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls shareURL:(NSString *)shareURL user:(NSString *)user force:(BOOL)force;
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc;
+ (void)saveVideoToAlbumAtPath:(NSString *)path;
+ (void)saveImageToAlbumAtPath:(NSString *)path;
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls shareURL:(NSString *)shareURL;
@end

@implementation DDPPanel

// 系统 UIAlertController actionSheet（对齐 PKC 面板风格：标题"抖音解析"，message 为消息原文）
+ (BOOL)showForContent:(NSString *)content user:(NSString *)user {
    if (!content.length) return NO;

    @try {
        UIWindow *window = DDPKeyWindow();
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (!top) { DDDLog(@"DDPanel: 找不到顶层 VC"); return NO; }

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"抖音解析"
                                                                       message:content
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        if (!sheet) { DDDLog(@"DDPanel: UIAlertController 初始化失败"); return NO; }

        // 取消：iPad 必须设置 popover 锚点，否则崩溃
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            sheet.popoverPresentationController.sourceView = top.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMaxY(top.view.bounds), 1, 1);
            sheet.popoverPresentationController.permittedArrowDirections = 0;
        }

        // 5 个操作按钮（对齐 PKC 抖音解析面板：直接发送 / 解析发送 / 解析预览 / 解析链接 / 保存相册）
        [sheet addAction:[UIAlertAction actionWithTitle:@"直接发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [DDPPanel handleDirectSend:content user:user];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"解析发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *url = DDPExtractURL(content);
            if (url.length) [DDPPanel handleParseSend:url user:user force:NO];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"解析预览" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *url = DDPExtractURL(content);
            if (!url.length) return;
            [DDPPanel handleParsePreview:url fromVC:top];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"解析链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *url = DDPExtractURL(content);
            if (url.length) [DDPPanel handleParseLink:url user:user];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"保存相册" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *url = DDPExtractURL(content);
            if (url.length) [DDPPanel handleSaveAlbum:url];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

        [top presentViewController:sheet animated:YES completion:nil];
        DDDLog(@"DDPanel: 系统 actionSheet 已 show user=%@", user);
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
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        @try {
            if (err || type == DDPMediaTypeUnknown) {
                DDDLog(@"handleParseSend: 解析失败 url=%@ err=%@", url, err);
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败，请检查网络重试！"); });
                return;
            }
            if (type == DDPMediaTypeVideo) {
                [self sendVideoForURL:videoURL shareURL:url user:user force:force];
            } else {
                [self sendImagesForURLs:imageURLs shareURL:url user:user force:force];   // 图文/滑块：下载直链逐张发进聊天
            }
        } @catch (NSException *e) {
            DDDLog(@"handleParseSend 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
        }
    }];
}

// 下载视频直链并发到聊天（含本地缓存复用）
+ (void)sendVideoForURL:(NSString *)videoURL shareURL:(NSString *)url user:(NSString *)user force:(BOOL)force {
    if (!videoURL.length) { dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); }); return; }
    NSString *path = DDPTempPath(url);
    if (!force && DDPFileUsable(path)) {
        [DDPPanel sendVideoAtPath:path toUser:user];
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
        if (ok) [DDPPanel sendVideoAtPath:path toUser:user];
        else dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"下载失败"); });
    });
}

// 下载图片直链并批量存相册（图文/滑块，纯本机官方直链）
+ (void)downloadAndSaveImages:(NSArray<NSString *> *)urls shareURL:(NSString *)shareURL {
    if (!urls.count) { DDPShowSystemTip(@"未找到图片"); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger saved = 0;
        for (NSString *imgURL in urls) {
            NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL headers:nil];
            if (!data.length) continue;
            NSString *ext = @"jpg";
            if ([[imgURL pathExtension].lowercaseString isEqualToString:@"png"]) ext = @"png";
            NSString *path = DDPTempPathExt(imgURL, ext);
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
            if ([data writeToFile:path atomically:YES]) {
                [DDPPanel saveImageToAlbumAtPath:path];
                saved++;
            }
        }
        NSInteger n = saved;
        dispatch_async(dispatch_get_main_queue(), ^{
            DDPShowSystemTip(n > 1 ? [NSString stringWithFormat:@"已保存 %ld 张", (long)n]
                            : (n == 1 ? @"已保存到相册" : @"保存失败"));
        });
    });
}

// 生成视频缩略图（对齐 PKC generateThumbnailForVideo:，main_parser.asm:128727）：
// AVAssetImageGenerator 取第 0.5s 帧 → JPEG 写临时目录 thumb_<UUID>.jpg → 返回路径
+ (NSString *)generateThumbnailForVideoPath:(NSString *)path {
    if (!path.length) return nil;
    NSString *thumbPath = nil;
    @try {
        NSURL *videoURL = [NSURL fileURLWithPath:path];
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        if (!asset) return nil;
        AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        gen.appliesPreferredTrackTransform = YES;
        // CMTimeMake(1,2) = 0.5s（对齐 PKC）
        CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 2)
                                    actualTime:NULL error:NULL];
        if (!cg) return nil;
        UIImage *img = [UIImage imageWithCGImage:cg];
        CGImageRelease(cg);
        NSData *jpg = UIImageJPEGRepresentation(img, 0.5);   // 对齐 PKC 压缩质量 0.5
        if (jpg.length) {
            thumbPath = [NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.jpg",
                                                [[NSUUID UUID] UUIDString]]];
            [jpg writeToFile:thumbPath atomically:YES];
        }
    } @catch (NSException *e) {
        DDDLog(@"generateThumbnail 异常 %@", e);
        return nil;
    }
    return thumbPath;
}

// 发视频消息（CMessageMgr AddVideoMsg:ToUsr:VideoInfo:）
// 完整对齐 PKC sendVideo:videoPath:（main_parser.asm:129031）：
//   取码率(getVideoBitrateFromFilePath:)→生成缩略图(generateThumbnailForVideo:)→
//   码率≥300kbps(0x4b400)走 OpenApiMgrHelper.genCaptureVideoInfoWithVideoData:，
//   <300kbps 走 CaptureVideoInfo.genVideoInfoWithVideoUrl:thumb: → setThumb_path:
+ (void)sendVideoAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) {
            DDPShowSystemTip(@"发送失败");
            return;
        }
        CMessageMgr *msgMgr = DDPMessageMgr();
        if (!msgMgr || ![msgMgr respondsToSelector:@selector(AddVideoMsg:ToUsr:VideoInfo:)]) {
            DDPShowSystemTip(@"发送失败");
            return;
        }
        id videoInfo = nil;
        @try {
            // 1) 生成缩略图（对齐 PKC generateThumbnailForVideo:）
            NSString *thumbPath = [self generateThumbnailForVideoPath:path];

            // 2) 取码率（对齐 PKC getVideoBitrateFromFilePath: → videoBitrate 字典 → longLongValue）
            long long bitrate = 0;
            Class pkcCls = objc_getClass("GXYeazddpmkzikglugu");   // 混淆类，暴露 getVideoBitrateFromFilePath:
            if (pkcCls && [pkcCls respondsToSelector:@selector(getVideoBitrateFromFilePath:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id bd = [pkcCls performSelector:@selector(getVideoBitrateFromFilePath:) withObject:path];
#pragma clang diagnostic pop
                if ([bd respondsToSelector:@selector(objectForKeyedSubscript:)]) {
                    id v = [bd objectForKeyedSubscript:@"videoBitrate"];
                    if ([v respondsToSelector:@selector(longLongValue)]) bitrate = [v longLongValue];
                }
            }
            // 码率拿不到时按体积/时长粗略估计：>2MB 视为高码率（兜底）
            if (bitrate == 0) {
                NSNumber *sz = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize];
                if (sz.longLongValue > 2 * 1024 * 1024) bitrate = 400000;   // >2MB 视为 ≥300kbps
            }

            // 3) 分支构造 VideoInfo（对齐 PKC：0x4b400 = 307200）
            if (bitrate >= 307200) {
                // 高码率分支：OpenApiMgrHelper.genCaptureVideoInfoWithVideoData:mediaMessage:nil param:nil
                Class ohCls = objc_getClass("OpenApiMgrHelper");
                if (ohCls && [ohCls respondsToSelector:@selector(genCaptureVideoInfoWithVideoData:mediaMessage:param:)]) {
                    // 动态调用（objc_getClass 返回裸 Class，编译器不认该 selector，走 performSelector）
                    NSData *videoData = [NSData dataWithContentsOfFile:path];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    videoInfo = [ohCls performSelector:@selector(genCaptureVideoInfoWithVideoData:mediaMessage:param:)
                                            withObject:videoData
                                            withObject:nil
                                            withObject:nil];
#pragma clang diagnostic pop
                }
            } else {
                // 低码率分支：CaptureVideoInfo.genVideoInfoWithVideoUrl:thumb: + setThumb_path:
                Class capCls = objc_getClass("CaptureVideoInfo");
                if (capCls && [capCls respondsToSelector:@selector(genVideoInfoWithVideoUrl:thumb:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    videoInfo = [capCls performSelector:@selector(genVideoInfoWithVideoUrl:thumb:)
                                             withObject:[NSURL fileURLWithPath:path]
                                             withObject:thumbPath];
#pragma clang diagnostic pop
                    if (videoInfo && thumbPath && [videoInfo respondsToSelector:@selector(setThumb_path:)]) {
                        [videoInfo setThumb_path:thumbPath];
                    }
                }
            }
        } @catch (NSException *e) {
            DDDLog(@"构造 VideoInfo 异常 %@", e);
            videoInfo = nil;
        }
        DDPShowSystemTip(@"解析成功，正在发送");
        [msgMgr AddVideoMsg:path ToUsr:chatName VideoInfo:videoInfo];
    });
}

// 发图片消息（CMessageMgr AddMsg:MsgWrap:；wrap 由 WeixinContentLogicController.FormImageMsg:withImage:withData: 构造，对齐 PKC sendImg:image:）
+ (void)sendImageAtPath:(NSString *)path toUser:(NSString *)user {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *chatName = user.length ? user : DDPCurrentChatName();
        if (!chatName.length) { DDPShowSystemTip(@"发送失败"); return; }

        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image) { DDPShowSystemTip(@"发送失败"); return; }
        NSData *data = UIImagePNGRepresentation(image);
        if (!data.length) { DDPShowSystemTip(@"发送失败"); return; }

        Class ctrlCls = objc_getClass("WeixinContentLogicController");
        if (!ctrlCls) { DDPShowSystemTip(@"发送失败"); return; }
        id ctrl = [[ctrlCls alloc] init];
        if (!ctrl || ![ctrl respondsToSelector:@selector(FormImageMsg:withImage:withData:)]) {
            DDPShowSystemTip(@"发送失败"); return;
        }
        CMessageWrap *wrap = [ctrl FormImageMsg:chatName withImage:image withData:data];
        if (!wrap) { DDPShowSystemTip(@"发送失败"); return; }

        // 写入原图扩展信息（对齐 PKC：m_extendInfoWithMsgType → setImage:withData:isOriginImage:YES）
        id<DDPMsgExtendOperation> ext = [wrap m_extendInfoWithMsgType];
        if (ext && [ext respondsToSelector:@selector(setImage:withData:isOriginImage:)]) {
            [ext setImage:image withData:data isOriginImage:YES];
        }

        CMessageMgr *mgr = DDPMessageMgr();
        if (mgr && [mgr respondsToSelector:@selector(AddMsg:MsgWrap:)]) {
            DDPShowSystemTip(@"解析成功，正在发送");
            [mgr AddMsg:chatName MsgWrap:wrap];   // 图片 type=3，不会命中抖音面板拦截
        } else {
            DDPShowSystemTip(@"发送失败");
        }
    });
}

// 下载图片直链并逐张发进聊天（图文/滑块，纯本机官方直链；对齐 PKC sendImg:image:）
+ (void)sendImagesForURLs:(NSArray<NSString *> *)urls shareURL:(NSString *)shareURL user:(NSString *)user force:(BOOL)force {
    if (!urls.count) { DDPShowSystemTip(@"未找到图片"); return; }
    DDPShowSystemTip(@"抖音解析后台任务开始");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger sent = 0;
        for (NSString *imgURL in urls) {
            @autoreleasepool {
                NSString *ext = @"jpg";
                if ([[imgURL pathExtension].lowercaseString isEqualToString:@"png"]) ext = @"png";
                NSString *path = DDPTempPathExt(imgURL, ext);
                if (!force && DDPFileUsable(path)) {
                    [DDPPanel sendImageAtPath:path toUser:user];
                    sent++;
                    continue;
                }
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL headers:nil];
                if (!data.length) continue;
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                if ([data writeToFile:path atomically:YES]) {
                    [DDPPanel sendImageAtPath:path toUser:user];
                    sent++;
                }
            }
        }
        NSInteger n = sent;
        dispatch_async(dispatch_get_main_queue(), ^{
            DDPShowSystemTip(n > 0 ? [NSString stringWithFormat:@"已发送 %ld 张", (long)n] : @"发送失败");
        });
    });
}

// 解析预览：视频→AVPlayer 播放；图文/滑块→下载存相册后查看
+ (void)handleParsePreview:(NSString *)url fromVC:(UIViewController *)vc {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        @try {
            if (err || type == DDPMediaTypeUnknown) {
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
                return;
            }
            if (type == DDPMediaTypeVideo) {
                NSString *path = DDPTempPath(url);
                if (DDPFileUsable(path)) {
                    dispatch_async(dispatch_get_main_queue(), ^{ [DDPPanel playVideoAtPath:path fromVC:vc]; });
                    return;
                }
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL headers:nil];
                    if (data.length) {
                        NSFileManager *fm = [NSFileManager defaultManager];
                        if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                        [data writeToFile:path atomically:YES];
                        dispatch_async(dispatch_get_main_queue(), ^{ [DDPPanel playVideoAtPath:path fromVC:vc]; });
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"下载失败"); });
                    }
                });
            } else {
                // 图文/滑块：下载到本地后直接观看（多图横向滑动 + 捏合缩放）
                [DDPPanel downloadImagesLocally:imageURLs completion:^(NSArray<NSString *> *paths) {
                    if (!paths.count) { DDPShowSystemTip(@"下载失败"); return; }
                    [DDPPanel presentImageViewer:paths fromVC:vc];
                }];
            }
        } @catch (NSException *e) {
            DDDLog(@"handleParsePreview 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
        }
    }];
}

// 视频预览：对齐 PKC pkcDyVideoJxYl —— 用微信自带 MMMoviePlayerController 播放本地 mp4 并 push 到导航栈
+ (void)playVideoAtPath:(NSString *)path fromVC:(UIViewController *)vc {
    if (!path.length || !vc) return;
    Class cls = objc_getClass("MMMoviePlayerController");
    if (cls && [cls instancesRespondToSelector:@selector(initWithMsgWrap:VideoPath:)]) {
        id player = [[cls alloc] initWithMsgWrap:nil VideoPath:path];
        UINavigationController *nav = vc.navigationController;
        if (nav) { [nav pushViewController:player animated:YES]; return; }
        [vc presentViewController:player animated:YES completion:nil];
        return;
    }
    // 兜底：MMMoviePlayerController 不可用时退回系统播放器
    AVPlayerViewController *player = [[AVPlayerViewController alloc] init];
    player.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    [vc presentViewController:player animated:YES completion:^{ [player.player play]; }];
}

// 下载图片直链到本地缓存（供"直接观看"，不存相册；复用 MD5 缓存）
+ (void)downloadImagesLocally:(NSArray<NSString *> *)urls completion:(void (^)(NSArray<NSString *> *paths))completion {
    if (!urls.count) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[]); }); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *out = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *imgURL in urls) {
            NSString *ext = @"jpg";
            if ([[imgURL pathExtension].lowercaseString isEqualToString:@"png"]) ext = @"png";
            NSString *path = DDPTempPathExt(imgURL, ext);
            if (![fm fileExistsAtPath:path]) {
                NSData *data = [[DDPEngine shared] downloadVideoFromURL:imgURL headers:nil];
                if (data.length) {
                    if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                    [data writeToFile:path atomically:YES];
                }
            }
            if ([fm fileExistsAtPath:path]) [out addObject:path];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(out); });
    });
}

// 直接观看图片（多图横向分页 + 捏合缩放），系统 UIKit，无第三方依赖
+ (void)presentImageViewer:(NSArray<NSString *> *)paths fromVC:(UIViewController *)vc {
    if (!paths.count || !vc) return;
    DDPImageViewerController *ivc = [[DDPImageViewerController alloc] init];
    ivc.imagePaths = paths;
    [vc presentViewController:ivc animated:YES completion:nil];
}

// 解析链接（对齐 PKC dyjxlj:，type=1 以文本消息发送原始直链）
// 视频→发 aweme 无水管直链；图文/滑块→发图片直链（每行一张）
+ (void)handleParseLink:(NSString *)url user:(NSString *)user {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if (err || type == DDPMediaTypeUnknown) { DDPShowSystemTip(@"解析失败"); return; }
                NSString *link = (type == DDPMediaTypeVideo)
                    ? videoURL
                    : [imageURLs componentsJoinedByString:@"\n"];
                if (!link.length) { DDPShowSystemTip(@"解析失败"); return; }
                DDPCopyToPasteboard(link);
                NSString *target = user.length ? user : DDPCurrentChatName();
                if (target.length) {
                    DDPSendTextMsg(link, target);   // 原始直链以文本消息发出
                    DDPShowSystemTip(@"已发送解析链接");
                } else {
                    DDPShowSystemTip(@"已复制无水印链接");
                }
            } @catch (NSException *e) {
                DDDLog(@"handleParseLink 异常 %@", e);
                DDPShowSystemTip(@"解析失败");
            }
        });
    }];
}

// 保存相册：视频→存视频；图文/滑块→下载存图片
+ (void)handleSaveAlbum:(NSString *)url {
    DDPShowSystemTip(@"抖音解析后台任务开始");
    [[DDPEngine shared] parseDouyinURL:url completion:^(DDPMediaType type, NSString *videoURL, NSArray<NSString *> *imageURLs, NSError *err) {
        @try {
            if (err || type == DDPMediaTypeUnknown) {
                dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"解析失败"); });
                return;
            }
            if (type == DDPMediaTypeVideo) {
                NSString *path = DDPTempPath(url);
                if (DDPFileUsable(path)) { [DDPPanel saveVideoToAlbumAtPath:path]; return; }
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSData *data = [[DDPEngine shared] downloadVideoFromURL:videoURL headers:nil];
                    BOOL ok = NO;
                    if (data.length) {
                        NSFileManager *fm = [NSFileManager defaultManager];
                        if ([fm fileExistsAtPath:path]) [fm removeItemAtPath:path error:nil];
                        ok = [data writeToFile:path atomically:YES];
                    }
                    if (ok) [DDPPanel saveVideoToAlbumAtPath:path];
                    else dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"保存失败"); });
                });
            } else {
                [self downloadAndSaveImages:imageURLs shareURL:url];
            }
        } @catch (NSException *e) {
            DDDLog(@"handleSaveAlbum 异常 %@", e);
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"保存失败"); });
        }
    }];
}

// 保存到相册（视频）
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

// 保存到相册（图片，图文/滑块）
+ (void)saveImageToAlbumAtPath:(NSString *)path {
    if (!path.length) return;
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{ DDPShowSystemTip(@"未授权相册权限"); });
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromImageAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError *error) {
            if (success) DDPShowSystemTip(@"已保存到相册");
            else DDPShowSystemTip(@"保存失败");
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

#pragma mark - 图片查看器（直接观看，多图横向分页 + 捏合缩放）

@implementation DDPImageViewerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    NSInteger n = self.imagePaths.count;
    self.pager = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.pager.pagingEnabled = YES;
    self.pager.showsHorizontalScrollIndicator = NO;
    self.pager.showsVerticalScrollIndicator = NO;
    self.pager.contentSize = CGSizeMake(w * n, h);
    self.pager.delegate = self;
    self.pager.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.pager];

    for (NSInteger i = 0; i < n; i++) {
        CGRect f = CGRectMake(w * i, 0, w, h);
        UIScrollView *zoom = [[UIScrollView alloc] initWithFrame:f];
        zoom.minimumZoomScale = 1.0;
        zoom.maximumZoomScale = 3.0;
        zoom.showsHorizontalScrollIndicator = NO;
        zoom.showsVerticalScrollIndicator = NO;
        zoom.delegate = self;
        UIImage *img = [UIImage imageWithContentsOfFile:self.imagePaths[i]];
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = YES;
        CGSize sz = [self fitSize:img.size inSize:CGSizeMake(w, h)];
        iv.frame = CGRectMake((w - sz.width) / 2, (h - sz.height) / 2, sz.width, sz.height);
        [zoom addSubview:iv];
        zoom.contentSize = CGSizeMake(w, h);
        [self.pager addSubview:zoom];
        // 单击关闭 / 双击放大（对齐 PKCShowImgVC handleDoubleTap:）
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSelf)];
        tap.numberOfTapsRequired = 1;
        UITapGestureRecognizer *dtap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTap:)];
        dtap.numberOfTapsRequired = 2;
        [tap requireGestureRecognizerToFail:dtap];
        [zoom addGestureRecognizer:tap];
        [zoom addGestureRecognizer:dtap];
    }

    // 关闭按钮（右上，对齐 PKCShowImgVC closeView）
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.frame = CGRectMake(w - 64, 20, 56, 32);
    [close addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // 保存到相册按钮（左上，对齐 PKCShowImgVC saveImageToCameraRoll:）
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:@"保存" forState:UIControlStateNormal];
    [save setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    save.frame = CGRectMake(20, 20, 56, 32);
    [save addTarget:self action:@selector(onSaveCurrent) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:save];

    if (n > 1) {
        self.pageCtl = [[UIPageControl alloc] initWithFrame:CGRectMake(0, h - 30, w, 20)];
        self.pageCtl.numberOfPages = n;
        self.pageCtl.currentPage = 0;
        [self.view addSubview:self.pageCtl];
    }
}

- (CGSize)fitSize:(CGSize)src inSize:(CGSize)box {
    if (src.width <= 0 || src.height <= 0) return box;
    CGFloat r = MIN(box.width / src.width, box.height / src.height);
    return CGSizeMake(src.width * r, src.height * r);
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.pager && self.pageCtl) {
        NSInteger p = (NSInteger)(self.pager.contentOffset.x / self.pager.bounds.size.width + 0.5);
        self.pageCtl.currentPage = p;
        self.currentIndex = p;
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    if (scrollView == self.pager) return nil;
    return scrollView.subviews.firstObject;
}

// 双击放大/还原（对齐 PKCShowImgVC handleDoubleTap:）
- (void)onDoubleTap:(UITapGestureRecognizer *)gesture {
    UIScrollView *zoom = (UIScrollView *)gesture.view;
    CGFloat scale = (zoom.zoomScale > 1.0) ? 1.0 : 2.0;
    [zoom setZoomScale:scale animated:YES];
}

// 保存当前图片到相册（对齐 PKCShowImgVC saveImageToCameraRoll:）
- (void)onSaveCurrent {
    if (self.currentIndex < 0 || self.currentIndex >= self.imagePaths.count) return;
    [DDPPanel saveImageToAlbumAtPath:self.imagePaths[self.currentIndex]];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
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
