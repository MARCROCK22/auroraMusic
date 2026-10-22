import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';
import 'modern_theme.dart' show ModernMarker;

/// Paleta Slush: neo-brutalismo de pegatinas, tinta negra y colores planos.
abstract final class Slush {
  static const ink = Color(0xff0a0a0a);
  static const mint = Color(0xff5fe0a0);
  static const yellow = Color(0xffffd62e);
  static const lilac = Color(0xffe3cdfb);
  static const orange = Color(0xffff4d0a);
  static const blue = Color(0xff3b8bf2);
  static const violet = Color(0xff5b3fe0);

  /// Borde grueso de todas las piezas.
  static const border = BorderSide(color: ink, width: 2);

  /// Sombra dura sin desenfoque, típica de pegatina.
  static const hardShadow = [BoxShadow(color: ink, offset: Offset(3, 4))];

  /// Fondo plano de pantalla: pastel con el tono de la portada (texto negro
  /// siempre legible: luminosidad fija alta).
  static Color background(Color accent) {
    final h = HSLColor.fromColor(accent);
    return HSLColor.fromAHSL(
      1,
      h.hue,
      h.saturation.clamp(.45, .85),
      .86,
    ).toColor();
  }
}

/// Tema «Slush»: siempre claro; fondo plano teñido por la portada, contornos
/// negros de 2,5 px, titulares Bagel Fat One, píldoras y tarjetas blancas.
/// Misma firma que `auroraTheme`. Lleva también [ModernMarker] para reutilizar
/// las composiciones de Modern (tarjetas, paneles, barras) con su aspecto.
ThemeData slushTheme(Brightness brightness, Color accent) {
  const ink = Slush.ink;
  final bg = Slush.background(accent);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Slush.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: ink,
        onPrimary: Colors.white,
        primaryContainer: ink,
        onPrimaryContainer: Colors.white,
        secondary: Slush.mint,
        onSecondary: ink,
        secondaryContainer: Slush.mint,
        onSecondaryContainer: ink,
        tertiary: Slush.orange,
        onTertiary: ink,
        error: const Color(0xffc62828),
        surface: bg,
        surfaceDim: bg,
        surfaceBright: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Colors.white,
        surfaceContainerHigh: Slush.lilac,
        surfaceContainerHighest: Slush.yellow,
        onSurface: ink,
        onSurfaceVariant: const Color(0xff2b2b2b),
        outline: ink,
        outlineVariant: ink,
      );

  const font = 'Inter';
  const display = 'Bagel Fat One';
  TextStyle head(double size, double h) => TextStyle(
    fontFamily: display,
    fontSize: size,
    height: h,
    letterSpacing: -size * .01,
    color: ink,
  );
  final textTheme = ThemeData.light().textTheme
      .apply(fontFamily: font, bodyColor: ink, displayColor: ink)
      .copyWith(
        displayLarge: head(72, 1),
        headlineLarge: head(44, 1.05),
        headlineMedium: head(32, 1.1),
        headlineSmall: head(26, 1.15),
        titleLarge: head(22, 1.2),
        titleMedium: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
        ),
        labelLarge: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
        ),
      );

  final states = AuroraStates.from(scheme);
  const pill = StadiumBorder(side: Slush.border);
  RoundedRectangleBorder card(double r) => RoundedRectangleBorder(
    side: Slush.border,
    borderRadius: BorderRadius.circular(r),
  );
  OutlineInputBorder field([double w = 2]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: ink, width: w),
  );
  const heavy = TextStyle(fontFamily: font, fontWeight: FontWeight.w800);
  // Hover amarillo, pulsado lila: se ve sobre blanco, menta y el fondo pastel.
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? Slush.lilac.withValues(alpha: .85)
        : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
        ? Slush.yellow.withValues(alpha: .55)
        : null,
  );
  final ringSide = WidgetStateProperty.resolveWith<BorderSide>(
    (s) => s.contains(WidgetState.disabled)
        ? const BorderSide(color: Color(0xff6b6b6b), width: 2)
        : Slush.border,
  );

  return ThemeData(
    useMaterial3: true,
    extensions: [states, const ModernMarker(), const SlushMarker()],
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: textTheme,
    scaffoldBackgroundColor: bg,
    dividerTheme: const DividerThemeData(color: ink, thickness: 2, space: 2),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: Slush.mint,
        foregroundColor: ink,
        disabledBackgroundColor: Colors.white,
        disabledForegroundColor: const Color(0xff595959),
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: Colors.white,
        foregroundColor: ink,
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: ringSide,
        foregroundColor: WidgetStateProperty.all(ink),
        textStyle: WidgetStateProperty.all(heavy),
        overlayColor: overlay,
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Slush.mint
              : s.contains(WidgetState.hovered)
              ? Slush.yellow
              : Colors.white,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: ink,
        textStyle: heavy,
        // Sin contorno propio: dentro de listas el borde se recortaba.
        shape: const StadiumBorder(),
      ).copyWith(overlayColor: overlay),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: card(24),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Slush.mint,
      elevation: 0,
      pressElevation: 0,
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? const Color(0xffe6e6e6)
            : s.contains(WidgetState.selected)
            ? Slush.mint
            : s.contains(WidgetState.pressed)
            ? Slush.lilac
            : s.contains(WidgetState.hovered)
            ? Slush.yellow
            : Colors.white,
      ),
      disabledColor: const Color(0xffe6e6e6),
      labelStyle: heavy.copyWith(color: ink),
      secondaryLabelStyle: heavy.copyWith(color: ink),
      checkmarkColor: ink,
      shape: pill,
      side: Slush.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xff4a4a4a)),
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w700),
      border: field(),
      enabledBorder: field(),
      focusedBorder: field(4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: card(28),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: ink,
      selectedTileColor: Slush.mint,
      textColor: ink,
      iconColor: ink,
      shape: card(16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: card(16),
      textStyle: const TextStyle(color: ink, fontWeight: FontWeight.w700),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ink,
      indicatorColor: Slush.yellow,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? ink : Colors.white,
        ),
      ),
      labelTextStyle: WidgetStateProperty.all(
        heavy.copyWith(fontSize: 12, color: Colors.white),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(ink),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Slush.mint : Slush.lilac,
      ),
      trackOutlineColor: WidgetStateProperty.all(ink),
      trackOutlineWidth: WidgetStateProperty.all(2),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 6,
      activeTrackColor: ink,
      thumbColor: Slush.violet,
      inactiveTrackColor: Color(0xff5c5c5c),
      overlayColor: Color(0x335b3fe0),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: Colors.white,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

/// Marca del tema Slush: la UI añade bordes/pegatinas con `isSlush(context)`.
class SlushMarker extends ThemeExtension<SlushMarker> {
  const SlushMarker();
  @override
  SlushMarker copyWith() => this;
  @override
  SlushMarker lerp(SlushMarker? other, double t) => this;
}

bool isSlush(BuildContext context) =>
    Theme.of(context).extension<SlushMarker>() != null;
