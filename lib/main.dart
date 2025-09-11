import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
//import 'package:google_maps_flutter/google_maps_flutter.dart';
void main() => runApp(const NearbyApp());

class NearbyApp extends StatelessWidget {
  const NearbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorSchemeSeed: const Color(0xFF5B8DEF),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nearby Events',
      theme: theme,
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final Set<String> _favourites = {}; // event ids

  // NEW: hold events loaded from assets
  List<_Event> _events = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadFavourites();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/events.json');
      final List<dynamic> data = json.decode(jsonStr) as List<dynamic>;
      final items = data.map((e) => _Event.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.start.compareTo(b.start)); // keep ascending
      setState(() {
        _events = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favs') ?? const <String>[];
    setState(() {
      _favourites
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _saveFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favs', _favourites.toList());
  }

  void _toggleFav(String id) {
    setState(() {
      if (_favourites.contains(id)) {
        _favourites.remove(id);
      } else {
        _favourites.add(id);
      }
    });
    _saveFavourites();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load events: $_loadError'),
          ),
        ),
      );
    }

    final pages = [
      DiscoverPage(
        events: _events,                      // ← pass events
        favourites: _favourites,
        onToggleFavourite: _toggleFav,
      ),
      FavouritesPage(
        favourites: _events
            .where((e) => _favourites.contains(e.id))
            .toList(),                        // ← use loaded events
        onToggleFavourite: _toggleFav,
      ),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favourites',
          ),
        ],
      ),
    );
  }
}

/// ---------- DISCOVER (HOME) ----------
class DiscoverPage extends StatefulWidget {
  final List<_Event> events;                 // ← NEW
  final Set<String> favourites;
  final void Function(String id) onToggleFavourite;

  const DiscoverPage({
    super.key,
    required this.events,
    required this.favourites,
    required this.onToggleFavourite,
  });

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

enum TimeScope { today, week }
enum Category { all, concert, theatre, cinema }

class _DiscoverPageState extends State<DiscoverPage> {
  TimeScope _timeScope = TimeScope.today;
  double _radiusKm = 5;
  Category _category = Category.all;

  // search query state
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilters(
      events: widget.events,                 // ← use events from props
      timeScope: _timeScope,
      radiusKm: _radiusKm,
      category: _category,
      query: _query,                         // ← apply search too
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _LocationChip(
          label:
          'Near me • ${_timeScope == TimeScope.today ? "Today" : "This Week"}',
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () async {
              final q = await showSearch<String?>(
                context: context,
                delegate: _EventSearchDelegate(all: widget.events), // ← use loaded
              );
              if (q != null) {
                setState(() => _query = q);
              }
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          const _MapPlaceholder(),
          const SizedBox(height: 12),
          _QuickFilterChips(
            timeScope: _timeScope,
            onTimeScopeChanged: (v) => setState(() => _timeScope = v),
            radiusKm: _radiusKm,
            onRadiusToggle: () => setState(() {
              _radiusKm = _radiusKm == 5 ? 10 : 5;
            }),
            category: _category,
            onCategoryToggle: () => setState(() {
              _category =
              _category == Category.all ? Category.concert : Category.all;
            }),
          ),
          const SizedBox(height: 8),

          // show the active query as a chip
          if (_query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text('“$_query”'),
                  avatar: const Icon(Icons.search, size: 18),
                  onDeleted: () => setState(() => _query = ''),
                ),
              ),
            ),

          const SizedBox(height: 8),
          Expanded(
            child: _EventList(
              events: filtered,
              favourites: widget.favourites,
              onToggleFavourite: widget.onToggleFavourite,
            ),
          ),
        ],
      ),
    );
  }

  void _openFilters() async {
    final result = await showModalBottomSheet<_FiltersResult>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _FiltersSheet(
        initial: _FiltersResult(
          timeScope: _timeScope,
          radiusKm: _radiusKm,
          category: _category,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _timeScope = result.timeScope;
        _radiusKm = result.radiusKm;
        _category = result.category;
      });
    }
  }

  List<_Event> _applyFilters({
    required List<_Event> events,
    required TimeScope timeScope,
    required double radiusKm,
    required Category category,
    String query = '',
  }) {
    final now = DateTime.now();
    final to = timeScope == TimeScope.today
        ? now.add(const Duration(days: 1))
        : now.add(const Duration(days: 7));

    bool matchesQuery(_Event e) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return e.title.toLowerCase().contains(q) ||
          e.venue.toLowerCase().contains(q);
    }

    return events
        .where((e) {
      final inTime = e.start.isAfter(now) && e.start.isBefore(to);
      final inCategory =
      category == Category.all ? true : e.category == category;
      // radiusKm not used yet (no real coordinates) — UI-only for now
      return inTime && inCategory && matchesQuery(e);
    })
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }
}

class _LocationChip extends StatelessWidget {
  final String label;
  const _LocationChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShapeDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          shape: StadiumBorder(
            side: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(.3),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location, size: 18),
            const SizedBox(width: 8),
            Text(label),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFB9D6FF), Color(0xFFEEF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Text('Map placeholder')),
    );
  }
}

class _QuickFilterChips extends StatelessWidget {
  final TimeScope timeScope;
  final ValueChanged<TimeScope> onTimeScopeChanged;
  final double radiusKm;
  final VoidCallback onRadiusToggle;
  final Category category;
  final VoidCallback onCategoryToggle;

  const _QuickFilterChips({
    super.key,
    required this.timeScope,
    required this.onTimeScopeChanged,
    required this.radiusKm,
    required this.onRadiusToggle,
    required this.category,
    required this.onCategoryToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Today'),
              selected: timeScope == TimeScope.today,
              onSelected: (_) => onTimeScopeChanged(TimeScope.today),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('This Week'),
              selected: timeScope == TimeScope.week,
              onSelected: (_) => onTimeScopeChanged(TimeScope.week),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text('${radiusKm.toInt()} km'),
              avatar: const Icon(Icons.radar, size: 18),
              onPressed: onRadiusToggle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(category == Category.all ? 'All' : 'Concert'),
              avatar: const Icon(Icons.category, size: 18),
              onPressed: onCategoryToggle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Search delegate
class _EventSearchDelegate extends SearchDelegate<String?> {
  final List<_Event> all;
  _EventSearchDelegate({required this.all});

  @override
  String? get searchFieldLabel => 'Search title or venue';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear',
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) {
    final result = query.trim();
    close(context, result.isEmpty ? null : result);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.toLowerCase();
    final items = q.isEmpty
        ? all.take(8).toList()
        : all
        .where((e) =>
    e.title.toLowerCase().contains(q) ||
        e.venue.toLowerCase().contains(q))
        .take(20)
        .toList();

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No matches'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = items[i];
        return ListTile(
          leading: const Icon(Icons.search),
          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${e.venue} • ${e.city}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => close(context, e.title),
        );
      },
    );
  }
}

class _EventList extends StatelessWidget {
  final List<_Event> events;
  final Set<String> favourites;
  final void Function(String id) onToggleFavourite;

  const _EventList({
    super.key,
    required this.events,
    required this.favourites,
    required this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _EmptyState(
        emoji: '🔍',
        title: 'No events match',
        caption: 'Try changing the filters.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _EventCard(
        event: events[i],
        isFavourite: favourites.contains(events[i].id),
        onToggleFavourite: onToggleFavourite,
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final _Event event;
  final bool isFavourite;
  final void Function(String id) onToggleFavourite;

  const _EventCard({
    required this.event,
    required this.isFavourite,
    required this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 10,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                color: Color(0xFFEAF2FF),
              ),
              child:
              const Icon(Icons.event, size: 36, color: Color(0xFF5B8DEF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('${event.venue} • ${event.city}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 16),
                        const SizedBox(width: 4),
                        Text(event.prettyTime),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip:
              isFavourite ? 'Remove from favourites' : 'Add to favourites',
              onPressed: () => onToggleFavourite(event.id),
              icon: Icon(
                isFavourite ? Icons.favorite : Icons.favorite_border,
                color: isFavourite ? Colors.pink : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// ---------- EVENT DETAIL ----------
class EventDetailPage extends StatelessWidget {
  final _Event event;
  const EventDetailPage({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Event details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFB9D6FF), Color(0xFFEEF4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(Icons.event, size: 60, color: Color(0xFF5B8DEF)),
            ),
          ),
          const SizedBox(height: 16),
          Text(event.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.place, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('${event.venue} • ${event.city}')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.schedule, size: 18),
            const SizedBox(width: 6),
            Text(event.prettyTime),
          ]),
          const SizedBox(height: 16),
          Text(
            'About',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is a placeholder description for the event. '
                'When we connect the backend, this will show real details, prices and links.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.confirmation_number),
            label: const Text('Get Tickets'),
            onPressed: () {},
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.favorite_border),
            label: const Text('Add to Favourites'),
            onPressed: () {},
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Open Source Link'),
            onPressed: () {},
          ),
        ],
      ),
      backgroundColor: cs.background,
    );
  }
}

/// ---------- FAVOURITES ----------
class FavouritesPage extends StatelessWidget {
  final List<_Event> favourites;
  final void Function(String id) onToggleFavourite;
  const FavouritesPage({
    super.key,
    required this.favourites,
    required this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: favourites.isEmpty
          ? const _EmptyState(
        emoji: '💖',
        title: 'No favourites yet',
        caption: 'Tap the heart on an event to save it.',
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: favourites.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _EventCard(
          event: favourites[i],
          isFavourite: true,
          onToggleFavourite: onToggleFavourite,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji, title, caption;
  const _EmptyState(
      {required this.emoji, required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// ---------- FILTERS SHEET ----------
class _FiltersResult {
  final TimeScope timeScope;
  final double radiusKm;
  final Category category;
  _FiltersResult({
    required this.timeScope,
    required this.radiusKm,
    required this.category,
  });
}

class _FiltersSheet extends StatefulWidget {
  final _FiltersResult initial;
  const _FiltersSheet({required this.initial});

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late TimeScope _timeScope = widget.initial.timeScope;
  late double _radiusKm = widget.initial.radiusKm;
  late Category _category = widget.initial.category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('Time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _timeScope == TimeScope.today,
                  onSelected: (_) =>
                      setState(() => _timeScope = TimeScope.today),
                ),
                ChoiceChip(
                  label: const Text('This Week'),
                  selected: _timeScope == TimeScope.week,
                  onSelected: (_) =>
                      setState(() => _timeScope = TimeScope.week),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Radius (${_radiusKm.toInt()} km)',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              min: 1,
              max: 25,
              divisions: 24,
              value: _radiusKm,
              label: '${_radiusKm.toInt()} km',
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const SizedBox(height: 8),
            Text('Category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _category == Category.all,
                  onSelected: (_) => setState(() => _category = Category.all),
                ),
                FilterChip(
                  label: const Text('Concert'),
                  selected: _category == Category.concert,
                  onSelected: (_) =>
                      setState(() => _category = Category.concert),
                ),
                FilterChip(
                  label: const Text('Theatre'),
                  selected: _category == Category.theatre,
                  onSelected: (_) =>
                      setState(() => _category = Category.theatre),
                ),
                FilterChip(
                  label: const Text('Cinema'),
                  selected: _category == Category.cinema,
                  onSelected: (_) =>
                      setState(() => _category = Category.cinema),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(_FiltersResult(
                    timeScope: _timeScope,
                    radiusKm: _radiusKm,
                    category: _category,
                  ));
                },
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- MODEL ----------
class _Event {
  final String id;
  final String title;
  final String venue;
  final String city;
  final DateTime start;
  final Category category;

  _Event(this.id, this.title, this.venue, this.city, this.start, this.category);

  String get prettyTime {
    return DateFormat('y-MM-dd HH:mm').format(start);
  }

  factory _Event.fromJson(Map<String, dynamic> map) {
    return _Event(
      map['id'] as String,
      map['title'] as String,
      map['venue'] as String,
      map['city'] as String,
      DateTime.parse(map['start'] as String),
      _categoryFromString(map['category'] as String),
    );
  }

  static Category _categoryFromString(String v) {
    switch (v.toLowerCase()) {
      case 'concert':
        return Category.concert;
      case 'theatre':
        return Category.theatre;
      case 'cinema':
        return Category.cinema;
      default:
        return Category.all;
    }
  }
}