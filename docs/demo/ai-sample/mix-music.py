#!/usr/bin/env python3
"""Add the documented CC0 music without re-encoding the approved video."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
FFMPEG = shutil.which('ffmpeg')
FFPROBE = shutil.which('ffprobe')

def main():
    assert FFMPEG and FFPROBE
    video, music = HERE / 'sample.mp4', HERE / 'music/sherwood.ogg'
    target = HERE / 'sample-music.mp4'
    info = json.loads(subprocess.check_output([FFPROBE, '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(video)]))
    seconds = float(info['format']['duration'])
    fade_in, fade_out = 1.2, 3.2
    filters = (f'atrim=duration={seconds},asetpts=PTS-STARTPTS,'
               'loudnorm=I=-22:TP=-2:LRA=8,'
               f'afade=t=in:st=0:d={fade_in},afade=t=out:st={seconds-fade_out}:d={fade_out}')
    subprocess.run([FFMPEG, '-y', '-v', 'error', '-i', str(video), '-stream_loop', '-1', '-i', str(music),
                    '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-af', filters, '-c:a', 'aac',
                    '-b:a', '192k', '-ar', '48000', '-t', str(seconds), '-map_metadata', '-1',
                    '-metadata', 'comment=Music: Sherwood by Chris Murphy (zesona), CC0 1.0; https://opengameart.org/content/sherwood',
                    '-movflags', '+faststart', str(target)], check=True)
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    result = {'track': 'Sherwood', 'author': 'Chris Murphy (zesona)', 'license': 'CC0-1.0',
              'source_url': 'https://opengameart.org/content/sherwood',
              'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/',
              'music_sha256': sha(music), 'input_video_sha256': sha(video), 'output_sha256': sha(target),
              'duration_seconds': seconds, 'target_lufs_before_fades': -22, 'fade_in_seconds': fade_in,
              'fade_out_seconds': fade_out, 'video_stream': 'copied without re-encoding', 'output': target.name}
    (HERE / 'music/mix.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(target), 'duration': seconds, 'bytes': target.stat().st_size}, ensure_ascii=False))

if __name__ == '__main__':
    main()
