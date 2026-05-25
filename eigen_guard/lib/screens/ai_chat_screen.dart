import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:async';
import '../core/app_theme.dart';
import '../services/ai_assistant_service.dart';

class AiChatScreen extends StatefulWidget {
  final AiAssistantService aiService;

  const AiChatScreen({super.key, required this.aiService});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedAttachment;
  String? _selectedMimeType;
  String? _selectedFileName;
  bool _isSending = false;
  final Set<int> _typedMessageIndices = {}; // Qaysi xabarlar allaqachon animatsiya bo'lganini saqlaydi

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Sof terminal qoraligi
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EIGENGUARD AI TERMINAL',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    letterSpacing: 2.0)),
            Text('STATUS: ENCRYPTION ACTIVE',
                style: TextStyle(color: AppTheme.success, fontSize: 8, fontFamily: 'monospace')),
          ],
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_sharp, color: AppTheme.textMuted),
            onPressed: () {
              setState(() => widget.aiService.clearHistory());
            },
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Divider(color: AppTheme.primary, height: 1, thickness: 0.5),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: widget.aiService.getMessages.length,
                itemBuilder: (context, index) {
                  final msg = widget.aiService.getMessages[index];
                  return _buildTerminalMessage(msg);
                },
              ),
            ),
            if (_selectedAttachment != null) _buildAttachmentPreview(),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    bool isPdf = _selectedMimeType == 'application/pdf';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      child: Row(
        children: [
          if (isPdf)
            const Icon(Icons.picture_as_pdf, color: AppTheme.danger, size: 40)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(_selectedAttachment!, height: 60, width: 80, fit: BoxFit.cover),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPdf ? (_selectedFileName ?? 'DOCUMENT.PDF') : 'IMAGE_ATTACHED.JPG',
              style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontFamily: 'monospace', overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.danger, size: 20),
            onPressed: () => setState(() {
              _selectedAttachment = null;
              _selectedMimeType = null;
              _selectedFileName = null;
            }),
          ),
        ],
      ),
    );
  }
  Widget _buildTerminalMessage(ChatMessage msg) {
    bool isMe = msg.isUser;
    final color = isMe ? Colors.white : AppTheme.primary;
    final prefix = isMe ? "> [USER]: " : "> [AI_COPILOT]: ";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefix, 
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          if (msg.attachmentBytes != null) ...[
            if (msg.attachmentType == 'application/pdf')
              _buildPdfThumbnail()
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(msg.attachmentBytes!, width: 200, fit: BoxFit.contain),
              ),
            const SizedBox(height: 8),
          ],
          if (isMe)
            Text(
              msg.text,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4, fontFamily: 'monospace'),
            )
          else
            _TypingTerminalText(
              text: msg.text,
              onComplete: () => _typedMessageIndices.add(widget.aiService.getMessages.indexOf(msg)),
              shouldAnimate: !_typedMessageIndices.contains(widget.aiService.getMessages.indexOf(msg)),
            ),
          const SizedBox(height: 4),
          Text(
            "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}:${msg.timestamp.second.toString().padLeft(2, '0')}",
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5), fontSize: 9, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfThumbnail() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.picture_as_pdf, color: AppTheme.danger),
          SizedBox(width: 8),
          Text('ATTACHED_MANUAL.PDF', style: TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: AppTheme.primary, width: 0.5)),
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.attachment_rounded, color: AppTheme.primary),
            color: AppTheme.surface,
            onSelected: (value) {
              if (value == 'image') _pickImage();
              if (value == 'pdf') _pickPdf();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'image', child: Text('IMAGE', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'))),
              const PopupMenuItem(value: 'pdf', child: Text('DOC (PDF)', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'))),
            ],
          ),
          Expanded(
            child: TextField(
              controller: _textController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: "Enter command...",
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          if (_isSending)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
          else
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppTheme.primary, size: 22),
              onPressed: _sendMessage,
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedAttachment = bytes;
        _selectedMimeType = 'image/jpeg';
        _selectedFileName = 'IMAGE.JPG';
      });
    }
  }

  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _selectedAttachment = result.files.single.bytes;
        _selectedMimeType = 'application/pdf';
        _selectedFileName = result.files.single.name;
      });
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedAttachment == null) return;

    final attachment = _selectedAttachment;
    final mime = _selectedMimeType;
    
    _textController.clear();
    setState(() {
      _selectedAttachment = null;
      _selectedMimeType = null;
      _selectedFileName = null;
      _isSending = true;
    });

    widget.aiService.sendMessage(text, attachmentBytes: attachment, mimeType: mime).then((_) {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

/// Terminal style typing effect
class _TypingTerminalText extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;
  final bool shouldAnimate;

  const _TypingTerminalText({
    required this.text, 
    required this.onComplete,
    this.shouldAnimate = true,
  });

  @override
  State<_TypingTerminalText> createState() => _TypingTerminalTextState();
}

class _TypingTerminalTextState extends State<_TypingTerminalText> {
  String _displayedText = "";
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.shouldAnimate) {
      _startTyping();
    } else {
      _displayedText = widget.text;
    }
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      if (_currentIndex < widget.text.length) {
        setState(() {
          _displayedText += widget.text[_currentIndex];
          _currentIndex++;
        });
      } else {
        timer.cancel();
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText + (_currentIndex < widget.text.length ? "█" : ""),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        height: 1.4,
        fontFamily: 'monospace',
      ),
    );
  }
}
