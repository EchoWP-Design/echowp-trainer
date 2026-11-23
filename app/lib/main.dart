import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/coach_screen.dart';
import 'screens/data_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/today_screen.dart';
import 'screens/week_screen.dart';
import 'services/storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  final state = AppState(await Store.open(), DeviceSecrets());
  await state.init();
  runApp(TrainerApp(state: state));
}

class TrainerApp extends StatelessWidget {
  final AppState state;
  const TrainerApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'EchoWP Trainer',
        debugShowCheckedModeBanner: false,
        theme: echoTheme(),
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _autoSync();
  }

  /// Beim Öffnen synchronisieren, wenn der letzte Abruf über eine Stunde her ist.
  void _autoSync() {
    final st = context.read<AppState>();
    if (st.garminConfigured && st.syncDue && !st.busy) st.sync();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    const pages = [TodayScreen(), WeekScreen(), JournalScreen(), CoachScreen(), DataScreen()];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (st.busy) LinearProgressIndicator(minHeight: 3, color: echoYellow, backgroundColor: echoSurface2),
            if (st.lastError != null)
              MaterialBanner(
                backgroundColor: const Color(0xFF3A1416),
                content: Text(st.lastError!, style: const TextStyle(color: Colors.white)),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => st.lastError = null),
                    child: const Text('OK', style: TextStyle(color: echoYellow)),
                  )
                ],
              ),
            Expanded(child: IndexedStack(index: _tab, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Heute'),
          NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'Woche'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Journal'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Coach'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Daten'),
        ],
      ),
    );
  }
}

/// Kopfzeile mit Wortmarke „Echo“ + gelbem Block „Trainer“.
class EchoHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const EchoHeader({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Echo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: echoYellow, borderRadius: BorderRadius.circular(7)),
                    child: const Text('Trainer',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: echoBlack)),
                  ),
                ]),
              ),
              const SizedBox(height: 2),
              Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: echoMuted, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
          ...actions,
        ],
      ),
    );
  }
}
