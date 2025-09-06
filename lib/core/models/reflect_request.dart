// lib/core/models/reflect_request.dart
//
// ReflectRequest — stabiles DTO für /reflect & /reflect_full (Worker v8)
// - Schlank, ohne Service-Abhängigkeiten
// - Hilfs-Builder für ersten Turn und Folge-Turns
// - Sanfte Sanitizer (Trims, Bounds), aber KEIN PII-Stripe hier
//
// Verwendung:
//   final req = ReflectRequest.firstTurn(text: "…");
//   final json = req.toJson(); // direkt an HTTP schicken

class ReflectMessage {
  final String role;    // "user" | "assistant" | "system"
  final String content; // reiner Text

  const ReflectMessage({required this.role, required this.content});

  factory ReflectMessage.user(String text) =>
      ReflectMessage(role: 'user', content: text);

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };

  factory ReflectMessage.fromJson(Map<String, dynamic> json) {
    return ReflectMessage(
      role: (json['role'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
    );
  }
}

class ReflectSession {
  final String id;      // Thread-ID
  final int turn;       // 0..n
  final int maxTurns;   // 2..6 (empfohlen)

  const ReflectSession({required this.id, required this.turn, required this.maxTurns});

  ReflectSession copyWith({String? id, int? turn, int? maxTurns}) => ReflectSession(
        id: id ?? this.id,
        turn: turn ?? this.turn,
        maxTurns: maxTurns ?? this.maxTurns,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'turn': turn,
        'max_turns': maxTurns,
      };

  factory ReflectSession.fromJson(Map<String, dynamic> json) {
    return ReflectSession(
      id: (json['id'] ?? json['thread_id'] ?? '').toString(),
      turn: _asInt(json['turn'] ?? json['turn_index'], 0),
      maxTurns: _asInt(json['max_turns'], 3),
    );
  }
}

class ReflectRequest {
  final String text; // Eingabetext des Nutzers (kann leer sein für Follow-up)
  final List<ReflectMessage> messages; // Gesprächskontext (optional)
  final String locale; // z. B. "de"
  final String tz;     // z. B. "Europe/Zurich"
  final ReflectSession session;

  const ReflectRequest({
    required this.text,
    required this.messages,
    required this.locale,
    required this.tz,
    required this.session,
  });

  /// Builder: erster Turn (turn=0)
  factory ReflectRequest.firstTurn({
    required String text,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    required ReflectSession session,
    List<ReflectMessage> messages = const [],
  }) {
    return ReflectRequest(
      text: text.trim(),
      messages: messages,
      locale: locale,
      tz: tz,
      session: session.copyWith(turn: 0),
    );
  }

  /// Builder: Folge-Turn (turn+1)
  factory ReflectRequest.nextTurn({
    required String text,
    required ReflectSession previous,
    String locale = 'de',
    String tz = 'Europe/Zurich',
    List<ReflectMessage> messages = const [],
  }) {
    final nxt = previous.copyWith(
      turn: (previous.turn + 1),
      maxTurns: _clamp(previous.maxTurns, 2, 6),
    );
    return ReflectRequest(
      text: text.trim(),
      messages: messages,
      locale: locale,
      tz: tz,
      session: nxt,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (messages.isNotEmpty) 'messages': messages.map((m) => m.toJson()).toList(),
        'locale': locale,
        'tz': tz,
        'session': session.toJson(), // v8-konform: {id, turn, max_turns}
      };
}

// -----------------------
// kleine Helfer (internal)
// -----------------------
int _clamp(int v, int min, int max) => v < min ? min : (v > max ? max : v);
int _asInt(dynamic v, int def) {
  if (v is num) return v.toInt();
  if (v is String) {
    final p = int.tryParse(v);
    if (p != null) return p;
  }
  return def;
}
