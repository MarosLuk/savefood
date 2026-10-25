import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:design_system/design_system.dart';
import '../../state/app_store.dart';

class SupportPhotoView extends StatefulWidget {
  const SupportPhotoView({super.key, required this.id});
  final String id;
  @override
  State<SupportPhotoView> createState() => _SupportPhotoViewState();
}

class _SupportPhotoViewState extends State<SupportPhotoView> {
  Uint8List? bytes;
  String? identity;
  bool failed = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final email = StoreScope.of(context).email;
    if (identity != email) {
      identity = email;
      bytes = null;
      failed = false;
      load();
    }
  }

  Future<void> load() async {
    final email = identity;
    try {
      final b = await StoreScope.of(context).api!.supportPhoto(widget.id);
      if (mounted && identity == email) {
        setState(() {
          bytes = b;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && identity == email) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Fotografia reklamácie',
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: bytes == null
          ? (failed ? load : null)
          : () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Zavrieť fotografiu',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(AppIcons.close),
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        child: Image.memory(
                          bytes!,
                          fit: BoxFit.contain,
                          semanticLabel: 'Fotografia priložená k požiadavke',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: bytes == null
            ? Container(
                width: 96,
                height: 96,
                color: context.colors.tint,
                child: Icon(
                  failed ? AppIcons.refresh : AppIcons.photo,
                  color: context.colors.blue,
                ),
              )
            : Image.memory(
                bytes!,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
      ),
    ),
  );
}
