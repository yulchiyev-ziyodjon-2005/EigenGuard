import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:typed_data';

import '../services/settings_service.dart';

/// ChatMessage: Foydalanuvchi va AI o'rtasidagi muloqot xabari
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? attachmentBytes;
  final String? attachmentType; // 'image/jpeg', 'application/pdf', etc.

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.attachmentBytes,
    this.attachmentType,
  });
}

/// Sanoat anomaliyalarini aniqlovchi va xulosalar beruvchi AI Assistant (Gemini LLM Integratsiyalashgan)
class AiAssistantService {
  late GenerativeModel _model;
  late ChatSession _chat;
  String _currentApiKey = '';

  // Joriy uskuna xolati (Context)
  double _latestAmp = 0.0;
  double _latestFreq = 0.0;
  double _latestRisk = 0.0;
  String _latestObjectName = "Noma'lum uskuna";
  // §6.4 Predictive (RUL)
  double _latestHoursToCritical = -1.0;
  String _latestTrend = 'BARQAROR';
  // Material profili (Phase 1)
  String _latestMaterialName = 'Universal';
  String _latestMaterialTechnical = 'Generic / Unknown';
  List<String> _latestFailureModes = const [];

  // Chat tarixidagi xabarlar
  final List<ChatMessage> _messages = [];

  AiAssistantService() {
    _initModel();
  }

  void _initModel() {
    _currentApiKey = SettingsService().geminiApiKey;
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _currentApiKey.isNotEmpty ? _currentApiKey : 'MISSING_API_KEY',
      systemInstruction: Content.system(
        "Sen ISO 10816-3 standartida ishlovchi sanoat tebranishlari bo'yicha Bosh Muhandissan. "
        "ISMING: EigenGuard AI Copilot. "
        "XARAKTERING: Jiddiy, professional, qisqa va aniq gapiradigan muhandis. "
        "HECH QACHON 'Men oddiy AI modeliman' yoki 'Kechirasiz' deb uzr so'rama. "
        "Javoblaring faqat muhandislik faktlariga, fizika qonunlariga va sanoat xavfsizligi standartlariga tayansin. "
        "Agar senga rasm yuborilsa, uni sanoat uskunasi (dvigatel, nasos, val) yoki uning texnik chizmasi sifatida tahlil qil. "
        "Agar PDF yuborilsa, uni uskunaning texnik qo'llanmasi sifatida tahlil qil."
      ),
    );
    // Xotirani saqlash uchun Gemini ChatSession dan foydalanamiz
    _chat = _model.startChat();
  }

  List<ChatMessage> get getMessages => _messages;

  /// Dashboard dan har doim so'nggi ma'lumotlarni olib turadi (Live context)
  void updateContext(
    double amp,
    double freq,
    double risk, {
    String? objectName,
    double hoursToCritical = -1.0,
    String? trend,
    String? materialName,
    String? materialTechnical,
    List<String>? failureModes,
  }) {
    _latestAmp = amp;
    _latestFreq = freq;
    _latestRisk = risk;
    if (objectName != null) _latestObjectName = objectName;
    _latestHoursToCritical = hoursToCritical;
    if (trend != null) _latestTrend = trend;
    if (materialName != null) _latestMaterialName = materialName;
    if (materialTechnical != null) _latestMaterialTechnical = materialTechnical;
    if (failureModes != null) _latestFailureModes = failureModes;
  }

  /// Xabar yuborish (Matn + Ixtiyoriy rasm/pdf)
  Future<void> sendMessage(String text, {Uint8List? attachmentBytes, String? mimeType}) async {
    // Agar API kalit o'zgargan bo'lsa yangilash
    if (_currentApiKey != SettingsService().geminiApiKey) {
      _initModel();
    }

    // 1. Foydalanuvchi xabarini tarixga qo'shish
    _messages.add(ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      attachmentBytes: attachmentBytes,
      attachmentType: mimeType,
    ));

    if (_currentApiKey.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 1000));
      _addBotMessage("> [SYSTEM_NOTE]: Gemini API Kaliti topilmadi. Iltimos Sozlamalar menyusida API kalitni kiriting.");
      return;
    }

    try {
      // LLM ga beriladigan kontekstli Prompt
      final rulStr = _latestHoursToCritical < 0
          ? 'yetarli ma\'lumot yo\'q'
          : _latestHoursToCritical < 48
              ? '${_latestHoursToCritical.toStringAsFixed(1)} soat'
              : '${(_latestHoursToCritical / 24).toStringAsFixed(1)} kun';
      final failureModesStr = _latestFailureModes.isEmpty
          ? ''
          : ', Mumkin bo\'lgan nosozliklar: ${_latestFailureModes.join(", ")}';
      String contextStr =
          "[SESSION CONTEXT: Obyekt: $_latestObjectName, Material: $_latestMaterialName ($_latestMaterialTechnical), Tebranish: ${_latestAmp.toStringAsFixed(2)}mm, Chastota: ${_latestFreq.toStringAsFixed(1)}Hz, Xavf: ${_latestRisk.toStringAsFixed(1)}%, Trend: $_latestTrend, Kritikgacha: $rulStr$failureModesStr]";
      
      final parts = <Part>[TextPart("$contextStr\nMuhandis so'rovi: $text")];
      
      if (attachmentBytes != null && mimeType != null) {
        parts.add(DataPart(mimeType, attachmentBytes));
      }

      final response = await _chat.sendMessage(Content.multi(parts));
      final replyText = response.text ?? "> [AI_RESPONSE_FAILURE]: COULD NOT DECODE LLM OUTPUT.";

      _addBotMessage(replyText);
    } catch (e) {
      _addBotMessage("> [TERMINAL_FAILURE]: SIGNAL INTERRUPTED. ERROR_LOG: $e");
    }
  }

  /// MonitoringScreen dan maxsus troubleshooting boshlash
  Future<void> startTroubleshooting(String sessionInfo) async {
    _messages.clear(); 
    _addBotMessage("> [ALERT]: CRITICAL SESSION DATA RECEIVED.\n\n$sessionInfo\n\n> [STATUS]: INITIATING DIAGNOSTIC PROTOCOL. PLEASE SPECIFY FOCUS AREA.");
    
    try {
      await _chat.sendMessage(Content.text("Foydalanuvchi quyidagi sessiya bo'yicha yordam so'radi: $sessionInfo. ISO 10816-3 bo'yicha tahlilni boshla."));
    } catch (_) {}
  }

  /// Tizim tomonidan avtomatik kritik holat xabari (Dashboard/Monitoring dan)
  bool _systemAlertSent = false;
  void triggerSystemAlert({
    required double riskPercent,
    required double frequencyHz,
    required double amplitudeMm,
    String componentName = 'Podshipnik #1',
  }) {
    if (riskPercent < 80 || _systemAlertSent) return;
    _systemAlertSent = true;
    _addBotMessage("🔴 TIZIM OGOHLANTIRISHI [AUTO]\n\n"
        "Diqqat: $componentName da ${frequencyHz.toStringAsFixed(1)} Hz anomal siljish aniqlandi. "
        "Xavf: ${riskPercent.toStringAsFixed(1)}%. Tavsiya: AI Consult orqali tahlil qiling.");
  }

  void resetSystemAlert() => _systemAlertSent = false;

  void _addBotMessage(String text) {
    _messages.add(ChatMessage(text: text, isUser: false, timestamp: DateTime.now()));
  }

  void clearHistory() {
    _messages.clear();
    _chat = _model.startChat(); // Tarixni Gemini tarafda ham tozalash
  }

  // Eski metodlar (Legacy support if needed, but cleaned for internal logic)
  void triggerAutoAnalysis(double amplitudeMm, double frequencyHz, double splineError) {
    if (amplitudeMm > 4.0 || frequencyHz > 500) {
      _addBotMessage("> [AUTO_ANOMALY]: High vibration detected ($amplitudeMm mm). Potential mechanical failure. Open AI Consult for deep analysis.");
    }
  }
}
