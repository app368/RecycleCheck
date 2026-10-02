# RecycleCheck

An iOS app that tells you whether an item can go in the recycling bin, according to your city's own recycling rules.

Take a photo of an item, and RecycleCheck answers **yes**, **no**, or **not sure**, quoting the exact line from the city's list that the answer is based on.

The app uses AI (Anthropic's Claude) to recognize items and match them against the city's lists.

## How it works

1. **Refresh.** The app reads the city's recycling page and builds a local list of allowed and not-allowed items.
2. **Recognize.** You photograph an item, and Claude describes what it is. You can edit the description.
3. **Check.** Claude matches the item against the lists by meaning, not by exact words (a *mug* counts as *drinkware*).
4. **Answer.** Yes, no, or not sure, with the quote from the list. For "not sure", the app can draft an email question to the city's recycling team.

The default source is the City of Portland, Oregon. The website URL and contact email can be changed in Settings.

## Requirements

- Xcode 26 or later
- iOS 26.2 or later
- An [Anthropic API key](https://console.anthropic.com/)

## Setup

The repository contains no keys or signing data. To build the app:

1. **API key.** Copy `RecycleCheck/RecycleCheck/Secrets.swift.example` to `Secrets.swift` in the same folder and paste your Anthropic API key.
2. **Signing.** Create `RecycleCheck/Local.xcconfig` with your team and bundle ID:

   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.yourname.RecycleCheck
   ```

   This step is only needed to run on a real device; the simulator works without it.

3. Open `RecycleCheck/RecycleCheck.xcodeproj` and run.

Both files are listed in `.gitignore` and stay on your machine.

> **Note.** The API key is compiled into the app. This is fine for personal use, but an app distributed to others should call the API through a backend instead.

## Accuracy and project status

RecycleCheck can be wrong: by our preliminary estimates, in roughly 5–7% of cases. Both the recognition of the item and the match against the city's lists are done by AI, so treat an answer as a hint, not an official ruling. When in doubt, check with your local recycling program.

The project is currently on hold: the author got absorbed in another app. If you would like to work on it, improving the accuracy of the results (recognition, matching, handling of unclear cases) is the most useful place to start. Contributions are welcome.

## License

[MIT](LICENSE)
