import Foundation
import AVFoundation
import AppKit

/// Generates a simple bar-style waveform image from an audio file
public actor AudioWaveformGenerator {
    public static let shared = AudioWaveformGenerator()
    
    private init() {}
    
    /// Generates a waveform image for the given audio file
    public func generateWaveform(for url: URL, size: CGSize) async -> NSImage? {
        let asset = AVAsset(url: url)
        
        guard let reader = try? AVAssetReader(asset: asset),
              let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var sampleData = Data()
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = [Int16](repeating: 0, count: length / 2)
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
                data.withUnsafeBufferPointer { buffer in
                    sampleData.append(buffer)
                }
            }
        }
        
        guard !sampleData.isEmpty else { return nil }
        
        // Downsample to the number of bars we want
        let barCount = 10
        let samplesPerBar = sampleData.count / 2 / barCount
        var amplitudes: [Float] = []
        
        sampleData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<barCount {
                var maxAmplitude: Int16 = 0
                for j in 0..<samplesPerBar {
                    let sample = abs(int16Ptr[i * samplesPerBar + j])
                    if sample > maxAmplitude {
                        maxAmplitude = sample
                    }
                }
                amplitudes.append(Float(maxAmplitude) / Float(Int16.max))
            }
        }
        
        return drawWaveform(amplitudes: amplitudes, size: size)
    }
    
    private func drawWaveform(amplitudes: [Float], size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        let barWidth = size.width / CGFloat(amplitudes.count)
        let spacing: CGFloat = 2.0
        
        NSColor.systemRed.set() // Use red for audio as per existing convention
        
        for (index, amplitude) in amplitudes.enumerated() {
            let height = max(size.height * CGFloat(amplitude), 2.0)
            let x = CGFloat(index) * barWidth + (spacing / 2)
            let y = (size.height - height) / 2
            
            let rect = NSRect(x: x, y: y, width: barWidth - spacing, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.fill()
        }
        
        image.unlockFocus()
        return image
    }
}
