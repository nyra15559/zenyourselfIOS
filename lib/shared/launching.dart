// lib/shared/launching.dart
// -----------------------------------------------------------------------------
// Oxford–Zen v1.2 — Einheitliches Öffnen von Links, Telefon, Mail & SMS
// - Sichere Normalisierung von CH-Telefonnummern (E.164, Kurznummern 143/144…)
// - Einheitliches Fehler-Handling (silent, mit Haptik + debugPrint)
// - Immer "externalApplication", damit Browser/Telefon-App geöffnet wird
// - Null- und Whitespace-Schutz, automatische https://-Präfixe
// -----------------------------------------------------------------------------

library launching;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:url_launcher/url_launcher.dart' as ul;

class Launching {
  Launching._();

  /// Öffnet `https://…` / `http://…` / Domain (auto https-Vervollständigung).
  static Future<bool> openUrl(String input, {bool external = true}) async {
    final uri = _parseUrl(input);
    return _launch(uri, external: external);
  }

  /// Startet einen Anruf. Akzeptiert: "+41 44 123 45 67", "044…", "143", "144" etc.
  static Future<bool> openTel(String input) async {
    final normalized = _normalizeCHPhone(input);
    final uri = Uri(scheme: 'tel', path: normalized);
    return _launch(uri, external: true);
  }

  /// Öffnet die SMS-App (falls verfügbar).
  static Future<bool> openSms(String input, {String? body}) async {
    final normalized = _normalizeCHPhone(input);
    final qp = <String, String>{};
    if ((body ?? '').trim().isNotEmpty) qp['body'] = body!.trim();
    final uri = Uri(scheme: 'sms', path: normalized, queryParameters: qp.isEmpty ? null : qp);
    return _launch(uri, external: true);
  }

  /// Öffnet den E-Mail-Client.
  static Future<bool> openEmail(
    String to, {
    String? subject,
    String? body,
    List<String>? cc,
    List<String>? bcc,
  }) async {
    final qp = <String, String>{};
    if ((subject ?? '').trim().isNotEmpty) qp['subject'] = subject!.trim();
    if ((body ?? '').trim().isNotEmpty) qp['body'] = body!.trim();
    if (cc != null && cc.isNotEmpty) qp['cc'] = cc.join(',');
    if (bcc != null && bcc.isNotEmpty) qp['bcc'] = bcc.join(',');
    final uri = Uri(
      scheme: 'mailto',
      path: to.trim(),
      queryParameters: qp.isEmpty ? null : qp,
    );
    return _launch(uri, external: true);
  }

  // --------------------------- intern ----------------------------------------

  static Future<bool> _launch(Uri uri, {required bool external}) async {
    try {
      final mode = external ? ul.LaunchMode.externalApplication : ul.LaunchMode.platformDefault;
      final ok = await ul.launchUrl(uri, mode: mode);
      if (!ok) {
        debugPrint('[Launching] Konnte nicht öffnen: $uri');
        HapticFeedback.selectionClick();
      }
      return ok;
    } catch (e) {
      debugPrint('[Launching] Fehler beim Öffnen von $uri — $e');
      HapticFeedback.selectionClick();
      return false;
    }
  }

  static Uri _parseUrl(String input) {
    var s = (input).trim();
    if (s.isEmpty) s = 'https://example.com';
    if (!s.contains('://')) s = 'https://$s';
    return Uri.parse(s);
  }

  /// Normalisiert Schweizer Nummern:
  /// - Kurznummern (z. B. 143, 144, 117, 118, 112, 147, 145) bleiben dreistellig.
  /// - "0041…" → "+41…"
  /// - "0xx…" → "+41xx…"
  /// - Entfernt Leerzeichen, Klammern, Bindestriche.
  static String _normalizeCHPhone(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9+]+'), '');
    final short = digitsOnly.replaceAll(RegExp(r'\D'), '');

    // Kurz-/Notfallnummern (3–4 Ziffern) unverändert wählen lassen
    if (short.length <= 4 && short.isNotEmpty) return short;

    var s = digitsOnly;

    if (s.startsWith('00')) {
      s = '+${s.substring(2)}';
    }

    if (s.startsWith('+')) {
      return s;
    }

    // Nationale Schreibweise (0xx…) → +41xx…
    if (s.startsWith('0')) {
      return '+41${s.substring(1)}';
    }

    // Falls keine führende 0/+/00 und lang genug: als CH interpretieren
    if (s.length >= 6) {
      return '+41$s';
    }

    // Fallback (z. B. exotische Eingabe) – lieber roh wählen
    return short;
  }
}
