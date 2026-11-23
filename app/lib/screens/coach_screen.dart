import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../theme.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Wie sieht mein Training heute aus?',
    'Mein Knie zwickt. Was soll ich machen?',
    'Wie bereite ich mich auf 25 km mit 12 kg vor?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(AppState st, String text) async {
    if (text.trim().isEmpty || st.busy) return;
    _input.clear();
    await st.chat(text.trim());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final history = st.chatHistory('coach');
    return Column(children: [
      EchoHeader(title: 'Coach', actions: [
        if (history.isNotEmpty)
          IconButton(
            tooltip: 'Verlauf leeren',
            icon: const Icon(Icons.delete_outline, color: echoMuted),
            onPressed: st.clearChat,
          ),
      ]),
      Expanded(
        child: history.isEmpty
            ? ListView(padding: const EdgeInsets.all(16), children: [
                Text(
                  st.coachEnabled
                      ? 'Frag mich zu Training, Erholung, Plan oder Ernährung. Ich kenne deine Garmin-Daten, '
                          'dein Journal und deinen Wochenplan.'
                      : 'Für den Coach unter „Daten“ den Anthropic-API-Key eintragen.',
                  style: const TextStyle(color: echoMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(onPressed: () => _send(st, s), child: Text(s)),
                  ),
              ])
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: history.length,
                itemBuilder: (c, i) {
                  final m = history[i];
                  final me = m['role'] == 'user';
                  return Align(
                    alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * 0.86),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: me ? echoYellow : echoSurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SelectableText(
                        _plain(m['content'] ?? ''),
                        style: TextStyle(color: me ? echoBlack : Colors.white, height: 1.4),
                      ),
                    ),
                  );
                },
              ),
      ),
      if (st.busy && st.busyLabel != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(st.busyLabel!, style: const TextStyle(color: echoMuted, fontSize: 12)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (t) => _send(st, t),
              decoration: const InputDecoration(hintText: 'Nachricht an den Coach'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: echoYellow, foregroundColor: echoBlack),
            onPressed: st.busy ? null : () => _send(st, _input.text),
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }

  /// Einfaches Markdown (**fett**, # Überschrift) lesbar machen.
  static String _plain(String t) =>
      t.replaceAll('**', '').replaceAllMapped(RegExp(r'^#+\s*', multiLine: true), (_) => '');
}
