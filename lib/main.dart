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
// LABEL CLASSIFIER
// Uses both object-detection labels AND image-labeler labels.
// Image labeler returns 400+ categories including:
//   Cat, Dog, Toy, Toy vehicle, Vehicle, Furniture, Clutter,
//   Clothing, Shelf, Bottle, Cup, etc.
// ─────────────────────────────────────────────────

// Returns 0.0–1.0 boost for each category based on a label string.
// Called for EVERY label from BOTH detectors.
double felineBoost(String l) {
  if (l.contains('cat') || l.contains('feline')) return 0.18;
  if (l.contains('dog') || l.contains('canine') || l.contains('puppy')) return 0.18;
  if (l.contains('pet') || l.contains('kitten') || l.contains('animal')) return 0.10;
  if (l.contains('mammal') || l.contains('wildlife')) return 0.06;
  return 0.0;
}

double floorBoost(String l) {
  // Toys
  if (l.contains('lego') || l.contains('duplo')) return 0.20;
  if (l.contains('toy vehicle') || l.contains('toy car') || l.contains('toy truck')) return 0.20;
  if (l.contains('toy') || l.contains('doll') || l.contains('action figure')) return 0.15;
  if (l.contains('figurine') || l.contains('miniature')) return 0.12;
  if (l.contains('ball') || l.contains('balloon')) return 0.15;
  if (l.contains('puzzle') || l.contains('board game') || l.contains('game')) return 0.12;
  // Vehicles (toy scale)
  if (l.contains('vehicle') || l.contains('truck') || l.contains('car') ||
      l.contains('crane') || l.contains('construction') || l.contains('excavator')) return 0.15;
  if (l.contains('train') || l.contains('locomotive') || l.contains('aircraft') ||
      l.contains('boat') || l.contains('ship')) return 0.12;
  // Footwear
  if (l.contains('shoe') || l.contains('boot') || l.contains('sneaker') ||
      l.contains('footwear') || l.contains('sandal') || l.contains('slipper')) return 0.15;
  // Clutter / obstacles
  if (l.contains('clutter') || l.contains('mess') || l.contains('disorder')) return 0.18;
  if (l.contains('box') || l.contains('package') || l.contains('carton')) return 0.12;
  if (l.contains('bag') || l.contains('backpack') || l.contains('suitcase') ||
      l.contains('luggage')) return 0.12;
  if (l.contains('book') || l.contains('paper') || l.contains('magazine')) return 0.08;
  if (l.contains('sporting') || l.contains('sport') || l.contains('equipment')) return 0.10;
  if (l.contains('clothing') || l.contains('cloth') || l.contains('textile') ||
      l.contains('laundry') || l.contains('garment') || l.contains('shirt') ||
      l.contains('sock') || l.contains('pants') || l.contains('jacket')) return 0.12;
  if (l.contains('tool') || l.contains('hardware')) return 0.10;
  if (l.contains('household') || l.contains('goods') || l.contains('object')) return 0.06;
  return 0.0;
}

double splashBoost(String l) {
  if (l.contains('bottle') || l.contains('water bottle')) return 0.18;
  if (l.contains('cup') || l.contains('mug') || l.contains('glass') || l.contains('tumbler')) return 0.18;
  if (l.contains('bowl') || l.contains('bucket') || l.contains('jug')) return 0.15;
  if (l.contains('liquid') || l.contains('drink') || l.contains('beverage') ||
      l.contains('juice') || l.contains('water')) return 0.12;
  if (l.contains('spray') || l.contains('squirt') || l.contains('hose')) return 0.15;
  if (l.contains('sink') || l.contains('bathtub') || l.contains('toilet')) return 0.10;
  if (l.contains('food') || l.contains('fruit') || l.contains('banana') ||
      l.contains('orange') || l.contains('apple') || l.contains('snack')) return 0.12;
  return 0.0;
}

double furnitureBoost(String l) {
  if (l.contains('chair') || l.contains('sofa') || l.contains('couch') ||
      l.contains('armchair') || l.contains('stool') || l.contains('bench')) return 0.15;
  if (l.contains('table') || l.contains('desk') || l.contains('counter')) return 0.15;
  if (l.contains('shelf') || l.contains('bookcase') || l.contains('bookshelf') ||
      l.contains('cabinet') || l.contains('wardrobe') || l.contains('dresser')) return 0.12;
  if (l.contains('furniture') || l.contains('rack') || l.contains('stand')) return 0.10;
  if (l.contains('bed') || l.contains('mattress') || l.contains('pillow')) return 0.08;
  return 0.0;
}

// Human-readable label for bounding boxes.
// Shows ACTUAL ML Kit label text in brackets so you can see what it detected.
String getPrankLabel(String rawLabel) {
  final l = rawLabel.toLowerCase();
  if (felineBoost(l) > 0) return '🐱 ${rawLabel.toUpperCase()}';
  if (l.contains('lego') || l.contains('block') || l.contains('brick')) return '🧱 LEGO MINEFIELD';
  if (l.contains('toy vehicle') || l.contains('toy car') || l.contains('toy truck')) return '🚗 WHEELED MENACE';
  if (l.contains('toy') || l.contains('doll') || l.contains('figurine')) return '🪀 TOY TRAP';
  if (l.contains('ball')) return '⚽ ANKLE BREAKER';
  if (l.contains('shoe') || l.contains('boot') || l.contains('footwear')) return '👟 STAIR HAZARD';
  if (l.contains('clothing') || l.contains('cloth') || l.contains('laundry')) return '👕 TRIP FABRIC';
  if (l.contains('vehicle') || l.contains('truck') || l.contains('car') || l.contains('crane')) return '🚗 WHEELED MENACE';
  if (l.contains('clutter') || l.contains('mess')) return '⚠️ CHAOS DETECTED';
  if (l.contains('box') || l.contains('package')) return '📦 STUBBED TOE BAIT';
  if (l.contains('bottle') || l.contains('cup') || l.contains('glass')) return '💦 SPLASH ZONE';
  if (l.contains('food') || l.contains('fruit')) return '🍌 SLIP BAIT';
  if (l.contains('chair') || l.contains('table') || l.contains('furniture')) return '🪑 SHIN DESTROYER';
  if (l.contains('shelf') || l.contains('bookcase')) return '📚 FALLING HAZARD';
  if (l.contains('person') || l.contains('human')) return '👤 INTRUDER!';
  // Fallback: show what ML Kit actually said
  return '⚠️ ${rawLabel.toUpperCase()}';
}

// ─────────────────────────────────────────────────
// VERDICT & GRADE
// ─────────────────────────────────────────────────
String getChaosVerdict(double feline, double floor, double splash, double furniture) {
  final total = (feline + floor + splash + furniture) / 4.0;
  final hasCat = feline > 0.45;
  final hasFloor = floor > 0.45;
  final hasSplash = splash > 0.45;
  final hasFurniture = furniture > 0.45;

  if (hasCat && hasFloor && hasSplash) {
    return "🏆 GRAND SLAM PRANK HOUSE! Kevin McCallister would weep with pride. You've achieved LEGENDARY chaos status.";
  }
  if (hasFloor && total > 0.70) {
    return "☠️ The floor is basically a LEGO minefield wrapped in toy trucks. EMS has been pre-dialed. Godspeed.";
  }
  if (hasCat && hasFloor) {
    return "😈 Cats + floor traps = a lethal combo. Midnight trip to the ER is GUARANTEED tonight.";
  }
  if (hasCat) {
    return "🐱 Your cat has clearly been planning something. Those innocent eyes are DECEIVING you.";
  }
  if (hasSplash && hasFloor) {
    return "💦 Wet floors + scattered obstacles = lawsuit waiting to happen. CERTIFIED DANGER ZONE.";
  }
  if (hasFurniture && hasFloor) {
    return "🪑 Sharp corners EVERYWHERE. The furniture is conspiring with the clutter against your shins.";
  }
  if (hasFloor) {
    return "🧱 The floor has achieved sentience and chosen violence. Shoes mandatory. Socks forbidden.";
  }
  if (total > 0.65) return "☠️ EXTREME DANGER. Abandon all hope, ye who enter barefoot.";
  if (total > 0.45) return "😬 Risky in here. Proceed with maximum socks and a prayer to the god of shins.";
  if (total > 0.25) return "🤔 Some prank potential detected. Stay alert, stay alive.";
  return "😌 Surprisingly safe. Either it's genuinely tidy, or the pranks are VERY well hidden.";
}

String getChaosEmoji(double total) {
  if (total > 0.75) return '🏆💀😱🔥';
  if (total > 0.55) return '😱⚠️🚨';
  if (total > 0.35) return '😬🤔⚠️';
  if (total > 0.18) return '🙂👀';
  return '😌✅';
}

String getChaosGrade(double total) {
  if (total > 0.80) return 'S+';
  if (total > 0.65) return 'A';
  if (total > 0.50) return 'B';
  if (total > 0.35) return 'C';
  if (total > 0.20) return 'D';
  return 'F';
}

Color getGradeColor(String grade) {
  switch (grade) {
    case 'S+': return const Color(0xFFFF0055);
    case 'A':  return const Color(0xFFFF6B35);
    case 'B':  return const Color(0xFFFFD700);
    case 'C':  return const Color(0xFFADFF2F);
    case 'D':  return const Color(0xFF00BFFF);
    default:   return Colors.grey;
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

  // ML Kit — Object Detector (bounding boxes)
  ObjectDetector? _objectDetector;
  // ML Kit — Image Labeler (rich whole-frame labels)
  ImageLabeler? _imageLabeler;

  bool _canProcess = false;
  bool _isBusy = false;
  bool _cameraReady = false;
  int _frameCount = 0;

  List<DetectedObject> _detectedObjects = [];
  // Latest image labels for debug display
  List<ImageLabel> _latestLabels = [];

  final PrankCategory _felineCategory = PrankCategory(
      emoji: '🐱', name: 'FELINE AGENTS', color: const Color(0xFFFF6B35));
  final PrankCategory _floorCategory = PrankCategory(
      emoji: '🧱', name: 'FLOOR TRAPS', color: const Color(0xFFFF3366));
  final PrankCategory _splashCategory = PrankCategory(
      emoji: '💦', name: 'SPLASH ZONES', color: const Color(0xFF00CFFF));
  final PrankCategory _furnitureCategory = PrankCategory(
      emoji: '🪑', name: 'SHIN DESTROYERS', color: const Color(0xFFFFD700));

  bool _isSaving = false;
  bool _showDebugLabels = false; // toggle to see raw ML labels

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _initDetectors();

    _scanController = AnimationController(
        duration: const Duration(seconds: 2), vsync: this)
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
    // Object detector for bounding boxes
    _objectDetector = ObjectDetector(options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ));

    // Image labeler — 400+ categories, much richer than object detection
    // Uses the default MobileNet model bundled with ML Kit
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

  // ── Main frame processor ──────────────────────────
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

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      // ── 1. Object detection every frame (for bounding boxes) ──
      final objects = _objectDetector != null
          ? await _objectDetector!.processImage(inputImage)
          : <DetectedObject>[];

      // ── 2. Image labeling every 8 frames (rich category labels) ──
      List<ImageLabel> labels = [];
      if (_frameCount % 8 == 0 && _imageLabeler != null) {
        labels = await _imageLabeler!.processImage(inputImage);
      } else {
        labels = _latestLabels; // reuse last result
      }

      if (mounted) {
        setState(() {
          _detectedObjects = objects;
          if (_frameCount % 8 == 0) _latestLabels = labels;

          // ── Slow decay each frame ──
          const decay = 0.003;
          _felineCategory.level   = (_felineCategory.level   - decay).clamp(0.1, 1.0);
          _floorCategory.level    = (_floorCategory.level    - decay).clamp(0.1, 1.0);
          _splashCategory.level   = (_splashCategory.level   - decay).clamp(0.1, 1.0);
          _furnitureCategory.level = (_furnitureCategory.level - decay).clamp(0.1, 1.0);

          // ── SCORING STRATEGY 1: Object COUNT as chaos proxy ──
          // Each detected object = confirmed hazard, regardless of label.
          // This guarantees a messy room always scores high.
          final count = objects.length;
          if (count > 0) {
            // More objects → bigger boost. Caps at 8 objects for max boost.
            final countBoost = (count * 0.025).clamp(0.0, 0.20);
            _floorCategory.level =
                (_floorCategory.level + countBoost).clamp(0.1, 1.0);
          }

          // ── SCORING STRATEGY 2: Object detection labels ──
          for (var obj in objects) {
            for (var label in obj.labels) {
              if (label.confidence < 0.30) continue;
              final l = label.text.toLowerCase();
              final w = label.confidence; // weight by confidence
              _felineCategory.level   = (_felineCategory.level   + felineBoost(l) * w).clamp(0.1, 1.0);
              _floorCategory.level    = (_floorCategory.level    + floorBoost(l)  * w).clamp(0.1, 1.0);
              _splashCategory.level   = (_splashCategory.level   + splashBoost(l) * w).clamp(0.1, 1.0);
              _furnitureCategory.level = (_furnitureCategory.level + furnitureBoost(l) * w).clamp(0.1, 1.0);
            }
          }

          // ── SCORING STRATEGY 3: Image labeler (richest, most accurate) ──
          // These run every 8 frames so we apply a larger boost per hit.
          if (_frameCount % 8 == 0) {
            for (var label in labels) {
              if (label.confidence < 0.40) continue;
              final l = label.label.toLowerCase();
              final w = label.confidence;
              _felineCategory.level   = (_felineCategory.level   + felineBoost(l) * w * 1.5).clamp(0.1, 1.0);
              _floorCategory.level    = (_floorCategory.level    + floorBoost(l)  * w * 1.5).clamp(0.1, 1.0);
              _splashCategory.level   = (_splashCategory.level   + splashBoost(l) * w * 1.5).clamp(0.1, 1.0);
              _furnitureCategory.level = (_furnitureCategory.level + furnitureBoost(l) * w * 1.5).clamp(0.1, 1.0);
            }
          }
        });
      }
    } catch (e) {
      debugPrint("ML Error: $e");
    }
    _isBusy = false;
  }

  double get _totalChaos =>
      (_felineCategory.level + _floorCategory.level +
          _splashCategory.level + _furnitureCategory.level) / 4.0;

  // ── Save / Share ──────────────────────────────────
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
        text: '🏠 How Pranked My House? CHAOS GRADE: ${getChaosGrade(_totalChaos)}\n${getChaosEmoji(_totalChaos)}',
        subject: 'My House Prank Report',
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
                  ),
                ),

                // Gradients
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(height: 120,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(height: 220,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xEE000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // Title
                const Positioned(
                  top: 50, left: 0, right: 0,
                  child: Center(
                    child: Text(
                      '🏠 HOW PRANKED MY HOUSE',
                      style: TextStyle(
                        color: Color(0xFFADFF2F),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        shadows: [Shadow(blurRadius: 12, color: Color(0xFFADFF2F))],
                      ),
                    ),
                  ),
                ),

                // Green scan line
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, _) => Positioned(
                    top: size.height * _scanAnimation.value,
                    left: 0, right: 0,
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
                        boxShadow: [BoxShadow(
                          color: const Color(0xFFADFF2F).withOpacity(0.7),
                          blurRadius: 22, spreadRadius: 7,
                        )],
                      ),
                    ),
                  ),
                ),

                // Chaos meters (bottom-left)
                Positioned(
                  bottom: 130, left: 16,
                  child: _buildChaosMeters(),
                ),

                // Grade badge (bottom-right)
                Positioned(
                  bottom: 130, right: 16,
                  child: _buildGradeBadge(),
                ),

                // Debug label strip (tap title to toggle)
                if (_showDebugLabels)
                  Positioned(
                    top: 90, left: 0, right: 0,
                    child: Container(
                      color: Colors.black.withOpacity(0.75),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

          // Title tap area to toggle debug
          Positioned(
            top: 40, left: 0, right: 0, height: 45,
            child: GestureDetector(
              onDoubleTap: () =>
                  setState(() => _showDebugLabels = !_showDebugLabels),
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),

          // Buttons
          Positioned(
            bottom: 36, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFADFF2F),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 8,
                    shadowColor: const Color(0xFFADFF2F),
                  ),
                  onPressed: () => _showChaosReport(context),
                  icon: const Text('🔍', style: TextStyle(fontSize: 18)),
                  label: const Text('ANALYZE',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF222222),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: const BorderSide(color: Color(0xFFADFF2F), width: 1.5),
                    ),
                  ),
                  onPressed: _isSaving ? null : _captureAndShare,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text('📸', style: TextStyle(fontSize: 18)),
                  label: Text(
                    _isSaving ? 'SAVING...' : 'SAVE SCAN',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────
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
                color: cat.color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildGradeBadge() {
    final grade = getChaosGrade(_totalChaos);
    final color = getGradeColor(grade);
    return Container(
      width: 70, height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 3),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(grade, style: TextStyle(
              color: color, fontSize: 22, fontWeight: FontWeight.w900)),
          Text('CHAOS', style: TextStyle(
              color: color.withOpacity(0.8), fontSize: 8, letterSpacing: 1)),
        ],
      ),
    );
  }

  void _showChaosReport(BuildContext context) {
    final grade = getChaosGrade(_totalChaos);
    final gradeColor = getGradeColor(grade);
    final verdict = getChaosVerdict(
        _felineCategory.level, _floorCategory.level,
        _splashCategory.level, _furnitureCategory.level);
    final emojis = getChaosEmoji(_totalChaos);

    // Top image labels for the report
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('🏠 PRANK REPORT',
                style: TextStyle(color: gradeColor, fontSize: 22,
                    fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 4),
            Text(emojis, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: gradeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gradeColor, width: 2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('CHAOS GRADE: ', style: TextStyle(
                    color: gradeColor.withOpacity(0.8), fontSize: 14)),
                Text(grade, style: TextStyle(
                    color: gradeColor, fontSize: 32, fontWeight: FontWeight.w900)),
              ]),
            ),
            if (topLabels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('DETECTED: $topLabels',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, letterSpacing: 0.5)),
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(verdict,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.5)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFADFF2F),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Future.delayed(
                      const Duration(milliseconds: 200), _captureAndShare);
                },
                icon: const Icon(Icons.share_rounded),
                label: const Text('SHARE PRANK REPORT',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
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
              Text(cat.name, style: const TextStyle(
                  color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cat.level,
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(cat.color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('${(cat.level * 100).toInt()}%',
            style: TextStyle(
                color: cat.color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────
// BOUNDING BOX PAINTER
// Shows ACTUAL ML Kit label text so you know what was detected.
// ─────────────────────────────────────────────────
class PrankBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size widgetSize;

  const PrankBoxPainter(
      {required this.objects,
        required this.imageSize,
        required this.widgetSize});

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    for (final DetectedObject object in objects) {
      // Use best label if available, else show as "Object"
      final String rawLabel = object.labels.isNotEmpty
          ? object.labels
          .reduce((a, b) => a.confidence > b.confidence ? a : b)
          .text
          : 'Object';
      final double confidence = object.labels.isNotEmpty
          ? object.labels
          .reduce((a, b) => a.confidence > b.confidence ? a : b)
          .confidence
          : 0.5;

      // Draw ALL detected objects (no confidence cutoff on display)
      final rect = Rect.fromLTRB(
        (object.boundingBox.left * scaleX).clamp(0, widgetSize.width),
        (object.boundingBox.top * scaleY).clamp(0, widgetSize.height),
        (object.boundingBox.right * scaleX).clamp(0, widgetSize.width),
        (object.boundingBox.bottom * scaleY).clamp(0, widgetSize.height),
      );
      if (rect.width < 10 || rect.height < 10) continue;

      final color = confidence > 0.75
          ? const Color(0xFFFF3366)
          : confidence > 0.55
          ? const Color(0xFFFF6B35)
          : const Color(0xFFADFF2F);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = color;

      final cornerLen = (rect.width * 0.18).clamp(12.0, 28.0);
      _drawCorners(canvas, rect, paint, cornerLen);

      // Label: use our prank translation
      final displayLabel = getPrankLabel(rawLabel);
      final pct = confidence > 0.01 ? '  ${(confidence * 100).toInt()}%' : '';
      final labelText = '$displayLabel$pct';

      const pad = 4.0;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: widgetSize.width - rect.left);

      double labelTop = rect.top - tp.height - pad * 2 - 2;
      if (labelTop < 0) labelTop = rect.top + 2;

      final bgRect = Rect.fromLTWH(
          rect.left, labelTop, tp.width + pad * 2, tp.height + pad * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = color.withOpacity(0.85),
      );
      tp.paint(canvas, Offset(bgRect.left + pad, bgRect.top + pad));
    }
  }

  void _drawCorners(Canvas canvas, Rect rect, Paint paint, double len) {
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, len), paint);
    canvas.drawLine(rect.topRight, rect.topRight.translate(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, len), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -len), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -len), paint);
  }

  @override
  bool shouldRepaint(covariant PrankBoxPainter oldDelegate) =>
      oldDelegate.objects != objects;
}