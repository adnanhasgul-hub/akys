"""Real Firebase Auth + Firestore emulator + Flutter UI. Never production."""
import functools,http.server,threading,json,re,os,urllib.request,argparse
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
assert os.environ.get('FIRESTORE_EMULATOR_HOST') in ['127.0.0.1:8080','localhost:8080']
parser=argparse.ArgumentParser();parser.add_argument('--result',default='tool/solver_v2/results/stage_1_9e_browser.json');args=parser.parse_args()
results={'checks':[],'errors':[],'externalFirebaseRequests':[]}
def claim(email, value):
 lookup=urllib.request.Request('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:lookup?key=demo-api-key',data=json.dumps({'email':[email]}).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer owner'})
 users=json.load(urllib.request.urlopen(lookup))['users']
 uid=next(u['localId'] for u in users if u['email']==email)
 body=json.dumps({'localId':uid,'customAttributes':json.dumps({'admin':value})}).encode()
 request=urllib.request.Request('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo-api-key',data=body,headers={'Content-Type':'application/json','Authorization':'Bearer owner'})
 urllib.request.urlopen(request).read()

with http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory='build/v2-firebase')) as server:
 threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  results['chromium']=browser.version
  page=browser.new_page(viewport={'width':414,'height':1000})
  def reject_external(route):
   results['externalFirebaseRequests'].append(route.request.url.split('?')[0]);route.abort()
  page.route(re.compile(r'https://.*(googleapis|firebaseio)\.com/'),reject_external)
  page.on('pageerror',lambda e:(results['errors'].append(str(e)),print('PAGE ERROR',e.stack)))
  page.on('console',lambda m: print('BROWSER',m.type,m.text) if m.type in ['error','warning'] else None)
  page.on('requestfailed',lambda r: print('REQUEST FAILED',r.url,r.failure))
  page.on('response',lambda r: print('AUTH ERROR',r.status,r.text()) if ':9099/' in r.url and r.status >= 400 else None)
  def semantics():
   page.locator('flt-semantics-placeholder').wait_for(state='attached')
   page.evaluate("document.querySelector('flt-semantics-placeholder').click()")
  def button(name):return page.get_by_role('button',name=name,exact=isinstance(name,str))
  def login(email):
   for name,value in [('E-posta',email),('Şifre','EmulatorOnly123!')]:
    field=page.get_by_role('textbox',name=name,exact=True)
    field.click();page.wait_for_timeout(250)
    field.fill('');page.keyboard.insert_text(value)
    page.keyboard.press('Tab');page.wait_for_timeout(250)
    expect(field).to_have_value(value)
   button('Giriş Yap').click()

  try:
   page.goto(f'http://127.0.0.1:{server.server_port}/');semantics()
   login('v2-admin@example.test')
   page.get_by_role('tab',name='Hekimler').click(timeout=30000)
   button('Hekim ekle').click()
   name=page.get_by_role('textbox',name='Ad soyad',exact=True)
   name.click();page.wait_for_timeout(250);name.fill('Emulator Hekimi');page.keyboard.press('Tab');page.wait_for_timeout(250)
   expect(name).to_have_value('Emulator Hekimi')
   button('Uygula').click();button('Yeni taslak').click()
   page.get_by_role('tab',name='Çizelge').click()
   button(re.compile('^Kıdemli • REQUIRED')).first.click();page.get_by_text('Ata',exact=True).click();page.get_by_text('Emulator Hekimi',exact=True).click()
   button(re.compile('^Kıdemli • REQUIRED')).first.click();page.get_by_text('Kilitle',exact=True).click()
   page.wait_for_timeout(700)
   page.reload();semantics()
   button(re.compile('Kaydedilmemiş değişiklikler')).click(timeout=30000)
   button('Kurtar').click(timeout=15000)
   expect(button(re.compile('^Kıdemli • REQUIRED.*🔒',re.S)).first).to_be_visible(timeout=20000)
   results['checks'].append('encrypted unsaved local draft survives reload; same-owner recovery preserves locks')
   button('Kaydet').click()
   expect(page.get_by_role('group',name=re.compile('^Kaydedildi • v1'))).to_be_visible(timeout=30000)
   results['checks'].append('existing Auth UI admin claim, incomplete draft + doctor + lock saved atomically')
   page.reload();semantics()
   button(re.compile('Kaydedilmemiş değişiklikler')).click(timeout=30000);button('Taslakları aç').click()
   button(re.compile('v1 • draft')).click();button('Değişiklikleri bırak').click()
   expect(button(re.compile('^Kıdemli • REQUIRED.*🔒',re.S)).first).to_be_visible(timeout=20000)
   results['checks'].append('page reload, server list/open, doctor and lock restored')
   # New revision keeps source version immutable.
   if not button('Revizyon oluştur').is_visible():button(re.compile('Kaydedildi • v1')).click()
   page.context.set_offline(True)
   button('Kaydet').click()
   expect(page.get_by_role('group',name=re.compile('Kayıt tamamlanamadı veya sonucu belirsiz'))).to_be_visible(timeout=45000)
   page.context.set_offline(False)
   button('Aynı kaydı yeniden dene').click()
   expect(page.get_by_role('group',name=re.compile('^Kaydedildi • v2'))).to_be_visible(timeout=30000)
   results['checks'].append('real offline transaction failure preserves draft; online same-operation retry succeeds')
   button('Revizyon oluştur').click();button('Kaydet').click()
   expect(page.get_by_role('group',name=re.compile('^Kaydedildi • v1'))).to_be_visible(timeout=30000)
   button('Kaydet').click();expect(page.get_by_role('group',name=re.compile('^Kaydedildi • v2'))).to_be_visible(timeout=30000)
   button('Sürüm geçmişi').click();expect(button(re.compile('v1 • draft'))).to_be_visible();expect(button(re.compile('v2 • draft'))).to_be_visible()
   page.keyboard.press('Escape')
   expect(button('Kalıcı onay kapalı')).to_be_disabled()
   button('Onay neden kapalı?').click()
   expect(page.get_by_role('group',name=re.compile('Sunucu tarafında klinik doğrulama yok'))).to_be_visible(timeout=20000)
   results['checks'].append('revision and append-only version history; approval remains disabled and rejection logged')
   button('Çıkış yap').click()
   expect(button('Giriş Yap')).to_be_visible(timeout=10000)
   login('v2-user@example.test')
   expect(page.get_by_text('Erişim yetkiniz yok',exact=True)).to_be_visible(timeout=20000)
   results['checks'].append('same-document logout and different non-admin login: no reload; private UI blocked')
   claim('v2-user@example.test', True)
   button('Yetkiyi yeniden doğrula').click()
   expect(page.get_by_role('tab',name='Çizelge')).to_be_visible(timeout=15000)
   expect(page.get_by_text('Emulator Hekimi',exact=True)).to_have_count(0)
   results['checks'].append('admin claim grant refresh opens fresh workspace without prior-user draft')
   claim('v2-user@example.test', False)
   button('Yetkiyi yeniden doğrula').click()
   expect(page.get_by_text('Erişim yetkiniz yok',exact=True)).to_be_visible(timeout=15000)
   results['checks'].append('admin claim revoke refresh closes private workspace')
   assert not results['externalFirebaseRequests'],results

   assert not results['errors'],results
   results['pass']=True
  except Exception as e:
   results['pass']=False;results['failure']=str(e);results['aria']=page.locator('body').aria_snapshot()
   page.screenshot(path='build/v2-firebase/failure.png')
   raise
  finally:
   Path(args.result).write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n');browser.close()
 server.shutdown()
print(json.dumps(results,ensure_ascii=False,indent=2))
