import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The movies web-app's theme (movies PRD #19: "use the web-app theme, not UKOshop's"), taken from
/// web-app/src/index.css and the colours its components actually use:
///   page #0f111a (the nav's #0d0d0d -> #000 -> #0f111a gradient), panels #18181c,
///   borders / chips #2E2E3A, accent #ffd800, section bars #5A5A68, muted text #808C8C / #9CA3AF,
///   cinema red #E50914, Poppins for text and Playfair Display for headings.
/// The token names are the ones the screens already use, so they all follow these values.
class UkoColors {
  UkoColors._();
  static const background = Color(0xFF0F111A); // page
  static const card = Color(0xFF18181C); // panels, sheets, dialogs, inputs (bg-[#18181c])
  static const border = Color(0xFF2E2E3A); // borders, chips, skeletons (border-[#2E2E3A])
  static const text = Color(0xFFFFFFFF);
  static const destructive = Color(0xFFDC2626);
  static const yellow = Color(0xFFFFD800); // accent (text-[#ffd800])
  static const slate = Color(0xFF5A5A68); // section header bar (bg-[#5A5A68])
  static const divider = Color(0xFF808C8C); // card bottom border / muted text (text-[#808C8C])
  static const muted = Color(0xFF9CA3AF); // secondary text (text-[#9CA3AF])
  static const red = Color(0xFFE50914); // cinema red: progress, remove / unfollow
  static const green = Color(0xFF22C55E); // watch / read / done
  static const purple = Color(0xFF2E073F); // the web nav's outline buttons (border-[#2E073F])
  static const teal = Color(0xFF005B6E); // the web's gradient headings (#FFD800 -> #005B6E)
  // the Tailwind greys the RN port used, mapped onto the web palette
  static const gray900 = Color(0xFF0D0D0D); // drawer panel = the web sidebar
  static const gray800 = card;
  static const gray700 = border;
  static const gray400 = muted;
}

/// The web sidebar's background, `linear-gradient(85deg, #0d0d0d, rgba(0,0,0,0.75), #000, #0f111a)`.
const ukoNavGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF0D0D0D), Color(0xBF000000), Color(0xFF000000), UkoColors.background],
);

/// Web headings are Playfair Display and body text Poppins, loaded with google_fonts (fetched on first
/// use, then cached on the device; the platform font shows until then or while offline).
String? get ukoBodyFont => GoogleFonts.poppins().fontFamily;
String? get ukoHeadingFont => GoogleFonts.playfairDisplay().fontFamily;

/// A heading in the web's style (Playfair Display, weight 500), for screens that build their own titles.
TextStyle ukoHeading({double? fontSize, Color color = UkoColors.text, FontWeight fontWeight = FontWeight.w500}) =>
    GoogleFonts.playfairDisplay(fontSize: fontSize, color: color, fontWeight: fontWeight);

ThemeData buildUkoTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final radius = BorderRadius.circular(12); // --radius: 0.75rem
  final text = GoogleFonts.poppinsTextTheme(base.textTheme).apply(bodyColor: UkoColors.text, displayColor: UkoColors.text);
  TextStyle? heading(TextStyle? s) => s == null ? null : GoogleFonts.playfairDisplay(textStyle: s, fontWeight: FontWeight.w500);

  return base.copyWith(
    scaffoldBackgroundColor: UkoColors.background,
    canvasColor: UkoColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: UkoColors.card,
      surfaceContainerHighest: UkoColors.border,
      primary: UkoColors.yellow,
      onPrimary: Colors.black,
      secondary: UkoColors.yellow,
      onSecondary: Colors.black,
      tertiary: UkoColors.red,
      error: UkoColors.destructive,
      outline: UkoColors.border,
      outlineVariant: UkoColors.border,
    ),
    textTheme: text.copyWith(
      displayLarge: heading(text.displayLarge),
      displayMedium: heading(text.displayMedium),
      displaySmall: heading(text.displaySmall),
      headlineLarge: heading(text.headlineLarge),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: heading(text.titleLarge),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: UkoColors.background,
      foregroundColor: UkoColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: ukoHeading(fontSize: 20),
    ),
    dividerColor: UkoColors.border,
    dividerTheme: const DividerThemeData(color: UkoColors.border, thickness: 1),
    cardTheme: CardThemeData(
      color: UkoColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: UkoColors.border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: UkoColors.card,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: UkoColors.border)),
      titleTextStyle: ukoHeading(fontSize: 20),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: UkoColors.card, modalBackgroundColor: UkoColors.card),
    drawerTheme: const DrawerThemeData(backgroundColor: UkoColors.gray900),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: UkoColors.card,
      contentTextStyle: TextStyle(color: UkoColors.text),
      actionTextColor: UkoColors.yellow,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: UkoColors.yellow),
    sliderTheme: const SliderThemeData(
      activeTrackColor: UkoColors.yellow,
      thumbColor: UkoColors.yellow,
      inactiveTrackColor: UkoColors.border,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : UkoColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? UkoColors.yellow : UkoColors.border),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: UkoColors.yellow,
      unselectedLabelColor: UkoColors.muted,
      indicatorColor: UkoColors.yellow,
      dividerColor: UkoColors.border,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: UkoColors.border,
      selectedColor: UkoColors.yellow,
      labelStyle: const TextStyle(color: UkoColors.text),
      side: const BorderSide(color: UkoColors.border),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: UkoColors.yellow,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: UkoColors.yellow,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: UkoColors.text,
        side: const BorderSide(color: UkoColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: UkoColors.yellow)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: UkoColors.card,
      hintStyle: const TextStyle(color: UkoColors.divider),
      labelStyle: const TextStyle(color: UkoColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: UkoColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: UkoColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: UkoColors.yellow)),
    ),
  );
}
