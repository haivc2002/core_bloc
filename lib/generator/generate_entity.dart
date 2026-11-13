// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, depend_on_referenced_packages

import 'dart:io';
import 'package:path/path.dart' as p;

class ClassInfo {
  final String name;
  final List<FieldInfo> fields;
  ClassInfo(this.name, this.fields);
}

class FieldInfo {
  final String type;
  final String name;
  final bool hasAnnotation;
  FieldInfo(this.type, this.name, this.hasAnnotation);
}

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run lib/generator/generate_entity.dart <path_to_model_file.dart>');
    return;
  }

  var filePath = args[0];
  var file = File(filePath);
  
  if (!file.existsSync()) {
    // Try to find the file smartly by scanning the lib directory
    final libDir = Directory('lib');
    if (libDir.existsSync()) {
      var rawPath = filePath.replaceAll(r'\', '/');
      if (rawPath.endsWith('.dart')) {
        rawPath = rawPath.substring(0, rawPath.length - 5);
      }
      final searchParts = rawPath.split('/').where((p) => p.isNotEmpty).toList();
      var targetName = searchParts.isNotEmpty ? searchParts.last : '';
      if (targetName.startsWith('model_')) {
        targetName = targetName.substring('model_'.length);
      }

      final candidateBasenames = <String>{
        '$targetName.dart',
        'model_$targetName.dart',
        '${targetName}_model.dart',
      };

      final entities = libDir.listSync(recursive: true);
      File? bestMatch;

      for (final entity in entities) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.endsWith('.freezed.dart')) {
          final normalizedPath = entity.path.replaceAll(r'\', '/');
          final fileBase = p.basename(normalizedPath);

          if (candidateBasenames.contains(fileBase)) {
            bool matchesParts = true;
            for (final part in searchParts.take(searchParts.length - 1)) {
              if (!normalizedPath.contains(part)) {
                matchesParts = false;
                break;
              }
            }
            if (matchesParts) {
              bestMatch = entity;
              break;
            }
          }
        }
      }

      // If still not found and input might be a feature/directory name (e.g. "setting")
      if (bestMatch == null) {
        for (final entity in entities) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart') &&
              !entity.path.endsWith('.freezed.dart')) {
            final normalizedPath = entity.path.replaceAll(r'\', '/');
            if (normalizedPath.contains('/data/model/') &&
                searchParts.any((part) => normalizedPath.contains('/$part/'))) {
              bestMatch = entity;
              break;
            }
          }
        }
      }

      if (bestMatch != null) {
        filePath = bestMatch.path;
        file = bestMatch;
        print('⚡ Tự động tìm thấy file model: $filePath');
      }
    }
  }

  if (!file.existsSync()) {
    print('File not found: ${args[0]}');
    return;
  }

  final content = file.readAsStringSync();
  final allClasses = _parseClasses(content);
  final classes = _filterEntityClasses(allClasses);

  if (classes.isEmpty) {
    print('No classes with @EntityField or @entityField annotations found.');
    return;
  }

  final entityFilename = _getEntityFilename(p.basename(filePath));
  final defaultEntityName = _pascalCase(entityFilename.replaceAll('_entity.dart', ''));

  final entityNameMap = <String, String>{};
  for (final c in classes) {
    if (classes.length == 1 && (c.name == 'Data' || c.name == 'Item' || c.name == 'Result')) {
      entityNameMap[c.name] = '${defaultEntityName}Entity';
    } else {
      entityNameMap[c.name] = '${_cleanClassName(c.name)}Entity';
    }
  }
  
  String targetDir = p.dirname(filePath);
  // Check if it's in a standard Clean Architecture path structure (supports both data/model and data/models)
  final normalizedTargetDir = targetDir.replaceAll(r'\', '/');
  if (RegExp(r'/data/models?(/|$)').hasMatch(normalizedTargetDir)) {
    final candidateEntities = normalizedTargetDir.replaceAll(RegExp(r'/data/models?'), '/domain/entities');
    final candidateEntity = normalizedTargetDir.replaceAll(RegExp(r'/data/models?'), '/domain/entity');

    if (Directory(candidateEntities).existsSync()) {
      targetDir = candidateEntities;
    } else if (Directory(candidateEntity).existsSync()) {
      targetDir = candidateEntity;
    } else {
      targetDir = candidateEntities;
    }

    final dir = Directory(targetDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  final entityFilePath = p.join(targetDir, entityFilename);

  _generateEntityFile(entityFilePath, classes, entityNameMap);
  _injectExtensionToModel(file, content, classes, allClasses, entityNameMap, entityFilePath);
}

List<ClassInfo> _parseClasses(String content) {
  final lines = content.split('\n');
  final classes = <ClassInfo>[];
  
  bool insideClass = false;
  int braceCount = 0;
  String? currentClassName;
  List<FieldInfo> currentFields = [];
  bool pendingAnnotation = false;

  final classRegex = RegExp(r'class\s+([A-Za-z0-9_]+)');
  final fieldRegex = RegExp(r'^(?:final\s+|const\s+|var\s+|late\s+)?([A-Za-z0-9_<>?]+)\s+([A-Za-z0-9_]+)\s*;');
  final ignoredKeywords = {'return', 'throw', 'yield', 'case', 'break', 'continue', 'import', 'export', 'part', 'default'};

  for (var line in lines) {
    var trimmed = line.trim();

    if (!insideClass) {
      final match = classRegex.firstMatch(line);
      if (match != null) {
        insideClass = true;
        currentClassName = match.group(1);
        currentFields = [];
        braceCount = 0;
        if (line.contains('{')) braceCount += '{'.allMatches(line).length;
      }
    } else {
      bool isAnnotation = trimmed.startsWith('@EntityField') || trimmed.startsWith('@entityField');
      if (isAnnotation) {
        pendingAnnotation = true;
      } else if (braceCount == 1 && trimmed.isNotEmpty && !trimmed.startsWith('//')) {
        final match = fieldRegex.firstMatch(trimmed);
        if (match != null && !ignoredKeywords.contains(match.group(1))) {
          currentFields.add(FieldInfo(match.group(1)!, match.group(2)!, pendingAnnotation));
          pendingAnnotation = false;
        } else if (trimmed.contains('(')) {
          pendingAnnotation = false;
        }
      }

      if (trimmed.contains('{')) braceCount += '{'.allMatches(trimmed).length;
      if (trimmed.contains('}')) braceCount -= '}'.allMatches(trimmed).length;

      if (braceCount <= 0 && insideClass) {
        if (currentFields.isNotEmpty && currentClassName != null) {
          classes.add(ClassInfo(currentClassName, currentFields));
        }
        insideClass = false;
      }
    }
  }

  return classes;
}

List<ClassInfo> _filterEntityClasses(List<ClassInfo> classes) {
  final classMap = {for (final c in classes) c.name: c};
  final selectedClasses = <String, List<FieldInfo>>{};

  // Pass 1: find explicitly annotated classes
  for (final cls in classes) {
    final annotatedFields = cls.fields.where((f) => f.hasAnnotation).toList();
    if (annotatedFields.isNotEmpty) {
      selectedClasses[cls.name] = annotatedFields;
    }
  }

  // Pass 2: recursively collect referenced nested classes
  final queue = List<String>.from(selectedClasses.keys);
  while (queue.isNotEmpty) {
    final currentClassName = queue.removeAt(0);
    final fields = selectedClasses[currentClassName]!;

    for (final field in fields) {
      final cleanType = field.type.replaceAll('?', '').replaceAll(RegExp(r'List<|>'), '');
      if (classMap.containsKey(cleanType) && !selectedClasses.containsKey(cleanType)) {
        final nestedClass = classMap[cleanType]!;
        final nestedAnnotated = nestedClass.fields.where((f) => f.hasAnnotation).toList();
        // If nested class has annotations, use annotated fields; otherwise use all fields
        final nestedFields = nestedAnnotated.isNotEmpty ? nestedAnnotated : nestedClass.fields;
        selectedClasses[cleanType] = nestedFields;
        queue.add(cleanType);
      }
    }
  }

  // Return in original order from classes
  return classes
      .where((c) => selectedClasses.containsKey(c.name))
      .map((c) => ClassInfo(c.name, selectedClasses[c.name]!))
      .toList();
}

String _getEntityFilename(String modelFilename) {
  return '${modelFilename
      .replaceAll('model_', '')
      .replaceAll('_model', '')
      .replaceAll('dto_', '')
      .replaceAll('_dto', '')
      .replaceAll('.dart', '')}_entity.dart';
}

String _pascalCase(String text) {
  return text
      .split(RegExp(r'[_\-\s]'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
}

String _cleanClassName(String name) {
  return name
      .replaceAll(RegExp(r'^Model'), '')
      .replaceAll(RegExp(r'Model$'), '')
      .replaceAll(RegExp(r'^Dto'), '')
      .replaceAll(RegExp(r'Dto$'), '');
}

void _generateEntityFile(String path, List<ClassInfo> classes, Map<String, String> entityNameMap) {
  final buffer = StringBuffer();

  for (final classInfo in classes) {
    final entityName = entityNameMap[classInfo.name] ?? '${_cleanClassName(classInfo.name)}Entity';
    buffer.writeln('class $entityName {');
    for (final field in classInfo.fields) {
      String newType = field.type;
      final cleanType = field.type.replaceAll('?', '').replaceAll(RegExp(r'List<|>'), '');
      final isNestedEntity = classes.any((c) => c.name == cleanType);
      
      if (isNestedEntity) {
        final nestedEntityName = entityNameMap[cleanType] ?? '${_cleanClassName(cleanType)}Entity';
        newType = newType.replaceAll(RegExp(r'\b' + RegExp.escape(cleanType) + r'\b'), nestedEntityName);
      }
      buffer.writeln('  final $newType ${field.name};');
    }
    buffer.writeln();
    buffer.writeln('  const $entityName({');
    for (final field in classInfo.fields) {
      if (field.type.endsWith('?')) {
        buffer.writeln('    this.${field.name},');
      } else {
        buffer.writeln('    required this.${field.name},');
      }
    }
    buffer.writeln('  });');
    buffer.writeln('}');
    buffer.writeln();
  }

  File(path).writeAsStringSync(buffer.toString());
  print('Generated $path');
}

String _removeExtension(String content, String extensionName) {
  final pattern = RegExp(r'extension\s+' + RegExp.escape(extensionName) + r'\b');
  while (true) {
    final match = pattern.firstMatch(content);
    if (match == null) break;
    final startIndex = match.start;
    final openBraceIndex = content.indexOf('{', startIndex);
    if (openBraceIndex == -1) break;

    int depth = 0;
    int endIndex = openBraceIndex;
    for (int i = openBraceIndex; i < content.length; i++) {
      if (content[i] == '{') {
        depth++;
      } else if (content[i] == '}') {
        depth--;
        if (depth == 0) {
          endIndex = i + 1;
          break;
        }
      }
    }

    var replaceStart = startIndex;
    while (replaceStart > 0 && (content[replaceStart - 1] == ' ' || content[replaceStart - 1] == '\t')) {
      replaceStart--;
    }
    if (replaceStart > 0 && content[replaceStart - 1] == '\n') {
      replaceStart--;
    }
    content = content.substring(0, replaceStart) + content.substring(endIndex);
  }
  return content;
}

void _injectExtensionToModel(
  File file,
  String content,
  List<ClassInfo> classes,
  List<ClassInfo> allClasses,
  Map<String, String> entityNameMap,
  String entityFilePath,
) {
  var newContent = content;

  // 1. Ensure core_bloc is imported (needed for Result)
  if (!newContent.contains("import 'package:core_bloc/core_bloc.dart';")) {
    if (newContent.contains("import 'package:core_bloc/annotations/entity_field.dart';")) {
      newContent = newContent.replaceAll(
        "import 'package:core_bloc/annotations/entity_field.dart';",
        "import 'package:core_bloc/core_bloc.dart';",
      );
    } else {
      final importRegex = RegExp(r'^import\s+.*;', multiLine: true);
      final matches = importRegex.allMatches(newContent);
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        newContent = newContent.replaceRange(lastMatch.end, lastMatch.end, "\nimport 'package:core_bloc/core_bloc.dart';");
      } else {
        newContent = "import 'package:core_bloc/core_bloc.dart';\n" + newContent;
      }
    }
  }

  // 2. Remove any previous import of this entity filename
  final entityFileName = p.basename(entityFilePath);
  final oldImportRegex = RegExp('^import\\s+[\'"][^\'"]*' + RegExp.escape(entityFileName) + '[\'"];?\\s*\\n?', multiLine: true);
  newContent = newContent.replaceAll(oldImportRegex, '');

  // 3. Ensure import of entity file is present
  final relativePath = p.relative(entityFilePath, from: p.dirname(file.path)).replaceAll(r'\', '/');
  final importStatement = "import '$relativePath';";
  final importRegex = RegExp(r'^import\s+.*;', multiLine: true);
  final matches = importRegex.allMatches(newContent);
  if (matches.isNotEmpty) {
    final lastMatch = matches.last;
    newContent = newContent.replaceRange(lastMatch.end, lastMatch.end, '\n$importStatement');
  } else {
    newContent = '$importStatement\n\n' + newContent;
  }

  // 4. Clean up any existing extensions for these entities and wrappers
  for (final classInfo in classes) {
    final entityName = entityNameMap[classInfo.name] ?? '${_cleanClassName(classInfo.name)}Entity';
    final extensionNames = [
      '${entityName}Extension',
      'Result${entityName}Extension',
      'FutureResult${entityName}Extension',
      'List${entityName}Extension',
      'ResultList${entityName}Extension',
      'FutureResultList${entityName}Extension',
      '${classInfo.name}EntityExtension',
      'Result${classInfo.name}EntityExtension',
      'FutureResult${classInfo.name}EntityExtension',
      'List${classInfo.name}EntityExtension',
      'ResultList${classInfo.name}EntityExtension',
      'FutureResultList${classInfo.name}EntityExtension',
      'Result${classInfo.name}Extension',
      'FutureResult${classInfo.name}Extension',
      'List${classInfo.name}Extension',
      'ResultList${classInfo.name}Extension',
      'FutureResultList${classInfo.name}Extension',
    ];
    for (final extName in extensionNames) {
      newContent = _removeExtension(newContent, extName);
    }
  }

  for (final wrapper in allClasses) {
    final wrapperExtNames = [
      '${wrapper.name}EntityExtension',
      'Result${wrapper.name}EntityExtension',
      'FutureResult${wrapper.name}EntityExtension',
    ];
    for (final extName in wrapperExtNames) {
      newContent = _removeExtension(newContent, extName);
    }
  }

  // 5. Inject new extensions for all classes
  final extensionBuffer = StringBuffer();
  for (final classInfo in classes) {
    final entityName = entityNameMap[classInfo.name] ?? '${_cleanClassName(classInfo.name)}Entity';
    final extensionName = '${classInfo.name}EntityExtension';

    extensionBuffer.writeln('\nextension $extensionName on ${classInfo.name} {');
    extensionBuffer.writeln('  $entityName toEntity() {');
    extensionBuffer.writeln('    return $entityName(');
    for (final field in classInfo.fields) {
      final cleanType = field.type.replaceAll('?', '').replaceAll(RegExp(r'List<|>'), '');
      final isNestedEntity = classes.any((c) => c.name == cleanType);

      if (isNestedEntity) {
        final isNullable = field.type.endsWith('?');
        final q = isNullable ? '?' : '';
        if (field.type.contains('List<')) {
          extensionBuffer.writeln('      ${field.name}: ${field.name}$q.map((e) => e.toEntity()).toList(),');
        } else {
          extensionBuffer.writeln('      ${field.name}: ${field.name}$q.toEntity(),');
        }
      } else {
        extensionBuffer.writeln('      ${field.name}: ${field.name},');
      }
    }
    extensionBuffer.writeln('    );');
    extensionBuffer.writeln('  }');
    extensionBuffer.writeln('}');

    extensionBuffer.writeln('\nextension Result${classInfo.name}EntityExtension on Result<${classInfo.name}> {');
    extensionBuffer.writeln('  Result<$entityName> toEntity() => map((model) => model.toEntity());');
    extensionBuffer.writeln('}');

    extensionBuffer.writeln('\nextension FutureResult${classInfo.name}EntityExtension on Future<Result<${classInfo.name}>> {');
    extensionBuffer.writeln('  Future<Result<$entityName>> toEntity() async => (await this).toEntity();');
    extensionBuffer.writeln('}');

    extensionBuffer.writeln('\nextension List${classInfo.name}EntityExtension on List<${classInfo.name}> {');
    extensionBuffer.writeln('  List<$entityName> toEntity() => map((e) => e.toEntity()).toList();');
    extensionBuffer.writeln('}');

    extensionBuffer.writeln('\nextension ResultList${classInfo.name}EntityExtension on Result<List<${classInfo.name}>> {');
    extensionBuffer.writeln('  Result<List<$entityName>> toEntity() => map((list) => list.map((e) => e.toEntity()).toList());');
    extensionBuffer.writeln('}');

    extensionBuffer.writeln('\nextension FutureResultList${classInfo.name}EntityExtension on Future<Result<List<${classInfo.name}>>> {');
    extensionBuffer.writeln('  Future<Result<List<$entityName>>> toEntity() async => (await this).toEntity();');
    extensionBuffer.writeln('}');
  }

  // 6. Inject extensions for wrapper models (e.g. ModelUser wrapping Data/User)
  for (final wrapper in allClasses) {
    if (classes.any((c) => c.name == wrapper.name)) continue;

    for (final field in wrapper.fields) {
      final cleanFieldType = field.type.replaceAll('?', '').replaceAll(RegExp(r'List<|>'), '');
      if (classes.any((c) => c.name == cleanFieldType)) {
        final targetEntityName = entityNameMap[cleanFieldType] ?? '${_cleanClassName(cleanFieldType)}Entity';
        final isList = field.type.contains('List<');
        final isNullable = field.type.endsWith('?');
        final q = isNullable ? '?' : '';

        if (isList) {
          extensionBuffer.writeln('\nextension ${wrapper.name}EntityExtension on ${wrapper.name} {');
          extensionBuffer.writeln('  List<$targetEntityName> toEntity() => ${field.name}$q.map((e) => e.toEntity()).toList() ?? const [];');
          extensionBuffer.writeln('}');
          extensionBuffer.writeln('\nextension Result${wrapper.name}EntityExtension on Result<${wrapper.name}> {');
          extensionBuffer.writeln('  Result<List<$targetEntityName>> toEntity() => map((model) => model.toEntity());');
          extensionBuffer.writeln('}');
          extensionBuffer.writeln('\nextension FutureResult${wrapper.name}EntityExtension on Future<Result<${wrapper.name}>> {');
          extensionBuffer.writeln('  Future<Result<List<$targetEntityName>>> toEntity() async => (await this).toEntity();');
          extensionBuffer.writeln('}');
        } else {
          extensionBuffer.writeln('\nextension ${wrapper.name}EntityExtension on ${wrapper.name} {');
          extensionBuffer.writeln('  $targetEntityName toEntity() => ${field.name}$q.toEntity() ?? const $targetEntityName();');
          extensionBuffer.writeln('}');
          extensionBuffer.writeln('\nextension Result${wrapper.name}EntityExtension on Result<${wrapper.name}> {');
          extensionBuffer.writeln('  Result<$targetEntityName> toEntity() => map((model) => model.toEntity());');
          extensionBuffer.writeln('}');
          extensionBuffer.writeln('\nextension FutureResult${wrapper.name}EntityExtension on Future<Result<${wrapper.name}>> {');
          extensionBuffer.writeln('  Future<Result<$targetEntityName>> toEntity() async => (await this).toEntity();');
          extensionBuffer.writeln('}');
        }
        break;
      }
    }
  }

  newContent = newContent.trimRight() + '\n' + extensionBuffer.toString();
  file.writeAsStringSync(newContent);
  print('Updated ${file.path} with toEntity extensions');
}
