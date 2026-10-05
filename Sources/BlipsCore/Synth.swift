import Foundation
import JavaScriptCore

/// Runs jsfxr in JavaScriptCore. Every call seeds jsfxr's `Math.random` first, so the same seed
/// always rolls the same preset and renders the same noise. Not thread-safe: use one per task.
public final class Synth {
  private let context: JSContext
  private let presetFunction: JSValue
  private let renderFunction: JSValue
  private let base58Function: JSValue

  public static let presets = [
    "pickupCoin", "laserShoot", "explosion", "powerUp", "hitHurt", "jump", "blipSelect", "synth", "tone", "click",
    "random",
  ]

  public init() throws {
    guard let context = JSContext() else { throw BlipsError("JavaScriptCore couldn't create a context.") }
    self.context = context
    for source in [JSFXRSource.riffwave, JSFXRSource.sfxr, Self.glue] {
      context.evaluateScript(source)
      if let exception = context.exception {
        throw BlipsError("jsfxr didn't load: \(exception)")
      }
    }
    presetFunction = context.objectForKeyedSubscript("blipsPreset")
    renderFunction = context.objectForKeyedSubscript("blipsRender")
    base58Function = context.objectForKeyedSubscript("blipsBase58")
  }

  /// Rolls one of jsfxr's presets, like `pickupCoin`, with the volume `sfxr.generate` uses.
  public func preset(_ name: String, seed: UInt32) throws -> SoundParams {
    guard Self.presets.contains(name) else { throw BlipsError("jsfxr has no \(name) preset.") }
    let json = try call(presetFunction, [name, seed]).toString() ?? ""
    return try JSONDecoder().decode(SoundParams.self, from: Data(json.utf8))
  }

  /// Renders a sound to samples on -1...1 at 44.1 kHz, before any normalizing.
  public func render(_ params: SoundParams, seed: UInt32) throws -> [Float] {
    let value = try call(renderFunction, [params.json, seed])
    let ref = context.jsGlobalContextRef
    var exception: JSValueRef?
    guard let object = JSValueToObject(ref, value.jsValueRef, &exception),
      let bytes = JSObjectGetTypedArrayBytesPtr(ref, object, &exception)
    else {
      throw BlipsError("jsfxr didn't return samples.")
    }
    let count = JSObjectGetTypedArrayLength(ref, object, &exception)
    return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: Float.self), count: count))
  }

  /// The short base58 form jsfxr uses in sfxr.me links.
  public func base58(_ params: SoundParams) throws -> String {
    try call(base58Function, [params.json]).toString() ?? ""
  }

  private func call(_ function: JSValue, _ arguments: [Any]) throws -> JSValue {
    context.exception = nil
    let result = function.call(withArguments: arguments)
    if let exception = context.exception {
      throw BlipsError("jsfxr failed: \(exception)")
    }
    guard let result else { throw BlipsError("jsfxr returned nothing.") }
    return result
  }

  /// Replaces `Math.random` with mulberry32, a small seeded generator, before each call.
  private static let glue = """
    function blipsSeed(seed) {
      var state = seed >>> 0
      Math.random = function () {
        state = (state + 0x6D2B79F5) | 0
        var t = Math.imul(state ^ (state >>> 15), 1 | state)
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
      }
    }

    function blipsPreset(name, seed) {
      blipsSeed(seed)
      var params = jsfxr.sfxr.generate(name)
      return JSON.stringify(params)
    }

    function blipsRender(json, seed) {
      blipsSeed(seed)
      var params = new jsfxr.Params().fromJSON(JSON.parse(json))
      return new Float32Array(new jsfxr.SoundEffect(params).getRawBuffer().normalized)
    }

    function blipsBase58(json) {
      return new jsfxr.Params().fromJSON(JSON.parse(json)).toB58()
    }
    """
}

public struct BlipsError: LocalizedError, Sendable {
  public var message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? { message }
}
