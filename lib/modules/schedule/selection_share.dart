import 'ade_link.dart';

/// Turns a selection into a link someone else can use.
///
/// The link is an ade-planning `view` URL rather than anything of our own, and
/// that is deliberate: it opens the school's web timetable for anyone who taps
/// it, and [AdeLink.parseIds] already reads this exact shape back, so a
/// selection travels through a promo group chat without either side needing a
/// deep link to be registered first.
class SelectionShare {
  const SelectionShare._();

  static const String _origin = 'https://ade-planning.insa-rennes.fr';

  /// Empty when there is nothing to share, so callers can disable the action
  /// on the same check.
  static String buildUrl(List<int> ids) {
    if (ids.isEmpty) return '';
    // Trimmed to the ceiling ADE itself accepts, or the link would 404 for
    // whoever opened it.
    final capped = ids.length > AdeLink.maxIds
        ? ids.sublist(0, AdeLink.maxIds)
        : ids;
    return '$_origin/view/${capped.join(',')}/';
  }
}
