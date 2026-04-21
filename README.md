# The Abyss 

The official, ultra-optimized mobile application for **The Abyss** community. Built with Flutter, this app transcends a simple web-wrapper by deeply integrating native rendering features, advanced engine optimization, and custom APIs to deliver a blazing-fast, ad-free experience.

## ✨ Features (Version 1.0)

### 💬 Deep Chat Integration
* **Seamless Chat** - Connects directly to the latest "The Abyss" chatroom instantly.
* **Archive Navigator** - A native sidebar drawer that automatically fetches and archives all past chatrooms.
* **Zero Lag Scrolling** - Built-in custom JS smooth scroller to glide through thousands of comments effortlessly. 

### 🛡️ Ad-Free & Optimized
* **Native Ad-Blocker** - Preconfigured to block heavy trackers and ad servers at the network level, saving data and battery.
* **Repaint Boundaries** - The chat rendering engine is cached during drawer animations for buttery 60fps/120fps UI performance.
* **Instant Load CSS** - Pre-emptive DOM injection stops heavy background assets from downloading.

### 🎨 Custom Aesthetics
* **Theme Engine** - Multiple dark-mode themes designed specifically for OLED screens (Abyss Black, Silk Red, Midnight Purple, Deep Ocean).
* **Custom Backgrounds** - Support for injecting your own local image or image URLs directly behind the chat.

### 👥 The Members Hub
A dedicated native tab bridging the gap between web and app via the **Disqus Public API**.
* **Live Community Stream** - Real-time progressive streaming of all active *Abyssians*.
* **Moderator Detection** - The app officially detects and highlights community Moderators in a dedicated VIP section.
* **Stat Tracking** - Pulls background stats (Total Comments & Total Likes Received) for every member with zero UI lag.
* **Advanced Sorting** - Sort the community by Name (A-Z), Highest Likes ❤️, or Most Comments 💬.
* **Profile Integration** - Tap any member's tile to launch their full profile in a secure, transparent in-app browser.
* **State Persistence** - Using an `IndexedStack` architecture, you can seamlessly jump between the Chat and the Members tab without dropping focus or reloading the web engine.

## 🚀 Installation 

1. Go to the [Releases](https://github.com/your-repo/releases) tab.
2. Download the latest `app-release.apk`.
3. Install the APK on your Android device (You may need to allow "Install from Unknown Sources").

## 🛠️ Built With
* [Flutter](https://flutter.dev/) 
* [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview)
* Disqus API V3.0
