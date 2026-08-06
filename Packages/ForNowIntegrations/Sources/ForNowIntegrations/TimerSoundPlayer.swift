import AppKit

@MainActor
public protocol TimerSoundPlaying: AnyObject {
  func play(volume: Int)
}

@MainActor
public final class SystemTimerSoundPlayer: TimerSoundPlaying {
  public init() {}

  public func play(volume: Int) {
    guard volume > 0 else { return }
    guard
      let sound = NSSound(named: NSSound.Name("Glass"))
        ?? NSSound(named: NSSound.Name("Ping"))
    else {
      NSSound.beep()
      return
    }
    sound.volume = Float(min(max(volume, 0), 100)) / 100
    sound.play()
  }
}

@MainActor
public final class DisabledTimerSoundPlayer: TimerSoundPlaying {
  public private(set) var playedVolumes: [Int] = []

  public init() {}

  public func play(volume: Int) {
    playedVolumes.append(volume)
  }
}
