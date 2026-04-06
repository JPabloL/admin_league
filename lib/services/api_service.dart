import 'package:dio/dio.dart';

class ApiService {
  // URLs Base (Mismas que tenías en Angular)
  static const String _apiCdb = 'https://server.cuerposallimite.net';

  // Token constante
  static const String _token = '3es_ldo5%4d';

  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _apiCdb,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  // Helper privado para construir el body estándar
  Map<String, dynamic> _buildBody({
    required String view,
    required String mood,
    dynamic search,
    Map<String, dynamic>? extraData,
  }) {
    final Map<String, dynamic> body = {
      'token': _token,
      'view': view,
      'mood': mood,
    };
    if (search != null) {
      body['search'] = search;
    }
    if (extraData != null) {
      body.addAll(extraData);
    }
    return body;
  }

  // --- MÉTODOS DE MAIL ---

  Future<Response> sendWelcomeMail(Map<String, dynamic> params) async {
    return await _dio.post('/sendWelcomeMail', data: params);
  }

  Future<Response> sendRecoveryMail(Map<String, dynamic> params) async {
    return await _dio.post('/sendMailRecoverNffl', data: params);
  }

  // --- SESIÓN Y USUARIOS ---

  Future<Response> initSession(String mail, String pass) async {
    final params = [mail, pass];
    final data = {
      'token': _token,
      'view': 'liga',
      'mood': 'session',
      'search': params,
    };
    return await _dio.post('/viewNlff', data: data);
  }

  Future<Response> checkExistUser(String mail) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'users', mood: 'byEmail', search: mail),
    );
  }

  Future<Response> checkRecoverytUser(String mail) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'users', mood: 'recovery', search: mail),
    );
  }

  Future<Response> getTutorById(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'users', mood: 'tutorById', search: id),
    );
  }

  Future<Response> getTutorByEmail(String mail) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'users', mood: 'tutorByMail', search: mail),
    );
  }

  Future<Response> getUsersByEmail(String email) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'users', mood: 'allByEmail', search: email),
    );
  }

  // --- JUGADORES ---

  Future<Response> getPlayerByCurp(String curp) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'byCurp', search: curp),
    );
  }

  Future<Response> getPlayerByEmail(String mail) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'byEmail', search: mail),
    );
  }

  // Paginación
  Future<Response> getPendingPlayersByTournament(
    String tournamentId,
    int limit,
    int skip,
  ) async {
    final data = {
      'token': _token,
      'view': 'players',
      'mood': 'byTournamentPending',
      'search': tournamentId,
      'options': {'limit': limit, 'skip': skip},
    };
    return await _dio.post('/withPagination', data: data);
  }

  Future<Response> getMyPartners(List<dynamic> items) async {
    return await _dio.post(
      '/viewNlffMultiKeys',
      data: _buildBody(view: 'players', mood: 'multipleTeam', search: items),
    );
  }

  Future<Response> getMyPlayers(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'byAcademy', search: id),
    );
  }

  Future<Response> getMyPlayersTeams(String id) async {
    final data = {'token': _token, 'search': id};
    return await _dio.post('/getPlayers&Teams', data: data);
  }

  Future<Response> getPlayersByTeam(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'byTeam', search: id),
    );
  }

  Future<Response> getPlayersById(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'all', search: id),
    );
  }

  Future<Response> searchPlayer(String user) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'players', mood: 'byUserName', search: user),
    );
  }

  Future<Response> getPlayersTeamAssist(
    String idAcademy,
    String idTeam,
    String idTour,
  ) async {
    final data = {
      'token': _token,
      'idAcademy': idAcademy,
      'idTeam': idTeam,
      'idTournament': idTour,
    };
    return await _dio.post('/players&Assist', data: data);
  }

  // --- EQUIPOS Y ACADEMIAS ---

  Future<Response> getMyTeamsCats(String id) async {
    final data = {'token': _token, 'search': id};
    return await _dio.post('/getCat&Teams', data: data);
  }

  Future<Response> getMyTeams(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'teams', mood: 'byAcademy', search: id),
    );
  }

  Future<Response> getAllTeams() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'teams', mood: 'all'),
    );
  }

  Future<Response> getAllAcademys() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'academy', mood: 'all'),
    );
  }

  Future<Response> getAcademysByLeague(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'academy', mood: 'byLeague', search: id),
    );
  }

  Future<Response> getAcademysByTournament(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'academy', mood: 'byTournament', search: id),
    );
  }

  // Future<Response> getTeamsByTournament(String id) async {
  //   return await _dio.post(
  //     '/viewNlff',
  //     data: _buildBody(view: 'teams', mood: 'byTournament', search: id),
  //   );
  // }

  Future<Response> getTeamsAndSchedules(String tournamentId) async {
    return await _dio.post(
      '/getTeamsByTournament',
      data: {'token': '3es_ldo5%4d', 'tournamentId': tournamentId},
    );
  }

  Future<Response> getTeamsByTournamentCat(
    String tournament,
    String cate,
  ) async {
    final items = [tournament, cate];
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'teams', mood: 'byTournamentCat', search: items),
    );
  }

  Future<Response> getTeamsPaymentsByTournament(String id) async {
    final data = {'token': _token, 'id': id};
    return await _dio.post('/getTeamsPaymentsByTour', data: data);
  }

  Future<Response> generateOfficialSchedule(
    String tournamentId,
    String draftId,
  ) async {
    return await _dio.post(
      '/generateOfficialSchedule',
      data: {
        'token': _token, // Tu token de seguridad
        'tournamentId': tournamentId,
        'draftId': draftId,
      },
    );
  }

  Future<Response> getJornadaContext(
    String tournamentId,
    int jornadaNumber,
  ) async {
    return await _dio.post(
      '/getJornadaContext', // La ruta que definimos en el backend
      data: {
        'token': _token,
        'tournamentId': tournamentId,
        'jornadaNumber': jornadaNumber, // Enviamos el entero directo
      },
    );
  }

  Future<Response> getDocById(String id) async {
    final data = {'token': _token, 'id': id};
    return await _dio.post('/get-doc', data: data);
  }

  Future<Response> getOfficialScheduleSearch(
    String tournamentId,
    String categoryName,
  ) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(
        view: 'tournament',
        mood:
            'oficialScheduleCat', // Asegúrate de que tu backend/vista soporte este mood o tipo
        search: [tournamentId, categoryName],
      ),
    );
  }

  Future<Response> deletePayment(String paymentId, String paymentRev) async {
    final data = {
      'token': _token,
      'paymentId': paymentId,
      'paymentRev': paymentRev,
    };
    return await _dio.post('/deletePayment', data: data);
  }

  Future<Response> getTeamsByCate(String name) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'teams', mood: 'byCat', search: name),
    );
  }

  Future<Response> getRequestsAcademy(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'requests', mood: 'byAcademy', search: id),
    );
  }

  Future<Response> checkExistClaveAcademy(String clave) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'academy', mood: 'byClave', search: clave),
    );
  }

  Future<Response> getTeamsShort() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'teams', mood: 'short'),
    );
  }

  Future<Response> getTeamsByeAcademyTournament(dynamic datos) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(
        view: 'teams',
        mood: 'byAcademyTournament',
        search: datos,
      ),
    );
  }

  Future<Response> getDraft(String tournamentId, String categoryName) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(
        view: 'tournament', // Cambiado según instrucción
        mood: 'draft', // Cambiado según instrucción
        search: [
          tournamentId,
          categoryName,
        ], // Variables necesarias para encontrar el doc único
      ),
    );
  }

  Future<Response> getMyAcademy(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'academy', mood: 'all', search: id),
    );
  }

  // --- TORNEOS Y PARTIDOS ---

  Future<Response> getCategories() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'categories', mood: 'all'),
    );
  }

  Future<Response> getAllMatchs() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'match', mood: 'all'),
    );
  }

  Future<Response> getAllMatchsTournament(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'match', mood: 'byTournament', search: id),
    );
  }

  Future<Response> getAllMatchsByLeague(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'match', mood: 'byLeague', search: id),
    );
  }

  Future<Response> getRefById(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'referees', mood: 'all', search: id),
    );
  }

  Future<Response> getAllMeetings() async {
    return await _dio.post(
      '/viewNlffMultiKeys',
      data: _buildBody(
        view: 'meetings',
        mood: 'byMood',
        search: ['coach', 'all'],
      ),
    );
  }

  Future<Response> getAllActions() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'match', mood: 'actions'),
    );
  }

  Future<Response> getAllTournaments() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'tournament', mood: 'allActive'),
    );
  }

  Future<Response> getActiveTournamentsShort() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'tournament', mood: 'short'),
    );
  }

  Future<Response> getRolesCate(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'tournament', mood: 'roles', search: id),
    );
  }

  Future<Response> getTournamentsLeague(dynamic search) async {
    print(search);
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(
        view: 'tournament',
        mood: 'byLeagueFull',
        search: search,
      ),
    );
  }

  Future<Response> generateTournamentDraft({
    required int numTeams,
    required int targetGames,
    required int targetWeeks,
  }) async {
    try {
      // Usamos el token que manejas en tus otros endpoints
      const String token = '3es_ldo5%4d';

      final data = {
        "token": token,
        "numTeams": numTeams,
        "targetGames": targetGames,
        "targetWeeks": targetWeeks,
      };

      // Asumiendo que usas Dio (por el estilo de tus snippets previos)
      // Si usas http estándar, la sintaxis cambia ligeramente
      final response = await _dio.post('/generateTournamentDraft', data: data);

      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> editMultipleNlff(List<dynamic> items) async {
    return await _dio.post(
      '/editMultipleNlff',
      data: {
        'token': '3es_ldo5%4d',
        'items': items, // Tu endpoint espera 'items', no 'updates'
      },
    );
  }

  // EN api_service.dart

  Future<Response> generateComplexDraft({
    required int targetGames,
    required int targetWeeks,
    required List<Map<String, dynamic>> groupsConfig,
    // --- NUEVOS PARÁMETROS OPCIONALES ---
    String? tournamentId,
    String? categoryName,
    bool useHistory = false, // Por defecto es false (draft nuevo desde cero)
  }) async {
    try {
      const String token = '3es_ldo5%4d';

      final data = {
        "token": token,
        "targetGames": targetGames,
        "targetWeeks": targetWeeks,
        "groups": groupsConfig,
        // --- ENVIAMOS LA INFORMACIÓN AL BACKEND ---
        "tournamentId": tournamentId,
        "categoryName": categoryName,
        "useHistory": useHistory,
      };

      // Apuntamos al endpoint
      return await _dio.post('/generateComplexDraft', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> updateTeamGroups(List<Map<String, dynamic>> updates) async {
    return await _dio.post(
      '/updateTeamGroups',
      data: {"token": '3es_ldo5%4d', "teams": updates},
    );
  }

  // --- DASHBOARD (NUEVO ENDPOINT OPTIMIZADO) ---

  Future<Response> getDashboardTournaments(String leagueId) async {
    // Construimos el body específico para este endpoint de Node.js
    final data = {
      'token': _token, // Usa la variable _token que ya tienes definida arriba
      'leagueId': leagueId,
    };

    // Hacemos la petición POST al nuevo endpoint que creamos en el backend
    return await _dio.post('/getDashboardTournaments', data: data);
  }

  Future<Response> getToursAllData(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'tournament', mood: 'byLeagueAll', search: id),
    );
  }

  Future<Response> getTournamentById(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'tournament', mood: 'byId', search: id),
    );
  }

  Future<Response> getMatchsByTournament(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'match', mood: 'byTournament', search: id),
    );
  }

  Future<Response> getMatchByTournament(List<dynamic> items) async {
    return await _dio.post(
      '/viewNlffMultiKeys',
      data: _buildBody(view: 'match', mood: 'byTournament', search: items),
    );
  }

  Future<Response> getActionsMatch(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'match', mood: 'actions', search: id),
    );
  }

  Future<Response> getChecks(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'match', mood: 'check', search: id),
    );
  }

  Future<Response> getMatch(String id) async {
    final data = {'token': _token, 'search': id};
    return await _dio.post('/getMatch', data: data);
  }

  Future<Response> getActions() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'match', mood: 'actions'),
    );
  }

  Future<Response> getTournaments(String id) async {
    return await _dio.post(
      '/viewNlff',
      data: _buildBody(view: 'tournament', mood: 'byLeague', search: id),
    );
  }

  Future<Response> getRefereesShort() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'referees', mood: 'short'),
    );
  }

  Future<Response> getNews() async {
    return await _dio.post(
      '/viewNlffNoKey',
      data: _buildBody(view: 'news', mood: 'publics'),
    );
  }

  // --- EDICIÓN Y ELIMINACIÓN (CRUD) ---

  // --- JUGADORES Y VALIDACIÓN ---

  Future<Response> rotatePlayerPhoto(String playerId) async {
    final data = {
      'token': _token,
      'playerId': playerId,
    };
    return await _dio.post('/rotatePlayerPhoto', data: data);
  }

  Future<Response> validatePlayerAndSyncTeam({
    required String playerId,
    required String teamId,
    required Map<String, dynamic> validationData,
  }) async {
    final data = {
      'token': _token,
      'playerId': playerId,
      'teamId': teamId,
      'validationData': validationData,
    };
    return await _dio.post('/validatePlayerAndSyncTeam', data: data);
  }

  Future<Response> post(Map<String, dynamic> item) async {
    final data = {'token': _token, 'item': item};
    return await _dio.post('/editNlff', data: data);
  }

  Future<Response> postMultiple(List<dynamic> items) async {
    final data = {'token': _token, 'items': items};
    return await _dio.post('/editMultipleNlff', data: data);
  }

  /// Actualiza solo `mood` y metadatos de pago en el servidor (documento equipo intacto).
  Future<Response> assignTeamPayment({
    required String teamId,
    required int mood,
    required String actingUserId,
    String? assignedByUserName,
    double? amount,
    String? currency,
    String? notes,
  }) async {
    return await _dio.post(
      '/assignTeamPayment',
      data: {
        'token': _token,
        'teamId': teamId,
        'mood': mood,
        'actingUserId': actingUserId,
        if (assignedByUserName != null && assignedByUserName.isNotEmpty)
          'assignedByUserName': assignedByUserName,
        if (amount != null) 'amount': amount,
        if (currency != null) 'currency': currency,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// Varios equipos; el servidor hace get/merge por cada uno (no reemplaza el doc completo).
  Future<Response> assignTeamPaymentsBulk({
    required List<Map<String, dynamic>> updates,
    required String actingUserId,
    String? assignedByUserName,
    double? amount,
    String? tournamentIdForSocket,
  }) async {
    return await _dio.post(
      '/assignTeamPaymentsBulk',
      data: {
        'token': _token,
        'updates': updates,
        'actingUserId': actingUserId,
        if (assignedByUserName != null && assignedByUserName.isNotEmpty)
          'assignedByUserName': assignedByUserName,
        if (amount != null) 'amount': amount,
        if (tournamentIdForSocket != null)
          'tournamentIdForSocket': tournamentIdForSocket,
      },
    );
  }

  Future<Response> delImage(Map<String, dynamic> item) async {
    final data = {'token': _token, 'item': item};
    return await _dio.post('/deleteImageNlff', data: data);
  }

  Future<Response> delDoc(Map<String, dynamic> item, String type) async {
    final data = {'token': _token, 'item': item, 'docType': type};
    return await _dio.post('/deleteDocNlff', data: data);
  }

  Future<Response> remove(Map<String, dynamic> item) async {
    item['_deleted'] = true;
    final data = {'token': _token, 'item': item};
    return await _dio.post('/editNlff', data: data);
  }

  // --- SUBIDA DE ARCHIVOS (FILE UPLOAD) ---
  // Nota: Aquí se usa FormData, que es especial de Dio

  Future<Response> upload(String id, dynamic file) async {
    // Asumimos que 'file' es un File de dart:io o una ruta String
    // Si viene del FilePicker, suele ser un path.

    // Si 'file' es un String (ruta):
    String fileName = file.path.split('/').last;

    FormData formData = FormData.fromMap({
      "id": id,
      "photo": await MultipartFile.fromFile(file.path, filename: fileName),
    });

    return await _dio.post('/uploadFiles/$id', data: formData);
  }

  Future<Response> uploadAcademy(String id, dynamic file) async {
    String fileName = file.path.split('/').last;
    FormData formData = FormData.fromMap({
      "id": id,
      "photo": await MultipartFile.fromFile(file.path, filename: fileName),
    });

    return await _dio.post('/uploadFilesAcademy/$id', data: formData);
  }

  Future<Response> uploadPdf(String id, dynamic file, String type) async {
    String fileName = file.path.split('/').last;
    FormData formData = FormData.fromMap({
      "id": id,
      "pdf": await MultipartFile.fromFile(file.path, filename: fileName),
    });

    return await _dio.post('/uploadPdf/$id&$type', data: formData);
  }
}
