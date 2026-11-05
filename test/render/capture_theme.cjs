const {chromium}=require('playwright');
const fs=require('fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--disable-dev-shm-usage']});
 fs.mkdirSync('/tmp/akys-theme-shots',{recursive:true});
 for(const width of [414,1440]) {
  const page=await browser.newPage({viewport:{width,height:1000}});
  page.on('pageerror', e=>console.log('PAGE_ERROR', e.message));
  await page.goto('http://127.0.0.1:8765/?login=1',{waitUntil:'networkidle'});
  await page.waitForTimeout(2000);
  await page.screenshot({path:`/tmp/akys-theme-shots/${width}-login.png`});
  await page.goto('http://127.0.0.1:8765/',{waitUntil:'networkidle'});
  await page.waitForTimeout(2000);
  const sem=page.locator('flt-semantics-placeholder');if(await sem.count()) await sem.evaluate(e=>e.click());
  await page.waitForTimeout(500);
  await page.screenshot({path:`/tmp/akys-theme-shots/${width}-home.png`});
  console.log('HOME',width,(await page.locator('body').innerText()).slice(0,600));
  await page.getByRole('button',{name:/Çalışma Çizelgesi modülünü aç/}).click();
  await page.waitForTimeout(1500);
  console.log('SCHEDULE',width,(await page.locator('body').innerText()).slice(0,900));
  await page.screenshot({path:`/tmp/akys-theme-shots/${width}-overview.png`});
  await page.getByText('Çalışılan ay',{exact:true}).click();
  await page.waitForTimeout(300);
  console.log('MONTHS',await page.locator('body').innerText());
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  for (const label of ['Nöbet','Görevler','Personel','Birleşik Görünüm','Geçmiş Aylar','Ayarlar']) {
   if(width<600 && ['Birleşik Görünüm','Geçmiş Aylar','Ayarlar'].includes(label)) {
    await page.getByText('Diğer',{exact:true}).last().click();
    await page.waitForTimeout(200);
   }
   await page.getByText(label,{exact:true}).last().click();
   await page.waitForTimeout(500);
   await page.screenshot({path:`/tmp/akys-theme-shots/${width}-${label}.png`});
   if(label==='Personel') {
    await page.getByText('Personel Ekle',{exact:true}).click();
    await page.waitForTimeout(300);
    await page.screenshot({path:`/tmp/akys-theme-shots/${width}-dialog.png`});
    await page.getByText('Vazgeç',{exact:true}).click();
   }
  }
  await page.close();
 }
 await browser.close();
})();
