import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/services/app_config_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('konkurent_cfg');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  AppConfigService service() => AppConfigService(directory: tmp);

  test('первый запуск создаёт дефолтные файлы', () async {
    final config = await service().load();
    expect(config.vatRate, 0.22);
    expect(config.maxSuppliers, 3);
    expect(config.legalForms, contains('ООО'));
    expect(File(p.join(tmp.path, 'app-config.json')).existsSync(), isTrue);
    final forms = File(p.join(tmp.path, 'legal-forms.json'));
    expect(forms.existsSync(), isTrue);
    final list = jsonDecode(forms.readAsStringSync()) as List;
    expect(list, isNotEmpty);
  });

  test('читает пользовательские настройки и юрформы', () async {
    File(p.join(tmp.path, 'app-config.json'))
        .writeAsStringSync('{"vatRate": 0.2, "maxSuppliers": 5}');
    File(p.join(tmp.path, 'legal-forms.json'))
        .writeAsStringSync('["ТОО", "ООО"]');

    final config = await service().load();
    expect(config.vatRate, 0.2);
    expect(config.maxSuppliers, 5);
    expect(config.legalForms, ['ТОО', 'ООО']);
  });

  test('повреждённые файлы молча дают дефолты', () async {
    File(p.join(tmp.path, 'app-config.json')).writeAsStringSync('{broken');
    File(p.join(tmp.path, 'legal-forms.json')).writeAsStringSync('not json');

    final config = await service().load();
    expect(config.vatRate, 0.22);
    expect(config.legalForms, AppConfig.defaultLegalForms);
  });

  test('legalFormsPath отдаёт путь после загрузки', () async {
    await service().load();
    expect(await service().legalFormsPath(),
        p.join(tmp.path, 'legal-forms.json'));
  });
}
