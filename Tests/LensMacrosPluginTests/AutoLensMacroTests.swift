import LensMacrosPlugin
import MacroTesting
import XCTest

final class AutoLensMacroTests: BaseTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [AutoLensMacro.self]
    ) {
      super.invokeTest()
    }
  }
  
  func testGenerateExt() {
    assertMacro {
      """
      @AutoLens
      struct Person {
        public let name: String?
        let uuids: [UUID]
        let id: Int
      }
      """
    } expansion: {
      #"""
      struct Person {
        public let name: String?
        let uuids: [UUID]
        let id: Int

        public static subscript <T>(lens path: KeyPath<Person, T>) -> Lens<Person, T> {
          let anyLens = AllLenses.lensesDictionary[ObjectIdentifier(path)]
          return anyLens as! Lens<Person, T>
        }

        private init(
            name: String?,
            uuids: [UUID],
            id: Int
        ) {
            self.name = name
            self.uuids = uuids
            self.id = id
        }

        enum AllLenses {
          public static let name = Lens<Person, String?>(
          get: { whole in
            whole.name
          },
          set: { whole, target in
            Person(
            name: target,
            uuids: whole.uuids,
            id: whole.id
            )
          }
          )

          fileprivate static var lensesDictionary: [AnyHashable: Any] {
            [
                ObjectIdentifier(\Person.name): AllLenses.name
            ]
          }
        }
      }
      """#
    }
  }
}
