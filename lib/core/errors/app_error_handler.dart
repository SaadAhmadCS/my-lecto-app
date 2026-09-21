import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Catches errors nothing else handled, so they're logged in one place
/// (the hook for crash reporting later) and never crash the app or show a
/// grey box to a student.
class AppErrorHandler {
  AppErrorHandler._();

  /// Call once, before runApp().
  static void install() {
    // Errors thrown while building, laying out or painting widgets
    FlutterError.onError = (details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      report(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      );
    };

    // Uncaught async errors (futures without a catch, timers, streams)
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'uncaught async error');
      return true;
    };

    // In release, a widget that fails to build shows a quiet message instead
    // of a grey box. Debug keeps Flutter's red error screen.
    if (kReleaseMode) {
      ErrorWidget.builder = (_) => const _BuildErrorView();
    }
  }

  static void report(Object error, StackTrace? stack, {String? context}) {
    debugPrint(
      'AppErrorHandler${context == null ? '' : ' ($context)'}: $error',
    );
    if (stack != null) debugPrint(stack.toString());
  }
}

class _BuildErrorView extends StatelessWidget {
  const _BuildErrorView();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: Text(
            'This part of the screen couldn\'t load.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryDark),
          ),
        ),
      ),
    );
  }
}
