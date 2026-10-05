import Foundation

/// sin, cos, log2 and exp2 made of additions, multiplications and divisions only. Those round the
/// same way on every processor, while the system's math library can differ in the last digit between
/// Intel and Apple silicon. Everything the generator computes before jsfxr renders, and every
/// fingerprint it compares with a threshold, must not differ at all, or that Mac gets a different library.
enum ExactMath {
  /// 2 to the power of `value`.
  static func exp2(_ value: Double) -> Double {
    let whole = value.rounded(.down)
    let x = (value - whole) * 0.693_147_180_559_945_3
    var term = 1.0
    var sum = 1.0
    // e^x for x in [0, ln 2), from its Taylor series.
    for n in 1..<24 {
      term = term * x / Double(n)
      sum += term
    }
    return sum * Double(sign: .plus, exponent: Int(whole), significand: 1)
  }

  static func sinCos(_ angle: Double) -> (sin: Double, cos: Double) {
    var x = angle
    let tau = 2 * Double.pi
    while x > Double.pi { x -= tau }
    while x < -Double.pi { x += tau }
    var sin = 0.0
    var cos = 0.0
    var term = 1.0
    // The Taylor series: x^n / n!, alternating between cos and sin, with the signs going + + - -.
    for n in 0..<32 {
      let sign: Double = (n / 2) % 2 == 0 ? 1 : -1
      if n % 2 == 0 { cos += sign * term } else { sin += sign * term }
      term = term * x / Double(n + 1)
    }
    return (sin, cos)
  }

  static func log2(_ value: Double) -> Double {
    guard value > 0 else { return -.infinity }
    // value = significand × 2^exponent with the significand in [1, 2), both exact.
    let significand = value.significand
    let t = (significand - 1) / (significand + 1)
    let t2 = t * t
    var power = t
    var sum = 0.0
    // ln(significand) = 2 atanh(t) = 2 (t + t³/3 + t⁵/5 + ...), with t under 1/3.
    for k in 0..<30 {
      sum += power / Double(2 * k + 1)
      power *= t2
    }
    return Double(value.exponent) + 2 * sum / 0.693_147_180_559_945_3
  }
}
