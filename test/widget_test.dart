import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/main.dart';
import 'package:worship_setlist/presentation/providers/database_provider.dart';

void main() {
  testWidgets('WorshipSetlistApp launches into Playlists home screen', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const WorshipSetlistApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Playlists'), findsWidgets);
    expect(find.text('No playlists yet'), findsOneWidget);
    expect(find.text('New Playlist'), findsOneWidget);

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
