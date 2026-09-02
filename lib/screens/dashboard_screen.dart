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

part 'dashboard/subject_stats_sheet.dart';

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
  // Guard so we only call requestPermission() once across all DashboardScreen
  // instances in this process lifetime (the widget is recreated on every unlock).
  static bool _notificationPermissionRequested = false;

  void _requestNotificationPermissionOnce() {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    unawaited(NotificationService.requestPermission());
  }

  // Existing users reach the dashboard without passing through onboarding, so
  // the participation step never runs for them. Sharing is opt-in, so prompt
  // once here when consent was never asked, gated on grades being visible so
  // the dialog lands after the user sees their notes rather than over a splash.
  bool _consentPromptShown = false;

  void _maybePromptSharingConsent() {
    if (_consentPromptShown) return;
    final settings = ref.read(settingsProvider);
    if (settings.isLoading || settings.sharingConsentAsked) return;
    // Already opted in elsewhere (e.g. settings screen) with the asked flag not
    // yet persisted: never re-prompt someone who is already sharing.
    if (settings.sharingConsent) return;
    if (!ref.read(gradesProvider).hasData) return;
    _consentPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showSharingConsentDialog());
    });
  }

  Future<void> _showSharingConsentDialog() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Comparez vos notes avec la promo'),
        content: const Text(
          'Partagez vos moyennes de façon anonyme (moyenne par matière, '
          'département, semestre et année) et voyez en retour celles de votre '
          'promo. Votre nom, vos notes individuelles et toute information '
          'personnelle ne sont jamais partagés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non merci'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Participer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setSharingConsent(accepted ?? false);
    await notifier.markConsentAsked();
    // Submit the current snapshot right away if they just opted in.
    if (accepted == true && mounted) _trySubmitGrades();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    // Prompt for sharing consent once when it was never asked (existing users
    // who never saw onboarding's participation step). Fires when settings
    // finish loading and again when grades arrive, whichever is later.
    ref.listen<SettingsState>(
      settingsProvider,
      (_, _) => _maybePromptSharingConsent(),
    );

    ref.listen<GradesState>(gradesProvider, (prev, next) {
      if (prev?.isLoading == true &&
          !next.isLoading &&
          next.hasData &&
          next.error == null) {
        _trySubmitGrades();
        _maybePromptSharingConsent();
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
    final decodedGrades = ref.watch(decodedGradesProvider);

    final academicYear = ref.watch(academicYearProvider);

    // Pre-fetch coefficients for every semester so switching semesters
    // doesn't briefly show unweighted (1.0) averages while they load.
    ref.watch(coefficientsPrefetchProvider);

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

    // When there is nothing to display, distinguish a real problem (unreadable
    // data or a failed fetch) from a legitimately empty payload so the user
    // gets an error + retry instead of a silent "Aucune donnée.".
    String? gridError;
    if (curriculum.isEmpty && !isLoading) {
      final corrupt = gradesState.hasData && decodedGrades == null;
      if (corrupt) {
        gridError = 'Données illisibles. Réessayez pour les recharger.';
      } else if (gradesState.error != null) {
        gridError = 'Impossible de charger les notes.';
      }
    }

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
                          errorMessage: gridError,
                          onRetry: gridError == null
                              ? null
                              : () => ref
                                    .read(gradesProvider.notifier)
                                    .fetchGradesWithStoredCredentials()
                                    .catchError((_) {}),
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
    final ueColor = GradeUtils.getColorForStatus(
      widget.unit.average,
      widget.unit.extractedStatus,
    );
    final ueAveragePrefix = widget.unit.isAverageEstimated ? '≈' : '';
    final ueAverageText = widget.unit.average == null
        ? '–'
        : '$ueAveragePrefix${widget.unit.average!.toStringAsFixed(2)}';

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
                        ueAverageText,
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
    final averagePrefix = subject.isAverageEstimated ? '≈' : '';
    final averageText = subject.average == null
        ? '–'
        : '$averagePrefix${subject.average!.toStringAsFixed(2)}';

    // Screen readers otherwise announce the raw pills; give the whole card a
    // single actionable label (name + average) and mark it a button.
    final semanticLabel = subject.average == null
        ? '${titleCase(subject.name)}, pas encore de note'
        : '${titleCase(subject.name)}, moyenne $averageText sur 20';

    return Semantics(
      button: true,
      label: semanticLabel,
      // Carry the tap action on this node too: excludeSemantics drops the
      // GestureDetector's own descendant tap semantics, so without this the card
      // would be a labelled button that assistive tech cannot activate.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
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
                            // Validation tag (VAL / VALCOMP). Absent when the
                            // school has not published a status for this EC.
                            if (subject.extractedStatus != null) ...[
                              _StatusPill(status: subject.extractedStatus!),
                              const SizedBox(width: 6),
                            ],
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
                                averageText,
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

/// Small colored tag showing an EC's validation status. VAL reads as a plain
/// pass (green), VALCOMP as a pass by compensation (amber), and any other code
/// stays neutral grey.
class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (status.toUpperCase()) {
      'VAL' => (
        Colors.green.shade700,
        Colors.green.shade50,
        Colors.green.shade200,
      ),
      'VALCOMP' => (
        Colors.orange.shade800,
        Colors.orange.shade50,
        Colors.orange.shade200,
      ),
      _ => (Colors.grey.shade600, Colors.grey.shade100, Colors.grey.shade300),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
