import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:dart_style/dart_style.dart';

Builder shareBuilder(BuilderOptions options) => ShareApiBuilder();

class ShareApiBuilder implements Builder {
  static const _accessFile = 'feature_access.g.dart';
  static const _accessPath = 'shared/$_accessFile';
  static const _bindingsPath = 'shared/feature_access_bindings.g.dart';

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': [_accessPath, _bindingsPath],
  };

  String? annotation(Element element, String type) {
    for (final item in element.metadata.annotations) {
      final value = item.computeConstantValue();
      final owner = value?.type?.element;
      if (owner?.name == type &&
          owner?.library?.uri.toString() ==
              'package:core_bloc/annotations/share_public.dart') {
        return value?.getField('name')?.toStringValue() ?? '';
      }
    }
    return null;
  }

  String publicType(FormalParameterElement parameter) {
    return renderType(parameter.type);
  }

  final typeImports = <String, String>{};

  String renderType(DartType type) {
    if (type is InterfaceType) {
      final element = type.element;
      final name = element.name!;
      if (name.startsWith('_')) {
        throw StateError(
          'Private type $name cannot be exposed by PublicState/PublicEvent.',
        );
      }
      final uri = element.library.uri.toString();
      final prefix = uri == 'dart:core'
          ? ''
          : '${typeImports.putIfAbsent(uri, () => 'public_type_${typeImports.length}')}.';
      final arguments = type.typeArguments.isEmpty
          ? ''
          : '<${type.typeArguments.map(renderType).join(', ')}>';
      final nullable = type.nullabilitySuffix == NullabilitySuffix.question
          ? '?'
          : '';
      return '$prefix$name$arguments$nullable';
    }
    if (type is DynamicType || type is VoidType || type is NeverType) {
      return type.getDisplayString();
    }
    throw StateError(
      'Unsupported public type ${type.getDisplayString()}. Use a public class or value type.',
    );
  }

  @override
  Future<void> build(BuildStep step) async {
    commandCallbacks.clear();
    commandSignatures.clear();
    typeImports.clear();
    final classes = <ClassElement>[];
    final imports = <String>{};
    await for (final asset in step.findAssets(
      Glob('lib/feature/**/presentation/*_bloc.dart'),
    )) {
      final library = await step.resolver.libraryFor(asset);
      classes.addAll(library.classes);
    }
    final names = <String>{'bind', 'unbind'};
    void reserve(String name) {
      if (!RegExp(r'^[a-zA-Z][\w$]*$').hasMatch(name) || !names.add(name)) {
        throw StateError('Invalid or duplicate shared API name: $name');
      }
    }

    final api = StringBuffer(
      "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'package:flutter/foundation.dart';\nimport 'package:core_bloc/share/share.dart';\n\nfinal featAccess = FeatureAccess();\n\nclass FeatureAccess {\n",
    );
    final bindings = StringBuffer();
    final registrations = <String>[];
    for (final bloc in classes.where(
      (c) => c.supertype?.element.name == 'BaseBloc',
    )) {
      final arguments = bloc.supertype!.typeArguments;
      final eventType = arguments[0].element;
      final state = arguments[1].element;
      if (state is! ClassElement) continue;
      final commands = classes
          .where(
            (c) =>
                c.supertype?.element == eventType &&
                annotation(c, 'PublicEvent') != null,
          )
          .toList();
      final fields = state.constructors
          .expand((c) => c.formalParameters)
          .where((p) => annotation(p, 'PublicState') != null)
          .toList();
      if (commands.isEmpty && fields.isEmpty) continue;
      final owner = bloc.name!;
      registrations.add(
        'PublicRegistry.register<$owner>((bloc) => bind$owner(bloc));',
      );
      imports.add("import '${bloc.library.uri}';");
      final setters = <String>[];
      final clears = <String>[];
      final updates = <String>[];
      for (final command in commands) {
        final override = annotation(command, 'PublicEvent')!;
        final className = command.name!;
        final name = override.isEmpty
            ? '${className[0].toLowerCase()}${className.substring(1)}'
            : override;
        reserve(name);
        final constructor = command.unnamedConstructor;
        if (constructor == null) {
          throw StateError('$className needs an unnamed constructor.');
        }
        final required = <String>[];
        final optional = <String>[];
        final named = <String>[];
        final calls = <String>[];
        for (final p in constructor.formalParameters) {
          final declaration =
              '${p.isRequiredNamed ? 'required ' : ''}${publicType(p)} ${p.name}${p.defaultValueCode == null ? '' : ' = ${p.defaultValueCode}'}';
          if (p.isNamed) {
            named.add(declaration);
          } else if (p.isOptionalPositional) {
            optional.add(declaration);
          } else {
            required.add(declaration);
          }
          calls.add('${p.isNamed ? '${p.name}: ' : ''}${p.name}');
        }
        final params = [
          ...required,
          if (optional.isNotEmpty) '[${optional.join(', ')}]',
          if (named.isNotEmpty) '{${named.join(', ')}',
        ].join(', ');
        final types = constructor.formalParameters.map(publicType).join(', ');
        // Store a positional callback internally; public syntax preserves the constructor.
        api.writeln('void Function($types)? _${name}Handler;');
        api.writeln(
          'void $name($params) { final handler = _${name}Handler; if (handler == null) throw StateError("$owner is not active"); handler(${constructor.formalParameters.map((p) => p.name).join(', ')}); }',
        );
        final callbackParams = constructor.formalParameters
            .map((p) => p.name)
            .join(', ');
        setters.add(
          '_${name}Handler = ($callbackParams) => send$className(${constructor.formalParameters.map((p) => p.name).join(', ')});',
        );
        clears.add('_${name}Handler = null;');
        commandCallbacks[name] =
            '($callbackParams) => bloc.add($className(${calls.join(', ')}))';
        commandSignatures[name] =
            'required void Function($types) send$className';
      }
      for (final field in fields) {
        final override = annotation(field, 'PublicState')!;
        final name = override.isEmpty ? field.name! : override;
        reserve(name);
        reserve('${name}Stream');
        reserve('${name}Listenable');
        final type = publicType(field);
        api.writeln(
          'final _$name = PublicValue<$type>();\n$type get $name => _$name.value;\nStream<$type> get ${name}Stream => _$name.stream;\nValueListenable<$type> get ${name}Listenable => _$name;',
        );
        updates.add('_$name.publish(${field.name});');
        clears.add('_$name.disconnect();');
      }
      api.writeln(
        'Object? _owner$owner;\nvoid bind$owner(Object owner, {${commands.map((c) {
          final n = annotation(c, 'PublicEvent')!;
          final name = n.isEmpty ? '${c.name![0].toLowerCase()}${c.name!.substring(1)}' : n;
          return commandSignatures[name];
        }).join(', ')}}) { if (_owner$owner != null) { throw StateError("$owner already active"); } _owner$owner = owner; ${setters.join()} }',
      );
      api.writeln(
        'void publish$owner(Object owner, {${fields.map((p) => 'required ${publicType(p)} ${p.name}').join(', ')}}) { if (!identical(_owner$owner, owner)) return; ${updates.join()} }',
      );
      api.writeln(
        'void unbind$owner(Object owner) { if (!identical(_owner$owner, owner)) return; _owner$owner = null; ${clears.join()} }',
      );
      bindings.writeln(
        'Future<void> Function() bind$owner($owner bloc, {FeatureAccess? target}) {\nfinal access = target ?? featAccess;\naccess.bind$owner(bloc, ${commands.map((c) {
          final n = annotation(c, 'PublicEvent')!;
          final name = n.isEmpty ? '${c.name![0].toLowerCase()}${c.name!.substring(1)}' : n;
          return 'send${c.name}: ${commandCallbacks[name]}';
        }).join(', ')});\nvoid publish() => access.publish$owner(bloc, ${fields.map((p) => '${p.name}: bloc.state.${p.name}').join(', ')});\npublish();\nfinal subscription = bloc.stream.listen((_) => publish(), onDone: () => access.unbind$owner(bloc));\nreturn () async { access.unbind$owner(bloc); await subscription.cancel(); };\n}',
      );
    }
    if (registrations.isEmpty) return;

    api.writeln('}');
    final formatter = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    );
    final publicImports = typeImports.entries
        .map((e) => "import '${e.key}' as ${e.value};")
        .join('\n');
    await step.writeAsString(
      AssetId(step.inputId.package, 'lib/$_accessPath'),
      formatter.format(
        api
            .toString()
            .replaceFirst(
              "import 'package:flutter/foundation.dart';",
              "$publicImports\nimport 'package:flutter/foundation.dart';",
            )
            .replaceAll(', {}', ''),
      ),
    );
    final output =
        "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'package:core_bloc/share/public_registry.dart';\nimport '$_accessFile';\n${imports.join('\n')}\nvoid initializeFeatureAccess() { ${registrations.join()} }\n$bindings";
    await step.writeAsString(
      AssetId(step.inputId.package, 'lib/$_bindingsPath'),
      formatter.format(output.replaceAll('(bloc, )', '(bloc)')),
    );
  }

  final commandCallbacks = <String, String>{};
  final commandSignatures = <String, String>{};
}
