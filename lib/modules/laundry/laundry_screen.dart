import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'laundry_model.dart';
import 'laundry_provider.dart';

/// Refresh cadence while the screen is open and in the foreground.
const Duration _cadence = Duration(seconds: 30);

/// Auto refresh stops after this long, so a screen left open does not poll all
/// day. The user resumes with a pull or the "Reprendre" button.
const Duration _idleCutoff = Duration(minutes: 4);

/// Fixed machine cell size, so every machine reads as the same little card.
const double _cellWidth = 58;
const double _cellHeight = 54;

class LaundryScreen extends ConsumerStatefulWidget {
  const LaundryScreen({super.key});

  @override
  ConsumerState<LaundryScreen> createState() => _LaundryScreenState();
}

class _LaundryScreenState extends ConsumerState<LaundryScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _autoStartedAt = DateTime.now();
  bool _idle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAuto();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_idle) _startAuto();
    } else {
      _timer?.cancel();
    }
  }

  void _startAuto() {
    _timer?.cancel();
    _autoStartedAt = DateTime.now();
    if (_idle && mounted) setState(() => _idle = false);
    _timer = Timer.periodic(_cadence, (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    if (DateTime.now().difference(_autoStartedAt) >= _idleCutoff) {
      _timer?.cancel();
      _timer = null;
      setState(() => _idle = true);
      return;
    }
    ref.invalidate(laundryProvider);
  }

  Future<void> _refresh() async {
    _startAuto();
    ref.invalidate(laundryProvider);
    await ref.read(laundryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(laundryProvider);
    final status = async.value;

    final Widget body;
    if (status != null) {
      body = _StatusView(status: status, idle: _idle, onResume: _refresh);
    } else if (async.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = StateView(
        icon: Icons.local_laundry_service_outlined,
        title: 'Laverie indisponible',
        body: 'Impossible de récupérer l’état des machines pour le moment.',
        action: FilledButton.tonalIcon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Laverie')),
      body: RefreshIndicator(onRefresh: _refresh, child: body),
    );
  }
}

/// Splits the screen into top/bottom halves, one site each. Each card is at
/// least half the viewport, so in portrait the two fill the screen exactly; if
/// a card is too tall to fit (short or landscape screens) it grows and the page
/// scrolls instead of overflowing. Pull to refresh stays available throughout.
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.status,
    required this.idle,
    required this.onResume,
  });

  final LaundryStatus status;
  final bool idle;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = status.sites.length;
        final gaps = CampusSpacing.x3 * (count - 1);
        final half =
            (constraints.maxHeight - CampusSpacing.gutter * 2 - gaps) / count;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(CampusSpacing.gutter),
          children: <Widget>[
            if (idle)
              _Banner(
                icon: Icons.pause_circle_outline,
                text: 'Actualisation en pause',
                action: TextButton(
                  onPressed: () => onResume(),
                  child: const Text('Reprendre'),
                ),
              )
            else if (status.stale)
              const _Banner(
                icon: Icons.cloud_off_outlined,
                text: 'Hors ligne, données récentes.',
              ),
            for (var i = 0; i < count; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: CampusSpacing.x3),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: half > 0 ? half : 0),
                child: _SiteCard(site: status.sites[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site});

  final LaundrySite site;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (String title, String? sub) = _splitName(site.name);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(CampusSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CampusSpacing.x3),
            _GroupGrid(
              icon: Icons.local_laundry_service_outlined,
              label: 'Lave-linge',
              group: site.washers,
            ),
            const SizedBox(height: CampusSpacing.x4),
            _GroupGrid(
              icon: Icons.dry_cleaning_outlined,
              label: 'Sèche-linge',
              group: site.dryers,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupGrid extends StatelessWidget {
  const _GroupGrid({
    required this.icon,
    required this.label,
    required this.group,
  });

  final IconData icon;
  final String label;
  final LaundryGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasFree = group.free > 0;
    final unavailable = group.total == 0;
    final availability = unavailable
        ? 'Indisponible'
        : group.free == 0
        ? 'Complet'
        : '${group.free}/${group.total} libres';
    final availabilityBackground = unavailable
        ? scheme.surfaceContainerHighest
        : hasFree
        ? context.campus.positiveContainer
        : context.campus.attentionContainer;
    final availabilityForeground = unavailable
        ? scheme.onSurfaceVariant
        : hasFree
        ? context.campus.onPositiveContainer
        : context.campus.onAttentionContainer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: CampusSpacing.x2),
            Expanded(child: Text(label, style: text.labelMedium)),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CampusSpacing.x2,
                vertical: CampusSpacing.x1 / 2,
              ),
              decoration: BoxDecoration(
                color: availabilityBackground,
                borderRadius: CampusRadii.controlRadius,
              ),
              child: Text(
                availability,
                style: text.labelMedium?.copyWith(
                  color: availabilityForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CampusSpacing.x3),
        Wrap(
          spacing: CampusSpacing.x2,
          runSpacing: CampusSpacing.x2,
          children: <Widget>[
            for (final machine in group.machines)
              _MachineCell(machine: machine),
          ],
        ),
      ],
    );
  }
}

class _MachineCell extends StatelessWidget {
  const _MachineCell({required this.machine});

  final LaundryMachine machine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _stateColor(machine.state, context.campus, scheme);
    final text = Theme.of(context).textTheme;
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(CampusRadii.control),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            machine.name,
            style: text.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
          ),
          Text(
            _statusShort(machine),
            style: text.labelSmall?.copyWith(color: color),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: CampusSpacing.x3),
      padding: EdgeInsets.fromLTRB(
        CampusSpacing.x4,
        CampusSpacing.x2,
        action == null ? CampusSpacing.x4 : CampusSpacing.x2,
        CampusSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: CampusRadii.cardRadius,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: CampusSpacing.x3),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

String _statusShort(LaundryMachine m) {
  switch (m.state) {
    case LaundryMachineState.free:
      return 'Libre';
    case LaundryMachineState.busy:
      final minutes = (m.secLeft / 60).ceil();
      return minutes > 0 ? '$minutes′' : 'En cours';
    case LaundryMachineState.finished:
      return 'Fini';
    case LaundryMachineState.reserved:
      return 'Rés.';
    case LaundryMachineState.broken:
      return 'HS';
    case LaundryMachineState.unknown:
      return '?';
  }
}

/// "Les Glénans (Bât 16)" -> ("Les Glénans", "Bât 16").
(String, String?) _splitName(String name) {
  final open = name.indexOf('(');
  if (open == -1) return (name.trim(), null);
  final title = name.substring(0, open).trim();
  final sub = name.substring(open + 1).replaceAll(')', '').trim();
  return (title.isEmpty ? name.trim() : title, sub.isEmpty ? null : sub);
}

/// Colour per state, from the campus tokens so both themes stay legible.
/// A broken machine intentionally uses neutral ink: the theme's error and
/// attention roles share a hue, while a running cycle needs to stay distinct
/// from one that is unavailable.
Color _stateColor(
  LaundryMachineState state,
  CampusColors campus,
  ColorScheme scheme,
) => switch (state) {
  LaundryMachineState.free => campus.positive,
  LaundryMachineState.busy => campus.attention,
  LaundryMachineState.finished => campus.now,
  LaundryMachineState.broken => scheme.onSurface,
  LaundryMachineState.reserved ||
  LaundryMachineState.unknown => scheme.onSurfaceVariant,
};
