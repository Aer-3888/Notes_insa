import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'campus_places.dart';

/// Carte v0: the official plan and a searchable list of the INSA site's
/// buildings until the interactive map ships. The list becomes the search
/// layer over the map later.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openPlan() async {
    final opened = await launchUrl(
      Uri.parse(kCampusPlanUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir le plan.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places =
        ref.watch(campusPlacesProvider).value ?? const <CampusPlace>[];
    final matches = places.where((p) => p.matches(_query.text)).toList();
    final text = context.text;
    final scheme = context.scheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Carte')),
      body: ListView(
        padding: const EdgeInsets.all(CampusSpacing.gutter),
        children: [
          Text(
            'La carte interactive arrive. En attendant :',
            style: text.bodyLarge,
          ),
          const SizedBox(height: CampusSpacing.x4),
          FilledButton.icon(
            onPressed: _openPlan,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ouvrir le plan officiel'),
          ),
          if (places.isNotEmpty) ...[
            const SizedBox(height: CampusSpacing.x6),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un bâtiment, un amphi…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Effacer la recherche',
                        onPressed: () => setState(_query.clear),
                      ),
              ),
            ),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x6),
                child: Text(
                  'Aucun lieu ne correspond.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final kind in PlaceKind.values)
              if (matches.any((p) => p.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: CampusSpacing.x5,
                    bottom: CampusSpacing.x1,
                  ),
                  child: Text(
                    kind.label,
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final place in matches.where((p) => p.kind == kind))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: CampusSpacing.x10,
                      child: Text(
                        place.code,
                        style: context.campusType.numeral,
                        semanticsLabel: 'Bâtiment ${place.code}',
                      ),
                    ),
                    title: Text(place.name),
                  ),
              ],
          ],
        ],
      ),
    );
  }
}
