import 'package:flutter/foundation.dart';

import '../../core/search_text.dart';
import '../../core/time.dart';

/// What kind of association this is, for grouping and filtering the list.
enum AssociationCategory {
  bde,
  sport,
  culture,
  tech,
  solidarite,
  media,
  filiere,
  autre;

  static AssociationCategory parse(String? raw) {
    for (final value in AssociationCategory.values) {
      if (value.name == raw) return value;
    }
    return AssociationCategory.autre;
  }

  String get label => switch (this) {
    AssociationCategory.bde => 'Vie étudiante',
    AssociationCategory.sport => 'Sport',
    AssociationCategory.culture => 'Culture',
    AssociationCategory.tech => 'Technique',
    AssociationCategory.solidarite => 'Solidarité',
    AssociationCategory.media => 'Médias',
    AssociationCategory.filiere => 'Filières',
    AssociationCategory.autre => 'Autres',
  };
}

/// Where an association can be reached. Every field is optional: most
/// associations publish two or three of these, never all of them.
@immutable
class AssociationLinks {
  const AssociationLinks({
    this.instagram,
    this.website,
    this.email,
    this.discord,
    this.facebook,
  });

  /// Handle without the @, as it appears in the profile URL.
  final String? instagram;
  final String? website;
  final String? email;
  final String? discord;
  final String? facebook;

  bool get isEmpty =>
      instagram == null &&
      website == null &&
      email == null &&
      discord == null &&
      facebook == null;

  Uri? get instagramUri => instagram == null
      ? null
      : Uri.parse('https://www.instagram.com/$instagram/');

  static AssociationLinks fromJson(Object? raw) {
    if (raw is! Map) return const AssociationLinks();
    String? text(String key) {
      final value = raw[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return AssociationLinks(
      // Tolerated so a pasted "@ktulu" does not become a broken profile URL.
      instagram: text('instagram')?.replaceFirst(RegExp(r'^@'), ''),
      website: text('website'),
      email: text('email'),
      discord: text('discord'),
      facebook: text('facebook'),
    );
  }
}

/// One dated happening. Past events are kept: they are what tells a student
/// what an association actually does.
@immutable
class AssociationEvent {
  const AssociationEvent({
    required this.id,
    required this.associationId,
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.description,
    this.location,
    this.buildingCode,
    this.url,
  });

  final String id;
  final String associationId;
  final String title;

  /// Campus wall-clock time. The seed carries ISO 8601 without a zone, so it
  /// is reinterpreted as Europe/Paris rather than the device's own timezone.
  final DateTime startsAt;
  final DateTime? endsAt;

  final String? description;

  /// Free text, shown as written: "Halle Francis Querné", "Bar de l'INSA".
  final String? location;

  /// Building number on the INSA plan, when the event has one. Drives the
  /// map action, same as a schedule room.
  final String? buildingCode;

  final String? url;

  bool isPast(DateTime now) => (endsAt ?? startsAt).isBefore(now);

  static AssociationEvent? fromJson(Object? raw, String associationId) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final startsAt = DateTime.tryParse(raw['startsAt'] as String? ?? '');
    if (id is! String || id.isEmpty) return null;
    if (title is! String || title.isEmpty) return null;
    if (startsAt == null) return null;

    String? text(String key) {
      final value = raw[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final endsAt = DateTime.tryParse(raw['endsAt'] as String? ?? '');
    return AssociationEvent(
      id: id,
      associationId: associationId,
      title: title.trim(),
      startsAt: campusInstant(startsAt),
      // An end before the start is worse than no end at all.
      endsAt: endsAt != null && endsAt.isAfter(startsAt)
          ? campusInstant(endsAt)
          : null,
      description: text('description'),
      location: text('location'),
      buildingCode: text('buildingCode'),
      url: text('url'),
    );
  }
}

@immutable
class Association {
  const Association({
    required this.id,
    required this.name,
    required this.category,
    this.shortName,
    this.summary,
    this.description,
    this.logoAsset,
    this.buildingCode,
    this.links = const AssociationLinks(),
    this.events = const <AssociationEvent>[],
  });

  /// Stable slug. Follows and notifications key on it, so it must survive a
  /// rename of [name].
  final String id;
  final String name;
  final AssociationCategory category;

  /// Used where [name] does not fit, such as the today card.
  final String? shortName;

  /// One line for the list row.
  final String? summary;

  /// The longer text on the detail page.
  final String? description;

  /// Path under assets/images/associations, null until a logo is added.
  final String? logoAsset;

  /// Building on the INSA plan where the association is based, when it has one.
  final String? buildingCode;

  final AssociationLinks links;
  final List<AssociationEvent> events;

  String get displayName => shortName ?? name;

  List<AssociationEvent> upcoming(DateTime now) =>
      events.where((e) => !e.isPast(now)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  List<AssociationEvent> past(DateTime now) =>
      events.where((e) => e.isPast(now)).toList()
        ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

  bool matches(String query) {
    final q = foldForSearch(query);
    if (q.isEmpty) return true;
    return foldForSearch(name).contains(q) ||
        foldForSearch(shortName ?? '').contains(q) ||
        foldForSearch(summary ?? '').contains(q);
  }

  static Association? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;

    String? text(String key) {
      final value = raw[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final rawEvents = raw['events'];
    return Association(
      id: id,
      name: name.trim(),
      category: AssociationCategory.parse(raw['category'] as String?),
      shortName: text('shortName'),
      summary: text('summary'),
      description: text('description'),
      logoAsset: text('logoAsset'),
      buildingCode: text('buildingCode'),
      links: AssociationLinks.fromJson(raw['links']),
      events: rawEvents is! List
          ? const <AssociationEvent>[]
          : <AssociationEvent>[
              for (final event in rawEvents)
                ?AssociationEvent.fromJson(event, id),
            ],
    );
  }
}
