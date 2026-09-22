import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/exam_prep/exam_prep_screen.dart';
import '../../features/home/presentation/screens/calendar_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/tasks_screen.dart';
import '../../features/recording/presentation/screens/recording_detail_screen.dart';
import '../../features/recording/presentation/screens/recording_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/home/presentation/screens/quizzes_screen.dart';
import '../../features/subjects/presentation/screens/subject_detail_screen.dart';
import '../../features/subjects/presentation/screens/subjects_screen.dart';
import '../../features/timetable/presentation/screens/timetable_import_screen.dart';
import '../../features/timetable/presentation/screens/timetable_screen.dart';
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
  static const String timetable = '/timetable';
  static const String timetableImport = '/timetable-import';
  static const String examPrep = '/exam-prep';

  /// Exam prep, optionally opened on a course and an announced exam.
  static String examPrepFor({
    String? subjectId,
    String? exam,
    DateTime? date,
  }) => Uri(
    path: examPrep,
    queryParameters: {
      'subjectId': ?subjectId,
      'exam': ?exam,
      if (date != null) 'date': date.toIso8601String().substring(0, 10),
    },
  ).toString();
}

/// GoRouter configuration.
///
/// The app opens on Home: there is no account to sign in to and no first-run
/// flow to complete.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  /// The root navigator, for code outside the widget tree that needs a
  /// context — notification taps, say.
  static GlobalKey<NavigatorState> get navigatorKey => _rootNavigatorKey;
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
            pageBuilder: (context, state) => _tab(const HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.tasks,
            pageBuilder: (context, state) => _tab(const TasksScreen()),
          ),
          GoRoute(
            path: AppRoutes.calendar,
            pageBuilder: (context, state) => _tab(const CalendarScreen()),
          ),
          GoRoute(
            path: AppRoutes.subjects,
            pageBuilder: (context, state) => _tab(const SubjectsScreen()),
          ),
          GoRoute(
            path: AppRoutes.transcripts,
            pageBuilder: (context, state) => _tab(const TranscriptsScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) => _tab(const SettingsScreen()),
          ),
        ],
      ),
      // Full-screen routes (outside the shell)
      GoRoute(
        path: AppRoutes.subjectDetail,
        builder: (context, state) =>
            SubjectDetailScreen(subjectId: state.pathParameters['id']!),
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
        path: AppRoutes.timetable,
        builder: (context, state) => const TimetableScreen(),
      ),
      GoRoute(
        path: AppRoutes.timetableImport,
        builder: (context, state) => const TimetableImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.examPrep,
        builder: (context, state) => ExamPrepScreen(
          subjectId: state.uri.queryParameters['subjectId'],
          examTitle: state.uri.queryParameters['exam'],
          examDate: state.uri.queryParameters['date'],
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

/// Tabs cross-fade quickly rather than snapping, so switching between them
/// feels like one app rather than separate screens.
CustomTransitionPage<void> _tab(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: const Duration(milliseconds: 200),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
);
