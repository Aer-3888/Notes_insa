import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/dashboard_providers.dart';
import '../providers/grades_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/averages_provider.dart';
import '../providers/coefficients_provider.dart';
import '../components/app_drawer.dart';
import '../components/dashboard_header.dart';
import '../components/unit_card_grid.dart';
import '../services/averages_service.dart';
import '../services/notification_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  /// Called when 2FA is required and no OTP secret is stored.
  /// The caller should navigate to the login screen.
  final VoidCallback? onReauthRequired;

  const DashboardScreen({super.key, this.onReauthRequired});

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
  bool _consentDialogShown = false;

  // Guard so we only call requestPermission() once across all DashboardScreen
  // instances in this process lifetime (the widget is recreated on every unlock).
  static bool _notificationPermissionRequested = false;

  void _requestNotificationPermissionOnce() {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    unawaited(NotificationService.requestPermission());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Rebuild every minute so the "last updated" label stays accurate
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Request notification permission once per app session (not on every unlock).
    // Permission.notification.request() may re-prompt on Android 13+ if denied
    // but not permanently — calling it on every DashboardScreen init (every
    // biometric/PIN unlock) would show the dialog every screen-timeout cycle.
    _requestNotificationPermissionOnce();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // If 2FA was already required before the dashboard was built, show the banner now.
      if (ref.read(gradesProvider).needsReauth) _showReauthBanner();
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

  void _showReauthBanner() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        leading: const Icon(Icons.lock_outline, color: Colors.white),
        backgroundColor: Colors.orange.shade700,
        content: const Text(
          'Une double authentification est requise.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.clearMaterialBanners();
              widget.onReauthRequired?.call();
            },
            child: const Text(
              'Se reconnecter',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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

  void _swipeSemester(DragEndDetails details) {
    final available = ref.read(availableSemestersProvider);
    if (available.length <= 1) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    final current = ref.read(effectiveSemesterProvider);
    if (current == null) return;
    final idx = available.indexOf(current);
    if (idx == -1) return;
    // Display is lowest semester on left, so swipe left → newer semester.
    final newIdx = velocity > 0
        ? (idx - 1).clamp(0, available.length - 1)
        : (idx + 1).clamp(0, available.length - 1);
    if (newIdx != idx) {
      HapticFeedback.lightImpact();
      ref.read(selectedSemesterProvider.notifier).state = available[newIdx];
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _onManualRefresh(BuildContext context) async {
    final started = await ref.read(gradesProvider.notifier).manualRefresh();
    if (!started && context.mounted) {
      final remaining = ref.read(gradesProvider).manualRefreshCooldown;
      _showCooldownPill(remaining?.inSeconds ?? 0);
    } else if (started) {
      // Also refresh class averages if the grade fetch successfully started.
      final department = ref.read(departmentNameProvider);
      final semester = ref.read(effectiveSemesterProvider);
      final academicYear = ref.read(academicYearProvider);

      if (department.isNotEmpty && semester != null) {
        ref.invalidate(
          averagesProvider((
            department: department,
            semester: semester,
            academicYear: academicYear,
          )),
        );
      }
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

  void _showConsentDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => _ConsentSheet(
        onAccept: () {
          ref.read(settingsProvider.notifier).setSharingConsent(true);
          ref.read(settingsProvider.notifier).markConsentAsked();
          Navigator.pop(sheetContext);
        },
        onDecline: () {
          ref.read(settingsProvider.notifier).setSharingConsent(false);
          ref.read(settingsProvider.notifier).markConsentAsked();
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  // Called after every successful fresh fetch (login + manual refresh).
  void _trySubmitGrades() {
    final settings = ref.read(settingsProvider);
    final gradesJson = ref.read(gradesProvider).jsonData;

    if (settings.isLoading) return;
    if (!settings.sharingConsent) return;

    unawaited(AveragesService.submitAllSemesters(gradesJson));
  }

  @override
  Widget build(BuildContext context) {
    // Show consent dialog exactly once — when settings finishes loading for
    // the first time and the user has never been asked. Reading at construction
    // time is unreliable because _loadSettings() is async.
    ref.listen<SettingsState>(settingsProvider, (prev, next) {
      if (prev?.isLoading == true &&
          !next.isLoading &&
          !next.sharingConsentAsked &&
          !_consentDialogShown) {
        _consentDialogShown = true;
        _showConsentDialog();
      }
    });

    ref.listen<GradesState>(gradesProvider, (prev, next) {
      if (prev?.isLoading == true &&
          !next.isLoading &&
          next.hasData &&
          next.error == null) {
        _trySubmitGrades();
        ref.invalidate(coefficientsProvider);
      }

      // Reactively show or hide the 2FA banner
      if (next.needsReauth && !(prev?.needsReauth ?? false)) {
        _showReauthBanner();
      } else if (!next.needsReauth && (prev?.needsReauth ?? false)) {
        ScaffoldMessenger.of(context).clearMaterialBanners();
      }
    });

    final departmentName = ref.watch(departmentNameProvider);
    final curriculum = ref.watch(curriculumProvider);
    final semesterAverage = ref.watch(semesterAverageProvider);
    final effectiveSemester = ref.watch(effectiveSemesterProvider);
    final gradesState = ref.watch(gradesProvider);

    final academicYear = ref.watch(academicYearProvider);

    // Pre-fetch averages in the background so data is ready when user taps a subject.
    if (effectiveSemester != null) {
      ref.watch(
        averagesProvider((
          department: departmentName,
          semester: effectiveSemester,
          academicYear: academicYear,
        )),
      );
    }

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
                      provisional: ref.watch(
                        semesterAverageProvisionalProvider,
                      ),
                      onMenuPressed: () => Scaffold.of(context).openDrawer(),
                      lastUpdated: lastUpdated,
                      selectedSemester: effectiveSemester ?? 0,
                      availableSemesters: ref.watch(availableSemestersProvider),
                      onSemesterChanged: (newSem) {
                        ref.read(selectedSemesterProvider.notifier).state =
                            newSem;
                      },
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onHorizontalDragEnd: _swipeSemester,
                      behavior: HitTestBehavior.opaque,
                      child: RefreshIndicator(
                        onRefresh: () => _onManualRefresh(context),
                        color: Colors.black87,
                        backgroundColor: Colors.white,
                        child: UnitCardGrid(
                          curriculum: curriculum,
                          isLoading: isLoading,
                          onUnitTap: (unit) => _showUEDetails(context, unit),
                        ),
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

class _UEDetailSheet extends ConsumerStatefulWidget {
  final TeachingUnit unit;

  const _UEDetailSheet({required this.unit});

  @override
  ConsumerState<_UEDetailSheet> createState() => _UEDetailSheetState();
}

class _UEDetailSheetState extends ConsumerState<_UEDetailSheet> {
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  void _showSubjectStats(
    BuildContext context,
    Subject subject,
    SubjectAverage? avg,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubjectStatsSheet(subject: subject, avg: avg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ueColor = GradeUtils.getColor(widget.unit.average);

    final department = ref.watch(departmentNameProvider);
    final semester = ref.watch(effectiveSemesterProvider);
    final academicYear = ref.watch(academicYearProvider);
    final avgAsync = ref.watch(
      averagesProvider((
        department: department,
        semester: semester ?? 0,
        academicYear: academicYear,
      )),
    );

    final Map<String, SubjectAverage> avgMap = avgAsync.maybeWhen(
      data: (list) => {
        for (final a in list)
          '${a.ueName.cleanName()}|${a.subjectName.cleanName()}': a,
      },
      orElse: () => {},
    );

    if (kDebugMode && avgAsync.hasValue) {
      for (final subject in widget.unit.subjects) {
        final key =
            '${widget.unit.name.cleanName()}|${subject.name.cleanName()}';
        if (!avgMap.containsKey(key)) {
          debugPrint('[UEDetailSheet] No average data for subject: $key');
        }
      }
    }

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
                            titleCase(widget.unit.name),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.unit.isValidated ? 'Validé' : 'En cours',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.unit.isValidated
                                  ? AppColors.statusPositive
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
                        widget.unit.average?.toStringAsFixed(2) ?? '–',
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
              // Scroll shadow divider
              ValueListenableBuilder<bool>(
                valueListenable: _scrolled,
                builder: (_, isScrolled, _) => AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 1,
                  decoration: BoxDecoration(
                    color: isScrolled
                        ? Colors.grey.shade200
                        : Colors.transparent,
                    boxShadow: isScrolled
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              // Subject list
              Expanded(
                child: Column(
                  children: [
                    if (avgAsync.isLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    if (avgAsync.hasError)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        color: Colors.red.shade50,
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Erreur stats',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(averagesProvider),
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: widget.unit.subjects.isEmpty
                          ? Center(
                              child: Text(
                                'Aucune matière',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                _scrolled.value = n.metrics.pixels > 0;
                                return false;
                              },
                              child: ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  32,
                                ),
                                itemCount: widget.unit.subjects.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, i) {
                                  final subject = widget.unit.subjects[i];
                                  final key =
                                      '${widget.unit.name.cleanName()}|${subject.name.cleanName()}';
                                  final avg = avgMap[key];
                                  return _SubjectCard(
                                    subject: subject,
                                    hasData: avg != null,
                                    onTap: () => _showSubjectStats(
                                      context,
                                      subject,
                                      avg,
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
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
  final bool hasData;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.subject,
    required this.onTap,
    this.hasData = false,
  });

  @override
  Widget build(BuildContext context) {
    final subjectColor = GradeUtils.getColor(subject.average);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
                          const SizedBox(width: 4),
                          Icon(
                            Icons.bar_chart_outlined,
                            size: 14,
                            color: hasData
                                ? AppColors.textMuted
                                : Colors.grey.shade300,
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

// ---------------------------------------------------------------------------
// Subject stats bottom sheet
// ---------------------------------------------------------------------------

class _SubjectStatsSheet extends StatelessWidget {
  final Subject subject;
  final SubjectAverage? avg;

  const _SubjectStatsSheet({required this.subject, required this.avg});

  @override
  Widget build(BuildContext context) {
    final gradeColor = GradeUtils.getColor(subject.average);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Header: subject name + user grade
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleCase(subject.name),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    subject.average != null
                        ? Text(
                            'Ma note: ${subject.average!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: gradeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Text(
                            'Pas encore de note',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                  ],
                ),
              ),
              _CoeffPill(coeff: subject.coeff),
            ],
          ),
          const SizedBox(height: 20),
          // Histogram or placeholder
          if (avg == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Statistiques non disponibles',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Soyez le premier à partager vos notes !',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 160,
              child: _GradeHistogram(
                buckets: avg!.buckets,
                myGrade: subject.average,
              ),
            ),
          const SizedBox(height: 20),
          // Stats row
          if (avg != null)
            Row(
              children: [
                _StatCell(label: 'Moy', value: avg!.avg.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(
                  label: 'Médiane',
                  value: avg!.median.toStringAsFixed(1),
                ),
                _StatDivider(),
                _StatCell(label: 'Min', value: avg!.min.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(label: 'Max', value: avg!.max.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(label: 'Élèves', value: avg!.count.toString()),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: Colors.grey.shade200);
  }
}

// ---------------------------------------------------------------------------
// Grade histogram (CustomPainter)
// ---------------------------------------------------------------------------

class _GradeHistogram extends StatelessWidget {
  final List<int> buckets;
  final double? myGrade;

  const _GradeHistogram({required this.buckets, this.myGrade});

  static int? _bucketIndex(double grade) {
    if (grade < 0 || grade > 20) return null;
    return grade.floor().clamp(0, 19);
  }

  @override
  Widget build(BuildContext context) {
    final myBucket = myGrade != null ? _bucketIndex(myGrade!) : null;
    final myBucketColor = GradeUtils.getColor(myGrade);

    return CustomPaint(
      painter: _HistogramPainter(
        buckets: buckets,
        myBucket: myBucket,
        myBucketColor: myBucketColor,
      ),
      size: Size.infinite,
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> buckets;
  final int? myBucket;
  final Color myBucketColor;

  _HistogramPainter({
    required this.buckets,
    required this.myBucket,
    required this.myBucketColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 20.0;
    const barInset = 1.5; // gap between tick and bar edge

    final maxCount = buckets.fold<int>(0, (m, b) => b > m ? b : m);
    if (maxCount == 0) return;

    final n = buckets.length; // 20
    // Each bar occupies an equal slot; label centered under bar center
    final slotWidth = size.width / n;
    final barWidth = slotWidth - barInset * 2;

    final barPaint = Paint()..style = PaintingStyle.fill;
    final labelStyle = TextStyle(fontSize: 9, color: Colors.grey.shade500);
    final markerPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final slotCenter = i * slotWidth + slotWidth / 2;
      final barLeft = slotCenter - barWidth / 2;
      final count = buckets[i];

      // Bar
      double barH = count == 0
          ? 0
          : (count / maxCount) * (size.height - labelHeight);
      if (count > 0 && barH < 4) barH = 4;

      final isMyBar = myBucket == i;
      barPaint.color = isMyBar ? myBucketColor : Colors.grey.shade300;

      if (barH > 0) {
        final top = size.height - labelHeight - barH;
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(barLeft, top, barWidth, barH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, barPaint);

        // Triangle marker above user's bar
        if (isMyBar) {
          markerPaint.color = myBucketColor;
          const markerSize = 6.0;
          final path = Path()
            ..moveTo(slotCenter - markerSize / 2, top - 6)
            ..lineTo(slotCenter + markerSize / 2, top - 6)
            ..lineTo(slotCenter, top - 1)
            ..close();
          canvas.drawPath(path, markerPaint);
        }
      }

      // Label every 2 bars: 0, 2, 4, ..., 18
      if (i % 2 == 0 && i < n - 1) {
        final label = i.toString();
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(slotCenter - tp.width / 2, size.height - labelHeight + 4),
        );
      }
    }

    // "20" centered under the last bar (bar 19 = [19,20])
    final lastSlotCenter = (n - 1) * slotWidth + slotWidth / 2;
    final tp20 = TextPainter(
      text: TextSpan(text: '20', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp20.paint(
      canvas,
      Offset(lastSlotCenter - tp20.width / 2, size.height - labelHeight + 4),
    );
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.buckets != buckets ||
      old.myBucket != myBucket ||
      old.myBucketColor != myBucketColor;
}

// ---------------------------------------------------------------------------
// Consent bottom sheet
// ---------------------------------------------------------------------------

class _ConsentSheet extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ConsentSheet({required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.people_outline, size: 40, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Contribuer aux moyennes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Partagez vos notes de façon anonyme pour afficher la moyenne de promo par matière.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          const _BulletPoint('Aucune donnée personnelle identifiable'),
          const _BulletPoint('Calculé à partir des notes partagées'),
          const _BulletPoint('Modifiable à tout moment dans Paramètres'),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Désactiver',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Participer',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
