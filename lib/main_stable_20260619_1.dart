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

void main() {
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
      ),
      home: const MainRecordPage(),
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
  final TextEditingController _pIdCtrl = TextEditingController(text: '123456');
  final TextEditingController _pNameCtrl = TextEditingController(text: '麻酔 太郎');
  final TextEditingController _pAgeCtrl = TextEditingController(text: '35');
  final TextEditingController _pHeightCtrl = TextEditingController(text: '170');
  final TextEditingController _pWeightCtrl = TextEditingController(text: '65');
  final TextEditingController _pDiseaseCtrl = TextEditingController(
    text: '右下顎第三大臼歯完全埋伏智歯・含歯性嚢胞疑い',
  );
  final TextEditingController _pOpeCtrl = TextEditingController(
    text: '静脈内鎮静法下・下顎水平埋伏智歯抜歯術及び嚢胞摘出術',
  );
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
  };
  final List<BolusLog> _bolusLogs = [];

  bool _showN2oRow = false;
  bool _showAcerioRow = false;
  bool _showRopionRow = false;
  bool _isPrinting = false; // 👈 追加：PDF出力中ならtrueにするフラグ
  bool _hideEmptyTimelineRows = false; // 🌟 ここを追加！：未入力の行を隠すかどうかのフラグ

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
  final TextEditingController _propofolInfController = TextEditingController();

  String _propofolInfUnit = 'mg/kg/h';
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

  Future<void> _generatePdf() async {
    try {
      print('--- 【ログ】A4縦向き・3段コンパクトPDF生成スタート ---');

      // 💡 1. 描画の確定を少し待ってから、画面から「グラフ＋タイムライン＋ログ」をパシャッと撮影
      await Future.delayed(const Duration(milliseconds: 200));
      final Uint8List? capturedImageBytes = await _captureChartImage(context);

      final pw.Font fontRegular = await PdfGoogleFonts.notoSansJPRegular();
      final pw.Font fontBold = await PdfGoogleFonts.notoSansJPBold();
      final pdf = pw.Document();
      final bmiString = _calculateBmi();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4, // 👈 .landscape を削って「縦向き」に固定
          margin: const pw.EdgeInsets.all(25),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // =========================================================================
                // タイトルヘッダー（★しっかり残しています）
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
                      // ✨ 【1段目】患者情報（ラベル削除・フォント打ち分け版）
                      pw.Row(
                        children: [
                          // 患者ID (幅85)
                          pw.SizedBox(
                            width: 90,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '患者ID: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: _pIdCtrl.text.isEmpty
                                        ? "未入力"
                                        : _pIdCtrl.text,
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 氏名 (幅130)
                          pw.SizedBox(
                            width: 130,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '氏名: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text:
                                        '${_pNameCtrl.text.isEmpty ? "未入力" : _pNameCtrl.text} ',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 年齢 (幅45)
                          pw.SizedBox(
                            width: 60,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '年齢: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: '${_pAgeCtrl.text}歳',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 性別 (幅45)
                          pw.SizedBox(
                            width: 45,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '性別: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: _pGender,
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 身長 (幅60)
                          pw.SizedBox(
                            width: 60,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '身長: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: '${_pHeightCtrl.text}cm',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 体重 (幅60)
                          pw.SizedBox(
                            width: 60,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '体重: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: '${_pWeightCtrl.text}kg',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // BMI
                          pw.RichText(
                            text: pw.TextSpan(
                              children: [
                                pw.TextSpan(
                                  text: 'BMI: ',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    fontSize: 9,
                                  ),
                                ),
                                pw.TextSpan(
                                  text: bmiString,
                                  style: pw.TextStyle(fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey300),
                      pw.SizedBox(height: 4),

                      // ✨ 【2段目】病名
                      pw.Row(
                        children: [
                          pw.Text(
                            '術前診断: ',
                            style: pw.TextStyle(font: fontBold, fontSize: 9),
                          ),
                          pw.Expanded(
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(
                                _pDiseaseCtrl.text,
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      // ✨ 【3段目】術式
                      pw.Row(
                        children: [
                          pw.Text(
                            '予定術式: ',
                            style: pw.TextStyle(font: fontBold, fontSize: 9),
                          ),
                          pw.Expanded(
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(
                                _pOpeCtrl.text,
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey300),
                      pw.SizedBox(height: 4),

                      // ✨ 【4段目】管理情報（ラベル削除・フォント打ち分け版）
                      pw.Row(
                        children: [
                          // 担当医
                          pw.SizedBox(
                            width: 160,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '麻酔担当医: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: _anesthetistCtrl.text,
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 手術時間
                          pw.SizedBox(
                            width: 100,
                            child: pw.RichText(
                              text: pw.TextSpan(
                                children: [
                                  pw.TextSpan(
                                    text: '手術時間: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: _calculateTotalMinutes(
                                      _opStartTime,
                                      _opEndTime,
                                    ),
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
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
                                  pw.TextSpan(
                                    text: '麻酔時間: ',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 9,
                                    ),
                                  ),
                                  pw.TextSpan(
                                    text: _calculateTotalMinutes(
                                      _anesthesiaStartTime,
                                      _anesthesiaEndTime,
                                    ),
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
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
                // 【下部レイアウト】差し替えエリア
                // 💡 左側にトレンド画像、右側にイベント・処置ログを配置します
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
                          // 👈 ここをRowに変更して左右に分割します
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // --- 左側：トレンドキャプチャ画像 (全体の7割) ---
                            pw.Expanded(
                              flex: 7,
                              child: pw.Container(
                                padding: const pw.EdgeInsets.all(5), // 内側に少し余白を作る
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
                                    pw.SizedBox(height: 5), // 見出しと画像の間のすきま
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
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '【イベント・処置・メモ】',
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 9,
                                      ),
                                    ),
                                    pw.Divider(thickness: 0.5),
                                    // 💡 ここにログのテキストを抽出して表示するロジックを次に追加します
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
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          "download",
          '麻酔情報_${_pIdCtrl.text}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        )
        ..click();
      html.Url.revokeObjectUrl(url);

      print('--- 【ログ】横向き3段PDF処理が正常終了しました ---');
    } catch (e) {
      print('--- 【ログ】横向き3段PDF生成エラー: $e ---');
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
          content: 'PV ${iv.gauge}/${iv.site} -> ${iv.isSuccess ? "成功" : "失敗"}',
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

  void _addIvRecord(bool isSuccess) {
    setState(() {
      _initStartTimeIfNeeded();
      _ivRecords.add(
        IvRecord(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          gauge: _selectedIvGauge,
          site: _selectedIvSite,
          isSuccess: isSuccess,
        ),
      );
    });
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
    });
  }

  void _addInfusionPoint(String key, String val) {
    if (val.trim().isEmpty) return;
    setState(() {
      _initStartTimeIfNeeded();
      if (key == 'N2O') _showN2oRow = true;
      _infusionMap[key]!.add(
        InfusionPoint(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          val: val.trim(),
        ),
      );
      _infusionMap[key]!.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  void _stopInfusionPoint(String key) {
    setState(() {
      _initStartTimeIfNeeded();
      if (key == 'N2O') _showN2oRow = true;
      _infusionMap[key]!.add(
        InfusionPoint(
          id: DateTime.now().toString(),
          time: DateTime.now(),
          val: 'OFF',
          isStop: true,
        ),
      );
      _infusionMap[key]!.sort((a, b) => a.time.compareTo(b.time));
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
    required double maxMinutes,
    required List<Widget> children,
    Color? bgColor,
    double height = 25,
  }) {
    // 💡 heightを 21 ➔ 25 に拡大(4pxプラス)
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 0.8), // 💡 行間もわずかに調整
      child: Row(
        children: [
          Container(
            width: 122, // 💡 110px + Y軸ラベルの32px分を足して、グラフのグリッド始点と完全同期
            padding: const EdgeInsets.only(left: 4),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ), // 💡 文字を 9.0 ➔ 10.5 に拡大
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 15), // 💡 グラフの右側余白と完全同期
              decoration: BoxDecoration(
                color: bgColor ?? Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                // 💡 これにより、中のテキスト表示が上下中央に揃います
                children: [
                  //Positioned(left: 0, right: 0, top: height / 2 - 0.5, child: Container(height: 1, color: Colors.grey.withOpacity(0.04))),
                  ...children,
                ],
              ), // 💡 背景の線を消して、プロットされたピン（数字など）だけを描画するようにしました
            ),
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
                title: '処置メモ No.${rm.number} の修正',
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
                title: '${key == "PropofolInf" ? "Propofol civ" : key} 設定の修正',
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
    String spo2 = '98';
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
                  ? TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 0,
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
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
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 0,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
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

            final fixedDrugs = ['Propofol', 'Midazolam', 'LA', 'アセリオ', 'ロピオン'];
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
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.account_box,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          _hdrField('ID:', _pIdCtrl, width: 65),
                          const SizedBox(width: 10),
                          _hdrField('氏名:', _pNameCtrl, width: 100),
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
                              onChanged: (v) => setState(() => _pGender = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _hdrField(
                            '身長:',
                            _pHeightCtrl,
                            width: 45,
                            isNum: true,
                          ),
                          const Text(
                            'cm',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _hdrField(
                            '体重:',
                            _pWeightCtrl,
                            width: 45,
                            isNum: true,
                          ),
                          const Text(
                            'kg',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'BMI: ',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  _calculateBmi(),
                                  style: const TextStyle(
                                    color: Colors.yellow,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 💡 【ここから追加！】麻酔時間と手術時間の表示枠
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade900.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '手術時間: ',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                                // ※ _opStartTime と _opEndTime はご自身の変数名に合わせてください
                                Text(
                                  _calculateTotalMinutes(
                                    _opStartTime,
                                    _opEndTime,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade900.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '麻酔時間: ',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                                // ※ _anesthesiaStartTime と _anesthesiaEndTime はご自身の変数名に合わせてください
                                Text(
                                  _calculateTotalMinutes(
                                    _anesthesiaStartTime,
                                    _anesthesiaEndTime,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // 👈 これを入れることで、ボタンを一番右端にシュッと押し寄せます！

                          // 💡 PDF出力ボタンのすぐ左側に、他とお揃いのデザインで配置
                          _hdrField('担当医:', _anesthetistCtrl, width: 100),

                          const SizedBox(width: 12),
                          // 💡 ボタンとの間に綺麗な間隔を作ります

                          // PDF出力ボタン
                          SizedBox(
                            height: 24, // 👈 縦幅を24px（小さめ）にカチッと固定します
                            child: ElevatedButton.icon(
                              onPressed: _generatePdf,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                // 💡 上下余白を0にしてスリムに
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                elevation: 1,
                              ),
                              icon: const Icon(Icons.picture_as_pdf, size: 14),
                              // アイコンも少し小さく
                              label: const Text(
                                'PDF出力',
                                style: TextStyle(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.bold,
                                ), // 文字もヘッダーに合わせる
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _hdrField('病名:', _pDiseaseCtrl, width: null),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _hdrField('術式:', _pOpeCtrl, width: null),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ================= CORE INTERFACE =================
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
                                            onPressed: (idx) => setState(
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
                                            ),
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
                                                      _buildTimelineRow(
                                                        label: 'イベント',
                                                        maxMinutes: maxX,
                                                        children: _getEventPins(
                                                          maxX,
                                                          chartW,
                                                        ),
                                                      ),
                                                      _buildTimelineRow(
                                                        label: '処置メモ/PV',
                                                        maxMinutes: maxX,
                                                        children:
                                                            _getCombinedIvAndRemarkPins(
                                                              maxX,
                                                              chartW,
                                                            ),
                                                      ),
                                                      _buildTimelineRow(
                                                        label: 'O2 [L/min]',
                                                        maxMinutes: maxX,
                                                        children:
                                                            _getInfusionGraphics(
                                                              'O2',
                                                              maxX,
                                                              chartW,
                                                              Colors.blue,
                                                            ),
                                                        bgColor: Colors.blue
                                                            .withOpacity(0.01),
                                                      ),
                                                      if (_showN2oRow)
                                                        _buildTimelineRow(
                                                          label: 'N2O [L/min]',
                                                          maxMinutes: maxX,
                                                          children:
                                                              _getInfusionGraphics(
                                                                'N2O',
                                                                maxX,
                                                                chartW,
                                                                Colors
                                                                    .lightBlue
                                                                    .shade300,
                                                              ),
                                                          bgColor: Colors
                                                              .lightBlue
                                                              .withOpacity(
                                                                0.01,
                                                              ),
                                                        ),
                                                      _buildTimelineRow(
                                                        label:
                                                            'Propofol civ [$_propofolInfUnit]',
                                                        maxMinutes: maxX,
                                                        children:
                                                            _getInfusionGraphics(
                                                              'PropofolInf',
                                                              maxX,
                                                              chartW,
                                                              Colors.purple,
                                                            ),
                                                        bgColor: Colors.purple
                                                            .withOpacity(0.01),
                                                      ),
                                                      _buildTimelineRow(
                                                        label:
                                                            'Propofol iv [mg]',
                                                        maxMinutes: maxX,
                                                        children: _getBolusPins(
                                                          'Propofol',
                                                          maxX,
                                                          chartW,
                                                          Colors
                                                              .deepPurple
                                                              .shade400,
                                                        ),
                                                        bgColor: Colors.purple
                                                            .withOpacity(0.01),
                                                      ),
                                                      _buildTimelineRow(
                                                        label:
                                                            'Midazolam iv [mg]',
                                                        maxMinutes: maxX,
                                                        children: _getBolusPins(
                                                          'Midazolam',
                                                          maxX,
                                                          chartW,
                                                          Colors.teal,
                                                        ),
                                                        bgColor: Colors.teal
                                                            .withOpacity(0.01),
                                                      ),
                                                      if (_showAcerioRow)
                                                        _buildTimelineRow(
                                                          label: 'アセリオ [mg]',
                                                          maxMinutes: maxX,
                                                          children:
                                                              _getBolusPins(
                                                                'アセリオ',
                                                                maxX,
                                                                chartW,
                                                                Colors
                                                                    .orange
                                                                    .shade700,
                                                              ),
                                                          bgColor: Colors.orange
                                                              .withOpacity(
                                                                0.01,
                                                              ),
                                                        ),
                                                      if (_showRopionRow)
                                                        _buildTimelineRow(
                                                          label: 'ロピオン [mg]',
                                                          maxMinutes: maxX,
                                                          children:
                                                              _getBolusPins(
                                                                'ロピオン',
                                                                maxX,
                                                                chartW,
                                                                Colors.brown,
                                                              ),
                                                          bgColor: Colors.brown
                                                              .withOpacity(
                                                                0.01,
                                                              ),
                                                        ),
                                                      _buildTimelineRow(
                                                        label:
                                                            '$_selectedLaDrug [mL]',
                                                        maxMinutes: maxX,
                                                        children: _getBolusPins(
                                                          'LA',
                                                          maxX,
                                                          chartW,
                                                          Colors
                                                              .indigo
                                                              .shade800,
                                                        ),
                                                        bgColor: Colors.indigo
                                                            .withOpacity(0.01),
                                                      ),
                                                      ...customDrugNames
                                                          .where(
                                                            (name) =>
                                                                name !=
                                                                _selectedFluidType,
                                                          )
                                                          .map((drugName) {
                                                            String customUnit =
                                                                'mg';
                                                            if (drugName ==
                                                                _customDrugNameController
                                                                    .text
                                                                    .trim()) {
                                                              customUnit =
                                                                  _selectedCustomUnit;
                                                            } else {
                                                              try {
                                                                customUnit = _bolusLogs
                                                                    .firstWhere(
                                                                      (b) =>
                                                                          b.drugName ==
                                                                          drugName,
                                                                    )
                                                                    .unit;
                                                              } catch (_) {}
                                                            }
                                                            return _buildTimelineRow(
                                                              label:
                                                                  '$drugName [$customUnit]',
                                                              maxMinutes: maxX,
                                                              children:
                                                                  _getDynamicCustomBolusPins(
                                                                    drugName,
                                                                    maxX,
                                                                    chartW,
                                                                    Colors
                                                                        .grey
                                                                        .shade800,
                                                                  ),
                                                              bgColor: Colors
                                                                  .grey
                                                                  .shade100,
                                                            );
                                                          }),
                                                      _buildTimelineRow(
                                                        label:
                                                            '$_selectedFluidType [mL]',
                                                        maxMinutes: maxX,
                                                        children: _getBolusPins(
                                                          _selectedFluidType,
                                                          maxX,
                                                          chartW,
                                                          Colors.teal.shade700,
                                                        ),
                                                        bgColor: Colors.teal
                                                            .withOpacity(0.02),
                                                      ),
                                                      // 👈 ここに ), が必要
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
                                              '【 イベント・処置・メモ 】',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ..._events
                                                .where((e) => e.time != null)
                                                .map(
                                                  (e) => Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 1.0,
                                                          horizontal: 2.0,
                                                        ),
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _showEventTimeEditDialog(
                                                            e,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 3.0,
                                                              horizontal: 4.0,
                                                            ),
                                                        child: Text(
                                                          '[${DateFormat('HH:mm').format(e.time!)}]  (${e.symbol}) ${e.name}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .blueGrey,
                                                                letterSpacing:
                                                                    0.2,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ..._ivRecords.map(
                                              (iv) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 1.0,
                                                      horizontal: 2.0,
                                                    ),
                                                child: InkWell(
                                                  onTap: () => _showEditDeleteDialog(
                                                    title: 'ルート確保の修正',
                                                    initialTime: iv.time,
                                                    onDelete: () => setState(
                                                      () => _ivRecords
                                                          .removeWhere(
                                                            (i) =>
                                                                i.id == iv.id,
                                                          ),
                                                    ),
                                                    onUpdate: (nt, _) =>
                                                        setState(() {
                                                          int idx = _ivRecords
                                                              .indexWhere(
                                                                (i) =>
                                                                    i.id ==
                                                                    iv.id,
                                                              );
                                                          if (idx != -1)
                                                            _ivRecords[idx] =
                                                                IvRecord(
                                                                  id: iv.id,
                                                                  time: nt,
                                                                  gauge:
                                                                      iv.gauge,
                                                                  site: iv.site,
                                                                  isSuccess: iv
                                                                      .isSuccess,
                                                                );
                                                        }),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 3.0,
                                                          horizontal: 4.0,
                                                        ),
                                                    child: Text(
                                                      '[${DateFormat('HH:mm').format(iv.time)}]  PV ${iv.gauge}/${iv.site} -> ${iv.isSuccess ? "成功" : "失敗"}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.green,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            ..._remarkLogs.map(
                                              (rm) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 1.0,
                                                      horizontal: 2.0,
                                                    ),
                                                child: InkWell(
                                                  onTap: () => _showEditDeleteDialog(
                                                    title:
                                                        '処置メモ No.${rm.number} の修正',
                                                    initialTime: rm.time,
                                                    initialAmount: rm.text,
                                                    amountLabel: 'メモ内容',
                                                    onDelete: () => setState(
                                                      () {
                                                        _remarkLogs.removeWhere(
                                                          (r) => r.id == rm.id,
                                                        );
                                                        for (
                                                          int i = 0;
                                                          i <
                                                              _remarkLogs
                                                                  .length;
                                                          i++
                                                        ) {
                                                          _remarkLogs[i]
                                                                  .number =
                                                              i + 1;
                                                        }
                                                      },
                                                    ),
                                                    onUpdate: (nt, na) =>
                                                        setState(() {
                                                          int idx = _remarkLogs
                                                              .indexWhere(
                                                                (r) =>
                                                                    r.id ==
                                                                    rm.id,
                                                              );
                                                          if (idx != -1) {
                                                            _remarkLogs[idx] =
                                                                RemarkLog(
                                                                  id: rm.id,
                                                                  time: nt,
                                                                  text:
                                                                      na ??
                                                                      rm.text,
                                                                  number:
                                                                      rm.number,
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
                                                      '[${DateFormat('HH:mm').format(rm.time)}]  No.${rm.number}: ${rm.text}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .orange
                                                            .shade800,
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

                                            // ================= 💉 グループB：麻酔・呼吸・薬剤投与（持続＋iv） =================
                                            const Text(
                                              '【 麻酔・呼吸・薬剤設定 】',
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
                                                    "PropofolInf") {
                                                  displayName = "Propofol civ";
                                                  unit = _propofolInfUnit;
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
                                            const Text(
                                              'イベント',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 3),
                                            Expanded(
                                              child: ListView(
                                                children: _events.map((e) {
                                                  bool settled = e.time != null;
                                                  return SizedBox(
                                                    height: 33,
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
                                                const Text(
                                                  '輸液ルート確保',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
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
                                                      items: ['20G', '22G', '24G']
                                                          .map(
                                                            (v) =>
                                                                DropdownMenuItem(
                                                                  value: v,
                                                                  child: Text(
                                                                    v,
                                                                  ),
                                                                ),
                                                          )
                                                          .toList(),
                                                      onChanged: (v) => setState(
                                                        () => _selectedIvGauge =
                                                            v!,
                                                      ),
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
                                                        ),
                                                        items:
                                                            [
                                                                  '左前腕',
                                                                  '右前腕',
                                                                  '左手背',
                                                                  '右手背',
                                                                ]
                                                                .map(
                                                                  (
                                                                    v,
                                                                  ) => DropdownMenuItem(
                                                                    value: v,
                                                                    child: Text(
                                                                      v,
                                                                    ),
                                                                  ),
                                                                )
                                                                .toList(),
                                                        onChanged: (v) => setState(
                                                          () =>
                                                              _selectedIvSite =
                                                                  v!,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Text(
                                                      '繋ぐ輸液:',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: DropdownButton<String>(
                                                        value:
                                                            _selectedFluidType,
                                                        isDense: true,
                                                        isExpanded: true,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.black,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        items:
                                                            ['フィジオ140', '酢酸リンゲル', 'ソルデム3A', '生理食塩水', '5%ブドウ糖',]
                                                                .map(
                                                                  (
                                                                    v,
                                                                  ) => DropdownMenuItem(
                                                                    value: v,
                                                                    child: Text(
                                                                      v,
                                                                    ),
                                                                  ),
                                                                )
                                                                .toList(),
                                                        onChanged: (v) => setState(
                                                          () =>
                                                              _selectedFluidType =
                                                                  v!,
                                                        ),
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
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.teal.shade600,
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
                                                  const Text(
                                                    '処置メモ',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
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
                                                      '記録',
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
                                      const Text(
                                        '呼吸・麻酔薬剤設定',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 1),

                                      _alignedDrugRow(
                                        label: 'O2 流量 :',
                                        child: TextField(
                                          controller: _o2Controller,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'L/min',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_o2Controller
                                                      .text
                                                      .isEmpty)
                                                    return;
                                                  _addInfusionPoint(
                                                    'O2',
                                                    _o2Controller.text,
                                                  );
                                                  _o2Controller.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '投与',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    _stopInfusionPoint('O2'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'OFF',
                                                  style: TextStyle(fontSize: 9),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'N2O 流量 :',
                                        child: TextField(
                                          controller: _n2oController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'L/min',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_n2oController
                                                      .text
                                                      .isEmpty)
                                                    return;
                                                  _addInfusionPoint(
                                                    'N2O',
                                                    _n2oController.text,
                                                  );
                                                  _n2oController.clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.lightBlue.shade700,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '投与',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    _stopInfusionPoint('N2O'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'OFF',
                                                  style: TextStyle(fontSize: 9),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'Propofol civ :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller:
                                                    _propofolInfController,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '速度',
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            DropdownButton<String>(
                                              value: _propofolInfUnit,
                                              isDense: true,
                                              items:
                                                  ['mg/kg/h', 'mL/h', 'μg/mL']
                                                      .map(
                                                        (u) => DropdownMenuItem(
                                                          value: u,
                                                          child: Text(
                                                            u,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 9,
                                                                ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              onChanged: (v) => setState(
                                                () => _propofolInfUnit = v!,
                                              ),
                                            ),
                                          ],
                                        ),
                                        suffix: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  if (_propofolInfController
                                                      .text
                                                      .isEmpty)
                                                    return;
                                                  _addInfusionPoint(
                                                    'PropofolInf',
                                                    _propofolInfController.text,
                                                  );
                                                  _propofolInfController
                                                      .clear();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.purple,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '投与',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            SizedBox(
                                              width: 32,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    _stopInfusionPoint(
                                                      'PropofolInf',
                                                    ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.grey,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  '停止',
                                                  style: TextStyle(fontSize: 9),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'Propofol iv :',
                                        child: TextField(
                                          controller: _propofolBolusController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            _addBolus(
                                              'Propofol',
                                              _propofolBolusController.text,
                                              'mg',
                                            );
                                            _propofolBolusController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'Midazolam iv :',
                                        child: TextField(
                                          controller: _midazolamController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            _addBolus(
                                              'Midazolam',
                                              _midazolamController.text,
                                              'mg',
                                            );
                                            _midazolamController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'アセリオ iv :',
                                        child: TextField(
                                          controller: _acerioController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            _addBolus(
                                              'アセリオ',
                                              _acerioController.text,
                                              'mg',
                                            );
                                            _acerioController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.orange.shade800,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: 'ロピオン iv :',
                                        child: TextField(
                                          controller: _ropionController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mg',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            _addBolus(
                                              'ロピオン',
                                              _ropionController.text,
                                              'mg',
                                            );
                                            _ropionController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.brown,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: '局所麻酔 :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: DropdownButton<String>(
                                                value: _selectedLaDrug,
                                                isDense: true,
                                                isExpanded: true,
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  color: Colors.black,
                                                ),
                                                items:
                                                    [
                                                          'オーラ注',
                                                          'セプトカイン',
                                                          'キシロカイン',
                                                          'シタネスト',
                                                          'エピリド',
                                                          'スキャンドネスト',
                                                        ]
                                                        .map(
                                                          (v) =>
                                                              DropdownMenuItem(
                                                                value: v,
                                                                child: Text(v),
                                                              ),
                                                        )
                                                        .toList(),
                                                onChanged: (v) => setState(
                                                  () => _selectedLaDrug = v!,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            SizedBox(
                                              width: 42,
                                              child: TextField(
                                                controller: _laMlController,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: 'mL',
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_laMlController.text
                                                .trim()
                                                .isEmpty)
                                              return;
                                            setState(() {
                                              _initStartTimeIfNeeded();
                                              _bolusLogs.add(
                                                BolusLog(
                                                  id: DateTime.now().toString(),
                                                  time: DateTime.now(),
                                                  drugName: 'LA',
                                                  amount:
                                                      '$_selectedLaDrug ${_laMlController.text}',
                                                  unit: 'mL',
                                                ),
                                              );
                                            });
                                            _laMlController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.indigo,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      _alignedDrugRow(
                                        label: '自由追加薬 :',
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller:
                                                    _customDrugNameController,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '薬剤名',
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller:
                                                    _customDrugAmountController,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '量',
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            DropdownButton<String>(
                                              value: _selectedCustomUnit,
                                              isDense: true,
                                              items: ['mg', 'μg', 'mL', '管']
                                                  .map(
                                                    (u) => DropdownMenuItem(
                                                      value: u,
                                                      child: Text(
                                                        u,
                                                        style: const TextStyle(
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) => setState(
                                                () => _selectedCustomUnit = v!,
                                              ),
                                            ),
                                          ],
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            String dName =
                                                _customDrugNameController.text
                                                    .trim();
                                            String dAmount =
                                                _customDrugAmountController.text
                                                    .trim();
                                            if (dName.isEmpty ||
                                                dAmount.isEmpty)
                                              return;

                                            _addBolus(
                                              dName,
                                              dAmount,
                                              _selectedCustomUnit,
                                            );
                                            _customDrugAmountController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.grey.shade800,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '投与',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _alignedDrugRow(
                                        label: '$_selectedFluidType :',
                                        child: TextField(
                                          controller: _fluidController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          style: const TextStyle(fontSize: 11),
                                          decoration: const InputDecoration(
                                            hintText: 'mL',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        suffix: ElevatedButton(
                                          onPressed: () {
                                            if (_fluidController.text.isEmpty)
                                              return;
                                            setState(() {
                                              _initStartTimeIfNeeded();
                                              _bolusLogs.add(
                                                BolusLog(
                                                  id: DateTime.now().toString(),
                                                  time: DateTime.now(),
                                                  drugName: _selectedFluidType,
                                                  amount: _fluidController.text,
                                                  unit: 'mL',
                                                ),
                                              );
                                            });
                                            _fluidController.clear();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueGrey,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          child: const Text(
                                            '追加',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
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
