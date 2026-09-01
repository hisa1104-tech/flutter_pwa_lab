import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// 💡 PDF生成用の正しいインポート（.dart を外しました）
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// 💡 共有メニュー（LINEやメール、保存）を起動するために必須のインポートを追加
import 'package:share_plus/share_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart'; // 💡 アセット読み込み用に追加

void main() async {
  // 💡 プラグインの初期化を確実に行う
  WidgetsFlutterBinding.ensureInitialized();
  // 💡 Hive (IndexedDB) の初期化
  await Hive.initFlutter();
  await Hive.openBox('anes_box');
  await Hive.openBox('settings_box'); // 💡 ユーザー設定用に追加
  runApp(const AnesthesiaApp());
}

class AnesthesiaApp extends StatelessWidget {
  const AnesthesiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '麻酔記録システム',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'NotoSansJP', // 💡 埋め込みフォントをデフォルトに設定
      ),
      home: const _AuthWrapper(),
    );
  }
}

// 🔐 認証状態によって表示を切り替えるラッパー
class _AuthWrapper extends StatefulWidget {
  const _AuthWrapper();

  @override
  State<_AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<_AuthWrapper> {
  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final box = Hive.box('settings_box');
    // デバッグ用や再認証が必要な場合はここを false にしてリセット可能
    setState(() {
      _isAuthenticated = box.get('is_authenticated', defaultValue: false);
      _isLoading = false;
    });
  }

  void _onAuthenticated() {
    setState(() {
      _isAuthenticated = true;
    });
    Hive.box('settings_box').put('is_authenticated', true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return _isAuthenticated ? const MainRecordPage() : _LoginScreen(onSuccess: _onAuthenticated);
  }
}

// 🔐 ログイン画面
class _LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LoginScreen({required this.onSuccess});

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final TextEditingController _passCtrl = TextEditingController();
  String _errorMessage = '';
  // 💡 クローズドβ用パスワード
  final String _correctPassword = 'X7p9W2r4K1mQ';

  void _login() {
    if (_passCtrl.text == _correctPassword) {
      widget.onSuccess();
    } else {
      setState(() {
        _errorMessage = 'パスワードが正しくありません';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900,
      body: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              const Text('Anesthesia Case Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('Closed Beta Test', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'パスワード',
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage.isEmpty ? null : _errorMessage,
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade900,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ログイン', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainRecordPage extends StatefulWidget {
  const MainRecordPage({super.key});

  @override
  State<MainRecordPage> createState() => _MainRecordPageState();
}

// --- データモデルの定義 ---
class VitalRecord {
  final String id;
  DateTime dateTime;
  double sbp;
  double dbp;
  double hr;
  double spo2;

  VitalRecord({
    required this.id,
    required this.dateTime,
    required this.sbp,
    required this.dbp,
    required this.hr,
    required this.spo2,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'dateTime': dateTime.toIso8601String(),
        'sbp': sbp,
        'dbp': dbp,
        'hr': hr,
        'spo2': spo2,
      };

  factory VitalRecord.fromMap(Map<String, dynamic> map) => VitalRecord(
        id: map['id'],
        dateTime: DateTime.parse(map['dateTime']),
        sbp: (map['sbp'] as num).toDouble(),
        dbp: (map['dbp'] as num).toDouble(),
        hr: (map['hr'] as num).toDouble(),
        spo2: (map['spo2'] as num).toDouble(),
      );
}

class AnesthesiaEvent {
  final String id;
  final String name;
  final String symbol;
  final Color activeColor;
  DateTime? time;

  AnesthesiaEvent({
    required this.id,
    required this.name,
    required this.symbol,
    required this.activeColor,
    this.time,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'activeColor': activeColor.value,
        'time': time?.toIso8601String(),
      };

  factory AnesthesiaEvent.fromMap(Map<String, dynamic> map) => AnesthesiaEvent(
        id: map['id'],
        name: map['name'],
        symbol: map['symbol'],
        activeColor: Color(map['activeColor']),
        time: map['time'] != null ? DateTime.parse(map['time']) : null,
      );
}

class IvRecord {
  final String id;
  final DateTime time;
  final String gauge;
  final String site;
  final bool isSuccess;

  IvRecord({
    required this.id,
    required this.time,
    required this.gauge,
    required this.site,
    required this.isSuccess,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'gauge': gauge,
        'site': site,
        'isSuccess': isSuccess,
      };

  factory IvRecord.fromMap(Map<String, dynamic> map) => IvRecord(
        id: map['id'],
        time: DateTime.parse(map['time']),
        gauge: map['gauge'],
        site: map['site'],
        isSuccess: map['isSuccess'],
      );
}

class RemarkLog {
  final String id;
  final DateTime time;
  final String text;
  int number;

  RemarkLog({
    required this.id,
    required this.time,
    required this.text,
    required this.number,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'text': text,
        'number': number,
      };

  factory RemarkLog.fromMap(Map<String, dynamic> map) => RemarkLog(
        id: map['id'],
        time: DateTime.parse(map['time']),
        text: map['text'],
        number: map['number'],
      );
}

class InfusionPoint {
  final String id;
  DateTime time;
  final String val;
  final bool isStop;

  InfusionPoint({
    required this.id,
    required this.time,
    required this.val,
    this.isStop = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'val': val,
        'isStop': isStop,
      };

  factory InfusionPoint.fromMap(Map<String, dynamic> map) => InfusionPoint(
        id: map['id'],
        time: DateTime.parse(map['time']),
        val: map['val'],
        isStop: map['isStop'] ?? false,
      );
}

class BolusLog {
  final String id;
  DateTime time;
  final String drugName;
  String amount;
  final String unit;

  BolusLog({
    required this.id,
    required this.time,
    required this.drugName,
    required this.amount,
    required this.unit,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'drugName': drugName,
        'amount': amount,
        'unit': unit,
      };

  factory BolusLog.fromMap(Map<String, dynamic> map) => BolusLog(
        id: map['id'],
        time: DateTime.parse(map['time']),
        drugName: map['drugName'],
        amount: map['amount'],
        unit: map['unit'],
      );
}

// 💡 4. 【データ合流用のミニ道具箱】ファイルの一番下（クラスの外など）に置いてください
class _PdfLogItem {
  final DateTime time;
  final String category;
  final String content;
  final PdfColor color;

  _PdfLogItem({
    required this.time,
    required this.category,
    required this.content,
    required this.color,
  });
}

class AnesthesiaDotPainter extends FlDotCirclePainter {
  final String type;
  final Color customColor;
  final double customSize;

  AnesthesiaDotPainter({
    required this.type,
    required this.customColor,
    this.customSize = 10.0,
  }) : super(color: customColor, radius: customSize / 2);

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offset) {
    final paint = Paint()
      ..color = customColor
      ..style = (type == 'hr' || type == 'spo2')
          ? PaintingStyle.fill
          : PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final hSize = customSize / 2;
    if (type == 'sbp') {
      canvas.drawPath(
        Path()
          ..moveTo(offset.dx - hSize, offset.dy - hSize)
          ..lineTo(offset.dx, offset.dy + hSize)
          ..lineTo(offset.dx + hSize, offset.dy - hSize),
        paint,
      );
    } else if (type == 'dbp') {
      canvas.drawPath(
        Path()
          ..moveTo(offset.dx - hSize, offset.dy + hSize)
          ..lineTo(offset.dx, offset.dy - hSize)
          ..lineTo(offset.dx + hSize, offset.dy + hSize),
        paint,
      );
    } else if (type == 'hr') {
      canvas.drawRect(
        Rect.fromCenter(center: offset, width: customSize, height: customSize),
        paint,
      );
    } else if (type == 'spo2') {
      canvas.drawCircle(offset, customSize / 2, paint);
    }
  }

  @override
  Size getSize(FlSpot spot) => Size(customSize, customSize);
}

class _MainRecordPageState extends State<MainRecordPage> {
  // 🌟 初期値を空っぽに変更（これで最初から文字が入るのを防ぎます）
  final TextEditingController _pIdCtrl = TextEditingController(text: '');
  final TextEditingController _pNameCtrl = TextEditingController(text: '');
  final TextEditingController _pAgeCtrl = TextEditingController(text: '');
  final TextEditingController _pHeightCtrl = TextEditingController(text: '');
  final TextEditingController _pWeightCtrl = TextEditingController(text: '');
  final TextEditingController _pDiseaseCtrl = TextEditingController(text: '');
  final TextEditingController _pOpeCtrl = TextEditingController(text: '');
  String _pGender = '男';
  final TextEditingController _anesthetistCtrl = TextEditingController();

  final List<VitalRecord> _records = [];
  DateTime? _startTime;
  double _selectedTimelineMinutes = 30.0;

  final List<IvRecord> _ivRecords = [];
  final List<RemarkLog> _remarkLogs = [];

  final Map<String, List<InfusionPoint>> _infusionMap = {
    'O2': [],
    'N2O': [],
    'PropofolInf': [],
    'Dex': [], // 👈 追加
  };
  final List<BolusLog> _bolusLogs = [];

  bool _showN2oRow = false;
  bool _showAcerioRow = false;
  bool _showRopionRow = false;
  bool _showDexRow = false; // 👈 追加


  // 🌟 追加：非表示にした行の名前を保存する場所
  final Set<String> _hiddenRowKeys = {};
  // 🌟 追加：手動で非表示にした行を保存するセット
  final Set<String> _manuallyHiddenRows = {};

  // === 💡 ここから輸液機能のために新しく追記 ===
  String _selectedFluidType = 'フィジオ140'; // プルダウンで今選ばれている輸液名を記憶する変数
  final TextEditingController _fluidController =
  TextEditingController(); // 輸液の量を入力するテキスト欄のコントローラー
  // ===========================================
  String _selectedIvGauge = '22G';
  String _selectedIvSite = '左前腕';
  final TextEditingController _remarkController = TextEditingController();

  final TextEditingController _o2Controller = TextEditingController();
  final TextEditingController _n2oController = TextEditingController();
  final TextEditingController _dexController = TextEditingController(); // 👈 追加
  final TextEditingController _propofolInfController = TextEditingController();

  String _propofolInfUnit = 'mg/kg/h';
  String _dexUnit = 'μg/kg/h'; // 👈 追加
  String _selectedLaDrug = 'オーラ注';

  final TextEditingController _propofolBolusController =
  TextEditingController();
  final TextEditingController _midazolamController = TextEditingController();
  final TextEditingController _acerioController = TextEditingController();
  final TextEditingController _ropionController = TextEditingController();
  final TextEditingController _laMlController = TextEditingController();

  final TextEditingController _customDrugNameController =
  TextEditingController();
  final TextEditingController _customDrugAmountController =
  TextEditingController();
  String _selectedCustomUnit = 'mg';

  final List<AnesthesiaEvent> _events = [
    AnesthesiaEvent(
      id: 'enter',
      name: '入室',
      symbol: 'E',
      activeColor: Colors.purple,
    ),
    AnesthesiaEvent(
      id: 'anes_start',
      name: '麻酔開始',
      symbol: '×', //普通のバツに変更した
      activeColor: Colors.orange.shade800,
    ),
    AnesthesiaEvent(
      id: 'intro_comp',
      name: '導入完了',
      symbol: 'IC',
      activeColor: Colors.blue,
    ),
    AnesthesiaEvent(
      id: 'ope_start',
      name: '手術開始',
      symbol: '◎',
      activeColor: Colors.red.shade700,
    ),
    AnesthesiaEvent(
      id: 'ope_end',
      name: '手術終了',
      symbol: '◎',
      activeColor: Colors.red.shade400,
    ),
    AnesthesiaEvent(
      id: 'anes_end',
      name: '麻酔終了',
      symbol: '×', //普通のバツに変更した
      activeColor: Colors.orange.shade500,
    ),
    AnesthesiaEvent(
      id: 'exit',
      name: '退室',
      symbol: 'L',
      activeColor: Colors.brown,
    ),
  ];

  String _calculateBmi() {
    double? h = double.tryParse(_pHeightCtrl.text);
    double? w = double.tryParse(_pWeightCtrl.text);
    if (h == null || w == null || h <= 0) return '---';
    double bmi = w / ((h / 100) * (h / 100));
    return bmi.toStringAsFixed(1);
  }

  void _initStartTimeIfNeeded() {
    if (_startTime == null) {
      int roundedMinute = (DateTime.now().minute / 5).floor() * 5;
      DateTime rounded = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        DateTime.now().hour,
        roundedMinute,
      );
      _startTime = rounded.subtract(const Duration(minutes: 10));
    }
  }

  // 💡 ここから貼り付け（保険算定用の自動計算ロジック一式）
  String _calculateTotalMinutes(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-- 分';
    if (end.isBefore(start)) return '-- 分';
    final diff = end.difference(start);
    return '${diff.inMinutes} 分';
  }

  Map<String, String> _calculateO2Stats() {
    if (_startTime == null ||
        !_infusionMap.containsKey('O2') ||
        _infusionMap['O2']!.isEmpty) {
      return {'time': '0 分', 'amount': '0 L'};
    }

    final o2Points = _infusionMap['O2']!;
    int totalMinutes = 0;
    double totalVolumeLiters = 0.0;

    for (int i = 0; i < o2Points.length; i++) {
      final currentPoint = o2Points[i];
      if (currentPoint.isStop) continue;

      DateTime endTime = DateTime.now();
      if (i + 1 < o2Points.length) {
        endTime = o2Points[i + 1].time;
      }

      if (endTime.isBefore(currentPoint.time)) continue;
      final durationMinutes = endTime.difference(currentPoint.time).inMinutes;
      double flowRate = double.tryParse(currentPoint.val) ?? 0.0;

      totalMinutes += durationMinutes;
      totalVolumeLiters += flowRate * durationMinutes;
    }

    return {
      'time': '$totalMinutes 分',
      'amount': '${totalVolumeLiters.toStringAsFixed(1)} L',
    };
  }

  // 💡 ここまで貼り付け
  // 💡 【追加】保険算定用に、それぞれの開始・終了時刻を保存する変数を定義します
  DateTime? _anesthesiaStartTime;
  DateTime? _anesthesiaEndTime;
  DateTime? _opStartTime;
  DateTime? _opEndTime;

  // 💡 ユーザー設定（プリセット）を保持する変数
  List<String> _presetVisibleRows = ['O2', 'PropofolCiv', 'PropofolIv', 'Midazolam', 'LA', 'Fluid'];
  List<String> _presetVisiblePanelRows = ['O2', 'PropofolCiv', 'PropofolIv', 'Midazolam', 'LA', 'Fluid'];
  String _presetFluidType = 'フィジオ140';
  String _presetPropofolUnit = 'mg/kg/h';
  String _presetDexUnit = 'μg/kg/h';
  String _presetIvGauge = '22G';
  String _presetIvSite = '左前腕';
  String _presetLaDrug = 'オーラ注';
  String _presetAnesthetist = '';
  List<String> _pastAnesthetists = [];
  int _anesthetistHistoryLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings(); // 💡 まず設定を読み込む
    _loadAllData();
  }

  Future<void> _loadSettings() async {
    final box = Hive.box('settings_box');
    setState(() {
      _presetVisibleRows = box.get('visible_rows', defaultValue: ['O2', 'PropofolCiv', 'PropofolIv', 'Midazolam', 'LA', 'Fluid']).cast<String>();
      _presetVisiblePanelRows = box.get('visible_panel_rows', defaultValue: ['O2', 'PropofolCiv', 'PropofolIv', 'Midazolam', 'LA', 'Fluid']).cast<String>();
      _presetFluidType = box.get('fluid_type', defaultValue: 'フィジオ140');
      _presetPropofolUnit = box.get('propofol_unit', defaultValue: 'mg/kg/h');
      _presetDexUnit = box.get('dex_unit', defaultValue: 'μg/kg/h');
      _presetIvGauge = box.get('iv_gauge', defaultValue: '22G');
      _presetIvSite = box.get('iv_site', defaultValue: '左前腕');
      _presetLaDrug = box.get('la_drug', defaultValue: 'オーラ注');
      _presetAnesthetist = box.get('anesthetist', defaultValue: '');
      _pastAnesthetists = box.get('past_anesthetists', defaultValue: <String>[]).cast<String>();
      _anesthetistHistoryLimit = box.get('anesthetist_history_limit', defaultValue: 5);
      if (_anesthetistCtrl.text.isEmpty) _anesthetistCtrl.text = _presetAnesthetist;
    });
  }

  Future<void> _saveSettings() async {
    final box = Hive.box('settings_box');
    await box.put('visible_rows', _presetVisibleRows);
    await box.put('visible_panel_rows', _presetVisiblePanelRows);
    await box.put('fluid_type', _presetFluidType);
    await box.put('propofol_unit', _presetPropofolUnit);
    await box.put('dex_unit', _presetDexUnit);
    await box.put('iv_gauge', _presetIvGauge);
    await box.put('iv_site', _presetIvSite);
    await box.put('la_drug', _presetLaDrug);
    await box.put('anesthetist', _presetAnesthetist);
    await box.put('past_anesthetists', _pastAnesthetists);
    await box.put('anesthetist_history_limit', _anesthetistHistoryLimit);
  }

  // 💡 設定変更ダイアログを表示する
  void _showSettingsDialog() {
    List<String> tempVisible = List.from(_presetVisibleRows);
    List<String> tempPanelVisible = List.from(_presetVisiblePanelRows);
    String tempFluid = _presetFluidType;
    String tempPropofolUnit = _presetPropofolUnit;
    String tempDexUnit = _presetDexUnit;
    String tempIvGauge = _presetIvGauge;
    String tempIvSite = _presetIvSite;
    String tempLaDrug = _presetLaDrug;
    String tempAnesthetist = _presetAnesthetist;
    int tempHistoryLimit = _anesthetistHistoryLimit;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final TextEditingController anesthetistCtrl = TextEditingController(text: tempAnesthetist);
            final TextEditingController limitCtrl = TextEditingController(text: tempHistoryLimit.toString());

            // 💡 自由入力用のサブダイアログ
            Future<void> showFreeInput(String title, String hint, Function(String) onConfirm) async {
              final TextEditingController ctrl = TextEditingController();
              await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(fontSize: 12)),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                    ElevatedButton(
                      onPressed: () {
                        if (ctrl.text.trim().isNotEmpty) {
                          onConfirm(ctrl.text.trim());
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('確定'),
                    ),
                  ],
                ),
              );
            }

            Widget buildDropdownSetting(String label, String value, List<String> items, Function(String) onSelected, {bool allowFree = false, String? freeTitle, String? freeHint}) {
              final displayItems = <String>{
                ...items,
                if (value != '自由入力...') value,
                if (allowFree) '自由入力...',
              }.toList();

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: value,
                        items: displayItems.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: TextStyle(fontSize: 12, color: s == '自由入力...' ? Colors.blue : Colors.black87)),
                        )).toList(),
                        onChanged: (v) {
                          if (v == '自由入力...') {
                            showFreeInput(freeTitle!, freeHint!, (customValue) {
                              setDialogState(() => onSelected(customValue));
                            });
                          } else if (v != null) {
                            setDialogState(() => onSelected(v));
                          }
                        },
                        isDense: true,
                        isExpanded: true,
                        underline: const SizedBox(),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 💡 薬剤リストの中でインライン表示するドロップダウン
            Widget buildInlineDropdown(String value, List<String> items, Function(String) onSelected, {bool allowFree = false, String? freeTitle, String? freeHint}) {
              final displayItems = <String>{
                ...items,
                if (value != '自由入力...') value,
                if (allowFree) '自由入力...',
              }.toList();

              return Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<String>(
                  value: value,
                  items: displayItems.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: TextStyle(fontSize: 10, color: s == '自由入力...' ? Colors.blue : Colors.black87)),
                  )).toList(),
                  onChanged: (v) {
                    if (v == '自由入力...') {
                      showFreeInput(freeTitle!, freeHint!, (customValue) {
                        setDialogState(() => onSelected(customValue));
                      });
                    } else if (v != null) {
                      setDialogState(() => onSelected(v));
                    }
                  },
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox(),
                ),
              );
            }

            final Map<String, String> drugs = {
              'O2': 'O2', 'N2O': 'N2O', 'Dex': 'Dex civ',
              'PropofolCiv': 'Propofol civ', 'PropofolIv': 'Propofol iv',
              'Midazolam': 'Midazolam iv', 'Acerio': 'アセリオ',
              'Ropion': 'ロピオン', 'LA': '局所麻酔', 'Fluid': '輸液合計',
            };

            return AlertDialog(
              title: const Text('デフォルト表示と初期値の設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 600,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 左側: 薬剤表示設定 (単位/薬の選択を統合) ---
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 8),
                            child: Text('【薬剤表示設定】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                          ),
                          // ヘッダー行
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2),
                            child: Row(
                              children: [
                                const Expanded(flex: 5, child: SizedBox()),
                                Expanded(flex: 6, child: Text('単位 / 初期薬', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey.shade600))),
                                Expanded(flex: 3, child: Text('タイムライン', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey.shade600))),
                                Expanded(flex: 3, child: Text('薬剤投与', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey.shade600))),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView(
                              shrinkWrap: true,
                              children: drugs.entries.map((e) {
                                Widget? dropdown;
                                if (e.key == 'Dex') {
                                  dropdown = buildInlineDropdown(tempDexUnit, ['μg/kg/h', 'mL/h'], (v) => tempDexUnit = v);
                                } else if (e.key == 'PropofolCiv') {
                                  dropdown = buildInlineDropdown(tempPropofolUnit, ['mg/kg/h', 'mL/h', 'μg/mL'], (v) => tempPropofolUnit = v);
                                } else if (e.key == 'LA') {
                                  dropdown = buildInlineDropdown(tempLaDrug, ['オーラ注', 'セプトカイン', 'スキャンドネスト', 'シタネスト', 'エピリド', 'キシロカイン'], (v) => tempLaDrug = v, allowFree: true, freeTitle: '新しい局麻剤', freeHint: 'アナペイン');
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 0.5))),
                                  child: Row(
                                    children: [
                                      Expanded(flex: 5, child: Text(e.value, style: const TextStyle(fontSize: 11))),
                                      Expanded(flex: 6, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: dropdown ?? const SizedBox.shrink())),
                                      Expanded(
                                        flex: 3,
                                        child: Center(
                                          child: Checkbox(
                                            value: tempVisible.contains(e.key),
                                            onChanged: (val) => setDialogState(() {
                                              if (val == true) {
                                                tempVisible.add(e.key);
                                              } else {
                                                tempVisible.remove(e.key);
                                              }
                                            }),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Center(
                                          child: Checkbox(
                                            value: tempPanelVisible.contains(e.key),
                                            onChanged: (val) => setDialogState(() {
                                              if (val == true) {
                                                tempPanelVisible.add(e.key);
                                              } else {
                                                tempPanelVisible.remove(e.key);
                                              }
                                            }),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 32),
                    // --- 右側: 初期値の設定 ---
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text('【ルート確保設定】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                            ),
                            buildDropdownSetting('ゲージ数', tempIvGauge, ['20G', '22G', '24G'], (v) => tempIvGauge = v),
                            buildDropdownSetting('穿刺部位', tempIvSite, ['左前腕', '右前腕', '左手背', '右手背', '左肘', '右肘'], (v) => tempIvSite = v, allowFree: true, freeTitle: '新しい穿刺部位', freeHint: '例: 右大腿'),
                            buildDropdownSetting('輸液', tempFluid, ['フィジオ140', 'ラクテック注', 'ソルデム3A', '生理食塩水', 'ソリタT1', 'ソリタT3'], (v) => tempFluid = v, allowFree: true, freeTitle: '新しい輸液名', freeHint: '例: ビカネイト'),
                            const SizedBox(height: 16),
                            const Text('【麻酔担当医設定】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: anesthetistCtrl,
                              decoration: const InputDecoration(
                                labelText: 'デフォルト担当医名',
                                labelStyle: TextStyle(fontSize: 10),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (v) => tempAnesthetist = v,
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _pastAnesthetists.isEmpty ? null : () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => SimpleDialog(
                                      title: const Text('担当医履歴から選択', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                      children: _pastAnesthetists.map((name) => SimpleDialogOption(
                                        onPressed: () {
                                          setDialogState(() {
                                            tempAnesthetist = name;
                                            anesthetistCtrl.text = name;
                                          });
                                          Navigator.pop(ctx);
                                        },
                                        child: Text(name, style: const TextStyle(fontSize: 13)),
                                      )).toList(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.history, size: 14),
                                label: Text(
                                  _pastAnesthetists.isEmpty ? '履歴なし' : '履歴から選択',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                            if (_pastAnesthetists.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text('※設定を保存すると履歴に追加されます', style: TextStyle(fontSize: 8, color: Colors.grey)),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('履歴に保存する人数:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 40,
                                  height: 24,
                                  child: TextField(
                                    controller: limitCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 11),
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (v) {
                                      final val = int.tryParse(v);
                                      if (val != null) tempHistoryLimit = val;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _exportSettings,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('設定出力', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton.icon(
                      onPressed: _importSettings,
                      icon: const Icon(Icons.file_download, size: 16),
                      label: const Text('設定読込', style: TextStyle(fontSize: 11)),
                    ),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _presetVisibleRows = tempVisible;
                          _presetVisiblePanelRows = tempPanelVisible;
                          _presetFluidType = tempFluid;
                          _presetPropofolUnit = tempPropofolUnit;
                          _presetDexUnit = tempDexUnit;
                          _presetIvGauge = tempIvGauge;
                          _presetIvSite = tempIvSite;
                          _presetLaDrug = tempLaDrug;
                          _presetAnesthetist = tempAnesthetist;
                          _anesthetistHistoryLimit = tempHistoryLimit;

                          // 💡 履歴リストを更新
                          if (_presetAnesthetist.trim().isNotEmpty) {
                            _pastAnesthetists.remove(_presetAnesthetist.trim());
                            _pastAnesthetists.insert(0, _presetAnesthetist.trim());
                            if (_pastAnesthetists.length > _anesthetistHistoryLimit) {
                              _pastAnesthetists = _pastAnesthetists.sublist(0, _anesthetistHistoryLimit);
                            }
                          }
                        });
                        _saveSettings();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('デフォルト設定を更新しました。新規症例から反映されます。')));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                      child: const Text('設定を保存', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveAllData() async {
    try {
      final box = Hive.box('anes_box');
      final data = _createAllDataMap();
      final jsonStr = jsonEncode(data);
      await box.put('anes_case_data', jsonStr);
    } catch (e) {
      debugPrint('保存エラー: $e');
    }
  }

  Map<String, dynamic> _createAllDataMap() {
    return {
      'patientInfo': {
        'id': _pIdCtrl.text,
        'name': _pNameCtrl.text,
        'age': _pAgeCtrl.text,
        'height': _pHeightCtrl.text,
        'weight': _pWeightCtrl.text,
        'disease': _pDiseaseCtrl.text,
        'ope': _pOpeCtrl.text,
        'gender': _pGender,
        'anesthetist': _anesthetistCtrl.text,
      },
      'vitalRecords': _records.map((r) => r.toMap()).toList(),
      'startTime': _startTime?.toIso8601String(),
      'selectedTimelineMinutes': _selectedTimelineMinutes,
      'ivRecords': _ivRecords.map((r) => r.toMap()).toList(),
      'remarkLogs': _remarkLogs.map((r) => r.toMap()).toList(),
      'infusionMap': _infusionMap.map((k, v) => MapEntry(k, v.map((p) => p.toMap()).toList())),
      'bolusLogs': _bolusLogs.map((r) => r.toMap()).toList(),
      'toggles': {
        'showN2o': _showN2oRow,
        'showAcerio': _showAcerioRow,
        'showRopion': _showRopionRow,
        'showDex': _showDexRow,
      },
      'hiddenRowKeys': _hiddenRowKeys.toList(),
      'manuallyHiddenRows': _manuallyHiddenRows.toList(),
      'settings': {
        'fluidType': _selectedFluidType,
        'ivGauge': _selectedIvGauge,
        'ivSite': _selectedIvSite,
        'propofolUnit': _propofolInfUnit,
        'dexUnit': _dexUnit,
        'laDrug': _selectedLaDrug,
        'customUnit': _selectedCustomUnit,
      },
      'eventTimes': _events.map((e) => {'id': e.id, 'time': e.time?.toIso8601String()}).toList(),
      'insuranceTimes': {
        'anesStart': _anesthesiaStartTime?.toIso8601String(),
        'anesEnd': _anesthesiaEndTime?.toIso8601String(),
        'opStart': _opStartTime?.toIso8601String(),
        'opEnd': _opEndTime?.toIso8601String(),
      },
    };
  }

  Future<void> _loadAllData() async {
    try {
      final box = Hive.box('anes_box');
      final jsonStr = box.get('anes_case_data');
      if (jsonStr == null) {
        debugPrint('保存されているデータはありません');
        return;
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      _applyDataMap(data);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('前回のデータを復元しました'), duration: Duration(seconds: 5)),
        );
      }
    } catch (e) {
      debugPrint('読み込みエラー: $e');
    }
  }

  void _applyDataMap(Map<String, dynamic> data) {
    setState(() {
      if (data['patientInfo'] != null) {
        final pi = data['patientInfo'];
        _pIdCtrl.text = pi['id'] ?? '';
        _pNameCtrl.text = pi['name'] ?? '';
        _pAgeCtrl.text = pi['age'] ?? '';
        _pHeightCtrl.text = pi['height'] ?? '';
        _pWeightCtrl.text = pi['weight'] ?? '';
        _pDiseaseCtrl.text = pi['disease'] ?? '';
        _pOpeCtrl.text = pi['ope'] ?? '';
        _pGender = pi['gender'] ?? '男';
        _anesthetistCtrl.text = pi['anesthetist'] ?? '';
      }

      if (data['vitalRecords'] != null) {
        _records.clear();
        _records.addAll((data['vitalRecords'] as List).map((m) => VitalRecord.fromMap(m)));
      }

      if (data['startTime'] != null) {
        _startTime = DateTime.parse(data['startTime']);
      }
      _selectedTimelineMinutes = (data['selectedTimelineMinutes'] as num?)?.toDouble() ?? 30.0;

      if (data['ivRecords'] != null) {
        _ivRecords.clear();
        _ivRecords.addAll((data['ivRecords'] as List).map((m) => IvRecord.fromMap(m)));
      }
      if (data['remarkLogs'] != null) {
        _remarkLogs.clear();
        _remarkLogs.addAll((data['remarkLogs'] as List).map((m) => RemarkLog.fromMap(m)));
      }

      if (data['infusionMap'] != null) {
        final map = data['infusionMap'] as Map<String, dynamic>;
        _infusionMap.clear();
        map.forEach((k, v) {
          _infusionMap[k] = (v as List).map((m) => InfusionPoint.fromMap(m)).toList();
        });
        ['O2', 'N2O', 'PropofolInf', 'Dex'].forEach((key) {
          if (!_infusionMap.containsKey(key)) _infusionMap[key] = [];
        });
      }

      if (data['bolusLogs'] != null) {
        _bolusLogs.clear();
        _bolusLogs.addAll((data['bolusLogs'] as List).map((m) => BolusLog.fromMap(m)));
      }

      if (data['toggles'] != null) {
        final t = data['toggles'];
        _showN2oRow = t['showN2o'] ?? false;
        _showAcerioRow = t['showAcerio'] ?? false;
        _showRopionRow = t['showRopion'] ?? false;
        _showDexRow = t['showDex'] ?? false;
      }

      if (data['hiddenRowKeys'] != null) {
        _hiddenRowKeys.clear();
        _hiddenRowKeys.addAll((data['hiddenRowKeys'] as List).cast<String>());
      }
      if (data['manuallyHiddenRows'] != null) {
        _manuallyHiddenRows.clear();
        _manuallyHiddenRows.addAll((data['manuallyHiddenRows'] as List).cast<String>());
      }

      if (data['settings'] != null) {
        final s = data['settings'];
        _selectedFluidType = s['fluidType'] ?? 'フィジオ140';
        _selectedIvGauge = s['ivGauge'] ?? '22G';
        _selectedIvSite = s['ivSite'] ?? '左前腕';
        _propofolInfUnit = s['propofolUnit'] ?? 'mg/kg/h';
        _dexUnit = s['dexUnit'] ?? 'μg/kg/h';
        _selectedLaDrug = s['laDrug'] ?? 'オーラ注';
        _selectedCustomUnit = s['customUnit'] ?? 'mg';
      }

      if (data['eventTimes'] != null) {
        final etList = data['eventTimes'] as List;
        for (var et in etList) {
          final idx = _events.indexWhere((e) => e.id == et['id']);
          if (idx != -1) {
            _events[idx].time = et['time'] != null ? DateTime.parse(et['time']) : null;
          }
        }
      }

      if (data['insuranceTimes'] != null) {
        final it = data['insuranceTimes'];
        _anesthesiaStartTime = it['anesStart'] != null ? DateTime.parse(it['anesStart']) : null;
        _anesthesiaEndTime = it['anesEnd'] != null ? DateTime.parse(it['anesEnd']) : null;
        _opStartTime = it['opStart'] != null ? DateTime.parse(it['opStart']) : null;
        _opEndTime = it['opEnd'] != null ? DateTime.parse(it['opEnd']) : null;
      }
    });
  }

  Future<void> _exportToFile() async {
    final data = _createAllDataMap();
    final jsonStr = jsonEncode(data);
    final id = _pIdCtrl.text.isEmpty ? 'no-id' : _pIdCtrl.text;
    final name = _pNameCtrl.text.isEmpty ? 'no-name' : _pNameCtrl.text;
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = '${id}_${name}_$dateStr.json';

    // 💡 iPadやブラウザ環境を考慮
    if (html.window.navigator.userAgent.contains('Mobi') || html.window.navigator.userAgent.contains('iPad')) {
      // 💡 モバイル（iPad含む）の場合はShareを使ってファイルを書き出す
      final bytes = utf8.encode(jsonStr);
      final xFile = XFile.fromData(
        Uint8List.fromList(bytes),
        name: fileName,
        mimeType: 'application/json',
      );
      await Share.shareXFiles([xFile], text: 'Anesthesia Case Data');
    } else {
      // 💡 デスクトップブラウザの場合はダウンロード
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _importFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true, // 💡 iOS/Androidでバイトデータを取得するために必要
      );

      if (result != null) {
        String jsonStr;
        if (result.files.single.bytes != null) {
          jsonStr = utf8.decode(result.files.single.bytes!);
        } else {
          // 💡 Native環境の場合
          // ※ iPadのPWA版だとbytesの方に来るはずですが、念のため
          debugPrint('File picked but no bytes found. Path: ${result.files.single.path}');
          return;
        }

        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _applyDataMap(data);
        _saveAllData(); // インポートした内容をLocalStorageにも保存
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('データを復元しました')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error importing file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ファイルの読み込みに失敗しました')),
        );
      }
    }
  }

  // 💡 設定ファイルのエクスポート
  Future<void> _exportSettings() async {
    final box = Hive.box('settings_box');
    final Map<String, dynamic> data = {};
    for (var key in box.keys) {
      data[key.toString()] = box.get(key);
    }
    final jsonStr = jsonEncode(data);
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = 'anes_settings_$dateStr.json';

    if (html.window.navigator.userAgent.contains('Mobi') || html.window.navigator.userAgent.contains('iPad')) {
      final bytes = utf8.encode(jsonStr);
      final xFile = XFile.fromData(Uint8List.fromList(bytes), name: fileName, mimeType: 'application/json');
      await Share.shareXFiles([xFile], text: 'Anesthesia App Settings');
    } else {
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  // 💡 設定ファイルのインポート
  Future<void> _importSettings() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result != null) {
        final jsonStr = utf8.decode(result.files.single.bytes!);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        
        final box = Hive.box('settings_box');
        await box.clear();
        for (var entry in data.entries) {
          await box.put(entry.key, entry.value);
        }
        
        await _loadSettings(); // アプリの状態に反映
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設定をインポートしました')));
          Navigator.pop(context); // 設定画面を一度閉じる（反映を確実にするため）
        }
      }
    } catch (e) {
      debugPrint('設定インポートエラー: $e');
    }
  }

  Future<void> _clearAllData() async {
    final box = Hive.box('anes_box');
    await box.delete('anes_case_data');
    setState(() {
      _pIdCtrl.clear();
      _pNameCtrl.clear();
      _pAgeCtrl.clear();
      _pHeightCtrl.clear();
      _pWeightCtrl.clear();
      _pDiseaseCtrl.clear();
      _pOpeCtrl.clear();
      _pGender = '男';
      _anesthetistCtrl.text = _presetAnesthetist;
      _selectedCustomUnit = 'mg';
      _records.clear();
      _startTime = null;
      _ivRecords.clear();
      _remarkLogs.clear();
      _infusionMap.forEach((k, v) => v.clear());
      _bolusLogs.clear();
      // 💡 ユーザー設定（プリセット）に基づいて初期値をリセット
      _selectedFluidType = _presetFluidType;
      _propofolInfUnit = _presetPropofolUnit;
      _dexUnit = _presetDexUnit;
      _selectedIvGauge = _presetIvGauge;
      _selectedIvSite = _presetIvSite;
      _selectedLaDrug = _presetLaDrug;

      _showN2oRow = _presetVisibleRows.contains('N2O');
      _showAcerioRow = _presetVisibleRows.contains('Acerio');
      _showRopionRow = _presetVisibleRows.contains('Ropion');
      _showDexRow = _presetVisibleRows.contains('Dex');
      
      _hiddenRowKeys.clear();
      _manuallyHiddenRows.clear();
      for (var e in _events) {
        e.time = null;
      }
      _anesthesiaStartTime = null;
      _anesthesiaEndTime = null;
      _opStartTime = null;
      _opEndTime = null;
    });
  }

  // 🌟 自由入力用のポップアップダイアログ
  void _showCustomFluidDialog() {
    final TextEditingController customCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しい輸液の入力', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: customCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '例: ビカネイト',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (customCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    // 🌟 入力された文字列をそのまま現在の選択中の輸液名にする
                    _selectedFluidType = customCtrl.text.trim();
                  });
                  _saveAllData();
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('確定', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
// 🌟 ルート穿刺部位の自由入力用ポップアップダイアログ
  void _showCustomIvSiteDialog() {
    final TextEditingController customCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しい穿刺部位の入力', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: customCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '例: 右足背、左大腿 など',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (customCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    // 🌟 入力された文字列を現在の選択中の部位にする
                    _selectedIvSite = customCtrl.text.trim();
                  });
                  _saveAllData();
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('確定', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
// 🌟 局所麻酔剤の自由入力用ポップアップダイアログ
  void _showCustomLaDrugDialog() {
    final TextEditingController customCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しい局所麻酔剤の入力', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: customCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '例: アナペイン、マーカイン など',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (customCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    // 🌟 入力された文字列を現在の選択中の局麻剤にする
                    _selectedLaDrug = customCtrl.text.trim();
                  });
                  _saveAllData();
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('確定', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  final GlobalKey _chartCaptureKey = GlobalKey();

  Future<Uint8List?> _captureChartImage(BuildContext context) async {
    try {
      final boundary =
      _chartCaptureKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('画像キャプチャエラー: $e');
      return null;
    }
  }
  // 🌟 追加：PDF出力前の最終確認ダイアログ
  void _showPdfConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('PDF出力の確認', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: const Text(
            'トレンドおよびタイムラインはアプリ上の表示がそのままキャプチャされます。\n\n'
                '時間スケールの調整および未入力薬剤行の削除（ラベルをタップ）はお済みですか？\n\n'
                'PDF出力してよろしいですか？',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // ダイアログを閉じる
                _generatePdf();         // PDF生成を実行
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('PDF出力する', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // 🌟 追加：操作方法を表示するヘルプダイアログ
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('操作方法の確認', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('【基本操作】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('・左上の「患者アイコン」をタップするとメニュー（新規症例、データ出力、復元）が開きます。', style: TextStyle(fontSize: 12)),
                Text('・「バイタル入力」ボタンからSBP/DBP/HR/SpO2を一括入力できます。', style: TextStyle(fontSize: 12)),
                SizedBox(height: 10),
                Text('【タイムライン・グラフ】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('・薬剤名や項目の「ラベル」をタップすると、その行を一時的に非表示にできます。', style: TextStyle(fontSize: 12)),
                Text('・非表示にした行は、右下の「すべて再表示」ボタンで復元できます。', style: TextStyle(fontSize: 12)),
                Text('・上部の「10分〜180分」ボタンでタイムスケールを調整できます。', style: TextStyle(fontSize: 12)),
                SizedBox(height: 10),
                Text('【データの保存】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('・入力内容はブラウザ（IndexedDB）に自動保存され、再起動時に復元されます。', style: TextStyle(fontSize: 12)),
                Text('・「データ出力」でJSONファイルとしてiPad本体等に保存することをお勧めします。', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generatePdf() async {
    try {
      print('--- 【ログ】A4縦向き・3段コンパクトPDF生成スタート ---');

      await Future.delayed(const Duration(milliseconds: 200));
      final Uint8List? capturedImageBytes = await _captureChartImage(context);

      // 💡 ネットからではなく、アセットからフォントを読み込む（オフライン対策）
      final fontDataRegular = await rootBundle.load("assets/fonts/NotoSansJP-Regular.ttf");
      final fontDataBold = await rootBundle.load("assets/fonts/NotoSansJP-Bold.ttf");
      final pw.Font fontRegular = pw.Font.ttf(fontDataRegular);
      final pw.Font fontBold = pw.Font.ttf(fontDataBold);

      final pdf = pw.Document();
      final bmiString = _calculateBmi();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4, // 「縦向き」に固定
          margin: const pw.EdgeInsets.all(25),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // =========================================================================
                // タイトルヘッダー
                // =========================================================================
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '麻酔管理記録',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 15,
                        color: PdfColors.teal900,
                      ),
                    ),
                    pw.Text(
                      '出力日時: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Divider(thickness: 1.2, color: PdfColors.teal800),
                pw.SizedBox(height: 6),

                // =========================================================================
// 【上部レイアウト】3段構成（実際は4行）のコンパクト情報エリア
// =========================================================================
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey50,
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      // ✨ 【1段目】患者情報
                      pw.Row(
                        children: [
                          // 患者ID (幅90)
                          pw.SizedBox(
                            width: 90,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('患者ID: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                pw.Expanded(
                                  child: _pIdCtrl.text.isEmpty
                                      ? pw.Container(
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6, right: 5),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  )
                                      : pw.Text(_pIdCtrl.text, style: const pw.TextStyle(fontSize: 9)),
                                ),
                              ],
                            ),
                          ),
                          // 氏名 (幅130)
                          pw.SizedBox(
                            width: 130,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('氏名: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                pw.Expanded(
                                  child: _pNameCtrl.text.isEmpty
                                      ? pw.Container(
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6, right: 8),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  )
                                      : pw.Text(_pNameCtrl.text, style: const pw.TextStyle(fontSize: 9)),
                                ),
                              ],
                            ),
                          ),
                          // 年齢 (幅60)
                          pw.SizedBox(
                            width: 60,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('年齢: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                pw.Expanded(
                                  child: _pAgeCtrl.text.isEmpty
                                      ? pw.Container(
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6, right: 5),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  )
                                      : pw.Text('${_pAgeCtrl.text}歳', style: const pw.TextStyle(fontSize: 9)),
                                ),
                              ],
                            ),
                          ),
                          // 性別 (幅45)
                          pw.SizedBox(
                            width: 45,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(text: '性別: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                  pw.TextSpan(text: _pGender, style: const pw.TextStyle(fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                          // 身長 (幅65) ★下線 ＋ cm
                          pw.SizedBox(
                            width: 65,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('身長: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                if (_pHeightCtrl.text.isEmpty) ...[
                                  pw.Container(
                                    width: 25,
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  ),
                                  pw.Text('cm', style: const pw.TextStyle(fontSize: 9)),
                                ] else
                                  pw.Text('${_pHeightCtrl.text}cm', style: const pw.TextStyle(fontSize: 9)),
                              ],
                            ),
                          ),
                          // 体重 (幅65) ★下線 ＋ kg
                          pw.SizedBox(
                            width: 65,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('体重: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                if (_pWeightCtrl.text.isEmpty) ...[
                                  pw.Container(
                                    width: 25,
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  ),
                                  pw.Text('kg', style: const pw.TextStyle(fontSize: 9)),
                                ] else
                                  pw.Text('${_pWeightCtrl.text}kg', style: const pw.TextStyle(fontSize: 9)),
                              ],
                            ),
                          ),
                          // BMI
                          pw.RichText(
                            text: pw.TextSpan(
                              children: [
                                pw.TextSpan(text: 'BMI: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                pw.TextSpan(text: bmiString, style: pw.TextStyle(fontSize: 9)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey300),
                      pw.SizedBox(height: 4),

                      // ✨ 【2段目】病名（未入力時は手書き用の下線を表示）
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            '術前診断: ',
                            style: pw.TextStyle(font: fontBold, fontSize: 9),
                          ),
                          pw.Expanded(
                            child: _pDiseaseCtrl.text.isEmpty
                                ? pw.Container(
                              height: 12,
                              margin: const pw.EdgeInsets.only(top: 6),
                              decoration: pw.BoxDecoration(
                                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                              ),
                            )
                                : pw.Text(
                              _pDiseaseCtrl.text,
                              style: const pw.TextStyle(fontSize: 9),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),

                      // ✨ 【3段目】術式（未入力時は手書き用の下線を表示）
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            '予定術式: ',
                            style: pw.TextStyle(font: fontBold, fontSize: 9),
                          ),
                          pw.Expanded(
                            child: _pOpeCtrl.text.isEmpty
                                ? pw.Container(
                              height: 12,
                              margin: const pw.EdgeInsets.only(top: 6),
                              decoration: pw.BoxDecoration(
                                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                              ),
                            )
                                : pw.Text(
                              _pOpeCtrl.text,
                              style: const pw.TextStyle(fontSize: 9),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey300),
                      pw.SizedBox(height: 4),

                      // ✨ 【4段目】管理情報
                      pw.Row(
                        children: [
                          // 担当医 (幅160)
                          pw.SizedBox(
                            width: 160,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text('麻酔担当医: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                pw.Expanded(
                                  child: _anesthetistCtrl.text.isEmpty
                                      ? pw.Container(
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 6, right: 15),
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
                                    ),
                                  )
                                      : pw.Text(_anesthetistCtrl.text, style: const pw.TextStyle(fontSize: 9)),
                                ),
                              ],
                            ),
                          ),
                          // 手術時間
                          pw.SizedBox(
                            width: 100,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(text: '手術時間: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                  pw.TextSpan(text: _calculateTotalMinutes(_opStartTime, _opEndTime), style: const pw.TextStyle(fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                          // 麻酔時間
                          pw.SizedBox(
                            width: 100,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(text: '麻酔時間: ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                                  pw.TextSpan(text: _calculateTotalMinutes(_anesthesiaStartTime, _anesthesiaEndTime), style: const pw.TextStyle(fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // =========================================================================
                // 【下部レイアウト】差し替えエリア（トレンド＋ログ）
                // =========================================================================
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: capturedImageBytes == null
                      ? pw.Center(
                    child: pw.Text(
                      'データの取得に失敗しました',
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: 11,
                      ),
                    ),
                  )
                      : pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // --- 左側：トレンドキャプチャ画像 (全体の7割) ---
                      pw.Expanded(
                        flex: 7,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              color: PdfColors.grey300,
                              width: 0.5,
                            ),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '【トレンド】',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 9,
                                ),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Expanded(
                                child: pw.Image(
                                  pw.MemoryImage(capturedImageBytes),
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 10), // 左右の隙間
                      // --- 右側：【イベント・処置・メモ】のテキスト表示 (全体の3割) ---
                      pw.Expanded(
                        flex: 3,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              color: PdfColors.grey300,
                              width: 0.5,
                            ),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '【イベント・処置・メモ】',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 9,
                                ),
                              ),
                              pw.Divider(thickness: 0.5),
                              ..._buildPdfEventLogs(fontRegular),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '麻酔記録システム自動生成ドキュメント',
                    style: const pw.TextStyle(
                      fontSize: 6,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      final id = _pIdCtrl.text.isEmpty ? 'no-id' : _pIdCtrl.text;
      final name = _pNameCtrl.text.isEmpty ? 'no-name' : _pNameCtrl.text;
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final fileName = 'AnesRecord_${id}_${name}_$dateStr.pdf';

      if (html.window.navigator.userAgent.contains('Mobi') || html.window.navigator.userAgent.contains('iPad')) {
        final xFile = XFile.fromData(
          pdfBytes,
          name: fileName,
          mimeType: 'application/pdf',
        );
        await Share.shareXFiles([xFile], text: 'Anesthesia Record PDF');
      } else {
        final blob = html.Blob([pdfBytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      }

      print('--- 【ログ】縦向きPDF処理が正常終了しました ---');
    } catch (e) {
      print('--- 【ログ】縦向きPDF生成エラー: $e ---');
    }
  }

  // 👇 ここから追加（PDF用のイベントログを作成する道具）
  List<pw.Widget> _buildPdfEventLogs(pw.Font font) {
    List<_PdfLogItem> allLogs = [];

    // 1. イベント（入室、麻酔開始など）を収集
    for (var e in _events) {
      if (e.time != null) {
        allLogs.add(
          _PdfLogItem(
            time: e.time!,
            category: 'Event',
            content: '(${e.symbol}) ${e.name}',
            color: PdfColors.black,
          ),
        );
      }
    }

    // 2. ルート確保（PV）を収集
    for (var iv in _ivRecords) {
      allLogs.add(
        _PdfLogItem(
          time: iv.time,
          category: 'IV',
          content: 'PV ${iv.gauge}/${iv.site} ', //-> ${iv.isSuccess ? "成功" : "失敗"}',
          color: PdfColors.black,
        ),
      );
    }

    // 3. 処置メモ（No.1: ○○ など）を収集
    for (var rm in _remarkLogs) {
      allLogs.add(
        _PdfLogItem(
          time: rm.time,
          category: 'Remark',
          content: 'No.${rm.number}: ${rm.text}',
          color: PdfColors.black,
        ),
      );
    }

    // 💡 全てのログを時間順（古い順）に並べ替える
    allLogs.sort((a, b) => a.time.compareTo(b.time));

    // 💡 PDF用のテキストウィジェットのリストに変換
    return allLogs.map((log) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Text(
          '[${DateFormat('HH:mm').format(log.time)}] ${log.content}',
          style: pw.TextStyle(font: font, fontSize: 8),
        ),
      );
    }).toList();
  }

  // 👆 ここまで追加
  // 🌟 追加：薬剤の合計投与量を計算してPDF用の表にする
  // List<pw.Widget> _buildPdfDrugSummary(pw.Font fontBold, pw.Font fontRegular) {
  //   // 薬剤名をキーにして合計量を貯める箱
  //   Map<String, double> totals = {};
  //   Map<String, String> units = {};
  //
  //   for (var b in _bolusLogs) {
  //     // 局所麻酔(LA)と輸液以外を集計対象にする（輸液は別枠が多いため）
  //     if (b.drugName == 'LA' || ['フィジオ140', 'ラクテック注', 'ソルデム3A', '生理食塩水', 'ソリタT1', 'ソリタT3'].contains(b.drugName)) continue;
  //
  //     double amount = double.tryParse(b.amount) ?? 0;
  //     totals[b.drugName] = (totals[b.drugName] ?? 0) + amount;
  //     units[b.drugName] = b.unit;
  //   }
  //
  //   if (totals.isEmpty) return [];
  //
  //   return [
  //     pw.SizedBox(height: 10),
  //     pw.Text('【薬剤合計投与量（iv）】', style: pw.TextStyle(font: fontBold, fontSize: 9)),
  //     pw.Divider(thickness: 0.5),
  //     ...totals.entries.map((e) => pw.Padding(
  //       padding: const pw.EdgeInsets.symmetric(vertical: 1),
  //       child: pw.Text('${e.key}: ${e.value.toStringAsFixed(1)} ${units[e.key]}', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
  //     )),
  //   ];
  // }

  // 💡 選択されたタイムライン幅（30分など）に合わせて、5分刻みの目盛りリストを作ります
  List<double> _buildXAxisTicks() {
    final List<double> ticks = [];
    double interval = 5.0; // 基本は5分刻み

    // もしタイムラインが120分など長い場合は10分〜20分刻みに自動調整
    if (_selectedTimelineMinutes > 60) interval = 10.0;
    if (_selectedTimelineMinutes > 120) interval = 20.0;

    for (double i = 0; i <= _selectedTimelineMinutes; i += interval) {
      ticks.add(i);
    }
    return ticks;
  }



  void _addRemark() {
    if (_remarkController.text.trim().isEmpty) return;
    setState(() {
      _initStartTimeIfNeeded();
      _remarkLogs.add(
        RemarkLog(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          text: _remarkController.text.trim(),
          number: _remarkLogs.length + 1,
        ),
      );
      _remarkController.clear();
      _saveAllData();
    });
  }

  void _addInfusionPoint(String key, String val) {
    if (val.trim().isEmpty) return;
    setState(() {
      _initStartTimeIfNeeded();
      if (key == 'N2O') _showN2oRow = true;
      if (key == 'Dex') _showDexRow = true; // 👈 追加
      _infusionMap[key]!.add(
        InfusionPoint(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          val: val.trim(),
        ),
      );
      _infusionMap[key]!.sort((a, b) => a.time.compareTo(b.time));
      _saveAllData();
    });
  }

  void _stopInfusionPoint(String key) {
    setState(() {
      _initStartTimeIfNeeded();
      if (key == 'N2O') _showN2oRow = true;
      if (key == 'Dex') _showDexRow = true; // 👈 追加
      _infusionMap[key]!.add(
        InfusionPoint(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          val: 'OFF',
          isStop: true,
        ),
      );
      _infusionMap[key]!.sort((a, b) => a.time.compareTo(b.time));
      _saveAllData();
    });
  }

  void _addBolus(String drug, String amount, String unit) {
    if (amount.trim().isEmpty) return;
    setState(() {
      _initStartTimeIfNeeded();
      if (drug == 'アセリオ') _showAcerioRow = true;
      if (drug == 'ロピオン') _showRopionRow = true;
      _bolusLogs.add(
        BolusLog(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          drugName: drug,
          amount: amount.trim(),
          unit: unit,
        ),
      );
    });
  }

  void _showEditDeleteDialog({
    required String title,
    required DateTime initialTime,
    String? initialAmount,
    String? amountLabel,
    required Function(DateTime newTime, String? newAmount) onUpdate,
    required VoidCallback onDelete,
  }) {
    DateTime targetTime = initialTime;
    TextEditingController amountEditController = TextEditingController(
      text: initialAmount,
    );
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void adjustTime(int m) {
              setDialogState(() {
                targetTime = targetTime.add(Duration(minutes: m));
              });
            }

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () {
                      onDelete();
                      Navigator.pop(context);
                      setState(() {});
                      _saveAllData();
                    },
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      DateFormat('HH:mm').format(targetTime),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => adjustTime(-5),
                        child: const Text('-5分'),
                      ),
                      ElevatedButton(
                        onPressed: () => adjustTime(-1),
                        child: const Text('-1分'),
                      ),
                      ElevatedButton(
                        onPressed: () => adjustTime(1),
                        child: const Text('+1分'),
                      ),
                      ElevatedButton(
                        onPressed: () => adjustTime(5),
                        child: const Text('+5分'),
                      ),
                    ],
                  ),
                  if (initialAmount != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '$amountLabel: ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: TextField(
                              controller: amountEditController,
                              keyboardType: TextInputType.text,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    onUpdate(
                      targetTime,
                      initialAmount != null ? amountEditController.text : null,
                    );
                    Navigator.pop(context);
                    setState(() {});
                    _saveAllData();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEventTimeEditDialog(AnesthesiaEvent event) {
    if (event.time == null) return;
    _showEditDeleteDialog(
      title: '${event.name} の修正',
      initialTime: event.time!,
      // 💡 1. 時刻が更新されたときの連動
      onUpdate: (nt, _) => setState(() {
        event.time = nt; // 元のイベント時刻を更新

        if (event.name == '麻酔開始') {
          _anesthesiaStartTime = nt;
        } else if (event.name == '麻酔終了') {
          _anesthesiaEndTime = nt;
        } else if (event.name == '手術開始') {
          _opStartTime = nt;
        } else if (event.name == '手術終了') {
          _opEndTime = nt;
        }
      }),
      // 💡 2. イベントが削除されたときの連動
      onDelete: () => setState(() {
        event.time = null; // 元のイベント時刻を削除

        if (event.name == '麻酔開始') {
          _anesthesiaStartTime = null;
        } else if (event.name == '麻酔終了') {
          _anesthesiaEndTime = null;
        } else if (event.name == '手術開始') {
          _opStartTime = null;
        } else if (event.name == '手術終了') {
          _opEndTime = null;
        }
      }),
    );
  }

  void _showVitalEditDialog(VitalRecord record) {
    TextEditingController sbpCtrl = TextEditingController(
      text: record.sbp.toInt().toString(),
    );
    TextEditingController dbpCtrl = TextEditingController(
      text: record.dbp.toInt().toString(),
    );
    TextEditingController hrCtrl = TextEditingController(
      text: record.hr.toInt().toString(),
    );
    TextEditingController spo2Ctrl = TextEditingController(
      text: record.spo2.toInt().toString(),
    );
    DateTime targetTime = record.dateTime;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'バイタルデータの修正',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () {
                      setState(
                            () => _records.removeWhere((r) => r.id == record.id),
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('HH:mm').format(targetTime),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => setDialogState(
                              () => targetTime = targetTime.subtract(
                            const Duration(minutes: 1),
                          ),
                        ),
                        child: const Text('-1分'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () => setDialogState(
                              () => targetTime = targetTime.add(
                            const Duration(minutes: 1),
                          ),
                        ),
                        child: const Text('+1分'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sbpCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '収縮期血圧',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dbpCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '拡張期血圧',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hrCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '心拍数',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: spo2Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'SpO2',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      record.dateTime = targetTime;
                      record.sbp = double.tryParse(sbpCtrl.text) ?? record.sbp;
                      record.dbp = double.tryParse(dbpCtrl.text) ?? record.dbp;
                      record.hr = double.tryParse(hrCtrl.text) ?? record.hr;
                      record.spo2 =
                          double.tryParse(spo2Ctrl.text) ?? record.spo2;
                      _records.sort((a, b) => a.dateTime.compareTo(b.dateTime));
                    });
                    Navigator.pop(context);
                    _saveAllData();
                  },
                  child: const Text('変更保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 💡 始点を揃えるため、ラベル幅を110pxに、グリッド右端のマージンを15pxに設定（チャート側と完全に一致）
  Widget _buildTimelineRow({
    required String label,
    required String rowKey, // 🌟 追加：どの行か特定するための名前
    required double maxMinutes,
    required List<Widget> children,
    Color? bgColor,
    double height = 25,
  }) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 0.8),
      child: Row(
        children: [
          // 🌟 ラベル部分をタップ可能に変更
          InkWell(
            // 🌟【ここを追加】イベント、処置メモ、輸液のキーだったらタップ処理を無効にするガード
            onTap: (rowKey == 'event' || rowKey == 'remark' || rowKey == 'Fluid' || rowKey == '')
                ? null // nullを渡すことで、InkWellのタップエフェクト（波紋）も消えて完全に反応しなくなります
                : () => _confirmHideRow(label, rowKey),
            child: Container(
              width: 122,
              padding: const EdgeInsets.only(left: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 15),
              decoration: BoxDecoration(
                color: bgColor ?? Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [...children],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🌟 追加：削除確認ポップアップを出す命令
  void _confirmHideRow(String label, String rowKey) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('行の非表示', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text('タイムラインから「$label」の行を一時的に消しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hiddenRowKeys.add(rowKey);
              });
              _saveAllData(); // 非表示リストに追加
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('非表示にする'),
          ),
        ],
      ),
    );
  }


  /*List<Widget> _getVitalPins(double maxMinutes, double width) {
    if (_startTime == null || maxMinutes <= 0) return [];
    return _records.map((r) {
      double m = r.dateTime.difference(_startTime!).inMinutes.toDouble();
      return Positioned(
        left: (width * (m / maxMinutes)).clamp(0.0, width) - 6,
        top: 2,
        child: InkWell(
          onTap: () => _showVitalEditDialog(r),
          child: const Text('●', style: TextStyle(fontSize: 10, color: Colors.red)),
        ),
      );
    }).toList();
  }
  */

  List<Widget> _getEventPins(double maxMinutes, double width) {
    if (_startTime == null || maxMinutes <= 0) return [];
    return _events.where((e) => e.time != null).map((e) {
      double m = e.time!.difference(_startTime!).inSeconds.toDouble() / 60;
      return Positioned(
        left: (width * (m / maxMinutes)).clamp(0.0, width) - 8,
        top: 0,
        bottom: 0,
        child: Align(
          alignment: Alignment.center, // 💡 追加：上下中央に
          child: InkWell(
            onTap: () => _showEventTimeEditDialog(e),
            child: Text(
              e.symbol,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: e.activeColor,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _getCombinedIvAndRemarkPins(double maxMinutes, double width) {
    if (_startTime == null || maxMinutes <= 0) return [];
    List<Widget> pins = [];
    for (var iv in _ivRecords) {
      double m = iv.time.difference(_startTime!).inSeconds.toDouble() / 60;
      Color color = iv.isSuccess ? Colors.green : Colors.red;
      pins.add(
        Positioned(
          left: (width * (m / maxMinutes)).clamp(0.0, width) - 8,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => _showEditDeleteDialog(
                title: 'ルート確保の修正',
                initialTime: iv.time,
                onDelete: () => setState(
                      () => _ivRecords.removeWhere((i) => i.id == iv.id),
                ),
                onUpdate: (nt, _) => setState(() {
                  int idx = _ivRecords.indexWhere((i) => i.id == iv.id);
                  if (idx != -1)
                    _ivRecords[idx] = IvRecord(
                      id: iv.id,
                      time: nt,
                      gauge: iv.gauge,
                      site: iv.site,
                      isSuccess: iv.isSuccess,
                    );
                }),
              ),
              child: Text(
                'PV',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ), // 💡 10 ➔ 10.5
            ),
          ),
        ),
      );
    }
    for (var rm in _remarkLogs) {
      double m = rm.time.difference(_startTime!).inSeconds.toDouble() / 60;
      pins.add(
        Positioned(
          left: (width * (m / maxMinutes)).clamp(0.0, width) - 4,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => _showEditDeleteDialog(
                title: 'リマークス No.${rm.number} の修正',
                initialTime: rm.time,
                initialAmount: rm.text,
                amountLabel: 'メモ内容',
                onDelete: () => setState(() {
                  _remarkLogs.removeWhere((r) => r.id == rm.id);
                  for (int i = 0; i < _remarkLogs.length; i++) {
                    _remarkLogs[i].number = i + 1;
                  }
                }),
                onUpdate: (nt, na) => setState(() {
                  int idx = _remarkLogs.indexWhere((r) => r.id == rm.id);
                  if (idx != -1) {
                    _remarkLogs[idx] = RemarkLog(
                      id: rm.id,
                      time: nt,
                      text: na ?? rm.text,
                      number: rm.number,
                    );
                  }
                }),
              ),
              child: Text(
                '${rm.number}',
                style: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ), // 💡 10 ➔ 11.0
            ),
          ),
        ),
      );
    }
    return pins;
  }

  List<Widget> _getInfusionGraphics(
      String key,
      double maxMinutes,
      double width,
      Color color,
      ) {
    List<Widget> elements = [];
    if (_startTime == null || maxMinutes <= 0) return elements;
    final points = _infusionMap[key]!;

    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      if (current.isStop) continue;
      double startM =
          current.time.difference(_startTime!).inSeconds.toDouble() / 60;
      double endM = maxMinutes;
      if (i + 1 < points.length) {
        endM =
            points[i + 1].time.difference(_startTime!).inSeconds.toDouble() /
                60;
      }
      if (startM < 0) startM = 0;
      if (endM > maxMinutes) endM = maxMinutes;
      if (startM >= maxMinutes) continue;
      double left = width * (startM / maxMinutes);
      double lineWidth = (width * (endM / maxMinutes)) - left;
      if (lineWidth < 1) lineWidth = 1;
      elements.add(
        Positioned(
          left: left,
          top: 11,
          child: Container(
            width: lineWidth,
            height: 1.5,
            color: color.withOpacity(0.5),
          ),
        ),
      ); //持続投与の横線の上下的位置
    }

    for (var pt in points) {
      double m = pt.time.difference(_startTime!).inSeconds.toDouble() / 60;
      if (m < 0 || m > maxMinutes) continue;
      double leftPosition = width * (m / maxMinutes);

      String displayVal = pt.val;
      if (!pt.isStop) {
        final RegExp numRegex = RegExp(r'^\d+\.?\d*');
        final match = numRegex.firstMatch(pt.val);
        if (match != null) displayVal = match.group(0)!;
      }

      elements.add(
        Positioned(
          left: leftPosition - 6,
          top: 0,
          bottom: 0,
          // 💡 top:0, bottom:0 にすることで、Positionedの縦幅を行の高さ(25px)いっぱいに広げます
          child: Align(
            alignment: Alignment.center,
            // 💡 これにより、行の高さに対して「垂直方向のど真ん中」にカチッと配置されます
            child: InkWell(
              onTap: () => _showEditDeleteDialog(
                title: '${key == "PropofolInf" ? "Propofol civ" : key} の修正',
                initialTime: pt.time,
                initialAmount: pt.isStop ? null : pt.val,
                amountLabel: '設定値',
                onDelete: () => setState(
                      () => _infusionMap[key]!.removeWhere((p) => p.id == pt.id),
                ),
                onUpdate: (nt, na) => setState(() {
                  int idx = _infusionMap[key]!.indexWhere((p) => p.id == pt.id);
                  if (idx != -1) {
                    _infusionMap[key]![idx].time = nt;
                    if (na != null)
                      _infusionMap[key]![idx] = InfusionPoint(
                        id: pt.id,
                        time: nt,
                        val: na,
                        isStop: pt.isStop,
                      );
                    _infusionMap[key]!.sort((a, b) => a.time.compareTo(b.time));
                  }
                }),
              ),
              child: pt.isStop
                  ? Text(
                '┃',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              )
                  : Text(
                displayVal,
                style: TextStyle(
                  fontSize: 12, // 💡 文字サイズも 9.0 ➔ 9.5 へわずかに大きくして視認性アップ！
                  fontWeight: FontWeight.bold,
                  color: color,
                  backgroundColor: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return elements;
  }

  List<Widget> _getBolusPins(
      String drugFilter,
      double maxMinutes,
      double width,
      Color color,
      ) {
    List<Widget> pins = [];
    if (_startTime == null || maxMinutes <= 0) return pins;

    // 1. 該当する薬剤（または輸液）の全ログを抽出して時間順にソート
    List<BolusLog> targets = _bolusLogs
        .where((b) => b.drugName == drugFilter)
        .toList();
    targets.sort((a, b) => a.time.compareTo(b.time));

    if (targets.isEmpty) return pins;

    // 💡 【新機能】もしこの行が「輸液（または現在選択中の輸液名）」だった場合、最初と最後の点の間を繋ぐ横線を描画
    if (drugFilter == '輸液' || drugFilter == _selectedFluidType) {
      double startMin =
          targets.first.time.difference(_startTime!).inSeconds.toDouble() /
              60; // 👈 修正
      double endMin =
          targets.last.time.difference(_startTime!).inSeconds.toDouble() /
              60; // 👈 修正

      double startX = (width * (startMin / maxMinutes)).clamp(0.0, width);
      double endX = (width * (endMin / maxMinutes)).clamp(0.0, width);
      double lineWidth = endX - startX;

      // 最初の入力から最後の入力までの間に、持続投与のような太い線（3px）を引く
      pins.add(
        Positioned(
          left: startX,
          width: lineWidth,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              height: 1.5, //1.5pxに変更
              color: color.withOpacity(0.45), // 横線の色と不透明度
            ),
          ),
        ),
      );
    }

    // 2. 数字のピン（0 や 500 など）を上に重ねて描画
    for (var b in targets) {
      double m =
          b.time.difference(_startTime!).inSeconds.toDouble() / 60; // 👈 修正
      String displayAmount = b.amount;
      if (drugFilter == 'LA' && b.amount.contains(' ')) {
        displayAmount = b.amount.split(' ').last;
      }

      pins.add(
        Positioned(
          left: (width * (m / maxMinutes)).clamp(0.0, width) - 6,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => _showEditDeleteDialog(
                title: '${drugFilter == "LA" ? "局所麻酔" : drugFilter} の修正',
                initialTime: b.time,
                initialAmount: displayAmount,
                amountLabel: '投与量',
                onDelete: () => setState(
                      () => _bolusLogs.removeWhere((bl) => bl.id == b.id),
                ),
                onUpdate: (nt, na) => setState(() {
                  int idx = _bolusLogs.indexWhere((bl) => bl.id == b.id);
                  if (idx != -1) {
                    String finalAmount = na ?? displayAmount;
                    if (drugFilter == 'LA') {
                      String prefix = b.amount.split(' ').first;
                      finalAmount = '$prefix $finalAmount';
                    }
                    _bolusLogs[idx].time = nt;
                    _bolusLogs[idx].amount = finalAmount;
                  }
                }),
              ),
              child: Text(
                displayAmount,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                  // 💡 輸液の時、引かれた横線と文字が重なっても数字がクッキリ浮き上がって読めるように白背景を敷きます
                  backgroundColor:
                  (drugFilter == '輸液' || drugFilter == _selectedFluidType)
                      ? Colors.white.withOpacity(0.85)
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return pins;
  }

  List<Widget> _getDynamicCustomBolusPins(
      String drugName,
      double maxMinutes,
      double width,
      Color color,
      ) {
    List<Widget> pins = [];
    if (_startTime == null || maxMinutes <= 0) return pins;
    final targets = _bolusLogs.where((b) => b.drugName == drugName);
    for (var b in targets) {
      double m = b.time.difference(_startTime!).inSeconds.toDouble() / 60;
      pins.add(
        Positioned(
          left: (width * (m / maxMinutes)).clamp(0.0, width) - 6,
          top: 0,
          bottom: 0, // 💡 追加
          child: Align(
            alignment: Alignment.center, // 💡 追加
            child: InkWell(
              onTap: () => _showEditDeleteDialog(
                title: '$drugName の修正',
                initialTime: b.time,
                initialAmount: b.amount,
                amountLabel: '投与量',
                onDelete: () => setState(
                      () => _bolusLogs.removeWhere((bl) => bl.id == b.id),
                ),
                onUpdate: (nt, na) => setState(() {
                  int idx = _bolusLogs.indexWhere((bl) => bl.id == b.id);
                  if (idx != -1) {
                    _bolusLogs[idx].time = nt;
                    _bolusLogs[idx].amount = na ?? b.amount;
                  }
                }),
              ),
              child: Text(
                b.amount,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ), // 💡 9.0 ➔ 9.5
            ),
          ),
        ),
      );
    }
    return pins;
  }

  LineChartData _mainChartData() {
    double computedMaxY = 200;
    double maxMinutes = _selectedTimelineMinutes <= 0
        ? 30.0
        : _selectedTimelineMinutes;

    if (_startTime != null) {
      for (var r in _records) {
        double m = r.dateTime.difference(_startTime!).inMinutes.toDouble();
        if (r.sbp > computedMaxY) computedMaxY = r.sbp + 20;
        if (m > maxMinutes) maxMinutes = m + 5;
      }
    }

    List<FlSpot> sbpSpots = [];
    List<FlSpot> dbpSpots = [];
    List<FlSpot> hrSpots = [];
    List<FlSpot> spo2Spots = [];
    if (_startTime != null && _records.isNotEmpty) {
      for (var r in _records) {
        double m = r.dateTime.difference(_startTime!).inMinutes.toDouble();
        sbpSpots.add(FlSpot(m, r.sbp));
        dbpSpots.add(FlSpot(m, r.dbp));
        hrSpots.add(FlSpot(m, r.hr));
        spo2Spots.add(FlSpot(m, r.spo2));
      }
    } else {
      sbpSpots.add(const FlSpot(0, 0));
    }

    double interval = 5.0;
    if (maxMinutes >= 180) {
      interval = 30.0;
    } else if (maxMinutes >= 120) {
      interval = 20.0;
    } else if (maxMinutes >= 60) {
      interval = 10.0;
    }

    return LineChartData(
      // 💡 グラフの描画エリアを完全に数理計算通りに固定し、自動のブレをなくします
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 20,
        verticalInterval: interval,
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: interval,
            getTitlesWidget: (value, meta) {
              if (_startTime == null) return const Text('');
              return Text(
                DateFormat(
                  'HH:mm',
                ).format(_startTime!.add(Duration(minutes: value.toInt()))),
                style: const TextStyle(fontSize: 9),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 20,
            getTitlesWidget: (v, m) =>
                Text('${v.toInt()}', style: const TextStyle(fontSize: 9)),
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade400),
      ),
      minX: 0,
      maxX: maxMinutes,
      minY: 0,
      maxY: computedMaxY,
      lineBarsData: _records.isEmpty
          ? []
          : [
        LineChartBarData(
          spots: sbpSpots,
          color: Colors.red,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => AnesthesiaDotPainter(
              type: 'sbp',
              customColor: Colors.red,
            ),
          ),
        ),
        LineChartBarData(
          spots: dbpSpots,
          color: Colors.red,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => AnesthesiaDotPainter(
              type: 'dbp',
              customColor: Colors.red,
            ),
          ),
        ),
        LineChartBarData(
          spots: hrSpots,
          color: Colors.green,
          barWidth: 1.2,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => AnesthesiaDotPainter(
              type: 'hr',
              customColor: Colors.green,
              customSize: 6,
            ),
          ),
        ),
        LineChartBarData(
          spots: spo2Spots,
          color: Colors.cyan,
          barWidth: 1.2,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => AnesthesiaDotPainter(
              type: 'spo2',
              customColor: Colors.cyan,
              customSize: 6,
            ),
          ),
        ),
      ],
    );
  }

  void _showCustomKeypadDialog() {
    String sbp = '';
    String dbp = '';
    String hr = '';
    String spo2 = '';
    int activeIndex = 0;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void pressKey(String key) {
              setDialogState(() {
                if (key == 'C') {
                  if (activeIndex == 0) sbp = '';
                  if (activeIndex == 1) dbp = '';
                  if (activeIndex == 2) hr = '';
                  if (activeIndex == 3) spo2 = '';
                } else if (key == '➔') {
                  activeIndex = (activeIndex + 1) % 4;
                } else {
                  if (activeIndex == 0 && sbp.length < 3) sbp += key;
                  if (activeIndex == 1 && dbp.length < 3) dbp += key;
                  if (activeIndex == 2 && hr.length < 3) hr += key;
                  if (activeIndex == 3 && spo2.length < 3) spo2 += key;
                }
              });
            }

            Widget inputField(
                String label,
                String value,
                int index,
                Color color,
                ) {
              bool isActive = activeIndex == index;
              return GestureDetector(
                onTap: () => setDialogState(() => activeIndex = index),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? color.withOpacity(0.1) : Colors.white,
                    border: Border.all(
                      color: isActive ? color : Colors.grey.shade300,
                      width: isActive ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        value.isEmpty ? '---' : value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('バイタル入力'),
              content: SizedBox(
                width: 400,
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: inputField('収縮期', sbp, 0, Colors.red),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: inputField(
                                  '拡張期',
                                  dbp,
                                  1,
                                  Colors.red.shade300,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          inputField('心拍数', hr, 2, Colors.green),
                          const SizedBox(height: 5),
                          inputField('SpO2', spo2, 3, Colors.cyan),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('戻る'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _initStartTimeIfNeeded();
                                    _records.add(
                                      VitalRecord(
                                        id: DateTime.now().toString(),
                                        dateTime: DateTime.now(),
                                        sbp: double.tryParse(sbp) ?? 0,
                                        dbp: double.tryParse(dbp) ?? 0,
                                        hr: double.tryParse(hr) ?? 0,
                                        spo2: double.tryParse(spo2) ?? 0,
                                      ),
                                    );
                                  });
                                  Navigator.pop(context);
                                  _saveAllData();
                                },
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var row in [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                            ['C', '0', '➔'],
                          ])
                            Row(
                              children: row
                                  .map(
                                    (k) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: ElevatedButton(
                                      onPressed: () => pressKey(k),
                                      child: Text(
                                        k,
                                        style: const TextStyle(
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 💡 縦型コンパクトなLegendデザインに変更
  Widget _verticalLegendItem(String label, Color color, String sym) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sym,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrField(
      String label,
      TextEditingController ctrl, {
        double? width,
        bool isNum = false,
        String? hintText,
        Function(String)? onSubmitted,
      }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 4),
        if (width != null)
          SizedBox(
            width: width,
            height: 24,
            child: TextField(
              controller: ctrl,
              keyboardType: isNum
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              onChanged: (_) {
                setState(() {});
                _saveAllData();
              },
              onSubmitted: onSubmitted,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                // 🌟 ヒントテキストの設定を追加
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, fontWeight: FontWeight.normal),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 0,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: ctrl,
                keyboardType: isNum ? TextInputType.number : TextInputType.text,
                onChanged: (_) {
                setState(() {});
                _saveAllData();
              },
              onSubmitted: onSubmitted,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  // 🌟 こちらのヒントテキストの設定を追加（病名・術式用）
                  hintText: hintText,
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, fontWeight: FontWeight.normal),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 0,
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 1.2),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _alignedDrugRow({
    required String label,
    required Widget child,
    required Widget suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(flex: 3, child: SizedBox(height: 26, child: child)),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: SizedBox(height: 26, child: suffix)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double screenWidth = constraints.maxWidth;
            // 💡 グラフの枠線(Border)や内部パディングの厚み分(約4px)をさらに引き、タイムラインと完全同期させます
            double chartW = (screenWidth * 5 / 10) - 122 - 15 - 4;
            if (chartW <= 0) chartW = 100.0;

            double maxX = _selectedTimelineMinutes <= 0
                ? 30.0
                : _selectedTimelineMinutes;
            if (_startTime != null) {
              for (var r in _records) {
                double m = r.dateTime
                    .difference(_startTime!)
                    .inMinutes
                    .toDouble();
                if (m > maxX) maxX = m + 5;
              }
              for (var e in _events) {
                if (e.time != null) {
                  double em = e.time!
                      .difference(_startTime!)
                      .inMinutes
                      .toDouble();
                  if (em > maxX) maxX = em + 5;
                }
              }
              for (var key in _infusionMap.keys) {
                if (_infusionMap[key]!.isNotEmpty) {
                  double im = _infusionMap[key]!.last.time
                      .difference(_startTime!)
                      .inMinutes
                      .toDouble();
                  if (im > maxX) maxX = im + 5;
                }
              }
              for (var b in _bolusLogs) {
                double bm = b.time.difference(_startTime!).inMinutes.toDouble();
                if (bm > maxX) maxX = bm + 5;
              }
            }

            final fixedDrugs = ['Propofol', 'Midazolam', 'LA', 'アセリオ', 'ロピオン', _selectedLaDrug];
            final customDrugNames = _bolusLogs
                .map((b) => b.drugName)
                .where((name) => !fixedDrugs.contains(name))
                .toSet()
                .toList();

            return Column(
              children: [
                // ================= PATIENT HEADER =================
                Container(
                  color: Colors.blue.shade900,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 🌟 左側：大きくしたメニューアイコン
                      SizedBox(
                        height: 44,
                        width: 44,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.account_box,
                            color: Colors.white,
                            size: 40,
                          ),
                          tooltip: 'メニュー',
                          onSelected: (value) {
                            if (value == 'new_case') {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('新規症例の開始'),
                                  content: const Text('現在の入力内容をすべて削除し、新しい麻酔記録を開始します。よろしいですか？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('キャンセル'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        _clearAllData();
                                        Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('実行', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            } else if (value == 'export') {
                              _exportToFile();
                            } else if (value == 'import') {
                              _importFromFile();
                            } else if (value == 'settings') {
                              _showSettingsDialog();
                            } else if (value == 'help') {
                              _showHelpDialog();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'new_case',
                              child: Row(
                                children: [
                                  Icon(Icons.add_box, color: Colors.red, size: 18),
                                  SizedBox(width: 8),
                                  Text('新規症例を開始', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download, color: Colors.blueGrey, size: 18),
                                  SizedBox(width: 8),
                                  Text('データをファイル出力', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.upload, color: Colors.blueGrey, size: 18),
                                  SizedBox(width: 8),
                                  Text('ファイルから復元', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'settings',
                              child: Row(
                                children: [
                                  Icon(Icons.settings, color: Colors.blueGrey, size: 18),
                                  SizedBox(width: 8),
                                  Text('プリセット設定', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'help',
                              child: Row(
                                children: [
                                  Icon(Icons.help_outline, color: Colors.blueGrey, size: 18),
                                  SizedBox(width: 8),
                                  Text('操作方法を表示', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 🌟 右側：2段の入力フィールド
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _hdrField(
                                  'ID:',
                                  _pIdCtrl,
                                  width: 65,
                                  hintText: '123456',
                                  onSubmitted: (v) {
                                    if (v.isNotEmpty && v.length < 6) {
                                      _pIdCtrl.text = v.padLeft(6, '0');
                                      setState(() {});
                                      _saveAllData();
                                    }
                                  },
                                ),
                                const SizedBox(width: 10),
                                _hdrField('氏名:', _pNameCtrl, width: 100, hintText: '麻酔 太郎'),
                                const SizedBox(width: 10),
                                _hdrField('年齢:', _pAgeCtrl, width: 35, isNum: true),
                                const SizedBox(width: 8),
                                const Text(
                                  '性別:',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  height: 24,
                                  child: DropdownButton<String>(
                                    dropdownColor: Colors.blue.shade900,
                                    value: _pGender,
                                    isDense: true,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    items: ['男', '女']
                                        .map(
                                          (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v),
                                      ),
                                    )
                                        .toList(),
                                    onChanged: (v) {
                                      setState(() => _pGender = v!);
                                      _saveAllData();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _hdrField('身長:', _pHeightCtrl, width: 50, isNum: true),
                                const Text('cm', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                const SizedBox(width: 8),
                                _hdrField('体重:', _pWeightCtrl, width: 50, isNum: true),
                                const Text('kg', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                                  child: Row(
                                    children: [
                                      const Text('BMI: ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                      Text(_calculateBmi(), style: const TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(color: Colors.purple.shade900.withOpacity(0.4), borderRadius: BorderRadius.circular(3)),
                                  child: Row(
                                    children: [
                                      const Text('手術時間: ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                      Text(_calculateTotalMinutes(_opStartTime, _opEndTime), style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(color: Colors.purple.shade900.withOpacity(0.4), borderRadius: BorderRadius.circular(3)),
                                  child: Row(
                                    children: [
                                      const Text('麻酔時間: ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                      Text(_calculateTotalMinutes(_anesthesiaStartTime, _anesthesiaEndTime), style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: _showHelpDialog,
                                  child: const Text('HELP', style: TextStyle(color: Colors.white60, fontSize: 8.5, decoration: TextDecoration.underline)),
                                ),
                                const SizedBox(width: 20),
                                const Text('v1.00', style: TextStyle(color: Colors.white60, fontSize: 8.5)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: _hdrField('病名:', _pDiseaseCtrl, width: null, hintText: '診断名を入力')),
                                const SizedBox(width: 12),
                                Expanded(child: _hdrField('術式:', _pOpeCtrl, width: null, hintText: '予定術式を入力')),
                                const SizedBox(width: 12),
                                _hdrField('担当医:', _anesthetistCtrl, width: 100, hintText: '麻酔 科医'),
                                const SizedBox(width: 12),
                                SizedBox(
                                  height: 24,
                                  child: ElevatedButton.icon(
                                    onPressed: _showPdfConfirmationDialog,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      elevation: 1,
                                    ),
                                    icon: const Icon(Icons.picture_as_pdf, size: 14),
                                    label: const Text('PDF出力', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ================= CORE INTERFACE =================
                Expanded(
                  child: Row(
                    children: [
                      // 💡 1. リアルタイムにサイズ計算が変わる右側コントロールパネル（COLUMN 3）と、
                      // 撮影対象エリア（COLUMN 1 & 2）を分けるため、ここに大きな Row を配置します。
                      Expanded(
                        flex: 7, // COLUMN 1 (flex 5) + COLUMN 2 (flex 2) = 計 7

                        child: Container(
                          color: Colors.white,
                          // 💡 PDF化した際に背景が透明になるのを防ぐため、白で固定します
                          child: Row(
                            children: [
                              // ---------------------------------------------------------------------
                              // COLUMN 1: タイムライン＆トレンド (撮影範囲内)
                              // ---------------------------------------------------------------------
                              Expanded(
                                flex: 5,
                                child: Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      // 💡 3. トグルボタンも撮影に含める場合はこのまま内部に、
                                      // もし「トグルボタンはPDFに入れたくない」場合は外に出す必要がありますが、
                                      // レイアウトの一体性を維持するため、このRowの中に綺麗に収めています。
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            '【 バイタルサイン・トレンド 】',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                          ),
                                          ToggleButtons(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            isSelected: [
                                              _selectedTimelineMinutes == 10,
                                              _selectedTimelineMinutes == 30,
                                              _selectedTimelineMinutes == 60,
                                              _selectedTimelineMinutes == 120,
                                              _selectedTimelineMinutes == 180,
                                            ],
                                            onPressed: (idx) {
                                              setState(
                                                    () => _selectedTimelineMinutes =
                                                idx == 0
                                                    ? 10
                                                    : idx == 1
                                                    ? 30
                                                    : idx == 2
                                                    ? 60
                                                    : idx == 3
                                                    ? 120
                                                    : 180,
                                              );
                                              _saveAllData();
                                            },
                                            constraints: const BoxConstraints(
                                              minHeight: 22,
                                              minWidth: 42,
                                            ),
                                            children: const [
                                              Text(
                                                '10分',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                              Text(
                                                '30分',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                              Text('1h', style: TextStyle(fontSize: 10.5,
                                              ),
                                              ),
                                              Text(
                                                '2h',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                              Text(
                                                '3h',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),

                                      Expanded(
                                        child: RepaintBoundary(
                                          // 👈 ここに移動（撮影範囲を限定）
                                          key: _chartCaptureKey,
                                          child: Container(
                                            color: Colors.white,
                                            // キャプチャの背景を白く固定
                                            child: Column(
                                              children: [
                                                // 📈 グラフエリア
                                                Expanded(
                                                  flex: 3,
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 90,
                                                        padding:
                                                        const EdgeInsets.only(
                                                          left: 6,
                                                          top: 10,
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                          mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                          children: [
                                                            _verticalLegendItem(
                                                              'sBP',
                                                              Colors.red,
                                                              '   ∨',
                                                            ),
                                                            _verticalLegendItem(
                                                              'dBP',
                                                              Colors.red,
                                                              '   ∧',
                                                            ),
                                                            _verticalLegendItem(
                                                              'HR',
                                                              Colors.green,
                                                              '   ■',
                                                            ),
                                                            _verticalLegendItem(
                                                              'SpO2',
                                                              Colors.cyan,
                                                              '   ●',
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Container(
                                                          padding:
                                                          const EdgeInsets.only(
                                                            right: 15,
                                                            top: 4,
                                                          ),
                                                          child: LineChart(
                                                            _mainChartData(),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),

                                                // ⏱️ タイムラインエリア
                                                Expanded(
                                                  flex: 4,
                                                  child: ListView(
                                                    shrinkWrap: true,
                                                    physics:
                                                    const ClampingScrollPhysics(),
                                                    children: [
                                                      // 🌟 イベント行などは誤消去を防ぐため、rowKeyを渡さずタップ対象外（または消したいなら他と同様にifで囲む）にするのが安全です
                                                      _buildTimelineRow(
                                                        label: 'イベント',
                                                        rowKey: 'event', // 👈 新しく追加した引数
                                                        maxMinutes: maxX,
                                                        children: _getEventPins(maxX, chartW),
                                                      ),
                                                      _buildTimelineRow(
                                                        label: '処置メモ/PV',
                                                        rowKey: 'remark', // 👈 新しく追加した引数
                                                        maxMinutes: maxX,
                                                        children: _getCombinedIvAndRemarkPins(maxX, chartW),
                                                      ),

                                                      // 🌟 ここから下の薬剤・輸液行を「if (!_hiddenRowKeys.contains('識別名'))」で囲んでいきます
                                                      if (_presetVisibleRows.contains('O2') && !_hiddenRowKeys.contains('O2'))
                                                        _buildTimelineRow(
                                                          label: 'O2 [L/min]',
                                                          rowKey: 'O2',
                                                          maxMinutes: maxX,
                                                          children: _getInfusionGraphics('O2', maxX, chartW, Colors.blue),
                                                          bgColor: Colors.blue.withOpacity(0.01),
                                                        ),

                                                      if ((_showN2oRow || _presetVisibleRows.contains('N2O')) && !_hiddenRowKeys.contains('N2O'))
                                                        _buildTimelineRow(
                                                          label: 'N2O [L/min]',
                                                          rowKey: 'N2O',
                                                          maxMinutes: maxX,
                                                          children: _getInfusionGraphics('N2O', maxX, chartW, Colors.lightBlue.shade300),
                                                          bgColor: Colors.lightBlue.withOpacity(0.01),
                                                        ),

                                                      if ((_showDexRow || _presetVisibleRows.contains('Dex')) && !_hiddenRowKeys.contains('Dex'))
                                                        _buildTimelineRow(
                                                          label: 'Dex [$_dexUnit]',
                                                          rowKey: 'Dex',
                                                          maxMinutes: maxX,
                                                          children: _getInfusionGraphics('Dex', maxX, chartW, Colors.orange),
                                                          bgColor: Colors.orange.withOpacity(0.01),
                                                        ),

                                                      if (_presetVisibleRows.contains('PropofolCiv') && !_hiddenRowKeys.contains('PropofolCiv'))
                                                        _buildTimelineRow(
                                                          label: 'Propofol civ [$_propofolInfUnit]',
                                                          rowKey: 'PropofolCiv',
                                                          maxMinutes: maxX,
                                                          children: _getInfusionGraphics('PropofolInf', maxX, chartW, Colors.purple),
                                                          bgColor: Colors.purple.withOpacity(0.01),
                                                        ),

                                                      if (_presetVisibleRows.contains('PropofolIv') && !_hiddenRowKeys.contains('PropofolIv'))
                                                        _buildTimelineRow(
                                                          label: 'Propofol iv [mg]',
                                                          rowKey: 'PropofolIv',
                                                          maxMinutes: maxX,
                                                          children: _getBolusPins('Propofol', maxX, chartW, Colors.deepPurple.shade400),
                                                          bgColor: Colors.purple.withOpacity(0.01),
                                                        ),

                                                      if (_presetVisibleRows.contains('Midazolam') && !_hiddenRowKeys.contains('Midazolam'))
                                                        _buildTimelineRow(
                                                          label: 'Midazolam iv [mg]',
                                                          rowKey: 'Midazolam',
                                                          maxMinutes: maxX,
                                                          children: _getBolusPins('Midazolam', maxX, chartW, Colors.teal),
                                                          bgColor: Colors.teal.withOpacity(0.01),
                                                        ),

                                                      if ((_showAcerioRow || _presetVisibleRows.contains('Acerio')) && !_hiddenRowKeys.contains('Acerio'))
                                                        _buildTimelineRow(
                                                          label: 'アセリオ [mg]',
                                                          rowKey: 'Acerio',
                                                          maxMinutes: maxX,
                                                          children: _getBolusPins('アセリオ', maxX, chartW, Colors.orange.shade700),
                                                          bgColor: Colors.orange.withOpacity(0.01),
                                                        ),

                                                      if ((_showRopionRow || _presetVisibleRows.contains('Ropion')) && !_hiddenRowKeys.contains('Ropion'))
                                                        _buildTimelineRow(
                                                          label: 'ロピオン [mg]',
                                                          rowKey: 'Ropion',
                                                          maxMinutes: maxX,
                                                          children: _getBolusPins('ロピオン', maxX, chartW, Colors.brown),
                                                          bgColor: Colors.brown.withOpacity(0.01),
                                                        ),

                                                      if (_presetVisibleRows.contains('LA') && !_hiddenRowKeys.contains('LA'))
                                                        _buildTimelineRow(
                                                          label: '$_selectedLaDrug [mL]',
                                                          rowKey: 'LA',
                                                          maxMinutes: maxX,
                                                          children: [
                                                            ..._getBolusPins(_selectedLaDrug, maxX, chartW, Colors.indigo.shade800),
                                                            ..._getBolusPins('LA', maxX, chartW, Colors.indigo.shade800),
                                                          ],
                                                          bgColor: Colors.indigo.withOpacity(0.01),
                                                        ),



                                                      // カスタム追加された薬剤たちのループ（実際に投与されたもの）
                                                      ...customDrugNames
                                                          .where((name) => name != _selectedFluidType && 
                                                                           !_hiddenRowKeys.contains('custom_$name')) 
                                                          .map((drugName) {
                                                        String customUnit = 'mg';
                                                        if (drugName == _customDrugNameController.text.trim()) {
                                                          customUnit = _selectedCustomUnit;
                                                        } else {
                                                          try { customUnit = _bolusLogs.firstWhere((b) => b.drugName == drugName).unit; } catch (_) {}
                                                        }
                                                        return _buildTimelineRow(
                                                          label: '$drugName [$customUnit]',
                                                          rowKey: 'custom_$drugName', // 🌟 動的なキーを割り振る
                                                          maxMinutes: maxX,
                                                          children: _getDynamicCustomBolusPins(drugName, maxX, chartW, Colors.grey.shade800),
                                                          bgColor: Colors.grey.shade100,
                                                        );
                                                      }),
                                                      // 🌟 if 条件文を外し、rowKeyも指定しないことで削除対象から完全に除外します
                                                      if (_presetVisibleRows.contains('Fluid'))
                                                        _buildTimelineRow(
                                                          label: '$_selectedFluidType [mL]',
                                                          rowKey: '', // 👈 rowKeyを空にする、または引数ごと削ることでタップしても非表示になりません
                                                          maxMinutes: maxX,
                                                          children: _getBolusPins(
                                                            _selectedFluidType,
                                                            maxX,
                                                            chartW,
                                                            Colors.teal.shade700,
                                                          ),
                                                          bgColor: Colors.teal.withOpacity(0.02),
                                                        ),
                                                    ], // ListView の終わり
                                                  ),
                                                ),
                                              ], // Column (グラフ+タイムライン) の終わり
                                            ),
                                          ),
                                        ), // RepaintBoundary, Container, Expanded の終わり
                                      ),
                                    ], // COLUMN 1 の Column の終わり
                                  ),
                                ),
                              ),
                              // Padding, Expanded (flex: 5) の終わり

                              // ---------------------------------------------------------------------
                              // COLUMN 2: 記録ログ一覧 (撮影範囲の外になりました)
                              // ---------------------------------------------------------------------
                              Expanded(
                                flex: 2,
                                child: Container(
                                  color: Colors.grey.shade50,
                                  padding: const EdgeInsets.all(6.0),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '【 記録一覧ログ 】',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Divider(height: 8),
                                      Expanded(
                                        child: ListView(
                                          children: [
                                            // ================= 👑 グループA：イベント・ルート確保・処置メモ =================
                                            const Text(
                                              '【 リマークス 】',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ...([
                                              ..._events.where((e) => e.time != null),
                                              ..._ivRecords,
                                              ..._remarkLogs,
                                            ].toList()
                                              ..sort((a, b) {
                                                final DateTime timeA = (a is AnesthesiaEvent)
                                                    ? a.time!
                                                    : (a is IvRecord ? a.time : (a as RemarkLog).time);
                                                final DateTime timeB = (b is AnesthesiaEvent)
                                                    ? b.time!
                                                    : (b is IvRecord ? b.time : (b as RemarkLog).time);
                                                return timeA.compareTo(timeB);
                                              })).map((item) {
                                              if (item is AnesthesiaEvent) {
                                                final e = item;
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 1.0,
                                                    horizontal: 2.0,
                                                  ),
                                                  child: InkWell(
                                                    onTap: () => _showEventTimeEditDialog(e),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(
                                                        vertical: 3.0,
                                                        horizontal: 4.0,
                                                      ),
                                                      child: Text(
                                                        '[${DateFormat('HH:mm').format(e.time!)}]  (${e.symbol}) ${e.name}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.blueGrey,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              } else if (item is IvRecord) {
                                                final iv = item;
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 1.0,
                                                    horizontal: 2.0,
                                                  ),
                                                  child: InkWell(
                                                    onTap: () => _showEditDeleteDialog(
                                                      title: 'ルート確保の修正',
                                                      initialTime: iv.time,
                                                      onDelete: () => setState(
                                                        () => _ivRecords.removeWhere((i) => i.id == iv.id),
                                                      ),
                                                      onUpdate: (nt, _) => setState(() {
                                                        int idx = _ivRecords.indexWhere((i) => i.id == iv.id);
                                                        if (idx != -1)
                                                          _ivRecords[idx] = IvRecord(
                                                            id: iv.id,
                                                            time: nt,
                                                            gauge: iv.gauge,
                                                            site: iv.site,
                                                            isSuccess: iv.isSuccess,
                                                          );
                                                      }),
                                                    ),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(
                                                        vertical: 3.0,
                                                        horizontal: 4.0,
                                                      ),
                                                      child: Text(
                                                        '[${DateFormat('HH:mm').format(iv.time)}]  PV ${iv.gauge}/${iv.site} ',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.green,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              } else if (item is RemarkLog) {
                                                final rm = item;
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 1.0,
                                                    horizontal: 2.0,
                                                  ),
                                                  child: InkWell(
                                                    onTap: () => _showEditDeleteDialog(
                                                      title: 'リマークス No.${rm.number} の修正',
                                                      initialTime: rm.time,
                                                      initialAmount: rm.text,
                                                      amountLabel: 'メモ内容',
                                                      onDelete: () => setState(() {
                                                        _remarkLogs.removeWhere((r) => r.id == rm.id);
                                                        for (int i = 0; i < _remarkLogs.length; i++) {
                                                          _remarkLogs[i].number = i + 1;
                                                        }
                                                      }),
                                                      onUpdate: (nt, na) => setState(() {
                                                        int idx = _remarkLogs.indexWhere((r) => r.id == rm.id);
                                                        if (idx != -1) {
                                                          _remarkLogs[idx] = RemarkLog(
                                                            id: rm.id,
                                                            time: nt,
                                                            text: na ?? rm.text,
                                                            number: rm.number,
                                                          );
                                                        }
                                                      }),
                                                    ),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(
                                                        vertical: 3.0,
                                                        horizontal: 4.0,
                                                      ),
                                                      child: Text(
                                                        '[${DateFormat('HH:mm').format(rm.time)}]  No.${rm.number}: ${rm.text}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.orange.shade800,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            }),

                                            const Divider(
                                              height: 16,
                                              thickness: 1,
                                            ),

                                            // ================= 💉 グループB：麻酔・呼吸・薬剤投与（持続＋iv） =================
                                            const Text(
                                              '【 薬剤履歴 】',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),

                                            ..._infusionMap.entries.expand(
                                                  (entry) => entry.value.map((pt) {
                                                String unit = '';
                                                String displayName = entry.key;

                                                if (entry.key ==
                                                    "PropofolInf") {displayName = "Propofol civ";
                                                unit = _propofolInfUnit;
                                                } else if (entry.key == "Dex") { // 👈 追加
                                                  displayName = "Dex";
                                                  unit = _dexUnit;
                                                } else if (entry.key == "O2" ||
                                                    entry.key == "N2O") {
                                                  unit = "L/min";
                                                }

                                                String logText = pt.isStop
                                                    ? '[${DateFormat('HH:mm').format(pt.time)}]  $displayName: OFF'
                                                    : '[${DateFormat('HH:mm').format(pt.time)}]  $displayName: ${pt.val} $unit';

                                                return Padding(
                                                  padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 1.0,
                                                    horizontal: 2.0,
                                                  ),
                                                  child: InkWell(
                                                    onTap: () => _showEditDeleteDialog(
                                                      title: '$displayName の修正',
                                                      initialTime: pt.time,
                                                      initialAmount: pt.isStop
                                                          ? null
                                                          : pt.val,
                                                      amountLabel: '設定値',
                                                      onDelete: () => setState(
                                                            () =>
                                                            _infusionMap[entry
                                                                .key]!
                                                                .removeWhere(
                                                                  (p) =>
                                                              p.id ==
                                                                  pt.id,
                                                            ),
                                                      ),
                                                      onUpdate: (nt, na) => setState(() {
                                                        int idx =
                                                        _infusionMap[entry
                                                            .key]!
                                                            .indexWhere(
                                                              (p) =>
                                                          p.id ==
                                                              pt.id,
                                                        );
                                                        if (idx != -1) {
                                                          _infusionMap[entry
                                                              .key]![idx]
                                                              .time =
                                                              nt;
                                                          if (na != null)
                                                            _infusionMap[entry
                                                                .key]![idx] =
                                                                InfusionPoint(
                                                                  id: pt.id,
                                                                  time: nt,
                                                                  val: na,
                                                                  isStop:
                                                                  pt.isStop,
                                                                );
                                                          _infusionMap[entry
                                                              .key]!
                                                              .sort(
                                                                (a, b) => a.time
                                                                .compareTo(
                                                              b.time,
                                                            ),
                                                          );
                                                        }
                                                      }),
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 3.0,
                                                        horizontal: 4.0,
                                                      ),
                                                      child: Text(
                                                        logText,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                          FontWeight.bold,
                                                          color: pt.isStop
                                                              ? Colors
                                                              .red
                                                              .shade700
                                                              : Colors.indigo,
                                                          letterSpacing: 0.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),

                                            ..._bolusLogs.map((b) {
                                              String displayName = b.drugName;
                                              String displayAmount = b.amount;
                                              String unit = b.unit;

                                              if (b.drugName == 'LA') {
                                                displayName = _selectedLaDrug;
                                                unit = 'mL';
                                                if (b.amount.contains(' ')) {
                                                  displayAmount = b.amount
                                                      .split(' ')
                                                      .last;
                                                }
                                              } else if (b.drugName ==
                                                  _customDrugNameController.text
                                                      .trim()) {
                                                unit = _selectedCustomUnit;
                                              }
                                              return Padding(
                                                padding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 1.0,
                                                  horizontal: 2.0,
                                                ),
                                                child: InkWell(
                                                  onTap: () {
                                                    _showEditDeleteDialog(
                                                      title: '$displayName の修正',
                                                      initialTime: b.time,
                                                      initialAmount:
                                                      displayAmount,
                                                      amountLabel: '投与量',
                                                      onDelete: () => setState(
                                                            () => _bolusLogs
                                                            .removeWhere(
                                                              (bl) =>
                                                          bl.id == b.id,
                                                        ),
                                                      ),
                                                      onUpdate: (nt, na) =>
                                                          setState(() {
                                                            int idx = _bolusLogs
                                                                .indexWhere(
                                                                  (bl) =>
                                                              bl.id ==
                                                                  b.id,
                                                            );
                                                            if (idx != -1) {
                                                              String
                                                              finalAmount =
                                                                  na ??
                                                                      displayAmount;
                                                              if (b.drugName ==
                                                                  'LA') {
                                                                String prefix =
                                                                    b.amount
                                                                        .split(
                                                                      ' ',
                                                                    )
                                                                        .first;
                                                                finalAmount =
                                                                '$prefix $finalAmount';
                                                              }
                                                              _bolusLogs[idx]
                                                                  .time =
                                                                  nt;
                                                              _bolusLogs[idx]
                                                                  .amount =
                                                                  finalAmount;
                                                            }
                                                          }),
                                                    );
                                                  },
                                                  child: Padding(
                                                    padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 3.0,
                                                      horizontal: 4.0,
                                                    ),
                                                    child: Text(
                                                      '[${DateFormat('HH:mm').format(b.time)}]  $displayName: $displayAmount $unit',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                        color:
                                                        Colors.deepPurple,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),

                                            const Divider(
                                              height: 16,
                                              thickness: 1,
                                            ),

                                            // ================= 📊 グループC：バイタルサイン履歴（最下部） =================
                                            const Text(
                                              '【 バイタルサイン履歴 】',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ..._records.map(
                                                  (r) => Padding(
                                                padding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 1.0,
                                                  horizontal: 2.0,
                                                ),
                                                child: InkWell(
                                                  onTap: () =>
                                                      _showVitalEditDialog(r),
                                                  child: Padding(
                                                    padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 3.0,
                                                      horizontal: 4.0,
                                                    ),
                                                    child: Text(
                                                      '[${DateFormat('HH:mm').format(r.dateTime)}]  ${r.sbp.toInt()}/${r.dbp.toInt()}  (HR:${r.hr.toInt()})  SpO2:${r.spo2.toInt()}%',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                        color: Colors.red,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const Divider(
                                              height: 16,
                                              thickness: 1,
                                            ),

                                            // ================= 📋 グループD：保険算定用サマリー（最下部に追加） =================
                                            const Text(
                                              '【 保険算定用データ 】',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Builder(
                                              builder: (context) {
                                                final o2Stats =
                                                _calculateO2Stats();
                                                return Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(
                                                    6.0,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.teal.shade50,
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                      4,
                                                    ),
                                                    border: Border.all(
                                                      color:
                                                      Colors.teal.shade100,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                    children: [
                                                      Text(
                                                        '酸素投与総時間 : ${o2Stats['time']}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                          FontWeight.bold,
                                                          color: Colors.teal,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '酸素総投与量   : ${o2Stats['amount']}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                          FontWeight.bold,
                                                          color: Colors.teal,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ここで RepaintBoundary とその中の Container, Row などを綺麗に閉じます

                      // ---------------------------------------------------------------------
                      // COLUMN 3: 右側コントロールパネル (★ここは撮影範囲の外側です)
                      // ---------------------------------------------------------------------
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: Colors.grey.shade100,
                          padding: const EdgeInsets.all(6.0),
                          child: Column(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 左半分: イベントパネル
                                    Expanded(
                                      flex: 4,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: ListView(
                                                children: _events.map((e) {
                                                  bool settled = e.time != null;
                                                  return SizedBox(
                                                    height: 33.5,
                                                    child: Padding(
                                                      padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 1.5,
                                                      ),
                                                      child: InkWell(
                                                        onTap: () {
                                                          if (settled) {
                                                            _showEventTimeEditDialog(
                                                              e,
                                                            );
                                                          } else {
                                                            setState(() {
                                                              _initStartTimeIfNeeded();
                                                              final now =
                                                              DateTime.now();
                                                              e.time = now;

                                                              if (e.name ==
                                                                  '麻酔開始') {
                                                                _anesthesiaStartTime =
                                                                    now;
                                                              } else if (e
                                                                  .name ==
                                                                  '麻酔終了') {
                                                                _anesthesiaEndTime =
                                                                    now;
                                                              } else if (e
                                                                  .name ==
                                                                  '手術開始') {
                                                                _opStartTime =
                                                                    now;
                                                              } else if (e
                                                                  .name ==
                                                                  '手術終了') {
                                                                _opEndTime =
                                                                    now;
                                                              }
                                                            });
                                                            _saveAllData();
                                                          }
                                                        },
                                                        child: Container(
                                                          height: 26,
                                                          padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: settled
                                                                ? Colors
                                                                .grey
                                                                .shade300
                                                                : e.activeColor
                                                                .withOpacity(
                                                              0.12,
                                                            ),
                                                            border: Border.all(
                                                              color: settled
                                                                  ? Colors
                                                                  .grey
                                                                  .shade400
                                                                  : e.activeColor
                                                                  .withOpacity(
                                                                0.8,
                                                              ),
                                                              width: 1.1,
                                                            ),
                                                            borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                            children: [
                                                              Text(
                                                                '${e.symbol} ${e.name}',
                                                                style: const TextStyle(
                                                                  fontSize:
                                                                  10.0,
                                                                  fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                                ),
                                                              ),
                                                              if (settled)
                                                                Text(
                                                                  DateFormat(
                                                                    'HH:mm',
                                                                  ).format(
                                                                    e.time!,
                                                                  ),
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                    10.0,
                                                                    color: Colors
                                                                        .blue
                                                                        .shade900,
                                                                    fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),

                                    // 右半分: ルート確保 / 処置メモ
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                              borderRadius:
                                              BorderRadius.circular(4),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    DropdownButton<String>(
                                                      value: _selectedIvGauge,
                                                      isDense: true,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                      ),
                                                      items: <String>{'20G', '22G', '24G', _selectedIvGauge}
                                                          .map(
                                                            (v) =>
                                                            DropdownMenuItem(
                                                              value: v,
                                                              child: Text(v),
                                                            ),
                                                      )
                                                          .toList(),
                                                      onChanged: (v) {
                                                        setState(() => _selectedIvGauge = v!);
                                                        _saveAllData();
                                                      },
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: DropdownButton<String>(
                                                        value: _selectedIvSite,
                                                        isDense: true,
                                                        isExpanded: true,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        items: <String>{
                                                          '左前腕', '右前腕', '左手背', '右手背', '左肘', '右肘',
                                                          if (_selectedIvSite != '自由入力...') _selectedIvSite,
                                                          '自由入力...',
                                                        }.map((v) => DropdownMenuItem(
                                                          value: v,
                                                          child: Text(
                                                            v,
                                                            style: TextStyle(
                                                              color: v == '自由入力...' ? Colors.blue.shade700 : Colors.black,
                                                            ),
                                                          ),
                                                        )).toList(),
                                                        onChanged: (v) {
                                                          if (v == '自由入力...') {
                                                            // 🌟「自由入力...」がタップされたら専用ポップアップを開く
                                                            _showCustomIvSiteDialog();
                                                          } else {
                                                            setState(() => _selectedIvSite = v!);
                                                            _saveAllData();
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Text(
                                                      '輸液選択：',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: DropdownButton<String>(
                                                        value: _selectedFluidType,
                                                        isDense: true,
                                                        isExpanded: true,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        items: <String>{
                                                          'フィジオ140',
                                                          'ラクテック注',
                                                          'ソルデム3A',
                                                          '生理食塩水',
                                                          'ソリタT1',
                                                          'ソリタT3',
                                                          if (_selectedFluidType != '自由入力...') _selectedFluidType,
                                                          '自由入力...',
                                                        }.map((v) => DropdownMenuItem(
                                                          value: v,
                                                          child: Text(v, style: TextStyle(color: v == '自由入力...' ? Colors.blue.shade700 : Colors.black)),
                                                        )).toList(),
                                                        onChanged: (v) {
                                                          if (v == '自由入力...') {
                                                            // 🌟「自由入力...」がタップされたらポップアップを開く
                                                            _showCustomFluidDialog();
                                                          } else {
                                                            setState(() => _selectedFluidType = v!);
                                                            _saveAllData();
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 5),
                                                SizedBox(
                                                  width: double.infinity,
                                                  height: 28,
                                                  child: ElevatedButton(
                                                    onPressed: () {
                                                      setState(() {
                                                        _initStartTimeIfNeeded();
                                                        DateTime now =
                                                        DateTime.now();
                                                        _ivRecords.add(
                                                          IvRecord(
                                                            id: now.toString(),
                                                            time: now,
                                                            gauge:
                                                            _selectedIvGauge,
                                                            site:
                                                            _selectedIvSite,
                                                            isSuccess: true,
                                                          ),
                                                        );
                                                        _bolusLogs.add(
                                                          BolusLog(
                                                            id: 'fluid_${now.toString()}',
                                                            time: now,
                                                            drugName:
                                                            _selectedFluidType,
                                                            amount: '0',
                                                            unit: 'mL',
                                                          ),
                                                        );
                                                      });
                                                      _saveAllData();
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                      Colors.teal.shade700,
                                                      foregroundColor:
                                                      Colors.white,
                                                      padding: EdgeInsets.zero,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'ルート確保 ＆ 輸液開始',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: Colors.grey.shade300,
                                                ),
                                                borderRadius:
                                                BorderRadius.circular(4),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      controller:
                                                      _remarkController,
                                                      maxLines: null,
                                                      expands: true,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                      decoration:
                                                      const InputDecoration(
                                                        hintText: '入力...',
                                                        contentPadding:
                                                        EdgeInsets.all(
                                                          4,
                                                        ),
                                                        border:
                                                        OutlineInputBorder(),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  ElevatedButton(
                                                    onPressed: _addRemark,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                      Colors.orange,
                                                      foregroundColor:
                                                      Colors.white,
                                                      minimumSize: const Size(
                                                        double.infinity,
                                                        32,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'リマークス',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 4),

                              // 薬剤投与パネル
                              Expanded(
                                flex: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: ListView(
                                    children: [
                                      if (_presetVisiblePanelRows.contains('O2'))
                                      _alignedDrugRow(
                                        label: 'O2 流量 :',
                                        child: TextField(
                                          controller: _o2Controller,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'L/min',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_o2Controller.text.isEmpty) return;
                                                  _addInfusionPoint('O2', _o2Controller.text);
                                                  _o2Controller.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () => _stopInfusionPoint('O2'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('OFF', style: TextStyle(fontSize: 9)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('N2O'))
                                      _alignedDrugRow(
                                        label: 'N2O 流量 :',
                                        child: TextField(
                                          controller: _n2oController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'L/min',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_n2oController.text.isEmpty) return;
                                                  _addInfusionPoint('N2O', _n2oController.text);
                                                  _n2oController.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.lightBlue.shade300,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () => _stopInfusionPoint('N2O'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('OFF', style: TextStyle(fontSize: 9)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('Dex'))
                                      _alignedDrugRow(
                                        label: 'Dex:',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: _dexController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                style: const TextStyle(fontSize: 11),
                                                decoration: const InputDecoration(
                                                  hintText: '速度',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            DropdownButton<String>(
                                              value: _dexUnit,
                                              isDense: true,
                                              items: <String>{'μg/kg/h', 'mL/h', _dexUnit}
                                                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 9))))
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() => _dexUnit = v!);
                                                _saveAllData();
                                              },
                                            ),
                                          ],
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_dexController.text.isEmpty) return;
                                                  _addInfusionPoint('Dex', _dexController.text);
                                                  _dexController.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.orange,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () => _stopInfusionPoint('Dex'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('OFF', style: TextStyle(fontSize: 9)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('PropofolCiv'))
                                      _alignedDrugRow(
                                        label: 'Propofol civ :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: _propofolInfController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                style: const TextStyle(fontSize: 11),
                                                decoration: const InputDecoration(
                                                  hintText: '速度',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            DropdownButton<String>(
                                              value: _propofolInfUnit,
                                              isDense: true,
                                              items: <String>{'mg/kg/h', 'mL/h', 'μg/mL', _propofolInfUnit}
                                                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 9))))
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() => _propofolInfUnit = v!);
                                                _saveAllData();
                                              },
                                            ),
                                          ],
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_propofolInfController.text.isEmpty) return;
                                                  _addInfusionPoint('PropofolInf', _propofolInfController.text);
                                                  _propofolInfController.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.purple,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () => _stopInfusionPoint('PropofolInf'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                                child: const Text('OFF', style: TextStyle(fontSize: 9)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('PropofolIv'))
                                      _alignedDrugRow(
                                        label: 'Propofol iv :',
                                        child: TextField(
                                          controller: _propofolBolusController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_propofolBolusController.text.isEmpty) return;
                                            _addBolus('Propofol', _propofolBolusController.text, 'mg');
                                            _propofolBolusController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple.shade400,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('Midazolam'))
                                      _alignedDrugRow(
                                        label: 'Midazolam :',
                                        child: TextField(
                                          controller: _midazolamController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_midazolamController.text.isEmpty) return;
                                            _addBolus('Midazolam', _midazolamController.text, 'mg');
                                            _midazolamController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('Acerio'))
                                      _alignedDrugRow(
                                        label: 'アセリオ :',
                                        child: TextField(
                                          controller: _acerioController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_acerioController.text.isEmpty) return;
                                            _addBolus('アセリオ', _acerioController.text, 'mg');
                                            _acerioController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange.shade700,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('Ropion'))
                                      _alignedDrugRow(
                                        label: 'ロピオン :',
                                        child: TextField(
                                          controller: _ropionController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_ropionController.text.isEmpty) return;
                                            _addBolus('ロピオン', _ropionController.text, 'mg');
                                            _ropionController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.brown,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('LA'))
                                      _alignedDrugRow(
                                        label: '局所麻酔 :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButton<String>(
                                                value: _selectedLaDrug,
                                                isDense: true,
                                                isExpanded: true,
                                                style: const TextStyle(fontSize: 10, color: Colors.black),
                                                items: <String>{
                                                  'オーラ注', 'セプトカイン', 'スキャンドネスト', 'シタネスト', 'エピリド', 'キシロカイン',
                                                  if (_selectedLaDrug != '自由入力...') _selectedLaDrug,
                                                  '自由入力...',
                                                }.map((v) => DropdownMenuItem(
                                                  value: v,
                                                  child: Text(v, style: TextStyle(color: v == '自由入力...' ? Colors.blue.shade700 : Colors.black)),
                                                )).toList(),
                                                onChanged: (v) {
                                                  if (v == '自由入力...') {
                                                    _showCustomLaDrugDialog();
                                                  } else {
                                                    setState(() => _selectedLaDrug = v!);
                                                    _saveAllData();
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              flex: 1,
                                              child: TextField(
                                                controller: _laMlController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                style: const TextStyle(fontSize: 11),
                                                decoration: const InputDecoration(
                                                  hintText: 'mL',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_laMlController.text.isEmpty) return;
                                            _addBolus(_selectedLaDrug, _laMlController.text, 'mL');
                                            _laMlController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.indigo.shade800,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      if (_presetVisiblePanelRows.contains('Fluid'))
                                      _alignedDrugRow(
                                        label: '輸液合計量 :',
                                        child: TextField(
                                          controller: _fluidController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mL',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_fluidController.text.isEmpty) return;
                                            _addBolus(_selectedFluidType, _fluidController.text, 'mL');
                                            _fluidController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal.shade700,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      const Divider(),
                                      // カスタム薬剤の行
                                      _alignedDrugRow(
                                        label: '自由追加薬 :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: _customDrugNameController,
                                                style: const TextStyle(fontSize: 10),
                                                decoration: const InputDecoration(
                                                  hintText: '薬剤名',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller: _customDrugAmountController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                style: const TextStyle(fontSize: 11),
                                                decoration: const InputDecoration(
                                                  hintText: '量',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            DropdownButton<String>(
                                              value: _selectedCustomUnit,
                                              isDense: true,
                                              items: <String>{'mg', 'μg', 'mL', '管', _selectedCustomUnit}
                                                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 9))))
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() => _selectedCustomUnit = v!);
                                                _saveAllData();
                                              },
                                            ),
                                          ],
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_customDrugNameController.text.isEmpty || _customDrugAmountController.text.isEmpty) return;
                                            _addBolus(_customDrugNameController.text.trim(), _customDrugAmountController.text.trim(), _selectedCustomUnit);
                                            _customDrugAmountController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.grey.shade800,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: const Text('投与', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ),

                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 20,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _hiddenRowKeys.clear();
                                            });
                                            _saveAllData();
                                          },
                                          icon: Icon(Icons.refresh, size: 13, color: Colors.teal.shade700),
                                          label: Text(
                                            '非表示にした行をすべて再表示',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade800,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Colors.teal.shade300, width: 0.8),
                                            backgroundColor: Colors.teal.shade50.withOpacity(0.4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 5),
                              ElevatedButton.icon(
                                onPressed: _showCustomKeypadDialog,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 62),
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                icon: const Icon(Icons.edit_note, size: 20),
                                label: const Text(
                                  'バイタル入力',
                                  style: TextStyle(
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ], // 一番外側の Row を閉じる
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

//flutter run -d web-server --web-hostname=10.35.25.51 --web-port=8080
