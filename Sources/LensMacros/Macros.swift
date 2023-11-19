import Foundation

@attached(member, names: named(AllLenses), named(allLenses), named(init))
public macro AutoLens() =
  #externalMacro(
    module: "LensMacrosPlugin", type: "AutoLensMacro"
  )
