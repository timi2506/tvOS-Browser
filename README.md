# tvOS-Browser
A Browser for tvOS with UI similar to the Arc Browser. Supports tvOS 18+ (for now)

Supports Game Controllers, Keyboard, Mice and Siri Remote

<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 23 58" src="https://github.com/user-attachments/assets/2ec17c2a-b74b-422d-a993-c5486e1dbbfe" />

## Other Features
- Custom User Agent
- Tabs
- Cursor/Scroll/Remote Control Mode
- Enter Text on Website using Keyboard Menu
- Search Suggestions while typing
- Downloading Files from Websites, either directly onto the TV or share to Mobile Device over QR Code
- Customizable Settings

## Screenshots
<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 26 03" src="https://github.com/user-attachments/assets/d2afd1a6-b329-4593-99c9-0b1636fdb204" />
<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 25 33" src="https://github.com/user-attachments/assets/f03156ff-f3f3-4516-b696-9beca9c74389" />
<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 24 39" src="https://github.com/user-attachments/assets/d5a37422-7450-49ff-b722-29e3921bb130" />
<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 23 02" src="https://github.com/user-attachments/assets/d91cf4b8-d115-493a-9f8c-6025f51104e0" />
<img width="1920" height="1080" alt="Screenshot Main Bedroom 15 11 2026 at 12 22 11" src="https://github.com/user-attachments/assets/61b46547-159d-4c58-b19a-18fd87793f75" />

## Installation
### Method 1 (Easiest) - Use Impactor/Sideloadly
1. Download and install [Impactor](https://github.com/claration/impactor) or [Sideloadly](https://sideloadly.io) on your PC

> [!NOTE]  
> Even though I would generally recommend Impactor because it is smoother and usually works more reliably, currently I recommend using Sideloadly since Impactor has some issues with sideloading for tvOS

2. Drag in the IPA from [Releases](https://github.com/timi2506/tvOS-Browser/releases) and select your Apple TV in the Device List (TIP: If it doesn't appear, open Settings on the TV and go to Remotes and Devices -> Remote App and Devices)

3. Press "Install", you may be asked for your Apple ID

Done!

### Method 2 (Advanced) - Xcode
1. Clone this Repo

2. Open the Xcode Project in Xcode

3. Go to Targets -> Browser and under Signing choose your own Developer Team and a custom Bundle Identifier
<img width="1369" height="816" alt="Screenshot 2026-11-15 at 12 33 24" src="https://github.com/user-attachments/assets/69304d8f-f671-43cf-86e5-95dc94e52b3a" />

4. Pair your Apple TV to Xcode (For more info, [go here](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub#Pair-physical-devices-wirelessly-to-your-Mac))

5. Select your Apple TV in the list of available Run Targets in the Top Bar
<img width="1504" height="839" alt="Screenshot 2026-11-15 at 12 36 39" src="https://github.com/user-attachments/assets/6ba50635-ff16-4721-9b8c-92d4a59ed788" />

6. Press the "Run" Button (Play icon) to Build and Install Browser on your Apple TV

## Disclaimer
This Project uses Private API's so it will NOT be able to be uploaded to the App Store. AI was used in the development of this Project (mainly for bridging the Private API's) but the UI was human-made (by me) and features were also manually tested by me. It just made developing this much easier :3
