import 'package:aurora_music/core/desktop_shell.dart';
import 'package:aurora_music/core/window_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la X minimiza a la bandeja por defecto y respeta el ajuste', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(CloseBehavior.read(prefs), isTrue);
    await prefs.setBool(CloseBehavior.key, false);
    expect(CloseBehavior.read(prefs), isFalse);
  });

  test('sin ventana nativa las llamadas fallan sin lanzar', () async {
    expect(await WindowControls.invoke('setCloseToTray', true), isFalse);
    expect(await WindowControls.query('getAutostart'), isFalse);
    expect(await WindowControls.requestHardExit(), isFalse);
  });
}
