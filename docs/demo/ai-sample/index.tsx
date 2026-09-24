import React from 'react';
import {AbsoluteFill, Composition, Easing, Img, OffthreadVideo, Sequence, interpolate, registerRoot, staticFile, useCurrentFrame} from 'remotion';
import edit from './edit.json';

const W = 1920, H = 1080, FPS = edit.fps;
const FULL = [23, 16, 1380, 844];
const VIEW = {x: 624, y: 185, w: 1216, h: 744};
const C = {ink: '#262035', muted: '#787080', accent: '#8061df', line: '#e2dce9'};
const font = '"PingFang SC", "Helvetica Neue", sans-serif';
const frames = (cut: {start: number, end: number}) => Math.round((cut.end - cut.start) * FPS);
const chapters = edit.chapters.map((chapter, i) => ({...chapter, i, duration: chapter.cuts.reduce((n, cut) => n + frames(cut), 0)}));
const duration = edit.introFrames + chapters.reduce((n, ch) => n + ch.duration, 0) + edit.outroFrames;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.22, 0.75, 0.15, 1);

function fitCamera(rect: number[]) {
  const [x, y, w, h] = rect;
  const rw = Math.max(w, h * VIEW.w / VIEW.h), rh = rw * VIEW.h / VIEW.w;
  return [Math.max(23, Math.min(1403 - rw, x + w / 2 - rw / 2)), Math.max(16, Math.min(860 - rh, y + h / 2 - rh / 2)), rw, rh];
}

function Background() {
  const f = useCurrentFrame();
  return <AbsoluteFill style={{background: '#f8f6fa', fontFamily: font, color: C.ink}}>
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 82% 45%, #e5dcf6 0%, transparent 65%), radial-gradient(ellipse at 10% 90%, #f3e5eb 0%, transparent 53%)'}} />
    <div style={{position: 'absolute', left: 76, top: 50, display: 'flex', alignItems: 'center', gap: 16}}>
      <Img src={staticFile('icon.png')} style={{width: 62, height: 62}} />
      <span style={{fontSize: 36, fontWeight: 650, letterSpacing: -1}}>Clip</span>
      <span style={{height: 25, width: 1, margin: '0 8px', background: '#d7cfdf'}} />
      <span style={{fontSize: 22, color: C.muted}}>让复制过的内容，再次有用</span>
    </div>
    <div style={{position: 'absolute', right: 80, top: 68, fontSize: 19, color: C.muted, letterSpacing: 1}}>macOS · 使用演示</div>
    <div style={{position: 'absolute', left: 80, bottom: 35, fontSize: 18, color: '#8c8297'}}>实机录屏 · 演示数据</div>
    <div style={{position: 'absolute', right: 80, bottom: 35, fontSize: 18, color: '#8c8297'}}>已剪去等待 · 操作原速</div>
    <div style={{position: 'absolute', left: 80, bottom: 16, height: 3, width: 1760, background: '#e6dfed', borderRadius: 4}}>
      <div style={{height: 3, width: `${f / (duration - 1) * 100}%`, background: C.accent, borderRadius: 4}} />
    </div>
  </AbsoluteFill>;
}

function VideoShot({chapter, cut, previous, index}: {chapter: typeof chapters[number], cut: typeof chapters[number]['cuts'][number], previous: number[], index: number}) {
  const f = useCurrentFrame();
  const t = interpolate(f, [0, 20], [0, 1], {...clamp, easing: ease});
  const a = fitCamera(previous), b = fitCamera(cut.crop);
  const rect = a.map((value, i) => value + (b[i] - value) * t);
  const scale = VIEW.w / rect[2];
  const alpha = interpolate(f, [0, 7], [0, 1], clamp);
  const detail = 'detail' in cut ? cut.detail as number[] : undefined;
  const detailLabel = 'detailLabel' in cut ? cut.detailLabel as string : '';
  const detailAlpha = interpolate(f, [3, 16], [0, 1], {...clamp, easing: ease});
  const detailScale = detail ? 1070 / detail[2] : 1;
  return <>
    <div style={{position: 'absolute', left: VIEW.x, top: VIEW.y, width: VIEW.w, height: VIEW.h, borderRadius: 22, boxShadow: '0 26px 75px #47326524, 0 2px 8px #49375612', overflow: 'hidden', background: '#fff', border: '1px solid #ded5e6'}}>
      <OffthreadVideo src={staticFile(`${chapter.id}-${index}.mp4`)} muted style={{position: 'absolute', left: -rect[0] * scale, top: -rect[1] * scale, width: 1426 * scale, height: 890 * scale, maxWidth: 'none'}} />
      {detail && <>
        <AbsoluteFill style={{background: '#f7f4fa', opacity: detailAlpha * 0.52}} />
        <div style={{position: 'absolute', left: 72, top: 454, width: 1070, borderRadius: 16, boxShadow: '0 15px 55px #38254e38', background: '#fff', border: '2px solid #baa4e8', overflow: 'hidden', opacity: detailAlpha, transform: `translateY(${(1-detailAlpha)*14}px)`}}>
          <div style={{padding: '16px 22px', background: '#f6f1fc', color: '#8463bd', fontSize: 18}}>{detailLabel}</div>
          <div style={{height: detail[3] * detailScale, width: 1070, overflow: 'hidden', position: 'relative'}}>
            <OffthreadVideo src={staticFile(`${chapter.id}-${index}.mp4`)} muted style={{position: 'absolute', left: -detail[0] * detailScale, top: -detail[1] * detailScale, width: 1426 * detailScale, height: 890 * detailScale, maxWidth: 'none'}} />
          </div>
        </div>
      </>}
    </div>
    <div style={{position: 'absolute', left: VIEW.x + 4, top: 144, display: 'flex', gap: 10, alignItems: 'center', color: '#82768f', fontSize: 18}}>
      <span style={{width: 7, height: 7, borderRadius: 7, background: C.accent}} />
      {detail ? '完整窗口 + 细节放大' : index === 0 || cut.crop[2] === FULL[2] ? '完整窗口' : '局部放大'}
    </div>
    <div style={{position: 'absolute', left: VIEW.x, top: 958, width: VIEW.w, display: 'flex', alignItems: 'center', gap: 17, opacity: alpha}}>
      <span style={{minWidth: 38, height: 38, borderRadius: 12, background: '#e9e2f4', color: C.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, fontWeight: 600}}>{index + 1}</span>
      <span style={{fontSize: 30, fontWeight: 500, letterSpacing: -0.4}}>{cut.caption}</span>
    </div>
  </>;
}

function Chapter({chapter}: {chapter: typeof chapters[number]}) {
  const f = useCurrentFrame();
  const enter = interpolate(f, [0, 15], [0, 1], {...clamp, easing: ease});
  let offset = 0;
  return <AbsoluteFill>
    <div style={{position: 'absolute', left: 80, top: 218, width: 505, opacity: enter, transform: `translateY(${(1 - enter) * 18}px)`}}>
      <div style={{color: C.accent, fontSize: 23, fontWeight: 650, display: 'flex', alignItems: 'center', gap: 18}}>
        <span style={{fontSize: 62, fontWeight: 300, letterSpacing: -3}}>0{chapter.i + 1}</span>
        <span>{chapter.label}</span>
      </div>
      <div style={{fontSize: 74, lineHeight: 1.25, fontWeight: 650, letterSpacing: -4, marginTop: 47}}>{chapter.headline.map((line, i) => <div key={line} style={{color: i === 1 ? C.accent : C.ink}}>{line}</div>)}</div>
      <div style={{fontSize: 25, lineHeight: 1.75, color: C.muted, marginTop: 36}}>{chapter.description.map(line => <div key={line}>{line}</div>)}</div>
      <div style={{marginTop: 43, display: 'inline-flex', alignItems: 'center', gap: 13, fontSize: 23, background: '#ffffff99', border: '1px solid #ddd4e9', padding: '12px 23px', borderRadius: 14, color: '#7154b8'}}>
        <span style={{fontSize: 18, color: '#a394b8'}}>{chapter.id === 'search' ? '搜索' : '点击'}</span>{chapter.keyword}
      </div>
    </div>
    <div style={{position: 'absolute', left: 82, top: 878, display: 'flex', gap: 13}}>{chapters.map(ch => <div key={ch.id} style={{width: ch.i === chapter.i ? 56 : 18, height: 6, background: ch.i === chapter.i ? C.accent : '#d7cde4', borderRadius: 6}} />)}</div>
    {chapter.cuts.map((cut, index) => {
      const from = offset; offset += frames(cut);
      return <Sequence key={index} from={from} durationInFrames={frames(cut)} premountFor={15}><VideoShot chapter={chapter} cut={cut} previous={index ? chapter.cuts[index - 1].crop : FULL} index={index} /></Sequence>;
    })}
  </AbsoluteFill>;
}

function Bookend({end = false}: {end?: boolean}) {
  const f = useCurrentFrame();
  const t = interpolate(f, [0, 20], [0, 1], {...clamp, easing: ease});
  return <AbsoluteFill>
    <div style={{position: 'absolute', left: 80, top: end ? 245 : 260, width: 580, opacity: t, transform: `translateY(${(1 - t) * 20}px)`}}>
      <div style={{fontSize: 22, color: C.accent, fontWeight: 600, letterSpacing: 3}}>{end ? 'CLIP · 每一次复制，都能再用' : '你的剪贴板，也可以井井有条'}</div>
      <div style={{fontSize: 86, lineHeight: 1.25, letterSpacing: -5, fontWeight: 650, marginTop: 35}}>{end ? '少一点重复，' : '复制过的，'}<br/><span style={{color: C.accent}}>{end ? '多一点顺手。' : '随时找回。'}</span></div>
      <div style={{display: 'flex', gap: 16, marginTop: 47}}>{['搜索', '编辑', '复用'].map((word, i) => <div key={word} style={{fontSize: 24, border: '1px solid #dcd2e8', borderRadius: 14, background: '#ffffff99', padding: '11px 21px'}}><span style={{color: '#a696bc', paddingRight: 10}}>0{i + 1}</span>{word}</div>)}</div>
      {end && <div style={{fontSize: 24, color: C.muted, lineHeight: 1.8, marginTop: 34}}>搜索历史 · 更新模板 · 复制常用片段</div>}
    </div>
    <div style={{position: 'absolute', left: 726, top: 210, width: 1108, height: 678, overflow: 'hidden', borderRadius: 22, boxShadow: '0 32px 100px #6650812c', border: '1px solid #ddd3e7', transform: `translateY(${(1-t)*25}px) scale(${0.97 + t * 0.03})`, opacity: t}}>
      <Img src={staticFile('overview.jpg')} style={{width: '100%', height: '100%'}} />
    </div>
    <div style={{position: 'absolute', left: 736, top: 926, fontSize: 21, color: C.muted}}>真实 Clip 窗口 · 三个独立操作片段</div>
  </AbsoluteFill>;
}

function Film() {
  let offset = edit.introFrames;
  return <AbsoluteFill style={{fontFamily: font, color: C.ink}}>
    <Background />
    <Sequence durationInFrames={edit.introFrames}><Bookend /></Sequence>
    {chapters.map(chapter => {const from = offset; offset += chapter.duration; return <Sequence from={from} durationInFrames={chapter.duration} key={chapter.id} premountFor={15}><Chapter chapter={chapter} /></Sequence>;})}
    <Sequence from={offset} durationInFrames={edit.outroFrames}><Bookend end /></Sequence>
  </AbsoluteFill>;
}

registerRoot(() => <Composition id="ClipSample" component={Film} durationInFrames={duration} fps={FPS} width={W} height={H} />);
