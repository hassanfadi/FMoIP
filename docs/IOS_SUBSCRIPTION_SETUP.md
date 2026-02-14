# iOS Subscription Setup (App Store Connect)

To enable the subscription (FMoIP Pro / ad-free) on iOS:

## 1. App Store Connect – Paid Apps Agreement

- Sign in to [App Store Connect](https://appstoreconnect.apple.com)
- Go to **Agreements, Tax, and Banking**
- Complete the **Paid Apps** agreement (banking and tax info)

## 2. Create the In-App Purchase Product

1. In App Store Connect, open your app (**FMoIP**)
2. Go to **Monetization** → **In-App Purchases** (or **Subscriptions**)
3. Click **+** to add a product
4. Choose **Non-Consumable** (one-time purchase for ad-free), or **Auto-Renewable Subscription** (monthly/yearly)
5. Use Product ID: **`fmoip_pro`** (must match `IapConfig.subscriptionProductIdIos` in `lib/iap_config.dart`)
6. Fill in Reference Name, Price, and localizations
7. Submit for App Review with your next app version

## 3. Test Locally (Before App Store Connect)

1. Open `ios/Runner.xcworkspace` in Xcode
2. Go to **Product** → **Scheme** → **Edit Scheme…**
3. Select **Run** in the left sidebar
4. Open the **Options** tab
5. Under **StoreKit Configuration**, choose **FMoIPProducts.storekit**
6. Run the app on the simulator or a device – the subscription will be available for testing

## 4. Test on a Real Device (Sandbox)

- Create a **Sandbox Tester** in App Store Connect: **Users and Access** → **Sandbox** → **Testers**
- On your iPhone: **Settings** → **App Store** → sign out of your Apple ID
- When you tap Subscribe in the app, sign in with the sandbox tester account
- Purchases are free in sandbox and can be used to test the flow
