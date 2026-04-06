import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Valores de `mood` en documento de equipo (CouchDB).
const int kMoodUnpaid = 0;
const int kMoodPaid = 1;

/// Modal para un solo equipo: elegir sin pago / con pago y guardar.
class TeamPaymentSheet extends StatefulWidget {
  final Map<String, dynamic> team;
  final Future<void> Function(int mood, double? amount) onSave;
  /// Monto inicial si no hay `paymentRegistration.amount` (p. ej. primer precio del torneo).
  final double? defaultAmount;

  const TeamPaymentSheet({
    super.key,
    required this.team,
    required this.onSave,
    this.defaultAmount,
  });

  @override
  State<TeamPaymentSheet> createState() => _TeamPaymentSheetState();
}

class _TeamPaymentSheetState extends State<TeamPaymentSheet> {
  late int _mood;
  bool _saving = false;
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = widget.team['mood'];
    if (m == null) {
      _mood = kMoodUnpaid;
    } else if (m is int) {
      _mood = m;
    } else {
      _mood = int.tryParse(m.toString()) ?? kMoodUnpaid;
    }
    final pr = widget.team['paymentRegistration'];
    if (pr is Map && pr['amount'] != null) {
      _amountController.text = pr['amount'].toString();
    } else if (widget.defaultAmount != null) {
      final d = widget.defaultAmount!;
      _amountController.text = d == d.roundToDouble()
          ? d.toInt().toString()
          : d.toString();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final t = _amountController.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_mood, _parseAmount());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.team['name']?.toString() ?? 'Equipo';

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom + bottomInset,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Asignar pago',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Estado de inscripción',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: kMoodUnpaid,
                    label: Text('Sin pago'),
                    icon: Icon(Icons.money_off_outlined, size: 18),
                  ),
                  ButtonSegment<int>(
                    value: kMoodPaid,
                    label: Text('Con pago'),
                    icon: Icon(Icons.payments_outlined, size: 18),
                  ),
                ],
                selected: {_mood},
                onSelectionChanged: (s) {
                  setState(() => _mood = s.first);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Monto (opcional)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Ej. 1500',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixText: r'$ ',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF2E7D32),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Guardar',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal por academia: elegir uno o varios equipos y aplicar con pago o sin pago.
class AcademyPaymentSheet extends StatefulWidget {
  final String academyName;
  final List<Map<String, dynamic>> teams;
  final Future<void> Function(
    List<Map<String, dynamic>> teams,
    int mood,
    double? amount,
  ) onApply;
  final double? defaultAmount;

  const AcademyPaymentSheet({
    super.key,
    required this.academyName,
    required this.teams,
    required this.onApply,
    this.defaultAmount,
  });

  @override
  State<AcademyPaymentSheet> createState() => _AcademyPaymentSheetState();
}

class _AcademyPaymentSheetState extends State<AcademyPaymentSheet> {
  late Set<String> _selectedIds;
  bool _working = false;
  final TextEditingController _bulkAmountController = TextEditingController();

  String _teamKey(Map<String, dynamic> t) =>
      (t['_id'] ?? t['id']).toString();

  @override
  void initState() {
    super.initState();
    _selectedIds = {};
    if (widget.defaultAmount != null) {
      final d = widget.defaultAmount!;
      _bulkAmountController.text = d == d.roundToDouble()
          ? d.toInt().toString()
          : d.toString();
    }
  }

  @override
  void dispose() {
    _bulkAmountController.dispose();
    super.dispose();
  }

  double? _parseBulkAmount() {
    final t = _bulkAmountController.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  void _toggle(String id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds = widget.teams.map(_teamKey).toSet();
    });
  }

  void _selectNone() {
    setState(() => _selectedIds.clear());
  }

  void _selectUnpaidOnly() {
    setState(() {
      _selectedIds = widget.teams
          .where((t) {
            final m = t['mood'];
            final v = m is int ? m : int.tryParse(m.toString()) ?? 0;
            return v == kMoodUnpaid;
          })
          .map(_teamKey)
          .toSet();
    });
  }

  void _selectPaidOnly() {
    setState(() {
      _selectedIds = widget.teams
          .where((t) {
            final m = t['mood'];
            final v = m is int ? m : int.tryParse(m.toString()) ?? 0;
            return v != kMoodUnpaid;
          })
          .map(_teamKey)
          .toSet();
    });
  }

  List<Map<String, dynamic>> _selectedTeams() {
    return widget.teams
        .where((t) => _selectedIds.contains(_teamKey(t)))
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
  }

  Future<void> _apply(int mood) async {
    final list = _selectedTeams();
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un equipo'),
          backgroundColor: Color(0xFFE65100),
        ),
      );
      return;
    }
    setState(() => _working = true);
    try {
      await widget.onApply(list, mood, _parseBulkAmount());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> paidTeams = [];
    final List<Map<String, dynamic>> unpaidTeams = [];
    for (final t in widget.teams) {
      final m = t['mood'];
      final v = m is int ? m : int.tryParse(m.toString()) ?? 0;
      if (v != kMoodUnpaid) {
        paidTeams.add(t);
      } else {
        unpaidTeams.add(t);
      }
    }

    final paidSelected = paidTeams
        .map(_teamKey)
        .where(_selectedIds.contains)
        .length;
    final unpaidSelected = unpaidTeams
        .map(_teamKey)
        .where(_selectedIds.contains)
        .length;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pagos por academia',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.academyName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF007AFF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Todos'),
                        onPressed: _selectAll,
                      ),
                      ActionChip(
                        label: const Text('Ninguno'),
                        onPressed: _selectNone,
                      ),
                      ActionChip(
                        label: const Text('Solo con pago'),
                        onPressed: _selectPaidOnly,
                      ),
                      ActionChip(
                        label: const Text('Solo sin pago'),
                        onPressed: _selectUnpaidOnly,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF2E7D32).withAlpha(80),
                        ),
                      ),
                      child: Text(
                        'Con pago (${paidTeams.length}) · seleccionados: $paidSelected',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...paidTeams.map((t) {
                    final id = _teamKey(t);
                    return CheckboxListTile(
                      dense: true,
                      value: _selectedIds.contains(id),
                      onChanged: (c) => _toggle(id, c),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF2E7D32),
                      title: Text(
                        t['name']?.toString() ?? '—',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                      subtitle: Text(
                        t['category']?['name']?.toString() ?? '',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF8E8E93),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFC62828).withAlpha(90),
                        ),
                      ),
                      child: Text(
                        'Sin pago (${unpaidTeams.length}) · seleccionados: $unpaidSelected',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFC62828),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...unpaidTeams.map((t) {
                    final id = _teamKey(t);
                    return CheckboxListTile(
                      dense: true,
                      value: _selectedIds.contains(id),
                      onChanged: (c) => _toggle(id, c),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFFC62828),
                      title: Text(
                        t['name']?.toString() ?? '—',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: const Color(0xFFB71C1C),
                        ),
                      ),
                      subtitle: Text(
                        t['category']?['name']?.toString() ?? '',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF8E8E93),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: _working
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Monto mismo para todos (opcional)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8E8E93),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _bulkAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Vacío = sin monto',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixText: r'$ ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _apply(kMoodPaid),
                          icon: const Icon(Icons.payments_outlined, size: 20),
                          label: Text(
                            'Registrar pago a seleccionados',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC62828),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _apply(kMoodUnpaid),
                          icon: const Icon(Icons.money_off_outlined, size: 20),
                          label: Text(
                            'Quitar pago a seleccionados',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
