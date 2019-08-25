import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> args) async {
  // If we're run from the `tools` dir, set the cwd to the repo root.
  if (path.basename(Directory.current.path) == 'tools')
    Directory.current = Directory.current.parent.parent;

  final String flutterPackagePath = path.absolute('packages/flutter/lib');

  print('Setting up an analysis context...');

  final List<String> includedPaths = <String>[flutterPackagePath];
  final AnalysisContextCollection collection =
      AnalysisContextCollection(includedPaths: includedPaths);

  if (collection.contexts.length != 1) {
    fail('expected one analysis context, found ${collection.contexts.length}');
  }

  final AnalysisContext context = collection.contexts.first;
  final AnalysisSession session = context.currentSession;

  // Future<ErrorsResult> getErrors(String path);

  final List<String> files = context.contextRoot.analyzedFiles().toList();

  print('Scanning Dart files...');
  final List<String> libraryFiles = <String>[];
  for (String file in files) {
    final SourceKind kind = await session.getSourceKind(file);
    if (kind == SourceKind.LIBRARY) {
      libraryFiles.add(file);
    }
  }
  print('  ${libraryFiles.length} dart files');

  print("Resolving class 'Widget'...");

  final LibraryElement widgetsLibrary = await session
      .getLibraryByUri('package:flutter/src/widgets/framework.dart');

  final ClassElement widgetClass = widgetsLibrary.getType('Widget');

  print('Resolving widget subclasses...');
  final List<ClassElement> classes = <ClassElement>[];
  for (String file in libraryFiles) {
    final ResolvedLibraryResult resolvedLibraryResult =
        await session.getResolvedLibrary(file);

    final LibraryElement lib = resolvedLibraryResult.element;
    for (Element element in lib.topLevelElements) {
      if (element is! ClassElement) {
        continue;
      }

      final ClassElement clazz = element;
      if (clazz.allSupertypes.contains(widgetClass.type)) {
        // hide private classes
        final String name = clazz.name;
        if (!name.startsWith('_')) {
          classes.add(clazz);
        }
      }
    }
  }
  print('  ${classes.length} widgets');

  // Normalize the output json.
  classes.sort((ClassElement a, ClassElement b) => a.name.compareTo(b.name));

  // TODO(devoncarew): Output to a better file location.
  final File file = File('widgets.json');
  print('Generating ${path.relative(path.absolute(file.path))}...');
  final List<Map<String, Object>> json = <Map<String, Object>>[];
  for (ClassElement c in classes) {
    json.add(_convertToJson(c, widgetClass));
  }
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  final String output = encoder.convert(json);
  file.writeAsStringSync('$output\n');
  final int kb = (file.lengthSync() + 1023) ~/ 1024;
  print('  ${kb}kb');
}

Map<String, Object> _convertToJson(
  ClassElement classElement,
  ClassElement widgetClass,
) {
  // flutter/src/material/about.dart
  final String filePath = classElement.library.librarySource.uri.path;
  final String libraryName = filePath.split('/')[2];

  String summary;
  final ElementAnnotation summaryAnnotation =
      _getAnnotations(classElement, 'Summary')
          .firstWhere((ElementAnnotation _) => true, orElse: () => null);
  if (summaryAnnotation != null) {
    final DartObject text =
        summaryAnnotation.computeConstantValue().getField('text');
    summary = text.toStringValue().trim();
  }

  final List<String> categories = _getAnnotations(classElement, 'Category')
      .map((ElementAnnotation annotation) {
    return annotation.computeConstantValue().getField('value').toStringValue();
  }).toList()
        ..sort();

  final List<String> subcategories =
      _getAnnotations(classElement, 'Subcategory')
          .map((ElementAnnotation elementAnnotation) {
    return elementAnnotation
        .computeConstantValue()
        .getField('value')
        .toStringValue();
  }).toList()
            ..sort();

  final Map<String, Object> m = <String, Object>{};
  m['name'] = classElement.name;
  if (classElement != widgetClass) {
    m['parent'] = classElement.supertype.name;
  }
  m['library'] = libraryName;
  m['categories'] = categories;
  m['subcategories'] = subcategories;
  if (classElement.isAbstract) {
    m['abstract'] = true;
  }
  m['description'] = summary ?? _singleLine(classElement.documentationComment);

  return m;
}

List<ElementAnnotation> _getAnnotations(ClassElement c, String name) {
  return c.metadata.where((ElementAnnotation a) {
    if (a.element is ConstructorElement) {
      return a.element.enclosingElement.name == name;
    } else {
      return false;
    }
  }).toList();
}

String _singleLine(String docs) {
  if (docs == null) {
    return '';
  }

  return docs
      .split('\n')
      .map((String line) {
        return line.startsWith('/// ')
            ? line.substring(4)
            : line == '///' ? '' : line;
      })
      .map((String line) => line.trimRight())
      .takeWhile((String line) => line.isNotEmpty)
      .join(' ');
}

void fail(String message) {
  print(message);
  exit(1);
}
