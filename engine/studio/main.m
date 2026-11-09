// PGM Studio —— 素材浏览器（第一阶段）
// 列出工程里的背景/立绘/音乐，显示缩略图，点击生成对应指令并复制。
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>

static const CGFloat kThumbW = 128, kThumbH = 90;

@interface AssetItem : NSObject
@property (copy) NSString *name;      // 文件名
@property (copy) NSString *path;      // 完整路径
@property (copy) NSString *command;   // 要插入剧本的指令
@property (strong) NSImage *thumb;
@end
@implementation AssetItem @end

static NSSize imageSizeAtPath(NSString *path) {
    CGImageSourceRef src = CGImageSourceCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) return NSZeroSize;
    NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    CFRelease(src);
    return NSMakeSize([p[(id)kCGImagePropertyPixelWidth] doubleValue],
                      [p[(id)kCGImagePropertyPixelHeight] doubleValue]);
}

@interface PGMFlippedView : NSView
@property (copy) void (^onFileDrop)(NSArray<NSURL *> *urls);
@end
@implementation PGMFlippedView
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f]))
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    return self.onFileDrop ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    if (!self.onFileDrop) return NO;
    NSArray<NSURL *> *urls = [info.draggingPasteboard
        readObjectsForClasses:@[NSURL.class]
                      options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
    if (urls.count) self.onFileDrop(urls);
    return YES;
}
@end

@interface PGMDivider : NSView
@property (copy) void (^onDrag)(CGFloat xInSuperview);
@end
@implementation PGMDivider
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor];
}
- (void)drawRect:(NSRect)dirty {
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width / 2 - 0.5, 0, 1, self.bounds.size.height));
}
- (void)mouseDown:(NSEvent *)e {
    [self mouseDragged:e];
}
- (void)mouseDragged:(NSEvent *)e {
    if (!self.onDrag) return;
    NSPoint pt = [self.superview convertPoint:e.locationInWindow fromView:nil];
    self.onDrag(pt.x);
}
@end

@interface PGMPassLabel : NSTextField
@end
@implementation PGMPassLabel
- (NSView *)hitTest:(NSPoint)point { return nil; }   // 标签不吃鼠标事件
@end


@interface StudioController : NSObject <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *catTable;
@property (strong) NSScrollView *gridScroll;
@property (strong) PGMFlippedView *gridDoc;
@property (assign) NSInteger selItem;
@property (strong) NSTextField *status;
@property (strong) NSTextField *pathLabel;
@property (strong) NSArray<NSString *> *categories;
@property (strong) NSMutableDictionary<NSString *, NSArray<AssetItem *> *> *assets;
@property (copy) NSString *projectRoot;
@property (assign) NSInteger selCat;
// —— 剧本编辑 ——
@property (strong) NSView *assetView;
@property (strong) NSView *scriptView;
@property (strong) NSSegmentedControl *tabs;
@property (strong) NSTableView *fileTable;
@property (strong) NSTextView *editor;
@property (strong) NSArray<NSString *> *scriptFiles;
@property (copy) NSString *curScript;
@property (assign) BOOL dirty;
@property (strong) NSButton *runBtn;
@property (strong) NSButton *saveBtn;
@property (strong) AVAudioPlayer *player;
// —— 布局编辑 ——
@property (strong) NSView *layoutView;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *layoutValues;
@property (strong) NSMutableDictionary<NSString *, NSTextField *> *layoutReadouts;
@property (strong) NSMutableDictionary<NSString *, NSSlider *> *layoutSliders;
@property (strong) id previewView;
@property (assign) BOOL layoutDirty;
@property (copy) NSString *playingPath;
@property (assign) NSInteger previewOptionCount;
@property (strong) NSTextField *fitWarning;
@property (strong) NSArray<NSDictionary *> *swapSpecs;
@property (strong) NSScrollView *layoutPanel;
@property (strong) PGMDivider *layoutDivider;
@property (assign) CGFloat layoutPanelWidth;
@property (strong) NSView *layoutDoc;
@property (strong) NSMutableArray *layoutRows;
@end

@implementation StudioController

- (instancetype)init {
    if ((self = [super init])) {
        _categories = @[];
        _assets = [NSMutableDictionary dictionary];
        _scriptFiles = @[];
        _selCat = -1;
    }
    return self;
}

#pragma mark - 扫描工程

static BOOL isImage(NSString *p) {
    NSString *e = p.pathExtension.lowercaseString;
    return [e isEqualToString:@"png"] || [e isEqualToString:@"jpg"] || [e isEqualToString:@"jpeg"];
}
static BOOL isAudio(NSString *p) {
    NSString *e = p.pathExtension.lowercaseString;
    return [e isEqualToString:@"mp3"] || [e isEqualToString:@"wav"] || [e isEqualToString:@"ogg"];
}

- (NSImage *)thumbOf:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;
    NSDictionary *opts = @{ (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                            (id)kCGImageSourceThumbnailMaxPixelSize: @(kThumbW * 2),
                            (id)kCGImageSourceCreateThumbnailWithTransform: @YES };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cg) return nil;
    NSImage *img = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(kThumbW, kThumbH)];
    CGImageRelease(cg);
    return img;
}

- (NSString *)commandFor:(NSString *)file category:(NSString *)cat {
    NSString *base = file;
    NSString *stem = file.stringByDeletingPathExtension;
    if ([cat isEqualToString:@"bg"] || [cat isEqualToString:@"bgimage"])
        return [NSString stringWithFormat:@"bg(\"%@\")", base];
    if ([cat isEqualToString:@"fg"] || [cat isEqualToString:@"fgimage"])
        return [NSString stringWithFormat:@"fg(\"%@\")", base];
    if ([cat isEqualToString:@"音乐"])
        return [NSString stringWithFormat:@"bgm(\"%@\")", base];
    if ([cat isEqualToString:@"音效"])
        return [NSString stringWithFormat:@"sound(\"%@\")", base];
    if ([cat isEqualToString:@"语音"])
        return [NSString stringWithFormat:@"voice(\"%@\")", base];
    if (isImage(base))
        return [NSString stringWithFormat:@"fg(\"%@\")", base];
    return [NSString stringWithFormat:@"-- %@", stem];
}

- (void)loadProject:(NSString *)root {
    self.projectRoot = root;
    self.pathLabel.stringValue = root;
    self.window.title = [NSString stringWithFormat:@"PGM Studio — %@", root.lastPathComponent];
    self.selItem = -1;
    [NSUserDefaults.standardUserDefaults setObject:root forKey:@"lastProject"];
    [self.assets removeAllObjects];
    NSFileManager *fm = NSFileManager.defaultManager;

    // 图片：src/files/<类型>/...  也兼容解包出来的 bgimage / fgimage
    NSArray *imgRoots = @[ [root stringByAppendingPathComponent:@"src/files"],
                           [root stringByAppendingPathComponent:@"bgimage"],
                           [root stringByAppendingPathComponent:@"fgimage"],
                           [root stringByAppendingPathComponent:@"image"] ];
    for (NSString *r in imgRoots) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:r isDirectory:&isDir] || !isDir) continue;
        NSArray *subs = [fm contentsOfDirectoryAtPath:r error:NULL];
        // 目录里直接放着图片（解包出来的 bgimage/ 就是这种）
        {
            NSMutableArray *flat = [NSMutableArray array];
            for (NSString *f in subs) {
                if (!isImage(f)) continue;
                NSString *fp = [r stringByAppendingPathComponent:f];
                AssetItem *it = [AssetItem new];
                it.name = f; it.path = fp;
                it.command = [self commandFor:f category:r.lastPathComponent];
                it.thumb = [self thumbOf:fp];
                [flat addObject:it];
            }
            if (flat.count) {
                [flat sortUsingComparator:^NSComparisonResult(AssetItem *a, AssetItem *b){
                    return [a.name compare:b.name options:NSNumericSearch];
                }];
                self.assets[r.lastPathComponent] = flat;
            }
        }
        for (NSString *sub in subs) {
            if ([sub hasPrefix:@"."]) continue;
            NSString *sp = [r stringByAppendingPathComponent:sub];
            BOOL subIsDir = NO;
            [fm fileExistsAtPath:sp isDirectory:&subIsDir];
            if (!subIsDir) continue;
            NSMutableArray *items = [NSMutableArray array];
            for (NSString *f in [fm contentsOfDirectoryAtPath:sp error:NULL]) {
                if (!isImage(f)) continue;
                NSString *fp = [sp stringByAppendingPathComponent:f];
                AssetItem *it = [AssetItem new];
                it.name = f; it.path = fp;
                it.command = [self commandFor:f category:sub];
                it.thumb = [self thumbOf:fp];
                [items addObject:it];
            }
            if (items.count) {
                [items sortUsingComparator:^NSComparisonResult(AssetItem *a, AssetItem *b){
                    return [a.name compare:b.name options:NSNumericSearch];
                }];
                NSMutableArray *merged = [NSMutableArray arrayWithArray:self.assets[sub] ?: @[]];
                [merged addObjectsFromArray:items];
                self.assets[sub] = merged;
            }
        }
    }
    // 音频
    NSArray *audioDirs = @[ @[@"音乐", @"bgm"], @[@"音效", @"sound"], @[@"语音", @"voice"] ];
    for (NSArray *pair in audioDirs) {
        NSString *d = [[root stringByAppendingPathComponent:@"bin/data"]
                        stringByAppendingPathComponent:pair[1]];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:d isDirectory:&isDir] || !isDir) continue;
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:d error:NULL]) {
            if (!isAudio(f)) continue;
            AssetItem *it = [AssetItem new];
            it.name = f;
            it.path = [d stringByAppendingPathComponent:f];
            it.command = [self commandFor:f category:pair[0]];
            [items addObject:it];
        }
        if (items.count) {
            [items sortUsingComparator:^NSComparisonResult(AssetItem *a, AssetItem *b){
                return [a.name compare:b.name options:NSNumericSearch];
            }];
            self.assets[pair[0]] = items;
        }
    }

    NSMutableArray *cats = [NSMutableArray array];
    for (NSString *k in @[@"bg", @"fg", @"title", @"gallery", @"rule", @"system", @"音乐", @"音效", @"语音"]) {
        if (!self.assets[k]) self.assets[k] = @[];      // 空的也列出来，显示 0
        if (![cats containsObject:k]) [cats addObject:k];
    }
    for (NSString *k in self.assets.allKeys)
        if (![cats containsObject:k]) [cats addObject:k];
    self.categories = cats;
    self.selCat = cats.count ? 0 : -1;
    [self.catTable reloadData];
    if (cats.count) [self.catTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self rebuildGrid];
    NSInteger n = 0;
    for (NSString *k in cats) n += self.assets[k].count;
    self.status.stringValue = [NSString stringWithFormat:@"共 %ld 个素材，点一下即复制指令", (long)n];
    self.runBtn.enabled = (root.length > 0);
    [self loadScriptList];
    [self loadLayoutConfig];
    [self loadPreviewImages];
    [self loadGameFont];
    for (NSString *k in cats)
        fprintf(stdout, "  %-10s %3lu\n", k.UTF8String, (unsigned long)self.assets[k].count);
    fprintf(stdout, "  合计 %ld\n", (long)n);
    fflush(stdout);
}

#pragma mark - 界面

- (void)buildUI {
    NSRect frame = NSMakeRect(0, 0, 1100, 700);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
          backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"PGM Studio";
    self.window.delegate = self;
    NSView *cv = self.window.contentView;
    CGFloat W = frame.size.width, H = frame.size.height;

    // 顶部：页签切换
    self.tabs = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(16, H - 44, 280, 28)];
    self.tabs.segmentCount = 3;
    [self.tabs setLabel:@"素材" forSegment:0];
    [self.tabs setLabel:@"剧本" forSegment:1];
    [self.tabs setLabel:@"布局" forSegment:2];
    self.tabs.selectedSegment = 0;
    self.tabs.target = self;
    self.tabs.action = @selector(switchTab:);
    self.tabs.autoresizingMask = NSViewMinYMargin;
    [cv addSubview:self.tabs];

    NSButton *expBtn = [NSButton buttonWithTitle:@"导出游戏…" target:self action:@selector(exportGame:)];
    expBtn.frame = NSMakeRect(W - 366, H - 46, 110, 30);
    expBtn.autoresizingMask = NSViewMinYMargin|NSViewMinXMargin;
    [cv addSubview:expBtn];

    NSButton *newBtn = [NSButton buttonWithTitle:@"新建工程…" target:self action:@selector(newProject:)];
    newBtn.frame = NSMakeRect(W - 246, H - 46, 110, 30);
    newBtn.autoresizingMask = NSViewMinYMargin|NSViewMinXMargin;
    [cv addSubview:newBtn];

    NSButton *openBtn = [NSButton buttonWithTitle:@"打开工程…" target:self action:@selector(openProject:)];
    openBtn.frame = NSMakeRect(W - 126, H - 46, 110, 30);
    openBtn.autoresizingMask = NSViewMinYMargin|NSViewMinXMargin;
    [cv addSubview:openBtn];

    self.pathLabel = [[PGMPassLabel alloc] initWithFrame:NSMakeRect(16, H - 68, W - 380, 16)];
    self.pathLabel.stringValue = @"（未打开工程）";
    self.pathLabel.editable = NO;
    self.pathLabel.selectable = NO;
    self.pathLabel.bezeled = NO;
    self.pathLabel.drawsBackground = NO;
    self.pathLabel.autoresizingMask = NSViewWidthSizable|NSViewMinYMargin;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.pathLabel.textColor = NSColor.secondaryLabelColor;
    self.pathLabel.font = [NSFont systemFontOfSize:11];
    [cv addSubview:self.pathLabel];

    NSRect body = NSMakeRect(0, 26, W, H - 94);

    /* ---------------- 素材页 ---------------- */
    self.assetView = [[NSView alloc] initWithFrame:body];
    self.assetView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [cv addSubview:self.assetView];
    CGFloat aw = body.size.width, ah = body.size.height;

    NSScrollView *lsv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 170, ah)];
    lsv.autoresizingMask = NSViewHeightSizable;
    lsv.hasVerticalScroller = YES;
    lsv.drawsBackground = NO;
    self.catTable = [[NSTableView alloc] initWithFrame:lsv.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = 160;
    [self.catTable addTableColumn:col];
    self.catTable.headerView = nil;
    self.catTable.dataSource = self;
    self.catTable.delegate = self;
    self.catTable.rowHeight = 26;
    lsv.documentView = self.catTable;
    [self.assetView addSubview:lsv];

    self.gridScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(170, 0, aw - 170, ah)];
    self.gridScroll.hasVerticalScroller = YES;
    self.gridScroll.drawsBackground = NO;
    self.gridScroll.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    self.gridDoc = [[PGMFlippedView alloc] initWithFrame:NSMakeRect(0, 0, aw - 170, ah)];
    self.gridScroll.documentView = self.gridDoc;
    [self.assetView addSubview:self.gridScroll];

    __weak typeof(self) weakSelf = self;
    self.gridDoc.onFileDrop = ^(NSArray<NSURL *> *urls) {
        [weakSelf importFiles:urls];
    };

    /* ---------------- 剧本页 ---------------- */
    self.scriptView = [[NSView alloc] initWithFrame:body];
    self.scriptView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    self.scriptView.hidden = YES;
    [cv addSubview:self.scriptView];

    NSScrollView *fsv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, ah)];
    fsv.autoresizingMask = NSViewHeightSizable;
    fsv.hasVerticalScroller = YES;
    fsv.drawsBackground = NO;
    self.fileTable = [[NSTableView alloc] initWithFrame:fsv.bounds];
    NSTableColumn *fc = [[NSTableColumn alloc] initWithIdentifier:@"f"];
    fc.width = 190;
    [self.fileTable addTableColumn:fc];
    self.fileTable.headerView = nil;
    self.fileTable.dataSource = self;
    self.fileTable.delegate = self;
    self.fileTable.rowHeight = 24;
    fsv.documentView = self.fileTable;
    [self.scriptView addSubview:fsv];

    NSScrollView *esv = [[NSScrollView alloc] initWithFrame:NSMakeRect(200, 0, aw - 200, ah)];
    esv.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    esv.hasVerticalScroller = YES;
    esv.hasHorizontalScroller = YES;
    esv.borderType = NSNoBorder;
    self.editor = [[NSTextView alloc] initWithFrame:esv.bounds];
    self.editor.minSize = NSMakeSize(0, 0);
    self.editor.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.editor.verticallyResizable = YES;
    self.editor.horizontallyResizable = YES;
    self.editor.autoresizingMask = NSViewWidthSizable;
    self.editor.textContainer.widthTracksTextView = NO;
    self.editor.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.editor.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.editor.richText = NO;
    self.editor.allowsUndo = YES;
    self.editor.automaticQuoteSubstitutionEnabled = NO;
    self.editor.automaticDashSubstitutionEnabled = NO;
    self.editor.textColor = NSColor.textColor;
    self.editor.backgroundColor = NSColor.textBackgroundColor;
    self.editor.delegate = self;
    esv.documentView = self.editor;
    [self.scriptView addSubview:esv];

    /* ---------------- 底部 ---------------- */
    self.status = [NSTextField labelWithString:@"打开一个工程开始"];
    self.status.frame = NSMakeRect(16, 5, W - 300, 18);
    self.status.autoresizingMask = NSViewWidthSizable|NSViewMaxYMargin;
    self.status.font = [NSFont systemFontOfSize:12];
    self.status.textColor = NSColor.secondaryLabelColor;
    [cv addSubview:self.status];

    self.saveBtn = [NSButton buttonWithTitle:@"保存" target:self action:@selector(saveScript:)];
    self.saveBtn.frame = NSMakeRect(W - 200, 2, 84, 26);
    self.saveBtn.autoresizingMask = NSViewMinXMargin|NSViewMaxYMargin;
    self.saveBtn.keyEquivalent = @"s";
    self.saveBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    self.saveBtn.enabled = NO;
    [cv addSubview:self.saveBtn];

    self.runBtn = [NSButton buttonWithTitle:@"运行 ▶" target:self action:@selector(runGame:)];
    self.runBtn.frame = NSMakeRect(W - 110, 2, 94, 26);
    self.runBtn.autoresizingMask = NSViewMinXMargin|NSViewMaxYMargin;
    self.runBtn.bezelStyle = NSBezelStyleRounded;
    self.runBtn.enabled = NO;
    [cv addSubview:self.runBtn];

    [self buildLayoutTabIn:cv body:body];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildGrid]; });
}

- (void)switchTab:(id)sender {
    NSInteger t = self.tabs.selectedSegment;
    self.assetView.hidden  = (t != 0);
    self.scriptView.hidden = (t != 1);
    self.layoutView.hidden = (t != 2);
}

/* ---------- 剧本文件 ---------- */

- (void)loadScriptList {
    NSMutableArray *out = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *dirs = @[ @"src/user", @"src", @"scenario" ];
    for (NSString *d in dirs) {
        NSString *p = [self.projectRoot stringByAppendingPathComponent:d];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:p isDirectory:&isDir] || !isDir) continue;
        for (NSString *f in [fm contentsOfDirectoryAtPath:p error:NULL]) {
            NSString *e = f.pathExtension.lowercaseString;
            if ([e isEqualToString:@"ev"] || [e isEqualToString:@"ks"] || [e isEqualToString:@"lua"])
                [out addObject:[p stringByAppendingPathComponent:f]];
        }
    }
    [out sortUsingSelector:@selector(compare:)];
    self.scriptFiles = out;
    fprintf(stdout, "  剧本文件 %lu 个\n", (unsigned long)out.count);
    for (NSString *f in out) fprintf(stdout, "    %s\n", f.lastPathComponent.UTF8String);
    fflush(stdout);
    [self.fileTable reloadData];
    if (out.count) {
        [self.fileTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self openScript:out[0]];
    }
}

- (NSString *)readText:(NSString *)path {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return @"";
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s) return s;
    // 老文件是 GBK/GB18030
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    s = [[NSString alloc] initWithData:d encoding:gb];
    if (s) return s;
    return [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding] ?: @"";
}

- (void)openScript:(NSString *)path {
    self.curScript = path;
    self.editor.string = [self readText:path];
    self.dirty = NO;
    self.saveBtn.enabled = NO;
    self.status.stringValue = [NSString stringWithFormat:@"%@  ·  可直接编辑，保存后重新运行",
                               path.lastPathComponent];
}

- (void)saveScript:(id)sender {
    if (self.layoutDirty) {
        [self saveLayoutConfig];
        self.saveBtn.enabled = NO;
        return;
    }
    if (!self.curScript) return;
    NSError *err = nil;
    NSString *text = self.editor.string;
    if (![text writeToFile:self.curScript atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        self.status.stringValue = [NSString stringWithFormat:@"保存失败：%@", err.localizedDescription];
        return;
    }
    self.dirty = NO;
    self.saveBtn.enabled = NO;
    self.status.stringValue = [NSString stringWithFormat:@"已保存 %@", self.curScript.lastPathComponent];
}

- (void)runGame:(id)sender {
    if (!self.projectRoot) return;
    NSString *exeDir = NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent;
    NSString *engine = [exeDir stringByAppendingPathComponent:@"pgm-mac"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:engine]) {
        self.status.stringValue = @"找不到 pgm-mac，请先编译引擎";
        return;
    }
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:engine];
    t.arguments = @[ self.projectRoot ];
    t.currentDirectoryURL = [NSURL fileURLWithPath:exeDir];
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) {
        self.status.stringValue = [NSString stringWithFormat:@"启动失败：%@", err.localizedDescription];
        return;
    }
    self.status.stringValue = @"已启动游戏窗口";
}

- (void)windowDidResize:(NSNotification *)n {
    [self rebuildGrid];
    [self layoutPanes];
}

- (NSString *)templateRoot {
    // 优先用打进 App 的工程当模板；从源码跑就用当前工程
    NSString *res = NSBundle.mainBundle.resourcePath;
    if (res) {
        NSString *g = [res stringByAppendingPathComponent:@"game"];
        BOOL isDir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:g isDirectory:&isDir] && isDir)
            return g;
    }
    return self.projectRoot;
}

- (void)newProject:(id)sender {
    NSString *tpl = [self templateRoot];
    if (!tpl) {
        self.status.stringValue = @"找不到工程模板";
        return;
    }

    NSAlert *a = [NSAlert new];
    a.messageText = @"新建工程";
    a.informativeText = @"给新游戏起个名字（建议用英文或数字）：";
    [a addButtonWithTitle:@"下一步"];
    [a addButtonWithTitle:@"取消"];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    tf.placeholderString = @"my-game";
    a.accessoryView = tf;
    if ([a runModal] != NSAlertFirstButtonReturn) return;

    NSString *name = tf.stringValue;
    if (name.length == 0) {
        self.status.stringValue = @"没起名字，取消";
        return;
    }

    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
    op.canCreateDirectories = YES;
    op.prompt = @"建在这里";
    op.message = @"选一个文件夹放新工程";
    if ([op runModal] != NSModalResponseOK || !op.URL) return;

    NSString *dest = [op.URL.path stringByAppendingPathComponent:name];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dest]) {
        self.status.stringValue = [NSString stringWithFormat:@"%@ 已经存在", dest];
        return;
    }

    NSError *err = nil;
    [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:&err];
    for (NSString *sub in @[@"bin", @"src"]) {
        NSString *from = [tpl stringByAppendingPathComponent:sub];
        if (![fm fileExistsAtPath:from]) continue;
        if (![fm copyItemAtPath:from toPath:[dest stringByAppendingPathComponent:sub] error:&err]) {
            NSAlert *e = [NSAlert new];
            e.messageText = @"复制工程模板失败";
            e.informativeText = err.localizedDescription ?: @"未知错误";
            [e runModal];
            return;
        }
    }

    // 清掉模板里的存档和示例素材，新工程应该是干净的
    [fm removeItemAtPath:[dest stringByAppendingPathComponent:@"PGMSAVEDATA"] error:NULL];
    for (NSString *sub in @[@"src/files/bg", @"src/files/fg", @"src/files/gallery",
                            @"bin/data/bgm", @"bin/data/sound", @"bin/data/voice"]) {
        NSString *d = [dest stringByAppendingPathComponent:sub];
        for (NSString *f in [fm contentsOfDirectoryAtPath:d error:NULL]) {
            if ([f hasPrefix:@"."] || [f isEqualToString:@"README.txt"]) continue;
            if ([f.pathExtension.lowercaseString isEqualToString:@"lua"]) continue;  // CGlist.lua 保留
            [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:NULL];
        }
    }
    NSString *user = [dest stringByAppendingPathComponent:@"src/user"];
    [fm createDirectoryAtPath:user withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *emptyScript =
        @"-- 你的剧本写在这里\n"
        @"-- 一句台词两行：text(...) 然后 textcl()\n\n"
        @"*start\n"
        @"msgboxon()\n\n"
        @"text(\"第一句台词。\")\n"
        @"textcl()\n\n"
        @"jump(\"main.ev\")\n";
    [emptyScript writeToFile:[user stringByAppendingPathComponent:@"main.ev"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    if (![fm fileExistsAtPath:[dest stringByAppendingPathComponent:@"src/user/main.ev"]]) {
        NSAlert *e = [NSAlert new];
        e.messageText = @"新建失败";
        e.informativeText = [NSString stringWithFormat:@"没能写入 %@", dest];
        [e runModal];
        return;
    }

    [self loadProject:dest];
    self.status.stringValue = [NSString stringWithFormat:@"已新建并打开 %@", name];

    NSAlert *ok = [NSAlert new];
    ok.messageText = [NSString stringWithFormat:@"已创建「%@」", name];
    ok.informativeText = [NSString stringWithFormat:
        @"位置：%@\n\n舞台素材是空的，把图片放进 src/files/bg 和 src/files/fg 再回素材页刷新。", dest];
    [ok runModal];
}

- (NSString *)exportScriptPath {
    NSString *res = NSBundle.mainBundle.resourcePath;
    if (res) {
        NSString *p = [res stringByAppendingPathComponent:@"export-app.sh"];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) return p;
    }
    // 从源码跑：二进制在 build/Release/ 下，往上两层是仓库根
    NSString *exeDir = NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent;
    NSString *repo = [exeDir stringByDeletingLastPathComponent].stringByDeletingLastPathComponent;
    NSString *p = [repo stringByAppendingPathComponent:@"engine/scripts/export-app.sh"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) return p;
    return nil;
}

- (void)exportGame:(id)sender {
    if (!self.projectRoot) {
        self.status.stringValue = @"先打开一个工程";
        return;
    }
    NSString *script = [self exportScriptPath];
    NSString *exeDir = NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent;
    NSString *engine = [exeDir stringByAppendingPathComponent:@"pgm-mac"];
    if (!script || ![NSFileManager.defaultManager isExecutableFileAtPath:engine]) {
        self.status.stringValue = @"找不到导出脚本或引擎";
        return;
    }

    NSAlert *a = [NSAlert new];
    a.messageText = @"导出游戏";
    a.informativeText = @"给这个游戏起个名字（就是 .app 的名字）：";
    [a addButtonWithTitle:@"下一步"];
    [a addButtonWithTitle:@"取消"];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    tf.stringValue = self.projectRoot.lastPathComponent;
    a.accessoryView = tf;
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSString *name = tf.stringValue.length ? tf.stringValue : @"MyGame";

    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
    op.canCreateDirectories = YES;
    op.prompt = @"导出到这里";
    op.message = @"选一个文件夹放导出的 .app";
    if ([op runModal] != NSModalResponseOK || !op.URL) return;

    NSString *out = [[op.URL.path stringByAppendingPathComponent:name]
                        stringByAppendingPathExtension:@"app"];

    self.status.stringValue = @"正在导出…";
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSTask *t = [NSTask new];
        t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        t.arguments = @[ script, engine, self.projectRoot, out, name ];
        NSPipe *pipe = [NSPipe pipe];
        t.standardOutput = pipe;
        t.standardError = pipe;
        NSError *err = nil;
        BOOL ok = [t launchAndReturnError:&err] && ([t waitUntilExit], t.terminationStatus == 0);
        NSData *d = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *log = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                self.status.stringValue = [NSString stringWithFormat:@"导出完成：%@", out];
                [NSWorkspace.sharedWorkspace selectFile:out inFileViewerRootedAtPath:@""];
            } else {
                self.status.stringValue = @"导出失败，看下面的提示";
                NSAlert *e2 = [NSAlert new];
                e2.messageText = @"导出失败";
                e2.informativeText = log.length > 2000 ? [log substringToIndex:2000] : log;
                [e2 runModal];
            }
        });
    });
}

- (void)openProject:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseDirectories = YES;
    p.canChooseFiles = NO;
    p.message = @"选择 PGM 工程目录（含 bin/ 和 src/ 的那一层）";
    if ([p runModal] == NSModalResponseOK && p.URL)
        [self loadProject:p.URL.path];
}

#pragma mark - 表格

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == self.fileTable) return self.scriptFiles.count;
    return self.categories.count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTableCellView *v = [tv makeViewWithIdentifier:@"c" owner:self];
    if (!v) {
        v = [NSTableCellView new];
        v.identifier = @"c";
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.frame = NSMakeRect(10, 4, 150, 18);
        tf.font = [NSFont systemFontOfSize:13];
        tf.tag = 1;
        [v addSubview:tf];
        v.textField = tf;
    }
    if (tv == self.fileTable) {
        NSString *f = self.scriptFiles[row];
        v.textField.stringValue = f.lastPathComponent;
        v.textField.textColor = [f isEqualToString:self.curScript] ? NSColor.controlAccentColor
                                                                   : NSColor.labelColor;
        return v;
    }
    NSString *cat = self.categories[row];
    v.textField.stringValue = [NSString stringWithFormat:@"%@  (%lu)", cat,
                               (unsigned long)self.assets[cat].count];
    return v;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object == self.fileTable) {
        NSInteger r = self.fileTable.selectedRow;
        if (r >= 0) {
            [self openScript:self.scriptFiles[r]];
            [self.fileTable reloadData];
        }
        return;
    }
    NSInteger r = self.catTable.selectedRow;
    if (r < 0) return;
    self.selCat = r;
    [self rebuildGrid];
}

- (void)textDidChange:(NSNotification *)n {
    if (n.object != self.editor) return;
    self.dirty = YES;
    self.saveBtn.enabled = YES;
}

#pragma mark - 网格（手写，不用 NSCollectionView）

- (void)rebuildGrid {
    if (!self.gridDoc) return;
    for (NSView *v in self.gridDoc.subviews.copy) [v removeFromSuperview];
    if (self.selCat < 0 || self.selCat >= (NSInteger)self.categories.count) return;
    NSArray<AssetItem *> *list = self.assets[self.categories[self.selCat]];
    CGFloat clipW = self.gridScroll.contentView.bounds.size.width;
    if (clipW < 10) clipW = 600;
    CGFloat tileW = 132, tileH = 116, pad = 10;
    NSInteger cols = MAX(1, (NSInteger)((clipW - pad) / (tileW + pad)));
    NSInteger rows = (list.count + cols - 1) / cols;
    CGFloat totalH = pad + rows * (tileH + pad);
    self.gridDoc.frame = NSMakeRect(0, 0, clipW, MAX(totalH, self.gridScroll.contentView.bounds.size.height));

    for (NSInteger k = 0; k < (NSInteger)list.count; k++) {
        AssetItem *ai = list[k];
        NSInteger cx = k % cols, cy = k / cols;
        NSRect fr = NSMakeRect(pad + cx * (tileW + pad), pad + cy * (tileH + pad), tileW, tileH);

        NSButton *b = [[NSButton alloc] initWithFrame:fr];
        b.bordered = NO;
        b.imagePosition = NSImageAbove;
        b.imageScaling = NSImageScaleProportionallyUpOrDown;
        b.image = ai.thumb;
        b.target = self;
        b.action = @selector(tileClicked:);
        b.tag = k;
        b.toolTip = ai.name;

        NSString *shown = ai.name.stringByDeletingPathExtension;
        if (isAudio(ai.path)) {
            BOOL playing = self.playingPath && [self.playingPath isEqualToString:ai.path] && self.player.isPlaying;
            shown = [NSString stringWithFormat:@"%@ %@", playing ? @"■" : @"▶", shown];
        }
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.alignment = NSTextAlignmentCenter;
        ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
        b.attributedTitle = [[NSAttributedString alloc]
            initWithString:shown
                attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                              NSForegroundColorAttributeName: (k == self.selItem ? NSColor.controlAccentColor
                                                                                : NSColor.secondaryLabelColor),
                              NSParagraphStyleAttributeName: ps }];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *it1 = [[NSMenuItem alloc] initWithTitle:@"在访达中显示"
                                                     action:@selector(revealAsset:)
                                              keyEquivalent:@""];
        it1.target = self; it1.tag = k;
        [menu addItem:it1];
        NSMenuItem *it2 = [[NSMenuItem alloc] initWithTitle:@"删除文件"
                                                     action:@selector(deleteAsset:)
                                              keyEquivalent:@""];
        it2.target = self; it2.tag = k;
        [menu addItem:it2];
        b.menu = menu;

        [self.gridDoc addSubview:b];
    }
}

- (void)revealAsset:(NSMenuItem *)mi {
    NSArray<AssetItem *> *list = self.assets[self.categories[self.selCat]];
    if (mi.tag < 0 || mi.tag >= (NSInteger)list.count) return;
    [NSWorkspace.sharedWorkspace selectFile:list[mi.tag].path inFileViewerRootedAtPath:@""];
}

- (void)deleteAsset:(NSMenuItem *)mi {
    NSArray<AssetItem *> *list = self.assets[self.categories[self.selCat]];
    if (mi.tag < 0 || mi.tag >= (NSInteger)list.count) return;
    AssetItem *ai = list[mi.tag];

    NSAlert *a = [NSAlert new];
    a.messageText = @"删除文件";
    a.informativeText = [NSString stringWithFormat:@"确定删除「%@」吗？\n\n这个操作不可撤销。", ai.name];
    [a addButtonWithTitle:@"删除"];
    [a addButtonWithTitle:@"取消"];
    a.alertStyle = NSAlertStyleWarning;
    if ([a runModal] != NSAlertFirstButtonReturn) return;

    NSError *err = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:ai.path error:&err]) {
        NSAlert *e = [NSAlert new];
        e.messageText = @"删除失败";
        e.informativeText = err.localizedDescription ?: @"";
        [e runModal];
        return;
    }
    [self loadProject:self.projectRoot];
    self.status.stringValue = [NSString stringWithFormat:@"已删除 %@", ai.name];
}

- (void)importFiles:(NSArray<NSURL *> *)urls {
    if (!self.projectRoot) return;
    NSString *cat = (self.selCat >= 0 && self.selCat < (NSInteger)self.categories.count)
                    ? self.categories[self.selCat] : @"bg";
    NSArray *imgCats  = @[@"bg", @"fg", @"title", @"gallery", @"rule"];
    NSArray *audioMap = @[@"音乐", @"音效", @"语音"];

    NSString *sub = nil;
    if ([audioMap containsObject:cat]) {
        sub = [NSString stringWithFormat:@"bin/data/%@",
               [cat isEqualToString:@"音乐"] ? @"bgm" : ([cat isEqualToString:@"音效"] ? @"sound" : @"voice")];
    } else if ([imgCats containsObject:cat]) {
        sub = [NSString stringWithFormat:@"src/files/%@", cat];
    } else {
        self.status.stringValue = @"这个分类不能拖入，先选 bg / fg / 音乐 之类的";
        return;
    }

    NSString *dir = [self.projectRoot stringByAppendingPathComponent:sub];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

    NSInteger ok = 0;
    for (NSURL *u in urls) {
        NSString *name = u.lastPathComponent;
        NSString *dst = [dir stringByAppendingPathComponent:name];
        [fm removeItemAtPath:dst error:NULL];
        if ([fm copyItemAtPath:u.path toPath:dst error:NULL]) ok++;
    }
    [self loadProject:self.projectRoot];
    self.status.stringValue = [NSString stringWithFormat:@"导入 %ld 个文件到 %@", (long)ok, sub];
}

- (void)tileClicked:(NSButton *)b {
    NSArray<AssetItem *> *list = self.assets[self.categories[self.selCat]];
    if (b.tag < 0 || b.tag >= (NSInteger)list.count) return;
    self.selItem = b.tag;
    AssetItem *ai = list[b.tag];

    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:ai.command forType:NSPasteboardTypeString];
    NSString *hint = @"已复制";

    NSString *cat = self.categories[self.selCat];
    if (isAudio(ai.path)) {
        BOOL isMusic = [cat isEqualToString:@"音乐"];
        if (isMusic && self.player.isPlaying && [self.playingPath isEqualToString:ai.path]) {
            [self.player pause];
            self.playingPath = nil;
            hint = @"已复制 · 已暂停";
        } else {
            self.player = nil;
            self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:ai.path]
                                                                 error:NULL];
            if (self.player) {
                [self.player play];
                self.playingPath = ai.path;
                hint = [NSString stringWithFormat:@"已复制 · 播放中 (%.1fs)", self.player.duration];
            } else {
                hint = @"已复制 · 无法播放（macOS 不支持 ogg）";
            }
        }
    }
    self.status.stringValue = [NSString stringWithFormat:@"%@：%@", hint, ai.command];
    [self rebuildGrid];
}

- (void)buildLayoutTabIn:(NSView *)cv body:(NSRect)body {
    self.layoutView = [[NSView alloc] initWithFrame:body];
    self.layoutView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    self.layoutView.hidden = YES;
    [cv addSubview:self.layoutView];

    self.layoutValues = [NSMutableDictionary dictionary];
    self.layoutReadouts = [NSMutableDictionary dictionary];
    self.layoutSliders = [NSMutableDictionary dictionary];
    self.layoutRows = [NSMutableArray array];

    self.swapSpecs = @[
        @{ @"title": @"对话框",     @"file": @"msgbox01.png",    @"w": @480, @"h": @80  },
        @{ @"title": @"选项背景",   @"file": @"ramus_bg.png",    @"w": @480, @"h": @116 },
        @{ @"title": @"手型图标",   @"file": @"hand_icon02.png", @"w": @32,  @"h": @32  },
    ];

    NSMutableArray *spec = [NSMutableArray array];
    [spec addObject:@"素材替换"];
    for (NSDictionary *d in self.swapSpecs) [spec addObject:d];
    [spec addObject:@"对话框"];
    [spec addObjectsFromArray:@[
        @[@"MSGBOX_DY", @0, @272, @"框顶端"],
        @[@"DIALOG_NAME_DX", @0, @480, @"人名左"],
        @[@"DIALOG_NAME_DY", @0, @272, @"人名上"],
        @[@"MSGTEXT_DX", @0, @480, @"正文左"],
        @[@"MSGTEXT_DY", @0, @272, @"正文上"],
        @[@"MSGTEXT_LINELEN", @8, @40, @"每行字数"],
        @"选项菜单",
        @[@"RAMUS_BUTTON_BG_DY", @0, @272, @"起始位置"],
        @[@"RAMUS_BUTTON_STEP_DY", @20, @100, @"行距"],
        @[@"RAMUS_BUTTON_DX", @0, @240, @"文字左"],
        @[@"RAMUS_ICON_DY", @0, @272, @"手型图标"],
        @"游戏内菜单",
        @[@"MENU_BUTTON_DX", @0, @480, @"菜单左边"],
        @[@"MENU_BUTTON_DY", @0, @272, @"菜单顶端"],
        @[@"MENU_BUTTON_STEP_DY", @10, @60, @"按钮行距"],
        @"历史回想",
        @[@"HISTORY_TEXT_DX", @0, @480, @"正文左"],
        @[@"HISTORY_TEXT_DY", @0, @272, @"正文上"],
    ]];

    CGFloat rowH = 40, headerH = 26, y = 8;
    CGFloat panelW = 430;
    for (id entry in spec) y += [entry isKindOfClass:[NSString class]] ? headerH : rowH;

    PGMFlippedView *doc = [[PGMFlippedView alloc] initWithFrame:NSMakeRect(0, 0, panelW, y + 8)];
    CGFloat cy = 8;
    for (id entry in spec) {
        if ([entry isKindOfClass:[NSString class]]) {
            NSTextField *h = [NSTextField labelWithString:entry];
            h.frame = NSMakeRect(14, cy + 6, panelW - 28, 18);
            h.font = [NSFont boldSystemFontOfSize:11];
            h.textColor = NSColor.secondaryLabelColor;
            [doc addSubview:h];
            cy += headerH;
            continue;
        }
        if ([entry isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = entry;
            NSTextField *t = [NSTextField labelWithString:d[@"title"]];
            t.frame = NSMakeRect(22, cy + 10, 78, 18);
            t.font = [NSFont systemFontOfSize:11];
            [doc addSubview:t];

            NSTextField *info = [NSTextField labelWithString:
                [NSString stringWithFormat:@"%@  (%@×%@)",
                    d[@"file"], d[@"w"], d[@"h"]]];
            info.frame = NSMakeRect(100, cy + 10, 190, 18);
            info.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
            info.textColor = NSColor.secondaryLabelColor;
            info.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [doc addSubview:info];

            NSButton *sw = [NSButton buttonWithTitle:@"换…" target:self action:@selector(swapAsset:)];
            sw.frame = NSMakeRect(296, cy + 6, 60, 26);
            sw.tag = [self.swapSpecs indexOfObject:d];
            sw.bezelStyle = NSBezelStyleRounded;
            [doc addSubview:sw];
            cy += rowH;
            continue;
        }

        NSArray *k = entry;
        NSTextField *lbl = [NSTextField labelWithString:k[3]];
        lbl.frame = NSMakeRect(22, cy + 10, 78, 18);
        lbl.font = [NSFont systemFontOfSize:11];
        [doc addSubview:lbl];

        NSSlider *sl = [[NSSlider alloc] initWithFrame:NSMakeRect(98, cy + 6, 172, 24)];
        sl.minValue = [k[1] doubleValue];
        sl.maxValue = [k[2] doubleValue];
        sl.identifier = k[0];
        sl.target = self;
        sl.action = @selector(layoutSliderChanged:);
        sl.continuous = YES;
        [doc addSubview:sl];

        NSTextField *val = [NSTextField labelWithString:@"—"];
        val.frame = NSMakeRect(276, cy + 10, 148, 18);
        val.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
        val.textColor = NSColor.secondaryLabelColor;
        val.alignment = NSTextAlignmentRight;
        val.toolTip = k[0];           // 完整参数名放提示里
        [doc addSubview:val];

        [self.layoutRows addObject:@[ sl, val, lbl ]];
        self.layoutReadouts[k[0]] = val;
        self.layoutSliders[k[0]] = sl;
        self.layoutValues[k[0]] = @(sl.doubleValue);
        cy += rowH;
    }

    // 顶部：预览选项个数
    NSTextField *ocLbl = [NSTextField labelWithString:@"预览选项数"];
    ocLbl.frame = NSMakeRect(14, body.size.height - 28, 88, 18);
    ocLbl.font = [NSFont systemFontOfSize:11];
    ocLbl.textColor = NSColor.secondaryLabelColor;
    [self.layoutView addSubview:ocLbl];

    NSButton *handChk = [NSButton checkboxWithTitle:@"显示手型" target:self action:@selector(handToggle:)];
    handChk.frame = NSMakeRect(200, body.size.height - 30, 110, 22);
    handChk.state = NSControlStateValueOn;
    [self.layoutView addSubview:handChk];

    NSSegmentedControl *oc = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(104, body.size.height - 32, 200, 26)];
    oc.segmentCount = 4;
    for (int i = 0; i < 4; i++) [oc setLabel:[NSString stringWithFormat:@"%d", i + 1] forSegment:i];
    oc.selectedSegment = 1;
    oc.frame = NSMakeRect(104, body.size.height - 32, 90, 26);
    oc.target = self;
    oc.action = @selector(optionCountChanged:);
    [self.layoutView addSubview:oc];

    self.fitWarning = [NSTextField labelWithString:@""];
    self.fitWarning.frame = NSMakeRect(324, body.size.height - 28, body.size.width - 340, 18);
    self.fitWarning.font = [NSFont systemFontOfSize:11];
    self.fitWarning.textColor = NSColor.systemRedColor;
    self.fitWarning.autoresizingMask = NSViewWidthSizable;
    [self.layoutView addSubview:self.fitWarning];

    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, panelW, body.size.height - 38)];
    sv.autoresizingMask = NSViewHeightSizable;
    sv.hasVerticalScroller = YES;
    sv.drawsBackground = NO;
    sv.documentView = doc;
    self.layoutDoc = doc;

    self.layoutPanelWidth = panelW;
    self.layoutPanel = sv;
    [self.layoutView addSubview:sv];

    Class dv = NSClassFromString(@"PGMDivider");
    self.layoutDivider = [[dv alloc] initWithFrame:NSMakeRect(panelW, 0, 6, body.size.height - 38)];
    self.layoutDivider.autoresizingMask = NSViewHeightSizable;
    __weak typeof(self) ws = self;
    self.layoutDivider.onDrag = ^(CGFloat x) {
        CGFloat w = MIN(MAX(x, 360), ws.layoutView.bounds.size.width - 240);
        ws.layoutPanelWidth = w;
        [ws layoutPanes];
    };
    [self.layoutView addSubview:self.layoutDivider];

    Class pv = NSClassFromString(@"PGMPreviewView");
    self.previewView = [[pv alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [self.layoutView addSubview:(NSView *)self.previewView];

    [self layoutPanes];
}

- (void)layoutSliderChanged:(NSSlider *)sl {
    self.layoutValues[sl.identifier] = @(sl.doubleValue);
    NSTextField *val = self.layoutReadouts[sl.identifier];
    val.stringValue = [NSString stringWithFormat:@"%d", (int)sl.doubleValue];
    [self.previewView setValue:self.layoutValues forKey:@"values"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
    self.layoutDirty = YES;
    self.saveBtn.enabled = YES;
    [self updateFitWarning];
}

- (void)loadGameFont {
    NSString *fp = [self.projectRoot stringByAppendingPathComponent:@"bin/data/font/fz.ttf"];
    if (![NSFileManager.defaultManager fileExistsAtPath:fp]) return;
    NSURL *url = [NSURL fileURLWithPath:fp];
    CFArrayRef descs = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (!descs) return;
    if (CFArrayGetCount(descs) > 0) {
        CTFontDescriptorRef d = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descs, 0);
        CTFontRef ct = CTFontCreateWithFontDescriptor(d, 15.0, NULL);
        NSFont *f = (__bridge_transfer NSFont *)ct;
        [self.previewView setValue:f forKey:@"gameFont"];
        fprintf(stdout, "  预览字体: %s\n", f.fontName.UTF8String);
    }
    CFRelease(descs);
    [(NSView *)self.previewView setNeedsDisplay:YES];
}

- (void)loadPreviewImages {
    NSString *sys = [self.projectRoot stringByAppendingPathComponent:@"src/files/system"];
    NSImage *(^img)(NSString *) = ^NSImage *(NSString *n) {
        NSString *p = [sys stringByAppendingPathComponent:n];
        return [NSImage.alloc initWithContentsOfFile:p];
    };
    [self.previewView setValue:img(@"msgbox01.png") forKey:@"msgboxImage"];
    [self.previewView setValue:img(@"ramus_bg.png")  forKey:@"ramusImage"];
    [self.previewView setValue:img(@"hand_icon02.png") forKey:@"handImage"];
    self.previewOptionCount = 2;
    [self.previewView setValue:@YES forKey:@"showHand"];
    [self.previewView setValue:@(2) forKey:@"optionCount"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
}

- (void)layoutPanes {
    if (!self.layoutView) return;
    CGFloat W = self.layoutView.bounds.size.width;
    CGFloat H = self.layoutView.bounds.size.height - 38;
    CGFloat pw = MAX(self.layoutPanelWidth, 360);

    // 左边内容跟着面板宽度一起伸缩
    if (self.layoutDoc) {
        self.layoutDoc.frame = NSMakeRect(0, 0, pw, self.layoutDoc.frame.size.height);
        CGFloat valW = 64, valX = pw - valW - 12;
        CGFloat sliderX = 96, sliderW = MAX(valX - sliderX - 12, 70);
        for (NSArray *row in self.layoutRows) {
            NSSlider *sl = row[0];
            NSTextField *val = row[1];
            sl.frame = NSMakeRect(sliderX, sl.frame.origin.y, sliderW, 24);
            val.frame = NSMakeRect(valX, val.frame.origin.y, valW, 18);
        }
    }
    self.layoutPanel.frame = NSMakeRect(0, 0, pw, H);
    self.layoutDivider.frame = NSMakeRect(pw, 0, 6, H);
    NSView *pv = (NSView *)self.previewView;
    pv.frame = NSMakeRect(pw + 6, 0, MAX(W - pw - 6, 10), H);
    [pv setNeedsDisplay:YES];
}

- (void)swapAsset:(NSButton *)b {
    if (b.tag < 0 || b.tag >= (NSInteger)self.swapSpecs.count) return;
    NSDictionary *d = self.swapSpecs[b.tag];
    NSString *fname = d[@"file"];
    CGFloat needW = [d[@"w"] doubleValue], needH = [d[@"h"] doubleValue];

    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseFiles = YES;
    op.canChooseDirectories = NO;
    op.allowedFileTypes = @[@"png", @"jpg", @"jpeg"];
    op.message = [NSString stringWithFormat:@"选择新的「%@」图片（需要 %.0f×%.0f）",
                  d[@"title"], needW, needH];
    if ([op runModal] != NSModalResponseOK || !op.URL) return;

    NSString *src = op.URL.path;
    NSSize sz = imageSizeAtPath(src);
    if (sz.width != needW || sz.height != needH) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"尺寸不对";
        a.informativeText = [NSString stringWithFormat:
            @"「%@」必须是 %.0f×%.0f，你选的是 %.0f×%.0f。\n\n可以用预览或 sips 先改尺寸。",
            d[@"title"], needW, needH, sz.width, sz.height];
        [a runModal];
        return;
    }

    NSString *dir = [self.projectRoot stringByAppendingPathComponent:@"src/files/system"];
    NSString *dst = [dir stringByAppendingPathComponent:fname];
    NSString *bak = [dir stringByAppendingPathComponent:
        [[fname stringByDeletingPathExtension] stringByAppendingString:@"_orig.png"]];

    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:bak] && [fm fileExistsAtPath:dst])
        [fm copyItemAtPath:dst toPath:bak error:NULL];
    [fm removeItemAtPath:dst error:NULL];
    NSError *err = nil;
    if (![fm copyItemAtPath:src toPath:dst error:&err]) {
        self.status.stringValue = [NSString stringWithFormat:@"替换失败：%@", err.localizedDescription];
        return;
    }
    [self loadPreviewImages];
    [self rebuildGrid];
    self.status.stringValue = [NSString stringWithFormat:
        @"已替换 %@，原图备份为 %@", fname, bak.lastPathComponent];
}

- (void)handToggle:(NSButton *)b {
    [self.previewView setValue:@(b.state == NSControlStateValueOn) forKey:@"showHand"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
}

- (void)updateFitWarning {
    if (!self.fitWarning) return;
    int msgDY = self.layoutValues[@"MSGBOX_DY"].intValue;
    int start = self.layoutValues[@"RAMUS_BUTTON_BG_DY"].intValue;
    int step  = self.layoutValues[@"RAMUS_BUTTON_STEP_DY"].intValue;
    NSInteger n = self.previewOptionCount;
    int lastBottom = start + (int)(n - 1) * step + 58;
    if (n > 1 && lastBottom > msgDY - 4) {
        self.fitWarning.stringValue = [NSString stringWithFormat:
            @"⚠︎ %ld 个选项会压到对话框（底 %d > 框顶 %d）", (long)n, lastBottom, msgDY];
    } else if (step < 58) {
        self.fitWarning.stringValue = @"⚠︎ 行距小于 58，选项会重叠";
    } else {
        self.fitWarning.stringValue = @"";
    }
}

- (void)optionCountChanged:(NSSegmentedControl *)sc {
    self.previewOptionCount = sc.selectedSegment + 1;
    [self.previewView setValue:@(self.previewOptionCount) forKey:@"optionCount"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
    [self updateFitWarning];
}

- (void)loadLayoutConfig {
    if (!self.projectRoot) return;
    NSString *cfg = [self.projectRoot stringByAppendingPathComponent:@"src/user/config.lua"];
    NSString *text = [self readText:cfg];
    if (!text.length) {
        self.status.stringValue = @"没找到 src/user/config.lua";
        return;
    }
    for (NSString *key in self.layoutValues.allKeys) {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:[NSString stringWithFormat:@"(?m)^\\s*%@\\s*=\\s*([0-9]+)", key]
                                 options:0 error:NULL];
        NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (!m) continue;
        NSInteger v = [[text substringWithRange:[m rangeAtIndex:1]] integerValue];
        self.layoutValues[key] = @(v);
        NSTextField *val = self.layoutReadouts[key];
        val.stringValue = [NSString stringWithFormat:@"%ld", (long)v];
    }
    [self.previewView setValue:self.layoutValues forKey:@"values"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
    // 滑块位置
    for (NSString *key in self.layoutSliders) {
        NSSlider *sl = self.layoutSliders[key];
        NSNumber *v = self.layoutValues[key];
        if (v) sl.doubleValue = v.doubleValue;
    }
    self.layoutDirty = NO;
}

- (void)saveLayoutConfig {
    if (!self.projectRoot) return;
    NSString *cfg = [self.projectRoot stringByAppendingPathComponent:@"src/user/config.lua"];
    NSMutableString *text = [[self readText:cfg] mutableCopy];
    if (!text.length) { self.status.stringValue = @"没有 config.lua 可写"; return; }
    for (NSString *key in self.layoutValues.allKeys) {
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:[NSString stringWithFormat:@"(?m)^(\\s*%@\\s*=\\s*)([0-9]+)", key]
                                 options:0 error:NULL];
        NSString *rep = [NSString stringWithFormat:@"$1%d", self.layoutValues[key].intValue];
        NSRange r = NSMakeRange(0, text.length);
        if ([re firstMatchInString:text options:0 range:r])
            [re replaceMatchesInString:text options:0 range:r withTemplate:rep];
    }
    NSError *err = nil;
    if (![text writeToFile:cfg atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        self.status.stringValue = [NSString stringWithFormat:@"写入失败：%@", err.localizedDescription];
        return;
    }
    self.layoutDirty = NO;
    self.status.stringValue = @"布局已写入 config.lua，重新运行即可生效";
}

@end


@interface PGMAppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation PGMAppDelegate

// 关掉最后一个窗口就退出，别留在 Dock 里
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

// 点 Dock 图标时把窗口叫回来（万一还有窗口）
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        for (NSWindow *w in sender.windows) {
            [w makeKeyAndOrderFront:nil];
            break;
        }
    }
    return YES;
}

@end

@interface PGMPreviewView : NSView
@property (strong) NSDictionary<NSString *, NSNumber *> *values;
@property (strong) NSImage *msgboxImage;
@property (strong) NSImage *ramusImage;
@property (strong) NSImage *handImage;
@property (assign) NSInteger optionCount;
@property (assign) BOOL showHand;
@property (strong) NSFont *gameFont;
@end

@implementation PGMPreviewView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    [[NSColor darkGrayColor] setFill];
    NSRectFill(self.bounds);

    CGFloat cw = self.bounds.size.width  - 24;
    CGFloat ch = self.bounds.size.height - 24;
    CGFloat sc = MIN(cw / 480.0, ch / 272.0);
    if (sc <= 0) return;
    CGFloat ox = (self.bounds.size.width  - 480 * sc) / 2;
    CGFloat oy = (self.bounds.size.height - 272 * sc) / 2;

    NSGraphicsContext *ctx = NSGraphicsContext.currentContext;
    [ctx saveGraphicsState];
    NSAffineTransform *t = [NSAffineTransform transform];
    [t translateXBy:ox yBy:oy];
    [t scaleBy:sc];
    [t concat];

    // 背景画布
    [[NSColor colorWithCalibratedRed:0.16 green:0.18 blue:0.26 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, 480, 272));

    int msgDY   = [self.values[@"MSGBOX_DY"] intValue];
    int nameDX  = [self.values[@"DIALOG_NAME_DX"] intValue];
    int nameDY  = [self.values[@"DIALOG_NAME_DY"] intValue];
    int textDX  = [self.values[@"MSGTEXT_DX"] intValue];
    int textDY  = [self.values[@"MSGTEXT_DY"] intValue];
    int lineLen = [self.values[@"MSGTEXT_LINELEN"] intValue];
    int ramDY   = [self.values[@"RAMUS_BUTTON_BG_DY"] intValue];
    int ramStep = [self.values[@"RAMUS_BUTTON_STEP_DY"] intValue];
    int iconDY  = [self.values[@"RAMUS_ICON_DY"] intValue];

    // 对话框：直接画真图，保证和游戏里一模一样
    if (self.msgboxImage) {
        [self.msgboxImage drawInRect:NSMakeRect(0, msgDY, 480, 80)
                            fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                           fraction:1.0 respectFlipped:YES hints:nil];
    } else {
        NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, msgDY, 480, 80)
                                                           xRadius:8 yRadius:8];
        [[NSColor colorWithCalibratedRed:0.85 green:0.84 blue:0.80 alpha:0.95] setFill];
        [box fill];
    }

    // 用游戏自己的字体，字格 16x18
    NSFont *gf = self.gameFont ?: [NSFont systemFontOfSize:15];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.minimumLineHeight = 18;
    ps.maximumLineHeight = 18;
    NSDictionary *attr = @{ NSFontAttributeName: gf,
                            NSForegroundColorAttributeName: NSColor.blackColor,
                            NSParagraphStyleAttributeName: ps };

    // —— 坐标参考线，方便看出起点到底在哪 ——
    [[NSColor colorWithCalibratedRed:1 green:0.35 blue:0.35 alpha:0.85] setStroke];
    NSBezierPath *v = [NSBezierPath bezierPath];
    [v moveToPoint:NSMakePoint(nameDX + 0.5, 0)];
    [v lineToPoint:NSMakePoint(nameDX + 0.5, 272)];
    v.lineWidth = 1; [v stroke];
    NSBezierPath *h = [NSBezierPath bezierPath];
    [h moveToPoint:NSMakePoint(0, nameDY + 0.5)];
    [h lineToPoint:NSMakePoint(480, nameDY + 0.5)];
    h.lineWidth = 1; [h stroke];

    [[NSColor colorWithCalibratedRed:0.2 green:0.9 blue:0.4 alpha:0.85] setStroke];
    NSBezierPath *tv = [NSBezierPath bezierPath];
    [tv moveToPoint:NSMakePoint(textDX + 0.5, msgDY)];
    [tv lineToPoint:NSMakePoint(textDX + 0.5, msgDY + 80)];
    tv.lineWidth = 1; [tv stroke];
    for (int i = 0; i < 3; i++) {
        NSBezierPath *th = [NSBezierPath bezierPath];
        [th moveToPoint:NSMakePoint(0, textDY + i * 18 + 0.5)];
        [th lineToPoint:NSMakePoint(480, textDY + i * 18 + 0.5)];
        th.lineWidth = 1; [th stroke];
    }

    // 人名：先画字格边界（红框），再画字
    [[NSColor colorWithCalibratedRed:1 green:0.2 blue:0.2 alpha:0.55] setStroke];
    NSBezierPath *nbox = [NSBezierPath bezierPathWithRect:NSMakeRect(nameDX, nameDY, 32, 18)];
    nbox.lineWidth = 1; [nbox stroke];
    [@"人名" drawInRect:NSMakeRect(nameDX, nameDY, 32, 18) withAttributes:attr];

    // 正文：字格边界 + 每字 16 宽
    int cols = MIN(lineLen, 24);
    [[NSColor colorWithCalibratedRed:0.2 green:0.9 blue:0.4 alpha:0.35] setStroke];
    for (int i = 0; i < 3; i++) {
        NSBezierPath *rb = [NSBezierPath bezierPathWithRect:
            NSMakeRect(textDX, textDY + i * 18, cols * 16, 18)];
        rb.lineWidth = 1; [rb stroke];
        for (int c = 0; c < cols; c++)
            [@"字" drawInRect:NSMakeRect(textDX + c * 16, textDY + i * 18, 16, 18)
               withAttributes:attr];
    }

    // 选项：同样用真图（ramus_bg.png 是上下两帧，58px 一帧）
    NSInteger optN = self.optionCount > 0 ? self.optionCount : 2;
    for (NSInteger i = 0; i < optN; i++) {
        NSRect r = NSMakeRect(0, ramDY + i * ramStep, 480, 58);
        if (r.origin.y + 58 > 272) break;
        if (self.ramusImage) {
            [self.ramusImage drawInRect:r fromRect:NSZeroRect
                              operation:NSCompositingOperationSourceOver
                               fraction:1.0 respectFlipped:YES hints:nil];
        } else {
            NSBezierPath *b = [NSBezierPath bezierPathWithRoundedRect:r xRadius:8 yRadius:8];
            [[NSColor colorWithCalibratedRed:0.72 green:0.74 blue:0.82 alpha:0.85] setFill];
            [b fill];
        }
        [[NSString stringWithFormat:@"选项 %ld", (long)(i + 1)]
            drawAtPoint:NSMakePoint(24, r.origin.y + 20) withAttributes:attr];
    }

    // 手型图标
    if (self.showHand) {
        if (self.handImage) {
            [self.handImage drawInRect:NSMakeRect(6, iconDY - 12, 32, 32)
                              fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                               fraction:1.0 respectFlipped:YES hints:nil];
        } else {
            [[NSColor systemYellowColor] setFill];
            NSRectFill(NSMakeRect(6, iconDY, 16, 16));
        }
    }

    [ctx restoreGraphicsState];

    // 边框和尺寸标注
    NSFrameRect(NSMakeRect(ox, oy, 480 * sc, 272 * sc));
    [[NSColor secondaryLabelColor] set];
    NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                             NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
    [@"480 × 272（PSP 实际分辨率）" drawAtPoint:NSMakePoint(ox, oy + 272 * sc + 4)
                                withAttributes:small];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        static PGMAppDelegate *delegate = nil;
        delegate = [PGMAppDelegate new];
        NSApp.delegate = delegate;

        NSMenu *mb = [NSMenu new];
        NSMenuItem *appItem = [NSMenuItem new];
        [mb addItem:appItem];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItemWithTitle:@"隐藏 PGM Studio" action:@selector(hide:) keyEquivalent:@"h"];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"退出 PGM Studio" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        NSApp.mainMenu = mb;

        StudioController *c = [StudioController new];
        [c buildUI];
        NSString *proj = nil;
        if (argc > 1) {
            proj = [NSString stringWithUTF8String:argv[1]];
        } else {
            // 双击启动（从 .app 里跑）时，用打进包里的默认工程
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:@"lastProject"];
            BOOL isDir = NO;
            if (last.length && [fm fileExistsAtPath:last isDirectory:&isDir] && isDir) {
                proj = last;                       // 接着上次的工程
            } else {
                NSString *res = NSBundle.mainBundle.resourcePath;
                if (res) {
                    NSString *bundled = [res stringByAppendingPathComponent:@"game"];
                    if ([fm fileExistsAtPath:bundled isDirectory:&isDir] && isDir)
                        proj = bundled;
                }
            }
        }
        if (proj) [c loadProject:proj];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
