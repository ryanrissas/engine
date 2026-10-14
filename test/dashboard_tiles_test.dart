import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/dashboard_tiles.dart';

void main() {
  test('empty or unset is every tile, default order, none hidden', () {
    final l = parseDashLayout('');
    expect(l.order, DashTile.values);
    expect(l.hidden, isEmpty);
  });

  test('order and hidden round-trip', () {
    const raw = 'steps,-hrv,rhr,resp,-skinTemp,calories';
    final l = parseDashLayout(raw);
    expect(l.order.first, DashTile.steps);
    expect(l.hidden, {DashTile.hrv, DashTile.skinTemp});
    expect(encodeDashLayout(l), raw);
  });

  test('a tile missing from an old setting is appended, visible', () {
    final l = parseDashLayout('hrv,rhr');
    expect(l.order.take(2), [DashTile.hrv, DashTile.rhr]);
    expect(l.order, hasLength(DashTile.values.length));
    expect(l.hidden, isEmpty);
  });

  test('unknown names and duplicates are dropped', () {
    final l = parseDashLayout('nope,rhr,rhr,-gone');
    expect(l.order.where((t) => t == DashTile.rhr), hasLength(1));
    expect(l.order, hasLength(DashTile.values.length));
  });
}
