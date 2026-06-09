import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';

class CoLocatairesEditScreen extends StatefulWidget {
  final String logementId;
  const CoLocatairesEditScreen({super.key, required this.logementId});

  @override
  State<CoLocatairesEditScreen> createState() => _CoLocatairesEditScreenState();
}

class _CoLocatairesEditScreenState extends State<CoLocatairesEditScreen> {
  static const _bg = Color(0xFFEFF1F7);
  static const _ink = Color(0xFF1F1F2E);
  static const _muted = Color(0xFF8A8AA0);
  static const _hairline = Color(0xFFE3E5EE);
  static const _purple = Color(0xFF7C3AED);
  static const _purpleSoft = Color(0xFFEDE6FF);
  static const _purpleDeep = Color(0xFF5B21B6);
  static const _green = Color(0xFF1B7B4D);
  static const _greenSoft = Color(0xFFD7F1E2);
  static const _orange = Color(0xFFC66E1A);
  static const _orangeSoft = Color(0xFFFCE3C7);
  static const _gold = Color(0xFFC19A2C);
  static const _saveGreen1 = Color(0xFF5DBE89);
  static const _saveGreen2 = Color(0xFF2E875D);

  static const _avatarGradients = <List<Color>>[
    [Color(0xFF5BB9C4), Color(0xFF7C5BC4)],
    [Color(0xFFE07AB5), Color(0xFFE89460)],
    [Color(0xFF6FB1FF), Color(0xFFB46BFF)],
    [Color(0xFF6BD2A1), Color(0xFF3F8F6B)],
    [Color(0xFFFFB070), Color(0xFFE0608B)],
    [Color(0xFFA98EFF), Color(0xFF6B46FF)],
  ];

  late final List<_Draft> _drafts;
  late final Set<String> _initialIds;
  late String _selectedLogementId;
  DateTime? _dateEntree;
  late final TextEditingController _notes;
  int? _expandedIndex;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final svc = context.read<LocataireService>();
    final initial = svc.byLogement(widget.logementId);
    _drafts = initial.map(_Draft.fromExisting).toList();
    if (_drafts.isEmpty) {
      _drafts.add(_Draft.fresh(isPrincipal: true));
    } else if (!_drafts.any((d) => d.isPrincipal)) {
      _drafts.first.isPrincipal = true;
    }
    _initialIds = initial.map((l) => l.id).toSet();
    _selectedLogementId = widget.logementId;
    _dateEntree = _drafts
        .map((d) => d.dateEntree)
        .firstWhere((d) => d != null, orElse: () => null);
    final firstNotes = _drafts.isNotEmpty ? _drafts.first.notes : '';
    _notes = TextEditingController(text: firstNotes);
    _expandedIndex = 0;
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  List<Color> _gradientFor(int i) =>
      _avatarGradients[i % _avatarGradients.length];

  String _initialOf(_Draft d) {
    final t = d.firstName.text.trim();
    if (t.isNotEmpty) return t[0].toUpperCase();
    final l = d.lastName.text.trim();
    if (l.isNotEmpty) return l[0].toUpperCase();
    return '?';
  }

  String _displayName(_Draft d) {
    final fn = d.firstName.text.trim();
    final ln = d.lastName.text.trim().toUpperCase();
    if (fn.isEmpty && ln.isEmpty) return 'Nouveau locataire';
    return '${fn.isEmpty ? '' : '$fn '}$ln'.trim();
  }

  void _addDraft() {
    setState(() {
      _drafts.add(_Draft.fresh(isPrincipal: false));
      _expandedIndex = _drafts.length - 1;
    });
  }

  void _removeDraft(int index) {
    setState(() {
      _drafts[index].dispose();
      _drafts.removeAt(index);
      if (_expandedIndex != null) {
        if (_expandedIndex! >= _drafts.length) {
          _expandedIndex = _drafts.isEmpty ? null : _drafts.length - 1;
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEntree ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _dateEntree = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // expand first invalid
      for (int i = 0; i < _drafts.length; i++) {
        final d = _drafts[i];
        if (d.firstName.text.trim().length < 2 ||
            d.lastName.text.trim().length < 2 ||
            !EmailValidator.validate(d.email.text.trim())) {
          setState(() => _expandedIndex = i);
          break;
        }
      }
      return;
    }
    setState(() => _saving = true);
    final svc = context.read<LocataireService>();
    final originalLogId = widget.logementId;
    final newLogId = _selectedLogementId;
    try {
      final keptIds = <String>{};
      for (final d in _drafts) {
        if (d.id == null) {
          final created = Locataire.create(
            firstName: d.firstName.text,
            lastName: d.lastName.text,
            email: d.email.text,
            phone: d.phone.text,
            logementIds: [newLogId],
            dateEntree: _dateEntree,
            notes: _notes.text,
            isPrincipal: d.isPrincipal,
            dateNaissance: d.dateNaissance,
            adresse: d.adresse.text,
          );
          await svc.add(created);
          keptIds.add(created.id);
        } else {
          final l = svc.byId(d.id!);
          if (l == null) continue;
          l.firstName = d.firstName.text.trim();
          l.lastName = d.lastName.text.trim().toUpperCase();
          l.email = d.email.text.trim().toLowerCase();
          l.phone = d.phone.text.trim().isEmpty
              ? null
              : d.phone.text.trim();
          l.adresse = d.adresse.text.trim().isEmpty
              ? null
              : d.adresse.text.trim();
          l.dateNaissance = d.dateNaissance;
          l.dateEntree = _dateEntree;
          l.notes = _notes.text.trim();
          l.isPrincipal = d.isPrincipal;
          if (originalLogId != newLogId) {
            l.logementIds.remove(originalLogId);
            if (!l.logementIds.contains(newLogId)) {
              l.logementIds.add(newLogId);
            }
          } else if (!l.logementIds.contains(newLogId)) {
            l.logementIds.add(newLogId);
          }
          await svc.update(l);
          keptIds.add(l.id);
        }
      }
      // detach deleted drafts (locataires removed from this bail)
      for (final id in _initialIds.difference(keptIds)) {
        await svc.unassignFromLogement(id, originalLogId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final logement = context
        .watch<LogementService>()
        .byId(widget.logementId);
    final bailNo = context
        .watch<LogementService>()
        .bailNumberFor(widget.logementId);
    final selectedLog = logements
        .where((l) => l.id == _selectedLogementId)
        .cast<dynamic>()
        .firstWhere((_) => true, orElse: () => null);

    return Scaffold(
      backgroundColor: _bg,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            _GradientHeader(
              title: 'Modifier les locataires',
              subtitle:
                  'BAIL N° $bailNo · ${(logement?.libelle ?? '').toUpperCase()}',
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Transform.translate(
                  offset: const Offset(0, -36),
                  child: _HeroCard(
                    drafts: _drafts,
                    gradientFor: _gradientFor,
                    initialOf: _initialOf,
                    dateEntree: _dateEntree,
                    logementLabel: selectedLog?.libelle ?? '—',
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _SectionHeader(
                  bulletColor: _purple,
                  title: 'LOCATAIRES',
                  trailing: 'Solidaires sur le même bail',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final d = _drafts[index];
                    final expanded = _expandedIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LocataireCard(
                        index: index,
                        draft: d,
                        expanded: expanded,
                        gradient: _gradientFor(index),
                        initial: _initialOf(d),
                        displayName: _displayName(d),
                        onToggleExpand: () => setState(() {
                          _expandedIndex = expanded ? null : index;
                        }),
                        onTogglePrincipal: (v) {
                          setState(() => d.isPrincipal = v);
                        },
                        onChangedAny: () => setState(() {}),
                        canRemove: !d.isPrincipal,
                        onRemove: () => _removeDraft(index),
                      ),
                    );
                  },
                  childCount: _drafts.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: _AddCoLocataireButton(onPressed: _addDraft),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _SectionHeader(
                  bulletColor: _orange,
                  title: 'PÉRIODE DE LOCATION',
                  trailing: 'Bail commun',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _DateCard(
                  date: _dateEntree,
                  onTap: _pickDate,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _SectionHeader(
                  bulletColor: const Color(0xFF1F9D55),
                  title: 'LOGEMENT ASSOCIÉ',
                  trailing:
                      '${logements.length} disponible${logements.length > 1 ? 's' : ''} · 1 attribué',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: logements.length,
                separatorBuilder: (_, _) => const SizedBox(height: 0),
                itemBuilder: (context, i) {
                  final l = logements[i];
                  final selected = l.id == _selectedLogementId;
                  final first = i == 0;
                  final last = i == logements.length - 1;
                  return _LogementRow(
                    label: l.libelle,
                    address: l.adresseComplete,
                    selected: selected,
                    first: first,
                    last: last,
                    onTap: () => setState(() => _selectedLogementId = l.id),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: _SectionHeader(
                  bulletColor: _muted,
                  title: 'NOTES INTERNES',
                  trailing: 'Visible uniquement par le bailleur',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                child: _NotesCard(controller: _notes),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _CancelButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.of(context).viewPadding.bottom,
                ),
                child: _SaveButton(
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Draft {
  String? id;
  TextEditingController firstName;
  TextEditingController lastName;
  TextEditingController email;
  TextEditingController phone;
  TextEditingController adresse;
  DateTime? dateNaissance;
  bool isPrincipal;
  DateTime? dateEntree;
  String notes;

  _Draft({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.adresse,
    this.dateNaissance,
    required this.isPrincipal,
    this.dateEntree,
    this.notes = '',
  });

  factory _Draft.fromExisting(Locataire l) {
    return _Draft(
      id: l.id,
      firstName: TextEditingController(text: l.firstName),
      lastName: TextEditingController(text: l.lastName),
      email: TextEditingController(text: l.email),
      phone: TextEditingController(text: l.phone ?? ''),
      adresse: TextEditingController(text: l.adresse ?? ''),
      dateNaissance: l.dateNaissance,
      isPrincipal: l.isPrincipal,
      dateEntree: l.dateEntree,
      notes: l.notes,
    );
  }

  factory _Draft.fresh({required bool isPrincipal}) {
    return _Draft(
      id: null,
      firstName: TextEditingController(),
      lastName: TextEditingController(),
      email: TextEditingController(),
      phone: TextEditingController(),
      adresse: TextEditingController(),
      isPrincipal: isPrincipal,
    );
  }

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    phone.dispose();
    adresse.dispose();
  }
}

class _GradientHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _GradientHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Container(
        height: 140 + top,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
          ),
        ),
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, 30),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlassButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _GlassButton(
              icon: Icons.more_vert,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final List<_Draft> drafts;
  final List<Color> Function(int) gradientFor;
  final String Function(_Draft) initialOf;
  final DateTime? dateEntree;
  final String logementLabel;
  const _HeroCard({
    required this.drafts,
    required this.gradientFor,
    required this.initialOf,
    required this.dateEntree,
    required this.logementLabel,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final n = drafts.length;
    final namesSpans = <TextSpan>[];
    for (int i = 0; i < n; i++) {
      final d = drafts[i];
      if (i > 0) {
        namesSpans.add(const TextSpan(
          text: '  &  ',
          style: TextStyle(
            color: _CoLocatairesEditScreenState._gold,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ));
      }
      final fn = d.firstName.text.trim();
      final ln = d.lastName.text.trim().toUpperCase();
      namesSpans.add(TextSpan(
        children: [
          TextSpan(
            text: fn.isEmpty ? '' : '$fn ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          TextSpan(
            text: ln.isEmpty ? '' : ln,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (int i = 0; i < (n.clamp(0, 3)); i++)
                  Positioned(
                    left: null,
                    right: null,
                    child: Transform.translate(
                      offset: Offset((i - (n.clamp(1, 3) - 1) / 2) * 38, 0),
                      child: _SquareAvatar(
                        letter: initialOf(drafts[i]),
                        gradient: gradientFor(i),
                        size: 60,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                color: _CoLocatairesEditScreenState._ink,
                fontSize: 22,
                height: 1.2,
              ),
              children: namesSpans,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Pill(
                bg: _CoLocatairesEditScreenState._greenSoft,
                fg: _CoLocatairesEditScreenState._green,
                leadingDot: true,
                text: 'Bail actif',
              ),
              _Pill(
                bg: _CoLocatairesEditScreenState._orangeSoft,
                fg: _CoLocatairesEditScreenState._orange,
                icon: Icons.calendar_today_outlined,
                text: dateEntree == null
                    ? 'Aucune date'
                    : 'Depuis le ${df.format(dateEntree!)}',
              ),
              _Pill(
                bg: _CoLocatairesEditScreenState._purpleSoft,
                fg: _CoLocatairesEditScreenState._purple,
                icon: Icons.home_outlined,
                text: logementLabel,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _CoLocatairesEditScreenState._hairline),
          const SizedBox(height: 16),
          Text(
            n.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: _CoLocatairesEditScreenState._purple,
              fontStyle: FontStyle.italic,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            n > 1 ? 'CO-LOCATAIRES' : 'LOCATAIRE',
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: _CoLocatairesEditScreenState._muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareAvatar extends StatelessWidget {
  final String letter;
  final List<Color> gradient;
  final double size;
  const _SquareAvatar({
    required this.letter,
    required this.gradient,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool leadingDot;
  final String text;
  const _Pill({
    required this.bg,
    required this.fg,
    this.icon,
    this.leadingDot = false,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final Color bulletColor;
  final String title;
  final String trailing;
  const _SectionHeader({
    required this.bulletColor,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: bulletColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: _CoLocatairesEditScreenState._ink,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: const TextStyle(
            fontSize: 12,
            color: _CoLocatairesEditScreenState._muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LocataireCard extends StatelessWidget {
  final int index;
  final _Draft draft;
  final bool expanded;
  final List<Color> gradient;
  final String initial;
  final String displayName;
  final VoidCallback onToggleExpand;
  final ValueChanged<bool> onTogglePrincipal;
  final VoidCallback onChangedAny;
  final bool canRemove;
  final VoidCallback onRemove;
  const _LocataireCard({
    required this.index,
    required this.draft,
    required this.expanded,
    required this.gradient,
    required this.initial,
    required this.displayName,
    required this.onToggleExpand,
    required this.onTogglePrincipal,
    required this.onChangedAny,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fn = draft.firstName.text.trim();
    final ln = draft.lastName.text.trim().toUpperCase();
    final hasName = fn.isNotEmpty || ln.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  _SquareAvatar(
                    letter: initial,
                    gradient: gradient,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: hasName ? '$fn ' : 'Nouveau ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text: hasName ? ln : 'locataire',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: draft.isPrincipal
                                    ? _CoLocatairesEditScreenState._greenSoft
                                    : _CoLocatairesEditScreenState._purpleSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                draft.isPrincipal ? 'PRINCIPAL' : 'CO-LOCATAIRE',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800,
                                  color: draft.isPrincipal
                                      ? _CoLocatairesEditScreenState._green
                                      : _CoLocatairesEditScreenState._purple,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '· Bail signé',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _CoLocatairesEditScreenState._muted,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!expanded)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            draft.email.text.trim().isNotEmpty
                                ? 'EMAIL'
                                : 'TÉLÉPHONE',
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w700,
                              color: _CoLocatairesEditScreenState._muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              draft.email.text.trim().isNotEmpty
                                  ? draft.email.text.trim()
                                  : (draft.phone.text.trim().isNotEmpty
                                      ? draft.phone.text.trim()
                                      : '—'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _CoLocatairesEditScreenState._purpleSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: _CoLocatairesEditScreenState._purple,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  const Divider(
                    height: 1,
                    color: _CoLocatairesEditScreenState._hairline,
                  ),
                  const SizedBox(height: 10),
                  _FormField(
                    label: 'PRÉNOM',
                    required: true,
                    icon: Icons.person_outline,
                    iconBg: const Color(0xFFD6EFD9),
                    iconFg: const Color(0xFF1F9D55),
                    controller: draft.firstName,
                    capitalization: TextCapitalization.words,
                    onChanged: (_) => onChangedAny(),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Prénom requis'
                        : null,
                  ),
                  _FormField(
                    label: 'NOM',
                    required: true,
                    icon: Icons.badge_outlined,
                    iconBg: _CoLocatairesEditScreenState._purpleSoft,
                    iconFg: _CoLocatairesEditScreenState._purple,
                    highlight: true,
                    controller: draft.lastName,
                    capitalization: TextCapitalization.characters,
                    onChanged: (_) => onChangedAny(),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 2 ? 'Nom requis' : null,
                  ),
                  _FormField(
                    label: 'EMAIL',
                    required: true,
                    icon: Icons.email_outlined,
                    iconBg: const Color(0xFFFCE3C7),
                    iconFg: const Color(0xFFC66E1A),
                    controller: draft.email,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => onChangedAny(),
                    validator: (v) => EmailValidator.validate(v?.trim() ?? '')
                        ? null
                        : 'Email invalide',
                  ),
                  _FormField(
                    label: 'TÉLÉPHONE',
                    icon: Icons.phone_outlined,
                    iconBg: const Color(0xFFF3DCEE),
                    iconFg: const Color(0xFFC026D3),
                    controller: draft.phone,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => onChangedAny(),
                  ),
                  _FormField(
                    label: 'ADRESSE',
                    icon: Icons.home_outlined,
                    iconBg: const Color(0xFFDDE7F8),
                    iconFg: const Color(0xFF2B6CB0),
                    controller: draft.adresse,
                    capitalization: TextCapitalization.sentences,
                    onChanged: (_) => onChangedAny(),
                  ),
                  // Date de naissance (DatePicker)
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            draft.dateNaissance ?? DateTime(now.year - 30),
                        firstDate: DateTime(1900),
                        lastDate: now,
                        locale: const Locale('fr', 'FR'),
                      );
                      if (picked != null) {
                        // Setter d'état local : on re-build via le parent
                        draft.dateNaissance = picked;
                        onChangedAny();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE0B2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.cake_outlined,
                              color: Color(0xFFE65100),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'DATE DE NAISSANCE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  draft.dateNaissance == null
                                      ? 'Non renseignée'
                                      : '${draft.dateNaissance!.day.toString().padLeft(2, '0')}/'
                                          '${draft.dateNaissance!.month.toString().padLeft(2, '0')}/'
                                          '${draft.dateNaissance!.year}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          if (draft.dateNaissance != null)
                            IconButton(
                              iconSize: 18,
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                draft.dateNaissance = null;
                                onChangedAny();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: draft.isPrincipal,
                          onChanged: onTogglePrincipal,
                          activeThumbColor:
                              _CoLocatairesEditScreenState._purple,
                          title: const Text(
                            'Locataire principal',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            draft.isPrincipal
                                ? 'Ne peut être supprimé'
                                : 'Co-locataire solidaire',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _CoLocatairesEditScreenState._muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (canRemove) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Retirer du bail'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB42E2E),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: _CoLocatairesEditScreenState._muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Locataire principal · ne peut être supprimé',
                            style: TextStyle(
                              fontSize: 12,
                              color: _CoLocatairesEditScreenState._muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final bool required;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final bool highlight;
  final TextEditingController controller;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  const _FormField({
    required this.label,
    this.required = false,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    this.highlight = false,
    required this.controller,
    this.capitalization = TextCapitalization.none,
    this.keyboardType,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFF3EFFF)
            : const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: highlight
                ? _CoLocatairesEditScreenState._purple
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: _CoLocatairesEditScreenState._muted,
                          ),
                        ),
                        if (required)
                          const TextSpan(
                            text: ' *',
                            style: TextStyle(
                              color: Color(0xFFE0608B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextFormField(
                    controller: controller,
                    onChanged: onChanged,
                    validator: validator,
                    textCapitalization: capitalization,
                    keyboardType: keyboardType,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                      color: highlight
                          ? _CoLocatairesEditScreenState._purpleDeep
                          : _CoLocatairesEditScreenState._ink,
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

class _AddCoLocataireButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddCoLocataireButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: DottedBorderBox(
        borderRadius: 16,
        color: _CoLocatairesEditScreenState._purple,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: _CoLocatairesEditScreenState._purple,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ajouter un co-locataire',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _CoLocatairesEditScreenState._purple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color color;
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        radius: borderRadius,
        color: color.withValues(alpha: 0.55),
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final double radius;
  final Color color;
  _DashedBorderPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _DateCard extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;
  const _DateCard({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd / MM / yyyy', 'fr_FR');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  color: Color(0xFFC66E1A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "DATE D'ENTRÉE",
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: _CoLocatairesEditScreenState._muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date == null ? 'À renseigner' : df.format(date!),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _CoLocatairesEditScreenState._ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                size: 18,
                color: _CoLocatairesEditScreenState._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogementRow extends StatelessWidget {
  final String label;
  final String address;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;
  const _LogementRow({
    required this.label,
    required this.address,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(16) : Radius.zero,
      bottom: last ? const Radius.circular(16) : Radius.zero,
    );
    return Material(
      color: selected ? const Color(0xFFE7F5EE) : Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected
                    ? const Color(0xFF1F9D55)
                    : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(
                color: last
                    ? Colors.transparent
                    : _CoLocatairesEditScreenState._hairline,
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1F9D55)
                      : const Color(0xFFEDEFF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.home_outlined,
                  color: selected ? Colors.white : _CoLocatairesEditScreenState._muted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF1F9D55)
                            : _CoLocatairesEditScreenState._ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _CoLocatairesEditScreenState._muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? const Color(0xFF1F9D55) : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF1F9D55)
                        : _CoLocatairesEditScreenState._hairline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final TextEditingController controller;
  const _NotesCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE3EAF7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 18,
              color: Color(0xFF4F6FB5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(
                fontSize: 14,
                color: _CoLocatairesEditScreenState._ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText:
                    'Ajouter une remarque sur les locataires (préférences, contacts, observations particulières…)',
                hintStyle: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: _CoLocatairesEditScreenState._muted,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CancelButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _CoLocatairesEditScreenState._ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: const Text(
          'Annuler',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _SaveButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _CoLocatairesEditScreenState._saveGreen1,
              _CoLocatairesEditScreenState._saveGreen2,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _CoLocatairesEditScreenState._saveGreen2
                  .withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.check, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Enregistrer les modifications',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
