#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BlackEvidence 外部录像助手
================================================================================

为什么需要这个东西
--------------------------------------------------------------------------------
魔兽世界插件运行在一个沙箱里，**没有任何录屏 API**，也不能自己写文件。
插件唯一能做的两件"对外可见"的事情是：

    1. 调用 Screenshot()  ->  在 <魔兽目录>/Screenshots/ 里生成一张截图
    2. 插件聊天窗/游戏日志 -> <魔兽目录>/Logs/WoWChatLog.txt（需要 LoggingChat(true)）

所以配套方案就是本程序：

    本程序一直在后台跑着，用一个分段"环形缓冲"持续录屏（默认只保留最近 150 秒）；
    一旦发现 Screenshots/ 目录里冒出一张新截图（= BlackEvidence 触发了证据采集），
    就立刻把窗口内的分段拼成一个完整的 mp4，连同聊天记录一起，
    归档到 evidence/<时间戳>/ 目录里。

    插件那边会同时把"时间线"（最近几分钟的聊天 + 装备掉落 + 装备归属 + ROLL 点）
    和"备注"存进 SavedVariables；本程序会在存档刷新后自动把它读出来，
    补进同一个证据目录。

目录结构
--------------------------------------------------------------------------------
    recorder/
        blackevidence_recorder.py  本程序
        config.ini                 配置（首次运行自动生成，可手改）
        recorder.log               日志（排查问题就看这个）
        .lock                      单实例锁（内容是正在运行的 PID，退出时删除）
        evidence/                  证据归档
            _segments/             环形缓冲的临时分段（可随时删，不影响已归档证据）
                seg_<session>_0000000.mp4   分段名带启动会话号，重启不会覆盖旧段
            20261026-213045/       一次触发 = 一个目录
                capture.png        触发现场截图（插件截的那张）
                replay.mp4         窗口内的录像
                chatlog_tail.txt   最近 N 分钟聊天记录原文
                loot_and_rolls.txt 聊天记录里筛出的掉落 / 归属 / ROLL 相关行
                note.txt           你在插件里写的备注
                meta.json          这次触发的全部元数据（排查问题用）
            index.jsonl            所有触发的索引，一行一条
            _diagnostics/          插件诊断（排查插件问题时就看这里）
                plugin_live.log    实时日志：几分钟内游戏里发生的事（几秒延迟）
                plugin_full.log    插件日志缓冲的完整内容（/reload 时落盘）
                plugin_diag.txt    游戏里 /be test 的实机测试摘要

使用
--------------------------------------------------------------------------------
    python blackevidence_recorder.py                 # 常驻运行（平时就用这个）
    python blackevidence_recorder.py --selftest      # 环境自检：检查 ffmpeg / 目录 / 日志
    python blackevidence_recorder.py --dry-run       # 不真的录屏，只走"触发 -> 归档"流程（测试用）
    python blackevidence_recorder.py --fake-screenshot   # 造一张假截图，测试整条链路
    python blackevidence_recorder.py --sync-notes    # 从 SavedVariables 补齐 note.txt
    python blackevidence_recorder.py --export-diag   # 导出插件 /be test 的诊断摘要成文件

    调试插件时的推荐流程：
        游戏里执行 /be test  ->  /reload  ->  本程序会把摘要导出到
        evidence\\_diagnostics\\plugin_diag.txt，把这个文件发出来就行

正式服 / 时光服 / 经典客户端都能用
--------------------------------------------------------------------------------
    本程序只看"截图文件"和"SavedVariables 文件"，跟客户端版本无关。
    paths.wow_root 填什么就用什么（不再自动挑版本），选中的目录会写进 recorder.log。
    如果要盯另一个版本（_retail_ / _classic_era_ / _classic_ / _classic_beta_ /
    _classic_anniversary_），把该版本目录填进 paths.wow_root 即可。
    注意：一次只盯一个版本的游戏目录。想同时盯两个版本，
    复制一份本目录、改一份 config.ini、开两个窗口即可（证据目录分开更清楚）。

安全 / 稳定性
--------------------------------------------------------------------------------
    - 单实例：recorder/.lock 里存 PID，已有活着的实例时拒绝启动，退出时删除。
    - 磁盘保护：启动 ffmpeg 前检查输出盘剩余空间，低于 2 GB 自动降级为
      "只归档截图 + 聊天记录"（等同 --dry-run），不会把盘写满。
    - 分段名带会话号，新一次运行不会覆盖上一次的分段。

依赖
--------------------------------------------------------------------------------
    只依赖 Python 标准库 + 一个 ffmpeg.exe（放到 PATH 里，或用 --ffmpeg 指定）
    ffprobe 与 ffmpeg 同目录时用于校验 replay.mp4 的时长。
"""

from __future__ import annotations

import argparse
import configparser
import datetime as _dt
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
import zlib

APP_NAME = "BlackEvidence 录像助手"
APP_VERSION = "1.1.0"

# 截图文件后缀（插件默认 png；有些客户端配置成 jpg/tga）
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".bmp", ".tga")

# 磁盘保护：分段目录所在盘的剩余空间低于这个值就不启动 ffmpeg
MIN_FREE_BYTES = 2 * 1024 * 1024 * 1024

# replay.mp4 校验：实际时长低于期望窗口的这个比例就重编码兜底
DURATION_TOLERANCE = 0.8

# 聊天记录里跟"掉落 / 归属 / ROLL"有关的关键字（中文 + 英文，大小写不敏感）
LOOT_KEYWORDS = [
    "获得", "拾取", "掉落", "掷骰", "点投", "需求", "贪婪", "分解", "归属",
    "分配", "战利品", "装备", "储物箱", "幻化", "金币", "绑定",
    "roll", "loot", "need", "greed", "disenchant", "won", "receives",
    "received", "awarded", "assigned", "sold", "currency",
]

# 时间戳形如：10/26 21:30:45.123
CHATLOG_TS_RE = re.compile(r"^(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\.(\d{3})")

DEFAULT_CONFIG = """\
# BlackEvidence 录像助手 配置文件
# 所有路径都可以写绝对路径；留空表示用默认值（默认值见每项后面的注释）。
# 改完保存，重启录像助手生效。

[paths]
# 魔兽世界游戏目录。填什么就用什么，不再自动挑版本。
#   1) 直接填某一个版本的游戏目录（里面有 Screenshots / Logs / WTF）
#        例：D:\\Games\\World of Warcraft\\_retail_
#   2) 也可以填安装根目录（里面有 _retail_ / _classic_era_ 这些子目录），
#      但此时必须保证根目录下就有 Screenshots / Logs，否则请填 1) 的具体版本目录
# 支持的版本子目录：_retail_ / _classic_era_ / _classic_beta_ / _classic_ /
#                   _classic_anniversary_
# 最终选中的目录会写进 recorder.log。
wow_root =

# 截图目录。留空 = <wow_root>\\Screenshots
screenshot_dir =

# 证据输出目录。留空 = 本程序所在目录\\evidence
evidence_dir =

# 环形缓冲的临时分段目录（体积大，可以放在更快的盘上）。留空 = <evidence_dir>\\_segments
segment_dir =

# ffmpeg 可执行文件。留空 = 自动从 PATH 里找
# ffprobe 会从同一个目录自动找（用来校验 replay.mp4 的时长）
ffmpeg =

[recording]
# 录像保留时长（秒）。默认 150（最近 2.5 分钟）
video_seconds = 150

# 分段长度（秒）。越小越省内存，但触发时拼接的分段数越多。建议 15~30
segment_time = 20

# 帧率。15 够用且省 CPU；想更流畅可以调到 24/30
fps = 15

# 画质，CRF 越小越清晰、体积越大。18=很高 23=高 28=中（默认，够看装备/名字）
crf = 28

# 只录屏幕的一块区域，格式 x,y,宽度,高度。留空 = 全屏
# 例：0,0,1920,1080
region =

[evidence]
# 聊天记录回看的秒数。默认 180（最近 3 分钟）
chat_seconds = 180

# 触发之后再多抓几秒聊天记录（关键信息经常在触发之后才刷出来）。
# 到点会再读一次聊天日志，和第一次读到的内容合并去重。
chat_after_seconds = 20

# 两次触发之间的最小间隔（秒），防止同一秒内重复触发
min_interval = 5

# 读完聊天记录最多往回翻多少字节（太大启动会慢；4MB 一般够几小时）
chatlog_read_bytes = 4194304

[advanced]
# 轮询截图目录的间隔（秒）
poll_interval = 1.0

# 发现新截图后，等这么久再动手（给客户端把文件写完的时间）
post_delay = 2.0

# 是否在每次触发时打印一声蜂鸣提醒
beep = yes

# 从魔兽的 SavedVariables 里自动读出"备注"，
# 顺便把插件的诊断信息导出到 evidence\\_diagnostics\\
#   plugin_diag.txt   游戏里 /be test 的摘要
#   plugin_full.log   插件日志缓冲的完整内容（/reload 后落盘）
sync_notes = yes

# 实时日志：跟着 WoWChatLog.txt，把插件打进聊天窗的日志抄成
# evidence\\_diagnostics\\plugin_live.log（几秒延迟，游戏里发生什么马上能看到）
# 想看到除了 warn/error 以外的日志，游戏里执行：/be log mirror debug
follow_chatlog = yes
"""


# ----------------------------------------------------------------------------
# 日志
# ----------------------------------------------------------------------------
class Log:
    def __init__(self, path=None, quiet=False):
        self.path = path
        self.quiet = quiet
        self.levels = ("DEBUG", "INFO", "WARN", "ERROR")

    def _write(self, level, msg):
        line = "%s [%-5s] %s" % (
            _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), level, msg)
        if not self.quiet or level in ("WARN", "ERROR"):
            try:
                print(line, flush=True)
            except Exception:
                pass
        if self.path:
            try:
                with open(self.path, "a", encoding="utf-8") as fh:
                    fh.write(line + "\n")
            except Exception:
                pass

    def debug(self, msg):
        self._write("DEBUG", msg)

    def info(self, msg):
        self._write("INFO", msg)

    def warn(self, msg):
        self._write("WARN", msg)

    def error(self, msg):
        self._write("ERROR", msg)

    def exc(self, msg, ex):
        self._write("ERROR", "%s: %s: %s" % (msg, type(ex).__name__, ex))


LOG: Log = Log()


# ----------------------------------------------------------------------------
# 小工具
# ----------------------------------------------------------------------------
def ts2str(t):
    return _dt.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")


def ts2fs(t):
    return _dt.datetime.fromtimestamp(t).strftime("%Y%m%d-%H%M%S")


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "%.1f%s" % (n, unit) if unit != "B" else "%dB" % n
        n /= 1024.0


def ensure_dir(path):
    if path and not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)


def _tiny_png():
    """生成一张 1x1 的合法 PNG，用于测试（--fake-screenshot）。"""
    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)   # 1x1, RGBA
    raw = b"\x00\x00\x00\x00\x00"                          # 过滤字节 + RGBA
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def find_ffmpeg(explicit=None):
    if explicit:
        if os.path.isfile(explicit):
            return explicit
        LOG.warn("--ffmpeg 指定的路径不存在：%s，改为自动查找" % explicit)
    found = shutil.which("ffmpeg")
    if found:
        return found
    # 常见的几个位置（winget / chocolatey / scoop）
    guesses = [
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe"),
        r"C:\ffmpeg\bin\ffmpeg.exe",
        r"C:\ProgramData\chocolatey\bin\ffmpeg.exe",
        os.path.expandvars(r"%USERPROFILE%\scoop\shims\ffmpeg.exe"),
    ]
    for g in guesses:
        if os.path.isfile(g):
            return g
    return None


def find_ffprobe(ffmpeg=None):
    """找 ffprobe：优先 ffmpeg 同目录，其次 PATH。找不到返回 None（只跳过校验）。"""
    if ffmpeg:
        d = os.path.dirname(os.path.abspath(ffmpeg))
        cand = os.path.join(d, "ffprobe.exe" if os.name == "nt" else "ffprobe")
        if os.path.isfile(cand):
            return cand
        cand = os.path.join(d, "ffprobe")
        if os.path.isfile(cand):
            return cand
    found = shutil.which("ffprobe")
    if found:
        return found
    guesses = [
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Links\ffprobe.exe"),
        r"C:\ffmpeg\bin\ffprobe.exe",
        r"C:\ProgramData\chocolatey\bin\ffprobe.exe",
        os.path.expandvars(r"%USERPROFILE%\scoop\shims\ffprobe.exe"),
    ]
    for g in guesses:
        if os.path.isfile(g):
            return g
    return None


def popen_kwargs():
    """Windows 下不弹黑框。"""
    kw = {}
    if os.name == "nt":
        kw["creationflags"] = 0x08000000  # CREATE_NO_WINDOW
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        kw["startupinfo"] = si
    return kw


# ----------------------------------------------------------------------------
# 配置
# ----------------------------------------------------------------------------
class Cfg:
    def __init__(self, base_dir, config_path=None):
        self.base_dir = base_dir
        self.config_path = config_path or os.path.join(base_dir, "config.ini")
        self.raw = {}
        self._load()

    @property
    def path(self):
        return self.config_path

    def _load(self):
        p = self.path
        if not os.path.isfile(p):
            ensure_dir(os.path.dirname(p))
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(DEFAULT_CONFIG)
            LOG.info("已生成默认配置：%s" % p)
        cp = configparser.ConfigParser()
        try:
            cp.read(p, encoding="utf-8")
        except Exception as ex:
            LOG.exc("读取配置文件失败，改用默认值", ex)
        for sec in cp.sections():
            for k, v in cp.items(sec):
                self.raw["%s.%s" % (sec, k)] = v.strip()

    # --- 取值 ---
    def s(self, key, default=""):
        v = self.raw.get(key)
        if v is None or v == "":
            return default
        return v

    def i(self, key, default):
        v = self.raw.get(key)
        if v is None or v == "":
            return default
        try:
            return int(float(v))
        except Exception:
            LOG.warn("配置 %s = %r 不是数字，用默认值 %s" % (key, v, default))
            return default

    def f(self, key, default):
        v = self.raw.get(key)
        if v is None or v == "":
            return default
        try:
            return float(v)
        except Exception:
            LOG.warn("配置 %s = %r 不是数字，用默认值 %s" % (key, v, default))
            return default

    def b(self, key, default):
        v = self.raw.get(key)
        if v is None or v == "":
            return default
        return v.strip().lower() in ("1", "yes", "true", "on", "y")

    # --- 派生路径 ---
    def wow_root(self, cli=None):
        return cli or self.s("paths.wow_root")

    def screenshot_dir(self, wow_root, cli=None):
        return cli or self.s("paths.screenshot_dir") or os.path.join(wow_root, "Screenshots")

    def evidence_dir(self, cli=None):
        return cli or self.s("paths.evidence_dir") or os.path.join(self.base_dir, "evidence")

    def segment_dir(self, evidence_dir, cli=None):
        return cli or self.s("paths.segment_dir") or os.path.join(evidence_dir, "_segments")

    def log_path(self, cli=None):
        return cli or os.path.join(self.base_dir, "recorder.log")


# ----------------------------------------------------------------------------
# 游戏目录探测
# ----------------------------------------------------------------------------
# 一个安装目录里可能有多个"版本子目录"：正式服 _retail_、经典/时光服 _classic_era_ 等。
# 填 paths.wow_root 时按原样使用（不再自动挑版本）；未填时才在常见位置自动探测。
FLAVOR_SUBDIRS = (
    "_retail_",
    "_classic_era_",
    "_classic_beta_",
    "_classic_",
    "_classic_anniversary_",
)


def looks_like_game_dir(path):
    """这个目录像不像"真正的游戏目录"（里面有 Logs / Screenshots / WTF）。"""
    if not path or not os.path.isdir(path):
        return False
    for name in ("Logs", "Screenshots", "WTF"):
        if os.path.isdir(os.path.join(path, name)):
            return True
    return False


def expand_flavor_subdirs(path):
    """把"安装根目录"展开成真正的游戏目录列表（_retail_ / _classic_era_ ...）。"""
    out = []
    if not path or not os.path.isdir(path):
        return out
    try:
        names = sorted(os.listdir(path))
    except Exception:
        return out
    for name in names:
        if name.lower() in FLAVOR_SUBDIRS:
            sub = os.path.join(path, name)
            if looks_like_game_dir(sub):
                out.append(sub)
    return out


def resolve_wow_root(path):
    """把配置/命令行里填的路径解析成游戏目录。返回 (目录 or None, 说明文字)。

    paths.wow_root 填什么就用什么（原样使用，不再按 mtime 挑版本）；
    只有目录不存在时才失败。版本子目录的位置只在自动探测时参考。
    """
    if not path:
        return None, "没有填写"
    if not os.path.isdir(path):
        return None, "目录不存在"
    if looks_like_game_dir(path):
        return path, "按配置原样使用"
    subs = expand_flavor_subdirs(path)
    if subs:
        # 不擅自替换用户填的路径，只提示可以看到哪些版本目录
        return path, ("按配置原样使用（注意：这个目录本身没有 Logs/Screenshots/WTF；"
                      "下面这些版本子目录看起来才是游戏目录：%s）"
                      % ", ".join(os.path.basename(s) for s in subs))
    return path, "按配置原样使用（注意：里面没有 Logs / Screenshots / WTF，可能不是魔兽目录）"


def guess_wow_dirs():
    """在常见安装位置里找含有 Screenshots / Logs 的目录。"""
    cands = []
    roots = [
        r"C:\Program Files (x86)\World of Warcraft",
        r"C:\Program Files\World of Warcraft",
        r"D:\World of Warcraft",
        r"E:\World of Warcraft",
        r"D:\Games\World of Warcraft",
        r"E:\Games\World of Warcraft",
        r"F:\World of Warcraft",
    ]
    for r in roots:
        cands.append(r)
    for drive in ("C:", "D:", "E:", "F:", "G:"):
        try:
            for name in os.listdir(drive + "\\"):
                if "warcraft" in name.lower() or "魔兽" in name:
                    cands.append(os.path.join(drive + "\\", name))
        except Exception:
            continue
    out = []
    for c in cands:
        if not os.path.isdir(c):
            continue
        if os.path.isdir(os.path.join(c, "Screenshots")) or os.path.isdir(os.path.join(c, "Logs")):
            out.append(c)
            continue
        # 安装根目录：展开成 _retail_ / _classic_era_ 这些真正的游戏目录
        out.extend(expand_flavor_subdirs(c))
    return out


# ----------------------------------------------------------------------------
# 环形分段录像
# ----------------------------------------------------------------------------
class SegmentRing:
    """一个一直在跑的 ffmpeg，把屏幕切成小段 mp4；旧段自动删除。"""

    def __init__(self, ffmpeg, seg_dir, cfg, dry_run=False):
        self.ffmpeg = ffmpeg
        self.ffprobe = find_ffprobe(ffmpeg)
        self.seg_dir = seg_dir
        self.cfg = cfg
        self.dry_run = dry_run
        self.proc = None
        self.started_at = 0.0
        self.err_path = os.path.join(seg_dir, "ffmpeg_stderr.log")
        self.cycles = 0
        self.last_stop_reason = ""
        # 本次运行的会话号：分段名带上它，新一次运行不会覆盖上一次的分段
        self.session = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        # 分段序号起点：每重启一次 ffmpeg 就跳 100000，保证文件名永不重复
        self.next_start_number = 0
        # 磁盘保护：空间不够时置为 True（等同于 --dry-run，不启动 ffmpeg）
        self.disk_error = ""
        # 最近一次失败原因（写进 meta.json）
        self.last_error = ""

    # -- 磁盘保护 --
    def check_disk(self, need=None):
        """分段目录所在盘剩余空间够不够。不够就返回 False 并记下原因。"""
        if need is None:
            need = MIN_FREE_BYTES
        try:
            ensure_dir(self.seg_dir)
            free = shutil.disk_usage(self.seg_dir).free
        except Exception as ex:
            LOG.warn("检查磁盘剩余空间失败（按空间充足处理）：%s" % ex)
            return True
        if free < need:
            self.disk_error = ("分段目录剩余空间不足：%s（需要至少 %s）"
                               % (human_size(free), human_size(need)))
            return False
        self.disk_error = ""
        return True

    # -- 命令拼装 --
    def build_args(self):
        fps = max(1, self.cfg.i("recording.fps", 15))
        crf = self.cfg.i("recording.crf", 28)
        seg_time = max(2, self.cfg.i("recording.segment_time", 20))
        region = self.cfg.s("recording.region")

        args = [self.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
                "-f", "gdigrab", "-framerate", str(fps)]
        if region:
            parts = [p.strip() for p in region.split(",")]
            if len(parts) == 4:
                x, y, w, h = parts
                args += ["-offset_x", x, "-offset_y", y, "-video_size", "%sx%s" % (w, h)]
            else:
                LOG.warn("recording.region 格式应为 x,y,宽,高，当前=%r，已忽略" % region)
        args += [
            "-i", "desktop",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", str(crf),
            "-pix_fmt", "yuv420p",
            # 关键：segment 封装器只在"关键帧"处切分。
            # 必须强制让每个分段边界上都有一个关键帧，否则录 10 秒也只会得到 1 个文件。
            "-g", str(max(1, fps * seg_time)),
            "-force_key_frames", "expr:gte(t,n_forced*%d)" % seg_time,
            "-f", "segment",
            "-segment_time", str(seg_time),
            "-reset_timestamps", "1",
            # 分段序号每次重启 ffmpeg 都往后跳一大段，保证文件名不重复（不会被覆盖）
            "-segment_start_number", str(self.next_start_number),
            os.path.join(self.seg_dir, "seg_%s_%%07d.mp4" % self.session),
        ]
        return args

    def start(self):
        if self.dry_run:
            LOG.info("[dry-run] 不启动 ffmpeg（只走触发/归档流程）")
            self.started_at = time.time()
            return False
        if not self.check_disk():
            # 磁盘安全：宁可不录像，也不要把盘写满
            self.dry_run = True
            self.last_error = self.disk_error
            LOG.error("%s —— 降级为「只归档截图 / 聊天记录」模式（等同 --dry-run）"
                      % self.disk_error)
            self.started_at = time.time()
            return False
        ensure_dir(self.seg_dir)
        args = self.build_args()
        LOG.info("启动录像：%s" % " ".join('"%s"' % a if " " in a else a for a in args))
        try:
            errf = open(self.err_path, "ab")
            self.proc = subprocess.Popen(args, stdin=subprocess.PIPE,
                                         stdout=subprocess.DEVNULL, stderr=errf,
                                         **popen_kwargs())
            self.started_at = time.time()
            self.cycles += 1
            self.next_start_number += 100000
        except Exception as ex:
            LOG.exc("启动 ffmpeg 失败（录像功能不可用，其它功能继续）", ex)
            self.proc = None
            return False
        time.sleep(0.6)
        if self.proc.poll() is not None:
            self.last_error = "ffmpeg 启动后立刻退出（退出码 %s）" % self.proc.returncode
            LOG.error("%s。请看 %s" % (self.last_error, self.err_path))
            self.proc = None
            return False
        self.last_error = ""
        LOG.info("录像已开始（第 %d 轮，会话 %s），分段目录 %s"
                 % (self.cycles, self.session, self.seg_dir))
        return True

    def stop(self, reason="manual", timeout=8.0):
        """优雅停止：给 ffmpeg 的 stdin 写 'q'，让它自己收尾（否则 mp4 的索引会不完整）。"""
        self.last_stop_reason = reason
        if self.dry_run or not self.proc:
            return True
        proc = self.proc
        self.proc = None
        LOG.info("停止 ffmpeg（%s）…" % reason)
        try:
            if proc.stdin:
                proc.stdin.write(b"q")
                proc.stdin.flush()
        except Exception as ex:
            LOG.debug("给 ffmpeg 写 'q' 失败（将改用 terminate）：%s" % ex)
        try:
            proc.wait(timeout=timeout)
            LOG.info("ffmpeg 已正常退出（退出码 %s）" % proc.returncode)
            return True
        except subprocess.TimeoutExpired:
            LOG.warn("ffmpeg 超过 %.0f 秒没退出，强制结束" % timeout)
            try:
                proc.kill()
                proc.wait(timeout=5)
            except Exception as ex:
                LOG.exc("强制结束 ffmpeg 失败", ex)
            return False

    def alive(self):
        if self.dry_run:
            return True
        return self.proc is not None and self.proc.poll() is None

    # -- 分段管理 --
    def list_segments(self, all_sessions=False):
        """列出分段。默认只列本次运行（会话）的分段，避免拼进上一次的旧段。"""
        if not os.path.isdir(self.seg_dir):
            return []
        prefix = "seg_%s_" % self.session
        out = []
        for name in os.listdir(self.seg_dir):
            if not (name.startswith("seg_") and name.endswith(".mp4")):
                continue
            if not all_sessions and not name.startswith(prefix):
                continue
            p = os.path.join(self.seg_dir, name)
            try:
                out.append((os.path.getmtime(p), os.path.getsize(p), p))
            except OSError:
                continue
        out.sort()
        return out

    def prune(self):
        keep = self.cfg.i("recording.video_seconds", 150) \
            + self.cfg.i("recording.segment_time", 20) * 2 + 60
        cutoff = time.time() - keep
        removed, freed = 0, 0
        # 连同上一次运行残留的旧段一起清理（否则 repeatedly 启动会一直堆着）
        for mtime, size, path in self.list_segments(all_sessions=True):
            if mtime < cutoff:
                try:
                    os.remove(path)
                    removed += 1
                    freed += size
                except OSError:
                    pass
        if removed:
            LOG.debug("清理旧分段 %d 个，释放 %s" % (removed, human_size(freed)))
        return removed

    def segments_for_window(self, end_ts):
        """挑出覆盖 [end_ts - video_seconds, end_ts] 的分段。"""
        video_s = self.cfg.i("recording.video_seconds", 150)
        seg_time = self.cfg.i("recording.segment_time", 20)
        start_ts = end_ts - video_s
        segs = self.list_segments()
        picked = []
        for mtime, size, path in segs:
            # 一段文件覆盖 [mtime - seg_time, mtime]（mtime 是最后一次写入）
            if mtime >= start_ts - seg_time * 0.5:
                picked.append((mtime, size, path))
        if not picked and segs:
            # 兜底：至少给最后一段
            picked = [segs[-1]]
        return picked

    def expected_duration(self, end_ts):
        """这次窗口"理论上"该有多长：不超过 video_seconds，也不超过本次录像已跑的时间。"""
        video_s = self.cfg.i("recording.video_seconds", 150)
        if not self.started_at:
            return float(video_s)
        elapsed = max(0.0, end_ts - self.started_at)
        return float(min(video_s, elapsed)) if elapsed else float(video_s)

    def probe_duration(self, path):
        """用 ffprobe 读 mp4 时长（秒）。失败返回 None。"""
        if not self.ffprobe or not os.path.isfile(path):
            return None
        try:
            r = subprocess.run(
                [self.ffprobe, "-v", "error", "-show_entries", "format=duration",
                 "-of", "default=noprint_wrappers=1:nokey=1", path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=60, **popen_kwargs())
        except Exception as ex:
            LOG.warn("调用 ffprobe 失败：%s" % ex)
            return None
        if r.returncode != 0:
            msg = (r.stderr or b"").decode("utf-8", "replace").strip()[-300:]
            LOG.warn("ffprobe 返回 %s：%s" % (r.returncode, msg))
            return None
        try:
            return float((r.stdout or b"").decode("utf-8", "replace").strip())
        except ValueError:
            return None

    def reencode(self, segs, out_path):
        """兜底：分段时间戳不连续时，用 concat 滤镜重编码一份。"""
        if not self.ffmpeg or not segs:
            return False, "没有 ffmpeg 或没有分段"
        list_path = os.path.join(self.seg_dir, "_reencode_list.txt")
        try:
            with open(list_path, "w", encoding="utf-8") as fh:
                for _, _, p in segs:
                    fh.write("file '%s'\n" % p.replace("\\", "/").replace("'", "'\\''"))
        except Exception as ex:
            LOG.exc("写重编码列表失败", ex)
            return False, str(ex)

        args = [self.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
                "-f", "concat", "-safe", "0", "-i", list_path,
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path]
        LOG.info("校验未通过，改用重编码兜底 -> %s" % out_path)
        LOG.debug("re-encode 命令：%s" % " ".join(args))
        try:
            r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=1800, **popen_kwargs())
            if r.returncode != 0:
                msg = (r.stderr or b"").decode("utf-8", "replace").strip()[-800:]
                LOG.error("重编码失败（退出码 %s）：%s" % (r.returncode, msg))
                return False, msg
            return True, "reencode"
        except Exception as ex:
            LOG.exc("重编码异常", ex)
            return False, str(ex)
        finally:
            try:
                os.remove(list_path)
            except OSError:
                pass

    def concat_validated(self, segs, out_path, expected_s):
        """拼接 + 用 ffprobe 校验时长，必要时重编码兜底。

        返回 (ok, detail)。ok=False 时调用方要保留分段并在 meta.json 里写 video_ok=false。
        """
        ok, how = self.concat(segs, out_path)
        if not ok:
            return False, how

        if not self.ffprobe:
            LOG.warn("没有找到 ffprobe，跳过 replay.mp4 时长校验（按成功处理）")
            return True, how + "+unvalidated"

        duration = self.probe_duration(out_path)
        need = max(1.0, expected_s * DURATION_TOLERANCE)
        if duration is None:
            LOG.error("无法读出 replay.mp4 时长，尝试重编码兜底")
            ok2, how2 = self.reencode(segs, out_path)
            if not ok2:
                self.last_error = "时长校验失败，重编码也失败：%s" % how2
                return False, self.last_error
            duration2 = self.probe_duration(out_path)
            if duration2 is None:
                self.last_error = "重编码后仍读不出时长"
                return False, self.last_error
            LOG.info("重编码后时长 %.1f 秒（期望至少 %.1f 秒）" % (duration2, need))
            return True, how2

        if duration >= need:
            LOG.info("replay.mp4 时长校验通过：%.1f 秒（期望至少 %.1f 秒）" % (duration, need))
            return True, how

        LOG.warn("replay.mp4 只有 %.1f 秒，低于期望的 %.1f 秒（%.0f%%），重编码兜底"
                 % (duration, need, DURATION_TOLERANCE * 100))
        ok2, how2 = self.reencode(segs, out_path)
        if not ok2:
            self.last_error = "时长不足（%.1f 秒 < %.1f 秒）且重编码失败：%s" % (duration, need, how2)
            return False, self.last_error
        duration2 = self.probe_duration(out_path)
        if duration2 is not None and duration2 < need:
            self.last_error = "重编码后仍只有 %.1f 秒（期望至少 %.1f 秒）" % (duration2, need)
            LOG.error(self.last_error)
            return False, self.last_error
        LOG.info("重编码兜底成功：%.1f 秒（期望至少 %.1f 秒）"
                 % (duration2 if duration2 is not None else -1, need))
        return True, how2

    def concat(self, segs, out_path):
        """把若干分段拼成一个 mp4。"""
        if not segs:
            return False, "没有可用分段"
        if len(segs) == 1:
            src = segs[0][2]
            try:
                shutil.copy2(src, out_path)
                LOG.info("只有 1 个分段，直接复制：%s -> %s" % (src, out_path))
                return True, "copy"
            except Exception as ex:
                LOG.exc("复制分段失败", ex)
                return False, str(ex)

        list_path = os.path.join(self.seg_dir, "_concat_list.txt")
        try:
            with open(list_path, "w", encoding="utf-8") as fh:
                for _, _, p in segs:
                    fh.write("file '%s'\n" % p.replace("\\", "/").replace("'", "'\\''"))
        except Exception as ex:
            LOG.exc("写 concat 列表失败", ex)
            return False, str(ex)

        args = [self.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
                "-f", "concat", "-safe", "0", "-i", list_path,
                "-c", "copy", "-movflags", "+faststart", out_path]
        LOG.info("拼接 %d 个分段 -> %s" % (len(segs), out_path))
        LOG.debug("concat 命令：%s" % " ".join(args))
        try:
            r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=120, **popen_kwargs())
            if r.returncode != 0:
                msg = (r.stderr or b"").decode("utf-8", "replace").strip()[-800:]
                LOG.error("拼接失败（退出码 %s）：%s" % (r.returncode, msg))
                return False, msg
            return True, "concat"
        except Exception as ex:
            LOG.exc("拼接异常", ex)
            return False, str(ex)
        finally:
            try:
                os.remove(list_path)
            except OSError:
                pass


# ----------------------------------------------------------------------------
# 聊天记录
# ----------------------------------------------------------------------------
def parse_chatlog_time(line, year_hint):
    m = CHATLOG_TS_RE.match(line)
    if not m:
        return None
    mo, da, hh, mi, ss, ms = (int(x) for x in m.groups())
    try:
        dt = _dt.datetime(year_hint, mo, da, hh, mi, ss, ms * 1000)
    except ValueError:
        return None
    t = dt.timestamp()
    # 跨年：如果算出来的时间比现在晚很多，说明其实是去年
    if t > time.time() + 86400 * 2:
        try:
            dt = dt.replace(year=year_hint - 1)
            t = dt.timestamp()
        except ValueError:
            pass
    return t


def read_chatlog_window(path, start_ts, end_ts, max_bytes=4 * 1024 * 1024):
    """从聊天日志尾部读取 [start_ts, end_ts] 区间内的行。"""
    if not os.path.isfile(path):
        return [], ("聊天日志不存在：%s（插件里的『自动开启聊天日志』是否生效？）" % path)

    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        if size > max_bytes:
            fh.seek(size - max_bytes)
            fh.readline()  # 丢掉可能被切断的半行
        data = fh.read()
    text = data.decode("utf-8", "replace")
    lines = text.splitlines()

    year_hint = _dt.datetime.now().year
    out = []
    last_t = None
    kept_continuation = []
    for line in lines:
        t = parse_chatlog_time(line, year_hint)
        if t is not None:
            if kept_continuation and last_t is not None and start_ts <= last_t <= end_ts:
                out.extend(kept_continuation)
            last_t = t
            kept_continuation = []
            if start_ts <= t <= end_ts:
                out.append(line)
        else:
            # 续行（多行内容 / 插件输出），挂到上一行后面
            if last_t is not None:
                kept_continuation.append(line)
    if kept_continuation and last_t is not None and start_ts <= last_t <= end_ts:
        out.extend(kept_continuation)

    return out, None


def filter_loot_lines(lines):
    out = []
    for line in lines:
        low = line.lower()
        for kw in LOOT_KEYWORDS:
            if kw in low:
                out.append(line)
                break
    return out


# ----------------------------------------------------------------------------
# 从 SavedVariables 里读备注
# ----------------------------------------------------------------------------
# 插件落盘的表：
#   BlackEvidenceSnapshots = { records = { [1] = { id, reason, at, wall, profile,
#                               target = { key, name, surname, realm, guid, full, note },
#                               timelineText, screenshot = { predicted, ... } } } }
#   BlackEvidenceLog       = { session, seq, entries = { [1] = {...}, __cap, __head,
#                               __count, __seq }, marks = { {text, t} }, diag = { "..." } }
#   BlackEvidenceDB        = 设置 / 黑名单（本程序不解析内容，只确认文件里有没有）
SAVEDVARIABLES_FILES = ("BlackEvidence.lua", "BlackEvidence*.lua")

# 解析失败的原因（sync_notes 会把这些行写进 _diagnostics/plugin_parse_diag.txt）
PARSE_DIAG = []


def diag_note(msg):
    """记一条解析诊断：既写日志，也留给 Archiver 落成文件。"""
    PARSE_DIAG.append(msg)
    LOG.warn(msg)


def _find_savedvariables_files(wow_root):
    if not wow_root:
        return []
    sv_dir = os.path.join(wow_root, "WTF", "Account", "*", "SavedVariables")
    out = []
    for pat in SAVEDVARIABLES_FILES:
        out.extend(glob.glob(os.path.join(sv_dir, pat)))
    return sorted(set(out))


def _lua_block_end(text, start_idx):
    """text[start_idx] 是 '{'，返回与它配对的 '}' 的下标；找不到返回 -1。"""
    depth = 0
    i = start_idx
    n = len(text)
    in_str = False
    esc = False
    while i < n:
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def _lua_table_items(text, start_idx):
    """把一层表切成 [(key, block)]。

    key：`["x"]` -> "x"，`[12]` -> 12，裸元素（数组没写键）-> None。
    只返回值是表的元素；标量元素被跳过（它们的 key 也不返回）。
    """
    items = []
    i = start_idx
    n = len(text)
    pending_key = None
    while i < n:
        c = text[i]
        if c == '"':
            # 跳过字符串字面量：注释/备注里常有 [装备] 这种方括号，不能当键解析
            j = i + 1
            esc = False
            while j < n:
                ch = text[j]
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    break
                j += 1
            pending_key = None
            i = j + 1
            continue
        if c == "[":
            j = text.find("]", i)
            if j < 0:
                break
            raw = text[i + 1:j].strip()
            pending_key = _lua_key_value(raw)
            i = j + 1
            # 跳过空白和 '='
            while i < n and text[i] in " \t\r\n=":
                i += 1
            if i < n and text[i] == "{":
                end = _lua_block_end(text, i)
                if end < 0:
                    break
                items.append((pending_key, text[i:end + 1]))
                pending_key = None
                i = end + 1
                continue
            # 标量值：跳到这一层的分隔符
            pending_key = None
            continue
        if c == "{":
            end = _lua_block_end(text, i)
            if end < 0:
                break
            items.append((None, text[i:end + 1]))
            pending_key = None
            i = end + 1
            continue
        if c == "}":
            break
        i += 1
    return items


def _lua_key_value(raw):
    """"x" -> "x"；12 -> 12；其他原样返回字符串。"""
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        return _lua_unescape(raw[1:-1])
    try:
        f = float(raw)
        return int(f) if f.is_integer() else f
    except ValueError:
        return raw


_DECIMAL_ESC_RE = re.compile(r"\\(\d{1,3})")
_SIMPLE_ESC = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'"}


def _lua_unescape(s):
    """还原 Lua 字符串里的转义（\\n \\t \\r \\" \\\\ 以及 \\124 这类十进制转义）。

    插件会把玩家备注存成多行字符串，落盘后是 \\n 转义；也可能出现 WoW 的
    \\124（竖线）转义和超长字符串拆段，所以这里必须把常见转义都吃掉。
    """
    if "\\" not in s:
        return s

    def dec(m):
        try:
            return chr(int(m.group(1)))
        except ValueError:
            return m.group(0)

    s = _DECIMAL_ESC_RE.sub(dec, s)
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            nxt = s[i + 1]
            out.append(_SIMPLE_ESC.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _lua_field(block, name):
    """读一层表里的字段（字符串 / 数字 / bool）。找不到返回 None。"""
    m = re.search(r'\[\s*"%s"\s*\]\s*=\s*("(?:[^"\\]|\\.)*")' % re.escape(name), block)
    if m:
        return _lua_unescape(m.group(1)[1:-1])
    m = re.search(r'\[\s*"%s"\s*\]\s*=\s*(-?[\d.]+)' % re.escape(name), block)
    if m:
        try:
            f = float(m.group(1))
            return int(f) if f.is_integer() else f
        except ValueError:
            return None
    m = re.search(r'\[\s*"%s"\s*\]\s*=\s*(true|false)' % re.escape(name), block)
    if m:
        return m.group(1) == "true"
    return None


def _lua_subblock(block, name):
    """读一层表里的子表（例如 record.target / record.screenshot）。"""
    for key, sub in _lua_table_items(block, 1):
        if key == name:
            return sub
    return None


def _lua_string_list(block):
    """把一层表里的顶层字符串按顺序读出来（用于 BlackEvidenceLog.diag）。"""
    out = []
    i = 1
    n = len(block) - 1
    while i < n:
        c = block[i]
        if c == "{":
            end = _lua_block_end(block, i)
            if end < 0:
                break
            i = end + 1
            continue
        if c == '"':
            j = i + 1
            esc = False
            while j < n:
                ch = block[j]
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    break
                j += 1
            out.append(_lua_unescape(block[i + 1:j]))
            i = j + 1
            continue
        i += 1
    return out


def _read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception as ex:
        LOG.exc("读取存档失败：%s" % path, ex)
        return None


def _dated_files(wow_root):
    dated = []
    for path in _find_savedvariables_files(wow_root):
        try:
            dated.append((os.path.getmtime(path), path))
        except Exception:
            continue
    dated.sort(reverse=True)
    return dated


def _table_body(text, field):
    """找到 `["field"] = {` 并把表体切出来；找不到返回 None。"""
    idx = text.find('["%s"]' % field)
    if idx < 0:
        return None
    head = text.find("{", idx)
    if head < 0:
        return None
    end = _lua_block_end(text, head)
    if end < 0:
        return text[head:]
    return text[head:end + 1]


def load_plugin_text(wow_root, field):
    """读插件存档里某个"纯文本标量字段"。

    返回 (文本 or None, 存档文件 mtime or None, 存档文件名 or None)。
    """
    dated = _dated_files(wow_root)
    if not dated:
        return None, None, None

    newest_mtime = dated[0][0]
    newest_name = os.path.basename(dated[0][1])

    for mtime, path in dated:
        text = _read_text(path)
        if text is None:
            continue
        v = _lua_field(text, field)
        if isinstance(v, str) and v:
            return v, mtime, os.path.basename(path)
    return None, newest_mtime, newest_name


def load_plugin_diag(wow_root):
    """读 BlackEvidenceLog.diag（字符串数组），拼成整段文本。

    返回 (文本 or None, 存档 mtime or None, 存档文件名 or None)。
    """
    dated = _dated_files(wow_root)
    if not dated:
        return None, None, None

    for mtime, path in dated:
        text = _read_text(path)
        if text is None:
            continue
        body = _table_body(text, "diag")
        if not body:
            continue
        lines = _lua_string_list(body)
        if lines:
            return "\n".join(lines), mtime, os.path.basename(path)
    return None, dated[0][0], os.path.basename(dated[0][1])


def load_plugin_log(wow_root):
    """把插件存档里 BlackEvidenceLog.entries 那份环形缓冲还原成日志行。

    返回 (行列表, 行数, 存档 mtime, 存档文件名)。行列表按日志序号排好。
    entries 里除了数字键还有 __cap / __head / __count / __seq 这类字符串键，
    解析时必须忽略；否则会多出乱七八糟的行。
    """
    dated = _dated_files(wow_root)
    if not dated:
        return [], 0, None, None

    for mtime, path in dated:
        text = _read_text(path)
        if text is None:
            continue
        body = _table_body(text, "entries")
        if not body:
            continue

        rows = []
        skipped = 0
        for idx, (key, blk) in enumerate(_lua_table_items(body, 1), start=1):
            if key is not None and not isinstance(key, int):
                skipped += 1        # __cap / __head / __count / __seq -> 忽略
                continue
            lvl = _lua_field(blk, "lvl")
            msg = _lua_field(blk, "msg")
            if lvl is None and msg is None:
                continue
            t = _lua_field(blk, "t")
            seq = _lua_field(blk, "seq")
            tag = _lua_field(blk, "tag") or "?"
            ts = ts2str(t) if isinstance(t, (int, float)) else "?"
            order = seq if isinstance(seq, (int, float)) else (key if isinstance(key, int) else idx)
            rows.append((order,
                         "%s [%-5s] %s: %s" % (ts, str(lvl or "?").upper(), tag, msg or "")))

        if rows:
            rows.sort(key=lambda r: r[0])
            if skipped:
                LOG.debug("BlackEvidenceLog.entries：忽略 %d 个非数字键（__cap 等）" % skipped)
            return [r[1] for r in rows], len(rows), mtime, os.path.basename(path)

    return [], 0, dated[0][0], os.path.basename(dated[0][1])


def load_plugin_marks(wow_root):
    """读插件里的日志锚点（/be mark 打的），返回 [(text, t), ...]。"""
    out = []
    for path in _find_savedvariables_files(wow_root):
        text = _read_text(path)
        if text is None:
            continue
        body = _table_body(text, "marks")
        if not body:
            continue
        for key, blk in _lua_table_items(body, 1):
            if key is not None and not isinstance(key, int):
                continue
            t = _lua_field(blk, "text")
            at = _lua_field(blk, "t")
            if t is None:
                continue
            out.append((t, at if isinstance(at, (int, float)) else None))
    out.sort(key=lambda x: (x[1] or 0))
    return out



COLOR_RE = re.compile(r"\|c[0-9a-fA-F]{8}|\|c[0-9a-fA-F]{6}|\|r")


def strip_colors(s):
    return COLOR_RE.sub("", s or "")


class ChatLogFollower:
    """实时日志通道：tail 客户端的 WoWChatLog.txt，把插件写进聊天窗的行抄出来。

    插件没法写文件，但它的 warn/error（以及 /be log mirror debug 之后的全部日志）
    会打进聊天窗，而客户端开着聊天日志时会实时写进 WoWChatLog.txt。
    于是这个类就成了"实时日志文件"：游戏里发生什么，几秒后就能在这里看到。
    """

    MARKERS = ("[BlackEvidence]", "BlackEvidence")

    def __init__(self, wow_root, out_dir, cfg):
        self.enabled = cfg.b("advanced.follow_chatlog", True) and bool(wow_root)
        self.wow_root = wow_root or ""
        self.out_dir = out_dir
        self.chat_path = os.path.join(self.wow_root, "Logs", "WoWChatLog.txt") if wow_root else ""
        self.out_path = os.path.join(out_dir, "plugin_live.log")
        self.cursor_path = os.path.join(out_dir, ".chatlog_cursor")
        self.cursor = None
        self.lines_written = 0
        self.last_report = 0.0

    def _load_cursor(self):
        if self.cursor is not None:
            return
        self.cursor = None
        try:
            with open(self.cursor_path, "r", encoding="utf-8") as fh:
                self.cursor = int((fh.read() or "0").strip() or 0)
        except Exception:
            # 第一次跑：从文件末尾开始，只抓以后的日志
            try:
                self.cursor = os.path.getsize(self.chat_path)
                LOG.info("实时日志：首次运行，从 WoWChatLog.txt 末尾（%s）开始跟进" % self.cursor)
            except OSError:
                self.cursor = 0

    def _save_cursor(self):
        try:
            with open(self.cursor_path, "w", encoding="utf-8") as fh:
                fh.write(str(self.cursor or 0))
        except Exception as ex:
            LOG.exc("写实时日志游标失败", ex)

    def _rotate_if_needed(self, limit=4 * 1024 * 1024):
        try:
            if os.path.isfile(self.out_path) and os.path.getsize(self.out_path) > limit:
                bak = "%s.%s.log" % (self.out_path[:-4], _dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
                os.replace(self.out_path, bak)
                LOG.info("实时日志过大，已滚动到：%s" % bak)
        except Exception as ex:
            LOG.exc("滚动实时日志失败", ex)

    def poll(self):
        """看一眼聊天日志有没有新增，把插件的行抄到 plugin_live.log。返回抄到几行。"""
        if not self.enabled:
            return 0
        self._load_cursor()

        try:
            size = os.path.getsize(self.chat_path)
        except OSError:
            return 0        # 聊天日志还没生成（没开 /chatlog 或还没进游戏）

        if size < (self.cursor or 0):
            LOG.info("WoWChatLog.txt 变小了（客户端可能重建了文件），游标归零重读")
            self.cursor = 0

        if size == (self.cursor or 0):
            return 0

        try:
            ensure_dir(self.out_dir)
            self._rotate_if_needed()
            with open(self.chat_path, "rb") as fh:
                fh.seek(self.cursor or 0)
                raw = fh.read()
            self.cursor = (self.cursor or 0) + len(raw)
        except Exception as ex:
            LOG.exc("读 WoWChatLog.txt 失败", ex)
            return 0

        text = raw.decode("utf-8", errors="replace")
        picked = []
        for line in text.splitlines():
            if any(m in line for m in self.MARKERS):
                picked.append(strip_colors(line).rstrip())

        if picked:
            new_file = not os.path.isfile(self.out_path)
            try:
                with open(self.out_path, "a", encoding="utf-8") as fh:
                    if new_file:
                        fh.write("# BlackEvidence 实时日志（从 WoWChatLog.txt 抄出来的插件输出）\n")
                        fh.write("# 开始时间：%s\n%s\n" % (ts2str(time.time()), "=" * 70))
                    for line in picked:
                        fh.write(line + "\n")
                self.lines_written += len(picked)
                LOG.info("实时日志：新增 %d 行插件输出（累计 %d 行）→ %s"
                         % (len(picked), self.lines_written, self.out_path))
            except Exception as ex:
                LOG.exc("写 plugin_live.log 失败", ex)

        self._save_cursor()
        return len(picked)


def _parse_record(blk, src_name):
    """解析单条 record（含嵌套 target / screenshot）。解析不了返回 None 并记诊断。"""
    target = _lua_subblock(blk, "target")
    shot = _lua_subblock(blk, "screenshot")
    if target is None:
        # 兜底：有的旧存档把玩家字段平铺在 record 上
        diag_note("记录解析：%s 里有一条 record 没有 target 子表（按平铺字段兜底）" % src_name)
        target = blk

    rec = {
        "id": _lua_field(blk, "id"),
        "reason": _lua_field(blk, "reason"),
        "at": _lua_field(blk, "at"),
        "wall": _lua_field(blk, "wall"),
        "profile": _lua_field(blk, "profile"),
        "timelineText": _lua_field(blk, "timelineText"),
        # target.*
        "key": _lua_field(target, "key"),
        "name": _lua_field(target, "name"),
        "surname": _lua_field(target, "surname"),
        "realm": _lua_field(target, "realm"),
        "guid": _lua_field(target, "guid"),
        "fullName": _lua_field(target, "full") or _lua_field(target, "fullName"),
        "note": _lua_field(target, "note"),
        # screenshot.predicted（插件预测的截图文件名）
        "screenshot_predicted": _lua_field(shot, "predicted") if shot else None,
    }
    if rec["id"] is None and rec["wall"] is None:
        diag_note("记录解析：%s 里有一条 record 既没有 id 也没有 wall，已跳过" % src_name)
        return None
    if rec["note"] is None:
        # note 缺失是正常的（玩家没写备注），但 id 有值就说明记录本身读到了
        LOG.debug("记录 %s 没有 note 字段（玩家没写备注）" % rec.get("id"))
    return rec


def load_evidence_records(wow_root):
    """把插件存档里的 BlackEvidenceSnapshots.records 读成 Python 列表。

    返回 (records, err)。记录按 wall 排序；每条含 id / reason / at / wall /
    profile / target.* / timelineText / screenshot_predicted。
    """
    files = _find_savedvariables_files(wow_root)
    if not files:
        return [], ("没有找到 BlackEvidence 的 SavedVariables 文件"
                    "（%s\\WTF\\Account\\*\\SavedVariables\\BlackEvidence.lua）" % wow_root)

    records = []
    seen = set()
    for path in files:
        name = os.path.basename(path)
        text = _read_text(path)
        if text is None:
            diag_note("记录解析：读不了 %s" % name)
            continue
        if "BlackEvidenceSnapshots" not in text:
            LOG.debug("%s 里没有 BlackEvidenceSnapshots（可能还没触发过证据）" % name)
            continue
        body = _table_body(text, "records")
        if not body:
            diag_note("记录解析：%s 里找到了 BlackEvidenceSnapshots 但没有 records 表" % name)
            continue

        got = 0
        for key, blk in _lua_table_items(body, 1):
            if key is not None and not isinstance(key, int):
                # 非数字键（例如 __count / __seq 之类）一律忽略；
                # 裸元素（key is None）是数组没写键的写法，正常处理
                continue
            try:
                rec = _parse_record(blk, name)
            except Exception as ex:
                diag_note("记录解析：%s 第 %s 条记录抛异常 %s: %s"
                          % (name, key, type(ex).__name__, ex))
                continue
            if rec is None:
                continue
            rid = rec.get("id") or ("wall-%s" % rec.get("wall"))
            if rid in seen:
                continue
            seen.add(rid)
            records.append(rec)
            got += 1
        if got == 0:
            diag_note("记录解析：%s 的 records 表里没有解析出任何记录（结构可能变了）" % name)

    records.sort(key=lambda r: (r.get("wall") or 0))
    LOG.info("从 SavedVariables 读到 %d 条证据记录（来自 %d 个文件）" % (len(records), len(files)))
    return records, None


# ----------------------------------------------------------------------------
# 证据归档
# ----------------------------------------------------------------------------
class Archiver:
    def __init__(self, cfg, wow_root, screenshot_dir, evidence_dir, seg_dir, dry_run=False):
        self.cfg = cfg
        self.wow_root = wow_root
        self.screenshot_dir = screenshot_dir
        self.evidence_dir = evidence_dir
        self.seg_dir = seg_dir
        self.dry_run = dry_run
        # 延迟二次读取聊天记录的线程（退出时要等它们收尾）
        self._chat_threads = []

    # -- 聊天记录落盘 --
    def _write_chat_files(self, out_dir, meta, lines, trigger_t, chat_seconds,
                          after, chat_path, merged_at=None):
        """写 chatlog_tail.txt / loot_and_rolls.txt，并更新 meta 里的计数。

        返回 (tail_path, loot_path, loot_count)。
        """
        tail_path = os.path.join(out_dir, "chatlog_tail.txt")
        header = ("# 来源：%s\n# 窗口：%s ~ %s（共 %d 行）\n# 触发：%s\n%s\n"
                  % (chat_path, ts2str(trigger_t - chat_seconds), ts2str(trigger_t + after),
                     len(lines), ts2str(trigger_t), "=" * 60))
        with open(tail_path, "w", encoding="utf-8") as fh:
            fh.write(header)
            fh.write("\n".join(lines))
            if not lines or not lines[-1].endswith("\n"):
                fh.write("\n")
        meta["files"]["chatlog"] = tail_path
        meta["chatlog_lines"] = len(lines)

        loot = filter_loot_lines(lines)
        loot_path = os.path.join(out_dir, "loot_and_rolls.txt")
        with open(loot_path, "w", encoding="utf-8") as fh:
            fh.write("# 从最近 %d 秒聊天记录里筛出的「掉落 / 归属 / ROLL / 需求贪婪」相关行\n" % chat_seconds)
            fh.write("# 触发：%s\n%s\n" % (ts2str(trigger_t), "=" * 60))
            fh.write("\n".join(loot))
            if loot:
                fh.write("\n")
        meta["files"]["loot_and_rolls"] = loot_path
        meta["loot_lines"] = len(loot)
        if merged_at:
            meta["chatlog_merged_at"] = ts2str(merged_at)
        return tail_path, loot_path, len(loot)

    @staticmethod
    def _merge_chat_lines(first, second):
        """合并两次读取：second 覆盖的时间段更长，以它为主，保留 first 里独有的行。"""
        if not first:
            return list(second)
        if not second:
            return list(first)
        if second[:len(first)] == first:
            return list(second)          # 常见情况：第二次读是第一次的超集
        merged = list(first)
        seen = set(first)
        for line in second:
            if line in seen:
                continue
            seen.add(line)
            merged.append(line)
        return merged

    def _schedule_chat_merge(self, out_dir, trigger_t, chat_seconds, after,
                             chat_path, max_bytes, first_lines):
        """等 after 秒后再读一次聊天日志，把触发之后刷出来的行合并进证据目录。"""
        def work():
            try:
                time.sleep(max(0.0, after))
                now = time.time()
                lines2, err = read_chatlog_window(
                    chat_path, trigger_t - chat_seconds, now, max_bytes)
                if err:
                    LOG.warn("二次读取聊天记录失败（不影响已归档内容）：%s" % err)
                    return
                merged = self._merge_chat_lines(first_lines, lines2)
                meta_path = os.path.join(out_dir, "meta.json")
                try:
                    with open(meta_path, "r", encoding="utf-8") as fh:
                        meta = json.load(fh)
                except Exception:
                    meta = {"files": {}, "steps": [], "step_order": []}
                meta.setdefault("files", {})
                self._write_chat_files(out_dir, meta, merged, trigger_t, chat_seconds,
                                       after, chat_path, merged_at=now)
                meta["chatlog_lines_after_merge"] = len(merged)
                meta["chatlog_after_read"] = True
                with open(meta_path, "w", encoding="utf-8") as fh:
                    json.dump(meta, fh, ensure_ascii=False, indent=2)
                LOG.info("二次读取聊天记录完成：%d 行（新增 %d 行）"
                         % (len(merged), max(0, len(merged) - len(first_lines))))
            except Exception as ex:
                LOG.exc("二次读取聊天记录出错（不影响已归档内容）", ex)

        t = threading.Thread(target=work, name="be-chat-merge", daemon=True)
        self._chat_threads.append(t)
        t.start()
        LOG.info("已安排 %.0f 秒后二次读取聊天记录（补触发之后的行）" % after)
        return t

    def join_chat_threads(self, timeout=None):
        """等未完成的聊天合并线程收尾（--exit-after-trigger / 退出时用）。"""
        for t in list(self._chat_threads):
            try:
                t.join(timeout)
            except Exception:
                pass
        self._chat_threads = [t for t in self._chat_threads if t.is_alive()]

    def build(self, shot_path, ring, ring_stop_ok):
        """触发一次归档。返回证据目录路径。"""
        trigger_t = os.path.getmtime(shot_path) if os.path.isfile(shot_path) else time.time()
        name = "%s_%s" % (ts2fs(trigger_t), os.path.splitext(os.path.basename(shot_path))[0])
        out_dir = os.path.join(self.evidence_dir, name)
        ensure_dir(out_dir)
        LOG.info("=" * 70)
        LOG.info("触发归档：%s" % out_dir)
        LOG.info("  截图来源    ：%s" % shot_path)
        LOG.info("  触发时刻    ：%s" % ts2str(trigger_t))

        meta = {
            "app": APP_NAME,
            "app_version": APP_VERSION,
            "trigger_wall": trigger_t,
            "trigger_time": ts2str(trigger_t),
            "screenshot_source": shot_path,
            "screenshot_name": os.path.basename(shot_path),
            "video_seconds": self.cfg.i("recording.video_seconds", 150),
            "chat_seconds": self.cfg.i("evidence.chat_seconds", 180),
            "dry_run": self.dry_run,
            "files": {},
            "steps": [],
            "step_order": [],
        }

        def step(key, ok, detail):
            meta["step_order"].append(key)
            meta["steps"].append({"step": key, "ok": bool(ok), "detail": detail})
            LOG.info("  [%s] %s — %s" % ("OK " if ok else "!! ", key, detail))

        # 1) 录像
        video_seconds = self.cfg.i("recording.video_seconds", 150)
        win_start = trigger_t - video_seconds
        segs = ring.segments_for_window(trigger_t)
        LOG.info("  覆盖窗口    ：%s ~ %s（%d 秒）"
                 % (ts2str(win_start), ts2str(trigger_t), video_seconds))
        LOG.info("  命中分段    ：%d 个" % len(segs))
        for mtime, size, p in segs:
            LOG.debug("    - %s (%s, %s)" % (os.path.basename(p), ts2str(mtime), human_size(size)))
        meta["segments"] = [{"file": os.path.basename(p), "mtime": m, "size": s}
                            for m, s, p in segs]
        meta["segments_count"] = len(segs)
        meta["ffmpeg_alive_before_stop"] = ring.alive()
        meta["ffmpeg_stop_ok"] = ring_stop_ok

        replay = os.path.join(out_dir, "replay.mp4")
        meta["segment_session"] = getattr(ring, "session", "")
        if self.dry_run or getattr(ring, "dry_run", False):
            reason = getattr(ring, "last_error", "") or "dry-run"
            step("video", False, "跳过录像拼接（分段=%d，原因=%s）" % (len(segs), reason))
            meta["video_ok"] = False
            meta["video_reason"] = reason
        else:
            expected = ring.expected_duration(trigger_t)
            meta["video_expected_seconds"] = round(expected, 1)
            ok, how = ring.concat_validated(segs, replay, expected)
            if ok:
                meta["files"]["replay"] = replay
                meta["files"]["replay_size"] = os.path.getsize(replay) if os.path.isfile(replay) else 0
                step("video", True, "已生成 replay.mp4（%s，%s 个分段，方式=%s）"
                     % (human_size(meta["files"]["replay_size"]), len(segs), how))
            else:
                # 校验/拼接失败：保留分段（segments 已经写进 meta），标记 video_ok=false
                step("video", False, "拼接/校验失败：%s（分段已保留在 %s）" % (how, self.seg_dir))
            meta["video_ok"] = ok
            meta["video_reason"] = how

        # 2) 截图
        try:
            ext = os.path.splitext(shot_path)[1] or ".png"
            dst = os.path.join(out_dir, "capture" + ext)
            shutil.copy2(shot_path, dst)
            meta["files"]["capture"] = dst
            step("screenshot", True, "已复制截图 -> %s（%s）"
                 % (os.path.basename(dst), human_size(os.path.getsize(dst))))
        except Exception as ex:
            step("screenshot", False, "复制截图失败：%s" % ex)

        # 3) 聊天记录（先读一次，触发后再读一次补尾部）
        chat_seconds = self.cfg.i("evidence.chat_seconds", 180)
        after = self.cfg.i("evidence.chat_after_seconds", 20)
        chat_path = os.path.join(self.wow_root, "Logs", "WoWChatLog.txt")
        max_bytes = self.cfg.i("evidence.chatlog_read_bytes", 4 * 1024 * 1024)
        meta["chatlog_path"] = chat_path
        meta["chatlog_window"] = {"from": ts2str(trigger_t - chat_seconds),
                                  "to": ts2str(trigger_t + after)}
        lines, err = read_chatlog_window(chat_path, trigger_t - chat_seconds,
                                        trigger_t + after, max_bytes)
        if err:
            step("chatlog", False, err)
            meta["chatlog_lines"] = 0
        else:
            tail_path, loot_path, loot_n = self._write_chat_files(
                out_dir, meta, lines, trigger_t, chat_seconds, after, chat_path)
            step("chatlog", True, "已保存聊天记录 %d 行 -> %s"
                 % (len(lines), os.path.basename(tail_path)))
            step("loot_filter", True, "筛出掉落/ROLL 相关 %d 行 -> %s"
                 % (loot_n, os.path.basename(loot_path)))
            # 到点再读一次：关键信息（ROLL 结果、拾取）经常在触发之后才刷出来
            if after > 0:
                self._schedule_chat_merge(out_dir, trigger_t, chat_seconds, after,
                                          chat_path, max_bytes, lines)

        # 4) 备注（先留待同步）
        note_path = os.path.join(out_dir, "note.txt")
        with open(note_path, "w", encoding="utf-8") as fh:
            fh.write("（备注还没有同步）\n\n"
                     "插件把备注存在 SavedVariables 里，只有在游戏里 /reload 或退出游戏时才会落盘。\n"
                     "等你回游戏里 /reload 一次，录像助手会自动把备注补到这里；\n"
                     "也可以随时手动执行：python blackevidence_recorder.py --sync-notes\n")
        meta["note_status"] = "pending"
        meta["files"]["note"] = note_path
        step("note", True, "note.txt 已占位，等 SavedVariables 落盘后自动补齐")

        # 5) meta
        meta_path = os.path.join(out_dir, "meta.json")
        with open(meta_path, "w", encoding="utf-8") as fh:
            json.dump(meta, fh, ensure_ascii=False, indent=2)
        LOG.info("  元数据      ：%s" % meta_path)

        # 6) 索引
        try:
            idx_path = os.path.join(self.evidence_dir, "index.jsonl")
            with open(idx_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps({
                    "dir": out_dir,
                    "trigger_time": meta["trigger_time"],
                    "screenshot": meta["screenshot_name"],
                    "video_ok": meta.get("video_ok"),
                    "segments": meta.get("segments_count"),
                    "chatlog_lines": meta.get("chatlog_lines"),
                    "loot_lines": meta.get("loot_lines"),
                }, ensure_ascii=False) + "\n")
        except Exception as ex:
            LOG.exc("写 index.jsonl 失败（不影响证据本身）", ex)

        LOG.info("归档完成：%s" % out_dir)
        return out_dir

    # -- 备注同步 --
    def _write_parse_diag(self):
        """把本次解析诊断落成文件，方便排查 SavedVariables 结构变化。"""
        if not PARSE_DIAG:
            return None
        out_dir = os.path.join(self.evidence_dir, "_diagnostics")
        ensure_dir(out_dir)
        path = os.path.join(out_dir, "plugin_parse_diag.txt")
        try:
            with open(path, "a", encoding="utf-8") as fh:
                fh.write("# %s\n" % ts2str(time.time()))
                for line in PARSE_DIAG:
                    fh.write(line + "\n")
                fh.write("\n")
        except Exception as ex:
            LOG.exc("写 plugin_parse_diag.txt 失败", ex)
            return None
        return path

    def sync_notes(self, window=180):
        """把 SavedVariables 里 record.target.note 补进证据目录的 note.txt。

        优先按 id 精确匹配（meta.record_id）；没有 id 时退回到"触发时刻最接近"的
        一条记录，并记录相差秒数。
        """
        PARSE_DIAG.clear()
        records, err = load_evidence_records(self.wow_root)
        diag_path = self._write_parse_diag()
        if diag_path:
            LOG.warn("SavedVariables 解析有问题，详见 %s" % diag_path)
        if err:
            LOG.warn(err)
            return 0
        if not records:
            LOG.warn("存档里没有证据记录")
            return 0

        by_id = {}
        by_shot = {}
        for r in records:
            if r.get("id") is not None:
                by_id[str(r.get("id"))] = r
            shot = r.get("screenshot_predicted")
            if shot:
                by_shot[os.path.basename(shot)] = r

        done = 0
        for meta_path in glob.glob(os.path.join(self.evidence_dir, "*", "meta.json")):
            out_dir = os.path.dirname(meta_path)
            try:
                with open(meta_path, "r", encoding="utf-8") as fh:
                    meta = json.load(fh)
            except Exception:
                continue
            if meta.get("note_status") == "synced":
                continue
            trigger = meta.get("trigger_wall") or 0
            best, best_d = None, None

            # 1) 按 id 精确匹配（插件 record.id）
            rid = meta.get("record_id")
            if rid is None:
                rid = meta.get("note_record_id")
            shot_name = meta.get("screenshot_name") or ""
            if rid is not None and str(rid) in by_id:
                best = by_id[str(rid)]
                w = best.get("wall")
                best_d = abs((w or trigger) - trigger)
            elif shot_name and shot_name in by_shot:
                # 2) 用截图文件名对上 record.screenshot.predicted
                best = by_shot[shot_name]
                w = best.get("wall")
                best_d = abs((w or trigger) - trigger)
            else:
                # 3) 退回按时间最近匹配
                for r in records:
                    w = r.get("wall")
                    if not w:
                        continue
                    d = abs(w - trigger)
                    if best_d is None or d < best_d:
                        best, best_d = r, d
                if best is not None and (best_d is None or best_d > window):
                    best = None
            if best is None:
                continue
            if best_d is None:
                best_d = 0.0

            note_text = best.get("note")
            note_path = os.path.join(out_dir, "note.txt")
            with open(note_path, "w", encoding="utf-8") as fh:
                fh.write("触发 id   ：%s\n" % best.get("id"))
                fh.write("玩家      ：%s\n" % (best.get("fullName") or best.get("name")))
                fh.write("GUID      ：%s\n" % best.get("guid"))
                fh.write("触发原因  ：%s\n" % best.get("reason"))
                fh.write("游戏内时刻：%s\n" % best.get("at"))
                fh.write("存档时刻  ：%s（与归档相差 %.0f 秒）\n"
                         % (best.get("wall"), best_d))
                fh.write("=" * 60 + "\n")
                fh.write("黑名单备注：\n")
                if note_text:
                    fh.write(note_text.rstrip("\n") + "\n")
                else:
                    fh.write("（空）\n")
            meta["note_status"] = "synced"
            meta["record_id"] = best.get("id")
            meta["note_record_id"] = best.get("id")
            meta["note_delta_seconds"] = round(best_d, 1)
            try:
                with open(meta_path, "w", encoding="utf-8") as fh:
                    json.dump(meta, fh, ensure_ascii=False, indent=2)
            except Exception as ex:
                LOG.exc("回写 meta.json 失败", ex)
            done += 1
            LOG.info("已补齐备注：%s（id=%s，相差 %.0f 秒）"
                     % (os.path.basename(out_dir), best.get("id"), best_d))
        if done:
            LOG.info("本次共补齐 %d 个备注" % done)
        return done


# ----------------------------------------------------------------------------
# 主循环
# ----------------------------------------------------------------------------
class Recorder:
    def __init__(self, args, cfg):
        self.args = args
        self.cfg = cfg
        # 解析魔兽目录：paths.wow_root / --wow-root 填什么就用什么（原样使用）。
        # 只有没填时才会在常见安装位置自动探测；选中的目录一定写进日志。
        self.wow_root = None
        raw_root = cfg.wow_root(args.wow_root)
        if raw_root:
            self.wow_root, why = resolve_wow_root(raw_root)
            if self.wow_root:
                LOG.info("魔兽目录：%s（%s）" % (self.wow_root, why))
                LOG.info("（如要换版本，把 paths.wow_root 指向 _retail_ / _classic_era_ / "
                         "_classic_beta_ / _classic_ / _classic_anniversary_ 里的具体目录）")
            else:
                LOG.warn("paths.wow_root 填的目录用不了：%s（%s）" % (raw_root, why))
        if not self.wow_root:
            guesses = guess_wow_dirs()
            if guesses:
                self.wow_root = guesses[0]
                LOG.info("未指定魔兽目录，自动探测到：%s" % self.wow_root)
                LOG.info("（如果不是这个目录，请改 config.ini 的 paths.wow_root）")
        if not self.wow_root or not os.path.isdir(self.wow_root):
            self.wow_root = None
            LOG.warn("没有可用的魔兽目录：不录屏、也不回看聊天记录，"
                     "但仍然会响应截图触发并归档证据目录")

        self.screenshot_dir = args.watch or (
            cfg.screenshot_dir(self.wow_root) if self.wow_root
            else os.path.join(cfg.base_dir, "_no_wow", "Screenshots"))
        self.evidence_dir = cfg.evidence_dir(args.out)
        self.seg_dir = cfg.segment_dir(self.evidence_dir, args.segments)
        self.ffmpeg = find_ffmpeg(args.ffmpeg or cfg.s("paths.ffmpeg") or None)

        ensure_dir(self.screenshot_dir)
        ensure_dir(self.evidence_dir)
        ensure_dir(self.seg_dir)

        self.ring = SegmentRing(self.ffmpeg, self.seg_dir, cfg, dry_run=args.dry_run)
        self.archiver = Archiver(cfg, self.wow_root or "", self.screenshot_dir,
                                 self.evidence_dir, self.seg_dir, dry_run=args.dry_run)
        self.processed = {}          # path -> mtime
        self.last_trigger = 0.0
        self.started_at = time.time()    # 进程启动时刻：比它更老的截图一律忽略
        self.sv_mtimes = {}          # SavedVariables 文件 -> mtime
        self.text_written_mtimes = {}    # 已导出的插件文本字段 -> 存档时间
        self.full_log_mtime = None       # 已导出的插件完整日志对应的存档时间
        self.live = ChatLogFollower(self.wow_root, self.diag_dir(), cfg)
        self.stopping = False

    # -- 截图目录扫描 --
    def scan_new_screenshots(self, ignore_before):
        found = []
        try:
            names = os.listdir(self.screenshot_dir)
        except OSError as ex:
            LOG.error("读取截图目录失败：%s（%s）" % (self.screenshot_dir, ex))
            return found
        for name in names:
            if not name.lower().endswith(IMAGE_EXTS):
                continue
            p = os.path.join(self.screenshot_dir, name)
            try:
                mtime = os.path.getmtime(p)
                size = os.path.getsize(p)
            except OSError:
                continue
            if mtime < ignore_before:
                continue
            if self.processed.get(p) == mtime:
                continue
            # 文件还在写就先跳过（下次轮询再看）
            if size < 1024 and time.time() - mtime < 1.0:
                LOG.debug("截图 %s 可能还在写（%s），稍后再处理" % (name, human_size(size)))
                continue
            self.processed[p] = mtime
            found.append(p)
        found.sort()
        return found

    def wait_file_stable(self, path, timeout=5.0):
        last = -1
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                size = os.path.getsize(path)
            except OSError:
                return False
            if size == last and size > 0:
                return True
            last = size
            time.sleep(0.3)
        return True

    # -- 备注自动同步 --
    def maybe_sync_notes(self, force=False):
        if not self.cfg.b("advanced.sync_notes", True) and not force:
            return
        if not self.wow_root:
            return
        changed = force
        for f in _find_savedvariables_files(self.wow_root):
            try:
                m = os.path.getmtime(f)
            except OSError:
                continue
            if self.sv_mtimes.get(f) != m:
                self.sv_mtimes[f] = m
                changed = True
                LOG.info("检测到插件存档更新：%s" % f)
        if changed:
            try:
                self.archiver.sync_notes()
            except Exception as ex:
                LOG.exc("同步备注出错（不影响录像）", ex)
        # 顺手把插件里的诊断信息导出成文件（摘要 + 完整日志）
        self.export_diagnostics()

    # -- 插件诊断信息导出 --
    def diag_dir(self):
        return os.path.join(self.evidence_dir, "_diagnostics")

    def export_plugin_full_log(self, force=False):
        """把插件日志缓冲（BlackEvidenceLog.entries）整段导出成 plugin_full.log。

        插件 /reload 或退出时会把它落盘，所以这里拿到的是"上一次会话以来"的完整日志，
        比 plugin_diag.txt（只有 /be test 那一小段）全得多。
        """
        if not self.wow_root:
            return False
        try:
            lines, n, mtime, src = load_plugin_log(self.wow_root)
        except Exception as ex:
            LOG.exc("读取插件日志失败", ex)
            return False
        if not lines:
            if force:
                LOG.info("插件存档里还没有日志（进游戏跑一会儿，/reload 后再试）")
            return False
        if not force and self.full_log_mtime == mtime:
            return False

        out_dir = self.diag_dir()
        ensure_dir(out_dir)
        out_path = os.path.join(out_dir, "plugin_full.log")
        marks = load_plugin_marks(self.wow_root)
        header = [
            "BlackEvidence 插件完整日志（SavedVariables 里的环形缓冲）",
            "来源存档：%s" % src,
            "存档落盘时间：%s（游戏里 /reload 或退出的时刻）" % ts2str(mtime),
            "导出时间：%s" % ts2str(time.time()),
            "日志行数：%d" % n,
        ]
        if marks:
            header.append("日志锚点（/be mark）：")
            for text, at in marks[-20:]:
                header.append("    [%s] %s" % (ts2str(at) if at else "?", text))
        header.append("=" * 70)

        try:
            with open(out_path, "w", encoding="utf-8") as fh:
                fh.write("\n".join(header) + "\n")
                for line in lines:
                    fh.write(line + "\n")
        except Exception as ex:
            LOG.exc("写 plugin_full.log 失败", ex)
            return False

        self.full_log_mtime = mtime
        LOG.info("已导出插件完整日志：%s（%d 行，%d 个锚点）" % (out_path, n, len(marks)))
        return True

    # 插件里各种"文本字段" -> 落到 _diagnostics 下的文件名
    # BlackEvidenceLog.diag 是字符串数组（Logger.CaptureStop 累加），由 load_plugin_diag 拼成文本。
    EXPORT_FIELDS = (
        ("diag",       "plugin_diag.txt",
         "BlackEvidence 插件诊断摘要（游戏里执行 /be test 得到的）"),
    )

    @staticmethod
    def _load_export_field(wow_root, field):
        if field == "diag":
            return load_plugin_diag(wow_root)
        return load_plugin_text(wow_root, field)

    def export_plugin_texts(self, force=False):
        """把插件 SavedVariables 里的文本字段导出成文件。返回写了几个。"""
        if not self.wow_root:
            return 0
        written = 0
        for field, fname, title in self.EXPORT_FIELDS:
            try:
                text, mtime, src = self._load_export_field(self.wow_root, field)
            except Exception as ex:
                LOG.exc("读取插件字段 %s 出错" % field, ex)
                continue
            if not text:
                if force:
                    LOG.info("插件存档里还没有 %s（游戏里先用一次对应命令，再 /reload）" % field)
                continue
            if not force and self.text_written_mtimes.get(field) == mtime:
                continue

            out_dir = self.diag_dir()
            ensure_dir(out_dir)
            out_path = os.path.join(out_dir, fname)
            header = (
                "%s\n"
                "来源存档：%s\n"
                "存档落盘时间：%s（游戏里 /reload 或退出的时刻）\n"
                "导出时间：%s\n%s\n"
                % (title, src, ts2str(mtime), ts2str(time.time()), "=" * 70)
            )
            try:
                with open(out_path, "w", encoding="utf-8") as fh:
                    fh.write(header)
                    fh.write(text)
                    if not text.endswith("\n"):
                        fh.write("\n")
            except Exception as ex:
                LOG.exc("写 %s 失败" % fname, ex)
                continue

            self.text_written_mtimes[field] = mtime
            written += 1
            LOG.info("已导出 %s（%d 字）" % (out_path, len(text)))
        return written

    def export_diagnostics(self, force=False):
        """导出插件诊断文件（摘要 / 黑名单导出 / 证据包 / 完整日志）。"""
        n = self.export_plugin_texts(force)
        ok = self.export_plugin_full_log(force)
        return bool(n or ok)

    # -- 触发处理 --
    def handle_trigger(self, shot_path):
        now = time.time()
        min_interval = self.cfg.i("evidence.min_interval", 5)
        if now - self.last_trigger < min_interval:
            LOG.warn("距上次触发不足 %d 秒，忽略这张截图：%s" % (min_interval, shot_path))
            return None
        self.last_trigger = now
        self.wait_file_stable(shot_path)

        post = self.cfg.f("advanced.post_delay", 2.0)
        LOG.info("等待 %.1f 秒，让客户端把截图写完 / ffmpeg 把缓冲落盘…" % post)
        time.sleep(post)

        # 停掉当前 ffmpeg：这样"包含触发时刻"的那一段会被正确地收尾（moov 索引写全）
        stop_ok = self.ring.stop("触发归档")
        try:
            out_dir = self.archiver.build(shot_path, self.ring, stop_ok)
        except Exception as ex:
            LOG.exc("归档过程中出错", ex)
            out_dir = None

        self.ring.prune()

        if self.cfg.b("advanced.beep", True):
            try:
                if os.name == "nt":
                    import winsound
                    winsound.Beep(880, 120)
            except Exception:
                pass

        if not self.args.dry_run:
            LOG.info("重新开始录像…")
            self.ring.start()

        # 立刻试一次"从 SavedVariables 补备注"：
        # 如果玩家是 /reload 之后才触发的，备注这时已经在存档里了。
        self.maybe_sync_notes(force=True)
        return out_dir

    # -- 自检 --
    def selftest(self):
        LOG.info("=" * 70)
        LOG.info("%s 环境自检" % APP_NAME)
        LOG.info("=" * 70)
        problems = 0

        def item(name, ok, detail):
            nonlocal problems
            if not ok:
                problems += 1
            LOG.info("  [%s] %s — %s" % ("通过" if ok else "失败", name, detail))

        item("Python 版本", sys.version_info >= (3, 7), sys.version.split()[0])
        item("ffmpeg 可用", bool(self.ffmpeg), self.ffmpeg or "没找到！请装 ffmpeg 或改 config.ini 的 paths.ffmpeg")

        if self.ffmpeg:
            try:
                r = subprocess.run([self.ffmpeg, "-hide_banner", "-version"],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=15, **popen_kwargs())
                first = (r.stdout or b"").decode("utf-8", "replace").splitlines()
                item("ffmpeg 能执行", r.returncode == 0,
                     first[0] if first else "（无输出）")
            except Exception as ex:
                item("ffmpeg 能执行", False, str(ex))

            # 真录 2 秒试试 gdigrab（验证抓屏权限）
            if not self.args.dry_run:
                test_out = os.path.join(self.seg_dir, "_selftest.mp4")
                try:
                    r = subprocess.run(
                        [self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                         "-f", "gdigrab", "-framerate", "5", "-t", "2", "-i", "desktop",
                         "-c:v", "libx264", "-preset", "ultrafast", "-crf", "35",
                         "-pix_fmt", "yuv420p", test_out],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=40, **popen_kwargs())
                    ok = r.returncode == 0 and os.path.isfile(test_out) and os.path.getsize(test_out) > 1024
                    detail = ("已生成 %s（%s）" % (os.path.basename(test_out), human_size(os.path.getsize(test_out)))
                              if ok else (r.stderr or b"").decode("utf-8", "replace").strip()[-300:])
                    item("gdigrab 实际抓屏", ok, detail)
                except Exception as ex:
                    item("gdigrab 实际抓屏", False, str(ex))
                finally:
                    try:
                        os.remove(test_out)
                    except OSError:
                        pass

        item("魔兽目录", bool(self.wow_root and os.path.isdir(self.wow_root)),
             self.wow_root or "没找到，请在 config.ini 里填 paths.wow_root")
        item("截图目录可写", self._writable(self.screenshot_dir), self.screenshot_dir)
        item("证据目录可写", self._writable(self.evidence_dir), self.evidence_dir)
        item("分段目录可写", self._writable(self.seg_dir), self.seg_dir)

        if self.wow_root:
            chat = os.path.join(self.wow_root, "Logs", "WoWChatLog.txt")
            item("聊天日志存在", os.path.isfile(chat),
                 ("%s（%s）" % (chat, human_size(os.path.getsize(chat))))
                 if os.path.isfile(chat)
                 else "%s 不存在（进游戏后插件会自动开启聊天日志，产生该文件）" % chat)
            sv = _find_savedvariables_files(self.wow_root)
            item("插件存档存在", bool(sv),
                 ("；".join(os.path.basename(x) for x in sv))
                 if sv else "没找到 SavedVariables/BlackEvidence.lua（进游戏后自动生成）")
            if sv:
                text = _read_text(sv[0]) or ""
                tables = [t for t in ("BlackEvidenceSnapshots", "BlackEvidenceLog", "BlackEvidenceDB")
                          if t in text]
                item("插件存档表", bool(tables),
                     ("找到 %s" % "、".join(tables)) if tables else "存档里没有任何 BlackEvidence 表")

            # 插件里的诊断信息（有就说明能导出成文件，没有也不算错）
            for field, fname, title in self.EXPORT_FIELDS:
                text, mt, src = self._load_export_field(self.wow_root, field)
                item(title.split("（")[0], True,
                     ("已找到（%s，%s，%d 字）→ 会导出到 %s"
                      % (src, ts2str(mt), len(text), os.path.join("evidence", "_diagnostics", fname)))
                     if text
                     else "还没有（在游戏里用一次对应命令，然后 /reload，再回来看这里）")

            log_lines, log_n, log_mt, log_src = load_plugin_log(self.wow_root)
            marks = load_plugin_marks(self.wow_root)
            item("插件完整日志", True,
                 ("已找到 %d 行（%s，%s）｜锚点 %d 个 → 会导出到 %s"
                  % (log_n, log_src, ts2str(log_mt), len(marks),
                     os.path.join("evidence", "_diagnostics", "plugin_full.log")))
                 if log_n
                 else "还没有（进游戏玩一会儿，/reload 后再看）")

            item("实时日志跟随", True,
                 ("开着（%s）" % self.live.out_path) if self.live.enabled
                 else "已在配置里关掉（advanced.follow_chatlog）")
            if self.live.enabled:
                item("实时日志已抄到", True,
                     ("%s 行 → %s" % (self.live.lines_written, self.live.out_path))
                     if self.live.lines_written
                     else "本次启动还没抄到插件输出（游戏里 /be log mirror debug 之后会更全）")

        LOG.info("-" * 70)
        LOG.info("自检结束：%s" % ("全部通过" if problems == 0 else "有 %d 项需要注意" % problems))
        return 0 if problems == 0 else 1

    @staticmethod
    def _writable(path):
        try:
            ensure_dir(path)
            probe = os.path.join(path, "_be_write_test.tmp")
            with open(probe, "w") as fh:
                fh.write("ok")
            os.remove(probe)
            return True
        except Exception:
            return False

    # -- 造一张假截图，测试整条链路 --
    def fake_screenshot(self):
        ensure_dir(self.screenshot_dir)
        name = "WoWScrnShot_%s.png" % _dt.datetime.now().strftime("%m%d%y_%H%M%S")
        p = os.path.join(self.screenshot_dir, name)
        with open(p, "wb") as fh:
            fh.write(_tiny_png())
        LOG.info("已生成测试截图：%s" % p)
        return p

    # -- 主循环 --
    def run(self, exit_after_trigger=False):
        # 只处理"本进程启动之后"写入的截图：历史截图不算触发
        ignore_before = self.started_at
        LOG.info("=" * 70)
        LOG.info("%s v%s 启动" % (APP_NAME, APP_VERSION))
        LOG.info("  魔兽目录  ：%s" % (self.wow_root or "(未设置，仅归档截图+不录屏)"))
        LOG.info("  截图目录  ：%s" % self.screenshot_dir)
        LOG.info("  证据目录  ：%s" % self.evidence_dir)
        LOG.info("  分段目录  ：%s" % self.seg_dir)
        LOG.info("  ffmpeg    ：%s" % (self.ffmpeg or "(没找到，将不录屏)"))
        LOG.info("  ffprobe   ：%s" % (self.ring.ffprobe or "(没找到，replay.mp4 将跳过时长校验)"))
        LOG.info("  保留时长  ：%d 秒录像 / %d 秒聊天"
                 % (self.cfg.i("recording.video_seconds", 150),
                    self.cfg.i("evidence.chat_seconds", 180)))
        LOG.info("  轮询间隔  ：%.1f 秒" % self.cfg.f("advanced.poll_interval", 1.0))
        LOG.info("  忽略旧图  ：早于 %s 的截图不处理" % ts2str(ignore_before))
        if self.args.dry_run:
            LOG.info("  模式      ：dry-run（不真正录屏）")
        LOG.info("  提示      ：本窗口关掉录像就停了，可以最小化。Ctrl+C 退出。")
        LOG.info("=" * 70)

        if not self.ring.check_disk():
            LOG.error("%s —— 降级为「只归档截图 / 聊天记录」模式" % self.ring.disk_error)

        if self.ffmpeg and not self.args.dry_run:
            self.ring.start()
        elif not self.ffmpeg:
            LOG.warn("没有 ffmpeg，本次只归档截图和聊天记录，不会生成 replay.mp4")

        self.maybe_sync_notes(force=True)
        # 插件里如果已经跑过 /be test 并落过盘，启动时就把诊断信息导出成文件
        self.export_diagnostics()

        poll = max(0.2, self.cfg.f("advanced.poll_interval", 1.0))
        ticks = 0
        try:
            while not self.stopping:
                time.sleep(poll)
                ticks += 1

                # ffmpeg 掉了就重拉
                if not self.args.dry_run and self.ffmpeg and not self.ring.alive():
                    LOG.warn("ffmpeg 不在了（可能被结束或出错），重新启动")
                    self.ring.start()

                if ticks % 10 == 0:
                    self.ring.prune()

                # 实时日志：把插件写进聊天窗的行抄成文件（几秒的延迟）
                try:
                    self.live.poll()
                except Exception as ex:
                    LOG.exc("实时日志跟进出错（不影响其它功能）", ex)

                shots = self.scan_new_screenshots(ignore_before)
                for s in shots:
                    LOG.info("发现新截图：%s" % os.path.basename(s))
                    out = self.handle_trigger(s)
                    if out and exit_after_trigger:
                        LOG.info("--exit-after-trigger 已开启，归档完成后退出")
                        # 聊天二次读取是后台线程：给它一点时间收尾（不无限等）
                        self.archiver.join_chat_threads(timeout=5)
                        return 0
        except KeyboardInterrupt:
            LOG.info("收到 Ctrl+C，正在退出…")
        finally:
            self.ring.stop("退出")
            self.archiver.join_chat_threads(timeout=5)
        return 0


# ----------------------------------------------------------------------------
# 入口
# ----------------------------------------------------------------------------
def parse_args(argv):
    ap = argparse.ArgumentParser(
        prog="blackevidence_recorder.py",
        description="%s v%s —— 配合 BlackEvidence 插件保存最近几分钟的录像与聊天记录"
                    % (APP_NAME, APP_VERSION),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
常用示例：
  python blackevidence_recorder.py                      常驻运行
  python blackevidence_recorder.py --selftest            检查环境
  python blackevidence_recorder.py --dry-run --fake-screenshot --exit-after-trigger
                                                     跑一遍完整流程做测试（不录屏）
""")
    ap.add_argument("--wow-root", help="魔兽世界游戏目录（原样使用）")
    ap.add_argument("--watch", help="截图目录（默认 <wow-root>/Screenshots）")
    ap.add_argument("--out", help="证据输出目录")
    ap.add_argument("--segments", help="环形分段临时目录")
    ap.add_argument("--ffmpeg", help="ffmpeg 可执行文件路径")
    ap.add_argument("--config", help="配置文件路径")
    ap.add_argument("--log", help="日志文件路径")
    ap.add_argument("--video-seconds", type=int, help="录像保留秒数（默认 150）")
    ap.add_argument("--chat-seconds", type=int, help="聊天记录回看秒数（默认 180）")
    ap.add_argument("--region", help="只录屏幕区域 x,y,w,h")
    ap.add_argument("--dry-run", action="store_true", help="不启动 ffmpeg，只测归档流程")
    ap.add_argument("--selftest", action="store_true", help="环境自检后退出")
    ap.add_argument("--fake-screenshot", action="store_true", help="造一张假截图用于测试")
    ap.add_argument("--sync-notes", action="store_true", help="从 SavedVariables 补齐 note.txt 后退出")
    ap.add_argument("--export-diag", action="store_true",
                    help="把插件里 /be test 的诊断摘要导出成 evidence/_diagnostics/plugin_diag.txt 后退出")
    ap.add_argument("--exit-after-trigger", action="store_true", help="归档一次后退出（测试用）")
    ap.add_argument("--quiet", action="store_true", help="控制台只打印警告和错误")
    return ap.parse_args(argv)


# ----------------------------------------------------------------------------
# 单实例锁
# ----------------------------------------------------------------------------
def _pid_alive(pid):
    """判断某个 PID 是否还活着（跨平台，不依赖 psutil）。"""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            import ctypes
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            kernel32 = ctypes.windll.kernel32
            h = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
            if not h:
                return False
            try:
                code = ctypes.c_ulong()
                # STILL_ACTIVE = 259
                if kernel32.GetExitCodeProcess(h, ctypes.byref(code)):
                    return code.value == 259
                return True
            finally:
                kernel32.CloseHandle(h)
        except Exception:
            return False
    try:
        os.kill(pid, 0)          # 0 号信号只是探活
    except OSError:
        return False
    except Exception:
        return False
    return True


def acquire_lock(base_dir):
    """建 recorder/.lock 写入本进程 PID。已被别的活实例占用时返回 (None, 原因)。"""
    path = os.path.join(base_dir, ".lock")
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                other = (fh.read() or "").strip()
        except Exception:
            other = ""
        if other.isdigit() and int(other) != os.getpid() and _pid_alive(int(other)):
            return None, "已有录像助手在运行（PID %s），锁文件：%s" % (other, path)
        LOG.warn("发现过期的锁文件（PID %s 已不存在），接管" % (other or "?"))
    try:
        ensure_dir(base_dir)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(str(os.getpid()))
    except Exception as ex:
        LOG.exc("写锁文件失败（继续运行，但可能重复启动）", ex)
        return None, "写锁文件失败：%s" % ex
    return path, None


def release_lock(path):
    """退出时删锁；只删自己的（免得误删别人的锁）。"""
    if not path:
        return
    try:
        with open(path, "r", encoding="utf-8") as fh:
            owner = (fh.read() or "").strip()
        if owner and owner != str(os.getpid()):
            return
    except Exception:
        pass
    try:
        os.remove(path)
    except OSError:
        pass


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    base_dir = os.path.dirname(os.path.abspath(__file__))

    if args.config:
        cfg = Cfg(os.path.dirname(os.path.abspath(args.config)),
                  config_path=os.path.abspath(args.config))
    else:
        cfg = Cfg(base_dir)

    # 命令行覆盖配置
    override = {
        "recording.video_seconds": args.video_seconds,
        "evidence.chat_seconds": args.chat_seconds,
        "recording.region": args.region,
    }
    for k, v in override.items():
        if v is not None:
            cfg.raw[k] = str(v)

    global LOG
    LOG = Log(args.log or cfg.log_path(), quiet=args.quiet)
    LOG.info("%s v%s 日志开始（日志文件：%s）" % (APP_NAME, APP_VERSION, LOG.path))

    try:
        rec = Recorder(args, cfg)
    except Exception as ex:
        LOG.exc("初始化失败", ex)
        return 2

    if args.selftest:
        return rec.selftest()

    if args.sync_notes:
        n = rec.archiver.sync_notes()
        rec.export_diagnostics(force=True)
        return 0 if n >= 0 else 1

    if args.export_diag:
        rec.export_diagnostics(force=True)
        return 0

    # 常驻 / 触发类模式才需要单实例锁（自检、导出可以随便跑）
    lock_path, lock_err = acquire_lock(base_dir)
    if lock_err and lock_path is None and "已有录像助手" in lock_err:
        LOG.error(lock_err)
        LOG.error("如果确认没有别的实例，删掉锁文件后重试：%s"
                  % os.path.join(base_dir, ".lock"))
        return 3
    if lock_path:
        LOG.info("单实例锁：%s（PID %s）" % (lock_path, os.getpid()))

    try:
        if args.fake_screenshot:
            rec.fake_screenshot()
            if not args.exit_after_trigger:
                LOG.info("已生成测试截图。现在开始运行（Ctrl+C 退出）…")
                return rec.run()
            return rec.run(exit_after_trigger=True)

        return rec.run(exit_after_trigger=args.exit_after_trigger)
    finally:
        release_lock(lock_path)


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    sys.exit(main())
