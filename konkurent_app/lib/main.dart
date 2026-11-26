import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/supplier_db.dart';
import 'ui/app.dart';

Future<void> main() async {
  // БД поставщиков открывается до runApp; сбой не роняет приложение —
  // фичи памяти поставщиков просто гаснут (provider останется null).
  final supplierDb = await SupplierDb.openDefault();
  runApp(ProviderScope(
    overrides: [supplierDbProvider.overrideWithValue(supplierDb)],
    child: const KonkurentApp(),
  ));
}
