import 'package:flutter/material.dart';

import 'campus_context.dart';
import 'tokens.dart';

/// Empty, error, offline and locked states share this one layout so they
/// never drift apart. Icon 32, a title, an optional sentence, one action.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = context.text;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CampusSpacing.gutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: scheme.onSurfaceVariant),
              const SizedBox(height: CampusSpacing.x3),
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              if (body != null) ...[
                const SizedBox(height: CampusSpacing.x2),
                Text(
                  body!,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: CampusSpacing.x5),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
