import 'package:flutter/material.dart';

/// Which hues the timetable draws from. The label and description are the
/// French copy the picker shows.
enum ScheduleTintScheme {
  spectre('Spectre', 'Toutes les teintes'),
  froid('Froid', 'Verts, bleus et violets'),
  accessible('Accessible', 'Distinguable en cas de daltonisme'),
  aucune('Sans couleur', 'Gris uniquement');

  const ScheduleTintScheme(this.label, this.description);

  final String label;
  final String description;
}

/// How loudly the chosen tints are applied. This picks which ramp lands on
/// which surface; it introduces no colour of its own.
enum ScheduleTintIntensity {
  discret('Discret', 'Une fine barre de couleur'),
  standard('Standard', 'Blocs et barres teintés'),
  vif('Vif', 'Blocs pleine couleur');

  const ScheduleTintIntensity(this.label, this.description);

  final String label;
  final String description;
}

/// One scheme's two ramps for one brightness. [fill] is tuned to the weight of
/// the surface it replaces, [bold] to be legible as a graphic with no text.
@immutable
class ModuleTintRamps {
  const ModuleTintRamps({required this.fill, required this.bold});

  final List<Color> fill;
  final List<Color> bold;

  static const ModuleTintRamps none = ModuleTintRamps(
    fill: <Color>[],
    bold: <Color>[],
  );
}

/// Generated in OKLCH to the parameters in docs/design/design-direction.md.
/// test/theme/module_tints_test.dart is what holds these values honest.
const Map<ScheduleTintScheme, ModuleTintRamps> kLightModuleTints =
    <ScheduleTintScheme, ModuleTintRamps>{
      ScheduleTintScheme.spectre: ModuleTintRamps(
        fill: <Color>[
          Color(0xFFD0DDB9),
          Color(0xFFBDE1C9),
          Color(0xFFB2E2DD),
          Color(0xFFB4DFEF),
          Color(0xFFC1D9F8),
          Color(0xFFD3D3F7),
          Color(0xFFE6CDEC),
          Color(0xFFF2CADA),
        ],
        bold: <Color>[
          Color(0xFF5C7327),
          Color(0xFF297A4F),
          Color(0xFF007B75),
          Color(0xFF007594),
          Color(0xFF3B6BA4),
          Color(0xFF645FA2),
          Color(0xFF83548F),
          Color(0xFF964D6F),
        ],
      ),
      ScheduleTintScheme.froid: ModuleTintRamps(
        fill: <Color>[
          Color(0xFFC6DFC0),
          Color(0xFFB9E2CF),
          Color(0xFFB2E2DF),
          Color(0xFFB3E0ED),
          Color(0xFFBBDBF6),
          Color(0xFFC9D6F9),
          Color(0xFFD8D1F5),
          Color(0xFFE6CDEC),
        ],
        bold: <Color>[
          Color(0xFF47773D),
          Color(0xFF157B5B),
          Color(0xFF007B78),
          Color(0xFF007790),
          Color(0xFF2A6F9F),
          Color(0xFF5166A4),
          Color(0xFF6D5C9E),
          Color(0xFF83558E),
        ],
      ),
      ScheduleTintScheme.accessible: ModuleTintRamps(
        fill: <Color>[
          Color(0xFFB5E6E8),
          Color(0xFFC4B9DC),
          Color(0xFF83B2B4),
          Color(0xFF9F95B6),
        ],
        bold: <Color>[
          Color(0xFF007A80),
          Color(0xFF674F8E),
          Color(0xFF00555B),
          Color(0xFF4D3471),
        ],
      ),
      ScheduleTintScheme.aucune: ModuleTintRamps.none,
    };

const Map<ScheduleTintScheme, ModuleTintRamps> kDarkModuleTints =
    <ScheduleTintScheme, ModuleTintRamps>{
      ScheduleTintScheme.spectre: ModuleTintRamps(
        fill: <Color>[
          Color(0xFF2E371B),
          Color(0xFF1D3A28),
          Color(0xFF0D3B38),
          Color(0xFF113844),
          Color(0xFF21344B),
          Color(0xFF312F4A),
          Color(0xFF3D2B42),
          Color(0xFF462835),
        ],
        bold: <Color>[
          Color(0xFF92A965),
          Color(0xFF6BB086),
          Color(0xFF4BB1AA),
          Color(0xFF52ACC9),
          Color(0xFF75A1D9),
          Color(0xFF9996D7),
          Color(0xFFB88BC4),
          Color(0xFFCC86A5),
        ],
      ),
      ScheduleTintScheme.froid: ModuleTintRamps(
        fill: <Color>[
          Color(0xFF253921),
          Color(0xFF183B2D),
          Color(0xFF0D3B39),
          Color(0xFF0F3943),
          Color(0xFF1B3649),
          Color(0xFF29324B),
          Color(0xFF342E49),
          Color(0xFF3E2B42),
        ],
        bold: <Color>[
          Color(0xFF7FAD74),
          Color(0xFF5FB190),
          Color(0xFF4AB1AD),
          Color(0xFF4EADC5),
          Color(0xFF67A5D5),
          Color(0xFF869CDA),
          Color(0xFFA293D4),
          Color(0xFFB98BC3),
        ],
      ),
      ScheduleTintScheme.accessible: ModuleTintRamps(
        fill: <Color>[
          Color(0xFF013234),
          Color(0xFF463C58),
          Color(0xFF2B5659),
          Color(0xFF615774),
        ],
        bold: <Color>[
          Color(0xFF41A9AF),
          Color(0xFFBDA6E8),
          Color(0xFF6FD5DA),
          Color(0xFFE4CCFF),
        ],
      ),
      ScheduleTintScheme.aucune: ModuleTintRamps.none,
    };
