// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps

import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run core_bloc/lib/generator/generate_module.dart <module_name>');
    print('Example: dart run core_bloc/lib/generator/generate_module.dart login');
    return;
  }

  final rawName = args[0].trim();
  if (rawName.isEmpty) {
    print('Error: Module name cannot be empty.');
    return;
  }

  final snakeName = toSnakeCase(rawName);
  final pascalName = toPascalCase(snakeName);
  final camelName = toCamelCase(snakeName);
  final constantName = toConstantCase(snakeName);

  print('Generating module: $pascalName ($snakeName)...');

  final appRoot = findAppRoot();
  final packageName = getPackageName(appRoot);
  print('App root: ${appRoot.path}');
  print('Package name: $packageName');

  // 1. Generate Clean Architecture: Domain & Data layers
  generateCleanArchitecture(
    appRoot: appRoot,
    packageName: packageName,
    snakeName: snakeName,
    pascalName: pascalName,
  );

  // 2. Target directory: lib/feature/<module_name>/presentation
  final presentationDir = Directory('${appRoot.path}/lib/feature/$snakeName/presentation');
  if (!presentationDir.existsSync()) {
    presentationDir.createSync(recursive: true);
    print('Created directory: ${presentationDir.path}');
  }

  // 3. Generate <module_name>_bloc.dart
  final blocFile = File('${presentationDir.path}/${snakeName}_bloc.dart');
  if (!blocFile.existsSync()) {
    final blocContent = '''
import 'package:core_bloc/core_bloc.dart';
import 'package:$packageName/feature/$snakeName/domain/repositories/${snakeName}_repository.dart';
import 'package:$packageName/feature/$snakeName/presentation/${snakeName}_state.dart';

part '${snakeName}_event.dart';

@injectable
class ${pascalName}Bloc extends BaseBloc<${pascalName}Event, ${pascalName}State> {
  ${pascalName}Bloc(this._repository) : super(const ${pascalName}State()) {
    // todo: ...
  }

  final ${pascalName}Repository _repository;
}
''';
    blocFile.writeAsStringSync(blocContent);
    print('Created: ${blocFile.path}');
  }

  // 4. Generate <module_name>_event.dart
  final eventFile = File('${presentationDir.path}/${snakeName}_event.dart');
  if (!eventFile.existsSync()) {
    final eventContent = '''
part of '${snakeName}_bloc.dart';

sealed class ${pascalName}Event {
  const ${pascalName}Event();
}
''';
    eventFile.writeAsStringSync(eventContent);
    print('Created: ${eventFile.path}');
  }

  // 5. Generate <module_name>_state.dart
  final stateFile = File('${presentationDir.path}/${snakeName}_state.dart');
  if (!stateFile.existsSync()) {
    final stateContent = '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${snakeName}_state.freezed.dart';

/// ===========================================================================
/// How to update this Freezed State:
/// ===========================================================================
/// 1. Add fields into the factory constructor, e.g.:
///    const factory ${pascalName}State({
///      @Default('') String id,
///      @Default(false) bool isLoading,
///      String? errorMessage,
///    }) = _${pascalName}State;
///
/// 2. Run build_runner to regenerate .freezed.dart:
///    - Fast / Target this module only:
///      dart run build_runner build --build-filter="lib/feature/$snakeName/presentation/**"
///
///    - Watch mode (auto-regenerates on save):
///      dart run build_runner watch --delete-conflicting-outputs
///
///    - Full project rebuild:
///      dart run build_runner build --delete-conflicting-outputs
/// ===========================================================================
@freezed
abstract class ${pascalName}State with _\$${pascalName}State {
  const factory ${pascalName}State() = _${pascalName}State;
}
''';
    stateFile.writeAsStringSync(stateContent);
    print('Created: ${stateFile.path}');
  }

  // 6. Generate <module_name>_view.dart
  final viewFile = File('${presentationDir.path}/${snakeName}_view.dart');
  if (!viewFile.existsSync()) {
    final viewContent = '''
import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';
import 'package:$packageName/dependence/injection.dart';
import 'package:$packageName/feature/$snakeName/presentation/${snakeName}_bloc.dart';
import 'package:$packageName/feature/$snakeName/presentation/${snakeName}_state.dart';

class ${pascalName}View extends BaseView {
  const ${pascalName}View({super.key, super.args});

  @override
  State<${pascalName}View> createState() => _${pascalName}ViewState();

  static Widget builder([Object? args]) => BlocProvider(
        create: (_) => getIt<${pascalName}Bloc>(),
        child: ${pascalName}View(args: args),
      );

  static Route router([RouteSettings? settings]) => MaterialPageRoute(
        settings: settings,
        builder: (_) => builder(settings?.arguments),
      );
}

class _${pascalName}ViewState extends BaseViewState<${pascalName}View, ${pascalName}Bloc, ${pascalName}State> {

  @override
  Widget buildSuccessView() {
    return Scaffold(
      body: Center(child: Text("$pascalName View")),
    );
  }
}
''';
    viewFile.writeAsStringSync(viewContent);
    print('Created: ${viewFile.path}');
  }

  // 6. Ensure lib/dependence/injection.dart exists
  ensureInjectionFile(appRoot);

  // 7. Update or create lib/router/app_router.dart
  final routerFile = File('${appRoot.path}/lib/router/app_router.dart');
  updateAppRouter(
    routerFile: routerFile,
    packageName: packageName,
    snakeName: snakeName,
    pascalName: pascalName,
    camelName: camelName,
    constantName: constantName,
  );

  // 7. Run build_runner
  print('\n--- Running build_runner ---');
  final process = await Process.start(
    'dart',
    ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    workingDirectory: appRoot.path,
    runInShell: true,
  );

  await stdout.addStream(process.stdout);
  await stderr.addStream(process.stderr);

  final exitCode = await process.exitCode;
  if (exitCode == 0) {
    print('\n============================================================');
    print('Module $pascalName generated successfully!');
    print('============================================================');
    print('Freezed State Guide:');
    print('  1. Add fields to ${pascalName}State in:');
    print('     ${stateFile.path}');
    print('     Example:');
    print('       const factory ${pascalName}State({');
    print('         @Default(\'\') String id,');
    print('         @Default(false) bool isLoading,');
    print('       }) = _${pascalName}State;');
    print('');
    print('  2. Rebuild Freezed for this module only (faster):');
    print('     dart run build_runner build --build-filter="lib/feature/$snakeName/presentation/**"');
    print('');
    print('  3. Or run in watch mode (auto-rebuilds on save):');
    print('     dart run build_runner watch --delete-conflicting-outputs');
    print('============================================================\n');
  } else {
    print('\nbuild_runner exited with code $exitCode');
  }
}

Directory findAppRoot() {
  var dir = Directory.current;
  final currentPubspec = File('${dir.path}/pubspec.yaml');
  if (currentPubspec.existsSync()) {
    final content = currentPubspec.readAsStringSync();
    if (!content.contains('name: core_bloc')) {
      return dir;
    }
  }

  final parent = dir.parent;
  final parentPubspec = File('${parent.path}/pubspec.yaml');
  if (parentPubspec.existsSync()) {
    return parent;
  }

  return dir;
}

String getPackageName(Directory appRoot) {
  final pubspecFile = File('${appRoot.path}/pubspec.yaml');
  if (pubspecFile.existsSync()) {
    final match = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true).firstMatch(pubspecFile.readAsStringSync());
    if (match != null) {
      return match.group(1)!;
    }
  }
  return 'untitled';
}

String toSnakeCase(String text) {
  return text
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}')
      .replaceAll(RegExp(r'^_+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .toLowerCase();
}

String toPascalCase(String snake) {
  return snake
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join();
}

String toCamelCase(String snake) {
  final pascal = toPascalCase(snake);
  if (pascal.isEmpty) return '';
  return pascal[0].toLowerCase() + pascal.substring(1);
}

String toConstantCase(String snake) {
  return snake.toUpperCase();
}

void updateAppRouter({
  required File routerFile,
  required String packageName,
  required String snakeName,
  required String pascalName,
  required String camelName,
  required String constantName,
}) {
  if (!routerFile.existsSync()) {
    routerFile.parent.createSync(recursive: true);
    final initialContent = '''
import 'package:flutter/material.dart';
import 'package:$packageName/feature/$snakeName/presentation/${snakeName}_view.dart';

class AppRouter {
  static const String $camelName = "/${constantName}_VIEW";

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case $camelName:
        return ${pascalName}View.router(settings);
      default: return null;
    }
  }
}
''';
    routerFile.writeAsStringSync(initialContent);
    print('Created: ${routerFile.path}');
    return;
  }

  var content = routerFile.readAsStringSync();

  // 1. Add import
  final importStatement = "import 'package:$packageName/feature/$snakeName/presentation/${snakeName}_view.dart';";
  if (!content.contains(importStatement)) {
    final lines = content.split('\n');
    int lastImportIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('import ')) {
        lastImportIndex = i;
      }
    }
    if (lastImportIndex != -1) {
      lines.insert(lastImportIndex + 1, importStatement);
      content = lines.join('\n');
    } else {
      content = '$importStatement\n$content';
    }
  }

  // 2. Add route constant
  final constantDecl = '  static const String $camelName = "/${constantName}_VIEW";';
  if (!content.contains('static const String $camelName')) {
    final classMatch = RegExp(r'class\s+AppRouter\s*\{').firstMatch(content);
    if (classMatch != null) {
      final insertIndex = classMatch.end;
      content = content.substring(0, insertIndex) +
          '\n$constantDecl' +
          content.substring(insertIndex);
    }
  }

  // 3. Add switch case
  final caseDecl = '      case $camelName:\n        return ${pascalName}View.router(settings);';
  if (!content.contains('case $camelName:')) {
    final defaultIndex = content.indexOf('default:');
    if (defaultIndex != -1) {
      content = content.substring(0, defaultIndex) +
          '$caseDecl\n' +
          content.substring(defaultIndex);
    } else {
      final switchCloseMatch = RegExp(r'switch\s*\([^\)]*\)\s*\{([^}]*)\}').firstMatch(content);
      if (switchCloseMatch != null) {
        final endOfSwitch = switchCloseMatch.end - 1;
        content = content.substring(0, endOfSwitch) +
            '$caseDecl\n    ' +
            content.substring(endOfSwitch);
      }
    }
  }

  routerFile.writeAsStringSync(content);
  print('Updated: ${routerFile.path}');
}

void ensureInjectionFile(Directory appRoot) {
  final diFile = File('${appRoot.path}/lib/dependence/injection.dart');
  if (!diFile.existsSync()) {
    diFile.parent.createSync(recursive: true);
    final content = '''
import 'package:core_bloc/core_bloc.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;

abstract final class Dependencies {
  static void initialized() => _configureDependencies();
}

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
void _configureDependencies() => getIt.init();
''';
    diFile.writeAsStringSync(content);
    print('Created: ${diFile.path}');
  }
}

void generateCleanArchitecture({
  required Directory appRoot,
  required String packageName,
  required String snakeName,
  required String pascalName,
}) {
  final featureDir = '${appRoot.path}/lib/feature/$snakeName';

  // =========================================================================
  // 1. DOMAIN LAYER
  // =========================================================================
  final domainDir = Directory('$featureDir/domain');
  final entitiesDir = Directory('${domainDir.path}/entities');
  final domainRepoDir = Directory('${domainDir.path}/repositories');
  final usecasesDir = Directory('${domainDir.path}/usecases');

  entitiesDir.createSync(recursive: true);
  domainRepoDir.createSync(recursive: true);
  usecasesDir.createSync(recursive: true);

  // 1.1 domain/repositories/<name>_repository.dart
  final domainRepoFile = File('${domainRepoDir.path}/${snakeName}_repository.dart');
  if (!domainRepoFile.existsSync()) {
    domainRepoFile.writeAsStringSync('''
abstract interface class ${pascalName}Repository {}
''');
    print('Created: ${domainRepoFile.path}');
  }

  // 1.2 domain/usecases/.gitkeep (giữ thư mục khi chưa có file)
  final gitkeepFile = File('${usecasesDir.path}/.gitkeep');
  if (!gitkeepFile.existsSync()) {
    gitkeepFile.writeAsStringSync('');
  }

  // =========================================================================
  // 2. DATA LAYER
  // =========================================================================
  final dataDir = Directory('$featureDir/data');
  final datasourceDir = Directory('${dataDir.path}/datasource');
  final modelDir = Directory('${dataDir.path}/model');
  final dataRepoDir = Directory('${dataDir.path}/repositories');

  datasourceDir.createSync(recursive: true);
  modelDir.createSync(recursive: true);
  dataRepoDir.createSync(recursive: true);

  // 2.1 data/datasource/<name>_remote.dart
  final remoteFile = File('${datasourceDir.path}/${snakeName}_remote.dart');
  if (!remoteFile.existsSync()) {
    remoteFile.writeAsStringSync('''
import 'package:core_bloc/core_bloc.dart';

@lazySingleton
class ${pascalName}Remote {}
''');
    print('Created: ${remoteFile.path}');
  }

  // 2.2 data/repositories/<name>_repository_impl.dart
  final dataRepoFile = File('${dataRepoDir.path}/${snakeName}_repository_impl.dart');
  if (!dataRepoFile.existsSync()) {
    dataRepoFile.writeAsStringSync('''
// ignore_for_file: unused_field
import 'package:core_bloc/core_bloc.dart';
import 'package:$packageName/feature/$snakeName/data/datasource/${snakeName}_remote.dart';
import 'package:$packageName/feature/$snakeName/domain/repositories/${snakeName}_repository.dart';

@LazySingleton(as: ${pascalName}Repository)
class ${pascalName}RepositoryImpl implements ${pascalName}Repository {
  final ${pascalName}Remote _remote;

  const ${pascalName}RepositoryImpl(this._remote);
}
''');
    print('Created: ${dataRepoFile.path}');
  }
}


