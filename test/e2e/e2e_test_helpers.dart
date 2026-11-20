import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/app.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/state/app_state.dart';
import 'package:noukin/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// 1. Deterministic Clocks & TimeSlot Boundaries
// =============================================================================

/// Representative morning clock (08:00 -> TimeSlot.morning).
final DateTime kClockMorning0800 = DateTime(2026, 11, 19, 8, 0, 0);

/// Representative daytime clock (13:00 -> TimeSlot.daytime).
final DateTime kClockDaytime1300 = DateTime(2026, 11, 19, 13, 0, 0);

/// Representative evening clock (18:00 -> TimeSlot.evening).
final DateTime kClockEvening1800 = DateTime(2026, 11, 19, 18, 0, 0);

/// Representative night clock (22:30 -> TimeSlot.night).
final DateTime kClockNight2230 = DateTime(2026, 11, 19, 22, 30, 0);

/// Exact TimeSlot boundary timestamps (`00:00:00` .. `23:59:59`).
final DateTime kClockBoundary0000 = DateTime(2026, 11, 19, 0, 0, 0);
final DateTime kClockBoundary045959 = DateTime(2026, 11, 19, 4, 59, 59);
final DateTime kClockBoundary0500 = DateTime(2026, 11, 19, 5, 0, 0);
final DateTime kClockBoundary115959 = DateTime(2026, 11, 19, 11, 59, 59);
final DateTime kClockBoundary1200 = DateTime(2026, 11, 19, 12, 0, 0);
final DateTime kClockBoundary145959 = DateTime(2026, 11, 19, 14, 59, 59);
final DateTime kClockBoundary1500 = DateTime(2026, 11, 19, 15, 0, 0);
final DateTime kClockBoundary205959 = DateTime(2026, 11, 19, 20, 59, 59);
final DateTime kClockBoundary2100 = DateTime(2026, 11, 19, 21, 0, 0);
final DateTime kClockBoundary235959 = DateTime(2026, 11, 19, 23, 59, 59);

/// Returns a deterministic clock callback returning [fixed].
DateTime Function() fixedClock(DateTime fixed) => () => fixed;

/// Mutable deterministic clock for multi-day E2E progression journeys.
class MutableTestClock {
  DateTime current;

  MutableTestClock(this.current);

  DateTime call() => current;

  void advanceDays(int days) {
    current = current.add(Duration(days: days));
  }
}

// =============================================================================
// 2. Spec-Derived Oracle Constants (from spec_master_data.md / HTML Simulator)
// =============================================================================

/// Authoritative expected muscle spec entry for opaque-box parity assertions.
class ExpectedMuscleSpec {
  final String id;
  final String name;
  final MuscleGroup group;
  final MuscleTimeCategory timeCat;
  final int recoveryDays;
  final Map<TrainingPurpose, int> priorities;

  const ExpectedMuscleSpec({
    required this.id,
    required this.name,
    required this.group,
    required this.timeCat,
    required this.recoveryDays,
    required this.priorities,
  });
}

/// Authoritative expected machine spec entry for opaque-box parity assertions.
class ExpectedMachineSpec {
  final String id;
  final String name;
  final MuscleGroup category;
  final double baseWeight;
  final double bwFactor;
  final int baseReps;
  final int defaultSessionsSinceUsed;
  final bool isIsolationOrCore;
  final List<String> primaryMuscleIds;
  final List<String> synergistMuscleIds;

  const ExpectedMachineSpec({
    required this.id,
    required this.name,
    required this.category,
    required this.baseWeight,
    required this.bwFactor,
    required this.baseReps,
    required this.defaultSessionsSinceUsed,
    required this.isIsolationOrCore,
    required this.primaryMuscleIds,
    required this.synergistMuscleIds,
  });
}

Map<TrainingPurpose, int> _p(
  int male,
  int female,
  int health,
  int diet,
  int tennis,
  int windsurfing,
) => <TrainingPurpose, int>{
  TrainingPurpose.bodyMakeMale: male,
  TrainingPurpose.bodyMakeFemale: female,
  TrainingPurpose.health: health,
  TrainingPurpose.diet: diet,
  TrainingPurpose.tennis: tennis,
  TrainingPurpose.windsurfing: windsurfing,
};

/// All 54 authoritative muscle definitions (`m0`..`m53`) from `spec_master_data.md`.
final List<ExpectedMuscleSpec> kExpectedMuscleSpecs = <ExpectedMuscleSpec>[
  ExpectedMuscleSpec(
    id: 'm0',
    name: '大腿四頭筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.nightAvoid,
    recoveryDays: 3,
    priorities: _p(18, 10, 18, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm1',
    name: 'ハムストリングス',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.nightAvoid,
    recoveryDays: 3,
    priorities: _p(18, 18, 18, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm2',
    name: '大臀筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.nightAvoid,
    recoveryDays: 3,
    priorities: _p(18, 18, 18, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm3',
    name: '大胸筋（全体・中部）',
    group: MuscleGroup.chest,
    timeCat: MuscleTimeCategory.nightAvoid,
    recoveryDays: 3,
    priorities: _p(18, 10, 14, 18, 14, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm4',
    name: '広背筋',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.nightAvoid,
    recoveryDays: 3,
    priorities: _p(18, 18, 14, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm5',
    name: '中臀筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.eveningRec,
    recoveryDays: 2,
    priorities: _p(10, 18, 14, 14, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm6',
    name: '僧帽筋（中部・下部）',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.eveningRec,
    recoveryDays: 2,
    priorities: _p(14, 14, 14, 14, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm7',
    name: '腹直筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 2,
    priorities: _p(18, 14, 18, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm8',
    name: '腹横筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 2,
    priorities: _p(14, 18, 18, 18, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm9',
    name: '脊柱起立筋群',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 3,
    priorities: _p(14, 18, 18, 18, 14, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm10',
    name: '腸腰筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 2,
    priorities: _p(10, 14, 18, 14, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm11',
    name: '上腕二頭筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 2,
    priorities: _p(14, 10, 10, 10, 10, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm12',
    name: '上腕三頭筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.morningRec,
    recoveryDays: 2,
    priorities: _p(14, 14, 10, 14, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm13',
    name: '大腿直筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 3,
    priorities: _p(10, 10, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm14',
    name: '内転筋群',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 3,
    priorities: _p(10, 14, 14, 14, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm15',
    name: '薄筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm16',
    name: '下腿三頭筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 3,
    priorities: _p(10, 10, 18, 14, 18, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm17',
    name: '腓腹筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 3,
    priorities: _p(10, 10, 10, 10, 10, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm18',
    name: '前脛骨筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 14, 10, 10, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm19',
    name: '足底筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm20',
    name: '長母趾屈筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm21',
    name: '長趾屈筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm22',
    name: '後脛骨筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm23',
    name: '腓骨筋（長・短腓骨筋）',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm24',
    name: '縫工筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm25',
    name: '膝窩筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm26',
    name: '小臀筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm27',
    name: '大腿筋膜張筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm28',
    name: '梨状筋',
    group: MuscleGroup.legsGlutes,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm29',
    name: '大胸筋（上部・鎖骨部）',
    group: MuscleGroup.chest,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(18, 14, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm30',
    name: '大胸筋（下部・腹部）',
    group: MuscleGroup.chest,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 0, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm31',
    name: '小胸筋',
    group: MuscleGroup.chest,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm32',
    name: '烏口腕筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm33',
    name: '前鋸筋',
    group: MuscleGroup.chest,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm34',
    name: '三角筋前部',
    group: MuscleGroup.shoulders,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(14, 10, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm35',
    name: '三角筋中部',
    group: MuscleGroup.shoulders,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(18, 14, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm36',
    name: '三角筋後部',
    group: MuscleGroup.shoulders,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(14, 14, 10, 10, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm37',
    name: '棘上筋',
    group: MuscleGroup.shoulders,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm38',
    name: '棘下筋',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 14, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm39',
    name: '小円筋',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 14, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm40',
    name: '大円筋',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(14, 10, 10, 10, 10, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm41',
    name: '僧帽筋（上部）',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 0, 10, 10, 10, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm42',
    name: '菱形筋',
    group: MuscleGroup.back,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(14, 14, 14, 14, 14, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm43',
    name: '上腕筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 10, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm44',
    name: '腕橈骨筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 14, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm45',
    name: '肘筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm46',
    name: '円回内筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 14, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm47',
    name: '橈側手根屈筋',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 14, 10),
  ),
  ExpectedMuscleSpec(
    id: 'm48',
    name: '手関節屈筋群',
    group: MuscleGroup.arms,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 14, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm49',
    name: '外腹斜筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 14, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm50',
    name: '内腹斜筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 14, 18, 18),
  ),
  ExpectedMuscleSpec(
    id: 'm51',
    name: '錐体筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(0, 0, 0, 0, 0, 0),
  ),
  ExpectedMuscleSpec(
    id: 'm52',
    name: '腰方形筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 10, 10, 10, 14),
  ),
  ExpectedMuscleSpec(
    id: 'm53',
    name: '多裂筋',
    group: MuscleGroup.core,
    timeCat: MuscleTimeCategory.other,
    recoveryDays: 2,
    priorities: _p(10, 10, 14, 10, 10, 14),
  ),
];

/// Lookup map from muscle ID (`'m0'`..`'m53'`) to [ExpectedMuscleSpec].
final Map<String, ExpectedMuscleSpec> kExpectedMuscleSpecById =
    <String, ExpectedMuscleSpec>{
      for (final spec in kExpectedMuscleSpecs) spec.id: spec,
    };

/// Lookup map from purpose to `{muscleId: priorityP}` for all 54 muscles.
final Map<TrainingPurpose, Map<String, int>> kExpectedPurposePriorities =
    <TrainingPurpose, Map<String, int>>{
      for (final purpose in TrainingPurpose.values)
        purpose: <String, int>{
          for (final spec in kExpectedMuscleSpecs)
            spec.id: spec.priorities[purpose]!,
        },
    };

/// 10 quick-injury muscle IDs (`MasterData.quickInjuryMuscleIds`).
const List<String> kQuickInjuryMuscleIds = <String>[
  'm34', // 三角筋前部
  'm35', // 三角筋中部
  'm3', // 大胸筋（全体・中部）
  'm4', // 広背筋
  'm9', // 脊柱起立筋群
  'm0', // 大腿四頭筋
  'm1', // ハムストリングス
  'm2', // 大臀筋
  'm11', // 上腕二頭筋
  'm12', // 上腕三頭筋
];

/// 9 high-volume / `too_hard` +1 `R_i` extend muscle IDs (`MasterData.highVolumeExtendMuscleIds`).
const List<String> kHighVolumeExtendMuscleIds = <String>[
  'm29', // 大胸筋（上部・鎖骨部）
  'm30', // 大胸筋（下部・腹部）
  'm34', // 三角筋前部
  'm35', // 三角筋中部
  'm36', // 三角筋後部
  'm40', // 大円筋
  'm41', // 僧帽筋（上部）
  'm6', // 僧帽筋（中部・下部）
  'm42', // 菱形筋
];

/// 8 extended night-avoid muscle IDs (`MasterData.nightAvoidMuscleIds`).
const List<String> kNightAvoidExtendedMuscleIds = <String>[
  'm0',
  'm1',
  'm2',
  'm3',
  'm4',
  'm9',
  'm29',
  'm30',
];

/// Expected age-bracket weight coefficients (`MasterData.ageCoefficients`).
const Map<String, double> kExpectedAgeCoefficients = <String, double>{
  'under_20': 0.95,
  '20_30': 1.00,
  '40s': 0.90,
  '50s': 0.80,
  '60_plus': 0.65,
};

/// All 29 authoritative machine definitions (`mac1`..`mac29`) from `spec_master_data.md`.
const List<ExpectedMachineSpec> kExpectedMachineSpecs = <ExpectedMachineSpec>[
  ExpectedMachineSpec(
    id: 'mac1',
    name: 'レッグプレス',
    category: MuscleGroup.legsGlutes,
    baseWeight: 85.0,
    bwFactor: 1.25,
    baseReps: 10,
    defaultSessionsSinceUsed: 4,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m0', 'm2', 'm13'],
    synergistMuscleIds: <String>['m1', 'm14', 'm16', 'm17'],
  ),
  ExpectedMachineSpec(
    id: 'mac2',
    name: 'ハックスクワット',
    category: MuscleGroup.legsGlutes,
    baseWeight: 60.0,
    bwFactor: 0.9,
    baseReps: 10,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m0', 'm2'],
    synergistMuscleIds: <String>['m1', 'm14', 'm16'],
  ),
  ExpectedMachineSpec(
    id: 'mac3',
    name: 'ペンデュラムスクワット',
    category: MuscleGroup.legsGlutes,
    baseWeight: 40.0,
    bwFactor: 0.65,
    baseReps: 10,
    defaultSessionsSinceUsed: 2,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m0', 'm2'],
    synergistMuscleIds: <String>['m1', 'm5', 'm14', 'm16'],
  ),
  ExpectedMachineSpec(
    id: 'mac4',
    name: 'ベルトスクワット',
    category: MuscleGroup.legsGlutes,
    baseWeight: 60.0,
    bwFactor: 0.9,
    baseReps: 10,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m0', 'm2'],
    synergistMuscleIds: <String>['m1', 'm14', 'm16'],
  ),
  ExpectedMachineSpec(
    id: 'mac5',
    name: 'レッグエクステンション',
    category: MuscleGroup.legsGlutes,
    baseWeight: 45.0,
    bwFactor: 0.65,
    baseReps: 12,
    defaultSessionsSinceUsed: 9,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m0', 'm13'],
    synergistMuscleIds: <String>['m18'],
  ),
  ExpectedMachineSpec(
    id: 'mac6',
    name: 'レッグカール',
    category: MuscleGroup.legsGlutes,
    baseWeight: 40.0,
    bwFactor: 0.55,
    baseReps: 12,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m1'],
    synergistMuscleIds: <String>['m15', 'm17', 'm24', 'm25'],
  ),
  ExpectedMachineSpec(
    id: 'mac7',
    name: 'アブダクション／アダクション',
    category: MuscleGroup.legsGlutes,
    baseWeight: 45.0,
    bwFactor: 0.65,
    baseReps: 12,
    defaultSessionsSinceUsed: 2,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m2', 'm5', 'm14', 'm27'],
    synergistMuscleIds: <String>['m15', 'm24', 'm26', 'm28'],
  ),
  ExpectedMachineSpec(
    id: 'mac8',
    name: 'グルート／ヒップスラストマシン',
    category: MuscleGroup.legsGlutes,
    baseWeight: 70.0,
    bwFactor: 1.0,
    baseReps: 10,
    defaultSessionsSinceUsed: 3,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m2'],
    synergistMuscleIds: <String>['m0', 'm1', 'm5', 'm9', 'm26'],
  ),
  ExpectedMachineSpec(
    id: 'mac9',
    name: 'マルチヒップマシン',
    category: MuscleGroup.legsGlutes,
    baseWeight: 35.0,
    bwFactor: 0.5,
    baseReps: 12,
    defaultSessionsSinceUsed: 2,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m2', 'm5', 'm10', 'm14'],
    synergistMuscleIds: <String>['m1', 'm13', 'm26'],
  ),
  ExpectedMachineSpec(
    id: 'mac10',
    name: 'カーフレイズ／カーフプレス',
    category: MuscleGroup.legsGlutes,
    baseWeight: 60.0,
    bwFactor: 0.9,
    baseReps: 15,
    defaultSessionsSinceUsed: 7,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m16', 'm17'],
    synergistMuscleIds: <String>['m19', 'm20', 'm21', 'm22', 'm23'],
  ),
  ExpectedMachineSpec(
    id: 'mac11',
    name: 'チェストプレス（フラット／ヴァーティカル）',
    category: MuscleGroup.chest,
    baseWeight: 50.0,
    bwFactor: 0.5,
    baseReps: 10,
    defaultSessionsSinceUsed: 4,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m3'],
    synergistMuscleIds: <String>['m12', 'm32', 'm33', 'm34'],
  ),
  ExpectedMachineSpec(
    id: 'mac12',
    name: 'インクラインチェストプレス',
    category: MuscleGroup.chest,
    baseWeight: 45.0,
    bwFactor: 0.45,
    baseReps: 10,
    defaultSessionsSinceUsed: 3,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m29'],
    synergistMuscleIds: <String>['m12', 'm33', 'm34'],
  ),
  ExpectedMachineSpec(
    id: 'mac13',
    name: 'デクラインチェストプレス／ワイドチェスト',
    category: MuscleGroup.chest,
    baseWeight: 50.0,
    bwFactor: 0.5,
    baseReps: 10,
    defaultSessionsSinceUsed: 5,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m30'],
    synergistMuscleIds: <String>['m4', 'm12', 'm34'],
  ),
  ExpectedMachineSpec(
    id: 'mac14',
    name: 'ペックフライ／バタフライ（ペックデック）',
    category: MuscleGroup.chest,
    baseWeight: 40.0,
    bwFactor: 0.4,
    baseReps: 12,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m3'],
    synergistMuscleIds: <String>['m31', 'm32', 'm33', 'm34'],
  ),
  ExpectedMachineSpec(
    id: 'mac15',
    name: 'シーテッドディップ',
    category: MuscleGroup.chest,
    baseWeight: 55.0,
    bwFactor: 0.65,
    baseReps: 10,
    defaultSessionsSinceUsed: 2,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m12', 'm30'],
    synergistMuscleIds: <String>['m4', 'm31', 'm34', 'm42'],
  ),
  ExpectedMachineSpec(
    id: 'mac16',
    name: 'ラットプルダウン',
    category: MuscleGroup.back,
    baseWeight: 45.0,
    bwFactor: 0.6,
    baseReps: 10,
    defaultSessionsSinceUsed: 4,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m4', 'm40'],
    synergistMuscleIds: <String>[
      'm6',
      'm11',
      'm33',
      'm36',
      'm38',
      'm39',
      'm42',
      'm43',
      'm44',
    ],
  ),
  ExpectedMachineSpec(
    id: 'mac17',
    name: 'シーテッドロー／ミッドロウ',
    category: MuscleGroup.back,
    baseWeight: 45.0,
    bwFactor: 0.6,
    baseReps: 10,
    defaultSessionsSinceUsed: 3,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m4', 'm6', 'm42'],
    synergistMuscleIds: <String>['m9', 'm11', 'm36', 'm40', 'm43', 'm44'],
  ),
  ExpectedMachineSpec(
    id: 'mac18',
    name: 'アイソラテラル・ロー／ローロー／ハイロー',
    category: MuscleGroup.back,
    baseWeight: 45.0,
    bwFactor: 0.6,
    baseReps: 10,
    defaultSessionsSinceUsed: 2,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m4', 'm6', 'm42'],
    synergistMuscleIds: <String>[
      'm11',
      'm36',
      'm38',
      'm39',
      'm40',
      'm41',
      'm44',
    ],
  ),
  ExpectedMachineSpec(
    id: 'mac19',
    name: 'プルオーバーマシン',
    category: MuscleGroup.back,
    baseWeight: 40.0,
    bwFactor: 0.5,
    baseReps: 12,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m4', 'm30'],
    synergistMuscleIds: <String>['m12', 'm31', 'm33', 'm40', 'm42'],
  ),
  ExpectedMachineSpec(
    id: 'mac20',
    name: 'チェストサポート式Tバーロウ',
    category: MuscleGroup.back,
    baseWeight: 40.0,
    bwFactor: 0.55,
    baseReps: 10,
    defaultSessionsSinceUsed: 7,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m4', 'm6', 'm42'],
    synergistMuscleIds: <String>[
      'm11',
      'm36',
      'm38',
      'm39',
      'm40',
      'm41',
      'm44',
    ],
  ),
  ExpectedMachineSpec(
    id: 'mac21',
    name: 'ショルダープレス／オーバーヘッドプレス',
    category: MuscleGroup.shoulders,
    baseWeight: 30.0,
    bwFactor: 0.35,
    baseReps: 10,
    defaultSessionsSinceUsed: 3,
    isIsolationOrCore: false,
    primaryMuscleIds: <String>['m34', 'm35'],
    synergistMuscleIds: <String>['m6', 'm12', 'm29', 'm33', 'm37', 'm41'],
  ),
  ExpectedMachineSpec(
    id: 'mac22',
    name: 'リアデルト（ペックフライ・リアデルト兼用機）',
    category: MuscleGroup.shoulders,
    baseWeight: 30.0,
    bwFactor: 0.35,
    baseReps: 12,
    defaultSessionsSinceUsed: 5,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m36'],
    synergistMuscleIds: <String>['m6', 'm38', 'm39', 'm40', 'm42'],
  ),
  ExpectedMachineSpec(
    id: 'mac23',
    name: 'サイドレイズマシン（ラテラルレイズマシン）',
    category: MuscleGroup.shoulders,
    baseWeight: 20.0,
    bwFactor: 0.25,
    baseReps: 12,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m35'],
    synergistMuscleIds: <String>['m33', 'm37', 'm41'],
  ),
  ExpectedMachineSpec(
    id: 'mac24',
    name: 'バイセップスカールマシン（アームカールマシン）',
    category: MuscleGroup.arms,
    baseWeight: 25.0,
    bwFactor: 0.3,
    baseReps: 12,
    defaultSessionsSinceUsed: 4,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m11', 'm43'],
    synergistMuscleIds: <String>['m44', 'm46', 'm47'],
  ),
  ExpectedMachineSpec(
    id: 'mac25',
    name: 'プリーチャーカールマシン',
    category: MuscleGroup.arms,
    baseWeight: 25.0,
    bwFactor: 0.3,
    baseReps: 12,
    defaultSessionsSinceUsed: 6,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m11', 'm43'],
    synergistMuscleIds: <String>['m44', 'm46'],
  ),
  ExpectedMachineSpec(
    id: 'mac26',
    name: 'トライセプスプレスマシン／エクステンションマシン',
    category: MuscleGroup.arms,
    baseWeight: 30.0,
    bwFactor: 0.35,
    baseReps: 12,
    defaultSessionsSinceUsed: 5,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m12'],
    synergistMuscleIds: <String>['m45', 'm48'],
  ),
  ExpectedMachineSpec(
    id: 'mac27',
    name: 'アブドミナルクランチマシン',
    category: MuscleGroup.core,
    baseWeight: 35.0,
    bwFactor: 0.45,
    baseReps: 15,
    defaultSessionsSinceUsed: 3,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m7'],
    synergistMuscleIds: <String>['m49', 'm50', 'm51'],
  ),
  ExpectedMachineSpec(
    id: 'mac28',
    name: 'ロータリートルソー',
    category: MuscleGroup.core,
    baseWeight: 30.0,
    bwFactor: 0.4,
    baseReps: 15,
    defaultSessionsSinceUsed: 5,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m49', 'm50'],
    synergistMuscleIds: <String>['m7', 'm8', 'm9', 'm10', 'm52'],
  ),
  ExpectedMachineSpec(
    id: 'mac29',
    name: 'バックエクステンションマシン／ロウバックマシン',
    category: MuscleGroup.core,
    baseWeight: 40.0,
    bwFactor: 0.55,
    baseReps: 12,
    defaultSessionsSinceUsed: 4,
    isIsolationOrCore: true,
    primaryMuscleIds: <String>['m9'],
    synergistMuscleIds: <String>['m1', 'm2', 'm52', 'm53'],
  ),
];

/// Lookup map from machine ID (`'mac1'`..`'mac29'`) to [ExpectedMachineSpec].
final Map<String, ExpectedMachineSpec> kExpectedMachineSpecById =
    <String, ExpectedMachineSpec>{
      for (final m in kExpectedMachineSpecs) m.id: m,
    };

/// Default `sessionsSinceUsed` offsets keyed by `'mac1'`..`'mac29'`.
final Map<String, int> kExpectedDefaultMachineOffsets = <String, int>{
  for (final m in kExpectedMachineSpecs) m.id: m.defaultSessionsSinceUsed,
};

/// IDs of the 14 isolation/core machines per HTML `isIsolationOrCoreMachine`.
final Set<String> kExpectedIsolationOrCoreMachineIds = <String>{
  for (final m in kExpectedMachineSpecs)
    if (m.isIsolationOrCore) m.id,
};

/// Rounds [value] to 1 decimal place (half away from zero for positive values).
double oracleRound1(double value) => double.parse(value.toStringAsFixed(1));

/// Rounds [value] to nearest 2.5 kg increment with a 2.5 kg minimum floor.
double oracleRoundTo25(double value) =>
    math.max(2.5, (value / 2.5).round() * 2.5);

// =============================================================================
// 3. Spec-Derived Fixture Builders
// =============================================================================

/// Builds a fresh [UserProfile] fixture for tests.
///
/// Defaults [purpose] to [TrainingPurpose.bodyMakeFemale] when [gender] is
/// [Gender.female] and [purpose] is omitted, or [TrainingPurpose.bodyMakeMale]
/// otherwise.
UserProfile buildTestProfile({
  String id = 'local_user',
  Gender gender = Gender.male,
  int birthYear = 1995,
  ExperienceLevel experience = ExperienceLevel.beginner,
  double bodyWeightKg = 65.0,
  TrainingPurpose? purpose,
  bool isFirstTime = true,
  String? email,
}) {
  return UserProfile(
    id: id,
    gender: gender,
    birthYear: birthYear,
    experience: experience,
    bodyWeightKg: bodyWeightKg,
    purpose:
        purpose ??
        (gender == Gender.female
            ? TrainingPurpose.bodyMakeFemale
            : TrainingPurpose.bodyMakeMale),
    isFirstTime: isFirstTime,
    email: email,
  );
}

/// Builds all 54 [MuscleInputState] fixtures (`'m0'`..`'m53'`) using the
/// authoritative priority template for [purpose].
Map<String, MuscleInputState> buildDefaultMuscleStates(
  TrainingPurpose purpose, {
  Set<String> injuredIds = const <String>{},
  int blankDays = 4,
  double stimulationDays = 2.0,
  Map<String, MuscleInputState> overrides = const <String, MuscleInputState>{},
}) {
  final priorities = kExpectedPurposePriorities[purpose]!;
  final result = <String, MuscleInputState>{};
  for (final spec in kExpectedMuscleSpecs) {
    final override = overrides[spec.id];
    if (override != null) {
      result[spec.id] = override;
    } else {
      result[spec.id] = MuscleInputState(
        muscleId: spec.id,
        blankDays: blankDays,
        stimulationDays: stimulationDays,
        priorityP: priorities[spec.id]!,
        isInjured: injuredIds.contains(spec.id),
      );
    }
  }
  return result;
}

/// Builds all 29 [MachineHistoryEntry] fixtures (`'mac1'`..`'mac29'`) using
/// the authoritative default `sessionsSinceUsed` offsets.
Map<String, MachineHistoryEntry> buildDefaultMachineHistory({
  Map<String, MachineHistoryEntry> overrides =
      const <String, MachineHistoryEntry>{},
}) {
  final result = <String, MachineHistoryEntry>{};
  for (final spec in kExpectedMachineSpecs) {
    final override = overrides[spec.id];
    if (override != null) {
      result[spec.id] = override;
    } else {
      result[spec.id] = MachineHistoryEntry(
        machineId: spec.id,
        sessionsSinceUsed: spec.defaultSessionsSinceUsed,
      );
    }
  }
  return result;
}

// =============================================================================
// 4. Widget & App Harness Helpers
// =============================================================================

/// Contracted `NoukinApp` (from `lib/app.dart` per `PROJECT.md § Interface Contracts 6`):
/// `NoukinApp({super.key, AppState? appState, DateTime Function()? clock})`.
///
/// Clears/initializes mock `SharedPreferences`, sets the test viewport, mounts a
/// fresh [NoukinApp], and settles initial async hydration.
Future<void> pumpNoukinApp(
  WidgetTester tester, {
  DateTime Function()? clock,
  Map<String, Object>? initialPrefs,
  Size viewportSize = const Size(390, 844),
  AppState? appState,
}) async {
  SharedPreferences.setMockInitialValues(
    initialPrefs ?? const <String, Object>{},
  );
  await _mountNoukinApp(
    tester,
    clock: clock,
    viewportSize: viewportSize,
    appState: appState,
  );
}

/// Simulates a cold app restart WITHOUT resetting mock `SharedPreferences`.
Future<void> restartNoukinApp(
  WidgetTester tester, {
  DateTime Function()? clock,
  Size viewportSize = const Size(390, 844),
  AppState? appState,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await _mountNoukinApp(
    tester,
    clock: clock,
    viewportSize: viewportSize,
    appState: appState,
  );
}

Future<void> _mountNoukinApp(
  WidgetTester tester, {
  DateTime Function()? clock,
  required Size viewportSize,
  AppState? appState,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    NoukinApp(key: UniqueKey(), appState: appState, clock: clock),
  );
  await tester.pumpAndSettle();
}

const Map<String, ({String label, IconData icon})> _kNavTabFallbacks =
    <String, ({String label, IconData icon})>{
      'nav_tab_training': (label: 'トレーニング', icon: Icons.fitness_center),
      'nav_tab_custom': (label: 'カスタム', icon: Icons.tune),
      'nav_tab_settings': (label: '設定', icon: Icons.settings),
    };

/// Navigates to one of the 3 main tabs (`'nav_tab_training'`,
/// `'nav_tab_custom'`, `'nav_tab_settings'`).
Future<void> tapNavTab(WidgetTester tester, String tabKey) async {
  Finder target = find.byKey(Key(tabKey));
  if (target.evaluate().isEmpty) {
    final fallback = _kNavTabFallbacks[tabKey];
    if (fallback != null) {
      final navRoots = find.byWidgetPredicate(
        (w) => w is BottomNavigationBar || w is NavigationBar,
      );
      if (navRoots.evaluate().isNotEmpty) {
        final byLabel = find.descendant(
          of: navRoots,
          matching: find.textContaining(fallback.label),
        );
        final byIcon = find.descendant(
          of: navRoots,
          matching: find.byIcon(fallback.icon),
        );
        target = byLabel.evaluate().isNotEmpty ? byLabel.first : byIcon.first;
      }
    }
  } else {
    target = target.first;
  }

  expect(
    target,
    findsOneWidget,
    reason: 'Navigation tab "$tabKey" must exist and be uniquely tappable',
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

const Map<String, ({String up, String down})> _kCounterButtonKeys =
    <String, ({String up, String down})>{
      'card_weight': (up: 'btn_weight_up', down: 'btn_weight_down'),
      'card_reps': (up: 'btn_reps_up', down: 'btn_reps_down'),
      'card_sets': (up: 'btn_sets_up', down: 'btn_sets_down'),
    };

/// Taps the `+` ([increment] == true) or `-` ([increment] == false) button
/// inside a counter card keyed by [cardKey] (e.g. `'card_weight'`).
///
/// Checks both contracted button keys (`btn_weight_up`/`down`, `btn_reps_*`,
/// `btn_sets_*`) and icon descendants (`Icons.add`/`Icons.remove`) inside
/// [cardKey].
Future<void> tapCounterButton(
  WidgetTester tester,
  String cardKey, {
  required bool increment,
}) async {
  final cardFinder = find.byKey(Key(cardKey));
  expect(
    cardFinder,
    findsOneWidget,
    reason: 'Counter card "$cardKey" must be present',
  );

  final mappedKeys = _kCounterButtonKeys[cardKey];
  Finder buttonFinder = find.descendant(
    of: cardFinder,
    matching: find.byIcon(increment ? Icons.add : Icons.remove),
  );
  if (mappedKeys != null) {
    final keyFinder = find.descendant(
      of: cardFinder,
      matching: find.byKey(Key(increment ? mappedKeys.up : mappedKeys.down)),
    );
    if (keyFinder.evaluate().isNotEmpty) {
      buttonFinder = keyFinder;
    } else if (buttonFinder.evaluate().isEmpty) {
      buttonFinder = find.byKey(
        Key(increment ? mappedKeys.up : mappedKeys.down),
      );
    }
  }

  expect(
    buttonFinder,
    findsOneWidget,
    reason:
        'Counter card "$cardKey" must contain ${increment ? "increment" : "decrement"} button',
  );

  await tester.ensureVisible(buttonFinder);
  await tester.tap(buttonFinder);
  await tester.pump();
}

String _extractFinderText(WidgetTester tester, Finder root) {
  final widget = tester.widget(root.first);
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  final textWidgets = tester.widgetList<Text>(
    find.descendant(of: root.first, matching: find.byType(Text)),
  );
  return textWidgets
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty)
      .join(' ');
}

List<Finder> _resolveScrollableCandidates(
  WidgetTester tester, {
  Finder? explicitScrollable,
  String? preferredContainerKey,
}) {
  final seenElements = <Element>{};
  final candidates = <Finder>[];

  void addScrollableElement(Element element) {
    if (seenElements.add(element)) {
      candidates.add(find.byWidget(element.widget));
    }
  }

  void collectFromFinder(Finder source) {
    for (final element in source.evaluate()) {
      if (element.widget is Scrollable) {
        addScrollableElement(element);
      } else {
        final descendants = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Scrollable),
        );
        for (final desc in descendants.evaluate()) {
          addScrollableElement(desc);
        }
      }
    }
  }

  if (explicitScrollable != null && explicitScrollable.evaluate().isNotEmpty) {
    collectFromFinder(explicitScrollable);
  }
  if (preferredContainerKey != null) {
    final container = find.byKey(Key(preferredContainerKey));
    if (container.evaluate().isNotEmpty) {
      collectFromFinder(container);
    }
  }
  for (final element in find.byType(Scrollable).evaluate()) {
    addScrollableElement(element);
  }
  return candidates;
}

Future<void> _scrollToFinder(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  String? preferredContainerKey,
  double delta = 200.0,
  int maxScrolls = 60,
}) async {
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
    return;
  }

  final candidates = _resolveScrollableCandidates(
    tester,
    explicitScrollable: scrollable,
    preferredContainerKey: preferredContainerKey,
  );
  for (final candidate in candidates) {
    final candidateElement = candidate.evaluate().firstOrNull;
    if (candidateElement is StatefulElement &&
        candidateElement.state is ScrollableState) {
      final position = (candidateElement.state as ScrollableState).position;
      if (position.hasContentDimensions && position.maxScrollExtent <= 0) {
        continue;
      }
    }
    if (candidate.hitTestable().evaluate().isEmpty) {
      try {
        await tester.ensureVisible(candidate);
        await tester.pumpAndSettle();
      } catch (_) {
        // Ignore if candidate cannot be brought into view via ancestor.
      }
    }
    for (final step in <double>[delta, -delta]) {
      if (step == 0) {
        continue;
      }
      try {
        await tester.scrollUntilVisible(
          target,
          step,
          scrollable: candidate,
          maxScrolls: maxScrolls,
        );
        if (target.evaluate().isNotEmpty) {
          await tester.ensureVisible(target.first);
          await tester.pumpAndSettle();
          return;
        }
      } catch (_) {
        // Try opposite direction or next candidate Scrollable.
      }
    }
  }
}

/// Scrolls to the widget keyed by [targetKey], resolving actual [Scrollable]
/// widgets (via [preferredContainerKey] descendants if provided, else iterating
/// [Scrollable] widgets in the tree starting with `.first`).
Future<void> scrollToWidgetByKey(
  WidgetTester tester,
  String targetKey, {
  String? preferredContainerKey,
  double delta = 200.0,
}) async {
  final target = find.byKey(Key(targetKey));
  await _scrollToFinder(
    tester,
    target,
    preferredContainerKey: preferredContainerKey,
    delta: delta,
  );
  expect(
    target,
    findsAtLeastNWidgets(1),
    reason: 'Expected widget with Key("$targetKey") to be visible',
  );
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

/// Ensures [target] is scrolled into view (scrolling [scrollable] or active
/// [Scrollable]s if needed), taps it, and settles animations.
Future<void> scrollAndTap(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double delta = 200.0,
}) async {
  await _scrollToFinder(
    tester,
    target,
    scrollable: scrollable,
    delta: delta,
  );
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

/// Finds a widget by [Key(key)], scrolls it into view if necessary, taps it,
/// and calls `pumpAndSettle()`.
Future<void> tapKey(
  WidgetTester tester,
  String key, {
  Finder? scrollable,
  double delta = 200.0,
}) async {
  await scrollAndTap(
    tester,
    find.byKey(Key(key)),
    scrollable: scrollable,
    delta: delta,
  );
}

/// Selects an option containing [optionText] from a dropdown keyed by
/// [dropdownKey], scrolling inside the opened dropdown menu overlay if needed.
Future<void> selectDropdownOption(
  WidgetTester tester,
  String dropdownKey,
  String optionText,
) async {
  await scrollToWidgetByKey(tester, dropdownKey);
  final dropdownRoot = find.byKey(Key(dropdownKey));
  expect(
    dropdownRoot,
    findsAtLeastNWidgets(1),
    reason: 'Dropdown "$dropdownKey" must exist',
  );

  final dropdownDescendant = find.descendant(
    of: dropdownRoot.first,
    matching: find.byWidgetPredicate(
      (w) => w is DropdownButton || w is DropdownButtonFormField,
    ),
  );
  final rootWidget = tester.widget(dropdownRoot.first);
  final tapTarget =
      (rootWidget is DropdownButton ||
          rootWidget is DropdownButtonFormField ||
          dropdownDescendant.evaluate().isEmpty)
      ? dropdownRoot.first
      : dropdownDescendant.first;

  await tester.ensureVisible(tapTarget);
  await tester.tap(tapTarget);
  await tester.pumpAndSettle();

  final optionFinder = find.textContaining(optionText);
  final hitTestableOption = optionFinder.hitTestable();

  if (hitTestableOption.evaluate().isEmpty) {
    final scrollableElements = find
        .byType(Scrollable)
        .evaluate()
        .toList(growable: false);
    for (final element in scrollableElements.reversed) {
      final scrollableFinder = find.byWidget(element.widget);
      for (final delta in const <double>[180.0, -180.0]) {
        try {
          await tester.scrollUntilVisible(
            hitTestableOption,
            delta,
            scrollable: scrollableFinder,
            maxScrolls: 60,
          );
          if (hitTestableOption.evaluate().isNotEmpty) {
            break;
          }
        } catch (_) {
          // Try opposite direction or next scrollable.
        }
      }
      if (hitTestableOption.evaluate().isNotEmpty) {
        break;
      }
    }
  }

  if (optionFinder.evaluate().isEmpty) {
    final scrollableElements = find
        .byType(Scrollable)
        .evaluate()
        .toList(growable: false);
    for (final element in scrollableElements.reversed) {
      final scrollableFinder = find.byWidget(element.widget);
      for (final delta in const <double>[180.0, -180.0]) {
        try {
          await tester.scrollUntilVisible(
            optionFinder,
            delta,
            scrollable: scrollableFinder,
            maxScrolls: 60,
          );
          if (optionFinder.evaluate().isNotEmpty) {
            break;
          }
        } catch (_) {
          // Try opposite direction or next scrollable.
        }
      }
      if (optionFinder.evaluate().isNotEmpty) {
        break;
      }
    }
  }

  expect(
    optionFinder,
    findsAtLeastNWidgets(1),
    reason: 'Dropdown "$dropdownKey" option "$optionText" must appear',
  );
  await tester.ensureVisible(optionFinder.last);
  await tester.pumpAndSettle();

  final finalTarget = hitTestableOption.evaluate().isNotEmpty
      ? hitTestableOption.last
      : optionFinder.last;
  await tester.tap(finalTarget);
  await tester.pumpAndSettle();
}

/// Selects an option containing [optionText] inside a control keyed by
/// [containerKey], seamlessly supporting both `DropdownButton` /
/// `DropdownButtonFormField` and inline `ChoiceChip` / `SegmentedButton` /
/// `RadioListTile` / `InkWell` / `TextButton` groups.
Future<void> selectOptionInControl(
  WidgetTester tester,
  String containerKey,
  String optionText,
) async {
  await scrollToWidgetByKey(tester, containerKey);
  final container = find.byKey(Key(containerKey));
  expect(
    container,
    findsAtLeastNWidgets(1),
    reason: 'Control "$containerKey" must exist',
  );

  final containerWidget = tester.widget(container.first);
  final hasDropdownDescendant = find
      .descendant(
        of: container.first,
        matching: find.byWidgetPredicate(
          (w) => w is DropdownButton || w is DropdownButtonFormField,
        ),
      )
      .evaluate()
      .isNotEmpty;
  final isDropdown =
      containerWidget is DropdownButton ||
      containerWidget is DropdownButtonFormField ||
      hasDropdownDescendant;

  if (isDropdown) {
    await selectDropdownOption(tester, containerKey, optionText);
    return;
  }

  final inlineOption = find.descendant(
    of: container.first,
    matching: find.textContaining(optionText),
  );
  if (inlineOption.evaluate().isEmpty) {
    await _scrollToFinder(
      tester,
      inlineOption,
      preferredContainerKey: containerKey,
      delta: 180.0,
    );
  }
  expect(
    inlineOption,
    findsAtLeastNWidgets(1),
    reason: 'Control "$containerKey" must contain option "$optionText"',
  );
  await tester.ensureVisible(inlineOption.first);
  await tester.pumpAndSettle();
  await tester.tap(inlineOption.first);
  await tester.pumpAndSettle();
}

/// Advances one exercise on Screen A2 via `Key('btn_next_workout')`,
/// handling both direct `'次へ'` (1 tap) and `'開始' -> '次へ'` (2 taps).
Future<void> advanceToNextExercise(WidgetTester tester) async {
  final badgeFinder = find.byKey(const Key('exercise_progress_badge'));
  final beforeBadge = badgeFinder.evaluate().isNotEmpty
      ? _extractFinderText(tester, badgeFinder)
      : null;

  await tapKey(tester, 'btn_next_workout');

  final reachedA3 =
      find.byKey(const Key('btn_finish_workout')).evaluate().isNotEmpty ||
      find.byKey(const Key('feedback_just_right')).evaluate().isNotEmpty;
  if (reachedA3) {
    return;
  }

  if (beforeBadge != null && badgeFinder.evaluate().isNotEmpty) {
    final afterBadge = _extractFinderText(tester, badgeFinder);
    if (afterBadge == beforeBadge) {
      await tapKey(tester, 'btn_next_workout');
    }
  }
}

/// Walks through Screen A2 via `Key('btn_next_workout')` until Screen A3
/// (`btn_finish_workout` / `feedback_just_right`) appears, supporting both
/// `N` (`'次へ'`) and `N + 1` (`'開始' -> '次へ'`) tap counts.
///
/// Returns the ordered list of distinct `exercise_title` strings displayed.
Future<List<String>> advanceWorkoutToA3(
  WidgetTester tester, {
  required int expectedCount,
}) async {
  final titles = <String>[];
  final maxIterations = expectedCount + 2;
  var taps = 0;

  while (find.byKey(const Key('btn_finish_workout')).evaluate().isEmpty &&
      find.byKey(const Key('feedback_just_right')).evaluate().isEmpty &&
      taps < maxIterations) {
    final titleFinder = find.byKey(const Key('exercise_title'));
    if (titleFinder.evaluate().isNotEmpty) {
      final title = _extractFinderText(tester, titleFinder);
      if (title.isNotEmpty && (titles.isEmpty || titles.last != title)) {
        titles.add(title);
      }
    }
    await tapKey(tester, 'btn_next_workout');
    taps++;
  }

  expect(
    find.byKey(const Key('btn_finish_workout')),
    findsOneWidget,
    reason: 'Screen A3 btn_finish_workout should appear within $maxIterations taps',
  );
  expect(
    find.byKey(const Key('feedback_just_right')),
    findsOneWidget,
    reason: 'Screen A3 feedback_just_right should appear within $maxIterations taps',
  );
  expect(
    taps,
    greaterThanOrEqualTo(expectedCount),
    reason: 'Expected at least $expectedCount taps to complete $expectedCount exercises',
  );
  expect(
    taps,
    lessThanOrEqualTo(expectedCount + 1),
    reason:
        'Expected at most ${expectedCount + 1} taps (N or N+1 for 開始->次へ), got $taps',
  );
  return titles;
}

/// Enters [text] into a `TextField` / `TextFormField` keyed by [fieldKey].
Future<void> enterTextByKey(
  WidgetTester tester,
  String fieldKey,
  String text,
) async {
  await scrollToWidgetByKey(tester, fieldKey);
  final field = find.byKey(Key(fieldKey));
  expect(field, findsOneWidget, reason: 'Text field "$fieldKey" must exist');
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Asserts that no layout overflow or uncaught widget error occurred.
void expectNoRenderOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason:
        'Expected zero RenderFlex overflow / widget exceptions, got: $exception',
  );
  expect(find.byType(ErrorWidget), findsNothing);
}

Color? _resolveThemedButtonColor(
  WidgetTester tester,
  Finder buttonFinder, {
  required bool foreground,
}) {
  expect(buttonFinder, findsAtLeastNWidgets(1));
  final target = buttonFinder.first;
  final widget = tester.widget(target);
  final ctx = tester.element(target);

  WidgetStateProperty<Color?>? pickProp(ButtonStyle? style) =>
      foreground ? style?.foregroundColor : style?.backgroundColor;

  if (widget is ButtonStyleButton) {
    final inline = pickProp(widget.style)?.resolve(<WidgetState>{});
    if (inline != null) {
      return inline;
    }
    final theme = Theme.of(ctx);
    if (widget is ElevatedButton) {
      return pickProp(
        theme.elevatedButtonTheme.style,
      )?.resolve(<WidgetState>{});
    }
    if (widget is FilledButton) {
      return pickProp(theme.filledButtonTheme.style)?.resolve(<WidgetState>{});
    }
    if (widget is TextButton) {
      return pickProp(theme.textButtonTheme.style)?.resolve(<WidgetState>{});
    }
    if (widget is OutlinedButton) {
      return pickProp(
        theme.outlinedButtonTheme.style,
      )?.resolve(<WidgetState>{});
    }
  }
  return pickProp(
    Theme.of(ctx).elevatedButtonTheme.style,
  )?.resolve(<WidgetState>{});
}

/// Resolves the effective background color of a button matched by [buttonFinder],
/// checking inline `button.style` first and falling back to
/// `Theme.of(ctx).elevatedButtonTheme.style`.
Color? resolveEffectiveButtonBackgroundColor(
  WidgetTester tester,
  Finder buttonFinder,
) => _resolveThemedButtonColor(tester, buttonFinder, foreground: false);

/// Resolves the effective foreground color of a button matched by [buttonFinder],
/// checking inline `button.style` first and falling back to
/// `Theme.of(ctx).elevatedButtonTheme.style`.
Color? resolveEffectiveButtonForegroundColor(
  WidgetTester tester,
  Finder buttonFinder,
) => _resolveThemedButtonColor(tester, buttonFinder, foreground: true);

/// Resolves the effective surface color of a [Card] matched directly or as a
/// descendant of [cardFinder], checking inline `card.color` first and falling
/// back to `Theme.of(ctx).cardTheme.color`.
Color? resolveEffectiveCardColor(WidgetTester tester, Finder cardFinder) {
  expect(cardFinder, findsAtLeastNWidgets(1));
  final descendantCard = find.descendant(
    of: cardFinder.first,
    matching: find.byType(Card),
  );
  final target = tester.widgetList(cardFinder).any((w) => w is Card)
      ? cardFinder.first
      : (descendantCard.evaluate().isNotEmpty
            ? descendantCard.first
            : cardFinder.first);
  final widget = tester.widget(target);
  final ctx = tester.element(target);
  if (widget is Card) {
    return widget.color ?? Theme.of(ctx).cardTheme.color;
  }
  if (widget is Material) {
    return widget.color ?? Theme.of(ctx).cardTheme.color;
  }
  return Theme.of(ctx).cardTheme.color;
}

/// Verifies that the active [MaterialApp] (if present) and [Scaffold] use
/// dark theme with [AppColors.background] (`#121212`).
void expectDarkScaffoldTheme(WidgetTester tester) {
  final materialApps = find.byType(MaterialApp);
  if (materialApps.evaluate().isNotEmpty) {
    final materialApp = tester.widget<MaterialApp>(materialApps.first);
    expect(
      materialApp.themeMode == ThemeMode.dark ||
          materialApp.theme?.brightness == Brightness.dark,
      isTrue,
      reason:
          'MaterialApp must enable dark theme (themeMode == ThemeMode.dark or theme.brightness == Brightness.dark)',
    );
  }
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  final bg =
      scaffold.backgroundColor ??
      Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).scaffoldBackgroundColor;
  expect(bg, AppColors.background);
}

// =============================================================================
// 5. Offline Network Blocker (HttpOverrides)
// =============================================================================

/// Runs asynchronous [body] in a zone whose [HttpOverrides] blocks every
/// outbound HTTP client creation with a [StateError].
Future<T> runWithoutNetwork<T>(FutureOr<T> Function() body) async {
  try {
    return await HttpOverrides.runZoned<Future<T>>(
      () async => await body(),
      createHttpClient: (SecurityContext? context) {
        throw StateError('External network call prohibited by R1/R4');
      },
    );
  } finally {
    HttpOverrides.global = null;
  }
}

/// Runs synchronous [body] in a zone whose [HttpOverrides] blocks every
/// outbound HTTP client creation with a [StateError].
T runWithoutNetworkSync<T>(T Function() body) {
  return HttpOverrides.runZoned<T>(
    body,
    createHttpClient: (SecurityContext? context) {
      throw StateError('External network call prohibited by R1/R4');
    },
  );
}

// =============================================================================
// 6. Static Project Scanner Helpers (for R1 & R4 Compliance Tests)
// =============================================================================

/// Locates the project root directory containing `pubspec.yaml`.
Directory resolveProjectRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 10; i++) {
    final pubspec = File(
      '${dir.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (pubspec.existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError(
    'Unable to locate project root containing pubspec.yaml from ${Directory.current.path}',
  );
}

String _resolveRelativePath(String relativePath) {
  final root = resolveProjectRoot().path;
  final normalized = relativePath
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
  return '$root${Platform.pathSeparator}$normalized';
}

/// Returns whether a project file at [relativePath] exists.
bool projectFileExists(String relativePath) {
  return File(_resolveRelativePath(relativePath)).existsSync();
}

/// Reads a UTF-8 text file at [relativePath] relative to project root.
String readProjectFile(String relativePath) {
  final file = File(_resolveRelativePath(relativePath));
  if (!file.existsSync()) {
    throw FileSystemException('Project file not found', file.path);
  }
  return file.readAsStringSync();
}

/// Lists all files recursively under [relativeDir] matching [extension],
/// sorted deterministically by path. Returns an empty list if [relativeDir]
/// does not exist.
List<File> listProjectFiles(
  String relativeDir, {
  String extension = '.dart',
}) {
  final dir = Directory(_resolveRelativePath(relativeDir));
  if (!dir.existsSync()) {
    return const <File>[];
  }
  final files =
      dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where(
            (f) =>
                extension.isEmpty ||
                f.path.toLowerCase().endsWith(extension.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}
