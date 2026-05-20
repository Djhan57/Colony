import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ColonyApp());
}

class ColonyApp extends StatelessWidget {
  const ColonyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColonyAI Mobile',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF009688), // Couleur "Teal" scientifique
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  
  // IP locale de votre ordinateur Legion 5 (à modifier selon votre réseau Wi-Fi)
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.100");

  // Données géométriques ajustées par l'utilisateur pour la boîte de Pétri
  Offset _petriCenter = Offset.zero;
  double _petriRadius = 150.0;
  bool _initializedGeometry = false;

  // États de l'application
  bool _isLoading = false;
  bool _showOverlays = true;

  // Données de réponse de l'API FastAPI
  List<List<Offset>> _coloniesPolygons = [];
  Map<String, dynamic>? _apiResponse;

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _initializedGeometry = false; // Reset de la géométrie pour la nouvelle image
        _coloniesPolygons.clear();
        _apiResponse = null;
      });
    }
  }

  // Envoi de la requête Multipart au serveur FastAPI
  Future<void> _sendToBackend() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final ip = _ipController.text.trim();
      final uri = Uri.parse("http://$ip:8000/detect");

      var request = http.MultipartRequest('POST', uri);
      
      // Ajout de l'image
      request.files.add(await http.MultipartFile.fromPath('file', _image!.path));
      
      // Configuration des paramètres
      request.fields['mode'] = 'AUTO'; // On utilise Detectron2 en arrière-plan
      request.fields['score_threshold'] = '0.50';
      
      // Note : On pourrait envoyer _petriCenter et _petriRadius pour guider l'analyse 
      // si l'API est configurée pour recevoir ces coordonnées directes. 
      // Ici l'API fait sa propre transformée de Hough en arrière-plan.

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _parseResults(data);
      } else {
        _showErrorDialog("Erreur du serveur (${response.statusCode})", "Vérifiez que le serveur tourne et que l'IP est correcte.");
      }
    } catch (e) {
      _showErrorDialog("Erreur de connexion", "Impossible de joindre le serveur à l'adresse http://${_ipController.text}:8000.\n\nDétails : $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _parseResults(Map<String, dynamic> data) {
    List<List<Offset>> parsedPolygons = [];
    if (data['colonies'] != null) {
      for (var colony in data['colonies']) {
        List<Offset> poly = [];
        for (var pt in colony['points']) {
          poly.add(Offset(pt[0].toDouble(), pt[1].toDouble()));
        }
        parsedPolygons.add(poly);
      }
    }

    setState(() {
      _apiResponse = data;
      _coloniesPolygons = parsedPolygons;
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ColonyAI Mobile', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (_image != null && _apiResponse != null)
            IconButton(
              icon: Icon(_showOverlays ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _showOverlays = !_showOverlays;
                });
              },
              tooltip: "Masquer les calques",
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Configuration de la connexion
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, color: Colors.teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: "IP du Serveur de Calcul (FastAPI)",
                            hintText: "Ex: 192.168.1.50",
                            border: InputBorder.none,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Zone d'affichage et manipulation de l'image
              if (_image == null)
                Container(
                  height: 350,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.biotech, size: 64, color: Colors.teal),
                        SizedBox(height: 16),
                        Text(
                          "Prenez ou chargez une photo\nde boîte de Pétri pour commencer.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final containerWidth = constraints.maxWidth;
                    final containerHeight = 350.0;

                    // Initialisation des coordonnées du cercle au milieu du canvas
                    if (!_initializedGeometry) {
                      _petriCenter = Offset(containerWidth / 2, containerHeight / 2);
                      _petriRadius = containerWidth * 0.35;
                      _initializedGeometry = true;
                    }

                    return Container(
                      height: containerHeight,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.withOpacity(0.5)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // 1. L'image de fond
                            Positioned.fill(
                              child: Image.file(
                                _image!,
                                fit: BoxFit.contain,
                              ),
                            ),
                            // 2. Le Canvas Interactif (Dessin par-dessus)
                            if (_showOverlays)
                              Positioned.fill(
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    // Permet de déplacer le cercle au doigt
                                    setState(() {
                                      _petriCenter += details.delta;
                                    });
                                  },
                                  child: CustomPaint(
                                    painter: PetriAndColonyPainter(
                                      center: _petriCenter,
                                      radius: _petriRadius,
                                      polygons: _coloniesPolygons,
                                    ),
                                  ),
                                ),
                              ),
                            
                            if (_isLoading)
                              const Positioned.fill(
                                child: Container(
                                  color: Colors.black54,
                                  child: Center(
                                    child: CircularProgressIndicator(color: Colors.teal),
                                  ),
                                ),
                              )
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // Contrôles pour ajuster la boîte de Pétri en mode édition
              if (_image != null && _apiResponse == null && !_isLoading) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      const Text("Rayon :"),
                      Expanded(
                        child: Slider(
                          value: _petriRadius,
                          min: 50.0,
                          max: 250.0,
                          activeColor: Colors.teal,
                          onChanged: (val) {
                            setState(() {
                              _petriRadius = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    "💡 Glissez votre doigt sur l'image pour aligner le cercle rouge sur la boîte.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Boutons d'action principaux
              if (_image == null) ...[
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Prendre une Photo"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Choisir dans la Galerie"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ] else ...[
                if (_apiResponse == null)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendToBackend,
                    icon: const Icon(Icons.analytics),
                    label: const Text("Lancer l'Analyse"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  Card(
                    color: Colors.teal.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            "Analyse Terminée ! 🎉",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Nombre de colonies détectées : ${_coloniesPolygons.length}",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _isLoading ? null : () {
                    setState(() {
                      _image = null;
                      _coloniesPolygons.clear();
                      _apiResponse = null;
                    });
                  },
                  icon: const Icon(Icons.refresh, color: Colors.redAccent),
                  label: const Text("Recommencer", style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Peintre vectoriel personnalisé pour dessiner le cercle et les colonies
class PetriAndColonyPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final List<List<Offset>> polygons;

  PetriAndColonyPainter({
    required this.center,
    required this.radius,
    required this.polygons,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dessin du cercle guide (Rouge en pointillés)
    final petriPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius, petriPaint);

    // 2. Dessin des colonies (Polygones verts)
    if (polygons.isNotEmpty) {
      final polyPaint = Paint()
        ..color = const Color(0x3300FF00) // Vert très transparent (remplissage)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = const Color(0xFF00FF00) // Vert uni pour la bordure
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (int i = 0; i < polygons.length; i++) {
        final points = polygons[i];
        if (points.isEmpty) continue;

        final path = Path()..moveTo(points[0].dx, points[0].dy);
        for (int j = 1; j < points.length; j++) {
          path.lineTo(points[j].dx, points[j].dy);
        }
        path.close();

        // On dessine le polygone
        canvas.drawPath(path, polyPaint);
        canvas.drawPath(path, strokePaint);

        // Ajout du numéro de la colonie au centre du polygone
        _drawLabel(canvas, points, i + 1);
      }
    }
  }

  // Calcul du centroïde simple d'un polygone pour y placer le texte numérique
  void _drawLabel(Canvas canvas, List<Offset> points, int index) {
    double sumX = 0;
    double sumY = 0;
    for (var pt in points) {
      sumX += pt.dx;
      sumY += pt.dy;
    }
    final centerPt = Offset(sumX / points.length, sumY / points.length);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$index',
        style: const TextStyle(
          color: Colors.yellow,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, centerPt - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant PetriAndColonyPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radius != radius ||
        oldDelegate.polygons != polygons;
  }
}