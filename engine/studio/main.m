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

@interface StudioController : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *catTable;
@property (strong) NSCollectionView *grid;
@property (strong) NSTextField *status;
@property (strong) NSTextField *pathLabel;
@property (strong) NSArray<NSString *> *categories;
@property (strong) NSMutableDictionary<NSString *, NSArray<AssetItem *> *> *assets;
@property (copy) NSString *projectRoot;
@property (assign) NSInteger selCat;
@end

@implementation StudioController

- (instancetype)init {
    if ((self = [super init])) {
        _categories = @[];
        _assets = [NSMutableDictionary dictionary];
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
    for (NSString *k in cats)
        fprintf(stdout, "  %-10s %3lu\n", k.UTF8String, (unsigned long)self.assets[k].count);
    fprintf(stdout, "  合计 %ld\n", (long)n);
    fflush(stdout);
}

#pragma mark - 界面

- (void)buildUI {
    NSRect frame = NSMakeRect(0, 0, 980, 640);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
          backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"PGM Studio — 素材";
    self.window.delegate = self;
    NSView *cv = self.window.contentView;

    // 顶部
    NSButton *openBtn = [NSButton buttonWithTitle:@"打开工程…" target:self action:@selector(openProject:)];
    openBtn.frame = NSMakeRect(16, frame.size.height - 48, 110, 30);
    openBtn.autoresizingMask = NSViewMinYMargin;
    [cv addSubview:openBtn];

    self.pathLabel = [NSTextField labelWithString:@"（未打开工程）"];
    self.pathLabel.frame = NSMakeRect(136, frame.size.height - 42, frame.size.width - 160, 18);
    self.pathLabel.autoresizingMask = NSViewWidthSizable|NSViewMinYMargin;
    self.pathLabel.textColor = NSColor.secondaryLabelColor;
    self.pathLabel.font = [NSFont systemFontOfSize:11];
    [cv addSubview:self.pathLabel];

    CGFloat top = frame.size.height - 60;

    // 左：分类
    NSScrollView *lsv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 30, 170, top - 30)];
    lsv.autoresizingMask = NSViewHeightSizable;
    lsv.hasVerticalScroller = YES;
    lsv.borderType = NSNoBorder;
    self.catTable = [[NSTableView alloc] initWithFrame:lsv.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = 160;
    [self.catTable addTableColumn:col];
    self.catTable.headerView = nil;
    self.catTable.dataSource = self;
    self.catTable.delegate = self;
    self.catTable.rowHeight = 26;
    lsv.documentView = self.catTable;
    [cv addSubview:lsv];

    // 右：缩略图网格
    NSCollectionViewFlowLayout *layout = [NSCollectionViewFlowLayout new];
    layout.itemSize = NSMakeSize(kThumbW + 16, kThumbH + 34);
    layout.sectionInset = NSEdgeInsetsMake(12, 12, 12, 12);
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    self.grid = [[NSCollectionView alloc] initWithFrame:NSMakeRect(170, 30, frame.size.width - 170, top - 30)];
    self.grid.collectionViewLayout = layout;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.selectable = YES;
    [self.grid registerClass:[NSCollectionViewItem class] forItemWithIdentifier:@"cell"];
    NSScrollView *gsv = [[NSScrollView alloc] initWithFrame:NSMakeRect(170, 30, frame.size.width - 170, top - 30)];
    gsv.documentView = self.grid;
    gsv.hasVerticalScroller = YES;
    gsv.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [cv addSubview:gsv];

    // 底部状态
    self.status = [NSTextField labelWithString:@"打开一个工程开始"];
    self.status.frame = NSMakeRect(16, 6, frame.size.width - 32, 18);
    self.status.autoresizingMask = NSViewWidthSizable|NSViewMaxYMargin;
    self.status.font = [NSFont systemFontOfSize:12];
    [cv addSubview:self.status];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
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

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return self.categories.count; }

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
    NSString *cat = self.categories[row];
    v.textField.stringValue = [NSString stringWithFormat:@"%@  (%lu)", cat,
                               (unsigned long)self.assets[cat].count];
    return v;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger r = self.catTable.selectedRow;
    if (r < 0) return;
    self.selCat = r;
    [self.grid reloadData];
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
