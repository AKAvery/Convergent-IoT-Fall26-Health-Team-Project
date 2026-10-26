# Week 1 tasks: no-Mac version (Thu Oct 22 – Thu Oct 29)

An alternative to `docs/week1-tasks.md`, for review. Use it if one of the three of us has no
Mac. The goal for Thu Oct 29 is unchanged. It assumes:

- One person has no Mac, so they can't build the Swift or iOS code.
- Only Avery has the paid Apple Developer account.
- No hardware this week. Only Macs and our own phones are used.

## What changed from `week1-tasks.md`

- The no-Mac teammate takes everything that runs on any laptop: firmware, Python and Firebase.
- Avery's Python tasks move to them: compression, the two-phone test, the compression
  accuracy test and the detector outputs.
- Avery takes the tasks that need a Mac: model loading, the Swift decoder and the fake box.
- The end-to-end test becomes must. The iPhone Bluetooth receiver stays stretch.
- Direction is due Wed instead of Thu, so the end-to-end test has it.
- The decision rules read Python's probabilities directly, so they don't wait on model loading.
- The paid Apple account isn't needed this week. The Mac teammate runs the app on their own
  iPhone with a free Apple ID, which has to be reinstalled from Xcode every 7 days. From week 2,
  push notifications and TestFlight builds go through Avery's account.

## Tasks

**Avery**
- Fri: Pick the Bluetooth IDs with the No-Mac teammate.
- Sun: Write the shared Swift data formats, and get both teammates to approve them.
- Mon: Write the Swift audio decoder so it matches the Python test files.
- Mon: Build a fake box on your Mac that streams a recording over Bluetooth.
- Tue: Load both models in Swift, with results matching Python's.
- Wed: Port the detector's decision rules to Swift, with outputs matching Python on the test clips.
- Thu: Run the end-to-end test with the Mac teammate, so a recorded siren comes out with the
  right label and direction.

**Mac teammate**
- Fri: Set up the Xcode project and the code package, and get the ML library working. Everyone
  waits on this.
- Mon: Build the four-box simulator, which plays a recording as if it came from any direction.
- Wed: Write direction and box switching in Swift, with tests.
- Thu: Run the end-to-end test with Avery.
- Stretch: Build the iPhone Bluetooth receiver and test it against the fake box.

**No-Mac teammate**
- Fri: Write the audio compression in Python and make test files for the other versions.
- Fri: Pick the Bluetooth IDs with Avery.
- Sat: Write a simple firmware sketch that prints the mic's loudness.
- Sat: Run the two-phone test, one phone on the chest and one on the back, to see how much the
  body blocks sound.
- Sat: Test whether compression hurts detection accuracy. The result decides the audio format.
- Mon: Export the Python detector's outputs for the test clips.
- Mon: Write the compression encoder in C++ so it matches the Python test files.
- Wed: Set up the Firebase rules and a local test setup.
- Stretch: Write the full Bluetooth firmware.
