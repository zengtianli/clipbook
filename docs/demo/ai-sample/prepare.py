#!/usr/bin/env python3
"""Prepare lossless-source-derived clips for the editable Remotion sample."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RAW = ROOT / 'build/homepage-recording/raw'
PUBLIC = ROOT / 'build/ai-video-sample/public'
EDIT = json.loads((HERE / 'edit.json').read_text())
RECORDED = json.loads((HERE.parent / 'recording.json').read_text())
FFMPEG = shutil.which('ffmpeg')
FFPROBE = shutil.which('ffprobe')

def run(*args):
    subprocess.run(args, check=True)

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    assert FFMPEG and FFPROBE, 'ffmpeg and ffprobe are required'
    PUBLIC.mkdir(parents=True, exist_ok=True)
    sources = []
    offset = EDIT['introFrames'] / EDIT['fps']
    cues = []
    for chapter in EDIT['chapters']:
        raw = RAW / f"{chapter['id']}.mov"
        digest = sha(raw)
        assert digest == RECORDED['scenes'][chapter['id']]['raw_sha256'], f'Source changed: {raw}'
        info = json.loads(subprocess.check_output([FFPROBE, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(raw)]))
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        assert (video['width'], video['height']) == (1426, 890)
        sources.append({'file': str(raw.relative_to(ROOT)), 'sha256': digest, 'duration': float(info['format']['duration'])})
        for i, cut in enumerate(chapter['cuts']):
            assert 0 <= cut['start'] < cut['end'] <= float(info['format']['duration'])
            x, y, w, h = cut['crop']
            assert x >= 0 and y >= 0 and x+w <= 1426 and y+h <= 890
            n = round((cut['end'] - cut['start']) * EDIT['fps'])
            target = PUBLIC / f"{chapter['id']}-{i}.mp4"
            run(FFMPEG, '-y', '-v', 'error', '-ss', str(cut['start']), '-i', str(raw), '-vf', f"fps={EDIT['fps']},setpts=PTS-STARTPTS", '-frames:v', str(n), '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '16', '-pix_fmt', 'yuv420p', '-map_metadata', '-1', '-movflags', '+faststart', str(target))
            end = offset + n / EDIT['fps']
            cues.append((offset, end, cut['caption']))
            offset = end
    shutil.copyfile(ROOT / 'icon/AppIcon.png', PUBLIC / 'icon.png')
    run(FFMPEG, '-y', '-v', 'error', '-ss', '1', '-i', str(RAW / 'search.mov'), '-vf', 'crop=1380:844:23:16', '-frames:v', '1', str(PUBLIC / 'overview.jpg'))
    def timestamp(s):
        ms = round(s * 1000)
        return f'{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02}.{ms % 1000:03}'
    (HERE / 'sample.vtt').write_text('WEBVTT\n\n' + '\n\n'.join(f'{timestamp(a)} --> {timestamp(b)}\n{c}' for a, b, c in cues) + '\n')
    manifest = {'product': 'Clip', 'source_version': RECORDED['version'], 'source_build': RECORDED['build'], 'source_recorded_at': RECORDED['recorded_at'], 'synthetic_demo_data': True, 'sources': sources, 'resolution': [1920, 1080], 'fps': EDIT['fps'], 'duration': round(offset + EDIT['outroFrames'] / EDIT['fps'], 3), 'audio': 'silent; original sources have no audio', 'retained_footage_speed': 1, 'scope': ['搜索记录', '编辑保存', '从已有收藏夹取出并复制'], 'not_covered': RECORDED['not_covered'], 'edit_file': 'edit.json', 'composition': 'ClipSample'}
    (HERE / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'public': str(PUBLIC), 'duration': manifest['duration'], 'clips': len(cues)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
