import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:admin_league/services/api_service.dart';
import 'package:admin_league/screens/schedule_management_screen.dart';
import 'package:admin_league/models/user_model.dart';

class DraftCategoryScreen extends StatefulWidget {
  final String categoryName;
  final String tournamentId; // <--- AGREGAR ESTO

  // Recibimos los equipos ya organizados por grupo
  // Ej: {'1': [TeamA, TeamB], '2': [TeamC]}
  final Map<String, List<Map<String, dynamic>>> enrolledTeamsByGroup;

  // La respuesta compleja del backend con 'stats', 'jornadas', etc.
  final Map<String, dynamic> draftData;
  final Map<String, dynamic>? initialAssignments;
  final String? existingDraftId;
  final UserModel user;

  const DraftCategoryScreen({
    super.key,
    required this.categoryName,
    required this.tournamentId,
    required this.enrolledTeamsByGroup,
    required this.draftData,
    required this.user,
    this.initialAssignments,
    this.existingDraftId,
  });

  @override
  State<DraftCategoryScreen> createState() => _DraftCategoryScreenState();
}

class _DraftCategoryScreenState extends State<DraftCategoryScreen>
    with TickerProviderStateMixin {
  // ESTRUCTURA MAESTRA DE ASIGNACIÓN
  // Map<GroupId, Map<SlotId, TeamObject>>
  final ApiService _apiService = ApiService();
  String? _savedDraftId;
  bool _hasUnsavedChanges = false;

  final Map<String, Map<int, Map<String, dynamic>?>> _assignments = {};

  late TabController _tabController;
  List<String> _groupIds = [];
  String _currentGroupId = '';

  // Selección temporal
  Map<String, dynamic>? _selectedTeam;

  @override
  void initState() {
    super.initState();

    // SEGURIDAD: Capa de protección interna
    if (!widget.user.canManageSchedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Acceso restringido: Solo Master o Logística"),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
      return;
    }

    _initializeData();

    if (widget.existingDraftId != null) {
      _savedDraftId = widget.existingDraftId;
    }
    // NUEVO: Si hay datos guardados, restaurarlos
    if (widget.initialAssignments != null) {
      _restoreAssignments();
      _hasUnsavedChanges = true;
    }
  }

  void _initializeData() {
    // --- PASO 1: Obtener IDs de grupos de forma segura ---
    // Intentamos leer 'stats', pero si es null (viniendo de un calendario oficial), usamos un fallback
    Map<String, dynamic>? stats = widget.draftData['stats'];

    if (stats != null) {
      _groupIds = stats.keys.toList()..sort();
    } else {
      // FALLBACK: Si no hay stats, usamos las llaves de los equipos inscritos que nos pasaron
      _groupIds = widget.enrolledTeamsByGroup.keys.toList()..sort();
    }

    // Validación extra por seguridad
    if (_groupIds.isEmpty) {
      _groupIds = ['1'];
    }

    _currentGroupId = _groupIds[0];

    // --- PASO 2: Inicializar el TabController ---
    _tabController = TabController(length: _groupIds.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentGroupId = _groupIds[_tabController.index];
          _selectedTeam = null;
        });
      }
    });

    // --- PASO 3: Preparar los slots vacíos ---
    for (String gid in _groupIds) {
      _assignments[gid] = {};

      int numSlots;

      // Opción A: Tenemos la data estadística del backend
      if (stats != null && stats.containsKey(gid)) {
        Map<String, dynamic> groupStats = stats[gid];
        numSlots = groupStats.length;
      }
      // Opción B (Fallback): Calculamos slots basados en la cantidad de equipos
      else {
        // Obtenemos cuántos equipos hay en este grupo
        int teamCount = widget.enrolledTeamsByGroup[gid]?.length ?? 0;

        // Regla de negocio: Si es impar, sumamos 1 para que sea par (o mínimo 4)
        if (teamCount < 4) {
          numSlots = 4;
        } else if (teamCount % 2 != 0) {
          numSlots = teamCount + 1;
        } else {
          numSlots = teamCount;
        }
      }

      // Crear los huecos vacíos
      for (int i = 1; i <= numSlots; i++) {
        _assignments[gid]![i] = null;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- HELPERS DE DATOS ---

  void _restoreAssignments() {
    // 1. Mapa de búsqueda rápida de equipos ACTUALES (Vivos)
    Map<String, Map<String, dynamic>> teamLookup = {};
    widget.enrolledTeamsByGroup.forEach((groupId, teams) {
      for (var team in teams) {
        String tId = team['id'] ?? team['_id'];
        teamLookup[tId] = team;
      }
    });

    if (widget.initialAssignments == null) return;

    // 2. Intentar restaurar solo lo válido
    widget.initialAssignments!.forEach((slotKey, teamId) {
      try {
        // A. Parsear la llave del slot (Ej: "1-1" o "1")
        String groupId;
        int slotId;

        if (slotKey.contains('-')) {
          var parts = slotKey.split('-');
          groupId = parts[0];
          slotId = int.parse(parts[1]);
        } else {
          // Si guardaste "1", "2" asumimos Grupo 1 (o el primero disponible)
          groupId = _groupIds.isNotEmpty ? _groupIds.first : '1';
          slotId = int.parse(slotKey);
        }

        // B. VALIDACIONES DE SEGURIDAD (CRÍTICO PARA ACTUALIZACIONES)

        // 1. ¿El grupo existe en la NUEVA estructura?
        if (!_assignments.containsKey(groupId)) return;

        // 2. ¿El slot existe en la NUEVA estructura?
        if (!_assignments[groupId]!.containsKey(slotId)) return;

        // 3. ¿El equipo sigue existiendo en el torneo?
        var teamObject = teamLookup[teamId];
        if (teamObject == null)
          return; // El equipo fue eliminado, ignorar asignación

        // C. Asignar
        _assignments[groupId]![slotId] = teamObject;
      } catch (e) {
        print("Asignación obsoleta descartada: $slotKey -> $teamId");
      }
    });

    // Al final, setState para reflejar los cambios en la UI
    setState(() {});
  }

  // Obtiene el objeto completo del equipo dado un target (ID o Mapa)
  Map<String, dynamic>? _resolveTeamData(dynamic targetObj) {
    if (targetObj == null) return null;
    try {
      String group;
      int slot;
      if (targetObj is Map) {
        group = targetObj['group'].toString();
        slot = int.parse(targetObj['slot'].toString());
      } else {
        group = _currentGroupId; // Fallback para compatibilidad
        slot = int.parse(targetObj.toString());
      }
      return _assignments[group]?[slot];
    } catch (e) {
      return null;
    }
  }

  // Genera un ID único para contar repeticiones en el calendario
  String _getUniqueSlotId(dynamic targetObj) {
    if (targetObj == null) return "null";
    if (targetObj is Map) {
      return "${targetObj['group']}-${targetObj['slot']}";
    }
    return targetObj.toString();
  }

  // Genera la etiqueta visual del slot (Ej: "1" o "A-1")
  String _getSlotLabel(dynamic targetObj) {
    if (targetObj == null) return "?";
    String group;
    int slot;

    if (targetObj is Map) {
      group = targetObj['group'].toString();
      slot = int.parse(targetObj['slot'].toString());
    } else {
      // Si viene como int simple
      return targetObj.toString();
    }

    if (_groupIds.length == 1) return "$slot";
    return "$group-$slot";
  }

  void _autoFillSlots() {
    setState(() {
      _hasUnsavedChanges = true;
      // 1. Identificar equipos que AÚN no tienen slot
      List<Map<String, dynamic>> unassignedTeams = [];

      widget.enrolledTeamsByGroup.forEach((gId, teams) {
        for (var team in teams) {
          bool isAssigned = false;
          // Buscar en todos los grupos si ya está puesto
          for (var groupSlots in _assignments.values) {
            if (groupSlots.values.any((t) => t?['_id'] == team['_id'])) {
              isAssigned = true;
              break;
            }
          }
          if (!isAssigned) unassignedTeams.add(team);
        }
      });

      // 2. Barajarlos para que sea aleatorio
      unassignedTeams.shuffle();

      // 3. Llenar los huecos vacíos
      for (var groupId in _groupIds) {
        var slots = _assignments[groupId]!;
        for (var slotId in slots.keys) {
          if (slots[slotId] == null && unassignedTeams.isNotEmpty) {
            // Asignar y remover de la lista
            _assignments[groupId]![slotId] = unassignedTeams.removeAt(0);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isSingleGroup = _groupIds.length == 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sorteo ${widget.categoryName}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: "Auto-completar vacíos",
            onPressed: _autoFillSlots, // <--- Llamada
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: "Verificar Balance",
            onPressed: _showFairnessDialog,
          ),
          const SizedBox(width: 8),
        ],
        // Ocultamos Tabs si es solo 1 grupo
        bottom: isSingleGroup
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.black,
                indicatorColor: Colors.black,
                tabs: _groupIds.map((gid) => Tab(text: "GRUPO $gid")).toList(),
              ),
      ),
      body: Column(
        children: [
          // 1. Selector de Equipos (Estilo Trading Card)
          _buildTeamSelector(),

          // 2. Área Principal: Slots (Izq) + Calendario (Der)
          Expanded(
            child: Row(
              children: [
                // Panel de Slots (Varía según el Tab seleccionado)
                SizedBox(width: 140, child: _buildSlotsList(_currentGroupId)),

                // Línea divisoria con efecto "hundido"
                Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withAlpha(15),
                        blurRadius: 0,
                        offset: const Offset(1.2, 0), // Sombra derecha sutil
                      ),
                      BoxShadow(
                        color: Colors.grey.withAlpha(20),
                        blurRadius: 0,
                        offset: const Offset(-1.2, 0), // Sombra izquierda sutil
                      ),
                    ],
                  ),
                ),

                // Calendario Unificado (Compacto Texto)
                Expanded(child: _buildUnifiedCalendar()),
              ],
            ),
          ),

          // 3. Botón Guardar
          _buildBottomAction(),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET 1: SELECTOR DE EQUIPOS (TRADING CARD)
  // ===========================================================================
  Widget _buildTeamSelector() {
    List<Map<String, dynamic>> teamsToShow =
        widget.enrolledTeamsByGroup[_currentGroupId] ?? [];

    int totalTeams = teamsToShow.length;
    int assignedCount = 0;
    if (_assignments[_currentGroupId] != null) {
      assignedCount = _assignments[_currentGroupId]!.values
          .where((t) => t != null)
          .length;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 700;
        // AJUSTE: Aumentamos altura en móvil de 140 a 155 para evitar el overflow
        double containerHeight = isDesktop ? 170 : 155;

        return Container(
          height: containerHeight,
          width: double.infinity,
          color: const Color(0xFFE0E5EC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.black12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 16,
                          color: Colors.indigo[900],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "EQUIPOS",
                          style: GoogleFonts.oswald(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "$assignedCount / $totalTeams",
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: assignedCount == totalTeams
                            ? Colors.green[700]
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              // RIEL DE TICKETS
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.1],
                      colors: [Colors.black.withAlpha(5), Colors.transparent],
                    ),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    itemCount: teamsToShow.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        // Pasamos el constraints para saber el ancho disponible si fuera necesario
                        child: _buildTicketCard(teamsToShow[index], index),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> team, int index) {
    bool isAssigned = _assignments[_currentGroupId]!.values.any(
      (t) => t?['_id'] == team['_id'],
    );
    bool isSelected = _selectedTeam?['_id'] == team['_id'];
    String? imgUrl = team['img'] ?? team['logo'];

    List<String> nameParts = _splitTeamName(team['name']);
    String firstWord = nameParts[0];
    String restOfName = nameParts[1];

    double cardWidth = 75;
    // FIJAMOS LA ALTURA TOTAL para asegurar uniformidad en el "riel"
    double cardHeight = 105;

    Color cardColor = isAssigned
        ? const Color(0xFFEEEEEE)
        : (isSelected ? const Color(0xFFFFF8E1) : Colors.white);

    Color borderColor = isSelected ? Colors.orange : Colors.grey[300]!;
    Color textColor = isAssigned ? Colors.grey : Colors.black87;

    return GestureDetector(
      onTap: isAssigned ? null : () => setState(() => _selectedTeam = team),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: cardWidth,
        height: cardHeight, // Altura fija para alineación perfecta
        margin: EdgeInsets.only(top: isSelected ? 0 : 0),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          border: Border(
            left: BorderSide(color: borderColor, width: 1),
            right: BorderSide(color: borderColor, width: 1),
            bottom: BorderSide(color: borderColor, width: isSelected ? 3 : 1),
            top: BorderSide.none,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(5),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. FOLIO (Pegado arriba)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 3,
              ), // Padding reducido
              color: isSelected ? Colors.orange : Colors.grey[100],
              child: Center(
                child: Text(
                  "${index + 1}",
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : Colors.grey[500],
                  ),
                ),
              ),
            ),

            // 2. CONTENEDOR DE NOMBRE CON ALTURA FIJA (CLAVE PARA ALINEACIÓN)
            // Esto asegura que el logo siempre empiece en el mismo pixel vertical
            Container(
              height: 32, // Espacio fijo suficiente para 2 líneas
              padding: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment
                  .center, // Centra verticalmente el texto (1 o 2 lineas)
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    firstWord.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.oswald(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                  if (restOfName.isNotEmpty)
                    Text(
                      restOfName,
                      textAlign: TextAlign.center,
                      maxLines:
                          1, // Forzamos 1 linea para el resto (o 2 si prefieres)
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            ),

            // 3. DIVISIÓN COMPACTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: List.generate(
                  6, // Menos guiones
                  (index) => Expanded(
                    child: Container(
                      height: 1,
                      color: index % 2 == 0
                          ? Colors.grey[300]
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(), // Empuja el logo al fondo del contenedor
            // 4. LOGO ALINEADO AL FONDO
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: 36, // Compactado
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: (imgUrl != null && imgUrl.isNotEmpty)
                      ? Image.network(
                          imgUrl,
                          fit: BoxFit.cover,
                          color: isAssigned ? Colors.white.withAlpha(60) : null,
                          colorBlendMode: isAssigned
                              ? BlendMode.hardLight
                              : null,
                        )
                      : Icon(Icons.shield, size: 14, color: Colors.grey[300]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER PARA DIVIDIR NOMBRES ---
  List<String> _splitTeamName(String fullName) {
    if (fullName.isEmpty) return ["?", ""];

    List<String> parts = fullName.trim().split(" ");
    if (parts.length == 1) {
      return [parts[0], ""];
    } else {
      String first = parts[0];
      // Unir el resto de nuevo
      String rest = parts.sublist(1).join(" ");
      return [first, rest];
    }
  }

  // ===========================================================================
  // WIDGET 2: LISTA DE SLOTS (MINIMALISTA)
  // ===========================================================================
  Widget _buildSlotsList(String groupId) {
    var groupSlots = _assignments[groupId]!;
    var sortedKeys = groupSlots.keys.toList()..sort();
    bool isSingleGroup = _groupIds.length == 1;

    return Container(
      color: const Color(0xFFE0E5EC),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            width: double.infinity,
            decoration: const BoxDecoration(color: Color(0xFFE0E5EC)),
            child: Text(
              "SLOTS",
              textAlign: TextAlign.center,
              style: GoogleFonts.oswald(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 1.5,
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                int slotId = sortedKeys[index];
                var assignedTeam = groupSlots[slotId];
                bool isActiveSelection = _selectedTeam != null;
                String slotLabel = isSingleGroup
                    ? "$slotId"
                    : "$groupId-$slotId";

                // LÓGICA DE ESTILO "SUMIDO"
                // Si está vacío y hay selección activa -> Gris "Socket"
                // Si está lleno -> Blanco normal
                // Si está vacío normal -> Blanco normal o gris muy muy claro

                Color slotBgColor;
                BoxBorder? slotBorder;
                List<BoxShadow>? slotShadows;

                if (assignedTeam != null) {
                  // CASO: LLENO (Tarjeta normal)
                  slotBgColor = Colors.white;
                  slotBorder = Border.all(color: Colors.black12);
                  slotShadows = [
                    BoxShadow(
                      color: Colors.black.withAlpha(3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ];
                } else if (isActiveSelection) {
                  // CASO: SUMIDO / RECEPTÁCULO (Cuando traes un ticket seleccionado)
                  slotBgColor = const Color.fromARGB(
                    255,
                    219,
                    225,
                    232,
                  ); // Gris 300 aprox
                  slotBorder = Border.all(
                    color: const Color.fromARGB(255, 199, 204, 210),
                    width: 2,
                  ); // Borde más marcado para definir el hueco
                  slotShadows =
                      null; // SIN SOMBRA EXTERNA para que se vea plano/hundo
                } else {
                  // CASO: VACÍO NORMAL
                  slotBgColor = Colors.white;
                  slotBorder = Border.all(color: Colors.grey[200]!);
                  slotShadows = null;
                }

                return GestureDetector(
                  onTap: () {
                    if (isActiveSelection && assignedTeam == null) {
                      setState(() {
                        _assignments[groupId]![slotId] = _selectedTeam;
                        _selectedTeam = null;
                        _hasUnsavedChanges = true;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 65,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: slotBgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: slotBorder,
                      boxShadow: slotShadows,
                    ),
                    child: Stack(
                      children: [
                        // Contenido
                        if (assignedTeam != null)
                          _buildFilledSlotContent(assignedTeam)
                        else
                          _buildEmptySlotContent(isActiveSelection),

                        // Etiqueta del Número
                        Positioned(
                          top: 6,
                          left: 10,
                          child: Text(
                            slotLabel,
                            style: GoogleFonts.oswald(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              // Si está sumido (activo), oscurecemos un poco el número para que parezca grabado
                              color: (assignedTeam == null && isActiveSelection)
                                  ? Colors.grey[500]
                                  : Colors.grey[500],
                            ),
                          ),
                        ),

                        // Botón Eliminar
                        if (assignedTeam != null)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => setState(() {
                                _assignments[groupId]![slotId] = null;
                                _hasUnsavedChanges = true;
                              }),
                              child: Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- CONTENIDO VACÍO AJUSTADO ---
  Widget _buildEmptySlotContent(bool isActive) {
    return Center(
      child: isActive
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "INSERTAR AQUÍ",
                  style: GoogleFonts.oswald(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 138, 142, 146),
                    letterSpacing: 1,
                  ),
                ),
              ],
            )
          : Text(
              "VACÍO",
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: const Color.fromARGB(255, 198, 201, 205),
              ),
            ),
    );
  }

  Widget _buildFilledSlotContent(Map<String, dynamic> team) {
    String? imgUrl = team['img'] ?? team['logo'];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: ClipOval(
              child: (imgUrl != null && imgUrl.isNotEmpty)
                  ? Image.network(imgUrl, fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey[100],
                      child: const Icon(
                        Icons.shield,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              team['name'],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET 3: CALENDARIO UNIFICADO (COMPACTO - SOLO TEXTO)
  // ===========================================================================
  Widget _buildUnifiedCalendar() {
    // 1. OBTENCIÓN Y NORMALIZACIÓN DE DATOS ROBUSTOS
    // A veces el backend manda 'jornadas' como Map o List, aquí unificamos.
    dynamic rawJornadas =
        widget.draftData['jornadas'] ?? widget.draftData['matches'];
    List<dynamic> jornadas = [];

    if (rawJornadas is List) {
      jornadas = rawJornadas;
    } else if (rawJornadas is Map) {
      // Si viene como Mapa { "1": [...], "2": [...] }, lo ordenamos numéricamente
      var sortedKeys = rawJornadas.keys.toList()
        ..sort((a, b) {
          int? intA = int.tryParse(a.toString());
          int? intB = int.tryParse(b.toString());
          if (intA != null && intB != null) return intA.compareTo(intB);
          return a.toString().compareTo(b.toString());
        });
      for (var key in sortedKeys) {
        jornadas.add(rawJornadas[key]);
      }
    }

    return Container(
      color: const Color(0xFFE0E5EC),
      child: Column(
        children: [
          // HEADER PRINCIPAL
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            width: double.infinity,
            decoration: const BoxDecoration(color: Color(0xFFE0E5EC)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 16,
                  color: Colors.indigo[900],
                ),
                const SizedBox(width: 8),
                Text(
                  "CALENDARIO",
                  style: GoogleFonts.oswald(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: jornadas.length,
              itemBuilder: (context, i) {
                // 2. EXTRACCIÓN SEGURA DE PARTIDOS POR JORNADA
                // A veces la jornada es una lista directa, a veces un objeto { matches: [] }
                List games = [];
                var jornadaData = jornadas[i];

                if (jornadaData is List) {
                  games = jornadaData;
                } else if (jornadaData is Map &&
                    jornadaData.containsKey('matches')) {
                  games = jornadaData['matches'] ?? [];
                } else if (jornadaData is Map) {
                  // Intento de fallback si viene como objeto numerado
                  games = jornadaData.values.toList();
                }

                // Procesamiento de datos (Contadores y Dobles jornadas)
                List<dynamic> matches = [];
                List<dynamic> restingGames = [];
                Map<String, int> teamPlayCount = {};
                int roundNumber = i + 1;

                void incrementCount(dynamic target) {
                  // Usamos tu helper existente
                  String id = _getUniqueSlotId(target);
                  teamPlayCount[id] = (teamPlayCount[id] ?? 0) + 1;
                }

                for (var g in games) {
                  // Validación básica para evitar nulls
                  if (g == null) continue;

                  if (g['rest'] != null) {
                    restingGames.add(g);
                  } else {
                    matches.add(g);
                    incrementCount(g['home']);
                    incrementCount(g['away']);
                  }
                }

                List<String> doubleDutyIds = [];
                teamPlayCount.forEach((id, count) {
                  if (count > 1) doubleDutyIds.add(id);
                });

                return Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TITULO DE LA RONDA
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              "RONDA $roundNumber",
                              style: GoogleFonts.oswald(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[900],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "(Fecha por definir)",
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ENCABEZADOS DE COLUMNA (Solo Desktop)
                      if (matches.isNotEmpty)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 600)
                              return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "LOCAL",
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF64686B),
                                    ),
                                  ),
                                  Text(
                                    "VISITA",
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF64686B),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // LISTA DE PARTIDOS
                      Column(
                        children: matches.map((g) {
                          return _buildMatchRowResponsive(
                            g,
                            doubleDutyIds,
                            roundNumber,
                          );
                        }).toList(),
                      ),

                      // FOOTERS (Descansos y Dobles)
                      if (restingGames.isNotEmpty)
                        _buildFooterList(
                          restingGames,
                          "Descansa:",
                          Colors.grey,
                        ),

                      if (doubleDutyIds.isNotEmpty)
                        _buildFooterList(
                          doubleDutyIds,
                          "Doble Jornada:",
                          Colors.red,
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

  Widget _buildMatchRowResponsive(
    Map<String, dynamic> game,
    List<String> doubleDutyIds,
    int roundNumber, // <--- Recibimos la ronda actual
  ) {
    bool isInter = game['type'] == 'inter_group';
    String homeId = _getUniqueSlotId(game['home']);
    String awayId = _getUniqueSlotId(game['away']);
    bool homeIsDouble = doubleDutyIds.contains(homeId);
    bool awayIsDouble = doubleDutyIds.contains(awayId);
    bool isFixed = game['isFixed'] == true;

    var homeTeam = _resolveTeamData(game['home']);
    var awayTeam = _resolveTeamData(game['away']);

    String homeName =
        homeTeam?['name'] ?? "Slot ${_getSlotLabel(game['home'])}";
    String awayName =
        awayTeam?['name'] ?? "Slot ${_getSlotLabel(game['away'])}";
    String? homeLogo = homeTeam?['img'] ?? homeTeam?['logo'];
    String? awayLogo = awayTeam?['img'] ?? awayTeam?['logo'];

    // --- EVALUACIÓN DE CONFLICTOS ---
    bool isIncompatibleDays = _areTeamsIncompatible(homeTeam, awayTeam);
    bool homeHasConflict = _hasRoundConflict(homeTeam, roundNumber);
    bool awayHasConflict = _hasRoundConflict(awayTeam, roundNumber);
    bool hasAnyConflict =
        isIncompatibleDays || homeHasConflict || awayHasConflict;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 700) {
          return _buildDesktopRow(
            homeName,
            awayName,
            homeLogo,
            awayLogo,
            homeIsDouble,
            awayIsDouble,
            isInter,
            hasAnyConflict,
            isIncompatibleDays,
            homeHasConflict,
            awayHasConflict,
            isFixed,
          );
        } else {
          return _buildMobileRow(
            homeName,
            awayName,
            homeLogo,
            awayLogo,
            homeIsDouble,
            awayIsDouble,
            isInter,
            hasAnyConflict,
            isIncompatibleDays,
            homeHasConflict,
            awayHasConflict,
            isFixed,
          );
        }
      },
    );
  }

  Widget _buildDesktopRow(
    String homeName,
    String awayName,
    String? homeLogo,
    String? awayLogo,
    bool homeIsDouble,
    bool awayIsDouble,
    bool isInter,
    bool hasAnyConflict,
    bool isIncompatibleDays,
    bool homeHasConflict,
    bool awayHasConflict,
    bool isFixed,
  ) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hasAnyConflict ? Colors.red[50] : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasAnyConflict
              ? Colors.redAccent
              : (isInter ? Colors.orange.withAlpha(30) : Colors.grey[200]!),
          width: hasAnyConflict ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // LOCAL
          Expanded(
            child: Row(
              children: [
                _buildMiniAvatar(homeLogo, isDouble: homeIsDouble),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    homeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Icono si el local tiene conflicto de Jornada (Bye)
                if (homeHasConflict)
                  const Icon(Icons.hotel_class, color: Colors.red, size: 16),
              ],
            ),
          ),

          // CENTRO: Separador o Alerta de Incompatibilidad de Horarios
          if (isIncompatibleDays)
            Tooltip(
              message: "No tienen días en común para jugar",
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: const Icon(
                  Icons.calendar_month,
                  color: Colors.red,
                  size: 20,
                ),
              ),
            )
          else
            Container(
              width: 1,
              height: 24,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 24),
            ),

          // VISITA
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Icono si la visita tiene conflicto de Jornada (Bye)
                if (awayHasConflict)
                  const Icon(Icons.hotel_class, color: Colors.red, size: 16),
                Expanded(
                  child: Text(
                    awayName,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildMiniAvatar(awayLogo, isDouble: awayIsDouble),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRow(
    String homeName,
    String awayName,
    String? homeLogo,
    String? awayLogo,
    bool homeIsDouble,
    bool awayIsDouble,
    bool isInter,
    bool hasAnyConflict,
    bool isIncompatibleDays,
    bool homeHasConflict,
    bool awayHasConflict,
    bool isFixed,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: hasAnyConflict ? Colors.red[50] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasAnyConflict
              ? Colors.redAccent
              : (isInter ? Colors.orange.withAlpha(30) : Colors.grey[200]!),
          width: hasAnyConflict ? 1.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 24,
                    color: Colors.blue[100],
                    margin: const EdgeInsets.only(right: 8),
                  ),
                  _buildMiniAvatar(homeLogo, isDouble: homeIsDouble),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSplitNameMobile(
                      homeName,
                      isDouble: homeIsDouble,
                    ),
                  ),
                  if (homeHasConflict)
                    const Icon(Icons.hotel_class, color: Colors.red, size: 16),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  color: const Color.fromARGB(255, 209, 210, 218),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 24,
                    color: Colors.red[100],
                    margin: const EdgeInsets.only(right: 8),
                  ),
                  _buildMiniAvatar(awayLogo, isDouble: awayIsDouble),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSplitNameMobile(
                      awayName,
                      isDouble: awayIsDouble,
                    ),
                  ),
                  if (awayHasConflict)
                    const Icon(Icons.hotel_class, color: Colors.red, size: 16),
                ],
              ),
            ],
          ),

          if (isIncompatibleDays)
            Positioned(
              right: 20,
              top: 15,
              child: const Icon(
                Icons.calendar_month,
                color: Colors.red,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  // Helper para Split en Móvil
  Widget _buildSplitNameMobile(String fullName, {required bool isDouble}) {
    if (fullName.startsWith("Slot")) {
      return Text(
        fullName,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Colors.grey[400],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    List<String> parts = _splitTeamName(fullName);
    Color textColor = isDouble ? Colors.red[700]! : Colors.black87;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          parts[0].toUpperCase(),
          style: GoogleFonts.oswald(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        if (parts[1].isNotEmpty) ...[
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              parts[1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Helper Avatar Común
  Widget _buildMiniAvatar(String? imgUrl, {bool isDouble = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ClipOval(
            child: (imgUrl != null && imgUrl.isNotEmpty)
                ? Image.network(imgUrl, fit: BoxFit.cover)
                : Icon(Icons.shield, size: 16, color: Colors.grey[300]),
          ),
        ),
        if (isDouble)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 10,
                color: Colors.red,
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // C. HELPERS VISUALES
  // ===========================================================================

  // --- FOOTER LIST (PARA DESCANSOS Y DOBLES) ---
  Widget _buildFooterList(
    List<dynamic> items,
    String title,
    MaterialColor colorBase,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 6, left: 4, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorBase[50]!.withAlpha(50),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorBase[800],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: items.map((item) {
                dynamic target = (item is Map) ? item['rest'] : item;
                dynamic targetObj;
                if (target is String && target.contains('-')) {
                  var parts = target.split('-');
                  targetObj = {'group': parts[0], 'slot': int.parse(parts[1])};
                } else if (target is String) {
                  targetObj = int.parse(target);
                } else {
                  targetObj = target;
                }

                var team = _resolveTeamData(targetObj);
                String name =
                    team?['name'] ?? "Slot ${_getSlotLabel(targetObj)}";

                return Text(
                  name + (items.last == item ? "" : ","),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorBase[900],
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ACCIONES Y DIALOGOS
  // ===========================================================================
  Widget _buildBottomAction() {
    // Validar si está completo
    int totalSlots = 0;
    int filledSlots = 0;
    for (var groupSlots in _assignments.values) {
      totalSlots += groupSlots.length;
      filledSlots += groupSlots.values.where((t) => t != null).length;
    }
    bool isComplete = totalSlots > 0 && totalSlots == filledSlots;

    // Decidir acción
    String label;
    VoidCallback? action;
    Color btnColor;

    if (!isComplete) {
      label = "ASIGNA TODOS LOS SLOTS ($filledSlots/$totalSlots)";
      action = null;
      btnColor = Colors.grey;
    } else if (_savedDraftId == null || _hasUnsavedChanges) {
      // Paso 1: Guardar
      label = _savedDraftId == null ? "GUARDAR BORRADOR" : "GUARDAR CAMBIOS";
      action = _processFinalSave;
      btnColor = _hasUnsavedChanges ? Colors.orange[800]! : Colors.black87;
    } else {
      // Paso 2: Generar Oficial
      label = "GENERAR CALENDARIO OFICIAL";
      action = _generateOfficialSchedule;
      btnColor = Colors.indigo; // Color distintivo
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: action,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: btnColor,
            disabledBackgroundColor: Colors.grey[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            // Usamos Row para agregar icono si es el paso final
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono condicional
              if (_savedDraftId != null && !_hasUnsavedChanges)
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              if (_hasUnsavedChanges)
                const Icon(Icons.save_as, color: Colors.white, size: 18),
              if (_savedDraftId != null || _hasUnsavedChanges)
                const SizedBox(width: 8),

              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DIÁLOGO DE ANÁLISIS DE EQUIDAD (MEJORADO)
  // ===========================================================================
  void _showFairnessDialog() {
    Map<String, dynamic> allStats = widget.draftData['stats'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFE0E5EC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: 600,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: DefaultTabController(
            length: allStats.keys.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header del Modal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Analisis de Equidad",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Tabs de Grupos
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TabBar(
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey[600],
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(5),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: allStats.keys
                        .map((k) => Tab(text: "GRUPO $k"))
                        .toList(),
                  ),
                ),

                const SizedBox(height: 10),

                // Lista de Estadísticas
                Expanded(
                  child: TabBarView(
                    children: allStats.keys.map((gid) {
                      return _buildStatsListForGroup(gid, allStats[gid]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsListForGroup(
    String groupId,
    Map<String, dynamic> groupStats,
  ) {
    List<dynamic> list = groupStats.values.toList();
    // Ordenar por Slot ID numéricamente
    list.sort(
      (a, b) => int.parse(
        a['slot'].toString(),
      ).compareTo(int.parse(b['slot'].toString())),
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      itemCount: list.length,
      itemBuilder: (context, index) {
        var s = list[index];
        int slotId = int.parse(s['slot'].toString());
        int repeats = int.parse(s['repeats'].toString());
        int totalGames = int.parse(s['gamesPlayed'].toString());

        // 1. Resolver Datos del Equipo Asignado
        var assignedTeam = _assignments[groupId]?[slotId];
        bool isAssigned = assignedTeam != null;

        String displayName = isAssigned
            ? assignedTeam['name']
            : "Slot $slotId (Vacío)";
        String? imgUrl = isAssigned
            ? (assignedTeam['img'] ?? assignedTeam['logo'])
            : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),

            // AVATAR IZQUIERDO
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAssigned ? Colors.white : Colors.grey[100],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: ClipOval(
                child: (imgUrl != null && imgUrl.isNotEmpty)
                    ? Image.network(imgUrl, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          "$slotId",
                          style: GoogleFonts.oswald(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isAssigned ? Colors.black : Colors.grey[500],
                          ),
                        ),
                      ),
              ),
            ),

            // NOMBRE
            title: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isAssigned ? FontWeight.bold : FontWeight.normal,
                color: isAssigned ? Colors.black87 : Colors.grey[500],
              ),
            ),

            // SUBTITULO (Desglose Local/Visita)
            subtitle: Row(
              children: [
                _buildSimpleStat("L", "${s['home']}"),
                const SizedBox(width: 8),
                _buildSimpleStat("V", "${s['away']}"),
              ],
            ),

            // INDICADORES DERECHOS (TOTAL + REPETIDOS)
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. SIEMPRE VISIBLE: TOTAL DE JUEGOS (VERDE)
                _buildInfoBox("$totalGames", "JUEGOS", Colors.green),

                // 2. CONDICIONAL: REPETIDOS (ROJO)
                if (repeats > 0) ...[
                  const SizedBox(width: 8),
                  _buildInfoBox("$repeats", "REPETIDOS", Colors.red),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // --- HELPER PARA CAJITAS DE INFO (VERDE/ROJO) ---
  Widget _buildInfoBox(String value, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.oswald(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color[700],
              height: 1.0,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 7,
              fontWeight: FontWeight.bold,
              color: color[400],
            ),
          ),
        ],
      ),
    );
  }

  // Helper simple para texto L: 2, V: 3
  Widget _buildSimpleStat(String label, String value) {
    return Row(
      children: [
        Text(
          "$label: ",
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.grey[500],
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Pequeño helper para texto simple L: 2, V: 2
  Widget _buildStatBadge(String label, String value, MaterialColor color) {
    return Row(
      children: [
        Text(
          "$label: ",
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.grey[500],
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPERS DE RESTRICCIONES (CONSTRAINTS)
  // ===========================================================================

  // 1. Incompatibilidad de Días (Cruza timeRestrictions de ambos equipos)
  bool _areTeamsIncompatible(
    Map<String, dynamic>? team1,
    Map<String, dynamic>? team2,
  ) {
    if (team1 == null || team2 == null) return false;

    // Ajusta esto a los días reales en los que opera tu liga
    const leagueDays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];

    List<String> getAvailableDays(Map<String, dynamic> team) {
      var constraints = team['constraints'] ?? {};
      var restrictions =
          constraints['timeRestrictions'] as List<dynamic>? ?? [];

      List<String> blockedDays = [];
      for (var r in restrictions) {
        // Según tu modal: si ranges no existe o está vacío, TODO EL DÍA está bloqueado
        if (r['ranges'] == null || (r['ranges'] as List).isEmpty) {
          blockedDays.add(r['day'].toString());
        }
      }

      // Días disponibles = Días de liga MENOS días bloqueados
      return leagueDays.where((d) => !blockedDays.contains(d)).toList();
    }

    var available1 = getAvailableDays(team1);
    var available2 = getAvailableDays(team2);

    // Si la intersección de días disponibles está vacía, no tienen cuándo jugar
    return !available1.any((day) => available2.contains(day));
  }

  // 2. Conflicto de Jornada (Solicitud de Bye o Restricción de Foráneo)
  bool _hasRoundConflict(Map<String, dynamic>? team, int roundNumber) {
    if (team == null) return false;
    var constraints = team['constraints'] ?? {};

    // A) ¿Solicitó Bye en esta ronda?
    var byeJornadas = constraints['byeJornadas'] as List<dynamic>? ?? [];
    if (byeJornadas.contains(roundNumber)) return true;

    // B) Si es foráneo, ¿viaja en esta ronda?
    bool isForeign = constraints['isForeign'] ?? false;
    if (isForeign) {
      var availableJornadas =
          constraints['foreignAvailableJornadas'] as List<dynamic>? ?? [];
      if (!availableJornadas.contains(roundNumber)) return true;
    }

    return false;
  }

  // ---------------------------------------------------------
  // LÓGICA DE GUARDADO
  // ---------------------------------------------------------
  Future<void> _processFinalSave() async {
    // 1. Mostrar Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      // 2. Aplanar las Asignaciones (Assignments)
      // Convertimos el mapa complejo a uno simple: "Grupo-Slot" -> "ID_Equipo"
      // Ej: { "1-1": "mongo_id_raptors", "1-2": "mongo_id_falcons" }
      Map<String, String> flatAssignments = {};

      _assignments.forEach((groupId, slots) {
        slots.forEach((slotId, team) {
          if (team != null) {
            String key = _groupIds.length == 1 ? "$slotId" : "$groupId-$slotId";
            // Guardamos el ID del equipo (Soporte para _id o id)
            flatAssignments[key] = team['id'] ?? team['_id'];
          }
        });
      });

      // 3. Construir el Documento "Draft"
      // Este documento será la fuente de verdad para tu calendario
      final draftDoc = {
        'type': 'draft_record', // Identificador para tus queries en backend
        'tournamentId': widget.tournamentId,
        'categoryName': widget.categoryName,
        'status': 'active', // o 'published'
        'createdAt': DateTime.now().toIso8601String(),

        // DATOS CRÍTICOS:
        'assignments': flatAssignments, // ¿Quién es quién?
        'structure':
            widget.draftData, // El calendario matemático (Jornadas, Stats)
        // Opcional: Guardar un resumen legible para búsquedas rápidas
        'totalTeams': flatAssignments.length,
      };

      // 4. Enviar al Servidor
      final response = await _apiService.post(draftDoc);

      // 5. Manejar Respuesta
      if (!mounted) return;
      Navigator.pop(context); // Cerrar Loading

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Éxito: Regresar al detalle del torneo o ir al Dashboard
        setState(() {
          // Guardamos el ID que nos devolvió el backend (CouchDB devuelve 'id')
          _savedDraftId = response.data['id'];
          _hasUnsavedChanges = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Draft guardado. Ahora puedes generar el calendario.",
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception("Error ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Cerrar Loading si sigue abierto

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al guardar: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generateOfficialSchedule() async {
    if (_savedDraftId == null) return;

    // 1. Mostrar Loading (Calculando...)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 15),
            Text(
              "Optimizando calendario...",
              style: TextStyle(
                color: Colors.white,
                decoration: TextDecoration.none,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // 2. Llamar al Endpoint Poderoso
      final response = await _apiService.generateOfficialSchedule(
        widget.tournamentId,
        _savedDraftId!,
      );

      if (!mounted) return;
      Navigator.pop(context); // Cerrar Loading

      if (response.statusCode == 200) {
        // 3. Obtener el ID del nuevo Calendario Oficial
        String newScheduleId =
            response.data['id']; // CouchDB devuelve el ID del doc insertado

        // 4. Navegar a la pantalla de Gestión (Reemplazando la actual)
        // Importante importar schedule_management_screen.dart
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ScheduleManagementScreen(
              scheduleId: newScheduleId,
              categoryName: widget.categoryName,
              tournamentId: widget.tournamentId,
            ),
          ),
        );
      } else {
        throw Exception("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error generando calendario: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
