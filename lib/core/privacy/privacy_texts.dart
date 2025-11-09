// [MERGE SIGNAL] lib/core/privacy/privacy_texts.dart (v1.3 · 2025-11-09)
// ZenYourself — Privacy Texts (CH, neutral, ohne „Cloud“-Hinweise)
// -----------------------------------------------------------------------------
// • Zentrale, ruhige Texte für Datenschutz/Consent-UI (Ghost-Mode, Name, Export).
// • Rückwärts-Kompatibilität: *Body*-Aliasse zu *Blurb* bleiben erhalten.
// • Trial/Status/Upgrade-Microcopy ergänzt.
// • Keine technischen Begriffe wie „Cloud“ in den Texten.
// -----------------------------------------------------------------------------

class PrivacyTexts {
  // ---------------------------------------------------------------------------
  // Ghost-Mode (Kontext-Gedächtnis on-device)
  // ---------------------------------------------------------------------------
  static const String ghostTitle = 'Kontext-Gedächtnis (Ghost-Mode)';
  static const String ghostBlurb =
      'Der Panda merkt sich Themen und Facetten lokal auf deinem Gerät. '
      'Das unterstützt, Gespräche natürlicher fortzusetzen. '
      'Die Speicherung erfolgt ausschliesslich auf dem Gerät.';
  // Alias (Rückwärts-Kompatibilität)
  static const String ghostBody = ghostBlurb;

  // ---------------------------------------------------------------------------
  // Optionales Teilen (Therapeut·in / Begleitung) – rein optional
  // ---------------------------------------------------------------------------
  static const String shareTitle = 'Mit Therapeut·in teilen (Opt-in)';
  static const String shareBlurb =
      'Wenn du möchtest, kannst du ausgewählte Einträge teilen. '
      'Du bestimmst jederzeit, was geteilt wird, und kannst das Teilen jederzeit beenden.';
  // Alias
  static const String shareBody = shareBlurb;

  // ---------------------------------------------------------------------------
  // Name – ansprechen / löschen
  // ---------------------------------------------------------------------------
  static const String nameTitle = 'Mit Namen ansprechen';
  static const String nameBlurb =
      'Wenn du einen Namen hinterlegst, darf dich Panda damit ansprechen. '
      'Der Name wird lokal gespeichert und nie proaktiv genannt.';
  // Aliasse
  static const String nameBody = nameBlurb;

  static const String nameDeleteTitle = 'Name löschen';
  static const String nameDeleteBlurb =
      'Entfernt den gespeicherten Namen sofort. '
      'Dies hat keine Auswirkungen auf deine bisherigen Einträge.';
  static const String nameDeleteBody = nameDeleteBlurb;

  // Kurze Hinweise (UI-Microcopy)
  static const String nameNoneHint = 'Kein Name gespeichert.';
  static const String nameSavedToast = 'Name gespeichert.';
  static const String nameDeletedToast = 'Name gelöscht.';

  // ---------------------------------------------------------------------------
  // Erinnerungen / Consent (on-device)
  // ---------------------------------------------------------------------------
  static const String memoryConsentTitle = 'Erinnerungen erlauben (on-device)';
  static const String memoryConsentBlurb =
      'Panda darf auf deinem Gerät Erinnerungen an eure Gespräche speichern und nutzen. '
      'Nichts verlässt dein Gerät ohne dein Zutun.';
  static const String memoryConsentBody = memoryConsentBlurb;

  static const String memoryHint =
      'Hinweis: Erinnerungen werden nur lokal gespeichert. '
      'Panda nennt gespeicherte Inhalte nie proaktiv — nur wenn du das Thema wieder aufgreifst.';

  // ---------------------------------------------------------------------------
  // Löschen / Zurücksetzen (lokal)
  // ---------------------------------------------------------------------------
  static const String deleteTitle = 'Gedächtnis löschen';
  static const String deleteBlurb =
      'Löscht alle lokal gespeicherten Themen und Einsichten sofort. '
      'Das hat keine Auswirkungen auf dein Gedankenbuch.';
  static const String deleteBody = deleteBlurb;

  static const String resetFacetsTitle = 'Facetten zurücksetzen';
  static const String resetFacetsBlurb =
      'Setzt intern gezählte Facetten und Häufigkeiten zurück. '
      'Deine Einträge bleiben erhalten.';
  static const String resetFacetsBody = resetFacetsBlurb;

  // Bestätigungsdialoge
  static const String confirmDeleteTitle = 'Gedächtnis wirklich löschen?';
  static const String confirmDeleteBody =
      'Alle lokal gespeicherten Themen und Einsichten werden entfernt. '
      'Dieser Vorgang kann nicht rückgängig gemacht werden.';

  static const String confirmResetTitle = 'Facetten wirklich zurücksetzen?';
  static const String confirmResetBody =
      'Gezählte Häufigkeiten werden zurückgesetzt. Deine Einträge bleiben bestehen.';

  // ---------------------------------------------------------------------------
  // Diagnostik & Nutzung (neutral, ohne Technik-Jargon)
  // ---------------------------------------------------------------------------
  static const String diagnosticsTitle = 'Diagnose senden';
  static const String diagnosticsBlurb =
      'Fehler- und Crash-Infos helfen, die Stabilität zu verbessern. '
      'Deine Inhalte werden nicht übermittelt.';

  static const String usageTitle = 'Anonyme Nutzung teilen';
  static const String usageBlurb =
      'Aggregierte Nutzungswerte (z. B. App-Starts) helfen, die App zu verbessern. '
      'Es werden keine personenbezogenen Inhalte übertragen.';

  // ---------------------------------------------------------------------------
  // Trial / Status / Upgrade (Anzeige-Texte)
  // ---------------------------------------------------------------------------
  static const String statusOff = 'Kontext-Teilen: AUS';
  static const String statusOn = 'Kontext-Teilen: AN';
  static const String statusTrial = 'Kontext-Teilen: AN (Trial)';
  static const String statusExpired = 'Kontext-Teilen: AUS (Trial abgelaufen)';

  /// Formatiert eine kurze Restlaufzeit für den Trial, z. B. „noch 1 Tag“ / „noch 3 Tage“.
  static String trialDaysLeft(int days) =>
      'noch $days Tag${days == 1 ? '' : 'e'}';

  static const String upgradeTitle = 'Upgrade aktivieren';
  static const String upgradeBlurb =
      'Damit Panda dein Kontext-Gedächtnis dauerhaft nutzen darf, '
      'kannst du ein Upgrade aktivieren. Du entscheidest jederzeit.';
  static const String upgradeCta = 'Upgrade';

  // ---------------------------------------------------------------------------
  // Export-Disclaimer (CH)
  // ---------------------------------------------------------------------------
  static const String chDisclaimerShort =
      'Hinweis (CH): Dieser Export enthält keine Freitexte oder Audioinhalte und wird '
      'lokal erstellt. Ihre Daten verlassen das Gerät nur, wenn Sie die Datei selbst teilen. '
      'ZenYourself ist eine mentale Unterstützungs-App und ersetzt keine medizinische Behandlung.';

  static const String chDisclaimerLong =
      'Datensparsamkeit: Exporte sind standardmässig anonymisiert (redacted). '
      'Es werden keine Klarnamen, Freitexte oder Audiodaten exportiert. '
      'Die Übertragung an Drittpersonen erfolgt ausschliesslich durch Sie. '
      'ZenYourself ist keine medizinische Leistung und ersetzt keine Therapie.';

  // ---------------------------------------------------------------------------
  // Buttons / Labels
  // ---------------------------------------------------------------------------
  static const String btnSave = 'Speichern';
  static const String btnDeleteAll = 'Alle Daten löschen';
  static const String btnExport = 'Daten exportieren';
  static const String btnEditName = 'Namen ändern';
  static const String btnForgetName = 'Name löschen';
  static const String btnForgetMemories = 'Erinnerungen löschen';
  static const String btnUpgrade = 'Upgrade aktivieren';
  static const String btnOpenPolicy = 'Erklärung lesen';

  // Snackbars / Toaster
  static const String savedToast = 'Einstellungen gespeichert.';
  static const String exportReadyToast = 'Export erstellt.';
  static const String wipedToast = 'Daten gelöscht.';
  static const String actionCanceledToast = 'Abgebrochen.';
}
