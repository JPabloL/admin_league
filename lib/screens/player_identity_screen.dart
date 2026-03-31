import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:admin_league/models/player_model.dart';
import 'package:admin_league/models/user_model.dart';
import 'package:admin_league/services/api_service.dart';
import 'package:admin_league/theme/app_theme.dart';

enum IdentityFilter { all, pending, approved, rejected }

class PlayerIdentityScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final UserModel user;

  const PlayerIdentityScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.user,
  });

  @override
  State<PlayerIdentityScreen> createState() => _PlayerIdentityScreenState();
}

class _PlayerIdentityScreenState extends State<PlayerIdentityScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSilentRefreshing = false;
  List<Player> _players = [];
  String? _error;
  IdentityFilter _currentFilter = IdentityFilter.all;

  // Map to store keys for each card to trigger shake animations
  final Map<String, GlobalKey<_IdentityPlayerCardState>> _cardKeys = {};

  // Timestamp to force image refresh after rotation (Cache busting)
  String _imageTimestamp = DateTime.now().millisecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
  }

  Future<void> _fetchPlayers({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      if (!silent) _isLoading = true;
      _isSilentRefreshing = silent;
      _error = null;
    });
    try {
      final response = await _apiService.getPlayersByTeam(widget.teamId);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        if (!mounted) return;
        setState(() {
          _players = data.map((json) => Player.fromJson(json)).toList();
          _isLoading = false;
          _isSilentRefreshing = false;
        });
        // Pre-carga de las primeras 10 imágenes (thumbnails)
        _precacheImages();
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Error al cargar jugadores (${response.statusCode})';
          _isLoading = false;
          _isSilentRefreshing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de conexión: $e';
        _isLoading = false;
        _isSilentRefreshing = false;
      });
    }
  }

  List<Player> get _filteredPlayers {
    switch (_currentFilter) {
      case IdentityFilter.all:
        return _players;
      case IdentityFilter.pending:
        return _players.where((p) => p.identidadValidada == null).toList();
      case IdentityFilter.approved:
        return _players.where((p) => p.identidadValidada?.status == 3).toList();
      case IdentityFilter.rejected:
        return _players.where((p) => p.identidadValidada != null && p.identidadValidada!.status == 1).toList();
    }
  }

  int get _countPending => _players.where((p) => p.identidadValidada == null).toList().length;
  int get _countApproved => _players.where((p) => p.identidadValidada?.status == 3).toList().length;

  GlobalKey<_IdentityPlayerCardState> _getCardKey(String playerId) {
    if (!_cardKeys.containsKey(playerId)) {
      _cardKeys[playerId] = GlobalKey<_IdentityPlayerCardState>();
    }
    return _cardKeys[playerId]!;
  }

  void _precacheImages() {
    if (_players.isEmpty) return;
    final toPrecache = _players.take(10).toList();
    for (var p in toPrecache) {
      if (p.thumb != null && p.thumb!.isNotEmpty) {
        precacheImage(NetworkImage('${p.thumb}?t=$_imageTimestamp'), context);
      }
      if (p.ident.img != null && p.ident.img!.isNotEmpty) {
        precacheImage(NetworkImage('${p.ident.img}?t=$_imageTimestamp'), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth > 900;
                return CustomScrollView(
                  slivers: [
                    _buildSliverAppBar(),
                    SliverToBoxAdapter(
                      child: AnimatedCrossFade(
                        firstChild: const LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        ),
                        secondChild: const SizedBox(height: 2),
                        crossFadeState: _isSilentRefreshing ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildStatsHeader(isDesktop)),
                    SliverToBoxAdapter(child: _buildFilterTabs()),
                    _error != null
                        ? SliverFillRemaining(child: _buildErrorView())
                        : _filteredPlayers.isEmpty
                            ? SliverFillRemaining(child: _buildEmptyView())
                            : isDesktop
                                ? _buildDesktopGrid()
                                : _buildMobileList(),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 100,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revisión Técnica',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            widget.teamName,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _fetchPlayers(),
        ),
      ],
    );
  }

  Widget _buildStatsHeader(bool isDesktop) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              _buildMiniStat('TOTAL', '${_players.length}', AppColors.textPrimary),
              const SizedBox(width: 12),
              _buildMiniStat('PENDIENTES', '$_countPending', AppColors.warning),
              const SizedBox(width: 12),
              _buildMiniStat('APROBADOS', '$_countApproved', AppColors.success),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFilterChip(IdentityFilter.all, 'Todos'),
              _buildFilterChip(IdentityFilter.pending, 'Pendientes'),
              _buildFilterChip(IdentityFilter.approved, 'Aprobados'),
              _buildFilterChip(IdentityFilter.rejected, 'No Aptos'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(IdentityFilter filter, String label) {
    final isSelected = _currentFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (val) => setState(() => _currentFilter = filter),
        backgroundColor: Colors.white,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: BorderSide(color: isSelected ? Colors.transparent : AppColors.border),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final player = _filteredPlayers[index];
            return IdentityPlayerCard(
              key: _getCardKey(player.id),
              player: player,
              isDesktop: false,
              user: widget.user,
              onQuickUpdate: (status) => _quickUpdate(player, status),
              onRotate: () => _rotatePhoto(player),
              onReview: () => _showValidationModal(player),
              onImageTap: (url) => _showFullScreenImage(url),
              imageTimestamp: _imageTimestamp,
            );
          },
          childCount: _filteredPlayers.length,
        ),
      ),
    );
  }

  Widget _buildDesktopGrid() {
    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 600,
          mainAxisSpacing: 24,
          crossAxisSpacing: 24,
          mainAxisExtent: 440,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final player = _filteredPlayers[index];
            return IdentityPlayerCard(
              key: _getCardKey(player.id),
              player: player,
              isDesktop: true,
              user: widget.user,
              onQuickUpdate: (status) => _quickUpdate(player, status),
              onRotate: () => _rotatePhoto(player),
              onReview: () => _showValidationModal(player),
              onImageTap: (url) => _showFullScreenImage(url),
              imageTimestamp: _imageTimestamp,
            );
          },
          childCount: _filteredPlayers.length,
        ),
      ),
    );
  }

  Future<void> _quickUpdate(Player player, int status) async {
    final oldValidation = player.identidadValidada;
    final now = DateTime.now();
    final fechaStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final vigenciaStr = status == 3
        ? DateFormat('yyyy-MM-dd').format(DateTime(now.year + 1, now.month, now.day))
        : null;

    final newValidation = IdentityValidation(
      status: status,
      fecha: fechaStr,
      usuario: widget.user.userName,
      foto: status == 3,
      identificacion: status == 3,
      notas: '',
      vigencia: vigenciaStr,
    );

    final playerIndex = _players.indexWhere((p) => p.id == player.id);
    if (playerIndex != -1) {
      setState(() {
        final updatedPlayer = Player(
          id: player.id,
          rev: player.rev,
          name: player.name,
          apellidoPa: player.apellidoPa,
          apellidoMa: player.apellidoMa,
          photo: player.photo,
          thumb: player.thumb,
          number: player.number,
          ident: player.ident,
          teams: player.teams,
          identidadValidada: newValidation,
        );
        _players[playerIndex] = updatedPlayer;
      });
    }

    try {
      final response = await _apiService.validatePlayerAndSyncTeam(
        playerId: player.id,
        teamId: widget.teamId,
        validationData: newValidation.toJson(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _fetchPlayers(silent: true);
      } else {
        throw Exception('API error');
      }
    } catch (e) {
      _cardKeys[player.id]?.currentState?.shake();

      if (mounted) {
        setState(() {
          if (playerIndex != -1) {
            final revertedPlayer = Player(
              id: player.id,
              rev: player.rev,
              name: player.name,
              apellidoPa: player.apellidoPa,
              apellidoMa: player.apellidoMa,
              photo: player.photo,
              thumb: player.thumb,
              number: player.number,
              ident: player.ident,
              teams: player.teams,
              identidadValidada: oldValidation,
            );
            _players[playerIndex] = revertedPlayer;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error al actualizar: ${player.name}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _rotatePhoto(Player player) async {
    try {
      final response = await _apiService.rotatePlayerPhoto(player.id);
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _imageTimestamp = DateTime.now().millisecondsSinceEpoch.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Foto rotada correctamente'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        throw Exception('Error al rotar');
      }
    } catch (e) {
      _cardKeys[player.id]?.currentState?.shake();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ No se pudo rotar la foto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_error!, style: AppTextStyle.headline),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: () => _fetchPlayers(), child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No hay jugadores en esta categoría',
            style: AppTextStyle.headline.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network('$url?t=$_imageTimestamp', fit: BoxFit.contain))),
      ),
    ));
  }

  void _showValidationModal(Player player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ValidationForm(
        player: player,
        teamId: widget.teamId,
        currentUser: widget.user,
        apiService: _apiService,
        onSaved: () => _fetchPlayers(silent: true),
      ),
    );
  }
}

class IdentityPlayerCard extends StatefulWidget {
  final Player player;
  final bool isDesktop;
  final UserModel user;
  final Function(int) onQuickUpdate;
  final VoidCallback onReview;
  final VoidCallback onRotate;
  final Function(String) onImageTap;
  final String imageTimestamp;

  const IdentityPlayerCard({
    super.key,
    required this.player,
    required this.isDesktop,
    required this.user,
    required this.onQuickUpdate,
    required this.onReview,
    required this.onRotate,
    required this.onImageTap,
    required this.imageTimestamp,
  });

  @override
  State<IdentityPlayerCard> createState() => _IdentityPlayerCardState();
}

class _IdentityPlayerCardState extends State<IdentityPlayerCard> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 15).animate(
      CurvedAnimation(
        parent: _shakeController,
        curve: _ShakeCurve(),
      ),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void shake() {
    _shakeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final validation = player.identidadValidada;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.fullName,
                          style: GoogleFonts.inter(
                            fontSize: widget.isDesktop ? 18 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '#${player.number ?? 'S/N'}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                  child: Column(
                    key: ValueKey(validation?.status),
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildValidationStatusBadge(validation),
                      if (validation != null) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person_outline_rounded, size: 10, color: AppColors.textTertiary),
                                  const SizedBox(width: 4),
                                  Text(
                                    validation.usuario,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_outlined, size: 10, color: AppColors.textTertiary),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDateForDisplay(validation.fecha),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                              if (validation.status == 3 && validation.vigencia != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Expira: ${_formatDateForDisplay(validation.vigencia!)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.surfaceVariant),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: _buildImageSection('Foto', player.thumb ?? player.photo, showRotate: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildImageSection('Identificación', player.ident.img)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (validation != null && validation.notas.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        validation.notas,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onReview,
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text('REVISAR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceVariant,
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    if (widget.player.identidadValidada?.status != 3) ...[
                      IconButton.filled(
                        onPressed: () => widget.onQuickUpdate(3),
                        icon: const Icon(Icons.check_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.all(14),
                        ),
                        tooltip: 'Aprobación Rápida',
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => widget.onQuickUpdate(1),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.error,
                          padding: const EdgeInsets.all(14),
                        ),
                        tooltip: 'Rechazo Rápida',
                      ),
                    ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationStatusBadge(IdentityValidation? validation, {Key? key}) {
    if (validation == null) return _buildBadge('PENDIENTE', AppColors.textTertiary, Icons.access_time_rounded, key: key);
    switch (validation.status) {
      case 3: return _buildBadge('APROBADO', AppColors.success, Icons.verified_rounded, key: key);
      case 2: return _buildBadge('PARCIAL', AppColors.warning, Icons.rule_rounded, key: key);
      case 1:
      default: return _buildBadge('NO APTO', AppColors.error, Icons.gpp_bad_rounded, key: key);
    }
  }

  Widget _buildBadge(String label, Color color, IconData icon, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildImageSection(String label, String? url, {bool showRotate = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 1.0),
              ),
            ),
            if (showRotate && url != null)
              GestureDetector(
                onTap: widget.onRotate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.rotate_right_rounded, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'ROTAR',
                        style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => url != null ? widget.onImageTap(url) : null,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: url == null || url.isEmpty
                    ? const Center(child: Icon(Icons.no_photography_outlined, color: AppColors.textTertiary, size: 32))
                    : Image.network(
                        '$url?t=${widget.imageTimestamp}',
                        fit: BoxFit.cover,
                        cacheWidth: 400, // Optimización de memoria
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined, color: AppColors.error),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                  : null,
                              strokeWidth: 2,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateForDisplay(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      DateTime? dt;
      bool hasTime = dateStr.contains(':');
      if (hasTime) {
        dt = DateFormat('yyyy-MM-dd HH:mm').parse(dateStr);
      } else {
        dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      }

      if (hasTime) {
        return DateFormat('dd - MMM - yyyy | HH:mm').format(dt);
      } else {
        return DateFormat('dd - MMM - yyyy').format(dt);
      }
    } catch (e) {
      return dateStr;
    }
  }
}

class _ShakeCurve extends Curve {
  @override
  double transformInternal(double t) {
    return math.sin(t * 3 * 2 * math.pi);
  }
}

class _ValidationForm extends StatefulWidget {
  final Player player;
  final String teamId;
  final UserModel currentUser;
  final ApiService apiService;
  final VoidCallback onSaved;

  const _ValidationForm({required this.player, required this.teamId, required this.currentUser, required this.apiService, required this.onSaved});

  @override
  State<_ValidationForm> createState() => _ValidationFormState();
}

class _ValidationFormState extends State<_ValidationForm> {
  late int _status;
  late bool _fotoValida;
  late bool _identificacionValida;
  final TextEditingController _notasController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.player.identidadValidada;
    _status = v?.status ?? 1;
    _fotoValida = v?.foto ?? false;
    _identificacionValida = v?.identificacion ?? false;
    _notasController.text = v?.notas ?? '';
  }

  void _updateStatus(int value) {
    setState(() {
      _status = value;
      if (_status == 3) {
        _fotoValida = true;
        _identificacionValida = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32))),
      padding: EdgeInsets.only(left: 24, right: 24, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Text('Validar Identidad', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(widget.player.fullName, style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              _buildStatusSelector(),
              const SizedBox(height: 24),
              _buildSwitchTile('Foto de perfil válida', _fotoValida, (v) => setState(() => _fotoValida = v)),
              const SizedBox(height: 12),
              _buildSwitchTile('Identificación válida', _identificacionValida, (v) => setState(() => _identificacionValida = v)),
              const SizedBox(height: 24),
              TextField(
                controller: _notasController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'NOTAS / OBSERVACIONES',
                  labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('GUARDAR VALIDACIÓN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _buildStatusItem(1, 'NO APTO', AppColors.error),
          _buildStatusItem(2, 'PARCIAL', AppColors.warning),
          _buildStatusItem(3, 'APTO', AppColors.success),
        ],
      ),
    );
  }

  Widget _buildStatusItem(int value, String label, Color color) {
    final isSelected = _status == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateStatus(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : null),
          child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: isSelected ? color : AppColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700))),
        Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: AppColors.success.withValues(alpha: 0.5)),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final now = DateTime.now();
    final fechaStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final vigenciaStr = _status == 3
        ? DateFormat('yyyy-MM-dd').format(DateTime(now.year + 1, now.month, now.day))
        : null;

    try {
      final validation = IdentityValidation(
        status: _status,
        fecha: fechaStr,
        usuario: widget.currentUser.userName,
        foto: _fotoValida,
        identificacion: _identificacionValida,
        notas: _notasController.text,
        vigencia: vigenciaStr,
      );
      
      final response = await widget.apiService.validatePlayerAndSyncTeam(
        playerId: widget.player.id,
        teamId: widget.teamId,
        validationData: validation.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context);
          widget.onSaved();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
