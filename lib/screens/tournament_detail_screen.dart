import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:admin_league/models/dashboard_tournament_model.dart';
import 'package:admin_league/services/api_service.dart';
import 'package:admin_league/theme/app_theme.dart';
import 'package:admin_league/models/user_model.dart';
import 'package:admin_league/screens/draft_category_screen.dart';
import 'package:admin_league/screens/group_management_screen.dart';
import 'package:admin_league/modals/team_constraints_modal.dart'; // Ajusta la ruta si es diferente
import 'package:admin_league/modals/team_payment_modal.dart';
import 'package:admin_league/screens/schedule_management_screen.dart';
import 'package:admin_league/screens/player_identity_screen.dart';

class TournamentDetailScreen extends StatefulWidget {
  final DashboardTournament tournament;
  final UserModel user; // <--- AGREGAR ESTO

  const TournamentDetailScreen({
    super.key,
    required this.tournament,
    required this.user,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groupedAcademies = [];
  List<Map<String, dynamic>> _groupedCategories = [];
  List<dynamic> _allTeamsRaw = []; // <--- AGREGAR ESTO

  // Métricas calculadas en el cliente
  int _totalTeams = 0;
  int _paidTeamsCount = 0;
  int _unpaidTeamsCount = 0;
  /// Suma de equipos con pago en categorías que ya alcanzan [minTeams] pagados (viabilidad).
  int _realTeams = 0;

  int _viewMode = 0; // 0 = Academias, 1 = Categorías

  // --- PALETA IOS ---
  final Color _bgScaffold = const Color(0xFFE8E8ED);
  final Color _textPrimary = const Color(0xFF1C1C1E);
  final Color _textSecondary = const Color(0xFF8E8E93);
  final Color _dividerColor = const Color(0xFFC6C6C8);

  // Semáforo
  final Color _statusCritical = const Color(0xFFFF3B30); // Rojo
  final Color _statusMin = const Color(0xFFFF9500); // Naranja
  final Color _statusViable = const Color(0xFF34C759); // Verde
  final Color _statusOptimal = const Color(0xFF007AFF); // Azul
  final Color _statusPurple = const Color(0xFFAF52DE); // Morado iOS

  Map<String, dynamic> _schedulesMap = {}; // <--- CAMBIO

  /// Monto sugerido al registrar pagos (dashboard + respuesta de equipos si trae `tournament.price`).
  double? _paymentAmountDefault;

  @override
  void initState() {
    super.initState();
    _paymentAmountDefault = widget.tournament.defaultPriceAmount;
    _loadTeams();
  }

  /// `mood == 0`: sin pago; el equipo no debe considerarse al completo.
  static int _teamMoodValue(Map<String, dynamic> team) {
    final m = team['mood'];
    if (m == null) return 0;
    if (m is int) return m;
    return int.tryParse(m.toString()) ?? 0;
  }

  static bool _teamHasPaidRegistration(Map<String, dynamic> team) {
    return _teamMoodValue(team) != 0;
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getTeamsAndSchedules(
        widget.tournament.id,
      );

      if (response.statusCode == 200) {
        final data = response.data;

        List<dynamic> allTeams = data['teams'] ?? [];
        _allTeamsRaw = allTeams;

        _schedulesMap = Map<String, dynamic>.from(data['schedules'] ?? {});

        // Procesamiento de datos
        final academies = _groupByAcademy(allTeams);
        final categories = _groupByCategory(allTeams);

        int paid = 0;
        for (var t in allTeams) {
          if (_teamHasPaidRegistration(
              Map<String, dynamic>.from(t as Map<dynamic, dynamic>))) {
            paid++;
          }
        }

        final int minTeams = widget.tournament.minTeams;
        int real = 0;
        for (var cat in categories) {
          final int paidInCat = cat['paidCount'] as int? ?? 0;
          if (paidInCat >= minTeams) {
            real += paidInCat;
          }
        }

        double? priceFromPayload;
        final tourRaw = data['tournament'];
        if (tourRaw is Map) {
          priceFromPayload = DashboardTournament.defaultAmountFromPriceField(
            tourRaw['price'],
          );
        }
        priceFromPayload ??=
            DashboardTournament.defaultAmountFromPriceField(data['price']);

        setState(() {
          _groupedAcademies = academies;
          _groupedCategories = categories;
          _totalTeams = allTeams.length;
          _paidTeamsCount = paid;
          _unpaidTeamsCount = allTeams.length - paid;
          _realTeams = real;
          if (priceFromPayload != null) {
            _paymentAmountDefault = priceFromPayload;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _groupByAcademy(List<dynamic> teams) {
    Map<String, Map<String, dynamic>> groups = {};
    for (var item in teams) {
      if (item['academy'] == null || item['academy']['id'] == null) continue;
      String id = item['academy']['id'];
      if (!groups.containsKey(id)) {
        groups[id] = {
          'id': id,
          'name': item['academy']?['name'] ?? item['name'] ?? 'Sin Nombre',
          'logo': item['logo'],
          'total': 0,
          'paidCount': 0,
          'unpaidCount': 0,
          'items': [],
          'playerStats': {'approved': 0, 'partial': 0, 'rejected': 0, 'pending': 0},
        };
      }

      groups[id]!['total'] += 1;
      final mapItem = Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
      if (_teamHasPaidRegistration(mapItem)) {
        groups[id]!['paidCount'] = (groups[id]!['paidCount'] as int) + 1;
      } else {
        groups[id]!['unpaidCount'] = (groups[id]!['unpaidCount'] as int) + 1;
      }
      (groups[id]!['items'] as List).add(item);

      // Agregación de estadísticas de jugadores
      final pStats = item['playerStats'];
      if (pStats != null) {
        final gStats = groups[id]!['playerStats'] as Map<String, int>;
        gStats['approved'] = ((gStats['approved'] ?? 0) + (pStats['approved'] ?? 0)).toInt();
        gStats['partial'] = ((gStats['partial'] ?? 0) + (pStats['partial'] ?? 0)).toInt();
        gStats['rejected'] = ((gStats['rejected'] ?? 0) + (pStats['rejected'] ?? 0)).toInt();
        gStats['pending'] = ((gStats['pending'] ?? 0) + (pStats['pending'] ?? 0)).toInt();
      }
    }
    return groups.values.toList();
  }

  List<Map<String, dynamic>> _groupByCategory(List<dynamic> teams) {
    Map<String, Map<String, dynamic>> groups = {};
    for (var item in teams) {
      if (item['category'] == null) continue;
      String catName = item['category']['name'] ?? 'General';
      if (!groups.containsKey(catName)) {
        groups[catName] = {
          'name': catName,
          'total': 0,
          'paidCount': 0,
          'items': [],
          'playerStats': {'approved': 0, 'partial': 0, 'rejected': 0, 'pending': 0}
        };
      }
      groups[catName]!['total'] += 1;
      final mapItem = Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
      if (_teamHasPaidRegistration(mapItem)) {
        groups[catName]!['paidCount'] = (groups[catName]!['paidCount'] as int) + 1;
      }
      (groups[catName]!['items'] as List).add(item);

      // Agregación de estadísticas de jugadores
      final pStats = item['playerStats'];
      if (pStats != null) {
        final gStats = groups[catName]!['playerStats'] as Map<String, int>;
        gStats['approved'] = ((gStats['approved'] ?? 0) + (pStats['approved'] ?? 0)).toInt();
        gStats['partial'] = ((gStats['partial'] ?? 0) + (pStats['partial'] ?? 0)).toInt();
        gStats['rejected'] = ((gStats['rejected'] ?? 0) + (pStats['rejected'] ?? 0)).toInt();
        gStats['pending'] = ((gStats['pending'] ?? 0) + (pStats['pending'] ?? 0)).toInt();
      }
    }
    return groups.values.toList();
  }

  // --- LÓGICA DE ESTADO (categoría vs minTeams del torneo) ---
  /// [totalCount] = equipos en la categoría; [paidCount] = con pago (mood ≠ 0).
  /// Primero se cubre el cupo de **equipos inscritos**; luego el de **pagos** para salir a torneo.
  Map<String, dynamic> _calculateCategoryStatusMinTeams(
    int paidCount,
    int totalCount,
    int minTeams,
  ) {
    final int min = minTeams < 1 ? 4 : minTeams;

    if (totalCount < min) {
      final int missTeams = min - totalCount;
      if (missTeams >= 2) {
        return {
          'color': _statusCritical,
          'text': 'FALTAN $missTeams',
          'priority': 0,
        };
      }
      return {
        'color': _statusMin,
        'text': 'FALTA 1',
        'priority': 1,
      };
    }

    if (paidCount >= min) {
      if (paidCount == min) {
        return {
          'color': _statusViable,
          'text': 'LISTO',
          'priority': 2,
        };
      }
      return {
        'color': _statusOptimal,
        'text': 'SOBRE MÍNIMO',
        'priority': 3,
      };
    }

    final int missPay = min - paidCount;
    if (missPay >= 2) {
      return {
        'color': _statusCritical,
        'text': 'FALTAN $missPay PAGO',
        'priority': 0,
      };
    }
    return {
      'color': _statusMin,
      'text': 'FALTA 1 PAGO',
      'priority': 1,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _textPrimary))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(),

                // Nuevos Stats (Total vs Real)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: _buildRealStatsHeader(),
                  ),
                ),

                // Toggle
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Center(child: _buildViewToggle()),
                  ),
                ),

                // Listas
                _viewMode == 0 ? _buildAcademiesList() : _buildCategoriesList(),

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  // --- SLIVER APP BAR (Fixed Title) ---
  Widget _buildSliverAppBar() {
    return SliverAppBar.large(
      backgroundColor: _bgScaffold,
      surfaceTintColor: _bgScaffold,
      expandedHeight: 110,
      pinned: true,
      centerTitle: false,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 16,
            color: Colors.black,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsetsDirectional.only(start: 60, bottom: 14),
        title: Text(
          widget.tournament.name,
          style: GoogleFonts.inter(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontSize: 18,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // --- NUEVO HEADER DE MÉTRICAS (TOTAL VS REAL) ---
  Widget _buildRealStatsHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildBigStat("TOTAL", "$_totalTeams", _textSecondary),
              Container(width: 1, height: 40, color: _bgScaffold),
              _buildBigStat("CON PAGO", "$_paidTeamsCount", _statusViable),
              Container(width: 1, height: 40, color: _bgScaffold),
              _buildBigStat(
                "SIN PAGO",
                "$_unpaidTeamsCount",
                _unpaidTeamsCount > 0 ? _statusCritical : _textSecondary,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              "Cupos viables (categorías con al menos ${widget.tournament.minTeams} equipos con pago): $_realTeams",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                height: 1.3,
                color: _textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE3E3E8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildToggleItem("Academias", 0),
          _buildToggleItem("Categorías", 1),
        ],
      ),
    );
  }

  Widget _buildToggleItem(String text, int index) {
    final isSelected = _viewMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _viewMode = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(12),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? _textPrimary : _textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // --- LISTA 1: ACADEMIAS (Alfabético) ---
  // ===========================================================================
  // LISTA 1: ACADEMIAS (BADGES)
  // ===========================================================================
  Widget _buildAcademiesList() {
    if (_groupedAcademies.isEmpty) return _buildEmptySliver("Sin equipos");

    // Ordenar alfabéticamente por nombre de Academia
    _groupedAcademies.sort((a, b) => a['name'].compareTo(b['name']));

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = _groupedAcademies[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Sombra suave para separar las academias
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Theme(
              // Quitamos las líneas divisorias por defecto
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),

                // --- 1. LOGO DE LA ACADEMIA ---
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _bgScaffold,
                    borderRadius: BorderRadius.circular(8),
                    image: item['logo'] != null
                        ? DecorationImage(
                            image: NetworkImage(item['logo']),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: item['logo'] == null
                      ? Icon(Icons.shield, size: 18, color: _textSecondary)
                      : null,
                ),

                // --- 2. NOMBRE DE LA ACADEMIA + RESUMEN (NUEVO) ---
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name'],
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: _textPrimary,
                            ),
                          ),
                        ),
                        if (item['playerStats'] != null)
                          _buildSummaryStats(item['playerStats']),
                      ],
                    ),
                    if ((item['total'] as int) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${item['paidCount']} con pago · ${item['unpaidCount']} sin pago',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: _textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),

                // --- 3. CONTADOR + PAGOS ACADEMIA (Trailing) ---
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.user.canAssignPayments)
                      IconButton.filledTonal(
                        onPressed: () => _showAcademyPaymentModal(item),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F5E9),
                          foregroundColor: const Color(0xFF2E7D32),
                        ),
                        icon: const Icon(Icons.payments_rounded, size: 22),
                        tooltip: 'Asignar pagos por academia',
                      ),
                    if (widget.user.canAssignPayments)
                      const SizedBox(width: 4),
                    Tooltip(
                      message: 'Equipos con pago / total en la academia',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _bgScaffold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item['paidCount']}/${item['total']}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: (item['unpaidCount'] as int) > 0
                                ? _statusMin
                                : _statusViable,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // --- 4. LISTA DE EQUIPOS INTERNA ---
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: item['items'].length,
                    itemBuilder: (ctx, idx) {
                      final teamMap = Map<String, dynamic>.from(
                        item['items'][idx] as Map,
                      );

                      // Verificar si tiene condiciones especiales
                      final bool hasConstraints =
                          teamMap['constraints'] != null &&
                          (teamMap['constraints'] as Map).isNotEmpty;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: _bgScaffold)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasConstraints)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Colors.blue[800],
                                ),
                              )
                            else
                              const SizedBox(width: 30),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          teamMap['name'],
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: _teamHasPaidRegistration(
                                                    teamMap)
                                                ? _textPrimary
                                                : _textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _buildTeamPaymentBadge(teamMap),
                                      if (teamMap['playerStats'] != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: _buildPlayerStatsBadges(
                                            teamMap['playerStats'],
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (hasConstraints)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _buildConstraintsBadges(
                                        teamMap['constraints'],
                                      ),
                                    ),
                                  if ((teamMap['category']?['name'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        teamMap['category']?['name'] ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ),
                                  _buildTeamQuickActionsRow(teamMap),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }, childCount: _groupedAcademies.length),
      ),
    );
  }

  // --- LISTA 2: CATEGORÍAS (Priorizada & Compacta) ---
  Widget _buildCategoriesList() {
    if (_groupedCategories.isEmpty) return _buildEmptySliver("Sin categorías");

    List<Map<String, dynamic>> processed = List.from(_groupedCategories);

    // 1. Calcular Status y 2. Ordenar (Tu lógica actual se mantiene igual)
    final int minTeams = widget.tournament.minTeams;
    for (var cat in processed) {
      final int paidInCat = cat['paidCount'] as int? ?? 0;
      final int totalInCat = cat['total'] as int? ?? 0;
      cat['meta'] = _calculateCategoryStatusMinTeams(
        paidInCat,
        totalInCat,
        minTeams,
      );
    }
    processed.sort((a, b) {
      int pA = a['meta']['priority'];
      int pB = b['meta']['priority'];
      if (pA != pB) return pA.compareTo(pB);
      return a['total'].compareTo(b['total']);
    });

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final cat = processed[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(5),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Theme(
              // Quitamos las líneas divisorias feas por defecto del ExpansionTile
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets
                    .zero, // Usaremos nuestro propio padding en el header
                childrenPadding: const EdgeInsets.only(bottom: 16),

                // --- CABECERA (Lo que ya tenías) ---
                title: _buildCompactCategoryRow(cat),

                // --- CUERPO DESPLEGABLE (La lista de equipos) ---
                children: [
                  // 1. Divisor sutil
                  const Divider(
                    height: 1,
                    color: Color(0xFFF2F2F7),
                    indent: 16,
                    endIndent: 16,
                  ),
                  const SizedBox(height: 8),

                  // 2. Lista de Equipos
                  ...(cat['items'] as List)
                      .map((team) => _buildTeamRowForCategory(team))
                      .toList(),

                  const SizedBox(height: 16),

                  // 3. BOTÓN DE ACCIÓN (Ahora vive aquí adentro)
                  if (widget.user.canManageSchedules == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _goToDraftScreen(cat),
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                          ),
                          label: Text(
                            "GESTIONAR CALENDARIO",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }, childCount: processed.length),
      ),
    );
  }

  // Widget Nuevo: La barra de acción para grupos
  Widget _buildGroupManagementAction(Map<String, dynamic> cat) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF2F2F7))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Text(
            "Muchos equipos detectados",
            style: GoogleFonts.inter(fontSize: 11, color: Colors.orange[800]),
          ),
          const Spacer(),
          SizedBox(
            height: 32,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.blue[50],
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.groups, size: 16, color: Colors.blue),
              label: Text(
                "GESTIONAR GRUPOS",
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              onPressed: () {
                // Navegar a la pantalla de gestión
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManagementScreen(
                      categoryName: cat['name'],
                      teams: List<Map<String, dynamic>>.from(cat['items']),
                    ),
                  ),
                ).then((_) => _loadTeams()); // Recargar al volver
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRowForCategory(Map<String, dynamic> team) {
    final teamMap = Map<String, dynamic>.from(team);
    bool hasConstraints =
        teamMap['constraints'] != null &&
        (teamMap['constraints'] as Map).isNotEmpty;
    String academyName = teamMap['academy']?['name'] ?? 'Sin Academia';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[100],
              border: Border.all(color: Colors.grey[300]!),
              image: teamMap['logo'] != null
                  ? DecorationImage(
                      image: NetworkImage(teamMap['logo']),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: teamMap['logo'] == null
                ? const Icon(Icons.shield, size: 14, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        teamMap['name'],
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _teamHasPaidRegistration(teamMap)
                              ? _textPrimary
                              : _textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildTeamPaymentBadge(teamMap),
                    if (teamMap['playerStats'] != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _buildPlayerStatsBadges(teamMap['playerStats']),
                      ),
                  ],
                ),
                if (hasConstraints)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildConstraintsBadges(
                      teamMap['constraints'],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      academyName,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: _textSecondary,
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

  Widget _buildCompactCategoryRow(Map<String, dynamic> cat) {
    final meta = cat['meta'];
    final Color color = meta['color'];
    final int count = cat['total'];
    final int paidCount = cat['paidCount'] as int? ?? 0;
    final int unpaidCount = count - paidCount;
    final String statusText = meta['text'];
    final String catName = cat['name'];

    // --- 1. LÓGICA DE DETECCIÓN DE FORÁNEOS (NUEVO) ---
    // Recorremos la lista de equipos para ver si hay alguno foráneo
    bool hasForeignTeams = (cat['items'] as List).any((t) {
      return t['constraints'] != null && t['constraints']['isForeign'] == true;
    });

    // --- 2. LÓGICA DE SINCRONIZACIÓN (Existente) ---
    final scheduleInfo = _schedulesMap[catName];
    bool isPublished = scheduleInfo != null;
    bool isSynced = false;

    if (isPublished) {
      Set<String> currentIds = (cat['items'] as List)
          .map((t) => (t['id'] ?? t['_id']).toString())
          .toSet();

      List<dynamic> savedIdsRaw = scheduleInfo['teamIds'] ?? [];
      Set<String> savedIds = savedIdsRaw.map((e) => e.toString()).toSet();

      isSynced =
          currentIds.length == savedIds.length &&
          currentIds.containsAll(savedIds);
    }

    Widget syncIcon;
    if (!isPublished) {
      syncIcon = Icon(Icons.circle_outlined, size: 14, color: Colors.grey[400]);
    } else if (isSynced) {
      syncIcon = const Icon(
        Icons.check_circle,
        size: 18,
        color: Color(0xFF34C759),
      );
    } else {
      syncIcon = Tooltip(
        message: "Equipos modificados",
        child: Icon(
          Icons.sync_problem_rounded,
          size: 20,
          color: Colors.orange[800],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Icono Sync
          Padding(padding: const EdgeInsets.only(right: 12), child: syncIcon),

          // Nombre + Aviso Sync
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        catName,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // --- 3. INDICADOR VISUAL DE FORÁNEOS (NUEVO) ---
                    if (hasForeignTeams)
                      Tooltip(
                        message: "Incluye equipos foráneos",
                        triggerMode: TooltipTriggerMode.tap,
                        child: Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.purple[50], // Fondo sutil
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.flight_takeoff, // Icono de avión
                            size: 12,
                            color: Colors.purple[700],
                          ),
                        ),
                      ),
                  ],
                ),

                // --- NUEVO: RESUMEN DE JUGADORES EN CATEGORÍA ---
                if (cat['playerStats'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildSummaryStats(cat['playerStats']),
                  ),

                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$paidCount con pago · $unpaidCount sin pago',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                if (isPublished && !isSynced)
                  Text(
                    "Cambios sin publicar",
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),

          // Contador
          Text(
            "$count",
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),

          const SizedBox(width: 12),

          // Badge Estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            constraints: const BoxConstraints(minWidth: 70),
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusText,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tres acciones por equipo: configuración, roster e inscripción/pago.
  Widget _buildTeamQuickActionsRow(
    Map<String, dynamic> teamMap, {
    bool compact = false,
  }) {
    final double iconSize = compact ? 16 : 18;
    final double fontSize = compact ? 11 : 12;
    final EdgeInsets pad = EdgeInsets.symmetric(
      vertical: compact ? 8 : 10,
      horizontal: compact ? 4 : 8,
    );

    void openRoster() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerIdentityScreen(
            teamId: (teamMap['id'] ?? teamMap['_id']).toString(),
            teamName: teamMap['name'] ?? 'Sin Nombre',
            user: widget.user,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 10),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Configuración de restricciones y preferencias',
              child: OutlinedButton.icon(
                onPressed: () => _showConstraintsModal(teamMap),
                icon: Icon(Icons.tune_rounded, size: iconSize),
                label: Text(
                  compact ? 'Config' : 'Configuración',
                  style: GoogleFonts.inter(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(padding: pad),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: 'Revisión de roster e identidad de jugadores',
              child: OutlinedButton.icon(
                onPressed: openRoster,
                icon: Icon(Icons.groups_2_outlined, size: iconSize),
                label: Text(
                  'Roster',
                  style: GoogleFonts.inter(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: pad,
                  foregroundColor: const Color(0xFF1565C0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: 'Registrar o quitar pago de inscripción',
              child: widget.user.canAssignPayments
                  ? FilledButton.icon(
                      onPressed: () => _showTeamPaymentModal(teamMap),
                      icon: Icon(Icons.payments_rounded, size: iconSize),
                      label: Text(
                        'Pago',
                        style: GoogleFonts.inter(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        padding: pad,
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.visibility_off_outlined,
                          size: compact ? 14 : 16),
                      label: Text(
                        'Solo lectura',
                        style: GoogleFonts.inter(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(padding: pad),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamPaymentBadge(Map<String, dynamic> team) {
    final paid = _teamHasPaidRegistration(team);
    return Tooltip(
      message: paid
          ? 'Inscripción con pago registrado'
          : 'Sin pago confirmado; el equipo no cuenta al completo para el torneo.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: paid
              ? _statusViable.withAlpha(28)
              : _statusCritical.withAlpha(28),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: paid
                ? _statusViable.withAlpha(100)
                : _statusCritical.withAlpha(100),
            width: 0.5,
          ),
        ),
        child: Text(
          paid ? 'Con pago' : 'Sin pago',
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: paid ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
          ),
        ),
      ),
    );
  }

  // --- HELPER PARA RESUMEN SUTIL DE ESTADÍSTICAS (ACADEMIAS/CATEGORÍAS) ---
  Widget _buildSummaryStats(Map<String, dynamic> stats) {
    final approved = stats['approved'] ?? 0;
    final partial = stats['partial'] ?? 0;
    final rejected = stats['rejected'] ?? 0;
    final pending = stats['pending'] ?? 0;
    final total = approved + partial + rejected + pending;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (approved > 0) _buildSubtleCount("$approved", Colors.green),
        if (partial > 0) _buildSubtleCount("$partial", Colors.orange),
        if (rejected > 0) _buildSubtleCount("$rejected", Colors.red),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              "$total j.",
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _textSecondary.withAlpha(150),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubtleCount(String count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            count,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER PARA ESTADÍSTICAS DE JUGADORES ---
  Widget _buildPlayerStatsBadges(Map<String, dynamic> stats) {
    List<Widget> badges = [];

    final approved = stats['approved'] ?? 0;
    final rejected = stats['rejected'] ?? 0;
    final partial = stats['partial'] ?? 0;

    if (approved > 0) {
      badges.add(_buildStatBadge("$approved", Colors.green));
    }
    if (partial > 0) {
      badges.add(_buildStatBadge("$partial", Colors.orange));
    }
    if (rejected > 0) {
      badges.add(_buildStatBadge("$rejected", Colors.red));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Row(mainAxisSize: MainAxisSize.min, children: badges);
  }

  Widget _buildStatBadge(String count, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100), width: 0.5),
      ),
      child: Text(
        count,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  // --- HELPER PARA BADGES DE CONDICIONES ---
  Widget _buildConstraintsBadges(Map<String, dynamic> constraints) {
    List<Widget> badges = [];

    // 1. Foráneo
    if (constraints['isForeign'] == true) {
      badges.add(_buildMiniBadge("Foráneo", Colors.purple));
    }

    // 2. Byes Solicitados
    List byes = constraints['byeJornadas'] ?? [];
    if (byes.isNotEmpty) {
      String text = "Bye: J${byes.join(', J')}";
      badges.add(_buildMiniBadge(text, Colors.orange));
    }

    // 3. Restricciones Horarias
    List timeRest = constraints['timeRestrictions'] ?? [];
    if (timeRest.isNotEmpty) {
      // Podemos ser más específicos si quieres contar los días
      badges.add(_buildMiniBadge("Horario Restringido", Colors.blue));
    }

    // 4. Prioridad de Campo
    if (constraints['priorityField'] != null &&
        constraints['priorityField'].toString().isNotEmpty) {
      badges.add(_buildMiniBadge("Campo Fijo", Colors.teal));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }

  Widget _buildMiniBadge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color[200]!, width: 0.5),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color[800],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(String text) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(text, style: GoogleFonts.inter(color: _textSecondary)),
      ),
    );
  }

  Future<void> _goToDraftScreen(Map<String, dynamic> categoryData) async {
    // 1. Datos VIVOS (Estado actual de la categoría en memoria)
    List<dynamic> currentTeams = List.from(categoryData['items'] ?? []);
    int numTeamsTotal = categoryData['total'] ?? currentTeams.length;
    String catName = categoryData['name'];

    // Validación básica de mínimos
    if (numTeamsTotal < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Se requieren mínimo 4 equipos para generar un calendario.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // =======================================================================
    // FASE 1: FAST TRACK (Navegación Instantánea al Oficial)
    // =======================================================================
    // Usamos el mapa _schedulesMap que ya cargamos al inicio (optimización Backend-For-Frontend)
    final scheduleInfo = _schedulesMap[catName];

    if (scheduleInfo != null) {
      // 1. Convertimos equipos actuales a Set de IDs
      final Set<String> currentIds = currentTeams
          .map((t) => (t['id'] ?? t['_id']).toString())
          .toSet();

      // 2. Obtenemos los IDs que vienen del backend (ya listos)
      final List<dynamic> savedIdsRaw = scheduleInfo['teamIds'] ?? [];
      final Set<String> savedIds = savedIdsRaw.map((e) => e.toString()).toSet();

      // 3. Comparamos integridad exacta
      bool isSynced =
          currentIds.length == savedIds.length &&
          currentIds.containsAll(savedIds);

      if (isSynced) {
        // ¡Boom! Navegación inmediata sin spinners ni peticiones extra
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScheduleManagementScreen(
              scheduleId: scheduleInfo['scheduleId'],
              categoryName: catName,
              tournamentId: widget.tournament.id,
            ),
          ),
        );
        return; // DETENER EJECUCIÓN AQUÍ
      } else {
        print(">> Fast Track omitido: Cambios detectados en equipos.");
      }
    }

    // =======================================================================
    // FASE 2: GESTIÓN DE BORRADOR (DRAFT)
    // =======================================================================
    // Si llegamos aquí, es porque NO hay oficial o está desincronizado.
    // Toca trabajar con el Draft.

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
              "Preparando área de trabajo...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // Helper interno para extraer documentos de CouchDB
      Map<String, dynamic>? extractDoc(dynamic responseData) {
        if (responseData is List && responseData.isNotEmpty)
          return responseData[0];
        if (responseData is Map) {
          if (responseData.containsKey('rows') &&
              (responseData['rows'] as List).isNotEmpty) {
            var firstRow = responseData['rows'][0];
            return firstRow['value'] ?? firstRow['doc'] ?? firstRow;
          } else if (responseData.containsKey('_id') ||
              responseData.containsKey('type')) {
            return responseData as Map<String, dynamic>;
          }
        }
        return null;
      }

      // A. Buscar si existe un Draft guardado en BD
      final existingDraftResponse = await _apiService.getDraft(
        widget.tournament.id,
        catName,
      );

      Map<String, dynamic> structureToUse = {};
      Map<String, dynamic> assignmentsToUse = {};
      String? draftIdToUse;
      bool needsRegeneration =
          true; // Por defecto asumimos que hay que recalcular

      if (existingDraftResponse.statusCode == 200) {
        Map<String, dynamic>? savedDraft = extractDoc(
          existingDraftResponse.data,
        );

        if (savedDraft != null && savedDraft.containsKey('structure')) {
          draftIdToUse = savedDraft['_id'] ?? savedDraft['id'];
          Map<String, dynamic> savedAssignments =
              savedDraft['assignments'] ?? {};

          // Validación de integridad del Draft guardado
          // ¿El draft guardado tiene la misma cantidad de equipos que tenemos hoy?
          int savedTotalCount =
              savedDraft['totalTeams'] ?? savedAssignments.length;

          // Nota: Si el número coincide, asumimos que la estructura matemática (jornadas) sirve.
          // Si el usuario solo cambió nombres o logos, no necesitamos regenerar el fixture matemático.
          // Solo si agregó o quitó equipos (cambió N) necesitamos regenerar.
          if (savedTotalCount == numTeamsTotal) {
            print(">> Draft reutilizable encontrado.");
            structureToUse = savedDraft['structure'];
            assignmentsToUse = savedAssignments;
            needsRegeneration = false;
          } else {
            print(
              ">> Draft obsoleto ($savedTotalCount vs $numTeamsTotal). Se regenerará estructura.",
            );
            // Guardamos las asignaciones viejas por si podemos rescatar alguna coincidencia
            assignmentsToUse = savedAssignments;
            needsRegeneration = true;
          }
        }
      }

      // B. Regeneración Matemática (Si es necesaria)
      if (needsRegeneration) {
        // Regla de negocio: Si son 4 equipos = 6 juegos (3 vueltas), si son más = 8 juegos
        // O lo que tengas configurado como default
        int targetGames = (numTeamsTotal == 4) ? 6 : 8;

        // Preparamos la config para el algoritmo
        var configResult = _buildTournamentConfig(currentTeams, targetGames);

        // Llamada al motor matemático
        final genResponse = await _apiService.generateComplexDraft(
          targetGames: targetGames,
          targetWeeks: targetGames, // Semanas = Juegos aprox
          groupsConfig: configResult['groupsConfig'],
          useHistory:
              true, // Importante: Respetar partidos ya jugados si existen
          tournamentId: widget.tournament.id,
          categoryName: catName,
        );

        if (genResponse.statusCode == 200) {
          structureToUse = genResponse.data;

          // Si el backend logró hacer auto-match (por historia), usamos eso.
          // Si no, intentamos mantener las asignaciones viejas que rescatamos arriba.
          if (genResponse.data['autoAssignments'] != null) {
            assignmentsToUse = Map<String, dynamic>.from(
              genResponse.data['autoAssignments'],
            );
          }
          // Si no hay autoAssignments del backend, assignmentsToUse se queda con lo que
          // rescatamos del draft viejo (si existía), o vacío.
        } else {
          throw Exception(
            "Error al generar estructura: ${genResponse.statusCode}",
          );
        }
      }

      // C. Navegación al Editor (DraftScreen)
      if (!mounted) return;
      Navigator.pop(context); // Cerrar Loading

      // Re-empaquetamos los equipos para la vista visual
      var finalConfig = _buildTournamentConfig(currentTeams, 8);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DraftCategoryScreen(
            categoryName: catName,
            tournamentId: widget.tournament.id,

            // Lista de equipos vivos para el riel lateral
            enrolledTeamsByGroup: finalConfig['organizedTeams'],

            // La matriz matemática (Jornadas vacías o pre-llenadas)
            draftData: structureToUse,

            // Quién va en qué slot
            initialAssignments: assignmentsToUse,

            // ID para sobrescribir al guardar
            existingDraftId: draftIdToUse,
            user: widget.user,
          ),
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      print("Error en goToDraft: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ocurrió un error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- HELPER OBLIGATORIO (EL CEREBRO) ---
  Map<String, dynamic> _buildTournamentConfig(
    List<dynamic> allTeams,
    int targetGames,
  ) {
    Map<String, List<Map<String, dynamic>>> groupsMap = {};

    // A. Separación (Igual que antes)
    for (var team in allTeams) {
      String gpoId = (team['gpo'] ?? 1).toString();
      if (!groupsMap.containsKey(gpoId)) {
        groupsMap[gpoId] = [];
      }
      groupsMap[gpoId]!.add(Map<String, dynamic>.from(team));
    }

    // B. Construcción del Payload
    List<Map<String, dynamic>> groupsConfig = [];
    var sortedKeys = groupsMap.keys.toList()..sort();

    for (String gId in sortedKeys) {
      // AQUÍ ESTÁ EL CAMBIO IMPORTANTE:
      // Antes enviabas: "teams": groupsMap[gId]!.length
      // Ahora enviamos la lista completa para que el backend lea los IDs

      groupsConfig.add({
        "id": gId,
        "teams": groupsMap[gId], // <--- ENVIAR LA LISTA COMPLETA
        "interGroupGames": [],
      });
    }

    return {"groupsConfig": groupsConfig, "organizedTeams": groupsMap};
  }

  void _throwIfAssignPaymentError(dynamic data) {
    if (data is Map && data['status'] == 'error') {
      throw Exception(data['message'] ?? 'Error del servidor');
    }
  }

  String _teamIdOf(Map<String, dynamic> t) =>
      (t['_id'] ?? t['id']).toString();

  /// Aplica cambios de pago solo donde aplica y recalcula derivados
  /// únicamente para las academias/categorías afectadas.
  void _applyTeamPaymentUpdatesToStateFine(
    List<Map<String, dynamic>> updatedTeams,
  ) {
    if (updatedTeams.isEmpty) return;

    final minTeams = widget.tournament.minTeams;
    final Map<String, Map<String, dynamic>> updatesById = {};
    for (final ut in updatedTeams) {
      final id = _teamIdOf(ut);
      if (id.isNotEmpty) updatesById[id] = ut;
    }
    final updatedIds = updatesById.keys.toSet();
    if (updatedIds.isEmpty) return;

    // 1) Detectar qué academias/categorías se ven afectadas + snapshots previos
    final Set<String> affectedAcademyIds = {};
    final Map<String, int> oldAcademyPaid = {};

    final Set<String> affectedCategoryNames = {};
    final Map<String, int> oldCategoryContribution = {};

    for (final academy in _groupedAcademies) {
      final academyId = academy['id']?.toString() ?? '';
      if (academyId.isEmpty) continue;

      bool touches = false;
      for (final t in (academy['items'] as List)) {
        final tid = (t as Map)['_id'] ?? (t as Map)['id'];
        if (tid != null && updatedIds.contains(tid.toString())) {
          touches = true;
          break;
        }
      }
      if (touches) {
        affectedAcademyIds.add(academyId);
        oldAcademyPaid[academyId] = (academy['paidCount'] as int?) ?? 0;
      }
    }

    for (final cat in _groupedCategories) {
      final catName = cat['name']?.toString() ?? '';
      if (catName.isEmpty) continue;

      bool touches = false;
      for (final t in (cat['items'] as List)) {
        final tid = (t as Map)['_id'] ?? (t as Map)['id'];
        if (tid != null && updatedIds.contains(tid.toString())) {
          touches = true;
          break;
        }
      }
      if (touches) {
        affectedCategoryNames.add(catName);
        final paid = (cat['paidCount'] as int?) ?? 0;
        oldCategoryContribution[catName] = paid >= minTeams ? paid : 0;
      }
    }

    final int oldPaidTotal = oldAcademyPaid.values.fold(0, (a, b) => a + b);
    final int oldContributionTotal =
        oldCategoryContribution.values.fold(0, (a, b) => a + b);

    // 2) Aplicar mood/paymentRegistration en memoria (equipos cambiados)
    for (final academy in _groupedAcademies) {
      for (final t in (academy['items'] as List)) {
        final tid = (t as Map)['_id'] ?? (t as Map)['id'];
        if (tid == null) continue;
        final id = tid.toString();
        final ut = updatesById[id];
        if (ut == null) continue;

        (t as Map)['mood'] = ut['mood'];
        final pr = ut['paymentRegistration'];
        if (pr != null) {
          (t as Map)['paymentRegistration'] = pr;
        }
      }
    }

    // 3) Recalcular solo academias afectadas
    int newPaidTotal = 0;
    for (final academy in _groupedAcademies) {
      final academyId = academy['id']?.toString() ?? '';
      if (!affectedAcademyIds.contains(academyId)) continue;

      int paid = 0;
      int unpaid = 0;
      for (final t in (academy['items'] as List)) {
        final tMap = (t as Map).cast<String, dynamic>();
        if (_teamMoodValue(tMap) != 0) {
          paid++;
        } else {
          unpaid++;
        }
      }
      academy['paidCount'] = paid;
      academy['unpaidCount'] = unpaid;
      newPaidTotal += paid;
    }

    _paidTeamsCount = _paidTeamsCount - oldPaidTotal + newPaidTotal;
    _unpaidTeamsCount = _totalTeams - _paidTeamsCount;

    // 4) Recalcular solo categorías afectadas
    int newContributionTotal = 0;
    for (final cat in _groupedCategories) {
      final catName = cat['name']?.toString() ?? '';
      if (!affectedCategoryNames.contains(catName)) continue;

      final items = (cat['items'] as List);
      final total = items.length;
      int paid = 0;
      for (final t in items) {
        final tMap = (t as Map).cast<String, dynamic>();
        if (_teamMoodValue(tMap) != 0) paid++;
      }
      final unpaid = total - paid;

      cat['paidCount'] = paid;
      cat['unpaidCount'] = unpaid;
      cat['total'] = total;
      cat['meta'] = _calculateCategoryStatusMinTeams(paid, total, minTeams);

      if (paid >= minTeams) newContributionTotal += paid;
    }

    _realTeams = _realTeams - oldContributionTotal + newContributionTotal;
  }

  void _applyTeamPaymentUpdateToState(Map<String, dynamic> updatedTeam) {
    final String id = _teamIdOf(updatedTeam);
    final dynamic updatedMood = updatedTeam['mood'];
    final dynamic updatedPaymentRegistration = updatedTeam['paymentRegistration'];

    // Actualizamos en academias
    for (final academy in _groupedAcademies) {
      final items = (academy['items'] as List);
      for (final t in items) {
        final tId = (t as Map)['_id'] ?? (t as Map)['id'];
        if (tId != null && tId.toString() == id) {
          (t as Map)['mood'] = updatedMood;
          if (updatedPaymentRegistration != null) {
            (t as Map)['paymentRegistration'] = updatedPaymentRegistration;
          }
        }
      }
    }

    // Actualizamos en categorías
    for (final cat in _groupedCategories) {
      final items = (cat['items'] as List);
      for (final t in items) {
        final tId = (t as Map)['_id'] ?? (t as Map)['id'];
        if (tId != null && tId.toString() == id) {
          (t as Map)['mood'] = updatedMood;
          if (updatedPaymentRegistration != null) {
            (t as Map)['paymentRegistration'] = updatedPaymentRegistration;
          }
        }
      }
    }
  }

  void _recalculatePaymentDerivedState() {
    final int minTeams = widget.tournament.minTeams;

    int paidTotal = 0;
    for (final academy in _groupedAcademies) {
      int paid = 0;
      int unpaid = 0;
      for (final t in (academy['items'] as List)) {
        final tMap = Map<String, dynamic>.from(t as Map);
        final moodVal = _teamMoodValue(tMap);
        if (moodVal != 0) {
          paid++;
        } else {
          unpaid++;
        }
      }
      academy['paidCount'] = paid;
      academy['unpaidCount'] = unpaid;
      paidTotal += paid;
    }

    _paidTeamsCount = paidTotal;
    _unpaidTeamsCount = _totalTeams - paidTotal;

    int real = 0;
    for (final cat in _groupedCategories) {
      final items = (cat['items'] as List);
      final int total = items.length;
      int paid = 0;
      for (final t in items) {
        final tMap = Map<String, dynamic>.from(t as Map);
        final moodVal = _teamMoodValue(tMap);
        if (moodVal != 0) paid++;
      }

      cat['paidCount'] = paid;
      cat['unpaidCount'] = total - paid;
      cat['total'] = total;
      cat['meta'] = _calculateCategoryStatusMinTeams(paid, total, minTeams);

      if (paid >= minTeams) {
        real += paid;
      }
    }

    _realTeams = real;
  }

  Future<Map<String, dynamic>> _persistTeamMood(
    Map<String, dynamic> team,
    int mood, {
    double? amount,
  }) async {
    final teamId = (team['_id'] ?? team['id']).toString();
    final response = await _apiService.assignTeamPayment(
      teamId: teamId,
      mood: mood,
      actingUserId: widget.user.id,
      assignedByUserName: widget.user.userName,
      amount: amount,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error HTTP ${response.statusCode}');
    }
    _throwIfAssignPaymentError(response.data);

    final teamOut = response.data is Map ? response.data['team'] : null;
    if (teamOut is Map) return Map<String, dynamic>.from(teamOut);
    throw Exception('Respuesta inválida del servidor (team)');
  }

  Future<List<Map<String, dynamic>>> _persistTeamsMoodBulk(
    List<Map<String, dynamic>> teams,
    int mood, {
    double? amount,
  }) async {
    final updates = teams
        .map(
          (t) => <String, dynamic>{
            'teamId': (t['_id'] ?? t['id']).toString(),
            'mood': mood,
          },
        )
        .toList();
    final response = await _apiService.assignTeamPaymentsBulk(
      updates: updates,
      actingUserId: widget.user.id,
      assignedByUserName: widget.user.userName,
      amount: amount,
      tournamentIdForSocket: widget.tournament.id,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error HTTP ${response.statusCode}');
    }
    _throwIfAssignPaymentError(response.data);

    final out = response.data is Map ? response.data['teams'] : null;
    if (out is List) {
      return out.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  void _showTeamPaymentModal(Map<String, dynamic> team) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TeamPaymentSheet(
        team: team,
        defaultAmount: _paymentAmountDefault,
        onSave: (mood, amount) async {
          try {
            final updated = await _persistTeamMood(team, mood, amount: amount);
            setState(() {
              _applyTeamPaymentUpdatesToStateFine([updated]);
            });
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Estado de pago actualizado'),
                backgroundColor: Color(0xFF34C759),
              ),
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('No se pudo guardar: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            rethrow;
          }
        },
      ),
    );
  }

  void _showAcademyPaymentModal(Map<String, dynamic> academyGroup) {
    final raw = academyGroup['items'] as List? ?? [];
    final teams = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (teams.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: AcademyPaymentSheet(
          academyName: academyGroup['name']?.toString() ?? 'Academia',
          teams: teams,
          defaultAmount: _paymentAmountDefault,
          onApply: (selected, mood, amount) async {
            try {
              final updatedTeams =
                  await _persistTeamsMoodBulk(selected, mood, amount: amount);
              setState(() {
                _applyTeamPaymentUpdatesToStateFine(updatedTeams);
              });
              if (!mounted) return;
              final n = selected.length;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    mood == kMoodPaid
                        ? 'Pago registrado en $n equipo${n == 1 ? '' : 's'}'
                        : 'Pago quitado en $n equipo${n == 1 ? '' : 's'}',
                  ),
                  backgroundColor: const Color(0xFF34C759),
                ),
              );
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo guardar: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              rethrow;
            }
          },
        ),
      ),
    );
  }

  // --- MODAL DE RESTRICCIONES Y PREFERENCIAS ---
  void _showConstraintsModal(Map<String, dynamic> team) {
    // Definir total de jornadas (DashboardTournament no expone gameweeks; usar default)
    const int totalJornadas = 8;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Importante para que el modal crezca
      backgroundColor:
          Colors.transparent, // El modal gestiona su propio fondo redondeado
      builder: (ctx) {
        return TeamConstraintsModal(
          team: team,
          allTeams: _allTeamsRaw, // Enviamos la lista completa para búsquedas
          totalJornadas: totalJornadas,
          currentUser: widget.user,
          onSave: (payload) async {
            // 1. UI Optimista: Actualizamos localmente para feedback inmediato
            setState(() {
              team['constraints'] = payload;
            });
            Navigator.pop(context); // Cerramos modal

            // 2. Preparar el objeto para el Backend
            // IMPORTANTE: Creamos un "mini objeto" que solo tiene el ID y lo que queremos cambiar
            Map<String, dynamic> updateItem = {
              '_id':
                  team['id'] ??
                  team['_id'], // Asegúrate de mandar el ID correcto de CouchDB
              'constraints': payload, // Aquí va todo el objeto de condiciones
            };

            // 3. Llamada al API usando tu función post existente
            try {
              // Usamos tu método .post() que ya tienes en api_service
              final response = await _apiService.post(updateItem);

              if (response.statusCode == 200 || response.statusCode == 201) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Condiciones guardadas correctamente"),
                    backgroundColor: Color(0xFF34C759),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                throw Exception("Error ${response.statusCode}");
              }
            } catch (e) {
              // Revertimos el cambio local si falla (opcional, pero recomendado)
              // setState(() { team['constraints'] = null; });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Error al guardar: $e"),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      },
    );
  }
}
