# ScreenRecorder

A macOS screen recording application designed for tutorial creators who want to record their screens efficiently while ensuring optimal visibility for both long-form and short-form video formats.

## Features

- **Screen Recording**: Capture the entire screen with high quality
- **Mouse Tracking & Zoom**: Recording follows the mouse pointer with smooth zoom transitions
- **Adjustable Zoom Levels**: Customize zoom levels for different output formats
- **Multiple Export Formats**: Support for both 16:9 (standard) and 9:16 (mobile) formats

## Requirements

- macOS 13.0+
- Xcode 15.0+ for development

## Installation

1. Clone the repository
2. Open the ScreenRecorder.xcodeproj file
3. Build and run the project in Xcode

## Usage

1. Launch the application
2. Set your desired zoom level using the slider
3. Click "Start Recording" to begin capturing your screen
4. When finished, click "Stop Recording" to save your recording
5. Find your recording in the Documents folder

## Development Roadmap

### Phase 1: Basic Recording & Zooming
- Screen recording using ScreenCaptureKit
- Cursor tracking and smooth zoom functionality
- Basic video playback for review

### Phase 2: Editing & Timeline Features
- Timeline-based editing using AVFoundation
- Spotlight effects & zoom controls
- Background padding & overlays

### Phase 3: Export System
- Export functionality with multiple aspect ratios (16:9 & 9:16)
- Optimized zoom levels for mobile-friendly exports

### Phase 4: Refinements & Optimization
- Improved UI/UX
- Bug fixes & performance optimization

## License

This project is licensed under the MIT License - see the LICENSE file for details. 