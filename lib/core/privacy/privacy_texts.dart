// lib/core/privacy/privacy_texts.dart
//
// Ruhige, klare Texte (CH) für Ghost-Mode, Teilen & Export-Disclaimer.
// Rückwärts-kompatibel: *Body*/Blurb-Aliasse vorhanden.
// Vorgaben: neutraler Ton, keine „Cloud“-Hinweise.

class PrivacyTexts {
  // ----- Ghost-Mode -----
  static const String ghostTitle = 'Kontext-Gedächtnis (Ghost-Mode)';
  static const String ghostBlurb =
      'Der Panda merkt sich Themen und Facetten lokal auf deinem Gerät. '
      'Das unterstützt, Gespräche natürlicher fortzusetzen. '
      'Die Speicherung erfolgt ausschliesslich auf dem Gerät.';
  // Alias für ältere Aufrufe
  static const String ghostBody = ghostBlurb;

  // ----- Optionales Teilen -----
  static const String shareTitle = 'Mit Therapeut·in teilen (Opt-in)';
  static const String shareBlurb =
      'Wenn du möchtest, kannst du ausgewählte Einträge teilen. '
      'Du bestimmst jederzeit, was geteilt wird, und kannst das Teilen jederzeit beenden.';
  // Alias
  static const String shareBody = shareBlurb;

  // ----- Löschen -----
  static const String deleteTitle = 'Gedächtnis löschen';
  static const String deleteBlurb =
      'Löscht alle lokal gespeicherten Themen und Einsichten sofort. '
      'Das hat keine Auswirkungen auf dein Gedankenbuch.';
  // Alias
  static const String deleteBody = deleteBlurb;

  // ----- Facetten zurücksetzen -----
  static const String resetFacetsTitle = 'Facetten zurücksetzen';
  static const String resetFacetsBlurb =
      'Setzt die intern gezählten Facetten und Häufigkeiten zurück. '
      'Deine Einträge bleiben erhalten.';
  // Alias
  static const String resetFacetsBody = resetFacetsBlurb;

  // ----- Schweizer Kurz-Disclaimer (Export/Übersicht) -----
  static const String chDisclaimerShort =
      'Hinweis (CH): Dieser Export enthält keine Freitexte oder Audioinhalte und wird '
      'lokal erstellt. Ihre Daten verlassen das Gerät nur, wenn Sie die Datei selbst teilen. '
      'ZenYourself ist eine mentale Unterstützungs-App und ersetzt keine medizinische Behandlung.';

  // (Optional) längere Fassung für Settings/Info
  static const String chDisclaimerLong =
      'Datensparsamkeit: Exporte sind standardmässig anonymisiert (redacted). '
      'Es werden keine Klarnamen, Freitexte oder Audiodaten exportiert. '
      'Die Übertragung an Drittpersonen erfolgt ausschliesslich durch Sie. '
      'ZenYourself ist keine medizinische Leistung und ersetzt keine Therapie.';
}
