import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/remote_image_cache.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'association.dart';

/// An association's logo in a fixed square, its initials until the image is
/// there. The slot keeps its size whatever it holds, so a directory never
/// reflows as logos arrive.
class AssociationLogo extends StatefulWidget {
  const AssociationLogo({
    required this.association,
    required this.size,
    this.initialsStyle,
    super.key,
  });

  final Association association;
  final double size;
  final TextStyle? initialsStyle;

  @override
  State<AssociationLogo> createState() => _AssociationLogoState();
}

class _AssociationLogoState extends State<AssociationLogo> {
  bool _deferred = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deferred = Scrollable.recommendDeferredLoadingForContext(context);
    if (deferred == _deferred) return;
    _deferred = deferred;
    if (deferred) _recheckNextFrame();
  }

  /// The recommendation describes the fling happening right now, and nothing
  /// rebuilds a row once that fling ends. Ask again every frame until the list
  /// is calm, otherwise the initials shown mid-scroll would stay for good.
  void _recheckNextFrame() {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted) return;
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _recheckNextFrame();
        return;
      }
      setState(() => _deferred = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.association.logoAsset;
    final logoUrl = widget.association.logoUrl;
    if (asset == null && (logoUrl == null || _deferred)) {
      return _slot(_initials());
    }

    final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round();
    return _slot(
      Image(
        image: asset != null
            ? ResizeImage.resizeIfNeeded(pixels, pixels, AssetImage(asset))
            : ResizeImage(
                CachedRemoteImage(logoUrl!),
                width: pixels,
                height: pixels,
                policy: ResizeImagePolicy.fit,
                allowUpscaling: false,
              ),
        // Logos are wordmarks as often as marks. Cropping one to fill a square
        // makes it unreadable, so the square holds it rather than the reverse.
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? child : _initials(),
        errorBuilder: (context, _, _) => _initials(),
      ),
    );
  }

  Widget _slot(Widget child) => Container(
    width: widget.size,
    height: widget.size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.scheme.secondaryContainer,
      borderRadius: CampusRadii.controlRadius,
    ),
    child: child,
  );

  Widget _initials() => Text(
    associationInitials(widget.association.displayName),
    style: (widget.initialsStyle ?? context.text.labelLarge)?.copyWith(
      color: context.scheme.onSecondaryContainer,
    ),
  );
}

/// Up to two initials, from the first two words that start with a letter.
String associationInitials(String name) {
  final words = name
      .split(RegExp(r'[\s-]+'))
      .where(
        (w) => w.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(w),
      )
      .take(2);
  if (words.isEmpty) return '?';
  return words.map((w) => w.characters.first.toUpperCase()).join();
}
