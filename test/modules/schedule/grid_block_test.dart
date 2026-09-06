import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';

void main() {
  test('a wide block shows the module and the room', () {
    expect(
      blockLabelDensity(width: 115, height: 80),
      BlockLabelDensity.moduleAndRoom,
    );
  });

  test('a medium block shows the module alone', () {
    expect(
      blockLabelDensity(width: 64, height: 80),
      BlockLabelDensity.moduleOnly,
    );
  });

  test('56 dp is the narrowest width that can hold a module name', () {
    expect(
      blockLabelDensity(width: 56, height: 80),
      BlockLabelDensity.moduleOnly,
    );
    expect(blockLabelDensity(width: 55.9, height: 80), BlockLabelDensity.none);
  });

  test('a seven-column block on a 384 dp phone shows no label', () {
    // 384 dp minus the 40 dp gutter, over seven columns.
    expect(blockLabelDensity(width: 49.1, height: 80), BlockLabelDensity.none);
  });

  test('a short block shows no label however wide it is', () {
    expect(blockLabelDensity(width: 300, height: 23.9), BlockLabelDensity.none);
    expect(
      blockLabelDensity(width: 300, height: 24),
      BlockLabelDensity.moduleAndRoom,
    );
  });
}
