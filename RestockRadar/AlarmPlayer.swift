import Foundation
import AVFoundation
import AudioToolbox

/// Loud beeping + vibration when something is back in stock.
/// Uses the "playback" audio mode so it still sounds when the silent switch is on.
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    private var vibrateTask: Task<Void, Never>?

    func start() {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let p = try AVAudioPlayer(data: Tone.alarmWAV)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.play()
            player = p
        } catch {
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
        vibrateTask = Task { @MainActor [weak self] in
            for _ in 0..<40 {                       // about one minute
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
            }
            self?.stop()
        }
    }

    func stop() {
        vibrateTask?.cancel()
        vibrateTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Builds a short beep-beep-beep sound in memory (no sound file needed).
enum Tone {
    static let alarmWAV: Data = makeWAV()

    static func makeWAV() -> Data {
        let sampleRate = 44_100
        let seconds = 1.0
        let count = Int(Double(sampleRate) * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let inBeep = t.truncatingRemainder(dividingBy: 0.25) < 0.15 && t < 0.75
            if inBeep {
                samples[i] = Int16(sin(2 * Double.pi * 1046.5 * t) * 0.8 * Double(Int16.max))
            }
        }

        var data = Data()
        func put(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func put32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        let byteCount = UInt32(count * 2)
        put("RIFF"); put32(36 + byteCount); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2)); put16(2); put16(16)
        put("data"); put32(byteCount)
        for s in samples { put16(UInt16(bitPattern: s)) }
        return data
    }
}
