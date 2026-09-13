import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models.dart';
import '../../providers/dashboard_providers.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'grades_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/averages_provider.dart';
import '../../providers/coefficients_provider.dart';
import '../../components/dashboard_header.dart';
import '../../components/grades_view_menu.dart';
import '../../components/grades_views.dart';
import '../../providers/grades_view_mode_provider.dart';
import '../../services/averages_service.dart';
import '../../services/notification_service.dart';

part 'dashboard/subject_stats_sheet.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  /// Called when 2FA is required and no OTP secret is stored.
  /// The caller should navigate to the login screen.
  final VoidCallback? onReauthRequired;

  const DashboardScreen({super.key, this.onReauthRequired});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
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
          FilledButton(
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
    // but not permanently, calling it on every DashboardScreen init (every
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
    final scheme = Theme.of(context).colorScheme;
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: Icon(Icons.lock_outline, color: scheme.error),
        content: const Text('Une double authentification est requise.'),
        actions: [
          TextButton(
            onPressed: () {
              messenger.clearMaterialBanners();
              widget.onReauthRequired?.call();
            },
            child: const Text('Se reconnecter'),
          ),
        ],
      ),
    );
  }

  void _showCooldownMessage(int secs) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Actualisable dans $secs s'),
          duration: const Duration(seconds: 2),
        ),
      );
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
      _showCooldownMessage(remaining?.inSeconds ?? 0);
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
      useSafeArea: true,
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

    // When there is nothing to display, distinguish a real problem (unreadable
    // data or a failed fetch) from a legitimately empty payload so the user
    // gets an error + retry instead of a silent "Aucune donnée.".
    String? gridError;
    if (curriculum.isEmpty && !isLoading) {
      final corrupt = gradesState.hasData && decodedGrades == null;
      if (corrupt) {
        gridError = 'Données illisibles. Réessayez pour les recharger.';
      } else if (gradesState.error != null) {
        gridError =
            'Impossible de joindre le portail. Vérifiez la connexion, '
            'puis réessayez.';
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Builder(
              builder: (context) => DashboardHeader(
                title: 'Notes',
                titleWidget: const GradesViewMenu(),
                subtitle: departmentName,
                average: semesterAverage,
                provisional: ref.watch(semesterAverageProvisionalProvider),
                lastUpdated: lastUpdated,
                selectedSemester: effectiveSemester ?? 0,
                availableSemesters: ref.watch(availableSemestersProvider),
                onSemesterChanged: (newSem) {
                  ref.read(selectedSemesterProvider.notifier).state = newSem;
                },
              ),
            ),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: _swipeSemester,
                behavior: HitTestBehavior.opaque,
                child: RefreshIndicator(
                  onRefresh: () => _onManualRefresh(context),
                  child: GradesViews(
                    key: ValueKey(effectiveSemester),
                    mode: ref.watch(gradesViewModeProvider),
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
      useSafeArea: true,
      builder: (_) => _SubjectStatsSheet(subject: subject, avg: avg),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CampusSpacing.gutter,
                CampusSpacing.x1,
                CampusSpacing.gutter,
                CampusSpacing.x4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleCase(widget.unit.name),
                          style: context.text.titleLarge,
                        ),
                        const SizedBox(height: CampusSpacing.x2),
                        _StatusChip(
                          validated: widget.unit.isValidated,
                          label: widget.unit.isValidated
                              ? 'Validé'
                              : 'En cours',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CampusSpacing.x3),
                  Text(
                    ueAverageText,
                    style: context.campusType.displayNumeral.copyWith(
                      fontSize: 32,
                      height: 36 / 32,
                      color:
                          GradeUtils.needsAttention(
                            widget.unit.average,
                            widget.unit.extractedStatus,
                          )
                          ? context.scheme.error
                          : context.scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            // Scroll shadow divider
            ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (_, isScrolled, _) => AnimatedContainer(
                duration: CampusMotion.of(context, CampusMotion.fast),
                height: 1,
                color: isScrolled
                    ? context.scheme.outlineVariant
                    : Colors.transparent,
              ),
            ),
            // Subject list
            Expanded(
              child: Column(
                children: [
                  if (avgAsync.isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (avgAsync.hasError)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: context.scheme.error,
                      ),
                      title: const Text('Statistiques indisponibles'),
                      trailing: TextButton(
                        onPressed: () => ref.invalidate(averagesProvider),
                        child: const Text('Réessayer'),
                      ),
                    ),
                  Expanded(
                    child: widget.unit.subjects.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune matière',
                              style: context.text.bodyMedium?.copyWith(
                                color: context.scheme.onSurfaceVariant,
                              ),
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
                                  onTap: () =>
                                      _showSubjectStats(context, subject, avg),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
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
    final scheme = context.scheme;
    final attention = GradeUtils.needsAttention(
      subject.average,
      subject.extractedStatus,
    );
    final averagePrefix = subject.isAverageEstimated ? '\u2248' : '';
    final averageText = subject.average == null
        ? '\u2013'
        : '$averagePrefix${subject.average!.toStringAsFixed(2)}';

    // Screen readers otherwise announce the raw chips; give the whole card a
    // single actionable label (name + average) and mark it a button.
    final semanticLabel = subject.average == null
        ? '${titleCase(subject.name)}, pas encore de note'
        : '${titleCase(subject.name)}, moyenne $averageText sur 20';

    return Semantics(
      button: true,
      label: semanticLabel,
      // Carry the tap action on this node too: excludeSemantics drops the
      // descendant tap semantics, so without this the card would be a labelled
      // button that assistive tech cannot activate.
      onTap: onTap,
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(CampusSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        titleCase(subject.name),
                        style: context.text.titleMedium,
                      ),
                    ),
                    const SizedBox(width: CampusSpacing.x2),
                    Text(
                      averageText,
                      style: context.campusType.numeral.copyWith(
                        color: attention ? scheme.error : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CampusSpacing.x2),
                Row(
                  children: [
                    if (subject.extractedStatus != null) ...[
                      _StatusChip(
                        validated: !GradeUtils.needsAttention(
                          null,
                          subject.extractedStatus,
                        ),
                        label: subject.extractedStatus!,
                      ),
                      const SizedBox(width: CampusSpacing.x2),
                    ],
                    _CoeffChip(coeff: subject.coeff),
                    const Spacer(),
                    if (hasData)
                      Icon(
                        Icons.bar_chart_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                if (subject.grades.isNotEmpty) ...[
                  const SizedBox(height: CampusSpacing.x3),
                  const Divider(),
                  const SizedBox(height: CampusSpacing.x2),
                  ...subject.grades.map((g) => _GradeRow(grade: g)),
                ],
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
    final scheme = context.scheme;
    final attention = GradeUtils.needsAttention(grade.value, null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titleCase(grade.label),
              style: context.text.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (grade.coeff.isNotEmpty) ...[
            const SizedBox(width: CampusSpacing.x2),
            Text(
              '\u00d7${grade.coeff}',
              style: context.text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: CampusSpacing.x3),
          Text(
            grade.value.toStringAsFixed(2),
            semanticsLabel: '${grade.value.toStringAsFixed(2)} sur 20',
            style: context.campusType.numeral.copyWith(
              color: attention ? scheme.error : scheme.onSurface,
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

class _CoeffChip extends StatelessWidget {
  final double coeff;

  const _CoeffChip({required this.coeff});

  @override
  Widget build(BuildContext context) {
    final label = coeff % 1 == 0 ? coeff.toInt().toString() : coeff.toString();
    return Chip(
      label: Text('Coeff $label'),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Validation state as a tonal chip. The label carries the meaning and the fill
/// only reinforces it, so it still reads without colour.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.validated, required this.label});

  final bool validated;
  final String label;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: validated
          ? campus.positiveContainer
          : context.scheme.surfaceContainerHighest,
      labelStyle: context.text.labelMedium?.copyWith(
        color: validated
            ? campus.onPositiveContainer
            : context.scheme.onSurface,
      ),
    );
  }
}
