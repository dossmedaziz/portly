import 'package:shared_preferences/shared_preferences.dart';

const defaultFavoritePorts = [3000, 5173, 8000, 8080, 5432, 3306, 6379, 27017];

class Settings {
  const Settings({
    this.refreshSeconds = 3,
    this.startOnLogin = false,
    this.startHidden = true,
    this.notifications = true,
    this.favorites = defaultFavoritePorts,
  });

  final int refreshSeconds;
  final bool startOnLogin;

  /// Whether autostart launches with `--hidden`.
  final bool startHidden;
  final bool notifications;
  final List<int> favorites;

  Settings copyWith({
    int? refreshSeconds,
    bool? startOnLogin,
    bool? startHidden,
    bool? notifications,
    List<int>? favorites,
  }) {
    return Settings(
      refreshSeconds: refreshSeconds ?? this.refreshSeconds,
      startOnLogin: startOnLogin ?? this.startOnLogin,
      startHidden: startHidden ?? this.startHidden,
      notifications: notifications ?? this.notifications,
      favorites: favorites ?? this.favorites,
    );
  }
}

/// Persists [Settings] with shared_preferences.
class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static const _refresh = 'refreshSeconds';
  static const _startOnLogin = 'startOnLogin';
  static const _startHidden = 'startHidden';
  static const _notifications = 'notifications';
  static const _favorites = 'favorites';

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {
          _refresh,
          _startOnLogin,
          _startHidden,
          _notifications,
          _favorites,
        },
      ),
    );
    return SettingsService(prefs);
  }

  Settings load() {
    const d = Settings();
    final favorites = _prefs.getStringList(_favorites);
    return Settings(
      refreshSeconds: (_prefs.getInt(_refresh) ?? d.refreshSeconds).clamp(
        1,
        60,
      ),
      startOnLogin: _prefs.getBool(_startOnLogin) ?? d.startOnLogin,
      startHidden: _prefs.getBool(_startHidden) ?? d.startHidden,
      notifications: _prefs.getBool(_notifications) ?? d.notifications,
      favorites: favorites == null
          ? d.favorites
          : [for (final p in favorites) ?int.tryParse(p)],
    );
  }

  Future<void> save(Settings s) async {
    await _prefs.setInt(_refresh, s.refreshSeconds);
    await _prefs.setBool(_startOnLogin, s.startOnLogin);
    await _prefs.setBool(_startHidden, s.startHidden);
    await _prefs.setBool(_notifications, s.notifications);
    await _prefs.setStringList(_favorites, [for (final p in s.favorites) '$p']);
  }
}
