import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/dashboard_providers.dart';
import '../providers/grades_provider.dart';
import '../components/app_drawer.dart';
import '../components/dashboard_header.dart';
import '../components/semester_selector.dart';
import '../components/unit_card_grid.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

enum _PillMode { hidden, loading, cooldown }

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  _PillMode _pillMode = _PillMode.hidden;
  int _cooldownSecs = 0;
  Timer? _cooldownTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Rebuild every minute so the "last updated" label stays accurate
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(gradesProvider.notifier).loadStoredGrades();
    }
  }

  void _showCooldownPill(int secs) {
    _cooldownTimer?.cancel();
    setState(() {
      _pillMode = _PillMode.cooldown;
      _cooldownSecs = secs;
    });
    _cooldownTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pillMode = _PillMode.hidden);
    });
  }

  Future<void> _onManualRefresh(BuildContext context) async {
    final started = await ref.read(gradesProvider.notifier).manualRefresh();
    if (!started && context.mounted) {
      final remaining = ref.read(gradesProvider).manualRefreshCooldown;
      _showCooldownPill(remaining?.inSeconds ?? 0);
    }
  }

  void _showUEDetails(BuildContext context, TeachingUnit unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UEDetailSheet(unit: unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final departmentName = ref.watch(departmentNameProvider);
    final curriculum = ref.watch(curriculumProvider);
    final semesterAverage = ref.watch(semesterAverageProvider);
    final selectedSemester = ref.watch(selectedSemesterProvider);
    final gradesState = ref.watch(gradesProvider);
    final isLoading = gradesState.isLoading;
    final lastUpdated = gradesState.lastUpdated;
    final pillMode = isLoading ? _PillMode.loading : _pillMode;
    final pillVisible = pillMode != _PillMode.hidden;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        drawer: const AppDrawer(selected: DrawerItem.notes),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Builder(
                    builder: (context) => DashboardHeader(
                      title: departmentName,
                      average: semesterAverage,
                      onMenuPressed: () => Scaffold.of(context).openDrawer(),
                      lastUpdated: lastUpdated,
                    ),
                  ),
                  SemesterSelector(
                    selectedSemester: selectedSemester,
                    onSemesterChanged: (newSem) {
                      ref.read(selectedSemesterProvider.notifier).state =
                          newSem;
                    },
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _onManualRefresh(context),
                      color: Colors.black87,
                      backgroundColor: Colors.white,
                      child: UnitCardGrid(
                        curriculum: curriculum,
                        onUnitTap: (unit) => _showUEDetails(context, unit),
                      ),
                    ),
                  ),
                ],
              ),
              // Floating pill — overlaid, no layout shift
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  offset: pillVisible ? Offset.zero : const Offset(0, 0.5),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: pillVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: pillMode == _PillMode.cooldown
                              ? Row(
                                  key: const ValueKey('cooldown'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 12,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Actualisable dans $_cooldownSecs s',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  key: const ValueKey('loading'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Mise à jour...',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet
// ---------------------------------------------------------------------------

class _UEDetailSheet extends StatelessWidget {
  final TeachingUnit unit;

  const _UEDetailSheet({required this.unit});

  @override
  Widget build(BuildContext context) {
    final ueColor = GradeUtils.getColor(unit.average);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleCase(unit.name),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            unit.isValidated ? 'Validé' : 'En cours',
                            style: TextStyle(
                              fontSize: 12,
                              color: unit.isValidated
                                  ? Colors.green.shade600
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Large average circle matching dashboard header style
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ueColor,
                        boxShadow: [
                          BoxShadow(
                            color: ueColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unit.average?.toStringAsFixed(2) ?? '–',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              // Subject list
              Expanded(
                child: unit.subjects.isEmpty
                    ? Center(
                        child: Text(
                          'Aucune matière',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: unit.subjects.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _SubjectCard(subject: unit.subjects[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Subject card
// ---------------------------------------------------------------------------

class _SubjectCard extends StatelessWidget {
  final Subject subject;

  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final subjectColor = GradeUtils.getColor(subject.average);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color accent strip
            Container(width: 4, color: subjectColor),
            // Card content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject name + coeff pill
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            titleCase(subject.name),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CoeffPill(coeff: subject.coeff),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Moyenne — full-width tinted row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: subjectColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Moyenne',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: subjectColor,
                            ),
                          ),
                          Text(
                            subject.average?.toStringAsFixed(2) ?? '–',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: subjectColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (subject.grades.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 6),
                      ...subject.grades.map((g) => _GradeRow(grade: g)),
                    ],
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

// ---------------------------------------------------------------------------
// Grade row
// ---------------------------------------------------------------------------

class _GradeRow extends StatelessWidget {
  final GradeInstance grade;

  const _GradeRow({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = GradeUtils.getColor(grade.value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Color dot indicator
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              titleCase(grade.label),
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Colors.grey.shade800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (grade.coeff.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '×${grade.coeff}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Text(
            '${grade.value.toStringAsFixed(2)}/20',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _CoeffPill extends StatelessWidget {
  final double coeff;

  const _CoeffPill({required this.coeff});

  @override
  Widget build(BuildContext context) {
    final label = coeff % 1 == 0 ? coeff.toInt().toString() : coeff.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        'Coeff $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
