import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:alarm/alarm.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 🚀 نقطة البداية (Main & Initialization)
// ══════════════════════════════════════════════════════════════════════════════

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();

  try {
    await appState.initialize();
  } catch (e) {
    debugPrint('AppState init error: $e');
  }

  try {
    await Alarm.init();
  } catch (e) {
    debugPrint('Alarm init error: $e');
  }

  // الاستماع لرنين المنبه لفتح شاشة المنبه فوراً
  try {
    Alarm.ringStream.stream.listen((dynamic alarmSettings) {
      try {
        if (alarmSettings != null) {
          final int id = (alarmSettings.id is int) ? (alarmSettings.id as int) : 0;
          final appointment = appState.getAppointmentById(id);
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => AlarmScreen(
                alarmId: id,
                title: appointment?.title ?? 'موعد مذاكرة',
                note: appointment?.note ?? '',
                appointment: appointment,
              ),
            ),
          );
        }
      } catch (err) {
        debugPrint('Error navigating to AlarmScreen: $err');
      }
    });
  } catch (e) {
    debugPrint('Error listening to Alarm ringStream: $e');
  }

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MawaidApp(),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 🎨 التطبيق الرئيسي ودعم اللغة العربية (RTL)
// ══════════════════════════════════════════════════════════════════════════════

class MawaidApp extends StatelessWidget {
  const MawaidApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'مواعيد',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [
        Locale('ar', 'EG'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.light,
          primary: const Color(0xFF00897B),
          secondary: const Color(0xFF004D40),
          tertiary: const Color(0xFFFF7043),
          surface: const Color(0xFFFBFDFA),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF00897B),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.dark,
          primary: const Color(0xFF26A69A),
          secondary: const Color(0xFF80CBC4),
          tertiary: const Color(0xFFFF8A65),
          surface: const Color(0xFF1E2322),
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1E2322),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 📦 نماذج البيانات (Data Models)
// ══════════════════════════════════════════════════════════════════════════════

enum RepeatType { once, daily, specificDays }

enum SoundType { tts, record, file }

class Appointment {
  final int id;
  String title;
  String note;
  RepeatType repeatType;
  DateTime? date; // لو "مرة واحدة"
  TimeOfDay time;
  List<int> daysOfWeek; // 1 = الاثنين ... 7 = الأحد (نظام DateTime)
  SoundType soundType;
  String? soundPath; // مسار الملف الصوتي أو المسجل
  String? ttsText; // نص تحويل الكلام
  bool isEnabled;

  Appointment({
    required this.id,
    required this.title,
    this.note = '',
    this.repeatType = RepeatType.once,
    this.date,
    required this.time,
    this.daysOfWeek = const [],
    this.soundType = SoundType.tts,
    this.soundPath,
    this.ttsText = 'قوم ذاكر يا بطل، مستقبلك بيناديك!',
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'repeatType': repeatType.name,
        'date': date?.toIso8601String(),
        'hour': time.hour,
        'minute': time.minute,
        'daysOfWeek': daysOfWeek,
        'soundType': soundType.name,
        'soundPath': soundPath,
        'ttsText': ttsText,
        'isEnabled': isEnabled,
      };

  factory Appointment.fromJson(Map<String, dynamic> json) {
    RepeatType rep = RepeatType.once;
    try {
      rep = RepeatType.values.byName(json['repeatType'] ?? 'once');
    } catch (_) {}

    SoundType st = SoundType.tts;
    try {
      st = SoundType.values.byName(json['soundType'] ?? 'tts');
    } catch (_) {}

    return Appointment(
      id: json['id'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      title: json['title'] as String? ?? 'موعد بدون عنوان',
      note: json['note'] as String? ?? '',
      repeatType: rep,
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
      time: TimeOfDay(
        hour: json['hour'] as int? ?? 8,
        minute: json['minute'] as int? ?? 0,
      ),
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)
              ?.whereType<int>()
              .toList() ??
          [],
      soundType: st,
      soundPath: json['soundPath'] as String?,
      ttsText: json['ttsText'] as String? ?? 'قوم ذاكر يا بطل، مستقبلك بيناديك!',
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}

class PomodoroSession {
  final DateTime timestamp;
  final int durationMinutes;
  final String title;

  PomodoroSession({
    required this.timestamp,
    required this.durationMinutes,
    this.title = 'جلسة تركيز',
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'durationMinutes': durationMinutes,
        'title': title,
      };

  factory PomodoroSession.fromJson(Map<String, dynamic> json) {
    return PomodoroSession(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      durationMinutes: json['durationMinutes'] as int? ?? 25,
      title: json['title'] as String? ?? 'جلسة تركيز',
    );
  }
}

class PomodoroSettings {
  int studyMinutes;
  int breakMinutes;
  String studyEndSound;
  String breakEndSound;

  PomodoroSettings({
    this.studyMinutes = 25,
    this.breakMinutes = 5,
    this.studyEndSound = 'default',
    this.breakEndSound = 'default',
  });

  Map<String, dynamic> toJson() => {
        'studyMinutes': studyMinutes,
        'breakMinutes': breakMinutes,
        'studyEndSound': studyEndSound,
        'breakEndSound': breakEndSound,
      };

  factory PomodoroSettings.fromJson(Map<String, dynamic> json) {
    return PomodoroSettings(
      studyMinutes: json['studyMinutes'] as int? ?? 25,
      breakMinutes: json['breakMinutes'] as int? ?? 5,
      studyEndSound: json['studyEndSound'] as String? ?? 'default',
      breakEndSound: json['breakEndSound'] as String? ?? 'default',
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ⚡ مزود الحالة الموحد وترحيل البيانات (AppState & Migration)
// ══════════════════════════════════════════════════════════════════════════════

class AppState extends ChangeNotifier {
  List<Appointment> _appointments = [];
  List<PomodoroSession> _sessions = [];
  bool _isDarkMode = false;
  PomodoroSettings _pomodoroSettings = PomodoroSettings();

  List<Appointment> get appointments => List.unmodifiable(_appointments);
  List<PomodoroSession> get sessions => List.unmodifiable(_sessions);
  bool get isDarkMode => _isDarkMode;
  PomodoroSettings get pomodoroSettings => _pomodoroSettings;

  static const String keyAppointments = 'appointments_v6';
  static const String keySessions = 'sessions_v6';
  static const String keyDarkMode = 'dark_mode_v6';
  static const String keyPomodoroSettings = 'pomodoro_settings_v6';

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacyData(prefs);
      await _loadData(prefs);
    } catch (e) {
      debugPrint('Error in AppState initialize: $e');
    }
  }

  // ترحيل البيانات القديمة (appointments_v1..v5 إلخ)
  Future<void> _migrateLegacyData(SharedPreferences prefs) async {
    try {
      // 1. استيراد المواعيد القديمة
      if (!prefs.containsKey(keyAppointments)) {
        for (final oldKey in [
          'appointments_v5',
          'appointments_v4',
          'appointments_v3',
          'appointments_v2',
          'appointments_v1',
          'appointments',
        ]) {
          if (prefs.containsKey(oldKey)) {
            final oldRaw = prefs.getString(oldKey);
            if (oldRaw != null && oldRaw.isNotEmpty) {
              await prefs.setString(keyAppointments, oldRaw);
              break;
            }
          }
        }
      }

      // 2. استيراد الجلسات القديمة
      if (!prefs.containsKey(keySessions)) {
        for (final oldKey in [
          'sessions_v5',
          'sessions_v4',
          'sessions_v3',
          'sessions_v2',
          'sessions_v1',
          'sessions',
        ]) {
          if (prefs.containsKey(oldKey)) {
            final oldRaw = prefs.getString(oldKey);
            if (oldRaw != null && oldRaw.isNotEmpty) {
              await prefs.setString(keySessions, oldRaw);
              break;
            }
          }
        }
      }

      // 3. استيراد الوضع الليلي
      if (!prefs.containsKey(keyDarkMode)) {
        for (final oldKey in [
          'dark_mode_v5',
          'dark_mode_v4',
          'dark_mode_v3',
          'dark_mode_v2',
          'dark_mode_v1',
          'dark_mode',
        ]) {
          if (prefs.containsKey(oldKey)) {
            final oldVal = prefs.getBool(oldKey);
            if (oldVal != null) {
              await prefs.setBool(keyDarkMode, oldVal);
              break;
            }
          }
        }
      }

      // 4. استيراد إعدادات البومودورو
      if (!prefs.containsKey(keyPomodoroSettings)) {
        for (final oldKey in [
          'pomodoro_settings_v5',
          'pomodoro_settings_v4',
          'pomodoro_settings_v3',
          'pomodoro_settings_v2',
          'pomodoro_settings_v1',
          'pomodoro_settings',
        ]) {
          if (prefs.containsKey(oldKey)) {
            final oldRaw = prefs.getString(oldKey);
            if (oldRaw != null && oldRaw.isNotEmpty) {
              await prefs.setString(keyPomodoroSettings, oldRaw);
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error during data migration: $e');
    }
  }

  Future<void> _loadData(SharedPreferences prefs) async {
    try {
      _isDarkMode = prefs.getBool(keyDarkMode) ?? false;

      final appsJson = prefs.getString(keyAppointments);
      if (appsJson != null) {
        final decoded = jsonDecode(appsJson) as List<dynamic>;
        _appointments = decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => Appointment.fromJson(e))
            .toList();
      }

      final sessJson = prefs.getString(keySessions);
      if (sessJson != null) {
        final decoded = jsonDecode(sessJson) as List<dynamic>;
        _sessions = decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => PomodoroSession.fromJson(e))
            .toList();
      }

      final pomoJson = prefs.getString(keyPomodoroSettings);
      if (pomoJson != null) {
        final decoded = jsonDecode(pomoJson) as Map<String, dynamic>;
        _pomodoroSettings = PomodoroSettings.fromJson(decoded);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading saved data: $e');
    }
  }

  Future<void> toggleDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyDarkMode, value);
    } catch (e) {
      debugPrint('Error saving dark mode: $e');
    }
  }

  Appointment? getAppointmentById(int id) {
    try {
      return _appointments.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addOrUpdateAppointment(Appointment app) async {
    final index = _appointments.indexWhere((a) => a.id == app.id);
    if (index >= 0) {
      _appointments[index] = app;
    } else {
      _appointments.add(app);
    }
    notifyListeners();
    await _saveAppointments();

    if (app.isEnabled) {
      await scheduleAlarm(app);
    } else {
      await cancelAlarm(app.id);
    }
  }

  Future<void> toggleAppointmentStatus(int id) async {
    final index = _appointments.indexWhere((a) => a.id == id);
    if (index >= 0) {
      _appointments[index].isEnabled = !_appointments[index].isEnabled;
      final item = _appointments[index];
      notifyListeners();
      await _saveAppointments();

      if (item.isEnabled) {
        await scheduleAlarm(item);
      } else {
        await cancelAlarm(item.id);
      }
    }
  }

  Future<void> deleteAppointment(int id) async {
    _appointments.removeWhere((a) => a.id == id);
    notifyListeners();
    await _saveAppointments();
    await cancelAlarm(id);
  }

  Future<void> clearAllAppointments() async {
    for (final app in _appointments) {
      await cancelAlarm(app.id);
    }
    _appointments.clear();
    notifyListeners();
    await _saveAppointments();
  }

  Future<void> clearAllData() async {
    for (final app in _appointments) {
      await cancelAlarm(app.id);
    }
    _appointments.clear();
    _sessions.clear();
    _pomodoroSettings = PomodoroSettings();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error clearing all preferences: $e');
    }
  }

  Future<void> _saveAppointments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_appointments.map((a) => a.toJson()).toList());
      await prefs.setString(keyAppointments, data);
    } catch (e) {
      debugPrint('Error saving appointments: $e');
    }
  }

  Future<void> addPomodoroSession(int minutes, {String title = 'جلسة تركيز'}) async {
    _sessions.insert(
      0,
      PomodoroSession(
        timestamp: DateTime.now(),
        durationMinutes: minutes,
        title: title,
      ),
    );
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      await prefs.setString(keySessions, data);
    } catch (e) {
      debugPrint('Error saving pomodoro sessions: $e');
    }
  }

  Future<void> updatePomodoroSettings(PomodoroSettings settings) async {
    _pomodoroSettings = settings;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyPomodoroSettings, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving pomodoro settings: $e');
    }
  }

  // 🔔 جدولة المنبه عبر مكتبة Alarm مع الملف الصامت
  Future<void> scheduleAlarm(Appointment app) async {
    try {
      final now = DateTime.now();
      DateTime scheduledDateTime;

      if (app.repeatType == RepeatType.once) {
        final d = app.date ?? now;
        scheduledDateTime = DateTime(
          d.year,
          d.month,
          d.day,
          app.time.hour,
          app.time.minute,
        );
        if (scheduledDateTime.isBefore(now)) {
          // إذا كان الوقت قد مضى اليوم، يضبط على الغد
          scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
        }
      } else {
        // متكرر يومياً أو أيام محددة
        scheduledDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          app.time.hour,
          app.time.minute,
        );
        if (scheduledDateTime.isBefore(now)) {
          scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
        }

        if (app.repeatType == RepeatType.specificDays && app.daysOfWeek.isNotEmpty) {
          while (!app.daysOfWeek.contains(scheduledDateTime.weekday)) {
            scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
          }
        }
      }

      final String alarmTitle = app.title.trim().isNotEmpty ? app.title.trim() : 'موعد مذاكرة';
      final String alarmBody = app.note.trim().isNotEmpty ? app.note.trim() : 'حان وقت المذاكرة والتركيز يا بطل!';

      final alarmSettings = AlarmSettings(
        id: app.id % 2147483647,
        dateTime: scheduledDateTime,
        assetAudioPath: 'assets/silent.mp3', // ملف صامت لتفادي تضارب الأصوات
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        volumeSettings: VolumeSettings.fixed(volume: 1.0, volumeEnforced: true),
        notificationSettings: NotificationSettings(
          title: alarmTitle,
          body: alarmBody,
          stopButton: 'إيقاف',
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);
      debugPrint('Alarm scheduled successfully for: $scheduledDateTime');
    } catch (e) {
      debugPrint('Error scheduling alarm: $e');
    }
  }

  Future<void> cancelAlarm(int id) async {
    try {
      await Alarm.stop(id % 2147483647);
    } catch (e) {
      debugPrint('Error canceling alarm: $e');
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 📱 الشاشة 1: الرئيسية (HomeScreen)
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm, size: 24),
            SizedBox(width: 8),
            Text('مواعيد المذاكرة', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'بومودورو',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PomodoroScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'الإحصائيات',
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatisticsScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات إضافية',
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'clear_all') {
                _confirmClearAll(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('مسح كل المواعيد'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: appState.appointments.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: appState.appointments.length,
              itemBuilder: (context, index) {
                final app = appState.appointments[index];
                return Dismissible(
                  key: ValueKey(app.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('حذف الموعد',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        SizedBox(width: 8),
                        Icon(Icons.delete_forever, color: Colors.white, size: 28),
                      ],
                    ),
                  ),
                  confirmDismiss: (dir) => _confirmDelete(context, app.title),
                  onDismissed: (_) {
                    appState.deleteAppointment(app.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم حذف "${app.title}" بنجاح')),
                    );
                  },
                  child: _AppointmentCard(appointment: app),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('إضافة موعد', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddEditAppointmentScreen(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'لا توجد مواعيد مذاكرة مسجلة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'نظّم أوقاتك وحقق أهدافك الدراسية عبر الضغط على زر "إضافة موعد" بالأسفل.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف موعد "$title"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل المواعيد'),
        content: const Text('هل ترغب حقاً في حذف جميع المواعيد المسجلة وإلغاء تنبيهاتها؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<AppState>().clearAllAppointments();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم مسح جميع المواعيد')),
              );
            },
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;

  const _AppointmentCard({required this.appointment});

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatRepeat() {
    switch (appointment.repeatType) {
      case RepeatType.once:
        final d = appointment.date;
        if (d != null) {
          return 'مرة واحدة (${DateFormat('yyyy/MM/dd').format(d)})';
        }
        return 'مرة واحدة';
      case RepeatType.daily:
        return 'يومياً';
      case RepeatType.specificDays:
        const daysArabic = {
          1: 'اثنين',
          2: 'ثلاثاء',
          3: 'أربعاء',
          4: 'خميس',
          5: 'جمعة',
          6: 'سبت',
          7: 'أحد',
        };
        final names = appointment.daysOfWeek.map((d) => daysArabic[d] ?? '').where((s) => s.isNotEmpty).join('، ');
        return names.isNotEmpty ? 'أيام: $names' : 'أيام محددة';
    }
  }

  IconData _getSoundIcon() {
    switch (appointment.soundType) {
      case SoundType.tts:
        return Icons.record_voice_over_rounded;
      case SoundType.record:
        return Icons.mic_rounded;
      case SoundType.file:
        return Icons.audio_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.read<AppState>();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // أيقونة الصوت والحالة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appointment.isEnabled
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getSoundIcon(),
                color: appointment.isEnabled ? theme.colorScheme.primary : Colors.grey,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            // تفاصيل الموعد
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appointment.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            decoration: appointment.isEnabled ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      Switch(
                        value: appointment.isEnabled,
                        onChanged: (_) {
                          appState.toggleAppointmentStatus(appointment.id);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 16, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(appointment.time),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.repeat_rounded, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        _formatRepeat(),
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (appointment.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      appointment.note,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // أزرار سريعة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('تعديل'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEditAppointmentScreen(appointment: appointment),
                            ),
                          );
                        },
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('حذف'),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('حذف الموعد'),
                              content: Text('هل تريد حذف "${appointment.title}"؟'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('حذف'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            appState.deleteAppointment(appointment.id);
                          }
                        },
                      ),
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
}

// ══════════════════════════════════════════════════════════════════════════════
// 📝 الشاشة 2: إضافة وتعديل موعد (AddEditAppointmentScreen)
// ══════════════════════════════════════════════════════════════════════════════

class AddEditAppointmentScreen extends StatefulWidget {
  final Appointment? appointment;

  const AddEditAppointmentScreen({super.key, this.appointment});

  @override
  State<AddEditAppointmentScreen> createState() => _AddEditAppointmentScreenState();
}

class _AddEditAppointmentScreenState extends State<AddEditAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _noteController;
  late TextEditingController _ttsController;

  late RepeatType _repeatType;
  DateTime? _date;
  late TimeOfDay _time;
  late List<int> _daysOfWeek;
  late SoundType _soundType;
  String? _soundPath;

  // أدوات التسجيل المباشر
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;

  // أدوات الاستماع والصوتيات
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;

  // تحويل النص لكلام
  final FlutterTts _flutterTts = FlutterTts();
  double _ttsPitch = 1.0;
  double _ttsRate = 0.5;

  @override
  void initState() {
    super.initState();
    final app = widget.appointment;
    _titleController = TextEditingController(text: app?.title ?? '');
    _noteController = TextEditingController(text: app?.note ?? '');
    _ttsController = TextEditingController(
      text: app?.ttsText ?? 'قوم ذاكر يا بطل، مستقبلك بيناديك!',
    );

    _repeatType = app?.repeatType ?? RepeatType.once;
    _date = app?.date ?? DateTime.now();
    _time = app?.time ?? TimeOfDay.now();
    _daysOfWeek = List<int>.from(app?.daysOfWeek ?? [6, 7, 1, 2, 3]); // افتراضياً السبت للأربعاء
    _soundType = app?.soundType ?? SoundType.tts;
    _soundPath = app?.soundPath;

    _initTts();

    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingPreview = false);
    });
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('ar-EG');
      await _flutterTts.setPitch(_ttsPitch);
      await _flutterTts.setSpeechRate(_ttsRate);
    } catch (e) {
      debugPrint('Error init TTS: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _ttsController.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _previewPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // 1. اختيار ملف صوتي من الهاتف
  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          final sourceFile = File(filePath);
          final docsDir = await getApplicationDocumentsDirectory();
          final ext = sourceFile.path.split('.').last;
          final targetPath =
              '${docsDir.path}/sound_${DateTime.now().millisecondsSinceEpoch}.$ext';
          await sourceFile.copy(targetPath);

          setState(() {
            _soundPath = targetPath;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم استيراد الملف الصوتي وحفظه بنجاح')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في اختيار الملف: $e')),
      );
    }
  }

  // 2. التسجيل المباشر
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final docsDir = await getApplicationDocumentsDirectory();
        final path = '${docsDir.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordDurationSeconds = 0;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() => _recordDurationSeconds++);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى منح إذن استخدام المايكروفون')),
        );
      }
    } catch (e) {
      debugPrint('Recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordTimer?.cancel();
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        if (path != null) {
          _soundPath = path;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنهاء التسجيل وحفظ الصوت بنجاح')),
      );
    } catch (e) {
      debugPrint('Stop recording error: $e');
    }
  }

  // معاينة الصوت المسجل أو الملف
  Future<void> _togglePreviewSound() async {
    try {
      if (_isPlayingPreview) {
        await _previewPlayer.stop();
        setState(() => _isPlayingPreview = false);
      } else {
        final path = _soundPath;
        if (path != null && File(path).existsSync()) {
          setState(() => _isPlayingPreview = true);
          await _previewPlayer.play(DeviceFileSource(path));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الملف الصوتي غير موجود حالياً')),
          );
        }
      }
    } catch (e) {
      setState(() => _isPlayingPreview = false);
      debugPrint('Error preview sound: $e');
    }
  }

  // تجربة النص المقروء (TTS Preview)
  Future<void> _previewTts() async {
    try {
      final text = _ttsController.text.trim();
      if (text.isEmpty) return;
      await _flutterTts.stop();
      await _flutterTts.setPitch(_ttsPitch);
      await _flutterTts.setSpeechRate(_ttsRate);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
  }

  // حفظ الموعد
  Future<void> _saveAppointment() async {
    if (_formKey.currentState?.validate() != true) return;

    final appState = context.read<AppState>();
    final newId = widget.appointment?.id ?? DateTime.now().millisecondsSinceEpoch;

    // إذا تم اختيار TTS، نقوم بتوليد ملف صوتي دائم له إذا أمكن
    String? finalSoundPath = _soundPath;
    if (_soundType == SoundType.tts) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final ttsFilePath = '${docsDir.path}/tts_$newId.wav';
        await _flutterTts.synthesizeToFile(_ttsController.text.trim(), ttsFilePath);
        finalSoundPath = ttsFilePath;
      } catch (e) {
        debugPrint('TTS synthesis error: $e');
      }
    }

    final appointment = Appointment(
      id: newId,
      title: _titleController.text.trim(),
      note: _noteController.text.trim(),
      repeatType: _repeatType,
      date: _repeatType == RepeatType.once ? _date : null,
      time: _time,
      daysOfWeek: _repeatType == RepeatType.specificDays ? _daysOfWeek : [],
      soundType: _soundType,
      soundPath: finalSoundPath,
      ttsText: _ttsController.text.trim(),
      isEnabled: widget.appointment?.isEnabled ?? true,
    );

    await appState.addOrUpdateAppointment(appointment);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.appointment == null ? 'تمت إضافة الموعد وجدولته' : 'تم تعديل الموعد بنجاح',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appointment == null ? 'إضافة موعد جديد' : 'تعديل الموعد'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // اسم الموعد
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'اسم الموعد *',
                hintText: 'مثلاً: مذاكرة رياضيات، مراجعة فيزياء',
                prefixIcon: const Icon(Icons.title_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'الرجاء إدخال اسم الموعد' : null,
            ),
            const SizedBox(height: 16),

            // ملاحظة
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                hintText: 'مثلاً: حل تمارين الفصل الثالث',
                prefixIcon: const Icon(Icons.note_alt_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            // نوع التكرار
            const Text('نوع التكرار', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<RepeatType>(
              segments: const [
                ButtonSegment(value: RepeatType.once, label: Text('مرة واحدة')),
                ButtonSegment(value: RepeatType.daily, label: Text('كل يوم')),
                ButtonSegment(value: RepeatType.specificDays, label: Text('أيام محددة')),
              ],
              selected: {_repeatType},
              onSelectionChanged: (val) {
                setState(() => _repeatType = val.first);
              },
            ),
            const SizedBox(height: 16),

            // التاريخ (لو مرة واحدة)
            if (_repeatType == RepeatType.once) ...[
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('تاريخ الموعد'),
                subtitle: Text(DateFormat('yyyy/MM/dd').format(_date ?? DateTime.now())),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _date = picked);
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            // أيام الأسبوع (لو أيام محددة)
            if (_repeatType == RepeatType.specificDays) ...[
              const Text('اختر الأيام:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildDayChip('السبت', 6),
                  _buildDayChip('الأحد', 7),
                  _buildDayChip('الاثنين', 1),
                  _buildDayChip('الثلاثاء', 2),
                  _buildDayChip('الأربعاء', 3),
                  _buildDayChip('الخميس', 4),
                  _buildDayChip('الجمعة', 5),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // اختيار الوقت
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: Icon(Icons.access_time_rounded, color: theme.colorScheme.primary),
              title: const Text('وقت المنبه (12 ساعة)'),
              subtitle: Text(
                '${_time.hourOfPeriod == 0 ? 12 : _time.hourOfPeriod}:${_time.minute.toString().padLeft(2, '0')} ${_time.period == DayPeriod.am ? 'صباحاً' : 'مساءً'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) {
                  setState(() => _time = picked);
                }
              },
            ),
            const SizedBox(height: 24),

            // قسم اختيار الصوت (3 طرق)
            const Text('🔊 صوت المنبه المخصص',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<SoundType>(
              segments: const [
                ButtonSegment(
                  value: SoundType.tts,
                  icon: Icon(Icons.record_voice_over),
                  label: Text('تحويل نص'),
                ),
                ButtonSegment(
                  value: SoundType.record,
                  icon: Icon(Icons.mic),
                  label: Text('تسجيل صوتي'),
                ),
                ButtonSegment(
                  value: SoundType.file,
                  icon: Icon(Icons.audio_file),
                  label: Text('ملف صوتي'),
                ),
              ],
              selected: {_soundType},
              onSelectionChanged: (val) {
                setState(() => _soundType = val.first);
              },
            ),
            const SizedBox(height: 16),

            // تفاصيل الخيار الصوتي المختار
            _buildSoundPickerSection(theme),
            const SizedBox(height: 32),

            // زر الحفظ
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('حفظ وجدولة الموعد',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              onPressed: _saveAppointment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayChip(String label, int day) {
    final isSelected = _daysOfWeek.contains(day);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            _daysOfWeek.add(day);
          } else {
            _daysOfWeek.remove(day);
          }
        });
      },
    );
  }

  Widget _buildSoundPickerSection(ThemeData theme) {
    switch (_soundType) {
      case SoundType.tts:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.amber),
                    SizedBox(width: 8),
                    Text('تحويل النص لكلام (Text-to-Speech)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ttsController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'الجملة المنطوقة باللغة العربية',
                    hintText: 'قوم ذاكر يا بطل، حلمك مستنيك!',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('سرعة النطق: ${_ttsRate.toStringAsFixed(1)}'),
                          Slider(
                            value: _ttsRate,
                            min: 0.1,
                            max: 1.0,
                            onChanged: (v) => setState(() => _ttsRate = v),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نبرة الصوت: ${_ttsPitch.toStringAsFixed(1)}'),
                          Slider(
                            value: _ttsPitch,
                            min: 0.5,
                            max: 1.5,
                            onChanged: (v) => setState(() => _ttsPitch = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('استماع للجملة'),
                    onPressed: _previewTts,
                  ),
                ),
              ],
            ),
          ),
        );

      case SoundType.record:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.mic, color: Colors.red),
                    SizedBox(width: 8),
                    Text('تسجيل صوتي مباشر بصوتك', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _isRecording
                      ? 'جاري التسجيل: $_recordDurationSeconds ثانية'
                      : (_soundPath != null ? 'يوجد تسجيل جاهز ومحفوظ' : 'اضغط للبدء في التسجيل'),
                  style: TextStyle(
                    fontSize: 16,
                    color: _isRecording ? Colors.red : Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_isRecording)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        icon: const Icon(Icons.mic),
                        label: const Text('بدء التسجيل'),
                        onPressed: _startRecording,
                      )
                    else
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                        icon: const Icon(Icons.stop),
                        label: const Text('إيقاف وحفظ'),
                        onPressed: _stopRecording,
                      ),
                    if (!_isRecording && _soundPath != null) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: Icon(_isPlayingPreview ? Icons.stop : Icons.play_arrow),
                        label: Text(_isPlayingPreview ? 'إيقاف' : 'تشغيل التسجيل'),
                        onPressed: _togglePreviewSound,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );

      case SoundType.file:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('اختيار ملف صوتي من الهاتف', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final path = _soundPath;
                    return Text(
                      path != null
                          ? 'الملف المحدد: ${path.split('/').last}'
                          : 'لم يتم اختيار ملف صوتي بعد',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('استعراض الملفات'),
                      onPressed: _pickAudioFile,
                    ),
                    if (_soundPath != null) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: Icon(_isPlayingPreview ? Icons.stop : Icons.play_arrow),
                        label: Text(_isPlayingPreview ? 'إيقاف' : 'استماع'),
                        onPressed: _togglePreviewSound,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 🚨 الشاشة 3: رنين المنبه (AlarmScreen)
// ══════════════════════════════════════════════════════════════════════════════

class AlarmScreen extends StatefulWidget {
  final int alarmId;
  final String title;
  final String note;
  final Appointment? appointment;

  const AlarmScreen({
    super.key,
    required this.alarmId,
    required this.title,
    this.note = '',
    this.appointment,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  final AudioPlayer _ringPlayer = AudioPlayer();
  final FlutterTts _alarmTts = FlutterTts();
  Timer? _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _playActualAlarmSound();
  }

  void _updateClock() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour >= 12 ? 'م' : 'ص';
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _currentTime = '$hour:$minute:$second $period';
      });
    }
  }

  // 🔔 تشغيل الصوت الفعلي (صوت واحد فقط مستقل مع 3 محاولات)
  Future<void> _playActualAlarmSound() async {
    final app = widget.appointment;
    await _ringPlayer.setReleaseMode(ReleaseMode.loop);
    await _ringPlayer.setVolume(1.0);

    // المحاولة 1: صوت المستخدم المخصص (ملف أو مسجل أو TTS)
    if (app != null) {
      final tts = app.ttsText;
      if (app.soundType == SoundType.tts && tts != null && tts.trim().isNotEmpty) {
        try {
          await _alarmTts.setLanguage('ar-EG');
          await _alarmTts.setSpeechRate(0.5);
          await _alarmTts.setPitch(1.0);
          await _alarmTts.speak(tts.trim());
          return;
        } catch (e) {
          debugPrint('Failed to speak alarm TTS: $e');
        }
      }

      final sound = app.soundPath;
      if (sound != null && File(sound).existsSync()) {
        try {
          await _ringPlayer.play(DeviceFileSource(sound));
          return;
        } catch (e) {
          debugPrint('Failed to play custom user audio: $e');
        }
      }
    }

    // المحاولة 2: صوت نظام مدمج أو نغمة
    try {
      await _ringPlayer.play(AssetSource('silent.mp3'));
    } catch (_) {
      // المحاولة 3: أي محاولة طارئة
      debugPrint('Fallback alarm sound execution completed.');
    }
  }

  Future<void> _stopAlarmAndDismiss() async {
    try {
      await _ringPlayer.stop();
      await _alarmTts.stop();
      await Alarm.stop(widget.alarmId);
    } catch (e) {
      debugPrint('Error stopping alarm: $e');
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _animController.dispose();
    _ringPlayer.dispose();
    _alarmTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.isNotEmpty ? widget.title : (widget.appointment?.title ?? 'موعد مذاكرة');
    final note = widget.note.isNotEmpty ? widget.note : (widget.appointment?.note ?? '');

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFB71C1C), Color(0xFFE53935), Color(0xFFD32F2F)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // رأس الشاشة والوقت الحالي
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        _currentTime,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'حان موعد المذاكرة الآن!',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),

                  // أيقونة منبه نابضة ومتحركة
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.alarm_on_rounded,
                        size: 100,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // تفاصيل الموعد وزر الإيقاف
                  Column(
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          note,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFB71C1C),
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          onPressed: _stopAlarmAndDismiss,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.stop_circle_rounded, size: 36),
                              SizedBox(width: 12),
                              Text(
                                'إيقاف المنبه',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ⏱️ الشاشة 4: البومودورو (PomodoroScreen)
// ══════════════════════════════════════════════════════════════════════════════

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  Timer? _timer;
  bool _isStudyMode = true;
  bool _isRunning = false;
  late int _remainingSeconds;
  late int _totalSeconds;

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _resetToCurrentSettings();
  }

  void _resetToCurrentSettings() {
    final settings = context.read<AppState>().pomodoroSettings;
    final mins = _isStudyMode ? settings.studyMinutes : settings.breakMinutes;
    _totalSeconds = mins * 60;
    _remainingSeconds = _totalSeconds;
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        setState(() => _isRunning = false);
        _onSessionComplete();
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _resetToCurrentSettings();
    });
  }

  Future<void> _onSessionComplete() async {
    final appState = context.read<AppState>();

    if (_isStudyMode) {
      // تسجيل جلسة مذاكرة مكتملة
      await appState.addPomodoroSession(
        appState.pomodoroSettings.studyMinutes,
        title: 'جلسة تركيز بومودورو',
      );

      // تشغيل نغمة إنهاء المذاكرة
      _playChime();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('أحسنت يا بطل! 🎉'),
            content: const Text('انتهت جلسة المذاكرة بنجاح. حان وقت الاستراحة الآن!'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _isStudyMode = false;
                    _resetToCurrentSettings();
                  });
                },
                child: const Text('بدء الاستراحة'),
              ),
            ],
          ),
        );
      }
    } else {
      // انتهاء الاستراحة
      _playChime();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('انتهت الاستراحة ⏰'),
            content: const Text('هل أنت مستعد لبدء جولة مذاكرة وتركيز جديدة؟'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _isStudyMode = true;
                    _resetToCurrentSettings();
                  });
                },
                child: const Text('بدء المذاكرة'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _playChime() async {
    try {
      await _audioPlayer.play(AssetSource('silent.mp3'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0.0;
    final mins = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_remainingSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: const Text('مؤقت البومودورو'),
        actions: [
          IconButton(
            tooltip: 'إعدادات البومودورو',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              _pauseTimer();
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PomodoroSettingsScreen()),
              );
              setState(() => _resetToCurrentSettings());
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // اختيار النمط (مذاكرة / راحة)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.school_rounded),
                    label: Text('مذاكرة'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.coffee_rounded),
                    label: Text('استراحة'),
                  ),
                ],
                selected: {_isStudyMode},
                onSelectionChanged: (val) {
                  setState(() {
                    _isStudyMode = val.first;
                    _resetTimer();
                  });
                },
              ),
              const SizedBox(height: 48),

              // دائرة التقدم مع العداد
              SizedBox(
                width: 250,
                height: 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 14,
                        backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isStudyMode ? theme.colorScheme.primary : Colors.orange,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$mins:$secs',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isStudyMode ? 'وقت التركيز' : 'وقت الراحة',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),

              // أزرار التحكم
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isRunning)
                    FloatingActionButton.large(
                      heroTag: 'start_pomodoro',
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      onPressed: _startTimer,
                      child: const Icon(Icons.play_arrow_rounded, size: 48),
                    )
                  else
                    FloatingActionButton.large(
                      heroTag: 'pause_pomodoro',
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      onPressed: _pauseTimer,
                      child: const Icon(Icons.pause_rounded, size: 48),
                    ),
                  const SizedBox(width: 24),
                  FloatingActionButton(
                    heroTag: 'reset_pomodoro',
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black87,
                    onPressed: _resetTimer,
                    child: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ⚙️ الشاشة 5: إعدادات البومودورو (PomodoroSettingsScreen)
// ══════════════════════════════════════════════════════════════════════════════

class PomodoroSettingsScreen extends StatefulWidget {
  const PomodoroSettingsScreen({super.key});

  @override
  State<PomodoroSettingsScreen> createState() => _PomodoroSettingsScreenState();
}

class _PomodoroSettingsScreenState extends State<PomodoroSettingsScreen> {
  late int _studyMinutes;
  late int _breakMinutes;
  late String _studyEndSound;
  late String _breakEndSound;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().pomodoroSettings;
    _studyMinutes = s.studyMinutes;
    _breakMinutes = s.breakMinutes;
    _studyEndSound = s.studyEndSound;
    _breakEndSound = s.breakEndSound;
  }

  void _saveSettings() {
    final settings = PomodoroSettings(
      studyMinutes: _studyMinutes,
      breakMinutes: _breakMinutes,
      studyEndSound: _studyEndSound,
      breakEndSound: _breakEndSound,
    );
    context.read<AppState>().updatePomodoroSettings(settings);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات البومودورو')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات البومودورو'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('مدة المذاكرة والتركيز',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('$_studyMinutes دقيقة',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                  Slider(
                    value: _studyMinutes.toDouble(),
                    min: 1,
                    max: 180,
                    divisions: 179,
                    label: '$_studyMinutes دقيقة',
                    onChanged: (v) => setState(() => _studyMinutes = v.toInt()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('مدة الاستراحة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('$_breakMinutes دقيقة',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                  Slider(
                    value: _breakMinutes.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    label: '$_breakMinutes دقيقة',
                    onChanged: (v) => setState(() => _breakMinutes = v.toInt()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('نغمات التنبيه',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.music_note_rounded),
                    title: const Text('صوت نهاية المذاكرة'),
                    subtitle: Text(_studyEndSound == 'default' ? 'النغمة الافتراضية الهادئة' : _studyEndSound),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_rounded),
                    title: const Text('صوت نهاية الاستراحة'),
                    subtitle: Text(_breakEndSound == 'default' ? 'نغمة التنبيه المنشطة' : _breakEndSound),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ الإعدادات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _saveSettings,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 📊 الشاشة 6: الإحصائيات (StatisticsScreen)
// ══════════════════════════════════════════════════════════════════════════════

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppState>().sessions;
    final now = DateTime.now();

    // حساب دقائق اليوم
    final todayMinutes = sessions
        .where((s) =>
            s.timestamp.year == now.year &&
            s.timestamp.month == now.month &&
            s.timestamp.day == now.day)
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);

    // إجمالي كل الدقائق
    final totalMinutes = sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);

    // آخر 20 جلسة
    final last20Sessions = sessions.take(20).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('إحصائيات المذاكرة'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // كروت الملخص
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'دقائق اليوم',
                  value: '$todayMinutes',
                  subtitle: 'دقيقة مذاكرة',
                  icon: Icons.today_rounded,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'إجمالي الدقائق',
                  value: '$totalMinutes',
                  subtitle: 'كل الجلسات',
                  icon: Icons.all_inclusive_rounded,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            context,
            title: 'عدد الجلسات المنجزة',
            value: '${sessions.length}',
            subtitle: 'جلسة تركيز كاملة',
            icon: Icons.check_circle_outline_rounded,
            color: Colors.deepOrange,
          ),
          const SizedBox(height: 24),

          // قائمة آخر 20 جلسة
          const Text(
            'سجل آخر 20 جلسة تركيز:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (last20Sessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded, size: 60, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد جلسات مسجلة بعد.\nابدأ جلسة بومودورو لتسجيل إنجازك!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            ...last20Sessions.map(
              (sess) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.timer),
                  ),
                  title: Text(sess.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    DateFormat('yyyy/MM/dd - hh:mm a').format(sess.timestamp),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sess.durationMinutes} دقيقة',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                Icon(icon, color: color, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 🛠️ الشاشة 7: الإعدادات (SettingsScreen)
// ══════════════════════════════════════════════════════════════════════════════

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: ListView(
        children: [
          // الوضع الليلي
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('الوضع الليلي'),
            subtitle: const Text('تفعيل السمة الداكنة لإراحة العينين'),
            value: appState.isDarkMode,
            onChanged: (val) {
              context.read<AppState>().toggleDarkMode(val);
            },
          ),
          const Divider(),

          // إعدادات البومودورو
          ListTile(
            leading: const Icon(Icons.timelapse_rounded),
            title: const Text('إعدادات البومودورو'),
            subtitle: const Text('تخصيص أوقات المذاكرة والاستراحة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PomodoroSettingsScreen()),
              );
            },
          ),
          const Divider(),

          // عن التطبيق
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('عن التطبيق'),
            subtitle: const Text('معلومات المطور والإصدار'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutAppScreen()),
              );
            },
          ),
          const Divider(),

          // مسح كل البيانات
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
            title: const Text('مسح كل البيانات', style: TextStyle(color: Colors.red)),
            subtitle: const Text('حذف كافة المواعيد والجلسات والإعدادات نهائياً'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تحذير: مسح كل البيانات'),
                  content: const Text(
                    'هل أنت متأكد من رغبتك في حذف كافة المواعيد وسجل الجلسات؟ هذا الإجراء لا يمكن التراجع عنه.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        context.read<AppState>().clearAllData();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم مسح جميع البيانات بنجاح')),
                        );
                      },
                      child: const Text('مسح نهائي'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ℹ️ الشاشة 8: عن التطبيق (AboutAppScreen)
// ══════════════════════════════════════════════════════════════════════════════

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عن التطبيق'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alarm_rounded,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'تطبيق مواعيد (Mawaid)',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'منبه المذاكرة والتركيز الذكي',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.person_pin_rounded, size: 48, color: Colors.teal),
                      const SizedBox(height: 12),
                      const Text(
                        'تطوير وتصميم:',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'المهندس يوسف أحمد مصطفى',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text('الإصدار: 1.0.0 (Stable)'),
                      const SizedBox(height: 4),
                      const Text('Flutter: 3.27.1 • Dart: 3.2.0'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'صُمم هذا التطبيق خصيصاً لمساعدة الطلاب والباحثين على إدارة أوقاتهم بكفاءة عالية، مع تنبيهات صوتية موثوقة ومحفزة وجلسات بومودورو للتركيز المثمر.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
