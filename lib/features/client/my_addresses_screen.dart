import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'address_picker.dart';
import 'city_street_sheet.dart';
import 'saved_addresses.dart';

/// Мекенжайды сақтау/өңдеу парағын ашады.
/// [place] — координата мен адрес мәтіні (жаңа сақтауда — таңдалған нүкте,
/// өңдеуде — бар мекенжайдың нүктесі). [existing] берілсе — өңдеу режимі.
/// Сәтті сақталса `true` қайтарады.
Future<bool> showSaveAddressSheet(
  BuildContext context, {
  required PickedAddress place,
  SavedAddress? existing,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Gz.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SaveAddressSheet(place: place, existing: existing),
  );
  return ok ?? false;
}

class _SaveAddressSheet extends StatefulWidget {
  final PickedAddress place;
  final SavedAddress? existing;
  const _SaveAddressSheet({required this.place, this.existing});

  @override
  State<_SaveAddressSheet> createState() => _SaveAddressSheetState();
}

class _SaveAddressSheetState extends State<_SaveAddressSheet> {
  late SavedAddressKind _kind = widget.existing?.kind ?? SavedAddressKind.home;
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late bool _primary = widget.existing?.isPrimary ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_kind == SavedAddressKind.other && _label.text.trim().isEmpty) {
      showSnack(context, t('Мекенжайға атау беріңіз'), error: true);
      return;
    }
    setState(() => _saving = true);
    final e = widget.existing;
    final id = e?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    await AddressBook.addOrUpdate(
      SavedAddress(
        id: id,
        kind: _kind,
        label: _kind == SavedAddressKind.other ? _label.text.trim() : '',
        address: widget.place.address,
        lat: widget.place.point.latitude,
        lng: widget.place.point.longitude,
        city: widget.place.city,
        isPrimary: _primary,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Gz.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.existing == null
                      ? t('Мекенжайды сақтау')
                      : t('Мекенжайды өңдеу'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Gz.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18, color: Gz.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        place.city != null && place.city!.isNotEmpty
                            ? '${place.address} · ${place.city}'
                            : place.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  for (final k in SavedAddressKind.values) ...[
                    Expanded(child: _kindChip(k)),
                    if (k != SavedAddressKind.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (_kind == SavedAddressKind.other)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: TextField(
                  controller: _label,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: t('Атауы (мыс: Ата-анам, дача)'),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: SwitchListTile(
                value: _primary,
                activeThumbColor: Gz.green,
                onChanged: (v) => setState(() => _primary = v),
                title: Text(
                  t('Негізгі мекенжай'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                subtitle: Text(
                  t('Жаңа заказ ашылғанда бірінші болып ұсынылады'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(t('Сақтау')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(SavedAddressKind k) {
    final sel = _kind == k;
    return InkWell(
      onTap: () => setState(() => _kind = k),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? Gz.ink : Gz.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? Gz.ink : Gz.border),
        ),
        child: Column(
          children: [
            Icon(
              savedAddressIcon(k),
              size: 20,
              color: sel ? Colors.white : Gz.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              savedAddressKindLabel(k),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : Gz.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Менің мекенжайларым» — сақталған мекенжайларды басқару экраны.
class MyAddressesScreen extends StatefulWidget {
  const MyAddressesScreen({super.key});

  @override
  State<MyAddressesScreen> createState() => _MyAddressesScreenState();
}

class _MyAddressesScreenState extends State<MyAddressesScreen> {
  List<SavedAddress> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AddressBook.saved();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  /// Жаңа мекенжай қосу: алдымен нүктені (қала + көше) таңдатамыз,
  /// сосын оны үй/жұмыс/басқа етіп белгілейміз.
  Future<void> _add() async {
    final picked = await CityStreetSheet.show(
      context,
      title: t('Мекенжайды таңдаңыз'),
    );
    if (picked == null || !mounted) return;
    final saved = await showSaveAddressSheet(context, place: picked);
    if (saved) await _load();
  }

  Future<void> _edit(SavedAddress a) async {
    final saved = await showSaveAddressSheet(
      context,
      place: a.toPicked(),
      existing: a,
    );
    if (saved) await _load();
  }

  Future<void> _delete(SavedAddress a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Өшіру керек пе?')),
        content: Text('«${savedAddressTitle(a)}» — ${a.address}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Жоқ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Gz.red),
            child: Text(t('Өшіру')),
          ),
        ],
      ),
    );
    if (yes == true) {
      await AddressBook.remove(a.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Менің мекенжайларым'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: Gz.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(t('Мекенжай қосу')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? EmptyState(
              icon: Icons.bookmark_border,
              title: t('Сақталған мекенжай жоқ'),
              subtitle: t(
                'Үй, жұмыс сияқты жиі қолданатын мекенжайды '
                'сақтап қойсаңыз, заказ бергенде қайта термейсіз.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: _items.length,
              separatorBuilder: (_, i) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _tile(_items[i]),
            ),
    );
  }

  Widget _tile(SavedAddress a) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Gz.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(savedAddressIcon(a.kind), size: 20, color: Gz.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        savedAddressTitle(a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (a.isPrimary) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Gz.yellowDark,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  a.city != null && a.city!.isNotEmpty
                      ? '${a.address} · ${a.city}'
                      : a.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Gz.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Gz.textSecondary),
            onSelected: (v) async {
              switch (v) {
                case 'primary':
                  await AddressBook.setPrimary(a.id);
                  await _load();
                case 'edit':
                  await _edit(a);
                case 'delete':
                  await _delete(a);
              }
            },
            itemBuilder: (_) => [
              if (!a.isPrimary)
                PopupMenuItem(
                  value: 'primary',
                  child: Row(
                    children: [
                      const Icon(Icons.star_outline, size: 20),
                      const SizedBox(width: 10),
                      Text(t('Негізгі ету')),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(t('Өңдеу')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, size: 20, color: Gz.red),
                    const SizedBox(width: 10),
                    Text(t('Өшіру'), style: const TextStyle(color: Gz.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
