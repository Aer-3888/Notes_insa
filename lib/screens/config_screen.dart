import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_colors.dart';
import '../models.dart';
import '../data.dart';
import '../providers/dashboard_providers.dart';
import '../components/app_drawer.dart';

class ConfigScreen extends ConsumerWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use computed provider for available semesters (cached)
    final availableSemesters = ref.watch(availableSemestersProvider);

    // Shared single decode of the grades payload for parsing each semester.
    final gradesData = ref.watch(decodedGradesProvider);

    final profiles = <Profile>[
      if (gradesData != null)
        for (var semNum in availableSemesters)
          Profile(
            'Semestre $semNum',
            units: JsonCurriculumParser.parseSemester(gradesData, semNum),
            isActive:
                availableSemesters.isNotEmpty &&
                semNum == availableSemesters.first,
          ),
    ];

    const crossAxisCount = 2;
    const childAspectRatio = 4 / 3;

    return Scaffold(
      drawer: const AppDrawer(selected: DrawerItem.config),
      appBar: AppBar(
        toolbarHeight: 84,
        elevation: 4,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.headerGradient,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
          ),
        ),
        title: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Profils',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Semestres et cursus',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            // Small avatar/action on the right
            Container(
              margin: const EdgeInsets.only(left: 8),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: profiles.length + 1,
          itemBuilder: (context, index) {
            if (index < profiles.length) {
              final profile = profiles[index];
              return _ProfileCard(profile: profile);
            }

            return const _AddProfileCard();
          },
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(10.0),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.layers,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${profile.unitCount} UE',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (profile.units.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        profile.units.take(2).map((u) => u.name).join(' • '),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // active indicator (small green dot at top-right)
            if (profile.isActive)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.statusPositive,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.statusPositive.withValues(alpha: .4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      color: Colors.white.withValues(alpha: .95),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // scale add-card content to available height
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 120.0;
          final scale = (maxH / 120.0).clamp(0.6, 1.0);
          final iconSize = 36.0 * scale;
          final titleSize = 14.0 * scale;
          final subtitleSize = 12.0 * scale;

          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10.0,
              horizontal: 8.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: iconSize,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: 6 * scale),
                Text(
                  'Ajouter un profil',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4 * scale),
                Text(
                  'Non implémenté',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: subtitleSize,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
