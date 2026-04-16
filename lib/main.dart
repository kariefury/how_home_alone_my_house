import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const HowPrankedApp());
}

class HowPrankedApp extends StatelessWidget {
  const HowPrankedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'How Pranked My House',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFADFF2F),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const PrankScannerHome(),
    );
  }
}

// ─────────────────────────────────────────────────
// PRANK CATEGORY MODEL
// ─────────────────────────────────────────────────
class PrankCategory {
  final String emoji;
  final String name;
  final Color color;
  double level;
  PrankCategory(
      {required this.emoji,
      required this.name,
      required this.color,
      this.level = 0.1});
}

// ─────────────────────────────────────────────────
// LABEL CLASSIFIERS
// ─────────────────────────────────────────────────
double felineBoost(String l) {
  if (l.contains('cat') || l.contains('feline')) return 0.18;
  if (l.contains('dog') || l.contains('canine') || l.contains('puppy'))
    return 0.18;
  if (l.contains('pet') || l.contains('kitten') || l.contains('animal'))
    return 0.10;
  if (l.contains('mammal') || l.contains('wildlife')) return 0.06;
  return 0.0;
}

double floorBoost(String l) {
  if (l.contains('lego') || l.contains('duplo')) return 0.20;
  if (l.contains('toy vehicle') ||
      l.contains('toy car') ||
      l.contains('toy truck')) return 0.20;
  if (l.contains('toy') || l.contains('doll') || l.contains('action figure'))
    return 0.15;
  if (l.contains('figurine') || l.contains('miniature')) return 0.12;
  if (l.contains('ball') || l.contains('balloon')) return 0.15;
  if (l.contains('puzzle') ||
      l.contains('board game') ||
      l.contains('game')) return 0.12;
  if (l.contains('vehicle') ||
      l.contains('truck') ||
      l.contains('car') ||
      l.contains('crane') ||
      l.contains('construction') ||
      l.contains('excavator')) return 0.15;
  if (l.contains('train') ||
      l.contains('locomotive') ||
      l.contains('aircraft') ||
      l.contains('boat') ||
      l.contains('ship')) return 0.12;
  if (l.contains('shoe') ||
      l.contains('boot') ||
      l.contains('sneaker') ||
      l.contains('footwear') ||
      l.contains('sandal') ||
      l.contains('slipper')) return 0.15;
  if (l.contains('clutter') || l.contains('mess') || l.contains('disorder'))
    return 0.18;
  if (l.contains('box') || l.contains('package') || l.contains('carton'))
    return 0.12;
  if (l.contains('bag') ||
      l.contains('backpack') ||
      l.contains('suitcase') ||
      l.contains('luggage')) return 0.12;
  if (l.contains('book') || l.contains('paper') || l.contains('magazine'))
    return 0.08;
  if (l.contains('sporting') ||
      l.contains('sport') ||
      l.contains('equipment')) return 0.10;
  if (l.contains('clothing') ||
      l.contains('laundry') ||
      l.contains('garment') ||
      l.contains('shirt') ||
      l.contains('sock') ||
      l.contains('pants') ||
      l.contains('jacket') ||
      l.contains('hoodie') ||
      l.contains('jumper') ||
      l.contains('sweater') ||
      l.contains('pyjama') ||
      l.contains('pajama') ||
      l.contains('underwear') ||
      l.contains('hat') ||
      l.contains('cap') ||
      l.contains('glove') ||
      l.contains('scarf')) return 0.12;
  // Soft furnishings on the floor — very common child mess
  if (l.contains('blanket') ||
      l.contains('quilt') ||
      l.contains('duvet') ||
      l.contains('comforter') ||
      l.contains('throw')) return 0.18;
  if (l.contains('pillow') ||
      l.contains('cushion') ||
      l.contains('bolster')) return 0.16;
  // Stuffed animals / soft toys
  if (l.contains('stuffed') ||
      l.contains('plush') ||
      l.contains('teddy') ||
      l.contains('soft toy') ||
      l.contains('cuddly')) return 0.18;
  // Other common floor clutter
  if (l.contains('towel') || l.contains('rag'))
    return 0.14;
  if (l.contains('remote') ||
      l.contains('controller') ||
      l.contains('gamepad') ||
      l.contains('joystick')) return 0.14;
  if (l.contains('pencil') ||
      l.contains('pen') ||
      l.contains('crayon') ||
      l.contains('marker') ||
      l.contains('ruler')) return 0.14;
  if (l.contains('block') || l.contains('brick')) return 0.18;
  if (l.contains('rope') || l.contains('string') || l.contains('cord'))
    return 0.10;
  if (l.contains('bottle') && l.contains('water')) return 0.14;
  if (l.contains('tool') || l.contains('hardware')) return 0.10;
  if (l.contains('household') ||
      l.contains('goods') ||
      l.contains('object')) return 0.06;
  return 0.0;
}

double splashBoost(String l) {
  if (l.contains('bottle') || l.contains('water bottle')) return 0.18;
  if (l.contains('cup') ||
      l.contains('mug') ||
      l.contains('glass') ||
      l.contains('tumbler') ||
      l.contains('tupperware') ||
      l.contains('container') ||
      l.contains('food storage')) return 0.18;
  if (l.contains('bowl') || l.contains('bucket') || l.contains('jug'))
    return 0.15;
  if (l.contains('liquid') ||
      l.contains('drink') ||
      l.contains('beverage') ||
      l.contains('juice') ||
      l.contains('water')) return 0.12;
  if (l.contains('spray') || l.contains('squirt') || l.contains('hose'))
    return 0.15;
  if (l.contains('sink') || l.contains('bathtub') || l.contains('toilet'))
    return 0.10;
  if (l.contains('food') ||
      l.contains('fruit') ||
      l.contains('banana') ||
      l.contains('orange') ||
      l.contains('apple') ||
      l.contains('snack')) return 0.12;
  return 0.0;
}

double furnitureBoost(String l) {
  if (l.contains('chair') ||
      l.contains('sofa') ||
      l.contains('couch') ||
      l.contains('armchair') ||
      l.contains('stool') ||
      l.contains('bench')) return 0.15;
  if (l.contains('table') || l.contains('desk') || l.contains('counter'))
    return 0.15;
  if (l.contains('shelf') ||
      l.contains('bookcase') ||
      l.contains('bookshelf') ||
      l.contains('cabinet') ||
      l.contains('wardrobe') ||
      l.contains('dresser')) return 0.12;
  if (l.contains('furniture') || l.contains('rack') || l.contains('stand'))
    return 0.10;
  if (l.contains('bed') || l.contains('mattress')) return 0.08;
  return 0.0;
}

// Kid-friendly pickup label for the mission card
String getMissionLabel(String rawLabel) {
  final l = rawLabel.toLowerCase();
  if (felineBoost(l) > 0) return 'the pet toy';
  if (l.contains('lego') || l.contains('block') || l.contains('brick'))
    return 'those LEGO bricks';
  if (l.contains('toy vehicle') ||
      l.contains('toy car') ||
      l.contains('toy truck')) return 'that toy car';
  if (l.contains('stuffed') ||
      l.contains('plush') ||
      l.contains('teddy') ||
      l.contains('cuddly')) return 'that stuffed animal';
  if (l.contains('toy') || l.contains('doll') || l.contains('figurine'))
    return 'that toy';
  if (l.contains('ball')) return 'that ball';
  if (l.contains('blanket') || l.contains('quilt') ||
      l.contains('duvet') || l.contains('comforter') ||
      l.contains('throw')) return 'that blanket';
  if (l.contains('pillow') || l.contains('cushion') ||
      l.contains('bolster')) return 'that pillow';
  if (l.contains('towel')) return 'that towel';
  if (l.contains('shoe') || l.contains('boot') || l.contains('footwear') ||
      l.contains('sneaker') || l.contains('slipper')) return 'those shoes';
  if (l.contains('sock')) return 'those socks';
  if (l.contains('clothing') || l.contains('cloth') ||
      l.contains('laundry') || l.contains('shirt') ||
      l.contains('pants') || l.contains('jacket') ||
      l.contains('hoodie') || l.contains('pyjama') ||
      l.contains('pajama')) return 'those clothes';
  if (l.contains('hat') || l.contains('cap')) return 'that hat';
  if (l.contains('book') || l.contains('magazine')) return 'that book';
  if (l.contains('paper')) return 'that paper';
  if (l.contains('pencil') || l.contains('pen') ||
      l.contains('crayon') || l.contains('marker')) return 'those pencils';
  if (l.contains('remote') || l.contains('controller') ||
      l.contains('gamepad')) return 'that remote control';
  if (l.contains('bottle') || l.contains('cup') ||
      l.contains('mug') || l.contains('glass')) return 'that cup';
  if (l.contains('bowl')) return 'that bowl';
  if (l.contains('box') || l.contains('package')) return 'that box';
  if (l.contains('bag') || l.contains('backpack')) return 'that bag';
  if (l.contains('vehicle') || l.contains('truck') ||
      l.contains('car') || l.contains('train')) return 'that toy vehicle';
  return rawLabel.isNotEmpty ? 'that ${rawLabel.toLowerCase()}' : 'that item';
}

// Bounding box display label
String getPrankLabel(String rawLabel) {
  final l = rawLabel.toLowerCase();
  if (felineBoost(l) > 0) return '🐱 ${rawLabel.toUpperCase()}';
  if (l.contains('lego') || l.contains('block') || l.contains('brick'))
    return '🧱 LEGO MINEFIELD';
  if (l.contains('toy vehicle') ||
      l.contains('toy car') ||
      l.contains('toy truck')) return '🚗 WHEELED MENACE';
  if (l.contains('toy') || l.contains('doll') || l.contains('figurine'))
    return '🪀 TOY TRAP';
  if (l.contains('ball')) return '⚽ ANKLE BREAKER';
  if (l.contains('shoe') || l.contains('boot') || l.contains('footwear'))
    return '👟 STAIR HAZARD';
  if (l.contains('clothing') || l.contains('cloth') || l.contains('laundry'))
    return '👕 TRIP FABRIC';
  if (l.contains('vehicle') ||
      l.contains('truck') ||
      l.contains('car') ||
      l.contains('crane')) return '🚗 WHEELED MENACE';
  if (l.contains('clutter') || l.contains('mess')) return '⚠️ CHAOS DETECTED';
  if (l.contains('box') || l.contains('package')) return '📦 STUBBED TOE BAIT';
  if (l.contains('bottle') || l.contains('cup') || l.contains('glass'))
    return '💦 SPLASH ZONE';
  if (l.contains('food') || l.contains('fruit')) return '🍌 SLIP BAIT';
  if (l.contains('chair') || l.contains('table') || l.contains('furniture'))
    return '🪑 SHIN DESTROYER';
  if (l.contains('shelf') || l.contains('bookcase')) return '📚 FALLING HAZARD';
  if (l.contains('person') || l.contains('human')) return '👤 INTRUDER!';
  return '⚠️ ${rawLabel.toUpperCase()}';
}

// ─────────────────────────────────────────────────
// VERDICT & GRADE
// ─────────────────────────────────────────────────
String getChaosVerdict(
    double feline, double floor, double splash, double furniture) {
  final total = (feline + floor + splash + furniture) / 4.0;
  final hasCat = feline > 0.45;
  final hasFloor = floor > 0.45;
  final hasSplash = splash > 0.45;
  final hasFurniture = furniture > 0.45;

  if (hasCat && hasFloor && hasSplash)
    return "🏆 GRAND SLAM PRANK HOUSE! Kevin McCallister would weep with pride.";
  if (hasFloor && total > 0.70)
    return "☠️ The floor is basically a LEGO minefield wrapped in toy trucks. EMS has been pre-dialed.";
  if (hasCat && hasFloor)
    return "😈 Cats + floor traps = a lethal combo. Midnight trip to the ER is GUARANTEED tonight.";
  if (hasCat)
    return "🐱 Your cat has clearly been planning something. Those innocent eyes are DECEIVING you.";
  if (hasSplash && hasFloor)
    return "💦 Wet floors + scattered obstacles = lawsuit waiting to happen.";
  if (hasFurniture && hasFloor)
    return "🪑 Sharp corners EVERYWHERE. The furniture is conspiring with the clutter against your shins.";
  if (hasFloor)
    return "🧱 The floor has achieved sentience and chosen violence. Shoes mandatory.";
  if (total > 0.65)
    return "☠️ EXTREME DANGER. Abandon all hope, ye who enter barefoot.";
  if (total > 0.45)
    return "😬 Risky in here. Proceed with maximum socks and a prayer to the god of shins.";
  if (total > 0.25) return "🤔 Some prank potential. Stay alert, stay alive.";
  return "😌 Surprisingly safe! Either genuinely tidy, or the pranks are VERY well hidden.";
}

String getChaosEmoji(double total) {
  if (total > 0.75) return '🏆💀😱🔥';
  if (total > 0.55) return '😱⚠️🚨';
  if (total > 0.35) return '😬🤔⚠️';
  if (total > 0.18) return '🙂👀';
  return '😌✅';
}

// Chaos grade: S+ = messiest, F = cleanest. Lower chaos = better room.
String getChaosGrade(double total) {
  if (total > 0.80) return 'S+';
  if (total > 0.65) return 'A';
  if (total > 0.50) return 'B';
  if (total > 0.35) return 'C';
  if (total > 0.20) return 'D';
  return 'F';
}

// CLEANUP grade: improves as more items are collected. Traditional A = great.
String getCleanupGrade(int items) {
  if (items >= 20) return 'S+';
  if (items >= 12) return 'A';
  if (items >= 7) return 'B';
  if (items >= 3) return 'C';
  if (items >= 1) return 'D';
  return 'F';
}

String getCleanupLabel(int items) {
  if (items >= 20) return 'LEGENDARY TIDIER! 🏆';
  if (items >= 12) return 'AMAZING CLEANER! 🌟';
  if (items >= 7) return 'GREAT JOB! 💪';
  if (items >= 3) return 'GETTING THERE! 👍';
  if (items >= 1) return 'NICE START! ✨';
  return 'SCAN A ROOM TO BEGIN!';
}

Color getGradeColor(String grade) {
  switch (grade) {
    case 'S+':
      return const Color(0xFFFF0055);
    case 'A':
      return const Color(0xFFFF6B35);
    case 'B':
      return const Color(0xFFFFD700);
    case 'C':
      return const Color(0xFFADFF2F);
    case 'D':
      return const Color(0xFF00BFFF);
    default:
      return Colors.grey;
  }
}

// ─────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────
class PrankScannerHome extends StatefulWidget {
  const PrankScannerHome({super.key});
  @override
  State<PrankScannerHome> createState() => _PrankScannerHomeState();
}

class _PrankScannerHomeState extends State<PrankScannerHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late CameraController _cameraController;
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;
  final GlobalKey _captureKey = GlobalKey();

  ObjectDetector? _objectDetector;
  ImageLabeler? _imageLabeler;

  bool _canProcess = false;
  bool _isBusy = false;
  bool _cameraReady = false;
  int _frameCount = 0;

  List<DetectedObject> _detectedObjects = [];
  List<ImageLabel> _latestLabels = [];

  // Actual camera frame area in pixels — captured from the first frame.
  // Used for the size-gate: objects > 25% of frame area are not pickuppable.
  double _frameArea = 640.0 * 480.0; // sensible default, overwritten on first frame

  // ── Cleanup tracking ──────────────────────────────
  int _itemsCollected = 0;

  // Current mission: the object we're asking the kid to pick up.
  // Identified by trackingId (or negative list-index if trackingId is null).
  int? _targetId;
  String? _targetRawLabel;      // ML Kit label text (for re-matching)
  String? _missionFriendlyLabel; // Kid-friendly display

  bool _celebrating = false;
  String _celebrationText = '';

  static const List<String> _celebrations = [
    '⭐ AMAZING! +1 item!',
    '🎉 GREAT JOB! Keep going!',
    '🌟 SUPERSTAR CLEANER!',
    '✨ YOU ROCK! +1!',
    '🏆 CHAMPION TIDIER!',
    '🎯 BULLSEYE! +1 item!',
    '💪 SO STRONG AND TIDY!',
    '🥳 PARTY TIME! +1!',
    '🌈 INCREDIBLE! +1!',
    '🚀 POWER CLEANER! +1!',
  ];

  final PrankCategory _felineCategory = PrankCategory(
      emoji: '🐱',
      name: 'FELINE AGENTS',
      color: const Color(0xFFFF6B35));
  final PrankCategory _floorCategory = PrankCategory(
      emoji: '🧱',
      name: 'FLOOR TRAPS',
      color: const Color(0xFFFF3366));
  final PrankCategory _splashCategory = PrankCategory(
      emoji: '💦',
      name: 'SPLASH ZONES',
      color: const Color(0xFF00CFFF));
  final PrankCategory _furnitureCategory = PrankCategory(
      emoji: '🪑',
      name: 'SHIN DESTROYERS',
      color: const Color(0xFFFFD700));

  bool _isSaving = false;
  bool _showDebugLabels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _initDetectors();

    _scanController =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);
    _scanAnimation =
        Tween<double>(begin: 0.05, end: 0.95).animate(_scanController);
  }

  // ── Camera ────────────────────────────────────────
  Future<void> _initCamera() async {
    _cameraController = CameraController(
        _cameras[0], ResolutionPreset.medium,
        enableAudio: false);
    try {
      await _cameraController.initialize();
      if (!mounted) return;
      await _cameraController.startImageStream(_processFrame);
      setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _disposeCamera() async {
    _canProcess = false;
    try {
      if (_cameraController.value.isInitialized) {
        if (_cameraController.value.isStreamingImages) {
          await _cameraController.stopImageStream();
        }
        await _cameraController.dispose();
      }
    } catch (e) {
      debugPrint('Camera dispose error: $e');
    }
    if (mounted) setState(() => _cameraReady = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _disposeCamera();
        break;
      case AppLifecycleState.resumed:
        _initCamera();
        _canProcess = true;
        break;
      default:
        break;
    }
  }

  // ── Detectors ─────────────────────────────────────
  void _initDetectors() {
    _objectDetector = ObjectDetector(
        options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ));
    _imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.40),
    );
    _canProcess = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _scanController.dispose();
    _objectDetector?.close();
    _imageLabeler?.close();
    super.dispose();
  }

  // ── Mission target selection ───────────────────────
  //
  // NEW APPROACH: size-first, not label-first.
  //
  // The fundamental insight is that anything you can physically pick up fits
  // in your arms — it cannot fill 25%+ of the camera frame from a normal
  // standing distance. Pianos, cabinets, yoga mats, and carpets all fail
  // this test naturally, without needing to name them in a blocklist.
  //
  // Algorithm:
  //   1. Size gate  — drop any object whose bounding box > 25% of frame area.
  //   2. Label preference — among the survivors, score by known messy labels
  //      (toys, clothes, cups, etc.) and pick the highest scorer.
  //   3. Fallback — if nothing has a recognisable label, pick the smallest
  //      object that passed the size gate (unlabelled small object = probably
  //      a toy or clutter).
  //   4. Minimal blocklist — last-resort veto for a handful of things that
  //      can appear small in frame (e.g. a close-up of a shelf bracket).
  //
  void _updateMissionTarget(List<DetectedObject> objects) {
    if (objects.isEmpty) return;

    // ── Sticky: keep current target while it's still visible ──────────────
    if (_targetId != null) {
      final byId = objects.where((o) => o.trackingId == _targetId);
      if (byId.isNotEmpty) return;

      if (_targetRawLabel != null) {
        final byLabel = objects.where((o) => o.labels.any(
            (lbl) => lbl.text == _targetRawLabel && lbl.confidence > 0.25));
        if (byLabel.isNotEmpty) {
          final matched = byLabel.first;
          _targetId = matched.trackingId ?? -(objects.indexOf(matched) + 1);
          return;
        }
      }

      _targetId = null;
      _targetRawLabel = null;
      _missionFriendlyLabel = null;
    }

    // ── STEP 1: Size gate (primary filter) ────────────────────────────────
    // Reject objects whose bounding box covers > 25% of the camera frame.
    // This single rule eliminates pianos, cabinets, sofas, yoga mats, rugs,
    // and anything else that is too large to pick up.
    final maxArea = _frameArea * 0.25;

    final sizeFiltered = objects.where((o) {
      final area = o.boundingBox.width * o.boundingBox.height;
      return area <= maxArea;
    }).toList();

    if (sizeFiltered.isEmpty) return; // Everything in frame is too large.

    // ── STEP 2: Minimal blocklist veto ────────────────────────────────────
    // Only used for the small set of things that can look "small" in frame
    // (e.g. camera very close to a shelf) but are still not pickuppable.
    final candidates = sizeFiltered.where((o) =>
        !o.labels.any((lbl) => _isObviouslyFixed(lbl.text))).toList();

    // If the blocklist removed everything, fall back to size-only list.
    final pool = candidates.isNotEmpty ? candidates : sizeFiltered;

    // ── STEP 3: Label-based scoring ───────────────────────────────────────
    // Prefer objects with known "messy" labels. Score by boost × confidence.
    DetectedObject? best;
    String? bestLabel;
    double bestScore = -1;

    for (final obj in pool) {
      for (final lbl in obj.labels) {
        if (lbl.confidence < 0.25) continue;
        final l = lbl.text.toLowerCase();
        final score =
            (floorBoost(l) + splashBoost(l) + felineBoost(l)) * lbl.confidence;
        if (score > bestScore) {
          bestScore = score;
          best = obj;
          bestLabel = lbl.text;
        }
      }
    }

    // ── STEP 4: Fallback — smallest object ────────────────────────────────
    if (best == null) {
      pool.sort((a, b) {
        final aArea = a.boundingBox.width * a.boundingBox.height;
        final bArea = b.boundingBox.width * b.boundingBox.height;
        return aArea.compareTo(bArea);
      });
      best = pool.first;
      bestLabel = best.labels.isNotEmpty ? best.labels.first.text : null;
    }

    final idx = objects.indexOf(best!);
    _targetId = best.trackingId ?? -(idx + 1);
    _targetRawLabel = bestLabel;
    _missionFriendlyLabel = bestLabel != null
        ? getMissionLabel(bestLabel!)
        : 'that item on the floor';
  }

  // Minimal blocklist — only items that can appear small in frame but are
  // still not pickuppable. Kept deliberately short; size does the real work.
  bool _isObviouslyFixed(String rawLabel) {
    final l = rawLabel.toLowerCase();
    const fixed = [
      'wall', 'ceiling', 'floor', 'flooring', 'tile', 'door', 'window',
      'shelf', 'bookcase', 'bookshelf',
      'person', 'human', 'face',
      'television', 'monitor', 'screen',
      'room', 'interior', 'building',
    ];
    return fixed.any((f) => l.contains(f));
  }

  // ── Frame processor ───────────────────────────────
  void _processFrame(CameraImage image) async {
    if (!_canProcess || _isBusy) return;
    _isBusy = true;
    _frameCount++;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      // Capture real frame area once (ML Kit bounding boxes are in this space).
      _frameArea = image.width.toDouble() * image.height.toDouble();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final objects = _objectDetector != null
          ? await _objectDetector!.processImage(inputImage)
          : <DetectedObject>[];

      List<ImageLabel> labels = [];
      if (_frameCount % 8 == 0 && _imageLabeler != null) {
        labels = await _imageLabeler!.processImage(inputImage);
      } else {
        labels = _latestLabels;
      }

      if (mounted) {
        setState(() {
          _detectedObjects = objects;
          if (_frameCount % 8 == 0) _latestLabels = labels;

          // Update mission target (only when not celebrating).
          if (!_celebrating) _updateMissionTarget(objects);

          // Cleanup bonus: each item collected permanently damps chaos boosts.
          // Using a smaller per-item value so the room doesn't clean itself
          // too fast — 20 items needed for maximum relief (~0.30 cap).
          final cleanupBonus =
              (_itemsCollected * 0.015).clamp(0.0, 0.30);

          // Passive decay is very slow — the room should stay messy unless
          // the child is actively picking things up.
          const decay = 0.0005;
          _felineCategory.level =
              (_felineCategory.level - decay).clamp(0.1, 1.0);
          _floorCategory.level =
              (_floorCategory.level - decay).clamp(0.1, 1.0);
          _splashCategory.level =
              (_splashCategory.level - decay).clamp(0.1, 1.0);
          _furnitureCategory.level =
              (_furnitureCategory.level - decay).clamp(0.1, 1.0);

          // Object count → floor chaos, slightly offset by cleanup bonus.
          final count = objects.length;
          if (count > 0) {
            final countBoost = (count * 0.025).clamp(0.0, 0.20);
            _floorCategory.level = (_floorCategory.level +
                    countBoost -
                    cleanupBonus * 0.15)
                .clamp(0.1, 1.0);
          }

          // Object detection labels.
          for (final obj in objects) {
            for (final label in obj.labels) {
              if (label.confidence < 0.30) continue;
              final l = label.text.toLowerCase();
              final w = label.confidence;
              _felineCategory.level = (_felineCategory.level +
                      felineBoost(l) * w -
                      cleanupBonus * 0.03)
                  .clamp(0.1, 1.0);
              _floorCategory.level = (_floorCategory.level +
                      floorBoost(l) * w -
                      cleanupBonus * 0.03)
                  .clamp(0.1, 1.0);
              _splashCategory.level = (_splashCategory.level +
                      splashBoost(l) * w -
                      cleanupBonus * 0.03)
                  .clamp(0.1, 1.0);
              _furnitureCategory.level = (_furnitureCategory.level +
                      furnitureBoost(l) * w -
                      cleanupBonus * 0.03)
                  .clamp(0.1, 1.0);
            }
          }

          // Image labeler (every 8 frames, larger boost).
          if (_frameCount % 8 == 0) {
            for (final label in labels) {
              if (label.confidence < 0.40) continue;
              final l = label.label.toLowerCase();
              final w = label.confidence;
              _felineCategory.level = (_felineCategory.level +
                      felineBoost(l) * w * 1.5 -
                      cleanupBonus * 0.05)
                  .clamp(0.1, 1.0);
              _floorCategory.level = (_floorCategory.level +
                      floorBoost(l) * w * 1.5 -
                      cleanupBonus * 0.05)
                  .clamp(0.1, 1.0);
              _splashCategory.level = (_splashCategory.level +
                      splashBoost(l) * w * 1.5 -
                      cleanupBonus * 0.05)
                  .clamp(0.1, 1.0);
              _furnitureCategory.level = (_furnitureCategory.level +
                      furnitureBoost(l) * w * 1.5 -
                      cleanupBonus * 0.05)
                  .clamp(0.1, 1.0);
            }
          }
        });
      }
    } catch (e) {
      debugPrint("ML Error: $e");
    }
    _isBusy = false;
  }

  // ── Item collected ────────────────────────────────
  void _onItemCollected() {
    if (_celebrating) return;
    setState(() {
      _itemsCollected++;
      _celebrating = true;
      _celebrationText =
          _celebrations[(_itemsCollected - 1) % _celebrations.length];

      // Immediate chaos reduction on pickup — kept modest so the bars
      // don't crater instantly. The real benefit builds up via cleanupBonus.
      const reduction = 0.06;
      _floorCategory.level =
          (_floorCategory.level - reduction).clamp(0.1, 1.0);
      _felineCategory.level =
          (_felineCategory.level - reduction * 0.4).clamp(0.1, 1.0);
      _splashCategory.level =
          (_splashCategory.level - reduction * 0.4).clamp(0.1, 1.0);
      _furnitureCategory.level =
          (_furnitureCategory.level - reduction * 0.4).clamp(0.1, 1.0);

      // Clear mission so a new one is selected after celebration.
      _targetId = null;
      _targetRawLabel = null;
      _missionFriendlyLabel = null;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  double get _totalChaos =>
      (_felineCategory.level +
          _floorCategory.level +
          _splashCategory.level +
          _furnitureCategory.level) /
      4.0;

  // ── Share ─────────────────────────────────────────
  Future<void> _captureAndShare() async {
    setState(() => _isSaving = true);
    try {
      final boundary = _captureKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image img = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/prank_scan_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '🏠 How Pranked My House?\nCLEANUP GRADE: ${getCleanupGrade(_itemsCollected)}\n⭐ $_itemsCollected items picked up!',
        subject: 'My House Cleanup Report',
      );
    } catch (e) {
      debugPrint("Share error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_cameraReady) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFADFF2F)),
              SizedBox(height: 16),
              Text('INITIALIZING PRANK DETECTOR...',
                  style: TextStyle(color: Color(0xFFADFF2F))),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final hasMission = _missionFriendlyLabel != null && !_celebrating;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _captureKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController.value.previewSize!.height,
                      height: _cameraController.value.previewSize!.width,
                      child: CameraPreview(_cameraController),
                    ),
                  ),
                ),

                // Bounding boxes
                CustomPaint(
                  painter: PrankBoxPainter(
                    objects: _detectedObjects,
                    imageSize: Size(
                      _cameraController.value.previewSize!.height,
                      _cameraController.value.previewSize!.width,
                    ),
                    widgetSize: size,
                    targetId: _targetId,
                  ),
                ),

                // Top gradient
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    height: 170,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // Bottom gradient
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 310,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xEE000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // ── Top bar: title + cleanup counter ──
                Positioned(
                  top: 48,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onDoubleTap: () => setState(
                            () => _showDebugLabels = !_showDebugLabels),
                        child: const Text(
                          '🏠 HOW PRANKED MY HOUSE',
                          style: TextStyle(
                            color: Color(0xFFADFF2F),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(
                                  blurRadius: 12,
                                  color: Color(0xFFADFF2F))
                            ],
                          ),
                        ),
                      ),
                      _buildItemBadge(),
                    ],
                  ),
                ),

                // ── Mission panel / celebration ──
                Positioned(
                  top: 100,
                  left: 16,
                  right: 16,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: _celebrating
                        ? _buildCelebrationPanel(key: const ValueKey('cel'))
                        : hasMission
                            ? _buildMissionPanel(key: const ValueKey('mis'))
                            : const SizedBox.shrink(
                                key: ValueKey('empty')),
                  ),
                ),

                // Green scan line
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, _) => Positioned(
                    top: size.height * _scanAnimation.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.transparent,
                          const Color(0xFFADFF2F).withOpacity(0.8),
                          const Color(0xFFADFF2F),
                          const Color(0xFFADFF2F).withOpacity(0.8),
                          Colors.transparent,
                        ]),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFADFF2F).withOpacity(0.7),
                            blurRadius: 22,
                            spreadRadius: 7,
                          )
                        ],
                      ),
                    ),
                  ),
                ),

                // Chaos meters (bottom-left)
                Positioned(
                  bottom: 170,
                  left: 16,
                  child: _buildChaosMeters(),
                ),

                // Grade badge (bottom-right)
                Positioned(
                  bottom: 165,
                  right: 16,
                  child: _buildGradeBadge(),
                ),

                // Debug label strip
                if (_showDebugLabels)
                  Positioned(
                    top: 92,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withOpacity(0.75),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Text(
                        _latestLabels.isEmpty
                            ? 'No image labels yet...'
                            : _latestLabels
                                .take(10)
                                .map((l) =>
                                    '${l.label} ${(l.confidence * 100).toInt()}%')
                                .join('  •  '),
                        style: const TextStyle(
                            color: Color(0xFFADFF2F),
                            fontSize: 10,
                            fontFamily: 'monospace'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Bottom controls ──
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "I PICKED IT UP!" — only visible when mission is active
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) =>
                      SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero)
                        .animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: hasMission
                      ? Padding(
                          key: const ValueKey('pickupBtn'),
                          padding: const EdgeInsets.only(
                              bottom: 12, left: 20, right: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E87A),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(32)),
                                elevation: 14,
                                shadowColor: const Color(0xFF00E87A),
                              ),
                              onPressed: _onItemCollected,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: const [
                                  Text('✅',
                                      style:
                                          TextStyle(fontSize: 22)),
                                  SizedBox(width: 10),
                                  Text(
                                    'I PICKED IT UP!',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox(key: ValueKey('noPick')),
                ),

                // ANALYZE + SAVE row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFADFF2F),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        elevation: 8,
                        shadowColor: const Color(0xFFADFF2F),
                      ),
                      onPressed: () => _showReport(context),
                      icon: const Text('🔍',
                          style: TextStyle(fontSize: 18)),
                      label: const Text('ANALYZE',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF222222),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: const BorderSide(
                              color: Color(0xFFADFF2F), width: 1.5),
                        ),
                      ),
                      onPressed: _isSaving ? null : _captureAndShare,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('📸',
                              style: TextStyle(fontSize: 18)),
                      label: Text(
                        _isSaving ? 'SAVING...' : 'SAVE SCAN',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────

  /// Small badge in the top-right showing items collected.
  Widget _buildItemBadge() {
    final grade = getCleanupGrade(_itemsCollected);
    final color = getGradeColor(grade);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$_itemsCollected picked up',
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Gold card showing the current mission target.
  Widget _buildMissionPanel({Key? key}) {
    return Container(
      key: key,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.25),
              blurRadius: 18)
        ],
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR MISSION',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick up $_missionFriendlyLabel!',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Then tap the green button ↓',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text('👆', style: TextStyle(fontSize: 22)),
        ],
      ),
    );
  }

  /// Green celebration panel shown briefly after each pickup.
  Widget _buildCelebrationPanel({Key? key}) {
    return Container(
      key: key,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF00E87A).withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E87A), width: 2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF00E87A).withOpacity(0.35),
              blurRadius: 22)
        ],
      ),
      child: Column(
        children: [
          Text(
            _celebrationText,
            style: const TextStyle(
              color: Color(0xFF00E87A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            getCleanupLabel(_itemsCollected),
            style: const TextStyle(
                color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChaosMeters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chaosBar(_felineCategory),
        const SizedBox(height: 6),
        _chaosBar(_floorCategory),
        const SizedBox(height: 6),
        _chaosBar(_splashCategory),
        const SizedBox(height: 6),
        _chaosBar(_furnitureCategory),
        const SizedBox(height: 4),
        Text(
          '${_detectedObjects.length} objects detected',
          style: const TextStyle(
              color: Colors.white38, fontSize: 9, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _chaosBar(PrankCategory cat) {
    return Row(
      children: [
        Text(cat.emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cat.level,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(cat.color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${(cat.level * 100).toInt()}%',
            style: TextStyle(
                color: cat.color,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Right-side badge showing BOTH cleanup grade (primary) and chaos grade.
  Widget _buildGradeBadge() {
    final cleanupGrade = getCleanupGrade(_itemsCollected);
    final cleanupColor = getGradeColor(cleanupGrade);
    final chaosGrade = getChaosGrade(_totalChaos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Primary: cleanup grade (gets BETTER over time)
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cleanupColor.withOpacity(0.15),
            border: Border.all(color: cleanupColor, width: 3),
            boxShadow: [
              BoxShadow(
                  color: cleanupColor.withOpacity(0.4),
                  blurRadius: 12)
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(cleanupGrade,
                  style: TextStyle(
                      color: cleanupColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              Text('CLEAN',
                  style: TextStyle(
                      color: cleanupColor.withOpacity(0.8),
                      fontSize: 7,
                      letterSpacing: 0.8)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        // Secondary: live chaos level
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Colors.white24, width: 1),
          ),
          child: Text(
            'CHAOS $chaosGrade  ${(_totalChaos * 100).toInt()}%',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  // ── Report modal ──────────────────────────────────
  void _showReport(BuildContext context) {
    final cleanupGrade = getCleanupGrade(_itemsCollected);
    final cleanupColor = getGradeColor(cleanupGrade);
    final chaosGrade = getChaosGrade(_totalChaos);
    final chaosColor = getGradeColor(chaosGrade);
    final verdict = getChaosVerdict(
        _felineCategory.level,
        _floorCategory.level,
        _splashCategory.level,
        _furnitureCategory.level);
    final emojis = getChaosEmoji(_totalChaos);
    final topLabels = _latestLabels
        .where((l) => l.confidence > 0.50)
        .take(6)
        .map((l) => l.label)
        .join(', ');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              Text('🏠 PRANK REPORT',
                  style: TextStyle(
                      color: cleanupColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(emojis,
                  style: const TextStyle(fontSize: 28)),

              const SizedBox(height: 16),

              // Two grade boxes side by side
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  _reportGradeBox(
                      'CLEANUP GRADE', cleanupGrade, cleanupColor,
                      subtitle: '$_itemsCollected items picked up'),
                  _reportGradeBox(
                      'CHAOS LEVEL', chaosGrade, chaosColor,
                      subtitle:
                          '${(_totalChaos * 100).toInt()}% messy'),
                ],
              ),

              const SizedBox(height: 12),

              // Progress toward next cleanup grade
              _buildCleanupProgress(cleanupColor),

              if (topLabels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('DETECTED: $topLabels',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 0.5)),
              ],

              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              _reportRow(_felineCategory),
              const SizedBox(height: 8),
              _reportRow(_floorCategory),
              const SizedBox(height: 8),
              _reportRow(_splashCategory),
              const SizedBox(height: 8),
              _reportRow(_furnitureCategory),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(verdict,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.5)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFADFF2F),
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(30)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Future.delayed(
                        const Duration(milliseconds: 200),
                        _captureAndShare);
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('SHARE REPORT',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportGradeBox(String label, String grade, Color color,
      {String subtitle = ''}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.85),
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold)),
          Text(grade,
              style: TextStyle(
                  color: color,
                  fontSize: 34,
                  fontWeight: FontWeight.w900)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  /// Progress bar toward the next cleanup grade inside the report.
  Widget _buildCleanupProgress(Color color) {
    // Thresholds: 1=D, 3=C, 7=B, 12=A, 20=S+
    final thresholds = [0, 1, 3, 7, 12, 20];
    final labels = ['F', 'D', 'C', 'B', 'A', 'S+'];
    int current = 0;
    for (int i = 0; i < thresholds.length - 1; i++) {
      if (_itemsCollected >= thresholds[i]) current = i;
    }

    final nextThreshold = current < thresholds.length - 1
        ? thresholds[current + 1]
        : thresholds.last;
    final currentThreshold = thresholds[current];
    final progress = current >= thresholds.length - 1
        ? 1.0
        : (_itemsCollected - currentThreshold) /
            (nextThreshold - currentThreshold);
    final nextLabel =
        current < labels.length - 1 ? labels[current + 1] : 'MAX';
    final remaining = nextThreshold - _itemsCollected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress to $nextLabel',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              Text(
                  current >= thresholds.length - 1
                      ? 'MAX RANK!'
                      : '$remaining more to go!',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportRow(PrankCategory cat) {
    return Row(
      children: [
        Text(cat.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.name,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cat.level,
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(cat.color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('${(cat.level * 100).toInt()}%',
            style: TextStyle(
                color: cat.color,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────
// BOUNDING BOX PAINTER
// The mission target object gets a gold pulsing highlight;
// all others get the standard colour-coded corners.
// ─────────────────────────────────────────────────
class PrankBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size widgetSize;
  final int? targetId;

  const PrankBoxPainter({
    required this.objects,
    required this.imageSize,
    required this.widgetSize,
    this.targetId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    for (int i = 0; i < objects.length; i++) {
      final DetectedObject obj = objects[i];

      // Determine if this object is the mission target.
      final bool isTarget = targetId != null &&
          (obj.trackingId == targetId ||
              (obj.trackingId == null && -(i + 1) == targetId));

      final String rawLabel = obj.labels.isNotEmpty
          ? obj.labels
              .reduce((a, b) => a.confidence > b.confidence ? a : b)
              .text
          : 'Object';
      final double conf = obj.labels.isNotEmpty
          ? obj.labels
              .reduce((a, b) => a.confidence > b.confidence ? a : b)
              .confidence
          : 0.5;

      final rect = Rect.fromLTRB(
        (obj.boundingBox.left * scaleX).clamp(0, widgetSize.width),
        (obj.boundingBox.top * scaleY).clamp(0, widgetSize.height),
        (obj.boundingBox.right * scaleX).clamp(0, widgetSize.width),
        (obj.boundingBox.bottom * scaleY).clamp(0, widgetSize.height),
      );
      if (rect.width < 10 || rect.height < 10) continue;

      final Color color = isTarget
          ? const Color(0xFFFFD700) // Gold for mission target
          : conf > 0.75
              ? const Color(0xFFFF3366)
              : conf > 0.55
                  ? const Color(0xFFFF6B35)
                  : const Color(0xFFADFF2F);

      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isTarget ? 4.5 : 2.5
        ..color = color;

      final double cornerLen =
          (rect.width * 0.20).clamp(12.0, 32.0);
      _drawCorners(canvas, rect, paint, cornerLen);

      // Gold tinted fill for the mission target.
      if (isTarget) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = const Color(0xFFFFD700).withOpacity(0.09),
        );
      }

      // Label chip.
      final String labelText = isTarget
          ? '🎯 PICK THIS UP!'
          : '${getPrankLabel(rawLabel)}  ${(conf * 100).toInt()}%';

      const double pad = 4.0;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: isTarget ? Colors.black : Colors.white,
            fontSize: isTarget ? 12 : 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: widgetSize.width - rect.left);

      double labelTop = rect.top - tp.height - pad * 2 - 2;
      if (labelTop < 0) labelTop = rect.top + 2;

      final bgRect = Rect.fromLTWH(
          rect.left, labelTop, tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = color.withOpacity(0.90),
      );
      tp.paint(canvas, Offset(bgRect.left + pad, bgRect.top + pad));
    }
  }

  void _drawCorners(
      Canvas canvas, Rect rect, Paint paint, double len) {
    canvas.drawLine(
        rect.topLeft, rect.topLeft.translate(len, 0), paint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft.translate(0, len), paint);
    canvas.drawLine(
        rect.topRight, rect.topRight.translate(-len, 0), paint);
    canvas.drawLine(
        rect.topRight, rect.topRight.translate(0, len), paint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft.translate(len, 0), paint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft.translate(0, -len), paint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight.translate(-len, 0), paint);
    canvas.drawLine(
        rect.bottomRight, rect.bottomRight.translate(0, -len), paint);
  }

  @override
  bool shouldRepaint(covariant PrankBoxPainter old) =>
      old.objects != objects || old.targetId != targetId;
}