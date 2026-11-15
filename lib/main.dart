import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090B10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FamilyAgeApp());
}

class FamilyAgeApp extends StatelessWidget {
  const FamilyAgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Age',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF59E0B),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF131722),
        ),
      ),
      home: const FamilyAgeHome(),
    );
  }
}

class AgeBreakdown {
  final int years;
  final int months;
  final int days;
  final int totalDays;
  final int daysToNextBirthday;
  final int nextAge;
  final double progress;

  const AgeBreakdown({
    required this.years,
    required this.months,
    required this.days,
    required this.totalDays,
    required this.daysToNextBirthday,
    required this.nextAge,
    required this.progress,
  });

  String get compact => '${years}y ${months}m ${days}d';
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

AgeBreakdown calculateAge(DateTime dob, DateTime now) {
  final start = DateTime(dob.year, dob.month, dob.day);
  final end = DateTime(now.year, now.month, now.day);

  if (!end.isAfter(start)) {
    return const AgeBreakdown(
      years: 0,
      months: 0,
      days: 0,
      totalDays: 0,
      daysToNextBirthday: 0,
      nextAge: 1,
      progress: 0,
    );
  }

  final totalDays = end.difference(start).inDays;

  int years = end.year - start.year;
  int months = end.month - start.month;
  int days = end.day - start.day;

  if (days < 0) {
    months -= 1;
    final prevYear = end.month == 1 ? end.year - 1 : end.year;
    final prevMonth = end.month == 1 ? 12 : end.month - 1;
    days += _daysInMonth(prevYear, prevMonth);
  }

  if (months < 0) {
    years -= 1;
    months += 12;
  }

  final nextDay = min(start.day, _daysInMonth(end.year, start.month));
  DateTime nextBday = DateTime(end.year, start.month, nextDay);
  if (!nextBday.isAfter(end)) {
    final ny = end.year + 1;
    nextBday = DateTime(ny, start.month, min(start.day, _daysInMonth(ny, start.month)));
  }

  final prevYear = nextBday.year - 1;
  final prevBday = DateTime(
    prevYear,
    start.month,
    min(start.day, _daysInMonth(prevYear, start.month)),
  );
  final span = max(1, nextBday.difference(prevBday).inDays);
  final elapsed = end.difference(prevBday).inDays.clamp(0, span);

  return AgeBreakdown(
    years: years,
    months: months,
    days: days,
    totalDays: totalDays,
    daysToNextBirthday: nextBday.difference(end).inDays,
    nextAge: years + 1,
    progress: elapsed / span,
  );
}

class FamilyMember {
  final String role;
  String name;
  DateTime dob;

  FamilyMember({
    required this.role,
    required this.name,
    required this.dob,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        'dob': dob.toIso8601String(),
      };

  factory FamilyMember.fromJson(Map<String, dynamic> json, String fallbackRole) {
    final defaultDob = fallbackRole == 'Father'
        ? DateTime(1990, 5, 15)
        : fallbackRole == 'Mother'
            ? DateTime(1993, 9, 20)
            : DateTime(2021, 3, 10);
    return FamilyMember(
      role: fallbackRole,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : fallbackRole,
      dob: DateTime.tryParse(json['dob'] as String? ?? '') ?? defaultDob,
    );
  }
}

class FamilyAgeHome extends StatefulWidget {
  const FamilyAgeHome({super.key});

  @override
  State<FamilyAgeHome> createState() => _FamilyAgeHomeState();
}

class _FamilyAgeHomeState extends State<FamilyAgeHome> {
  static const MethodChannel _channel = MethodChannel('com.familyage/widget');

  final PageController _pageController = PageController();
  int _tabIndex = 0;

  late FamilyMember _father;
  late FamilyMember _mother;
  late FamilyMember _child;

  @override
  void initState() {
    super.initState();
    _father = FamilyMember(role: 'Father', name: 'Father', dob: DateTime(1990, 5, 15));
    _mother = FamilyMember(role: 'Mother', name: 'Mother', dob: DateTime(1993, 9, 20));
    _child = FamilyMember(role: 'Child', name: 'Child', dob: DateTime(2021, 3, 10));
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final raw = await _channel.invokeMethod<String>('loadState');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          if (map['father'] is Map<String, dynamic>) {
            _father = FamilyMember.fromJson(map['father'], 'Father');
          }
          if (map['mother'] is Map<String, dynamic>) {
            _mother = FamilyMember.fromJson(map['mother'], 'Mother');
          }
          if (map['child'] is Map<String, dynamic>) {
            _child = FamilyMember.fromJson(map['child'], 'Child');
          }
        });
      }
    } catch (_) {}
    await _syncWidgets(notify: false);
  }

  Future<void> _syncWidgets({bool notify = true}) async {
    final now = DateTime.now();
    final fAge = calculateAge(_father.dob, now);
    final mAge = calculateAge(_mother.dob, now);
    final cAge = calculateAge(_child.dob, now);

    final payload = jsonEncode({
      'father': _father.toJson(),
      'mother': _mother.toJson(),
      'child': _child.toJson(),
    });

    try {
      await _channel.invokeMethod('saveAndSync', {
        'json': payload,
        'fatherLine': '${_father.name}: ${fAge.compact}',
        'motherLine': '${_mother.name}: ${mAge.compact}',
        'childLine': '${_child.name}: ${cAge.compact}',
        'fatherSub': 'Next bday in ${fAge.daysToNextBirthday}d (${fAge.nextAge}y)',
        'motherSub': 'Next bday in ${mAge.daysToNextBirthday}d (${mAge.nextAge}y)',
        'childSub': '${cAge.totalDays} days • Next in ${cAge.daysToNextBirthday}d',
      });
    } catch (_) {}

    if (notify && mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Home screen widgets updated'),
          duration: Duration(milliseconds: 1100),
        ),
      );
    }
  }

  Future<void> _pickDob(FamilyMember member) async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: member.dob.isAfter(now) ? now : member.dob,
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
      helpText: '${member.role} Date of Birth',
    );
    if (picked != null) {
      setState(() => member.dob = picked);
      await _syncWidgets(notify: true);
    }
  }

  Future<void> _editName(FamilyMember member) async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController(text: member.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('${member.role} Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter name',
            filled: true,
            fillColor: const Color(0xFF090B10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => member.name = result);
      await _syncWidgets(notify: true);
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  void _switchTab(int index) {
    HapticFeedback.selectionClick();
    setState(() => _tabIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fAge = calculateAge(_father.dob, now);
    final mAge = calculateAge(_mother.dob, now);
    final cAge = calculateAge(_child.dob, now);

    final fAtChildBirth = calculateAge(_father.dob, _child.dob);
    final mAtChildBirth = calculateAge(_mother.dob, _child.dob);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSmoothTabSwitcher(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _tabIndex = i),
                children: [
                  _buildFamilyList(fAge, mAge, cAge, fAtChildBirth, mAtChildBirth),
                  _buildWidgetGallery(fAge, mAge, cAge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.family_restroom_rounded, color: Colors.black),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family Age',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Father • Mother • Child + Widgets',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => _syncWidgets(notify: true),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSmoothTabSwitcher() {
    const tabs = ['Family Ages', 'Home Widgets'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 230),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFF59E0B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: selected ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFamilyList(
    AgeBreakdown fAge,
    AgeBreakdown mAge,
    AgeBreakdown cAge,
    AgeBreakdown fAtBirth,
    AgeBreakdown mAtBirth,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _MemberCard(
          member: _father,
          age: fAge,
          dateText: _fmtDate(_father.dob),
          accent: const Color(0xFF38BDF8),
          icon: Icons.man_rounded,
          subText: 'At child birth: ${fAtBirth.years}y ${fAtBirth.months}m',
          onPickDate: () => _pickDob(_father),
          onEditName: () => _editName(_father),
        ),
        const SizedBox(height: 12),
        _MemberCard(
          member: _mother,
          age: mAge,
          dateText: _fmtDate(_mother.dob),
          accent: const Color(0xFFF472B6),
          icon: Icons.woman_rounded,
          subText: 'At child birth: ${mAtBirth.years}y ${mAtBirth.months}m',
          onPickDate: () => _pickDob(_mother),
          onEditName: () => _editName(_mother),
        ),
        const SizedBox(height: 12),
        _MemberCard(
          member: _child,
          age: cAge,
          dateText: _fmtDate(_child.dob),
          accent: const Color(0xFFF59E0B),
          icon: Icons.child_care_rounded,
          subText: 'Total lived: ${cAge.totalDays} days',
          onPickDate: () => _pickDob(_child),
          onEditName: () => _editName(_child),
        ),
      ],
    );
  }

  Widget _buildWidgetGallery(
    AgeBreakdown fAge,
    AgeBreakdown mAge,
    AgeBreakdown cAge,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _PreviewBox(
          title: 'SMALL WIDGET (2×1)',
          height: 96,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHILD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  Text(
                    '${_child.name}: ${cAge.compact}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              Text(
                'F:${fAge.years}y • M:${mAge.years}y',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _PreviewBox(
          title: 'MEDIUM WIDGET (4×2)',
          height: 148,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FAMILY AGE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(height: 6),
              Text('${_father.name}: ${fAge.compact}', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 3),
              Text('${_mother.name}: ${mAge.compact}', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 3),
              Text(
                '${_child.name}: ${cAge.compact}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _PreviewBox(
          title: 'LARGE WIDGET (4×4)',
          height: 225,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'FAMILY DASHBOARD',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  Text(
                    '${cAge.totalDays}d',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              _previewRow(_father.name, fAge.compact, 'Next: ${fAge.daysToNextBirthday}d', const Color(0xFF38BDF8)),
              _previewRow(_mother.name, mAge.compact, 'Next: ${mAge.daysToNextBirthday}d', const Color(0xFFF472B6)),
              _previewRow(_child.name, cAge.compact, 'Next: ${cAge.daysToNextBirthday}d', const Color(0xFFF59E0B)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => _syncWidgets(notify: true),
          icon: const Icon(Icons.add_to_home_screen_rounded),
          label: const Text(
            'Sync All Home Screen Widgets',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _previewRow(String name, String age, String sub, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name: $age',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final FamilyMember member;
  final AgeBreakdown age;
  final String dateText;
  final Color accent;
  final IconData icon;
  final String subText;
  final VoidCallback onPickDate;
  final VoidCallback onEditName;

  const _MemberCard({
    required this.member,
    required this.age,
    required this.dateText,
    required this.accent,
    required this.icon,
    required this.subText,
    required this.onPickDate,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onEditName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: accent,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit_rounded, size: 14, color: Colors.white38),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ActionChip(
                avatar: Icon(Icons.cake_rounded, size: 15, color: accent),
                label: Text(dateText, style: TextStyle(color: accent, fontSize: 12)),
                onPressed: onPickDate,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _tile('${age.years}', 'Years', accent),
              const SizedBox(width: 8),
              _tile('${age.months}', 'Months', accent),
              const SizedBox(width: 8),
              _tile('${age.days}', 'Days', accent),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: age.progress),
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutCubic,
            builder: (context, val, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: val,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(subText, style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text(
                'Next: ${age.nextAge}y in ${age.daysToNextBirthday}d',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String value, String label, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF090B10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;

  const _PreviewBox({
    required this.title,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}
