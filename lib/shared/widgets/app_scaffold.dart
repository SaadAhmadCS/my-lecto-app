import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Shell for the tabbed screens, with the floating navigation pill.
///
/// The bar floats over the content rather than sitting in a slab at the
/// bottom, so the warm background runs to the edge of the screen. Screens
/// leave room for it with bottom padding.
class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  static const _destinations = <_NavDestination>[
    _NavDestination(
      route: AppRoutes.home,
      icon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavDestination(
      route: AppRoutes.transcripts,
      icon: Icons.bar_chart_rounded,
      label: 'Lectures',
    ),
    _NavDestination(
      route: AppRoutes.subjects,
      icon: Icons.folder_rounded,
      label: 'Subjects',
    ),
    _NavDestination(
      route: AppRoutes.settings,
      icon: Icons.person_rounded,
      label: 'You',
    ),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _destinations.indexWhere(
      (destination) => location.startsWith(destination.route),
    );
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      // The pill overlaps the content, so it goes in a Stack rather than
      // bottomNavigationBar.
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.base,
            child: SafeArea(
              top: false,
              child: _NavPill(
                destinations: _destinations,
                currentIndex: current,
                onSelected: (index) =>
                    context.go(_destinations[index].route),
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
  final IconData icon;
  final String label;

  const _NavDestination({
    required this.route,
    required this.icon,
    required this.label,
  });
}

class _NavPill extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const _NavPill({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.navBar,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // The current tab is a filled coral disc, as in the design.
            color: selected ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            destination.icon,
            size: 24,
            color: selected
                ? AppColors.textOnPrimary
                : AppColors.textOnPrimary.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
