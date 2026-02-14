# Android release signing (for Google Play)

To build an **App Bundle** that Google Play will accept for production, you need a release keystore and `key.properties`.

## 1. Create a keystore (one-time)

From the **android** directory run:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- You will be asked for a keystore password and a key password (you can use the same).
- Enter your name/organization and other details when prompted.
- Keep `upload-keystore.jks` and the passwords **safe and private**. You need them for all future updates.

**Important:** Back up `upload-keystore.jks` and the passwords. If you lose them, you cannot update the app on Play Store with the same app identity.

## 2. Create key.properties

In the **android** folder, copy the example and edit:

```bash
cp key.properties.example key.properties
```

Edit `key.properties` and set:

- `storePassword` – keystore password
- `keyPassword` – key password (often same as storePassword)
- `keyAlias` – use `upload` (same as in the keytool command)
- `storeFile` – use `upload-keystore.jks` if the file is in the android folder

Do **not** commit `key.properties` or `upload-keystore.jks` to git (they are in .gitignore).

## 3. Build the App Bundle

From the **project root** (FMoIP):

```bash
flutter build appbundle
```

The signed bundle will be at:

**build/app/outputs/bundle/release/app-release.aab**

Upload this file in Google Play Console under Release → Production (or your chosen track) → App bundles.
