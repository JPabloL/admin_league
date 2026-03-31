import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // Para fechas
import 'package:intl/date_symbol_data_local.dart'; // <--- IMPORTANTE: Inicialización de locales
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:admin_league/screens/tournament_detail_screen.dart';
import 'package:admin_league/screens/global_schedule_editor_screen.dart';
import 'package:admin_league/models/user_model.dart';
import 'package:admin_league/services/api_service.dart';
import 'package:admin_league/models/dashboard_tournament_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  UserModel? _currentUser;

  List<DashboardTournament> _tournaments = [];
  bool _isLoading = true;

  // --- PALETA DE COLORES "CLEAN TECH" ---
  final Color _bgScaffold = const Color.fromARGB(
    255,
    238,
    238,
    244,
  ); // Gris iOS sistema
  final Color _cardWhite = const Color.fromARGB(255, 233, 234, 236);
  final Color _surfaceInfo = const Color(0xFFF9FAFB); // Gris muy tenue
  final Color _textPrimary = const Color(0xFF111827); // Negro suave
  final Color _textSecondary = const Color(0xFF6B7280); // Gris medio

  // Colores semánticos
  final Color _accentBlue = const Color(0xFF0EA5E9);
  final Color _accentPurple = const Color(0xFF8B5CF6);
  final Color _statusGreen = const Color(0xFF10B981);
  final Color _statusOrange = const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // INICIALIZAMOS EL LOCALE EN ESPAÑOL ANTES DE CARGAR DATOS
    initializeDateFormatting('es_MX', null).then((_) {
      _initData();
    });
  }

  Future<void> _initData() async {
    await _loadUserData();
    if (_currentUser != null) {
      await _loadDashboard();
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString('lga-mn-sr');
    if (userJson != null) {
      setState(() {
        _currentUser = UserModel.fromJson(json.decode(userJson));
      });
    } else {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    try {
      final leagueId = _currentUser!.liga['id'];
      final response = await _apiService.getDashboardTournaments(leagueId);

      if (response.statusCode == 200) {
        final List<dynamic> rawList = response.data;
        setState(() {
          _tournaments = rawList
              .map((json) => DashboardTournament.fromJson(json))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error cargando dashboard: $e");
      setState(() => _isLoading = false);
    }
  }

  void _goToTournamentDetail(DashboardTournament tournament) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TournamentDetailScreen(tournament: tournament, user: _currentUser!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgScaffold,
      drawer: _buildDrawer(),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _textPrimary))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(),
                if (_tournaments.isEmpty)
                  SliverFillRemaining(child: _buildEmptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return _buildStructuredCard(_tournaments[index]);
                      }, childCount: _tournaments.length),
                    ),
                  ),
              ],
            ),
    );
  }

  // --- HEADER COLAPSABLE (SLIVER APP BAR) ---
  Widget _buildSliverAppBar() {
    return SliverAppBar.large(
      backgroundColor: _bgScaffold,
      surfaceTintColor: _bgScaffold,
      elevation: 0,
      expandedHeight: 120,
      pinned: true,
      floating: false,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          color: _textPrimary,
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            backgroundImage: _currentUser?.logo != null
                ? NetworkImage(_currentUser!.logo!)
                : null,
            child: _currentUser?.logo == null
                ? Text(
                    (_currentUser?.userName ?? 'U')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  )
                : null,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        centerTitle: false,
        title: Text(
          "Dashboard",
          style: GoogleFonts.inter(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  // --- TARJETA ESTRUCTURADA ---
  Widget _buildStructuredCard(DashboardTournament tour) {
    String dateFormatted = 'N/A';
    if (tour.limitDate != null) {
      try {
        dateFormatted = DateFormat('d MMM', 'es_MX').format(tour.limitDate!);
      } catch (e) {
        dateFormatted = tour.limitDate.toString().split(' ')[0];
      }
    }

    return GestureDetector(
      onTap: () => _goToTournamentDetail(tour),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _surfaceInfo, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 15,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header compacto: logo + título + flecha
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  Hero(
                    tag: tour.id,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _surfaceInfo,
                        borderRadius: BorderRadius.circular(12),
                        image: tour.logo != null
                            ? DecorationImage(
                                image: NetworkImage(tour.logo!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: tour.logo == null
                          ? Icon(
                              Icons.emoji_events_rounded,
                              size: 22,
                              color: _textSecondary,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tour.name.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tour.subname.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tour.subname,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: _textSecondary,
                  ),
                ],
              ),
            ),

            // Métricas en una sola fila compacta
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricBlock(
                      label: "EQUIPOS",
                      value: "${tour.teamsCount}",
                      color: _accentBlue,
                      icon: Icons.groups_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricBlock(
                      label: "ACADEMIAS",
                      value: "${tour.academiesCount}",
                      color: _accentPurple,
                      icon: Icons.business_outlined,
                    ),
                  ),
                ],
              ),
            ),

            // Footer: fecha + badge en una línea
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: tour.isClosingSoon
                    ? _statusOrange.withAlpha(12)
                    : _surfaceInfo,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: tour.isClosingSoon ? _statusOrange : _textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tour.isClosingSoon
                        ? "Cierra: $dateFormatted"
                        : "Registro hasta $dateFormatted",
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tour.isClosingSoon
                          ? _statusOrange
                          : _textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_currentUser?.canManageSchedules == true)
                    IconButton(
                      icon: Icon(
                        Icons.schedule_rounded,
                        size: 22,
                        color: _accentBlue,
                      ),
                      tooltip: "Agenda de horarios",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ScheduleEditorScreen(
                              tournamentId: tour.id,
                              tournamentName: tour.name,
                              user: _currentUser!,
                            ),
                          ),
                        );
                      },
                    ),
                  _buildStatusBadge(tour),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBlock({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: _surfaceInfo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(DashboardTournament tour) {
    Color color = _statusGreen;
    String text = "EN CURSO";

    if (tour.isClosingSoon) {
      color = _statusOrange;
      text = "CIERRA PRONTO";
    } else if (!tour.isActive) {
      color = _textSecondary;
      text = "FINALIZADO";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_football_rounded,
            size: 80,
            color: _textSecondary.withAlpha(30),
          ),
          const SizedBox(height: 16),
          Text(
            "No hay torneos activos",
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF111827)),
            accountName: Text(
              _currentUser?.userName ?? 'Admin',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(_currentUser?.mail ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              "Cerrar Sesión",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}
