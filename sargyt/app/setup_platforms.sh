#!/usr/bin/env bash
# Создаёт папки android/ и ios/ и прописывает разрешения (геолокация, интернет).
# Запуск на компьютере разработчика с установленным Flutter 3.24+ (для iOS — на Mac с Xcode).
set -e
cd "$(dirname "$0")"
flutter create --platforms=android,ios --org tm.sargyt --project-name sargyt .
flutter pub get

# Android: разрешения
M=android/app/src/main/AndroidManifest.xml
grep -q ACCESS_FINE_LOCATION $M || sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application#' $M
# http для тестового сервера (в проде использовать https)
grep -q usesCleartextTraffic $M || sed -i.bak 's#<application#<application android:usesCleartextTraffic="true"#' $M
sed -i.bak 's#android:label="sargyt"#android:label="SARGYT"#' $M
rm -f $M.bak

# iOS: тексты запроса геолокации
P=ios/Runner/Info.plist
if ! grep -q NSLocationWhenInUseUsageDescription $P; then
  /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string 'Ýakyndaky edaralary görkezmek we salgyňyzy kesgitlemek üçin / Чтобы показать заведения рядом и определить адрес'" $P 2>/dev/null || \
  sed -i.bak 's#<dict>#<dict>\n\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>Ýakyndaky edaralary görkezmek üçin / Чтобы показать заведения рядом</string>#' $P
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName SARGYT" $P 2>/dev/null || true
fi
echo "Готово. Запуск: flutter run --dart-define=API_URL=http://<IP сервера>:8080"
