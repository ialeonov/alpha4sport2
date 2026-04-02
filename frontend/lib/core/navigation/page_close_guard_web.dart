// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

typedef UnsavedChangesGetter = bool Function();

class PageCloseGuard {
  PageCloseGuard(this._hasUnsavedChanges);

  final UnsavedChangesGetter _hasUnsavedChanges;
  html.EventListener? _listener;

  void attach() {
    _listener ??= (event) {
      if (!_hasUnsavedChanges()) {
        return;
      }

      final beforeUnloadEvent = event as html.BeforeUnloadEvent;
      beforeUnloadEvent.preventDefault();
      beforeUnloadEvent.returnValue = '';
    };
    html.window.addEventListener('beforeunload', _listener);
  }

  void dispose() {
    final listener = _listener;
    if (listener == null) {
      return;
    }
    html.window.removeEventListener('beforeunload', listener);
  }
}
