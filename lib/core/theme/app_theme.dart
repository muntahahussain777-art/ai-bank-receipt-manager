import 'package:flutter/material.dart';

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pending,
    required this.pendingContainer,
    required this.entered,
    required this.enteredContainer,
    required this.reconciliation,
    required this.reconciliationContainer,
    required this.received,
    required this.sent,
  });

  final Color pending;
  final Color pendingContainer;
  final Color entered;
  final Color enteredContainer;
  final Color reconciliation;
  final Color reconciliationContainer;
  final Color received;
  final Color sent;

  static const light = StatusColors(
    pending: Color(0xFF9A3412),
    pendingContainer: Color(0xFFFFEDD5),
    entered: Color(0xFF166534),
    enteredContainer: Color(0xFFDCFCE7),
    reconciliation: Color(0xFF9F1239),
    reconciliationContainer: Color(0xFFFFE4E6),
    received: Color(0xFF166534),
    sent: Color(0xFF9A3412),
  );

  static const dark = StatusColors(
    pending: Color(0xFFFDBA74),
    pendingContainer: Color(0xFF431407),
    entered: Color(0xFF86EFAC),
    enteredContainer: Color(0xFF052E16),
    reconciliation: Color(0xFFFDA4AF),
    reconciliationContainer: Color(0xFF4C0519),
    received: Color(0xFF86EFAC),
    sent: Color(0xFFFDBA74),
  );

  @override
  StatusColors copyWith({
    Color? pending,
    Color? pendingContainer,
    Color? entered,
    Color? enteredContainer,
    Color? reconciliation,
    Color? reconciliationContainer,
    Color? received,
    Color? sent,
  }) {
    return StatusColors(
      pending: pending ?? this.pending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      entered: entered ?? this.entered,
      enteredContainer: enteredContainer ?? this.enteredContainer,
      reconciliation: reconciliation ?? this.reconciliation,
      reconciliationContainer:
          reconciliationContainer ?? this.reconciliationContainer,
      received: received ?? this.received,
      sent: sent ?? this.sent,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) {
      return this;
    }
    return StatusColors(
      pending: Color.lerp(pending, other.pending, t)!,
      pendingContainer: Color.lerp(
        pendingContainer,
        other.pendingContainer,
        t,
      )!,
      entered: Color.lerp(entered, other.entered, t)!,
      enteredContainer: Color.lerp(
        enteredContainer,
        other.enteredContainer,
        t,
      )!,
      reconciliation: Color.lerp(reconciliation, other.reconciliation, t)!,
      reconciliationContainer: Color.lerp(
        reconciliationContainer,
        other.reconciliationContainer,
        t,
      )!,
      received: Color.lerp(received, other.received, t)!,
      sent: Color.lerp(sent, other.sent, t)!,
    );
  }
}

StatusColors statusColorsOf(BuildContext context) {
  return Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
}

abstract final class AppTheme {
  static ThemeData light() => _base(_lightScheme(), StatusColors.light);

  static ThemeData dark() => _base(_darkScheme(), StatusColors.dark);

  static ColorScheme _lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E4C59),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0E4C59),
      onPrimary: Colors.white,
      secondary: const Color(0xFF1B6B45),
      onSecondary: Colors.white,
      tertiary: const Color(0xFF8A4B08),
      onTertiary: Colors.white,
    );
  }

  static ColorScheme _darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF7DCFC3),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF8ED9CE),
      onPrimary: const Color(0xFF00332F),
      secondary: const Color(0xFF8FDBB4),
      onSecondary: const Color(0xFF003822),
      tertiary: const Color(0xFFF2C078),
      onTertiary: const Color(0xFF3F2A00),
    );
  }

  static ThemeData _base(ColorScheme scheme, StatusColors status) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      extensions: [status],
    );
    final text = base.textTheme;
    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
