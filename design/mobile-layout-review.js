// Layout prototype only: no live requests, notification rules or Flutter changes.
const app = document.querySelector('.app');
const layoutState = {
  seismic: {camera: {x: -130, y: -50, z: 1}, collapsed: true, side: 0},
  weather: {camera: {x: 0, y: 0, z: 1}, collapsed: true, side: 0},
};
let currentPage = 'seismic';
const nav = document.createElement('nav');
nav.className = 'mobile-nav';
nav.setAttribute('aria-label', '页面切换');
nav.innerHTML = [['seismic','地震·火山'],['weather','气象'],['settings','设置']].map(([id,label]) => `<button data-page="${id}" onclick="switchMobilePage('${id}')">${label}</button>`).join('');
app.append(nav);
const status = document.createElement('div');
status.className = 'preview-status';
status.innerHTML = '<span>09:41 JST · 非实时</span><button onclick="showScenarios()" title="切换示例场景">演示数据 · 切换场景</button>';
app.append(status);
const actions = document.createElement('div');
actions.className = 'mobile-map-actions';
actions.innerHTML = `<button title="回到中心" aria-label="回到中心" onclick="resetMobileMap()"><i class="mi">my_location</i></button>
<button title="查看历史" aria-label="查看历史" onclick="openDialog('历史记录','原有历史记录入口。当前为 HTML 布局稿，不读取应用记录。')"><i class="mi">history</i></button>
<button title="手动查看 CENC 烈度速报" aria-label="手动查看 CENC 烈度速报" onclick="openDialog('手动 CENC 烈度速报','保留原有手动查看入口。本稿不发起真实请求或修改应用状态。')"><i class="mi">waves</i></button>`;
app.append(actions);
// Remove the desktop reference's hidden zoom controls from this mobile draft.
document.querySelector('.maptools').remove();
const settings = document.createElement('iframe');
settings.className = 'settings-page';
settings.hidden = true;
settings.title = '应用设置';
settings.src = 'settings-page.html?embed=mobile';
app.append(settings);
window.addEventListener('message', event => {
  if (event.source === settings.contentWindow && event.data?.type === 'settings-preview-back') {
    switchMobilePage('seismic');
  }
});

sideDefs.rain = {name:'气象预警', html:()=>'<h2>暴雨黄色预警</h2><div class="sidename">杭州市气象台 · 示例</div>'+kv([['发布时间','09:35'],['预计解除','15:00'],['预警级别','黄色']])+'<h3>预警正文</h3><p>部分地区将出现短时强降水，局地伴有雷电。仅用于验证长正文在右侧悬浮面板中的显示。</p>'};
sideDefs.typhoon = {name:'台风情报', html:()=>'<h2>示例台风</h2>'+kv([['强度','强热带风暴'],['最大风速','28 m/s'],['中心气压','985 hPa'],['移动方向','西北']])+'<p>并非实际台风，不用于气象判断。</p>'};
const originalSetScenario = setScenario;
setScenario = function () {
  if (currentPage !== 'seismic') return;
  originalSetScenario();
  if ($('scenario').value === 'idle') {
    $('alerts').hidden = false;
    $('alerts').innerHTML = '<div class="idle-alert">当前暂无预警</div>';
  }
};

function setCollapsed(collapsed) {
  $('eqlist').classList.toggle('collapsed', collapsed);
  app.classList.toggle('list-open', !collapsed);
  $('collapseicon').textContent = '';
  const button = document.querySelector('.collapse');
  button.title = collapsed ? '拉开列表' : '收起列表';
  button.setAttribute('aria-label', button.title);
  button.setAttribute('aria-expanded', String(!collapsed));
  document.querySelector('.listbody').inert = collapsed;
  if (layoutState[currentPage]) layoutState[currentPage].collapsed = collapsed;
}
collapseList = () => setCollapsed(!$('eqlist').classList.contains('collapsed'));
const grip = document.querySelector('.collapse');
let gripY = null, gripDragged = false;
grip.addEventListener('pointerdown', e => {gripY=e.clientY;gripDragged=false;grip.setPointerCapture(e.pointerId)});
grip.addEventListener('pointerup', e => {
  if (gripY === null) return;
  const dy = e.clientY-gripY;
  if (Math.abs(dy)>16) {gripDragged=true;setCollapsed(dy>0)}
  gripY=null;
});
grip.addEventListener('pointercancel',()=>{gripY=null});
grip.addEventListener('click', e => {if(gripDragged){e.stopImmediatePropagation();gripDragged=false}},true);
new ResizeObserver(entries => {app.style.setProperty('--group-height', `${Math.ceil(entries[0].contentRect.height)}px`)}).observe(document.querySelector('.left'));

function renderWeather() {
  $('alerts').hidden=false;
  $('alerts').innerHTML=card('#f7e757','气象预警 · 杭州市气象台','黄色<small>暴雨</small>','杭州市','暴雨黄色预警','09-06 09:35 · 示例','气象板块布局尚待进一步讨论');
  document.querySelector('.filterbar').hidden=true;
  $('entries').innerHTML=[['暴雨黄色预警','杭州市','09:35','rain'],['示例台风','西北方向移动','09:30','typhoon']].map(([title,name,time,key])=>`<button class="eqrow" onclick="selectSide('${key}')"><div class="eqcopy"><strong>${title}</strong><p>${name} · ${time} · 示例</p></div><i class="mi">chevron_right</i></button>`).join('');
  $('listcount').textContent='2 条气象示例';
  sideKeys=['rain','typhoon'];sideIndex=layoutState.weather.side%2;renderSide();
  const ctx=$('overlay').getContext('2d');ctx.clearRect(0,0,1792,1280);
  ctx.beginPath();[[830,480],[940,460],[988,555],[911,610],[814,563]].forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.fillStyle='#ffce5740';ctx.strokeStyle='#ffce57';ctx.lineWidth=2;ctx.fill();ctx.stroke();
  document.querySelector('.cross').hidden=true;document.querySelector('.maplabel').hidden=true;document.querySelector('.volcano').hidden=true;
}
function switchMobilePage(page) {
  if(layoutState[currentPage]){layoutState[currentPage].camera={...camera};layoutState[currentPage].side=sideIndex}
  currentPage=page;app.dataset.page=page;closeDialog();$('sourcepanel').hidden=true;
  nav.querySelectorAll('button').forEach(b=>{const selected=b.dataset.page===page;b.classList.toggle('active',selected);b.setAttribute('aria-current',selected?'page':'false')});
  settings.hidden=page!=='settings';
  if(page==='settings'){sideKeys=[];return}
  camera={...layoutState[page].camera};updateMap();
  if(page==='seismic'){document.querySelector('.filterbar').hidden=false;renderList();setScenario();if(sideKeys.length){sideIndex=Math.min(layoutState.seismic.side,sideKeys.length-1);renderSide()}}
  else renderWeather();
  setCollapsed(layoutState[page].collapsed);
}
function resetMobileMap(){camera=currentPage==='seismic'?{x:-130,y:-50,z:1}:{x:0,y:0,z:1};updateMap()}
function showScenarios(){
  if(currentPage!=='seismic'){openDialog('示例说明','当前为气象或设置布局预览。地震·火山页可以切换检出、S-Net、火山、CMT 等展示场景。');return}
  $('dialogtitle').textContent='地震·火山示例场景';
  $('dialogcontent').innerHTML='<select id="mobile-scenario" aria-label="示例场景"><option value="idle">无活动事件</option><option value="eew">EEW 与检出</option><option value="all">多内容并存</option><option value="volcano">火山情报</option><option value="cmt">CMT 情报</option></select><p>仅切换示例数据，不改变真实应用。</p>';
  $('dialog').hidden=false;$('mobile-scenario').value=$('scenario').value;
  $('mobile-scenario').onchange=e=>{$('scenario').value=e.target.value;layoutState.seismic.side=0;setScenario();closeDialog()};
}
$('scenario').value='eew';
switchMobilePage('seismic');
