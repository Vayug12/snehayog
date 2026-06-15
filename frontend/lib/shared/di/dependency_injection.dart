import 'package:vayug/features/video/core/data/datasources/video_remote_datasource.dart';
import 'package:vayug/features/video/core/data/repositories/video_repository_impl.dart';
import 'package:vayug/features/video/core/domain/repositories/video_repository.dart';
import 'package:vayug/features/video/core/presentation/managers/video_provider.dart';
import 'package:vayug/core/interfaces/i_e2ee_service.dart';
import 'package:vayug/features/video/core/data/services/e2ee_service_impl.dart';

/// Simple service locator for dependency injection
/// This provides a lightweight alternative to external DI libraries
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Core services
  VideoRemoteDataSource? _videoRemoteDataSource;
  VideoRepository? _videoRepository;
  IE2eeService? _e2eeService;

  // Getters
  VideoRemoteDataSource get videoRemoteDataSource =>
      _videoRemoteDataSource ??= VideoRemoteDataSource();
  VideoRepository get videoRepository => _videoRepository ??=
      VideoRepositoryImpl(remoteDataSource: videoRemoteDataSource);
  IE2eeService get e2eeService => _e2eeService ??= E2eeServiceImpl();

  /// Creates a new VideoProvider instance
  VideoProvider createVideoProvider() {
    return VideoProvider();
  }

  /// Cleans up all dependencies
  void dispose() {
    _videoRemoteDataSource = null;
    _videoRepository = null;
    _e2eeService = null;
  }
}

/// Global service locator instance
final serviceLocator = ServiceLocator();

