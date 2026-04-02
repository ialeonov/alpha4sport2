typedef UnsavedChangesGetter = bool Function();

class PageCloseGuard {
  PageCloseGuard(UnsavedChangesGetter hasUnsavedChanges);

  void attach() {
    // No-op outside the web platform.
  }

  void dispose() {
    // No-op outside the web platform.
  }
}
