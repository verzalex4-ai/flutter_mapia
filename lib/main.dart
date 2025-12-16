import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PlaceFinderApp());
}

class PlaceFinderApp extends StatefulWidget {
  const PlaceFinderApp({super.key});

  @override
  State<PlaceFinderApp> createState() => _PlaceFinderAppState();
}

class _PlaceFinderAppState extends State<PlaceFinderApp> {
  bool _isDarkMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  // Cargar la preferencia del tema al iniciar
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _isLoading = false;
    });
  }

  // Guardar la preferencia del tema
  Future<void> _saveThemePreference(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    _saveThemePreference(_isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar un splash mientras carga la preferencia
    if (_isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.indigo,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map,
                  size: 80,
                  color: Colors.white,
                ),
                SizedBox(height: 20),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Explorador de Lugares',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey[100],
        cardColor: Colors.white,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: PlaceFinderScreen(
        isDarkMode: _isDarkMode,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}

class PlaceFinderScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  const PlaceFinderScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeToggle,
  });

  @override
  State<PlaceFinderScreen> createState() => _PlaceFinderScreenState();
}

class _PlaceFinderScreenState extends State<PlaceFinderScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  List<Place> _places = [];
  List<Place> _favorites = [];
  Place? _selectedPlace;
  PlaceInfo? _placeInfo;
  bool _isSearching = false;
  bool _isLoadingInfo = false;
  String? _error;
  bool _showingFavorites = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getStringList('favorites') ?? [];

    setState(() {
      _favorites = favoritesJson.map((json) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return Place.fromJson(map);
      }).toList();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = _favorites.map((place) {
      return jsonEncode(place.toJson());
    }).toList();
    await prefs.setStringList('favorites', favoritesJson);
  }

  Future<void> _searchPlaces() async {
    if (_searchController.text.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
      _places = [];
      _selectedPlace = null;
      _placeInfo = null;
      _showingFavorites = false;
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(_searchController.text)}&format=json&limit=5&addressdetails=1',
        ),
        headers: {'User-Agent': 'PlaceFinderApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        if (data.isEmpty) {
          setState(() {
            _error = 'No se encontraron lugares. Intenta con otro término.';
          });
        } else {
          setState(() {
            _places = data.map((p) => Place.fromJson(p)).toList();
          });
        }
      } else {
        throw Exception('Error al buscar lugares');
      }
    } catch (e) {
      setState(() {
        _error = 'Error al buscar lugares. Verifica tu conexión.';
      });
      developer.log('Error en búsqueda: $e', name: 'PlaceFinder');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _getPlaceInfo(Place place) async {
    setState(() {
      _selectedPlace = place;
      _isLoadingInfo = true;
      _placeInfo = null;
      _error = null;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        try {
          _mapController.move(
            LatLng(place.lat, place.lon),
            place.type == 'country'
                ? 5.0
                : (place.type == 'city' ? 12.0 : 15.0),
          );
        } catch (e) {
          developer.log('Error moviendo mapa: $e', name: 'PlaceFinder');
        }
      }
    });

    try {
      final searchResponse = await http.get(
        Uri.parse(
          'https://es.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(place.displayName)}&format=json&origin=*&srlimit=1',
        ),
      );

      if (searchResponse.statusCode == 200) {
        final searchData = json.decode(searchResponse.body);
        final searchResults = searchData['query']['search'] as List;

        if (searchResults.isEmpty) {
          if (mounted) {
            setState(() {
              _placeInfo = PlaceInfo(
                title: place.displayName,
                extract:
                    'No se encontró información en Wikipedia para este lugar.',
                url: null,
                location: place.displayName,
              );
            });
          }
          return;
        }

        final pageTitle = searchResults[0]['title'];

        final contentResponse = await http.get(
          Uri.parse(
            'https://es.wikipedia.org/w/api.php?action=query&prop=extracts|info&exintro=1&explaintext=1&titles=${Uri.encodeComponent(pageTitle)}&format=json&origin=*&inprop=url',
          ),
        );

        if (contentResponse.statusCode == 200) {
          final contentData = json.decode(contentResponse.body);
          final pages = contentData['query']['pages'] as Map<String, dynamic>;
          final pageData = pages.values.first;

          if (mounted) {
            setState(() {
              _placeInfo = PlaceInfo(
                title: pageData['title'] ?? place.displayName,
                extract:
                    pageData['extract'] ?? 'No hay información disponible.',
                url: pageData['fullurl'],
                location: place.displayName,
              );
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al obtener información del lugar.';
        });
      }
      developer.log('Error obteniendo info: $e', name: 'PlaceFinder');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInfo = false;
        });
      }
    }
  }

  void _toggleFavorite(Place place) {
    setState(() {
      final index = _favorites.indexWhere((p) => p.placeId == place.placeId);
      if (index >= 0) {
        _favorites.removeAt(index);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${place.name} eliminado de favoritos'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _favorites.add(place);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${place.name} agregado a favoritos'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _saveFavorites();
    });
  }

  bool _isFavorite(Place place) {
    return _favorites.any((p) => p.placeId == place.placeId);
  }

  void _showFavorites() {
    setState(() {
      _showingFavorites = true;
      _places = List.from(_favorites);
      _selectedPlace = null;
      _placeInfo = null;
    });
  }

  Widget _buildMap() {
    if (_selectedPlace == null) {
      return Center(
        child: Text(
          'Selecciona un lugar para ver el mapa',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(_selectedPlace!.lat, _selectedPlace!.lon),
        initialZoom: 13.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.map_culture',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(_selectedPlace!.lat, _selectedPlace!.lon),
              width: 50,
              height: 50,
              child: const Column(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 800;
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: const Text('Explorador de Lugares'),
        elevation: 0,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite),
                tooltip: 'Favoritos',
                onPressed: _favorites.isEmpty ? null : _showFavorites,
              ),
              if (_favorites.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_favorites.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            tooltip: isDark ? 'Modo Claro' : 'Modo Oscuro',
            onPressed: widget.onThemeToggle,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Busca un lugar: ciudad, monumento...',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _searchPlaces(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isSearching ? null : _searchPlaces,
                  backgroundColor: Colors.white,
                  elevation: 2,
                  child: _isSearching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.indigo),
                          ),
                        )
                      : const Icon(Icons.search, color: Colors.indigo),
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _places.isEmpty && !_isSearching
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showingFavorites
                              ? Icons.favorite_border
                              : Icons.public,
                          size: 80,
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _showingFavorites
                              ? 'No tienes favoritos guardados'
                              : 'Busca cualquier lugar del mundo',
                          style: TextStyle(
                            fontSize: 18,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showingFavorites
                              ? 'Agrega lugares a favoritos para acceder rápidamente'
                              : 'Descubre su historia y cultura en el mapa',
                          style: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : isWideScreen
                    ? Row(
                        children: [
                          SizedBox(
                            width: 300,
                            child: Column(
                              children: [
                                if (_showingFavorites)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    margin: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 8),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.favorite,
                                            color: Colors.indigo),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Mis Favoritos (${_favorites.length})',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              color: Colors.indigo),
                                          onPressed: () {
                                            setState(() {
                                              _showingFavorites = false;
                                              _places = [];
                                              _selectedPlace = null;
                                              _placeInfo = null;
                                            });
                                          },
                                          tooltip: 'Cerrar favoritos',
                                        ),
                                      ],
                                    ),
                                  ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _places.length,
                                    itemBuilder: (context, index) {
                                      final place = _places[index];
                                      final isSelected =
                                          _selectedPlace?.placeId ==
                                              place.placeId;
                                      final isFav = _isFavorite(place);
                                      return Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        color: isSelected
                                            ? (isDark
                                                ? Colors.indigo[900]
                                                : Colors.indigo[50])
                                            : (isDark
                                                ? const Color(0xFF1E1E1E)
                                                : Colors.white),
                                        elevation: isSelected ? 4 : 1,
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: isSelected
                                                ? Colors.indigo
                                                : Colors.grey[400],
                                            child: const Icon(Icons.place,
                                                color: Colors.white),
                                          ),
                                          title: Text(
                                            place.name,
                                            style: TextStyle(
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: Text(
                                            place.displayName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  isFav
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  color: isFav
                                                      ? Colors.red
                                                      : Colors.grey,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _toggleFavorite(place),
                                                tooltip: isFav
                                                    ? 'Quitar de favoritos'
                                                    : 'Agregar a favoritos',
                                              ),
                                              const Icon(
                                                  Icons.arrow_forward_ios,
                                                  size: 16),
                                            ],
                                          ),
                                          onTap: () {
                                            developer.log(
                                                'Lugar seleccionado: ${place.name}',
                                                name: 'PlaceFinder');
                                            _getPlaceInfo(place);
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedPlace != null)
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      margin: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: _buildMap(),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      margin: const EdgeInsets.only(
                                          top: 16, bottom: 16, right: 16),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: _isLoadingInfo
                                          ? const Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  CircularProgressIndicator(),
                                                  SizedBox(height: 16),
                                                  Text(
                                                      'Obteniendo información...'),
                                                ],
                                              ),
                                            )
                                          : _placeInfo != null
                                              ? SingleChildScrollView(
                                                  padding:
                                                      const EdgeInsets.all(20),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.book,
                                                              color:
                                                                  Colors.indigo,
                                                              size: 28),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              _placeInfo!.title,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 22,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const Divider(height: 24),
                                                      const Row(
                                                        children: [
                                                          Icon(
                                                              Icons.history_edu,
                                                              color:
                                                                  Colors.indigo,
                                                              size: 20),
                                                          SizedBox(width: 8),
                                                          Text(
                                                            'Historia y Cultura',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.indigo,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      Text(
                                                        _placeInfo!.extract,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          height: 1.6,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 20),
                                                      if (_placeInfo!.url !=
                                                          null)
                                                        ElevatedButton.icon(
                                                          onPressed: () async {
                                                            try {
                                                              final url =
                                                                  Uri.parse(
                                                                      _placeInfo!
                                                                          .url!);
                                                              final canLaunch =
                                                                  await canLaunchUrl(
                                                                      url);
                                                              if (canLaunch) {
                                                                await launchUrl(
                                                                    url);
                                                              } else {
                                                                if (!context
                                                                    .mounted) {
                                                                  return;
                                                                }
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  const SnackBar(
                                                                    content: Text(
                                                                        'No se pudo abrir el navegador'),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                              }
                                                            } catch (e) {
                                                              developer.log(
                                                                  'Error al abrir URL: $e',
                                                                  name:
                                                                      'PlaceFinder');
                                                              if (!context
                                                                  .mounted) {
                                                                return;
                                                              }
                                                              ScaffoldMessenger
                                                                      .of(context)
                                                                  .showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                      'Error: ${e.toString()}'),
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red,
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          icon: const Icon(Icons
                                                              .open_in_new),
                                                          label: const Text(
                                                              'Ver artículo completo'),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.indigo,
                                                            foregroundColor:
                                                                Colors.white,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 20,
                                                              vertical: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      const SizedBox(
                                                          height: 20),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(16),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isDark
                                                              ? Colors
                                                                  .indigo[900]
                                                                  ?.withValues(
                                                                      alpha:
                                                                          0.3)
                                                              : Colors
                                                                  .indigo[50],
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Row(
                                                              children: [
                                                                Icon(
                                                                    Icons
                                                                        .location_on,
                                                                    color: Colors
                                                                        .indigo,
                                                                    size: 20),
                                                                SizedBox(
                                                                    width: 8),
                                                                Text(
                                                                  'Ubicación',
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(_placeInfo!
                                                                .location),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                              'Coordenadas: ${_selectedPlace!.lat.toStringAsFixed(4)}, ${_selectedPlace!.lon.toStringAsFixed(4)}',
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: isDark
                                                                    ? Colors.grey[
                                                                        400]
                                                                    : Colors.grey[
                                                                        700],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : const Center(
                                                  child: Text(
                                                      'Cargando información...'),
                                                ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _places.length,
                              itemBuilder: (context, index) {
                                final place = _places[index];
                                final isSelected =
                                    _selectedPlace?.placeId == place.placeId;
                                final isFav = _isFavorite(place);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  color: isSelected
                                      ? (isDark
                                          ? Colors.indigo[900]
                                          : Colors.indigo[50])
                                      : (isDark
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? Colors.indigo
                                          : Colors.grey[400],
                                      child: const Icon(Icons.place,
                                          color: Colors.white),
                                    ),
                                    title: Text(
                                      place.name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      place.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        isFav
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: isFav ? Colors.red : Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleFavorite(place),
                                    ),
                                    onTap: () => _getPlaceInfo(place),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_selectedPlace != null)
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: _buildMap(),
                                      ),
                                    ),
                                  ),
                                  if (_placeInfo != null)
                                    Container(
                                      constraints:
                                          const BoxConstraints(maxHeight: 300),
                                      margin: const EdgeInsets.only(
                                          left: 16, right: 16, bottom: 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _placeInfo!.title,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _placeInfo!.extract,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(height: 12),
                                            if (_placeInfo!.url != null)
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  onPressed: () async {
                                                    try {
                                                      final url = Uri.parse(
                                                          _placeInfo!.url!);
                                                      final canLaunch =
                                                          await canLaunchUrl(
                                                              url);
                                                      if (canLaunch) {
                                                        await launchUrl(url);
                                                      } else {
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                                'No se pudo abrir el navegador'),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      developer.log(
                                                          'Error al abrir URL: $e',
                                                          name: 'PlaceFinder');
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Error: ${e.toString()}'),
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                      Icons.open_in_new),
                                                  label: const Text(
                                                      'Ver en Wikipedia'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.indigo,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class Place {
  final String placeId;
  final String name;
  final String displayName;
  final double lat;
  final double lon;
  final String type;

  Place({
    required this.placeId,
    required this.name,
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.type,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      placeId: json['place_id'].toString(),
      name: json['display_name'].toString().split(',')[0],
      displayName: json['display_name'].toString(),
      lat: double.parse(json['lat'].toString()),
      lon: double.parse(json['lon'].toString()),
      type: json['type']?.toString() ?? 'place',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place_id': placeId,
      'display_name': displayName,
      'lat': lat.toString(),
      'lon': lon.toString(),
      'type': type,
    };
  }
}

class PlaceInfo {
  final String title;
  final String extract;
  final String? url;
  final String location;

  PlaceInfo({
    required this.title,
    required this.extract,
    required this.url,
    required this.location,
  });
}
