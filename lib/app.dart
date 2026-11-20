import 'package:flutter/material.dart';

import 'screens/custom_settings_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'screens/training_flow_screen.dart';
import 'state/app_state.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// 「のう筋（Noukin）」ルートアプリケーションウィジェット
class NoukinApp extends StatefulWidget {
  final AppState? appState;
  final DateTime Function()? clock;

  const NoukinApp({super.key, this.appState, this.clock});

  @override
  State<NoukinApp> createState() => _NoukinAppState();
}

class _NoukinAppState extends State<NoukinApp> {
  late AppState _appState;
  bool _ownsAppState = false;

  @override
  void initState() {
    super.initState();
    _initAppState();
  }

  void _initAppState() {
    if (widget.appState != null) {
      _appState = widget.appState!;
      _ownsAppState = false;
      if (widget.clock != null) {
        _appState.updateClock(widget.clock);
      }
    } else {
      _appState = AppState(clock: widget.clock);
      _ownsAppState = true;
    }
    if (!_appState.isInitialized) {
      _appState.initialize();
    }
  }

  @override
  void didUpdateWidget(covariant NoukinApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      if (_ownsAppState) {
        _appState.dispose();
      }
      _initAppState();
    } else if (widget.clock != null && oldWidget.clock != widget.clock) {
      _appState.updateClock(widget.clock);
    }
  }

  @override
  void dispose() {
    if (_ownsAppState) {
      _appState.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'のう筋（Noukin）',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      home: NoukinHomeShell(appState: _appState),
    );
  }
}

/// 3画面（画面A: トレーニング / 画面B: カスタム / 画面C: 設定）を切り替えるボトムナビゲーションシェル
class NoukinHomeShell extends StatefulWidget {
  final AppState appState;

  const NoukinHomeShell({super.key, required this.appState});

  @override
  State<NoukinHomeShell> createState() => _NoukinHomeShellState();
}

class _NoukinHomeShellState extends State<NoukinHomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final pages = <Widget>[
          TrainingFlowScreen(
            profile: widget.appState.profile,
            muscleStates: widget.appState.muscleStates,
            machineHistory: widget.appState.machineHistory,
            sessionCount: widget.appState.sessionCount,
            clock: widget.appState.now,
            generator: widget.appState.generator,
            onMenuGenerated: widget.appState.recordGeneratedMenu,
            onWorkoutCompleted: widget.appState.completeWorkout,
          ),
          CustomSettingsScreen(appState: widget.appState),
          ProfileSettingsScreen(appState: widget.appState),
        ];

        return Scaffold(
          backgroundColor: AppColors.background,
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.highlightSelectedSurface,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                key: Key('nav_tab_training'),
                icon: Icon(Icons.fitness_center),
                label: 'トレーニング',
              ),
              NavigationDestination(
                key: Key('nav_tab_custom'),
                icon: Icon(Icons.tune),
                label: 'カスタム',
              ),
              NavigationDestination(
                key: Key('nav_tab_settings'),
                icon: Icon(Icons.settings),
                label: '設定',
              ),
            ],
          ),
        );
      },
    );
  }
}
