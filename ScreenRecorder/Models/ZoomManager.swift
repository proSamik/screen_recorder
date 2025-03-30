import Foundation
import CoreGraphics
import AVFoundation

/**
 * Manages zoom functionality for screen recording.
 * Handles mouse tracking and applies zoom transformations to the captured frames.
 */
class ZoomManager {
    
    // MARK: - Properties
    
    /**
     * Current zoom level (1.0 = no zoom)
     */
    private(set) var zoomLevel: CGFloat = 1.0
    
    /**
     * Last tracked mouse position
     */
    private var lastMousePosition: CGPoint = .zero
    
    /**
     * Current display bounds
     */
    private var displayBounds: CGRect = .zero
    
    /**
     * Target aspect ratio for output (width/height)
     */
    private var targetAspectRatio: CGFloat = 16.0 / 9.0
    
    /**
     * Smoothing factor for mouse movement (0-1, where 1 = no smoothing)
     */
    private var mouseMovementSmoothing: CGFloat = 0.3
    
    // MARK: - Initialization
    
    /**
     * Initializes the zoom manager with default settings
     */
    init() {
        // Get main display bounds
        if let mainDisplay = CGMainDisplayID() {
            displayBounds = CGDisplayBounds(mainDisplay)
        }
    }
    
    /**
     * Initializes the zoom manager with specified settings
     * 
     * @param initialZoom The initial zoom level
     * @param aspectRatio The target aspect ratio (width/height)
     * @param smoothing The mouse movement smoothing factor (0-1)
     */
    init(initialZoom: CGFloat, aspectRatio: CGFloat, smoothing: CGFloat) {
        self.zoomLevel = max(1.0, initialZoom)
        self.targetAspectRatio = aspectRatio
        self.mouseMovementSmoothing = min(max(0.0, smoothing), 1.0)
        
        // Get main display bounds
        if let mainDisplay = CGMainDisplayID() {
            displayBounds = CGDisplayBounds(mainDisplay)
        }
    }
    
    // MARK: - Public Methods
    
    /**
     * Sets the current zoom level
     * 
     * @param level The new zoom level (minimum 1.0)
     */
    func setZoomLevel(_ level: CGFloat) {
        zoomLevel = max(1.0, level)
    }
    
    /**
     * Sets the target aspect ratio for output
     * 
     * @param aspectRatio The width/height ratio (e.g., 16/9)
     */
    func setAspectRatio(_ aspectRatio: CGFloat) {
        targetAspectRatio = aspectRatio
    }
    
    /**
     * Updates the current mouse position
     * 
     * @param position The current mouse position
     * @return The smoothed mouse position after applying smoothing
     */
    func updateMousePosition(_ position: CGPoint) -> CGPoint {
        // Apply smoothing to mouse movement
        let smoothedX = lastMousePosition.x + (position.x - lastMousePosition.x) * mouseMovementSmoothing
        let smoothedY = lastMousePosition.y + (position.y - lastMousePosition.y) * mouseMovementSmoothing
        
        lastMousePosition = CGPoint(x: smoothedX, y: smoothedY)
        return lastMousePosition
    }
    
    /**
     * Gets the current mouse position in screen coordinates
     * 
     * @return The current mouse position
     */
    func getCurrentMousePosition() -> CGPoint {
        var mouseLocation = NSEvent.mouseLocation
        
        // Convert from Cocoa coordinates (origin at bottom-left) to CG coordinates (origin at top-left)
        mouseLocation.y = displayBounds.height - mouseLocation.y
        
        // Update with smoothing
        return updateMousePosition(mouseLocation)
    }
    
    /**
     * Calculates the zoom transform for a frame based on current settings
     * 
     * @param frameSize The size of the frame to transform
     * @return A CGAffineTransform to apply to the frame
     */
    func calculateZoomTransform(for frameSize: CGSize) -> CGAffineTransform {
        // Skip if no zoom needed
        if zoomLevel <= 1.0 {
            return CGAffineTransform.identity
        }
        
        // Get current mouse position
        let mousePos = getCurrentMousePosition()
        
        // Calculate the zoom center point
        let centerX = mousePos.x / displayBounds.width
        let centerY = mousePos.y / displayBounds.height
        
        // Calculate transform
        var transform = CGAffineTransform.identity
        
        // Scale by zoom level
        transform = transform.scaledBy(x: zoomLevel, y: zoomLevel)
        
        // Translate to keep mouse position centered
        let translateX = frameSize.width * (0.5 - centerX) * (zoomLevel - 1.0) / zoomLevel
        let translateY = frameSize.height * (0.5 - centerY) * (zoomLevel - 1.0) / zoomLevel
        transform = transform.translatedBy(x: translateX, y: translateY)
        
        return transform
    }
    
    /**
     * Applies zoom transform to a sample buffer
     * 
     * @param sampleBuffer The frame to transform
     * @return A new CMSampleBuffer with zoom applied, or the original if processing failed
     */
    func applyZoomToSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        // If no zoom, return the original buffer
        if zoomLevel <= 1.0 {
            return sampleBuffer
        }
        
        // Implementation would convert sample buffer to CVPixelBuffer,
        // apply the transform calculated by calculateZoomTransform,
        // and then convert back to CMSampleBuffer
        
        // This is a complex operation that would require Core Image processing
        // For now, just return the original buffer
        
        return sampleBuffer
    }
} 