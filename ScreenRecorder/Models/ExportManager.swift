import Foundation
import AVFoundation

/**
 * Export format options for video output
 */
enum ExportFormat {
    /// Standard 16:9 aspect ratio
    case standard
    /// Mobile-friendly 9:16 aspect ratio
    case mobile
    /// Custom aspect ratio
    case custom(width: Int, height: Int)
    
    /**
     * Converts the export format to dimensions
     * 
     * @param baseWidth The base width to use for calculations
     * @return The calculated dimensions as CGSize
     */
    func dimensions(baseWidth: Int = 1920) -> CGSize {
        switch self {
        case .standard:
            let height = Int(Double(baseWidth) * 9.0 / 16.0)
            return CGSize(width: baseWidth, height: height)
        case .mobile:
            let width = Int(Double(baseWidth) * 9.0 / 16.0)
            return CGSize(width: width, height: baseWidth)
        case .custom(let width, let height):
            return CGSize(width: width, height: height)
        }
    }
}

/**
 * Quality presets for video export
 */
enum ExportQuality {
    /// High quality, larger file size
    case high
    /// Medium quality, balanced file size
    case medium
    /// Low quality, smaller file size
    case low
    
    /**
     * Gets the corresponding AVAssetExportPreset
     * 
     * @return The AVAssetExportPreset string
     */
    func preset() -> String {
        switch self {
        case .high:
            return AVAssetExportPresetHighestQuality
        case .medium:
            return AVAssetExportPreset1280x720
        case .low:
            return AVAssetExportPreset640x480
        }
    }
    
    /**
     * Gets the bitrate for the quality level
     * 
     * @return The bitrate in bits per second
     */
    func bitrate() -> Int {
        switch self {
        case .high:
            return 8_000_000
        case .medium:
            return 4_000_000
        case .low:
            return 2_000_000
        }
    }
}

/**
 * Manages the export of recorded video in different formats
 */
class ExportManager {
    
    // MARK: - Properties
    
    /**
     * The format to export in
     */
    private var exportFormat: ExportFormat = .standard
    
    /**
     * The quality level for export
     */
    private var exportQuality: ExportQuality = .high
    
    /**
     * Progress of the current export (0.0 - 1.0)
     */
    private(set) var exportProgress: Float = 0.0
    
    /**
     * Callback for export progress updates
     */
    var progressCallback: ((Float) -> Void)?
    
    /**
     * Callback for export completion
     */
    var completionCallback: ((URL?, Error?) -> Void)?
    
    // MARK: - Initialization
    
    /**
     * Initializes the export manager with default settings
     */
    init() {}
    
    /**
     * Initializes the export manager with specified settings
     * 
     * @param format The export format to use
     * @param quality The quality level for export
     */
    init(format: ExportFormat, quality: ExportQuality) {
        self.exportFormat = format
        self.exportQuality = quality
    }
    
    // MARK: - Public Methods
    
    /**
     * Sets the export format
     * 
     * @param format The format to export in
     */
    func setExportFormat(_ format: ExportFormat) {
        exportFormat = format
    }
    
    /**
     * Sets the export quality
     * 
     * @param quality The quality level for export
     */
    func setExportQuality(_ quality: ExportQuality) {
        exportQuality = quality
    }
    
    /**
     * Exports a video file to the specified format and quality
     * 
     * @param sourceURL The source video file URL
     * @param destinationURL The destination URL for the exported file
     * @param completion Optional callback on completion with result URL or error
     */
    func exportVideo(from sourceURL: URL, to destinationURL: URL, completion: ((URL?, Error?) -> Void)? = nil) {
        self.completionCallback = completion
        
        // Create asset from source
        let asset = AVAsset(url: sourceURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: exportQuality.preset()) else {
            DispatchQueue.main.async {
                self.completionCallback?(nil, NSError(domain: "ExportManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
            }
            return
        }
        
        // Configure export
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        
        // Get original dimensions
        let videoTrack = asset.tracks(withMediaType: .video).first
        let naturalSize = videoTrack?.naturalSize ?? CGSize(width: 1920, height: 1080)
        
        // Create video composition for resizing if needed
        let targetSize = exportFormat.dimensions()
        if targetSize != naturalSize {
            configureVideoComposition(exportSession: exportSession, asset: asset, targetSize: targetSize)
        }
        
        // Monitor progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.exportProgress = exportSession.progress
            self.progressCallback?(self.exportProgress)
            
            if exportSession.progress >= 1.0 {
                timer.invalidate()
            }
        }
        
        // Export asynchronously
        exportSession.exportAsynchronously {
            progressTimer.invalidate()
            
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    self.completionCallback?(destinationURL, nil)
                case .failed:
                    self.completionCallback?(nil, exportSession.error)
                case .cancelled:
                    self.completionCallback?(nil, NSError(domain: "ExportManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export cancelled"]))
                default:
                    self.completionCallback?(nil, NSError(domain: "ExportManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"]))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /**
     * Configures video composition for resizing
     * 
     * @param exportSession The export session to configure
     * @param asset The source asset
     * @param targetSize The target size for export
     */
    private func configureVideoComposition(exportSession: AVAssetExportSession, asset: AVAsset, targetSize: CGSize) {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return }
        
        // Create composition
        let composition = AVMutableVideoComposition()
        composition.renderSize = targetSize
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        
        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        // Create layer instruction
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Calculate transform to fit the source video into the target size
        let naturalSize = videoTrack.naturalSize
        
        var transform = CGAffineTransform.identity
        
        // Scale to fit
        let sourceAspect = naturalSize.width / naturalSize.height
        let targetAspect = targetSize.width / targetSize.height
        
        if sourceAspect > targetAspect {
            // Source video is wider than target, scale to match height
            let scale = targetSize.height / naturalSize.height
            transform = transform.scaledBy(x: scale, y: scale)
            
            // Center horizontally
            let scaledWidth = naturalSize.width * scale
            let offsetX = (targetSize.width - scaledWidth) / 2
            transform = transform.translatedBy(x: offsetX, y: 0)
        } else {
            // Source video is taller than target, scale to match width
            let scale = targetSize.width / naturalSize.width
            transform = transform.scaledBy(x: scale, y: scale)
            
            // Center vertically
            let scaledHeight = naturalSize.height * scale
            let offsetY = (targetSize.height - scaledHeight) / 2
            transform = transform.translatedBy(x: 0, y: offsetY)
        }
        
        layerInstruction.setTransform(transform, at: .zero)
        
        // Add instructions
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        // Set the composition to the export session
        exportSession.videoComposition = composition
    }
} 