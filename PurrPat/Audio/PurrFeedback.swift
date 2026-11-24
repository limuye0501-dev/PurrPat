import AVFoundation
import CoreHaptics
import Foundation
import os

/// A 26 Hz purr you can hear (respecting the silent switch) and feel.
final class PurrFeedback {
    private let purrGain = OSAllocatedUnfairLock(initialState: Float(0))
    private let rainGain = OSAllocatedUnfairLock(initialState: Float(0))
    private let audio = AVAudioEngine()
    private var started = false
    private var phase: Float = 0
    private var noise: UInt32 = 0x12345678
    private var haptics: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var hapticsPlaying = false

    func start() {
        guard !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, buffers -> OSStatus in
            self?.render(frameCount: frameCount, buffers: buffers, sampleRate: Float(format.sampleRate))
            return noErr
        }
        audio.attach(node)
        audio.connect(node, to: audio.mainMixerNode, format: format)
        do { try audio.start() } catch { started = false }
    }

    func setActive(_ active: Bool) {
        if active {
            try? audio.start()
        } else {
            audio.pause()
            stopHaptics()
        }
    }

    func setPurr(enabled: Bool, level: Float) {
        let gain = enabled ? min(1, max(0, level)) : 0
        purrGain.withLock { $0 = gain }
        updateHaptics(enabled: enabled, level: gain)
    }

    func setRain(on: Bool) {
        rainGain.withLock { $0 = on ? 0.22 : 0 }
    }

    func playDelight() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let haptics else { return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
        ], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let one = try? haptics.makePlayer(with: pattern) {
            try? one.start(atTime: CHHapticTimeImmediate)
        }
    }

    private func render(frameCount: AVAudioFrameCount, buffers: UnsafeMutablePointer<AudioBufferList>, sampleRate: Float) {
        let gain = purrGain.withLock { $0 }
        let rain = rainGain.withLock { $0 }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        guard let data = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let step = (2 * Float.pi * 26) / sampleRate
        for i in 0..<Int(frameCount) {
            phase += step
            if phase > 2 * Float.pi { phase -= 2 * Float.pi }
            noise = noise &* 1664525 &+ 1013904223
            let n = Float(Int32(bitPattern: noise)) / Float(Int32.max)
            let env = 0.62 + 0.38 * sin(phase)
            let voice = (sin(phase) * 0.55 + sin(phase * 2) * 0.2 + n * 0.12) * env
            let hiss = n * rain
            data[i] = voice * gain * 0.28 + hiss * 0.18
        }
    }

    private func updateHaptics(enabled: Bool, level: Float) {
        guard enabled, level > 0.05, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            stopHaptics()
            return
        }
        if haptics == nil { prepareHaptics() }
        guard let player else { return }
        if !hapticsPlaying {
            try? haptics?.start()
            try? player.start(atTime: CHHapticTimeImmediate)
            hapticsPlaying = true
        }
        let intensity = 0.28 + 0.6 * level
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    private func prepareHaptics() {
        guard let engine = try? CHHapticEngine() else { return }
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak self] in
            try? self?.haptics?.start()
            self?.hapticsPlaying = false
        }
        engine.stoppedHandler = { [weak self] _ in self?.hapticsPlaying = false }
        try? engine.start()
        var events: [CHHapticEvent] = []
        for i in 0..<25 {
            let t = Double(i) / 25.0
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.07),
            ], relativeTime: t))
        }
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.04),
        ], relativeTime: 0, duration: 1))
        guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        player = try? engine.makeAdvancedPlayer(with: pattern)
        player?.loopEnabled = true
        player?.loopEnd = 1
        haptics = engine
    }

    private func stopHaptics() {
        guard hapticsPlaying else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        hapticsPlaying = false
    }
}
