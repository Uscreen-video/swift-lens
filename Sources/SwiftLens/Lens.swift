import Foundation

/// A ``Lens`` (or Functional Reference) is an optic that can focus into a structure for
/// getting, setting or modifying the focus (target).
///
///
/// A ``Lens`` can be seen as a pair of functions:
/// - `get: (S) -> T` meaning we can focus into an `S` and extract an `T`
/// - `set: (S) -> (T) -> S` meaning we can focus into an `S` and set a value `T` for a target `T` and obtain a modified source `S`
///
/// Generic Lens parameters:
/// - `S` the source of a ``Lens``;
/// - `T` the modified focus of a ``Lens``;
public struct Lens<S, T> {
  private let getFunc: (S) -> T
  private let setFunc: (S, T) -> S
  
  public init(
    get: @escaping (S) -> T,
    set: @escaping (S, T) -> S
  ) {
    self.getFunc = get
    self.setFunc = set
  }
  
  public static func * <A>(_ lhs: Lens<S, T>, _ rhs: Lens<S, A>) -> Lens<S, (T, A)> {
    lhs.concat(rhs)
  }
  
  public static func + <A>(_ lhs: Lens<S, T>, _ rhs: Lens<T, A>) -> Lens<S, A> {
    lhs.compose(rhs)
  }
  
  public func get(_ s: S) -> T {
    getFunc(s)
  }
  
  public func set(_ s: S, _ t: T) -> S {
    setFunc(s, t)
  }
  
  public func compose<A>(_ other: Lens<T, A>) -> Lens<S, A> {
    Lens<S, A>(
      get: { whole in
        other.get(self.get(whole))
      },
      set: { (whole: S, target: A) in
        set(whole, other.set(self.get(whole), target))
      }
    )
  }
  
  public func concat<A>(_ other: Lens<S, A>) -> Lens<S, (T, A)> {
    Lens<S, (T, A)>(
      get: { whole in
        (self.get(whole), other.get(whole))
      },
      set: { whole, pair in
        other.set(self.set(whole, pair.0), pair.1)
      }
    )
  }
  
  public func modify(_ s: S, _ f: @escaping (T) -> T) -> S {
    set(s, f(get(s)))
  }
  
  public func lift(_ f: @escaping (T) -> T) -> (S) -> S {
    { s in self.modify(s, f) }
  }
}
