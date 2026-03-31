import 'dart:convert';

class UserModel {
  final String id;
  final Map<String, dynamic> liga; // Se espera como {id, name}
  final String userName;
  final String mail;
  final String rol;
  final String? logo; // Puede ser nulo

  UserModel({
    required this.id,
    required this.liga,
    required this.userName,
    required this.mail,
    required this.rol,
    this.logo,
  });

  bool get isMaster => rol.toLowerCase() == 'master';
  bool get isLogistic => rol.toLowerCase() == 'logistic';
  bool get canManageSchedules =>
      rol.toLowerCase() == 'master' || rol.toLowerCase() == 'logistic';

  // Factory para crear el usuario desde el JSON del API
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      // Usamos ?.toString() para asegurar que si viene un número o ID raro, sea String
      id: json['_id']?.toString() ?? '',

      // Si 'liga' viene como objeto, esto lo convierte a string o evita el crash
      liga: json['liga'] ?? {},

      userName: json['userName']?.toString() ?? '',
      mail: json['mail']?.toString() ?? '',
      rol: json['rol']?.toString() ?? '',

      // AQUÍ suele estar el error: Validamos si 'logo' es realmente un String.
      // Si es un mapa (objeto), lo dejamos como null para que no rompa la app.
      logo: json['logo'] is String ? json['logo'] : null,
    );
  }

  // Para guardar en SharedPreferences (convertir objeto a String)
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'liga': liga,
      'userName': userName,
      'mail': mail,
      'rol': rol,
      'logo': logo,
    };
  }

  // Helper para codificar a String directamente
  String toRawJson() => json.encode(toJson());
}
