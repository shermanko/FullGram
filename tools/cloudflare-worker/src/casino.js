export const CASINO_HTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<title>PARIMATCH · BETON CASINO</title>
<style>
:root{
  --bg:#090b10;--bg2:#111520;--card:#171d2c;--card2:#1f273b;
  --pm:#f8ff13;--gold:#ffb800;--green:#00e676;--red:#ff2d55;--border:rgba(255,255,255,.08);
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none}
html,body{margin:0;padding:0;width:100%;height:100%;background:var(--bg);color:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif;overflow:hidden}
#app{display:flex;flex-direction:column;height:100%;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}
.topbar{display:flex;align-items:center;justify-content:space-between;padding:8px 12px;background:#0e121b;border-bottom:1px solid var(--border);gap:6px;flex-shrink:0}
.brand{display:flex;align-items:center;gap:6px;font-weight:900;font-size:14px;letter-spacing:.6px}
.pm-tag{background:var(--pm);color:#000;padding:2px 6px;border-radius:5px;font-size:11px;font-weight:900}
.bal-wrap{display:flex;align-items:center;gap:6px}
.bal-pill{background:var(--card2);border:1px solid rgba(248,255,19,.4);padding:5px 10px;border-radius:999px;font-weight:800;font-size:13px;font-variant-numeric:tabular-nums}
.btn-dep{background:linear-gradient(135deg,#00e676,#00b85c);color:#001a0c;border:none;padding:6px 10px;border-radius:999px;font-weight:900;font-size:11px}
.btn-ic{background:var(--card2);color:#fff;border:1px solid var(--border);width:30px;height:30px;border-radius:50%;font-size:13px;font-weight:800;display:flex;align-items:center;justify-content:center}
.main{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:10px 10px 16px}
.banner{position:relative;border-radius:18px;padding:16px;background:radial-gradient(circle at 85% 20%,rgba(248,255,19,.24),transparent 50%),linear-gradient(135deg,#241142 0%,#101628 60%,#2c1e06 100%);border:1px solid rgba(248,255,19,.32);margin-bottom:12px}
.banner h2{margin:6px 0 4px;font-size:18px;font-weight:900}
.banner p{margin:0 0 10px;font-size:12px;color:#94a3b8}
.bcta{background:var(--pm);color:#000;border:none;padding:9px 16px;border-radius:999px;font-weight:900;font-size:12px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.gcard{border-radius:16px;overflow:hidden;border:1px solid var(--border);background:var(--card);display:flex;flex-direction:column}
.gcard:active{transform:scale(.97)}
.gart{height:112px;position:relative;overflow:hidden}
.gart canvas{width:100%;height:100%;display:block}
.gbadge{position:absolute;top:7px;left:7px;font-size:9px;font-weight:900;padding:2px 6px;border-radius:5px}
.grtp{position:absolute;top:7px;right:7px;background:rgba(0,0,0,.6);font-size:9px;font-weight:700;padding:2px 6px;border-radius:5px;color:#e2e8f0}
.ginfo{padding:8px 10px 10px;display:flex;align-items:center;justify-content:space-between}
.gtitle{font-size:13px;font-weight:800}.gsub{font-size:10px;color:#94a3b8}
.gplay{background:var(--pm);color:#000;border:none;border-radius:999px;width:28px;height:28px;font-weight:900;font-size:11px}
.ghead{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;gap:8px}
.back{background:var(--card2);color:#fff;border:1px solid var(--border);padding:6px 11px;border-radius:999px;font-size:12px;font-weight:700}
.gname{font-size:13px;font-weight:900;color:var(--pm);letter-spacing:.4px}
.stage{border-radius:18px;overflow:hidden;border:1.5px solid rgba(255,184,0,.35);background:#090c14;position:relative;margin-bottom:9px;box-shadow:0 10px 30px rgba(0,0,0,.5)}
.stage canvas{width:100%;display:block}
.winbar{text-align:center;padding:7px 10px;font-size:13px;font-weight:900;background:rgba(12,16,28,.95);border-top:1px solid var(--border);min-height:34px;display:flex;align-items:center;justify-content:center}
.winbar.pos{color:var(--green)}.winbar.jackpot{color:var(--pm)}.winbar.neg{color:#94a3b8}
.ctrl{background:var(--bg2);border:1px solid var(--border);border-radius:16px;padding:10px}
.brow{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px;font-size:11px;font-weight:700;color:#94a3b8}
.bval{font-size:14px;font-weight:900;color:#fff}
.chips{display:grid;grid-template-columns:repeat(7,1fr);gap:5px;margin-bottom:8px}
.chip{background:var(--card2);color:#fff;border:1px solid var(--border);border-radius:9px;padding:7px 2px;font-size:11px;font-weight:800}
.chip:active{background:var(--pm);color:#000}
.extras{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-bottom:8px}
.xbtn{background:var(--card2);color:#fff;border:1px solid var(--border);border-radius:11px;padding:8px;font-size:11px;font-weight:800}
.xbtn.on{background:var(--gold);color:#000;border-color:var(--gold)}
.xbtn.bonus{background:linear-gradient(135deg,#9333ea,#6366f1);color:#fff;border:none}
.mbtn{width:100%;padding:13px;border-radius:13px;border:none;font-size:15px;font-weight:900;letter-spacing:.5px;background:linear-gradient(135deg,var(--pm),#ffd600);color:#000;box-shadow:0 5px 18px rgba(248,255,19,.25)}
.mbtn.cash{background:linear-gradient(135deg,#00e676,#00b85c);color:#001a0c}
.mbtn:active{transform:scale(.98)}
.rbets{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-bottom:8px}
.rb{padding:9px 4px;border-radius:10px;border:2px solid transparent;font-size:12px;font-weight:900;color:#fff}
.rb.r{background:#dc2626}.rb.b{background:#1e293b}.rb.g{background:#059669}.rb.sel{border-color:var(--pm)}
.chist{display:flex;gap:5px;overflow-x:auto;margin-bottom:7px;scrollbar-width:none}
.cp{padding:3px 8px;border-radius:999px;font-size:11px;font-weight:800;background:var(--card2)}
.cp.hi{color:var(--green)}.cp.lo{color:var(--red)}
.nav{display:flex;justify-content:space-around;padding:6px 4px;background:#0e121b;border-top:1px solid var(--border);flex-shrink:0}
.nitem{background:none;border:none;color:#64748b;font-size:11px;font-weight:800;padding:4px 8px}
.nitem.active{color:var(--pm)}
.modal{position:fixed;inset:0;background:rgba(0,0,0,.75);backdrop-filter:blur(6px);display:none;align-items:center;justify-content:center;padding:20px;z-index:60}
.modal.open{display:flex}
.mbox{width:100%;max-width:330px;background:var(--card);border:1px solid rgba(248,255,19,.35);border-radius:18px;padding:16px}
.mbox h3{margin:0 0 6px;font-size:16px;color:var(--pm)}
.minput{width:100%;padding:10px 12px;border-radius:11px;border:1px solid var(--border);background:var(--bg);color:#fff;font-size:16px;font-weight:800;margin:8px 0 10px}
.mq{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-bottom:10px}
.mq button{background:var(--card2);color:#fff;border:1px solid var(--border);border-radius:9px;padding:8px;font-size:12px;font-weight:800}
.ma{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.ma button{padding:11px;border-radius:11px;border:none;font-size:13px;font-weight:900}
</style>
</head>
<body>
<div id="app">
  <div class="topbar">
    <div class="brand"><span class="pm-tag">PM</span>BETON</div>
    <div class="bal-wrap">
      <div class="bal-pill" onclick="openDep()"><span id="balTxt">0</span> 🪙</div>
      <button class="btn-dep" onclick="openDep()">+ Касса</button>
      <button class="btn-ic" onclick="shareLast()">↗</button>
      <button class="btn-ic" onclick="closeApp()">✕</button>
    </div>
  </div>
  <div class="main" id="main"></div>
  <div class="nav">
    <button class="nitem" id="nv-lobby" onclick="openView('lobby')">Лобби</button>
    <button class="nitem" id="nv-zeus" onclick="openView('zeus')">Olympus</button>
    <button class="nitem" id="nv-crash" onclick="openView('crash')">Aviator</button>
    <button class="nitem" id="nv-roulette" onclick="openView('roulette')">Рулетка</button>
    <button class="nitem" id="nv-mines" onclick="openView('mines')">Мины</button>
  </div>
</div>

<div class="modal" id="depModal">
  <div class="mbox">
    <h3>Касса PARIMATCH · BETON</h3>
    <input class="minput" id="depIn" type="number" value="25000" inputmode="numeric">
    <div class="mq">
      <button onclick="addBal(5000)">+5 000</button>
      <button onclick="addBal(25000)">+25 000</button>
      <button onclick="addBal(100000)">+100 000</button>
    </div>
    <div class="ma">
      <button style="background:#334155;color:#fff" onclick="closeDep()">Отмена</button>
      <button style="background:var(--pm);color:#000" onclick="applyDep()">Зачислить</button>
    </div>
  </div>
</div>

<script>
const params = new URLSearchParams(location.search);
const savedBal = parseInt(localStorage.getItem('pm_beton_bal') || '10000', 10);
const savedFs = parseInt(localStorage.getItem('pm_beton_fs') || '0', 10);
const S = {
  balance: isNaN(savedBal) ? 10000 : savedBal,
  fs: isNaN(savedFs) ? 0 : savedFs,
  bmult: 1, ante: false, bet: 100,
  view: params.get('game') || 'lobby',
  lastShare: ''
};
const RED = new Set([1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]);
const WHEEL = [0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26];
let raf = null;

function bridge(action, payload){
  try { window.webkit.messageHandlers.fullgramPlugin.postMessage({ action, payload }); } catch(e){}
}
function hap(k){ bridge('haptic', k || 'light'); }
function save(){
  localStorage.setItem('pm_beton_bal', String(S.balance));
  localStorage.setItem('pm_beton_fs', String(S.fs));
  document.getElementById('balTxt').textContent = S.balance.toLocaleString('ru-RU');
}
function closeApp(){ stopAll(); bridge('close', true); }
function shareLast(){ bridge('shareChat', S.lastShare || ('PARIMATCH · BETON\\nБаланс: ' + S.balance + ' 🪙')); }
function openDep(){ document.getElementById('depModal').classList.add('open'); }
function closeDep(){ document.getElementById('depModal').classList.remove('open'); }
function addBal(n){ S.balance += n; save(); hap('success'); closeDep(); }
function applyDep(){ const v = parseInt(document.getElementById('depIn').value, 10); if(!isNaN(v) && v > 0){ S.balance += v; save(); hap('success'); } closeDep(); }
function stopAll(){ if(raf){ cancelAnimationFrame(raf); raf = null; } olympus.spinning = false; aviator.running = false; roul.spinning = false; }

function setBet(m){
  if(olympus.spinning || aviator.running || roul.spinning || mines.active) return;
  hap('light');
  const b = Math.max(10, S.balance);
  if(m==='half') S.bet = Math.max(10, Math.floor(S.bet/2));
  else if(m==='dbl') S.bet = Math.min(b, Math.max(10, S.bet*2));
  else if(m==='max') S.bet = b;
  else S.bet = Math.min(b, m);
  const el = document.getElementById('bval'); if(el) el.textContent = S.bet.toLocaleString('ru-RU') + ' 🪙';
  const bb = document.getElementById('bonusBtn'); if(bb) bb.textContent = 'Buy Bonus (' + (S.bet*100).toLocaleString('ru-RU') + ')';
}
function chipsHTML(){
  return '<div class="brow"><span>СТАВКА</span><span class="bval" id="bval">' + S.bet.toLocaleString('ru-RU') + ' 🪙</span></div>'
    + '<div class="chips">'
    + '<button class="chip" onclick="setBet(10)">10</button><button class="chip" onclick="setBet(50)">50</button>'
    + '<button class="chip" onclick="setBet(100)">100</button><button class="chip" onclick="setBet(500)">500</button>'
    + '<button class="chip" onclick="setBet(\\'half\\')">½</button><button class="chip" onclick="setBet(\\'dbl\\')">2x</button>'
    + '<button class="chip" onclick="setBet(\\'max\\')">MAX</button></div>';
}
function setBar(txt, cls){ const e = document.getElementById('wbar'); if(e){ e.textContent = txt; e.className = 'winbar ' + (cls || ''); } }

function drawGem(ctx, x, y, r, c1, c2, sides){
  ctx.save(); ctx.translate(x,y); ctx.shadowColor = c1; ctx.shadowBlur = 14;
  ctx.beginPath();
  for(let i=0;i<sides;i++){ const a=-Math.PI/2+i*(Math.PI*2/sides); const px=Math.cos(a)*r, py=Math.sin(a)*r; if(i===0) ctx.moveTo(px,py); else ctx.lineTo(px,py); }
  ctx.closePath();
  const g = ctx.createLinearGradient(-r,-r,r,r); g.addColorStop(0,c1); g.addColorStop(1,c2);
  ctx.fillStyle = g; ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.65)'; ctx.lineWidth = 2.5; ctx.stroke();
  ctx.shadowBlur = 0; ctx.beginPath();
  for(let i=0;i<sides;i++){ const a=-Math.PI/2+i*(Math.PI*2/sides); const px=Math.cos(a)*r*0.52, py=Math.sin(a)*r*0.52; if(i===0) ctx.moveTo(px,py); else ctx.lineTo(px,py); }
  ctx.closePath(); ctx.fillStyle = 'rgba(255,255,255,0.28)'; ctx.fill();
  ctx.beginPath(); ctx.arc(-r*0.28,-r*0.28,r*0.16,0,Math.PI*2); ctx.fillStyle = 'rgba(255,255,255,0.85)'; ctx.fill();
  ctx.restore();
}
function drawCrown(ctx, x, y, r){
  ctx.save(); ctx.translate(x,y); ctx.shadowColor='#ffb800'; ctx.shadowBlur=16;
  const g=ctx.createLinearGradient(0,-r,0,r); g.addColorStop(0,'#fff3a0'); g.addColorStop(0.5,'#ffb800'); g.addColorStop(1,'#b45309');
  ctx.beginPath(); ctx.moveTo(-r*0.85,r*0.55); ctx.lineTo(-r*0.95,-r*0.35); ctx.lineTo(-r*0.38,r*0.05); ctx.lineTo(0,-r*0.72); ctx.lineTo(r*0.38,r*0.05); ctx.lineTo(r*0.95,-r*0.35); ctx.lineTo(r*0.85,r*0.55); ctx.closePath();
  ctx.fillStyle=g; ctx.fill(); ctx.strokeStyle='#fef08a'; ctx.lineWidth=2.5; ctx.stroke();
  ctx.fillStyle='#ff2d55'; ctx.beginPath(); ctx.arc(0,r*0.18,r*0.16,0,Math.PI*2); ctx.fill();
  ctx.fillStyle='#38bdf8'; ctx.beginPath(); ctx.arc(-r*0.48,r*0.24,r*0.11,0,Math.PI*2); ctx.fill();
  ctx.beginPath(); ctx.arc(r*0.48,r*0.24,r*0.11,0,Math.PI*2); ctx.fill();
  ctx.restore();
}
function drawHourglass(ctx, x, y, r){
  ctx.save(); ctx.translate(x,y); ctx.shadowColor='#38bdf8'; ctx.shadowBlur=12;
  const g=ctx.createLinearGradient(-r,-r,r,r); g.addColorStop(0,'#fde047'); g.addColorStop(1,'#b45309');
  ctx.fillStyle=g; ctx.fillRect(-r*0.65,-r*0.82,r*1.3,r*0.18); ctx.fillRect(-r*0.65,r*0.64,r*1.3,r*0.18);
  ctx.beginPath(); ctx.moveTo(-r*0.52,-r*0.64); ctx.lineTo(r*0.52,-r*0.64); ctx.lineTo(r*0.12,0); ctx.lineTo(r*0.52,r*0.64); ctx.lineTo(-r*0.52,r*0.64); ctx.lineTo(-r*0.12,0); ctx.closePath();
  ctx.fillStyle='rgba(56,189,248,0.35)'; ctx.fill(); ctx.strokeStyle='#fde047'; ctx.lineWidth=3; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(-r*0.36,r*0.58); ctx.lineTo(r*0.36,r*0.58); ctx.lineTo(0,r*0.15); ctx.closePath(); ctx.fillStyle='#fbbf24'; ctx.fill();
  ctx.restore();
}
function drawZeusScatter(ctx, x, y, r){
  ctx.save(); ctx.translate(x,y); ctx.shadowColor='#f8ff13'; ctx.shadowBlur=20;
  const g=ctx.createRadialGradient(0,0,r*0.1,0,0,r); g.addColorStop(0,'#fffbeb'); g.addColorStop(0.45,'#facc15'); g.addColorStop(1,'#92400e');
  ctx.beginPath(); ctx.arc(0,0,r*0.92,0,Math.PI*2); ctx.fillStyle=g; ctx.fill(); ctx.strokeStyle='#fff'; ctx.lineWidth=3; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(r*0.12,-r*0.62); ctx.lineTo(-r*0.35,r*0.04); ctx.lineTo(r*0.02,r*0.04); ctx.lineTo(-r*0.14,r*0.64); ctx.lineTo(r*0.38,-r*0.06); ctx.lineTo(0,-r*0.06); ctx.closePath();
  ctx.fillStyle='#1e1b4b'; ctx.fill(); ctx.strokeStyle='#fef08a'; ctx.lineWidth=2; ctx.stroke();
  ctx.restore();
}
function drawSymbol(ctx, id, x, y, r){
  if(id===0) drawGem(ctx,x,y,r,'#38bdf8','#1d4ed8',6);
  else if(id===1) drawGem(ctx,x,y,r,'#34d399','#047857',5);
  else if(id===2) drawGem(ctx,x,y,r,'#f43f5e','#9f1239',4);
  else if(id===3) drawGem(ctx,x,y,r,'#c084fc','#6b21a8',8);
  else if(id===4) drawHourglass(ctx,x,y,r);
  else if(id===5) drawCrown(ctx,x,y,r);
  else drawZeusScatter(ctx,x,y,r);
}

// 1. GATES OF OLYMPUS
const olympus = { grid: Array.from({length:15},(_,i)=>i%7), yOff: Array(15).fill(0), winMask: Array(15).fill(false), spinning:false, lightning:0, orb:null, coins:[] };
function renderOlympus(){
  document.getElementById('main').innerHTML =
    '<div class="ghead"><button class="back" onclick="openView(\\'lobby\\')">← Лобби</button><div class="gname">GATES OF OLYMPUS · HD</div><span style="font-size:11px;font-weight:900;color:var(--pm)" id="fsLbl">' + (S.fs>0?'FS:'+S.fs:'') + '</span></div>'
    + '<div class="stage"><canvas id="olyCv" height="310"></canvas><div class="winbar" id="wbar">Нажмите SPIN для запуска барабанов</div></div>'
    + '<div class="ctrl">' + chipsHTML()
    + '<div class="extras"><button class="xbtn ' + (S.ante?'on':'') + '" id="anteBtn" onclick="toggleAnte()">Ante Bet +25%</button><button class="xbtn bonus" id="bonusBtn" onclick="buyBonus()">Buy Bonus (' + (S.bet*100).toLocaleString('ru-RU') + ')</button></div>'
    + '<button class="mbtn" onclick="spinOlympus()">SPIN</button></div>';
  startOlympusLoop();
}
function toggleAnte(){ if(olympus.spinning||S.fs>0) return; S.ante=!S.ante; hap('light'); document.getElementById('anteBtn')?.classList.toggle('on',S.ante); }
function buyBonus(){
  if(olympus.spinning) return;
  const cost=S.bet*100;
  if(S.balance<cost){ setBar('Нужно '+cost+' 🪙 (пополните в Кассе)','neg'); return; }
  S.balance-=cost; S.fs+=10; S.bmult=1; save(); hap('success');
  document.getElementById('fsLbl').textContent='FS:'+S.fs;
  setBar('КУПЛЕНО 10 ФРИСПИНОВ! Жмите SPIN!','jackpot');
}
function startOlympusLoop(){
  const cv=document.getElementById('olyCv'); if(!cv) return;
  const ctx=cv.getContext('2d');
  const loop=(t)=>{
    if(S.view!=='zeus') return;
    const w=cv.width=cv.clientWidth*2, h=cv.height=620;
    const bg=ctx.createLinearGradient(0,0,0,h); bg.addColorStop(0,'#1e0b36'); bg.addColorStop(0.55,'#11152c'); bg.addColorStop(1,'#29160a');
    ctx.fillStyle=bg; ctx.fillRect(0,0,w,h);
    ctx.fillStyle='rgba(255,215,120,0.08)'; ctx.fillRect(14,20,32,h-40); ctx.fillRect(w-46,20,32,h-40);
    const padX=36, padY=28, rw=w-padX*2, rh=h-padY*2;
    ctx.fillStyle='rgba(8,10,22,0.82)'; ctx.beginPath(); ctx.roundRect(padX,padY,rw,rh,22); ctx.fill();
    ctx.strokeStyle='#ffb800'; ctx.lineWidth=5; ctx.stroke();
    const cw=rw/5, ch=rh/3;
    ctx.strokeStyle='rgba(255,184,0,0.16)'; ctx.lineWidth=2;
    for(let c=1;c<5;c++){ ctx.beginPath(); ctx.moveTo(padX+c*cw,padY+8); ctx.lineTo(padX+c*cw,padY+rh-8); ctx.stroke(); }
    ctx.save(); ctx.beginPath(); ctx.roundRect(padX+4,padY+4,rw-8,rh-8,18); ctx.clip();
    for(let r=0;r<3;r++){
      for(let c=0;c<5;c++){
        const idx=r*5+c, cx=padX+c*cw+cw/2, cy=padY+r*ch+ch/2+olympus.yOff[idx];
        if(olympus.winMask[idx]){
          const pulse=0.5+0.5*Math.sin(t/110);
          ctx.fillStyle='rgba(248,255,19,'+(0.14+pulse*0.18)+')';
          ctx.beginPath(); ctx.roundRect(padX+c*cw+6,padY+r*ch+6,cw-12,ch-12,14); ctx.fill();
          ctx.strokeStyle='#f8ff13'; ctx.lineWidth=3.5; ctx.stroke();
        }
        drawSymbol(ctx, olympus.grid[idx], cx, cy, Math.min(cw,ch)*0.34);
      }
    }
    ctx.restore();
    if(olympus.lightning>0){
      olympus.lightning-=0.04; ctx.save();
      ctx.strokeStyle='rgba(248,255,19,'+olympus.lightning+')'; ctx.shadowColor='#f8ff13'; ctx.shadowBlur=24; ctx.lineWidth=7;
      ctx.beginPath(); let lx=w*0.5, ly=0; ctx.moveTo(lx,ly);
      for(let k=1;k<=7;k++){ lx+=(Math.random()-0.5)*140; ly=(h/7)*k; ctx.lineTo(lx,ly); }
      ctx.stroke(); ctx.restore();
    }
    if(olympus.orb && olympus.orb.alpha>0){
      olympus.orb.alpha-=0.012; ctx.save(); ctx.globalAlpha=Math.min(1,olympus.orb.alpha*1.5); ctx.translate(w/2,h/2);
      const og=ctx.createRadialGradient(0,0,10,0,0,90); og.addColorStop(0,'#fff'); og.addColorStop(0.45,'#f8ff13'); og.addColorStop(1,'rgba(255,184,0,0)');
      ctx.fillStyle=og; ctx.beginPath(); ctx.arc(0,0,95,0,Math.PI*2); ctx.fill();
      ctx.fillStyle='#090b10'; ctx.font='900 62px -apple-system,sans-serif'; ctx.textAlign='center'; ctx.fillText('x'+olympus.orb.mult,0,22); ctx.restore();
    }
    for(let i=olympus.coins.length-1;i>=0;i--){
      const cn=olympus.coins[i]; cn.x+=cn.vx; cn.y+=cn.vy; cn.vy+=0.6; cn.life-=0.015;
      if(cn.life<=0){ olympus.coins.splice(i,1); continue; }
      ctx.save(); ctx.globalAlpha=cn.life; ctx.fillStyle='#f8ff13'; ctx.beginPath(); ctx.arc(cn.x,cn.y,cn.r,0,Math.PI*2); ctx.fill();
      ctx.strokeStyle='#b45309'; ctx.lineWidth=3; ctx.stroke(); ctx.restore();
    }
    raf=requestAnimationFrame(loop);
  };
  raf=requestAnimationFrame(loop);
}
function spinOlympus(){
  if(olympus.spinning) return;
  if(S.balance<10) S.balance=500;
  if(S.bet>S.balance) S.bet=S.balance;
  const isFS=S.fs>0, cost=isFS?0:Math.min(S.balance,S.ante?Math.round(S.bet*1.25):S.bet);
  if(!isFS) S.balance-=cost; else S.fs--;
  save(); hap('medium'); olympus.spinning=true; olympus.winMask.fill(false); setBar('Барабаны Олимпа в движении…','');
  const weights=(S.ante||isFS)?[26,22,18,14,10,6,10]:[30,24,18,14,9,5,5];
  const pick=()=>{ const tot=weights.reduce((a,b)=>a+b,0); let r=Math.random()*tot; for(let i=0;i<weights.length;i++){ if(r<weights[i]) return i; r-=weights[i]; } return 0; };
  const nextGrid=Array.from({length:15},pick);
  const t0=performance.now();
  const dropAnim=(now)=>{
    const dt=now-t0;
    if(dt<260){ const p=dt/260; for(let i=0;i<15;i++) olympus.yOff[i]=p*p*650; requestAnimationFrame(dropAnim); return; }
    if(dt>=260 && olympus.grid!==nextGrid){ olympus.grid=nextGrid; for(let i=0;i<15;i++) olympus.yOff[i]=-650; }
    let allDone=true;
    for(let c=0;c<5;c++){
      const cd=dt-260-c*75;
      for(let r=0;r<3;r++){
        const idx=r*5+c;
        if(cd<=0){ olympus.yOff[idx]=-650; allDone=false; }
        else if(cd<320){ const p=cd/320; olympus.yOff[idx]=-650*(1-(1-Math.pow(1-p,3))); allDone=false; }
        else olympus.yOff[idx]=0;
      }
    }
    if(!allDone){ requestAnimationFrame(dropAnim); return; }
    hap('light'); olympus.spinning=false; evalOlympus(nextGrid,S.bet,cost,isFS);
  };
  requestAnimationFrame(dropAnim);
}
function evalOlympus(grid, bet, cost, isFS){
  const cnt=[0,0,0,0,0,0,0]; grid.forEach(id=>cnt[id]++);
  const pays=[0.4,0.55,0.8,1.1,1.6,2.5]; let best=0, winId=-1;
  for(let id=0;id<6;id++){ if(cnt[id]>=6){ const v=pays[id]*(1+(cnt[id]-6)*0.65); if(v>best){ best=v; winId=id; } } }
  const scatters=cnt[6]; let mult=0, status='Пустой спин';
  if(best>0){
    const orbs=[2,2,3,5,10,25,50,100], orb=(scatters>0||isFS)?orbs[Math.floor(Math.random()*orbs.length)]:1;
    if(isFS && orb>1) S.bmult+=orb;
    const eff=isFS?S.bmult:orb; mult=best*eff;
    if(eff>1){ olympus.lightning=1.0; olympus.orb={mult:eff,alpha:1.2}; }
    status=eff>1?('МОЛНИЯ ЗЕВСА x'+eff+'!'):'КЛАСТЕР СЫГРАЛ!';
    grid.forEach((id,i)=>{ if(id===winId||id===6) olympus.winMask[i]=true; });
  }
  if(scatters>=4){ S.fs+=isFS?5:10; if(!isFS){ S.bmult=1; mult=Math.max(mult,3); } olympus.lightning=1.0; status='4+ SCATTER! БОНУС ФРИСПИНЫ!'; }
  const pay=Math.round(bet*mult); S.balance+=pay; save();
  const fsl=document.getElementById('fsLbl'); if(fsl) fsl.textContent=S.fs>0?'FS:'+S.fs:'';
  if(pay>0){
    hap('success');
    for(let i=0;i<26;i++) olympus.coins.push({x:320+(Math.random()-0.5)*220,y:300,vx:(Math.random()-0.5)*14,vy:-Math.random()*16-6,r:10+Math.random()*7,life:1});
    setBar(status+'  +'+pay.toLocaleString('ru-RU')+' 🪙', pay>=bet*5?'jackpot':'pos');
  } else setBar(status+' (-'+cost+' 🪙)','neg');
  S.lastShare='PARIMATCH · Gates of Olympus\\n'+status+' · Выплата: '+pay+' 🪙 · Баланс: '+S.balance+' 🪙';
}

// 2. AVIATOR CRASH
const aviator = { running:false, mult:1, crashAt:2, bet:100, start:0, hist:[2.84,1.15,6.40,1.92,18.5,1.03] };
function renderAviator(){
  document.getElementById('main').innerHTML =
    '<div class="ghead"><button class="back" onclick="openView(\\'lobby\\')">← Лобби</button><div class="gname">AVIATOR · LIVE CRASH</div><span style="width:52px"></span></div>'
    + '<div class="chist" id="chist">' + aviator.hist.map(x=>'<span class="cp '+(x>=2?'hi':'lo')+'">'+x.toFixed(2)+'x</span>').join('') + '</div>'
    + '<div class="stage"><canvas id="avCv" height="260"></canvas><div class="winbar" id="wbar">Нажмите СТАРТ и заберите до улёта самолёта!</div></div>'
    + '<div class="ctrl">' + chipsHTML() + '<button class="mbtn" id="avBtn" onclick="toggleAviator()">СТАРТ ПОЛЁТА</button></div>';
  drawAviator(1.0,0,false,0);
}
function drawPlane(ctx, x, y, angle, t){
  ctx.save(); ctx.translate(x,y); ctx.rotate(angle); ctx.shadowColor='#ff2d55'; ctx.shadowBlur=18;
  ctx.fillStyle='#ff2d55'; ctx.beginPath(); ctx.ellipse(0,0,34,11,0,0,Math.PI*2); ctx.fill();
  ctx.beginPath(); ctx.moveTo(-26,-2); ctx.lineTo(-40,-20); ctx.lineTo(-18,-6); ctx.closePath(); ctx.fill();
  ctx.fillStyle='#ff6b81'; ctx.beginPath(); ctx.ellipse(2,-10,20,6,-0.15,0,Math.PI*2); ctx.fill();
  ctx.fillStyle='#e0f2fe'; ctx.beginPath(); ctx.arc(8,-4,6,0,Math.PI*2); ctx.fill();
  const ph=12+Math.sin(t/25)*10; ctx.strokeStyle='#fff'; ctx.lineWidth=3.5; ctx.beginPath(); ctx.moveTo(35,-ph); ctx.lineTo(35,ph); ctx.stroke();
  ctx.restore();
}
function drawAviator(mult, prog, crashed, t){
  const cv=document.getElementById('avCv'); if(!cv) return;
  const ctx=cv.getContext('2d'); const w=cv.width=cv.clientWidth*2, h=cv.height=520;
  ctx.fillStyle='#0a0c12'; ctx.fillRect(0,0,w,h);
  ctx.save(); ctx.translate(0,h); ctx.rotate((t||0)*0.00018);
  for(let i=0;i<12;i++){ ctx.rotate(Math.PI/6); ctx.fillStyle=i%2===0?'rgba(255,45,85,0.035)':'transparent'; ctx.beginPath(); ctx.moveTo(0,0); ctx.arc(0,0,w*1.4,0,Math.PI/12); ctx.closePath(); ctx.fill(); }
  ctx.restore();
  if(prog>0){
    const sx=28, sy=h-28, ex=sx+(w-110)*Math.min(1,prog), ey=sy-(h-110)*Math.pow(Math.min(1,prog),1.3);
    const cx=sx+(ex-sx)*0.6, cy=sy-(sy-ey)*0.12;
    const g=ctx.createLinearGradient(0,ey,0,sy); g.addColorStop(0,'rgba(255,45,85,0.42)'); g.addColorStop(1,'rgba(255,45,85,0)');
    ctx.beginPath(); ctx.moveTo(sx,sy); ctx.quadraticCurveTo(cx,cy,ex,ey); ctx.lineTo(ex,sy); ctx.closePath(); ctx.fillStyle=g; ctx.fill();
    ctx.beginPath(); ctx.moveTo(sx,sy); ctx.quadraticCurveTo(cx,cy,ex,ey); ctx.strokeStyle='#ff2d55'; ctx.lineWidth=7; ctx.stroke();
    if(!crashed) drawPlane(ctx,ex+8,ey-12,-0.32,t);
  }
  ctx.fillStyle=crashed?'#ff2d55':'#fff'; ctx.font='900 104px -apple-system,sans-serif'; ctx.textAlign='center';
  ctx.fillText(mult.toFixed(2)+'x', w/2, h/2+24);
  if(crashed){ ctx.fillStyle='#ff2d55'; ctx.font='900 30px -apple-system,sans-serif'; ctx.fillText('FLEW AWAY!', w/2, h/2-74); }
}
function toggleAviator(){
  if(aviator.running){
    aviator.running=false; if(raf) cancelAnimationFrame(raf);
    const pay=Math.round(aviator.bet*aviator.mult); S.balance+=pay; save(); hap('success');
    aviator.hist.unshift(aviator.crashAt); aviator.hist=aviator.hist.slice(0,10);
    setBar('ЗАБРАЛ '+aviator.mult.toFixed(2)+'x (+'+pay.toLocaleString('ru-RU')+' 🪙)!','pos');
    S.lastShare='PARIMATCH Aviator\\nЗабрал на '+aviator.mult.toFixed(2)+'x (+'+pay+' 🪙)! Баланс: '+S.balance+' 🪙';
    const b=document.getElementById('avBtn'); if(b){ b.className='mbtn'; b.textContent='СТАРТ ПОЛЁТА'; }
    return;
  }
  if(S.balance<10) S.balance=500;
  if(S.bet>S.balance) S.bet=S.balance;
  S.balance-=S.bet; save(); hap('medium');
  aviator.bet=S.bet; aviator.mult=1; aviator.start=performance.now(); aviator.running=true;
  aviator.crashAt=Math.random()<0.03?1.01:Math.min(50,Math.max(1.06,0.97/(1-Math.random()*0.985)));
  setBar('Самолёт набирает высоту…','');
  const tick=(now)=>{
    if(!aviator.running) return;
    const sec=(now-aviator.start)/1000, m=Math.exp(sec*0.25); aviator.mult=m;
    if(m>=aviator.crashAt){
      aviator.running=false; drawAviator(aviator.crashAt,Math.min(1,sec/7.5),true,now);
      aviator.hist.unshift(aviator.crashAt); aviator.hist=aviator.hist.slice(0,10);
      const ch=document.getElementById('chist'); if(ch) ch.innerHTML=aviator.hist.map(x=>'<span class="cp '+(x>=2?'hi':'lo')+'">'+x.toFixed(2)+'x</span>').join('');
      hap('error'); setBar('УЛЕТЕЛ на '+aviator.crashAt.toFixed(2)+'x (-'+aviator.bet+' 🪙)','neg');
      const b=document.getElementById('avBtn'); if(b){ b.className='mbtn'; b.textContent='СТАРТ ПОЛЁТА'; }
      return;
    }
    drawAviator(m,Math.min(1,sec/7.5),false,now);
    const b=document.getElementById('avBtn'); if(b){ b.className='mbtn cash'; b.textContent='ЗАБРАТЬ '+m.toFixed(2)+'x (+'+Math.round(aviator.bet*m)+' 🪙)'; }
    raf=requestAnimationFrame(tick);
  };
  raf=requestAnimationFrame(tick);
}

// 3. EUROPEAN ROULETTE 3D
const roul = { bet:'red', a:0, ba:0, spinning:false };
function renderRoulette(){
  document.getElementById('main').innerHTML =
    '<div class="ghead"><button class="back" onclick="openView(\\'lobby\\')">← Лобби</button><div class="gname">EUROPEAN ROULETTE · 3D</div><span style="width:52px"></span></div>'
    + '<div class="stage"><canvas id="rCv" height="260"></canvas><div class="winbar" id="wbar">Выберите цвет и крутите колесо!</div></div>'
    + '<div class="ctrl"><div class="rbets">'
    + '<button class="rb r '+(roul.bet==='red'?'sel':'')+'" onclick="pickR(\\'red\\')">Красное x2</button>'
    + '<button class="rb b '+(roul.bet==='black'?'sel':'')+'" onclick="pickR(\\'black\\')">Чёрное x2</button>'
    + '<button class="rb g '+(roul.bet==='green'?'sel':'')+'" onclick="pickR(\\'green\\')">Зеро x36</button></div>'
    + chipsHTML() + '<button class="mbtn" onclick="spinRoul()">КРУТИТЬ КОЛЕСО</button></div>';
  drawRoul(roul.a, roul.ba, null);
}
function pickR(b){ if(roul.spinning) return; roul.bet=b; hap('light'); renderRoulette(); }
function drawRoul(a, ba, landed){
  const cv=document.getElementById('rCv'); if(!cv) return;
  const ctx=cv.getContext('2d'); const w=cv.width=cv.clientWidth*2, h=cv.height=520;
  const bg=ctx.createRadialGradient(w/2,h/2,40,w/2,h/2,w*0.6); bg.addColorStop(0,'#0f3b28'); bg.addColorStop(1,'#071710');
  ctx.fillStyle=bg; ctx.fillRect(0,0,w,h);
  const cx=w/2, cy=h/2, R=Math.min(w,h)*0.44, step=(Math.PI*2)/37;
  const wg=ctx.createRadialGradient(cx,cy,R,cx,cy,R+26); wg.addColorStop(0,'#3b180b'); wg.addColorStop(0.5,'#7c3518'); wg.addColorStop(1,'#290f06');
  ctx.beginPath(); ctx.arc(cx,cy,R+24,0,Math.PI*2); ctx.fillStyle=wg; ctx.fill(); ctx.strokeStyle='#ffb800'; ctx.lineWidth=4; ctx.stroke();
  for(let i=0;i<37;i++){
    const num=WHEEL[i], a0=a+i*step, a1=a0+step;
    ctx.beginPath(); ctx.moveTo(cx,cy); ctx.arc(cx,cy,R,a0,a1); ctx.closePath();
    ctx.fillStyle=num===0?'#059669':(RED.has(num)?'#c81e2b':'#141820'); ctx.fill(); ctx.strokeStyle='#d4af37'; ctx.lineWidth=1.8; ctx.stroke();
    ctx.save(); ctx.translate(cx+Math.cos(a0+step/2)*R*0.85, cy+Math.sin(a0+step/2)*R*0.85); ctx.rotate(a0+step/2+Math.PI/2);
    ctx.fillStyle='#fff'; ctx.font='bold 18px sans-serif'; ctx.textAlign='center'; ctx.fillText(String(num),0,6); ctx.restore();
  }
  const cg=ctx.createRadialGradient(cx-15,cy-15,10,cx,cy,R*0.44); cg.addColorStop(0,'#fde047'); cg.addColorStop(0.5,'#b45309'); cg.addColorStop(1,'#451a03');
  ctx.beginPath(); ctx.arc(cx,cy,R*0.44,0,Math.PI*2); ctx.fillStyle=cg; ctx.fill();
  ctx.beginPath(); ctx.arc(cx,cy,R*0.30,0,Math.PI*2); ctx.fillStyle='#0b0d12'; ctx.fill();
  ctx.fillStyle='#f8ff13'; ctx.font='900 48px -apple-system,sans-serif'; ctx.textAlign='center'; ctx.fillText(landed!==null?String(landed):'PM', cx, cy+17);
  const br=R*0.66, bx=cx+Math.cos(ba)*br, by=cy+Math.sin(ba)*br;
  ctx.shadowColor='#000'; ctx.shadowBlur=10;
  const bg2=ctx.createRadialGradient(bx-3,by-3,2,bx,by,11); bg2.addColorStop(0,'#fff'); bg2.addColorStop(1,'#94a3b8');
  ctx.beginPath(); ctx.arc(bx,by,11,0,Math.PI*2); ctx.fillStyle=bg2; ctx.fill();
}
function spinRoul(){
  if(roul.spinning) return;
  if(S.balance<10) S.balance=500;
  if(S.bet>S.balance) S.bet=S.balance;
  const bet=S.bet; S.balance-=bet; save(); hap('medium'); roul.spinning=true;
  const idx=Math.floor(Math.random()*37), landed=WHEEL[idx], step=(Math.PI*2)/37;
  const sa=roul.a, ea=sa+Math.PI*6, tba=ea+idx*step+step/2, sba=tba-Math.PI*10;
  const t0=performance.now(), dur=2700; setBar('Колесо вращается…','');
  const go=(now)=>{
    const p=Math.min(1,(now-t0)/dur), ease=1-Math.pow(1-p,3);
    roul.a=sa+(ea-sa)*ease; roul.ba=sba+(tba-sba)*ease; drawRoul(roul.a,roul.ba,p>=1?landed:null);
    if(p<1){ raf=requestAnimationFrame(go); return; }
    roul.spinning=false;
    const isG=landed===0, isR=RED.has(landed);
    const won=(roul.bet==='green'&&isG)||(roul.bet==='red'&&isR)||(roul.bet==='black'&&!isG&&!isR);
    const mult=roul.bet==='green'?36:2, pay=won?bet*mult:0; S.balance+=pay; save();
    const lbl=isG?'Зеро [0]':(isR?'Красное ['+landed+']':'Чёрное ['+landed+']');
    if(won){ hap('success'); setBar('ВЫИГРЫШ! '+lbl+' · +'+pay.toLocaleString('ru-RU')+' 🪙','pos'); }
    else { hap('error'); setBar('Выпало '+lbl+' (-'+bet+' 🪙)','neg'); }
    S.lastShare='PARIMATCH Roulette\\nВыпало '+lbl+' · Выплата: '+pay+' 🪙 · Баланс: '+S.balance+' 🪙';
  };
  raf=requestAnimationFrame(go);
}

// 4. BETON MINES 5x5
const mines = { active:false, count:3, bombs:new Set(), opened:new Set(), bet:100, mult:1.0 };
function renderMines(){
  const cash=Math.round(mines.bet*mines.mult);
  document.getElementById('main').innerHTML =
    '<div class="ghead"><button class="back" onclick="openView(\\'lobby\\')">← Лобби</button><div class="gname">BETON MINES · x'+mines.mult.toFixed(2)+'</div><span style="font-size:11px;font-weight:800;color:var(--pm)">'+mines.count+' мин</span></div>'
    + '<div class="stage"><canvas id="mCv" height="280"></canvas><div class="winbar" id="wbar">'+(mines.active?'Открывайте алмазы или забирайте выигрыш!':'Выберите число мин и нажмите СТАРТ')+'</div></div>'
    + '<div class="ctrl">' + chipsHTML()
    + '<div class="extras" style="grid-template-columns:repeat(3,1fr)"><button class="xbtn '+(mines.count===3?'on':'')+'" onclick="setMC(3)">3 мины</button><button class="xbtn '+(mines.count===5?'on':'')+'" onclick="setMC(5)">5 мин</button><button class="xbtn '+(mines.count===10?'on':'')+'" onclick="setMC(10)">10 мин</button></div>'
    + '<button class="mbtn '+(mines.active?'cash':'')+'" onclick="toggleMines()">'+(mines.active?'ЗАБРАТЬ '+mines.mult.toFixed(2)+'x (+'+cash+' 🪙)':'НАЧАТЬ ИГРУ')+'</button></div>';
  const cv=document.getElementById('mCv');
  cv.onclick=(ev)=>{ if(!mines.active) return; const rect=cv.getBoundingClientRect(); const col=Math.floor(((ev.clientX-rect.left)/rect.width)*5), row=Math.floor(((ev.clientY-rect.top)/rect.height)*5); if(col>=0&&col<5&&row>=0&&row<5) tapMine(row*5+col); };
  drawMines();
}
function drawMines(){
  const cv=document.getElementById('mCv'); if(!cv) return;
  const ctx=cv.getContext('2d'); const w=cv.width=cv.clientWidth*2, h=cv.height=560;
  ctx.fillStyle='#0c101b'; ctx.fillRect(0,0,w,h);
  const pad=14, gap=10, cw=(w-pad*2-gap*4)/5, ch=(h-pad*2-gap*4)/5;
  for(let r=0;r<5;r++){
    for(let c=0;c<5;c++){
      const i=r*5+c, x=pad+c*(cw+gap), y=pad+r*(ch+gap), op=mines.opened.has(i), isB=mines.bombs.has(i);
      ctx.beginPath(); ctx.roundRect(x,y,cw,ch,16);
      if(op && !isB){
        ctx.fillStyle='rgba(0,230,118,0.18)'; ctx.fill(); ctx.strokeStyle='#00e676'; ctx.lineWidth=3; ctx.stroke();
        drawGem(ctx, x+cw/2, y+ch/2, Math.min(cw,ch)*0.32, '#38bdf8', '#0284c7', 6);
      } else if(!mines.active && mines.bombs.size>0 && isB){
        ctx.fillStyle='rgba(255,45,85,0.22)'; ctx.fill(); ctx.strokeStyle='#ff2d55'; ctx.lineWidth=3; ctx.stroke();
        ctx.save(); ctx.translate(x+cw/2,y+ch/2); ctx.fillStyle='#ff2d55'; ctx.beginPath(); ctx.arc(0,0,Math.min(cw,ch)*0.24,0,Math.PI*2); ctx.fill(); ctx.fillStyle='#fff'; ctx.beginPath(); ctx.arc(-6,-6,4,0,Math.PI*2); ctx.fill(); ctx.restore();
      } else {
        const g=ctx.createLinearGradient(x,y,x,y+ch); g.addColorStop(0,'#25314d'); g.addColorStop(1,'#161e31');
        ctx.fillStyle=g; ctx.fill(); ctx.strokeStyle='rgba(255,255,255,0.12)'; ctx.lineWidth=2; ctx.stroke();
      }
    }
  }
}
function setMC(n){ if(mines.active) return; mines.count=n; hap('light'); renderMines(); }
function toggleMines(){
  if(mines.active){
    mines.active=false; const pay=Math.round(mines.bet*mines.mult); S.balance+=pay; save(); hap('success');
    renderMines(); setBar('ЗАБРАЛ +'+pay.toLocaleString('ru-RU')+' 🪙 (x'+mines.mult.toFixed(2)+')!','pos');
    S.lastShare='BETON Mines\\nЗабрал x'+mines.mult.toFixed(2)+' (+'+pay+' 🪙)! Баланс: '+S.balance+' 🪙';
    return;
  }
  if(S.balance<10) S.balance=500;
  if(S.bet>S.balance) S.bet=S.balance;
  S.balance-=S.bet; save(); hap('medium');
  mines.bet=S.bet; mines.active=true; mines.mult=1.0; mines.opened=new Set(); mines.bombs=new Set();
  while(mines.bombs.size<mines.count) mines.bombs.add(Math.floor(Math.random()*25));
  renderMines();
}
function tapMine(i){
  if(!mines.active||mines.opened.has(i)) return;
  if(mines.bombs.has(i)){ mines.active=false; hap('error'); renderMines(); setBar('БОМБА! -'+mines.bet+' 🪙','neg'); return; }
  mines.opened.add(i);
  const safeLeft=25-mines.count-(mines.opened.size-1), totalLeft=25-(mines.opened.size-1);
  mines.mult*=(totalLeft/safeLeft)*0.97; hap('light'); renderMines();
}

function renderLobby(){
  const cards=[
    { id:'zeus', title:'Gates of Olympus', sub:'Pragmatic · Tumble HD', badge:'HOT', bcol:'#ff2d55', rtp:'96.5%' },
    { id:'crash', title:'Aviator Live', sub:'Spribe · до x100', badge:'LIVE', bcol:'#00e676', rtp:'97.0%' },
    { id:'roulette', title:'European Roulette', sub:'3D Wheel · 37 сект.', badge:'LIVE', bcol:'#ff2d55', rtp:'97.3%' },
    { id:'mines', title:'Beton Mines', sub:'Сапёр 5×5 · Алмазы', badge:'TOP', bcol:'#f8ff13', rtp:'98.0%' }
  ];
  document.getElementById('main').innerHTML =
    '<div class="banner"><span class="pm-tag">PARIMATCH × BETON</span><h2>HD Графическое Казино</h2><p>Нарисованные 60fps Canvas-игры: Gates of Olympus, Aviator с самолётом, 3D-Рулетка и Beton Mines.</p><button class="bcta" onclick="openView(\\'zeus\\')">ИГРАТЬ В OLYMPUS</button></div>'
    + '<div class="grid">' + cards.map(c=>'<div class="gcard" onclick="hap(\\'light\\');openView(\\''+c.id+'\\')"><div class="gart"><canvas id="art_'+c.id+'" height="112"></canvas><span class="gbadge" style="background:'+c.bcol+';color:'+(c.bcol==='#f8ff13'?'#000':'#fff')+'">'+c.badge+'</span><span class="grtp">'+c.rtp+'</span></div><div class="ginfo"><div><div class="gtitle">'+c.title+'</div><div class="gsub">'+c.sub+'</div></div><button class="gplay">▶</button></div></div>').join('') + '</div>';
  drawLobbyCovers();
}
function drawLobbyCovers(){
  const c1=document.getElementById('art_zeus');
  if(c1){ const ctx=c1.getContext('2d'); const w=c1.width=320, h=c1.height=224; const g=ctx.createLinearGradient(0,0,w,h); g.addColorStop(0,'#3b126b'); g.addColorStop(1,'#613a00'); ctx.fillStyle=g; ctx.fillRect(0,0,w,h); drawCrown(ctx,w*0.5,h*0.52,54); drawGem(ctx,w*0.2,h*0.6,26,'#38bdf8','#1d4ed8',6); drawGem(ctx,w*0.8,h*0.6,26,'#f43f5e','#9f1239',4); }
  const c2=document.getElementById('art_crash');
  if(c2){ const ctx=c2.getContext('2d'); const w=c2.width=320, h=c2.height=224; const g=ctx.createLinearGradient(0,0,w,h); g.addColorStop(0,'#091826'); g.addColorStop(1,'#3a0817'); ctx.fillStyle=g; ctx.fillRect(0,0,w,h); ctx.strokeStyle='#ff2d55'; ctx.lineWidth=6; ctx.beginPath(); ctx.moveTo(20,h-20); ctx.quadraticCurveTo(w*0.55,h-30,w*0.78,60); ctx.stroke(); drawPlane(ctx,w*0.76,56,-0.35,0); }
  const c3=document.getElementById('art_roulette');
  if(c3){ const ctx=c3.getContext('2d'); const w=c3.width=320, h=c3.height=224; ctx.fillStyle='#0a2c1d'; ctx.fillRect(0,0,w,h); const cx=w/2, cy=h/2, R=76; for(let i=0;i<18;i++){ ctx.beginPath(); ctx.moveTo(cx,cy); ctx.arc(cx,cy,R,i*(Math.PI/9),(i+1)*(Math.PI/9)); ctx.closePath(); ctx.fillStyle=i===0?'#059669':(i%2===0?'#dc2626':'#141820'); ctx.fill(); } ctx.beginPath(); ctx.arc(cx,cy,R,0,Math.PI*2); ctx.strokeStyle='#ffb800'; ctx.lineWidth=6; ctx.stroke(); ctx.beginPath(); ctx.arc(cx,cy,26,0,Math.PI*2); ctx.fillStyle='#ffb800'; ctx.fill(); }
  const c4=document.getElementById('art_mines');
  if(c4){ const ctx=c4.getContext('2d'); const w=c4.width=320, h=c4.height=224; const g=ctx.createLinearGradient(0,0,w,h); g.addColorStop(0,'#0f2447'); g.addColorStop(1,'#291242'); ctx.fillStyle=g; ctx.fillRect(0,0,w,h); drawGem(ctx,w*0.36,h*0.52,42,'#38bdf8','#0284c7',6); ctx.fillStyle='#ff2d55'; ctx.beginPath(); ctx.arc(w*0.68,h*0.56,30,0,Math.PI*2); ctx.fill(); ctx.fillStyle='#fff'; ctx.beginPath(); ctx.arc(w*0.65,h*0.51,7,0,Math.PI*2); ctx.fill(); }
}

function openView(v){
  stopAll(); S.view=v;
  document.querySelectorAll('.nitem').forEach(e=>e.classList.remove('active'));
  document.getElementById('nv-'+v)?.classList.add('active');
  if(v==='lobby') renderLobby();
  else if(v==='zeus') renderOlympus();
  else if(v==='crash') renderAviator();
  else if(v==='roulette') renderRoulette();
  else if(v==='mines') renderMines();
}
save();
openView(S.view);
</script>
</body>
</html>`;
