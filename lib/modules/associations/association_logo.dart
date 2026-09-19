import 'package:flutter/material.dart';

import '../../core/remote_image_cache.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'association.dart';

final RegExp _words = RegExp(r'[\s-]+');
final RegExp _startsWithLetter = RegExp(r'^\p{L}', unicode: true);

/// An association's logo in a fixed avatar, its initials until the image is
/// there. The slot keeps its size whatever it holds, so a directory never
/// reflows as logos arrive.
class AssociationLogo extends StatelessWidget {
  const AssociationLogo({
    required this.association,
    required this.size,
    this.initialsStyle,
    this.shape = BoxShape.circle,
    super.key,
  });

  final Association association;
  final double size;
  final TextStyle? initialsStyle;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final asset = association.logoAsset;
    final logoUrl = association.logoUrl;
    if (asset == null && logoUrl == null) {
      return _slot(context, _initials(context));
    }

    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return _slot(
      context,
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
        // Logos are wordmarks as often as marks. Cropping one to fill a slot
        // makes it unreadable, so the slot holds it rather than the reverse.
        fit: BoxFit.contain,
        // ResizeImage already decodes at the drawn size, so mipmaps buy
        // nothing here.
        filterQuality: FilterQuality.low,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null
            ? child
            : _initials(context),
        errorBuilder: (context, _, _) => _initials(context),
      ),
      // A baked logo carries its own inset. A remote one has not been through
      // the baker, so the circle's corners need keeping clear.
      inset: asset == null && shape == BoxShape.circle ? 2.0 : 0.0,
    );
  }

  Widget _slot(BuildContext context, Widget child, {double inset = 0.0}) =>
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        padding: EdgeInsets.all(inset),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.scheme.secondaryContainer,
          shape: shape,
          // Most logos carry their own background, white more often than not.
          // Without this the slot has no edge against a light card.
          border: Border.all(color: context.scheme.outlineVariant),
          borderRadius: shape == BoxShape.rectangle
              ? CampusRadii.controlRadius
              : null,
        ),
        child: child,
      );

  Widget _initials(BuildContext context) => Text(
    associationInitials(association.displayName),
    style: (initialsStyle ?? context.text.labelLarge)?.copyWith(
      color: context.scheme.onSecondaryContainer,
    ),
  );
}

/// Up to two initials, from the first two words that start with a letter.
String associationInitials(String name) {
  final words = name
      .split(_words)
      .where((w) => w.isNotEmpty && _startsWithLetter.hasMatch(w))
      .take(2);
  if (words.isEmpty) return '?';
  return words.map((w) => w.characters.first.toUpperCase()).join();
}
