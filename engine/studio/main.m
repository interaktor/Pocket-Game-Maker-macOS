// PGM Studio —— 素材浏览器（第一阶段）
// 列出工程里的背景/立绘/音乐，显示缩略图，点击生成对应指令并复制。
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

static const CGFloat kThumbW = 128, kThumbH = 90;

@interface AssetItem : NSObject
@property (copy) NSString *name;      // 文件名
@property (copy) NSString *path;      // 完整路径
@property (copy) NSString *command;   // 要插入剧本的指令
@property (strong) NSImage *thumb;
@end
@implementation AssetItem @end

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
    self.tabs = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(16, H - 44, 200, 28)];
    self.tabs.segmentCount = 2;
    [self.tabs setLabel:@"素材" forSegment:0];
    [self.tabs setLabel:@"剧本" forSegment:1];
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
    self.pathLabel.frame = NSMakeRect(228, H - 40, W - 366, 18);
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

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)switchTab:(id)sender {
    BOOL asset = (self.tabs.selectedSegment == 0);
    self.assetView.hidden = !asset;
    self.scriptView.hidden = asset;
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

    NSTextField *tf = [NSTextField labelWithString:ai.name.stringByDeletingPathExtension];
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
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:ai.command forType:NSPasteboardTypeString];
    self.status.stringValue = [NSString stringWithFormat:@"已复制：%@", ai.command];
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
