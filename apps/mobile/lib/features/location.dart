import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_data/marketplace_data.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import '../widgets/offer_map.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final search = TextEditingController();
  GeoPoint? point;
  String? label;
  double? radius;
  bool busy = false, searching = false;
  Timer? debounce;
  int generation = 0;
  List<({String label, GeoPoint point})> remotePlaces = [];
  void searchPlaces(String query) {
    debounce?.cancel();
    final version = ++generation;
    final store = StoreScope.of(context);
    setState(() {
      remotePlaces = [];
      searching = false;
    });
    if (query.trim().length < 3 ||
        store.api == null ||
        store.serverConfig['placeSearchEnabled'] != true) {
      return;
    }
    debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => searching = true);
      try {
        final json = await store.api!.request(
          'GET',
          '/v1/places?q=${Uri.encodeQueryComponent(query.trim())}&lang=${store.language}',
        );
        if (mounted && version == generation) {
          setState(
            () => remotePlaces = (json['places'] as List)
                .map(
                  (p) => (
                    label: p['label'] as String,
                    point: GeoPoint.fromJson(
                      Map<String, dynamic>.from(p['point'] as Map),
                    ),
                  ),
                )
                .toList(),
          );
        }
      } catch (e) {
        if (mounted && version == generation) {
          setState(() => error = e.toString());
        }
      } finally {
        if (mounted && version == generation) setState(() => searching = false);
      }
    });
  }

  String? error;
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> gps() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Zapni lokalizačné služby alebo vyber mesto ručne.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Prístup k polohe je vypnutý v systémových nastaveniach. Mesto môžeš vybrať ručne.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Poloha nie je povolená. Vyber mesto ručne.');
      }
      final result = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          point = GeoPoint(result.latitude, result.longitude);
          label = 'Moja poloha';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'Polohu sa nepodarilo zistiť. Vyber mesto ručne.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final current = point ?? store.location;
    final currentRadius = radius ?? store.filters.radiusKm;
    final places = <({String label, GeoPoint point})>[
      (label: 'Bratislava, Staré Mesto', point: bratislava),
      (label: 'Košice, Centrum', point: kosice),
      (label: 'Trnava, Centrum', point: trnava),
      ...store.offers.map((o) => (label: o.address, point: o.point)),
    ];
    final localSuggestions = places
        .where(
          (p) =>
              normalizeSearch(p.label).contains(normalizeSearch(search.text)),
        )
        .toList();
    final suggestions = [...remotePlaces, ...localSuggestions];
    return ScreenScaffold(
      title: 'Čo dobré je v okolí?',
      bottom: PrimaryButton(
        'Potvrdiť polohu',
        icon: AppIcons.check,
        onPressed: () {
          store.setLocation(
            current,
            label ?? store.locationLabel,
            currentRadius,
          );
          Navigator.pop(context);
        },
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          AppText(
            'Dobroty sú bližšie,\nnež si myslíš.',
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 12),
          AppText(
            'Vyber mesto, použi svoju polohu alebo ťukni na mapu.',
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: search,
            onChanged: searchPlaces,
            decoration: InputDecoration(
              hintText: context.tr('Mesto alebo adresa prevádzky'),
              prefixIcon: Icon(AppIcons.search, size: 20),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('Vymazať'),
                      onPressed: () {
                        search.clear();
                        searchPlaces('');
                      },
                      icon: Icon(AppIcons.close, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          AppText(
            store.serverConfig['placeSearchEnabled'] == true
                ? 'Vyhľadávanie adries · OpenStreetMap / Photon'
                : 'Vyhľadávanie v lokalitách a prevádzkach katalógu',
            style: context.text.bodySmall,
          ),
          if (searching) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          for (final place in suggestions.take(search.text.isEmpty ? 3 : 6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(AppIcons.pin, color: context.colors.blue),
              title: AppText(place.label),
              trailing: Icon(AppIcons.external, size: 18),
              onTap: () => setState(() {
                point = place.point;
                label = place.label;
                search.clear();
                generation++;
                debounce?.cancel();
                remotePlaces = [];
                searching = false;
              }),
            ),
          if (suggestions.isEmpty && !searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AppText(
                'Túto adresu sme nenašli. Miesto môžeš označiť na mape.',
              ),
            ),
          TextButton.icon(
            onPressed: busy ? null : gps,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(AppIcons.navigation, size: 18),
            label: const AppText('Použiť moju polohu'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppText(
                error!,
                style: TextStyle(color: context.colors.warning),
              ),
            ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 230,
              child: OfferMap(
                center: current,
                onPoint: (p) => setState(() {
                  point = p;
                  label =
                      'Bod na mape (${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)})';
                }),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppText(
            label ?? store.locationLabel,
            style: context.text.titleMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: AppText('Vzdialenosť od teba')),
              AppText(
                '${currentRadius.round()} km',
                style: context.text.titleMedium?.copyWith(
                  color: context.colors.blue,
                ),
              ),
            ],
          ),
          Slider(
            value: currentRadius,
            min: 1,
            max: 30,
            divisions: 29,
            label: '${currentRadius.round()} km',
            onChanged: (v) => setState(() => radius = v),
          ),
          if (store.isDemo)
            AppText(
              'Demo ponuky sú v Bratislave, Košiciach a Trnave.',
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}
