# FMoIP Specifications

## Overview
FMoIP is a Flutter (Dart) mobile app for Android and iOS that lets users discover local FM radio stations by country and listen to streams over the internet. The app supports background playback, recordings, ads for free users, and a $1/month subscription for an ad-free experience.

## Core Features
- Country selector (dropdown) to fetch local FM stations.
- Station list with metadata (name, frequency, stream URL, country, genre if available).
- Player with play/pause, metadata display, background audio support.
- Recording feature to save audio locally.
- Settings: language (EN, AR, ES, ZH), playback preferences, storage limits, data usage, and ad/subscription status.
- Ads for free users; subscription removes ads.
- App and station icons; clean modern UI.

## Data Sources
- Use a public FM/radio directory API to search by country and return stream links + metadata.
- Cache last successful country results locally.

## Monetization
- Free tier: ads displayed (banner + interstitial at station changes).
- Subscription: $1/month removes ads and enables higher recording quality.

## Non-Functional Requirements
- Background audio playback on Android and iOS.
- Respect platform audio focus and interruptions.
- Handle poor network and retry gracefully.
- Localized UI for EN/AR/ES/ZH.

## Initial Screens
1. **Home**: Country dropdown + station list.
2. **Player**: Station info, play/pause, recording controls.
3. **Settings**: Language picker, recording quality, data saver, subscription status.

## Storage
- Recordings saved in app documents directory.
- Metadata stored in local preferences.

## Compliance
- Follow platform background audio policies.
- Prompt for microphone and storage permissions when recording.
