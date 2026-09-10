"""Create fictional, isolated data for recording the real Clip app."""
from pathlib import Path
import hashlib
import shutil
import sqlite3
import time
import argparse

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--out", type=Path, default=repo / "build/promotion-demo")
home = parser.parse_args().out
home.mkdir(parents=True, exist_ok=True)
(home / "blobs").mkdir(exist_ok=True)
db = home / "clipbook.sqlite3"
if db.exists():
    raise SystemExit("Demo exists; reuse it or choose another isolated directory.")
c = sqlite3.connect(db)
c.executescript("""
CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,text TEXT NOT NULL DEFAULT '',blob TEXT,hash TEXT NOT NULL UNIQUE,app_name TEXT NOT NULL DEFAULT '',app_bundle TEXT NOT NULL DEFAULT '',created_at REAL NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,bytes INTEGER NOT NULL DEFAULT 0,width INTEGER NOT NULL DEFAULT 0,height INTEGER NOT NULL DEFAULT 0,rtf TEXT,title TEXT NOT NULL DEFAULT '',extra TEXT NOT NULL DEFAULT '');
CREATE TABLE collections(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,color TEXT NOT NULL DEFAULT '#2563eb',icon TEXT NOT NULL DEFAULT 'folder',sort_order INTEGER NOT NULL DEFAULT 0);
CREATE TABLE item_collections(item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,PRIMARY KEY(item_id,collection_id));
CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
INSERT INTO meta VALUES('deck_imported','demo-fixture');
INSERT INTO collections(name,color,icon) VALUES('常用片段','#8250ad','star');
""")
samples = [
    ("text", "你好！这是一段可以反复使用的开场白。\n找到、选中，再复制。", "常用开场白", "Notes", "com.apple.Notes"),
    ("text", "会议纪要\n1. 明确目标\n2. 分配任务\n3. 跟进结果", "会议纪要模板", "Notes", "com.apple.Notes"),
    ("code", '{"name":"Clip","platform":"macOS","local":true}', "JSON 片段", "Terminal", "com.apple.Terminal"),
    ("link", "https://developer.apple.com/swift/", "Swift 开发文档", "Safari", "com.apple.Safari"),
    ("color", "#8250ad", "品牌紫", "Notes", "com.apple.Notes"),
    ("text", "让工具更轻，让操作更快。", "产品笔记", "Notes", "com.apple.Notes"),
    ("code", "git status\ngit diff --stat", "常用 Git 命令", "Terminal", "com.apple.Terminal"),
    ("text", "发布前检查\n功能可用 · 键盘顺手 · 性能实测 · 演示清楚", "发布检查", "Notes", "com.apple.Notes"),
    ("link", "https://www.sqlite.org/", "SQLite 本地存储", "Safari", "com.apple.Safari"),
    ("text", "任务完成后回收预览内存。\n原始图片保持完整。", "轻量化笔记", "Notes", "com.apple.Notes"),
    ("text", "会议安排\n周三 10:00：产品演示\n周五 15:00：版本复盘", "会议安排", "Notes", "com.apple.Notes"),
    ("text", "快捷操作\n方向键移动\nShift 扩选\nReturn 复制", "键盘操作", "Notes", "com.apple.Notes"),
]
now = time.time()
for i, (kind, text, title, app, bundle) in enumerate(samples):
    c.execute("INSERT INTO items(kind,text,hash,app_name,app_bundle,created_at,pinned,bytes,title) VALUES(?,?,?,?,?,?,?,?,?)",
              (kind, text, hashlib.sha256((kind+text).encode()).hexdigest(), app, bundle, now-i*90, int(i==0), len(text.encode()), title))
shutil.copy2(repo/'icon/AppIcon.png', home/'blobs/demo-icon.png')
c.execute("INSERT INTO items(kind,text,blob,hash,app_name,app_bundle,created_at,bytes,width,height,title) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
          ('image','Clip 图标','demo-icon.png','demo-image','Finder','com.apple.finder',now-180,(home/'blobs/demo-icon.png').stat().st_size,1024,1024,'应用图标'))
c.execute("INSERT INTO item_collections VALUES(1,1)")
c.commit();c.close()
print(home)
