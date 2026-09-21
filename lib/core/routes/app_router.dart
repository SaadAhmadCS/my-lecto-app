import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/screens/calendar_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/tasks_screen.dart';
import '../../features/recording/presentation/screens/recording_detail_screen.dart';
import '../../features/recording/presentation/screens/recording_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/home/presentation/screens/quizzes_screen.dart';
import '../../features/subjects/presentation/screens/subject_detail_screen.dart';
import '../../features/subjects/presentation/screens/subjects_screen.dart';
import '../../features/transcript/presentation/screens/transcripts_screen.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Route names as constants for type-safe navigation.
class AppRoutes {
  AppRoutes._();

  static const String home = '/home';
  static const String subjects = '/subjects';
  static const String subjectDetail = '/subjects/:id';
  static const String record = '/record';
  static const String transcripts = '/transcripts';
  static const String settings = '/settings';
  static const String recordingDetail = '/recording/:id';
  static const String quizzes = '/quizzes';
  static const String tasks = '/tasks';
  static const String calendar = '/calendar';
}

/// GoRouter configuration.
///
/// The app opens on Home: there is no account to sign in to and no first-run
/// flow to complete.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter router() => GoRouter(
        navigatorKey: _rootNavigatorKey,
        initialLocation: AppRoutes.home,
        routes: [
          ShellRoute(
            navigatorKey: _shellNavigatorKey,
            builder: (context, state, child) => AppScaffold(child: child),
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: HomeScreen()),
              ),
              GoRoute(
                path: AppRoutes.tasks,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TasksScreen()),
              ),
              GoRoute(
                path: AppRoutes.calendar,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: CalendarScreen()),
              ),
              GoRoute(
                path: AppRoutes.subjects,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SubjectsScreen()),
              ),
              GoRoute(
                path: AppRoutes.transcripts,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: TranscriptsScreen()),
              ),
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SettingsScreen()),
              ),
            ],
          ),
          // Full-screen routes (outside the shell)
          GoRoute(
            path: AppRoutes.subjectDetail,
            builder: (context, state) => SubjectDetailScreen(
              subjectId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: AppRoutes.record,
            builder: (context, state) => RecordingScreen(
              initialSubjectId: state.uri.queryParameters['subjectId'],
              // Arriving with a subject already chosen starts straight away.
              autoStart: state.uri.queryParameters['start'] == '1',
            ),
          ),
          GoRoute(
            path: AppRoutes.quizzes,
            builder: (context, state) => const QuizzesScreen(),
          ),
          GoRoute(
            path: AppRoutes.recordingDetail,
            builder: (context, state) => RecordingDetailScreen(
              recordingId: state.pathParameters['id']!,
              title: state.uri.queryParameters['title'] ?? 'Recording',
            ),
          ),
        ],
      );
}
