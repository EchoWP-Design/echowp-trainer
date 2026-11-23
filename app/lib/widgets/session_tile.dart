import 'package:flutter/material.dart';

import '../logic/planner.dart';
import '../theme.dart';

const kindIcons = {
  'kraft': Icons.fitness_center,
  'cardio': Icons.trending_up,
  'intervall': Icons.timer_outlined,
  'marsch': Icons.hiking,
  'mobility': Icons.self_improvement,
  'lauf': Icons.directions_run,
  'gehen': Icons.directions_walk,
  'sonstiges': Icons.sports,
};

/// Eine geplante Einheit, aufklappbar mit Übungen und Status-Knöpfen.
class SessionTile extends StatelessWidget {
  final PlannedSession session;
  final void Function(String status) onStatus;
  const SessionTile({super.key, required this.session, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final done = s.status == 'erledigt';
    final skipped = s.status == 'ausgelassen';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: echoSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: done ? const Color(0xFF3DDC84) : echoYellow, width: 4)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            iconColor: echoYellow,
            collapsedIconColor: echoMuted,
            leading: Icon(kindIcons[s.kind] ?? Icons.sports, color: echoYellow),
            title: Text(s.title,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: skipped ? TextDecoration.lineThrough : null,
                    color: skipped ? echoMuted : Colors.white)),
            subtitle: Text(
              '${s.start}–${s.end}${s.rpe != null ? ' · RPE ${s.rpe}' : ''}'
              '${done ? ' · erledigt' : skipped ? ' · ausgelassen' : ''}',
              style: const TextStyle(color: echoMuted, fontSize: 12),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.focus.isNotEmpty) Text(s.focus, style: const TextStyle(height: 1.35)),
              if (s.exercises.isNotEmpty) const SizedBox(height: 8),
              for (final e in s.exercises)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('•  ', style: TextStyle(color: echoYellow)),
                    Expanded(child: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text('${e['detail'] ?? ''}',
                            textAlign: TextAlign.right, style: const TextStyle(color: echoMuted, fontSize: 12))),
                  ]),
                ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => onStatus(done ? 'geplant' : 'erledigt'),
                  icon: Icon(done ? Icons.undo : Icons.check, size: 18),
                  label: Text(done ? 'Zurücksetzen' : 'Erledigt'),
                ),
                if (!done)
                  OutlinedButton(
                    onPressed: () => onStatus(skipped ? 'geplant' : 'ausgelassen'),
                    child: Text(skipped ? 'Doch machen' : 'Auslassen'),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
