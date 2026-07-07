import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../core/repo.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../client/my_orders_screen.dart';
import '../support/support_screen.dart';
import 'reviews_screen.dart';

/// Ортақ профиль экраны (клиент те, орындаушы да қолданады).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 1000);
    if (f == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await f.readAsBytes();
      await Repo.updateAvatar(bytes);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) showSnack(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _edit(Profile p) async {
    final name = TextEditingController(text: p.fullName);
    final phone = TextEditingController(text: p.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Профильді өзгерту'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(hintText: 'Аты-жөні'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Телефон'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Болдырмау')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сақтау')),
        ],
      ),
    );
    if (ok == true) {
      await Repo.updateProfile(fullName: name.text, phone: phone.text);
      ref.invalidate(myProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final execAsync = ref.watch(myExecutorProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) =>
            EmptyState(icon: Icons.error_outline, title: errText(e)),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          final ep = execAsync.value;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _changeAvatar,
                      child: Stack(
                        children: [
                          InitialsAvatar(p.fullName,
                              radius: 30, imageUrl: p.avatarUrl),
                          if (_uploadingAvatar)
                            const Positioned.fill(
                              child: CircleAvatar(
                                backgroundColor: Colors.black38,
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white)),
                              ),
                            )
                          else
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                    color: Gz.yellow, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt,
                                    size: 13, color: Gz.ink),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fullName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(p.phone,
                              style: const TextStyle(
                                  color: Gz.textSecondary, fontSize: 13.5)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              RatingStars(p.rating,
                                  count: p.ratingCount, size: 14),
                              const SizedBox(width: 10),
                              const Icon(Icons.local_shipping,
                                  size: 13, color: Gz.textSecondary),
                              const SizedBox(width: 3),
                              Text('${p.trips} рейс',
                                  style: const TextStyle(
                                      fontSize: 12, color: Gz.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _edit(p),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (p.role == 'executor' && ep != null) ...[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Көлігім',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      InfoRow('Көлік', ep.vehicleTitle),
                      InfoRow('Өлшемі', ep.vehicleSize.label),
                      InfoRow('Мемнөмір', ep.vehiclePlate),
                      InfoRow('Статус', switch (ep.status) {
                        'approved' => 'Расталған',
                        'pending' => 'Тексерілуде',
                        'rejected' => 'Қабылданбаған',
                        _ => 'Бұғатталған',
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (p.role == 'client') ...[
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, color: Gz.blue),
                    title: const Text('Тапсырыстар',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Белсенді және өткен заказдар'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MyOrdersScreen())),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                  title: const Text('Пікірлер',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.ratingCount == 0
                      ? 'Әзірге пікір жоқ'
                      : '${p.rating.toStringAsFixed(1)} · ${p.ratingCount} пікір'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewsScreen(
                      userId: p.id,
                      name: p.fullName,
                      rating: p.rating,
                      ratingCount: p.ratingCount,
                    ),
                  )),
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.support_agent, color: Gz.ink),
                  title: const Text('Қолдау қызметі',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Сұрақ, шағым, көмек'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SupportScreen())),
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.logout, color: Gz.red),
                  title: const Text('Шығу',
                      style: TextStyle(
                          color: Gz.red, fontWeight: FontWeight.w700)),
                  onTap: Repo.signOut,
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text('GazelGo v1.0',
                    style: TextStyle(color: Gz.textSecondary, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

