import 'dart:js_interop';

@JS('tasuShowNotification')
external void _tasuShowNotification(JSString title, JSString body);

@JS('tasuIsStandalone')
external JSBoolean _tasuIsStandalone();

/// Қосымша ашық тұрғанда келген push-ты жүйелік хабарландыру етіп көрсету.
void showWebNotification(String title, String body) {
  try {
    _tasuShowNotification(title.toJS, body.toJS);
  } catch (_) {}
}

/// Web қосымша «Басты экранға қосылған» (PWA) күйде ашылды ма?
bool webIsStandalone() {
  try {
    return _tasuIsStandalone().toDart;
  } catch (_) {
    return false;
  }
}
