import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_colors.dart';

/// Shell for the tabbed screens, with the floating navigation dock.
///
/// The dock floats over the content rather than sitting in a slab at the
/// bottom, so the warm background runs to the edge of the screen. Screens
/// leave room for it with bottom padding.
class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  static const _destinations = <_NavDestination>[
    _NavDestination(route: AppRoutes.home, icon: _NavIcons.home, label: 'Home'),
    _NavDestination(
      route: AppRoutes.tasks,
      icon: _NavIcons.tasks,
      label: 'Tasks',
    ),
    _NavDestination(
      route: AppRoutes.calendar,
      icon: _NavIcons.calendar,
      label: 'Calendar',
    ),
    _NavDestination(
      route: AppRoutes.settings,
      icon: _NavIcons.profile,
      label: 'Profile',
    ),
  ];

  /// The selected tab, or -1 on a screen that is not a tab (Subjects,
  /// Lectures), which are reached from Home.
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return _destinations.indexWhere(
      (destination) => location.startsWith(destination.route),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      // The dock overlaps the content, so it goes in a Stack rather than
      // bottomNavigationBar.
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 24,
            right: 24,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: _NavDock(
                destinations: _destinations,
                currentIndex: current,
                onSelected: (index) => context.go(_destinations[index].route),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final String route;
  final String icon;
  final String label;

  const _NavDestination({
    required this.route,
    required this.icon,
    required this.label,
  });
}

/// Outline icons from the design, drawn at a 2.2 stroke.
class _NavIcons {
  static const _open =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="#000" stroke-width="2.2" stroke-linecap="round" '
      'stroke-linejoin="round">';

  static const home =
      '$_open<path d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 '
      '001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 '
      '011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/></svg>';

  static const tasks =
      '$_open<rect x="6" y="4" width="4.5" height="16" '
      'rx="2.25"/><rect x="13.5" y="4" width="4.5" height="16" rx="2.25"/>'
      '</svg>';

  static const calendar =
      '$_open<path d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 '
      '002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>';

  static const profile =
      '$_open<path d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 '
      '14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>';
}

class _NavDock extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const _NavDock({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.navBar,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.25),
            blurRadius: 36,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < destinations.length; i++)
            _NavItem(
              destination: destinations[i],
              selected: i == currentIndex,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  static const _inactive = Color(0xFF807973);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 48,
          height: 44,
          alignment: Alignment.center,
          // The current tab is a coral rounded square, as in the design.
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [AppColors.primary, Color(0xFFFF7B54)],
                  )
                : null,
            borderRadius: BorderRadius.circular(21),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 24,
                      spreadRadius: -6,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: SvgPicture.string(
            destination.icon,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              selected ? AppColors.textOnPrimary : _inactive,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}
