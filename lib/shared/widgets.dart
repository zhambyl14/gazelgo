import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/theme.dart';

/// Async-әрекеті бар батырма: басқанда spinner көрсетеді.
class BusyButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  final bool outlined;
  final Color? color;
  final IconData? icon;

  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.color,
    this.icon,
  });

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Gz.ink),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(widget.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          );
    if (widget.outlined) {
      return OutlinedButton(onPressed: _busy ? null : _run, child: child);
    }
    return FilledButton(
      onPressed: _busy ? null : _run,
      style: widget.color == null
          ? null
          : FilledButton.styleFrom(
              backgroundColor: widget.color,
              foregroundColor: Colors.white,
            ),
      child: child,
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) =>
      Card(child: Padding(padding: padding, child: child));
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  Color get _color => switch (status) {
        'searching' => Gz.blue,
        'accepted' || 'arrived' || 'loading' || 'in_transit' => Gz.green,
        'completed' => Gz.ink,
        _ => Gz.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
            color: _color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  final double rating;
  final int count;
  final double size;
  const RatingStars(this.rating, {super.key, this.count = -1, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: const Color(0xFFF59E0B), size: size + 2),
        const SizedBox(width: 3),
        Text(
          rating <= 0 ? 'жаңа' : rating.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.85),
        ),
        if (count >= 0) ...[
          const SizedBox(width: 3),
          Text('($count)',
              style: TextStyle(color: Gz.textSecondary, fontSize: size * 0.8)),
        ],
      ],
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final String? imageUrl;
  const InitialsAvatar(this.name, {super.key, this.radius = 22, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: Gz.ink,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
            color: Gz.yellow,
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.72),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Gz.bg,
      foregroundImage: NetworkImage(imageUrl!),
      onForegroundImageError: (_, _) {},
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
            color: Gz.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.72),
      ),
    );
  }
}

/// Аты + рейтинг + поездка саны бар қысқа профиль жолы.
class ProfileBrief extends StatelessWidget {
  final Profile? profile;
  final double radius;
  final String? subtitle;
  const ProfileBrief(
      {super.key, required this.profile, this.radius = 20, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Row(
      children: [
        InitialsAvatar(p?.fullName ?? '?', radius: radius, imageUrl: p?.avatarUrl),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p?.fullName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
              Row(
                children: [
                  RatingStars(p?.rating ?? 0, count: p?.ratingCount ?? 0, size: 12),
                  if ((p?.trips ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.local_shipping,
                        size: 12, color: Gz.textSecondary),
                    const SizedBox(width: 2),
                    Text('${p!.trips}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Gz.textSecondary)),
                  ],
                ],
              ),
              if (subtitle != null)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Gz.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Gz.yellow.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Gz.ink),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Gz.textSecondary, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A → B адрес бағаны.
class RouteLine extends StatelessWidget {
  final String from;
  final String to;
  const RouteLine({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    // A нүктесі — жасыл сақина (домалақ емес), B — қызыл пин
    Widget originRing() => Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Gz.green, width: 3.5),
            color: Colors.white,
          ),
        );
    Widget row(Widget lead, String label, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 18, child: Center(child: lead)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10.5, color: Gz.textSecondary)),
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(originRing(), 'Қайдан', from),
        Padding(
          padding: const EdgeInsets.only(left: 8.5),
          child: Container(width: 2, height: 14, color: Gz.border),
        ),
        row(const Icon(Icons.location_on, size: 18, color: Gz.red), 'Қайда', to),
      ],
    );
  }
}

class VehicleSizeSelector extends StatelessWidget {
  final VehicleSize value;
  final ValueChanged<VehicleSize> onChanged;
  const VehicleSizeSelector(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in VehicleSize.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: value == s ? Gz.yellow : Gz.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: value == s ? Gz.yellowDark : Gz.border,
                      width: 1.4),
                ),
                child: Column(
                  children: [
                    Icon(Icons.local_shipping,
                        size: s == VehicleSize.small
                            ? 22
                            : s == VehicleSize.medium
                                ? 27
                                : 32,
                        color: Gz.ink),
                    const SizedBox(height: 6),
                    Text(
                      s.label.split(' ').first,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      s.hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10.5, color: Gz.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (s != VehicleSize.large) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Заказ карточкасы (лента мен тізімдерге ортақ).
class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? footer;

  const OrderCard(
      {super.key,
      required this.order,
      this.onTap,
      this.trailing,
      this.footer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Gz.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fmtT(order.displayPrice),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  trailing ?? StatusChip(order.status),
                ],
              ),
              const SizedBox(height: 10),
              RouteLine(from: order.fromAddress, to: order.toAddress),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _tag(Icons.local_shipping, order.size.label),
                  if (order.distanceKm > 0)
                    _tag(Icons.route, '${order.distanceKm.toStringAsFixed(1)} км'),
                  _tag(
                    order.type == 'instant' ? Icons.flash_on : Icons.gavel,
                    order.type == 'instant' ? 'Жедел' : 'Баға ұсыну',
                  ),
                  if (order.createdAt != null)
                    _tag(Icons.schedule, fmtTime(order.createdAt)),
                ],
              ),
              if (order.cargoDesc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  order.cargoDesc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Gz.textSecondary, fontSize: 13.5),
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 12),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Gz.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Gz.textSecondary),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    color: Gz.ink,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: Gz.textSecondary, fontSize: 13.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

/// Заказ фотоларының жолағы (public 'orders' бакеті). Басқанда үлкейеді.
class OrderPhotosStrip extends StatelessWidget {
  final List<String> paths;
  const OrderPhotosStrip({super.key, required this.paths});

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Жүк фотолары',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 6),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paths.length,
            separatorBuilder: (_, i) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final url = Repo.orderPhotoUrl(paths[i]);
              return GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    insetPadding: const EdgeInsets.all(10),
                    child: InteractiveViewer(child: Image.network(url)),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url,
                      width: 84, height: 84, fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => Container(
                            width: 84,
                            height: 84,
                            color: Gz.bg,
                            child: const Icon(Icons.broken_image,
                                color: Gz.textSecondary),
                          )),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Пікір қалдыру блогы (клиент те, орындаушы да — екінші тарапты бағалайды).
class ReviewPrompt extends StatefulWidget {
  final String orderId;
  final String title;
  const ReviewPrompt(
      {super.key, required this.orderId, this.title = 'Бағалаңыз'});

  @override
  State<ReviewPrompt> createState() => _ReviewPromptState();
}

class _ReviewPromptState extends State<ReviewPrompt> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _done = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final rows = await Repo.c
          .from('reviews')
          .select('id')
          .eq('order_id', widget.orderId)
          .eq('author_id', Repo.uid ?? '');
      if (mounted) {
        setState(() {
          _done = (rows as List).isNotEmpty;
          _checked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (_done) {
      return const SectionCard(
        child: Row(children: [
          Icon(Icons.check_circle, color: Gz.green),
          SizedBox(width: 10),
          Expanded(child: Text('Пікіріңіз үшін рахмет!')),
        ]),
      );
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 34,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
            ],
          ),
          TextField(
            controller: _comment,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Пікір жазыңыз (міндетті емес)'),
          ),
          const SizedBox(height: 12),
          BusyButton(
            label: 'Жіберу',
            onPressed: () async {
              try {
                await Repo.submitReview(widget.orderId, _rating, _comment.text);
                if (mounted) setState(() => _done = true);
              } catch (e) {
                if (context.mounted) {
                  showSnack(context, errText(e), error: true);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/// GazelGo логотипі (мәтіндік).
class GazelGoLogo extends StatelessWidget {
  final double size;
  const GazelGoLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: size * 0.3, vertical: size * 0.12),
          decoration: BoxDecoration(
            color: Gz.yellow,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(Icons.local_shipping, size: size * 0.9, color: Gz.ink),
        ),
        SizedBox(width: size * 0.3),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: 'Gazel',
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w900,
                    color: Gz.ink)),
            TextSpan(
                text: 'Go',
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w900,
                    color: Gz.yellowDark)),
          ]),
        ),
      ],
    );
  }
}
