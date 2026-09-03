/// Extracts ADE resource ids from a pasted link.
///
/// Students who already use the ade-planning web app have a curated selection
/// in their URL, sometimes twenty subgroups deep. Retyping that into a picker is
/// worse than pasting it, and the ids are the same ones INSA's ADE uses.
///
/// Handles the shapes seen in the wild:
///   https://ade-planning.insa-rennes.fr/view/1214,133,136/
///   .../anonymous_cal.jsp?resources=2152,248&projectId=2
///   a bare "2152,248"
class AdeLink {
  const AdeLink._();

  /// Matches the ade-planning web app's own MAX_SELECT, so any selection a
  /// student can build there imports here intact. Verified against ADE: 100 ids
  /// is a 437-character URL and returns HTTP 200.
  static const int maxIds = 100;

  /// Returns the ids found in [input], de-duplicated and in the order given.
  /// Returns an empty list when nothing usable is present.
  static List<int> parseIds(String input) {
    final text = input.trim();
    if (text.isEmpty) return const <int>[];

    final candidates = <String>[];

    // A resources= query parameter, if this is a URL we can parse.
    final uri = Uri.tryParse(text);
    final fromQuery = uri?.queryParameters['resources'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      candidates.add(fromQuery);
    } else if (uri != null && uri.pathSegments.isNotEmpty) {
      // .../view/<ids>/ — take the first segment that looks like an id list.
      for (final segment in uri.pathSegments) {
        if (RegExp(r'^\d+(,\d+)*$').hasMatch(segment)) {
          candidates.add(segment);
          break;
        }
      }
    }

    // A bare list, or a last resort when the URL had no recognisable segment.
    // Minus signs are admitted here so the id check below is what rejects them,
    // rather than the whole paste being silently ignored.
    if (candidates.isEmpty && RegExp(r'^[\d,\s-]+$').hasMatch(text)) {
      candidates.add(text);
    }

    final ids = <int>[];
    for (final raw in candidates) {
      for (final part in raw.split(',')) {
        final id = int.tryParse(part.trim());
        // Reject 0 and negatives: ADE resource ids are positive.
        if (id != null && id > 0 && !ids.contains(id)) ids.add(id);
      }
    }
    return ids.length > maxIds ? ids.sublist(0, maxIds) : ids;
  }
}
