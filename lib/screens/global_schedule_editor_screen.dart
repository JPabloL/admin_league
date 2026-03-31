import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
// Asegúrate de que este import apunte a tu servicio real
import 'package:admin_league/services/api_service.dart';
import 'package:admin_league/models/user_model.dart';
import 'package:intl/date_symbol_data_local.dart'; // <--- IMPORTANTE
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
// =============================================================================
//  MODELOS DE DATOS
// =============================================================================

class DayConfig {
  DateTime date;
  // Guardamos la lista exacta de horarios de inicio para permitir edición individual
  List<DateTime> timeSlots;
  int fieldCount;

  DayConfig({required this.date, required this.timeSlots, this.fieldCount = 3});

  // Copia profunda para edición segura
  DayConfig copy() {
    return DayConfig(
      date: date,
      timeSlots: List.from(timeSlots),
      fieldCount: fieldCount,
    );
  }
}

class SpecialEvent {
  final String id;
  final DateTime start;
  final DateTime end;
  String title;

  SpecialEvent({
    required this.id,
    required this.start,
    required this.end,
    required this.title,
  });
}

// =============================================================================
//  WIDGET PRINCIPAL
// =============================================================================

class ScheduleEditorScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;
  final UserModel user;

  const ScheduleEditorScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
    required this.user,
  });

  @override
  State<ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<ScheduleEditorScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  // --- ESTADO GENERAL ---
  bool _isLoading = false;
  List<String> _lastAssignedBatchKeys = [];
  bool _isSaving = false;
  bool _isFabOpen = false;
  late AnimationController _fabAnimationController;
  int _currentJornada = 1;
  final List<int> _availableJornadas = List.generate(15, (i) => i + 1);
  String? _globalDocRev;
  // --- CONTROLADOR MÓVIL ---
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  String _selectedCategoryFilter = 'Todas';
  String _selectedAcademyFilter = 'Todas';

  // Configuración Dinámica (Días y sus slots)
  List<DayConfig> _daysConfig = [];

  // Eventos Especiales (Inauguraciones, etc.)
  // Key: "ISO_START_TIME" para fácil acceso
  final Map<String, SpecialEvent> _specialEvents = {};

  // Datos del Torneo
  Map<String, dynamic> _teamsLookup = {};
  List<Map<String, dynamic>> _allMatches = [];

  // Asignaciones: Key="ISO_Date_String_FieldIdx" -> Value=MatchId
  final Map<String, String> _gridAssignments = {};

  List<String> get _availableCategories {
    // 1. Obtenemos solo los partidos que NO están asignados aún
    final pendingMatches = _allMatches
        .where((m) => !_gridAssignments.containsValue(m['matchId']))
        .toList();

    // 2. Extraemos las categorías únicas de esos partidos pendientes
    final cats = pendingMatches
        .map((m) => m['categoryName']?.toString() ?? "Sin Categoría")
        .toSet()
        .toList();

    cats.sort();

    // 3. Retornamos la lista con 'Todas' al inicio
    final list = ['Todas', ...cats];

    // 4. Seguridad: Si la categoría seleccionada desaparece (porque asignaste el último juego),
    // reseteamos el filtro a 'Todas' en el siguiente frame para evitar errores de Dropdown.
    if (!list.contains(_selectedCategoryFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedCategoryFilter = 'Todas');
      });
    }

    return list;
  }

  List<String> get _availableAcademies {
    // Extraemos los nombres de las academias de todos los equipos en el lookup
    final academies = _teamsLookup.values
        .map(
          (t) => (t['academy'] != null && t['academy']['name'] != null)
              ? t['academy']['name'].toString()
              : "Independiente",
        )
        .toSet()
        .toList();

    academies.sort();
    return ['Todas', ...academies];
  }

  // --- ESTILOS DE CATEGORÍA (Mapeo idéntico al de Ionic) ---
  final Map<String, Map<String, PdfColor>> _categoryStyles = {
    // --- INFANTILES (Tonos Brillantes/Primarios) ---
    'U6': {
      'bg': PdfColor.fromHex('#ffe666'),
      'text': PdfColors.black,
    }, // Amarillo
    'U7': {'bg': PdfColor.fromHex('#17dcff'), 'text': PdfColors.black}, // Cian
    'U8': {
      'bg': PdfColor.fromHex('#00ff00'),
      'text': PdfColors.black,
    }, // Verde Neón
    'U9': {
      'bg': PdfColor.fromHex('#baffc9'),
      'text': PdfColors.black,
    }, // Verde Menta
    'U10': {'bg': PdfColor.fromHex('#fa5757'), 'text': PdfColors.white}, // Rojo
    'U11': {'bg': PdfColor.fromHex('#ccff00'), 'text': PdfColors.black}, // Lima
    'U12': {
      'bg': PdfColor.fromHex('#ff9900'),
      'text': PdfColors.black,
    }, // Naranja
    // --- SUB 12 (Pasteles) ---
    'FU12': {
      'bg': PdfColor.fromHex('#ff94e6'),
      'text': PdfColors.black,
    }, // Rosa
    'VU12': {
      'bg': PdfColor.fromHex('#9ba2d1'),
      'text': PdfColors.black,
    }, // Lavanda
    // --- SUB 14 (Azules y cremas) ---
    'U14': {
      'bg': PdfColor.fromHex('#3d85c6'),
      'text': PdfColors.white,
    }, // Azul Medio
    'VU14': {
      'bg': PdfColor.fromHex('#073763'),
      'text': PdfColors.white,
    }, // Azul Marino
    'FU14': {
      'bg': PdfColor.fromHex('#fce5cd'),
      'text': PdfColors.black,
    }, // Crema/Piel
    // --- NUEVAS: SUB 15 (Gamas de Marrón/Ocre para diferenciar) ---
    'U15': {
      'bg': PdfColor.fromHex('#a64d79'),
      'text': PdfColors.white,
    }, // Magenta Oscuro
    'VU15': {
      'bg': PdfColor.fromHex('#4c1130'),
      'text': PdfColors.white,
    }, // Vino Tinto
    'FU15': {
      'bg': PdfColor.fromHex('#ead1dc'),
      'text': PdfColors.black,
    }, // Rosa Pálido
    // --- SUB 16 (Púrpuras) ---
    'U16': {'bg': PdfColor.fromHex('#674ea7'), 'text': PdfColors.white},
    'FU16': {'bg': PdfColor.fromHex('#d9d2e9'), 'text': PdfColors.black},
    'VU16': {'bg': PdfColor.fromHex('#20124d'), 'text': PdfColors.white},

    // --- NUEVAS: SUB 17 (Gamas de Turquesa/Petróleo) ---
    'U17': {
      'bg': PdfColor.fromHex('#45818e'),
      'text': PdfColors.white,
    }, // Turquesa Oscuro
    'VU17': {
      'bg': PdfColor.fromHex('#134f5c'),
      'text': PdfColors.white,
    }, // Petróleo
    'FU17': {
      'bg': PdfColor.fromHex('#d0e0e3'),
      'text': PdfColors.black,
    }, // Cian muy pálido
    // --- SUB 18 (Verdes Bosque) ---
    'U18': {'bg': PdfColor.fromHex('#4fa02d'), 'text': PdfColors.black},
    'VU18': {'bg': PdfColor.fromHex('#0b5394'), 'text': PdfColors.white},
    'FU18': {'bg': PdfColor.fromHex('#c0fbf0'), 'text': PdfColors.black},

    // --- NUEVAS: SUB 21C (Grises y metálicos) ---
    'U21C': {
      'bg': PdfColor.fromHex('#7f6000'),
      'text': PdfColors.white,
    }, // Mostaza Quemada
    'VU21C': {
      'bg': PdfColor.fromHex('#333333'),
      'text': PdfColors.white,
    }, // Carbón
    'FU21C': {
      'bg': PdfColor.fromHex('#cccccc'),
      'text': PdfColors.black,
    }, // Gris Plata
    // --- MAYORES / LIBRES (Identidad fuerte) ---
    'MV': {'bg': PdfColor.fromHex('#000000'), 'text': PdfColors.white}, // Negro
    'MF': {
      'bg': PdfColor.fromHex('#f78764'),
      'text': PdfColors.white,
    }, // Coral fuerte
    'MM': {
      'bg': PdfColor.fromHex('#8f2d56'),
      'text': PdfColors.white,
    }, // Ciruela
    'LV': {
      'bg': PdfColor.fromHex('#1155cc'),
      'text': PdfColors.white,
    }, // Royal Blue
    'LF': {'bg': PdfColor.fromHex('#00ffd5'), 'text': PdfColors.black}, // Aqua
    'LM': {
      'bg': PdfColor.fromHex('#351c75'),
      'text': PdfColors.white,
    }, // Índigo
  };

  // Interacción
  String? _selectedMatchId;
  String _activeFilter = 'todos';

  // Constantes
  static const int _slotDurationMinutes = 60;
  static const Color _bgScaffold = Color(0xFFF2F2F7);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _sidebarBg = Color(0xFFE5E5EA);
  static const Color _accentColor = Color(0xFF007AFF);
  static const Color _selectionColor = Color(0xFFFFD60A);
  static const Color _textPrimary = Color(0xFF1C1C1E);
  static const Color _textSecondary = Color(0xFF8E8E93);
  static const Color _redError = Color(0xFFFF453A);
  static const Color _greenSuccess = Color(0xFF32D74B);
  static const Color _orangeGap = Color(0xFFFF9500);

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

    initializeDateFormatting('es', null);
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _initializeDefaultConfig();
    _loadJornadaData();
  }

  void _initializeDefaultConfig() {
    // Generar un sábado por defecto de 8am a 2pm si no hay config
    final now = DateTime.now();
    int daysToSat = DateTime.saturday - now.weekday;
    if (daysToSat <= 0) daysToSat += 7;
    final nextSat = DateTime(now.year, now.month, now.day + daysToSat, 8, 0);

    List<DateTime> initialSlots = [];
    for (int i = 0; i < 6; i++) {
      initialSlots.add(
        nextSat.add(Duration(minutes: i * _slotDurationMinutes)),
      );
    }

    _daysConfig.add(
      DayConfig(date: nextSat, timeSlots: initialSlots, fieldCount: 3),
    );
  }

  // ===========================================================================
  //  CARGA DE DATOS
  // ===========================================================================
  Future<void> _loadJornadaData() async {
    setState(() {
      _isLoading = true;
      _globalDocRev = null;
    });
    _selectedMatchId = null;
    _gridAssignments.clear();
    _daysConfig.clear();

    Map<String, dynamic>? savedDoc;

    try {
      // 1. CARGAR BORRADOR (Si existe)
      try {
        final String globalDocId =
            "roljornada_${widget.tournamentId}_$_currentJornada";
        final responseSaved = await _apiService.getDocById(globalDocId);
        if (responseSaved.statusCode == 200) {
          savedDoc = responseSaved.data['doc'] ?? responseSaved.data;
          _globalDocRev = savedDoc?['_rev'];
        }
      } catch (_) {}

      // 2. CARGAR CONTEXTO OFICIAL
      final responseCtx = await _apiService.getJornadaContext(
        widget.tournamentId,
        _currentJornada,
      );

      if (responseCtx.statusCode == 200) {
        final data = responseCtx.data;

        // =============================================================
        print(data);

        // =============================================================
        // A. PREPARAR FUENTES DE EQUIPOS
        // =============================================================
        // Necesitamos 'rawLookup' para resolver Slots (llaves "1", "2")
        // Necesitamos 'normalizedLookup' para la UI (llaves UUID)

        Map<String, dynamic> rawLookup = {};
        if (data['teamsLookup'] != null) {
          rawLookup = Map<String, dynamic>.from(data['teamsLookup']);
        }

        // Si viene 'teams' (formato nuevo), lo mezclamos al rawLookup usando sus IDs
        if (data['teams'] != null) {
          Map<String, dynamic> teamsList = Map<String, dynamic>.from(
            data['teams'],
          );
          rawLookup.addAll(teamsList);
        }

        Map<String, dynamic> normalizedLookup = {};

        rawLookup.forEach((key, value) {
          if (value is Map && value.containsKey('_id')) {
            normalizedLookup[value['_id']] = value;
          }
        });

        // =============================================================
        // B. EXTRACCIÓN DE PARTIDOS
        // =============================================================
        List<dynamic> rawMatches = data['matches'] ?? [];

        // Búsqueda profunda en 'jornadas' si la raíz está vacía
        if (rawMatches.isEmpty && data['jornadas'] != null) {
          var jornadaObj = (data['jornadas'] as List).firstWhere(
            (j) => j['number'] == _currentJornada,
            orElse: () => null,
          );
          if (jornadaObj != null) rawMatches = jornadaObj['matches'];
        }

        // =============================================================
        // C. NORMALIZACIÓN AVANZADA (Slots + Strings + Objects)
        // =============================================================
        // Función Helper para resolver ID sea cual sea el formato
        String? resolveTeamId(dynamic ref) {
          if (ref == null) return null;

          // CASO 1: Es un String directo (ID)
          if (ref is String) return ref;

          if (ref is Map) {
            // CASO 2: Objeto hidratado (tiene _id)
            if (ref.containsKey('_id')) return ref['_id'];

            // CASO 3: Referencia de Slot ({group: "1", slot: 4})
            if (ref.containsKey('slot')) {
              String slotKey = ref['slot'].toString();
              // Buscamos en el rawLookup (que tiene llaves numéricas "1", "2")
              if (rawLookup.containsKey(slotKey)) {
                return rawLookup[slotKey]['_id'];
              }
              // A veces la llave es compuesta "1-4" (group-slot), intento fallback
              String compositeKey = "${ref['group']}-${ref['slot']}";
              if (rawLookup.containsKey(compositeKey)) {
                return rawLookup[compositeKey]['_id'];
              }
            }
          }
          return null;
        }

        _allMatches = [];
        for (var m in rawMatches) {
          var map = Map<String, dynamic>.from(m);

          // 1. RESOLVER IDs (La clave del arreglo)
          String? hId = resolveTeamId(
            map['homeId'] ?? map['home'] ?? map['homeRef'],
          );
          String? aId = resolveTeamId(
            map['awayId'] ?? map['away'] ?? map['awayRef'],
          );

          // Si no pudimos resolver alguno de los dos equipos, saltamos el partido por seguridad
          // (Opcional: podrías dejarlo pero se verá roto)
          if (hId == null || aId == null) {
            print("⚠️ Partido ignorado por falta de IDs: ${map}");
            continue;
          }

          map['homeId'] = hId;
          map['awayId'] = aId;

          // 2. ID DEL PARTIDO
          if (map['matchId'] == null) {
            map['matchId'] = "${hId}_${aId}";
          }

          // 3. CATEGORÍA
          if (map['categoryName'] == null) {
            if (map['category'] is Map) {
              map['categoryName'] = map['category']['name'];
            } else {
              map['categoryName'] = data['categoryName'] ?? "General";
            }
          }

          // 4. HIDRATACIÓN INVERSA (Si el partido trae datos que el lookup no tenía)
          if (!normalizedLookup.containsKey(hId) &&
              map['home'] is Map &&
              map['home'].containsKey('_id')) {
            normalizedLookup[hId] = map['home'];
          }
          if (!normalizedLookup.containsKey(aId) &&
              map['away'] is Map &&
              map['away'].containsKey('_id')) {
            normalizedLookup[aId] = map['away'];
          }

          _allMatches.add(map);
        }

        setState(() {
          _teamsLookup = normalizedLookup;

          if (savedDoc != null) {
            _restoreFromSavedDoc(savedDoc);
          } else {
            _restoreInitialAssignments();
            _initializeDefaultConfig();
          }
        });
      }
    } catch (e, stack) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error visualizando datos: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _restoreFromSavedDoc(Map<String, dynamic> doc) {
    // 1. Limpieza inicial del estado actual para evitar duplicados
    setState(() {
      _gridAssignments.clear();
      _daysConfig.clear();

      // Marcamos todos los partidos como no asignados antes de hidratar
      for (var m in _allMatches) {
        m['assignedTime'] = null;
        m['assignedField'] = null;
      }

      final board = doc['boardConfig'];
      if (board == null) return;

      List<dynamic> diasSaved = board['diasConfig'] ?? [];
      int numCampos = board['numCampos'] ?? 6;

      // 2. Reconstrucción de la configuración de días y slots
      _daysConfig = diasSaved.map((d) {
        DateTime fechaBase = DateTime.parse(d['fecha']);
        List<DateTime> slots = [];

        // Prioridad: Usar la lista de slots exactos guardados
        if (d['slots'] != null) {
          slots = (d['slots'] as List)
              .map((s) => DateTime.parse(s.toString()))
              .toList();
        } else {
          // Fallback: Si es un doc viejo, reconstruir por horaInicio/Fin (cada 60 min)
          try {
            String startStr = d['horaInicio'];
            String endStr = d['horaFin'];
            DateTime startDt = DateTime(
              fechaBase.year,
              fechaBase.month,
              fechaBase.day,
              int.parse(startStr.split(':')[0]),
              int.parse(startStr.split(':')[1]),
            );
            DateTime endDt = DateTime(
              fechaBase.year,
              fechaBase.month,
              fechaBase.day,
              int.parse(endStr.split(':')[0]),
              int.parse(endStr.split(':')[1]),
            );

            DateTime current = startDt;
            while (current.isBefore(endDt)) {
              slots.add(current);
              current = current.add(const Duration(hours: 1));
            }
          } catch (e) {
            print("Error reconstruyendo slots antiguos: $e");
          }
        }

        return DayConfig(
          date: fechaBase,
          timeSlots: slots,
          fieldCount: numCampos,
        );
      }).toList();

      // 3. Hidratación de partidos en la grilla
      List<dynamic> partidosGuardados = doc['partidos'] ?? [];

      for (var p in partidosGuardados) {
        if (p['date'] == null || p['field'] == null) continue;

        // Normalizamos la fecha guardada para comparar (evita errores de milisegundos)
        String savedDateIso = DateTime.parse(
          p['date'],
        ).toIso8601String().substring(0, 19);
        int fieldIdx = p['field'] - 1; // La API suele usar base 1 para campos

        // Buscamos el matchId correspondiente en nuestra lista maestra (_allMatches)
        // Usamos los IDs de equipos para asegurar el match correcto
        int matchIdx = _allMatches.indexWhere(
          (m) =>
              m['homeId'] == p['home']['_id'] &&
              m['awayId'] == p['visitor']['_id'],
        );

        if (matchIdx != -1) {
          String matchId = _allMatches[matchIdx]['matchId'];

          // Buscamos el slot exacto en nuestra nueva configuración que coincida con la fecha guardada
          bool slotEncontrado = false;
          for (var day in _daysConfig) {
            for (var slot in day.timeSlots) {
              if (slot.toIso8601String().substring(0, 19) == savedDateIso) {
                String gridKey = "${slot.toIso8601String()}_$fieldIdx";

                // Asignamos a la grilla visual
                _gridAssignments[gridKey] = matchId;

                // Actualizamos el objeto en la lista maestra
                _allMatches[matchIdx]['assignedTime'] = slot.toIso8601String();
                _allMatches[matchIdx]['assignedField'] =
                    "Campo ${fieldIdx + 1}";

                slotEncontrado = true;
                break;
              }
            }
            if (slotEncontrado) break;
          }
        }
      }
    });

    // Al final de _restoreFromSavedDoc
    if (doc['specialEvents'] != null) {
      Map<String, dynamic> savedEvents = doc['specialEvents'];
      _specialEvents.clear();
      savedEvents.forEach((key, data) {
        _specialEvents[key] = SpecialEvent(
          id: data['id'],
          start: DateTime.parse(data['start']),
          end: DateTime.parse(data['end']),
          title: data['title'],
        );
      });
    }
  }

  void _restoreInitialAssignments() {
    // Lógica original para casos donde el match ya trae assignedTime del generador
    for (var match in _allMatches) {
      if (match['assignedTime'] != null && match['assignedField'] != null) {
        final assignedDate = DateTime.parse(match['assignedTime']);
        int fieldIdx = 0;
        try {
          fieldIdx =
              int.parse(
                match['assignedField'].toString().replaceAll(
                  RegExp(r'[^0-9]'),
                  '',
                ),
              ) -
              1;
        } catch (_) {}
        String key = "${assignedDate.toIso8601String()}_$fieldIdx";
        _gridAssignments[key] = match['matchId'];
      }
    }
  }

  // ===========================================================================
  //  LÓGICA DE TIEMPO DINÁMICO
  // ===========================================================================

  /// Cambia una hora específica y recorre todas las siguientes (Efecto Dominó)
  void _updateSlotTime(DayConfig config, int slotIndex, TimeOfDay newTime) {
    setState(() {
      DateTime oldDt = config.timeSlots[slotIndex];
      DateTime newDt = DateTime(
        oldDt.year,
        oldDt.month,
        oldDt.day,
        newTime.hour,
        newTime.minute,
      );

      Duration diff = newDt.difference(oldDt);

      // IMPORTANTE: Primero movemos las asignaciones de todos los bloques afectados
      // de atrás hacia adelante para no perder datos.
      _pushAssignmentsAfterChange(config, slotIndex, diff);
    });
  }

  /// Mueve físicamente los partidos en _gridAssignments de una Key vieja a una nueva
  void _moveAssignmentsForTime(
    DateTime oldTime,
    DateTime newTime,
    int fieldCount,
  ) {
    for (int f = 0; f < fieldCount; f++) {
      String oldKey = "${oldTime.toIso8601String()}_$f";
      if (_gridAssignments.containsKey(oldKey)) {
        String matchId = _gridAssignments[oldKey]!;
        _gridAssignments.remove(oldKey);

        String newKey = "${newTime.toIso8601String()}_$f";
        _gridAssignments[newKey] = matchId;

        // Actualizar el modelo del partido
        int idx = _allMatches.indexWhere((m) => m['matchId'] == matchId);
        if (idx != -1) {
          _allMatches[idx]['assignedTime'] = newTime.toIso8601String();
        }
      }
    }
  }

  Future<void> guardarHorarios() async {
    setState(() => _isSaving = true);
    try {
      List<Map<String, dynamic>> partidosAGuardar = [];

      _gridAssignments.forEach((key, matchId) {
        final parts = key.split('_');
        final dateIso = parts[0];
        final fieldIdx = int.parse(parts[1]);
        final dateObj = DateTime.parse(dateIso);

        final matchBase = _allMatches.firstWhere(
          (m) => m['matchId'] == matchId,
        );

        // Limpiamos los equipos para eliminar 'constraints' y otros datos extra
        final Map<String, dynamic> homeClean = _cleanTeamForSave(
          _teamsLookup[matchBase['homeId']],
        );
        final Map<String, dynamic> visitorClean = _cleanTeamForSave(
          _teamsLookup[matchBase['awayId']],
        );

        final diaNombre = DateFormat('EEEE', 'es').format(dateObj);
        final diaNombreCap =
            diaNombre[0].toUpperCase() + diaNombre.substring(1);

        partidosAGuardar.add({
          "home": homeClean,
          "visitor": visitorClean,
          "isRepeat": matchBase['isRepeat'] ?? false,
          "group": matchBase['group'] ?? "G1",
          "type": "match",
          "tournament": {
            "id": widget.tournamentId,
            "name": widget.tournamentName,
            "start": matchBase['tournament']?['start'] ?? "",
            "end": matchBase['tournament']?['end'] ?? "",
          },
          "date": dateIso,
          "sede": {
            "name": matchBase['sede']?['name'] ?? "Por definir",
            "dir": matchBase['sede']?['dir'] ?? "Por definir",
          },
          "friendly": matchBase['friendly'] ?? false,
          "referee": matchBase['referee'] ?? [],
          "active": true,
          "public": true,
          "typeGame": matchBase['typeGame'] ?? {"name": "Regular"},
          "journey": _currentJornada,
          "field": fieldIdx + 1,
          "team1HasConflict": _hasConflictInGrid(
            matchBase['homeId'],
            dateObj,
            excludeMatchId: matchId,
          ),
          "team2HasConflict": _hasConflictInGrid(
            matchBase['awayId'],
            dateObj,
            excludeMatchId: matchId,
          ),
          "_id": "${matchBase['homeId']}_${matchBase['awayId']}",
          "category": {"name": matchBase['categoryName']},
          "dia": diaNombreCap,
          "hora": DateFormat('HH:mm').format(dateObj),
          "campo": fieldIdx + 1,
        });
      });

      // Listas de apoyo
      List<Map<String, dynamic>> pendientes = _allMatches
          .where((m) => !_gridAssignments.containsValue(m['matchId']))
          .toList();

      List<Map<String, dynamic>> listaDescansos = _calcularEquiposEnDescanso();
      List<Map<String, dynamic>> listaDobles = _calcularEquiposJuegoDoble();

      final datosFinales = {
        "_id": "roljornada_${widget.tournamentId}_$_currentJornada",
        if (_globalDocRev != null) "_rev": _globalDocRev,
        "type": "rolJornada",
        "torneoId": widget.tournamentId,
        "jornadaNum": _currentJornada,
        "partidos": partidosAGuardar,
        "partidosPendientes": pendientes,
        "equiposEnDescanso": listaDescansos,
        "equiposJuegoDoble": listaDobles,
        "lastUpdated": DateTime.now().toIso8601String(),
        "boardConfig": {
          "diasConfig": _daysConfig
              .map(
                (d) => {
                  "dia": DateFormat('EEEE', 'es')
                      .format(d.date)
                      .replaceFirstMapped(
                        RegExp(r"^\w"),
                        (m) => m[0]!.toUpperCase(),
                      ),
                  "seleccionado": true,
                  "horaInicio": DateFormat('HH:mm').format(d.timeSlots.first),
                  "horaFin": DateFormat(
                    'HH:mm',
                  ).format(d.timeSlots.last.add(const Duration(hours: 1))),
                  "fecha": d.date.toIso8601String(),
                  "slots": d.timeSlots.map((t) => t.toIso8601String()).toList(),
                },
              )
              .toList(),
          "numCampos": _daysConfig.isNotEmpty
              ? _daysConfig.first.fieldCount
              : 6,
        },
      };

      // Enviar a la API
      final response = await _apiService.post(datosFinales);
      if (response.statusCode == 200) {
        _globalDocRev =
            response.data['rev']; // Actualizar para el siguiente guardado
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rol guardado exitosamente"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al guardar: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Map<String, dynamic> _cleanTeamForSave(Map<String, dynamic> team) {
    return {
      "_id": team["_id"],
      "_rev": team["_rev"],
      "type": "team",
      "name": team["name"],
      "category":
          team["category"], // Objeto completo: name, shortName, longName, etc.
      "academy": team["academy"], // Objeto: id, name
      "mood": team["mood"] ?? 0,
      "tournament": team["tournament"],
      "logo": team["logo"],
      "toF": team["toF"] ?? 2,
      "toS": team["toS"] ?? 2,
      "toList": team["toList"] ?? [],
      if (team.containsKey("byes")) "byes": team["byes"],
    };
  }

  // --- FUNCIONES DE APOYO PARA EL GUARDADO ---

  /// Identifica equipos que NO tienen ningún partido en la jornada actual
  List<Map<String, dynamic>> _calcularEquiposEnDescanso() {
    // 1. Recopilar IDs de todos los equipos que SÍ tienen partido (asignado o pendiente)
    Set<String> equiposConActividad = {};
    for (var m in _allMatches) {
      equiposConActividad.add(m['homeId']);
      equiposConActividad.add(m['awayId']);
    }

    List<Map<String, dynamic>> descansos = [];

    // 2. Comparar contra el Lookup Global (que ahora trae a todos gracias al cambio en el backend)
    _teamsLookup.forEach((id, team) {
      if (!equiposConActividad.contains(id)) {
        descansos.add({
          "_id": id,
          "name": team["name"],
          "logo": team["logo"],
          "categoryName": (team["category"] is Map)
              ? team["category"]["name"]
              : team["category"].toString(),
        });
      }
    });

    // Ordenar alfabéticamente para que se vea bien en la lista
    descansos.sort((a, b) => a['name'].compareTo(b['name']));
    return descansos;
  }

  /// Identifica equipos que aparecen 2 o más veces en la lista de partidos
  List<Map<String, dynamic>> _calcularEquiposJuegoDoble() {
    Map<String, int> conteo = {};
    Map<String, Set<String>> categorias = {};

    for (var m in _allMatches) {
      String hId = m['homeId'];
      String vId = m['awayId'];
      String cat = m['categoryName'] ?? "N/A";

      conteo[hId] = (conteo[hId] ?? 0) + 1;
      conteo[vId] = (conteo[vId] ?? 0) + 1;

      categorias.putIfAbsent(hId, () => {}).add(cat);
      categorias.putIfAbsent(vId, () => {}).add(cat);
    }

    List<Map<String, dynamic>> dobles = [];
    conteo.forEach((id, total) {
      if (total > 1) {
        final team = _teamsLookup[id];
        if (team != null) {
          dobles.add({
            "_id": id,
            "name": team["name"],
            "logo": team["logo"],
            "conteo": total,
            "categoryNames": categorias[id]?.toList() ?? [],
          });
        }
      }
    });
    return dobles;
  }

  // Agrega esto a tus métodos de lógica
  bool _checkIfDoubleHeader(String teamId) {
    // Contamos cuántas veces aparece el teamId en la lista completa de partidos
    int count = 0;
    for (var match in _allMatches) {
      if (match['homeId'] == teamId || match['awayId'] == teamId) {
        count++;
      }
    }
    return count > 1;
  }

  Future<void> crearPartidosParaGuardar() async {
    if (_gridAssignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No hay partidos asignados para generar."),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      List<Map<String, dynamic>> partidosFormateados = [];

      // Recorremos las asignaciones
      _gridAssignments.forEach((key, matchId) {
        final match = _allMatches.firstWhere((m) => m['matchId'] == matchId);
        final home = _teamsLookup[match['homeId']];
        final away = _teamsLookup[match['awayId']];

        // Key es "ISO_DATE_FIELDIDX"
        final parts = key.split('_');
        final assignedDateIso = parts[0]; // Esto ya es "YYYY-MM-DDTHH:mm:ss..."
        final fieldIdx = int.parse(parts[1]);

        // Formato para la API: YYYY-MM-DDTHH:mm
        // Flutter toIso8601String incluye segundos y .000Z, a veces conviene limpiar
        final cleanDate = assignedDateIso.substring(0, 16);

        final nuevoPartido = {
          'type': 'match',
          'home': home, // Objeto completo del equipo
          'visitor': away, // Objeto completo del equipo

          'date': cleanDate,
          'journey': _currentJornada,
          'field': fieldIdx + 1,

          'tournament': {
            '_id': widget.tournamentId,
            'name': widget.tournamentName,
          },
          'category': {'name': match['categoryName']},

          // --- DATOS HARDCODEADOS DEL PROYECTO IONIC ---
          'sede': {
            'name': "Flag Zone Querétaro",
            'dir':
                "Av. Del Río S/N, Col. El Pueblito, Corregidora, Mexico, 76900",
          },
          'friendly': false,
          'referee': [
            {
              "id": "70e58f92151781f7fe6cf8cc8e8eae44",
              "name": "Genérico ",
              "gender": "M",
              "bd": "2003-04-01",
              "thumb":
                  "https://cuerposallimite.net/nlff/resources/images/refs/70e58f92151781f7fe6cf8cc8e8eae44/thumb_862e9629-fdb2-4870-b4cd-33de46cd604f 2.jpg",
            },
            {
              "id": "70e58f92151781f7fe6cf8cc8e931f89",
              "name": "Ernesto Magos",
              "gender": "M",
              "bd": "2003-04-01",
              "thumb":
                  "https://cuerposallimite.net/nlff/resources/images/refs/70e58f92151781f7fe6cf8cc8e8eae44/thumb_862e9629-fdb2-4870-b4cd-33de46cd604f 2.jpg",
            },
            {
              "id": "ace77646edb89e03e79dbdbc75fcf107",
              "name": "Pablo",
              "gender": "M",
              "bd": "2003-04-01",
            },
          ],
          'public': true,
          'typeGame': {"name": "Regular"},
          'gameStatus': 'scheduled',
          'mvp': {},
          'refComments': [],
        };

        partidosFormateados.add(nuevoPartido);
      });

      // Enviar a la API (Endpoint postMultiple)
      await _apiService.postMultiple(partidosFormateados);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Partidos generados y publicados con éxito."),
          backgroundColor: _greenSuccess,
        ),
      );
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al generar partidos: $e"),
          backgroundColor: _redError,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> exportarAPDF() async {
    // 0. CÁLCULO DE LISTAS (Datos dinámicos para el final del PDF)
    final descansos = _calcularEquiposEnDescanso();
    final doblesData = _calcularEquiposJuegoDoble();

    if (_gridAssignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No hay partidos asignados para exportar."),
        ),
      );
      return;
    }

    try {
      final fontRegular = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      );

      // 1. ORGANIZAR DATOS POR DÍA -> HORA
      Map<String, Map<String, List<dynamic>>> datosPorDia = {};
      var asignacionesOrdenadas = _gridAssignments.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      for (var entry in asignacionesOrdenadas) {
        final parts = entry.key.split('_');
        final dateIso = parts[0];
        final dateObj = DateTime.parse(dateIso);

        final diaKey = DateFormat(
          'EEEE d MMMM',
          'es',
        ).format(dateObj).toUpperCase();
        final horaKey = DateFormat('HH:mm').format(dateObj);

        final match = _allMatches.firstWhere(
          (m) => m['matchId'] == entry.value,
        );
        final fieldIdx = int.parse(parts[1]) + 1;

        final matchPdf = {
          ...match,
          'temp_field': fieldIdx.toString(),
          'raw_date': dateIso,
        };

        if (!datosPorDia.containsKey(diaKey)) datosPorDia[diaKey] = {};
        if (!datosPorDia[diaKey]!.containsKey(horaKey))
          datosPorDia[diaKey]![horaKey] = [];
        datosPorDia[diaKey]![horaKey]!.add(matchPdf);
      }

      // 2. GENERAR PÁGINAS
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(25),
          build: (pw.Context context) {
            List<pw.Widget> widgets = [];

            // Header
            widgets.add(
              pw.Center(
                child: pw.Text(
                  "ROL DE JUEGOS - JORNADA $_currentJornada",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );
            widgets.add(
              pw.Center(
                child: pw.Text(
                  widget.tournamentName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 20));

            datosPorDia.forEach((diaNombre, horariosMap) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                  child: pw.Text(
                    diaNombre,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              );

              List<pw.TableRow> tableRows = [];
              // Encabezado
              tableRows.add(
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _pdfCell("HORA", isHeader: true),
                    _pdfCell("CAT", isHeader: true),
                    _pdfCell("EQUIPO LOCAL", isHeader: true),
                    _pdfCell("EQUIPO VISITANTE", isHeader: true),
                    _pdfCell("CAMPO", isHeader: true),
                  ],
                ),
              );

              horariosMap.forEach((hora, partidos) {
                // --- EVENTO ESPECIAL (GAP) ---
                final String firstMatchDate = partidos.first['raw_date'];
                SpecialEvent? event = _specialEvents[firstMatchDate];

                if (event != null) {
                  tableRows.add(
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.orange50,
                      ),
                      children: [
                        _pdfCell(hora, isBold: true),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              "*** ${event.title.toUpperCase()} ***",
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.orange900,
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.SizedBox(),
                        pw.SizedBox(),
                      ],
                    ),
                  );
                } else {
                  // PARTIDOS NORMALES
                  partidos.sort(
                    (a, b) => int.parse(
                      a['temp_field'],
                    ).compareTo(int.parse(b['temp_field'])),
                  );
                  for (var i = 0; i < partidos.length; i++) {
                    final p = partidos[i];
                    final catName = p['categoryName'];
                    final style =
                        _categoryStyles[catName] ??
                        {'bg': PdfColors.white, 'text': PdfColors.black};

                    // HIDRATACIÓN DE EQUIPOS: Buscamos en el lookup por ID
                    final homeTeam = _teamsLookup[p['homeId']];
                    final awayTeam = _teamsLookup[p['awayId']];

                    tableRows.add(
                      pw.TableRow(
                        children: [
                          _pdfCell(i == 0 ? hora : "", isBold: true),
                          pw.Container(
                            color: style['bg'],
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              catName,
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: style['text'],
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          _pdfCell(
                            homeTeam?['name'] ?? "No encontrado",
                            align: pw.TextAlign.left,
                            isBold: true,
                            // NUEVO: Pinta de rojo si es jornada doble
                            textColor: _checkIfDoubleHeader(p['homeId'])
                                ? PdfColors.red700
                                : PdfColors.black,
                          ),
                          _pdfCell(
                            awayTeam?['name'] ?? "No encontrado",
                            align: pw.TextAlign.left,
                            isBold: true,
                            // NUEVO: Pinta de rojo si es jornada doble
                            textColor: _checkIfDoubleHeader(p['awayId'])
                                ? PdfColors.red700
                                : PdfColors.black,
                          ),
                          _pdfCell(p['temp_field'], isBold: true),
                        ],
                      ),
                    );
                  }
                }
              });

              widgets.add(
                pw.Table(
                  border: pw.TableBorder.all(
                    width: 0.5,
                    color: PdfColors.grey400,
                  ),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(45),
                    1: const pw.FixedColumnWidth(35),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FixedColumnWidth(40),
                  },
                  children: tableRows,
                ),
              );
              widgets.add(pw.SizedBox(height: 15));
            });

            // --- SECCIÓN FINAL: AGRUPADOS ---
            widgets.add(pw.Divider(thickness: 1, color: PdfColors.grey300));
            widgets.add(pw.SizedBox(height: 10));

            // 1. DESCANSOS POR CATEGORÍA
            widgets.add(
              pw.Text(
                "EQUIPOS EN DESCANSO POR CATEGORÍA",
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 5));

            if (descansos.isEmpty) {
              widgets.add(
                pw.Text("Ninguno", style: const pw.TextStyle(fontSize: 8)),
              );
            } else {
              Map<String, List<String>> descansosPorCat = {};
              for (var t in descansos) {
                String cat = t['categoryName'] ?? "General";
                descansosPorCat.putIfAbsent(cat, () => []).add(t['name']);
              }
              descansosPorCat.forEach((cat, equipos) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: "$cat: ",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.TextSpan(
                            text: equipos.join(", "),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              });
            }

            widgets.add(pw.SizedBox(height: 15));

            // 2. JORNADAS DOBLES POR CATEGORÍA
            widgets.add(
              pw.Text(
                "EQUIPOS CON JORNADA DOBLE POR CATEGORÍA",
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red700,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 5));

            if (doblesData.isEmpty) {
              widgets.add(
                pw.Text("Ninguno", style: const pw.TextStyle(fontSize: 8)),
              );
            } else {
              Map<String, List<String>> doblesPorCat = {};
              for (var t in doblesData) {
                // Aquí doblesData ya trae la categoría o la buscamos en el lookup
                final team = _teamsLookup[t['_id']];
                String cat = (team?['category'] is Map)
                    ? team!['category']['name']
                    : (team?['category']?.toString() ?? "General");
                doblesPorCat
                    .putIfAbsent(cat, () => [])
                    .add("${t['name']} (${t['conteo']} juegos)");
              }
              doblesPorCat.forEach((cat, equipos) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: "$cat: ",
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red700,
                            ),
                          ),
                          pw.TextSpan(
                            text: equipos.join(", "),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              });
            }
            return widgets;
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name:
            "Rol_Jornada_${_currentJornada}_${widget.tournamentName.replaceAll(' ', '_')}",
      );
    } catch (e) {
      debugPrint("Error exportando PDF: $e");
    }
  }

  // Helper para celdas de texto en PDF
  pw.Widget _pdfCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    PdfColor? textColor,
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: (isHeader || isBold)
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          color: textColor ?? PdfColors.black,
        ),
        textAlign: align,
      ),
    );
  }

  /// Agrega una hora extra al final del día
  void _addSlotAtEnd(DayConfig config) {
    setState(() {
      DateTime last = config.timeSlots.isEmpty
          ? DateTime(config.date.year, config.date.month, config.date.day, 8, 0)
          : config.timeSlots.last;

      config.timeSlots.add(last.add(Duration(minutes: _slotDurationMinutes)));
    });
  }

  /// Crea un evento especial (Inauguración) en un hueco
  void _createSpecialEvent(DateTime start, DateTime end) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          "Evento Especial",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Espacio disponible: ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}",
            ),
            SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Nombre del Evento (ej. Inauguración)",
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  String key = start.toIso8601String();
                  _specialEvents[key] = SpecialEvent(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    start: start,
                    end: end,
                    title: controller.text,
                  );
                });
              }
              Navigator.pop(ctx);
            },
            child: Text("Crear"),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  //  VALIDACIONES Y REGLAS (EL PORTERO)
  // ===========================================================================

  // ===========================================================================
  //  CEREBRO DE VALIDACIONES DEL TABLERO (SEMI-AUTOMÁTICO)
  // ===========================================================================

  String? _validateAssignment(
    Map<String, dynamic> match,
    DateTime slotTime,
    int fieldIdx,
  ) {
    return _getMatchConflictError(match, simulatedTime: slotTime);
  }

  String? _getMatchConflictError(
    Map<String, dynamic> match, {
    DateTime? simulatedTime,
  }) {
    DateTime? slotTime =
        simulatedTime ??
        (match['assignedTime'] != null
            ? DateTime.parse(match['assignedTime'])
            : null);
    if (slotTime == null) return null;

    String currentMatchId = match['matchId'];
    final home = _teamsLookup[match['homeId']];
    final away = _teamsLookup[match['awayId']];
    final homeName = home?['name'] ?? "Local";
    final awayName = away?['name'] ?? "Visita";

    // 1. REGLA ESTRICTA: DESCANSOS (BYES)
    if (_checkIfHasBye(home)) return "🛑 DESCANSO (BYE): $homeName";
    if (_checkIfHasBye(away)) return "🛑 DESCANSO (BYE): $awayName";

    // 2. REGLA ESTRICTA: FORÁNEOS NO VIAJAN
    if (!_checkIfForeignerCanPlay(home))
      return "✈️ NO VIAJA J$_currentJornada: $homeName";
    if (!_checkIfForeignerCanPlay(away))
      return "✈️ NO VIAJA J$_currentJornada: $awayName";

    // 3. REGLA ESTRICTA: RESTRICCIONES DE HORARIO (Bloqueos)
    if (_checkTimeRestriction(home, slotTime))
      return "⏰ HORARIO BLOQUEADO: $homeName";
    if (_checkTimeRestriction(away, slotTime))
      return "⏰ HORARIO BLOQUEADO: $awayName";

    // 4. REGLA ESTRICTA: EMPALMES Y CONFLICTOS DE COACH EN LA GRILLA
    String timeIso = slotTime.toIso8601String();
    Set<String> homeConflicts = _getConflictIds(home);
    Set<String> awayConflicts = _getConflictIds(away);

    for (var entry in _gridAssignments.entries) {
      if (entry.key.startsWith(timeIso) && entry.value != currentMatchId) {
        String otherMatchId = entry.value;
        var otherMatch = _allMatches.firstWhere(
          (m) => m['matchId'] == otherMatchId,
          orElse: () => {},
        );

        if (otherMatch.isNotEmpty) {
          String oHomeId = otherMatch['homeId'];
          String oAwayId = otherMatch['awayId'];

          // A. Empalme: El mismo equipo ya tiene otro partido a esta hora
          if (match['homeId'] == oHomeId || match['homeId'] == oAwayId)
            return "⚠️ EMPALME EQUIPO: $homeName";
          if (match['awayId'] == oHomeId || match['awayId'] == oAwayId)
            return "⚠️ EMPALME EQUIPO: $awayName";

          // B. Conflicto: Coach compartiendo categoría
          if (homeConflicts.contains(oHomeId) ||
              homeConflicts.contains(oAwayId))
            return "👥 EMPALME COACH: $homeName";
          if (awayConflicts.contains(oHomeId) ||
              awayConflicts.contains(oAwayId))
            return "👥 EMPALME COACH: $awayName";
        }
      }
    }

    // 5. ADVERTENCIAS VISUALES: PREFERENCIAS DE HORARIO (Lo asignaste en una hora que no es su favorita)
    if (_hasMissedPreference(home, slotTime))
      return "⭐ FUERA DE PREFERENCIA: $homeName";
    if (_hasMissedPreference(away, slotTime))
      return "⭐ FUERA DE PREFERENCIA: $awayName";

    return null; // El horario es perfecto y no rompe ninguna regla
  }

  // Devuelve TRUE si un equipo (o el coach) ya está asignado a esa hora
  bool _hasConflictInGrid(
    String teamId,
    DateTime slotTime, {
    String? excludeMatchId,
  }) {
    final team = _teamsLookup[teamId];
    Set<String> conflictIds = _getConflictIds(team);
    conflictIds.add(teamId); // Se incluye a sí mismo en la lista de conflictos

    String timeIso = slotTime.toIso8601String();

    for (var entry in _gridAssignments.entries) {
      if (entry.key.startsWith(timeIso) && entry.value != excludeMatchId) {
        String otherMatchId = entry.value;
        var otherMatch = _allMatches.firstWhere(
          (m) => m['matchId'] == otherMatchId,
          orElse: () => {},
        );

        if (otherMatch.isNotEmpty) {
          if (conflictIds.contains(otherMatch['homeId']) ||
              conflictIds.contains(otherMatch['awayId'])) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // --- HELPERS DE LECTURA DEL JSON ---

  bool _checkIfHasBye(Map<String, dynamic>? team) {
    if (team == null || team['constraints'] == null) return false;
    List byes = team['constraints']['byeJornadas'] ?? [];
    return byes.map((e) => e.toString()).contains(_currentJornada.toString());
  }

  bool _checkIfForeignerCanPlay(Map<String, dynamic>? team) {
    if (team == null || team['constraints'] == null) return true;
    if (team['constraints']['isForeign'] != true) return true;
    List allowed = team['constraints']['foreignAvailableJornadas'] ?? [];
    return allowed
        .map((e) => e.toString())
        .contains(_currentJornada.toString());
  }

  Set<String> _getConflictIds(Map<String, dynamic>? team) {
    Set<String> ids = {};
    if (team == null || team['constraints'] == null) return ids;
    List conflicts = team['constraints']['conflictTeams'] ?? [];
    for (var c in conflicts) {
      if (c['teamId'] != null) ids.add(c['teamId'].toString());
    }
    return ids;
  }

  String _normalizeDay(String day) {
    return day
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .trim();
  }

  int _parseTimeSafe(dynamic t) {
    if (t == null || t.toString().isEmpty) return 0;
    var p = t.toString().split(':');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _checkTimeRestriction(Map<String, dynamic>? team, DateTime time) {
    if (team == null || team['constraints'] == null) return false;
    List restrictions = team['constraints']['timeRestrictions'] ?? [];
    if (restrictions.isEmpty) return false;

    String dayName = _normalizeDay(DateFormat('EEEE', 'es').format(time));
    int minutes = time.hour * 60 + time.minute;

    for (var res in restrictions) {
      if (_normalizeDay(res['day']) == dayName) {
        List ranges = res['ranges'] ?? [];
        if (ranges.isEmpty) return true; // Todo el día bloqueado
        for (var range in ranges) {
          int start = _parseTimeSafe(range['start']);
          int end = _parseTimeSafe(range['end']);
          if (minutes >= start && minutes < end) return true;
        }
      }
    }
    return false;
  }

  bool _hasMissedPreference(Map<String, dynamic>? team, DateTime time) {
    if (team == null || team['constraints'] == null) return false;
    List preferences = team['constraints']['timePreferences'] ?? [];
    if (preferences.isEmpty)
      return false; // Si no pidió preferencia, cualquier hora es buena

    String dayName = _normalizeDay(DateFormat('EEEE', 'es').format(time));
    int minutes = time.hour * 60 + time.minute;
    bool matchedPreference = false;

    for (var pref in preferences) {
      if (_normalizeDay(pref['day']) == dayName) {
        List ranges = pref['ranges'] ?? [];
        if (ranges.isEmpty) {
          matchedPreference = true; // Todo el día le gusta
          break;
        }
        for (var range in ranges) {
          int start = _parseTimeSafe(range['start']);
          int end = _parseTimeSafe(range['end']);
          if (minutes >= start && minutes <= end) {
            matchedPreference = true;
            break;
          }
        }
      }
    }
    return !matchedPreference; // Devuelve TRUE (Error) si la hora no coincide con lo que pidió
  }

  // ===========================================================================
  //  INTERACCIÓN UI
  // ===========================================================================

  void _onMatchListClick(String matchId) {
    setState(() {
      _selectedMatchId = (_selectedMatchId == matchId) ? null : matchId;
    });

    // NUEVO: Si estamos en móvil y seleccionamos un partido, ocultar el cajón
    if (_selectedMatchId != null && MediaQuery.of(context).size.width <= 900) {
      _sheetController.animateTo(
        0.08, // Colapsar
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _esJuegoDoble(String teamId) {
    int count = 0;
    for (var m in _allMatches) {
      if (m['homeId'] == teamId || m['awayId'] == teamId) count++;
    }
    return count > 1;
  }

  void _onGridSlotClick(DateTime slotTime, int fieldIdx) {
    String key = "${slotTime.toIso8601String()}_$fieldIdx";

    // CASO A: ASIGNAR (Ya traigo un partido seleccionado "en la mano")
    if (_selectedMatchId != null) {
      if (_gridAssignments.containsKey(key)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Espacio ocupado"),
            backgroundColor: _redError,
          ),
        );
        return;
      }

      final match = _allMatches.firstWhere(
        (m) => m['matchId'] == _selectedMatchId,
      );

      // Intentamos asignar (sin bloqueo, solo notificación si hay error)
      _executeAssignment(match, slotTime, fieldIdx, key);

      // Validamos POST-asignación para avisar al usuario si rompió una regla
      String? error = _validateAssignment(match, slotTime, fieldIdx);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ Asignado con conflicto: $error"),
            backgroundColor: Colors.orange,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
    // CASO B: LEVANTAR / MOVER (No traigo nada, clic en uno asignado)
    else if (_gridAssignments.containsKey(key)) {
      String matchId = _gridAssignments[key]!;

      setState(() {
        // 1. Quitar de la grilla (Liberar el espacio visualmente)
        _gridAssignments.remove(key);

        // 2. Limpiar datos del partido (Técnicamente regresa a la lista de pendientes)
        int idx = _allMatches.indexWhere((m) => m['matchId'] == matchId);
        if (idx != -1) {
          _allMatches[idx]['assignedTime'] = null;
          _allMatches[idx]['assignedField'] = null;
        }

        // 3. Auto-seleccionar ("Tomarlo en la mano")
        _selectedMatchId = matchId;
      });
    }
  }

  void _executeAssignment(
    Map<String, dynamic> match,
    DateTime time,
    int fieldIdx,
    String key,
  ) {
    setState(() {
      _gridAssignments.removeWhere((k, v) => v == match['matchId']);
      _gridAssignments[key] = match['matchId'];
      int idx = _allMatches.indexOf(match);
      _allMatches[idx]['assignedTime'] = time.toIso8601String();
      _allMatches[idx]['assignedField'] = "Campo ${fieldIdx + 1}";
      _selectedMatchId = null;
    });
  }

  void _showAssignedOptions(String matchId, String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.swap_horiz, color: _accentColor),
              title: Text("Mover (Tomar para reubicar)"),
              onTap: () {
                setState(() {
                  _gridAssignments.remove(key);
                  int idx = _allMatches.indexWhere(
                    (m) => m['matchId'] == matchId,
                  );
                  _allMatches[idx]['assignedTime'] = null;
                  _allMatches[idx]['assignedField'] = null;
                  _selectedMatchId = matchId;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.close, color: _redError),
              title: Text("Desasignar"),
              onTap: () {
                setState(() {
                  _gridAssignments.remove(key);
                  int idx = _allMatches.indexWhere(
                    (m) => m['matchId'] == matchId,
                  );
                  _allMatches[idx]['assignedTime'] = null;
                  _allMatches[idx]['assignedField'] = null;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  //  SISTEMA DE DESHACER (UNDO)
  // ===========================================================================
  void _undoLastBatchAssignment() {
    if (_lastAssignedBatchKeys.isEmpty) return;

    setState(() {
      for (String key in _lastAssignedBatchKeys) {
        String? matchId = _gridAssignments.remove(key);
        if (matchId != null) {
          int idx = _allMatches.indexWhere((m) => m['matchId'] == matchId);
          if (idx != -1) {
            _allMatches[idx]['assignedTime'] = null;
            _allMatches[idx]['assignedField'] = null;
          }
        }
      }
      _lastAssignedBatchKeys.clear();
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🔄 Asignación automática deshecha."),
        backgroundColor: Colors.blueGrey,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- AUTO ASIGNACIÓN FILTRADA ---

  // ===========================================================================
  //  OPCIÓN 1: AUTO-ASIGNAR LISTA (PUSH)
  // ===========================================================================
  void _runAutoScheduleForFilteredList(List<Map<String, dynamic>> matches) {
    List<Map<String, dynamic>> slots = [];
    for (var d in _daysConfig) {
      if (_activeFilter == 'viernes' && d.date.weekday != DateTime.friday)
        continue;
      if (_activeFilter == 'sabado' && d.date.weekday != DateTime.saturday)
        continue;
      if (_activeFilter == 'domingo' && d.date.weekday != DateTime.sunday)
        continue;

      for (var t in d.timeSlots) {
        for (int f = 0; f < d.fieldCount; f++) {
          slots.add({'time': t, 'fieldIdx': f});
        }
      }
    }

    int count = 0;
    List<String> batchKeys = []; // Registramos lo que se asigne en este clic

    setState(() {
      for (var match in matches) {
        for (var slot in slots) {
          DateTime t = slot['time'];
          int f = slot['fieldIdx'];
          String key = "${t.toIso8601String()}_$f";

          if (!_gridAssignments.containsKey(key)) {
            // Si el cerebro dice que NO hay errores graves (ignoramos los warnings '⭐')
            String? error = _validateAssignment(match, t, f);
            if (error == null || error.startsWith("⭐")) {
              _gridAssignments[key] = match['matchId'];
              int idx = _allMatches.indexOf(match);
              _allMatches[idx]['assignedTime'] = t.toIso8601String();
              _allMatches[idx]['assignedField'] = "Campo ${f + 1}";

              batchKeys.add(key); // Guardar para el Undo
              count++;
              break;
            }
          }
        }
      }
    });

    if (count > 0) {
      _lastAssignedBatchKeys = batchKeys;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✨ $count partidos asignados automáticamente."),
          backgroundColor: _greenSuccess,
          duration: const Duration(
            seconds: 8,
          ), // Dura 8 segundos para dar tiempo a deshacer
          action: SnackBarAction(
            label: 'DESHACER',
            textColor: Colors.white,
            onPressed: _undoLastBatchAssignment,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No se encontró espacio libre que cumpla las reglas."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ===========================================================================
  //  OPCIÓN 2: RELLENADO INTELIGENTE DE HORA (PULL)
  // ===========================================================================
  void _showSmartFillDialog(DateTime slotTime, int fieldCount) {
    // Buscar qué categorías tienen partidos pendientes
    final pendingMatches = _allMatches
        .where((m) => !_gridAssignments.containsValue(m['matchId']))
        .toList();
    if (pendingMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay partidos pendientes.")),
      );
      return;
    }

    final cats = pendingMatches
        .map((m) => m['categoryName']?.toString() ?? "General")
        .toSet()
        .toList();
    cats.sort();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Rellenar ${DateFormat('HH:mm').format(slotTime)}",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: cats
              .map(
                (cat) => ListTile(
                  title: Text("Categoría $cat"),
                  trailing: const Icon(Icons.flash_on, color: Colors.amber),
                  onTap: () {
                    Navigator.pop(ctx);
                    _fillSlotWithCategory(slotTime, fieldCount, cat);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _fillSlotWithCategory(
    DateTime slotTime,
    int fieldCount,
    String category,
  ) {
    int count = 0;
    List<String> batchKeys = [];

    setState(() {
      // Tomamos solo los pendientes de esa categoría
      var pending = _allMatches
          .where(
            (m) =>
                !_gridAssignments.containsValue(m['matchId']) &&
                m['categoryName'] == category,
          )
          .toList();

      for (var match in pending) {
        // Intentar acomodarlo en los campos de esta hora específica
        for (int f = 0; f < fieldCount; f++) {
          String key = "${slotTime.toIso8601String()}_$f";
          if (!_gridAssignments.containsKey(key)) {
            String? error = _validateAssignment(match, slotTime, f);
            if (error == null || error.startsWith("⭐")) {
              _gridAssignments[key] = match['matchId'];
              int idx = _allMatches.indexOf(match);
              _allMatches[idx]['assignedTime'] = slotTime.toIso8601String();
              _allMatches[idx]['assignedField'] = "Campo ${f + 1}";

              batchKeys.add(key);
              count++;
              break; // Partido acomodado, pasar al siguiente
            }
          }
        }
      }
    });

    if (count > 0) {
      _lastAssignedBatchKeys = batchKeys;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "⚡ $count partidos de $category asignados a las ${DateFormat('HH:mm').format(slotTime)}.",
          ),
          backgroundColor: Colors.blue[700],
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'DESHACER',
            textColor: Colors.white,
            onPressed: _undoLastBatchAssignment,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se pudo acomodar ninguno por reglas o falta de campos.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _openConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _ConfigDialog(
        initialConfig: _daysConfig,
        onApply: (newConfig) {
          setState(() {
            _daysConfig = newConfig;
          });
        },
      ),
    );
  }

  // ===========================================================================
  //  UI BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgScaffold,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Punto de quiebre: Si la pantalla es ancha (Escritorio/Tablet)
        if (constraints.maxWidth > 900) {
          return _buildDesktopLayout();
        }
        // Si es estrecha (Celular)
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: _buildAppBar(isMobile: false),
      floatingActionButton: _buildFab(),
      body: Row(
        children: [
          // SIDEBAR
          Expanded(
            flex: 3,
            child: Container(
              color: _sidebarBg,
              child: Column(
                children: [
                  _buildFilterBar(),
                  Expanded(child: _buildMatchesList()),
                ],
              ),
            ),
          ),
          // CONTENT
          Expanded(
            flex: 9,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildAcademySummaryPanel(),
                  if (_daysConfig.isNotEmpty)
                    _buildAddDayButton(isBefore: true),
                  ..._daysConfig.map((c) => _buildDayTimeline(c)).toList(),
                  if (_daysConfig.isNotEmpty)
                    _buildAddDayButton(isBefore: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar({required bool isMobile}) {
    return AppBar(
      backgroundColor: _cardBg,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Editor de Horarios",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _textPrimary,
            ),
          ),
          Text(
            widget.tournamentName,
            style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bgScaffold,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _currentJornada,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _currentJornada = val);
                  _loadJornadaData();
                }
              },
              items: _availableJornadas
                  .map(
                    (j) =>
                        DropdownMenuItem(value: j, child: Text("Jornada $j")),
                  )
                  .toList(),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: _textPrimary),
          onPressed: _openConfigDialog,
        ),
        if (!isMobile) const SizedBox(width: 16),
        if (!isMobile)
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text("Guardar"),
            onPressed: guardarHorarios,
          ),
        if (isMobile)
          IconButton(
            icon: const Icon(Icons.save, color: _accentColor),
            onPressed: guardarHorarios,
          ),
      ],
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isFabOpen) ...[
          _buildFabAction(
            "Exportar PDF",
            Icons.picture_as_pdf,
            Colors.redAccent,
            exportarAPDF,
          ),
          const SizedBox(height: 16),
          _buildFabAction(
            "Publicar Partidos",
            Icons.cloud_upload,
            Colors.orange,
            crearPartidosParaGuardar,
          ),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          onPressed: () {
            setState(() {
              _isFabOpen = !_isFabOpen;
              if (_isFabOpen)
                _fabAnimationController.forward();
              else
                _fabAnimationController.reverse();
            });
          },
          backgroundColor: _accentColor,
          child: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _fabAnimationController,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  //  LAYOUT MÓVIL (AGENDA VERTICAL + CAJÓN FLOTANTE)
  // ===========================================================================

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: _bgScaffold,
      appBar: _buildAppBar(isMobile: true),
      floatingActionButton: _isFabOpen
          ? _buildFab()
          : null, // Ocultar el fab base si está cerrado para no estorbar el cajón
      body: Stack(
        children: [
          // CAPA 1: TABLERO VERTICAL
          Column(
            children: [
              // Filtros Horizontales Rápidos
              _buildMobileFilterBar(),

              // Banner de "Partido Seleccionado en mano"
              if (_selectedMatchId != null) _buildMobileSelectionBanner(),

              // Tablero de Agenda
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 120,
                  ), // Bottom padding para el cajón
                  child: Column(
                    children: [
                      if (_selectedAcademyFilter != 'Todas')
                        _buildAcademySummaryPanel(),
                      if (_daysConfig.isNotEmpty)
                        _buildAddDayButton(isBefore: true),
                      ..._daysConfig
                          .map((c) => _buildMobileDayTimeline(c))
                          .toList(),
                      if (_daysConfig.isNotEmpty)
                        _buildAddDayButton(isBefore: false),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // CAPA 2: CAJÓN FLOTANTE DE PENDIENTES
          _buildMobileBottomSheet(),

          // Mini Fab para abrir menú de opciones
          if (!_isFabOpen)
            Positioned(
              right: 16,
              bottom: 80, // Arriba del cajón colapsado
              child: FloatingActionButton(
                mini: true,
                onPressed: () => setState(() {
                  _isFabOpen = true;
                  _fabAnimationController.forward();
                }),
                backgroundColor: _accentColor,
                child: const Icon(Icons.menu),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterBar() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Dropdown de Academia Compacto
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _availableAcademies.contains(_selectedAcademyFilter)
                      ? _selectedAcademyFilter
                      : 'Todas',
                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: (val) =>
                      setState(() => _selectedAcademyFilter = val!),
                  items: _availableAcademies
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            a.length > 15 ? "${a.substring(0, 15)}..." : a,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Dropdown Categoría
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _availableCategories.contains(_selectedCategoryFilter)
                      ? _selectedCategoryFilter
                      : 'Todas',
                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: (val) =>
                      setState(() => _selectedCategoryFilter = val!),
                  items: _availableCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const VerticalDivider(width: 10, thickness: 1),
            // Chips
            _buildFilterChip("Todos", "todos"),
            const SizedBox(width: 4),
            _buildFilterChip("Con Problemas", "con_restricciones"),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSelectionBanner() {
    final match = _allMatches.firstWhere(
      (m) => m['matchId'] == _selectedMatchId,
      orElse: () => {},
    );
    if (match.isEmpty) return const SizedBox();

    final home = _teamsLookup[match['homeId']];
    final away = _teamsLookup[match['awayId']];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.indigo.shade50,
      child: Row(
        children: [
          const Icon(Icons.touch_app, color: Colors.indigo, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Selecciona un espacio en el tablero para:",
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.indigo),
                ),
                Text(
                  "${home?['name']} vs ${away?['name']}",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[900],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => setState(() => _selectedMatchId = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDayTimeline(DayConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            DateFormat('EEEE d MMMM', 'es').format(config.date).toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _textPrimary,
            ),
          ),
        ),
        // Horas hacia abajo
        ...config.timeSlots.asMap().entries.map((entry) {
          int slotIndex = entry.key;
          DateTime time = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera de la Hora
                // Cabecera de la Hora
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      // --- NUEVO: Toque para editar la hora ---
                      InkWell(
                        onTap: () async {
                          TimeOfDay? t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(time),
                          );
                          if (t != null) _updateSlotTime(config, slotIndex, t);
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: _accentColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('HH:mm').format(time),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _accentColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit,
                              size: 12,
                              color: _accentColor.withAlpha(150),
                            ), // Ícono de edición
                          ],
                        ),
                      ),

                      // --- NUEVO: Botón para borrar el bloque de hora (si está vacío) ---
                      if (!_gridAssignments.keys.any(
                        (key) => key.startsWith(time.toIso8601String()),
                      ))
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.cancel,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            setState(() {
                              config.timeSlots.removeAt(slotIndex);
                            });
                          },
                        ),

                      const Spacer(),

                      // Botón Llenar Mágico
                      InkWell(
                        onTap: () =>
                            _showSmartFillDialog(time, config.fieldCount),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.flash_on,
                                size: 12,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Llenar",
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Lista de Campos Vertical
                ...List.generate(config.fieldCount, (fieldIdx) {
                  String key = "${time.toIso8601String()}_$fieldIdx";
                  String? matchId = _gridAssignments[key];
                  bool isOccupied = matchId != null;

                  return InkWell(
                    onTap: () => _onGridSlotClick(time, fieldIdx),
                    onLongPress: isOccupied
                        ? () => _showAssignedOptions(matchId, key)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: fieldIdx == config.fieldCount - 1
                                ? Colors.transparent
                                : Colors.grey[100]!,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          // Insignia del Campo
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${fieldIdx + 1}",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Contenido (Partido o Hueco)
                          Expanded(
                            child: isOccupied
                                ? _buildAssignedCell(
                                    matchId,
                                  ) // Reusa tu misma tarjeta, se expandirá a lo ancho!
                                : _buildMobileEmptySlot(time, fieldIdx),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildMobileEmptySlot(DateTime time, int fieldIdx) {
    bool hasMatchInHand = _selectedMatchId != null;
    String? conflictError;

    if (hasMatchInHand) {
      final match = _allMatches.firstWhere(
        (m) => m['matchId'] == _selectedMatchId,
        orElse: () => {},
      );
      conflictError = _validateAssignment(match, time, fieldIdx);
    }

    if (hasMatchInHand && conflictError == null) {
      return Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(20),
          border: Border.all(color: Colors.blue.withAlpha(50)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Text(
            "Toca para soltar aquí",
            style: TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      );
    } else if (hasMatchInHand && conflictError != null) {
      return Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(10),
          border: Border.all(color: Colors.red.withAlpha(50)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            conflictError,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }

    return Container(
      height: 45,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[200]!, style: BorderStyle.none),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          "Disponible",
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildMobileBottomSheet() {
    final unassignedCount = _allMatches
        .where((m) => !_gridAssignments.containsValue(m['matchId']))
        .length;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.08, // Colapsado muestra solo el header
      minChildSize: 0.08,
      maxChildSize: 0.85, // Expande casi hasta arriba
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 15,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Grab Handle y Header
              GestureDetector(
                onTap: () {
                  if (_sheetController.size < 0.5)
                    _sheetController.animateTo(
                      0.85,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  else
                    _sheetController.animateTo(
                      0.08,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 20,
                  ),
                  color: Colors
                      .transparent, // Para que el tap funcione en toda la barra
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _redError,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "$unassignedCount",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Pendientes (Desliza)",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Botón de Varita Mágica Móvil
                      IconButton(
                        icon: const Icon(
                          Icons.auto_awesome,
                          color: _accentColor,
                        ),
                        onPressed: () {
                          // Llama a la auto-asignación con los filtros actuales
                          final pending = _allMatches
                              .where(
                                (m) => !_gridAssignments.containsValue(
                                  m['matchId'],
                                ),
                              )
                              .toList();
                          _runAutoScheduleForFilteredList(pending);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Lista de Partidos Scrollable
              Expanded(
                child: Container(
                  color: _bgScaffold,
                  // Eliminamos el ListView extra que escondía la lista
                  child: _buildMatchesList(scrollController: scrollController),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- SIDEBAR WIDGETS ---

  Widget _buildFilterBar() {
    final int totalMatches = _allMatches.length;
    final int assignedCount = _gridAssignments.length;
    final int pendingCount = totalMatches - assignedCount;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel de Estadísticas (Contadores)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCounterStat("Totales", totalMatches, Colors.grey),
              _buildCounterStat("Asignados", assignedCount, _greenSuccess),
              _buildCounterStat("Pendientes", pendingCount, _redError),
            ],
          ),
          const Divider(height: 20),

          // Filtros de Día / Especiales (Chips)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip("Todos", "todos"),
                const SizedBox(width: 4),
                _buildFilterChip("Foráneos", "foraneos"),
                const SizedBox(width: 4),
                _buildFilterChip("Viernes", "viernes"),
                const SizedBox(width: 4),
                _buildFilterChip("Sábado", "sabado"),
                const SizedBox(width: 4),
                _buildFilterChip("Domingo", "domingo"),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Filtros por condiciones (alineados con tournament_detail_screen)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip("Con condiciones", "con_restricciones"),
                const SizedBox(width: 4),
                _buildFilterChip("Restricción horaria", "restriccion_horaria"),
                const SizedBox(width: 4),
                _buildFilterChip("Bye J$_currentJornada", "bye"),
                const SizedBox(width: 4),
                _buildFilterChip("Empalmes", "empalmes"),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // SELECTORES DROPDOWN (Cambiados a Columna para evitar el error de ancho)
          // Usamos una columna para que cada filtro ocupe todo el ancho disponible del sidebar
          Column(
            children: [
              // Filtro Categoría
              DropdownButtonFormField<String>(
                isExpanded: true, // Importante para que el texto no se corte
                value: _availableCategories.contains(_selectedCategoryFilter)
                    ? _selectedCategoryFilter
                    : 'Todas',
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(),
                  labelText: "Filtrar por Categoría",
                  labelStyle: TextStyle(fontSize: 11),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black),
                items: _availableCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) =>
                    setState(() => _selectedCategoryFilter = val!),
              ),
              const SizedBox(height: 10),

              // Filtro Academia
              DropdownButtonFormField<String>(
                isExpanded: true, // Importante para que el texto no se corte
                value: _availableAcademies.contains(_selectedAcademyFilter)
                    ? _selectedAcademyFilter
                    : 'Todas',
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(),
                  labelText: "Filtrar por Academia",
                  labelStyle: TextStyle(fontSize: 11),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black),
                items: _availableAcademies
                    .map(
                      (a) => DropdownMenuItem(
                        value: a,
                        child: Text(a, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) =>
                    setState(() => _selectedAcademyFilter = val!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounterStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: _textSecondary),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    bool selected = _activeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) => setState(() => _activeFilter = v ? value : 'todos'),
      selectedColor: _accentColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black,
        fontSize: 11,
      ),
      showCheckmark: false,
    );
  }

  // --- Filtros por condiciones de equipo (ver tournament_detail_screen + TeamConstraintsModal) ---
  // Estructura team['constraints']: isForeign, acceptDoubleHeader, foreignAvailableJornadas,
  // byeJornadas, timePreferences, timeRestrictions, conflictTeams. Usados para asignación y filtros.

  bool _teamPrefers(Map<String, dynamic>? team, String day) {
    List prefs = team?['constraints']?['timePreferences'] ?? [];
    for (var p in prefs) if (p['day'] == day) return true;
    return false;
  }

  /// Equipo con restricciones de horario (no puede jugar en ciertos días/horas).
  bool _teamHasTimeRestriction(Map<String, dynamic>? team) {
    if (team == null) return false;
    List r = team['constraints']?['timeRestrictions'] ?? [];
    return r.isNotEmpty;
  }

  /// Equipo que pidió bye en la jornada actual.
  bool _teamHasByeThisRound(Map<String, dynamic>? team) {
    return _checkIfHasBye(team); // <--- Actualizado para usar el nuevo motor
  }

  /// Equipo con empalmes (jugadores compartidos con otros equipos).
  bool _teamHasConflictTeams(Map<String, dynamic>? team) {
    if (team == null) return false;
    List c = team['constraints']?['conflictTeams'] ?? [];
    return c.isNotEmpty;
  }

  /// Equipo con al menos una condición/restricción configurada.
  bool _teamHasAnyConstraint(Map<String, dynamic>? team) {
    if (team == null) return false;
    final c = team['constraints'];
    if (c == null || c is! Map || c.isEmpty) return false;
    if (c['isForeign'] == true) return true;
    if ((c['byeJornadas'] as List?)?.isNotEmpty == true) return true;
    if ((c['timeRestrictions'] as List?)?.isNotEmpty == true) return true;
    if ((c['timePreferences'] as List?)?.isNotEmpty == true) return true;
    if ((c['conflictTeams'] as List?)?.isNotEmpty == true) return true;
    if ((c['foreignAvailableJornadas'] as List?)?.isNotEmpty == true)
      return true;
    return false;
  }

  // ===========================================================================
  //  MODO ENFOQUE: RESUMEN DE ACADEMIA
  // ===========================================================================

  Widget _buildAcademySummaryPanel() {
    if (_selectedAcademyFilter == 'Todas') return const SizedBox();

    // 1. Recopilar los partidos de esta academia que YA están asignados en el tablero
    List<Map<String, dynamic>> academyMatches = [];

    _gridAssignments.forEach((key, matchId) {
      final match = _allMatches.firstWhere(
        (m) => m['matchId'] == matchId,
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        final home = _teamsLookup[match['homeId']];
        final away = _teamsLookup[match['awayId']];

        String hAcad = home?['academy']?['name']?.toString() ?? "Independiente";
        String aAcad = away?['academy']?['name']?.toString() ?? "Independiente";

        if (hAcad == _selectedAcademyFilter ||
            aAcad == _selectedAcademyFilter) {
          academyMatches.add({
            'match': match,
            'time': DateTime.parse(
              key.split('_')[0],
            ), // Extraemos la hora de la llave de la grilla
          });
        }
      }
    });

    if (academyMatches.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withAlpha(50)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 12),
            Text(
              "Modo Enfoque: $_selectedAcademyFilter (Sin partidos asignados en el tablero aún)",
              style: GoogleFonts.inter(
                color: Colors.blue[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // 2. Ordenar cronológicamente
    academyMatches.sort(
      (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime),
    );

    DateTime firstGame = academyMatches.first['time'];
    DateTime lastGame = academyMatches.last['time'];

    // 3. Calcular el mayor tiempo muerto (Hueco)
    Duration maxGap = Duration.zero;
    for (int i = 0; i < academyMatches.length - 1; i++) {
      // Suponemos que cada partido dura lo que dura tu bloque (_slotDurationMinutes)
      DateTime endCurrent = (academyMatches[i]['time'] as DateTime).add(
        const Duration(minutes: _slotDurationMinutes),
      );
      DateTime startNext = academyMatches[i + 1]['time'];

      if (startNext.isAfter(endCurrent)) {
        Duration gap = startNext.difference(endCurrent);
        if (gap > maxGap) maxGap = gap;
      }
    }

    // 4. Determinar color de alerta según el tiempo muerto
    int gapHours = maxGap.inHours;
    Color gapColor = Colors.green;
    if (gapHours >= 3)
      gapColor = Colors.red;
    else if (gapHours >= 2)
      gapColor = Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withAlpha(30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accentColor.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.center_focus_strong, color: _accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Radiografía: $_selectedAcademyFilter",
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildMiniStat(
                      "1er Juego",
                      DateFormat('HH:mm').format(firstGame),
                      Colors.blueGrey,
                    ),
                    const SizedBox(width: 16),
                    _buildMiniStat(
                      "Último Juego",
                      DateFormat('HH:mm').format(lastGame),
                      Colors.blueGrey,
                    ),
                    const SizedBox(width: 16),
                    _buildMiniStat(
                      "Mayor espera",
                      maxGap.inMinutes == 0
                          ? "Continua"
                          : "${gapHours}h ${maxGap.inMinutes.remainder(60)}m",
                      gapColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: _textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // --- TIMELINE WIDGETS ---

  Widget _buildDayTimeline(DayConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: // En _buildDayTimeline:
          Text(
            DateFormat(
              'EEEE d MMMM',
              'es',
            ).format(config.date).toUpperCase(), // <--- Agrega 'es'
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 80,
                    padding: EdgeInsets.all(12),
                    alignment: Alignment.center,
                    child: Text(
                      "HORA",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  ...List.generate(
                    config.fieldCount,
                    (i) => Expanded(
                      child: Center(
                        child: Text(
                          "CAMPO ${i + 1}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 1),
              // Time Rows
              ..._buildTimeRows(config),
            ],
          ),
        ),
        SizedBox(height: 40),
      ],
    );
  }

  List<Widget> _buildTimeRows(DayConfig config) {
    List<Widget> rows = [];

    // Si hay un partido seleccionado, lo buscamos una sola vez para no buscarlo en cada celda
    Map<String, dynamic>? selectedMatch;
    if (_selectedMatchId != null) {
      selectedMatch = _allMatches.firstWhere(
        (m) => m['matchId'] == _selectedMatchId,
        orElse: () => {},
      );
    }

    // --- 1. BOTÓN SUPERIOR: AGREGAR HORA ANTES ---
    rows.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
        child: InkWell(
          onTap: () {
            setState(() {
              if (config.timeSlots.isEmpty) return;
              DateTime first = config.timeSlots.first;
              // Insertamos al inicio restando exactamente 1 bloque de tiempo
              config.timeSlots.insert(
                0,
                first.subtract(const Duration(minutes: _slotDurationMinutes)),
              );
            });
          },
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withAlpha(50)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  "Agregar bloque antes",
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // --- 2. RENDERIZADO DE LAS FILAS DE HORARIOS ---
    for (int i = 0; i < config.timeSlots.length; i++) {
      DateTime currentSlot = config.timeSlots[i];
      String slotIso = currentSlot.toIso8601String();

      // Verificamos si este horario tiene algún partido asignado en cualquier campo
      bool hasAnyAssignment = _gridAssignments.keys.any(
        (key) => key.startsWith(slotIso),
      );

      // --- Lógica de GAPS (Huecos) ---
      if (i > 0) {
        DateTime prevEnd = config.timeSlots[i - 1].add(
          const Duration(minutes: _slotDurationMinutes),
        );
        if (currentSlot.isAfter(prevEnd)) {
          rows.add(_buildGapRow(prevEnd, currentSlot));
        }
      }

      rows.add(
        Container(
          height: 70,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              // Columna Hora (Izquierda)
              Container(
                width: 80,
                color: Colors.grey[50],
                child: Stack(
                  children: [
                    InkWell(
                      onTap: () async {
                        TimeOfDay? t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(currentSlot),
                        );
                        if (t != null) _updateSlotTime(config, i, t);
                      },
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('HH:mm').format(currentSlot),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.edit,
                                  size: 8,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                            // --- BOTÓN DE RELLENADO MÁGICO (Rayo) ---
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: () => _showSmartFillDialog(
                                currentSlot,
                                config.fieldCount,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.amber.withAlpha(100),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.flash_on,
                                      size: 10,
                                      color: Colors.orange,
                                    ),
                                    Text(
                                      "Llenar",
                                      style: GoogleFonts.inter(
                                        fontSize: 8,
                                        color: Colors.orange[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Botón para borrar el renglón (Solo si no hay partidos asignados)
                    if (!hasAnyAssignment)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              config.timeSlots.removeAt(i);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cancel,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),

              // Columnas de Campos (Celdas)
              ...List.generate(config.fieldCount, (fieldIdx) {
                String key = "${currentSlot.toIso8601String()}_$fieldIdx";
                String? matchId = _gridAssignments[key];
                bool isOccupied = matchId != null;

                Color cellBg = Colors.transparent;
                Widget? iconIndicator;

                // Si tengo un partido "en la mano" (_selectedMatchId)
                if (selectedMatch != null && selectedMatch.isNotEmpty) {
                  if (isOccupied) {
                    cellBg = Colors.grey.withAlpha(5);
                  } else {
                    String? conflictError = _validateAssignment(
                      selectedMatch,
                      currentSlot,
                      fieldIdx,
                    );

                    // Si no hay error, O si es solo una advertencia de horario preferido (⭐), pintamos azul (disponible)
                    if (conflictError == null ||
                        conflictError.startsWith("⭐")) {
                      cellBg = const Color.fromARGB(
                        255,
                        3,
                        122,
                        220,
                      ).withAlpha(20);
                      iconIndicator = Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.add_circle_outline,
                              color: Colors.grey,
                              size: 18,
                            ),
                            Text(
                              "Asignar",
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // CONFLICTO GRAVE
                      cellBg = Colors.red.withAlpha(5);
                      iconIndicator = const Center(
                        child: Icon(Icons.block, color: Colors.red, size: 16),
                      );
                    }
                  }
                }

                return Expanded(
                  child: InkWell(
                    onTap: () => _onGridSlotClick(currentSlot, fieldIdx),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cellBg,
                        border: Border.all(
                          color: Colors.grey.withAlpha(30),
                          width: 0.5,
                        ),
                      ),
                      child: isOccupied
                          ? _buildAssignedCell(matchId)
                          : iconIndicator,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }

    // --- 3. BOTÓN INFERIOR: AGREGAR HORA DESPUÉS ---
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
        child: InkWell(
          onTap: () => _addSlotAtEnd(config),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withAlpha(50)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  "Agregar bloque después",
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return rows;
  }

  // ... imports previos ...

  // [AGREGAR ESTO AL FINAL DEL ARCHIVO O JUNTO A TUS OTROS WIDGETS]

  // -----------------------------------------------------------------------------
  // REEMPLAZAR ESTOS DOS MÉTODOS EN TU CLASE _ScheduleEditorScreenState
  // -----------------------------------------------------------------------------

  // 1. SIDEBAR (Con Logo)
  Widget _buildMatchesList({ScrollController? scrollController}) {
    final unassigned = _allMatches.where((m) {
      // 1. Ocultar si ya está en el tablero
      if (_gridAssignments.containsValue(m['matchId'])) return false;

      final home = _teamsLookup[m['homeId']];
      final away = _teamsLookup[m['awayId']];

      // 2. FILTRO DE ACADEMIA (Nuevo)
      if (_selectedAcademyFilter != 'Todas') {
        final String homeAcad = home?['academy']?['name'] ?? "Independiente";
        final String awayAcad = away?['academy']?['name'] ?? "Independiente";
        if (homeAcad != _selectedAcademyFilter &&
            awayAcad != _selectedAcademyFilter) {
          return false;
        }
      }

      // 3. FILTRO DE CATEGORÍA
      if (_selectedCategoryFilter != 'Todas' &&
          m['categoryName'] != _selectedCategoryFilter) {
        return false;
      }

      // 4. FILTROS DE DÍA / ESPECIALES / CONDICIONES
      if (_activeFilter == 'todos') return true;

      if (_activeFilter == 'foraneos') {
        return (home?['constraints']?['isForeign'] == true) ||
            (away?['constraints']?['isForeign'] == true);
      }

      // Filtros por condiciones (restricciones definidas en tournament_detail)
      if (_activeFilter == 'con_restricciones') {
        return _teamHasAnyConstraint(home) || _teamHasAnyConstraint(away);
      }
      if (_activeFilter == 'restriccion_horaria') {
        return _teamHasTimeRestriction(home) || _teamHasTimeRestriction(away);
      }
      if (_activeFilter == 'bye') {
        return _teamHasByeThisRound(home) || _teamHasByeThisRound(away);
      }
      if (_activeFilter == 'empalmes') {
        return _teamHasConflictTeams(home) || _teamHasConflictTeams(away);
      }

      // Filtro por día preferido (Viernes, Sábado, Domingo)
      String day = _activeFilter[0].toUpperCase() + _activeFilter.substring(1);
      return _teamPrefers(home, day) || _teamPrefers(away, day);
    }).toList();

    return Column(
      children: [
        if (_activeFilter != 'todos' && unassigned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text("Auto-Asignar Lista"),
                onPressed: () => _runAutoScheduleForFilteredList(unassigned),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: scrollController, // <--- AGREGA ESTA LÍNEA
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            itemCount: unassigned.length,
            itemBuilder: (ctx, i) {
              final match = unassigned[i];
              bool isSelected = _selectedMatchId == match['matchId'];
              final home = _teamsLookup[match['homeId']];
              final away = _teamsLookup[match['awayId']];
              final String category =
                  match['categoryName']?.toString() ?? "N/A";

              Color catBg = _getUiColor(category, isBackground: true);
              Color catText = _getUiColor(category, isBackground: false);

              return GestureDetector(
                onTap: () => _onMatchListClick(match['matchId']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? _selectionColor : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.orange
                          : Colors.grey.withAlpha(20),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(5),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _SplitTeamName(
                          name: home?['name'] ?? "Local",
                          showLogo: true,
                          logoUrl: home?['logo'],
                          isDoubleHeader: _checkIfDoubleHeader(match['homeId']),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: catBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 7,
                              fontWeight: FontWeight.w900,
                              color: catText,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: _SplitTeamName(
                          name: away?['name'] ?? "Visita",
                          showLogo: true,
                          logoUrl: away?['logo'],
                          logoAtEnd: true,
                          isDoubleHeader: _checkIfDoubleHeader(match['awayId']),
                          crossAlign: CrossAxisAlignment.end,
                          textAlign: TextAlign.end,
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
    );
  }

  Widget _buildAddDayButton({required bool isBefore}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: OutlinedButton.icon(
        icon: Icon(isBefore ? Icons.first_page : Icons.last_page),
        label: Text(isBefore ? "Agregar Día Antes" : "Agregar Día Después"),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentColor,
          side: BorderSide(color: _accentColor.withAlpha(100)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        onPressed: () {
          setState(() {
            if (_daysConfig.isEmpty) return;

            // Tomamos como referencia el primer o último día del tablero
            DayConfig refConfig = isBefore
                ? _daysConfig.first
                : _daysConfig.last;
            DateTime newDate = isBefore
                ? refConfig.date.subtract(const Duration(days: 1))
                : refConfig.date.add(const Duration(days: 1));

            // Generamos los bloques estándar (ej. 8am a 2pm)
            List<DateTime> newSlots = [];
            for (int i = 0; i < 6; i++) {
              newSlots.add(
                DateTime(newDate.year, newDate.month, newDate.day, 8 + i, 0),
              );
            }

            DayConfig newConfig = DayConfig(
              date: newDate,
              timeSlots: newSlots,
              // ¡Mantiene exactamente la misma cantidad de campos que el día de referencia!
              fieldCount: refConfig.fieldCount,
            );

            if (isBefore) {
              _daysConfig.insert(0, newConfig);
            } else {
              _daysConfig.add(newConfig);
            }
          });
        },
      ),
    );
  }

  Widget _buildFabAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: _textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: label, // Importante para evitar errores de Hero
          onPressed: () {
            setState(() => _isFabOpen = false);
            _fabAnimationController.reverse();
            onTap();
          },
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildAssignedCell(String matchId) {
    // 1. Obtención del partido y sus datos
    final match = _allMatches.firstWhere(
      (m) => m['matchId'] == matchId,
      orElse: () => {},
    );

    if (match.isEmpty) return const SizedBox();

    final home = _teamsLookup[match['homeId']];
    final away = _teamsLookup[match['awayId']];
    final String category = match['categoryName']?.toString() ?? "N/A";

    // 2. Validación de conflictos (Recíproca)
    String? conflictError = _getMatchConflictError(match);
    bool hasIssue = conflictError != null;

    // Si empieza con la estrella de preferencia, es advertencia. Si no, es error grave.
    bool isWarning = hasIssue && conflictError.startsWith("⭐");

    // 3. Colores dinámicos (UI Helper)
    Color catBg = _getUiColor(category, isBackground: true);
    Color catText = _getUiColor(category, isBackground: false);

    // Colores de la alerta
    Color cellBg = hasIssue
        ? (isWarning ? const Color(0xFFFFF8E1) : const Color(0xFFFFEBEB))
        : Colors.white;

    Color alertColor = hasIssue
        ? (isWarning ? Colors.orange : _redError)
        : Colors.transparent;

    // =========================================================
    // LÓGICA DE OPACIDAD PARA "MODO ENFOQUE"
    // =========================================================
    bool isDimmed = false;
    if (_selectedAcademyFilter != 'Todas') {
      String hAcad = home?['academy']?['name']?.toString() ?? "Independiente";
      String aAcad = away?['academy']?['name']?.toString() ?? "Independiente";

      // Si ninguno de los dos equipos pertenece a la academia seleccionada, atenuamos la celda
      if (hAcad != _selectedAcademyFilter && aAcad != _selectedAcademyFilter) {
        isDimmed = true;
      }
    }

    Widget cellContent = Container(
      // Margen mínimo para no tapar los bordes de la cuadrícula del tablero
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: cellBg,
        borderRadius: BorderRadius.circular(4),
        // Borde exterior para definir la card dentro del slot
        border: Border.all(
          color: hasIssue ? alertColor : Colors.grey.withAlpha(10),
          width: hasIssue ? 1.5 : 0.5,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- COLUMNA 1: CATEGORÍA (Vertical y estrecha) ---
            Container(
              width: 22,
              decoration: BoxDecoration(
                color: catBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    category.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: catText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),

            // --- COLUMNA 2: CONTENIDO PRINCIPAL (Equipos y Errores) ---
            Expanded(
              child: Column(
                children: [
                  // BANDA DE ALERTA (ROJA O NARANJA Si existe)
                  if (hasIssue)
                    Container(
                      width: double.infinity,
                      color: alertColor,
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 2,
                      ),
                      child: Text(
                        conflictError.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // FILA LOCAL
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.centerLeft,
                      child: _SplitTeamName(
                        name: home?['name'] ?? "Local",
                        isDoubleHeader: _checkIfDoubleHeader(match['homeId']),
                        textColor: hasIssue && !isWarning
                            ? Colors.red.shade900
                            : _textPrimary,
                      ),
                    ),
                  ),

                  // DIVISIÓN SUTIL ENTRE EQUIPOS
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.grey.withAlpha(15),
                  ),

                  // FILA VISITA (Con efecto cebra muy suave)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(5), // Efecto cebra sutil
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: _SplitTeamName(
                        name: away?['name'] ?? "Visita",
                        isDoubleHeader: _checkIfDoubleHeader(match['awayId']),
                        textColor: hasIssue && !isWarning
                            ? Colors.red.shade900
                            : _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Retornamos el contenido con opacidad condicional si el filtro de academia está activo
    return isDimmed ? Opacity(opacity: 0.25, child: cellContent) : cellContent;
  }

  Widget _buildSummaryLists() {
    final descansos = _calcularEquiposEnDescanso();
    final dobles = _calcularEquiposJuegoDoble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // COLUMNA EQUIPOS EN DESCANSO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "EQUIPOS EN DESCANSO (${descansos.length})",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 8),
                ...descansos.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 6,
                          backgroundImage: NetworkImage(t['logo'] ?? ''),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t['name'],
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(),
          // COLUMNA JORNADA DOBLE
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "JORNADA DOBLE (${dobles.length})",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                ...dobles.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 6,
                          backgroundImage: NetworkImage(t['logo'] ?? ''),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "${t['name']} (x${t['conteo']})",
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
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
    );
  }

  Widget _buildGapRow(DateTime start, DateTime end) {
    String key = start.toIso8601String();
    SpecialEvent? event = _specialEvents[key];
    return InkWell(
      onTap: () => _createSpecialEvent(start, end),
      child: Container(
        height: 40,
        width: double.infinity,
        color: _orangeGap.withAlpha(10),
        child: Center(
          child: event != null
              ? Text(
                  event.title,
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  "Hueco Disponible (${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}) - Clic para agregar evento",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMatchCard(String matchId) {
    final match = _allMatches.firstWhere((m) => m['matchId'] == matchId);
    final home = _teamsLookup[match['homeId']];
    final away = _teamsLookup[match['awayId']];
    return Container(
      decoration: BoxDecoration(
        color: _accentColor.withAlpha(10),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: _accentColor, width: 3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            match['categoryName'] ?? "",
            style: TextStyle(fontSize: 8, color: _textSecondary),
          ),
          Text(
            "${home?['name']} vs ${away?['name']}",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _pushAssignmentsAfterChange(
    DayConfig config,
    int slotIndex,
    Duration difference,
  ) {
    // Recorremos los slots desde el final hasta el actual para evitar colisiones de llaves
    for (int i = config.timeSlots.length - 1; i >= slotIndex; i--) {
      DateTime oldSlotTime = config.timeSlots[i];
      DateTime newSlotTime = oldSlotTime.add(difference);

      // Movimiento físico de los partidos en la grilla para este bloque horario
      for (int f = 0; f < config.fieldCount; f++) {
        String oldKey = "${oldSlotTime.toIso8601String()}_$f";
        if (_gridAssignments.containsKey(oldKey)) {
          String matchId = _gridAssignments.remove(oldKey)!;
          String newKey = "${newSlotTime.toIso8601String()}_$f";
          _gridAssignments[newKey] = matchId;

          // Actualizamos el objeto match para que el guardado sea consistente
          int matchIdx = _allMatches.indexWhere((m) => m['matchId'] == matchId);
          if (matchIdx != -1) {
            _allMatches[matchIdx]['assignedTime'] = newSlotTime
                .toIso8601String();
          }
        }
      }
      // Actualizamos el objeto de configuración de tiempo
      config.timeSlots[i] = newSlotTime;
    }
  }

  Color _getUiColor(String? category, {bool isBackground = true}) {
    // 1. Si la categoría es nula o no existe en el mapa, damos un color por defecto
    if (category == null || !_categoryStyles.containsKey(category)) {
      return isBackground ? Colors.grey[300]! : Colors.black;
    }

    // 2. Obtenemos el estilo (PdfColor)
    final style = _categoryStyles[category]!;
    final pdfColor = isBackground ? style['bg'] : style['text'];

    // 3. Convertimos PdfColor a Color de Flutter
    // PdfColor almacena el color en formato 0xRRGGBB
    // Necesitamos convertirlo a 0xAARRGGBB para Flutter
    if (pdfColor == null) return Colors.transparent;

    // Obtenemos los componentes RGB
    final int r = (pdfColor.red * 255).toInt();
    final int g = (pdfColor.green * 255).toInt();
    final int b = (pdfColor.blue * 255).toInt();

    return Color.fromARGB(255, r, g, b);
  }
}

// =============================================================================
//  DIÁLOGO DE CONFIGURACIÓN
// =============================================================================

class _ConfigDialog extends StatefulWidget {
  final List<DayConfig> initialConfig;
  final ValueChanged<List<DayConfig>> onApply;

  const _ConfigDialog({required this.initialConfig, required this.onApply});

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late List<DayConfig> _localConfigs;

  @override
  void initState() {
    super.initState();
    _localConfigs = widget.initialConfig.map((e) => e.copy()).toList();
  }

  void _addDay() {
    setState(() {
      // Por defecto agrega mañana de 8 a 14
      final tomorrow = DateTime.now().add(Duration(days: 1));
      final date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

      // Generar slots por defecto
      List<DateTime> slots = [];
      for (int i = 0; i < 6; i++) {
        slots.add(DateTime(date.year, date.month, date.day, 8 + i, 0));
      }

      _localConfigs.add(DayConfig(date: date, timeSlots: slots, fieldCount: 3));
    });
  }

  Future<void> _pickDate(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _localConfigs[index].date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        // Mantener los horarios, solo cambiar la fecha base
        var oldConfig = _localConfigs[index];
        List<DateTime> newSlots = [];
        for (var slot in oldConfig.timeSlots) {
          newSlots.add(
            DateTime(
              picked.year,
              picked.month,
              picked.day,
              slot.hour,
              slot.minute,
            ),
          );
        }
        _localConfigs[index].date = picked;
        _localConfigs[index].timeSlots = newSlots;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey,
      child: Container(
        width: 600,
        height: 500,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Configuración de Jornada",
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: _localConfigs.length,
                separatorBuilder: (_, __) => SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final config = _localConfigs[i];
                  String timeRange = config.timeSlots.isNotEmpty
                      ? "${DateFormat('HH:mm').format(config.timeSlots.first)} - ${DateFormat('HH:mm').format(config.timeSlots.last.add(Duration(hours: 1)))}"
                      : "Sin horarios";

                  return Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              "Día ${i + 1}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.delete,
                                size: 18,
                                color: Colors.red,
                              ),
                              onPressed: () =>
                                  setState(() => _localConfigs.removeAt(i)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.calendar_today, size: 16),
                                label: Text(
                                  DateFormat('dd/MM/yyyy').format(config.date),
                                ),
                                onPressed: () => _pickDate(i),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              timeRange,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Text("Campos: "),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline),
                              onPressed: () => setState(() {
                                if (config.fieldCount > 1) config.fieldCount--;
                              }),
                            ),
                            Text(
                              "${config.fieldCount}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline),
                              onPressed: () =>
                                  setState(() => config.fieldCount++),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: Icon(Icons.add),
                  label: Text("Agregar Día"),
                  onPressed: _addDay,
                ),
                Spacer(),
                TextButton(
                  child: Text("Cancelar"),
                  onPressed: () => Navigator.pop(context),
                ),
                SizedBox(width: 8),
                FilledButton(
                  child: Text("Aplicar"),
                  onPressed: () {
                    widget.onApply(_localConfigs);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET HELPER PARA EL NOMBRE SPLIT
// -----------------------------------------------------------------------------
class _SplitTeamName extends StatelessWidget {
  final String name;
  final CrossAxisAlignment crossAlign;
  final TextAlign textAlign;
  final bool showLogo;
  final String? logoUrl;
  final Color textColor;
  final bool
  logoAtEnd; // Nuevo: Para poner el logo a la derecha en el equipo visita
  final bool isDoubleHeader; // <--- NUEVO

  const _SplitTeamName({
    required this.name,
    this.crossAlign = CrossAxisAlignment.start,
    this.textAlign = TextAlign.start,
    this.showLogo = false,
    this.logoUrl,
    this.textColor = const Color(0xFF1C1C1E),
    this.logoAtEnd = false,
    this.isDoubleHeader = false, // <--- POR DEFECTO FALSE
  });

  @override
  Widget build(BuildContext context) {
    List<String> words = name.trim().split(' ');
    final Color effectiveColor = isDoubleHeader ? Colors.red : textColor;

    // REGLA: Split si son más de 2 palabras O si la segunda palabra es un color específico
    bool isColorSuffix = false;
    if (words.length >= 2) {
      String secondWord = words[1].toLowerCase().replaceAll(
        RegExp(r'[^a-z]'),
        '',
      );
      if (['orange', 'blue', 'white'].contains(secondWord)) {
        isColorSuffix = true;
      }
    }

    bool shouldSplit = words.length > 2 || isColorSuffix;

    String mainText = shouldSplit ? words.first : name;
    String subText = shouldSplit ? words.sublist(1).join(' ') : "";

    Widget textBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAlign,
      children: [
        Text(
          mainText,
          textAlign: textAlign,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: effectiveColor, // <--- USAR COLOR EFECTIVO
            height: 1.0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (shouldSplit)
          Text(
            subText,
            textAlign: textAlign,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              fontSize: 9, // Pequeña y sutil
              color: effectiveColor,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    if (!showLogo) return textBlock;

    Widget logoWidget = CircleAvatar(
      radius: 12,
      backgroundColor: Colors.grey[200],
      backgroundImage: (logoUrl != null && logoUrl!.isNotEmpty)
          ? NetworkImage(logoUrl!)
          : null,
      child: (logoUrl == null || logoUrl!.isEmpty)
          ? const Icon(Icons.shield, size: 14, color: Colors.grey)
          : null,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: logoAtEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: logoAtEnd
          ? [Flexible(child: textBlock), const SizedBox(width: 6), logoWidget]
          : [logoWidget, const SizedBox(width: 6), Flexible(child: textBlock)],
    );
  }
}
