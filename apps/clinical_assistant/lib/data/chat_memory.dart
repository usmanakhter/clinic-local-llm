import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// In-process + SharedPreferences transcript so Chat survives tab switches
/// and process restarts (UI text only — citation bundles are not restored).
class ChatMemory {
  ChatMemory._();
  static final ChatMemory instance = ChatMemory._();

  static const _prefsKey = 'nepal_chat_transcript_v1';
  static const maxStoredMessages = 80;

  final List<ChatMemoryMessage> messages = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      messages
        ..clear()
        ..addAll(
          list.map(
            (e) => ChatMemoryMessage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
    } catch (_) {
      // Corrupt prefs — start fresh.
      messages.clear();
    }
  }

  void replaceAll(List<ChatMemoryMessage> next) {
    messages
      ..clear()
      ..addAll(next);
    // Fire-and-forget persist.
    // ignore: discarded_futures
    _persist();
  }

  Future<void> clear() async {
    messages.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slice = messages.length <= maxStoredMessages
          ? messages
          : messages.sublist(messages.length - maxStoredMessages);
      await prefs.setString(
        _prefsKey,
        jsonEncode(slice.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }
}

class ChatMemoryMessage {
  const ChatMemoryMessage({
    required this.role,
    required this.text,
    this.fromModel = false,
    this.isError = false,
    this.sessionId,
    this.feedback,
  });

  final String role;
  final String text;
  final bool fromModel;
  final bool isError;
  final String? sessionId;
  final String? feedback;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'fromModel': fromModel,
        'isError': isError,
        if (sessionId != null) 'sessionId': sessionId,
        if (feedback != null) 'feedback': feedback,
      };

  factory ChatMemoryMessage.fromJson(Map<String, dynamic> json) {
    return ChatMemoryMessage(
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      fromModel: json['fromModel'] as bool? ?? false,
      isError: json['isError'] as bool? ?? false,
      sessionId: json['sessionId'] as String?,
      feedback: json['feedback'] as String?,
    );
  }
}
