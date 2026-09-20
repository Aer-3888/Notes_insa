import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/state_view.dart';
import '../ade_breadcrumb.dart';
import '../ade_groups.dart';
import '../ade_groups_provider.dart';
import '../ade_tree.dart';
import '../ade_tree_list.dart';
import '../schedule_provider.dart';
import 'wizard_scaffold.dart';
import 'wizard_step.dart';

/// Asks a short sequence of questions instead of showing 1433 checkboxes.
///
/// The old picker modelled a subscription as an arbitrary set of resource ids,
/// which is not what one is: ADE hands a parent the union of its whole
/// subtree, and a leaf already carries the promo's CMs, so the answer is one
/// deep group per semester plus the few branches that sit beside them.
///
/// The sequence is built rather than fixed. See [WizardStep] for the two
/// shapes in the data that force that.
class GroupWizardScreen extends ConsumerStatefulWidget {
  const GroupWizardScreen({super.key});

  @override
  ConsumerState<GroupWizardScreen> createState() => _GroupWizardScreenState();
}

class _GroupWizardScreenState extends ConsumerState<GroupWizardScreen> {
  int _pageIndex = 0;

  int? _formation;

  /// Insertion-ordered: the group steps that follow run in this order, and the
  /// committed list reads the same way.
  final Set<int> _semestres = <int>{};

  /// Semester id to the group chosen inside it.
  final Map<int, int> _bases = <int, int>{};

  final Set<int> _extras = <int>{};

  /// Where the current step has drilled to, null at its own top level.
  int? _drill;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adeStudentGroupsProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => StateView(
          icon: Icons.cloud_off_outlined,
          title: 'Liste des groupes indisponible',
          body: 'Impossible de charger les groupes ADE. Réessayez plus tard.',
          action: FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(adeGroupsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ),
        data: _buildStep,
      ),
    );
  }

  // ----------------------------------------------------------------- pages

  /// The sequence as it stands, recomputed from the answers so far.
  List<WizardPage> _pages(List<AdeGroup> rows) {
    final pages = <WizardPage>[(kind: WizardStep.formation, semestre: null)];
    final formation = _formation;
    if (formation == null) return pages;
    if (AdeTree.hasSemesters(rows, formation)) {
      pages.add((kind: WizardStep.semestre, semestre: null));
    }
    for (final s in _semestres) {
      pages.add((kind: WizardStep.groupe, semestre: s));
    }
    if (_semestres.isNotEmpty) {
      pages.add((kind: WizardStep.options, semestre: null));
    }
    return pages;
  }

  /// Dropping a semester shortens the sequence under us, so the index is
  /// always read back through the current list.
  int _indexIn(List<WizardPage> pages) => _pageIndex.clamp(0, pages.length - 1);

  // ----------------------------------------------------------------- build

  Widget _buildStep(List<AdeGroup> rows) {
    final pages = _pages(rows);
    final index = _indexIn(pages);
    final page = pages[index];
    // Only the options page finishes. Before a formation is picked the
    // sequence is one page long, which is not the same thing as being done.
    final last = page.kind == WizardStep.options;
    final drilled = _drill;

    return WizardScaffold(
      stepCount: pages.length,
      currentIndex: index,
      title: _title(rows, page),
      subtitle: _subtitle(page),
      onBack: _back,
      breadcrumb: drilled == null ? null : _breadcrumb(rows, page, drilled),
      primaryLabel: last ? 'Terminer' : 'Continuer',
      onPrimary: _canAdvance(page) ? () => _advance(rows) : null,
      child: AdeTreeList(
        rows: rows,
        visible: _visible(rows, page),
        selected: _selected(page),
        mode: page.kind == WizardStep.groupe
            ? AdeTreeSelection.radio
            : AdeTreeSelection.check,
        // The first two steps ask which level you are on, and every answer
        // there has children. Only the last two navigate the tree.
        drillable:
            page.kind == WizardStep.groupe || page.kind == WizardStep.options,
        headerBefore: _headerBefore(rows, page),
        emptyTitle: page.kind == WizardStep.options ? 'Aucune option' : null,
        emptyBody: page.kind == WizardStep.options
            ? 'Vos groupes couvrent déjà tout ce que ces promos publient.'
            : null,
        onToggle: (g) => setState(() => _pick(rows, page, g)),
        onDrill: (g) => setState(() => _drill = g.id),
      ),
    );
  }

  String _title(List<AdeGroup> rows, WizardPage page) => switch (page.kind) {
    WizardStep.formation => 'Votre formation',
    WizardStep.semestre => 'Vos semestres',
    // Named, because this step repeats and two runs look alike otherwise.
    WizardStep.groupe => 'Votre groupe en ${_name(rows, page.semestre)}',
    WizardStep.options => 'Vos options',
  };

  String _subtitle(WizardPage page) => switch (page.kind) {
    WizardStep.formation =>
      'Votre département, ou le master ou parcours que vous suivez.',
    WizardStep.semestre =>
      'Prenez les deux semestres de l’année : ADE les publie séparément, '
          'et sans le second votre emploi du temps sera vide au printemps.',
    WizardStep.groupe =>
      'Choisissez le groupe le plus précis : il contient déjà les cours '
          'de toute la promo.',
    WizardStep.options =>
      'Ce qui ne vient pas avec vos groupes : option, ouverture, langues. '
          'Vous pourrez en ajouter plus tard.',
  };

  String _name(List<AdeGroup> rows, int? id) =>
      rows.where((g) => g.id == id).firstOrNull?.name ?? '';

  /// Section breaks, for the two steps that mix kinds of row.
  String? Function(AdeGroup)? _headerBefore(
    List<AdeGroup> rows,
    WizardPage page,
  ) {
    switch (page.kind) {
      case WizardStep.formation:
        final firstFormation = AdeTree.formations(rows).firstOrNull?.id;
        final firstOther = AdeTree.otherTracks(rows).firstOrNull?.id;
        return (g) => g.id == firstFormation
            ? 'Formations'
            : g.id == firstOther
            ? 'Autres parcours'
            : null;
      case WizardStep.options:
        if (_drill != null) return null;
        final firstOwn = AdeTree.electivesForAll(
          rows,
          _bases.values,
        ).firstOrNull?.id;
        final firstShared = AdeTree.crossCutting(rows).firstOrNull?.id;
        return (g) => g.id == firstOwn
            ? 'Vos promos'
            : g.id == firstShared
            ? 'Langues et humanités'
            : null;
      case WizardStep.semestre || WizardStep.groupe:
        return null;
    }
  }

  Widget _breadcrumb(List<AdeGroup> rows, WizardPage page, int drilled) {
    final root = page.kind == WizardStep.options ? 'Options' : 'Groupes';
    // Only the part below this step's own root: the levels above it were
    // already answered by the earlier steps.
    final from = page.semestre;
    final full = AdeTree.pathTo(rows, drilled);
    final path = from == null
        ? full
        : full.skipWhile((g) => g.id != from).skip(1).toList();
    return AdeBreadcrumb(
      rootLabel: root,
      path: path,
      onRoot: () => setState(() => _drill = null),
      onTap: (g) => setState(() => _drill = g.id),
    );
  }

  List<AdeGroup> _visible(List<AdeGroup> rows, WizardPage page) =>
      switch (page.kind) {
        WizardStep.formation => <AdeGroup>[
          ...AdeTree.formations(rows),
          ...AdeTree.otherTracks(rows),
        ],
        WizardStep.semestre => AdeTree.childrenOf(rows, _formation),
        WizardStep.groupe => AdeTree.childrenOf(rows, _drill ?? page.semestre),
        WizardStep.options =>
          _drill != null
              ? AdeTree.childrenOf(rows, _drill)
              : <AdeGroup>[
                  ...AdeTree.electivesForAll(rows, _bases.values),
                  ...AdeTree.crossCutting(rows),
                ],
      };

  Set<int> _selected(WizardPage page) => switch (page.kind) {
    WizardStep.formation => <int>{?_formation},
    WizardStep.semestre => _semestres,
    WizardStep.groupe => <int>{?_bases[page.semestre]},
    WizardStep.options => _extras,
  };

  // ------------------------------------------------------------- answering

  /// Every answer above the one being changed stays. Everything below it goes,
  /// because it answered a question that no longer applies.
  void _pick(List<AdeGroup> rows, WizardPage page, AdeGroup g) {
    switch (page.kind) {
      case WizardStep.formation:
        if (_formation == g.id) return;
        _formation = g.id;
        _semestres.clear();
        _bases.clear();
        _extras.clear();
        // A formation with no semester level is its own semester, so the
        // group step has something to hang off.
        if (!AdeTree.hasSemesters(rows, g.id)) _semestres.add(g.id);
      case WizardStep.semestre:
        if (_semestres.remove(g.id)) {
          // The group chosen in it answered a question that is now gone.
          _bases.remove(g.id);
        } else {
          _semestres.add(g.id);
        }
        _extras.clear();
      case WizardStep.groupe:
        final semestre = page.semestre;
        if (semestre == null || _bases[semestre] == g.id) return;
        _bases[semestre] = g.id;
        _extras.clear();
      case WizardStep.options:
        _extras.contains(g.id) ? _extras.remove(g.id) : _extras.add(g.id);
    }
  }

  bool _canAdvance(WizardPage page) => switch (page.kind) {
    WizardStep.formation => _formation != null,
    WizardStep.semestre => _semestres.isNotEmpty,
    WizardStep.groupe => _bases[page.semestre] != null,
    WizardStep.options => true,
  };

  // ------------------------------------------------------------ navigating

  Future<void> _advance(List<AdeGroup> rows) async {
    final pages = _pages(rows);
    if (pages[_indexIn(pages)].kind != WizardStep.options) {
      setState(() {
        _pageIndex = _indexIn(pages) + 1;
        _drill = null;
      });
      return;
    }
    // Bases first, in the order the semesters were chosen, so the summary and
    // any shared link read the way the wizard was answered.
    await ref.read(selectedGroupsProvider.notifier).set(<int>[
      for (final s in _semestres) ?_bases[s],
      ..._extras,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  /// Inside a drilled step, back climbs one level first. Only once it is at
  /// that step's own top level does it move to the previous question, and on
  /// the first question it leaves.
  void _back() {
    final rows = ref.read(adeStudentGroupsProvider).value ?? const <AdeGroup>[];
    final pages = _pages(rows);
    final page = pages[_indexIn(pages)];
    final drilled = _drill;
    if (drilled != null) {
      final path = AdeTree.pathTo(rows, drilled);
      final above = path.length >= 2 ? path[path.length - 2].id : null;
      // Reaching this step's own root means the drill is over rather than one
      // more level up.
      setState(() => _drill = above == page.semestre ? null : above);
      return;
    }
    if (_indexIn(pages) == 0) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    setState(() => _pageIndex = _indexIn(pages) - 1);
  }
}
