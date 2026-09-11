import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/freshness.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'library_provider.dart';
import 'library_site.dart';

/// Opens a booking page. Injected so the tap can be tested without the plugin.
typedef LibraryLinkOpener = Future<bool> Function(Uri uri);

Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// A manual refresh cannot be spammed: the upstream has no published limit.
const Duration _manualRefreshCooldown = Duration(seconds: 60);

/// How full the two libraries are, and one tap to book a study room.
class LibraryTodayCard extends ConsumerStatefulWidget {
  const LibraryTodayCard({super.key, this.openLink = _openExternally});

  final LibraryLinkOpener openLink;

  @override
  ConsumerState<LibraryTodayCard> createState() => _LibraryTodayCardState();
}

class _LibraryTodayCardState extends ConsumerState<LibraryTodayCard> {
  DateTime? _lastManualRefresh;

  void _refresh() {
    final now = DateTime.now();
    final last = _lastManualRefresh;
    if (last != null && now.difference(last) < _manualRefreshCooldown) return;
    _lastManualRefresh = now;
    ref.read(libraryRefreshTickProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(libraryStatusProvider);
    final entry = async.value;
    final sites = entry?.data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x2,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CampusSpacing.x4,
                  CampusSpacing.x1,
                  CampusSpacing.x2,
                  CampusSpacing.x1,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.menu_book_outlined, size: 20),
                    const SizedBox(width: CampusSpacing.x3),
                    Expanded(
                      child: Text(
                        'Bibliothèques',
                        style: context.text.titleSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _refresh,
                      tooltip: 'Actualiser l’affluence',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              if (sites != null && sites.isNotEmpty)
                for (final status in sites)
                  _LibraryRow(
                    status: status,
                    onBook: () =>
                        widget.openLink(Uri.parse(status.site.bookingUrl)),
                  )
              else if (async.isLoading)
                const _Message(text: 'Chargement de l’affluence…')
              else
                _Message(
                  text: 'Affluence indisponible',
                  action: TextButton(
                    onPressed: _refresh,
                    child: const Text('Réessayer'),
                  ),
                ),
              if (entry != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CampusSpacing.x4,
                    CampusSpacing.x1,
                    CampusSpacing.x4,
                    CampusSpacing.x2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Source Affluences · '
                      '${freshnessLabel(entry.refreshState, entry.cachedAt)}',
                      style: context.text.labelSmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
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

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.x4,
        CampusSpacing.x2,
        CampusSpacing.x2,
        CampusSpacing.x2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.status, required this.onBook});

  final LibraryStatus status;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final crowdColor = switch (status.crowd) {
      LibraryCrowd.calm => context.campus.positive,
      LibraryCrowd.busy => context.scheme.onSurface,
      LibraryCrowd.packed => context.campus.attention,
      LibraryCrowd.closed ||
      LibraryCrowd.unknown => context.scheme.onSurfaceVariant,
    };
    final gaugeColor = status.crowd == LibraryCrowd.busy
        ? context.campus.now
        : crowdColor;
    final gauge = status.gauge;
    final hint = status.forecastHint;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.x4,
        vertical: CampusSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: CampusSpacing.x2),
            child: Container(
              width: CampusSpacing.x2,
              height: CampusSpacing.x2,
              decoration: BoxDecoration(
                color: status.isOpen
                    ? context.campus.positive
                    : context.scheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: CampusSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        status.site.shortName,
                        style: context.text.labelLarge,
                      ),
                    ),
                    Text(
                      status.occupancyLabel,
                      style: context.text.labelMedium?.copyWith(
                        color: crowdColor,
                      ),
                    ),
                  ],
                ),
                if (gauge != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CampusSpacing.x2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(CampusRadii.bar),
                      child: LinearProgressIndicator(
                        value: gauge,
                        minHeight: CampusSpacing.x1,
                        backgroundColor: context.scheme.surfaceContainerHighest,
                        color: gaugeColor,
                      ),
                    ),
                  ),
                if (status.statusLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CampusSpacing.x1),
                    child: Text(
                      status.statusLabel!,
                      style: context.text.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (hint != null)
                  Text(
                    hint,
                    style: context.text.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                for (final notice in status.notices)
                  Text(
                    notice,
                    style: context.text.bodySmall?.copyWith(
                      color: context.campus.attention,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CampusSpacing.x2),
          TextButton(onPressed: onBook, child: const Text('Réserver')),
        ],
      ),
    );
  }
}
