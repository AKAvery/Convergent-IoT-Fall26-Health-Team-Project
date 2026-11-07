# Firebase setup (Spark plan only, never Blaze)

1. console.firebase.google.com: Add project (Google Analytics off is fine).
2. Build, Authentication, Get started, Sign-in method: enable **Anonymous**.
3. Build, Firestore Database, Create (production mode). Paste `firestore.rules` into the Rules tab and Publish.
4. Project settings, Add app, iOS, bundle ID `edu.utexas.convergent.soundring` (or your own suffix).
   Download `GoogleService-Info.plist` into `ios/SoundRing/`, then run `xcodegen`.

Without the plist the app still builds and runs; it just skips Firebase.

Data layout: `users/{uid}/events/{id}` (one per finished sound) and `users/{uid}/settings/app`.
