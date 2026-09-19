import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/remote_image_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_logo.dart';
import 'package:notes_insa/modules/associations/association_logo_assets.dart';
import 'package:notes_insa/theme/campus_theme.dart';

/// An id the baker produced a file for, and the URL it was baked from.
final MapEntry<String, String> _bundled =
    kBundledAssociationLogos.entries.first;

Association _asso({required String id, String? name, String? logoUrl}) =>
    Association(
      id: id,
      name: name ?? 'Association $id',
      category: AssociationCategory.culture,
      logoUrl: logoUrl,
    );

Future<void> _pump(
  WidgetTester tester,
  Association association, {
  BoxShape shape = BoxShape.circle,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: campusTheme(brightness),
      home: Scaffold(
        body: Center(
          child: AssociationLogo(
            association: association,
            size: 40,
            shape: shape,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

BoxDecoration _slotDecoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(AssociationLogo),
                matching: find.byType(Container),
              ),
            )
            .decoration
        as BoxDecoration;

ImageProvider _resolvedProvider(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  return image is ResizeImage ? image.imageProvider : image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);

  group('AssociationLogo shape and defaults', () {
    testWidgets('defaults to a round (circle) shape with anti-alias clipping', (
      tester,
    ) async {
      await _pump(tester, _asso(id: 'nothing-bundled', name: 'AEIR'));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AssociationLogo),
          matching: find.byType(Container),
        ),
      );

      expect(container.clipBehavior, Clip.antiAlias);
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('supports rectangular/square shape when requested', (
      tester,
    ) async {
      await _pump(
        tester,
        _asso(id: 'nothing-bundled', name: 'AEIR'),
        shape: BoxShape.rectangle,
      );

      final decoration = _slotDecoration(tester);
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull);
    });

    testWidgets('the slot carries a hairline in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          _asso(id: 'nothing-bundled'),
          brightness: brightness,
        );
        expect(
          _slotDecoration(tester).border,
          isNotNull,
          reason: 'no edge against the card in $brightness',
        );
      }
    });
  });

  group('AssociationLogo picks its image', () {
    testWidgets('an association with no logo at all shows its initials', (
      tester,
    ) async {
      await _pump(tester, _asso(id: 'nothing-bundled', name: 'Club Théâtre'));

      expect(find.byType(Image), findsNothing);
      expect(find.text('CT'), findsOneWidget);
    });

    testWidgets('the bundled asset is preferred over the remote URL', (
      tester,
    ) async {
      await _pump(tester, _asso(id: _bundled.key, logoUrl: _bundled.value));

      final provider = _resolvedProvider(tester);
      expect(provider, isA<AssetImage>());
      expect(
        (provider as AssetImage).assetName,
        'assets/images/associations/${_bundled.key}.webp',
      );
    });

    // A baked file is only the normalised form of the URL it came from.
    testWidgets('a logo that moved upstream falls back to the remote image', (
      tester,
    ) async {
      await _pump(
        tester,
        _asso(
          id: _bundled.key,
          logoUrl: 'https://example.test/a-brand-new-logo.png',
        ),
      );

      expect(_resolvedProvider(tester), isA<CachedRemoteImage>());
    });

    testWidgets('an association the baker skipped uses its remote URL', (
      tester,
    ) async {
      await _pump(
        tester,
        _asso(id: 'nothing-bundled', logoUrl: 'https://example.test/logo.png'),
      );

      expect(_resolvedProvider(tester), isA<CachedRemoteImage>());
    });
  });
}
