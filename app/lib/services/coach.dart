/// KI-Coach mit Claude (Messages API per HTTP, es gibt kein offizielles Dart-SDK).
///
/// Ohne API-Schlüssel arbeitet die App mit den regelbasierten Texten und
/// Plänen. Mit Schlüssel formuliert Claude das Tages-Briefing, plant die
/// Woche anhand deiner Daten und beantwortet Fragen im Chat.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/planner.dart';
import '../logic/readiness.dart';

const coachModels = {
  'claude-opus-5-5': 'Claude Opus 5.5 (beste Qualität)',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 (günstiger)',
  'claude-haiku-5-5': 'Claude Haiku 5.5 (am günstigsten)',
};
const defaultCoachModel = 'claude-opus-5-5';

const coachSystem = '''Du bist der Performance-Coach in der App "EchoWP Trainer".
Du sprichst Deutsch, duzt, bist direkt, ruhig und konkret. Keine Floskeln, keine Emojis.
Du kennst Trainingslehre (Periodisierung, Zone-2-Training, RPE, Deload, Regeneration)
und begründest Empfehlungen mit den gelieferten Daten (Bereitschafts-Score, Schlaf, HRV,
Ruhepuls, Body Battery, Gefühl, Trainingshistorie, Journal, Ernährung).
Wenn Daten fehlen, sag das kurz, statt etwas zu erfinden.
Trainingsschwerpunkt: Functional Fitness mit Eigengewicht, Kettlebell und Gewichten,
Ausdauer als Steigungsgehen auf dem Laufband, lange Märsche auch mit Rucksack (Rucking).
Wegen Kniebeschwerden: kaum Laufen, keine Sprünge, keine tiefen Ausfallschritte, Kniebeugen
auf Box. Beachte zusätzlich die Einschränkungen im Feld "einschraenkungen".
Bei Warnzeichen (Krankheit, Schmerzen, Brustschmerz, Schwindel) rätst du zu Pause und ärztlicher Abklärung.
Du stellst keine medizinischen Diagnosen.
Antworten erscheinen in einer Handy-App: kurze Absätze, höchstens einfache Aufzählungen mit "- ".''';

const weekSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['phase', 'summary', 'rationale', 'questions', 'sessions'],
  'properties': {
    'phase': {
      'type': 'string',
      'enum': ['Aufbau', 'Erhaltung', 'Deload', 'Entlastung']
    },
    'summary': {'type': 'string'},
    'rationale': {'type': 'string'},
    'questions': {
      'type': 'array',
      'items': {'type': 'string'}
    },
    'sessions': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['date', 'start', 'end', 'kind', 'title', 'focus', 'rpe', 'exercises'],
        'properties': {
          'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'start': {'type': 'string', 'description': 'HH:MM'},
          'end': {'type': 'string', 'description': 'HH:MM'},
          'kind': {
            'type': 'string',
            'enum': ['kraft', 'cardio', 'intervall', 'marsch', 'mobility']
          },
          'title': {'type': 'string'},
          'focus': {'type': 'string'},
          'rpe': {'type': 'integer'},
          'exercises': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['name', 'detail'],
              'properties': {
                'name': {'type': 'string'},
                'detail': {'type': 'string'}
              },
            },
          },
        },
      },
    },
  },
};

class CoachError implements Exception {
  final String message;
  CoachError(this.message);
  @override
  String toString() => message;
}

class Briefing {
  final String text, source, level, label;
  final int? score;
  Briefing(this.text, this.source, this.level, this.label, this.score);

  Map<String, dynamic> toJson() => {'text': text, 'source': source, 'level': level, 'label': label, 'score': score};

  factory Briefing.fromJson(Map<String, dynamic> j) => Briefing(j['text'] as String? ?? '',
      j['source'] as String? ?? 'regeln', j['level'] as String? ?? '', j['label'] as String? ?? '', j['score'] as int?);
}

Briefing ruleBriefing(Readiness r, List<PlannedSession> today) {
  final planned = today.where((s) => s.kind != 'mobility').toList();
  final title = planned.isEmpty ? null : planned.map((s) => s.title).join(', ');
  final String text;
  if (r.score == null) {
    text = 'Noch keine Daten für heute. Synchronisiere Garmin und füll kurz das Journal aus.';
  } else if (r.level == 'push') {
    text = 'Du bist gut erholt (Score ${r.score}). ' +
        (title != null ? '$title: wie geplant, gern am oberen Ende der RPE.' : 'Guter Tag für eine harte Einheit.');
  } else if (r.level == 'normal') {
    text = 'Solide Bereitschaft (Score ${r.score}). ' +
        (title != null ? '$title wie geplant durchziehen.' : 'Lockeres Training oder Spaziergang passt.');
  } else if (r.level == 'locker') {
    text = 'Bereitschaft eingeschränkt (Score ${r.score}). ' +
        (title != null ? '$title: RPE um 1–2 senken und pro Übung einen Satz weniger.' : 'Heute nur locker bewegen.');
  } else {
    text = 'Niedrige Bereitschaft (Score ${r.score}). Heute Recovery: Spaziergang, Mobility, früh schlafen.' +
        (title != null ? ' $title verschieben.' : '');
  }
  final extra = (r.score ?? 0) >= 50
      ? 'Was heute noch geht: 20 min Mobility oder ein Spaziergang.'
      : 'Was heute noch geht: Spaziergang an der frischen Luft, Dehnen.';
  return Briefing('$text\n$extra', 'regeln', r.level, r.label, r.score);
}

class CoachClient {
  final String apiKey;
  final String model;
  final http.Client http_;

  CoachClient(this.apiKey, {this.model = defaultCoachModel, http.Client? client}) : http_ = client ?? http.Client();

  Future<String> call(List<Map<String, dynamic>> messages,
      {int maxTokens = 4000, String effort = 'low', Map<String, dynamic>? schema}) async {
    final outputConfig = <String, dynamic>{'effort': effort};
    if (schema != null) outputConfig['format'] = {'type': 'json_schema', 'schema': schema};
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'system': coachSystem,
      'messages': messages,
      'output_config': outputConfig,
    };
    final http.Response resp;
    try {
      resp = await http_
          .post(Uri.parse('https://api.anthropic.com/v1/messages'),
              headers: {
                'x-api-key': apiKey.trim(),
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json',
              },
              body: jsonEncode(body))
          .timeout(const Duration(minutes: 5));
    } catch (_) {
      throw CoachError('Claude ist nicht erreichbar. Internetverbindung prüfen.');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode == 401) throw CoachError('Der Anthropic-API-Key wurde abgelehnt.');
    if (resp.statusCode != 200) {
      final msg = data is Map && data['error'] is Map ? (data['error'] as Map)['message'] : null;
      throw CoachError('Claude-Fehler (HTTP ${resp.statusCode})${msg != null ? ': $msg' : ''}');
    }
    final stop = data['stop_reason'];
    if (stop == 'refusal') throw CoachError('Der Coach hat die Anfrage abgelehnt.');
    if (stop == 'max_tokens') throw CoachError('Antwort des Coaches war zu lang und wurde abgeschnitten.');
    return [
      for (final b in (data['content'] as List))
        if (b is Map && b['type'] == 'text') b['text'] as String
    ].join().trim();
  }

  Future<Briefing> briefing(Map<String, dynamic> ctx, Readiness r, List<PlannedSession> today) async {
    final prompt = 'Schreib mein Coaching-Briefing für heute in 3 bis 5 kurzen Sätzen. '
        'Sag, ob ich das geplante Training wie geplant, angepasst oder gar nicht machen soll, '
        'und nenn konkrete Anpassungen (RPE, Sätze, Dauer). Danach eine Zeile "Was heute noch geht:".\n\n'
        'Daten:\n${jsonEncode(ctx)}';
    final text = await call([
      {'role': 'user', 'content': prompt}
    ], maxTokens: 2000);
    return Briefing(text, 'claude', r.level, r.label, r.score);
  }

  Future<WeekPlan> planWeek(Map<String, dynamic> ctx, WeekPlan base, {String? instruction}) async {
    var task = 'Erstelle meinen Trainingsplan für die Woche ab ${base.weekStart}. Grundlage ist der '
        'regelbasierte Entwurf unten. Halte dich an meine Wochenziele und an die freien Zeitfenster. '
        'Verbessere Reihenfolge, Inhalte und Intensität anhand meiner Daten der letzten 30 Tage. Übungen mit '
        'Sätzen, Wiederholungen und RPE im Feld detail. Begründe die Phase kurz mit Daten und stelle maximal '
        'zwei Rückfragen.';
    if (instruction != null && instruction.trim().isNotEmpty) task += '\n\nMeine Änderungswünsche: $instruction';
    final prompt = '$task\n\nEntwurf:\n${jsonEncode(base.toJson())}\n\nKontext:\n${jsonEncode(ctx)}';
    final raw = await call([
      {'role': 'user', 'content': prompt}
    ], maxTokens: 16000, effort: 'medium', schema: weekSchema);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final sessions = [
      for (final s in data['sessions'] as List)
        if ((s['date'] as String).compareTo(base.weekStart) >= 0) PlannedSession.fromJson(Map<String, dynamic>.from(s))
    ]..sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}'));
    return WeekPlan(
      base.weekStart,
      data['phase'] as String,
      data['summary'] as String,
      data['rationale'] as String,
      [for (final q in (data['questions'] as List).take(2)) q.toString()],
      sessions,
      source: 'claude',
    );
  }

  Future<String> chat(List<Map<String, String>> history, String message, Map<String, dynamic> ctx) {
    final msgs = <Map<String, dynamic>>[
      for (final h in history.length > 20 ? history.sublist(history.length - 20) : history)
        {'role': h['role'], 'content': h['content']},
      {'role': 'user', 'content': '$message\n\n[Aktuelle Daten]\n${jsonEncode(ctx)}'},
    ];
    return call(msgs, maxTokens: 3000);
  }
}
