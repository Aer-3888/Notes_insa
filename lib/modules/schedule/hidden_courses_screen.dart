import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'course_picker_screen.dart';
import 'hidden_courses_provider.dart';
import 'hide_rule.dart';
import 'schedule_event.dart';

/// What a custom filter can match on, and how to ask for it.
enum _CustomField {
  teacher(HideField.teacher, 'Enseignant', 'Nom de l’enseignant'),
  titleContains(
    HideField.titleContains,
    'Intitulé contient',
    'Texte à exclure',
  ),
  room(HideField.room, 'Salle', 'Salle ou bâtiment');

  const _CustomField(this.field, this.label, this.hint);

  final HideField field;
  final String label;
  final String hint;

  HideRule ruleFor(String value) => switch (field) {
    HideField.teacher => HideRule.teacher(value),
    HideField.room => HideRule.room(value),
    _ => HideRule.titleContains(value),
  };
}

String _fieldLabel(HideField field) => switch (field) {
  HideField.series => 'Série',
  HideField.module => 'Module',
  HideField.occurrence => 'Séance',
  HideField.teacher => 'Enseignant',
  HideField.titleContains => 'Intitulé',
  HideField.room => 'Salle',
  HideField.nonCourse => 'Préréglage',
};

/// The two ways a course leaves the timetable, one section each.
///
/// Switching a series off in the catalogue stores a rule like any other, but
/// listing those here as well would put a row on this screen for every switch
/// on that one, and the catalogue shows them where they mean something. So
/// this screen counts them and links out, and keeps the list for the filters
/// that have nowhere else to live.
class HiddenCoursesScreen extends ConsumerWidget {
  const HiddenCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(hiddenRulesProvider);
    final modules = ref.watch(courseModulesProvider);
    final events = eventsOfModules(modules);
    final notifier = ref.read(hiddenRulesProvider.notifier);
    final hasNonCourse = rules.contains(const HideRule.nonCourse());
    final hidden = hiddenSeriesCount(modules, rules);
    // The catalogue shows its own rules, and the preset has its own switch
    // below, so neither is repeated as a row here.
    final filters = <HideRule>[
      for (final rule in rules)
        if (!isCatalogueRule(rule) && rule.field != HideField.nonCourse) rule,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cours masqués'),
        actions: <Widget>[
          if (rules.isNotEmpty)
            TextButton(
              onPressed: () => unawaited(notifier.clear()),
              child: const Text('Tout afficher'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
        children: <Widget>[
          const _SectionHeader('Cours'),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('Parcourir les cours de la période'),
            subtitle: Text(_moduleCount(modules)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPicker(context),
          ),
          if (hidden > 0)
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(
                hidden == 1 ? '1 série masquée' : '$hidden séries masquées',
              ),
              subtitle: const Text('Revoir ce qui est retiré du planning'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openPicker(context, CourseFilter.hidden),
            )
          else
            const _Hint(
              'Appuyez longuement sur un cours de l’emploi du temps pour le '
              'retirer, ou parcourez le catalogue ci-dessus.',
            ),

          const _SectionHeader('Filtres'),
          if (filters.isEmpty)
            const _Hint(
              'Un filtre masque d’un coup tout ce qui correspond à un '
              'enseignant, une salle ou un intitulé.',
            ),
          for (final rule in filters)
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: Text(rule.label),
              subtitle: Text(
                '${_fieldLabel(rule.field)} · ${_reach(rule, events)}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Retirer le filtre',
                onPressed: () => unawaited(notifier.remove(rule)),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Ajouter un filtre'),
            onTap: () => unawaited(_addRule(context, ref)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.campaign_outlined),
            title: const Text('Masquer les événements hors cours'),
            subtitle: Text(
              hasNonCourse
                  ? _reach(const HideRule.nonCourse(), events)
                  : 'Réunions et distributions que ADE publie sans module',
            ),
            value: hasNonCourse,
            onChanged: (on) => unawaited(
              on
                  ? notifier.add(const HideRule.nonCourse())
                  : notifier.remove(const HideRule.nonCourse()),
            ),
          ),
        ],
      ),
    );
  }

  static void _openPicker(BuildContext context, [CourseFilter? filter]) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CoursePickerScreen(initialFilter: filter ?? CourseFilter.all),
        ),
      );

  /// How far a rule actually reaches, so a teacher or a room filter shows its
  /// scope before it has to be tested.
  ///
  /// Nothing matched means the courses it was written for are outside the
  /// loaded window, not that the filter is broken.
  static String _reach(HideRule rule, List<ScheduleEvent> events) {
    final matched = events.where(rule.matches).length;
    return switch (matched) {
      0 => 'Aucune séance dans la période chargée',
      1 => '1 séance masquée',
      _ => '$matched séances masquées',
    };
  }

  static String _moduleCount(List<CourseModule> modules) {
    if (modules.isEmpty) return 'Aucun cours chargé';
    final series = modules.fold(0, (total, m) => total + m.series.length);
    final modulePart = modules.length == 1
        ? '1 module'
        : '${modules.length} modules';
    final seriesPart = series == 1 ? '1 série' : '$series séries';
    return '$modulePart · $seriesPart';
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final rule = await showDialog<HideRule>(
      context: context,
      builder: (_) => const _RuleDialog(),
    );
    if (rule == null) return;
    await ref.read(hiddenRulesProvider.notifier).add(rule);
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  _CustomField _field = _CustomField.titleContains;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouveau filtre'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<_CustomField>(
          segments: <ButtonSegment<_CustomField>>[
            for (final field in _CustomField.values)
              ButtonSegment<_CustomField>(
                value: field,
                label: Text(field.label),
              ),
          ],
          selected: <_CustomField>{_field},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _field = s.first),
        ),
        const SizedBox(height: CampusSpacing.x4),
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _field.hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Masquer')),
    ],
  );

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(_field.ruleFor(value));
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: CampusSpacing.gutter,
      vertical: CampusSpacing.x2,
    ),
    child: Text(
      text,
      style: context.text.bodyMedium?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x5,
      CampusSpacing.gutter,
      CampusSpacing.x2,
    ),
    child: Text(
      title,
      style: context.text.labelLarge?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}
