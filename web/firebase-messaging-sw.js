// Tasu · Web push (FCM) service worker.
//
// Web нұсқасы (gazelgo.pages.dev, PWA) жабық/фонда тұрғанда push-ты осы
// файл қабылдап, жүйелік хабарландыру ретінде көрсетеді. Firebase JS SDK
// бұл файлды `/firebase-messaging-sw.js` жолынан ӨЗІ тіркейді
// (scope: /firebase-cloud-messaging-push-scope), сол себепті аты мен орны
// өзгермеуі керек.
//
// Нұсқа firebase_core_web плагинінің JS SDK нұсқасымен сәйкес
// (supportedFirebaseJsSdkVersion).

// notificationclick-ті Firebase скриптерінен БҰРЫН тіркейміз: қосымша өзі
// (foreground кезінде) шығарған хабарландыруды басқанда қосымшаны ашады.
// FCM-нің өз хабарландыруларын (FCM_MSG) Firebase SDK өзі өңдейді.
self.addEventListener('notificationclick', function (event) {
  var data = event.notification && event.notification.data;
  if (data && data.FCM_MSG) return;
  event.notification.close();
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (list) {
        for (var i = 0; i < list.length; i++) {
          if ('focus' in list[i]) return list[i].focus();
        }
        if (self.clients.openWindow) return self.clients.openWindow('/');
      })
  );
});

importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC2EKnEwJLG7-FjGPbPsxFNe5YBcmkmjNs',
  appId: '1:602555256548:web:38f380e638a33d0f4626f1',
  messagingSenderId: '602555256548',
  projectId: 'gazelgo',
  authDomain: 'gazelgo.firebaseapp.com',
  storageBucket: 'gazelgo.firebasestorage.app',
});

// Сервер `notification` payload жібереді — SDK оны фонда өзі көрсетеді.
firebase.messaging();
