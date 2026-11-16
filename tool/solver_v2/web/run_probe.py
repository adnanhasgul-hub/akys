"""Local-only real Chromium feasibility probe; no production access."""
import functools
import http.server
import json
import threading
from playwright.sync_api import sync_playwright

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory="build/v2-probe")
with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path="/usr/bin/chromium", args=["--no-sandbox"], headless=True)
        page = browser.new_page()
        page.goto(f"http://127.0.0.1:{server.server_port}/")
        result = page.evaluate("""async () => {
          const w = new Worker('probe.js'); const events=[]; let ticks=0;
          const start=performance.now(); const tick=setInterval(()=>ticks++,5);
          return await new Promise((resolve,reject)=>{
            const fail=setTimeout(()=>reject(Error('probe timeout')),5000);
            w.onerror=e=>reject(Error(e.message));
            w.onmessage=e=>{
              const m=JSON.parse(e.data); events.push({...m,hostMs:performance.now()-start});
              if(m.type==='ready') {
                w.postMessage(JSON.stringify({command:'start'}));
                setTimeout(()=>w.postMessage(JSON.stringify({command:'extendDeadline'})),150);
                setTimeout(()=>w.postMessage(JSON.stringify({command:'cancel'})),700);
              }
              if(m.type==='cancelled') {clearTimeout(fail);clearInterval(tick);w.terminate();resolve({events,ticks});}
            };
          });
        }""")
        browser.close()
    server.shutdown()
assert [e['type'] for e in result['events']] == ['ready', 'started', 'extended', 'cancelled'], result
assert result['events'][-1]['elapsed'] > 500000, result
assert result['events'][-1]['nodes'] > result['events'][2]['nodes'] > 0, result
assert result['ticks'] > 50, result
print(json.dumps(result))
