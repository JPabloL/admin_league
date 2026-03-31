class DashboardTournament {
  final String id;
  final String name;
  final String subname;
  final String? logo;
  final DateTime? startDate;
  final DateTime? limitDate;
  final int teamsCount;
  final int academiesCount;
  final bool isClosingSoon;
  final bool isActive;

  DashboardTournament({
    required this.id,
    required this.name,
    required this.subname,
    this.logo,
    this.startDate,
    this.limitDate,
    required this.teamsCount,
    required this.academiesCount,
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
      isClosingSoon: json['isClosingSoon'] ?? false,
      // Lógica simple: Si tiene equipos y no ha pasado la fecha fin, está activo
      isActive: true,
    );
  }
}
