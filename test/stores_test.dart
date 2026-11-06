import 'dart:io';

import 'package:cal_scanner/core/privacy/photo_cleaner.dart';
import 'package:cal_scanner/features/chat/data/chat_store.dart';
import 'package:cal_scanner/features/memory/data/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('MemoryStore', () {
    setUp(() => freshPrefs());

    test('add, dedupe, edit, delete', () async {
      final a = await MemoryStore.add('I get acid reflux');
      expect(a, isNotNull);
      expect(await MemoryStore.add('  i GET acid reflux  '), isNull, reason: 'duplicate');
      expect(await MemoryStore.add('   '), isNull, reason: 'empty');
      await MemoryStore.add('Vegetarian', source: 'ai');
      var items = await MemoryStore.items();
      expect(items.length, 2);
      expect(items.first.text, 'Vegetarian'); // newest first
      expect(items.first.source, 'ai');
      await MemoryStore.update(a!.id, 'I get acid reflux and gastritis');
      await MemoryStore.remove(items.first.id);
      items = await MemoryStore.items();
      expect(items.single.text, 'I get acid reflux and gastritis');
    });

    test('long text and the item cap are enforced', () async {
      final m = await MemoryStore.add('x' * 1000);
      expect(m!.text.length, MemoryStore.maxTextLength);
      for (var i = 0; i < 120; i++) {
        await MemoryStore.add('fact $i');
      }
      expect((await MemoryStore.items()).length, MemoryStore.maxItems);
    });

    test('health notes save, trim, truncate and clear', () async {
      await MemoryStore.setHealthNotes('  gastric problems  ');
      expect(await MemoryStore.healthNotes(), 'gastric problems');
      await MemoryStore.setHealthNotes('y' * 5000);
      expect((await MemoryStore.healthNotes()).length, MemoryStore.maxHealthLength);
      await MemoryStore.setHealthNotes('');
      expect(await MemoryStore.healthNotes(), '');
    });

    test('prompt block contains notes and memories, and stays a sensible size', () async {
      await MemoryStore.setHealthNotes('Acid reflux, no spicy food');
      await MemoryStore.add('Lactose intolerant');
      var block = await MemoryStore.promptBlock();
      expect(block, contains('HEALTH NOTES'));
      expect(block, contains('Acid reflux, no spicy food'));
      expect(block, contains('- Lactose intolerant'));
      for (var i = 0; i < 100; i++) {
        await MemoryStore.add('${'word ' * 50} number $i');
      }
      block = await MemoryStore.promptBlock();
      expect(block.length, lessThan(4500));
      expect(block, contains('number 99'), reason: 'newest memories are kept');
    });

    test('empty state is described, not blank', () async {
      final block = await MemoryStore.promptBlock();
      expect(block, contains('none provided'));
      expect(block, contains('nothing saved yet'));
    });
  });

  group('ChatStore', () {
    setUp(() => freshPrefs());

    test('threads, messages and actions survive a save/load round trip', () async {
      final t = ChatThread.fresh();
      t.title = 'Dinner ideas';
      t.messages.addAll([
        ChatMessage(role: 'user', content: 'hi', time: DateTime(2026, 11, 6, 8)),
        ChatMessage(
          role: 'assistant',
          content: 'Log it?',
          time: DateTime(2026, 11, 6, 8, 1),
          actions: [
            ChatAction(id: 'a1', name: 'log_meal', args: {'name': 'Eggs', 'calories': 200}),
            ChatAction(id: 'a2', name: 'save_memory', args: {'text': 't'}, status: 'done', result: 'ok'),
          ],
        ),
      ]);
      await ChatStore.save(t);
      final loaded = (await ChatStore.all()).single;
      expect(loaded.title, 'Dinner ideas');
      expect(loaded.messages.length, 2);
      final acts = loaded.messages.last.actions;
      expect(acts.first.args['name'], 'Eggs');
      expect(acts.first.status, 'pending');
      expect(acts.last.status, 'done');
      expect(acts.last.result, 'ok');
    });

    test('newest chat first, update in place, delete, cap at 100', () async {
      final a = ChatThread.fresh()..title = 'A';
      await ChatStore.save(a);
      await Future.delayed(const Duration(milliseconds: 5));
      final b = ChatThread(id: 'b', title: 'B', messages: [], updated: DateTime.now());
      await ChatStore.save(b);
      expect((await ChatStore.all()).map((t) => t.title), ['B', 'A']);
      a.updated = DateTime.now().add(const Duration(seconds: 1));
      await ChatStore.save(a);
      expect((await ChatStore.all()).map((t) => t.title), ['A', 'B']);
      await ChatStore.delete('b');
      expect((await ChatStore.all()).length, 1);
      for (var i = 0; i < 110; i++) {
        await ChatStore.save(ChatThread(
            id: 'x$i', title: 'T$i', messages: [], updated: DateTime.now().add(Duration(seconds: i))));
      }
      expect((await ChatStore.all()).length, 100);
    });

    test('old chats saved before actions existed still load', () async {
      await freshPrefs({
        'ai_chats':
            '[{"id":"1","title":"Old","updated":"2026-11-01T10:00:00.000","messages":[{"role":"user","content":"hello","time":"2026-11-01T10:00:00.000"}]}]'
      });
      final t = (await ChatStore.all()).single;
      expect(t.messages.single.actions, isEmpty);
    });

    test('corrupt data does not crash', () async {
      await freshPrefs({'ai_chats': 'not json'});
      expect(await ChatStore.all(), isEmpty);
    });
  });

  group('PhotoCleaner', () {
    final created = <FileSystemEntity>[];
    File mk(String name, Duration age) {
      final f = File('${Directory.systemTemp.path}/$name')..writeAsStringSync('x');
      f.setLastModifiedSync(DateTime.now().subtract(age));
      created.add(f);
      return f;
    }

    tearDown(() {
      for (final e in created) {
        if (e.existsSync()) e.deleteSync(recursive: true);
      }
      created.clear();
    });

    test('deletes camera copies older than 24 hours, keeps fresh and unrelated files', () async {
      final old = mk('image_picker_test_old.jpg', const Duration(hours: 30));
      final fresh = mk('image_picker_test_new.jpg', const Duration(hours: 2));
      final other = mk('unrelated_test_old.jpg', const Duration(hours: 30));
      await PhotoCleaner.purge();
      expect(old.existsSync(), false);
      expect(fresh.existsSync(), true);
      expect(other.existsSync(), true, reason: 'only photo copies are touched');
    });

    test('cleans old files inside a recent image_picker folder', () async {
      final dir = Directory('${Directory.systemTemp.path}/image_picker_test_dir')..createSync();
      created.add(dir);
      final inside = File('${dir.path}/a.jpg')..writeAsStringSync('x');
      inside.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 40)));
      final recent = File('${dir.path}/b.jpg')..writeAsStringSync('x');
      await PhotoCleaner.purge();
      expect(inside.existsSync(), false);
      expect(recent.existsSync(), true);
    });

    test('"delete now" removes everything, even new photos', () async {
      final fresh = mk('image_picker_test_new2.jpg', const Duration(minutes: 5));
      await PhotoCleaner.purge(all: true);
      expect(fresh.existsSync(), false);
    });
  });
}
