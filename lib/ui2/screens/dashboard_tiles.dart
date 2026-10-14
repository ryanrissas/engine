// Home's "My dashboard": which tiles show, in what order.
//
// Stored as one string, e.g. `rhr,hrv,-resp,skinTemp,steps,calories` — the
// order is the list, a leading `-` hides a tile. Unknown names are dropped
// and tiles added in a later build are appended visible, so an old setting
// never hides something new.

/// The tiles Home can show. Order here is the default order.
enum DashTile { rhr, hrv, resp, skinTemp, steps, calories }

/// The preference key the layout lives under.
const String kDashboardPref = 'ui.home_dashboard.v1';

typedef DashLayout = ({List<DashTile> order, Set<DashTile> hidden});

/// Every tile, default order, none hidden.
DashLayout get defaultDashLayout =>
    (order: List.of(DashTile.values), hidden: <DashTile>{});

DashLayout parseDashLayout(String raw) {
  final order = <DashTile>[];
  final hidden = <DashTile>{};
  for (final part in raw.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final off = t.startsWith('-');
    final name = off ? t.substring(1) : t;
    DashTile? tile;
    for (final v in DashTile.values) {
      if (v.name == name) tile = v;
    }
    if (tile == null || order.contains(tile)) continue;
    order.add(tile);
    if (off) hidden.add(tile);
  }
  for (final t in DashTile.values) {
    if (!order.contains(t)) order.add(t);
  }
  return (order: order, hidden: hidden);
}

String encodeDashLayout(DashLayout l) => [
      for (final t in l.order) '${l.hidden.contains(t) ? '-' : ''}${t.name}',
    ].join(',');
