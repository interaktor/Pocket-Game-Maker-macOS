#!/usr/bin/env python3
"""
gen_api_list.py — 生成 src/pgm_api_names.h（PGM 原生 API 名称表）。

两个来源合并：

1. 《PGM指令表v0.7.txt》—— PGM 官方文档，列出 136 个接口与 49 个宏。
   这是"规范"层面的完整清单。

2. 扫描 PGM_CE / 原版 v0.83 的 Lua 脚本 —— 找出脚本里实际调用、但由原生层
   提供（Lua 里没有定义）的全局函数。官方文档并不完整，例如
   am_font_getinstance / am_ramus_render 这类内部接口就没写进去。

   合并两边的意义：文档保证"覆盖全"，扫描保证"不漏掉真的被调用的"。

用法：
    python3 scripts/gen_api_list.py [PGM_CE目录] [原版src目录]
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Lua 标准库/关键字，不算原生 API
LUA_BUILTINS = set("""
assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile
loadstring module next pairs pcall print rawequal rawget rawset require select
setfenv setmetatable tonumber tostring type unpack xpcall
string table math io os coroutine debug
if then else elseif end while for in do return local function and or not nil
true false break repeat until goto self
""".split())


def scan_lua(bases):
    """扫描 Lua 脚本，返回 (被调用的名字, Lua 里定义的名字)"""
    called, defined = set(), set()
    files = 0
    for base in bases:
        if not os.path.isdir(base):
            continue
        for dp, _dn, fn in os.walk(base):
            for f in fn:
                if not f.endswith(('.lua', '.ev')):
                    continue
                files += 1
                path = os.path.join(dp, f)
                try:
                    t = open(path, 'rb').read().decode('gb18030', 'replace')
                except Exception:
                    continue
                t = re.sub(r'--\[\[.*?\]\]', ' ', t, flags=re.S)
                t = re.sub(r'--[^\n]*', ' ', t)
                for m in re.finditer(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(', t):
                    called.add(m.group(1))
                for m in re.finditer(
                        r'(?:function\s+|local\s+function\s+)([A-Za-z_][\w.:]*)', t):
                    defined.add(m.group(1).split(':')[0].split('.')[0])
                for m in re.finditer(r'^\s*([A-Za-z_]\w*)\s*=\s*function',
                                     t, flags=re.M):
                    defined.add(m.group(1))
    return called, defined, files


def scan_doc(doc_path):
    """从 PGM指令表v0.7.txt 提取接口名与宏名"""
    names, macros = [], []
    if not os.path.isfile(doc_path):
        return names, macros
    text = open(doc_path, 'rb').read().decode('gb18030', 'replace')
    in_macro = False
    for line in text.splitlines():
        s = line.strip()
        if s == '宏':
            in_macro = True
            continue
        if s == '接口':
            in_macro = False
            continue
        m = re.match(r'^([A-Za-z_]\w*)\s*\(', s)
        if m:
            names.append(m.group(1))
            continue
        if in_macro and re.fullmatch(r'[A-Z][A-Z0-9_]+', s):
            macros.append(s)
    return names, macros


def dedup(seq):
    seen = set()
    return [x for x in seq if not (x in seen or seen.add(x))]


def main():
    ce = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'PGM-CE')
    orig = (sys.argv[2] if len(sys.argv) > 2
            else os.path.join(ROOT, '..', 'PGM-orig', 'PGMv0.83完整版', 'src'))

    doc_path = os.path.join(ce, 'tools', 'PGM指令表v0.7.txt')
    doc_names, doc_macros = scan_doc(doc_path)

    called, defined, nfiles = scan_lua([os.path.join(ce, 'src'), orig])
    scanned = sorted(called - defined - LUA_BUILTINS)

    # 文档名单在前（按规范顺序），扫描补充在后
    names = dedup(doc_names + scanned)
    macros = dedup(doc_macros)

    out = os.path.join(ROOT, 'src', 'pgm_api_names.h')
    with open(out, 'w', encoding='utf-8') as f:
        f.write("/* 自动生成，勿手改：由 scripts/gen_api_list.py 生成 */\n")
        f.write("/* 来源：PGM指令表v0.7.txt（%d 个接口）+ "
                "Lua 脚本扫描（%d 个文件） */\n\n" % (len(doc_names), nfiles))
        f.write("#ifndef PGM_API_NAMES_H\n#define PGM_API_NAMES_H\n\n")
        f.write("/* 接口函数名（文档优先，扫描补充） */\n")
        f.write("static const char *PGM_API_NAMES[] = {\n")
        for i in range(0, len(names), 4):
            f.write("\t" + ", ".join('"%s"' % n for n in names[i:i + 4]) + ",\n")
        f.write("};\n\n")
        f.write("/* 常量/宏名 */\n")
        f.write("static const char *PGM_API_MACROS[] = {\n")
        for i in range(0, len(macros), 4):
            f.write("\t" + ", ".join('"%s"' % n for n in macros[i:i + 4]) + ",\n")
        f.write("};\n\n#endif /* PGM_API_NAMES_H */\n")

    print("扫描 %d 个脚本；文档接口 %d；扫描补充 %d；合计 %d 接口 / %d 宏"
          % (nfiles, len(doc_names), len(scanned), len(names), len(macros)))
    print("已写", out)


if __name__ == '__main__':
    main()
