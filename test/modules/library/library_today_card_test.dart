import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/library/library_provider.dart';
import 'package:notes_insa/modules/library/library_site.dart';
import 'package:notes_insa/modules/library/library_today_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  setUpAll(initCampusTime);

  LibraryStatus status(
    LibrarySite site, {
    bool isOpen = true,
    int? occupancy = 20,
    String? statusLabel = 'Ferme à 18:00',
    List<String> notices = const <String>[],
    LibraryForecast? forecast,
  }) => LibraryStatus(
    site: site,
    isOpen: isOpen,
    occupancy: occupancy,
    statusLabel: statusLabel,
    notices: notices,
    nextForecast: forecast,
  );

  Future<List<Uri>> pumpCard(
    WidgetTester tester, {
    List<LibraryStatus>? sites,
    RefreshState state = RefreshState.fresh,
  }) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryStatusProvider.overrideWith(
            (ref) => Stream<CachedEntry<List<LibraryStatus>>>.value(
              CachedEntry<List<LibraryStatus>>(
                data: sites,
                cachedAt: sites == null ? null : campusNow(),
                refreshState: state,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LibraryTodayCard(
                openLink: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('lists both libraries with how full they are', (tester) async {
    await pumpCard(
      tester,
      sites: <LibraryStatus>[
        status(kLibrarySites.first, occupancy: 10),
        status(kLibrarySites.last, occupancy: 35),
      ],
    );

    expect(find.text('Bibliothèques'), findsOneWidget);
    expect(find.text('Biblinsa'), findsOneWidget);
    expect(find.text('BU Beaulieu'), findsOneWidget);
    expect(find.text('Calme · 10 %'), findsOneWidget);
    expect(find.text('Calme · 35 %'), findsOneWidget);
    expect(find.text('Ferme à 18:00'), findsNWidgets(2));
    expect(find.textContaining('Source Affluences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says when a library is packed or shut', (tester) async {
    await pumpCard(
      tester,
      sites: <LibraryStatus>[
        status(kLibrarySites.first, occupancy: 90),
        status(
          kLibrarySites.last,
          isOpen: false,
          occupancy: 0,
          statusLabel: 'Ouvre à 9:00',
        ),
      ],
    );

    expect(find.text('Bondée · 90 %'), findsOneWidget);
    expect(find.text('Fermée'), findsOneWidget);
    expect(find.text('Ouvre à 9:00'), findsOneWidget);
  });

  testWidgets('shows the forecast turn and any notice', (tester) async {
    await pumpCard(
      tester,
      sites: <LibraryStatus>[
        status(
          kLibrarySites.first,
          forecast: LibraryForecast(
            startsAt: campusInstant(DateTime(2026, 9, 11, 17)),
            occupancy: 5,
            trend: LibraryTrend.decrease,
          ),
          notices: <String>['Travaux au 1er étage'],
        ),
      ],
    );

    expect(find.text('plus calme après 17:00'), findsOneWidget);
    expect(find.text('Travaux au 1er étage'), findsOneWidget);
  });

  testWidgets('opens the booking page of the library that was tapped', (
    tester,
  ) async {
    final opened = await pumpCard(
      tester,
      sites: <LibraryStatus>[
        status(kLibrarySites.first),
        status(kLibrarySites.last),
      ],
    );

    expect(find.text('Réserver'), findsNWidgets(2));
    await tester.tap(find.text('Réserver').last);
    await tester.pump();

    expect(opened, <Uri>[Uri.parse(kLibrarySites.last.bookingUrl)]);
  });

  testWidgets('offers a retry when there is nothing to show', (tester) async {
    await pumpCard(tester, state: RefreshState.failedOffline);

    expect(find.textContaining('indisponible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('a second refresh tap in a row is ignored', (tester) async {
    await pumpCard(tester, sites: <LibraryStatus>[status(kLibrarySites.first)]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryTodayCard)),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(container.read(libraryRefreshTickProvider), 1);
  });
}
