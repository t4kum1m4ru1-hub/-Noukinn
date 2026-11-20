import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';

void main() {
  group('MasterData 54 Muscles Integrity', () {
    test('defines exactly 54 unique muscles in exact m0..m53 index order', () {
      expect(MasterData.muscles.length, 54);
      expect(MasterData.muscleById.length, 54);

      final seenNames = <String>{};
      for (var i = 0; i < 54; i++) {
        final m = MasterData.muscles[i];
        expect(m.id, 'm$i', reason: 'Index $i must match m$i');
        expect(m.name, isNotEmpty);
        expect(seenNames.add(m.name), isTrue, reason: 'Duplicate name ${m.name}');
        expect(MasterData.muscleById[m.id], m);
      }
    });

    test('matches exact MuscleGroup, MuscleTimeCategory, and recoveryDays counts', () {
      final groupCounts = <MuscleGroup, int>{};
      final timeCatCounts = <MuscleTimeCategory, int>{};
      final r3Ids = <String>{};

      for (final m in MasterData.muscles) {
        groupCounts[m.group] = (groupCounts[m.group] ?? 0) + 1;
        timeCatCounts[m.timeCat] = (timeCatCounts[m.timeCat] ?? 0) + 1;
        expect(m.recoveryDays, anyOf(2, 3));
        if (m.recoveryDays == 3) {
          r3Ids.add(m.id);
        }
      }

      expect(groupCounts, <MuscleGroup, int>{
        MuscleGroup.legsGlutes: 20,
        MuscleGroup.chest: 5,
        MuscleGroup.back: 7,
        MuscleGroup.shoulders: 4,
        MuscleGroup.arms: 9,
        MuscleGroup.core: 9,
      });

      expect(timeCatCounts, <MuscleTimeCategory, int>{
        MuscleTimeCategory.nightAvoid: 5,
        MuscleTimeCategory.eveningRec: 2,
        MuscleTimeCategory.morningRec: 6,
        MuscleTimeCategory.other: 41,
      });

      expect(r3Ids, <String>{
        'm0',
        'm1',
        'm2',
        'm3',
        'm4',
        'm9',
        'm13',
        'm14',
        'm16',
        'm17',
      });

      // Specific subtle timeCat checks: m9 is morningRec; m29 & m30 are other
      expect(MasterData.muscleById['m9']!.timeCat, MuscleTimeCategory.morningRec);
      expect(MasterData.muscleById['m29']!.timeCat, MuscleTimeCategory.other);
      expect(MasterData.muscleById['m30']!.timeCat, MuscleTimeCategory.other);
    });
  });

  group('MasterData 29 Machines Integrity', () {
    test('defines exactly 29 machines in exact mac1..mac29 index order', () {
      expect(MasterData.machines.length, 29);
      expect(MasterData.machineById.length, 29);

      for (var i = 0; i < 29; i++) {
        final mac = MasterData.machines[i];
        expect(mac.id, 'mac${i + 1}');
        expect(mac.name, isNotEmpty);
        expect(mac.baseWeight, greaterThan(0));
        expect(mac.bwFactor, greaterThan(0));
        expect(mac.baseReps, greaterThanOrEqualTo(10));
        expect(MasterData.machineById[mac.id], mac);
      }
    });

    test('matches exact categories, imageAssetPath, offsets, and isolation flags', () {
      final catCounts = <MuscleGroup, int>{};
      final isoIds = <String>{};
      final allCoveredMuscles = <String>{};

      for (final mac in MasterData.machines) {
        catCounts[mac.category] = (catCounts[mac.category] ?? 0) + 1;
        if (mac.isIsolationOrCore) {
          isoIds.add(mac.id);
        }

        expect(mac.primaryMuscleIds, isNotEmpty);
        expect(mac.synergistMuscleIds, isNotEmpty);

        final primarySet = mac.primaryMuscleIds.toSet();
        final synergistSet = mac.synergistMuscleIds.toSet();
        expect(primarySet.length, mac.primaryMuscleIds.length);
        expect(synergistSet.length, mac.synergistMuscleIds.length);
        expect(primarySet.intersection(synergistSet), isEmpty);

        for (final id in <String>[
          ...mac.primaryMuscleIds,
          ...mac.synergistMuscleIds,
        ]) {
          expect(MasterData.muscleById.containsKey(id), isTrue, reason: '$id invalid');
          allCoveredMuscles.add(id);
        }
      }

      expect(catCounts, <MuscleGroup, int>{
        MuscleGroup.legsGlutes: 10,
        MuscleGroup.chest: 5,
        MuscleGroup.back: 5,
        MuscleGroup.shoulders: 3,
        MuscleGroup.arms: 3,
        MuscleGroup.core: 3,
      });

      expect(isoIds, <String>{
        'mac5',
        'mac6',
        'mac10',
        'mac12',
        'mac13',
        'mac14',
        'mac22',
        'mac23',
        'mac24',
        'mac25',
        'mac26',
        'mac27',
        'mac28',
        'mac29',
      });

      // All 54 muscles must be covered by at least one machine
      expect(allCoveredMuscles.length, 54);

      // Image asset paths
      expect(
        MasterData.machineById['mac1']!.imageAssetPath,
        'assets/images/workout/leg_press.avif',
      );
      expect(
        MasterData.machineById['mac11']!.imageAssetPath,
        'assets/images/workout/bench_press.avif',
      );
      for (final mac in MasterData.machines) {
        if (mac.id != 'mac1' && mac.id != 'mac11') {
          expect(mac.imageAssetPath, isNull, reason: '${mac.id} should be null');
        }
      }

      // Default offsets from HTML customOffsets
      const expectedOffsets = <String, int>{
        'mac1': 4,
        'mac2': 6,
        'mac3': 2,
        'mac4': 6,
        'mac5': 9,
        'mac6': 6,
        'mac7': 2,
        'mac8': 3,
        'mac9': 2,
        'mac10': 7,
        'mac11': 4,
        'mac12': 3,
        'mac13': 5,
        'mac14': 6,
        'mac15': 2,
        'mac16': 4,
        'mac17': 3,
        'mac18': 2,
        'mac19': 6,
        'mac20': 7,
        'mac21': 3,
        'mac22': 5,
        'mac23': 6,
        'mac24': 4,
        'mac25': 6,
        'mac26': 5,
        'mac27': 3,
        'mac28': 5,
        'mac29': 4,
      };
      for (final entry in expectedOffsets.entries) {
        expect(
          MasterData.machineById[entry.key]!.defaultSessionsSinceUsed,
          entry.value,
        );
      }
    });
  });

  group('MasterData Purpose Templates, Sets & Default Factories', () {
    test('defines complete 6x54 purpose priorities with valid tier integers', () {
      expect(MasterData.purposePriorities.length, 6);
      expect(TrainingPurpose.windsurfing.label, 'ウィンドサーフィン');

      for (final purpose in TrainingPurpose.values) {
        final map = MasterData.purposePriorities[purpose]!;
        expect(map.length, 54);
        for (var i = 0; i < 54; i++) {
          final p = map['m$i']!;
          expect(p, anyOf(0, 10, 14, 18));
        }
        expect(map['m27'], 0, reason: 'm27 is 0 across all 6 templates');
      }

      // Spot-check key purpose differences
      expect(
        MasterData.purposePriorities[TrainingPurpose.bodyMakeMale]!['m3'],
        18,
      );
      expect(
        MasterData.purposePriorities[TrainingPurpose.bodyMakeFemale]!['m3'],
        10,
      );
      expect(
        MasterData.purposePriorities[TrainingPurpose.bodyMakeFemale]!['m5'],
        18,
      );
      expect(
        MasterData.purposePriorities[TrainingPurpose.tennis]!['m49'],
        18,
      );
      expect(
        MasterData.purposePriorities[TrainingPurpose.windsurfing]!['m48'],
        18,
      );
      expect(
        MasterData.purposePriorities[TrainingPurpose.windsurfing]!['m11'],
        18,
      );
    });

    test('defines exact quickInjury, highVolumeExtend, nightAvoid, and ageCoefficients', () {
      expect(MasterData.quickInjuryMuscleIds, <String>{
        'm34',
        'm35',
        'm3',
        'm4',
        'm9',
        'm0',
        'm1',
        'm2',
        'm11',
        'm12',
      });
      expect(MasterData.highVolumeExtendMuscleIds, <String>{
        'm29',
        'm30',
        'm34',
        'm35',
        'm36',
        'm40',
        'm41',
        'm6',
        'm42',
      });
      expect(MasterData.nightAvoidMuscleIds, <String>{
        'm0',
        'm1',
        'm2',
        'm3',
        'm4',
        'm9',
        'm29',
        'm30',
      });
      expect(MasterData.ageCoefficients, <String, double>{
        'under_20': 0.95,
        '20_30': 1.00,
        '40s': 0.90,
        '50s': 0.80,
        '60_plus': 0.65,
      });
    });

    test('defaultMuscleStates and defaultMachineHistory return fresh mutable maps', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.diet);
      expect(states.length, 54);
      expect(states['m0']!.blankDays, 4);
      expect(states['m0']!.stimulationDays, 2.0);
      expect(states['m0']!.priorityP, 18);
      expect(states['m0']!.isInjured, isFalse);

      // Must be mutable
      states['m0'] = states['m0']!.copyWith(blankDays: 10);
      expect(states['m0']!.blankDays, 10);

      final history = MasterData.defaultMachineHistory();
      expect(history.length, 29);
      expect(history['mac5']!.sessionsSinceUsed, 9);
      expect(history['mac5']!.lastWeightKg, isNull);
      expect(history['mac5']!.lastFeedback, isNull);

      // Must be mutable
      history['mac5'] = history['mac5']!.copyWith(sessionsSinceUsed: 0);
      expect(history['mac5']!.sessionsSinceUsed, 0);
    });

    test('matches M値計算シミュレーター.html 1:1 across all 54 muscles, 29 machines, and 324 priorities', () {
      final htmlFile = File('M値計算シミュレーター.html');
      expect(htmlFile.existsSync(), isTrue);
      final html = htmlFile.readAsStringSync();

      final muscleRegex = RegExp(
        r"id:\s*`(m\d+)`,\s*name:\s*`([^`]+)`,\s*group:\s*`([^`]+)`,\s*timeCat:\s*`([^`]+)`,\s*r:\s*(\d+),\s*p:\s*\{([^}]+)\}",
      );
      final htmlMuscles = muscleRegex.allMatches(html).toList();
      expect(htmlMuscles.length, 54);

      final nameToId = <String, String>{};
      for (var i = 0; i < 54; i++) {
        final hm = htmlMuscles[i];
        final m = MasterData.muscles[i];
        expect(m.id, hm.group(1)!);
        expect(m.name, hm.group(2)!);
        expect(m.group, MuscleGroup.fromId(hm.group(3)!));
        expect(m.timeCat, MuscleTimeCategory.fromId(hm.group(4)!));
        expect(m.recoveryDays, int.parse(hm.group(5)!));
        nameToId[m.name] = m.id;

        final pRaw = hm.group(6)!;
        for (final purpose in TrainingPurpose.values) {
          final pm = RegExp('${purpose.id}:\\s*(\\d+)').firstMatch(pRaw)!;
          expect(
            MasterData.purposePriorities[purpose]![m.id],
            int.parse(pm.group(1)!),
            reason: 'Mismatch at ${purpose.id} / ${m.id}',
          );
        }
      }

      final macRegex = RegExp(
        r"id:\s*`(mac\d+)`,\s*name:\s*`([^`]+)`,\s*cat:\s*`([^`]+)`,\s*baseW:\s*([\d.]+),\s*bwFactor:\s*([\d.]+),\s*reps:\s*(\d+),\s*primary:\s*\[([^\]]+)\],\s*synergist:\s*\[([^\]]+)\]",
      );
      final htmlMacs = macRegex.allMatches(html).toList();
      expect(htmlMacs.length, 29);

      for (var i = 0; i < 29; i++) {
        final hm = htmlMacs[i];
        final mac = MasterData.machines[i];
        expect(mac.id, hm.group(1)!);
        expect(mac.name, hm.group(2)!);
        expect(mac.category, MuscleGroup.fromId(hm.group(3)!));
        expect(mac.baseWeight, double.parse(hm.group(4)!));
        expect(mac.bwFactor, double.parse(hm.group(5)!));
        expect(mac.baseReps, int.parse(hm.group(6)!));

        final expectedPrim = RegExp(r'`([^`]+)`')
            .allMatches(hm.group(7)!)
            .map((m) => nameToId[m.group(1)!]!)
            .toList();
        final expectedSyn = RegExp(r'`([^`]+)`')
            .allMatches(hm.group(8)!)
            .map((m) => nameToId[m.group(1)!]!)
            .toList();
        expect(mac.primaryMuscleIds, expectedPrim);
        expect(mac.synergistMuscleIds, expectedSyn);
      }
    });
  });
}
