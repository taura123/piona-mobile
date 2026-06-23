import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OnDeviceOcrResult {
  const OnDeviceOcrResult({
    required this.fullText,
    required this.lines,
  });

  final String fullText;
  final List<String> lines;
}

class OnDeviceOcr {
  OnDeviceOcr._();

  static Future<OnDeviceOcrResult> recognizeTextFromImagePath(
    String imagePath,
  ) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      final lines = <String>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) lines.add(t);
        }
      }
      final fullText = recognized.text.trim();
      return OnDeviceOcrResult(fullText: fullText, lines: lines);
    } finally {
      await recognizer.close();
    }
  }
}

