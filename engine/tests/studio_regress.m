// studio_regress.m —— PGM Studio 回归测试
//
// 把工作台的 main.m 直接编进来（把原来的 main 改名），在临时目录里复制一份
// 工程做断言，绝不碰用户正在用的工程。
//
// 用法: studio_regress <仓库根目录> [临时目录]
// 退出码 0 表示全部通过。

#define main PGMStudioOriginalMain
#import "../studio/main.m"
#undef main

static int gTotal = 0, gFail = 0;

static void check(BOOL cond, NSString *what) {
    gTotal++;
    if (!cond) gFail++;
    printf("%s  %s\n", cond ? "PASS" : "FAIL", what.UTF8String);
}

static BOOL has(NSString *text, NSString *needle) {
    return text && [text rangeOfString:needle].location != NSNotFound;
}

static NSString *readFile(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

static BOOL exists(NSString *path) {
    return [NSFileManager.defaultManager fileExistsAtPath:path];
}

static BOOL copyTree(NSString *from, NSString *to) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:to error:NULL];
    return [fm copyItemAtPath:from toPath:to error:NULL];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *root = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        if (!root.length) {
            fprintf(stderr, "用法: studio_regress <仓库根目录> [临时目录]\n");
            return 2;
        }
        NSString *tmp = argc > 2 ? [NSString stringWithUTF8String:argv[2]]
            : [NSTemporaryDirectory() stringByAppendingPathComponent:
               [NSString stringWithFormat:@"pgm_regress_%d", getpid()]];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:tmp error:NULL];
        NSString *proj = [tmp stringByAppendingPathComponent:@"proj"];
        [fm createDirectoryAtPath:proj withIntermediateDirectories:YES attributes:nil error:NULL];
        if (!copyTree([root stringByAppendingPathComponent:@"src"],
                      [proj stringByAppendingPathComponent:@"src"]) ||
            !copyTree([root stringByAppendingPathComponent:@"bin"],
                      [proj stringByAppendingPathComponent:@"bin"])) {
            fprintf(stderr, "复制测试工程失败\n");
            return 2;
        }

        StudioController *c = [StudioController new];
        [c buildUI];
        [c loadProject:proj];
        // 列表按字母序会先选中 src/am_start.ev，这里显式切到剧本文件
        [c openScript:[proj stringByAppendingPathComponent:@"src/user/main.ev"]];

        NSString *bgDir   = [proj stringByAppendingPathComponent:@"src/files/bg"];
        NSString *bgmDir  = [proj stringByAppendingPathComponent:@"bin/data/bgm"];
        NSString *cfgPath = [proj stringByAppendingPathComponent:@"src/user/config.lua"];
        NSString *mainEv  = [proj stringByAppendingPathComponent:@"src/user/main.ev"];
        NSString *titleEv = [proj stringByAppendingPathComponent:@"src/user/title.ev"];
        NSString *startEv = [proj stringByAppendingPathComponent:@"src/am_start.ev"];
        NSString *outside = [tmp stringByAppendingPathComponent:@"outside"];
        [fm createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:NULL];

        check([c.categories containsObject:@"bg"], @"扫描出 bg 分类");
        check([c.scriptFiles containsObject:mainEv], @"扫描出 main.ev");
        check([c.curScript isEqualToString:mainEv], @"默认打开 main.ev");

        // ---- P1-3 布局控件回来了 ----
        BOOL hasHand = NO, hasOpt = NO;
        for (NSView *v in c.layoutView.subviews) {
            if ([v isKindOfClass:[NSButton class]] &&
                [[(NSButton *)v title] isEqualToString:@"显示手型"]) hasHand = YES;
        }
        for (NSView *v in c.layoutView.subviews)
            if ([v isKindOfClass:[NSTextField class]] &&
                [[(NSTextField *)v stringValue] isEqualToString:@"预览选项数"]) hasOpt = YES;
        check(hasHand, @"布局页有“显示手型”");
        check(hasOpt, @"布局页有“预览选项数”");
        check(c.fitWarning != nil, @"布局页有 fitWarning 标签");

        NSSegmentedControl *sc = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
        sc.segmentCount = 4;
        sc.selectedSegment = 3;
        [c optionCountChanged:sc];
        check(c.previewOptionCount == 4, @"预览选项数切到 4");
        BOOL handBtnFound = NO;
        for (NSView *v in c.layoutView.subviews) {
            if ([v isKindOfClass:[NSButton class]] &&
                [[(NSButton *)v title] isEqualToString:@"显示手型"]) {
                [(NSButton *)v setState:NSControlStateValueOff];
                [c handToggle:(NSButton *)v];
                handBtnFound = YES;
            }
        }
        check(handBtnFound && !c.showHandInGame && c.layoutDirty, @"手型开关生效并标记布局脏");

        // ---- P0-3 导入同一个文件不能删源文件 ----
        c.selCat = [c.categories indexOfObject:@"bg"];
        NSString *backdrop = [bgDir stringByAppendingPathComponent:@"backdrop.png"];
        NSData *before = [NSData dataWithContentsOfFile:backdrop];
        [c importFiles:@[[NSURL fileURLWithPath:backdrop]]];
        check(exists(backdrop) && [[NSData dataWithContentsOfFile:backdrop] isEqualToData:before],
              @"把已有素材拖回原目录不会删掉它");

        // ---- P0-3 分类校验 ----
        NSString *badTxt = [outside stringByAppendingPathComponent:@"bad.txt"];
        [@"hello" writeToFile:badTxt atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:badTxt]]];
        check(!exists([bgDir stringByAppendingPathComponent:@"bad.txt"]), @"图片分类拒绝 .txt");

        NSString *badWav = [outside stringByAppendingPathComponent:@"bad.wav"];
        [@"fake" writeToFile:badWav atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:badWav]]];
        check(!exists([bgDir stringByAppendingPathComponent:@"bad.wav"]), @"图片分类拒绝音频");

        // ---- P0-3 覆盖导入 + 不留临时文件 ----
        NSString *newPng = [outside stringByAppendingPathComponent:@"extra.png"];
        [@"OLD" writeToFile:newPng atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:newPng]]];
        NSString *dstPng = [bgDir stringByAppendingPathComponent:@"extra.png"];
        BOOL firstOK = exists(dstPng) && [readFile(dstPng) isEqualToString:@"OLD"];
        [@"NEW-CONTENT" writeToFile:newPng atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:newPng]]];
        BOOL secondOK = [readFile(dstPng) isEqualToString:@"NEW-CONTENT"];
        BOOL leftover = NO;
        for (NSString *f in [fm contentsOfDirectoryAtPath:bgDir error:NULL])
            if ([f hasPrefix:@".import-"]) leftover = YES;
        check(firstOK && secondOK, @"重复导入同名文件时内容被替换");
        check(!leftover, @"导入后没有遗留临时文件");

        // ---- 音频分类只收音频 ----
        NSString *pngToAudio = [outside stringByAppendingPathComponent:@"pic.png"];
        [@"pic" writeToFile:pngToAudio atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        c.selCat = [c.categories indexOfObject:@"音乐"];
        [c importFiles:@[[NSURL fileURLWithPath:pngToAudio]]];
        check(!exists([bgmDir stringByAppendingPathComponent:@"pic.png"]), @"音乐分类拒绝图片");
        NSString *okWav = [outside stringByAppendingPathComponent:@"ok.wav"];
        [@"wav" writeToFile:okWav atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:okWav]]];
        check(exists([bgmDir stringByAppendingPathComponent:@"ok.wav"]), @"音乐分类接受 .wav");

        // ---- P1-2 导入/刷新不换分类、不动编辑器 ----
        c.selCat = [c.categories indexOfObject:@"bg"];
        c.editor.string = @"-- MARK-EDITOR";
        c.dirty = YES;
        NSString *png2 = [outside stringByAppendingPathComponent:@"p2.png"];
        [@"p2" writeToFile:png2 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [c importFiles:@[[NSURL fileURLWithPath:png2]]];
        check([c.categories[c.selCat] isEqualToString:@"bg"], @"导入后仍停在原分类");
        check([c.editor.string isEqualToString:@"-- MARK-EDITOR"], @"导入后编辑器内容还在");
        check(c.dirty, @"导入后未保存标记还在");

        [c reloadAssetList];
        check([c.categories[c.selCat] isEqualToString:@"bg"], @"刷新素材列表保留分类");
        check([c.editor.string isEqualToString:@"-- MARK-EDITOR"], @"刷新素材列表不动编辑器");

        // ---- P1-2 打开同一个文件不重读 ----
        [c openScript:c.curScript];
        check([c.editor.string isEqualToString:@"-- MARK-EDITOR"] && c.dirty,
              @"重复打开当前文件不冲掉编辑");

        [c loadScriptList];
        check([c.curScript isEqualToString:mainEv], @"刷新剧本列表仍停在 main.ev");
        check([c.editor.string isEqualToString:@"-- MARK-EDITOR"], @"刷新剧本列表不冲掉编辑");

        // ---- P1-1 一次保存同时写剧本和布局 ----
        c.editor.string = @"-- SAVED-BOTH\n";
        c.dirty = YES;
        c.layoutDirty = YES;
        c.layoutValues[@"MSGBOX_DY"] = @200;
        [c saveScript:nil];
        NSString *cfg = readFile(cfgPath);
        check([readFile(mainEv) isEqualToString:@"-- SAVED-BOTH\n"], @"保存写入了剧本");
        check(has(cfg, @"MSGBOX_DY   = 200") || has(cfg, @"MSGBOX_DY = 200"),
              @"同一次保存也写入了布局");
        check(!c.dirty && !c.layoutDirty, @"保存后两个脏标记都清掉");
        check(!c.saveBtn.enabled, @"没有改动时保存按钮禁用");

        // ---- P0-1/P2-2 标题脚本内容 ----
        c.titleChk.state = NSControlStateValueOn;
        [c toggleTitle:c.titleChk];
        NSString *t = readFile(titleEv);
        NSString *start = readFile(startEv);
        check(t != nil, @"启用标题后生成 title.ev");
        check(has(t, @"bg(\"title.png\")"), @"标题背景是已有的 title.png");
        check(has(t, @"bgm(\"theme.wav\")"), @"标题音乐是已有的 theme.wav");
        check(has(t, @"QUIT()"), @"标题退出用 QUIT()");
        check(!has(t, @"jump(\"title.ev\")"), @"标题脚本不再跳回自己");
        check(has(start, @"jump(\"title.ev\")"), @"am_start.ev 已跳转到 title.ev");
        check(exists([bgDir stringByAppendingPathComponent:@"title.png"]), @"title.png 素材存在");
        check(exists([bgmDir stringByAppendingPathComponent:@"theme.wav"]), @"theme.wav 素材存在");

        c.titleChk.state = NSControlStateValueOff;
        [c toggleTitle:c.titleChk];
        start = readFile(startEv);
        check(has(start, @"jump(\"main.ev\")"), @"关掉标题后 am_start.ev 跳回 main.ev");
        check(!has(start, @"title.ev"), @"关掉标题后不再引用 title.ev");

        // ---- P2 新建工程样例不再自跳 ----
        NSString *sample = PGMSampleMainScript();
        check(has(sample, @"text(") && !has(sample, @"jump(\"main.ev\")"),
              @"新建工程样例剧本不自跳");

        // ---- P2-1 编辑菜单 ----
        NSMenu *menu = PGMCreateMainMenu();
        BOOL hasEdit = NO, hasUndo = NO, hasCopy = NO, hasPaste = NO, hasAll = NO;
        for (NSMenuItem *it in menu.itemArray) {
            NSMenu *sub = it.submenu;
            if (!sub) continue;
            for (NSMenuItem *m in sub.itemArray) {
                if (m.action == @selector(undo:)) hasUndo = YES;
                if (m.action == @selector(copy:)) hasCopy = YES;
                if (m.action == @selector(paste:)) hasPaste = YES;
                if (m.action == @selector(selectAll:)) hasAll = YES;
            }
            if (hasUndo && hasCopy && hasPaste && hasAll) hasEdit = YES;
        }
        check(hasEdit, @"主菜单含标准编辑菜单（撤销/复制/粘贴/全选）");
        check(hasUndo && hasCopy && hasPaste && hasAll, @"编辑菜单各项齐全");

        // ---- PSP 图标/背景图缩放 ----
        NSString *iconOut = [tmp stringByAppendingPathComponent:@"icon0.png"];
        NSString *picOut  = [tmp stringByAppendingPathComponent:@"pic1.png"];
        check(saveScaledPNG(backdrop, NSMakeSize(144, 80), iconOut), @"图标缩放成功");
        check(saveScaledPNG(backdrop, NSMakeSize(480, 272), picOut), @"背景图缩放成功");
        NSSize is = imageSizeAtPath(iconOut), ps = imageSizeAtPath(picOut);
        check(is.width == 144 && is.height == 80, @"图标输出 144×80");
        check(ps.width == 480 && ps.height == 272, @"背景图输出 480×272");
        check(imageSizeAtPath(@"/no/such/file.png").width == 0, @"不存在的图片返回空尺寸");

        // 把标题重新打开，留给后面的引擎测试跑标题画面
        c.titleChk.state = NSControlStateValueOn;
        [c toggleTitle:c.titleChk];
        check(has(readFile(startEv), @"jump(\"title.ev\")"), @"样例工程最终处于启用标题状态");

        printf("\n%d 项检查，%d 项失败\n", gTotal, gFail);
        printf("测试工程: %s\n", proj.UTF8String);
        if (gFail) return 1;
    }
    return 0;
}
