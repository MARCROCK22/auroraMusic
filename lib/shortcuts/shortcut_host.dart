import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import 'shortcut_service.dart';

final shortcutServiceProvider = Provider<ShortcutService>(
  (ref) => ShortcutService(ref.read(controllerProvider).preferences),
);

/// ¿El foco primario está dentro de un campo de texto?
bool primaryFocusIsTextInput() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Sustituye al CallbackShortcuts fijo: lee los atajos del [ShortcutService].
class ShortcutHost extends StatelessWidget {
  const ShortcutHost({
    super.key,
    required this.service,
    required this.onAction,
    required this.child,
    this.enabled,
    this.extraBindings = const {},
    this.isTextInputFocused = primaryFocusIsTextInput,
  });
  final ShortcutService service;
  final void Function(ShortcutId id) onAction;
  final bool Function(ShortcutId id)? enabled;
  final Map<ShortcutActivator, VoidCallback> extraBindings;
  final bool Function() isTextInputFocused;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Shortcuts(
      shortcuts: service.bindings,
      child: Actions(
        actions: {
          ShortcutIntent: _Act(service, onAction, enabled, isTextInputFocused),
        },
        child: CallbackShortcuts(bindings: extraBindings, child: child),
      ),
    ),
  );
}

class _Act extends Action<ShortcutIntent> {
  _Act(this.service, this.onAction, this.enabled, this.textFocused);
  final ShortcutService service;
  final void Function(ShortcutId) onAction;
  final bool Function(ShortcutId)? enabled;
  final bool Function() textFocused;

  @override
  bool isEnabled(ShortcutIntent intent) {
    if (enabled?.call(intent.id) == false) return false;
    return !(ShortcutService.yieldsToTextField(
          service.activatorOf(intent.id),
        ) &&
        textFocused());
  }

  @override
  Object? invoke(ShortcutIntent intent) {
    onAction(intent.id);
    return null;
  }
}
