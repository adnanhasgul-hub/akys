const{chromium}=require('playwright'); const fs=require('fs');
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--disable-dev-shm-usage']}); const width=Number(process.env.RENDER_WIDTH || 414); const p=await b.newPage({viewport:{width,height:736}});
const errors=[];p.on('pageerror',e=>errors.push(e.message));
await p.route(/(firestore|identitytoolkit|securetoken)\.googleapis\.com/, route=>{errors.push('Fixture attempted a Firebase API request');return route.abort();});fs.mkdirSync(`/tmp/reference-shots-${width}`,{recursive:true});
await p.goto('http://127.0.0.1:8767/',{waitUntil:'networkidle'});await p.waitForTimeout(6000);await p.locator('flt-semantics-placeholder').evaluate(e=>e.click());await p.waitForTimeout(700);
await p.getByRole('button',{name:/Çalışma Çizelgesi modülünü aç/}).click();await p.waitForTimeout(1000);
await p.getByText('Çalışılan ay',{exact:true}).click();await p.waitForTimeout(300);await p.keyboard.press('ArrowDown');await p.keyboard.press('Enter');await p.waitForTimeout(1000);
await p.screenshot({path:`/tmp/reference-shots-${width}/01-overview.png`});
for(const [label,file] of [['Nöbet','02-list'],['Personel','04-personnel'],['Görevler','05-tasks'],['Ayarlar','06-settings']]){
if(label==='Ayarlar' && width<720){await p.getByText('Diğer',{exact:true}).click();await p.waitForTimeout(300);}
await p.getByText(label,{exact:true}).last().click();await p.waitForTimeout(700);await p.mouse.move(1,1);await p.waitForTimeout(600);await p.screenshot({path:`/tmp/reference-shots-${width}/${file}.png`});
if(label==='Nöbet'){await p.getByText('Takvim',{exact:true}).click();await p.waitForTimeout(500);await p.mouse.move(1,1);await p.waitForTimeout(600);await p.screenshot({path:`/tmp/reference-shots-${width}/03-calendar.png`});}
}
console.log(JSON.stringify({width,errors,captured:6}));await b.close();if(errors.length)process.exitCode=1;})();
