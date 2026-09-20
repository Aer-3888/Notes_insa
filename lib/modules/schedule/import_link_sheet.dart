import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ade_link.dart';

/// Asks for an ADE link and returns the ids in it, or null if the user backed
/// out or pasted something unusable.
///
/// Pre-filled from the clipboard, because the way this is reached is almost
/// always the same: someone in the promo shared their selection, and the link
/// is already copied. Retyping a twenty-id URL is not a thing anyone does.
Future<List<int>?> showImportLinkSheet(BuildContext context) async {
  final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
  final suggested = clipboard?.text?.trim() ?? '';
  // Only offered when it actually parses, so an unrelated clipboard never
  // lands in the field.
  final prefill = AdeLink.parseIds(suggested).isEmpty ? '' : suggested;
  if (!context.mounted) return null;

  final link = await showDialog<String>(
    context: context,
    builder: (context) => _LinkDialog(initial: prefill),
  );
  if (link == null) return null;

  final ids = AdeLink.parseIds(link);
  if (ids.isEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aucun groupe trouvé dans ce lien.')),
    );
    return null;
  }
  return ids.isEmpty ? null : ids;
}

/// Owns its controller, so it lives exactly as long as the dialog does.
/// Disposing one right after `showDialog` returns throws, because the route is
/// still animating out with the field mounted.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial});

  final String initial;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Coller un lien ADE'),
    content: TextField(
      controller: _field,
      autofocus: true,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        hintText: 'https://ade-planning.insa-rennes.fr/view/...',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_field.text),
        child: const Text('Importer'),
      ),
    ],
  );
}
