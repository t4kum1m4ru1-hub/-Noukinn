import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/models/enums.dart';

void main() {
  group('001_initial_schema.sql structural & enum parity', () {
    late String rawSql;
    late String sql;

    setUpAll(() {
      final file = File('supabase/migrations/001_initial_schema.sql');
      expect(file.existsSync(), isTrue);
      rawSql = file.readAsStringSync();
      sql = rawSql.toLowerCase();
    });

    test('defines all 4 contracted tables, PKs, FKs, indexes, and 26 columns', () {
      for (final table in const <String>[
        'user_profiles',
        'muscle_states',
        'machine_history',
        'workout_sessions',
      ]) {
        expect(RegExp('create\\s+table[^;]*$table').hasMatch(sql), isTrue);
        expect(
          RegExp('alter\\s+table[^;]*$table[^;]*enable\\s+row\\s+level\\s+security')
              .hasMatch(sql),
          isTrue,
        );
      }

      expect(sql, contains('references auth.users(id) on delete cascade'));
      expect(sql, contains('primary key (user_id, muscle_id)'));
      expect(sql, contains('primary key (user_id, machine_id)'));
      expect(sql, contains('id uuid primary key'));
      expect(sql, contains('exercises_json jsonb'));
      expect(sql, contains('stimulation_days double precision'));
      expect(sql, contains('idx_workout_sessions_user_completed_at'));
      expect(sql, contains('idx_muscle_states_user_id'));
      expect(sql, contains('idx_machine_history_user_id'));

      const expectedColumns = <String>[
        'user_id',
        'gender',
        'birth_year',
        'experience',
        'body_weight_kg',
        'purpose',
        'is_first_time',
        'session_count',
        'muscle_id',
        'blank_days',
        'stimulation_days',
        'priority_p',
        'is_injured',
        'machine_id',
        'sessions_since_used',
        'last_weight_kg',
        'last_feedback',
        'completed_at',
        'duration_course',
        'condition',
        'time_slot',
        'focus_muscle_id',
        'feedback',
        'exercises_json',
        'created_at',
        'updated_at',
      ];
      for (final col in expectedColumns) {
        expect(sql, contains(col));
      }
    });

    test('enables RLS on all 4 tables and defines SELECT/INSERT/UPDATE/DELETE policies with auth.uid() = user_id', () {
      expect(
        RegExp(r'enable\s+row\s+level\s+security').allMatches(sql).length,
        4,
      );
      expect(RegExp(r'create\s+policy').allMatches(sql).length, 16);
      expect(
        RegExp(r'auth\.uid\(\)\s*=\s*user_id').allMatches(sql).length,
        greaterThanOrEqualTo(16),
      );

      for (final table in const <String>[
        'user_profiles',
        'muscle_states',
        'machine_history',
        'workout_sessions',
      ]) {
        for (final op in const <String>['select', 'insert', 'update', 'delete']) {
          expect(
            RegExp('create\\s+policy[^;]*on\\s+public\\.$table\\s+for\\s+$op')
                .hasMatch(sql),
            isTrue,
            reason: 'Missing $op policy on $table',
          );
        }
      }
    });

    test('CHECK constraints match Dart enum .id values', () {
      for (final g in Gender.values) {
        expect(sql, contains("'${g.id}'"));
      }
      for (final e in ExperienceLevel.values) {
        expect(sql, contains("'${e.id}'"));
      }
      for (final p in TrainingPurpose.values) {
        expect(sql, contains("'${p.id}'"));
      }
      for (final c in WorkoutDurationCourse.values) {
        expect(sql, contains("'${c.id}'"));
      }
      for (final c in WorkoutCondition.values) {
        expect(sql, contains("'${c.id}'"));
      }
      for (final t in TimeSlot.values) {
        expect(sql, contains("'${t.id}'"));
      }
      for (final f in WorkoutFeedback.values) {
        expect(sql, contains("'${f.id}'"));
      }
    });
  });

  group('R1 & R4 static hygiene across M3 files', () {
    test('lib/config and lib/services contain zero hardcoded Supabase URLs, JWTs, or prohibited R1 symbols', () {
      final files = <File>[
        ...Directory('lib/config')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
        ...Directory('lib/services')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      ];
      expect(files, isNotEmpty);

      final jwtPattern = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}');
      final supabaseUrlPattern = RegExp(
        r'https://[a-z0-9-]+\.supabase\.co',
        caseSensitive: false,
      );
      final gymAiPattern = RegExp(r'Gym\s*AI', caseSensitive: false);
      const prohibited = <String>[
        'flutter_tts',
        'audio_session',
        'button_controll_test',
        'TtsService',
        'api.openai.com',
        'api.anthropic.com',
        'generativelanguage.googleapis.com',
      ];

      for (final file in files) {
        final content = file.readAsStringSync();
        expect(jwtPattern.hasMatch(content), isFalse, reason: file.path);
        expect(supabaseUrlPattern.hasMatch(content), isFalse, reason: file.path);
        expect(gymAiPattern.hasMatch(content), isFalse, reason: file.path);
        for (final symbol in prohibited) {
          expect(content.contains(symbol), isFalse, reason: '${file.path}: $symbol');
        }
      }
    });
  });
}
