/// Web-ке ғана тән push көмекшілері (web/index.html ішіндегі JS функциялар).
/// Мобиль build-та бос stub қолданылады — `dart:js_interop` тек web-те бар.
library;

export 'web_notify_stub.dart'
    if (dart.library.js_interop) 'web_notify_web.dart';
