import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Asegúrate de importar tu ApiService correctamente
import 'package:admin_league/services/api_service.dart';

class GroupManagementScreen extends StatefulWidget {
  final String categoryName;
  final List<Map<String, dynamic>> teams;

  const GroupManagementScreen({
    super.key,
    required this.categoryName,
    required this.teams,
  });

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  final ApiService _apiService = ApiService();

  // Mapa para editar grupos: ID -> Int (1, 2, 3) o null
  Map<String, int?> _tempGroups = {};

  // Mapa para editar nombres: ID -> String (Nuevo nombre)
  Map<String, String> _tempNames = {};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Cargar estado inicial
    for (var team in widget.teams) {
      // Si no tiene gpo, es null (Sin grupo)
      _tempGroups[team['_id']] = team['gpo'];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ordenar visualmente: Primero por grupo, luego alfabéticamente
    var sortedTeams = List.from(widget.teams);
    sortedTeams.sort((a, b) {
      // Tratamos null como 0 para el ordenamiento
      int gA = _tempGroups[a['_id']] ?? 0;
      int gB = _tempGroups[b['_id']] ?? 0;

      if (gA != gB) return gA.compareTo(gB);

      // Ordenar por el nombre ACTUAL (considerando edición)
      String nameA = _tempNames[a['_id']] ?? a['name'];
      String nameB = _tempNames[b['_id']] ?? b['name'];
      return nameA.compareTo(nameB);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Gestionar Equipos", style: TextStyle(fontSize: 16)),
            Text(
              widget.categoryName,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveChanges,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    "GUARDAR",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedTeams.length,
        itemBuilder: (context, index) {
          final team = sortedTeams[index];
          final teamId = team['_id'];

          final currentGroup = _tempGroups[teamId];
          final currentName = _tempNames[teamId] ?? team['name'];
          final isNameChanged = _tempNames.containsKey(teamId);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Borde izquierdo indica el grupo actual
              border: Border(
                left: BorderSide(color: _getGroupColor(currentGroup), width: 4),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila Superior: Nombre y Edición
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          // Si se editó, cambiar estilo visual
                          color: isNameChanged
                              ? Colors.blue[800]
                              : Colors.black,
                          fontStyle: isNameChanged
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.grey,
                      ),
                      tooltip: "Renombrar equipo",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showRenameDialog(teamId, currentName),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Fila Inferior: Selector de Grupo
                Row(
                  children: [
                    Text(
                      "Asignar a:",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    // Lista de opciones: [null, 1, 2, 3]
                    ...[null, 1, 2, 3].map(
                      (gNum) => _buildGroupOption(teamId, currentGroup, gNum),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Botón individual de selección (Circular)
  Widget _buildGroupOption(
    String teamId,
    int? currentSelection,
    int? optionValue,
  ) {
    bool isSelected = currentSelection == optionValue;
    bool isNullOption = optionValue == null;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tempGroups[teamId] = optionValue;
        });
      },
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isNullOption ? Colors.grey[600] : _getGroupColor(optionValue))
              : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey[300]!,
          ),
        ),
        child: Center(
          child: isNullOption
              ? Icon(
                  Icons.close,
                  size: 16,
                  color: isSelected ? Colors.white : Colors.grey,
                )
              : Text(
                  "$optionValue",
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Color _getGroupColor(int? group) {
    if (group == null) return Colors.grey;
    switch (group) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // Diálogo para renombrar
  void _showRenameDialog(String teamId, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Renombrar Equipo"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Nuevo nombre (Ej. Raptors B)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _tempNames[teamId] = controller.text.trim();
                });
              }
              Navigator.pop(context);
            },
            child: const Text("ACEPTAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    // Preparar payload combinado
    List<Map<String, dynamic>> updates = [];

    // Recorremos los equipos originales para ver qué cambió
    for (var team in widget.teams) {
      String id = team['_id'];

      // Datos nuevos vs originales
      int? newGroup = _tempGroups[id];
      int? oldGroup = team['gpo'];

      String? newName = _tempNames[id];
      String oldName = team['name'];

      bool groupChanged = newGroup != oldGroup;
      bool nameChanged = newName != null && newName != oldName;

      if (groupChanged || nameChanged) {
        Map<String, dynamic> updateObj = {"_id": id};

        // Solo enviamos lo necesario, pero enviamos 'gpo' aunque sea null si cambió
        if (groupChanged) updateObj["gpo"] = newGroup;
        if (nameChanged) updateObj["name"] = newName;

        updates.add(updateObj);
      }
    }

    if (updates.isEmpty) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
      return;
    }

    try {
      final res = await _apiService.updateTeamGroups(updates);
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context); // Volver
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Se actualizaron ${updates.length} equipos")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
