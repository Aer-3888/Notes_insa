import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_colors.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';
import '../providers/grades_provider.dart';
import '../screens/login_screen.dart';
import '../screens/raw_json_viewer_screen.dart';
import '../screens/settings_screen.dart';
import '../providers/package_info_provider.dart';

enum DrawerItem { notes, rawJson, config, settings }

class AppDrawer extends ConsumerWidget {
  final DrawerItem selected;
  const AppDrawer({super.key, this.selected = DrawerItem.notes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          // Gradient header matching AppBars
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.headerGradient,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.school,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relevé',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Étudiant',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _NavTile(
                  icon: Icons.school_outlined,
                  selectedIcon: Icons.school,
                  label: 'Mes Notes',
                  isSelected: selected == DrawerItem.notes,
                  onTap: () {
                    Navigator.pop(context);
                    if (selected != DrawerItem.notes) {
                      // Return to the AuthGate-owned dashboard (which keeps the
                      // 2FA reauth callback and stays under AuthGate's control)
                      // rather than pushing a new bare DashboardScreen on top.
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                ),
                _NavTile(
                  icon: Icons.tune_outlined,
                  selectedIcon: Icons.tune,
                  label: 'Paramètres',
                  isSelected: selected == DrawerItem.settings,
                  onTap: () {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearMaterialBanners();
                    }
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                _NavTile(
                  icon: Icons.data_object_outlined,
                  selectedIcon: Icons.data_object,
                  label: 'JSON Brut',
                  isSelected: selected == DrawerItem.rawJson,
                  onTap: () {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearMaterialBanners();
                    }
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RawJsonViewerScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 8),

                // Logout
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(
                    Icons.logout,
                    color: Colors.red.shade400,
                    size: 22,
                  ),
                  title: Text(
                    'Déconnexion',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearMaterialBanners();
                    }
                    ref.read(gradesProvider.notifier).clearGrades();
                    await AuthService().clear();
                    // Reset native CAS session so no in-memory state leaks to the next user.
                    await GradesService.newCAS();
                    if (context.mounted) {
                      Navigator.pop(context);
                      unawaited(
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // App version
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 10),
                  ref
                      .watch(packageInfoProvider)
                      .when(
                        data: (info) => Text(
                          'v${info.version}+${info.buildNumber}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        isSelected ? selectedIcon : icon,
        color: isSelected ? AppColors.primary : Colors.grey.shade600,
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? AppColors.primary : Colors.black87,
          fontSize: 15,
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      onTap: onTap,
    );
  }
}
