import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/dashboard_providers.dart';
import '../providers/grades_provider.dart';
import '../components/app_drawer.dart';
import '../components/dashboard_header.dart';
import '../components/semester_selector.dart';
import '../components/unit_card_grid.dart';

/// Dashboard screen - main grades view with lifecycle handling for background updates
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Register lifecycle observer to detect when app resumes from background
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload grades from storage when app resumes (to pick up background fetch updates)
    if (state == AppLifecycleState.resumed) {
      ref.read(gradesProvider.notifier).loadStoredGrades();
    }
  }

  void _showUEDetails(BuildContext context, TeachingUnit unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    titleCase(unit.name),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: GradeUtils.getColor(
                      unit.average,
                    ).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    unit.average?.toStringAsFixed(2) ?? "-",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: GradeUtils.getColor(unit.average),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            Expanded(
              child: ListView.separated(
                itemCount: unit.subjects.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final sub = unit.subjects[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                titleCase(sub.name),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Coeff ${sub.coeff}",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Allow horizontal scrolling for chips so long labels can be read
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: sub.grades.isEmpty
                                ? [
                                    Chip(
                                      label: const Text('Aucun résultat'),
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ]
                                : sub.grades.map((g) {
                                    final fullText = '${g.label}: ${g.value}';
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8.0,
                                      ),
                                      child: Tooltip(
                                        message: fullText,
                                        child: Chip(
                                          label: Text(fullText),
                                          backgroundColor: GradeUtils.getColor(
                                            g.value,
                                          ).withValues(alpha: 0.1),
                                          labelStyle: TextStyle(
                                            color: GradeUtils.getColor(g.value),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          side: BorderSide.none,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch computed providers - Riverpod caches and only recomputes when dependencies change
    final departmentName = ref.watch(departmentNameProvider);
    final curriculum = ref.watch(curriculumProvider);
    final semesterAverage = ref.watch(semesterAverageProvider);
    final selectedSemester = ref.watch(selectedSemesterProvider);

    return Scaffold(
      drawer: const AppDrawer(selected: DrawerItem.notes),
      body: SafeArea(
        child: Column(
          children: [
            Builder(
              builder: (context) => DashboardHeader(
                title: departmentName,
                average: semesterAverage,
                onMenuPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            SemesterSelector(
              selectedSemester: selectedSemester,
              onSemesterChanged: (newSem) {
                // Update provider state - UI rebuilds automatically
                ref.read(selectedSemesterProvider.notifier).state = newSem;
              },
            ),
            Expanded(
              child: UnitCardGrid(
                curriculum: curriculum,
                onUnitTap: (unit) => _showUEDetails(context, unit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
