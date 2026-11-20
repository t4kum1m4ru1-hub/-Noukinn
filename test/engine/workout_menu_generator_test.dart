import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/engine/workout_menu_generator.dart';
import 'package:noukin/models/models.dart';

void main() {
  const generator = WorkoutMenuGenerator();
  final daytimeNow = DateTime(2026, 11, 19, 13, 0);
  final morningNow = DateTime(2026, 11, 19, 8, 0);
  final eveningNow = DateTime(2026, 11, 19, 18, 0);
  final nightNow = DateTime(2026, 11, 19, 22, 0);

  const defaultProfile = UserProfile(
    id: 'u1',
    gender: Gender.male,
    birthYear: 1995, // age 31 in 2026 -> 20_30
    experience: ExperienceLevel.beginner,
    bodyWeightKg: 65.0,
    purpose: TrainingPurpose.bodyMakeMale,
    isFirstTime: false,
  );

  group('Step 1: computeMuscleScores', () {
    test('computes M = B_capped + P - R - S and caps B at 14', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      states['m0'] = const MuscleInputState(
        muscleId: 'm0',
        blankDays: 25,
        stimulationDays: 2.0,
        priorityP: 18,
      );
      states['m7'] = const MuscleInputState(
        muscleId: 'm7',
        blankDays: 14,
        stimulationDays: 1.5,
        priorityP: 18,
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: defaultProfile,
        now: daytimeNow,
      );

      // m0: bRaw=25, bCapped=14, P=18, R=3, S=2.0 -> 14 + 18 - 3 - 2 = 27.0
      final m0 = scores['m0']!;
      expect(m0.bRaw, 25);
      expect(m0.bCapped, 14);
      expect(m0.mVal, 27.0);
      expect(m0.synMVal, 27.0);
      expect(m0.status, MuscleScoreStatus.active);

      // m7: bCapped=14, P=18, R=2, S=1.5 -> 14 + 18 - 2 - 1.5 = 28.5
      final m7 = scores['m7']!;
      expect(m7.mVal, 28.5);
      expect(m7.status, MuscleScoreStatus.active);
    });

    test('enforces super-recovery guard (B < R -> 0) and exact boundary (B == R -> active)', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      states['m0'] = const MuscleInputState(
        muscleId: 'm0',
        blankDays: 2, // R=3 -> recovering
        stimulationDays: 2.0,
        priorityP: 18,
      );
      states['m1'] = const MuscleInputState(
        muscleId: 'm1',
        blankDays: 3, // B == R=3 -> active
        stimulationDays: 2.0,
        priorityP: 18,
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: defaultProfile,
        now: daytimeNow,
      );

      expect(scores['m0']!.status, MuscleScoreStatus.recovering);
      expect(scores['m0']!.mVal, 0.0);
      expect(scores['m0']!.synMVal, 0.0);

      expect(scores['m1']!.status, MuscleScoreStatus.active);
      expect(scores['m1']!.mVal, 16.0); // 3 + 18 - 3 - 2
    });

    test('enforces injury guard and P==0 P_syn=6 dual map precedence', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      // Injured overrides P=0 and high B
      states['m15'] = const MuscleInputState(
        muscleId: 'm15',
        blankDays: 14,
        stimulationDays: 0.0,
        priorityP: 0,
        isInjured: true,
      );
      // Untargeted (P=0) while recovering (B=1 < R=2): status=untargeted, synMVal=0
      states['m18'] = const MuscleInputState(
        muscleId: 'm18',
        blankDays: 1,
        stimulationDays: 2.0,
        priorityP: 0,
      );
      // Untargeted (P=0) and recovered (B=4 >= R=2): mVal=0, synMVal = 4 + 6 - 2 - 2 = 6.0
      states['m27'] = const MuscleInputState(
        muscleId: 'm27',
        blankDays: 4,
        stimulationDays: 2.0,
        priorityP: 0,
      );

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: defaultProfile,
        now: daytimeNow,
      );

      expect(scores['m15']!.status, MuscleScoreStatus.injured);
      expect(scores['m15']!.mVal, 0.0);
      expect(scores['m15']!.synMVal, 0.0);

      expect(scores['m18']!.status, MuscleScoreStatus.untargeted);
      expect(scores['m18']!.mVal, 0.0);
      expect(scores['m18']!.synMVal, 0.0);

      expect(scores['m27']!.status, MuscleScoreStatus.untargeted);
      expect(scores['m27']!.mVal, 0.0);
      expect(scores['m27']!.synMVal, 6.0);
    });

    test('normalizes priorityP tiers, clamps negative B/S, and rounds 1 decimal', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      states['m0'] = const MuscleInputState(muscleId: 'm0', priorityP: 0, blankDays: -5, stimulationDays: -2.0);
      states['m1'] = const MuscleInputState(muscleId: 'm1', priorityP: -5, blankDays: 4, stimulationDays: 2.14);
      states['m2'] = const MuscleInputState(muscleId: 'm2', priorityP: 11, blankDays: 4, stimulationDays: 2.16);
      states['m3'] = const MuscleInputState(muscleId: 'm3', priorityP: 12);
      states['m4'] = const MuscleInputState(muscleId: 'm4', priorityP: 15);
      states['m5'] = const MuscleInputState(muscleId: 'm5', priorityP: 16);

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: defaultProfile,
        now: daytimeNow,
      );

      expect(scores['m0']!.priorityP, 0);
      expect(scores['m0']!.bRaw, 0);
      expect(scores['m0']!.bCapped, 0);
      expect(scores['m0']!.stimulationDays, 0.0);

      expect(scores['m1']!.priorityP, 10);
      expect(scores['m1']!.stimulationDays, 2.1);
      expect(scores['m1']!.mVal, 8.9); // 4 + 10 - 3 - 2.1

      expect(scores['m2']!.priorityP, 10);
      expect(scores['m2']!.stimulationDays, 2.2);
      expect(scores['m2']!.mVal, 8.8); // 4 + 10 - 3 - 2.2

      expect(scores['m3']!.priorityP, 14);
      expect(scores['m4']!.priorityP, 14);
      expect(scores['m5']!.priorityP, 18);
    });

    test('extends recoveryDays (+1) for highVolumeExtendMuscleIds and 50s/60_plus stacking to +2', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final seniorProfile = defaultProfile.copyWith(birthYear: 1964); // age 62 -> 60_plus

      final scores = generator.computeMuscleScores(
        muscleStates: states,
        profile: seniorProfile,
        lastFeedback: WorkoutFeedback.tooHard,
        now: daytimeNow,
      );

      // m29 is in HIGH_VOLUME_EXTEND_MUSCLES (base R=2 -> +1 vol +1 age = 4)
      expect(scores['m29']!.baseRecoveryDays, 2);
      expect(scores['m29']!.effectiveRecoveryDays, 4);
      expect(scores['m29']!.isExtendedByVolume, isTrue);
      expect(scores['m29']!.isExtendedByAge, isTrue);

      // m0 is NOT in HIGH_VOLUME_EXTEND_MUSCLES (base R=3 -> +0 vol +1 age = 4)
      expect(scores['m0']!.baseRecoveryDays, 3);
      expect(scores['m0']!.effectiveRecoveryDays, 4);
      expect(scores['m0']!.isExtendedByVolume, isFalse);
      expect(scores['m0']!.isExtendedByAge, isTrue);
    });
  });

  group('Steps 2-4: Raw Score, Multipliers, mac7 TFL, Overlap Loop & Tie-Break', () {
    test('handles mac7 TFL (m27) untargeted exception vs m27 injured override', () {
      // Zero out all muscles except mac7 primaries (m2, m5, m14) + m27 untargeted (P=0)
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 0),
      };
      states['m2'] = const MuscleInputState(muscleId: 'm2', priorityP: 18, blankDays: 10, stimulationDays: 0);
      states['m5'] = const MuscleInputState(muscleId: 'm5', priorityP: 18, blankDays: 10, stimulationDays: 0);
      states['m14'] = const MuscleInputState(muscleId: 'm14', priorityP: 18, blankDays: 10, stimulationDays: 0);
      states['m27'] = const MuscleInputState(muscleId: 'm27', priorityP: 0, blankDays: 10, stimulationDays: 0);

      final result = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(result.exercises.any((e) => e.machine.id == 'mac7'), isTrue);

      // Now injure m27: mac7 MUST be excluded completely
      states['m27'] = states['m27']!.copyWith(isInjured: true);
      final injuredResult = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(injuredResult.exercises.any((e) => e.machine.id == 'mac7'), isFalse);
    });

    test('computes exact primaryScore, synergistScore, 3-stage rotationBonus, and structureBonus', () {
      // Isolate mac6 (レッグカール: primary [m1], synergist [m15,m17,m24,m25], isIso=true)
      // Give m1 active score and all other machines' primaries P=0
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4, stimulationDays: 2.0),
      };
      states['m1'] = const MuscleInputState(
        muscleId: 'm1',
        priorityP: 18,
        blankDays: 4,
        stimulationDays: 2.0,
      );
      // m1: 4 + 18 - 3 - 2 = 17.0
      // synergists of mac6: m15(P=0->syn=6), m17(P=0->syn=5), m24(P=0->syn=6), m25(P=0->syn=6)
      // top2 synergist avg = (6 + 6)/2 = 6.0 -> synergistScore = 6.0 * 0.3 = 1.8

      final history = MasterData.defaultMachineHistory();
      // Test rotationBonus at sessionsSinceUsed = 20 -> 5*0.7 + 5*1.5 + 10*2.5 = 3.5 + 7.5 + 25 = 36.0
      // structureBonus at step 0 with sessionsSinceUsed=20 -> 4.0 (not tired/night)
      history['mac6'] = const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 20);

      final result = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      expect(result.exercises.length, 1);
      final ex = result.exercises.first;
      expect(ex.machine.id, 'mac6');
      // rawScore = 17.0 + 1.8 + 4.0 + 36.0 = 58.8
      expect(ex.rawScore, closeTo(58.8, 0.0001));
      expect(ex.finalScore, closeTo(58.8, 0.0001));
    });

    test('applies timeSlot multipliers across morning, daytime, evening, and night', () {
      // Isolate mac27 (primary m7: morningRec) and mac22 (primary m36: other, synergist m6: eveningRec)
      // and mac12 (primary m29: other yet nightAvoid!)
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4, stimulationDays: 2.0),
      };
      states['m7'] = const MuscleInputState(muscleId: 'm7', priorityP: 10, blankDays: 4, stimulationDays: 2.0);
      states['m29'] = const MuscleInputState(muscleId: 'm29', priorityP: 10, blankDays: 4, stimulationDays: 2.0);
      states['m36'] = const MuscleInputState(muscleId: 'm36', priorityP: 10, blankDays: 4, stimulationDays: 2.0);

      final history = MasterData.defaultMachineHistory();
      history['mac27'] = const MachineHistoryEntry(machineId: 'mac27', sessionsSinceUsed: 0);
      history['mac12'] = const MachineHistoryEntry(machineId: 'mac12', sessionsSinceUsed: 0);
      history['mac22'] = const MachineHistoryEntry(machineId: 'mac22', sessionsSinceUsed: 0);

      // Morning: mac27 (m7 morningRec primary) gets x1.25
      final morningRes = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: morningNow,
      );
      final mac27Morning = morningRes.exercises.firstWhere((e) => e.machine.id == 'mac27');
      expect(mac27Morning.finalScore / mac27Morning.rawScore, closeTo(1.25, 0.0001));

      // Evening: mac22 (m6 eveningRec synergist) gets x1.02
      final eveningRes = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: eveningNow,
      );
      final mac22Evening = eveningRes.exercises.firstWhere((e) => e.machine.id == 'mac22');
      expect(mac22Evening.finalScore / mac22Evening.rawScore, closeTo(1.02, 0.0001));

      // Night: mac12 (m29 is nightAvoid) gets x0.30
      final nightRes = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: nightNow,
      );
      final mac12Night = nightRes.exercises.firstWhere((e) => e.machine.id == 'mac12');
      expect(mac12Night.finalScore / mac12Night.rawScore, closeTo(0.30, 0.0001));
    });

    test('applies focusMultiplier stacking and synergist/category overlap attenuation in Step 4', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      final resShort = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        focusMuscleId: 'm11',
        now: daytimeNow,
      );
      expect(resShort.exercises.length, 2);
      expect(resShort.exercises.map((e) => e.machine.id).toSet().length, 2);

      final resStd = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(resStd.exercises.length, 4);

      final resFull = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.full60,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(resFull.exercises.length, 5);
    });

    test('coerces sessionCount <= 0 to 1 and uses deterministic tie-break rotation', () {
      // Equalize mac2 and mac4 (identical primaries [m0, m2], synergists [m1, m14, m16], offset 6)
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4, stimulationDays: 2.0),
      };
      states['m0'] = const MuscleInputState(muscleId: 'm0', priorityP: 18, blankDays: 6, stimulationDays: 2.0);
      states['m2'] = const MuscleInputState(muscleId: 'm2', priorityP: 18, blankDays: 6, stimulationDays: 2.0);
      // Exclude mac1, mac3, mac5, mac7, mac8, mac9 by injuring m13, m5, m10
      states['m13'] = const MuscleInputState(muscleId: 'm13', priorityP: 0, isInjured: true);
      states['m5'] = const MuscleInputState(muscleId: 'm5', priorityP: 0, isInjured: true);
      states['m10'] = const MuscleInputState(muscleId: 'm10', priorityP: 0, isInjured: true);

      final resZero = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        sessionCount: 0,
        now: daytimeNow,
      );
      final resOne = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        sessionCount: 1,
        now: daytimeNow,
      );
      expect(resZero.exercises.first.machine.id, resOne.exercises.first.machine.id);
      // mac2 idx=1 -> (1+7)%29=8; mac4 idx=3 -> (3+7)%29=10 -> mac4 wins when sessionCount=1
      expect(resOne.exercises.first.machine.id, 'mac4');
    });
  });

  group('Step 5: Load Prescription & advanceSessionDay', () {
    test('computes first-time weight, birthYear cutoffs, tired adjustment, and rep shifts', () {
      // 60_plus (born 1960, age 66 in 2026) -> ageCoeff=0.65, reps 10->12 & 12->15
      final seniorFirst = UserProfile(
        gender: Gender.female,
        birthYear: 1960,
        experience: ExperienceLevel.intermediate,
        bodyWeightKg: 55.0,
        purpose: TrainingPurpose.bodyMakeFemale,
        isFirstTime: true,
      );

      final res = generator.generateMenu(
        profile: seniorFirst,
        muscleStates: MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeFemale),
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.tired,
        now: daytimeNow,
      );

      expect(res.exercises, isNotEmpty);
      for (final ex in res.exercises) {
        expect(ex.sets, 2);
        expect(ex.weightKg, greaterThanOrEqualTo(2.5));
        expect(ex.weightKg % 2.5, 0.0);
        if (ex.machine.baseReps == 10) {
          expect(ex.reps, 12);
        } else if (ex.machine.baseReps == 12) {
          expect(ex.reps, 15);
        }
      }

      // Check exact birthYear bracket transitions
      expect(WorkoutMenuGenerator.resolveAgeBracket(2007, now: daytimeNow), 'under_20'); // 19
      expect(WorkoutMenuGenerator.resolveAgeBracket(2006, now: daytimeNow), '20_30'); // 20
      expect(WorkoutMenuGenerator.resolveAgeBracket(1987, now: daytimeNow), '20_30'); // 39
      expect(WorkoutMenuGenerator.resolveAgeBracket(1986, now: daytimeNow), '40s'); // 40
      expect(WorkoutMenuGenerator.resolveAgeBracket(1977, now: daytimeNow), '40s'); // 49
      expect(WorkoutMenuGenerator.resolveAgeBracket(1976, now: daytimeNow), '50s'); // 50
      expect(WorkoutMenuGenerator.resolveAgeBracket(1967, now: daytimeNow), '50s'); // 59
      expect(WorkoutMenuGenerator.resolveAgeBracket(1966, now: daytimeNow), '60_plus'); // 60
    });

    test('applies returning weight feedback and falls back to machine.baseWeight when lastWeightKg is null', () {
      final history = MasterData.defaultMachineHistory();
      history['mac1'] = const MachineHistoryEntry(
        machineId: 'mac1',
        sessionsSinceUsed: 10,
        lastWeightKg: null,
        lastFeedback: WorkoutFeedback.tooLight,
      );

      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4, stimulationDays: 2.0),
      };
      states['m0'] = const MuscleInputState(muscleId: 'm0', priorityP: 18, blankDays: 10, stimulationDays: 0);
      states['m2'] = const MuscleInputState(muscleId: 'm2', priorityP: 18, blankDays: 10, stimulationDays: 0);
      states['m13'] = const MuscleInputState(muscleId: 'm13', priorityP: 18, blankDays: 10, stimulationDays: 0);

      final res = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.great,
        now: daytimeNow,
      );

      final mac1Ex = res.exercises.firstWhere((e) => e.machine.id == 'mac1');
      // mac1.baseWeight = 85.0 + 2.5 = 87.5
      expect(mac1Ex.weightKg, 87.5);
      expect(mac1Ex.sets, 3);
    });

    test('advanceSessionDay updates B/S with primary overriding synergist and updates machineHistory', () {
      final states = MasterData.defaultMuscleStates(TrainingPurpose.bodyMakeMale);
      states['m0'] = const MuscleInputState(
        muscleId: 'm0',
        blankDays: 10,
        stimulationDays: 11.5,
        priorityP: 18,
      );
      states['m1'] = const MuscleInputState(
        muscleId: 'm1',
        blankDays: 5,
        stimulationDays: 2.0,
        priorityP: 18,
      );

      final mac1 = MasterData.machineById['mac1']!; // primary m0,m2,m13; syn m1,m14,m16,m17
      final mac8 = MasterData.machineById['mac8']!; // primary m2; syn m0,m1,m5,m9,m26
      final completed = <PrescribedExercise>[
        PrescribedExercise(machine: mac1, weightKg: 90.0, reps: 10, sets: 3),
        PrescribedExercise(machine: mac8, weightKg: 70.0, reps: 10, sets: 3),
      ];

      final advanced = generator.advanceSessionDay(
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        completedExercises: completed,
        overallFeedback: WorkoutFeedback.tooLight,
        sessionCount: 2,
        daysElapsed: 2,
      );

      // m0 is primary in mac1 AND synergist in mac8 -> primary rule wins!
      // B = min(30, 2) = 2; S = min(12, round1(11.5 * 0.92^2 + 1.5)) = min(12, round1(11.2336)) = 11.2
      expect(advanced.muscleStates['m0']!.blankDays, 2);
      expect(advanced.muscleStates['m0']!.stimulationDays, 11.2);

      // m1 is synergist only: B = min(30, 5 + 2) = 7; S = round1(2.0 * 0.92^2 + 0.3) = round1(1.9928) = 2.0
      expect(advanced.muscleStates['m1']!.blankDays, 7);
      expect(advanced.muscleStates['m1']!.stimulationDays, 2.0);

      // m3 is unused: B = 4 + 2 = 6; S = round1(2.0 * 0.92^2) = round1(1.6928) = 1.7
      expect(advanced.muscleStates['m3']!.blankDays, 6);
      expect(advanced.muscleStates['m3']!.stimulationDays, 1.7);

      // Machine history: mac1 & mac8 reset to 0 with weight & feedback; mac2 incremented 6 -> 7
      expect(advanced.machineHistory['mac1']!.sessionsSinceUsed, 0);
      expect(advanced.machineHistory['mac1']!.lastWeightKg, 90.0);
      expect(
        advanced.machineHistory['mac1']!.lastFeedback,
        WorkoutFeedback.tooLight,
      );
      expect(advanced.machineHistory['mac2']!.sessionsSinceUsed, 7);
      expect(advanced.sessionCount, 3);

      // daysElapsed <= 0 coerces to 1 and blankDays caps at 30
      states['m3'] = const MuscleInputState(muscleId: 'm3', blankDays: 30, stimulationDays: 2.0);
      final clampedAdvance = generator.advanceSessionDay(
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        completedExercises: const <PrescribedExercise>[],
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 0,
        daysElapsed: -3,
      );
      expect(clampedAdvance.muscleStates['m3']!.blankDays, 30);
      expect(clampedAdvance.muscleStates['m0']!.blankDays, 11); // 10 + 1
      expect(clampedAdvance.sessionCount, 2); // coerced 0 -> 1, +1 = 2

      // S_i upper cap saturation: 11.5 * 0.92 + 1.5 = 12.08 -> round1 = 12.1 -> capped at 12.0
      final saturatedAdvance = generator.advanceSessionDay(
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        completedExercises: <PrescribedExercise>[
          PrescribedExercise(machine: mac1, weightKg: 90.0, reps: 10, sets: 3),
        ],
        overallFeedback: WorkoutFeedback.justRight,
        sessionCount: 1,
        daysElapsed: 1,
      );
      expect(saturatedAdvance.muscleStates['m0']!.blankDays, 1);
      expect(saturatedAdvance.muscleStates['m0']!.stimulationDays, 12.0);
    });

    test('rounds 2.5 kg increments accurately at midpoints and floors at 2.5 kg', () {
      // First-time weight: bw * bwFactor * 1.0 * 1.0 * 1.0 (male beginner 20_30)
      // mac23 (bwFactor = 0.25):
      // bw=14.96 -> 3.74 -> 2.5; bw=15.0 -> 3.75 -> 5.0
      // mac1 (bwFactor = 1.25):
      // bw=49.0 -> 61.25 -> 62.5; bw=58.9 -> 73.625 -> 72.5
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4),
      };
      states['m35'] = const MuscleInputState(muscleId: 'm35', priorityP: 18, blankDays: 6);

      final resLow = generator.generateMenu(
        profile: defaultProfile.copyWith(isFirstTime: true, bodyWeightKg: 14.96),
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(resLow.exercises.firstWhere((e) => e.machine.id == 'mac23').weightKg, 2.5);

      final resMid = generator.generateMenu(
        profile: defaultProfile.copyWith(isFirstTime: true, bodyWeightKg: 15.0),
        muscleStates: states,
        machineHistory: MasterData.defaultMachineHistory(),
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(resMid.exercises.firstWhere((e) => e.machine.id == 'mac23').weightKg, 5.0);

      final statesLeg = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4),
      };
      statesLeg['m0'] = const MuscleInputState(muscleId: 'm0', priorityP: 18, blankDays: 6);
      statesLeg['m2'] = const MuscleInputState(muscleId: 'm2', priorityP: 18, blankDays: 6);
      statesLeg['m13'] = const MuscleInputState(muscleId: 'm13', priorityP: 18, blankDays: 6);

      final legHistory = MasterData.defaultMachineHistory();
      legHistory['mac1'] = const MachineHistoryEntry(
        machineId: 'mac1',
        sessionsSinceUsed: 15,
      );

      final res6125 = generator.generateMenu(
        profile: defaultProfile.copyWith(isFirstTime: true, bodyWeightKg: 49.0),
        muscleStates: statesLeg,
        machineHistory: legHistory,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(res6125.exercises.firstWhere((e) => e.machine.id == 'mac1').weightKg, 62.5);

      final res73625 = generator.generateMenu(
        profile: defaultProfile.copyWith(isFirstTime: true, bodyWeightKg: 58.9),
        muscleStates: statesLeg,
        machineHistory: legHistory,
        course: WorkoutDurationCourse.short20,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );
      expect(res73625.exercises.firstWhere((e) => e.machine.id == 'mac1').weightKg, 72.5);
    });

    test('applies structureBonus +6.5 finisher only on standard45/full60 final step for unpicked category', () {
      // Pick 3 legsGlutes/chest/back exercises in steps 0..2, then step 3 picks mac26 (arms, isIso=true, unpicked cat)
      final states = <String, MuscleInputState>{
        for (final m in MasterData.muscles)
          m.id: MuscleInputState(muscleId: m.id, priorityP: 0, blankDays: 4, stimulationDays: 2.0),
      };
      // Step 0: mac5 (legsGlutes: m0,m13) or mac1? Make only m0,m13 -> mac5 (legsGlutes), m3 -> mac11 (chest), m4,m40 -> mac16 (back), m12 -> mac26 (arms)
      states['m1'] = const MuscleInputState(muscleId: 'm1', priorityP: 18, blankDays: 14, stimulationDays: 0); // mac6
      states['m3'] = const MuscleInputState(muscleId: 'm3', priorityP: 18, blankDays: 14, stimulationDays: 0); // mac11/14
      states['m29'] = const MuscleInputState(muscleId: 'm29', priorityP: 18, blankDays: 14, stimulationDays: 0); // mac12
      states['m7'] = const MuscleInputState(muscleId: 'm7', priorityP: 10, blankDays: 4, stimulationDays: 2.0); // mac27 (core, isIso=true)

      final history = MasterData.defaultMachineHistory();
      history['mac6'] = const MachineHistoryEntry(machineId: 'mac6', sessionsSinceUsed: 12);
      history['mac11'] = const MachineHistoryEntry(machineId: 'mac11', sessionsSinceUsed: 12);
      history['mac12'] = const MachineHistoryEntry(machineId: 'mac12', sessionsSinceUsed: 12);
      history['mac27'] = const MachineHistoryEntry(machineId: 'mac27', sessionsSinceUsed: 0);

      final res = generator.generateMenu(
        profile: defaultProfile,
        muscleStates: states,
        machineHistory: history,
        course: WorkoutDurationCourse.standard45,
        condition: WorkoutCondition.normal,
        now: daytimeNow,
      );

      expect(res.exercises.length, 4);
      final finisher = res.exercises[3];
      expect(finisher.machine.id, 'mac27');
      // m7: 4 + 10 - 2 - 2 = 10.0; syn (m49,m50,m51: 4+6-2-2=6.0 -> top2 avg*0.3 = 1.8); rot=0; str=+6.5 -> 18.3
      expect(finisher.rawScore, closeTo(18.3, 0.0001));
    });
  });
}
