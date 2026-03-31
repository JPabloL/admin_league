class Player {
  final String id;
  final String? rev;
  final String name;
  final String apellidoPa;
  final String apellidoMa;
  final String? photo;
  final String? thumb;
  final String? number;
  final PlayerIdent ident;
  final List<dynamic> teams;
  final IdentityValidation? identidadValidada;

  Player({
    required this.id,
    this.rev,
    required this.name,
    required this.apellidoPa,
    required this.apellidoMa,
    this.photo,
    this.thumb,
    this.number,
    required this.ident,
    required this.teams,
    this.identidadValidada,
  });

  String get fullName => '$name $apellidoPa $apellidoMa'.trim();

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['_id']?.toString() ?? '',
      rev: json['_rev']?.toString(),
      name: json['name']?.toString() ?? '',
      apellidoPa: json['apellidoPa']?.toString() ?? '',
      apellidoMa: json['apellidoMa']?.toString() ?? '',
      photo: json['photo']?.toString(),
      thumb: json['thumb']?.toString(),
      number: json['number']?.toString(),
      ident: PlayerIdent.fromJson(json['ident'] is Map ? json['ident'] : {}),
      teams: json['teams'] is Iterable ? List<dynamic>.from(json['teams']) : [],
      identidadValidada: json['identidadValidada'] != null && json['identidadValidada'] is Map
          ? IdentityValidation.fromJson(json['identidadValidada'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      if (rev != null) '_rev': rev,
      'name': name,
      'apellidoPa': apellidoPa,
      'apellidoMa': apellidoMa,
      'photo': photo,
      'thumb': thumb,
      'number': number,
      'ident': ident.toJson(),
      'teams': teams,
      if (identidadValidada != null) 'identidadValidada': identidadValidada!.toJson(),
    };
  }
}

class PlayerIdent {
  final bool exist;
  final String? img;

  PlayerIdent({
    required this.exist,
    this.img,
  });

  factory PlayerIdent.fromJson(Map<String, dynamic> json) {
    return PlayerIdent(
      exist: json['exist'] == true,
      img: json['img']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exist': exist,
      'img': img,
    };
  }
}

class IdentityValidation {
  final int status; // 1 = no aprobado, 2 = aprobacion parcial, 3 aprobado
  final String fecha;
  final String usuario;
  final bool foto;
  final bool identificacion;
  final String notas;
  final String? vigencia;

  IdentityValidation({
    required this.status,
    required this.fecha,
    required this.usuario,
    required this.foto,
    required this.identificacion,
    required this.notas,
    this.vigencia,
  });

  factory IdentityValidation.fromJson(Map<String, dynamic> json) {
    int parsedStatus = 1;
    if (json['status'] != null) {
      if (json['status'] is int) {
        parsedStatus = json['status'];
      } else {
        parsedStatus = int.tryParse(json['status'].toString()) ?? 1;
      }
    }

    return IdentityValidation(
      status: parsedStatus,
      fecha: json['fecha']?.toString() ?? '',
      usuario: json['usuario']?.toString() ?? '',
      foto: json['foto'] == true || json['foto'] == 1,
      identificacion: json['identificacion'] == true || json['identificacion'] == 1,
      notas: json['notas']?.toString() ?? '',
      vigencia: json['vigencia']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'fecha': fecha,
      'usuario': usuario,
      'foto': foto,
      'identificacion': identificacion,
      'notas': notas,
      if (vigencia != null) 'vigencia': vigencia,
    };
  }
}
