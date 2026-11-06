<div align="center">

<br>

 <img src="assets/screenshots/main.png" width="140"/>

# Cal AI

**AI-Powered Calorie Tracker for Android & iOS**

Track what you eat. Understand your nutrition. Powered by AI.

<br>

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=flat-square&logo=dart&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-10B981?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey?style=flat-square)

<br>

</div>

---

> ### 🤖 This is a fork — it adds an AI coach, widgets and a lot more
>
> A fork of [junaidjamel/cal_scanner](https://github.com/junaidjamel/cal_scanner) that keeps the original photo calorie scanner and adds: an AI chat that knows your data, health memory, home-screen widgets, dark mode, a fourth goal (body recomposition), a weekly workout slider, photo notes and meal editing.
>
> Everything is stored on your phone. The only thing that leaves it is what you send to your own Groq account.
>
> → [What changed in this fork](#what-changed-in-this-fork) · [Setup](#getting-started) · [Privacy & security](#privacy--security-in-this-fork)

---

## Overview

Cal AI is a Flutter mobile app that uses artificial intelligence to make calorie tracking effortless. Photograph your meal, and Cal AI instantly estimates nutritional information — no manual logging required.

---

## Screenshots

<table>
  <tr>
    <th align="center">Onboarding</th>
    <th align="center">Calorie Log & Tracking</th>
  </tr>
  <tr>
    <td align="center">
      <img src="assets/screenshots/o1.png" width="140"/>
      <img src="assets/screenshots/o2.png" width="140"/>
      <img src="assets/screenshots/o3.png" width="140"/>
      <br/>
      <img src="assets/screenshots/o4.png" width="140"/>
      <img src="assets/screenshots/o5.png" width="140"/>
      <img src="assets/screenshots/o6.png" width="140"/>
    </td>
    <td align="center">
      <img src="assets/screenshots/h1.png" width="140"/>
      <img src="assets/screenshots/h2.png" width="140"/>
      <br/>
      <img src="assets/screenshots/h3.png" width="140"/>
      <img src="assets/screenshots/h4.png" width="140"/>
    </td>
  </tr>
</table>

---

## Features

| Feature                     | Description                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| **AI Meal Recognition**     | Snap a photo of your food — Cal AI identifies the item and estimates calories automatically |
| **Daily Calorie Dashboard** | Clean summary of your daily intake vs your personal calorie goal                            |
| **Macro Breakdown**         | Track proteins, carbohydrates, and fats alongside total calories                            |
| **Meal History Log**        | Full history of logged meals with timestamps and nutritional details                        |
| **Personalized Goals**      | Set custom calorie and macro targets based on your health goals                             |
| **Nutritional Insights**    | AI-generated tips based on your eating patterns                                             |
| **Lightweight & Fast**      | Smooth, native experience on both Android and iOS                                           |

---

## What changed in this fork

Version **1.9.0**. Original app: Flutter + Cubit + local storage. Everything below was added on top.

### AI and chat
| Feature | What it does |
| --- | --- |
| **AI chat** (button top-left) | Talk with an AI that sees your profile, today's meals and the last 13 days. It suggests foods that fit the calories and macros you have left. Chats are saved with history. |
| **AI actions** | In chat the AI can propose logging a meal or changing your goal. Nothing changes until you tap **Confirm**. |
| **Health notes & memory** | Write health notes (for example gastric problems) and the AI also saves lasting facts from chat. Both are sent to the AI with every message so replies respect them. View, edit and delete them in **Settings → Memory & health notes**. |
| **Photo notes** | After taking or choosing a photo you can add a note ("2 rotis, little oil") that is sent with the photo. |
| **Edit a meal** | The pencil on a meal re-sends the photo (if still kept) and your note, then shows the new estimate to **Save** or **Keep old**. |
| **Gallery upload** | Pick a meal photo from the gallery as well as the camera (resized to 1600 px). |

### Goals and nutrition
| Feature | What it does |
| --- | --- |
| **Body recomposition goal** | A fourth goal next to lose, maintain and gain: a small deficit (10%, at most 300 kcal) with high protein (2.2 g/kg). |
| **Goal changer** | Change your goal any time in Settings. Targets are recalculated from your saved profile. |
| **Weekly workout slider** | Set how much you train this week (5 levels). Daily calories update immediately. |

### App and phone
| Feature | What it does |
| --- | --- |
| **Home-screen widgets** | 4x4 and 2x2 widgets with calories, macros and meals, in light and dark. |
| **Dark mode** | System / Light / Dark switch in Settings, also applied to the widgets. |
| **Key and model settings** | Change the API key and model in Settings. If the model is retired, the app finds a working one and switches automatically (can be turned off). Updates keep your data. |
| **Built-in key** | The key can be bundled in `.env` at build time, so the app works right after install. |

### Privacy & security in this fork
- All data (meals, chats, memory, profile) stays in the app's private storage on the phone.
- Meal photos are one-shot: only the text result is saved. A temporary copy is kept up to 24 hours (for editing), then deleted. **Settings → Memory → Delete temporary photos now** removes them immediately.
- Only HTTPS is allowed. Cloud and device-transfer backups are turned off for app data.
- The app only asks for internet access.
- Sent to Groq: the photo, your note, your profile, meals, health notes and memory. Groq states it does not retain inference data by default and may log it up to 30 days.
- **Limits:** a key bundled in the APK can be extracted from it, so do not share your APK. Data on the phone is not encrypted beyond Android's own app isolation.

### Tested
62 automated tests cover the calculators, goal changer, memory and chat storage, the AI chat flow (with a fake server), model fallback, photo scanning and editing, the 24-hour photo cleanup, and the Settings, Memory, scan and meal screens. It has not been tested on a physical phone or emulator.

### Using the fork's features
1. Get a free API key from [console.groq.com](https://console.groq.com) (Groq is used instead of Grok).
2. Put it in `.env` as `GROK_API_KEY=gsk_...` before building, or paste it in the app under **Settings**. Never commit a real key.
3. Build: `flutter build apk --release`. Sign every update with the same keystore, otherwise it will not install over the old app and its data will be lost.

---

## Tech Stack

| Layer            | Technology         |
| ---------------- | ------------------ |
| Framework        | Flutter (Dart)     |
| AI / NLP         | Groq (OpenAI-compatible API), model `qwen/qwen3.8-27b` by default |
| State Management | Cubit              |
| Local Storage    | Shared Preferences |
| UI Components    | Material Design 3  |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) v3.0 or higher
- [Dart](https://dart.dev/get-dart) — bundled with Flutter

### Installation

**1. Clone the repository**

```bash
git clone https://github.com/junaidjamel/cal_scanner
```

**2. Install dependencies**

```bash
flutter pub get
```

**3. Configure environment variables**

Add your API key to the `.env` file in the root directory:

```env
GROK_API_KEY=your_api_key_here
```

**4. Run the app**

```bash
flutter run
```

---

## Project Structure

```
cal-ai/
├── lib/
│   ├── main.dart           # App entry point
│   ├── screens/            # UI screens
│   ├── widgets/            # Reusable UI components
│   ├── models/             # Data models
│   ├── services/           # API & AI services
│   └── utils/              # Helper functions
├── assets/
│   └── images/             # App images & icons
├── test/                   # Unit & widget tests
├── pubspec.yaml            # Dependencies
└── README.md
```

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a new branch — `git checkout -b feature/your-feature-name`
3. Commit your changes — `git commit -m 'Add some feature'`
4. Push to the branch — `git push origin feature/your-feature-name`
5. Open a Pull Request

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Author

**Original app: Junaid Jamel**

- Email: junaidsupercoder@gmail.com
- LinkedIn: [linkedin.com/in/junaid-jamel](https://www.linkedin.com/in/junaid-jamel/)
  
- Fork additions: [stha-hardik](https://github.com/stha-hardik)
- If you liked the repo then kindly support it by giving it a star ⭐!



---

<div align="center">
<sub>Built with Flutter &mdash; Cal AI &copy; Junaid Jamel</sub>
</div>
