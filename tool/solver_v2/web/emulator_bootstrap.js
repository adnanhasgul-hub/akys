// Local release acceptance only. Never included by the production build.
// Connect before Firebase Auth restores persisted users; Dart initializeApp awaits
// plugin restoration before useAuthEmulator can run. Same pinned SDK as FlutterFire.
if (!['127.0.0.1', 'localhost'].includes(location.hostname)) {
  throw new Error('Emulator bootstrap requires loopback');
}
const sdk = 'https://www.gstatic.com/firebasejs/13.1.0/';
const core = await import(sdk + 'firebase-app.js');
const auth = await import(sdk + 'firebase-auth.js');
const app = core.initializeApp({apiKey:'demo-api-key',appId:'1:123456:web:local',messagingSenderId:'123456',projectId:'demo-akys',authDomain:null,databaseURL:null,storageBucket:null,measurementId:null}, 'akys-v2-emulator');
const instance = auth.initializeAuth(app, {
  errorMap: auth.debugErrorMap,
  persistence: [auth.indexedDBLocalPersistence, auth.browserLocalPersistence, auth.browserSessionPersistence],
  popupRedirectResolver: auth.browserPopupRedirectResolver,
});
auth.connectAuthEmulator(instance, 'http://127.0.0.1:9099');
const flutter = document.createElement('script');
flutter.src = 'flutter_bootstrap.js';
document.body.appendChild(flutter);
