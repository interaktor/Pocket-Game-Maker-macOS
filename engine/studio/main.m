// PGM Studio —— 素材浏览器（第一阶段）
// 列出工程里的背景/立绘/音乐，显示缩略图，点击生成对应指令并复制。
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>

static const CGFloat kThumbW = 128, kThumbH = 90;

@interface AssetItem : NSObject
@property (copy) NSString *name;      // 文件名
@property (copy) NSString *path;      // 完整路径
@property (copy) NSString *command;   // 要插入剧本的指令
@property (strong) NSImage *thumb;
@end
@implementation AssetItem @end

@interface PGMFlippedView : NSView
@end
@implementation PGMFlippedView
- (BOOL)isFlipped { return YES; }
@end


@interface StudioController : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *catTable;
@property (strong) NSCollectionView *grid;
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
    for (NSString *k in @[@"bg", @"fg", @"title", @"gallery", @"rule", @"system", @"音乐", @"音效", @"语音"])
        if (self.assets[k]) [cats addObject:k];
    for (NSString *k in self.assets.allKeys)
        if (![cats containsObject:k]) [cats addObject:k];
    self.categories = cats;
    self.selCat = cats.count ? 0 : -1;
    [self.catTable reloadData];
    if (cats.count) [self.catTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self.grid reloadData];
    NSInteger n = 0;
    for (NSString *k in cats) n += self.assets[k].count;
    self.status.stringValue = [NSString stringWithFormat:@"共 %ld 个素材，点一下即复制指令", (long)n];
    self.runBtn.enabled = (root.length > 0);
    [self loadScriptList];
    [self loadLayoutConfig];
    [self loadPreviewImages];
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

    NSButton *openBtn = [NSButton buttonWithTitle:@"打开工程…" target:self action:@selector(openProject:)];
    openBtn.frame = NSMakeRect(W - 126, H - 46, 110, 30);
    openBtn.autoresizingMask = NSViewMinYMargin|NSViewMinXMargin;
    [cv addSubview:openBtn];

    self.pathLabel = [NSTextField labelWithString:@"（未打开工程）"];
    self.pathLabel.frame = NSMakeRect(308, H - 40, W - 446, 18);
    self.pathLabel.autoresizingMask = NSViewWidthSizable|NSViewMinYMargin;
    self.pathLabel.textColor = NSColor.secondaryLabelColor;
    self.pathLabel.font = [NSFont systemFontOfSize:11];
    [cv addSubview:self.pathLabel];

    NSRect body = NSMakeRect(0, 26, W, H - 74);

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

    NSCollectionViewFlowLayout *layout = [NSCollectionViewFlowLayout new];
    layout.itemSize = NSMakeSize(kThumbW + 16, kThumbH + 34);
    layout.sectionInset = NSEdgeInsetsMake(12, 12, 12, 12);
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    self.grid = [[NSCollectionView alloc] initWithFrame:NSMakeRect(170, 0, aw - 170, ah)];
    self.grid.collectionViewLayout = layout;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.selectable = YES;
    [self.grid registerClass:[NSCollectionViewItem class] forItemWithIdentifier:@"cell"];
    NSScrollView *gsv = [[NSScrollView alloc] initWithFrame:NSMakeRect(170, 0, aw - 170, ah)];
    gsv.documentView = self.grid;
    gsv.hasVerticalScroller = YES;
    gsv.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [self.assetView addSubview:gsv];

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
    [self.grid reloadData];
}

- (void)textDidChange:(NSNotification *)n {
    if (n.object != self.editor) return;
    self.dirty = YES;
    self.saveBtn.enabled = YES;
}

#pragma mark - 网格

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    if (self.selCat < 0) return 0;
    return self.assets[self.categories[self.selCat]].count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip {
    NSCollectionViewItem *item = [cv makeItemWithIdentifier:@"cell" forIndexPath:ip];
    NSArray<AssetItem *> *list = self.assets[self.categories[self.selCat]];
    AssetItem *ai = list[ip.item];

    NSView *v = item.view;
    for (NSView *sub in v.subviews.copy) [sub removeFromSuperview];

    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 26, kThumbW, kThumbH)];
    iv.imageScaling = NSImageScaleProportionallyUpOrDown;
    iv.image = ai.thumb;
    iv.wantsLayer = YES;
    iv.layer.cornerRadius = 4;
    iv.layer.masksToBounds = YES;
    iv.layer.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.12].CGColor;
    [v addSubview:iv];

    NSString *shown = ai.name.stringByDeletingPathExtension;
    if (isAudio(ai.path)) {
        BOOL playing = self.playingPath && [self.playingPath isEqualToString:ai.path] && self.player.isPlaying;
        shown = [NSString stringWithFormat:@"%@ %@", playing ? @"■" : @"▶", shown];
    }
    NSTextField *tf = [NSTextField labelWithString:shown];
    tf.frame = NSMakeRect(8, 6, kThumbW, 16);
    tf.font = [NSFont systemFontOfSize:10];
    tf.alignment = NSTextAlignmentCenter;
    tf.lineBreakMode = NSLineBreakByTruncatingMiddle;
    tf.textColor = NSColor.secondaryLabelColor;
    [v addSubview:tf];
    return item;
}

- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)paths {
    NSIndexPath *ip = paths.anyObject;
    if (!ip) return;
    AssetItem *ai = self.assets[self.categories[self.selCat]][ip.item];

    // 点一下复制可直接粘贴进剧本的完整指令
    NSString *text = ai.command;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    NSString *hint = @"已复制";

    // 音频：音乐点了播放/暂停，音效播一次
    NSString *cat = self.categories[self.selCat];
    if (isAudio(ai.path)) {
        BOOL isMusic = [cat isEqualToString:@"音乐"];
        if (isMusic && self.player.isPlaying && [self.playingPath isEqualToString:ai.path]) {
            [self.player pause];
            self.playingPath = nil;
            hint = [hint stringByAppendingString:@" · 已暂停"];
        } else {
            self.player = nil;
            NSError *err = nil;
            self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:ai.path]
                                                                 error:&err];
            if (self.player) {
                [self.player play];
                self.playingPath = ai.path;
                hint = [hint stringByAppendingFormat:@" · 播放中 (%.1fs)", self.player.duration];
            } else {
                hint = [hint stringByAppendingString:@" · 无法播放（macOS 不支持 ogg）"];
            }
        }
        [self.grid reloadData];
    }

    self.status.stringValue = [NSString stringWithFormat:@"%@：%@", hint, text];
}

- (void)buildLayoutTabIn:(NSView *)cv body:(NSRect)body {
    self.layoutView = [[NSView alloc] initWithFrame:body];
    self.layoutView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    self.layoutView.hidden = YES;
    [cv addSubview:self.layoutView];

    self.layoutValues = [NSMutableDictionary dictionary];
    self.layoutReadouts = [NSMutableDictionary dictionary];
    self.layoutSliders = [NSMutableDictionary dictionary];

    NSArray *spec = @[
        @"对话框",
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
    ];

    CGFloat rowH = 40, headerH = 26, y = 8;
    CGFloat panelW = 400;
    for (id entry in spec)
        y += [entry isKindOfClass:[NSString class]] ? headerH : rowH;

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
        NSArray *k = entry;
        NSTextField *lbl = [NSTextField labelWithString:k[3]];
        lbl.frame = NSMakeRect(22, cy + 10, 78, 18);
        lbl.font = [NSFont systemFontOfSize:11];
        [doc addSubview:lbl];

        NSSlider *sl = [[NSSlider alloc] initWithFrame:NSMakeRect(100, cy + 6, 180, 24)];
        sl.minValue = [k[1] doubleValue];
        sl.maxValue = [k[2] doubleValue];
        sl.identifier = k[0];
        sl.target = self;
        sl.action = @selector(layoutSliderChanged:);
        sl.continuous = YES;
        [doc addSubview:sl];

        NSTextField *val = [NSTextField labelWithString:@"—"];
        val.frame = NSMakeRect(288, cy + 10, 100, 18);
        val.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        val.textColor = NSColor.secondaryLabelColor;
        [doc addSubview:val];

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
    [self.layoutView addSubview:sv];

    Class pv = NSClassFromString(@"PGMPreviewView");
    NSRect pr = NSMakeRect(panelW + 8, 8, body.size.width - panelW - 24, body.size.height - 16);
    self.previewView = [[pv alloc] initWithFrame:pr];
    NSView *v = (NSView *)self.previewView;
    v.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [self.layoutView addSubview:v];
}

- (void)layoutSliderChanged:(NSSlider *)sl {
    self.layoutValues[sl.identifier] = @(sl.doubleValue);
    NSTextField *val = self.layoutReadouts[sl.identifier];
    val.stringValue = [NSString stringWithFormat:@"%@ = %d", sl.identifier, (int)sl.doubleValue];
    [self.previewView setValue:self.layoutValues forKey:@"values"];
    [(NSView *)self.previewView setNeedsDisplay:YES];
    self.layoutDirty = YES;
    self.saveBtn.enabled = YES;
    [self updateFitWarning];
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
        val.stringValue = [NSString stringWithFormat:@"%@ = %ld", key, (long)v];
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


@interface PGMPreviewView : NSView
@property (strong) NSDictionary<NSString *, NSNumber *> *values;
@property (strong) NSImage *msgboxImage;
@property (strong) NSImage *ramusImage;
@property (strong) NSImage *handImage;
@property (assign) NSInteger optionCount;
@property (assign) BOOL showHand;
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

    // 用 16x18 的固定字格（和引擎的 FONTWIDTH/FONTHEIGHT 一致）
    NSDictionary *attr = @{ NSFontAttributeName: [NSFont fontWithName:@"PingFang SC" size:15]
                                              ?: [NSFont systemFontOfSize:15],
                            NSForegroundColorAttributeName: NSColor.blackColor };

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

    // 人名（画在 16x18 格子里，顶端对齐）
    [@"人名" drawInRect:NSMakeRect(nameDX, nameDY, 64, 18) withAttributes:attr];

    // 正文三行，每字 16 宽
    int cols = MIN(lineLen, 24);
    for (int i = 0; i < 3; i++) {
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

        NSMenu *mb = [NSMenu new];
        NSMenuItem *appItem = [NSMenuItem new];
        [mb addItem:appItem];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        NSApp.mainMenu = mb;

        StudioController *c = [StudioController new];
        [c buildUI];
        if (argc > 1) [c loadProject:[NSString stringWithUTF8String:argv[1]]];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
