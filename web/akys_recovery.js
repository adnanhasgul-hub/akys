/* Local recovery only. AES-GCM, fresh IV per write, non-extractable IndexedDB
 * CryptoKey. Protects persisted bytes, not an XSS-compromised same origin. */
(() => {
  'use strict';
  const encoder = new TextEncoder(), decoder = new TextDecoder();
  const db = () => new Promise((resolve, reject) => {
    const request = indexedDB.open('akys-encrypted-recovery-v1', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('entries');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const transaction = async (mode, body) => {
    const database = await db();
    try { return await new Promise((resolve, reject) => {
      const tx = database.transaction('entries', mode);
      let result;
      body(tx.objectStore('entries'), value => { result = value; });
      tx.oncomplete = () => resolve(result);
      tx.onabort = tx.onerror = () => reject(tx.error || Error('Recovery transaction failed'));
    }); } finally { database.close(); }
  };
  const id = async owner => {
    if (!owner || owner.length > 256) throw Error('Invalid recovery owner');
    const digest = await crypto.subtle.digest('SHA-256', encoder.encode(owner));
    return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2,'0')).join('');
  };
  // Serialize writes/removals within one page; atomic IndexedDB writes across tabs.
  let queue = Promise.resolve();
  const serial = work => { const next = queue.then(work); queue = next.catch(() => {}); return next; };
  window.akysRecovery = Object.freeze({
    read: owner => serial(async () => {
      const key = await id(owner);
      const entry = await transaction('readonly', (s, done) => { const r=s.get(key); r.onsuccess=()=>done(r.result); });
      if (!entry) return null;
      const bytes = await crypto.subtle.decrypt({name:'AES-GCM',iv:entry.iv,additionalData:encoder.encode(key)},entry.key,entry.ciphertext);
      return decoder.decode(bytes);
    }),
    write: (owner, plaintext) => serial(async () => {
      if (encoder.encode(plaintext).length > 2500000) throw Error('Recovery size limit');
      const idValue = await id(owner);
      // An independently generated key for each atomic entry avoids key/record races.
      const key = await crypto.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']);
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const ciphertext = await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode(idValue)},key,encoder.encode(plaintext));
      await transaction('readwrite', s => s.put({key,iv,ciphertext},idValue));
    }),
    remove: owner => serial(async () => { const key=await id(owner); await transaction('readwrite', s=>s.delete(key)); })
  });
})();
