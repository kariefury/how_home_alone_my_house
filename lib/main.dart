import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const HowHomeAloneApp());
}

class HowHomeAloneApp extends StatelessWidget {
  const HowHomeAloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFADFF2F),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const TrapScannerHome(),
    );
  }
}

class TrapScannerHome extends StatefulWidget {
  const TrapScannerHome({super.key});

  @override
  State<TrapScannerHome> createState() => _TrapScannerHomeState();
}

class _TrapScannerHomeState extends State<TrapScannerHome> with SingleTickerProviderStateMixin {
  late CameraController controller;
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  // AI Tools
  ObjectDetector? _objectDetector;
  bool _canProcess = false;
  bool _isBusy = false;
  List<DetectedObject> _detectedObjects = [];

  // Radar Danger Levels
  double felineLevel = 0.1;
  double floorLevel = 0.1;
  double airLevel = 0.1;

  @override
  void initState() {
    super.initState();

    // 1. Setup Camera (Medium res is best for AI speed)
    controller = CameraController(_cameras[0], ResolutionPreset.medium, enableAudio: false);
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.startImageStream((CameraImage image) => _processImage(image));
      setState(() {});
    });

    _initializeDetector();

    _scanController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(_scanController);
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
    _canProcess = true;
  }

  @override
  void dispose() {
    controller.dispose();
    _scanController.dispose();
    _objectDetector?.close();
    super.dispose();
  }

  void _processImage(CameraImage image) async {
    if (!_canProcess || _isBusy || _objectDetector == null) return;
    _isBusy = true;

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

      final objects = await _objectDetector!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _detectedObjects = objects; // Update our list for the painter
          for (var obj in objects) {
            for (var label in obj.labels) {
              String text = label.text.toLowerCase();
              if (text.contains('cat') || text.contains('dog')) {
                felineLevel = (felineLevel + 0.05).clamp(0.1, 1.0);
              } else if (text.contains('toy') || text.contains('shoe') || text.contains('box')) {
                floorLevel = (floorLevel + 0.05).clamp(0.1, 1.0);
              } else if (text.contains('bottle') || text.contains('cup')) {
                airLevel = (airLevel + 0.05).clamp(0.1, 1.0);
              }
            }
          }
          // Slow decay
          felineLevel = (felineLevel - 0.005).clamp(0.1, 1.0);
          floorLevel = (floorLevel - 0.005).clamp(0.1, 1.0);
          airLevel = (airLevel - 0.005).clamp(0.1, 1.0);
        });
      }
    } catch (e) { debugPrint("AI Error: $e"); }
    _isBusy = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFADFF2F))));
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // LAYER 1: The Camera (Wrapped to prevent stretching)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover, // This crops the sides but keeps everything in proportion
              child: SizedBox(
                width: controller.value.previewSize!.height,
                height: controller.value.previewSize!.width,
                child: CameraPreview(controller),
              ),
            ),
          ),

          // LAYER 2: BOUNDING BOXES (The Custom Painter)
          CustomPaint(
            painter: TrapBoxPainter(
              objects: _detectedObjects,
              imageSize: Size(
                controller.value.previewSize!.height,
                controller.value.previewSize!.width,
              ),
              widgetSize: size,
            ),
          ),

          // LAYER 3: Radar
          _buildHazardRadar(),

          // LAYER 4: Scan Line
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              return Positioned(
                top: size.height * _scanAnimation.value,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFADFF2F),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFADFF2F).withOpacity(0.9),
                        blurRadius: 25,
                        spreadRadius: 8,
                      )
                    ],
                  ),
                ),
              );
            },
          ),

          // LAYER 5: Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFADFF2F),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () => _showChaosReport(context),
                icon: const Icon(Icons.radar),
                label: const Text("ANALYZE CHAOS"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardRadar() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _radarRing(size: 280, value: felineLevel, label: "FELINE CHAOS"),
          _radarRing(size: 200, value: floorLevel, label: "FLOOR TRAPS"),
          _radarRing(size: 120, value: airLevel, label: "AIRBORNE"),
          const Icon(Icons.radar, color: Color(0xFFADFF2F), size: 30),
        ],
      ),
    );
  }

  Widget _radarRing({required double size, required double value, required String label}) {
    return Opacity(
      opacity: 0.5,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: value,
              strokeWidth: 6,
              color: const Color(0xFFADFF2F),
              backgroundColor: Colors.white10,
            ),
            Transform.translate(
              offset: Offset(0, -(size / 2) - 15),
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFFADFF2F), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChaosReport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 250,
        child: Column(
          children: [
            const Text("CHAOS REPORT", style: TextStyle(color: Color(0xFFADFF2F), fontSize: 24, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            Text("FELINE ACTIVITY: ${(felineLevel * 100).toInt()}%", style: const TextStyle(fontSize: 16)),
            Text("TRAP DENSITY: ${(floorLevel * 100).toInt()}%", style: const TextStyle(fontSize: 16)),
            const Spacer(),
            const Text("VERDICT: STAY OUT, YA FILTHY ANIMAL!", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// THE NEW CUSTOM PAINTER: Draws neon boxes around detected objects
class TrapBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize; // The AI's resolution (e.g., 480x640)
  final Size widgetSize; // Your actual phone screen size

  TrapBoxPainter({required this.objects, required this.imageSize, required this.widgetSize});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFFADFF2F);

    // Calculate how much to scale the AI coordinates to match the screen
    // Since the camera is usually rotated 90 deg, we swap width and height here
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    for (DetectedObject object in objects) {
      // Adjust coordinates based on the scale factors
      final rect = Rect.fromLTRB(
        object.boundingBox.left * scaleX,
        object.boundingBox.top * scaleY,
        object.boundingBox.right * scaleX,
        object.boundingBox.bottom * scaleY,
      );

      // Draw the box
      canvas.drawRect(rect, paint);

      // Draw Labels - ensuring they stay inside the screen
      for (Label label in object.labels) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: "${label.text.toUpperCase()} (${(label.confidence * 100).toInt()}%)",
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xFFADFF2F), // Neon background for readability
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        // Draw label background slightly above the box
        textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}