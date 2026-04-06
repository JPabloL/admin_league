class DashboardTournament {
  final String id;
  final String name;
  final String subname;
  final String? logo;
  final DateTime? startDate;
  final DateTime? limitDate;
  final int teamsCount;
  final int academiesCount;
  /// Mínimo de equipos **con pago** para que la categoría cumpla cupo de torneo.
  final int minTeams;
  /// Precios de inscripción (`price` en el doc del torneo); el primero se usa como monto sugerido al registrar pagos.
  final List<dynamic> price;
  final bool isClosingSoon;
  final bool isActive;

  /// Primer valor de [price] como monto por defecto en asignación de pagos.
  double? get defaultPriceAmount =>
      DashboardTournament.defaultAmountFromPriceList(price);

  DashboardTournament({
    required this.id,
    required this.name,
    required this.subname,
    this.logo,
    this.startDate,
    this.limitDate,
    required this.teamsCount,
    required this.academiesCount,
    this.minTeams = 4,
    this.price = const [],
    required this.isClosingSoon,
    required this.isActive,
  });

  factory DashboardTournament.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] ?? {};

    return DashboardTournament(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Torneo',
      subname: json['subname'] ?? '',
      logo: json['logo'],
      startDate: DateTime.tryParse(json['start'] ?? ''),
      limitDate: DateTime.tryParse(json['limitConfirmation'] ?? ''),
      teamsCount: int.tryParse(stats['teamsCount'].toString()) ?? 0,
      academiesCount: int.tryParse(stats['academiesCount'].toString()) ?? 0,
      minTeams: _parseMinTeams(json['minTeams']),
      price: parsePriceField(
        json['price'] ?? json['prices'],
      ),
      isClosingSoon: json['isClosingSoon'] ?? false,
      // Lógica simple: Si tiene equipos y no ha pasado la fecha fin, está activo
      isActive: true,
    );
  }

  static int _parseMinTeams(dynamic v) {
    if (v == null) return 4;
    if (v is int) return v < 1 ? 4 : v;
    return int.tryParse(v.toString()) ?? 4;
  }

  /// `price` puede ser un array, un número, un mapa o string; normalizamos a lista.
  static List<dynamic> parsePriceField(dynamic v) {
    if (v == null) return const [];
    if (v is List) return List<dynamic>.from(v);
    return [v];
  }

  /// Útil cuando `price` viene en otro payload (p. ej. `getTeamsByTournament`).
  static double? defaultAmountFromPriceField(dynamic priceRaw) {
    return defaultAmountFromPriceList(parsePriceField(priceRaw));
  }

  static double? defaultAmountFromPriceList(List<dynamic> list) {
    if (list.isEmpty) return null;
    return coercePriceToDouble(list.first);
  }

  /// Interpreta un ítem de `price`: número, string, o mapa con amount/value/price/…
  static double? coercePriceToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '').trim());
    }
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      for (final k in [
        'amount',
        'value',
        'price',
        'monto',
        'cost',
        'total',
        'importe',
      ]) {
        final x = m[k];
        if (x == null) continue;
        if (x is num) return x.toDouble();
        final d = double.tryParse(x.toString().replaceAll(',', '').trim());
        if (d != null) return d;
      }
    }
    return double.tryParse(v.toString().replaceAll(',', '').trim());
  }
}
