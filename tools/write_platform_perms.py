# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile_app"

(APP / "test" / "widget_test.dart").unlink(missing_ok=True)

manifest = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
manifest.write_text(r'''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>

    <application
        android:label="GlassesPro"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
'''.replace('\r\n', '\n'), encoding='utf-8')

plist = APP / "ios" / "Runner" / "Info.plist"
text = plist.read_text(encoding='utf-8')
inject = '''	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>GlassesPro usa Bluetooth para emparejar y configurar las gafas.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>GlassesPro usa Bluetooth para hablar con las gafas inteligentes.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>La ubicación se usa solo para el escaneo Bluetooth en Android/iOS.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>El micrófono permite dictar consultas de soporte técnico.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Se usa la red local para capturas JPEG, audio y OTA de las gafas.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_http._tcp</string>
	</array>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<key>CFBundleDisplayName</key>
'''
# CFBundleDisplayName already exists; just insert usage keys before closing dict
if 'NSBluetoothAlwaysUsageDescription' not in text:
    text = text.replace(
        '\t<key>CADisableMinimumFrameDurationOnPhone</key>',
        inject.split('	<key>CFBundleDisplayName</key>')[0] + '\t<key>CADisableMinimumFrameDurationOnPhone</key>',
    )
    text = text.replace('<string>Smart Glasses App</string>', '<string>GlassesPro</string>')
    plist.write_text(text, encoding='utf-8')

gradle = APP / "android" / "app" / "build.gradle"
g = gradle.read_text(encoding='utf-8')
g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 21')
gradle.write_text(g, encoding='utf-8')
print('platform permissions written')
