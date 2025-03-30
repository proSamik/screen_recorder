import Cocoa
import AVFoundation
import ScreenCaptureKit
import CoreGraphics

class MainViewController: NSViewController {
    
    // MARK: - Outlets
    @IBOutlet weak var recordButton: NSButton!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var zoomLevelSlider: NSSlider!
    @IBOutlet weak var previewView: NSView!
    
    // MARK: - Properties
    
    /**
     * The screen capture session for recording
     */
    private var captureSession: SCStreamConfiguration?
    
    /**
     * The screen content to be captured
     */
    private var captureStream: SCStream?
    
    /**
     * The output file for the recording
     */
    private var outputFileURL: URL?
    
    /**
     * The asset writer to record the screen content
     */
    private var assetWriter: AVAssetWriter?
    
    /**
     * The asset writer input for video
     */
    private var assetWriterVideoInput: AVAssetWriterInput?
    
    /**
     * Flag indicating if recording is in progress
     */
    private var isRecording = false
    
    /**
     * Flag to prevent multiple stop attempts
     */
    private var isFinalizingRecording = false
    
    /**
     * Current zoom level (1.0 = no zoom)
     */
    private var zoomLevel: CGFloat = 1.0
    
    /**
     * Current cursor position for zoom tracking
     */
    private var cursorPosition: CGPoint = .zero
    
    /**
     * Flag to enable cursor tracking for zoom
     */
    private var trackCursorForZoom: Bool = false
    
    /**
     * Preview layer for displaying captured content
     */
    private var previewLayer: AVSampleBufferDisplayLayer?
    
    /**
     * First sample time for recording
     */
    private var firstSampleTime: CMTime?
    
    /**
     * Timer for tracking recording duration
     */
    private var recordingTimer: Timer?
    
    /**
     * Recording duration in seconds
     */
    private var recordingDuration: Int = 0
    
    /**
     * Progress indicator for showing recording finalization
     */
    private var progressIndicator: NSProgressIndicator?
    
    /**
     * Visual indicator showing that recording is active
     */
    private var recordingIndicator: NSView?
    
    /**
     * Timer to flash the recording indicator
     */
    private var indicatorTimer: Timer?
    
    /**
     * Timer for cursor position tracking
     */
    private var cursorTrackingTimer: Timer?
    
    /**
     * Count of failed restart attempts
     */
    private var restartAttempts: Int = 0
    
    // MARK: - Lifecycle
    
    /**
     * Called when the view is loaded
     * Sets up the UI and initializes screen capture components
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPreviewLayer()
        checkAppIdentity()
        prepareScreenCapture()
        
        // Add notification observers for app activation/deactivation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDeactivation),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    /**
     * Clean up resources when the view controller is deallocated
     */
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /**
     * Called when the view will appear
     * Prepares screen capture if needed
     */
    override func viewWillAppear() {
        super.viewWillAppear()
    }
    
    /**
     * Called when the view will disappear
     * Stops screen capture if active, but only when the app is actually closing
     */
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // Only stop recording if the app is actually closing, not just losing focus
        if isRecording && view.window?.isVisible == false {
            stopRecording()
        }
    }
    
    // MARK: - Setup
    
    /**
     * Sets up the user interface elements
     */
    private func setupUI() {
        recordButton.title = "Start Recording"
        recordButton.isEnabled = false // Disable until permission is granted
        statusLabel.stringValue = "Checking permissions..."
        zoomLevelSlider.minValue = 1.0
        zoomLevelSlider.maxValue = 4.0
        zoomLevelSlider.doubleValue = Double(zoomLevel)
        
        // Add progress indicator - position below the status label
        progressIndicator = NSProgressIndicator(frame: NSRect(x: statusLabel.frame.origin.x + statusLabel.frame.width + 10, 
                                                             y: statusLabel.frame.origin.y,
                                                             width: 20, 
                                                             height: 20))
        if let progressIndicator = progressIndicator {
            progressIndicator.style = .spinning
            progressIndicator.isDisplayedWhenStopped = false
            progressIndicator.isHidden = true
            view.addSubview(progressIndicator)
        }
        
        // Create recording indicator
        setupRecordingIndicator()
        
        // Add a toggle button for cursor tracking
        let trackCursorButton = NSButton(checkboxWithTitle: "Track Cursor", target: self, action: #selector(toggleCursorTracking))
        trackCursorButton.frame = NSRect(x: zoomLevelSlider.frame.origin.x, 
                                        y: zoomLevelSlider.frame.origin.y - 30, 
                                        width: 120, 
                                        height: 20)
        trackCursorButton.state = trackCursorForZoom ? .on : .off
        view.addSubview(trackCursorButton)
    }
    
    /**
     * Sets up the preview layer for displaying captured content
     */
    private func setupPreviewLayer() {
        previewLayer = AVSampleBufferDisplayLayer()
        previewLayer?.videoGravity = .resizeAspect
        previewLayer?.frame = previewView.bounds
        
        if let previewLayer = previewLayer {
            previewView.layer = previewLayer
            previewView.wantsLayer = true
        }
    }
    
    /**
     * Checks if the app's identity might be causing permission issues
     */
    private func checkAppIdentity() {
        print("--- App Identity Check ---")
        
        // Check bundle ID
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        print("Bundle ID: \(bundleID)")
        
        // Check if the app is properly code signed
        if let signingInfo = Bundle.main.infoDictionary?["SignerIdentity"] as? String {
            print("App is signed with: \(signingInfo)")
        } else {
            print("App doesn't appear to have a standard code signature")
        }
        
        // Check entitlements
        if Bundle.main.infoDictionary?["com.apple.security.screen-capture"] != nil {
            print("Screen capture entitlement found in info dictionary")
        }
        
        // Check permission entitlements are present
        let expectedEntitlements = [
            "com.apple.security.screen-capture",
            "com.apple.security.app-sandbox"
        ]
        
        for entitlement in expectedEntitlements {
            let processInfo = ProcessInfo.processInfo
            let environment = processInfo.environment
            if environment[entitlement] != nil {
                print("Runtime has \(entitlement) entitlement")
            } else {
                print("WARNING: \(entitlement) entitlement may be missing at runtime")
            }
        }
        
        // Check for permission setting in TCC database (indirect check)
        // This just checks if the Downloads folder is accessible, which is a hint our app has permissions
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloadsURL = downloadsURL, FileManager.default.isWritableFile(atPath: downloadsURL.path) {
            print("App has permission to write to Downloads folder")
        } else {
            print("App may lack permission to write to Downloads folder")
        }
        
        print("-------------------------")
    }
    
    /**
     * Prepares the screen capture settings and permissions
     */
    private func prepareScreenCapture() {
        // Request screen recording permission
        Task {
            do {
                // Get available content - this will trigger permission request
                let content = try await SCShareableContent.current
                print("Available displays: \(content.displays.count)")
                print("Available windows: \(content.windows.count)")
                
                if content.displays.isEmpty {
                    throw NSError(domain: "ScreenRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No displays available to capture"])
                }
                
                // Update UI on success
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.stringValue = "Permission granted. Ready to record."
                    // Enable recording button
                    self?.recordButton.isEnabled = true
                }
            } catch {
                print("Screen capture permission error: \(error)")
                DispatchQueue.main.async { [weak self] in
                    if error.localizedDescription.contains("declined") || error.localizedDescription.contains("denied") {
                        self?.statusLabel.stringValue = "Screen recording permission denied. Please enable in System Settings → Privacy & Security → Screen Recording."
                    } else {
                        self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    }
                    // Disable recording button if there's an error
                    self?.recordButton.isEnabled = false
                }
            }
        }
    }
    
    /**
     * Sets up the recording indicator that flashes during recording
     */
    private func setupRecordingIndicator() {
        // Create a small red circle indicator
        recordingIndicator = NSView(frame: NSRect(x: statusLabel.frame.origin.x - 20, 
                                                 y: statusLabel.frame.origin.y, 
                                                 width: 12, 
                                                 height: 12))
        
        if let recordingIndicator = recordingIndicator {
            recordingIndicator.wantsLayer = true
            recordingIndicator.layer?.cornerRadius = recordingIndicator.frame.width / 2
            recordingIndicator.layer?.backgroundColor = NSColor.red.cgColor
            recordingIndicator.layer?.opacity = 0.0 // Start hidden
            view.addSubview(recordingIndicator)
        }
    }
    
    /**
     * Shows and starts flashing the recording indicator
     */
    private func showRecordingIndicator() {
        // Stop any existing timer
        indicatorTimer?.invalidate()
        
        // Make sure the indicator is created
        if recordingIndicator == nil {
            setupRecordingIndicator()
        }
        
        // Start flashing with animation
        recordingIndicator?.layer?.opacity = 1.0
        
        // Create timer that toggles the opacity
        indicatorTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            if let indicator = self?.recordingIndicator, let layer = indicator.layer {
                // Animate opacity change with fade effect
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = layer.opacity
                animation.toValue = layer.opacity > 0.5 ? 0.3 : 1.0
                animation.duration = 0.3
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                
                layer.add(animation, forKey: "opacity")
                layer.opacity = layer.opacity > 0.5 ? 0.3 : 1.0
            }
        }
    }
    
    /**
     * Hides the recording indicator
     */
    private func hideRecordingIndicator() {
        indicatorTimer?.invalidate()
        indicatorTimer = nil
        
        // Fade out with animation
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = recordingIndicator?.layer?.opacity ?? 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        
        recordingIndicator?.layer?.add(fadeOut, forKey: "opacity")
        recordingIndicator?.layer?.opacity = 0.0
    }
    
    // MARK: - Recording Control
    
    /**
     * Toggles recording on/off when the record button is clicked
     */
    @IBAction func recordButtonClicked(_ sender: NSButton) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /**
     * Updates the zoom level when the slider value changes
     */
    @IBAction func zoomLevelChanged(_ sender: NSSlider) {
        zoomLevel = CGFloat(sender.doubleValue)
        statusLabel.stringValue = "Zoom level: \(String(format: "%.1f", zoomLevel))x"
        
        // Enable cursor tracking if zoom level is greater than 1.0
        updateCursorTracking()
    }
    
    /**
     * Updates cursor tracking based on zoom level
     */
    private func updateCursorTracking() {
        // Only track cursor if zoomed in
        let shouldTrackCursor = zoomLevel > 1.0
        
        if shouldTrackCursor != trackCursorForZoom {
            trackCursorForZoom = shouldTrackCursor
            
            if trackCursorForZoom {
                // Start cursor tracking timer if not already running
                if cursorTrackingTimer == nil {
                    cursorTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                        self?.updateCursorPosition()
                    }
                }
                statusLabel.stringValue = "Zoom \(String(format: "%.1f", zoomLevel))x (following cursor)"
            } else {
                // Stop cursor tracking timer
                cursorTrackingTimer?.invalidate()
                cursorTrackingTimer = nil
                statusLabel.stringValue = "Zoom disabled"
            }
        }
    }
    
    /**
     * Updates the cursor position for zoom tracking
     */
    private func updateCursorPosition() {
        guard trackCursorForZoom, zoomLevel > 1.0 else { return }
        
        // Get current cursor position in screen coordinates
        let cursorLocation = NSEvent.mouseLocation
        
        // Convert from screen coordinates to window coordinates
        if let window = view.window, let screen = window.screen {
            // Compensate for screen coordinate system starting from bottom left
            let flippedPos = CGPoint(
                x: cursorLocation.x,
                y: screen.frame.height - cursorLocation.y
            )
            
            // Store the cursor position
            cursorPosition = flippedPos
            
            // Apply zoom centered on cursor position if we have a preview layer
            applyCursorZoom()
        }
    }
    
    /**
     * Applies zoom transformation to preview layer centered on cursor
     */
    private func applyCursorZoom() {
        guard let previewLayer = previewLayer, trackCursorForZoom, zoomLevel > 1.0 else { return }
        
        // Calculate the visible window bounds
        if let screen = NSScreen.main {
            // Calculate proportion of cursor position relative to screen
            let screenBounds = screen.frame
            let relativeX = cursorPosition.x / screenBounds.width
            let relativeY = cursorPosition.y / screenBounds.height
            
            // Apply zoom transformation to preview layer
            let zoom = zoomLevel
            
            // Create zoom transform centered on cursor position
            let transform = CATransform3DIdentity
            
            // 1. Scale by zoom factor
            let scaledTransform = CATransform3DScale(transform, zoom, zoom, 1.0)
            
            // 2. Translate to keep cursor position visible in the center
            // This calculation moves the content so cursor stays visible
            let translateX = (0.5 - relativeX) * previewLayer.bounds.width * zoom
            let translateY = (0.5 - relativeY) * previewLayer.bounds.height * zoom
            let finalTransform = CATransform3DTranslate(scaledTransform, translateX, translateY, 0)
            
            // Apply transform with animation for smoother experience
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1)
            previewLayer.transform = finalTransform
            CATransaction.commit()
        }
    }
    
    /**
     * Starts the screen recording process
     */
    private func startRecording() {
        // Check if we need to configure the screen capture session first
        if captureStream == nil {
            // Show a loading message
            statusLabel.stringValue = "Preparing screen capture..."
            
            // Configure the capture session - this will set up captureStream
            configureCaptureSession()
            
            // Schedule a check to see if captureStream is available after configuration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                if self.captureStream != nil {
                    // Now that we have a capture stream, proceed with recording
                    self.continueStartRecording()
                } else {
                    // Still no capture stream after waiting
                    self.statusLabel.stringValue = "Failed to initialize screen capture. Please try again."
                    self.recordButton.isEnabled = true
                }
            }
            return
        }
        
        // If we already have a capture stream, proceed directly
        continueStartRecording()
    }
    
    /**
     * Continues the recording process after ensuring capture stream is available
     */
    private func continueStartRecording() {
        // Make sure we still have screen capture configured
        guard captureStream != nil else {
            print("No active capture stream available")
            statusLabel.stringValue = "Error: No screen capture stream available"
            return
        }
        
        // Reset any previous state and create output file URL
        let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        outputFileURL = downloadsPath.appendingPathComponent("ScreenRecording_\(dateString).mp4")
        
        // Initialize the asset writer with the output file
        initializeAssetWriter()
        
        // Make sure asset writer was successfully initialized
        guard assetWriter != nil, assetWriterVideoInput != nil else {
            handleRecordingError("Failed to initialize recording")
            return
        }
        
        // Reset recording duration
        recordingDuration = 0
        firstSampleTime = nil
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateRecordingTime), userInfo: nil, repeats: true)
        
        // Show recording indicator
        showRecordingIndicator()
        
        // Update UI
        isRecording = true
        recordButton.title = "Stop Recording"
        statusLabel.stringValue = "Recording... (0:00)"
        
        // Debug info
        if let assetWriter = self.assetWriter {
            print("AssetWriter initialized with status: \(assetWriter.status.rawValue)")
        } else {
            print("AssetWriter is nil when starting recording")
        }
    }
    
    /**
     * Initializes the asset writer for the recording session
     */
    private func initializeAssetWriter() {
        guard let outputFileURL = outputFileURL else { 
            handleRecordingError("Could not create output file path")
            return 
        }
        
        // Delete any existing file at that path
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            do {
                try FileManager.default.removeItem(at: outputFileURL)
                print("Removed existing file at \(outputFileURL.path)")
            } catch {
                print("Error removing existing file: \(error.localizedDescription)")
                // Continue anyway, as AVAssetWriter will fail if file exists
            }
        }
        
        // Reset state variables
        firstSampleTime = nil
        
        // Create asset writer with better error handling
        do {
            assetWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
            print("Created asset writer for: \(outputFileURL.path)")
            
            // Add metadata for better file compatibility
            let metadataItem = AVMutableMetadataItem()
            metadataItem.key = AVMetadataKey.commonKeyTitle as (NSCopying & NSObjectProtocol)
            metadataItem.keySpace = AVMetadataKeySpace.common
            metadataItem.value = "ScreenRecording" as NSString
            assetWriter?.metadata = [metadataItem]
            
            // Add observer for errors (using notification name is not available)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAVAssetWriterFailure),
                name: NSNotification.Name("AVAssetWriterFailureNotification"),
                object: assetWriter
            )
            
        } catch {
            statusLabel.stringValue = "Error creating asset writer: \(error.localizedDescription)"
            handleRecordingError("Failed to create asset writer: \(error.localizedDescription)")
            return
        }
        
        guard let assetWriter = assetWriter else {
            handleRecordingError("AssetWriter unexpectedly nil after creation")
            return
        }
        
        // Configure video settings for optimal quality and performance
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920, // Full HD as per PRD
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12000000, // 12 Mbps for high quality tutorial videos
                AVVideoProfileLevelKey: "H264_High_AutoLevel", // High profile for better quality
                AVVideoMaxKeyFrameIntervalKey: 30, // Keyframe every 1 second at 30fps
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0, // 1 second between keyframes for stability
                AVVideoAllowFrameReorderingKey: false, // Disable frame reordering for more stable output
                AVVideoExpectedSourceFrameRateKey: 30 // Explicitly tell encoder the frame rate
            ]
        ]
        
        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        
        // Configure for realtime capture with optimized settings
        if let assetWriterVideoInput = assetWriterVideoInput {
            assetWriterVideoInput.expectsMediaDataInRealTime = true
            
            // Set transform to ensure correct orientation
            assetWriterVideoInput.transform = CGAffineTransform.identity
            
            // Configure proper timebase for more stable recording
            let fps = CMTimeScale(30)
            assetWriterVideoInput.mediaTimeScale = fps
            
            if assetWriter.canAdd(assetWriterVideoInput) {
                assetWriter.add(assetWriterVideoInput)
                print("Added video input to asset writer")
            } else {
                handleRecordingError("Cannot add video input to asset writer")
                return
            }
            
            // Create pixel buffer adaptor for more efficient encoding
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            // The pixel buffer adaptor can improve encoding efficiency
            _ = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterVideoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
        } else {
            handleRecordingError("Failed to create video input")
            return
        }
        
        // Add audio input if audio capture is enabled
        if captureSession?.capturesAudio == true {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000 // 128 kbps audio
            ]
            
            let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            assetWriterAudioInput.expectsMediaDataInRealTime = true
            
            if assetWriter.canAdd(assetWriterAudioInput) {
                assetWriter.add(assetWriterAudioInput)
                print("Added audio input to asset writer")
            } else {
                print("Warning: Could not add audio input to asset writer")
                // Continue without audio rather than failing completely
            }
        }
    }
    
    /**
     * Handle AssetWriter failure notifications
     */
    @objc private func handleAVAssetWriterFailure(_ notification: Notification) {
        // Since AVAssetWriterFailureReasonKey isn't available, extract the error directly
        let error = assetWriter?.error
        print("AVAssetWriter failure notification: \(error?.localizedDescription ?? "Unknown error")")
        
        // Attempt to restart recording if we're still supposed to be recording
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            
            // If we're not already finalizing, try to recover
            if !self.isFinalizingRecording {
                self.restartAttempts += 1
                
                if self.restartAttempts <= 3 {
                    print("Attempting to restart recording after failure (attempt \(self.restartAttempts))")
                    self.resetRecordingSession()
                } else {
                    print("Too many restart attempts, stopping recording")
                    self.stopRecording()
                }
            }
        }
    }
    
    /**
     * Updates recording time display
     */
    @objc private func updateRecordingTime() {
        recordingDuration += 1
        let minutes = recordingDuration / 60
        let seconds = recordingDuration % 60
        statusLabel.stringValue = "Recording... (\(minutes):\(String(format: "%02d", seconds)))"
    }
    
    /**
     * Stops the screen recording process
     */
    private func stopRecording() {
        guard !isFinalizingRecording else {
            print("Already stopping recording, ignoring duplicate call")
            return
        }
        
        isFinalizingRecording = true
        print("Stopping recording...")
        statusLabel.stringValue = "Stopping recording..."
        
        // Stop cursor tracking if active
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = nil
        
        // Reset transform on preview layer if cursor tracking for zoom is active
        if trackCursorForZoom && previewLayer != nil {
            let isTransformed = !CATransform3DIsIdentity(previewLayer!.transform)
            if isTransformed {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                previewLayer?.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        }
        
        guard captureStream != nil, let assetWriter = assetWriter, isRecording else {
            statusLabel.stringValue = "No active recording to stop"
            isFinalizingRecording = false
            isRecording = false
            updateUI()
            return
        }
        
        // First stop the stream
        if let captureStream = captureStream {
            captureStream.stopCapture { [weak self] error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error stopping capture stream: \(error.localizedDescription)")
                } else {
                    print("Capture stream stopped successfully")
                }
                
                // Now finalize the recording
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    
                    // Finalize asset writer if it was started
                    if assetWriter.status == .writing {
                        self.finalizeRecording(success: true) { [weak self] in
                            guard let self = self else { return }
                            
                            // Cleanup after finalization
                            self.isRecording = false
                            self.isFinalizingRecording = false
                            self.recordingTimer?.invalidate()
                            self.recordingTimer = nil
                            self.recordingDuration = 0
                            self.restartAttempts = 0
                            
                            // Update UI on main thread
                            DispatchQueue.main.async {
                                self.updateUI()
                                self.statusLabel.stringValue = "Recording saved"
                                if let url = self.outputFileURL {
                                    self.showCompletedDialog(for: url)
                                }
                            }
                        }
                    } else {
                        // If asset writer wasn't started or failed, just clean up
                        print("Asset writer was not in writing state: \(assetWriter.status.rawValue)")
                        self.outputFileURL = nil
                        self.assetWriter = nil
                        self.assetWriterVideoInput = nil
                        
                        self.isRecording = false
                        self.isFinalizingRecording = false
                        self.recordingTimer?.invalidate()
                        self.recordingTimer = nil
                        self.recordingDuration = 0
                        self.restartAttempts = 0
                        
                        // Update UI
                        DispatchQueue.main.async {
                            self.updateUI()
                            self.statusLabel.stringValue = "Recording discarded"
                        }
                    }
                }
            }
        } else {
            // No capture stream to stop, just update UI
            isRecording = false
            isFinalizingRecording = false
            updateUI()
            statusLabel.stringValue = "Recording ended"
        }
    }
    
    /**
     * Shows a dialog when recording is completed with export options
     */
    private func showCompletedDialog(for videoURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Recording Complete"
        alert.informativeText = "Your screen recording has been saved to Downloads.\nDuration: \(formatDuration(recordingDuration))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open File")
        alert.addButton(withTitle: "Export for Mobile (9:16)")
        alert.addButton(withTitle: "Open in Finder")
        alert.addButton(withTitle: "Close")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open the file with QuickTime Player
            NSWorkspace.shared.open(videoURL)
        } else if response == NSApplication.ModalResponse(1001) {
            // Export for mobile
            exportForMobile(videoURL)
        } else if response == NSApplication.ModalResponse(1002) {
            // Show in Finder
            NSWorkspace.shared.activateFileViewerSelecting([videoURL])
        }
    }
    
    /**
     * Exports the recording in mobile-friendly 9:16 format as specified in the PRD
     */
    private func exportForMobile(_ sourceURL: URL) {
        // Show progress indicator
        progressIndicator?.startAnimation(nil)
        progressIndicator?.isHidden = false
        statusLabel.stringValue = "Preparing mobile export..."
        
        // Create a destination URL for the export
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let mobileName = "\(filename)_mobile.mp4"
        let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent(mobileName)
        
        // Remove any existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create asset and export session
        let asset = AVAsset(url: sourceURL)
        
        Task {
            do {
                // Load video track
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else {
                    throw NSError(domain: "ScreenRecorder", code: 201, 
                                 userInfo: [NSLocalizedDescriptionKey: "No video track found"])
                }
                
                // Get the natural size of the video
                let videoSize = try await videoTrack.load(.naturalSize)
                let videoTransform = try await videoTrack.load(.preferredTransform)
                
                // Calculate the export composition for 9:16 aspect ratio
                let exportSession = try await createMobileExportSession(
                    for: asset,
                    outputURL: outputURL,
                    originalSize: videoSize,
                    transform: videoTransform
                )
                
                // Start export on main actor to avoid sendable warning
                await MainActor.run {
                    // Start the export (will be inherently on the main actor)
                    exportSession.exportAsynchronously {
                        // Handle completion on main thread
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.progressIndicator?.stopAnimation(nil)
                            self.progressIndicator?.isHidden = true
                            
                            if exportSession.status == .completed {
                                self.statusLabel.stringValue = "Mobile export completed"
                                
                                // Show completion dialog
                                let exportAlert = NSAlert()
                                exportAlert.messageText = "Mobile Export Complete"
                                exportAlert.informativeText = "The 9:16 version has been saved to Downloads"
                                exportAlert.alertStyle = .informational
                                exportAlert.addButton(withTitle: "Open File")
                                exportAlert.addButton(withTitle: "Open in Finder")
                                
                                let response = exportAlert.runModal()
                                if response == .alertFirstButtonReturn {
                                    NSWorkspace.shared.open(outputURL)
                                } else if response == .alertSecondButtonReturn {
                                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                                }
                            } else if let error = exportSession.error {
                                self.statusLabel.stringValue = "Export failed: \(error.localizedDescription)"
                                
                                // Show error dialog
                                let errorAlert = NSAlert()
                                errorAlert.messageText = "Export Failed"
                                errorAlert.informativeText = "Error creating mobile version: \(error.localizedDescription)"
                                errorAlert.alertStyle = .warning
                                errorAlert.addButton(withTitle: "OK")
                                errorAlert.runModal()
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.progressIndicator?.stopAnimation(nil)
                    self.progressIndicator?.isHidden = true
                    self.statusLabel.stringValue = "Export failed: \(error.localizedDescription)"
                    
                    // Show error dialog
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Export Failed"
                    errorAlert.informativeText = "There was an error creating the mobile version: \(error.localizedDescription)"
                    errorAlert.alertStyle = .warning
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /**
     * Creates export session for mobile-friendly 9:16 format
     */
    private func createMobileExportSession(for asset: AVAsset, 
                                         outputURL: URL,
                                         originalSize: CGSize,
                                         transform: CGAffineTransform) async throws -> AVAssetExportSession {
        // Create a composition for the export
        let composition = AVMutableComposition()
        
        // Create video composition for 9:16 transformation
        let videoComposition = AVMutableVideoComposition()
        
        // Calculate target size for 9:16 aspect ratio
        // For mobile, we want 9:16 aspect ratio (portrait mode)
        let targetWidth: CGFloat = 1080 // Standard width for mobile videos
        let targetHeight: CGFloat = 1920 // 9:16 aspect ratio
        
        // Get the video track and add it to the composition
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video, 
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "ScreenRecorder", code: 203, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not create composition tracks"])
        }
        
        // Get the duration of the original video
        let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        // Add the video track to the composition
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        
        // Set up the video composition
        videoComposition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30) // 30fps
        
        // Create an instruction for the video composition
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        
        // Create a layer instruction
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        
        // Calculate the scaling to fill the 9:16 frame while preserving content
        // For tutorial videos, we want to ensure the content is large enough to be visible on mobile
        let scale = max(targetWidth / originalSize.width, targetHeight / originalSize.height) * 1.1 // Slight zoom for better visibility
        
        // Center the content in the frame
        let xPosition = (targetWidth - (originalSize.width * scale)) / 2
        let yPosition = (targetHeight - (originalSize.height * scale)) / 2
        
        // Create a transform that:
        // 1. Applies the original transform from the source video
        // 2. Scales the content to fill the 9:16 frame
        // 3. Centers the content in the frame
        var finalTransform = transform
        finalTransform = finalTransform.translatedBy(x: xPosition, y: yPosition)
        finalTransform = finalTransform.scaledBy(x: scale, y: scale)
        
        // Set the transform on the layer instruction
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Create and configure the export session
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "ScreenRecorder", code: 204, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true
        
        return exportSession
    }
    
    /**
     * Formats duration in seconds to mm:ss format
     */
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }
    
    /**
     * Handles recording errors
     */
    private func handleRecordingError(_ message: String) {
        // Hide progress
        progressIndicator?.stopAnimation(nil)
        progressIndicator?.isHidden = true
        
        // Update UI
        statusLabel.stringValue = message
        recordButton.title = "Start Recording"
        recordButton.isEnabled = true
        isFinalizingRecording = false
    }
    
    /**
     * Configures the screen capture session
     */
    private func configureCaptureSession() {
        // Only set up the screen capture itself without creating output file yet
        // This prevents unexpected exports at start
        setupScreenCapture()
    }
    
    /**
     * Sets up the screen capture using ScreenCaptureKit
     */
    private func setupScreenCapture() {
        // Get the main display
        Task {
            do {
                // First check if we have permission by retrieving the current content
                let content = try await SCShareableContent.current
                
                // Log available content for diagnostics
                print("SCShareableContent: \(content.displays.count) displays, \(content.windows.count) windows")
                for (i, display) in content.displays.enumerated() {
                    print("Display \(i): \(display.width)x\(display.height)")
                }
                
                // Store the app's bundle ID to check if we're getting asked for permissions repeatedly
                print("App bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                
                // Filter for displays only
                guard !content.displays.isEmpty else {
                    throw NSError(domain: "ScreenRecorder", code: 1, 
                                  userInfo: [NSLocalizedDescriptionKey: "No displays found. Screen recording permission may be missing."])
                }
                
                let mainDisplay = content.displays.first!
                
                // Create a stream configuration
                let config = SCStreamConfiguration()
                
                // Configure video quality
                config.width = 1920
                config.height = 1080
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
                config.queueDepth = 5
                
                // Enable cursor capture with mouse clicks
                config.showsCursor = true
                // config.showsMouseClicks = true  // Not available in older macOS versions
                
                // Audio capture settings
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                
                captureSession = config
                
                // IMPORTANT: Use empty array for excludingApplications to ensure recording continues when focus changes
                // Create filter that captures entire display without excluding any windows or applications
                let filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])
                
                // Create and start the stream with our filter and configuration
                captureStream = SCStream(filter: filter, configuration: config, delegate: self)
                
                // Add stream output to handle frames
                try captureStream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
                
                // Add audio output separately
                if config.capturesAudio {
                    try captureStream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
                }
                
                // Start capture
                try await captureStream?.startCapture()
                
                // Update UI on success
                DispatchQueue.main.async { [weak self] in
                    self?.statusLabel.stringValue = "Capturing screen..."
                }
            } catch {
                print("Screen capture setup error: \(error)")
                DispatchQueue.main.async { [weak self] in
                    if error.localizedDescription.contains("declined") || error.localizedDescription.contains("denied") {
                        self?.statusLabel.stringValue = "Permission denied. Enable in System Settings → Privacy & Security → Screen Recording."
                        // Add a button to open system settings directly
                        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(self?.openScreenRecordingSettings))
                        settingsButton.setFrameOrigin(NSPoint(x: self?.recordButton.frame.origin.x ?? 0, 
                                                             y: (self?.recordButton.frame.origin.y ?? 0) - 40))
                        self?.view.addSubview(settingsButton)
                    } else {
                        self?.statusLabel.stringValue = "Failed to start capture: \(error.localizedDescription)"
                    }
                    self?.isRecording = false
                    self?.recordButton.title = "Start Recording"
                    self?.recordButton.isEnabled = false
                }
            }
        }
    }
    
    /**
     * Opens System Settings to the Screen Recording privacy section
     */
    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    
    /**
     * Manually requests screen recording permission
     */
    @IBAction func requestPermissionClicked(_ sender: NSButton) {
        // Show a dialog explaining why permission is needed
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "This app needs screen recording permission to capture your screen. You'll be prompted by macOS to allow access."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Request Permission")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Trigger permission request
            prepareScreenCapture()
            
            // Also provide instructions to manually enable in System Settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let settingsAlert = NSAlert()
                settingsAlert.messageText = "Check System Settings"
                settingsAlert.informativeText = "If permission dialog didn't appear, please manually enable screen recording for this app in System Settings → Privacy & Security → Screen Recording."
                settingsAlert.alertStyle = .informational
                settingsAlert.addButton(withTitle: "Open Settings")
                settingsAlert.addButton(withTitle: "OK")
                
                let settingsResponse = settingsAlert.runModal()
                if settingsResponse == .alertFirstButtonReturn {
                    // Open Security & Privacy settings
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
        }
    }
    
    // MARK: - App Focus Handling
    
    /**
     * Handles app activation (coming to foreground)
     */
    @objc private func handleAppActivation() {
        print("App became active")
        // We don't need to restart recording here as it should continue in the background
    }
    
    /**
     * Handles app deactivation (going to background)
     */
    @objc private func handleAppDeactivation() {
        print("App resigned active")
        // We don't need to stop recording here, just log that we're continuing recording in background
        if isRecording {
            print("Continuing recording in background")
            // Optionally update UI to indicate background recording
        }
    }
    
    /**
     * Toggles cursor tracking for zoom
     */
    @objc private func toggleCursorTracking(_ sender: NSButton) {
        trackCursorForZoom = (sender.state == .on)
        updateCursorTracking()
    }
    
    /**
     * Updates the UI based on the current state of recording
     */
    private func updateUI() {
        if isRecording {
            recordButton.title = "Stop Recording"
            recordButton.contentTintColor = NSColor.systemRed
            hideRecordingIndicator()
        } else {
            recordButton.title = "Start Recording"
            recordButton.contentTintColor = nil
            showRecordingIndicator()
        }
        
        // Update other UI elements as needed
        zoomLevelSlider.isEnabled = !isRecording
    }
    
    /**
     * Finalizes the recording and completes asset writer
     */
    private func finalizeRecording(success: Bool, completion: @escaping () -> Void) {
        print("Finalizing recording, success: \(success)")
        
        guard let assetWriter = assetWriter else {
            print("Asset writer is nil during finalization")
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        // Check if asset writer is in a valid state for finalization
        if assetWriter.status != .writing {
            print("Asset writer not in writing state during finalization: \(assetWriter.status.rawValue)")
            
            // Try to recover if possible by removing any partial files
            if let url = outputFileURL, FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("Removed corrupt or partial file at: \(url.path)")
                } catch {
                    print("Failed to remove corrupt file: \(error)")
                }
            }
            
            // Clean up resources
            self.assetWriter = nil
            self.assetWriterVideoInput = nil
            self.outputFileURL = nil
            self.firstSampleTime = nil
            
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        // Add a small delay to ensure the last frames are processed
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Mark all inputs as finished
            for input in assetWriter.inputs {
                input.markAsFinished()
                print("Marked input as finished: \(input.mediaType.rawValue)")
            }
            
            // Finalize writing with timeout protection
            let finalizationStartTime = Date()
            
            assetWriter.finishWriting { [weak self] in
                guard let self = self else { return }
                
                let finalizationDuration = Date().timeIntervalSince(finalizationStartTime)
                print("Finalization took \(finalizationDuration) seconds")
                
                switch assetWriter.status {
                case .completed:
                    print("Recording completed successfully")
                    
                    // Verify the file exists and has valid size
                    if let url = self.outputFileURL, 
                       FileManager.default.fileExists(atPath: url.path),
                       let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = attributes[.size] as? NSNumber,
                       fileSize.int64Value > 1000 { // Minimum valid size
                        print("Recording saved successfully at: \(url.path)")
                        print("File size: \(fileSize.int64Value / 1024 / 1024) MB")
                    } else {
                        print("Warning: Recording file may be missing or corrupted")
                    }
                    
                case .failed:
                    print("AssetWriter failed: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
                    
                    // Remove corrupted file
                    if let url = self.outputFileURL, FileManager.default.fileExists(atPath: url.path) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            print("Removed corrupted file at: \(url.path)")
                        } catch {
                            print("Failed to remove corrupted file: \(error)")
                        }
                    }
                    
                default:
                    print("AssetWriter in unexpected state after finishing: \(assetWriter.status.rawValue)")
                }
                
                // Clean up resources
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
}

// MARK: - SCStreamOutput Delegate
extension MainViewController: SCStreamOutput {
    /**
     * Processes captured video frames
     */
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isFinalizingRecording else { return }
        
        switch type {
        case .screen:
            // Create a copy of the buffer to prevent modifications during processing
            var bufferCopy: CMSampleBuffer?
            
            // Create a deep copy of the sample buffer to ensure thread safety
            let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
            if let _ = blockBuffer, let _ = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var timingInfo = CMSampleTimingInfo()
                CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
                
                CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleBufferOut: &bufferCopy)
            }
            
            var bufferToProcess = sampleBuffer
            if let copiedBuffer = bufferCopy {
                bufferToProcess = copiedBuffer
            } else {
                print("Warning: Using original buffer without copy")
            }
            
            // Use the buffer for preview and recording
            handleVideoSampleBuffer(bufferToProcess)
            
        case .audio:
            handleAudioSampleBuffer(sampleBuffer)
            
        @unknown default:
            print("Unknown sample buffer type: \(type)")
            break
        }
    }
    
    /**
     * Handles video sample buffer processing
     */
    private func handleVideoSampleBuffer(_ buffer: CMSampleBuffer) {
        // Ensure buffer is valid
        guard CMSampleBufferIsValid(buffer) else {
            print("Invalid sample buffer, skipping")
            return
        }
        
        // Preview the frame on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Enqueue the sample buffer to the preview layer
            self.previewLayer?.enqueue(buffer)
            
            // Apply cursor zoom if needed
            if self.trackCursorForZoom && self.zoomLevel > 1.0 {
                self.updateCursorPosition()
            }
        }
        
        // Bail early if not recording or if finalizing
        guard isRecording && !isFinalizingRecording else {
            return
        }
        
        // Get asset writer and input - bail early if not available
        guard let assetWriter = assetWriter, 
              let assetWriterVideoInput = assetWriterVideoInput else {
            return
        }
        
        // Initialize recording time if needed
        let sampleTime = CMSampleBufferGetPresentationTimeStamp(buffer)
        
        if firstSampleTime == nil {
            firstSampleTime = sampleTime
            print("First video sample time: \(firstSampleTime!.seconds)")
            
            // Start the asset writer if it's in the unknown state
            if assetWriter.status == .unknown {
                print("Starting AssetWriter session")
                assetWriter.startWriting()
                assetWriter.startSession(atSourceTime: firstSampleTime!)
                print("AssetWriter status after starting session: \(assetWriter.status.rawValue)")
            } else if assetWriter.status != .writing {
                print("AssetWriter in unexpected state: \(assetWriter.status.rawValue)")
                
                // Try to reset the session if not already writing
                if assetWriter.status != .completed {
                    DispatchQueue.main.async { [weak self] in
                        self?.resetRecordingSession()
                    }
                    return
                }
            }
        } else {
            // Ensure frame timing is valid
            let elapsed = CMTimeSubtract(sampleTime, firstSampleTime!)
            if CMTimeCompare(elapsed, .zero) < 0 {
                print("Warning: Dropping frame with negative timestamp")
                return
            }
        }
        
        // Only append if the asset writer is in writing state and ready for more data
        if assetWriter.status == .writing && assetWriterVideoInput.isReadyForMoreMediaData {
            // Debug keyframes for diagnostics
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]]
            let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil
            
            if isKeyFrame && recordingDuration % 5 == 0 {
                let frameTime = sampleTime.seconds - firstSampleTime!.seconds
                let duration = CMSampleBufferGetDuration(buffer).seconds
                print("Processing keyframe at \(String(format: "%.2f", frameTime))s, duration: \(duration)s")
            }
            
            // Append the sample buffer on a dedicated queue
            let appendSuccess = assetWriterVideoInput.append(buffer)
            
            if !appendSuccess {
                let status = assetWriter.status.rawValue
                let errorDesc = assetWriter.error?.localizedDescription ?? "Unknown error"
                print("Failed to append video frame - status: \(status), error: \(errorDesc)")
                
                // Handle critical errors
                if assetWriter.status == .failed {
                    DispatchQueue.main.async { [weak self] in
                        self?.handleAssetWriterFailure()
                    }
                }
            }
        } else if assetWriter.status != .writing {
            print("AssetWriter not in writing state: \(assetWriter.status.rawValue)")
            if let error = assetWriter.error {
                print("AssetWriter error: \(error.localizedDescription)")
            }
        }
    }
    
    /**
     * Handles audio sample buffer processing
     */
    private func handleAudioSampleBuffer(_ buffer: CMSampleBuffer) {
        // Skip if not recording or finalizing
        guard isRecording && !isFinalizingRecording else {
            return
        }
        
        // Get asset writer and ensure it's in writing state
        guard let assetWriter = assetWriter,
              assetWriter.status == .writing else {
            return
        }
        
        // Find the audio input from the asset writer's inputs
        guard let audioInput = assetWriter.inputs.first(where: { $0.mediaType == .audio }),
              audioInput.isReadyForMoreMediaData else {
            return
        }
        
        // Initialize first sample time if needed
        if firstSampleTime == nil {
            firstSampleTime = CMSampleBufferGetPresentationTimeStamp(buffer)
            print("First audio sample time: \(firstSampleTime!.seconds)")
            
            if assetWriter.status == .unknown {
                assetWriter.startWriting()
                assetWriter.startSession(atSourceTime: firstSampleTime!)
                print("Started AssetWriter session from audio")
            }
        }
        
        // Append the audio buffer
        let success = audioInput.append(buffer)
        
        if !success {
            print("Failed to append audio sample: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    /**
     * Resets the recording session when AssetWriter is in an invalid state
     */
    private func resetRecordingSession() {
        print("Resetting recording session due to invalid AssetWriter state")
        // Only attempt this if we're still supposed to be recording
        if isRecording {
            // Stop any existing capture
            Task {
                do {
                    try await captureStream?.stopCapture()
                    captureStream = nil
                    
                    // Reset recording state
                    assetWriter = nil
                    assetWriterVideoInput = nil
                    firstSampleTime = nil
                    
                    // Restart the recording
                    configureCaptureSession()
                } catch {
                    print("Error resetting capture session: \(error)")
                    handleRecordingError("Recording failed - please try again")
                }
            }
        }
    }
    
    /**
     * Handles asset writer failure during recording
     */
    private func handleAssetWriterFailure() {
        if isRecording {
            print("Asset writer failed during recording - attempting to save partial recording")
            stopRecording()
        }
    }
}

// MARK: - SCStreamDelegate
extension MainViewController: SCStreamDelegate {
    /**
     * Handles stream errors and attempts to restart if recording is still active
     */
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error.localizedDescription)")
        
        // Only attempt to restart if we're recording and NOT in the process of stopping
        if isRecording && !isFinalizingRecording {
            restartAttempts += 1
            if restartAttempts > 3 {
                print("Too many restart attempts, stopping recording")
                DispatchQueue.main.async {
                    self.stopRecording()
                }
                return
            }
            
            print("Attempting to restart stream in 1 second")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Double-check we're still recording before restarting
                if self.isRecording && !self.isFinalizingRecording {
                    self.setupScreenCapture()
                } else {
                    print("Cancelling restart because recording was stopped")
                }
            }
        } else {
            print("Not restarting stream because recording is being finalized or stopped")
        }
    }
} 