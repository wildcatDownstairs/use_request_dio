typedef VisibilityChangeCallback = void Function(bool visible);
typedef VisibilityChangeDisposer = void Function();

/// Non-web implementation: no-op.
VisibilityChangeDisposer registerVisibilityChange(VisibilityChangeCallback callback) {
  return () {};
}

