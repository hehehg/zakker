import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:adhan/adhan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzd;
import 'package:timezone/timezone.dart' as tz;
import 'firebase_options.dart';

const green = Color(0xFF0B6B4F), gold = Color(0xFFC9A24B);
const offsetsAll = {0: 'وقت المهمة', 5: 'قبلها 5 د', 15: 'قبلها 15 د', 30: 'قبلها 30 د', 60: 'قبلها ساعة', 1440: 'قبلها يوم'};
const repeats = ['مرة واحدة', 'يوميًا', 'أسبوعيًا'];
const cats = ['عام', 'عبادة', 'عمل', 'دراسة', 'أسرة', 'صحة'];
const pris = ['عادية', 'مهمة', 'عاجلة'];
const List<Color?> priColors = [null, Colors.orange, Colors.red];
const cities = {'الإسماعيلية': [30.5965, 32.2715], 'القاهرة': [30.0444, 31.2357], 'الإسكندرية': [31.2001, 29.9187], 'مكة': [21.4225, 39.8262], 'المدينة': [24.4686, 39.6142]};
NotificationDetails nd(bool alarm) => NotificationDetails(android: alarm
  ? AndroidNotificationDetails('alarm', 'منبهات', importance: Importance.max, priority: Priority.max, category: AndroidNotificationCategory.alarm, fullScreenIntent: true, audioAttributesUsage: AudioAttributesUsage.alarm, additionalFlags: Int32List.fromList([4]))
  : const AndroidNotificationDetails('tasks', 'تذكير المهمات', importance: Importance.max, priority: Priority.high));

class T {
  int id, due, rep, upd, cat = 0, pri = 0; String title, note; List<int> offs; bool done, del, alarm = false;
  T(this.id, this.title, this.note, this.due, this.offs, this.rep, this.done, this.del, this.upd);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'note': note, 'due': due, 'offs': offs, 'rep': rep, 'done': done, 'del': del, 'upd': upd, 'cat': cat, 'pri': pri, 'alarm': alarm};
  factory T.fromJson(Map<String, dynamic> j) => T(j['id'], j['title'], j['note'] ?? '', j['due'], List<int>.from(j['offs']), j['rep'], j['done'], j['del'] ?? false, j['upd'])..cat = j['cat'] ?? 0..pri = j['pri'] ?? 0..alarm = j['alarm'] ?? false;
}

class Store extends ChangeNotifier {
  List<T> tasks = []; bool syncOn = true, fb = false, dark = false, salawat = true; String? status; String city = 'الإسماعيلية'; int filter = -1;
  late SharedPreferences sp;
  final np = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    syncOn = sp.getBool('sync') ?? true; dark = sp.getBool('dark') ?? false; salawat = sp.getBool('sal') ?? true; city = sp.getString('city') ?? city;
    tasks = (jsonDecode(sp.getString('tasks') ?? '[]') as List).map((e) => T.fromJson(e)).toList();
    try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); fb = true; } catch (_) {}
    tzd.initializeTimeZones();
    try { tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone())); } catch (_) {}
    await np.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(appName: 'ذكّرني', appUserModelId: 'com.zakker.app', guid: 'b1f0c1de-4a53-4a6e-9a1d-5a1f3d0c7e11')));
    if (Platform.isAndroid) {
      final a = np.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission(); await a?.requestExactAlarmsPermission();
    }
    await schedule();
    Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    sync();
  }

  void _save() { sp.setString('tasks', jsonEncode(tasks.map((e) => e.toJson()).toList())); notifyListeners(); }
  List<T> get live => tasks.where((t) => !t.del).toList()..sort((a, b) => a.due.compareTo(b.due));

  Future<void> upsert(T t) async {
    t.upd = DateTime.now().millisecondsSinceEpoch;
    final i = tasks.indexWhere((e) => e.id == t.id);
    i < 0 ? tasks.add(t) : tasks[i] = t;
    _save(); await schedule(); sync();
  }

  // أندرويد: إشعارات مجدولة (تعمل والتطبيق مقفول). ويندوز: فحص دوري أثناء تشغيل التطبيق.
  Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await np.cancelAll();
    for (final e in auto()) {
      await np.zonedSchedule(e.$1, e.$3, e.$4, tz.TZDateTime.from(e.$2, tz.local), nd(false),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
    }
    if (salawat) await np.periodicallyShow(1600000000, 'صلِّ على النبي ﷺ', 'اللهم صلِّ وسلِّم على نبينا محمد', RepeatInterval.hourly, nd(false), androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
    final now = DateTime.now();
    for (final t in tasks.where((t) => !t.del && !t.done)) {
      for (final o in t.offs) {
        final at = DateTime.fromMillisecondsSinceEpoch(t.due).subtract(Duration(minutes: o));
        if (at.isBefore(now) && t.rep == 0) continue;
        await np.zonedSchedule((t.id % 100000000) * 10 + o % 10 + (o ~/ 10 % 10), t.title,
          o == 0 ? 'حان موعد المهمة' : offsetsAll[o], tz.TZDateTime.from(at, tz.local),
          nd(t.alarm),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: t.rep == 1 ? DateTimeComponents.time : t.rep == 2 ? DateTimeComponents.dayOfWeekAndTime : null);
      }
    }
  }

  // مواقيت الصلاة تُحسب محليًا (تعمل أوفلاين) + أذكار الصباح والمساء
  List<(int, DateTime, String, String)> auto({bool all = false}) {
    final c = cities[city]!, p = CalculationMethod.egyptian.getParameters(), now = DateTime.now();
    final out = <(int, DateTime, String, String)>[];
    for (var d = 0; d < 7; d++) {
      final pt = PrayerTimes(Coordinates(c[0], c[1]), DateComponents.from(now.add(Duration(days: d))), p);
      final ps = [('الفجر', pt.fajr), ('الظهر', pt.dhuhr), ('العصر', pt.asr), ('المغرب', pt.maghrib), ('العشاء', pt.isha)];
      for (var k = 0; k < 5; k++) out.add((1500000000 + d * 10 + k, ps[k].$2.toLocal(), 'حان موعد صلاة ${ps[k].$1}', 'حيّ على الصلاة 🕌'));
      out.add((1500000100 + d, ps[0].$2.toLocal().add(const Duration(minutes: 30)), 'أذكار الصباح', 'ابدأ يومك بذكر الله ☀️'));
      out.add((1500000200 + d, ps[2].$2.toLocal().add(const Duration(minutes: 30)), 'أذكار المساء', 'حصّن نفسك بأذكار المساء 🌙'));
    }
    return out.where((e) => all || e.$2.isAfter(now)).toList();
  }

  final fired = <String>{};
  void _tick() {
    if (!Platform.isWindows) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    for (final e in auto(all: true)) {
      final at = e.$2.millisecondsSinceEpoch;
      if (n >= at && n < at + 120000 && fired.add('a${e.$1}')) np.show(e.$1, e.$3, e.$4, null);
    }
    for (final t in tasks.where((t) => !t.del && !t.done)) {
      for (final o in t.offs) {
        final at = t.due - o * 60000, k = '${t.id}-$o-$at';
        if (n >= at && n < at + 120000 && fired.add(k)) {
          np.show(t.id % 100000000, t.title, o == 0 ? 'حان موعد المهمة' : offsetsAll[o], null);
        }
      }
    }
  }

  Future<void> sync() async {
    if (!syncOn || !fb || FirebaseAuth.instance.currentUser == null) return;
    try {
      final col = FirebaseFirestore.instance.collection('users/${FirebaseAuth.instance.currentUser!.uid}/tasks');
      final remote = {for (final d in (await col.get()).docs) d.id: T.fromJson(d.data())};
      for (final r in remote.values) {
        final i = tasks.indexWhere((t) => t.id == r.id);
        if (i < 0) tasks.add(r); else if (r.upd > tasks[i].upd) tasks[i] = r;
      }
      for (final t in tasks) {
        final r = remote['${t.id}'];
        if (r == null || t.upd > r.upd) await col.doc('${t.id}').set(t.toJson());
      }
      status = 'تمت المزامنة ${DateFormat.Hm().format(DateTime.now())}'; _save(); schedule();
    } catch (_) { status = 'تعذرت المزامنة (أوفلاين؟)'; notifyListeners(); }
  }

  Future<String> auth(String e, String p, bool up) async {
    try {
      up ? await FirebaseAuth.instance.createUserWithEmailAndPassword(email: e, password: p)
         : await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: p);
      await sync(); return 'تم تسجيل الدخول';
    } catch (x) { return 'خطأ: $x'; }
  }
  void setPref({bool? d, bool? s, String? c}) {
    dark = d ?? dark; salawat = s ?? salawat; city = c ?? city;
    sp.setBool('dark', dark); sp.setBool('sal', salawat); sp.setString('city', city); notifyListeners(); schedule();
  }
  void setSync(bool v) { syncOn = v; sp.setBool('sync', v); notifyListeners(); if (v) sync(); }
}

final store = Store();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  runApp(ListenableBuilder(listenable: store, builder: (_, __) => MaterialApp(
    debugShowCheckedModeBanner: false, themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
    darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green, secondary: gold, brightness: Brightness.dark)),
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green, secondary: gold), scaffoldBackgroundColor: const Color(0xFFF7F3E8)),
    builder: (c, w) => Directionality(textDirection: ui.TextDirection.rtl, child: w!),
    home: const Home())));
}

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: store, builder: (c, _) {
    final l = store.live.where((t) => store.filter < 0 || t.cat == store.filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('﷽  ذكّرني'), backgroundColor: green, foregroundColor: Colors.white, actions: [
        IconButton(icon: const Icon(Icons.bar_chart), onPressed: () => showDialog(context: c, builder: (_) => const Stats())),
        IconButton(icon: const Icon(Icons.sync), onPressed: store.sync),
        IconButton(icon: const Icon(Icons.settings), onPressed: () => showDialog(context: c, builder: (_) => const Settings()))]),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: gold, onPressed: () => edit(c, null), icon: const Icon(Icons.add), label: const Text('مهمة جديدة')),
      body: Column(children: [SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(6), children: [for (var i = -1; i < cats.length; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: ChoiceChip(label: Text(i < 0 ? 'الكل' : cats[i]), selected: store.filter == i, onSelected: (_) { store.filter = i; store.setPref(); }))])), Expanded(child: l.isEmpty ? const Center(child: Text('لا توجد مهام.. استعن بالله وابدأ ✨'))
        : ListView(padding: const EdgeInsets.all(12), children: [for (final t in l) Card(child: ListTile(
            leading: Checkbox(value: t.done, activeColor: green, onChanged: (v) { t.done = v!; store.upsert(t); }),
            title: Text(t.title, style: TextStyle(color: priColors[t.pri], decoration: t.done ? TextDecoration.lineThrough : null)),
            subtitle: Text('${DateFormat('EEE d MMM – hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(t.due))}  •  ${repeats[t.rep]}  •  ${cats[t.cat]}${t.alarm ? '  ⏰' : ''}'),
            onTap: () => edit(c, t),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { t.del = true; store.upsert(t); })))]))]),
      bottomNavigationBar: store.status == null ? null : Padding(padding: const EdgeInsets.all(8), child: Text(store.status!, textAlign: TextAlign.center)));
  });
}

void edit(BuildContext c, T? old) {
  final t = old ?? T(DateTime.now().microsecondsSinceEpoch % 1000000000, '', '', DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch, [0, 15], 0, false, false, 0);
  final title = TextEditingController(text: t.title), note = TextEditingController(text: t.note);
  showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (c, set) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.due);
    return Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'المهمة')),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.event), label: Text(DateFormat('d MMM yyyy').format(d)), onPressed: () async {
          final p = await showDatePicker(context: c, initialDate: d, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (p != null) set(() => t.due = DateTime(p.year, p.month, p.day, d.hour, d.minute).millisecondsSinceEpoch);
        })),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.access_time), label: Text(DateFormat('hh:mm a').format(d)), onPressed: () async {
          final p = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(d));
          if (p != null) set(() => t.due = DateTime(d.year, d.month, d.day, p.hour, p.minute).millisecondsSinceEpoch);
        }))]),
      Wrap(spacing: 6, children: [for (final e in offsetsAll.entries) FilterChip(label: Text(e.value), selected: t.offs.contains(e.key),
        onSelected: (v) => set(() => v ? t.offs.add(e.key) : t.offs.remove(e.key)))]),
      DropdownButton<int>(value: t.rep, isExpanded: true, items: [for (var i = 0; i < 3; i++) DropdownMenuItem(value: i, child: Text(repeats[i]))], onChanged: (v) => set(() => t.rep = v!)),
      Row(children: [
        Expanded(child: DropdownButton<int>(value: t.cat, isExpanded: true, items: [for (var i = 0; i < cats.length; i++) DropdownMenuItem(value: i, child: Text(cats[i]))], onChanged: (v) => set(() => t.cat = v!))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButton<int>(value: t.pri, isExpanded: true, items: [for (var i = 0; i < 3; i++) DropdownMenuItem(value: i, child: Text(pris[i]))], onChanged: (v) => set(() => t.pri = v!)))]),
      SwitchListTile(title: const Text('منبّه بصوت وشاشة كاملة'), value: t.alarm, onChanged: (v) => set(() => t.alarm = v)),
      FilledButton(style: FilledButton.styleFrom(backgroundColor: green), onPressed: () {
        if (title.text.trim().isEmpty) return;
        t.title = title.text.trim(); t.note = note.text; if (t.offs.isEmpty) t.offs = [0];
        store.upsert(t); Navigator.pop(c);
      }, child: const Text('حفظ'))])));
  }));
}

class Settings extends StatefulWidget { const Settings({super.key}); @override State<Settings> createState() => _S(); }
class _S extends State<Settings> {
  final e = TextEditingController(), p = TextEditingController(); String msg = '';
  @override
  Widget build(BuildContext c) {
    final u = store.fb ? FirebaseAuth.instance.currentUser : null;
    return AlertDialog(title: const Text('الإعدادات'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(title: const Text('المزامنة التلقائية'), value: store.syncOn, onChanged: (v) { store.setSync(v); setState(() {}); }),
      SwitchListTile(title: const Text('الوضع الداكن'), value: store.dark, onChanged: (v) { store.setPref(d: v); setState(() {}); }),
      SwitchListTile(title: const Text('تذكير بالصلاة على النبي ﷺ كل ساعة'), value: store.salawat, onChanged: (v) { store.setPref(s: v); setState(() {}); }),
      DropdownButton<String>(value: store.city, isExpanded: true, items: [for (final k in cities.keys) DropdownMenuItem(value: k, child: Text('مدينة المواقيت: $k'))], onChanged: (v) { store.setPref(c: v); setState(() {}); }),
      if (!store.fb) const Text('Firebase غير مفعّل - عدّل firebase_options.dart')
      else if (u != null) ...[Text(u.email ?? ''), TextButton(onPressed: () async { await FirebaseAuth.instance.signOut(); setState(() {}); }, child: const Text('تسجيل خروج'))]
      else ...[
        TextField(controller: e, decoration: const InputDecoration(labelText: 'البريد')),
        TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
        Row(children: [
          TextButton(onPressed: () async { msg = await store.auth(e.text, p.text, false); setState(() {}); }, child: const Text('دخول')),
          TextButton(onPressed: () async { msg = await store.auth(e.text, p.text, true); setState(() {}); }, child: const Text('حساب جديد'))])],
      Text(msg)])));
  }
}

class Stats extends StatelessWidget {
  const Stats({super.key});
  @override
  Widget build(BuildContext c) {
    final l = store.live, now = DateTime.now().millisecondsSinceEpoch, done = l.where((t) => t.done).length;
    return AlertDialog(title: const Text('إحصائياتك'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('الإجمالي: ${l.length}  •  المنجزة: $done  •  المتأخرة: ${l.where((t) => !t.done && t.due < now).length}'),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: l.isEmpty ? 0 : done / l.length, color: green, minHeight: 10),
      const SizedBox(height: 12),
      for (var i = 0; i < cats.length; i++) Text('${cats[i]}: ${l.where((t) => t.cat == i).length}')]));
  }
}
