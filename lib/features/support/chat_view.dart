import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lang.dart';
import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Ортақ чат көрінісі (клиент/орындаушы да, модератор да қолданады).
class ChatView extends StatefulWidget {
  final String? threadId;
  final bool asModerator;
  final bool threadOpen;

  /// Хабарлама жіберу. Тредтің id-ін қайтарады (жаңа болса).
  final Future<String> Function(String body, String? imagePath) onSend;
  final Future<void> Function()? onClose;

  const ChatView({
    super.key,
    required this.threadId,
    required this.asModerator,
    required this.threadOpen,
    required this.onSend,
    this.onClose,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _threadId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _threadId = widget.threadId;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({String? imagePath}) async {
    final body = _input.text.trim();
    if (body.isEmpty && imagePath == null) return;
    setState(() => _sending = true);
    try {
      final id = await widget.onSend(body, imagePath);
      _input.clear();
      if (mounted) setState(() => _threadId = id);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600);
    if (f == null) return;
    setState(() => _sending = true);
    try {
      final bytes = await f.readAsBytes();
      final path = await Repo.uploadSupportImage(bytes);
      await _send(imagePath: path);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _isMine(SupportMessage m) =>
      widget.asModerator ? m.senderRole == 'moderator' : m.senderRole == 'user';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _threadId == null
              ? const _IntroPlaceholder()
              : StreamBuilder<List<SupportMessage>>(
                  stream: Repo.supportMessagesStream(_threadId!),
                  builder: (context, snap) {
                    final msgs = snap.data ?? [];
                    if (msgs.isEmpty) return const _IntroPlaceholder();
                    // reverse:true — жаңа хабарлама астында (кіру өрісінің үстінде)
                    final ordered = msgs.reversed.toList();
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: ordered.length,
                      itemBuilder: (_, i) =>
                          _Bubble(msg: ordered[i], mine: _isMine(ordered[i])),
                    );
                  },
                ),
        ),
        if (!widget.threadOpen && _threadId != null)
          Container(
            width: double.infinity,
            color: Gz.bg,
            padding: const EdgeInsets.all(12),
            child: Text(
              t('Чат аяқталды. Жаңа хабарлама жазсаңыз, қайта ашылады.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Gz.textSecondary, fontSize: 12.5),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: _sending ? null : _sendImage,
                  icon: const Icon(Icons.photo_outlined),
                  color: Gz.textSecondary,
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: t('Хабарлама…'),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton.filled(
                        style: IconButton.styleFrom(
                            backgroundColor: Gz.yellow,
                            foregroundColor: Gz.ink),
                        onPressed: () => _send(),
                        icon: const Icon(Icons.send),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final SupportMessage msg;
  final bool mine;
  const _Bubble({required this.msg, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? Gz.yellow : Gz.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: mine ? null : Border.all(color: Gz.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.imagePath != null)
              Padding(
                padding: EdgeInsets.only(bottom: msg.body.isEmpty ? 0 : 6),
                child: GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      insetPadding: const EdgeInsets.all(10),
                      child: InteractiveViewer(
                        child: Image.network(
                            Repo.supportImageUrl(msg.imagePath!)),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      Repo.supportImageUrl(msg.imagePath!),
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            if (msg.body.isNotEmpty)
              Text(msg.body, style: const TextStyle(fontSize: 14.5)),
            const SizedBox(height: 3),
            Text(
              fmtTime(msg.createdAt),
              style: TextStyle(
                  fontSize: 10.5,
                  color: mine ? Gz.ink.withValues(alpha: 0.5) : Gz.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPlaceholder extends StatelessWidget {
  const _IntroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.support_agent,
      title: t('Қолдау қызметі'),
      subtitle:
          t('Сұрағыңызды жазыңыз — модератор жауап береді. Фото да тіркей аласыз.'),
    );
  }
}
