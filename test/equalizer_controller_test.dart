import 'package:aurora_music/audio/eq_model.dart';
import 'package:aurora_music/audio/equalizer_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<(EqualizerController, FakeAudio, SharedPreferences)> make([
  Map<String, Object> initial = const {},
  SharedPreferences? reuse,
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = reuse ?? await SharedPreferences.getInstance();
  final audio = FakeAudio();
  return (
    EqualizerController(audio: audio, preferences: prefs)..load(),
    audio,
    prefs,
  );
}

void main() {
  test(
    'starts flat and off; applying sends the effective state to the engine',
    () async {
      final (eq, audio, _) = await make();
      expect(eq.enabled, isFalse);
      expect(eq.bands, eqFlatBands());
      expect(eq.presetName, 'Plano');
      eq.apply();
      expect(audio.eqCalls.last.$1, isFalse);
      eq.setEnabled(true);
      expect(audio.eqCalls.last.$1, isTrue);
      eq.setBypass(true);
      expect(eq.active, isFalse);
      expect(audio.eqCalls.last.$1, isFalse);
      eq.setBypass(false);
      expect(audio.eqCalls.last.$1, isTrue);
      eq.dispose();
    },
  );

  test(
    'gains move in 0.1 dB steps within ±12 dB and reset on demand',
    () async {
      final (eq, audio, _) = await make();
      eq.setGain(2, 3.14159);
      expect(eq.bands[2].gainDb, 3.1);
      eq.setGain(2, 40);
      expect(eq.bands[2].gainDb, 12);
      eq.setGain(2, -40);
      expect(eq.bands[2].gainDb, -12);
      eq.setGain(99, 1); // fuera de rango: ignorado
      eq.setBand(1, eq.bands[1].copyWith(frequency: 250, q: 3));
      expect(audio.eqCalls.last.$2[1].frequency, 250);
      eq.resetBand(2);
      eq.resetBand(1);
      expect(eq.bands, eqFlatBands());
      eq.dispose();
    },
  );

  test(
    'the adjustment survives a restart (debounced write is flushed)',
    () async {
      final (eq, _, prefs) = await make();
      eq.setEnabled(true);
      eq.setBand(4, EqBand(1200, 5.5, 2));
      eq.setAutoPreamp(false);
      eq.dispose(); // vuelca el guardado pendiente
      final (again, _, _) = await make({
        for (final key in prefs.getKeys()) key: prefs.get(key)!,
      });
      expect(again.enabled, isTrue);
      expect(again.autoPreamp, isFalse);
      expect(again.bands[4], EqBand(1200, 5.5, 2));
      again.dispose();
    },
  );

  test('migrates the old eight-gain preference', () async {
    final (eq, _, _) = await make({
      'eqGains': ['6.0', '3.0', '0.0', '-1.0', '-2.0', '-2.0', '-2.0', '0.0'],
      'eqEnabled': true,
    });
    expect(eq.enabled, isTrue);
    expect(eq.bands.map((b) => b.gainDb), [6, 3, 0, -1, -2, -2, -2, 0]);
    expect(eq.bands.map((b) => b.frequency), eqDefaultFrequencies);
    expect(eq.presetName, 'Graves');
    eq.dispose();
  });

  test('a corrupt stored adjustment falls back to flat', () async {
    final (eq, _, _) = await make({
      'eqBands': '{no es json',
      'eqPresets': '[[',
    });
    expect(eq.bands, eqFlatBands());
    expect(eq.userPresets, isEmpty);
    eq.dispose();
  });

  test('user presets: save, replace, reject reserved names, delete', () async {
    final (eq, _, prefs) = await make();
    eq.setGain(0, 4);
    expect(eq.savePreset('  Mi ajuste '), isTrue);
    expect(eq.presetName, 'Mi ajuste');
    eq.setGain(0, 5);
    expect(eq.savePreset('Mi ajuste'), isTrue);
    expect(eq.userPresets.length, 1);
    expect(eq.userPresets.single.bands[0].gainDb, 5);
    expect(eq.savePreset('Plano'), isFalse);
    expect(eq.savePreset('   '), isFalse);
    expect(
      prefs.getString(EqualizerController.presetsKey),
      contains('Mi ajuste'),
    );
    eq.applyPreset(eqBuiltInPresets[0]);
    expect(eq.bands, eqFlatBands());
    eq.applyPreset(eq.userPresets.single);
    expect(eq.bands[0].gainDb, 5);
    eq.deletePreset('Mi ajuste');
    expect(eq.userPresets, isEmpty);
    eq.dispose();
  });

  test('export then import into another controller', () async {
    final (a, _, _) = await make();
    a.setBand(3, EqBand(700, -4.2, 2.5));
    expect(a.savePreset('Voz'), isTrue);
    final json = a.exportPresets();
    final (b, _, _) = await make();
    expect(b.importPresets(json), 1);
    expect(b.userPresets.single.name, 'Voz');
    expect(b.userPresets.single.bands[3], EqBand(700, -4.2, 2.5));
    // Re-importing the same name replaces it, factory names are skipped.
    expect(b.importPresets(json), 1);
    expect(b.userPresets.length, 1);
    expect(
      () => b.importPresets(eqPresetsToJson([eqBuiltInPresets[1]])),
      throwsFormatException,
    );
    expect(() => b.importPresets('[]'), throwsFormatException);
    a.dispose();
    b.dispose();
  });

  test(
    'an engine without EQ support is never driven and cannot be enabled',
    () async {
      final (eq, audio, _) = await make({'eqEnabled': true});
      audio.eqSupported = false;
      audio.setVolume(0.5);
      expect(eq.supported, isFalse);
      expect(eq.active, isFalse);
      audio.eqCalls.clear();
      eq.setEnabled(false);
      eq.setBypass(true);
      expect(audio.eqCalls, isEmpty);
      // La preferencia guardada no se pierde: al volver el soporte, se reaplica.
      expect(eq.enabled, isTrue);
      audio.eqSupported = true;
      audio.setVolume(0.5);
      expect(audio.eqCalls.last.$1, isTrue);
      eq.dispose();
    },
  );
}
