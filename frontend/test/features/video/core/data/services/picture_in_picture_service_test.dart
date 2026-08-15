import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/video/core/data/services/picture_in_picture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PictureInPictureService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('forwards owner playback state and source bounds to the platform',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isSupported' => true,
        'enter' => true,
        _ => null,
      };
    });
    final service = PictureInPictureService(channel: channel);

    expect(await service.initialize(), isTrue);
    await service.update(
      ownerId: 'yug',
      aspectRatio: 9 / 16,
      isPlaying: true,
      autoEnterEnabled: true,
      sourceRect: const <double>[0, 120, 1080, 2040],
    );
    expect(
      await service.enter(
        ownerId: 'yug',
        aspectRatio: 9 / 16,
        isPlaying: true,
        sourceRect: const <double>[0, 120, 1080, 2040],
      ),
      isTrue,
    );

    expect(calls.map((call) => call.method), <String>[
      'isSupported',
      'update',
      'enter',
    ]);
    expect(
      (calls[1].arguments as Map<Object?, Object?>)['autoEnterEnabled'],
      isTrue,
    );
    expect(
      (calls[2].arguments as Map<Object?, Object?>)['sourceRect'],
      const <double>[0, 120, 1080, 2040],
    );
    await service.dispose();
  });

  test('ignores inactive owners so a hidden feed cannot steal PiP', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'isSupported' ? true : null;
    });
    final service = PictureInPictureService(channel: channel);
    await service.initialize();
    await service.update(
      ownerId: 'yug',
      aspectRatio: 9 / 16,
      isPlaying: true,
      autoEnterEnabled: true,
    );
    await service.update(
      ownerId: 'hidden-vayu',
      aspectRatio: 16 / 9,
      isPlaying: false,
      autoEnterEnabled: false,
    );

    expect(calls.where((call) => call.method == 'update'), hasLength(1));
    await service.dispose();
  });

  test('reports unsupported when the host has no PiP implementation', () async {
    final service = PictureInPictureService(channel: channel);

    expect(await service.initialize(), isFalse);
    expect(
      await service.enter(
        ownerId: 'test',
        aspectRatio: 16 / 9,
        isPlaying: false,
      ),
      isFalse,
    );
    await service.dispose();
  });

  test('routes native callbacks only to the active owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    PictureInPictureModeEvent? modeEvent;
    PictureInPicturePlaybackEvent? playbackEvent;
    final service = PictureInPictureService(channel: channel);
    final modeSubscription = service.modeChanges.listen((event) {
      modeEvent = event;
    });
    final playbackSubscription = service.playbackRequests.listen((event) {
      playbackEvent = event;
    });
    await service.initialize();
    await service.update(
      ownerId: 'yug',
      aspectRatio: 9 / 16,
      isPlaying: true,
      autoEnterEnabled: true,
    );

    await messenger.handlePlatformMessage(
      PictureInPictureService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('modeChanged', <String, Object>{'isActive': true}),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      PictureInPictureService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(
          'playbackRequested',
          <String, Object>{'shouldPlay': false},
        ),
      ),
      (_) {},
    );

    expect(modeEvent?.ownerId, 'yug');
    expect(modeEvent?.isActive, isTrue);
    expect(playbackEvent?.ownerId, 'yug');
    expect(playbackEvent?.shouldPlay, isFalse);
    await modeSubscription.cancel();
    await playbackSubscription.cancel();
    await service.dispose();
  });

}
