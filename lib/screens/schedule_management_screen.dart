import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:admin_league/services/api_service.dart';

class ScheduleManagementScreen extends StatefulWidget {
  final String scheduleId; // ID del documento 'official_schedule'
  final String categoryName;
  final String tournamentId;

  const ScheduleManagementScreen({
    super.key,
    required this.scheduleId,
    required this.categoryName,
    required this.tournamentId,
  });

  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  Map<String, dynamic>? _scheduleDoc;
  Map<String, dynamic> _teamsLookup = {};
  List<dynamic> _conflicts = [];
  List<dynamic> _jornadas = [];

  Map<String, dynamic>? _selectedMatch;
  int? _sourceJornadaIndex;

  // Paleta unificada (eficiencia visual y consistencia)
  static const Color _bgScaffold = Color(0xFFF2F2F7);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _orangeWarning = Color(0xFFFF9500);
  static const Color _redError = Color(0xFFFF3B30);
  static const Color _textPrimary = Color(0xFF1C1C1E);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _borderLight = Color(0xFFE5E7EB);
  static const Color _success = Color(0xFF10B981);
  static const double _radiusCard = 16;
  static const double _radiusChip = 20;

  @override
  void initState() {
    super.initState();
    _loadScheduleData();
  }

  Future<void> _loadScheduleData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getDocById(widget.scheduleId);

      // 2. Cargar Equipos FRESCOS de esta categoría
      // Usamos tu función específica para traer solo lo necesario
      final freshTeamsRes = await _apiService.getTeamsByTournamentCat(
        widget.tournamentId,
        widget.categoryName,
      );

      if (response.statusCode == 200) {
        final jsonResponse = response.data;
        final doc = jsonResponse['doc'];

        Map<String, dynamic> lookup = Map<String, dynamic>.from(
          doc['teamsLookup'] ?? {},
        );

        // --- FUSIÓN DE DATOS (CORREGIDA) ---
        if (freshTeamsRes.statusCode == 200) {
          var rawData = freshTeamsRes.data;
          List<dynamic> freshTeams = [];

          if (rawData is Map && rawData.containsKey('rows')) {
            freshTeams = (rawData['rows'] as List)
                .map((r) => r['value'] ?? r['doc'])
                .toList();
          } else if (rawData is List) {
            freshTeams = rawData;
          }

          for (var freshTeam in freshTeams) {
            String freshId = (freshTeam['_id'] ?? freshTeam['id']).toString();
            bool wasUpdated = false;

            // 1. Buscar si está guardado por su ID directo
            if (lookup.containsKey(freshId)) {
              lookup[freshId]['constraints'] = freshTeam['constraints'];
              lookup[freshId]['name'] = freshTeam['name'];
              lookup[freshId]['logo'] = freshTeam['logo'];
              wasUpdated = true;
            }

            // 2. BÚSQUEDA PROFUNDA: Si está guardado bajo una llave de Slot (ej. "1-2")
            lookup.forEach((key, savedTeam) {
              String savedId = (savedTeam['_id'] ?? savedTeam['id'] ?? '')
                  .toString();

              if (savedId == freshId) {
                // Actualizamos los datos frescos
                lookup[key]['constraints'] = freshTeam['constraints'];
                lookup[key]['name'] = freshTeam['name'];
                lookup[key]['logo'] = freshTeam['logo'];
                wasUpdated = true;
              }
            });

            // 3. Si el equipo es completamente nuevo y no estaba en el calendario viejo, lo agregamos
            if (!wasUpdated) {
              lookup[freshId] = freshTeam;
            }
          }
          print(
            ">>> Datos frescos de Constraints sincronizados correctamente.",
          );
        }

        setState(() {
          _scheduleDoc = doc;
          _conflicts = doc['unresolvedConflicts'] ?? [];
          _jornadas = doc['jornadas'] ?? [];
          _teamsLookup = lookup;
          _isLoading = false;
        });
      } else {
        throw Exception("Error ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error cargando calendario: $e"),
          backgroundColor: _redError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si no hay datos, mostrar carga
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Punto de quiebre: 900px
        bool isDesktop = constraints.maxWidth > 900;

        return Scaffold(
          backgroundColor: _bgScaffold,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tablero de Control",
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "${widget.categoryName} • ${_jornadas.length} Jornadas",
                  style: GoogleFonts.inter(color: _textSecondary, fontSize: 12),
                ),
              ],
            ),
            actions: [
              // Botones existentes (Refrescar, Balance)
              IconButton(
                icon: const Icon(Icons.refresh, color: _textPrimary),
                onPressed: _loadScheduleData,
              ),
              IconButton(
                icon: const Icon(Icons.bar_chart, color: _textPrimary),
                onPressed: _showBalanceStats,
              ),

              // --- NUEVO: MENÚ DE ESTRUCTURA ---
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _textPrimary),
                tooltip: "Modificar estructura",
                onSelected: (value) {
                  switch (value) {
                    case 'add_end':
                      _addNewJornadaAtEnd();
                      break;
                    case 'insert_start':
                      _insertJornadaAtStart(); // <--- ESTO ES EL "RECORRER"
                      break;
                    case 'delete_empty':
                      _deleteAllEmptyJornadas();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'add_end',
                    child: ListTile(
                      leading: Icon(Icons.playlist_add, color: Colors.indigo),
                      title: Text("Agregar Jornada al final"),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'insert_start',
                    child: ListTile(
                      leading: Icon(Icons.start, color: Colors.orange),
                      title: Text("Insertar vacía al inicio"),
                      subtitle: Text("Recorre todo +1 (J1 -> J2)"),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'delete_empty',
                    child: ListTile(
                      leading: Icon(Icons.delete_sweep, color: Colors.red),
                      title: Text("Borrar todas las vacías"),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
            leading: const BackButton(color: _textPrimary),
          ),
          body: Column(
            children: [
              // Zona de Conflictos (Siempre visible si hay problemas)
              if (_conflicts.isNotEmpty) _buildConflictZone(),

              // Cuerpo Principal
              Expanded(
                child: isDesktop
                    ? _buildDesktopGrid() // VISTA ESCRITORIO
                    : _buildMobileTabs(), // VISTA MÓVIL
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileTabs() {
    return DefaultTabController(
      length: _jornadas.length,
      child: Column(
        children: [
          // 1. Pestañas Superiores
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelColor: Colors.indigo,
              unselectedLabelColor: _textSecondary,
              indicatorColor: Colors.indigo,
              tabs: _jornadas.map((j) => Tab(text: "J${j['number']}")).toList(),
            ),
          ),

          // 2. Contenido de la Jornada
          Expanded(
            child: TabBarView(
              children: List.generate(_jornadas.length, (index) {
                final analysis = _analyzeJornada(index);

                // Lógica para saber si mostrar el botón de mover
                bool isMovingMode = _selectedMatch != null;
                bool isSource = _sourceJornadaIndex == index;
                bool canDropHere = isMovingMode && !isSource;

                return Column(
                  children: [
                    // --- ZONA DE ACCIÓN (NUEVO PARA MÓVIL) ---
                    if (canDropHere)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(16),
                        child: ElevatedButton.icon(
                          onPressed: () => _moveMatchToJornada(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            "MOVER PARTIDO A JORNADA ${analysis.jornadaNumber}",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Lista de Partidos
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        children: [
                          // Alerta Foráneos móvil
                          if (analysis.foreignRequests.isNotEmpty)
                            _buildForeignHeaderMobile(analysis),

                          ...analysis.matches
                              .map(
                                (m) => _buildMatchCard(
                                  m,
                                  index,
                                  analysis.doubleDutyIds,
                                ),
                              )
                              .toList(),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),

                    // Panel de Estado
                    _buildStatusPanelMobile(analysis),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // Header especial para móvil si hay foráneos
  Widget _buildForeignHeaderMobile(JornadaAnalysis analysis) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple[100]!),
      ),
      child: Row(
        children: [
          Icon(Icons.flight_takeoff, size: 16, color: Colors.purple[700]),
          const SizedBox(width: 8),
          Text(
            "Jornada de viaje (${analysis.foreignRequests.length} equipos)",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.purple[900],
            ),
          ),
        ],
      ),
    );
  }

  // Panel Inferior (Resumen de Descansos)
  Widget _buildStatusPanelMobile(JornadaAnalysis analysis) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Estado de la Jornada",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Chips de Descanso
                ...analysis.restingTeams.map(
                  (t) => _buildStatusChip(t['name'], Colors.grey),
                ),
                // Chips de Bye (Verdes si descansan, Rojos si juegan por error - lógica en analyze)
                ...analysis.byeRequests.map(
                  (t) => _buildStatusChip(
                    t['name'],
                    Colors.green,
                    icon: Icons.pause_circle,
                  ),
                ),
              ],
            ),
          ),
          if (analysis.restingTeams.isEmpty && analysis.byeRequests.isEmpty)
            Text(
              "Todos juegan",
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopGrid() {
    // 1. Configuración de columnas
    double screenWidth = MediaQuery.of(context).size.width;
    int numColumns = (screenWidth / 300).floor().clamp(
      2,
      4,
    ); // Entre 2 y 4 columnas dinámicas

    // 2. Inicializar listas
    List<List<Widget>> columns = List.generate(numColumns, (_) => []);

    // 3. Repartir Jornadas (Waterfall)
    for (int i = 0; i < _jornadas.length; i++) {
      final analysis = _analyzeJornada(i);
      int columnIndex = i % numColumns;
      columns[columnIndex].add(_buildJornadaPanel(analysis, i));
    }

    // 4. Renderizar
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns.map((colWidgets) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: colWidgets, // Columnas verticales flexibles
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Nuevo Widget: Panel de Jornada (Tarjeta Compacta)
  Widget _buildJornadaPanel(JornadaAnalysis analysis, int index) {
    // 1. ESTADOS DE INTERACCIÓN
    bool isSource = _sourceJornadaIndex == index;
    bool isMovingMode = _selectedMatch != null;

    // 2. DATOS DE CONTENIDO
    int totalDescansos =
        analysis.restingTeams.length + analysis.byeRequests.length;
    int totalPartidos = analysis.matches.length;

    // 3. CONDICIÓN DE FOOTER (Mostrar si hay alertas o descansos)
    bool showFooter =
        analysis.foreignRequests.isNotEmpty ||
        analysis.restingTeams.isNotEmpty ||
        analysis.byeRequests.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // Naranja si es origen, Azul tenue si es destino posible, Gris si es normal
          color: isSource
              ? _orangeWarning
              : (isMovingMode
                    ? Colors.indigoAccent.withAlpha(100)
                    : Colors.grey[200]!),
          width: isSource || isMovingMode ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min, // Se ajusta al contenido (sin scroll interno)
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // =========================================================
          // A. CABECERA INTELIGENTE
          // =========================================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              // Resaltamos suavemente el fondo si es un destino válido para soltar
              color: (isMovingMode && !isSource)
                  ? Colors.indigo.withAlpha(10)
                  : Colors.grey[50],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                // A1. Título de Jornada
                Text(
                  "JORNADA ${analysis.jornadaNumber}",
                  style: GoogleFonts.oswald(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSource ? _orangeWarning : _textPrimary,
                  ),
                ),

                const Spacer(),

                // A2. LÓGICA DE BOTONES A LA DERECHA

                // CASO 1: Modo Mover y es un destino válido (incl. jornadas vacías) -> MOVER AQUÍ
                if (isMovingMode && !isSource)
                  ElevatedButton.icon(
                    onPressed: () => _moveMatchToJornada(index),
                    icon: const Icon(Icons.input, size: 12),
                    label: const Text("MOVER AQUÍ"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 28), // Altura compacta
                      textStyle: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                // CASO 2: Jornada vacía (y no en modo mover) -> Mostrar opción de BORRAR
                else if (totalPartidos == 0)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    tooltip: "Borrar jornada vacía",
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(), // Elimina padding extra
                    onPressed: () => _deleteJornada(index),
                  )
                // CASO 3: Normal -> Mostrar Contadores (Badges)
                else ...[
                  // Badge Partidos
                  _buildHeaderBadge("$totalPartidos P.", Colors.blueGrey),

                  // Badge Descansos (si hay)
                  if (totalDescansos > 0) ...[
                    const SizedBox(width: 4),
                    _buildHeaderBadge("$totalDescansos D.", Colors.orange),
                  ],
                ],
              ],
            ),
          ),

          // =========================================================
          // B. CUERPO (LISTA DE PARTIDOS)
          // =========================================================
          if (totalPartidos > 0)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: analysis.matches
                    .map(
                      (m) => _buildMatchCard(m, index, analysis.doubleDutyIds),
                    )
                    .toList(),
              ),
            )
          else
            // Espacio vacío visual si no hay partidos (para que no se vea tan aplastado)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "Sin partidos asignados",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

          // =========================================================
          // C. FOOTER (ALERTAS Y DESCANSOS)
          // =========================================================
          if (showFooter) _buildPanelFooter(analysis),
        ],
      ),
    );
  }

  // Helper para los badges pequeños del header
  Widget _buildHeaderBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPanelFooter(JornadaAnalysis analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[100]!)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ALERTAS FORÁNEAS
          if (analysis.foreignRequests.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.flight_takeoff, size: 12, color: Colors.purple[700]),
                const SizedBox(width: 4),
                Text(
                  "VIAJAN:",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: analysis.foreignRequests.map((team) {
                int played =
                    analysis.foreignPlayCount[team['_id'].toString()] ?? 0;
                Color color = played == 0
                    ? _redError
                    : (played == 1 ? _orangeWarning : _success);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "${team['name']} ($played/2)",
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],

          // 2. DESCANSOS (Esta es la parte que querías recuperar)
          if (analysis.restingTeams.isNotEmpty ||
              analysis.byeRequests.isNotEmpty) ...[
            Text(
              "DESCANSAN:",
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                ...analysis.byeRequests.map((t) => "${t['name']} (Bye)"),
                ...analysis.restingTeams.map((t) => t['name']),
              ].join(", "),
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[700]),
              maxLines: 10, // Permitimos ver varios si son muchos
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKanbanFooter(JornadaAnalysis analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sección Foráneos (CRÍTICA)
          if (analysis.foreignRequests.isNotEmpty) ...[
            Text(
              "FORÁNEOS (META: 2 JUEGOS)",
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: analysis.foreignRequests.map((team) {
                int played = analysis.foreignPlayCount[team['_id']] ?? 0;
                Color status = played == 0
                    ? _redError
                    : (played == 1 ? _orangeWarning : _success);

                return Tooltip(
                  message: "Ha jugado $played partidos en esta jornada",
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: status,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${team['name']} ($played/2)",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 16),
          ],

          // Sección Descansos
          if (analysis.restingTeams.isNotEmpty) ...[
            Text(
              "DESCANSAN",
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              analysis.restingTeams.map((t) => t['name']).join(", "),
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchCard(dynamic match, int index, Set<String> doubleDutyIds) {
    final homeData = _getTeamData(match['home']);
    final awayData = _getTeamData(match['away']);

    // Número de jornada actual (para marcar equipos que pidieron bye)
    int jornadaNum = _jornadas[index]?['number'] ?? (index + 1);

    // Estados
    bool isFixed = match['isFixed'] == true;
    bool isSelected = _selectedMatch == match;

    // Detectar dobles y foráneos
    bool homeIsDouble = !isFixed && doubleDutyIds.contains(homeData['_id']);
    bool awayIsDouble = !isFixed && doubleDutyIds.contains(awayData['_id']);
    bool homeIsForeign =
        _teamsLookup[homeData['_id']]?['constraints']?['isForeign'] == true;
    bool awayIsForeign =
        _teamsLookup[awayData['_id']]?['constraints']?['isForeign'] == true;

    // Equipos que pidieron bye en esta jornada
    bool homeHasBye = _checkIfRequestedBye(
      homeData['_id'].toString(),
      jornadaNum,
    );
    bool awayHasBye = _checkIfRequestedBye(
      awayData['_id'].toString(),
      jornadaNum,
    );

    // --- NUEVO: Bandera unificada de conflicto de Bye ---
    bool hasByeConflict = homeHasBye || awayHasBye;

    // Formatear nombres
    final homeFmt = _formatTeamName(
      homeData['name'],
      homeIsForeign,
      homeIsDouble,
    );
    final awayFmt = _formatTeamName(
      awayData['name'],
      awayIsForeign,
      awayIsDouble,
    );

    // Colores de Barras Laterales
    Color homeBarColor = Colors.transparent;
    if (homeIsDouble)
      homeBarColor = homeIsForeign ? Colors.purple : const Color(0xFFD32F2F);

    Color awayBarColor = Colors.transparent;
    if (awayIsDouble)
      awayBarColor = awayIsForeign ? Colors.purple : const Color(0xFFD32F2F);

    // --- CONFIGURACIÓN VISUAL DEL ESTADO "JUGADO" O "CONFLICTO" ---
    Color bgColor = hasByeConflict
        ? _redError.withAlpha(20) // 1. Prioridad Máxima: Conflicto
        : (isFixed
              ? const Color(
                  0xFFE3F2FD,
                ) // 2. Prioridad Media: Partido fijo/jugado
              : (isSelected
                    ? const Color(0xFFFFF7ED)
                    : Colors.white)); // 3. Normal

    Color borderColor = hasByeConflict
        ? _redError // 1. Prioridad Máxima: Conflicto
        : (isSelected
              ? _orangeWarning // 2. Prioridad Media: Seleccionado
              : (isFixed ? Colors.blue[200]! : Colors.grey[200]!)); // 3. Normal

    return GestureDetector(
      onTap: () => _handleMatchTap(match, index, isFixed),
      onLongPress: () => _showMatchOptionsDialog(match, index, isFixed),
      child: Stack(
        children: [
          // 1. EL CONTENEDOR PRINCIPAL
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(5),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barra Lateral Izquierda
                  if (homeBarColor != Colors.transparent)
                    Container(width: 4, color: homeBarColor),

                  // Contenido Central
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        8,
                        8,
                        8,
                        8,
                      ), // Padding ajustado
                      child: Row(
                        children: [
                          // LOCAL
                          Expanded(
                            child: _buildTeamSide(
                              data: homeData,
                              fmt: homeFmt,
                              isLeft: true,
                              hasBye: homeHasBye,
                            ),
                          ),

                          // VS (Pequeño y centrado)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              "vs",
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: isFixed
                                    ? Colors.blue[300]
                                    : Colors.grey[400],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          // VISITA
                          Expanded(
                            child: _buildTeamSide(
                              data: awayData,
                              fmt: awayFmt,
                              isLeft: false,
                              hasBye: awayHasBye,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Barra Lateral Derecha
                  if (awayBarColor != Colors.transparent)
                    Container(width: 4, color: awayBarColor),
                ],
              ),
            ),
          ),

          // 2. BADGE SUTIL DE JORNADA (Solo si es partido Fijo/Jugado)
          if (isFixed)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(
                    150,
                  ), // Semitransparente para que se mezcle
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, size: 8, color: Colors.blue[800]),
                    const SizedBox(width: 2),
                    Text(
                      "J${index + 1}", // Muestra J1, J2, etc.
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Widget auxiliar para construir cada lado del equipo con su línea de color
  Widget _buildTeamSide({
    required Map<String, dynamic> data,
    required Map<String, dynamic> fmt,
    required bool isLeft,
    bool hasBye = false,
  }) {
    // Si pidió bye en esta jornada: resaltado ROJO FUERTE
    final Color textColor = hasBye ? _redError : (fmt['color'] as Color);
    final Color smallColor = hasBye
        ? _redError.withAlpha(200)
        : Colors.grey[500]!;

    Widget textContent = Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            fmt['big'],
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isLeft ? TextAlign.left : TextAlign.right,
          ),
        ),
        if ((fmt['small'] as String).isNotEmpty)
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              fmt['small'],
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: smallColor,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: isLeft ? TextAlign.left : TextAlign.right,
            ),
          ),
      ],
    );

    // Alerta de Bye muy visual
    Widget? byeBadge = hasBye
        ? Container(
            margin: const EdgeInsets.only(left: 4, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _redError.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _redError.withAlpha(150)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 10, color: _redError),
                const SizedBox(width: 2),
                Text(
                  "BYE",
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _redError,
                  ),
                ),
              ],
            ),
          )
        : null;

    Widget rowContent = Row(
      mainAxisAlignment: isLeft
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: isLeft
          ? [
              _buildMiniLogo(data['logo']),
              const SizedBox(width: 6),
              Expanded(child: textContent),
              if (byeBadge != null) byeBadge,
            ]
          : [
              if (byeBadge != null) byeBadge,
              Expanded(child: textContent),
              const SizedBox(width: 6),
              _buildMiniLogo(data['logo']),
            ],
    );

    if (hasBye) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _redError.withAlpha(10), // Resaltado de fondo rojo suave
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _redError.withAlpha(100), width: 1.5),
        ),
        child: rowContent,
      );
    }
    return rowContent;
  }

  Widget _buildMiniLogo(String? url) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[300]!, width: 0.5),
        image: url != null
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? const Icon(Icons.shield, size: 10, color: Colors.grey)
          : null,
    );
  }

  bool _checkIfRequestedBye(String teamId, int jornadaNum) {
    String targetJornada = jornadaNum.toString();

    // 1. Imprimir los datos de entrada
    print("\n[DEBUG BYE] ---------------------------------------");
    print(
      "[DEBUG BYE] Evaluando Equipo ID: '$teamId' para Jornada: $targetJornada",
    );

    // 2. Revisar en scheduleDoc
    if (_scheduleDoc?['teamConstraints'] != null) {
      var constraints = _scheduleDoc!['teamConstraints'];
      if (constraints[teamId] != null &&
          constraints[teamId]['requestedByes'] != null) {
        List byes = List.from(constraints[teamId]['requestedByes']);
        print("[DEBUG BYE] 📂 Encontrado en scheduleDoc: $byes");

        if (byes.map((e) => e.toString()).contains(targetJornada)) {
          print("[DEBUG BYE] ✅ ¡Match exitoso en scheduleDoc!");
          return true;
        }
      } else {
        print(
          "[DEBUG BYE] ⚠️ No hay 'requestedByes' en scheduleDoc para este ID.",
        );
      }
    } else {
      print("[DEBUG BYE] ⚠️ scheduleDoc no tiene 'teamConstraints'.");
    }

    // 3. Revisar en _teamsLookup
    var richTeamData;
    if (_teamsLookup.containsKey(teamId)) {
      richTeamData = _teamsLookup[teamId];
      print(
        "[DEBUG BYE] 🔍 Equipo encontrado en _teamsLookup por llave directa.",
      );
    } else {
      for (var team in _teamsLookup.values) {
        if (team['_id']?.toString() == teamId ||
            team['id']?.toString() == teamId) {
          richTeamData = team;
          print(
            "[DEBUG BYE] 🔍 Equipo encontrado iterando _teamsLookup (ID: ${team['_id']}).",
          );
          break;
        }
      }
    }

    if (richTeamData != null) {
      print("[DEBUG BYE] 👤 Nombre del equipo: ${richTeamData['name']}");

      if (richTeamData['constraints'] != null) {
        List byeJornadas =
            richTeamData['constraints']['byeJornadas'] ??
            richTeamData['constraints']['requestedByes'] ??
            [];

        print("[DEBUG BYE] 📋 Arrays encontrados -> byeJornadas: $byeJornadas");

        if (byeJornadas.map((e) => e.toString()).contains(targetJornada)) {
          print("[DEBUG BYE] ✅ ¡Match exitoso en _teamsLookup!");
          return true;
        } else {
          print(
            "[DEBUG BYE] ❌ El array no contiene la jornada $targetJornada.",
          );
        }
      } else {
        print(
          "[DEBUG BYE] ⚠️ El objeto del equipo no tiene la propiedad 'constraints'.",
        );
      }
    } else {
      print("[DEBUG BYE] 🚨 ¡Alerta! Equipo no encontrado en _teamsLookup.");
    }

    print("[DEBUG BYE] Resultado final: FALSE");
    return false;
  }

  Widget _buildConflictZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: _orangeWarning.withAlpha(8),
        border: Border(bottom: BorderSide(color: _borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: _orangeWarning,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                "Pendientes de asignar (${_conflicts.length})",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _conflicts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final conflict = _conflicts[i];
                final homeName = conflict['teams']?['home']?['name'] ?? "Local";
                final awayName =
                    conflict['teams']?['away']?['name'] ?? "Visita";
                final reason = conflict['conflictReason'] ?? "Conflicto";
                final originalRound = conflict['originalRound'];

                return Container(
                  width: 260,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(_radiusCard),
                    border: Border.all(color: _orangeWarning.withAlpha(30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _orangeWarning.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "Ronda $originalRound",
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _orangeWarning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "$homeName vs $awayName",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        reason,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _redError,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(
                        height: 32,
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _orangeWarning),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _showResolveDialog(conflict),
                          child: Text(
                            "Resolver",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _orangeWarning,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJornadaCard(
    int index,
    Map<String, dynamic> jornada,
    Set<String> doubleDutyIds,
    List<Map<String, dynamic>> restTeams,
    List<Map<String, dynamic>> byeTeams,
  ) {
    int number = jornada['number'];
    List matches = jornada['matches'] ?? [];

    // --- NUEVO: Detectar Foráneos ---
    List<Map<String, dynamic>> foreignRequests = _getForeignRequestsForJornada(
      number,
    );

    // Calculamos cuántos juegos tiene ya cada foráneo en ESTA jornada
    // Para mostrar visualmente si ya tienen su doble jornada (2) o les falta.
    Map<String, int> foreignMatchCount = {};
    if (foreignRequests.isNotEmpty) {
      for (var m in matches) {
        String hId = _getTeamData(m['home'])['_id'];
        String aId = _getTeamData(m['away'])['_id'];
        if (hId.isNotEmpty)
          foreignMatchCount[hId] = (foreignMatchCount[hId] ?? 0) + 1;
        if (aId.isNotEmpty)
          foreignMatchCount[aId] = (foreignMatchCount[aId] ?? 0) + 1;
      }
    }

    // Determinar si hay una reasignación en curso
    bool isMovingMode = _selectedMatch != null;
    bool isSourceJornada = _sourceJornadaIndex == index;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(_radiusCard),
        border: Border.all(
          color: (isMovingMode && !isSourceJornada)
              ? _orangeWarning
              : _borderLight,
          width: (isMovingMode && !isSourceJornada) ? 2 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: number == 1 || (isMovingMode && isSourceJornada),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSourceJornada
                  ? _orangeWarning.withAlpha(30)
                  : _bgScaffold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "J$number",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                color: isSourceJornada ? _orangeWarning : _textPrimary,
                fontSize: 15,
              ),
            ),
          ),
          title: Row(
            children: [
              Text(
                "Jornada $number",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),

              // Indicador rápido si hay foráneos en esta fecha
              if (foreignRequests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.flight_takeoff,
                    size: 16,
                    color: Colors.purple[300],
                  ),
                ),

              if (isMovingMode && !isSourceJornada)
                ElevatedButton.icon(
                  onPressed: () => _moveMatchToJornada(index),
                  icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                  label: const Text("Mover aquí"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orangeWarning,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
          children: [
            ...matches
                .map((match) => _buildMatchItem(match, index, doubleDutyIds))
                .toList(),

            // SECCIÓN INFERIOR DE ESTADO
            if (restTeams.isNotEmpty ||
                byeTeams.isNotEmpty ||
                foreignRequests.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bgScaffold,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(_radiusCard),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(height: 1, color: _borderLight),
                    const SizedBox(height: 10),

                    // 1. SECCIÓN FORÁNEOS (NUEVO)
                    if (foreignRequests.isNotEmpty) ...[
                      _buildForeignRequestsRow(
                        foreignRequests,
                        foreignMatchCount,
                      ),
                      const SizedBox(
                        height: 12,
                      ), // Separador si hay más listas abajo
                    ],

                    // 2. SECCIÓN DESCANSOS NORMALES
                    if (restTeams.isNotEmpty)
                      _buildInactivityRow(
                        "En descanso",
                        restTeams,
                        _textSecondary,
                      ),

                    if (restTeams.isNotEmpty && byeTeams.isNotEmpty)
                      const SizedBox(height: 10),

                    // 3. SECCIÓN BYES SOLICITADOS
                    if (byeTeams.isNotEmpty)
                      _buildInactivityRow(
                        "Bye solicitado",
                        byeTeams,
                        _orangeWarning,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForeignRequestsRow(
    List<Map<String, dynamic>> teams,
    Map<String, int> matchCounts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flight_takeoff, size: 12, color: Colors.purple[700]),
            const SizedBox(width: 6),
            Text(
              "Solicitud Foránea (Viaje)",
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.purple[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: teams.map((team) {
            String id = team['_id'];
            int played = matchCounts[id] ?? 0;

            // Color semáforo: Rojo (0 juegos), Naranja (1 juego), Verde (2 juegos)
            Color statusColor = played == 0
                ? Colors.red
                : (played == 1 ? Colors.orange : Colors.green);
            bool isComplete = played >= 2;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple.withAlpha(10),
                borderRadius: BorderRadius.circular(_radiusChip),
                border: Border.all(color: Colors.purple.withAlpha(30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.purple.withAlpha(20),
                    backgroundImage: team['logo'] != null
                        ? NetworkImage(team['logo'])
                        : null,
                    child: team['logo'] == null
                        ? Icon(
                            Icons.shield,
                            size: 10,
                            color: Colors.purple[300],
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    team['name'],
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple[900],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Contador de Partidos: (0/2)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "$played", // Muestra 0, 1 o 2
                      style: GoogleFonts.oswald(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInactivityRow(
    String label,
    List<Map<String, dynamic>> teams,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: teams
              .map(
                (team) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(_radiusChip),
                    border: Border.all(color: _borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: Colors.grey[100],
                        backgroundImage: team['logo'] != null
                            ? NetworkImage(team['logo'])
                            : null,
                        child: team['logo'] == null
                            ? const Icon(
                                Icons.shield,
                                size: 10,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        team['name'],
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Map<String, dynamic> _getTeamData(dynamic teamInput) {
    if (teamInput == null) return {'_id': '', 'name': 'Error', 'isReal': false};

    // OPCIÓN A: Nuevo formato (Objeto completo)
    if (teamInput is Map && teamInput.containsKey('_id')) {
      return {
        '_id': teamInput['_id'].toString(),
        'name': teamInput['name'] ?? "Desconocido",
        'logo': teamInput['logo'] ?? teamInput['img'],
        'isReal': true,
      };
    }

    // OPCIÓN B: Referencia vieja o Slot (Fallback)
    String key = "";
    if (teamInput is Map && teamInput.containsKey('slot')) {
      // Si viene {group:1, slot:2} y no lo encontramos hidratado
      key = "${teamInput['group']}-${teamInput['slot']}";
      // Intenta también solo slot si no encuentra grupo-slot
      if (!_teamsLookup.containsKey(key)) key = teamInput['slot'].toString();
    } else {
      key = teamInput.toString();
    }

    if (_teamsLookup.containsKey(key)) {
      final team = _teamsLookup[key];
      return {
        '_id': team['_id'] ?? key,
        'name': team['name'] ?? "Equipo Desconocido",
        'logo': team['logo'] ?? team['img'],
        'isReal': true,
      };
    }

    // Si falló todo
    return {'_id': key, 'name': "Slot $key", 'logo': null, 'isReal': false};
  }

  Widget _buildMatchItem(
    dynamic match,
    int jornadaIndex,
    Set<String> doubleDutyIds,
  ) {
    final homeData = _getTeamData(match['home']);
    final awayData = _getTeamData(match['away']);

    // Flags nuevos del backend
    bool isFixed = match['isFixed'] == true || match['played'] == true;
    bool isRepeat = match['isRepeat'] == true;
    String? score = match['score']?.toString(); // Si hay marcador

    String homeId = homeData['_id'];
    String awayId = awayData['_id'];

    int jornadaNum = _jornadas[jornadaIndex]?['number'] ?? (jornadaIndex + 1);
    bool hasByeConflict =
        _checkIfRequestedBye(homeId, jornadaNum) ||
        _checkIfRequestedBye(awayId, jornadaNum);

    // Solo marcamos doble jornada si NO es un partido fijo (histórico)
    bool homeIsDouble = !isFixed && doubleDutyIds.contains(homeId);
    bool awayIsDouble = !isFixed && doubleDutyIds.contains(awayId);

    // Estado de selección (Solo permitimos seleccionar si NO es fijo)
    bool isSelected = _selectedMatch == match;

    // Colores para partidos fijos/jugados o con error
    Color matchBg = isFixed
        ? const Color(0xFFF0FDF4)
        : (isSelected
              ? _orangeWarning.withAlpha(25)
              : (hasByeConflict
                    ? _redError.withAlpha(20)
                    : _cardBg)); // Fondo rojo tenue al fallar

    Color borderColor = isFixed
        ? _success.withAlpha(50)
        : (hasByeConflict
              ? _redError
              : _borderLight); // Borde rojo fuerte al fallar

    return InkWell(
      // Si es fijo, bloqueamos la interacción (onTap null)
      onTap: isFixed
          ? null
          : () {
              setState(() {
                if (isSelected) {
                  _selectedMatch = null;
                  _sourceJornadaIndex = null;
                } else {
                  _selectedMatch = match;
                  _sourceJornadaIndex = jornadaIndex;
                }
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: matchBg,
          border: Border(
            bottom: BorderSide(color: borderColor),
            left: BorderSide(
              color: isSelected
                  ? _orangeWarning
                  : (isFixed ? _success : Colors.transparent),
              width: 4,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildHalfTeam(
                name: homeData['name'],
                logoUrl: homeData['logo'],
                isDouble: homeIsDouble,
                isHome: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  if (isFixed) ...[
                    // Mostrar Marcador o Candado
                    if (score != null && score != "null")
                      Text(
                        score,
                        style: GoogleFonts.oswald(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _success,
                        ),
                      )
                    else
                      const Icon(Icons.lock, size: 14, color: _success),
                  ] else if (isSelected) ...[
                    const Icon(
                      Icons.touch_app,
                      size: 16,
                      color: _orangeWarning,
                    ),
                  ] else ...[
                    Text(
                      "VS",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ],

                  if (isRepeat && !isFixed)
                    Icon(Icons.repeat_rounded, size: 14, color: _orangeWarning),
                ],
              ),
            ),
            Expanded(
              child: _buildHalfTeam(
                name: awayData['name'],
                logoUrl: awayData['logo'],
                isDouble: awayIsDouble,
                isHome: false,
              ),
            ),
            // Botón cerrar solo si está seleccionado
            if (isSelected)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: _redError),
                onPressed: () => setState(() {
                  _selectedMatch = null;
                  _sourceJornadaIndex = null;
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHalfTeam({
    required String name,
    String? logoUrl,
    required bool isDouble,
    required bool isHome,
  }) {
    Widget avatar = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bgScaffold,
        border: Border.all(
          color: isDouble ? _redError.withAlpha(50) : _borderLight,
          width: isDouble ? 2 : 1,
        ),
      ),
      child: ClipOval(
        child: (logoUrl != null && logoUrl.isNotEmpty)
            ? Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.shield, size: 14, color: Colors.grey),
              )
            : const Icon(Icons.shield, size: 14, color: Colors.grey),
      ),
    );

    Widget nameWidget = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: isHome ? TextAlign.left : TextAlign.right,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: isDouble ? FontWeight.w800 : FontWeight.w600,
          color: isDouble ? _redError : _textPrimary,
        ),
      ),
    );

    Widget? doubleBadge = isDouble
        ? Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _redError.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _redError.withAlpha(30)),
            ),
            child: Text(
              "2x",
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _redError,
              ),
            ),
          )
        : null;

    return Row(
      mainAxisAlignment: isHome
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: isHome
          ? [
              avatar,
              const SizedBox(width: 8),
              nameWidget,
              if (doubleBadge != null) doubleBadge,
            ]
          : [
              if (doubleBadge != null) doubleBadge,
              nameWidget,
              const SizedBox(width: 8),
              avatar,
            ],
    );
  }

  // A. AGREGAR AL FINAL
  void _addNewJornadaAtEnd() {
    setState(() {
      int nextNum = _jornadas.length + 1;
      _jornadas.add({'number': nextNum, 'matches': []});
    });
    // Scroll al final (opcional)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Jornada agregada al final")));
  }

  // B. INSERTAR AL INICIO (RECORRER TODO)
  // Esto soluciona tu problema: "Categorías que inician en J2"
  void _insertJornadaAtStart() {
    setState(() {
      // 1. Insertamos una vacía al principio
      _jornadas.insert(0, {
        'number': 1, // Provisional
        'matches': [],
      });

      // 2. Renumeramos TODAS las jornadas para que sean consecutivas
      _renumberJornadas();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Se insertó una jornada vacía al inicio. Todo se recorrió +1.",
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // C. BORRAR INDIVIDUAL (Se llama desde el botón de basura en la tarjeta)
  void _deleteJornada(int index) {
    setState(() {
      _jornadas.removeAt(index);
      _renumberJornadas(); // Importante: Recalcular números (J3 -> J2)
    });
  }

  // D. BORRAR TODAS LAS VACÍAS
  void _deleteAllEmptyJornadas() {
    setState(() {
      _jornadas.removeWhere((j) => (j['matches'] as List).isEmpty);
      _renumberJornadas();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Jornadas vacías eliminadas")));
  }

  // HELPER: RENUMERAR
  // Asegura que siempre digan J1, J2, J3 en orden, sin huecos
  void _renumberJornadas() {
    for (int i = 0; i < _jornadas.length; i++) {
      _jornadas[i]['number'] = i + 1;
    }
    // Guardamos cambios automáticamente o esperamos que el usuario de guardar?
    // Sugiero que el usuario deba dar click en Guardar cambios,
    // pero si prefieres auto-guardado, llama a _saveScheduleChangesToDB() aquí.
  }

  void _showResolveDialog(Map<String, dynamic> conflict) {
    final int originalRound = conflict['originalRound'] ?? -1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusCard)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Asignar partido manualmente",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _jornadas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final jornada = _jornadas[index];
                  final int roundNum = jornada['number'];
                  final bool isOriginal = roundNum == originalRound;
                  return ListTile(
                    enabled: !isOriginal,
                    tileColor: isOriginal ? _redError.withAlpha(8) : _cardBg,
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isOriginal
                            ? _redError.withAlpha(15)
                            : _bgScaffold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "J$roundNum",
                        style: GoogleFonts.inter(
                          color: isOriginal ? _redError : _textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    title: Text(
                      "Jornada $roundNum",
                      style: GoogleFonts.inter(
                        color: isOriginal ? _redError : _textPrimary,
                        fontWeight: isOriginal
                            ? FontWeight.w500
                            : FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isOriginal
                        ? Icon(Icons.block_rounded, size: 20, color: _redError)
                        : Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: _textSecondary,
                          ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmManualAssignment(conflict, index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveMatchToJornada(int targetJornadaIndex) {
    if (_selectedMatch == null || _sourceJornadaIndex == null) return;
    if (_sourceJornadaIndex == targetJornadaIndex) {
      setState(() => _selectedMatch = null);
      return;
    }

    setState(() {
      // 1. Remover de la jornada origen
      (_jornadas[_sourceJornadaIndex!]['matches'] as List).remove(
        _selectedMatch,
      );

      // 2. Agregar a la jornada destino
      (_jornadas[targetJornadaIndex]['matches'] as List).add(_selectedMatch);

      // 3. Limpiar selección
      _selectedMatch = null;
      _sourceJornadaIndex = null;

      // Actualizar el documento principal
      _scheduleDoc!['jornadas'] = _jornadas;
    });

    _saveScheduleChangesToDB();
  }

  void _confirmManualAssignment(
    Map<String, dynamic> conflict,
    int targetJornadaIndex,
  ) {
    final targetJornada = _jornadas[targetJornadaIndex];

    // 1. Extraer datos básicos del conflicto
    final homeSource = conflict['teams']['home'];
    final awaySource = conflict['teams']['away'];

    // 2. BUSCADA MAESTRA: Intentar recuperar datos ricos del lookup
    // Si el logo no viene en el conflicto, seguro está en el lookup general
    Map<String, dynamic> getRichData(Map<String, dynamic> source) {
      String id = source['_id'] ?? source['id'];

      // Buscamos en el diccionario maestro usando el ID
      // (Iteramos porque a veces las llaves del lookup son slots "1-2" y no IDs directos)
      var richData = _teamsLookup.values.firstWhere(
        (t) => t['_id'] == id,
        orElse: () => null,
      );

      if (richData != null) {
        return {
          '_id': id,
          'name': richData['name'],
          // Priorizamos el logo del lookup, si falla usamos el del conflicto
          'logo':
              richData['logo'] ??
              richData['img'] ??
              source['logo'] ??
              source['img'],
          'shortName': richData['shortName'] ?? richData['name'],
        };
      }

      // Fallback: Si no estaba en el lookup, usamos lo que traía el conflicto
      return {
        '_id': id,
        'name': source['name'],
        'logo': source['logo'] ?? source['img'],
        'shortName': source['shortName'] ?? source['name'],
      };
    }

    final homeTeamObj = getRichData(homeSource);
    final awayTeamObj = getRichData(awaySource);

    setState(() {
      // 3. Actualizar Lookup (para seguridad futura)
      _teamsLookup[homeTeamObj['_id']] = homeTeamObj;
      _teamsLookup[awayTeamObj['_id']] = awayTeamObj;

      // 4. Agregar al calendario
      (targetJornada['matches'] as List).add({
        'home': homeTeamObj, // Objeto completo con logo recuperado
        'away': awayTeamObj,
        'isRepeat': conflict['match']?['isRepeat'] ?? false,
        'isManualResolve': true,
        'isFixed': false,
      });

      _conflicts.remove(conflict);

      _scheduleDoc!['teamsLookup'] = _teamsLookup;
      _scheduleDoc!['unresolvedConflicts'] = _conflicts;
      _scheduleDoc!['jornadas'] = _jornadas;
    });

    _saveScheduleChangesToDB();
  }

  Future<void> _saveScheduleChangesToDB() async {
    try {
      final response = await _apiService.post(_scheduleDoc!);
      if (response.statusCode == 200 && response.data['ok'] == true) {
        setState(() => _scheduleDoc!['_rev'] = response.data['rev']);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Guardado con éxito"),
            backgroundColor: _success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: _redError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Obtiene los equipos foráneos que pidieron jugar específicamente en esta jornada
  List<Map<String, dynamic>> _getForeignRequestsForJornada(int jornadaNumber) {
    List<Map<String, dynamic>> requestedTeams = [];
    Set<String> processedIds = {}; // Para no contar al mismo foráneo dos veces

    _teamsLookup.forEach((key, teamData) {
      // 1. Obtener el ID real del equipo, ignorando la llave (key) del diccionario
      String realId = (teamData['_id'] ?? teamData['id'] ?? key).toString();

      // Si no hay ID válido o ya lo procesamos, saltamos
      if (realId.isEmpty || realId == "null" || processedIds.contains(realId))
        return;

      // Lo marcamos como procesado
      processedIds.add(realId);

      final constraints = teamData['constraints'];
      if (constraints != null && constraints is Map) {
        // 2. Verificar si es foráneo
        bool isForeign = constraints['isForeign'] == true;

        // 3. Verificar si pidió esta jornada específica
        List<dynamic> availableRounds =
            constraints['foreignAvailableJornadas'] ?? [];

        bool wantsToPlay = availableRounds
            .map((e) => e.toString())
            .contains(jornadaNumber.toString());

        if (isForeign && wantsToPlay) {
          var team = Map<String, dynamic>.from(teamData);
          team['_id'] = realId; // AQUÍ ESTÁ LA MAGIA: Aseguramos el ID real
          requestedTeams.add(team);
        }
      }
    });

    return requestedTeams;
  }

  // Devuelve un mapa: {'big': 'Thunders', 'small': 'Blue', 'color': Color}
  Map<String, dynamic> _formatTeamName(
    String fullName,
    bool isForeign,
    bool isDouble,
  ) {
    List<String> words = fullName.trim().split(' ');
    String bigText = fullName;
    String smallText = "";

    // Palabras clave de color secundario
    const Set<String> secondaryColors = {
      'ORANGE',
      'BLUE',
      'WHITE',
      'GOLD',
      'BLACK',
      'RED',
    };

    if (words.length >= 2) {
      String lastWordUpper = words.last.toUpperCase();

      // Regla 1: Si contiene un color especial al final
      if (secondaryColors.contains(lastWordUpper)) {
        bigText = words.sublist(0, words.length - 1).join(" ");
        smallText = words.last;
      }
      // Regla 2: Si tiene más de 2 palabras y no es color (Ej: "Red Skulls Pro")
      else if (words.length > 2) {
        bigText = words.first;
        smallText = words.sublist(1).join(" ");
      }
      // Regla 3: Si son exactamente 2 palabras normales (Ej: "Bears Cumbres")
      // Decisión de diseño: ¿Dividimos o mantenemos?
      // Tu prompt: "si el nombre tiene más de 2 palabras...".
      // Asumiremos que 2 palabras caben bien, pero si quieres split forzoso:
      // bigText = words.first; smallText = words.last;
    }

    // Definir color del texto
    Color textColor = _textPrimary;
    if (isForeign) {
      textColor = Colors.purple[800]!; // Prioridad 1: Foráneo
    } else if (isDouble) {
      textColor = const Color(
        0xFFD32F2F,
      ); // Prioridad 2: Doble Jornada Local (Rojo)
    }

    return {
      'big': bigText,
      'small': smallText,
      'color': textColor,
      'isForeign': isForeign,
    };
  }

  JornadaAnalysis _analyzeJornada(int index) {
    final jornada = _jornadas[index];
    int number = jornada['number'];
    List matches = jornada['matches'] ?? [];

    // 1. Detectar Activos (Normalizando a String)
    Set<String> activeIds = {};
    Map<String, int> playCount = {};

    for (var m in matches) {
      final hData = _getTeamData(m['home']);
      final aData = _getTeamData(m['away']);

      String hId = hData['_id'].toString();
      String aId = aData['_id'].toString();

      if (hId.isNotEmpty && hData['isReal'] == true) {
        activeIds.add(hId);
        playCount[hId] = (playCount[hId] ?? 0) + 1;
      }
      if (aId.isNotEmpty && aData['isReal'] == true) {
        activeIds.add(aId);
        playCount[aId] = (playCount[aId] ?? 0) + 1;
      }
    }

    // 2. Detectar Dobles
    Set<String> doubles = {};
    playCount.forEach((id, count) {
      if (count > 1) doubles.add(id);
    });

    // 3. Detectar Descansos y Byes (SIN DUPLICADOS)
    List<Map<String, dynamic>> resting = [];
    List<Map<String, dynamic>> byes = [];

    // CORRECCIÓN: Set para rastrear IDs que ya revisamos en este ciclo
    Set<String> processedIds = {};

    _teamsLookup.forEach((key, rawData) {
      // Normalizamos ID
      String tId = (rawData['_id'] ?? rawData['id'] ?? "").toString();

      // A. Validaciones de Seguridad
      if (tId.isEmpty) return; // Si no tiene ID, ignorar
      if (tId == "null") return;

      // B. FILTRO ANTI-DUPLICADOS (La Clave)
      // Si ya procesamos este ID (sea porque vino por slot o por ID directo), saltamos
      if (processedIds.contains(tId)) return;

      // Marcamos como procesado
      processedIds.add(tId);

      // C. Clasificación
      // Si NO está jugando en esta jornada...
      if (!activeIds.contains(tId)) {
        Map<String, dynamic> team = Map<String, dynamic>.from(rawData);

        if (_checkIfRequestedBye(tId, number)) {
          byes.add(team);
        } else {
          resting.add(team);
        }
      }
    });

    // 4. Analizar Foráneos
    List<Map<String, dynamic>> foreignReqs = _getForeignRequestsForJornada(
      number,
    );
    Map<String, int> fCounts = {};
    for (var f in foreignReqs) {
      String fid = f['_id'].toString();
      fCounts[fid] = playCount[fid] ?? 0;
    }

    return JornadaAnalysis(
      jornadaNumber: number,
      matches: matches,
      restingTeams: resting,
      byeRequests: byes,
      foreignRequests: foreignReqs,
      foreignPlayCount: fCounts,
      doubleDutyIds: doubles,
    );
  }

  // Nuevo método para manejar el click en el partido
  Future<void> _handleMatchTap(dynamic match, int index, bool isFixed) async {
    // CASO 1: Si ya está seleccionado, lo deseleccionamos (cancelar)
    if (_selectedMatch == match) {
      setState(() {
        _selectedMatch = null;
        _sourceJornadaIndex = null;
      });
      return;
    }

    // CASO 2: Si es un partido FIJO (Candado)
    if (isFixed) {
      // Mostramos alerta de seguridad
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("¿Mover partido jugado?"),
          content: const Text(
            "Este partido ya tiene resultado o está marcado como oficial. \n\n"
            "Si lo mueves, perderá su estatus de 'Jugado' y el marcador. ¿Deseas continuar?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                "Sí, liberar y mover",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      // Si dijo que NO o cerró, no hacemos nada
      if (confirm != true) return;

      // Si dijo que SÍ, procedemos a seleccionarlo como si fuera normal
    }

    // CASO 3: Selección Normal (o desbloqueada)
    setState(() {
      _selectedMatch = match;
      _sourceJornadaIndex = index;
    });

    // Feedback visual pequeño en móvil
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Partido seleccionado. Ve a otra jornada para moverlo."),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.indigo,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Menú al mantener pulsado: Invertir o Eliminar (Eliminar solo si no está jugado).
  Future<void> _showMatchOptionsDialog(
    dynamic match,
    int jornadaIndex,
    bool isFixed,
  ) async {
    final homeData = _getTeamData(match['home']);
    final awayData = _getTeamData(match['away']);
    final homeName = homeData['name'] as String? ?? 'Local';
    final awayName = awayData['name'] as String? ?? 'Visita';

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Opciones del partido"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$homeName vs $awayName",
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            if (isFixed) ...[
              const SizedBox(height: 8),
              Text(
                "Partido jugado: no se puede eliminar.",
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text("Cancelar"),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'invert'),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text("Invertir local/visita"),
          ),
          if (!isFixed)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red[700],
              ),
              label: Text(
                "Eliminar",
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'invert') {
      await _showSwapHomeAwayConfirm(match, jornadaIndex, isFixed);
    } else if (action == 'delete') {
      await _showDeleteMatchConfirm(match, jornadaIndex);
    }
  }

  Future<void> _showSwapHomeAwayConfirm(
    dynamic match,
    int jornadaIndex,
    bool isFixed,
  ) async {
    final homeData = _getTeamData(match['home']);
    final awayData = _getTeamData(match['away']);
    final homeName = homeData['name'] as String? ?? 'Local';
    final awayName = awayData['name'] as String? ?? 'Visita';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Invertir local y visita"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Se intercambiarán los equipos (y sus slots):",
              style: GoogleFonts.inter(fontSize: 14, color: _textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              "• $homeName → pasará a visita\n• $awayName → pasará a local",
              style: GoogleFonts.inter(fontSize: 13, color: _textPrimary),
            ),
            if (isFixed) ...[
              const SizedBox(height: 12),
              Text(
                "Este partido está marcado como jugado. La inversión no afecta el resultado.",
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Invertir"),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _swapMatchHomeAway(match, jornadaIndex);
    }
  }

  Future<void> _showDeleteMatchConfirm(dynamic match, int jornadaIndex) async {
    final homeData = _getTeamData(match['home']);
    final awayData = _getTeamData(match['away']);
    final homeName = homeData['name'] as String? ?? 'Local';
    final awayName = awayData['name'] as String? ?? 'Visita';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar partido"),
        content: Text(
          "¿Eliminar el partido \"$homeName vs $awayName\" de esta jornada? Esta acción no se puede deshacer.",
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "Eliminar",
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _deleteMatch(match, jornadaIndex);
    }
  }

  void _deleteMatch(dynamic match, int jornadaIndex) {
    final matches = _jornadas[jornadaIndex]['matches'] as List;
    matches.remove(match);
    if (_selectedMatch == match) {
      _selectedMatch = null;
      _sourceJornadaIndex = null;
    }
    setState(() {});
    _saveScheduleChangesToDB();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Partido eliminado. Cambios guardados."),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _swapMatchHomeAway(dynamic match, int jornadaIndex) {
    final homeSlot = match['home'];
    final awaySlot = match['away'];
    match['home'] = awaySlot;
    match['away'] = homeSlot;
    setState(() {});
    _saveScheduleChangesToDB();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Local y visita invertidos. Cambios guardados."),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showBalanceStats() {
    Map<String, Map<String, dynamic>> stats = {};
    _teamsLookup.forEach((key, data) {
      final teamData = _getTeamData(key);
      String id = teamData['_id'];
      if (!stats.containsKey(id)) {
        stats[id] = {
          'name': teamData['name'],
          'games': 0,
          'home': 0,
          'away': 0,
          'doubles': 0,
          'repeats': 0,
          'byes': 0,
          'logo': teamData['logo'],
          'rivals':
              <String, int>{}, // nombre rival -> veces que juega contra él
        };
      }
    });

    for (var jornada in _jornadas) {
      List matches = jornada['matches'] ?? [];
      Map<String, int> teamsInRound = {};
      for (var m in matches) {
        final homeData = _getTeamData(m['home']);
        final awayData = _getTeamData(m['away']);
        String hId = homeData['_id'];
        String aId = awayData['_id'];
        String homeName = homeData['name'] as String;
        String awayName = awayData['name'] as String;

        if (stats.containsKey(hId)) {
          stats[hId]!['games']++;
          stats[hId]!['home']++;
          (stats[hId]!['rivals'] as Map<String, int>)[awayName] =
              ((stats[hId]!['rivals'] as Map<String, int>)[awayName] ?? 0) + 1;
          teamsInRound[hId] = (teamsInRound[hId] ?? 0) + 1;
        }
        if (stats.containsKey(aId)) {
          stats[aId]!['games']++;
          stats[aId]!['away']++;
          (stats[aId]!['rivals'] as Map<String, int>)[homeName] =
              ((stats[aId]!['rivals'] as Map<String, int>)[homeName] ?? 0) + 1;
          teamsInRound[aId] = (teamsInRound[aId] ?? 0) + 1;
        }
      }
      teamsInRound.forEach((id, count) {
        if (count > 1 && stats.containsKey(id)) {
          stats[id]!['doubles']++;
        }
      });
    }

    stats.keys.forEach((teamId) {
      int jornadasJugadas = 0;
      for (var j in _jornadas) {
        if ((j['matches'] as List).any(
          (m) =>
              _getTeamData(m['home'])['_id'] == teamId ||
              _getTeamData(m['away'])['_id'] == teamId,
        )) {
          jornadasJugadas++;
        }
      }
      stats[teamId]!['byes'] = _jornadas.length - jornadasJugadas;
    });

    List<Map<String, dynamic>> statsList = stats.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusCard)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Balance del torneo",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            Divider(color: _borderLight, height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: statsList.length,
                itemBuilder: (ctx, i) {
                  final s = statsList[i];
                  final rivals = s['rivals'] as Map<String, int>? ?? {};
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: _bgScaffold,
                      backgroundImage: s['logo'] != null
                          ? NetworkImage(s['logo'] as String)
                          : null,
                      child: s['logo'] == null
                          ? Icon(
                              Icons.shield_rounded,
                              size: 20,
                              color: _textSecondary,
                            )
                          : null,
                    ),
                    title: Text(
                      s['name'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      "J:${s['games']} | L:${s['home']} | V:${s['away']} | 2x:${s['doubles']} | B:${s['byes']}",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                    trailing: rivals.isEmpty
                        ? null
                        : Icon(
                            Icons.people_outline_rounded,
                            size: 20,
                            color: _textSecondary,
                          ),
                    onTap: () => _showRivalsDialog(
                      teamName: s['name'] as String,
                      rivals: rivals,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRivalsDialog({
    required String teamName,
    required Map<String, int> rivals,
  }) {
    final list = rivals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxSheetHeight = MediaQuery.of(context).size.height * 0.6;
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusCard)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: list.isEmpty ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Rivales de $teamName",
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  "Sin partidos asignados",
                  style: GoogleFonts.inter(fontSize: 14, color: _textSecondary),
                ),
              )
            else ...[
              Divider(color: _borderLight, height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final e = list[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: _bgScaffold,
                        child: Text(
                          "${e.value}",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      title: Text(
                        e.key,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        e.value == 1 ? "1 partido" : "${e.value} partidos",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class JornadaAnalysis {
  final int jornadaNumber;
  final List<dynamic> matches;
  final List<Map<String, dynamic>> restingTeams;
  final List<Map<String, dynamic>> byeRequests; // Equipos que pidieron Bye
  final List<Map<String, dynamic>>
  foreignRequests; // Foráneos que pidieron jugar aquí
  final Map<String, int> foreignPlayCount; // Cuántos juegos llevan (0, 1, 2)
  final Set<String> doubleDutyIds; // IDs de equipos que juegan 2 veces

  JornadaAnalysis({
    required this.jornadaNumber,
    required this.matches,
    required this.restingTeams,
    required this.byeRequests,
    required this.foreignRequests,
    required this.foreignPlayCount,
    required this.doubleDutyIds,
  });
}
