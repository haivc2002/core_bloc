import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

Builder layoutRegistryBuilder(BuilderOptions options) => LayoutRegistryBuilder();

class LayoutRegistryBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['router/layout_registry.g.dart']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final glob = Glob('lib/feature/**/presentation/*_view.dart');
    final Map<String, String> routes = {};
    final Set<String> imports = {};
    
    await for (final assetId in buildStep.findAssets(glob)) {
      final content = await buildStep.readAsString(assetId);
      final unit = parseString(content: content, throwIfDiagnostics: false).unit;
      final classes = unit.declarations.whereType<ClassDeclaration>();
      for (final declaration in classes) {
        for (final annotation in declaration.metadata) {
          if (annotation.name.name != 'RegisterLayout') continue;
          final arguments = annotation.arguments?.arguments;
          if (arguments == null || arguments.length != 1) continue;

          final routeName = arguments.single.toSource();
          final className = declaration.namePart.typeName.lexeme;
          final hasBuilder = declaration.body.members.any(
            (member) => switch (member) {
              MethodDeclaration() =>
                member.isStatic && member.name.lexeme == 'builder',
              FieldDeclaration() => member.isStatic &&
                  member.fields.variables.any(
                    (variable) => variable.name.lexeme == 'builder',
                  ),
              _ => false,
            },
          );
          imports.add("import 'package:${assetId.package}/${assetId.path.replaceFirst('lib/', '')}';");
          routes[routeName] = hasBuilder
              ? '(args) => $className.builder(args)'
              : '(args) => Builder(builder: (context) {\n'
                  '      final route = $className.router(RouteSettings(name: $routeName, arguments: args));\n'
                  '      return route.builder(context);\n'
                  '    })';
        }
      }
    }

    if (routes.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln("// GENERATED CODE - DO NOT MODIFY BY HAND");
    buffer.writeln();
    buffer.writeln("import 'package:flutter/material.dart';");
    buffer.writeln("import 'package:${buildStep.inputId.package}/router/app_router.dart';");
    for (var imp in imports) {
      buffer.writeln(imp);
    }
    
    buffer.writeln();
    buffer.writeln("class LayoutRegistry {");
    buffer.writeln("  static final Map<String, Widget Function(Object? args)> _registry = {};");
    buffer.writeln();
    buffer.writeln("  static void _register(String routeName, Widget Function(Object? args) builder) {");
    buffer.writeln("    _registry[routeName] = builder;");
    buffer.writeln("  }");
    buffer.writeln();
    buffer.writeln("  static Widget takeOut(String routeName, {Object? args}) {");
    buffer.writeln("    final builder = _registry[routeName];");
    buffer.writeln("    if (builder != null) {");
    buffer.writeln("      return builder(args);");
    buffer.writeln("    }");
    buffer.writeln("    return Center(child: Text('Route not found: \$routeName'));");
    buffer.writeln("  }");
    buffer.writeln();
    buffer.writeln("  static void init() {");
    for (var entry in routes.entries) {
      buffer.writeln("    _register(${entry.key}, ${entry.value});");
    }
    buffer.writeln("  }");
    buffer.writeln("}");

    final outputId = AssetId(buildStep.inputId.package, 'lib/router/layout_registry.g.dart');
    await buildStep.writeAsString(outputId, buffer.toString());
  }
}
