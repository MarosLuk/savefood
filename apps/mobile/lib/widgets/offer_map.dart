import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';

class OfferMap extends StatefulWidget {
  const OfferMap({
    super.key,
    required this.center,
    this.offers = const [],
    this.onSelect,
    this.onPoint,
    this.selected,
  });
  final GeoPoint center;
  final List<FoodOffer> offers;
  final ValueChanged<FoodOffer>? onSelect;
  final ValueChanged<GeoPoint>? onPoint;
  final String? selected;
  @override
  State<OfferMap> createState() => _OfferMapState();
}

class _OfferMapState extends State<OfferMap> {
  bool tileFailed = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const lightUrl = String.fromEnvironment(
      'MAP_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    const darkUrl = String.fromEnvironment('MAP_DARK_TILE_URL');
    final tiles = TileLayer(
      urlTemplate: dark && darkUrl.isNotEmpty ? darkUrl : lightUrl,
      userAgentPackageName: 'com.dakoty.savefood',
      panBuffer: 0,
      errorTileCallback: (_, error, stack) {
        if (!tileFailed && mounted) setState(() => tileFailed = true);
      },
    );
    return Stack(
      children: [
        FlutterMap(
          key: ValueKey(
            '${widget.center.latitude}-${widget.center.longitude}-$dark',
          ),
          options: MapOptions(
            initialCenter: LatLng(
              widget.center.latitude,
              widget.center.longitude,
            ),
            initialZoom: 14,
            minZoom: 5,
            maxZoom: 18,
            onTap: (_, point) =>
                widget.onPoint?.call(GeoPoint(point.latitude, point.longitude)),
          ),
          children: [
            if (dark && darkUrl.isEmpty)
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  -0.18071,
                  -0.60792,
                  -0.06137,
                  0,
                  233,
                  -0.174332,
                  -0.586464,
                  -0.059204,
                  0,
                  232,
                  -0.165828,
                  -0.557856,
                  -0.056316,
                  0,
                  233,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: tiles,
              )
            else
              tiles,
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(
                    widget.center.latitude,
                    widget.center.longitude,
                  ),
                  width: 24,
                  height: 24,
                  child: Semantics(
                    label: 'Vybraná poloha',
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.blue.withValues(alpha: .25),
                            spreadRadius: 5,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ...widget.offers.map(
                  (o) => Marker(
                    point: LatLng(o.point.latitude, o.point.longitude),
                    width: 88,
                    height: 48,
                    child: Semantics(
                      button: true,
                      label: '${o.store}, ${euro(o.price)}',
                      child: GestureDetector(
                        onTap: () => widget.onSelect?.call(o),
                        child: Container(
                          alignment: Alignment.center,
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: widget.selected == o.id
                                ? context.colors.blue
                                : context.colors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: widget.selected == o.id
                                  ? context.colors.blue
                                  : context.colors.line,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .13),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: AppText(
                            euro(o.price),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: widget.selected == o.id
                                  ? (dark
                                        ? const Color(0xFF10233E)
                                        : Colors.white)
                                  : context.colors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (tileFailed)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(AppIcons.info, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: AppText(
                      'Podklad mapy je offline. Ponuky môžeš prezerať v zozname.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            color: context.colors.surface.withValues(alpha: .94),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 28),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () => launchUrl(
                Uri.parse(
                  const String.fromEnvironment(
                    'MAP_ATTRIBUTION_URL',
                    defaultValue: 'https://www.openstreetmap.org/copyright',
                  ),
                ),
              ),
              child: AppText(
                const String.fromEnvironment(
                  'MAP_ATTRIBUTION',
                  defaultValue: '© OpenStreetMap contributors',
                ),
                style: TextStyle(fontSize: 9, color: context.colors.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
