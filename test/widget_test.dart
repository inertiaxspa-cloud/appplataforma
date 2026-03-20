import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inertiax/app.dart';

void main() {
  testWidgets('App smoke test — renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: InertiaXApp()));
    // Just verify the app builds without throwing
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
