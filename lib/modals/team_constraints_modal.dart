import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// Asegúrate de importar tu modelo de usuario aquí
import 'package:admin_league/models/user_model.dart';

class TeamConstraintsModal extends StatefulWidget {
  final Map<String, dynamic> team;
  final List<dynamic> allTeams; // Lista completa para el buscador global
  final int totalJornadas; // Ej. 10
  final UserModel currentUser;
  final Function(Map<String, dynamic>) onSave;

  const TeamConstraintsModal({
    super.key,
    required this.team,
    required this.allTeams,
    required this.totalJornadas,
    required this.currentUser,
    required this.onSave,
  });

  @override
  State<TeamConstraintsModal> createState() => _TeamConstraintsModalState();
}

class _TeamConstraintsModalState extends State<TeamConstraintsModal> {
  // --- ESTADO DEL FORMULARIO ---
  bool _isForeign = false;
  bool _acceptDoubleHeader = false;
  List<int> _foreignAvailableJornadas = [];

  List<int> _byeJornadas = [];

  // Estructura: { 'day': 'Sábado', 'ranges': [{'start': '10:00', 'end': '12:00'}] }
  List<Map<String, dynamic>> _timePreferences = [];
  List<Map<String, dynamic>> _timeRestrictions = [];

  // Equipos con conflicto
  List<Map<String, dynamic>> _conflictTeams = [];

  // Buscador
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searchingExternal = false;

  final List<String> _days = ['Miércoles', 'Jueves', 'Viernes', 'Sábado'];

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    final data = widget.team['constraints'] ?? {};
    // Si no hay datos previos, iniciamos limpio
    if (data.isEmpty) return;

    setState(() {
      _isForeign = data['isForeign'] ?? false;
      _acceptDoubleHeader = data['acceptDoubleHeader'] ?? false;
      _foreignAvailableJornadas = List<int>.from(
        data['foreignAvailableJornadas'] ?? [],
      );
      _byeJornadas = List<int>.from(data['byeJornadas'] ?? []);

      // Casteo seguro de listas complejas
      _timePreferences =
          (data['timePreferences'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _timeRestrictions =
          (data['timeRestrictions'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _conflictTeams =
          (data['conflictTeams'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // HEADER FIJO
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.indigo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Condiciones: ${widget.team['name']}",
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // CONTENIDO SCROLLABLE
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. SECCIÓN FORÁNEO
                    _buildSectionTitle("Estatus del Equipo"),
                    SwitchListTile(
                      title: const Text("Es equipo Foráneo"),
                      subtitle: const Text(
                        "Habilita opciones de viajes y disponibilidad limitada.",
                      ),
                      value: _isForeign,
                      activeColor: Colors.indigo,
                      onChanged: (val) => setState(() => _isForeign = val),
                    ),
                    if (_isForeign) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              title: const Text("Acepta Dobles Jornadas"),
                              value: _acceptDoubleHeader,
                              onChanged: (val) =>
                                  setState(() => _acceptDoubleHeader = val!),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                            const Text(
                              "Jornadas Disponibles para jugar:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            _buildJornadaSelector(
                              _foreignAvailableJornadas,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(),

                    // 2. SOLICITUD DE BYE
                    _buildSectionTitle("Solicitud de Bye (Descanso)"),
                    const Text(
                      "Selecciona las jornadas donde NO pueden jugar:",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildJornadaSelector(_byeJornadas, color: Colors.orange),
                    const Divider(),

                    // 3. PREFERENCIAS DE HORARIO
                    _buildTimeSection(
                      title: "Preferencias de Juego",
                      subtitle:
                          "Días y horas preferidas. Si no agregas horas, se asume todo el día.",
                      dataList: _timePreferences,
                      color: Colors.blue,
                      icon: Icons.thumb_up_alt_outlined,
                    ),
                    const Divider(),

                    // 4. RESTRICCIONES DE HORARIO
                    _buildTimeSection(
                      title: "Restricciones (Imposible Jugar)",
                      subtitle:
                          "Días y horas imposibles. Si no agregas horas, se asume todo el día.",
                      dataList: _timeRestrictions,
                      color: Colors.red,
                      icon: Icons.block,
                    ),
                    const Divider(),

                    // 5. EMPALMES / CONFLICTOS
                    _buildSectionTitle(
                      "Restricción por Empalme (Jugadores Compartidos)",
                    ),
                    _buildConflictsSection(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),

              // FOOTER BOTÓN
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.black12)),
                  color: Colors.white,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                    ),
                    onPressed: _handleSave,
                    child: const Text(
                      "GUARDAR CAMBIOS",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildJornadaSelector(List<int> selectedList, {required Color color}) {
    return Wrap(
      spacing: 8,
      children: List.generate(widget.totalJornadas, (index) {
        int jornada = index + 1;
        bool isSelected = selectedList.contains(jornada);
        return FilterChip(
          label: Text("J$jornada"),
          selected: isSelected,
          selectedColor: color.withOpacity(0.2),
          labelStyle: TextStyle(
            color: isSelected ? color : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          checkmarkColor: color,
          onSelected: (val) {
            setState(() {
              if (val) {
                selectedList.add(jornada);
              } else {
                selectedList.remove(jornada);
              }
              selectedList.sort();
            });
          },
        );
      }),
    );
  }

  Widget _buildTimeSection({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> dataList,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(title),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: color),
              onPressed: () => _addTimeEntry(dataList),
            ),
          ],
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),

        ...dataList.asMap().entries.map((entry) {
          int idx = entry.key;
          Map<String, dynamic> item = entry.value;
          List<dynamic> ranges = item['ranges'] ?? [];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: item['day'],
                      items: _days
                          .map(
                            (d) => DropdownMenuItem(value: d, child: Text(d)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => item['day'] = val),
                      isDense: true,
                      underline: const SizedBox(),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => dataList.removeAt(idx)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (ranges.isEmpty)
                      Chip(
                        label: const Text("Cualquier horario"),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(fontSize: 11, color: color),
                      ),

                    ...ranges.asMap().entries.map((rEntry) {
                      var range = rEntry.value;
                      return Chip(
                        label: Text("${range['start']} - ${range['end']}"),
                        backgroundColor: Colors.white,
                        labelStyle: const TextStyle(fontSize: 11),
                        onDeleted: () =>
                            setState(() => ranges.removeAt(rEntry.key)),
                      );
                    }),

                    ActionChip(
                      label: const Text("+ Hora"),
                      backgroundColor: Colors.transparent,
                      shape: StadiumBorder(side: BorderSide(color: color)),
                      labelStyle: TextStyle(color: color, fontSize: 11),
                      onPressed: () => _addRangeToItem(ranges),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildConflictsSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !_searchingExternal
                      ? Colors.grey[800]
                      : Colors.grey[200],
                  foregroundColor: !_searchingExternal
                      ? Colors.white
                      : Colors.black,
                  elevation: 0,
                ),
                onPressed: () => setState(() {
                  _searchingExternal = false;
                  _searchController.clear();
                  _searchResults.clear();
                }),
                child: const Text("Misma Academia"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _searchingExternal
                      ? Colors.grey[800]
                      : Colors.grey[200],
                  foregroundColor: _searchingExternal
                      ? Colors.white
                      : Colors.black,
                  elevation: 0,
                ),
                onPressed: () => setState(() {
                  _searchingExternal = true;
                  _searchController.clear();
                  _searchResults.clear();
                }),
                child: const Text("Otra Academia"),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        if (_searchingExternal)
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Buscar equipo foráneo...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onChanged: _runSearch,
          )
        else
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: _getSameAcademyTeams()
                  .map((t) => _buildTeamListTile(t))
                  .toList(),
            ),
          ),

        if (_searchingExternal && _searchResults.isNotEmpty)
          Container(
            height: 150,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: _searchResults
                  .map((t) => _buildTeamListTile(t))
                  .toList(),
            ),
          ),

        const SizedBox(height: 10),
        const Text(
          "Equipos Seleccionados (Conflicto):",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Wrap(
          spacing: 8,
          children: _conflictTeams.map((c) {
            return Chip(
              avatar: const Icon(Icons.people_outline, size: 14),
              label: Text(
                "${c['name']} (${c['categoryName']})",
                style: const TextStyle(fontSize: 10),
              ),
              onDeleted: () => setState(() => _conflictTeams.remove(c)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTeamListTile(dynamic team) {
    // Manejar _id de mongo o id normal
    String teamId = team['id'] ?? team['_id'];
    bool isAdded = _conflictTeams.any((c) => c['teamId'] == teamId);

    return ListTile(
      dense: true,
      title: Text(
        team['name'],
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        "${team['academy']['name']} - ${team['category']['name']}",
      ),
      trailing: isAdded
          ? const Icon(Icons.check_circle, color: Colors.green)
          : IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                setState(() {
                  _conflictTeams.add({
                    'teamId': teamId,
                    'name': team['name'],
                    'academyId': team['academy']['id'],
                    'academyName': team['academy']['name'],
                    'categoryName': team['category']['name'],
                  });
                });
              },
            ),
    );
  }

  // --- LOGICA INTERNA ---

  void _addTimeEntry(List<Map<String, dynamic>> list) {
    setState(() {
      list.add({'day': 'Sábado', 'ranges': []});
    });
  }

  Future<void> _addRangeToItem(List<dynamic> ranges) async {
    TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: "HORA INICIO",
    );
    if (start == null) return;

    if (!mounted) return;
    TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour + 1, minute: start.minute),
      helpText: "HORA FIN",
    );
    if (end == null) return;

    setState(() {
      ranges.add({'start': _formatTime(start), 'end': _formatTime(end)});
    });
  }

  String _formatTime(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat('HH:mm').format(dt);
  }

  List<dynamic> _getSameAcademyTeams() {
    String myAcademyId = widget.team['academy']['id'];
    String myId = widget.team['id'] ?? widget.team['_id'];
    return widget.allTeams
        .where(
          (t) =>
              t['academy']['id'] == myAcademyId &&
              (t['id'] ?? t['_id']) != myId,
        )
        .toList();
  }

  void _runSearch(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    String myAcademyId = widget.team['academy']['id'];
    setState(() {
      _searchResults = widget.allTeams.where((t) {
        bool notMyAcademy = t['academy']['id'] != myAcademyId;
        bool matchesName = t['name'].toString().toLowerCase().contains(
          query.toLowerCase(),
        );
        return notMyAcademy && matchesName;
      }).toList();
    });
  }

  void _handleSave() {
    final now = DateTime.now();
    final auditInfo =
        "${widget.currentUser.userName} el ${DateFormat('dd/MM/yy HH:mm').format(now)}";

    Map<String, dynamic> finalData = {
      'isForeign': _isForeign,
      'acceptDoubleHeader': _acceptDoubleHeader,
      'foreignAvailableJornadas': _foreignAvailableJornadas,
      'byeJornadas': _byeJornadas,
      'timePreferences': _timePreferences,
      'timeRestrictions': _timeRestrictions,
      'conflictTeams': _conflictTeams,
      'lastUpdateInfo': auditInfo,
      'updatedByUserId': widget.currentUser.id,
      'updatedAt': now.toIso8601String(),
    };

    widget.onSave(finalData);
  }
}
